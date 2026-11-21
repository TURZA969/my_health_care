import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class InvoiceHelper {
  static Future<void> printInvoice({
    required String orderId,
    required List<Map<String, dynamic>> items,
    required int medicineTotal,
    required int homeServiceCharge,
    required int platformCharge,
    required int totalAmount,
    required String paymentMethod,
    required String deliveryAddress,
    required String customerName,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // ── Header ──
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('MY_HEALTH_CARE',
                        style: pw.TextStyle(
                            fontSize: 24,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.orange700)),
                    pw.Text('Medicine Delivery Service',
                        style: const pw.TextStyle(
                            fontSize: 11, color: PdfColors.grey700)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('INVOICE',
                        style: pw.TextStyle(
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey800)),
                    pw.Text('Order #${orderId.substring(0, 8).toUpperCase()}',
                        style: const pw.TextStyle(
                            fontSize: 11, color: PdfColors.grey600)),
                    pw.Text(
                        'Date: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                        style: const pw.TextStyle(
                            fontSize: 11, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),

            pw.SizedBox(height: 20),
            pw.Divider(color: PdfColors.orange200),
            pw.SizedBox(height: 16),

            // ── Customer Info ──
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Bill To',
                          style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.grey600)),
                      pw.SizedBox(height: 4),
                      pw.Text(customerName,
                          style: pw.TextStyle(
                              fontSize: 13, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Delivery Address',
                          style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.grey600)),
                      pw.SizedBox(height: 4),
                      pw.Text(deliveryAddress,
                          style: const pw.TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Payment Method',
                          style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.grey600)),
                      pw.SizedBox(height: 4),
                      pw.Text(paymentMethod,
                          style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.orange700)),
                    ],
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 24),

            // ── Items Table ──
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(4),
                1: const pw.FixedColumnWidth(60),
                2: const pw.FixedColumnWidth(60),
                3: const pw.FixedColumnWidth(80),
              },
              children: [
                // header
                pw.TableRow(
                  decoration:
                      const pw.BoxDecoration(color: PdfColors.orange700),
                  children: [
                    _tableCell('Medicine', isHeader: true),
                    _tableCell('Price', isHeader: true),
                    _tableCell('Qty', isHeader: true),
                    _tableCell('Total', isHeader: true),
                  ],
                ),
                // rows
                ...items.map((item) => pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.white),
                      children: [
                        _tableCell(item['name'] ?? ''),
                        _tableCell('${item['price']}'),
                        _tableCell('${item['qty']}'),
                        _tableCell(
                            '${(item['price'] as int) * (item['qty'] as int)}'),
                      ],
                    )),
              ],
            ),

            pw.SizedBox(height: 16),

            // ── Charges Breakdown ──
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                width: 240,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.orange50,
                  border: pw.Border.all(color: PdfColors.orange200),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _chargeRow('Medicine total', '$medicineTotal'),
                    pw.SizedBox(height: 6),
                    _chargeRow('Home service charge', '$homeServiceCharge'),
                    pw.SizedBox(height: 6),
                    _chargeRow('Platform charge', '$platformCharge'),
                    pw.Divider(color: PdfColors.orange300),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Grand total',
                            style: pw.TextStyle(
                                fontSize: 13,
                                fontWeight: pw.FontWeight.bold)),
                        pw.Text('$totalAmount',
                            style: pw.TextStyle(
                                fontSize: 15,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.orange700)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            pw.SizedBox(height: 40),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(
                  'Thank you for your order! Stay healthy.',
                  style: const pw.TextStyle(
                      fontSize: 11, color: PdfColors.grey600)),
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  static pw.Widget _chargeRow(String label, String amount) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label,
            style: const pw.TextStyle(
                fontSize: 11, color: PdfColors.grey700)),
        pw.Text(amount,
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey800)),
      ],
    );
  }

  static pw.Widget _tableCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight:
              isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isHeader ? PdfColors.white : PdfColors.grey800,
        ),
      ),
    );
  }
}