import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../domain/domain.dart';
import '../calculations/calculation_engine.dart';
import '../ui/formatters/id_formatter.dart';
import '../utils/app_date_formatter.dart';
import 'pdf_fonts.dart';

/// Customer Statement report model (§6.1 & §6.2).
///
/// Encapsulates full single-customer ledger history including:
/// - Business header: shop name, phone, address, generated date.
/// - Customer info: name, phone, address, customer ID.
/// - Transaction ID header for every record row with exact startDate timestamp ("dd/MM/yyyy, HH:mm").
/// - Active records table: item details, principal, rate, interest accrued, total due.
/// - Payment history per record: exact payment date ("dd/MM/yyyy, HH:mm"), amount, interest, principal.
/// - Summary footer: total principal out, total interest accrued, total due.
class CustomerStatementReport {
  final Customer customer;
  final List<LedgerRecord> records;
  final BusinessInfo businessInfo;
  final DateTime generatedDate;
  final double totalPrincipal;
  final double totalInterestAccrued;
  final double totalPaid;
  final double totalDue;
  final int activeRecordCount;
  final int settledRecordCount;
  final PdfFonts? fonts;

  const CustomerStatementReport({
    required this.customer,
    required this.records,
    required this.businessInfo,
    required this.generatedDate,
    required this.totalPrincipal,
    required this.totalInterestAccrued,
    required this.totalPaid,
    required this.totalDue,
    required this.activeRecordCount,
    required this.settledRecordCount,
    this.fonts,
  });

  /// Builds the [pw.Document] widget tree for this customer statement (§6.1, §6.2).
  pw.Document buildDocument([PdfFonts? overrideFonts]) {
    final effectiveFonts = overrideFonts ?? fonts;
    final pdf = pw.Document(theme: effectiveFonts?.toTheme());
    final targetDate = DateTime(generatedDate.year, generatedDate.month, generatedDate.day);

    final activeRecords = records.where((r) => r.isActive).toList();
    final settledRecords = records.where((r) => r.isSettled).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          final content = <pw.Widget>[];

          // 1. Business Header (§6.2)
          content.add(
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      businessInfo.name.isNotEmpty ? businessInfo.name : 'Money Lending Ledger',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (businessInfo.address.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        businessInfo.address,
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                      ),
                    ],
                    if (businessInfo.phone.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Phone: ${businessInfo.phone}',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                      ),
                    ],
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'CUSTOMER STATEMENT',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blueGrey800,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Generated: ${AppDateFormatter.formatDate(generatedDate)}',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ],
            ),
          );
          content.add(pw.Divider(thickness: 1, color: PdfColors.grey400));
          content.add(pw.SizedBox(height: 6));

          // 2. Customer Info Box (§6.2: name, phone, address, customer ID)
          content.add(
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Customer Name: ${customer.name}',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Customer ID: ${AppIdFormatter.formatCustomerId(customer.displayId)}',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: PdfColors.blueGrey800),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Phone: ${customer.phone ?? '-'}',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Address: ${customer.address ?? '-'}',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
          content.add(pw.SizedBox(height: 14));

          // 3. Section: Active Records & Per-Record Payment History (§6.2)
          content.add(
            pw.Text(
              'Active Loan Records (${activeRecords.length})',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
            ),
          );
          content.add(pw.SizedBox(height: 6));

          if (activeRecords.isEmpty) {
            content.add(
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text('No active records on file for this customer.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              ),
            );
          } else {
            for (final record in activeRecords) {
              content.add(_buildRecordSection(record, targetDate));
              content.add(pw.SizedBox(height: 12));
            }
          }

          // 4. Section: Settled Records (if any)
          if (settledRecords.isNotEmpty) {
            content.add(pw.SizedBox(height: 4));
            content.add(
              pw.Text(
                'Settled Records (${settledRecords.length})',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
              ),
            );
            content.add(pw.SizedBox(height: 6));
            for (final record in settledRecords) {
              content.add(_buildRecordSection(record, targetDate));
              content.add(pw.SizedBox(height: 12));
            }
          }

          // 5. Summary Footer Card (§6.2: total principal out, total interest accrued, total due)
          content.add(pw.SizedBox(height: 8));
          content.add(
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.blueGrey50,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.blueGrey300, width: 1.5),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _buildFooterSummaryCol('Total Active Loans', '$activeRecordCount'),
                  _buildFooterSummaryCol('Total Principal Out', 'Rs. ${totalPrincipal.toStringAsFixed(2)}'),
                  _buildFooterSummaryCol('Total Accrued Interest', 'Rs. ${totalInterestAccrued.toStringAsFixed(2)}'),
                  _buildFooterSummaryCol('Total Amount Due', 'Rs. ${totalDue.toStringAsFixed(2)}', isBold: true),
                ],
              ),
            ),
          );

          return content;
        },
        footer: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(top: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Customer Statement - Generated: ${AppDateFormatter.formatDate(generatedDate)}',
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf;
  }

  /// Generates the offline PDF document bytes for this customer statement.
  Future<Uint8List> buildPdf([PdfFonts? overrideFonts]) async {
    return buildDocument(overrideFonts).save();
  }

  /// Builds a dedicated record section displaying:
  /// - Transaction ID Header (§6.2)
  /// - Exact start timestamp "dd/MM/yyyy, HH:mm" ([FIX-TIMESTAMP-PDF-1])
  /// - Active records details table (items, principal, rate, interest, due)
  /// - Payment history table for this record with timestamp "dd/MM/yyyy, HH:mm"
  pw.Widget _buildRecordSection(LedgerRecord record, DateTime targetDate) {
    final fin = CalculationEngine.calculateRecordFinancials(record, targetDate, targetDate);

    // Collateral items text
    String itemDetails = 'None';
    if (record.items.isNotEmpty) {
      itemDetails = record.items.map((it) {
        final val = it.itemValue > 0 ? it.itemValue : CalculationEngine.calculateItemValue(it);
        final wt = it.weight > 0 ? '${it.weight}g' : '';
        final pur = it.purity > 0 ? ' (${it.purity}%)' : '';
        return '${it.name} - $wt$pur [Rs. ${val.toStringAsFixed(0)}]';
      }).join(', ');
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Transaction ID Header (§6.2: surface transactionId e.g. TRAN092601)
          // Mandates startDate formatted as "dd/MM/yyyy, HH:mm" ([FIX-TIMESTAMP-PDF-1])
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const pw.BoxDecoration(
              color: PdfColors.blueGrey800,
              borderRadius: pw.BorderRadius.vertical(top: pw.Radius.circular(3)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  children: [
                    pw.Text(
                      'Transaction ID: ',
                      style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 8.5),
                    ),
                    pw.Text(
                      AppIdFormatter.formatTransactionId(record.transactionId),
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Text(
                      '(${record.type.name} - ${record.status.name})',
                      style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 8),
                    ),
                  ],
                ),
                pw.Text(
                  '${record.isGiven ? "Given" : "Taken"}: ${AppDateFormatter.formatDate(record.startDate)} • ${AppDateFormatter.formatMonths(fin.months)}'
                  '${record.endDate != null ? " | Due: ${AppDateFormatter.formatDate(record.endDate!)}" : ""}'
                  '${record.settledDate != null ? " | Settled: ${AppDateFormatter.formatDate(record.settledDate!)}" : ""}',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 8.5,
                  ),
                ),
              ],
            ),
          ),

          // Active Records Table Details (§6.2: item details, principal, rate, interest accrued, total due)
          pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.TableHelper.fromTextArray(
                  headers: ['Collateral Item Details', 'Principal', 'Interest Rate', 'Accrued (${AppDateFormatter.formatMonths(fin.months)})', 'Total Due'],
                  data: [
                    [
                      itemDetails,
                      'Rs. ${record.principalAmount.toStringAsFixed(2)}',
                      '${record.interestRate.toStringAsFixed(1)}% / mo',
                      'Rs. ${fin.totalInterest.toStringAsFixed(2)}',
                      'Rs. ${fin.totalDue.toStringAsFixed(2)}',
                    ],
                  ],
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5, color: PdfColors.blueGrey900),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  cellStyle: const pw.TextStyle(fontSize: 7.5),
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.centerRight,
                    2: pw.Alignment.centerRight,
                    3: pw.Alignment.centerRight,
                    4: pw.Alignment.centerRight,
                  },
                ),

                pw.SizedBox(height: 6),

                // Payment history per record (§6.2 & [FIX-TIMESTAMP-PDF-1] revised v1.15)
                // payment date (formatDate(), e.g. "5 August 2026"), payment ID (e.g. PAY092601), amount, interest, principal
                if (record.payments.isNotEmpty) ...[
                  pw.Text(
                    'Payment History for ${AppIdFormatter.formatTransactionId(record.transactionId)}:',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800),
                  ),
                  pw.SizedBox(height: 3),
                  pw.TableHelper.fromTextArray(
                    headers: ['Payment Date', 'Payment ID', 'Amount Paid', 'Interest Portion', 'Principal Portion', 'Notes'],
                    data: record.payments.map((p) {
                      final rawPaymentId = p.paymentId.isNotEmpty ? p.paymentId : (p.id.isNotEmpty ? p.id : '-');
                      final paymentDisplayId = rawPaymentId != '-' ? AppIdFormatter.formatPaymentId(rawPaymentId) : '-';
                      return [
                        AppDateFormatter.formatDate(p.date),
                        paymentDisplayId,
                        'Rs. ${p.amount.toStringAsFixed(2)}',
                        'Rs. ${p.interestPaid.toStringAsFixed(2)}',
                        'Rs. ${p.principalPaid.toStringAsFixed(2)}',
                        p.notes ?? '-',
                      ];
                    }).toList(),
                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7, color: PdfColors.grey800),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                    cellStyle: const pw.TextStyle(fontSize: 7),
                    cellAlignments: {
                      0: pw.Alignment.centerLeft,
                      1: pw.Alignment.centerLeft,
                      2: pw.Alignment.centerRight,
                      3: pw.Alignment.centerRight,
                      4: pw.Alignment.centerRight,
                      5: pw.Alignment.centerLeft,
                    },
                  ),
                ] else ...[
                  pw.Text(
                    'No payments recorded for this record yet.',
                    style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600, fontStyle: pw.FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooterSummaryCol(String label, String val, {bool isBold = false}) {
    return pw.Column(
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        pw.SizedBox(height: 3),
        pw.Text(
          val,
          style: pw.TextStyle(
            fontSize: isBold ? 11 : 9.5,
            fontWeight: pw.FontWeight.bold,
            color: isBold ? PdfColors.blueGrey900 : PdfColors.black,
          ),
        ),
      ],
    );
  }
}

/// Generates a full single-customer statement (§6.1, §6.2).
///
/// Features complete record details, payment history per record, interest breakdown, and totals.
CustomerStatementReport generateCustomerStatement(
  Customer customer,
  List<LedgerRecord> records, [
  BusinessInfo businessInfo = const BusinessInfo(),
  Object? arg4,
  Object? arg5,
]) {
  DateTime? today;
  PdfFonts? resolvedFonts;

  for (final arg in [arg4, arg5]) {
    if (arg is DateTime) {
      today = arg;
    } else if (arg is PdfFonts) {
      resolvedFonts = arg;
    }
  }

  final now = today ?? DateTime.now();
  final targetDate = DateTime(now.year, now.month, now.day);

  // Filter records belonging to this customer
  final customerRecords = records.where((r) => r.customerId == customer.id).toList();

  double totalPrincipal = 0.0;
  double totalInterestAccrued = 0.0;
  double totalPaid = 0.0;
  double totalDue = 0.0;
  int activeCount = 0;
  int settledCount = 0;

  for (final r in customerRecords) {
    if (r.isActive) activeCount++;
    if (r.isSettled) settledCount++;

    final fin = CalculationEngine.calculateRecordFinancials(r, targetDate, targetDate);
    totalPrincipal += r.principalAmount;
    totalInterestAccrued += fin.totalInterest;
    totalPaid += fin.totalPaid;
    totalDue += fin.totalDue;
  }

  return CustomerStatementReport(
    customer: customer,
    records: customerRecords,
    businessInfo: businessInfo,
    generatedDate: now,
    totalPrincipal: totalPrincipal,
    totalInterestAccrued: totalInterestAccrued,
    totalPaid: totalPaid,
    totalDue: totalDue,
    activeRecordCount: activeCount,
    settledRecordCount: settledCount,
    fonts: resolvedFonts,
  );
}

/// Data payload for background isolate PDF generation ([FIX-PDFBGTHREAD-1] & §6.3).
class StatementJob {
  final Customer customer;
  final List<LedgerRecord> records;
  final BusinessInfo businessInfo;
  final PdfFonts? fonts;
  final DateTime? today;

  const StatementJob(
    this.customer,
    this.records,
    this.businessInfo, [
    this.fonts,
    this.today,
  ]);
}

/// Pure top-level worker function executed on a background isolate via [compute] ([FIX-PDFBGTHREAD-1] & §6.3).
Future<Uint8List> buildStatementBytes(StatementJob job) async {
  final statement = generateCustomerStatement(
    job.customer,
    job.records,
    job.businessInfo,
    job.fonts,
    job.today,
  );
  return statement.buildPdf(job.fonts);
}
