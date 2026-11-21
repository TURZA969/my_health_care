import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  bool isLoading = true;
  List<Map<String, dynamic>> promotions = [];
  List<Map<String, dynamic>> vouchers = [];
  Set<String> claimingIds = {}; // voucher ids currently being claimed (loading state)
  Set<String> claimingPromoIds = {}; // promotion ids currently being claimed (loading state)

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final results = await Future.wait([
        _fetchPromotions(),
        _fetchVouchers(),
      ]);
      setState(() {
        promotions = results[0];
        vouchers = results[1];
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ডেটা লোড করতে সমস্যা হয়েছে: $e')),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPromotions() async {
    final snap = await FirebaseFirestore.instance
        .collection('promotions')
        .where('isActive', isEqualTo: true)
        .get();

    final now = DateTime.now();
    final list = snap.docs.where((doc) {
      final data = doc.data();
      final endDate = (data['endDate'] as Timestamp?)?.toDate();
      final startDate = (data['startDate'] as Timestamp?)?.toDate();
      if (endDate != null && endDate.isBefore(now)) return false;
      if (startDate != null && startDate.isAfter(now)) return false;
      return true;
    }).map((doc) => {...doc.data(), 'id': doc.id}).toList();

    list.sort((a, b) =>
        ((a['priority'] ?? 999) as num).compareTo((b['priority'] ?? 999) as num));
    return list;
  }

  Future<List<Map<String, dynamic>>> _fetchVouchers() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '0';

    // userId == "0"  -> public, everyone sees it
    // userId == uid  -> only that user sees it
    // userId == null -> hidden (never fetched, since Firestore whereIn skips nulls)
    final snap = await FirebaseFirestore.instance
        .collection('vouchers')
        .where('userId', whereIn: ['0', uid])
        .where('isActive', isEqualTo: true)
        .get();

    final now = DateTime.now();
    final list = snap.docs.where((doc) {
      final data = doc.data();
      final endDate = (data['endDate'] as Timestamp?)?.toDate();
      final startDate = (data['startDate'] as Timestamp?)?.toDate();
      if (endDate != null && endDate.isBefore(now)) return false;
      if (startDate != null && startDate.isAfter(now)) return false;
      return true;
    }).map((doc) => {...doc.data(), 'id': doc.id}).toList();

    return list;
  }

  Future<void> _claimVoucher(Map<String, dynamic> voucher) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final voucherId = voucher['id'] as String;
    setState(() => claimingIds.add(voucherId));

    final voucherRef =
        FirebaseFirestore.instance.collection('vouchers').doc(voucherId);
    final claimRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('claimedVouchers')
        .doc(voucherId);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final voucherSnap = await transaction.get(voucherRef);
        final claimSnap = await transaction.get(claimRef);

        if (!voucherSnap.exists) {
          throw 'ভাউচারটি আর নেই';
        }
        final data = voucherSnap.data()!;

        if (data['isActive'] != true) {
          throw 'এই ভাউচারটি বর্তমানে সক্রিয় নয়';
        }

        final endDate = (data['endDate'] as Timestamp?)?.toDate();
        if (endDate != null && endDate.isBefore(DateTime.now())) {
          throw 'এই ভাউচারের মেয়াদ শেষ হয়ে গেছে';
        }

        final usageLimit = data['usageLimit'];
        final usedCount = (data['usedCount'] ?? 0) as int;
        if (usageLimit != null && usedCount >= (usageLimit as int)) {
          throw 'এই ভাউচারের ব্যবহারসীমা শেষ হয়ে গেছে';
        }

        // perUserLimit == null -> unlimited uses per user (as requested)
        final perUserLimit = data['perUserLimit'];
        if (perUserLimit != null) {
          final timesClaimed = claimSnap.exists
              ? (claimSnap.data()?['timesClaimed'] ?? 0) as int
              : 0;
          if (timesClaimed >= (perUserLimit as int)) {
            throw 'আপনি এই ভাউচারের ব্যবহারসীমা পার করে ফেলেছেন';
          }
        }

        transaction.update(voucherRef, {'usedCount': FieldValue.increment(1)});

        transaction.set(
          claimRef,
          {
            'code': data['code'],
            'voucherId': voucherId,
            'timesClaimed': FieldValue.increment(1),
            'lastClaimedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });

      if (mounted) {
        _showClaimedDialog(voucher['code']);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => claimingIds.remove(voucherId));
    }
  }

  // Same claim logic as _claimVoucher, but reads from the `promotions`
  // collection and writes into the SAME users/{uid}/claimedVouchers
  // collection as regular vouchers, so both live in one place.
  Future<void> _claimPromotion(Map<String, dynamic> promo) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final promoId = promo['id'] as String;
    setState(() => claimingPromoIds.add(promoId));

    final promoRef =
        FirebaseFirestore.instance.collection('promotions').doc(promoId);
    final claimRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('claimedVouchers')
        .doc(promoId);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final promoSnap = await transaction.get(promoRef);
        final claimSnap = await transaction.get(claimRef);

        if (!promoSnap.exists) {
          throw 'অফারটি আর নেই';
        }
        final data = promoSnap.data()!;

        if (data['isActive'] != true) {
          throw 'এই অফারটি বর্তমানে সক্রিয় নয়';
        }

        final endDate = (data['endDate'] as Timestamp?)?.toDate();
        if (endDate != null && endDate.isBefore(DateTime.now())) {
          throw 'এই অফারের মেয়াদ শেষ হয়ে গেছে';
        }

        final usageLimit = data['usageLimit'];
        final usedCount = (data['usedCount'] ?? 0) as int;
        if (usageLimit != null && usedCount >= (usageLimit as int)) {
          throw 'এই অফারের ব্যবহারসীমা শেষ হয়ে গেছে';
        }

        // perUserLimit == null -> unlimited uses per user
        final perUserLimit = data['perUserLimit'];
        if (perUserLimit != null) {
          final timesClaimed = claimSnap.exists
              ? (claimSnap.data()?['timesClaimed'] ?? 0) as int
              : 0;
          if (timesClaimed >= (perUserLimit as int)) {
            throw 'আপনি এই অফারের ব্যবহারসীমা পার করে ফেলেছেন';
          }
        }

        transaction.update(promoRef, {'usedCount': FieldValue.increment(1)});

        transaction.set(
          claimRef,
          {
            'code': data['promoCode'],
            'voucherId': promoId,
            'timesClaimed': FieldValue.increment(1),
            'lastClaimedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });

      if (mounted) {
        _showClaimedDialog(promo['promoCode']);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => claimingPromoIds.remove(promoId));
    }
  }

  void _showClaimedDialog(String? code) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Color(0xFF00B894)),
            SizedBox(width: 10),
            Text('Claimed!'),
          ],
        ),
        content: Text(
          'কোডটি সংরক্ষণ করা হয়েছে। বুকিং/চেকআউটের সময় এই কোডটি ব্যবহার করুন:\n\n${code ?? ''}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ঠিক আছে'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0077B6),
        foregroundColor: Colors.white,
        title: const Text('Explore Offers'),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0077B6)))
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (promotions.isNotEmpty) ...[
                    const Text('Special Promotions',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A2E))),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 150,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: promotions.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, i) =>
                            _promotionCard(promotions[i]),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  const Text('Available Vouchers',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 10),
                  if (vouchers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: Text('এই মুহূর্তে কোনো ভাউচার নেই',
                            style: TextStyle(color: Colors.grey.shade600)),
                      ),
                    )
                  else
                    ...vouchers.map((v) => _voucherCard(v)),
                ],
              ),
            ),
    );
  }

  Widget _promotionCard(Map<String, dynamic> promo) {
    final promoId = promo['id'] as String;
    final hasCode = (promo['promoCode'] ?? '').toString().isNotEmpty;
    final isClaiming = claimingPromoIds.contains(promoId);

    return Container(
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF023E8A), Color(0xFF0096C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(promo['title'] ?? '',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Expanded(
            child: Text(promo['subtitle'] ?? '',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12),
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
          ),
          if (hasCode)
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text('Code: ${promo['promoCode']}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  height: 26,
                  child: ElevatedButton(
                    onPressed: isClaiming ? null : () => _claimPromotion(promo),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF023E8A),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: isClaiming
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFF023E8A)))
                        : const Text('Use',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _voucherCard(Map<String, dynamic> voucher) {
    final voucherId = voucher['id'] as String;
    final isClaiming = claimingIds.contains(voucherId);
    final endDate = (voucher['endDate'] as Timestamp?)?.toDate();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(voucher['title'] ?? '',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text(voucher['subtitle'] ?? '',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(voucher['code'] ?? '',
                      style: const TextStyle(
                          color: Color(0xFF0077B6),
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ),
                if (endDate != null) ...[
                  const SizedBox(height: 6),
                  Text(
                      'মেয়াদ: ${endDate.day}/${endDate.month}/${endDate.year}',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: isClaiming ? null : () => _claimVoucher(voucher),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0077B6),
              foregroundColor: Colors.white,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: isClaiming
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Use'),
          ),
        ],
      ),
    );
  }
}