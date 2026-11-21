import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class InvoiceScreen extends StatefulWidget {
  final String appointmentId;
  const InvoiceScreen({super.key, required this.appointmentId});

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  Map<String, dynamic>? appointmentData;
  Map<String, dynamic>? doctorData;
  bool isLoading = true;

  static const Color kPrimary = Color(0xFF1565C0);
  static const Color kPrimaryLight = Color(0xFFE3F2FD);
  static const Color kGreen = Color(0xFF2E7D32);
  static const Color kGreenLight = Color(0xFFE8F5E9);
  static const Color kRed = Color(0xFFC62828);
  static const Color kRedLight = Color(0xFFFFEBEE);
  static const Color kAmber = Color(0xFFF57F17);
  static const Color kAmberLight = Color(0xFFFFF8E1);
  static const Color kBg = Color(0xFFF0F4F8);
  static const Color kText = Color(0xFF1A1A2E);
  static const Color kSubtext = Color(0xFF6B7280);
  static const Color kBorder = Color(0xFFE5E7EB);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final apptDoc = await FirebaseFirestore.instance
          .collection('appointments')
          .doc(widget.appointmentId)
          .get();

      if (!apptDoc.exists) return;
      final appt = apptDoc.data()!;

      final doctorDoc = await FirebaseFirestore.instance
          .collection('doctors')
          .doc(appt['doctorId'])
          .get();

      setState(() {
        appointmentData = appt;
        doctorData = doctorDoc.data();
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  // Raw paymentType string as stored on the appointment doc — can be
  // 'Online', 'Cash', or 'Balance' (fully covered by wallet balance).
  String get paymentTypeRaw =>
      (appointmentData?['paymentType'] ?? '').toString();

  String get paymentMethodLabel {
    final t = paymentTypeRaw.toLowerCase();
    if (t == 'balance') return 'Wallet balance';
    if (t == 'cash') return 'Cash on delivery';
    return 'Online payment';
  }

  // Kept for the "payment confirmed" style badge — Balance-covered
  // bookings read as confirmed same as Online.
  bool get isOnline => paymentTypeRaw.toLowerCase() != 'cash';

  int get consultationFee => (appointmentData?['fee'] ?? 0) as int;
  int get platformCharge => (appointmentData?['platformCharge'] ?? 20) as int;

  // ── Promo / discount / wallet-balance fields ──
  // These are 0 / empty for older appointments booked before this feature
  // existed, so every read below falls back safely.
  int get discountAmount =>
      ((appointmentData?['discountAmount'] ?? 0) as num).toInt();
  int get balanceUsed =>
      ((appointmentData?['balanceUsed'] ?? 0) as num).toInt();
  String get promoCode => (appointmentData?['promoCode'] ?? '').toString();

  // Fee after promo discount is applied — this is the number that feeds
  // every other total below.
  int get feeAfterDiscount => consultationFee - discountAmount;
  int get totalAmount => feeAfterDiscount + platformCharge;

  // amountPaid / dueAmount are read from the stored appointment fields
  // (computed correctly at booking time, including any wallet balance
  // applied). Falls back to the old on-the-fly formula for appointments
  // created before this feature existed and never got these fields.
  int get amountPaid =>
      ((appointmentData?['amountPaid'] ??
              (isOnline ? totalAmount : platformCharge)) as num)
          .toInt();
  int get dueAmount =>
      ((appointmentData?['dueAmount'] ??
              (isOnline ? 0 : feeAfterDiscount)) as num)
          .toInt();

  bool get hasDue => dueAmount > 0;

  String get receiptNumber =>
      appointmentData?['receiptNumber'] ?? 'MHC000000';
  String get patientName =>
      appointmentData?['userName'] ?? 'Patient';
  // Bill the account holder's real profile phone number, not the
  // bKash/Nagad/Rocket sender number used just to make the payment.
  String get patientPhone =>
      appointmentData?['userPhone'] ??
      appointmentData?['senderNumber'] ??
      '';
  String get doctorName =>
      appointmentData?['doctorName'] ?? '';
  String get doctorDegree =>
      doctorData?['degree'] ?? '';
  String get hospitalName =>
      appointmentData?['hospitalName'] ?? '';
  String get specialty =>
      appointmentData?['specialty'] ?? '';
  String get transactionId =>
      appointmentData?['transactionId'] ?? '';
  String get appointmentDate =>
      appointmentData?['date'] ?? '';
  int? get slotNumber => appointmentData?['slotNumber'] as int?;
  String get status =>
      appointmentData?['status'] ?? 'pending';

  // Gate: invoice can be downloaded once the appointment is approved
  // OR completed. Adjust the strings below if your admin panel writes
  // different status values.
  bool get isApproved =>
      status.toLowerCase() == 'approved' ||
      status.toLowerCase() == 'completed';

  String get formattedDate {
    try {
      final d = DateTime.parse(appointmentDate);
      return DateFormat('dd MMM yyyy').format(d);
    } catch (_) {
      return appointmentDate;
    }
  }

  String get formattedCreatedAt {
    try {
      final ts = appointmentData?['createdAt'] as Timestamp?;
      if (ts == null) return '';
      return DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate());
    } catch (_) {
      return '';
    }
  }

  Future<void> _downloadPdf() async {
    if (!isApproved) return;
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#1565C0'),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('My_Health_Care',
                            style: pw.TextStyle(
                                fontSize: 22,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.white)),
                        pw.SizedBox(height: 3),
                        pw.Text('Healthcare Management Platform',
                            style: const pw.TextStyle(
                                fontSize: 10, color: PdfColors.white)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('INVOICE',
                            style: pw.TextStyle(
                                fontSize: 11,
                                letterSpacing: 2,
                                color: PdfColor.fromHex('#90CAF9'))),
                        pw.SizedBox(height: 4),
                        pw.Text('#$receiptNumber',
                            style: pw.TextStyle(
                                fontSize: 16,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.white)),
                        pw.SizedBox(height: 2),
                        pw.Text('Issue: $formattedCreatedAt',
                            style: const pw.TextStyle(
                                fontSize: 9, color: PdfColors.white)),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 16),

              // Status badge
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: !hasDue
                      ? PdfColor.fromHex('#E8F5E9')
                      : PdfColor.fromHex('#FFF8E1'),
                  borderRadius: pw.BorderRadius.circular(20),
                  border: pw.Border.all(color: PdfColor.fromHex('#E5E7EB'), width: 0.5),
                ),
                child: pw.Text(
                  !hasDue ? 'Payment confirmed' : 'Platform charge paid · Fee due',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: !hasDue
                        ? PdfColor.fromHex('#2E7D32')
                        : PdfColor.fromHex('#F57F17'),
                  ),
                ),
              ),

              pw.SizedBox(height: 16),

              // Bill to + Appointment
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(14),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#F8FAFC'),
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(color: PdfColor.fromHex('#E5E7EB'), width: 0.5),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('BILL TO',
                              style: pw.TextStyle(
                                  fontSize: 9,
                                  letterSpacing: 1.2,
                                  color: PdfColor.fromHex('#9CA3AF'))),
                          pw.SizedBox(height: 6),
                          pw.Text(patientName,
                              style: pw.TextStyle(
                                  fontSize: 13,
                                  fontWeight: pw.FontWeight.bold)),
                          if (patientPhone.isNotEmpty) ...[
                            pw.SizedBox(height: 3),
                            pw.Text(patientPhone,
                                style: const pw.TextStyle(fontSize: 11)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(14),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#F8FAFC'),
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(color: PdfColor.fromHex('#E5E7EB'), width: 0.5),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('APPOINTMENT',
                              style: pw.TextStyle(
                                  fontSize: 9,
                                  letterSpacing: 1.2,
                                  color: PdfColor.fromHex('#9CA3AF'))),
                          pw.SizedBox(height: 6),
                          pw.Text(formattedDate,
                              style: pw.TextStyle(
                                  fontSize: 13,
                                  fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 3),
                          pw.Text('Specialty: $specialty',
                              style: const pw.TextStyle(fontSize: 11)),
                          if (slotNumber != null) ...[
                            pw.SizedBox(height: 2),
                            pw.Text('Slot: #$slotNumber',
                                style: pw.TextStyle(
                                    fontSize: 11,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColor.fromHex('#1565C0'))),
                          ],
                          pw.SizedBox(height: 2),
                          pw.Text('Status: $status',
                              style: pw.TextStyle(
                                  fontSize: 11,
                                  color: PdfColor.fromHex('#2E7D32'))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 16),

              // Doctor
              pw.Container(
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#F8FAFC'),
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColor.fromHex('#E5E7EB'), width: 0.5),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('CONSULTING DOCTOR',
                        style: pw.TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.2,
                            color: PdfColor.fromHex('#9CA3AF'))),
                    pw.SizedBox(height: 8),
                    pw.Text(doctorName,
                        style: pw.TextStyle(
                            fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    if (doctorDegree.isNotEmpty) ...[
                      pw.SizedBox(height: 3),
                      pw.Text(doctorDegree,
                          style: pw.TextStyle(
                              fontSize: 11,
                              color: PdfColor.fromHex('#4B5563'))),
                    ],
                    pw.SizedBox(height: 2),
                    pw.Text(hospitalName,
                        style: pw.TextStyle(
                            fontSize: 11,
                            color: PdfColor.fromHex('#9CA3AF'))),
                  ],
                ),
              ),

              pw.SizedBox(height: 16),

              // Charges table — fee, promo discount, platform charge,
              // total, wallet balance used, amount paid, and any due.
              pw.Container(
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#F8FAFC'),
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColor.fromHex('#E5E7EB'), width: 0.5),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('CHARGES',
                        style: pw.TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.2,
                            color: PdfColor.fromHex('#9CA3AF'))),
                    pw.SizedBox(height: 10),
                    _pdfRow('Consultation fee', 'BDT $consultationFee'),
                    if (discountAmount > 0) ...[
                      pw.Divider(color: PdfColor.fromHex('#E5E7EB')),
                      _pdfRow(
                        promoCode.isNotEmpty
                            ? 'Promo discount ($promoCode)'
                            : 'Promo discount',
                        '- BDT $discountAmount',
                        color: PdfColor.fromHex('#2E7D32'),
                      ),
                    ],
                    pw.Divider(color: PdfColor.fromHex('#E5E7EB')),
                    _pdfRow('Platform charge', 'BDT $platformCharge'),
                    pw.Divider(
                        color: PdfColor.fromHex('#1565C0'), thickness: 0.8),
                    _pdfRow('Total', 'BDT $totalAmount', bold: true),
                    if (balanceUsed > 0) ...[
                      pw.SizedBox(height: 6),
                      _pdfRow('Wallet balance used', '- BDT $balanceUsed',
                          color: PdfColor.fromHex('#2E7D32')),
                    ],
                    pw.SizedBox(height: 6),
                    _pdfRow(
                      hasDue ? '✓  Amount paid' : '✓  Amount paid',
                      'BDT $amountPaid',
                      color: PdfColor.fromHex('#2E7D32'),
                    ),
                    if (hasDue) ...[
                      pw.SizedBox(height: 4),
                      _pdfRow('⚠  Due at doctor\'s chamber',
                          'BDT $dueAmount',
                          color: PdfColor.fromHex('#C62828')),
                    ],
                  ],
                ),
              ),

              pw.SizedBox(height: 14),

              // Summary box
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#1565C0'),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(!hasDue ? 'Total paid' : 'Now paid',
                            style: pw.TextStyle(
                                fontSize: 11, color: PdfColor(1,1,1,0.7))),
                        if (hasDue)
                          pw.Text('BDT $dueAmount due at chamber',
                              style: pw.TextStyle(
                                  fontSize: 10, color: PdfColor(1,1,1,0.7))),
                      ],
                    ),
                    pw.Text('BDT $amountPaid',
                        style: pw.TextStyle(
                            fontSize: 22,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white)),
                  ],
                ),
              ),

              pw.SizedBox(height: 14),

              // Payment method
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Payment method',
                          style: const pw.TextStyle(
                              fontSize: 10, color: PdfColors.grey)),
                      pw.Text(paymentMethodLabel,
                          style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold)),
                      if (transactionId.isNotEmpty)
                        pw.Text('TXN: $transactionId',
                            style: const pw.TextStyle(
                                fontSize: 10, color: PdfColors.grey)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Receipt no.',
                          style: const pw.TextStyle(
                              fontSize: 10, color: PdfColors.grey)),
                      pw.Text('#$receiptNumber',
                          style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ],
              ),

              pw.Spacer(),

              // Footer
              pw.Divider(color: PdfColor.fromHex('#E5E7EB')),
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.Text(
                  'Generated by My_Health_Care · This is a system-generated invoice',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey),
                ),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Invoice_$receiptNumber.pdf',
    );
  }

  pw.Widget _pdfRow(String label, String value,
      {bool bold = false, PdfColor? color}) {
    final style = bold
        ? pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            color: color ?? PdfColor.fromHex('#1A1A2E'))
        : pw.TextStyle(
            fontSize: 12, color: color ?? PdfColor.fromHex('#4B5563'));
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(value, style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: kBg,
        body: Center(
          child: CircularProgressIndicator(color: kPrimary),
        ),
      );
    }

    if (appointmentData == null) {
      return Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          title: const Text('Invoice'),
        ),
        body: const Center(child: Text('Invoice not found')),
      );
    }

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Invoice',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          TextButton.icon(
            onPressed: isApproved ? _downloadPdf : null,
            icon: Icon(Icons.download_rounded,
                color: isApproved ? Colors.white : Colors.white38, size: 18),
            label: Text('PDF',
                style: TextStyle(
                    color: isApproved ? Colors.white : Colors.white38,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Main invoice card
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: kPrimary.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Blue header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: kPrimary,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('My_Health_Care',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.3)),
                            const SizedBox(height: 3),
                            Text('Healthcare Management Platform',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withValues(alpha: 0.75))),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('INVOICE',
                                style: TextStyle(
                                    fontSize: 10,
                                    letterSpacing: 2,
                                    color: Colors.white.withValues(alpha: 0.7))),
                            const SizedBox(height: 4),
                            Text('#$receiptNumber',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                            const SizedBox(height: 2),
                            Text(formattedCreatedAt,
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white.withValues(alpha: 0.7))),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Status bar
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: !hasDue ? kGreenLight : kAmberLight,
                      border: Border(
                          bottom: BorderSide(color: kBorder)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: !hasDue ? kGreen : kAmber,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          !hasDue
                              ? 'Payment confirmed'
                              : 'Platform charge paid · Fee due at chamber',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: !hasDue ? kGreen : kAmber),
                        ),
                      ],
                    ),
                  ),

                  // Bill to + Appointment
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(child: _infoBox(
                          label: 'BILL TO',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(patientName,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: kText)),
                              if (patientPhone.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(patientPhone,
                                    style: const TextStyle(
                                        fontSize: 12, color: kSubtext)),
                              ],
                            ],
                          ),
                        )),
                        const SizedBox(width: 10),
                        Expanded(child: _infoBox(
                          label: 'APPOINTMENT',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(formattedDate,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: kText)),
                              const SizedBox(height: 3),
                              Text(specialty,
                                  style: const TextStyle(
                                      fontSize: 12, color: kSubtext)),
                              if (slotNumber != null) ...[
                                const SizedBox(height: 3),
                                Text('Slot #$slotNumber',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: kPrimary,
                                        fontWeight: FontWeight.w600)),
                              ],
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: kGreenLight,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  status.toUpperCase(),
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: kGreen),
                                ),
                              ),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),

                  _divider(),

                  // Doctor section
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('CONSULTING DOCTOR'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              width: 48, height: 48,
                              decoration: BoxDecoration(
                                color: kPrimaryLight,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Center(
                                child: Text('👨‍⚕️', style: TextStyle(fontSize: 22)),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(doctorName,
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: kText)),
                                  if (doctorDegree.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(doctorDegree,
                                        style: const TextStyle(
                                            fontSize: 12, color: kSubtext)),
                                  ],
                                  const SizedBox(height: 2),
                                  Text(hospitalName,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF9CA3AF))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  _divider(),

                  // Charges — fee, promo discount, platform charge, total,
                  // wallet balance used, amount paid, and any chamber due.
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('CHARGES'),
                        const SizedBox(height: 12),
                        _chargeRow('Consultation fee', '৳ $consultationFee'),
                        if (discountAmount > 0) ...[
                          const SizedBox(height: 8),
                          _chargeRow(
                            promoCode.isNotEmpty
                                ? 'Promo discount ($promoCode)'
                                : 'Promo discount',
                            '- ৳ $discountAmount',
                            color: kGreen,
                          ),
                        ],
                        const SizedBox(height: 8),
                        _chargeRow('Platform charge', '৳ $platformCharge'),
                        const SizedBox(height: 12),
                        Container(height: 1, color: kPrimary.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        _chargeRow('Total', '৳ $totalAmount', bold: true),
                        if (balanceUsed > 0) ...[
                          const SizedBox(height: 8),
                          _chargeRow(
                            'Wallet balance used',
                            '- ৳ $balanceUsed',
                            color: kGreen,
                          ),
                        ],
                        const SizedBox(height: 8),
                        _chargeRow(
                          '✓  Amount paid',
                          '৳ $amountPaid',
                          color: kGreen,
                        ),
                        if (hasDue) ...[
                          const SizedBox(height: 6),
                          _chargeRow(
                            '⚠  Due at doctor\'s chamber',
                            '৳ $dueAmount',
                            color: kRed,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Summary box
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: kPrimary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                !hasDue ? 'Total paid' : 'Now paid',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.75)),
                              ),
                              if (hasDue) ...[
                                const SizedBox(height: 3),
                                Text(
                                  '৳ $dueAmount due at chamber',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withValues(alpha: 0.65)),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            '৳ $amountPaid',
                            style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),

                  _divider(),

                  // Payment method
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Payment method',
                                style: TextStyle(fontSize: 11, color: kSubtext)),
                            const SizedBox(height: 3),
                            Text(
                              paymentMethodLabel,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: kText),
                            ),
                            if (transactionId.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text('TXN: $transactionId',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: kSubtext,
                                      fontFamily: 'monospace')),
                            ],
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Receipt no.',
                                style:
                                    TextStyle(fontSize: 11, color: kSubtext)),
                            const SizedBox(height: 3),
                            Text('#$receiptNumber',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: kText)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Footer
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: kBg,
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(20)),
                      border: Border(top: BorderSide(color: kBorder)),
                    ),
                    child: const Text(
                      'Generated by My_Health_Care',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: kSubtext),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Pending-approval notice — shown until admin approves/completes
            if (!isApproved)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: kAmberLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kAmber.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.hourglass_top_rounded, color: kAmber, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Invoice download will be available once admin approves this appointment.',
                        style: TextStyle(fontSize: 12, color: kAmber),
                      ),
                    ),
                  ],
                ),
              ),

            // Download button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: isApproved ? _downloadPdf : null,
                icon: const Icon(Icons.download_rounded, size: 20),
                label: Text(
                  isApproved ? 'Download Invoice PDF' : 'Pending Approval',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isApproved ? kPrimary : Colors.grey.shade300,
                  foregroundColor:
                      isApproved ? Colors.white : Colors.grey.shade600,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _infoBox({required String label, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.2,
                  color: kSubtext,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(label,
        style: const TextStyle(
            fontSize: 9,
            letterSpacing: 1.2,
            color: kSubtext,
            fontWeight: FontWeight.bold));
  }

  Widget _divider() {
    return Divider(color: kBorder, height: 1);
  }

  Widget _chargeRow(String label, String value,
      {bool bold = false, Color? color}) {
    final style = TextStyle(
      fontSize: bold ? 14 : 13,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: color ?? (bold ? kText : kSubtext),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}