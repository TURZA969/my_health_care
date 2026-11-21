import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'invoice_appoinment.dart';

class AppointmentScreen extends StatefulWidget {
  const AppointmentScreen({super.key});

  @override
  State<AppointmentScreen> createState() => _AppointmentScreenState();
}

class _AppointmentScreenState extends State<AppointmentScreen> {
  String? selectedLocation;
  String? selectedDistrict;
  String selectedType = 'Government';
  String? selectedHospitalId;
  String? selectedHospitalName;
  String? selectedSpecialty;
  DateTime? selectedDate;
  bool isLoadingHospitals = false;
  bool isLoadingDoctors = false;
  bool isDetectingLocation = false; // GPS icon tap থেকে location detect হওয়ার সময় true
  List<Map<String, dynamic>> hospitals = [];
  List<Map<String, dynamic>> doctors = [];
  List<String> locations = [];
  List<String> specialties = [];

  // ── Promo code & wallet balance state ────────────────
  final TextEditingController promoCodeController = TextEditingController();
  Map<String, dynamic>? appliedVoucher; // raw voucher doc data
  String? appliedVoucherId;
  String? promoError;
  bool isCheckingPromo = false;

  bool useBalance = false;
  int userBalance = 0;

  // ── Colors ──────────────────────────────────────────
  static const Color kPrimary    = Color(0xFF1565C0);
  static const Color kAccent     = Color(0xFF0288D1);
  static const Color kBg         = Color(0xFFF0F4F8);
  static const Color kCard       = Colors.white;
  static const Color kText       = Color(0xFF1A1A2E);
  static const Color kSubtext    = Color(0xFF6B7280);
  static const Color kBorder     = Color(0xFFE5E7EB);
  static const Color kGreen      = Color(0xFF2E7D32);
  static const Color kGreenLight = Color(0xFFE8F5E9);
  static const Color kRed        = Color(0xFFC62828);
  static const Color kRedLight   = Color(0xFFFFEBEE);
  static const Color kAmber      = Color(0xFFF59E0B);

  // ── GPS sub-area name (lowercase) -> hospitals collection-এর
  // 'location' field-এর সাথে exact match হওয়া নাম। প্রয়োজনমতো এখানে
  // আরও area/alias যোগ করে নিন যাতে আপনার আসল Firestore data-র সাথে মেলে। ──
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
    loadUserLocation();
    loadLocations();
    loadUserBalance();
  }

  Future<void> loadUserLocation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final address = doc.data()?['address'] ?? '';
        final parts = address.split(',');
        setState(() {
          selectedLocation = parts.isNotEmpty ? parts[0].trim() : '';
          selectedDistrict = parts.length > 1 ? parts[1].trim() : '';
        });
      }
    }
  }

  // ── Tap করলে GPS দিয়ে current location detect করে LOCATION dropdown-এ
  // select করে দেয়। Scroll করে manual select করার সুবিধা আগের মতোই থাকে —
  // এটা শুধু dropdown-এর value পরিবর্তন করে, dropdown নিজে অপরিবর্তিত। ──
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
        doctors = [];
        isDetectingLocation = false;
      });
      loadHospitals();
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
  Future<void> loadUserBalance() async {
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
          'You have been blocked from booking appointments at ${selectedHospitalName ?? 'this hospital'}. '
          'You can still book at other hospitals. Please contact the hospital if you think this is a mistake.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary, foregroundColor: Colors.white),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  Future<void> loadLocations() async {
    final snapshot =
        await FirebaseFirestore.instance.collection('hospitals').get();
    final locs = snapshot.docs
        .map((d) => d.data()['location']?.toString() ?? '')
        .toSet()
        .toList();
    setState(() => locations = locs);
    if (selectedLocation != null && locations.contains(selectedLocation)) {
      loadHospitals();
    } else if (locations.isNotEmpty) {
      setState(() => selectedLocation = locations.first);
      loadHospitals();
    }
  }

  Future<void> loadHospitals() async {
    if (selectedLocation == null) return;
    setState(() {
      isLoadingHospitals = true;
      hospitals = [];
      selectedHospitalId = null;
      doctors = [];
    });
    final snapshot = await FirebaseFirestore.instance
        .collection('hospitals')
        .where('location', isEqualTo: selectedLocation)
        .where('type', isEqualTo: selectedType)
        .get();
    setState(() {
      hospitals =
          snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      isLoadingHospitals = false;
    });
  }

  Future<void> loadSpecialties() async {
    if (selectedHospitalId == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('hospitals')
        .doc(selectedHospitalId)
        .get();
    if (doc.exists) {
      final specs = List<String>.from(doc.data()?['specialties'] ?? []);
      setState(() {
        specialties
          ..clear()
          ..addAll(specs);
        selectedSpecialty = null;
        doctors = [];
      });
    }
  }

  Future<void> loadDoctors() async {
    if (selectedHospitalId == null || selectedSpecialty == null) return;
    setState(() {
      isLoadingDoctors = true;
      doctors = [];
    });
    final snapshot = await FirebaseFirestore.instance
        .collection('doctors')
        .where('hospitalId', isEqualTo: selectedHospitalId)
        .where('specialty', isEqualTo: selectedSpecialty)
        .get();
    setState(() {
      doctors =
          snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      isLoadingDoctors = false;
    });
  }

  Future<int> getBookedSlots(String doctorId, String date) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('appointments')
        .where('doctorId', isEqualTo: doctorId)
        .where('date', isEqualTo: date)
        .get();
    return snapshot.docs.length;
  }

  Future<Map<String, dynamic>> getSettings() async {
    final doc = await FirebaseFirestore.instance
        .collection('settings')
        .doc('app_settings')
        .get();
    return {
      'platformCharge': (doc.data()?['platformCharge'] ?? 20) as int,
      'bkashNumber':  doc.data()?['bkashNumber']  ?? '01XXXXXXXXX',
      'nagadNumber':  doc.data()?['nagadNumber']  ?? '01XXXXXXXXX',
      'rocketNumber': doc.data()?['rocketNumber'] ?? '01XXXXXXXXX',
    };
  }

  // ── Date picker — max 20 days ────────────────────────
  Future<void> pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 20)), // max 20 days
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: kPrimary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => selectedDate = picked);
      if (selectedHospitalId != null && selectedSpecialty != null) {
        loadDoctors();
      }
    }
  }

  // ── Validation helpers ───────────────────────────────
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
      if (applicableTo != 'all' && applicableTo != 'appointment') {
        setModalState(() {
          isCheckingPromo = false;
          promoError = 'This code is not valid for appointments';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Book Appointment',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'My Appointments & Invoices',
            icon: const Icon(Icons.receipt_long_rounded),
            onPressed: _showMyAppointmentsSheet,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero ──────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D47A1), kPrimary, Color(0xFF0288D1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('FIND THE BEST DOCTOR',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                          letterSpacing: 1)),
                  const SizedBox(height: 4),
                  const Text('Book Appointment',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _chip('📍 ${selectedLocation ?? 'Loading...'}'),
                      const SizedBox(width: 8),
                      _chip('🏥 $selectedType'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Filter ────────────────────────────────
            const Text('Filter',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: kText)),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _dropdownBox(
                    label: 'LOCATION',
                    active: true,
                    child: DropdownButton<String>(
                      value: locations.contains(selectedLocation)
                          ? selectedLocation
                          : null,
                      hint: const Text('Select',
                          style: TextStyle(fontSize: 12)),
                      isExpanded: true,
                      underline: const SizedBox(),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: kText),
                      items: locations
                          .map((loc) => DropdownMenuItem(
                              value: loc, child: Text(loc)))
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          selectedLocation = val;
                          selectedHospitalId = null;
                          doctors = [];
                        });
                        loadHospitals();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // ── Current location icon — tap করলে GPS দিয়ে area detect
                // করে LOCATION dropdown-এ নিজে থেকে select হয়ে যায়।
                // Scroll করে manual select করার সুবিধা এতে বদলায় না। ──
                GestureDetector(
                  onTap: isDetectingLocation ? null : detectCurrentLocation,
                  child: Container(
                    height: 45,
                    width: 45,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: kCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kBorder),
                    ),
                    child: isDetectingLocation
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: kPrimary),
                          )
                        : const Icon(Icons.my_location,
                            color: kPrimary, size: 20),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _dropdownBox(
                    label: 'TYPE',
                    active: false,
                    child: DropdownButton<String>(
                      value: selectedType,
                      isExpanded: true,
                      underline: const SizedBox(),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: kText),
                      items: ['Government', 'Private']
                          .map((t) => DropdownMenuItem(
                              value: t, child: Text(t)))
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          selectedType = val!;
                          selectedHospitalId = null;
                          doctors = [];
                        });
                        loadHospitals();
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Hospital list ─────────────────────────
            if (hospitals.isNotEmpty || isLoadingHospitals) ...[
              const Text('Select Hospital',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: kText)),
              const SizedBox(height: 10),
              if (isLoadingHospitals)
                const Center(
                    child: CircularProgressIndicator(color: kPrimary))
              else
                SizedBox(
                  height: 45,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: hospitals.length,
                    itemBuilder: (context, index) {
                      final hospital = hospitals[index];
                      final isSelected =
                          selectedHospitalId == hospital['id'];
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            selectedHospitalId = hospital['id'];
                            selectedHospitalName = hospital['name'];
                            doctors = [];
                          });
                          loadSpecialties();
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? kPrimary : kCard,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? kPrimary : kBorder,
                            ),
                          ),
                          child: Text(
                            hospital['name'] ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white : kText,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
            ],

            // ── Specialty ─────────────────────────────
            if (selectedHospitalId != null && specialties.isNotEmpty) ...[
              const Text('Select Specialist',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: kText)),
              const SizedBox(height: 10),
              SizedBox(
                height: 45,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: specialties.length,
                  itemBuilder: (context, index) {
                    final spec = specialties[index];
                    final isSelected = selectedSpecialty == spec;
                    return GestureDetector(
                      onTap: () {
                        setState(() => selectedSpecialty = spec);
                        if (selectedDate != null) loadDoctors();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? kPrimary : kCard,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? kPrimary : kBorder,
                          ),
                        ),
                        child: Text(
                          spec,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.white : kText,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Date picker ───────────────────────────
            if (selectedSpecialty != null) ...[
              const Text('Select Date',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: kText)),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: pickDate,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selectedDate != null ? kPrimary : kBorder,
                      width: selectedDate != null ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month, color: kPrimary),
                      const SizedBox(width: 10),
                      Text(
                        selectedDate != null
                            ? DateFormat('EEEE, MMM d, yyyy')
                                .format(selectedDate!)
                            : 'Tap to select date (within 20 days)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selectedDate != null ? kText : kSubtext,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Doctor list ───────────────────────────
            if (selectedDate != null && selectedSpecialty != null) ...[
              const Text('Available Doctors',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: kText)),
              const SizedBox(height: 10),
              if (isLoadingDoctors)
                const Center(
                    child: CircularProgressIndicator(color: kPrimary))
              else if (doctors.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      color: kCard,
                      borderRadius: BorderRadius.circular(16)),
                  child: const Center(
                      child: Text('No doctors found',
                          style: TextStyle(color: kSubtext))),
                )
              else
                ...doctors.map((doctor) => _buildDoctorCard(doctor)),
            ],
          ],
        ),
      ),
    );
  }

  // ── My Appointments Bottom Sheet ──────────────────────
  void _showMyAppointmentsSheet() {
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
                    Icon(Icons.receipt_long_rounded, color: kPrimary),
                    SizedBox(width: 8),
                    Text('My Appointments',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: kText)),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                    'Approved or completed appointments — download their invoice',
                    style: TextStyle(fontSize: 12, color: kSubtext)),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _MyAppointmentsList(scrollController: controller),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Chip ──────────────────────────────────────────────
  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 11, color: Colors.white)),
    );
  }

  Widget _dropdownBox(
      {required String label,
      required bool active,
      required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? kPrimary : kBorder,
          width: active ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 9,
                  color: active ? kPrimary : kSubtext,
                  fontWeight: FontWeight.bold)),
          child,
        ],
      ),
    );
  }

  // ── Doctor card ───────────────────────────────────────
  Widget _buildDoctorCard(Map<String, dynamic> doctor) {
    final dateStr = selectedDate != null
        ? DateFormat('yyyy-MM-dd').format(selectedDate!)
        : '';

    // Doctor unavailable check
    final bool isAvailable = doctor['isAvailable'] ?? true;

    return FutureBuilder<int>(
      future: getBookedSlots(doctor['id'], dateStr),
      builder: (context, snapshot) {
        final bookedSlots = snapshot.data ?? 0;
        const totalSlots = 20;
        final availableSlots = totalSlots - bookedSlots;
        final isFull = availableSlots <= 0;

        // rating
        final double rating =
            (doctor['rating'] ?? 0).toDouble();
        final int totalRatings = (doctor['totalRatings'] ?? 0) as int;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kBorder),
            boxShadow: [
              BoxShadow(
                color: kPrimary.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Unavailable banner
              if (!isAvailable)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: const BoxDecoration(
                    color: kRedLight,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(18)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.block, color: kRed, size: 14),
                      SizedBox(width: 6),
                      Text('Doctor Unavailable',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: kRed)),
                    ],
                  ),
                ),

              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Avatar
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE3F2FD),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                              child: Text('👨‍⚕️',
                                  style: TextStyle(fontSize: 28))),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(doctor['name'] ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: kText)),
                              const SizedBox(height: 2),
                              // Degree under name
                              if ((doctor['degree'] ?? '').isNotEmpty)
                                Text(doctor['degree'],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: kSubtext)),
                              const SizedBox(height: 2),
                              Text(doctor['specialty'] ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: kPrimary,
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(height: 6),
                              // Use Wrap (not Row) so long rating/experience
                              // text never overflows the card horizontally.
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment:
                                    WrapCrossAlignment.center,
                                children: [
                                  _starDisplay(rating),
                                  Text(
                                    rating > 0
                                        ? '${rating.toStringAsFixed(1)} ($totalRatings)'
                                        : 'No ratings',
                                    style: const TextStyle(
                                        fontSize: 11, color: kSubtext),
                                  ),
                                  Text(
                                      '${doctor['experience'] ?? '0'} yrs exp',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: kSubtext)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('৳${doctor['fee'] ?? '500'}',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: kPrimary)),
                            const SizedBox(height: 4),
                            if (!isAvailable)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: kRedLight,
                                  borderRadius:
                                      BorderRadius.circular(6),
                                ),
                                child: const Text('Unavailable',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: kRed)),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isFull
                                      ? kRedLight
                                      : kGreenLight,
                                  borderRadius:
                                      BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isFull
                                      ? 'Full'
                                      : '$availableSlots left',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isFull ? kRed : kGreen,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Slots
                    if (isAvailable)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children:
                            List.generate(totalSlots, (index) {
                          final slotNum = index + 1;
                          final isBooked = slotNum <= bookedSlots;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isBooked
                                  ? kRedLight
                                  : const Color(0xFFE3F2FD),
                              borderRadius:
                                  BorderRadius.circular(20),
                            ),
                            child: Text(
                              isBooked ? '×' : '$slotNum',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isBooked
                                    ? kRed
                                    : kPrimary,
                              ),
                            ),
                          );
                        }),
                      ),
                    const SizedBox(height: 12),

                    // Book button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (!isAvailable || isFull)
                            ? null
                            : () => _showPaymentSheet(
                                doctor, bookedSlots + 1),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              (!isAvailable || isFull)
                                  ? Colors.grey.shade300
                                  : kPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: Text(
                          !isAvailable
                              ? 'Doctor Unavailable'
                              : isFull
                                  ? 'Fully Booked'
                                  : 'Book Now',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Star display (read-only) ──────────────────────────
  Widget _starDisplay(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        if (rating >= i + 1) {
          return const Icon(Icons.star, color: kAmber, size: 14);
        } else if (rating > i) {
          return const Icon(Icons.star_half, color: kAmber, size: 14);
        } else {
          return const Icon(Icons.star_border, color: kAmber, size: 14);
        }
      }),
    );
  }

  // ── Payment bottom sheet ──────────────────────────────
  void _showPaymentSheet(
      Map<String, dynamic> doctor, int slotNumber) async {
    // ── BLOCK CHECK: refuse to even open the payment sheet if this user
    // has been blocked by admin for this specific hospital ──
    final blocked = await _isUserBlockedForSelectedHospital();
    if (blocked) {
      _showBlockedDialog();
      return;
    }

    final fee = (doctor['fee'] ?? 500) as int;
    final settings = await getSettings();
    final platformCharge = settings['platformCharge'] as int;
    final bkashNumber  = settings['bkashNumber']  as String;
    final nagadNumber  = settings['nagadNumber']  as String;
    final rocketNumber = settings['rocketNumber'] as String;

    // Refresh wallet balance right before opening the sheet, and reset any
    // promo/balance state left over from a previous booking attempt.
    await loadUserBalance();
    appliedVoucher = null;
    appliedVoucherId = null;
    promoError = null;
    useBalance = false;
    promoCodeController.clear();

    final senderController      = TextEditingController();
    final transactionController = TextEditingController();
    String selectedPaymentType  = 'Online';
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

          // Cash on Delivery always still needs the platform charge paid
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
                        const Icon(Icons.phone, color: kPrimary),
                    errorText: phoneError,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: kPrimary, width: 2),
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
                        const Icon(Icons.receipt, color: kPrimary),
                    errorText: txnError,
                    helperText:
                        '10 characters · UPPERCASE + numbers (e.g. AB12CD34EF)',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: kPrimary, width: 2),
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
                                color: kPrimary),
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
                          backgroundColor: kPrimary,
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
                color: kCard,
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
                    activeColor: kPrimary,
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
                          title: 'Cash on Delivery',
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
                      color: const Color(0xFFE3F2FD),
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
                                Text(doctor['name'] ?? '',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: kText)),
                                const SizedBox(height: 2),
                                Text(
                                  DateFormat('MMM d, yyyy')
                                      .format(selectedDate!),
                                  style: const TextStyle(
                                      fontSize: 12, color: kSubtext),
                                ),
                                Text(selectedSpecialty ?? '',
                                    style: const TextStyle(
                                        fontSize: 11, color: kPrimary)),
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
                                        color: kPrimary)),
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
                        _calcRow('Appointment fee', '৳$fee'),
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
                          _calcRow('Due at chamber', '৳$dueAmount',
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
                      // COD info
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
                                'Pay platform charge now. Remaining appointment fee is due at the doctor\'s chamber.',
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
                      onPressed: () => _submitAppointment(
                        doctor,
                        slotNumber,
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
                        backgroundColor: kPrimary,
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
          color: selected ? kPrimary : kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? kPrimary : kBorder, width: 1.5),
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
                    color: selected ? Colors.white : kPrimary)),
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

  // ── Submit ────────────────────────────────────────────
  Future<void> _submitAppointment(
    Map<String, dynamic> doctor,
    int slotNumber,
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

    try {
      final firestore = FirebaseFirestore.instance;
      final userRef = firestore.collection('users').doc(user.uid);
      final appointmentRef = firestore.collection('appointments').doc();
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

      // Fetch the patient's real profile name/phone so the invoice always
      // bills the account holder — not whatever bKash/Nagad sender number
      // was used to pay (that stays saved separately as senderNumber).
      final userSnap = await userRef.get();
      final userName =
          userSnap.data()?['name'] ?? user.displayName ?? 'Patient';
      final userPhone =
          userSnap.data()?['phone'] ?? user.phoneNumber ?? '';

      final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate!);
      final receiptNumber =
          'MHC${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

      // ── Transaction: re-validate + atomically update voucher usage,
      // the user's wallet balance, and create the appointment together.
      // This prevents double-spending a limited voucher or the wallet
      // balance if the user has two booking attempts running at once. ──
      await firestore.runTransaction((transaction) async {
        Map<String, dynamic>? voucherData;
        int currentBalance = 0;

        // Re-check the hospital-specific block status fresh, inside the
        // transaction, right before writing the appointment.
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

        transaction.set(appointmentRef, {
          'userId':        user.uid,
          'userName':      userName,
          'userPhone':     userPhone,
          'doctorId':      doctor['id'],
          'doctorName':    doctor['name'],
          'hospitalId':    selectedHospitalId,
          'hospitalName':  selectedHospitalName,
          'specialty':     selectedSpecialty,
          'date':          dateStr,
          'slotNumber':    slotNumber,
          'fee':           fee,
          'platformCharge': platformCharge,
          'promoCode':     promoCode,
          'voucherId':     voucherId ?? '',
          'discountAmount': discount,
          'balanceUsed':   balanceUsed,
          'amountPaid':    amountPaid,
          'dueAmount':     dueAmount,
          'paymentType':   fullyCoveredByBalance ? 'Balance' : paymentType,
          'senderNumber':  fullyCoveredByBalance ? '' : sender,
          'transactionId': fullyCoveredByBalance ? '' : transactionId,
          'receiptNumber': receiptNumber,
          'status':        'pending',
          'ratingGiven':   false,
          'prescriptionUrl': '',
          'createdAt':     FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      Navigator.pop(context); // close bottom sheet

      // Local balance display refresh (already deducted server-side above).
      if (balanceUsed > 0) {
        setState(() => userBalance -= balanceUsed);
      }

      // ── Success popup ──────────────────────────────────
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: kGreenLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded,
                      color: kGreen, size: 44),
                ),
                const SizedBox(height: 16),
                const Text('Appointment Booked!',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  fullyCoveredByBalance
                      ? 'Fully paid from your wallet balance. Your appointment is pending admin approval.'
                      : paymentType == 'Cash'
                          ? 'Platform charge paid. Remaining ৳$dueAmount is due at the doctor\'s chamber.'
                          : 'Full payment confirmed. Your appointment is pending admin approval.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: kSubtext),
                ),
                const SizedBox(height: 6),
                Text('Receipt: #$receiptNumber',
                    style: const TextStyle(
                        fontSize: 12,
                        color: kPrimary,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 20),
                // Invoice download button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InvoiceScreen(
                              appointmentId: appointmentRef.id),
                        ),
                      );
                    },
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Download Invoice',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close',
                      style: TextStyle(color: kSubtext)),
                ),
              ],
            ),
          ),
        ),
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
// MY APPOINTMENTS LIST WIDGET
// (mirrors _MyBookingsList in the lab test screen)
// ════════════════════════════════

class _MyAppointmentsList extends StatelessWidget {
  final ScrollController scrollController;
  static const Color primary = Color(0xFF1565C0);

  const _MyAppointmentsList({required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Please login to view appointments.'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('appointments')
          .where('userId', isEqualTo: user.uid)
          // ── orderBy সরানো হয়েছে — client-side sort করা হবে, তাই
          // composite index লাগবে না ──
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
                Text('No appointments yet.',
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
            final appointmentId = docs[i].id;
            final status = (data['status'] ?? 'pending').toString();
            final doctorName = data['doctorName'] ?? '';
            final specialty = data['specialty'] ?? '';
            final hospitalName = data['hospitalName'] ?? '';
            final date = data['date'] ?? '';
            final slotNumber = data['slotNumber'];
            final fee = (data['fee'] as num? ?? 0).toInt();
            final platformCharge =
                (data['platformCharge'] as num? ?? 0).toInt();
            final total = fee + platformCharge;
            final createdAt = data['createdAt'];
            String createdStr = '';
            if (createdAt is Timestamp) {
              createdStr =
                  DateFormat('dd MMM yyyy').format(createdAt.toDate());
            }

            Color statusColor;
            String statusLabel;
            IconData statusIcon;
            switch (status.toLowerCase()) {
              case 'approved':
                statusColor = primary;
                statusLabel = 'Approved';
                statusIcon = Icons.check_circle_rounded;
                break;
              case 'completed':
                statusColor = Colors.green;
                statusLabel = 'Completed';
                statusIcon = Icons.task_alt_rounded;
                break;
              case 'rejected':
              case 'cancelled':
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
                        child: Text(doctorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                            Icon(statusIcon, size: 12, color: statusColor),
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
                  const SizedBox(height: 4),
                  Text(
                      '$specialty • $hospitalName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(
                      'Date: $date${slotNumber != null ? '  •  Slot #$slotNumber' : ''}',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey)),
                  if (createdStr.isNotEmpty)
                    Text('Booked: $createdStr',
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('৳$total',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: primary)),
                      const Spacer(),
                      if (status.toLowerCase() == 'approved' ||
                          status.toLowerCase() == 'completed')
                        ElevatedButton.icon(
                          icon: const Icon(Icons.download_rounded, size: 14),
                          label: const Text('Invoice',
                              style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            Navigator.pop(context); // close sheet
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => InvoiceScreen(
                                    appointmentId: appointmentId),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        )
                      else if (status.toLowerCase() == 'pending')
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: Colors.orange.shade200),
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