import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// =====================================================================
/// "Your Points" / Rewards screen.
///
/// HOW POINTS ARE CALCULATED (incremental, not recomputed from scratch):
///   1. Count how many documents this user currently has in
///      `appointments`, `lab_bookings`, and `medicine_orders` combined,
///      where the document's `status` is approved / completed /
///      delivered. (Soft-deleted items -- deletedByUser: true -- are
///      still counted, since the data still exists in the database.)
///   2. Compare that count against `users/{uid}.lastCountedHistoryTotal`
///      (how many eligible items were counted the last time points were
///      calculated). Only the *difference* (newly booked/approved items
///      since last time) earns new points:
///        newItems = currentEligibleCount - lastCountedHistoryTotal
///        pointsEarnedNow = newItems * Rewards.point_value
///   3. `users/{uid}.points` = existing stored points + pointsEarnedNow
///      `users/{uid}.lastCountedHistoryTotal` = currentEligibleCount
///
///   This way, redeeming (which zeroes out `points`) never gets
///   "undone" by a recalculation next time the screen opens -- points
///   only go up when a genuinely NEW eligible item appears. If nothing
///   new happened, points stay exactly as they were left (0 after a
///   redeem, unchanged otherwise).
///
/// REDEEM (instant -- no pending/approval step):
///   Tapping "Redeem Now" immediately:
///     - converts current points -> taka using
///       taka = points * (Rewards.taka / 100)
///     - sets `users/{uid}.points` to 0 right away
///     - adds that taka amount to `users/{uid}.pendingClaimTaka` (money
///       that has been redeemed but not yet claimed)
///     - logs a record in a `redemptions` collection (status:
///       'completed') purely for reference/history, not for approval
///
/// CLAIM:
///   Once redeemed, a "Balance" card shows the pending (unclaimed) taka
///   amount with a "Claim" button. Tapping it:
///     - adds `pendingClaimTaka` into the permanent `users/{uid}.balance`
///       field (accumulated total the user has ever claimed)
///     - resets `users/{uid}.pendingClaimTaka` back to 0
///   Because `pendingClaimTaka` is zeroed out right after claiming, the
///   same redeemed amount can never be claimed a second time. A brand
///   new pending amount only appears after the next redeem.
/// =====================================================================
class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  static const Color kPrimary = Color(0xFF0077B6);
  static const Color kSecondary = Color(0xFF00B4D8);

  bool isLoading = true;
  String? errorMessage;

  int appointmentCount = 0;
  int labTestCount = 0;
  int medicineOrderCount = 0;
  int totalEligibleCount = 0;

  num pointValue = 0;
  double takaPercent = 0;

  num points = 0;
  int newItemsSinceLastCount = 0;

  num pendingClaimTaka = 0;
  num claimedBalance = 0;

  double get availableTaka => points * (takaPercent / 100);

  bool isRedeeming = false;
  bool isClaiming = false;

  @override
  void initState() {
    super.initState();
    _loadEverything();
  }

  Future<int> _countEligible(String collection, String uid) async {
    const eligibleStatuses = {'approved', 'completed', 'delivered'};
    final snap = await FirebaseFirestore.instance
        .collection(collection)
        .where('userId', isEqualTo: uid)
        .get();
    return snap.docs.where((d) {
      final data = d.data();
      final status = (data['status'] ?? '').toString().toLowerCase();
      return eligibleStatuses.contains(status);
    }).length;
  }

  Future<void> _loadEverything() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          errorMessage = 'Please log in to see your points.';
          isLoading = false;
        });
        return;
      }
      final uid = user.uid;

      // 1) Eligible history counts right now (run in parallel).
      final results = await Future.wait([
        _countEligible('appointments', uid),
        _countEligible('lab_bookings', uid),
        _countEligible('medicine_orders', uid),
      ]);
      final currentEligibleCount = results[0] + results[1] + results[2];

      // 2) Rewards config (single document inside `Rewards` collection).
      final rewardsSnap =
          await FirebaseFirestore.instance.collection('Rewards').limit(1).get();

      num fetchedPointValue = 0;
      double fetchedTakaPercent = 0;
      if (rewardsSnap.docs.isNotEmpty) {
        final cfg = rewardsSnap.docs.first.data();
        fetchedPointValue = (cfg['point_value'] ?? 0) as num;
        fetchedTakaPercent = double.tryParse(cfg['taka']?.toString() ?? '0') ?? 0;
      }

      // 3) What we already knew about this user (existing point balance +
      //    how many eligible items were counted last time).
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final userDoc = await userRef.get();
      final userData = userDoc.data() ?? {};
      final storedPoints = (userData['points'] ?? 0) as num;
      final lastCountedTotal = (userData['lastCountedHistoryTotal'] ?? 0) as num;
      final storedPendingClaimTaka = (userData['pendingClaimTaka'] ?? 0) as num;
      final storedBalance = (userData['balance'] ?? 0) as num;

      // 4) Only NEW items (since the last time we counted) earn new points.
      final newItems = (currentEligibleCount - lastCountedTotal) > 0
          ? (currentEligibleCount - lastCountedTotal).toInt()
          : 0;
      final pointsEarnedNow = newItems * fetchedPointValue;
      final updatedPoints = storedPoints + pointsEarnedNow;

      // 5) Persist the updated balance + the new "last counted" marker.
      await userRef.set({
        'points': updatedPoints,
        'lastCountedHistoryTotal': currentEligibleCount,
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        appointmentCount = results[0];
        labTestCount = results[1];
        medicineOrderCount = results[2];
        totalEligibleCount = currentEligibleCount;
        pointValue = fetchedPointValue;
        takaPercent = fetchedTakaPercent;
        points = updatedPoints;
        newItemsSinceLastCount = newItems;
        pendingClaimTaka = storedPendingClaimTaka;
        claimedBalance = storedBalance;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'Something went wrong: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _handleRedeem() async {
    if (points <= 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.redeem, color: kPrimary),
            SizedBox(width: 10),
            Text('Redeem Points'),
          ],
        ),
        content: Text(
          'You are redeeming ${points.toStringAsFixed(0)} points '
          'for ৳${availableTaka.toStringAsFixed(2)}.\n\n'
          'Your points will be reset to 0 right away. Continue?',
          style: TextStyle(fontSize: 13.5, color: Colors.grey.shade700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => isRedeeming = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');
      final uid = user.uid;

      final pointsRedeemed = points;
      final takaCredited = availableTaka;

      final batch = FirebaseFirestore.instance.batch();
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final redemptionRef = FirebaseFirestore.instance.collection('redemptions').doc();

      // Instant redeem: points go to 0 right away, no pending/approval step.
      // The redeemed taka is added to a claimable pending balance.
      batch.update(userRef, {
        'points': 0,
        'pendingClaimTaka': FieldValue.increment(takaCredited),
      });

      // Kept purely as a reference log, already marked 'completed'.
      batch.set(redemptionRef, {
        'userId': uid,
        'pointsRedeemed': pointsRedeemed,
        'takaAmount': takaCredited,
        'status': 'completed',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      if (!mounted) return;
      setState(() {
        points = 0;
        pendingClaimTaka += takaCredited;
        isRedeeming = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Redeemed! ৳${takaCredited.toStringAsFixed(2)} added to your Balance -- claim it below.'),
          backgroundColor: const Color(0xFF1B9C63),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => isRedeeming = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Redeem failed: $e'),
          backgroundColor: const Color(0xFFE0413F),
        ),
      );
    }
  }

  Future<void> _handleClaim() async {
    if (pendingClaimTaka <= 0) return;

    setState(() => isClaiming = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');
      final uid = user.uid;
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

      final amountToClaim = pendingClaimTaka;

      // Move pendingClaimTaka into the permanent `balance` field, then
      // zero pendingClaimTaka out so it can never be claimed again.
      await userRef.update({
        'balance': FieldValue.increment(amountToClaim),
        'pendingClaimTaka': 0,
      });

      if (!mounted) return;
      setState(() {
        claimedBalance += amountToClaim;
        pendingClaimTaka = 0;
        isClaiming = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('৳${amountToClaim.toStringAsFixed(2)} claimed to your balance.'),
          backgroundColor: const Color(0xFF1B9C63),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => isClaiming = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Claim failed: $e'),
          backgroundColor: const Color(0xFFE0413F),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: kPrimary,
        elevation: 0,
        title: const Text('Your Points',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: isLoading ? null : _loadEverything,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                )
              : RefreshIndicator(
                  color: kPrimary,
                  onRefresh: _loadEverything,
                  child: ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      // ===== Points balance card =====
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [kPrimary, kSecondary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: kPrimary.withValues(alpha: 0.30),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.20),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.stars_rounded,
                                      color: Colors.white, size: 24),
                                ),
                                const SizedBox(width: 12),
                                const Text('Available Points',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 13.5)),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              points.toStringAsFixed(0),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 40,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '≈ ৳${availableTaka.toStringAsFixed(2)} if redeemed now',
                              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                            ),
                            if (newItemsSinceLastCount > 0) ...[
                              const SizedBox(height: 6),
                              Text(
                                '+ $newItemsSinceLastCount new item(s) added just now',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: (points <= 0 || isRedeeming)
                                    ? null
                                    : _handleRedeem,
                                icon: isRedeeming
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: kPrimary),
                                      )
                                    : const Icon(Icons.redeem, size: 18),
                                label: Text(isRedeeming
                                    ? 'Processing...'
                                    : 'Redeem Now'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: kPrimary,
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ===== Balance card (shows after a redeem, until claimed) =====
                      if (pendingClaimTaka > 0 || claimedBalance > 0) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(9),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1B9C63).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.account_balance_wallet_outlined,
                                        color: Color(0xFF1B9C63), size: 20),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text('Balance',
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF1A1A2E))),
                                ],
                              ),
                              const SizedBox(height: 16),
                              if (pendingClaimTaka > 0) ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Available to claim',
                                            style: TextStyle(
                                                fontSize: 12, color: Colors.grey.shade600)),
                                        const SizedBox(height: 3),
                                        Text(
                                          '৳${pendingClaimTaka.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF1B9C63)),
                                        ),
                                      ],
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: isClaiming ? null : _handleClaim,
                                      icon: isClaiming
                                          ? const SizedBox(
                                              width: 15,
                                              height: 15,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2, color: Colors.white),
                                            )
                                          : const Icon(Icons.check_circle_outline, size: 17),
                                      label: Text(isClaiming ? 'Claiming...' : 'Claim'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF1B9C63),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 18, vertical: 12),
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12)),
                                        elevation: 0,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (pendingClaimTaka > 0 && claimedBalance > 0)
                                const Divider(height: 26),
                              if (claimedBalance > 0)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Total claimed so far',
                                        style: TextStyle(
                                            fontSize: 12.5, color: Colors.grey.shade600)),
                                    Text('৳${claimedBalance.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1A1A2E))),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}