import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../domain/domain.dart';
import '../calculations/calculation_engine.dart';
import '../ui/formatters/id_formatter.dart';
import '../utils/app_date_formatter.dart';
import 'pdf_fonts.dart';

/// Single Lender Statement report model (§6.1 & §6.2b).
///
/// Full single-lender ledger report, the TAKEN-side mirror of [CustomerStatementReport]:
/// - Business header: shop name, phone, address, generated timestamp.
/// - Lender info: name, phone, institutionDetails / address, lender ID, lender type.
/// - Transaction ID header for every TAKEN record row with exact startDate timestamp ("dd/MM/yyyy").
/// - Active records table: collateral item details, principal taken, rate, interest payable, total due.
/// - Payment history per record: payment date ("dd/MM/yyyy"), amount, interest portion, principal portion.
/// - Summary footer: total principal taken, total interest payable, total due to lender.
/// - [FIX-PDF-OVERDUEFLAG-1]: per-party statements carry NO overdue flag.
class LenderStatementReport {
  final Lender lender;
  final List<LedgerRecord> records;
  final BusinessInfo businessInfo;
  final DateTime generatedDate;
  final double totalPrincipalTaken;
  final double totalInterestPayable;
  final double totalPaid;
  final double totalDueToLender;
  final int activeRecordCount;
  final int settledRecordCount;
  final PdfFonts? fonts;
  final LenderReport? lenderReport;

  const LenderStatementReport({
    required this.lender,
    required this.records,
    required this.businessInfo,
    required this.generatedDate,
    required this.totalPrincipalTaken,
    required this.totalInterestPayable,
    required this.totalPaid,
    required this.totalDueToLender,
    required this.activeRecordCount,
    required this.settledRecordCount,
    this.fonts,
    this.lenderReport,
  });

  /// Builds the [pw.Document] widget tree for this lender statement (§6.1, §6.2b).
  pw.Document buildDocument([PdfFonts? overrideFonts]) {
    final effectiveFonts = overrideFonts ?? fonts;
    final pdf = pw.Document(theme: effectiveFonts?.toTheme());
    final targetDate = DateTime(generatedDate.year, generatedDate.month, generatedDate.day);

    final activeRecords = records.where((r) => r.isActive && r.isTaken).toList();
    final settledRecords = records.where((r) => r.isSettled && r.isTaken).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          final content = <pw.Widget>[];

          // 1. Business Header (§6.1, §6.2b)
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
                      'LENDER STATEMENT',
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

          // 2. Lender Info Box (§6.2b: name, displayId, type, phone, institutionDetails)
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
                        'Lender Name: ${lender.name}',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Lender ID: ${AppIdFormatter.formatLenderId(lender.displayId)} • Type: ${lender.lenderType.displayName}',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: PdfColors.blueGrey800),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Phone: ${lender.phone ?? '-'}',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
                      ),
                      if (lender.institutionDetails != null && lender.institutionDetails!.isNotEmpty) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Details: ${lender.institutionDetails}',
                          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
          content.add(pw.SizedBox(height: 14));

          // 3. Section: Active Taken Loans & Per-Record Payment History (§6.2b)
          content.add(
            pw.Text(
              'Active Loans Borrowed (${activeRecords.length})',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
            ),
          );
          content.add(pw.SizedBox(height: 6));

          if (activeRecords.isEmpty) {
            content.add(
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text('No active taken records on file for this lender.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              ),
            );
          } else {
            for (final record in activeRecords) {
              content.add(_buildRecordSection(record, targetDate));
              content.add(pw.SizedBox(height: 12));
            }
          }

          // 4. Section: Settled Taken Records (if any)
          if (settledRecords.isNotEmpty) {
            content.add(pw.SizedBox(height: 4));
            content.add(
              pw.Text(
                'Settled Loans (${settledRecords.length})',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
              ),
            );
            content.add(pw.SizedBox(height: 6));
            for (final record in settledRecords) {
              content.add(_buildRecordSection(record, targetDate));
              content.add(pw.SizedBox(height: 12));
            }
          }

          // 5. Summary Footer Card (§6.2b: total principal taken, total interest payable, total due to lender reading LenderReport)
          content.add(pw.SizedBox(height: 8));
          final effectiveLenderReport = lenderReport ??
              CalculationEngine.getLenderReports(
                lenders: [lender],
                records: records,
                today: targetDate,
              ).firstOrNull;

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
                  _buildFooterSummaryCol('Total Active Loans', '${effectiveLenderReport?.activeRecordCount ?? activeRecordCount}'),
                  _buildFooterSummaryCol('Total Principal Taken', 'Rs. ${(effectiveLenderReport?.totalPrincipalTaken ?? totalPrincipalTaken).toStringAsFixed(2)}'),
                  _buildFooterSummaryCol('Total Interest Payable', 'Rs. ${(effectiveLenderReport?.totalInterestPayable ?? totalInterestPayable).toStringAsFixed(2)}'),
                  _buildFooterSummaryCol('Total Due to Lender', 'Rs. ${(effectiveLenderReport?.totalDueToLender ?? totalDueToLender).toStringAsFixed(2)}', isBold: true),
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
                  'Lender Statement - Generated: ${AppDateFormatter.formatDate(generatedDate)}',
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

  /// Generates the offline PDF document bytes for this lender statement.
  Future<Uint8List> buildPdf([PdfFonts? overrideFonts]) async {
    return buildDocument(overrideFonts).save();
  }

  pw.Widget _buildRecordSection(LedgerRecord record, DateTime targetDate) {
    final fin = CalculationEngine.calculateRecordFinancials(record, targetDate, targetDate);

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
                      '(${record.status.name})',
                      style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 8),
                    ),
                  ],
                ),
                pw.Text(
                  'Start Date: ${AppDateFormatter.formatDate(record.startDate)} • ${AppDateFormatter.formatMonths(fin.months)}'
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
          pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.TableHelper.fromTextArray(
                  headers: [
                    'Collateral Item Details',
                    'Principal Taken',
                    'Interest Rate',
                    'Payable (${AppDateFormatter.formatMonths(fin.months)})',
                    'Total Due',
                  ],
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
                if (record.payments.isNotEmpty) ...[
                  pw.Text(
                    'Repayment History for ${AppIdFormatter.formatTransactionId(record.transactionId)}:',
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

/// Generates a full single-lender statement (§6.1 & §6.2b).
///
/// Features complete record details, payment history per record, interest breakdown, and totals.
/// The per-party statements carry no flag ([FIX-PDF-OVERDUEFLAG-1]).
LenderStatementReport generateLenderStatement(
  Lender lender,
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

  // Filter records belonging to this lender (TAKEN loans)
  final lenderRecords = records.where((r) => r.lenderId == lender.id && r.isTaken).toList();

  final lenderReports = CalculationEngine.getLenderReports(
    lenders: [lender],
    records: lenderRecords,
    today: targetDate,
  );
  final lenderReport = lenderReports.isNotEmpty ? lenderReports.first : null;

  double totalPrincipalTaken = 0.0;
  double totalInterestPayable = 0.0;
  double totalPaid = 0.0;
  double totalDueToLender = 0.0;
  int activeCount = 0;
  int settledCount = 0;

  for (final r in lenderRecords) {
    if (r.isActive) activeCount++;
    if (r.isSettled) settledCount++;

    final fin = CalculationEngine.calculateRecordFinancials(r, targetDate, targetDate);
    totalPrincipalTaken += r.principalAmount;
    totalInterestPayable += fin.totalInterest;
    totalPaid += fin.totalPaid;
    totalDueToLender += fin.totalDue;
  }

  return LenderStatementReport(
    lender: lender,
    records: lenderRecords,
    businessInfo: businessInfo,
    generatedDate: now,
    totalPrincipalTaken: totalPrincipalTaken,
    totalInterestPayable: totalInterestPayable,
    totalPaid: totalPaid,
    totalDueToLender: totalDueToLender,
    activeRecordCount: activeCount,
    settledRecordCount: settledCount,
    fonts: resolvedFonts,
    lenderReport: lenderReport,
  );
}

/// Data payload for background isolate Lender Statement PDF generation ([FIX-PDFBGTHREAD-1] & §6.3).
class LenderStatementJob {
  final Lender lender;
  final List<LedgerRecord> records;
  final BusinessInfo businessInfo;
  final PdfFonts? fonts;
  final DateTime? today;

  const LenderStatementJob(
    this.lender,
    this.records,
    this.businessInfo, [
    this.fonts,
    this.today,
  ]);
}

/// Pure top-level worker function executed on a background isolate via [compute] ([FIX-PDFBGTHREAD-1] & §6.3).
Future<Uint8List> buildLenderStatementBytes(LenderStatementJob job) async {
  final statement = generateLenderStatement(
    job.lender,
    job.records,
    job.businessInfo,
    job.fonts,
    job.today,
  );
  return statement.buildPdf(job.fonts);
}
