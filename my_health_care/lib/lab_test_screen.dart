import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'invoice_lab_test.dart'
    show BookingApprovalListener, showLabBookingConfirmationDialog, LabInvoiceService;

// ─────────────────────────────────────────────
// FIRESTORE COLLECTIONS GUIDE (create manually)
// ─────────────────────────────────────────────
// 1. hospitals/
//      name: "Dhaka Medical Center"
//      location: "Dhaka"
//      type: "Government" | "Private"
//      availableTests: ["Blood Test (CBC)", "ECG", ...]
//
// 2. lab_tests_catalog/
//      name: "Blood Test (CBC)"
//      icon: "🩸"
//      description: "Complete Blood Count"
//      fee: 500
//      color: 0xFF00B894
//      homeEligible: true
//      isAvailable: true
//      kitRequired: false
//      kitName: ""
//      kitCharge: 0
//
// 3. settings/app_settings  (single doc)
//      bkashNumber: "01XXXXXXXXX"
//      nagadNumber: "01XXXXXXXXX"
//      rocketNumber: "01XXXXXXXXX"
//      platformCharge: 50
//      homeServiceCharge: 150
//      helplineNumber: "01XXXXXXXXX"
//
// 4. vouchers/  (auto-id) — same promo-code system as AppointmentScreen
//      code: "VIP100"
//      isActive: true
//      applicableTo: "all" | "lab_test" | "appointment"
//      discountType: "flat" | "percent"
//      discountValue: 100
//      maxDiscountAmount: 200
//      minAmount: 0
//      startDate / endDate: Timestamp (optional)
//      usageLimit: 0 (0 = unlimited)
//      usedCount: 0
//      perUserLimit: 1
//
//    users/{uid}/claimedVouchers/{voucherId}
//      voucherId, code, timesClaimed, lastClaimedAt
//
// 5. lab_bookings/  (auto-id)
//      userId, tests: [{testName, testFee, kitRequired, kitCharge, kitName}],
//      hospitalId, hospitalName, location, date,
//      homeCollection, homeServiceCharge, kitCharge,
//      fee (tests+kit+home, before platform charge), platformCharge,
//      promoCode, voucherId, discountAmount, balanceUsed,
//      amountPaid, dueAmount, totalFee,
//      paymentType ('Online' | 'Cash' | 'Balance'),
//      senderNumber, transactionId,
//      status, createdAt, receiptNumber
//
// NOTE: status field values:
//   "pending"  → admin এখনো approve করেননি
//   "approved" → admin approve করেছেন, invoice download করা যাবে
//   "rejected" → admin reject করেছেন
// ─────────────────────────────────────────────

class LabTestScreen extends StatefulWidget {
  const LabTestScreen({super.key});

  @override
  State<LabTestScreen> createState() => _LabTestScreenState();
}

class _LabTestScreenState extends State<LabTestScreen> {
  // ── state ──
  String? selectedLocation;
  String selectedType = 'Government';
  String? selectedHospitalId;
  String? selectedHospitalName;

  // Multi-select: list of selected test data maps
  List<Map<String, dynamic>> selectedTests = [];

  DateTime? selectedDate;
  bool homeCollection = false;

  bool isLoadingHospitals = false;
  bool isLoadingTests = false;
  bool isLoadingConfig = false;
  bool isDetectingLocation = false; // GPS icon tap থেকে location detect হওয়ার সময় true

  List<String> locations = [];
  List<Map<String, dynamic>> hospitals = [];
  List<Map<String, dynamic>> labTests = [];
  Map<String, dynamic> paymentConfig = {};

  // ── Promo code & wallet balance state (same system as AppointmentScreen) ──
  final TextEditingController promoCodeController = TextEditingController();
  Map<String, dynamic>? appliedVoucher; // raw voucher doc data
  String? appliedVoucherId;
  String? promoError;
  bool isCheckingPromo = false;

  bool useBalance = false;
  int userBalance = 0;

  // ── colors ──
  static const primary = Color(0xFF00897B);
  static const primaryDark = Color(0xFF00695C);
  static const accent = Color(0xFF26C6DA);
  static const bg = Color(0xFFF0F6F5);
  static const kGreen = Color(0xFF2E7D32);
  static const kGreenLight = Color(0xFFE8F5E9);
  static const kRed = Color(0xFFC62828);
  static const kRedLight = Color(0xFFFFEBEE);
  static const kBorder = Color(0xFFE5E7EB);
  static const kText = Color(0xFF1A1A2E);
  static const kSubtext = Color(0xFF6B7280);
  static const kAmber = Color(0xFFF59E0B);

  // ── GPS sub-area name (lowercase) -> hospitals collection-এর
  // 'location' field-এর সাথে exact match হওয়া নাম। AppointmentScreen-এর
  // সাথে হুবহু same map, যাতে দুই screen-এ GPS detect একই hospital
  // location-এ resolve হয়। প্রয়োজনমতো এখানে আরও area/alias যোগ করে নিন। ──
  static const Map<String, String> _areaAliasMap = {
    'rupnagar': 'Mirpur',
    'kazipara': 'Mirpur',
    'shah ali': 'Mirpur',
    'pallabi': 'Mirpur',
    'mirpur': 'Mirpur',
    'kafrul': 'Mirpur',
    'darus salam': 'Mirpur',
    'chawkbazar': 'Old Dhaka',
    'lalbagh': 'Old Dhaka',
    'nawabganj': 'Old Dhaka',
    'kotwali': 'Old Dhaka',
    'sutrapur': 'Old Dhaka',
    'bangshal': 'Old Dhaka',
    'gandaria': 'Old Dhaka',
    'wari': 'Old Dhaka',
    'kamrangirchar': 'Old Dhaka',
    'dhanmondi': 'Dhanmondi',
    'mohammadpur': 'Mohammadpur',
    'shyamoli': 'Mohammadpur',
    'adabor': 'Mohammadpur',
    'uttara': 'Uttara',
    'gulshan': 'Gulshan',
    'banani': 'Gulshan',
    'baridhara': 'Gulshan',
    'badda': 'Badda',
    'rampura': 'Rampura',
    'khilgaon': 'Khilgaon',
    'motijheel': 'Motijheel',
    'paltan': 'Motijheel',
    'tejgaon': 'Tejgaon',
    'farmgate': 'Tejgaon',
    'mohakhali': 'Tejgaon',
    'jatrabari': 'Jatrabari',
    'shyampur': 'Jatrabari',
    'demra': 'Demra',
    'khilkhet': 'Khilkhet',
    'cantonment': 'Cantonment',
    'hazaribagh': 'Hazaribagh',
  };

  @override
  void initState() {
    super.initState();
    _loadUserLocation();
    _loadLocations();
    _loadPaymentConfig();
    _loadUserBalance();
  }

  // ════════════════════════════════
  // DATA LOADERS
  // ════════════════════════════════

  Future<void> _loadUserLocation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (doc.exists) {
      final address = doc.data()?['address'] ?? '';
      final parts = address.split(',');
      setState(() =>
          selectedLocation = parts.isNotEmpty ? parts[0].trim() : null);
    }
  }

  // ── Tap করলে GPS দিয়ে current location detect করে LOCATION dropdown-এ
  // select করে দেয়। Scroll করে manual select করার সুবিধা আগের মতোই থাকে —
  // এটা শুধু dropdown-এর value পরিবর্তন করে, dropdown নিজে অপরিবর্তিত।
  // AppointmentScreen.detectCurrentLocation()-এর সাথে হুবহু same logic। ──
  Future<void> detectCurrentLocation() async {
    if (!mounted) return;
    setState(() => isDetectingLocation = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationSnack('Please turn on location services');
        setState(() => isDetectingLocation = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showLocationSnack('Location permission denied');
        setState(() => isDetectingLocation = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final placemarks = await placemarkFromCoordinates(
          position.latitude, position.longitude);

      if (placemarks.isEmpty) {
        _showLocationSnack('Could not detect your area');
        setState(() => isDetectingLocation = false);
        return;
      }

      final place = placemarks.first;
      final candidates = <String>[
        place.subLocality ?? '',
        place.locality ?? '',
        place.subAdministrativeArea ?? '',
        place.thoroughfare ?? '',
        place.name ?? '',
      ].where((s) => s.trim().isNotEmpty).toList();

      String? matchedArea;
      outer:
      for (final c in candidates) {
        final key = c.trim().toLowerCase();
        if (_areaAliasMap.containsKey(key)) {
          matchedArea = _areaAliasMap[key];
          break;
        }
        for (final entry in _areaAliasMap.entries) {
          if (key.contains(entry.key)) {
            matchedArea = entry.value;
            break outer;
          }
        }
      }

      if (matchedArea == null || !locations.contains(matchedArea)) {
        _showLocationSnack(matchedArea == null
            ? 'Could not match your area to a known location'
            : 'No hospitals listed for "$matchedArea" yet');
        setState(() => isDetectingLocation = false);
        return;
      }

      if (!mounted) return;
      setState(() {
        selectedLocation = matchedArea;
        selectedHospitalId = null;
        selectedHospitalName = null;
        selectedTests = [];
        labTests = [];
        isDetectingLocation = false;
      });
      _loadHospitals();
    } catch (e) {
      if (!mounted) return;
      setState(() => isDetectingLocation = false);
      _showLocationSnack('Could not get your location');
    }
  }

  void _showLocationSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: kAmber),
    );
  }

  // ── Load current wallet balance for the logged-in user ──
  Future<void> _loadUserBalance() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (doc.exists && mounted) {
      setState(() {
        userBalance = ((doc.data()?['balance'] ?? 0) as num).toInt();
      });
    }
  }

  // ── BLOCK CHECK ───────────────────────────────────────
  // Returns true if the currently logged-in user has been blocked by
  // ADMIN for `selectedHospitalId` specifically (see
  // hospitals/{hospitalId}/blockedUsers/{uid} written from the admin
  // "Manage Users" page). Being blocked at one hospital never affects
  // booking at any other hospital.
  Future<bool> _isUserBlockedForSelectedHospital() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || selectedHospitalId == null) return false;
    final doc = await FirebaseFirestore.instance
        .collection('hospitals')
        .doc(selectedHospitalId)
        .collection('blockedUsers')
        .doc(user.uid)
        .get();
    return doc.exists;
  }

  void _showBlockedDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.block_rounded, color: kRed),
            SizedBox(width: 8),
            Text('Booking Not Allowed'),
          ],
        ),
        content: Text(
          'You have been blocked from booking lab tests at ${selectedHospitalName ?? 'this hospital'}. '
          'You can still book at other hospitals. Please contact the hospital if you think this is a mistake.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
                backgroundColor: primary, foregroundColor: Colors.white),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadLocations() async {
    final snap =
        await FirebaseFirestore.instance.collection('hospitals').get();
    final locs = snap.docs
        .map((d) => d.data()['location']?.toString() ?? '')
        .where((l) => l.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    setState(() => locations = locs);
    if (selectedLocation == null || !locations.contains(selectedLocation)) {
      if (locations.isNotEmpty) {
        setState(() => selectedLocation = locations.first);
      }
    }
    _loadHospitals();
  }

  Future<void> _loadHospitals() async {
    if (selectedLocation == null) return;
    setState(() {
      isLoadingHospitals = true;
      hospitals = [];
      selectedHospitalId = null;
      selectedHospitalName = null;
      selectedTests = [];
      labTests = [];
    });
    final snap = await FirebaseFirestore.instance
        .collection('hospitals')
        .where('location', isEqualTo: selectedLocation)
        .where('type', isEqualTo: selectedType)
        .get();
    setState(() {
      hospitals = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      isLoadingHospitals = false;
    });
  }

  Future<void> _loadTestsForHospital(
      List<dynamic> availableTestNames) async {
    setState(() {
      isLoadingTests = true;
      labTests = [];
      selectedTests = [];
    });
    final snap = await FirebaseFirestore.instance
        .collection('lab_tests_catalog')
        .get();
    final all = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    final filtered =
        all.where((t) => availableTestNames.contains(t['name'])).toList();
    setState(() {
      labTests = filtered;
      isLoadingTests = false;
    });
  }

  Future<void> _loadPaymentConfig() async {
    setState(() => isLoadingConfig = true);
    final doc = await FirebaseFirestore.instance
        .collection('settings')
        .doc('app_settings')
        .get();
    setState(() {
      paymentConfig = doc.data() ?? {};
      isLoadingConfig = false;
    });
  }

  // ════════════════════════════════
  // HELPERS
  // ════════════════════════════════

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  /// ── MHC Receipt Number Generator ──
  /// Format: MHC-YYMMDD-XXXXX
  ///   YYMMDD → booking date (readable, sortable)
  ///   XXXXX  → millisecond-timestamp based + random padding, so two
  ///            bookings created in the same millisecond still get a
  ///            different number.
  String _generateReceiptNumber() {
    final now = DateTime.now();
    final datePart = DateFormat('yyMMdd').format(now);
    final msPart = (now.millisecondsSinceEpoch % 100000)
        .toString()
        .padLeft(5, '0');
    final randPart = Random().nextInt(90) + 10; // 2-digit random 10-99
    return 'MHC-$datePart-$msPart$randPart';
  }

  int get _homeServiceCharge =>
      homeCollection
          ? (paymentConfig['homeServiceCharge'] as num? ?? 0).toInt()
          : 0;

  int get _platformCharge =>
      (paymentConfig['platformCharge'] as num? ?? 0).toInt();

  int get _totalKitCharge {
    int total = 0;
    for (final t in selectedTests) {
      if (t['kitRequired'] == true) {
        total += (t['kitCharge'] as num? ?? 0).toInt();
      }
    }
    return total;
  }

  int get _totalTestFee {
    int total = 0;
    for (final t in selectedTests) {
      total += (t['fee'] as num? ?? 0).toInt();
    }
    return total;
  }

  // "fee" analogous to AppointmentScreen's doctor fee — everything except
  // the platform charge (which is handled separately, same as appointments).
  int get _feeBeforePlatformCharge =>
      _totalTestFee + _totalKitCharge + _homeServiceCharge;

  // Grand total: test fees + kit charges + home service + platform charge
  int get _totalFee => _feeBeforePlatformCharge + _platformCharge;

  bool _isTestSelected(Map<String, dynamic> test) =>
      selectedTests.any((t) => t['id'] == test['id']);

  void _toggleTest(Map<String, dynamic> test) {
    final isAvailable = test['isAvailable'] == true;
    if (!isAvailable) return;

    final homeEligible = test['homeEligible'] == true;
    if (homeCollection && !homeEligible) {
      _showHomeNotEligibleDialog(test['name'] ?? '');
      return;
    }

    setState(() {
      if (_isTestSelected(test)) {
        selectedTests.removeWhere((t) => t['id'] == test['id']);
      } else {
        selectedTests.add(test);
      }
    });
  }

  // ════════════════════════════════
  // VALIDATION HELPERS (same rules as AppointmentScreen)
  // ════════════════════════════════

  bool _isValidPhone(String phone) {
    // exactly 11 digits
    return RegExp(r'^\d{11}$').hasMatch(phone.trim());
  }

  bool _isValidTransactionId(String txn) {
    // exactly 10 chars, UPPERCASE letters + digits only
    return RegExp(r'^[A-Z0-9]{10}$').hasMatch(txn.trim());
  }

  // ── Promo code validation against `vouchers` collection ──
  // Checks: exists, isActive, applicableTo, start/end date window,
  // minAmount vs fee, global usageLimit vs usedCount, and the per-user
  // limit stored at users/{uid}/claimedVouchers/{voucherId}.timesClaimed.
  Future<void> _applyPromoCode({
    required String code,
    required int fee,
    required StateSetter setModalState,
  }) async {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty) {
      setModalState(() => promoError = 'Enter a promo code');
      return;
    }

    setModalState(() {
      isCheckingPromo = true;
      promoError = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setModalState(() {
          isCheckingPromo = false;
          promoError = 'Please login first';
        });
        return;
      }

      final query = await FirebaseFirestore.instance
          .collection('vouchers')
          .where('code', isEqualTo: trimmed)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        setModalState(() {
          isCheckingPromo = false;
          promoError = 'Invalid promo code';
          appliedVoucher = null;
          appliedVoucherId = null;
        });
        return;
      }

      final voucherDoc = query.docs.first;
      final voucher = voucherDoc.data();
      final voucherId = voucherDoc.id;

      if (voucher['isActive'] != true) {
        setModalState(() {
          isCheckingPromo = false;
          promoError = 'This code is no longer active';
        });
        return;
      }

      final applicableTo = (voucher['applicableTo'] ?? 'all').toString();
      if (applicableTo != 'all' && applicableTo != 'lab_test') {
        setModalState(() {
          isCheckingPromo = false;
          promoError = 'This code is not valid for lab tests';
        });
        return;
      }

      final now = DateTime.now();
      final startDate = (voucher['startDate'] as Timestamp?)?.toDate();
      final endDate = (voucher['endDate'] as Timestamp?)?.toDate();
      if (startDate != null && now.isBefore(startDate)) {
        setModalState(() {
          isCheckingPromo = false;
          promoError = 'This code is not active yet';
        });
        return;
      }
      if (endDate != null && now.isAfter(endDate)) {
        setModalState(() {
          isCheckingPromo = false;
          promoError = 'This code has expired';
        });
        return;
      }

      final minAmount = ((voucher['minAmount'] ?? 0) as num).toInt();
      if (fee < minAmount) {
        setModalState(() {
          isCheckingPromo = false;
          promoError = 'Minimum ৳$minAmount fee required for this code';
        });
        return;
      }

      final usageLimit = ((voucher['usageLimit'] ?? 0) as num).toInt();
      final usedCount = ((voucher['usedCount'] ?? 0) as num).toInt();
      if (usageLimit > 0 && usedCount >= usageLimit) {
        setModalState(() {
          isCheckingPromo = false;
          promoError = 'This code has reached its usage limit';
        });
        return;
      }

      final perUserLimit = ((voucher['perUserLimit'] ?? 1) as num).toInt();
      final claimedDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('claimedVouchers')
          .doc(voucherId)
          .get();
      final timesClaimed = claimedDoc.exists
          ? ((claimedDoc.data()?['timesClaimed'] ?? 0) as num).toInt()
          : 0;
      if (timesClaimed >= perUserLimit) {
        setModalState(() {
          isCheckingPromo = false;
          promoError =
              'You have already used this code the maximum number of times';
        });
        return;
      }

      setModalState(() {
        isCheckingPromo = false;
        appliedVoucher = voucher;
        appliedVoucherId = voucherId;
        promoError = null;
      });
    } catch (e) {
      setModalState(() {
        isCheckingPromo = false;
        promoError = 'Something went wrong, try again';
      });
    }
  }

  // Computes the taka discount for the currently applied voucher against
  // a given fee, honouring flat/percent type and the maxDiscountAmount cap.
  int _calculateDiscount(int fee) {
    if (appliedVoucher == null) return 0;
    final discountType =
        (appliedVoucher!['discountType'] ?? 'flat').toString();
    final discountValue =
        ((appliedVoucher!['discountValue'] ?? 0) as num).toInt();
    final maxDiscount =
        ((appliedVoucher!['maxDiscountAmount'] ?? discountValue) as num)
            .toInt();

    int discount;
    if (discountType == 'percent') {
      discount = ((fee * discountValue) / 100).round();
    } else {
      discount = discountValue;
    }
    if (discount > maxDiscount) discount = maxDiscount;
    if (discount > fee) discount = fee;
    return discount;
  }

  String? _phoneError(String phone) {
    if (phone.trim().isEmpty) return null;
    return _isValidPhone(phone) ? null : 'Phone number must be exactly 11 digits';
  }

  String? _txnError(String txn) {
    if (txn.trim().isEmpty) return null;
    return _isValidTransactionId(txn)
        ? null
        : 'Must be 10 characters: UPPERCASE letters & numbers only';
  }

  // ════════════════════════════════
  // BUILD
  // ════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Book Lab Test',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            onPressed: _showMyBookingsSheet,
            icon: const Icon(Icons.folder_open_rounded),
            tooltip: 'My Bookings',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHero(),
            const SizedBox(height: 12),
            _buildExploreDocumentsBanner(),
            const SizedBox(height: 16),
            _buildFilters(),
            const SizedBox(height: 16),
            _buildHospitalList(),
            if (selectedHospitalId != null) ...[
              _buildHomeCollectionToggle(),
              const SizedBox(height: 16),
              _buildTestList(),
            ],
            if (selectedTests.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildDatePicker(),
            ],
            if (selectedTests.isNotEmpty && selectedDate != null) ...[
              const SizedBox(height: 16),
              _buildSummaryAndBook(),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ── Explore Documents Banner ──
  Widget _buildExploreDocumentsBanner() {
    return GestureDetector(
      onTap: _showMyBookingsSheet,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: primary.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                  child: Icon(Icons.folder_open_rounded,
                      color: primary, size: 22)),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Explore Your Documents',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A2E))),
                  Text('View bookings & download invoices anytime',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: primary, size: 14),
          ],
        ),
      ),
    );
  }

  // ── My Bookings Bottom Sheet ──
  void _showMyBookingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(Icons.folder_open_rounded, color: primary),
                    SizedBox(width: 8),
                    Text('My Lab Bookings',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A2E))),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('Select a booking to download its invoice',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _MyBookingsList(scrollController: controller),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Hero Banner ──
  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF004D40), primary, accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('DIAGNOSTIC TESTS NEAR YOU',
              style: TextStyle(
                  fontSize: 10,
                  color: Colors.white70,
                  letterSpacing: 1.2)),
          const SizedBox(height: 4),
          const Text('Book Lab Test',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 4),
          const Text('Fast • Reliable • Affordable',
              style: TextStyle(fontSize: 12, color: Colors.white60)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _chip('📍 ${selectedLocation ?? 'Loading...'}'),
              _chip('🏥 $selectedType'),
              if (homeCollection) _chip('🏠 Home Collection'),
              if (selectedTests.isNotEmpty)
                _chip('🧪 ${selectedTests.length} Test(s) Selected'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 11, color: Colors.white)));

  // ── Filters ──
  Widget _buildFilters() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
            child: _filterDropdown(
          label: 'LOCATION',
          value: locations.contains(selectedLocation) ? selectedLocation : null,
          items: locations,
          onChanged: (val) {
            setState(() {
              selectedLocation = val;
              selectedHospitalId = null;
              selectedTests = [];
              labTests = [];
            });
            _loadHospitals();
          },
          active: true,
        )),
        const SizedBox(width: 6),
        // ── Current location icon — tap করলে GPS দিয়ে area detect
        // করে LOCATION dropdown-এ নিজে থেকে select হয়ে যায়।
        // Scroll করে manual select করার সুবিধা এতে বদলায় না।
        // (AppointmentScreen-এর সাথে হুবহু same widget) ──
        GestureDetector(
          onTap: isDetectingLocation ? null : detectCurrentLocation,
          child: Container(
            height: 45,
            width: 45,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBorder),
            ),
            child: isDetectingLocation
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: primary),
                  )
                : const Icon(Icons.my_location,
                    color: primary, size: 20),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
            child: _filterDropdown(
          label: 'TYPE',
          value: selectedType,
          items: const ['Government', 'Private'],
          onChanged: (val) {
            setState(() {
              selectedType = val!;
              selectedHospitalId = null;
              selectedTests = [];
              labTests = [];
            });
            _loadHospitals();
          },
          active: false,
        )),
      ],
    );
  }

  Widget _filterDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required bool active,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? primary : Colors.grey.shade300,
          width: active ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 9,
                  color: active ? primary : Colors.grey,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5)),
          DropdownButton<String>(
            value: value,
            hint: const Text('Select', style: TextStyle(fontSize: 12)),
            isExpanded: true,
            underline: const SizedBox(),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E)),
            items: items
                .map((i) => DropdownMenuItem(value: i, child: Text(i)))
                .toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  // ── Hospital List ──
  Widget _buildHospitalList() {
    if (!isLoadingHospitals && hospitals.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Select Hospital / Lab',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E))),
        const SizedBox(height: 10),
        if (isLoadingHospitals)
          const Center(child: CircularProgressIndicator(color: primary))
        else
          SizedBox(
            height: 45,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: hospitals.length,
              itemBuilder: (context, i) {
                final h = hospitals[i];
                final sel = selectedHospitalId == h['id'];
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedHospitalId = h['id'];
                      selectedHospitalName = h['name'];
                      selectedTests = [];
                      homeCollection = false;
                    });
                    final tests =
                        List<dynamic>.from(h['availableTests'] ?? []);
                    _loadTestsForHospital(tests);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: sel ? primary : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: sel ? primary : Colors.grey.shade300),
                    ),
                    child: Text(h['name'] ?? '',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: sel
                                ? Colors.white
                                : const Color(0xFF1A1A2E))),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }

  // ── Home Collection Toggle ──
  Widget _buildHomeCollectionToggle() {
    final charge =
        (paymentConfig['homeServiceCharge'] as num? ?? 0).toInt();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary.withValues(alpha: 0.08),
            accent.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: homeCollection ? primary : Colors.grey.shade300,
            width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
                child: Text('🏠', style: TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Home Sample Collection',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A2E))),
                Text(
                  charge > 0
                      ? 'Extra charge: ৳$charge • We collect from your door'
                      : 'We collect from your door',
                  style: const TextStyle(fontSize: 11, color: primary),
                ),
              ],
            ),
          ),
          Switch(
            value: homeCollection,
            onChanged: (val) {
              if (val && selectedTests.isNotEmpty) {
                final notEligible = selectedTests
                    .where((t) => t['homeEligible'] != true)
                    .toList();
                if (notEligible.isNotEmpty) {
                  _showHomeNotEligibleDialog(
                      notEligible.map((t) => t['name']).join(', '));
                  return;
                }
              }
              setState(() => homeCollection = val);
            },
            thumbColor: WidgetStateProperty.resolveWith<Color>(
              (states) => states.contains(WidgetState.selected)
                  ? primary
                  : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  void _showHomeNotEligibleDialog(String testName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Not Available'),
          ],
        ),
        content: Text(
          '$testName cannot be done via home collection. '
          'Please visit the hospital/lab in person.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
                backgroundColor: primary, foregroundColor: Colors.white),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  // ── Test List (multi-select) ──
  Widget _buildTestList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Select Test(s)',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(width: 8),
            if (selectedTests.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${selectedTests.length} selected',
                    style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        const Text('Tap to select one or more tests',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 10),
        if (isLoadingTests)
          const Center(child: CircularProgressIndicator(color: primary))
        else if (labTests.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text('No tests found for this hospital.',
                  style: TextStyle(color: Colors.grey)),
            ),
          )
        else
          ...labTests.map((test) => _buildTestCard(test)),
      ],
    );
  }

  Widget _buildTestCard(Map<String, dynamic> test) {
    final isSelected = _isTestSelected(test);
    final isAvailable = test['isAvailable'] == true;
    final color = Color(test['color'] as int? ?? 0xFF00B894);
    final homeEligible = test['homeEligible'] == true;
    final kitRequired = test['kitRequired'] == true;
    final kitCharge = (test['kitCharge'] as num? ?? 0).toInt();

    return GestureDetector(
      onTap: () => _toggleTest(test),
      child: Opacity(
        opacity: isAvailable ? 1.0 : 0.5,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: !isAvailable
                  ? Colors.grey.shade300
                  : isSelected
                      ? color
                      : Colors.grey.shade200,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                    child: Text(test['icon'] ?? '🧪',
                        style: const TextStyle(fontSize: 24))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(test['name'] ?? '',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A2E))),
                    Text(test['description'] ?? '',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      children: [
                        if (!isAvailable)
                          _tag('Unavailable', Colors.red.shade100,
                              Colors.red),
                        if (isAvailable && !homeEligible)
                          _tag('Visit Only', Colors.orange.shade100,
                              Colors.orange),
                        if (isAvailable && homeEligible)
                          _tag('Home ✓', Colors.green.shade100,
                              Colors.green),
                        if (kitRequired)
                          _tag('Kit: ৳$kitCharge',
                              Colors.blue.shade100, Colors.blue.shade700),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('৳${test['fee'] ?? 0}',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: color)),
                  if (kitRequired)
                    Text('+৳$kitCharge kit',
                        style: TextStyle(
                            fontSize: 10, color: Colors.blue.shade700)),
                  const SizedBox(height: 4),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: isSelected ? color : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: isSelected ? color : Colors.grey.shade400,
                          width: 1.5),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check,
                            color: Colors.white, size: 14)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(text,
            style: TextStyle(
                fontSize: 9, color: fg, fontWeight: FontWeight.w600)),
      );

  // ── Date Picker ──
  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Select Date',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E))),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    selectedDate != null ? primary : Colors.grey.shade300,
                width: selectedDate != null ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_month, color: primary),
                const SizedBox(width: 10),
                Text(
                  selectedDate != null
                      ? DateFormat('EEEE, MMM d, yyyy').format(selectedDate!)
                      : 'Tap to select date',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selectedDate != null
                          ? const Color(0xFF1A1A2E)
                          : Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Summary + Book Button ──
  Widget _buildSummaryAndBook() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Cost Summary',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E))),
              const SizedBox(height: 10),
              ...selectedTests.map((t) {
                final fee = (t['fee'] as num? ?? 0).toInt();
                final kit = t['kitRequired'] == true
                    ? (t['kitCharge'] as num? ?? 0).toInt()
                    : 0;
                return Column(
                  children: [
                    _summaryRow(t['name'] ?? '', '৳$fee'),
                    if (kit > 0)
                      _summaryRow(
                          '  └ Kit: ${t['kitName'] ?? ''}', '৳$kit',
                          color: Colors.blue.shade700),
                  ],
                );
              }),
              if (homeCollection && _homeServiceCharge > 0)
                _summaryRow('Home Service Charge', '৳$_homeServiceCharge'),
              if (_platformCharge > 0)
                _summaryRow('Platform Charge', '৳$_platformCharge',
                    color: Colors.grey.shade700),
              const Divider(height: 16),
              _summaryRow('Total', '৳$_totalFee',
                  bold: true, color: primary),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF004D40), primary],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ElevatedButton(
              onPressed: _showPaymentSheet,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${selectedTests.length} Test(s) selected',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white70)),
                      Text('Total: ৳$_totalFee',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ],
                  ),
                  const Text('Book Now →',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value,
          {bool bold = false, Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                    color: color ?? const Color(0xFF1A1A2E))),
          ],
        ),
      );

  // ════════════════════════════════
  // PAYMENT BOTTOM SHEET
  // (mirrors AppointmentScreen._showPaymentSheet exactly:
  //  Online/Cash toggle, promo code, wallet balance, operator chips)
  // ════════════════════════════════

  void _showPaymentSheet() async {
    // ── BLOCK CHECK: refuse to even open the payment sheet if this user
    // has been blocked by admin for this specific hospital ──
    final blocked = await _isUserBlockedForSelectedHospital();
    if (blocked) {
      _showBlockedDialog();
      return;
    }

    final fee = _feeBeforePlatformCharge;
    final platformCharge = _platformCharge;
    final bkashNumber = (paymentConfig['bkashNumber'] ?? '01XXXXXXXXX') as String;
    final nagadNumber = (paymentConfig['nagadNumber'] ?? '01XXXXXXXXX') as String;
    final rocketNumber = (paymentConfig['rocketNumber'] ?? '01XXXXXXXXX') as String;

    // Refresh wallet balance right before opening the sheet, and reset any
    // promo/balance state left over from a previous booking attempt.
    await _loadUserBalance();
    appliedVoucher = null;
    appliedVoucherId = null;
    promoError = null;
    useBalance = false;
    promoCodeController.clear();

    final senderController = TextEditingController();
    final transactionController = TextEditingController();
    String selectedPaymentType = 'Online';
    // Which operator (bKash / Nagad / Rocket) the user tapped. Drives the
    // dynamic "Enter your <Operator> number" hint on the phone field below.
    String selectedOperator = 'bKash';

    // validation error states
    String? phoneError;
    String? txnError;

    if (!mounted) return;

    // Map operator name -> its receiving number, used to build the
    // "Send payment to" chips for both Online and Cash flows.
    Map<String, String> operatorNumbers() => {
          'bKash': bkashNumber,
          'Nagad': nagadNumber,
          'Rocket': rocketNumber,
        };

    Map<String, Color> operatorColors() => {
          'bKash': Colors.pink,
          'Nagad': Colors.orange,
          'Rocket': Colors.purple,
        };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          // ── Amount calculations (fee → discount → platform charge → balance) ──
          final int discount = _calculateDiscount(fee);
          final int feeAfterDiscount = fee - discount;

          // Cash-on-collection always still needs the platform charge paid
          // now; Online needs discounted-fee + platform charge paid now.
          final int baseNowPaying = selectedPaymentType == 'Online'
              ? feeAfterDiscount + platformCharge
              : platformCharge;

          final int maxBalanceApplicable =
              baseNowPaying < userBalance ? baseNowPaying : userBalance;
          final int balanceUsed =
              (useBalance && userBalance > 0) ? maxBalanceApplicable : 0;

          final int nowPaying = baseNowPaying - balanceUsed;
          final int dueAmount =
              selectedPaymentType == 'Online' ? 0 : feeAfterDiscount;
          final bool fullyCoveredByBalance = nowPaying <= 0;

          // Builds the tappable bKash/Nagad/Rocket row + the phone number
          // field whose label follows whichever operator is selected.
          Widget buildOperatorAndPhoneSection() {
            final numbers = operatorNumbers();
            final colors = operatorColors();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Send payment to:',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: numbers.keys.map((op) {
                    final isLast = op == numbers.keys.last;
                    return Expanded(
                      child: Padding(
                        padding:
                            EdgeInsets.only(right: isLast ? 0 : 8),
                        child: _paymentChip(
                          name: op,
                          number: numbers[op]!,
                          color: colors[op]!,
                          selected: selectedOperator == op,
                          onTap: () => setModalState(
                              () => selectedOperator = op),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Phone field — label/hint reflects the selected operator
                TextField(
                  controller: senderController,
                  keyboardType: TextInputType.phone,
                  maxLength: 11,
                  onChanged: (v) => setModalState(() {
                    phoneError = _isValidPhone(v)
                        ? null
                        : 'Phone number must be exactly 11 digits';
                  }),
                  decoration: InputDecoration(
                    labelText: 'Enter your $selectedOperator number',
                    hintText: '01XXXXXXXXX',
                    counterText: '',
                    prefixIcon:
                        const Icon(Icons.phone, color: primary),
                    errorText: phoneError,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: primary, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Transaction ID field
                TextField(
                  controller: transactionController,
                  maxLength: 10,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (v) => setModalState(() {
                    txnError = _isValidTransactionId(v)
                        ? null
                        : 'Must be 10 characters: UPPERCASE letters & numbers only';
                  }),
                  decoration: InputDecoration(
                    labelText:
                        '$selectedOperator Transaction ID',
                    hintText: 'AB12CD34EF',
                    counterText: '',
                    prefixIcon:
                        const Icon(Icons.receipt, color: primary),
                    errorText: txnError,
                    helperText:
                        '10 characters · UPPERCASE + numbers (e.g. AB12CD34EF)',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: primary, width: 2),
                    ),
                  ),
                ),
              ],
            );
          }

          // ── Promo code entry / applied-chip section ──
          Widget buildPromoSection() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Promo Code (optional)',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                if (appliedVoucher == null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: promoCodeController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            hintText: 'Enter code e.g. VIP100',
                            errorText: promoError,
                            isDense: true,
                            prefixIcon: const Icon(
                                Icons.local_offer_outlined,
                                color: primary),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: isCheckingPromo
                            ? null
                            : () => _applyPromoCode(
                                code: promoCodeController.text,
                                fee: fee,
                                setModalState: setModalState),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: isCheckingPromo
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Apply'),
                      ),
                    ],
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kGreenLight,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: kGreen.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: kGreen, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${appliedVoucher!['code']} applied — ৳${_calculateDiscount(fee)} off',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: kGreen),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setModalState(() {
                            appliedVoucher = null;
                            appliedVoucherId = null;
                            promoCodeController.clear();
                          }),
                          child: const Icon(Icons.close,
                              size: 18, color: kSubtext),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          }

          // ── Wallet balance toggle section ──
          Widget buildBalanceSection() {
            if (userBalance <= 0) return const SizedBox();
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Use wallet balance',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        Text('Available: ৳$userBalance',
                            style: const TextStyle(
                                fontSize: 11, color: kSubtext)),
                      ],
                    ),
                  ),
                  Switch(
                    value: useBalance,
                    activeColor: primary,
                    onChanged: (v) => setModalState(() => useBalance = v),
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: kBorder,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Payment Details',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),

                  // ── Payment type toggle ──────────────
                  const Text('Payment Type',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _payTypeCard(
                          selected: selectedPaymentType == 'Online',
                          icon: '📱',
                          title: 'Online Payment',
                          subtitle:
                              'Pay ৳${feeAfterDiscount + platformCharge} (full)',
                          onTap: () => setModalState(
                              () => selectedPaymentType = 'Online'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _payTypeCard(
                          selected: selectedPaymentType == 'Cash',
                          icon: '💵',
                          title: 'Pay at Lab/Hospital',
                          subtitle: 'Pay ৳$platformCharge now',
                          onTap: () => setModalState(
                              () => selectedPaymentType = 'Cash'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Promo code ────────────────────────
                  buildPromoSection(),
                  const SizedBox(height: 16),

                  // ── Wallet balance ────────────────────
                  buildBalanceSection(),
                  const SizedBox(height: 16),

                  // ── Summary box ──────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2F1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedTests.length == 1
                                      ? (selectedTests.first['name'] ?? '')
                                      : '${selectedTests.length} Tests',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: kText),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  DateFormat('MMM d, yyyy')
                                      .format(selectedDate!),
                                  style: const TextStyle(
                                      fontSize: 12, color: kSubtext),
                                ),
                                Text(selectedHospitalName ?? '',
                                    style: const TextStyle(
                                        fontSize: 11, color: primary)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.end,
                              children: [
                                Text('৳$nowPaying',
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: primary)),
                                Text(
                                  fullyCoveredByBalance
                                      ? 'Covered by balance'
                                      : selectedPaymentType == 'Online'
                                          ? 'Full payment'
                                          : 'Platform charge',
                                  style: const TextStyle(
                                      fontSize: 10, color: kSubtext),
                                ),
                              ],
                            ),
                          ],
                        ),
                        // calculation breakdown
                        const SizedBox(height: 10),
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        _calcRow('Test fee', '৳$_totalTestFee'),
                        if (_totalKitCharge > 0) ...[
                          const SizedBox(height: 4),
                          _calcRow('Kit charge', '৳$_totalKitCharge'),
                        ],
                        if (homeCollection && _homeServiceCharge > 0) ...[
                          const SizedBox(height: 4),
                          _calcRow(
                              'Home service charge', '৳$_homeServiceCharge'),
                        ],
                        if (discount > 0) ...[
                          const SizedBox(height: 4),
                          _calcRow('Promo discount', '- ৳$discount',
                              color: kGreen),
                        ],
                        const SizedBox(height: 4),
                        _calcRow('Platform charge', '৳$platformCharge'),
                        const Divider(height: 12),
                        _calcRow('Total',
                            '৳${feeAfterDiscount + platformCharge}',
                            bold: true),
                        if (balanceUsed > 0) ...[
                          const SizedBox(height: 4),
                          _calcRow('Balance used', '- ৳$balanceUsed',
                              color: kGreen),
                        ],
                        const SizedBox(height: 4),
                        _calcRow('Paying now', '৳$nowPaying',
                            color: kGreen),
                        if (dueAmount > 0) ...[
                          const SizedBox(height: 4),
                          _calcRow('Due at lab/hospital', '৳$dueAmount',
                              color: kRed),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Online / Cash fields ──────────────
                  // Skipped entirely if the wallet balance already covers
                  // the full "pay now" amount — nothing left to send via
                  // bKash/Nagad/Rocket in that case.
                  if (!fullyCoveredByBalance) ...[
                    if (selectedPaymentType == 'Online')
                      buildOperatorAndPhoneSection()
                    else ...[
                      // Pay-at-lab info
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: Colors.orange.shade200),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.orange, size: 16),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Pay platform charge now. Remaining test fee is due at the hospital/lab.',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.orange),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      buildOperatorAndPhoneSection(),
                    ],
                  ] else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kGreenLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: kGreen.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.account_balance_wallet,
                              color: kGreen, size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This payment is fully covered by your wallet balance — no bKash/Nagad/Rocket needed.',
                              style: TextStyle(
                                  fontSize: 12, color: kGreen),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),

                  // ── Submit button ────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => _submitLabBooking(
                        senderController.text,
                        transactionController.text,
                        selectedPaymentType,
                        nowPaying,
                        dueAmount,
                        platformCharge,
                        fee,
                        discount,
                        balanceUsed,
                        fullyCoveredByBalance,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(
                        fullyCoveredByBalance
                            ? 'Confirm Booking (Paid by Balance)'
                            : selectedPaymentType == 'Online'
                                ? 'Confirm & Pay ৳$nowPaying'
                                : 'Book — Pay Platform Charge ৳$nowPaying',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _payTypeCard({
    required bool selected,
    required String icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? primary : kBorder, width: 1.5),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 4),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: selected ? Colors.white : primary)),
            const SizedBox(height: 2),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10,
                    color: selected
                        ? Colors.white70
                        : kSubtext)),
          ],
        ),
      ),
    );
  }

  // Tappable operator chip — highlights when selected and toggles the
  // operator used to build the dynamic phone-field label.
  Widget _paymentChip({
    required String name,
    required String number,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.18) : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.3),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (selected) ...[
                  Icon(Icons.check_circle, size: 12, color: color),
                  const SizedBox(width: 3),
                ],
                Text(name,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ],
            ),
            Text(number,
                style: const TextStyle(fontSize: 9, color: kSubtext)),
          ],
        ),
      ),
    );
  }

  Widget _calcRow(String label, String value,
      {bool bold = false, Color? color}) {
    final style = TextStyle(
      fontSize: bold ? 13 : 12,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: color ?? (bold ? kText : kSubtext),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label, style: style), Text(value, style: style)],
    );
  }

  // ════════════════════════════════
  // SUBMIT (mirrors AppointmentScreen._submitAppointment)
  // ════════════════════════════════

  Future<void> _submitLabBooking(
    String sender,
    String transactionId,
    String paymentType,
    int amountPaid,
    int dueAmount,
    int platformCharge,
    int fee,
    int discount,
    int balanceUsed,
    bool fullyCoveredByBalance,
  ) async {
    // Validate phone/transaction ID only when there's actually something
    // to send via bKash/Nagad/Rocket. If wallet balance covers everything,
    // these fields never appeared in the sheet, so skip validating them.
    if (!fullyCoveredByBalance) {
      if (!_isValidPhone(sender)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid 11-digit phone number!'),
            backgroundColor: kRed,
          ),
        );
        return;
      }

      if (!_isValidTransactionId(transactionId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Transaction ID must be exactly 10 characters (UPPERCASE + numbers)!'),
            backgroundColor: kRed,
          ),
        );
        return;
      }
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final voucherId = appliedVoucherId;
    final promoCode = appliedVoucher != null
        ? (appliedVoucher!['code'] ?? '').toString()
        : '';

    final receiptNumber = _generateReceiptNumber();

    final testsList = selectedTests
        .map((t) => {
              'testName': t['name'],
              'testFee': (t['fee'] as num? ?? 0).toInt(),
              'kitRequired': t['kitRequired'] ?? false,
              'kitCharge': t['kitRequired'] == true
                  ? (t['kitCharge'] as num? ?? 0).toInt()
                  : 0,
              'kitName': t['kitName'] ?? '',
            })
        .toList();

    try {
      final firestore = FirebaseFirestore.instance;
      final userRef = firestore.collection('users').doc(user.uid);
      final bookingRef = firestore.collection('lab_bookings').doc();
      DocumentReference<Map<String, dynamic>>? voucherRef;
      DocumentReference<Map<String, dynamic>>? claimedVoucherRef;
      if (voucherId != null) {
        voucherRef = firestore.collection('vouchers').doc(voucherId);
        claimedVoucherRef =
            userRef.collection('claimedVouchers').doc(voucherId);
      }

      // Block-check reference for this hospital (re-verified inside the
      // transaction below so a block placed after the sheet opened still
      // stops the booking from being written).
      final blockedRef = selectedHospitalId == null
          ? null
          : firestore
              .collection('hospitals')
              .doc(selectedHospitalId)
              .collection('blockedUsers')
              .doc(user.uid);

      // ── Transaction: re-validate + atomically update voucher usage,
      // the user's wallet balance, and create the booking together.
      // This prevents double-spending a limited voucher or the wallet
      // balance if the user has two booking attempts running at once. ──
      await firestore.runTransaction((transaction) async {
        Map<String, dynamic>? voucherData;
        int currentBalance = 0;

        // Re-check the hospital-specific block status fresh, inside the
        // transaction, right before writing the booking.
        if (blockedRef != null) {
          final blockedSnap = await transaction.get(blockedRef);
          if (blockedSnap.exists) {
            throw Exception(
                'You are blocked from booking at this hospital.');
          }
        }

        // Re-read balance fresh inside the transaction.
        final freshUserSnap = await transaction.get(userRef);
        currentBalance =
            ((freshUserSnap.data()?['balance'] ?? 0) as num).toInt();

        if (balanceUsed > 0 && currentBalance < balanceUsed) {
          throw Exception(
              'Your wallet balance changed — please try again.');
        }

        if (voucherRef != null) {
          final freshVoucherSnap = await transaction.get(voucherRef);
          if (!freshVoucherSnap.exists) {
            throw Exception('This promo code is no longer available.');
          }
          voucherData = freshVoucherSnap.data();
          final usageLimit =
              ((voucherData?['usageLimit'] ?? 0) as num).toInt();
          final usedCount =
              ((voucherData?['usedCount'] ?? 0) as num).toInt();
          if (voucherData?['isActive'] != true ||
              (usageLimit > 0 && usedCount >= usageLimit)) {
            throw Exception('This promo code is no longer valid.');
          }

          int freshTimesClaimed = 0;
          if (claimedVoucherRef != null) {
            final freshClaimedSnap =
                await transaction.get(claimedVoucherRef);
            freshTimesClaimed = freshClaimedSnap.exists
                ? ((freshClaimedSnap.data()?['timesClaimed'] ?? 0) as num)
                    .toInt()
                : 0;
          }
          final perUserLimit =
              ((voucherData?['perUserLimit'] ?? 1) as num).toInt();
          if (freshTimesClaimed >= perUserLimit) {
            throw Exception(
                'You have already used this promo code the maximum number of times.');
          }

          transaction.update(voucherRef, {
            'usedCount': FieldValue.increment(1),
          });
          transaction.set(
            claimedVoucherRef!,
            {
              'voucherId': voucherId,
              'code': promoCode,
              'timesClaimed': FieldValue.increment(1),
              'lastClaimedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        if (balanceUsed > 0) {
          transaction.update(userRef, {
            'balance': FieldValue.increment(-balanceUsed),
          });
        }

        transaction.set(bookingRef, {
          'userId':           user.uid,
          'tests':            testsList,
          'testName':         selectedTests.length == 1
              ? selectedTests.first['name']
              : '${selectedTests.length} Tests',
          'testFee':          _totalTestFee,
          'hospitalId':       selectedHospitalId,
          'hospitalName':     selectedHospitalName,
          'location':         selectedLocation,
          'date':             DateFormat('yyyy-MM-dd').format(selectedDate!),
          'homeCollection':   homeCollection,
          'homeServiceCharge': _homeServiceCharge,
          'kitCharge':        _totalKitCharge,
          'fee':              fee,
          'platformCharge':   platformCharge,
          'promoCode':        promoCode,
          'voucherId':        voucherId ?? '',
          'discountAmount':   discount,
          'balanceUsed':      balanceUsed,
          'amountPaid':       amountPaid,
          'dueAmount':        dueAmount,
          'totalFee':         fee - discount + platformCharge,
          'codHospitalFee':   dueAmount,
          'paymentMethod':    fullyCoveredByBalance ? 'balance' : paymentType.toLowerCase(),
          'paymentType':      fullyCoveredByBalance ? 'Balance' : paymentType,
          'paymentNumber':    fullyCoveredByBalance ? '' : sender,
          'senderNumber':     fullyCoveredByBalance ? '' : sender,
          'transactionId':    fullyCoveredByBalance ? '' : transactionId,
          'status':           'pending',
          'reportUrl':        '',
          'receiptNumber':    receiptNumber,
          'createdAt':        FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      Navigator.pop(context); // close bottom sheet

      // Local balance display refresh (already deducted server-side above).
      if (balanceUsed > 0) {
        setState(() => userBalance -= balanceUsed);
      }

      showLabBookingConfirmationDialog(
        context,
        bookingRef.id,
        receiptNumber: receiptNumber,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: kRed,
        ),
      );
    }
  }
}

// ════════════════════════════════
// MY BOOKINGS LIST WIDGET
// ════════════════════════════════

class _MyBookingsList extends StatelessWidget {
  final ScrollController scrollController;
  static const primary = Color(0xFF00897B);

  const _MyBookingsList({required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Please login to view bookings.'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('lab_bookings')
          .where('userId', isEqualTo: user.uid)
          // ── orderBy সরানো হয়েছে — client-side sort করা হবে ──
          // Firestore composite index না থাকলে docs silently filter হয়ে
          // "No bookings yet" দেখায়। এই fix এ সেটা হবে না।
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: primary));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_open, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text('No bookings yet.',
                    style: TextStyle(color: Colors.grey, fontSize: 14)),
              ],
            ),
          );
        }

        // ── Client-side sort by createdAt descending ──
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTime = aData['createdAt'];
            final bTime = bData['createdAt'];
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return (bTime as Timestamp).compareTo(aTime as Timestamp);
          });

        return ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final bookingId = docs[i].id;
            final status = data['status'] ?? 'pending';
            final testName = data['testName'] ?? '';
            final hospitalName = data['hospitalName'] ?? '';
            final date = data['date'] ?? '';
            final totalFee = (data['totalFee'] as num? ?? 0).toInt();
            final receiptNumber = data['receiptNumber']?.toString() ?? '';
            final createdAt = data['createdAt'];
            String createdStr = '';
            if (createdAt is Timestamp) {
              createdStr = DateFormat('dd MMM yyyy')
                  .format(createdAt.toDate());
            }

            Color statusColor;
            String statusLabel;
            IconData statusIcon;
            switch (status) {
              case 'approved':
                statusColor = primary;
                statusLabel = 'Approved';
                statusIcon = Icons.check_circle_rounded;
                break;
              case 'rejected':
                statusColor = Colors.red;
                statusLabel = 'Rejected';
                statusIcon = Icons.cancel_rounded;
                break;
              default:
                statusColor = Colors.orange;
                statusLabel = 'Pending';
                statusIcon = Icons.hourglass_top_rounded;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(testName,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A2E))),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon,
                                size: 12, color: statusColor),
                            const SizedBox(width: 4),
                            Text(statusLabel,
                                style: TextStyle(
                                    fontSize: 10,
                                    color: statusColor,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('$hospitalName • $date',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey)),
                  if (receiptNumber.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('Receipt: $receiptNumber',
                          style: TextStyle(
                              fontSize: 10,
                              color: primary.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w600)),
                    ),
                  if (createdStr.isNotEmpty)
                    Text('Booked: $createdStr',
                        style: const TextStyle(
                            fontSize: 10, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('৳$totalFee',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: primary)),
                      const Spacer(),
                      if (status == 'approved')
                        ElevatedButton.icon(
                          icon: const Icon(Icons.download_rounded,
                              size: 14),
                          label: const Text('Invoice',
                              style: TextStyle(fontSize: 12)),
                          onPressed: () =>
                              LabInvoiceService.downloadInvoicePDF(
                                  bookingId),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(8)),
                          ),
                        )
                      else if (status == 'pending')
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.orange.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Colors.orange.shade600,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text('Awaiting Approval',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.orange.shade700,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        )
                      else
                        Text('Booking Rejected',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.red.shade600,
                                fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ════════════════════════════════
// TEST REPORT DOWNLOAD BUTTON
// ════════════════════════════════

class TestReportDownloadButton extends StatelessWidget {
  final String bookingId;
  final String? reportUrl;

  const TestReportDownloadButton({
    super.key,
    required this.bookingId,
    this.reportUrl,
  });

  @override
  Widget build(BuildContext context) {
    if (reportUrl == null || reportUrl!.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_empty, size: 14, color: Colors.grey),
            SizedBox(width: 4),
            Text('Report Pending',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
    }
    return ElevatedButton.icon(
      icon: const Icon(Icons.download, size: 16),
      label:
          const Text('Download Report', style: TextStyle(fontSize: 12)),
      onPressed: () async {
        // TODO: use dio/http to download reportUrl, then open with OpenFile
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}