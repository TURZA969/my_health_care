import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'invoice_helper.dart';

class OrderMedicineScreen extends StatefulWidget {
  const OrderMedicineScreen({super.key});

  @override
  State<OrderMedicineScreen> createState() => _OrderMedicineScreenState();
}

class _OrderMedicineScreenState extends State<OrderMedicineScreen> {
  int _currentTab = 0;
  final TextEditingController _searchController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> _cartItems = [];
  List<Map<String, dynamic>> _detectedMedicines = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _isScanning = false;
  bool _isSearching = false;

  // ── Medicine list from Firestore ──
  List<Map<String, dynamic>> _allMedicines = [];
  bool _medicinesLoaded = false;

  // ── Service charges from Firestore settings ──
  int _homeServiceCharge = 0;
  int _platformCharge = 0;

  // API key সরানো হয়েছে। অ্যাপ চালাতে নিচে নিজের নতুন কী বসান, কিন্তু সেই অবস্থায় GitHub-এ পুশ করবেন না।
  final String _apiKey = 'YOUR_GROQ_API_KEY';

  // Vision model used for prescription scanning.
  final String _visionModel = 'meta-llama/llama-4-scout-17b-16e-instruct';

  int get medicineTotal =>
      _cartItems.fold(0, (sum, item) => sum + (item['price'] as int) * (item['qty'] as int));

  int get totalPrice => medicineTotal + _homeServiceCharge + _platformCharge;

  @override
  void initState() {
    super.initState();
    _loadMedicinesFromDB();
    _loadServiceCharges();
  }

  // ─────────────────────────────────────────
  // Load service charges from settings
  // ─────────────────────────────────────────
  Future<void> _loadServiceCharges() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('app_settings')
          .get();
      if (doc.exists) {
        setState(() {
          _homeServiceCharge = (doc.data()?['homeServiceCharge'] ?? 0) as int;
          _platformCharge = (doc.data()?['platformCharge'] ?? 0) as int;
        });
      }
    } catch (e) {
      debugPrint('Settings load error: $e');
    }
  }

  // ─────────────────────────────────────────
  // Load medicines from Firestore
  // ─────────────────────────────────────────
  Future<void> _loadMedicinesFromDB() async {
    final snapshot = await FirebaseFirestore.instance.collection('medicines').get();
    setState(() {
      _allMedicines = snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      _medicinesLoaded = true;
    });
  }

  // ─────────────────────────────────────────
  // Prescription scan (Groq API)
  // ─────────────────────────────────────────
  Future<void> _scanPrescription(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source, imageQuality: 80);
    if (image == null) return;

    setState(() => _isScanning = true);

    try {
      final bytes = await File(image.path).readAsBytes();
      final base64Image = base64Encode(bytes);

      final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');

      final body = jsonEncode({
        "model": _visionModel,
        "messages": [
          {
            "role": "system",
            "content":
                "You are a medical prescription analyzer. Extract medicine names accurately from prescription images."
          },
          {
            "role": "user",
            "content": [
              {
                "type": "text",
                "text":
                    """Analyze this medical prescription image and extract ALL medicine names with their dosage and quantity.
Return ONLY a JSON array in this exact format, nothing else, no markdown, no explanation:
[{"name": "Medicine Name", "dosage": "500mg", "frequency": "2x daily", "quantity": "10 tabs", "price": 50}]
If you cannot read the prescription clearly, return an empty array: []"""
              },
              {
                "type": "image_url",
                "image_url": {
                  "url": "data:image/jpeg;base64,$base64Image"
                }
              }
            ]
          }
        ],
        "temperature": 0.3,
        "max_tokens": 1024
      });

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['choices'] == null || data['choices'].isEmpty) {
          throw Exception('No response from AI');
        }

        final text = data['choices'][0]['message']['content'] as String;
        String cleanText =
            text.replaceAll('```json', '').replaceAll('```', '').trim();
        final startIndex = cleanText.indexOf('[');
        final endIndex = cleanText.lastIndexOf(']');

        if (startIndex == -1 || endIndex == -1) {
          setState(() {
            _detectedMedicines = [];
            _isScanning = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Could not detect medicines. Try a clearer image.'),
                  backgroundColor: Colors.orange),
            );
          }
          return;
        }

        cleanText = cleanText.substring(startIndex, endIndex + 1);
        final List<dynamic> medicines = jsonDecode(cleanText);

        setState(() {
          _detectedMedicines = medicines
              .map((m) => {
                    'name': m['name'] ?? '',
                    'dosage': m['dosage'] ?? '',
                    'frequency': m['frequency'] ?? '',
                    'quantity': m['quantity'] ?? '',
                    'price': m['price'] ?? 50,
                    'added': false,
                  })
              .toList();
          _isScanning = false;
        });
      } else {
        debugPrint('API Error: ${response.statusCode} - ${response.body}');
        setState(() => _isScanning = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('API Error: ${response.statusCode}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Scan error: $e');
      setState(() => _isScanning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────
  // Search from local loaded list
  // ─────────────────────────────────────────
  void _searchMedicine(String query) {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    final q = query.toLowerCase();
    setState(() {
      _searchResults = _allMedicines
          .where((m) =>
              (m['name'] ?? '').toString().toLowerCase().contains(q) ||
              (m['generic_name'] ?? '').toString().toLowerCase().contains(q))
          .take(10)
          .toList();

      // fallback যদি কিছু না পাওয়া যায়
      if (_searchResults.isEmpty) {
        _searchResults = [
          {'name': query, 'generic_name': 'Generic Medicine', 'price': 50, 'unit': 'pcs'},
        ];
      }
    });
  }

  // ─────────────────────────────────────────
  // Cart
  // ─────────────────────────────────────────
  void _addToCart(Map<String, dynamic> medicine) {
    final existing = _cartItems.indexWhere((item) => item['name'] == medicine['name']);
    if (existing >= 0) {
      setState(() => _cartItems[existing]['qty']++);
    } else {
      setState(() => _cartItems.add({
            'name': medicine['name'],
            'price': medicine['price'] ?? 50,
            'qty': 1,
            'dosage': medicine['dosage'] ?? '',
          }));
    }
  }

  void _addAllToCart() {
    for (final medicine in _detectedMedicines) {
      _addToCart(medicine);
      medicine['added'] = true;
    }
    setState(() {});
  }

  // ─────────────────────────────────────────
  // Checkout + place order
  // ─────────────────────────────────────────
  Future<void> _checkout(String paymentMethod, String selectedOnlineMethod,
      String senderNumber, String transactionId, String deliveryAddress) async {
    if (_cartItems.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;

    final orderData = {
      'userId': user!.uid,
      'items': _cartItems,
      'medicineTotal': medicineTotal,
      'homeServiceCharge': _homeServiceCharge,
      'platformCharge': _platformCharge,
      'totalAmount': totalPrice,
      'paymentMethod': paymentMethod == 'COD' ? 'COD' : selectedOnlineMethod,
      'senderNumber': senderNumber,
      'transactionId': transactionId,
      'deliveryAddress': deliveryAddress,
      'status': paymentMethod == 'COD' ? 'approved' : 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    };

    final docRef =
        await FirebaseFirestore.instance.collection('medicine_orders').add(orderData);

    if (mounted) {
      Navigator.pop(context);

      // ── Invoice print ──
      await InvoiceHelper.printInvoice(
        orderId: docRef.id,
        items: _cartItems,
        medicineTotal: medicineTotal,
        homeServiceCharge: _homeServiceCharge,
        platformCharge: _platformCharge,
        totalAmount: totalPrice,
        paymentMethod: paymentMethod == 'COD' ? 'Cash on Delivery' : selectedOnlineMethod,
        deliveryAddress: deliveryAddress,
        customerName: user.displayName ?? 'Customer',
      );

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Order Placed!'),
            ],
          ),
          content: Text(paymentMethod == 'COD'
              ? 'Your order has been placed. Medicine will be delivered to your door!'
              : 'Your order is pending payment verification.'),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE17055), foregroundColor: Colors.white),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      setState(() => _cartItems = []);
    }
  }

  // ─────────────────────────────────────────
  // Checkout Bottom Sheet
  // ─────────────────────────────────────────
  void _showCheckoutSheet() {
    final senderController = TextEditingController();
    final transactionController = TextEditingController();
    final addressController = TextEditingController();
    String selectedPayment = 'COD';
    String selectedOnlineMethod = 'bKash'; // default
    bool isLoadingLocation = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
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
                // ── Handle bar ──
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Checkout',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),

                // ── Order summary ──
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFDF0EC),
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      ..._cartItems.map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${item['name']} x${item['qty']}',
                                    style: const TextStyle(fontSize: 13)),
                                Text(
                                    '৳${(item['price'] as int) * (item['qty'] as int)}',
                                    style: const TextStyle(
                                        fontSize: 13, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          )),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Medicine total',
                              style: TextStyle(fontSize: 13, color: Colors.grey)),
                          Text('৳$medicineTotal',
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Home service charge',
                              style: TextStyle(fontSize: 13, color: Colors.grey)),
                          Text('৳$_homeServiceCharge',
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Platform charge',
                              style: TextStyle(fontSize: 13, color: Colors.grey)),
                          Text('৳$_platformCharge',
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Grand total',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('৳$totalPrice',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFE17055))),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Delivery Address ──
                const Text('Delivery Address',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: addressController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Enter your delivery address...',
                    prefixIcon: const Icon(Icons.location_on, color: Color(0xFFE17055)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFFE17055), width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isLoadingLocation
                        ? null
                        : () async {
                            setModalState(() => isLoadingLocation = true);
                            try {
                              LocationPermission permission =
                                  await Geolocator.requestPermission();
                              if (permission == LocationPermission.denied ||
                                  permission ==
                                      LocationPermission.deniedForever) {
                                setModalState(() => isLoadingLocation = false);
                                return;
                              }
                              final position =
                                  await Geolocator.getCurrentPosition();
                              final placemarks = await placemarkFromCoordinates(
                                  position.latitude, position.longitude);
                              if (placemarks.isNotEmpty) {
                                final p = placemarks.first;
                                addressController.text =
                                    '${p.street}, ${p.subLocality}, ${p.locality}, ${p.administrativeArea}';
                              }
                            } catch (e) {
                              debugPrint('Location error: $e');
                            }
                            setModalState(() => isLoadingLocation = false);
                          },
                    icon: isLoadingLocation
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFFE17055)))
                        : const Icon(Icons.my_location, color: Color(0xFFE17055)),
                    label: Text(
                        isLoadingLocation
                            ? 'Getting location...'
                            : 'Use Current Location',
                        style: const TextStyle(color: Color(0xFFE17055))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE17055)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Payment Method ──
                const Text('Payment Method',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setModalState(() => selectedPayment = 'COD'),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: selectedPayment == 'COD'
                                ? const Color(0xFFE17055)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: const Color(0xFFE17055)),
                          ),
                          child: Column(
                            children: [
                              const Text('🚚', style: TextStyle(fontSize: 20)),
                              const SizedBox(height: 4),
                              Text('Cash on Delivery',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: selectedPayment == 'COD'
                                          ? Colors.white
                                          : const Color(0xFFE17055))),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setModalState(() => selectedPayment = 'Online'),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: selectedPayment == 'Online'
                                ? const Color(0xFFE17055)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: const Color(0xFFE17055)),
                          ),
                          child: Column(
                            children: [
                              const Text('📱', style: TextStyle(fontSize: 20)),
                              const SizedBox(height: 4),
                              Text('Online Payment',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: selectedPayment == 'Online'
                                          ? Colors.white
                                          : const Color(0xFFE17055))),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Online payment details ──
                if (selectedPayment == 'Online') ...[
                  const SizedBox(height: 16),

                  // bKash / Nagad / Rocket tabs
                  Row(
                    children: [
                      _onlineMethodTab('bKash', Colors.pink, selectedOnlineMethod,
                          (val) => setModalState(() => selectedOnlineMethod = val)),
                      const SizedBox(width: 8),
                      _onlineMethodTab('Nagad', Colors.orange, selectedOnlineMethod,
                          (val) => setModalState(() => selectedOnlineMethod = val)),
                      const SizedBox(width: 8),
                      _onlineMethodTab('Rocket', Colors.purple, selectedOnlineMethod,
                          (val) => setModalState(() => selectedOnlineMethod = val)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Dynamic placeholder
                  TextField(
                    controller: senderController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Your $selectedOnlineMethod Number',
                      hintText: 'Enter your $selectedOnlineMethod number',
                      prefixIcon:
                          const Icon(Icons.phone, color: Color(0xFFE17055)),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Color(0xFFE17055), width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Transaction ID — overflow fixed
                  TextField(
                    controller: transactionController,
                    decoration: InputDecoration(
                      labelText: 'Transaction ID',
                      hintText: 'Enter transaction ID',
                      prefixIcon:
                          const Icon(Icons.receipt, color: Color(0xFFE17055)),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Color(0xFFE17055), width: 2),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // ── Submit button (overflow fixed) ──
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      if (addressController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content:
                                  Text('Please enter a delivery address'),
                              backgroundColor: Colors.orange),
                        );
                        return;
                      }
                      Navigator.pop(context);
                      _checkout(
                        selectedPayment,
                        selectedOnlineMethod,
                        senderController.text,
                        transactionController.text,
                        addressController.text,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE17055),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      selectedPayment == 'COD'
                          ? 'Place Order (Cash on Delivery)'
                          : 'Submit $selectedOnlineMethod Payment',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Online method selector tab
  Widget _onlineMethodTab(String name, Color color, String selected,
      Function(String) onSelect) {
    final isSelected = selected == name;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelect(name),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: isSelected ? color : color.withValues(alpha: 0.3)),
          ),
          child: Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : color),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE17055),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Order Medicine',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          if (_cartItems.isNotEmpty)
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.shopping_cart),
                  onPressed: _showCheckoutSheet,
                ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                    child: Center(
                      child: Text('${_cartItems.length}',
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFE17055))),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Tab bar ──
          Container(
            color: const Color(0xFFE17055),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _currentTab = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _currentTab == 0
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('📋 Prescription',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _currentTab == 0
                                  ? const Color(0xFFE17055)
                                  : Colors.white)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _currentTab = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _currentTab == 1
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('🔍 Manual Search',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _currentTab == 1
                                  ? const Color(0xFFE17055)
                                  : Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _currentTab == 0
                  ? _buildPrescriptionTab()
                  : _buildManualTab(),
            ),
          ),

          if (_cartItems.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFE17055), Color(0xFFFDCB6E)]),
                boxShadow: [
                  BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, -3))
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_cartItems.length} items • Home Delivery',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white70)),
                      Text('৳$totalPrice',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: _showCheckoutSheet,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFFE17055),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Checkout →',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPrescriptionTab() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xFFE17055),
                width: 2,
                style: BorderStyle.solid),
          ),
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                    color: const Color(0xFFFDF0EC),
                    borderRadius: BorderRadius.circular(16)),
                child:
                    const Center(child: Text('📋', style: TextStyle(fontSize: 30))),
              ),
              const SizedBox(height: 12),
              const Text('Upload Prescription',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('AI will auto-detect medicines',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 14),
              if (_isScanning)
                const Column(
                  children: [
                    CircularProgressIndicator(color: Color(0xFFE17055)),
                    SizedBox(height: 10),
                    Text('Analyzing prescription...',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _scanPrescription(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt, size: 16),
                      label: const Text('Camera'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE17055),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () => _scanPrescription(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library,
                          size: 16, color: Color(0xFFE17055)),
                      label: const Text('Gallery',
                          style: TextStyle(color: Color(0xFFE17055))),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFE17055)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_detectedMedicines.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: const Color(0xFFE8FAF5),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Text('✅', style: TextStyle(fontSize: 14)),
                    ),
                    const SizedBox(width: 8),
                    const Text('Detected Medicines',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: const Color(0xFFE8FAF5),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text('${_detectedMedicines.length} found',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF00B894),
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ..._detectedMedicines.map((med) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                                color: const Color(0xFFFDF0EC),
                                borderRadius: BorderRadius.circular(12)),
                            child: const Center(
                                child: Text('💊',
                                    style: TextStyle(fontSize: 20))),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(med['name'],
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                Text(
                                    '${med['frequency']} • ${med['quantity']}',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: med['added']
                                ? null
                                : () {
                                    _addToCart(med);
                                    setState(() => med['added'] = true);
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: med['added']
                                  ? const Color(0xFFE8FAF5)
                                  : const Color(0xFFE17055),
                              foregroundColor: med['added']
                                  ? const Color(0xFF00B894)
                                  : Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              minimumSize: Size.zero,
                            ),
                            child: Text(med['added'] ? '✓ Added' : '+ Add',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    )),
                ElevatedButton(
                  onPressed: _addAllToCart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE17055),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Add All to Cart 🛒',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (_cartItems.isNotEmpty) _buildCartWidget(),
      ],
    );
  }

  Widget _buildManualTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE17055), width: 1.5),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: Color(0xFFE17055)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search medicine by name...',
                    hintStyle: TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                  ),
                  onChanged: _searchMedicine,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (!_medicinesLoaded)
          const Center(
              child: CircularProgressIndicator(color: Color(0xFFE17055)))
        else if (_searchResults.isNotEmpty) ...[
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Search Results',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E))),
          ),
          const SizedBox(height: 10),
          ..._searchResults.map((med) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                          color: const Color(0xFFFDF0EC),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Center(
                          child: Text('💊', style: TextStyle(fontSize: 22))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(med['name'] ?? '',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold)),
                          Text(med['generic_name'] ?? 'Generic Medicine',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey)),
                          Text('৳${med['price'] ?? 50}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFE17055))),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => _addToCart(med),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE17055),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('+ Add',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              )),
        ],

        if (_cartItems.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildCartWidget(),
        ],
      ],
    );
  }

  Widget _buildCartWidget() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('🛒 Cart (${_cartItems.length} items)',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold)),
              GestureDetector(
                onTap: () => setState(() => _cartItems = []),
                child: const Text('Clear all',
                    style:
                        TextStyle(fontSize: 12, color: Color(0xFFE17055))),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._cartItems.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    const Text('💊', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['name'],
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          Text('৳${item['price']}',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (item['qty'] > 1) {
                              setState(() => item['qty']--);
                            } else {
                              setState(() => _cartItems.remove(item));
                            }
                          },
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                                color: const Color(0xFFFDF0EC),
                                borderRadius: BorderRadius.circular(6)),
                            child: const Center(
                              child: Text('−',
                                  style: TextStyle(
                                      color: Color(0xFFE17055),
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text('${item['qty']}',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold)),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => item['qty']++),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                                color: const Color(0xFFE17055),
                                borderRadius: BorderRadius.circular(6)),
                            child: const Center(
                              child: Text('+',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Medicine total',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              Text('৳$medicineTotal',
                  style: const TextStyle(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Service charge',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              Text('৳${_homeServiceCharge + _platformCharge}',
                  style: const TextStyle(fontSize: 13)),
            ],
          ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Grand total', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('৳$totalPrice',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE17055))),
            ],
          ),
        ],
      ),
    );
  }
}