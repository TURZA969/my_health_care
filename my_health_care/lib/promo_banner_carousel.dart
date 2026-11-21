import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PromoBannerCarousel extends StatefulWidget {
  const PromoBannerCarousel({super.key});

  @override
  State<PromoBannerCarousel> createState() => _PromoBannerCarouselState();
}

class _PromoBannerCarouselState extends State<PromoBannerCarousel> {
  List<Map<String, dynamic>> promos = [];
  bool isLoading = true;
  int currentIndex = 0;
  bool visible = true;
  bool pausedByUser = false; // যতক্ষণ আঙুল চেপে ধরে রাখবে ততক্ষণ true, ছাড়লেই false
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadPromotions();
  }

  Future<void> _loadPromotions() async {
    try {
      final now = Timestamp.now();
      final snapshot = await FirebaseFirestore.instance
          .collection('promotions')
          .where('isActive', isEqualTo: true)
          .get();

      final list = snapshot.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }).where((p) {
        final start = p['startDate'] as Timestamp?;
        final end = p['endDate'] as Timestamp?;
        if (start != null && start.compareTo(now) > 0) return false;
        if (end != null && end.compareTo(now) < 0) return false;
        return true;
      }).toList();

      list.sort((a, b) => ((a['priority'] ?? 999) as num)
          .compareTo((b['priority'] ?? 999) as num));

      if (!mounted) return;
      setState(() {
        promos = list;
        isLoading = false;
      });

      if (promos.length > 1) _startCycle();
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ===== TIMING (আরো ধীরে চলবে) =====
  static const Duration _visibleDuration = Duration(seconds: 7); // কত সেকেন্ড দেখাবে
  static const Duration _fadeDuration = Duration(milliseconds: 600); // fade in/out speed
  static const Duration _gapDuration = Duration(milliseconds: 700); // মাঝে গায়েব থাকার সময়

  void _startCycle() {
    _timer?.cancel();
    _timer = Timer.periodic(_visibleDuration, (timer) async {
      if (!mounted || pausedByUser) return; // touch করা হলে skip করবে
      setState(() => visible = false); // fade out শুরু
      await Future.delayed(_fadeDuration);
      if (!mounted || pausedByUser) return;
      await Future.delayed(_gapDuration); // এই সময় সম্পূর্ণ গায়েব থাকবে
      if (!mounted || pausedByUser) return;
      setState(() {
        currentIndex = (currentIndex + 1) % promos.length;
        visible = true; // fade in
      });
    });
  }

  // আঙুল চেপে ধরার সাথে সাথে freeze হয়ে যাবে
  void _onPressStart() {
    setState(() {
      pausedByUser = true;
      visible = true; // চেপে ধরার মুহূর্তে যা দেখাচ্ছিল সেটাই স্থির থাকবে
    });
  }

  // আঙুল ছেড়ে দিলে normal cycle আবার চালু হয়ে যাবে
  void _onPressEnd() {
    setState(() => pausedByUser = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ফিক্সড height — carousel এর ভেতরের content পরিবর্তন হলেও
  // বাইরের space সবসময় একই থাকবে, তাই নিচের Overview/Services কখনো নড়বে না।
  static const double _bannerHeight = 140;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        height: _bannerHeight,
        child: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF0077B6),
            strokeWidth: 2.5,
          ),
        ),
      );
    }
    if (promos.isEmpty) return const SizedBox.shrink();

    final promo = promos[currentIndex];

    // AnimatedOpacity ব্যবহার করা হচ্ছে (SizeTransition নয়), কারণ
    // opacity বদলালে widget-এর height/space একদম অপরিবর্তিত থাকে —
    // ফলে scroll view-তে কোনো reflow/jump হয় না।
    return GestureDetector(
      onTapDown: (_) => _onPressStart(),
      onTapUp: (_) => _onPressEnd(),
      onTapCancel: _onPressEnd,
      onLongPressStart: (_) => _onPressStart(),
      onLongPressEnd: (_) => _onPressEnd(),
      child: SizedBox(
        height: _bannerHeight,
        width: double.infinity,
        child: AnimatedOpacity(
          duration: _fadeDuration,
          opacity: visible ? 1.0 : 0.0,
          curve: Curves.easeInOut,
          child: _buildBannerCard(promo, key: ValueKey(currentIndex)),
        ),
      ),
    );
  }

  Widget _buildBannerCard(Map<String, dynamic> promo, {required Key key}) {
    return Container(
      key: key,
      width: double.infinity,
      height: double.infinity,
      // বাড়তি প্যাডিং — লেখা যেন borderCurve এর সাথে মিশে না যায়
      padding: const EdgeInsets.fromLTRB(20, 18, 18, 16),
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B6B), Color(0xFFFFA36B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF6B6B).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // decorative circle সরিয়ে একদম কোণায় (top-right) রাখা হয়েছে,
            // যাতে টাইটেল টেক্সটের সাথে ওভারল্যাপ না করে
            Positioned(
              right: -34,
              top: -44,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
            ),
            Padding(
              // Stack-এর ভেতরের content-কে আরেকটু ভেতরে ঠেলে দেওয়া হলো
              // যাতে border/curve-এর কাছ ঘেঁষে টেক্সট শুরু না হয়
              padding: const EdgeInsets.only(top: 2, left: 1),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              promo['title'] ?? '',
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                height: 1.15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              promo['subtitle'] ?? '',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.9),
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 10),
                            if ((promo['promoCode'] ?? '').toString().isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Code: ${promo['promoCode']}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.local_offer_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ],
                  ),
                  if (promos.length > 1) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: List.generate(promos.length, (i) {
                        return Container(
                          margin: const EdgeInsets.only(right: 5),
                          width: i == currentIndex ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(
                                alpha: i == currentIndex ? 0.9 : 0.4),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}