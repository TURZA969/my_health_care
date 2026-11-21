// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// ─────────────────────────────────────────────
//  CONSTANTS
// ─────────────────────────────────────────────
const Color kPrimary   = Color(0xFF0077B6);
const Color kDark      = Color(0xFF03045E);
const Color kSecondary = Color(0xFF00B4D8);
const Color kAccent    = Color(0xFF90E0EF);
const Color kGreen     = Color(0xFF2DC653);
const Color kRed       = Color(0xFFE63946);
const Color kOrange    = Color(0xFFF4A261);
const Color kPurple    = Color(0xFF7B2FBE);
const Color kTeal      = Color(0xFF0B8793);
const Color kBg        = Color(0xFFF0F4F8);

// ─────────────────────────────────────────────
//  NOTIFICATION SERVICE (disabled)
// ─────────────────────────────────────────────
class NotificationService {
  static Future<void> init() async {}
  static Future<void> show(String title, String body) async {}
}

// ─────────────────────────────────────────────
//  PDF INVOICE GENERATOR
// ─────────────────────────────────────────────
class InvoiceGenerator {
  static Future<Uint8List> generate(Map<String, dynamic> data) async {
    final pdf  = pw.Document();
    final now  = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());
    final font = await PdfGoogleFonts.nunitoRegular();
    final bold = await PdfGoogleFonts.nunitoBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#0077B6'),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('MY HEALTH CARE',
                      style: pw.TextStyle(
                          font: bold,
                          fontSize: 22,
                          color: PdfColors.white)),
                  pw.Text('Appointment Invoice',
                      style: pw.TextStyle(
                          font: font,
                          fontSize: 13,
                          // FIX: PdfColors.white70 does not exist → use PdfColors.grey200
                          color: PdfColors.grey200)),
                ],
              ),
            ),
            pw.SizedBox(height: 24),
            // Invoice meta
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Invoice Date: $now',
                    style: pw.TextStyle(
                        font: font, fontSize: 11, color: PdfColors.grey700)),
                pw.Text('Receipt: ${data['receiptNumber'] ?? 'N/A'}',
                    style: pw.TextStyle(font: bold, fontSize: 11)),
              ],
            ),
            pw.Divider(thickness: 1, color: PdfColors.grey300),
            pw.SizedBox(height: 12),
            // Details
            _pdfRow(font, bold, 'Hospital',       data['hospitalName'] ?? ''),
            _pdfRow(font, bold, 'Doctor',         data['doctorName'] ?? ''),
            _pdfRow(font, bold, 'Specialty',      data['specialty'] ?? ''),
            _pdfRow(font, bold, 'Date',           data['date'] ?? ''),
            _pdfRow(font, bold, 'Slot Number',    '#${data['slotNumber'] ?? ''}'),
            _pdfRow(font, bold, 'Transaction ID', data['transactionId'] ?? ''),
            _pdfRow(font, bold, 'Sender Number',  data['senderNumber'] ?? ''),
            _pdfRow(font, bold, 'Payment Type',   data['paymentType'] ?? ''),
            pw.SizedBox(height: 20),
            // Fee box
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#E8F4FD'),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Amount Paid',
                      style: pw.TextStyle(font: bold, fontSize: 14)),
                  pw.Text('৳${data['amountPaid'] ?? 0}',
                      style: pw.TextStyle(
                          font: bold,
                          fontSize: 18,
                          color: PdfColor.fromHex('#0077B6'))),
                ],
              ),
            ),
            pw.SizedBox(height: 24),
            // Status
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#2DC653'),
                borderRadius: pw.BorderRadius.circular(20),
              ),
              child: pw.Text('APPROVED',
                  style: pw.TextStyle(
                      font: bold, fontSize: 12, color: PdfColors.white)),
            ),
            pw.Spacer(),
            pw.Divider(color: PdfColors.grey300),
            pw.Text(
                'This is a system-generated invoice. Thank you for using My Health Care.',
                style: pw.TextStyle(
                    font: font, fontSize: 9, color: PdfColors.grey)),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  static pw.Widget _pdfRow(
      pw.Font font, pw.Font bold, String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 140,
            child: pw.Text(label,
                style: pw.TextStyle(
                    font: font, fontSize: 11, color: PdfColors.grey700)),
          ),
          pw.Text(': ', style: pw.TextStyle(font: font, fontSize: 11)),
          pw.Expanded(
            child: pw.Text(value,
                style: pw.TextStyle(font: bold, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
// ─────────────────────────────────────────────
//  ADMIN DASHBOARD SCREEN
// ─────────────────────────────────────────────
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int     _selectedIndex = 0;
  String? _hospitalId;
  String? _adminId;
  String? _adminName;
  bool    _loading = true;

  static const _navItems = [
    _NavItem(icon: Icons.dashboard_rounded,      label: 'Dashboard'),
    _NavItem(icon: Icons.calendar_today_rounded, label: 'Appointments'),
    _NavItem(icon: Icons.science_rounded,        label: 'Lab Tests'),
    _NavItem(icon: Icons.upload_file_rounded,    label: 'Reports'),
    _NavItem(icon: Icons.person_rounded,         label: 'Doctors'),
    _NavItem(icon: Icons.biotech_rounded,        label: 'Test Catalog'),
    _NavItem(icon: Icons.medication_rounded,     label: 'Medicine Order'),
    _NavItem(icon: Icons.chat_bubble_rounded,    label: 'Live Chat'),
    // CHANGED: "Settings" → "Manage Users" (page content fully replaced below)
    _NavItem(icon: Icons.people_alt_rounded,     label: 'Manage Users'),
  ];

  @override
  void initState() {
    super.initState();
    NotificationService.init();
    _loadAdmin();
  }

  Future<void> _loadAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    _adminId = user.uid;

    // প্রথমে UID দিয়ে খোঁজো
    final docById = await FirebaseFirestore.instance
        .collection('admins')
        .doc(user.uid)
        .get();

    if (docById.exists) {
      setState(() {
        _hospitalId = docById['hospitalId'];
        _adminName  = docById['name'] ?? 'Admin';
        _loading    = false;
      });
      return;
    }

    // UID না পেলে email দিয়ে খোঁজো
    final query = await FirebaseFirestore.instance
        .collection('admins')
        .where('email', isEqualTo: user.email)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      final doc = query.docs.first;
      setState(() {
        _hospitalId = doc['hospitalId'];
        _adminName  = doc['name'] ?? 'Admin';
        _loading    = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Widget _page() {
    if (_hospitalId == null) return const SizedBox();
    switch (_selectedIndex) {
      case 0:  return _DashboardHome(hospitalId: _hospitalId!, adminName: _adminName!);
      case 1:  return _AppointmentManagement(hospitalId: _hospitalId!, adminId: _adminId!);
      case 2:  return _LabTestManagement(hospitalId: _hospitalId!, adminId: _adminId!);
      case 3:  return _LabReportUpload(hospitalId: _hospitalId!);
      case 4:  return _DoctorManagement(hospitalId: _hospitalId!);
      case 5:  return const _TestCatalogManagement();
      case 6:  return _MedicineOrderManagement(hospitalId: _hospitalId!, adminId: _adminId!);
      case 7:  return _AdminChatInbox(hospitalId: _hospitalId!, adminId: _adminId!);
      // CHANGED: case 8 now shows the new user management page (needs adminId
      // too, since Report entries created there are tagged with the admin
      // who wrote them).
      case 8:  return _UserManagementPage(hospitalId: _hospitalId!, adminId: _adminId!);
      default: return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: kDark,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final isWide = MediaQuery.of(context).size.width >= 600;

    final sidebar = _Sidebar(
      selected:  _selectedIndex,
      items:     _navItems,
      adminName: _adminName ?? 'Admin',
      hospitalId: _hospitalId!,
      onTap:     (i) {
        setState(() => _selectedIndex = i);
        if (!isWide) Navigator.of(context).pop();
      },
      onLogout: () async {
        await FirebaseAuth.instance.signOut();
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      },
    );

    if (isWide) {
      // Tablet / Desktop layout
      return Scaffold(
        backgroundColor: kBg,
        body: Row(
          children: [
            sidebar,
            Expanded(
              child: Column(
                children: [
                  _TopBar(title: _navItems[_selectedIndex].label),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: KeyedSubtree(
                          key: ValueKey(_selectedIndex), child: _page()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Mobile layout — Drawer + BottomNavigationBar
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _navItems[_selectedIndex].label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                DateFormat('dd MMM').format(DateTime.now()),
                style: const TextStyle(color: kAccent, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        width: 260,
        child: sidebar,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: KeyedSubtree(
            key: ValueKey(_selectedIndex), child: _page()),
      ),
      bottomNavigationBar: _BottomNavBar(
        items: _navItems,
        selected: _selectedIndex,
        hospitalId: _hospitalId!,
        onTap: (i) => setState(() => _selectedIndex = i),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  MOBILE BOTTOM NAV — horizontally scrollable, no overflow
// ─────────────────────────────────────────────
class _BottomNavBar extends StatelessWidget {
  final List<_NavItem> items;
  final int selected;
  final String hospitalId;
  final ValueChanged<int> onTap;
  const _BottomNavBar({
    required this.items,
    required this.selected,
    required this.hospitalId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kDark,
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final sel = i == selected;
              return GestureDetector(
                onTap: () => onTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 72,
                  margin: const EdgeInsets.symmetric(
                      horizontal: 3, vertical: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel
                        ? Colors.white.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      items[i].label == 'Live Chat'
                          ? _ChatNavIcon(
                              icon: items[i].icon,
                              selected: sel,
                              hospitalId: hospitalId,
                              size: 20,
                              inactiveColor: Colors.white38,
                            )
                          : Icon(items[i].icon,
                              color: sel ? Colors.white : Colors.white38,
                              size: 20),
                      const SizedBox(height: 3),
                      Text(items[i].label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: sel ? Colors.white : Colors.white38,
                            fontSize: 9,
                            fontWeight:
                                sel ? FontWeight.bold : FontWeight.normal,
                          )),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  SIDEBAR
// ─────────────────────────────────────────────
class _Sidebar extends StatelessWidget {
  final int selected;
  final List<_NavItem> items;
  final String adminName;
  final String hospitalId;
  final ValueChanged<int> onTap;
  final VoidCallback onLogout;

  const _Sidebar({
    required this.selected,
    required this.items,
    required this.adminName,
    required this.hospitalId,
    required this.onTap,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 232,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF03045E), Color(0xFF0077B6)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              // FIX: withOpacity instead of withValues
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.local_hospital_rounded,
                color: Colors.white, size: 36),
          ),
          const SizedBox(height: 8),
          const Text('My Health Care',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const Text('Admin Panel',
              style: TextStyle(color: kAccent, fontSize: 11)),
          const SizedBox(height: 20),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                    radius: 13,
                    backgroundColor: kSecondary,
                    child:
                        Icon(Icons.person, color: Colors.white, size: 15)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(adminName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24, indent: 14, endIndent: 14),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemBuilder: (_, i) {
                final sel = i == selected;
                return GestureDetector(
                  onTap: () => onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: sel
                          ? Colors.white.withValues(alpha: 0.18)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          sel ? Border.all(color: Colors.white24) : null,
                    ),
                    child: Row(
                      children: [
                        items[i].label == 'Live Chat'
                            ? _ChatNavIcon(
                                icon: items[i].icon,
                                selected: sel,
                                hospitalId: hospitalId,
                              )
                            : Icon(items[i].icon,
                                color: sel ? Colors.white : Colors.white54,
                                size: 19),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(items[i].label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: sel
                                      ? Colors.white
                                      : Colors.white60,
                                  fontSize: 13,
                                  fontWeight: sel
                                      ? FontWeight.bold
                                      : FontWeight.normal)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(color: Colors.white24, indent: 14, endIndent: 14),
          Padding(
            padding: const EdgeInsets.all(14),
            child: GestureDetector(
              onTap: onLogout,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: kRed.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kRed.withValues(alpha: 0.5)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout_rounded, color: kRed, size: 17),
                    SizedBox(width: 7),
                    Text('Logout',
                        style: TextStyle(
                            color: kRed,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  TOP BAR
// ─────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final String title;
  const _TopBar({required this.title});

  @override
  Widget build(BuildContext context) {
    final now = DateFormat('dd MMM yyyy').format(DateTime.now());
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        // FIX: Colors.black08 does not exist → use Colors.black12
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Row(
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: kDark)),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.circle, color: kGreen, size: 9),
                const SizedBox(width: 6),
                Text('Online  •  $now',
                    style: const TextStyle(
                        fontSize: 12,
                        color: kPrimary,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
// ─────────────────────────────────────────────
//  DASHBOARD HOME
// ─────────────────────────────────────────────
class _DashboardHome extends StatelessWidget {
  final String hospitalId;
  final String adminName;
  const _DashboardHome(
      {required this.hospitalId, required this.adminName});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [kDark, kPrimary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Welcome back, $adminName! 👋',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text(
                          "Here's your hospital overview today.",
                          style: TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
                const Icon(Icons.local_hospital_rounded,
                    color: Colors.white24, size: 64),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Stat cards — professional square grid
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth >= 900
                  ? 4
                  : constraints.maxWidth >= 560
                      ? 3
                      : 2;
              return GridView.count(
                crossAxisCount: crossAxisCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 1.15,
                children: [
                  _StatCard(
                    label: 'Pending Appointments',
                    icon: Icons.pending_actions_rounded,
                    color: kOrange,
                    stream: FirebaseFirestore.instance
                        .collection('appointments')
                        .where('hospitalId', isEqualTo: hospitalId)
                        .where('status', isEqualTo: 'pending')
                        .snapshots(),
                  ),
                  _StatCard(
                    label: 'Pending Lab Tests',
                    icon: Icons.science_rounded,
                    color: kPurple,
                    stream: FirebaseFirestore.instance
                        .collection('lab_bookings')
                        .where('hospitalId', isEqualTo: hospitalId)
                        .where('status', isEqualTo: 'pending')
                        .snapshots(),
                  ),
                  _StatCard(
                    label: 'Approved Appointments',
                    icon: Icons.check_circle_rounded,
                    color: kGreen,
                    stream: FirebaseFirestore.instance
                        .collection('appointments')
                        .where('hospitalId', isEqualTo: hospitalId)
                        .where('status', isEqualTo: 'approved')
                        .snapshots(),
                  ),
                  _StatCard(
                    label: 'Reports Pending Upload',
                    icon: Icons.upload_file_rounded,
                    color: kSecondary,
                    stream: FirebaseFirestore.instance
                        .collection('lab_bookings')
                        .where('hospitalId', isEqualTo: hospitalId)
                        .where('status', isEqualTo: 'approved')
                        .snapshots(),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),
          const Text('Recent Appointments',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: kDark)),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('appointments')
                .where('hospitalId', isEqualTo: hospitalId)
                .limit(6)
                .snapshots(),
            builder: (_, snap) {
              if (!snap.hasData)
                return const LinearProgressIndicator(color: kPrimary);
              final docs = snap.data!.docs;
              if (docs.isEmpty)
                return const _Empty(msg: 'No appointments yet');
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  // FIX: Colors.black08 → Colors.black12
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 8)
                  ],
                ),
                child: Column(
                  children: docs.map((d) => _RecentTile(doc: d)).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// Professional square stat card: flat white surface, colored icon chip,
// big number, label, and a slim colored accent bar along the bottom.
class _StatCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Stream<QuerySnapshot> stream;
  const _StatCard(
      {required this.label,
      required this.icon,
      required this.color,
      required this.stream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (_, snap) {
        final count = snap.data?.docs.length ?? 0;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: color, size: 20),
                      ),
                      const Spacer(),
                      Text('$count',
                          style: TextStyle(
                              color: kDark,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              height: 1)),
                      const SizedBox(height: 4),
                      Text(label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              height: 1.25)),
                    ],
                  ),
                ),
              ),
              Container(height: 4, color: color),
            ],
          ),
        );
      },
    );
  }
}

class _RecentTile extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const _RecentTile({required this.doc});

  @override
  Widget build(BuildContext context) {
    final d      = doc.data() as Map<String, dynamic>;
    final status = d['status'] ?? 'pending';
    final color  = status == 'approved'
        ? kGreen
        : status == 'rejected'
            ? kRed
            : kOrange;
    final ts   = d['createdAt'] as Timestamp?;
    final date = ts != null
        ? DateFormat('dd MMM, hh:mm a').format(ts.toDate())
        : '';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: kPrimary.withValues(alpha: 0.1),
        child: const Icon(Icons.medical_services_rounded,
            color: kPrimary, size: 18),
      ),
      title: Text(d['doctorName'] ?? '',
          style:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      subtitle: Text('${d['specialty'] ?? ''}  •  $date',
          style: const TextStyle(fontSize: 11)),
      trailing: _Badge(status: status, color: color),
    );
  }
}

// ─────────────────────────────────────────────
//  APPOINTMENT MANAGEMENT
// ─────────────────────────────────────────────
class _AppointmentManagement extends StatefulWidget {
  final String hospitalId;
  final String adminId;
  const _AppointmentManagement(
      {required this.hospitalId, required this.adminId});

  @override
  State<_AppointmentManagement> createState() =>
      _AppointmentManagementState();
}

class _AppointmentManagementState extends State<_AppointmentManagement>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tab,
            labelColor: kPrimary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: kPrimary,
            tabs: const [
              Tab(text: 'Pending'),
              Tab(text: 'Approved'),
              Tab(text: 'Rejected'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: ['pending', 'approved', 'rejected']
                .map((s) => _ApptList(
                      hospitalId: widget.hospitalId,
                      adminId: widget.adminId,
                      status: s,
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _ApptList extends StatelessWidget {
  final String hospitalId, adminId, status;
  const _ApptList(
      {required this.hospitalId,
      required this.adminId,
      required this.status});

  Future<void> _changeStatus(BuildContext ctx, String docId,
      Map<String, dynamic> data, String newStatus) async {
    final ok = await _confirm(ctx, 'Change to "${newStatus.toUpperCase()}"?');
    if (!ok) return;

    final ref = FirebaseFirestore.instance
        .collection('appointments')
        .doc(docId);
    await ref.update({
      'status':  newStatus,
      'adminId': adminId,
      'statusHistory': FieldValue.arrayUnion([
        {
          'status':    newStatus,
          'changedAt': Timestamp.now(),
          'adminId':   adminId,
        }
      ]),
    });

    if (newStatus == 'approved') {
      try {
        final bytes = await InvoiceGenerator.generate(data);
        final dir   = await getTemporaryDirectory();
        final file  = File('${dir.path}/invoice_$docId.pdf');
        await file.writeAsBytes(bytes);
        await OpenFile.open(file.path);

        // This project doesn't use Firebase Storage — keep the invoice
        // PDF directly inside the Firestore document as base64 instead.
        if (bytes.length < 700 * 1024) {
          await ref.update({'invoiceBase64': base64Encode(bytes)});
        }

        await NotificationService.show('Appointment Approved ✅',
            'Invoice generated for ${data['doctorName'] ?? ''}');
      } catch (_) {}
    }

    if (newStatus == 'rejected') {
      await NotificationService.show('Appointment Rejected ❌',
          '${data['doctorName'] ?? ''} booking rejected');
    }

    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('Status → $newStatus'),
        backgroundColor: newStatus == 'approved'
            ? kGreen
            : newStatus == 'rejected'
                ? kRed
                : kOrange,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('appointments')
          .where('hospitalId', isEqualTo: hospitalId)
          .where('status', isEqualTo: status)
          .snapshots(),
      builder: (_, snap) {
        if (!snap.hasData) return const _Loader(color: kPrimary);
        final docs = snap.data!.docs;
        if (docs.isEmpty) return _Empty(msg: 'No $status appointments');
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data  = docs[i].data() as Map<String, dynamic>;
            final docId = docs[i].id;
            return _ApptCard(
              data:      data,
              status:    status,
              onApprove: () => _changeStatus(context, docId, data, 'approved'),
              onReject:  () => _changeStatus(context, docId, data, 'rejected'),
              onReset:   () => _changeStatus(context, docId, data, 'pending'),
            );
          },
        );
      },
    );
  }
}

class _ApptCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String status;
  final VoidCallback onApprove, onReject, onReset;

  const _ApptCard({
    required this.data,
    required this.status,
    required this.onApprove,
    required this.onReject,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = status == 'approved'
        ? kGreen
        : status == 'rejected'
            ? kRed
            : kOrange;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        // FIX: Colors.black08 → Colors.black12
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8)
        ],
        border: Border(left: BorderSide(color: borderColor, width: 4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                    backgroundColor: kPrimary.withValues(alpha: 0.1),
                    child: const Icon(Icons.person_rounded,
                        color: kPrimary)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data['doctorName'] ?? '',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                      Text(data['specialty'] ?? '',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                _Badge(status: status, color: borderColor),
              ],
            ),
            const Divider(height: 20),
            _InfoRow(Icons.calendar_today_rounded,      'Date',           data['date'] ?? ''),
            _InfoRow(Icons.confirmation_number_rounded, 'Slot',           '#${data['slotNumber'] ?? ''}'),
            _InfoRow(Icons.receipt_long_rounded,        'Transaction ID', data['transactionId'] ?? ''),
            _InfoRow(Icons.phone_android_rounded,       'Sender Number',  data['senderNumber'] ?? ''),
            _InfoRow(Icons.attach_money_rounded,        'Amount Paid',    '৳${data['amountPaid'] ?? 0}'),
            _InfoRow(Icons.payment_rounded,             'Payment Type',   data['paymentType'] ?? ''),
            const SizedBox(height: 14),
            Row(
              children: [
                if (status != 'approved') ...[
                  Expanded(
                      child: _Btn(
                          label: 'Approve',
                          color: kGreen,
                          icon: Icons.check_circle_rounded,
                          onTap: onApprove)),
                  const SizedBox(width: 8),
                ],
                if (status != 'rejected')
                  Expanded(
                      child: _Btn(
                          label: 'Reject',
                          color: kRed,
                          icon: Icons.cancel_rounded,
                          onTap: onReject)),
                if (status != 'pending') ...[
                  const SizedBox(width: 8),
                  Expanded(
                      child: _Btn(
                          label: 'Reset',
                          color: kOrange,
                          icon: Icons.refresh_rounded,
                          onTap: onReset)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  LAB TEST MANAGEMENT
// ─────────────────────────────────────────────
class _LabTestManagement extends StatefulWidget {
  final String hospitalId, adminId;
  const _LabTestManagement(
      {required this.hospitalId, required this.adminId});

  @override
  State<_LabTestManagement> createState() => _LabTestManagementState();
}

class _LabTestManagementState extends State<_LabTestManagement>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tab,
            labelColor: kPurple,
            unselectedLabelColor: Colors.grey,
            indicatorColor: kPurple,
            tabs: const [
              Tab(text: 'Pending'),
              Tab(text: 'Approved'),
              Tab(text: 'Rejected'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: ['pending', 'approved', 'rejected']
                .map((s) => _LabList(
                      hospitalId: widget.hospitalId,
                      adminId: widget.adminId,
                      status: s,
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _LabList extends StatelessWidget {
  final String hospitalId, adminId, status;
  const _LabList(
      {required this.hospitalId,
      required this.adminId,
      required this.status});

  Future<void> _changeStatus(BuildContext ctx, String docId,
      Map<String, dynamic> data, String newStatus) async {
    final ok =
        await _confirm(ctx, 'Change to "${newStatus.toUpperCase()}"?');
    if (!ok) return;

    await FirebaseFirestore.instance
        .collection('lab_bookings')
        .doc(docId)
        .update({
      'status':  newStatus,
      'adminId': adminId,
      'statusHistory': FieldValue.arrayUnion([
        {
          'status':    newStatus,
          'changedAt': Timestamp.now(),
          'adminId':   adminId,
        }
      ]),
    });

    if (newStatus == 'approved') {
      await NotificationService.show('Lab Test Approved ✅',
          '${data['testName'] ?? ''} booking approved');
    }
    if (newStatus == 'rejected') {
      await NotificationService.show('Lab Test Rejected ❌',
          '${data['testName'] ?? ''} booking rejected');
    }

    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('Status → $newStatus'),
        backgroundColor: newStatus == 'approved'
            ? kGreen
            : newStatus == 'rejected'
                ? kRed
                : kOrange,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('lab_bookings')
          .where('hospitalId', isEqualTo: hospitalId)
          .where('status', isEqualTo: status)
          .snapshots(),
      builder: (_, snap) {
        if (!snap.hasData) return const _Loader(color: kPurple);
        final docs = snap.data!.docs;
        if (docs.isEmpty) return _Empty(msg: 'No $status lab bookings');
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data  = docs[i].data() as Map<String, dynamic>;
            final docId = docs[i].id;
            return _LabCard(
              data:      data,
              status:    status,
              onApprove: () => _changeStatus(context, docId, data, 'approved'),
              onReject:  () => _changeStatus(context, docId, data, 'rejected'),
              onReset:   () => _changeStatus(context, docId, data, 'pending'),
            );
          },
        );
      },
    );
  }
}

class _LabCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String status;
  final VoidCallback onApprove, onReject, onReset;

  const _LabCard({
    required this.data,
    required this.status,
    required this.onApprove,
    required this.onReject,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final isHome      = data['homeCollection'] == true;
    final borderColor = status == 'approved'
        ? kGreen
        : status == 'rejected'
            ? kRed
            : kPurple;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
        border: Border(left: BorderSide(color: borderColor, width: 4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                    backgroundColor: kPurple.withValues(alpha: 0.1),
                    child: const Icon(Icons.science_rounded,
                        color: kPurple)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data['testName'] ?? '',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text('৳${data['totalFee'] ?? 0}',
                          style: const TextStyle(
                              color: kPurple,
                              fontWeight: FontWeight.w600,
                              fontSize: 12)),
                    ],
                  ),
                ),
                if (isHome) ...[
                  _Chip(
                      label: 'Home',
                      color: kSecondary,
                      icon: Icons.home_rounded),
                  const SizedBox(width: 6),
                ],
                _Badge(status: status, color: borderColor),
              ],
            ),
            const Divider(height: 20),
            _InfoRow(Icons.calendar_today_rounded, 'Date',           data['date'] ?? ''),
            _InfoRow(Icons.receipt_long_rounded,   'Transaction ID', data['transactionId'] ?? ''),
            _InfoRow(Icons.payment_rounded,        'Payment',        data['paymentMethod'] ?? ''),
            _InfoRow(Icons.location_on_rounded,    'Location',       data['location'] ?? ''),
            const SizedBox(height: 14),
            Row(
              children: [
                if (status != 'approved') ...[
                  Expanded(
                      child: _Btn(
                          label: 'Approve',
                          color: kGreen,
                          icon: Icons.check_circle_rounded,
                          onTap: onApprove)),
                  const SizedBox(width: 8),
                ],
                if (status != 'rejected')
                  Expanded(
                      child: _Btn(
                          label: 'Reject',
                          color: kRed,
                          icon: Icons.cancel_rounded,
                          onTap: onReject)),
                if (status != 'pending') ...[
                  const SizedBox(width: 8),
                  Expanded(
                      child: _Btn(
                          label: 'Reset',
                          color: kOrange,
                          icon: Icons.refresh_rounded,
                          onTap: onReset)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
// ─────────────────────────────────────────────
//  LAB REPORT UPLOAD  (supports image + PDF)
// ─────────────────────────────────────────────
class _LabReportUpload extends StatelessWidget {
  final String hospitalId;
  const _LabReportUpload({required this.hospitalId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('lab_bookings')
          .where('hospitalId', isEqualTo: hospitalId)
          .where('status', isEqualTo: 'approved')
          .snapshots(),
      builder: (_, snap) {
        if (!snap.hasData) return const _Loader(color: kSecondary);
        final docs = snap.data!.docs;
        if (docs.isEmpty)
          return const _Empty(msg: 'No approved bookings');
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data  = docs[i].data() as Map<String, dynamic>;
            final docId = docs[i].id;
            return _ReportCard(data: data, docId: docId);
          },
        );
      },
    );
  }
}

class _ReportCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String docId;
  const _ReportCard({required this.data, required this.docId});

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _uploading = false;

  // Max raw file size accepted before base64-encoding. Firestore caps a
  // document at ~1MB and base64 adds ~33% overhead, so we stay well under
  // that ceiling. This project doesn't use Firebase Storage — the file is
  // embedded directly inside the Firestore document instead.
  static const int _maxBytes = 700 * 1024;

  // Lets the admin choose an IMAGE or a PDF and stores it as base64
  // straight inside the lab_bookings document — no Storage bucket needed.
  // FIX: base64 data now saved to `reportUrl` field (was `reportBase64`).
  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true, // read bytes directly — works on every platform
    );
    if (result == null || result.files.single.bytes == null) return;

    final picked = result.files.single;
    final bytes  = picked.bytes!;
    final ext    = (picked.extension ?? 'jpg').toLowerCase();
    final isPdf  = ext == 'pdf';

    if (bytes.length > _maxBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'File is too large (${(bytes.length / 1024).round()} KB). '
              'Please choose a file under ${_maxBytes ~/ 1024} KB.'),
          backgroundColor: kRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

    setState(() => _uploading = true);
    try {
      final base64Str = base64Encode(bytes);
      final mimeType = isPdf
          ? 'application/pdf'
          : 'image/${ext == 'jpg' ? 'jpeg' : ext}';

      await FirebaseFirestore.instance
          .collection('lab_bookings')
          .doc(widget.docId)
          .update({
        // FIX: field renamed reportBase64 → reportUrl
        'reportUrl':        base64Str,
        'reportType':       isPdf ? 'pdf' : 'image',
        'reportMimeType':   mimeType,
        'reportFileName':   picked.name,
        'reportUploadedAt': Timestamp.now(),
      });

      await NotificationService.show('Lab Report Ready 📄',
          '${widget.data['testName'] ?? ''} report has been uploaded');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Report uploaded successfully!'),
          backgroundColor: kGreen,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: kRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _view() async {
    // FIX: read from `reportUrl` field (was `reportBase64`).
    final b64 = (widget.data['reportUrl'] ?? '').toString();
    if (b64.isEmpty) return;
    final bytes = base64Decode(b64);
    final isPdf = (widget.data['reportType'] ?? 'image') == 'pdf';

    if (isPdf) {
      try {
        final dir  = await getTemporaryDirectory();
        final file = File('${dir.path}/report_${widget.docId}.pdf');
        await file.writeAsBytes(bytes);
        await OpenFile.open(file.path);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not open report: $e'),
            backgroundColor: kRed,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.black54,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close,
                      color: Colors.white, size: 16),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // FIX: check `reportUrl` field (was `reportBase64`).
    final hasReport =
        (widget.data['reportUrl'] ?? '').toString().isNotEmpty;
    final reportType = (widget.data['reportType'] ?? 'image').toString();
    final ts       = widget.data['reportUploadedAt'] as Timestamp?;
    final uploaded = ts != null
        ? DateFormat('dd MMM, hh:mm a').format(ts.toDate())
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
        border: Border(
            left: BorderSide(
                color: hasReport ? kGreen : kSecondary, width: 4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        // FIX (overflow bug): the whole row is now wrapped so the left
        // text column can never push past the fixed-width button column
        // on the right. Previously the "Receipt: ..." Row had no width
        // constraint of its own, so a long receipt number caused a
        // ~65px RIGHT OVERFLOW. Fix = put that Row's Text inside an
        // Expanded + maxLines:1 + ellipsis, so it always shrinks to fit
        // instead of pushing the layout wider than the screen.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: kSecondary.withValues(alpha: 0.1),
              child: Icon(
                  hasReport && reportType == 'pdf'
                      ? Icons.picture_as_pdf_rounded
                      : Icons.biotech_rounded,
                  color: kSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.data['testName'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 3),
                  // FIX: Receipt number Text wrapped in Expanded so it
                  // shrinks with ellipsis instead of overflowing right.
                  Row(
                    children: [
                      const Icon(Icons.receipt_long_rounded,
                          size: 12, color: kPrimary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Receipt: ${widget.data['receiptNumber'] ?? 'N/A'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: kPrimary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(widget.data['date'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 12)),
                  if (hasReport && uploaded != null)
                    Text(
                        'Uploaded (${reportType == 'pdf' ? 'PDF' : 'Image'}): $uploaded',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: kGreen, fontSize: 11)),
                  if (!hasReport)
                    const Text('⏳ Report not uploaded yet',
                        style:
                            TextStyle(color: kOrange, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _uploading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        color: kSecondary, strokeWidth: 2))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _upload,
                        icon: Icon(
                            hasReport
                                ? Icons.refresh_rounded
                                : Icons.upload_rounded,
                            size: 15),
                        label: Text(hasReport ? 'Re-upload' : 'Upload',
                            style: const TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              hasReport ? kOrange : kSecondary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                        ),
                      ),
                      if (hasReport) ...[
                        const SizedBox(height: 6),
                        TextButton.icon(
                          onPressed: _view,
                          icon: const Icon(Icons.visibility_rounded,
                              size: 14, color: kPrimary),
                          label: const Text('View',
                              style: TextStyle(
                                  fontSize: 11, color: kPrimary)),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}
// ─────────────────────────────────────────────
//  DOCTOR MANAGEMENT
// ─────────────────────────────────────────────
class _DoctorManagement extends StatelessWidget {
  final String hospitalId;
  const _DoctorManagement({required this.hospitalId});

  void _addDoctor(BuildContext context) {
    final nameC      = TextEditingController();
    final specialtyC = TextEditingController();
    final feeC       = TextEditingController();
    final expC       = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add New Doctor',
            style: TextStyle(
                color: kPrimary, fontWeight: FontWeight.bold)),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DField(c: nameC,      label: 'Doctor Name'),
              _DField(c: specialtyC, label: 'Specialty'),
              _DField(c: feeC,       label: 'Fee (৳)',            type: TextInputType.number),
              _DField(c: expC,       label: 'Experience (years)', type: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: kPrimary),
            onPressed: () async {
              if (nameC.text.trim().isEmpty) return;
              await FirebaseFirestore.instance
                  .collection('doctors')
                  .add({
                'name':        nameC.text.trim(),
                'specialty':   specialtyC.text.trim(),
                'hospitalId':  hospitalId,
                'fee':         int.tryParse(feeC.text) ?? 0,
                'experience':  int.tryParse(expC.text) ?? 0,
                'rating':      0.0,
                'isAvailable': true,
              });
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Add',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              const Text('Doctors',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: kDark)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _addDoctor(context),
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text('Add Doctor'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('doctors')
                .where('hospitalId', isEqualTo: hospitalId)
                .snapshots(),
            builder: (_, snap) {
              if (!snap.hasData) return const _Loader(color: kPrimary);
              final docs = snap.data!.docs;
              if (docs.isEmpty)
                return const _Empty(msg: 'No doctors added yet');
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final data  = docs[i].data() as Map<String, dynamic>;
                  final docId = docs[i].id;
                  return _DoctorTile(
                      data: data, docId: docId, ctx: context);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DoctorTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final BuildContext ctx;
  // FIX: renamed parameter from 'context' to 'ctx' to avoid shadowing
  const _DoctorTile(
      {required this.data, required this.docId, required this.ctx});

  void _editFee() {
    final c = TextEditingController(text: '${data['fee'] ?? 0}');
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Update Fee',
            style: TextStyle(
                color: kPrimary, fontWeight: FontWeight.bold)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        content: _DField(
            c: c,
            label: 'Consultation Fee (৳)',
            type: TextInputType.number),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: kPrimary),
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('doctors')
                  .doc(docId)
                  .update({'fee': int.tryParse(c.text) ?? data['fee']});
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAvail = data['isAvailable'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: kPrimary.withValues(alpha: 0.1),
            child: Text(
              (data['name'] ?? 'D')[0].toUpperCase(),
              style: const TextStyle(
                  color: kPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['name'] ?? '',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                Text(data['specialty'] ?? '',
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 12)),
                Text(
                    '৳${data['fee'] ?? 0}  •  ${data['experience'] ?? 0} yrs exp',
                    style: const TextStyle(
                        color: kPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Column(
            children: [
              Switch(
                value: isAvail,
                activeColor: kGreen,
                onChanged: (v) => FirebaseFirestore.instance
                    .collection('doctors')
                    .doc(docId)
                    .update({'isAvailable': v}),
              ),
              Text(isAvail ? 'Available' : 'Unavailable',
                  style: TextStyle(
                      fontSize: 9,
                      color: isAvail ? kGreen : kRed,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          IconButton(
            icon:
                const Icon(Icons.edit_rounded, color: kPrimary, size: 20),
            onPressed: _editFee,
          ),
          IconButton(
            icon: const Icon(Icons.delete_rounded, color: kRed, size: 20),
            onPressed: () async {
              final ok = await _confirm(
                  context, 'Remove Dr. ${data['name'] ?? ''}?');
              if (ok) {
                await FirebaseFirestore.instance
                    .collection('doctors')
                    .doc(docId)
                    .delete();
              }
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  TEST CATALOG MANAGEMENT
// ─────────────────────────────────────────────
class _TestCatalogManagement extends StatelessWidget {
  const _TestCatalogManagement();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('lab_tests_catalog')
          .snapshots(),
      builder: (_, snap) {
        if (!snap.hasData) return const _Loader(color: kPurple);
        final docs = snap.data!.docs;
        if (docs.isEmpty)
          return const _Empty(msg: 'No tests in catalog');
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data  = docs[i].data() as Map<String, dynamic>;
            final docId = docs[i].id;
            return _CatalogTile(
                data: data, docId: docId, ctx: context);
          },
        );
      },
    );
  }
}

class _CatalogTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final BuildContext ctx;
  const _CatalogTile(
      {required this.data, required this.docId, required this.ctx});

  void _editFee() {
    final c = TextEditingController(text: '${data['fee'] ?? 0}');
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Update Test Fee',
            style: TextStyle(
                color: kPurple, fontWeight: FontWeight.bold)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        content:
            _DField(c: c, label: 'Fee (৳)', type: TextInputType.number),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: kPurple),
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('lab_tests_catalog')
                  .doc(docId)
                  .update({'fee': int.tryParse(c.text) ?? data['fee']});
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAvail      = data['isAvailable'] == true;
    final homeEligible = data['homeEligible'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: kPurple.withValues(alpha: 0.1),
            child: const Icon(Icons.biotech_rounded, color: kPurple),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['name'] ?? '',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                Row(
                  children: [
                    Text('৳${data['fee'] ?? 0}',
                        style: const TextStyle(
                            color: kPurple,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    if (homeEligible) ...[
                      const SizedBox(width: 8),
                      _Chip(
                          label: 'Home',
                          color: kSecondary,
                          icon: Icons.home_rounded),
                    ],
                  ],
                ),
                if ((data['description'] ?? '').toString().isNotEmpty)
                  Text(data['description'],
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
          Column(
            children: [
              Switch(
                value: isAvail,
                activeColor: kGreen,
                onChanged: (v) => FirebaseFirestore.instance
                    .collection('lab_tests_catalog')
                    .doc(docId)
                    .update({'isAvailable': v}),
              ),
              Text(isAvail ? 'Available' : 'Off',
                  style: TextStyle(
                      fontSize: 9,
                      color: isAvail ? kGreen : kRed,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: kPurple, size: 20),
            onPressed: _editFee,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  MEDICINE ORDER MANAGEMENT  (new)
// ─────────────────────────────────────────────
class _MedicineOrderManagement extends StatefulWidget {
  final String hospitalId, adminId;
  const _MedicineOrderManagement(
      {required this.hospitalId, required this.adminId});

  @override
  State<_MedicineOrderManagement> createState() =>
      _MedicineOrderManagementState();
}

class _MedicineOrderManagementState extends State<_MedicineOrderManagement>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tab,
            labelColor: kTeal,
            unselectedLabelColor: Colors.grey,
            indicatorColor: kTeal,
            tabs: const [
              Tab(text: 'Pending'),
              Tab(text: 'Approved'),
              Tab(text: 'Rejected'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: ['pending', 'approved', 'rejected']
                .map((s) => _MedicineOrderList(
                      hospitalId: widget.hospitalId,
                      adminId: widget.adminId,
                      status: s,
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _MedicineOrderList extends StatelessWidget {
  final String hospitalId, adminId, status;
  const _MedicineOrderList(
      {required this.hospitalId,
      required this.adminId,
      required this.status});

  Future<void> _changeStatus(BuildContext ctx, String docId,
      Map<String, dynamic> data, String newStatus) async {
    final ok =
        await _confirm(ctx, 'Change to "${newStatus.toUpperCase()}"?');
    if (!ok) return;

    await FirebaseFirestore.instance
        .collection('medicine_orders')
        .doc(docId)
        .update({
      'status':  newStatus,
      'adminId': adminId,
      'statusHistory': FieldValue.arrayUnion([
        {
          'status':    newStatus,
          'changedAt': Timestamp.now(),
          'adminId':   adminId,
        }
      ]),
    });

    if (newStatus == 'approved') {
      await NotificationService.show('Medicine Order Approved ✅',
          'Order for ${data['patientName'] ?? ''} approved');
    }
    if (newStatus == 'rejected') {
      await NotificationService.show('Medicine Order Rejected ❌',
          'Order for ${data['patientName'] ?? ''} rejected');
    }

    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('Status → $newStatus'),
        backgroundColor: newStatus == 'approved'
            ? kGreen
            : newStatus == 'rejected'
                ? kRed
                : kOrange,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('medicine_orders')
          .where('hospitalId', isEqualTo: hospitalId)
          .where('status', isEqualTo: status)
          .snapshots(),
      builder: (_, snap) {
        if (!snap.hasData) return const _Loader(color: kTeal);
        final docs = snap.data!.docs;
        if (docs.isEmpty)
          return _Empty(msg: 'No $status medicine orders');
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data  = docs[i].data() as Map<String, dynamic>;
            final docId = docs[i].id;
            return _MedicineOrderCard(
              data:      data,
              status:    status,
              onApprove: () => _changeStatus(context, docId, data, 'approved'),
              onReject:  () => _changeStatus(context, docId, data, 'rejected'),
              onReset:   () => _changeStatus(context, docId, data, 'pending'),
            );
          },
        );
      },
    );
  }
}

class _MedicineOrderCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String status;
  final VoidCallback onApprove, onReject, onReset;

  const _MedicineOrderCard({
    required this.data,
    required this.status,
    required this.onApprove,
    required this.onReject,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = status == 'approved'
        ? kGreen
        : status == 'rejected'
            ? kRed
            : kTeal;
    final isDelivery = data['deliveryType'] == 'home';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
        border: Border(left: BorderSide(color: borderColor, width: 4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                    backgroundColor: kTeal.withValues(alpha: 0.1),
                    child: const Icon(Icons.medication_rounded,
                        color: kTeal)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data['patientName'] ?? 'Patient',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text('৳${data['totalAmount'] ?? 0}',
                          style: const TextStyle(
                              color: kTeal,
                              fontWeight: FontWeight.w600,
                              fontSize: 12)),
                    ],
                  ),
                ),
                if (isDelivery) ...[
                  _Chip(
                      label: 'Delivery',
                      color: kSecondary,
                      icon: Icons.local_shipping_rounded),
                  const SizedBox(width: 6),
                ],
                _Badge(status: status, color: borderColor),
              ],
            ),
            const Divider(height: 20),
            _InfoRow(Icons.medication_liquid_rounded, 'Medicines',
                data['medicineList'] ?? data['items'] ?? ''),
            _InfoRow(Icons.calendar_today_rounded, 'Date', data['date'] ?? ''),
            _InfoRow(Icons.receipt_long_rounded, 'Transaction ID',
                data['transactionId'] ?? ''),
            _InfoRow(Icons.phone_android_rounded, 'Phone',
                data['phone'] ?? ''),
            _InfoRow(Icons.location_on_rounded, 'Address',
                data['address'] ?? ''),
            const SizedBox(height: 14),
            Row(
              children: [
                if (status != 'approved') ...[
                  Expanded(
                      child: _Btn(
                          label: 'Approve',
                          color: kGreen,
                          icon: Icons.check_circle_rounded,
                          onTap: onApprove)),
                  const SizedBox(width: 8),
                ],
                if (status != 'rejected')
                  Expanded(
                      child: _Btn(
                          label: 'Reject',
                          color: kRed,
                          icon: Icons.cancel_rounded,
                          onTap: onReject)),
                if (status != 'pending') ...[
                  const SizedBox(width: 8),
                  Expanded(
                      child: _Btn(
                          label: 'Reset',
                          color: kOrange,
                          icon: Icons.refresh_rounded,
                          onTap: onReset)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
// ─────────────────────────────────────────────
//  LIVE CHAT — ADMIN SIDE
// ─────────────────────────────────────────────

// Small helper: renders a nav icon with a live "unread" dot/count badge,
// driven by hospitals/{hospitalId}/chats where unreadByAdmin > 0.
class _ChatNavIcon extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final String hospitalId;
  final double size;
  final Color inactiveColor;
  const _ChatNavIcon({
    required this.icon,
    required this.selected,
    required this.hospitalId,
    this.size = 19,
    this.inactiveColor = Colors.white54,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('hospitals')
          .doc(hospitalId)
          .collection('chats')
          .where('unreadByAdmin', isGreaterThan: 0)
          .snapshots(),
      builder: (_, snap) {
        final count = snap.data?.docs.length ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon,
                color: selected ? Colors.white : inactiveColor, size: size),
            if (count > 0)
              Positioned(
                right: -6,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  constraints:
                      const BoxConstraints(minWidth: 16, minHeight: 16),
                  decoration: BoxDecoration(
                    color: kRed,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: kDark, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                        height: 1.2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// Admin inbox — lists every active conversation for this hospital.
class _AdminChatInbox extends StatelessWidget {
  final String hospitalId;
  final String adminId;
  const _AdminChatInbox({required this.hospitalId, required this.adminId});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [kDark, kPrimary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.chat_bubble_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Live Chat',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    SizedBox(height: 2),
                    Text('Chat in real time with your patients',
                        style:
                            TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: kGreen, size: 8),
                    SizedBox(width: 5),
                    Text('Online',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('hospitals')
                .doc(hospitalId)
                .collection('chats')
                .orderBy('lastMessageAt', descending: true)
                .snapshots(),
            builder: (_, snap) {
              if (!snap.hasData) return const _Loader(color: kPrimary);
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const _Empty(msg: 'No conversations yet');
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final data  = docs[i].data() as Map<String, dynamic>;
                  final docId = docs[i].id;
                  return _ChatInboxTile(
                    data: data,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _AdminChatThread(
                          hospitalId: hospitalId,
                          adminId: adminId,
                          userId: docId,
                          userName: data['userName'] ?? 'Patient',
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChatInboxTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  const _ChatInboxTile({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = (data['unreadByAdmin'] ?? 0) as num;
    final ts     = data['lastMessageAt'] as Timestamp?;
    final time   = ts != null
        ? DateFormat('hh:mm a').format(ts.toDate())
        : '';
    final name = (data['userName'] ?? 'Patient').toString();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
          border: unread > 0
              ? Border.all(color: kPrimary.withValues(alpha: 0.35))
              : null,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: kPrimary.withValues(alpha: 0.1),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'P',
                style: const TextStyle(
                    color: kPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 17),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              unread > 0 ? FontWeight.bold : FontWeight.w600,
                          color: kDark)),
                  const SizedBox(height: 3),
                  Text(
                    (data['lastMessage'] ?? 'Say hello 👋').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: unread > 0 ? kDark : Colors.grey,
                        fontWeight:
                            unread > 0 ? FontWeight.w600 : FontWeight.normal),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(time,
                    style: TextStyle(
                        fontSize: 10.5,
                        color: unread > 0 ? kPrimary : Colors.grey)),
                const SizedBox(height: 6),
                if (unread > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: kPrimary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      unread > 9 ? '9+' : '${unread.toInt()}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Admin chat thread — mirror of the patient-side chat UI with roles reversed.
class _AdminChatThread extends StatefulWidget {
  final String hospitalId;
  final String adminId;
  final String userId;
  final String userName;
  const _AdminChatThread({
    required this.hospitalId,
    required this.adminId,
    required this.userId,
    required this.userName,
  });

  @override
  State<_AdminChatThread> createState() => _AdminChatThreadState();
}

class _AdminChatThreadState extends State<_AdminChatThread> {
  final _controller = TextEditingController();
  final _scroll      = ScrollController();
  bool _sending = false;

  DocumentReference get _chatRef => FirebaseFirestore.instance
      .collection('hospitals')
      .doc(widget.hospitalId)
      .collection('chats')
      .doc(widget.userId);

  @override
  void initState() {
    super.initState();
    // Reset the admin-side unread counter for this thread on open.
    _chatRef.set({'unreadByAdmin': 0}, SetOptions(merge: true));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _controller.clear();

    try {
      await _chatRef.collection('messages').add({
        'text':      text,
        'senderId':  widget.adminId,
        'isAdmin':   true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _chatRef.set({
        'lastMessage':   text,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unreadByUser':  FieldValue.increment(1),
        'unreadByAdmin': 0,
      }, SetOptions(merge: true));

      if (_scroll.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scroll.animateTo(0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut);
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kDark,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: kSecondary,
              child: Text(
                widget.userName.isNotEmpty
                    ? widget.userName[0].toUpperCase()
                    : 'P',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.userName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                  const Row(
                    children: [
                      Icon(Icons.circle, color: kGreen, size: 8),
                      SizedBox(width: 5),
                      Text('Patient',
                          style:
                              TextStyle(fontSize: 11, color: kAccent)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _chatRef
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (_, snap) {
                if (!snap.hasData) return const _Loader(color: kPrimary);
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const _Empty(msg: 'No messages yet — say hello 👋');
                }
                return ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final isAdmin = data['isAdmin'] == true;
                    final ts = data['createdAt'] as Timestamp?;

                    final showDateSeparator = _needsDateSeparator(docs, i);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showDateSeparator)
                          _DateSeparator(date: ts?.toDate()),
                        _ChatBubble(
                          text: data['text'] ?? '',
                          time: ts != null
                              ? DateFormat('hh:mm a').format(ts.toDate())
                              : '',
                          // Admin's own messages align right here.
                          alignRight: isAdmin,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          _ChatInputBar(
            controller: _controller,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  bool _needsDateSeparator(List<QueryDocumentSnapshot> docs, int i) {
    // docs is reverse-chronological (newest first); a separator belongs
    // above the *last* message of each calendar day as the list scrolls up.
    if (i == docs.length - 1) return true;
    final cur  = (docs[i].data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
    final next = (docs[i + 1].data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
    if (cur == null || next == null) return false;
    final a = cur.toDate();
    final b = next.toDate();
    return a.year != b.year || a.month != b.month || a.day != b.day;
  }
}

class _DateSeparator extends StatelessWidget {
  final DateTime? date;
  const _DateSeparator({required this.date});

  String _label(DateTime d) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that  = DateTime(d.year, d.month, d.day);
    final diff  = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('dd MMM yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    if (date == null) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
          ),
          child: Text(_label(date!),
              style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final String text;
  final String time;
  final bool alignRight;
  const _ChatBubble(
      {required this.text, required this.time, required this.alignRight});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          gradient: alignRight
              ? const LinearGradient(colors: [kPrimary, kSecondary])
              : null,
          color: alignRight ? null : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(alignRight ? 16 : 4),
            bottomRight: Radius.circular(alignRight ? 4 : 16),
          ),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text,
                style: TextStyle(
                    color: alignRight ? Colors.white : kDark,
                    fontSize: 13.5,
                    height: 1.3)),
            const SizedBox(height: 3),
            Text(time,
                style: TextStyle(
                    fontSize: 9.5,
                    color: alignRight
                        ? Colors.white70
                        : Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }
}

class _ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  const _ChatInputBar(
      {required this.controller,
      required this.sending,
      required this.onSend});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: kBg,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Type a reply…',
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: sending ? null : onSend,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [kPrimary, kSecondary]),
                  shape: BoxShape.circle,
                ),
                child: sending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// ─────────────────────────────────────────────
//  USER MANAGEMENT  (replaces the old Settings page)
// ─────────────────────────────────────────────
//
// NOTE ON DATA MODEL (please double-check against your real schema):
//  • All registered patients are assumed to live in a top-level
//    `users` collection, one doc per uid, with at least a `name` field.
//  • "Blocked for this hospital" is stored as its own doc at
//    `hospitals/{hospitalId}/blockedUsers/{uid}` — NOT a field on the
//    user doc itself. This keeps the block scoped to a single hospital,
//    exactly as requested (block করলে শুধু ওই hospital-এই বুক করতে পারবে না,
//    অন্য hospital-এ পারবে)।
//  • "Activity" = number of appointments + lab test bookings this user
//    made at this specific hospital, assuming both `appointments` and
//    `lab_bookings` documents store the patient's uid in a `userId`
//    field. If your field is named differently (e.g. `patientId`),
//    just rename it in `_UserActivityStats` below.
//
//  NEW — Report / Status:
//  • "Report" writes a short (<=100 word) note about a user to
//    `hospitals/{hospitalId}/userReports/{autoId}` with fields:
//        uid, userName, reportText, adminId, createdAt
//    This collection/fields did NOT exist before — Firestore creates
//    them automatically the first time an admin submits a report, no
//    manual setup needed.
//  • "Status" reads every doc in that collection where uid == this
//    user's uid and lists them (newest first). If there are none, a
//    friendly "User is Excellent 🌟 / No Reports Found" popup is shown
//    instead of an empty list.
//
// IMPORTANT — this page only records the block; it does NOT by itself
// stop a blocked user from booking. On the PATIENT side (wherever the
// appointment / lab-test booking button lives) you must add a check like:
//
//   final blocked = await FirebaseFirestore.instance
//       .collection('hospitals').doc(hospitalId)
//       .collection('blockedUsers').doc(myUid).get();
//   if (blocked.exists) {
//     // show "You are blocked from booking at this hospital" and stop
//   }
//
class _UserManagementPage extends StatefulWidget {
  final String hospitalId;
  final String adminId;
  const _UserManagementPage(
      {required this.hospitalId, required this.adminId});

  @override
  State<_UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<_UserManagementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _search.addListener(() {
      setState(() => _query = _search.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 6)
              ],
            ),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Search user by name…',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                prefixIcon: Icon(Icons.search_rounded,
                    color: kPrimary, size: 20),
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
            ),
          ),
        ),
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tab,
            labelColor: kPrimary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: kPrimary,
            tabs: const [
              Tab(text: 'Active Users'),
              Tab(text: 'Blocked Users'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _ActiveUsersList(
                  hospitalId: widget.hospitalId,
                  adminId: widget.adminId,
                  query: _query),
              _BlockedUsersList(
                  hospitalId: widget.hospitalId,
                  adminId: widget.adminId,
                  query: _query),
            ],
          ),
        ),
      ],
    );
  }
}

// ── ACTIVE USERS ────────────────────────────────────────────────
// Shows everyone in `users` who does NOT have a doc in this hospital's
// `blockedUsers` subcollection.
class _ActiveUsersList extends StatelessWidget {
  final String hospitalId;
  final String adminId;
  final String query;
  const _ActiveUsersList(
      {required this.hospitalId, required this.adminId, required this.query});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('hospitals')
          .doc(hospitalId)
          .collection('blockedUsers')
          .snapshots(),
      builder: (_, blockedSnap) {
        if (!blockedSnap.hasData) return const _Loader(color: kPrimary);
        final blockedIds =
            blockedSnap.data!.docs.map((d) => d.id).toSet();

        return StreamBuilder<QuerySnapshot>(
          stream:
              FirebaseFirestore.instance.collection('users').snapshots(),
          builder: (_, usersSnap) {
            if (!usersSnap.hasData) return const _Loader(color: kPrimary);

            var docs = usersSnap.data!.docs
                .where((d) => !blockedIds.contains(d.id))
                .toList();

            if (query.isNotEmpty) {
              docs = docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                final name = (data['name'] ?? data['fullName'] ?? '')
                    .toString()
                    .toLowerCase();
                return name.contains(query);
              }).toList();
            }

            if (docs.isEmpty) {
              return const _Empty(msg: 'No active users found');
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              itemBuilder: (_, i) {
                final data = docs[i].data() as Map<String, dynamic>;
                final uid  = docs[i].id;
                return _UserTile(
                  uid: uid,
                  data: data,
                  hospitalId: hospitalId,
                  adminId: adminId,
                  isBlocked: false,
                );
              },
            );
          },
        );
      },
    );
  }
}

// ── BLOCKED USERS ───────────────────────────────────────────────
class _BlockedUsersList extends StatelessWidget {
  final String hospitalId;
  final String adminId;
  final String query;
  const _BlockedUsersList(
      {required this.hospitalId, required this.adminId, required this.query});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('hospitals')
          .doc(hospitalId)
          .collection('blockedUsers')
          .orderBy('blockedAt', descending: true)
          .snapshots(),
      builder: (_, snap) {
        if (!snap.hasData) return const _Loader(color: kRed);
        var docs = snap.data!.docs;

        if (query.isNotEmpty) {
          docs = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final name = (data['name'] ?? '').toString().toLowerCase();
            return name.contains(query);
          }).toList();
        }

        if (docs.isEmpty) {
          return const _Empty(msg: 'No blocked users');
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final uid  = docs[i].id;
            return _UserTile(
              uid: uid,
              data: data,
              hospitalId: hospitalId,
              adminId: adminId,
              isBlocked: true,
            );
          },
        );
      },
    );
  }
}

// ── SHARED USER TILE ────────────────────────────────────────────
class _UserTile extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> data;
  final String hospitalId;
  final String adminId;
  final bool isBlocked;
  const _UserTile({
    required this.uid,
    required this.data,
    required this.hospitalId,
    required this.adminId,
    required this.isBlocked,
  });

  Future<void> _block(BuildContext context, String name) async {
    final ok = await _confirm(context,
        'Block "$name"? They will no longer be able to book an appointment or lab test at this hospital.');
    if (!ok) return;
    await FirebaseFirestore.instance
        .collection('hospitals')
        .doc(hospitalId)
        .collection('blockedUsers')
        .doc(uid)
        .set({
      'name':      name,
      'blockedAt': Timestamp.now(),
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$name has been blocked'),
        backgroundColor: kRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _unblock(BuildContext context, String name) async {
    final ok = await _confirm(context, 'Unblock "$name"?');
    if (!ok) return;
    await FirebaseFirestore.instance
        .collection('hospitals')
        .doc(hospitalId)
        .collection('blockedUsers')
        .doc(uid)
        .delete();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$name has been unblocked'),
        backgroundColor: kGreen,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // NEW — write a short (<=100 word) report about this user. The
  // `hospitals/{hospitalId}/userReports` collection and all its fields
  // are created automatically by Firestore on first write; nothing to
  // set up manually.
  Future<void> _addReport(BuildContext context, String name) async {
    final controller = TextEditingController();
    final formKey    = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        int wordCount = 0;
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              title: Text('Report: $name',
                  style: const TextStyle(
                      color: kOrange, fontWeight: FontWeight.bold)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: controller,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (v) {
                          final words = v.trim().isEmpty
                              ? 0
                              : v.trim().split(RegExp(r'\s+')).length;
                          setDialogState(() => wordCount = words);
                        },
                        decoration: InputDecoration(
                          hintText:
                              'Write a short report about this user (max 100 words)…',
                          hintStyle: const TextStyle(fontSize: 12.5),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text('$wordCount / 100 words',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color:
                                    wordCount > 100 ? kRed : Colors.grey)),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: const Text('Cancel')),
                ElevatedButton(
                  style:
                      ElevatedButton.styleFrom(backgroundColor: kOrange),
                  onPressed: () async {
                    final text = controller.text.trim();
                    if (text.isEmpty) return;
                    final words = text.split(RegExp(r'\s+')).length;
                    if (words > 100) {
                      ScaffoldMessenger.of(dialogCtx).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Report must be within 100 words'),
                          backgroundColor: kRed,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      return;
                    }
                    await FirebaseFirestore.instance
                        .collection('hospitals')
                        .doc(hospitalId)
                        .collection('userReports')
                        .add({
                      'uid':        uid,
                      'userName':   name,
                      'reportText': text,
                      'adminId':    adminId,
                      'createdAt':  Timestamp.now(),
                    });
                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Report submitted for $name'),
                        backgroundColor: kGreen,
                        behavior: SnackBarBehavior.floating,
                      ));
                    }
                  },
                  child: const Text('Submit',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // NEW — shows every report filed against this user at this hospital.
  // If there are none, shows a friendly "User is Excellent" popup
  // instead of an empty list.
  void _viewStatus(BuildContext context, String name) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
              maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.fact_check_rounded, color: kPrimary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Status: $name',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                    IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const Divider(),
                Flexible(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('hospitals')
                        .doc(hospitalId)
                        .collection('userReports')
                        .where('uid', isEqualTo: uid)
                        .snapshots(),
                    builder: (_, snap) {
                      if (!snap.hasData) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 30),
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: kPrimary)),
                        );
                      }

                      // Sort client-side (newest first) so no extra
                      // composite Firestore index is required.
                      final docs = snap.data!.docs.toList()
                        ..sort((a, b) {
                          final ta = (a.data()
                              as Map<String, dynamic>)['createdAt'] as Timestamp?;
                          final tb = (b.data()
                              as Map<String, dynamic>)['createdAt'] as Timestamp?;
                          if (ta == null || tb == null) return 0;
                          return tb.compareTo(ta);
                        });

                      if (docs.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 26),
                          child: Column(
                            children: [
                              const Icon(Icons.verified_rounded,
                                  color: kGreen, size: 54),
                              const SizedBox(height: 10),
                              const Text('No Reports Found',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: kDark)),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: kGreen.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text('User is Excellent 🌟',
                                    style: TextStyle(
                                        color: kGreen,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12)),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final d =
                              docs[i].data() as Map<String, dynamic>;
                          final ts = d['createdAt'] as Timestamp?;
                          final date = ts != null
                              ? DateFormat('dd MMM yyyy, hh:mm a')
                                  .format(ts.toDate())
                              : '';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: kBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: kOrange.withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(d['reportText'] ?? '',
                                    style: const TextStyle(
                                        fontSize: 12.5, height: 1.35)),
                                const SizedBox(height: 6),
                                Text(date,
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.grey)),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name  = (data['name'] ?? data['fullName'] ?? 'Unknown').toString();
    final email = (data['email'] ?? '').toString();
    final phone = (data['phone'] ?? data['phoneNumber'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
        border: Border(
            left: BorderSide(
                color: isBlocked ? kRed : kGreen, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor:
                    (isBlocked ? kRed : kPrimary).withValues(alpha: 0.1),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                      color: isBlocked ? kRed : kPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    if (email.isNotEmpty || phone.isNotEmpty)
                      Text(
                        [email, phone].where((s) => s.isNotEmpty).join('  •  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 11.5),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // FIX / NEW: Block/Unblock, Report, and Status buttons now sit
          // together in one equal-width row (instead of a single trailing
          // button squeezed into the header) so all three fit cleanly on
          // narrow mobile widths too.
          Row(
            children: [
              Expanded(
                child: isBlocked
                    ? _Btn(
                        label: 'Unblock',
                        color: kGreen,
                        icon: Icons.lock_open_rounded,
                        onTap: () => _unblock(context, name),
                      )
                    : _Btn(
                        label: 'Block',
                        color: kRed,
                        icon: Icons.block_rounded,
                        onTap: () => _block(context, name),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Btn(
                  label: 'Report',
                  color: kOrange,
                  icon: Icons.report_rounded,
                  onTap: () => _addReport(context, name),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Btn(
                  label: 'Status',
                  color: kPrimary,
                  icon: Icons.fact_check_rounded,
                  onTap: () => _viewStatus(context, name),
                ),
              ),
            ],
          ),
          const Divider(height: 22),
          // Activity for THIS hospital only.
          _UserActivityStats(hospitalId: hospitalId, uid: uid),
        ],
      ),
    );
  }
}

// ── ACTIVITY (appointment + lab-test counts at this hospital) ─────
class _UserActivityStats extends StatelessWidget {
  final String hospitalId;
  final String uid;
  const _UserActivityStats(
      {required this.hospitalId, required this.uid});

  Future<_ActivitySummary> _load() async {
    // NOTE: assumes both collections store the patient's uid in `userId`.
    final apptQ = FirebaseFirestore.instance
        .collection('appointments')
        .where('hospitalId', isEqualTo: hospitalId)
        .where('userId', isEqualTo: uid);
    final labQ = FirebaseFirestore.instance
        .collection('lab_bookings')
        .where('hospitalId', isEqualTo: hospitalId)
        .where('userId', isEqualTo: uid);

    final results = await Future.wait([
      apptQ.count().get(),
      labQ.count().get(),
      apptQ.orderBy('createdAt', descending: true).limit(1).get(),
    ]);

    final apptCount = (results[0] as AggregateQuerySnapshot).count ?? 0;
    final labCount  = (results[1] as AggregateQuerySnapshot).count ?? 0;
    final lastDocs  = (results[2] as QuerySnapshot).docs;
    DateTime? lastActivity;
    if (lastDocs.isNotEmpty) {
      final ts =
          (lastDocs.first.data() as Map<String, dynamic>)['createdAt']
              as Timestamp?;
      lastActivity = ts?.toDate();
    }

    return _ActivitySummary(
        appointments: apptCount, labTests: labCount, lastActive: lastActivity);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ActivitySummary>(
      future: _load(),
      builder: (_, snap) {
        if (!snap.hasData) {
          return const SizedBox(
              height: 18,
              child: LinearProgressIndicator(color: kAccent));
        }
        final s = snap.data!;
        return Row(
          children: [
            _StatPill(
                icon: Icons.calendar_today_rounded,
                label: '${s.appointments} Appointments',
                color: kOrange),
            const SizedBox(width: 8),
            _StatPill(
                icon: Icons.science_rounded,
                label: '${s.labTests} Lab Tests',
                color: kPurple),
            const Spacer(),
            if (s.lastActive != null)
              Text(
                'Last: ${DateFormat('dd MMM yyyy').format(s.lastActive!)}',
                style: const TextStyle(fontSize: 10.5, color: Colors.grey),
              ),
          ],
        );
      },
    );
  }
}

class _ActivitySummary {
  final int appointments, labTests;
  final DateTime? lastActive;
  _ActivitySummary(
      {required this.appointments,
      required this.labTests,
      required this.lastActive});
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatPill(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 10.5,
                    color: color,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
// ─────────────────────────────────────────────
//  SHARED MICRO-WIDGETS
// ─────────────────────────────────────────────
class _NavItem {
  final IconData icon;
  final String label;
  // FIX: removed positional constructor → named only to fix "missing required id" error
  const _NavItem({required this.icon, required this.label});
}

class _Badge extends StatelessWidget {
  final String status;
  final Color color;
  const _Badge({required this.status, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20)),
        child: Text(status.toUpperCase(),
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _Chip(
      {required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 11),
            const SizedBox(width: 3),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );
}

class _Btn extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  const _Btn(
      {required this.label,
      required this.color,
      required this.icon,
      required this.onTap});

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 15),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
}

// FIX: renamed _Row → _InfoRow to avoid conflict with Flutter's Row widget
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(icon, size: 13, color: Colors.grey),
            const SizedBox(width: 6),
            Text('$label: ',
                style:
                    const TextStyle(color: Colors.grey, fontSize: 12)),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
}

class _Empty extends StatelessWidget {
  final String msg;
  const _Empty({required this.msg});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(msg,
                style: TextStyle(
                    color: Colors.grey.shade400, fontSize: 14)),
          ],
        ),
      );
}

class _Loader extends StatelessWidget {
  final Color color;
  const _Loader({required this.color});

  @override
  Widget build(BuildContext context) =>
      Center(child: CircularProgressIndicator(color: color));
}

class _DField extends StatelessWidget {
  final TextEditingController c;
  final String label;
  final TextInputType type;
  const _DField(
      {required this.c,
      required this.label,
      this.type = TextInputType.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
          controller: c,
          keyboardType: type,
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 12),
          ),
        ),
      );
}

// ─────────────────────────────────────────────
//  CONFIRM DIALOG HELPER
// ─────────────────────────────────────────────
Future<bool> _confirm(BuildContext context, String message) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Confirm',
              style: TextStyle(
                  color: kPrimary, fontWeight: FontWeight.bold)),
          content: Text(message),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: kPrimary),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ) ??
      false;
}