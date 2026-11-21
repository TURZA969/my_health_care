import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// ─────────────────────────────────────────────
// USAGE
// ─────────────────────────────────────────────
// After booking confirmed, call:
//   showLabBookingConfirmationDialog(context, bookingId, receiptNumber: receiptNumber);
//
// Or generate PDF directly:
//   await LabInvoiceService.downloadInvoicePDF(bookingId);
//
// Firestore paths used:
//   lab_bookings/{bookingId}   → now also has the AppointmentScreen-style
//                                 payment fields written by the updated
//                                 lab_test_screen.dart:
//                                   fee              → test+kit+home fee, before platform charge
//                                   platformCharge
//                                   promoCode / voucherId / discountAmount
//                                   balanceUsed
//                                   amountPaid       → amount paid right now (online/cash flow)
//                                   dueAmount        → due at hospital/lab (Cash flow only)
//                                   totalFee         → fee - discountAmount + platformCharge
//                                   paymentType      → 'Online' | 'Cash' | 'Balance'
//                                   senderNumber / transactionId
//                                   receiptNumber
//   users/{uid}                 → name, phone
//   settings/app_settings       → helplineNumber
//
// Admin approval flow:
//   BookingApprovalListener widget tracks status in real-time.
//   status: "pending"  → shows "Please waiting for Admin Approval"
//   status: "approved" → shows "Download Your Invoice" button
//   status: "rejected" → shows rejection message
//
// Cash (pay-at-lab) invoice:
//   Payment status shows "DUE" with due amount breakdown whenever
//   dueAmount > 0 — regardless of paymentType — since balance/promo can
//   also leave a partial due for the Cash flow.
//
// Receipt Number:
//   Generated client-side in lab_test_screen.dart at booking time in the
//   format MHC-YYMMDD-XXXXX and saved permanently as `receiptNumber` on the
//   lab_bookings document. It is shown in the booking-confirmation dialog
//   right away, and printed on the PDF invoice header as "RECEIPT NO".
//   Older bookings created before this field existed fall back to a
//   MHC-prefixed short booking id so the invoice never shows a blank field.
// ─────────────────────────────────────────────

// ════════════════════════════════
// CONFIRMATION DIALOG
// (Persistent — stays until user closes or downloads)
// ════════════════════════════════

void showLabBookingConfirmationDialog(
  BuildContext context,
  String bookingId, {
  String? receiptNumber,
}) {
  showDialog(
    context: context,
    barrierDismissible: false, // ← stays until user taps Close
    builder: (_) => WillPopScope(
      onWillPop: () async => false, // ← back button se close hobe na
      child: AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text('Booking Submitted!',
                style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Receipt Number Box ──
              if (receiptNumber != null && receiptNumber.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00897B).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color:
                            const Color(0xFF00897B).withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF00897B).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.confirmation_number_rounded,
                            color: Color(0xFF00897B), size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Receipt No.',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey)),
                            Text(
                              receiptNumber,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A1A2E),
                                  letterSpacing: 0.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ── Waiting Banner ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.hourglass_top_rounded,
                        color: Colors.orange, size: 36),
                    const SizedBox(height: 8),
                    const Text(
                      'Please waiting for\nAdmin Approval',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your booking is under review.\n'
                      'Invoice will be available once approved.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: Colors.orange.shade700),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // ── Real-time approval listener ──
              BookingApprovalListener(bookingId: bookingId),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true)
                .pop(),
            child: const Text('Close',
                style: TextStyle(color: Color(0xFF00897B))),
          ),
        ],
      ),
    ),
  );
}

// ════════════════════════════════
// INVOICE SERVICE
// ════════════════════════════════

class LabInvoiceService {
  /// Fetches booking + user profile + app settings from Firestore,
  /// then generates and opens a PDF invoice.
  static Future<void> downloadInvoicePDF(String bookingId) async {
    final fs = FirebaseFirestore.instance;
    final currentUser = FirebaseAuth.instance.currentUser;

    // 1. Load booking data
    final bookingDoc =
        await fs.collection('lab_bookings').doc(bookingId).get();
    final booking = bookingDoc.data() ?? {};

    // 2. Load user profile (name + phone)
    String userName = '';
    String userPhone = '';
    final uid = currentUser?.uid ?? booking['userId'] ?? '';
    if (uid.isNotEmpty) {
      final userDoc = await fs.collection('users').doc(uid).get();
      final userData = userDoc.data() ?? {};
      userName = userData['name']?.toString() ?? '';
      userPhone = userData['phone']?.toString() ?? '';
    }

    // 3. Load app settings (helpline number)
    String helplineNumber = '';
    final settingsDoc = await fs
        .collection('settings')
        .doc('app_settings')
        .get();
    final settings = settingsDoc.data() ?? {};
    helplineNumber = settings['helplineNumber']?.toString() ?? '';

    // 4. Build PDF
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildPdfHeader(bookingId, booking),
            pw.SizedBox(height: 20),
            _buildPdfPatientSection(booking, userName, userPhone),
            pw.SizedBox(height: 16),
            _buildPdfTestSection(booking),
            pw.SizedBox(height: 16),
            _buildPdfCostSection(booking),
            pw.SizedBox(height: 16),
            _buildPdfPaymentSection(booking),
            pw.Spacer(),
            _buildPdfFooter(helplineNumber),
          ],
        ),
      ),
    );

    // 5. Save & open — filename also uses the MHC receipt number when
    //    available so downloaded files are easy to identify.
    final dir = await getApplicationDocumentsDirectory();
    final receiptNumber = booking['receiptNumber']?.toString() ?? '';
    final fileTag = receiptNumber.isNotEmpty
        ? receiptNumber.replaceAll('-', '')
        : (bookingId.length >= 8
            ? bookingId.substring(0, 8).toUpperCase()
            : bookingId.toUpperCase());
    final file = File('${dir.path}/lab_invoice_$fileTag.pdf');
    await file.writeAsBytes(await pdf.save());
    await OpenFile.open(file.path);
  }

  // ─── PDF Sections ────────────────────────────────

  /// Returns the MHC receipt number to print on the invoice.
  /// Prefers the stored `receiptNumber` field; falls back to a
  /// MHC-prefixed short booking id for older bookings that predate
  /// this field so the invoice never prints a blank value.
  static String _resolveReceiptNumber(
      String bookingId, Map<String, dynamic> data) {
    final stored = data['receiptNumber']?.toString() ?? '';
    if (stored.isNotEmpty) return stored;
    final shortId = bookingId.length >= 8
        ? bookingId.substring(0, 8).toUpperCase()
        : bookingId.toUpperCase();
    return 'MHC-$shortId';
  }

  static pw.Widget _buildPdfHeader(
      String bookingId, Map<String, dynamic> data) {
    final receiptNumber = _resolveReceiptNumber(bookingId, data);
    final createdAt = data['createdAt'];
    String dateStr = '';
    if (createdAt is Timestamp) {
      dateStr = DateFormat('dd MMM yyyy, hh:mm a')
          .format(createdAt.toDate());
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFF00695C),
        borderRadius:
            const pw.BorderRadius.all(pw.Radius.circular(10)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('My Health Care',
                  style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white)),
              pw.SizedBox(height: 4),
              pw.Text('Lab Test Invoice',
                  style: const pw.TextStyle(
                      fontSize: 12,
                      color: PdfColor(1, 1, 1, 0.7))),
              if (dateStr.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text('Issued: $dateStr',
                    style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColor(1, 1, 1, 0.54))),
              ],
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('RECEIPT NO',
                  style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColor(1, 1, 1, 0.54),
                      letterSpacing: 1.2)),
              pw.SizedBox(height: 4),
              pw.Text(receiptNumber,
                  style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white)),
              pw.SizedBox(height: 6),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                decoration: pw.BoxDecoration(
                  color: const PdfColor(0.2, 0.78, 0.35),
                  borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(20)),
                ),
                child: pw.Text(
                  '✓  APPROVED',
                  style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                      letterSpacing: 0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPdfPatientSection(
    Map<String, dynamic> data,
    String userName,
    String userPhone,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: const PdfColor(0.94, 0.98, 0.97),
        border: pw.Border.all(
            color: const PdfColor(0.36, 0.79, 0.65), width: 0.5),
        borderRadius:
            const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('PATIENT & APPOINTMENT DETAILS',
              style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                  letterSpacing: 1.0)),
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (userName.isNotEmpty)
                      _pdfLabelValue('Patient Name', userName),
                    if (userName.isNotEmpty) pw.SizedBox(height: 8),
                    if (userPhone.isNotEmpty)
                      _pdfLabelValue('Phone', userPhone),
                    if (userPhone.isNotEmpty) pw.SizedBox(height: 8),
                    _pdfLabelValue(
                        'Hospital', data['hospitalName'] ?? '-'),
                    pw.SizedBox(height: 8),
                    _pdfLabelValue(
                        'Location', data['location'] ?? '-'),
                  ],
                ),
              ),
              pw.SizedBox(width: 20),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _pdfLabelValue(
                        'Appointment Date', data['date'] ?? '-'),
                    pw.SizedBox(height: 8),
                    _pdfLabelValue(
                      'Home Collection',
                      data['homeCollection'] == true ? 'Yes' : 'No',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Test Section — supports multiple tests ──
  static pw.Widget _buildPdfTestSection(Map<String, dynamic> data) {
    final tests = data['tests'] as List<dynamic>?;

    // Multiple tests (new format)
    if (tests != null && tests.isNotEmpty) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('TEST DETAILS',
              style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                  letterSpacing: 1.0)),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border.all(
                  color: const PdfColor(0.88, 0.88, 0.88), width: 0.5),
              borderRadius:
                  const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              children: tests.map((t) {
                final tm = t as Map<String, dynamic>;
                final kitRequired = tm['kitRequired'] == true;
                final kitCharge =
                    (tm['kitCharge'] as num? ?? 0).toInt();
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 6),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment:
                            pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(tm['testName'] ?? '-',
                              style: pw.TextStyle(
                                  fontSize: 13,
                                  fontWeight: pw.FontWeight.bold,
                                  color:
                                      const PdfColor(0.1, 0.1, 0.18))),
                          pw.Text(
                              '৳${(tm['testFee'] as num? ?? 0).toInt()}',
                              style: pw.TextStyle(
                                  fontSize: 13,
                                  fontWeight: pw.FontWeight.bold,
                                  color:
                                      const PdfColor(0.0, 0.54, 0.48))),
                        ],
                      ),
                      if (kitRequired && kitCharge > 0)
                        pw.Row(
                          mainAxisAlignment:
                              pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                                '  Kit: ${tm['kitName'] ?? ''}',
                                style: const pw.TextStyle(
                                    fontSize: 10,
                                    color:
                                        PdfColor(0.39, 0.24, 0.04))),
                            pw.Text('৳$kitCharge',
                                style: const pw.TextStyle(
                                    fontSize: 10,
                                    color:
                                        PdfColor(0.39, 0.24, 0.04))),
                          ],
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      );
    }

    // Single test (legacy / backward compat)
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('TEST DETAILS',
            style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey700,
                letterSpacing: 1.0)),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            border: pw.Border.all(
                color: const PdfColor(0.88, 0.88, 0.88), width: 0.5),
            borderRadius:
                const pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(data['testName'] ?? '-',
                      style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor(0.1, 0.1, 0.18))),
                  pw.SizedBox(height: 4),
                  if (data['homeCollection'] == true)
                    pw.Text('Home collection',
                        style: const pw.TextStyle(
                            fontSize: 10,
                            color: PdfColor(0.06, 0.43, 0.33))),
                  if (data['kitRequired'] == true)
                    pw.Text(
                        'Kit included: ${data['kitName'] ?? ''}',
                        style: const pw.TextStyle(
                            fontSize: 10,
                            color: PdfColor(0.39, 0.24, 0.04))),
                ],
              ),
              pw.Text('৳${data['testFee'] ?? 0}',
                  style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor(0.0, 0.54, 0.48))),
            ],
          ),
        ),
      ],
    );
  }

  // ── Cost Breakdown — now mirrors AppointmentScreen: fee → promo
  // discount → platform charge → total, same field names written by the
  // updated lab_test_screen.dart. Falls back gracefully for older
  // bookings that don't have `fee` / `discountAmount` saved. ──
  static pw.Widget _buildPdfCostSection(Map<String, dynamic> data) {
    final testFee = (data['testFee'] as num? ?? 0).toInt();
    final homeCharge = (data['homeServiceCharge'] as num? ?? 0).toInt();
    final kitCharge = (data['kitCharge'] as num? ?? 0).toInt();
    final platformCharge = (data['platformCharge'] as num? ?? 0).toInt();
    final discount = (data['discountAmount'] as num? ?? 0).toInt();
    final promoCode = (data['promoCode'] ?? '').toString();
    final total = (data['totalFee'] as num? ?? 0).toInt();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('COST BREAKDOWN',
            style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey700,
                letterSpacing: 1.0)),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            border: pw.Border.all(
                color: const PdfColor(0.88, 0.88, 0.88), width: 0.5),
            borderRadius:
                const pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Column(
            children: [
              _pdfFeeRow('Test fee', '৳$testFee'),
              if (kitCharge > 0)
                _pdfFeeRow('Kit charge', '৳$kitCharge'),
              if (homeCharge > 0)
                _pdfFeeRow('Home service charge', '৳$homeCharge'),
              if (discount > 0)
                _pdfFeeRow(
                  promoCode.isNotEmpty
                      ? 'Promo discount ($promoCode)'
                      : 'Promo discount',
                  '- ৳$discount',
                  valueColor: const PdfColor(0.18, 0.49, 0.20),
                ),
              _pdfFeeRow('Platform charge', '৳$platformCharge'),
              pw.Divider(
                  color: const PdfColor(0.88, 0.88, 0.88),
                  thickness: 0.5),
              _pdfFeeRow('Total amount', '৳$total',
                  bold: true,
                  valueColor: const PdfColor(0.0, 0.54, 0.48)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Payment Info — now mirrors AppointmentScreen: Online / Cash /
  // Balance payment types, wallet balance used, amount paid now, and
  // any amount due at the hospital/lab. ──
  static pw.Widget _buildPdfPaymentSection(Map<String, dynamic> data) {
    final paymentType = (data['paymentType'] ?? '-').toString();
    final sender = (data['senderNumber'] ?? data['paymentNumber'] ?? '')
        .toString();
    final txId = (data['transactionId'] ?? '').toString();
    final balanceUsed = (data['balanceUsed'] as num? ?? 0).toInt();
    final amountPaid = (data['amountPaid'] as num? ?? 0).toInt();
    final dueAmount = (data['dueAmount'] as num? ?? 0).toInt();

    final methodDisplay = switch (paymentType) {
      'Online' => 'Online Payment (bKash/Nagad/Rocket)',
      'Cash' => 'Pay at Hospital / Lab',
      'Balance' => 'Wallet Balance',
      _ => paymentType,
    };

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('PAYMENT INFO',
            style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey700,
                letterSpacing: 1.0)),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            color: const PdfColor(0.94, 0.98, 0.97),
            border: pw.Border.all(
                color: const PdfColor(0.36, 0.79, 0.65), width: 0.5),
            borderRadius:
                const pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Column(
            children: [
              _pdfFeeRow('Method', methodDisplay),
              if (sender.isNotEmpty)
                _pdfFeeRow('From number', sender),
              if (txId.isNotEmpty)
                _pdfFeeRow('Transaction ID', txId),
              if (balanceUsed > 0)
                _pdfFeeRow('Wallet balance used', '৳$balanceUsed',
                    valueColor: const PdfColor(0.18, 0.49, 0.20)),
              _pdfFeeRow('Amount paid now', '৳$amountPaid',
                  bold: true,
                  valueColor: const PdfColor(0.18, 0.49, 0.20)),
              pw.SizedBox(height: 4),

              // ── Payment Status ──
              if (dueAmount > 0) ...[
                // Something still due at the hospital/lab → DUE
                pw.Row(
                  mainAxisAlignment:
                      pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Payment status',
                        style: const pw.TextStyle(
                            fontSize: 12,
                            color: PdfColors.grey700)),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: pw.BoxDecoration(
                        color: const PdfColor(0.95, 0.5, 0.1),
                        borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(20)),
                      ),
                      child: pw.Text('DUE',
                          style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white)),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                // Due breakdown box
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor(1.0, 0.95, 0.88),
                    border: pw.Border.all(
                        color: const PdfColor(0.95, 0.7, 0.3),
                        width: 0.5),
                    borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(6)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Amount Due at Hospital / Lab:',
                          style: const pw.TextStyle(
                              fontSize: 10,
                              color: PdfColors.grey700)),
                      pw.SizedBox(height: 4),
                      pw.Text('৳$dueAmount',
                          style: pw.TextStyle(
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              color:
                                  const PdfColor(0.8, 0.3, 0.0))),
                    ],
                  ),
                ),
              ] else ...[
                // Fully paid (online, or fully covered by balance) → SUCCESS
                pw.Row(
                  mainAxisAlignment:
                      pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Payment status',
                        style: const pw.TextStyle(
                            fontSize: 12,
                            color: PdfColors.grey700)),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: pw.BoxDecoration(
                        color: const PdfColor(0.2, 0.78, 0.35),
                        borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(20)),
                      ),
                      child: pw.Text('SUCCESS',
                          style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildPdfFooter(String helplineNumber) {
    return pw.Column(
      children: [
        pw.Divider(
            color: const PdfColor(0.88, 0.88, 0.88), thickness: 0.5),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                    'Powered by My Health Care · Your Health, Our Priority',
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey)),
                if (helplineNumber.isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Text('Helpline: $helplineNumber',
                      style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color:
                              const PdfColor(0.0, 0.54, 0.48))),
                ],
              ],
            ),
            pw.Text('This is a system-generated invoice.',
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey)),
          ],
        ),
      ],
    );
  }

  // ─── PDF Helpers ──────────────────────────────

  static pw.Widget _pdfLabelValue(String label, String value) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColors.grey600)),
          pw.SizedBox(height: 2),
          pw.Text(value,
              style:
                  pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ],
      );

  static pw.Widget _pdfFeeRow(
    String label,
    String value, {
    bool bold = false,
    PdfColor? valueColor,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label,
                style: const pw.TextStyle(
                    fontSize: 12, color: PdfColors.grey700)),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight:
                        bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                    color: valueColor ?? PdfColors.black)),
          ],
        ),
      );
}

// ════════════════════════════════
// BOOKING APPROVAL LISTENER
// ────────────────────────────────
// lab_test_screen.dart এর confirmation dialog এ use হয়।
// Real-time Firestore stream দিয়ে admin approval track করে।
//
//   pending  → কিছু দেখায় না (parent dialog এ banner আছে)
//   approved → "Download Your Invoice" gradient button দেখায়
//   rejected → rejection message দেখায়
// ════════════════════════════════

class BookingApprovalListener extends StatelessWidget {
  final String bookingId;
  static const _primary = Color(0xFF00897B);
  static const _primaryDark = Color(0xFF004D40);

  const BookingApprovalListener({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('lab_bookings')
          .doc(bookingId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final data =
            snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final status = data['status'] ?? 'pending';

        // ── Approved → Download Your Invoice gradient tab ──
        if (status == 'approved') {
          return Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_primaryDark, _primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _primary.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () =>
                    LabInvoiceService.downloadInvoicePDF(bookingId),
                child: const Padding(
                  padding: EdgeInsets.symmetric(
                      vertical: 16, horizontal: 20),
                  child: Row(
                    children: [
                      _DownloadIconBox(),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Download Your Invoice',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Admin approved • Tap to save PDF',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded,
                          color: Colors.white70, size: 16),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // ── Rejected ──
        if (status == 'rejected') {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.cancel_rounded,
                    color: Colors.red.shade700, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Booking Rejected.\nPlease contact support or try again.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.red.shade700),
                  ),
                ),
              ],
            ),
          );
        }

        // ── Pending → nothing extra (parent dialog handles it) ──
        return const SizedBox.shrink();
      },
    );
  }
}

// helper widget – const compatible
class _DownloadIconBox extends StatelessWidget {
  const _DownloadIconBox();

  @override
  Widget build(BuildContext context) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.download_rounded,
            color: Colors.white, size: 26),
      );
}

// ════════════════════════════════
// BOOKING HISTORY: Inline Invoice Button
// ────────────────────────────────
// Booking history screen এ প্রতিটি booking card এ বসাও।
// Status pending হলে spinning "Waiting for Approval" দেখাবে।
// Status approved হলে "Download Invoice" button দেখাবে।
// ════════════════════════════════

class LabInvoiceButton extends StatelessWidget {
  final String bookingId;
  static const _primary = Color(0xFF00897B);

  const LabInvoiceButton({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('lab_bookings')
          .doc(bookingId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final data =
            snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final status = data['status'] ?? 'pending';

        if (status == 'approved') {
          return ElevatedButton.icon(
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Download Invoice',
                style: TextStyle(fontSize: 12)),
            onPressed: () =>
                LabInvoiceService.downloadInvoicePDF(bookingId),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }

        // pending or anything else → waiting indicator
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.orange.shade700,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Waiting for Approval',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ════════════════════════════════
// REPORT DOWNLOAD BUTTON WIDGET
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
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
      label: const Text('Download Report',
          style: TextStyle(fontSize: 12)),
      onPressed: () async {
        // TODO: download from reportUrl using dio/http, then open
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}