import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../domain/domain.dart';
import '../calculations/calculation_engine.dart';
import '../calculations/util/date_extensions.dart';
import '../utils/app_date_formatter.dart';
import 'pdf_fonts.dart';

/// Aggregated Financial Report for all Borrowers (§5.1, §5.5, §6.1, [FIX-ARCH-PDFTEST-1], [FIX-PDF-OVERDUEFLAG-1]).
///
/// Output structure mandated by §6.1:
/// 1. Business header (from [businessInfo]).
/// 2. One row per customer in summary table: Customer Name, Customer ID (displayId),
///    Active Records (count), Total Principal Out, Total Interest Accrued, Total Due to You, Overdue Flag.
/// 3. Grand total row.
/// 4. Report footer: total customers, total active records, generated timestamp.
///
/// Captures customer breakdown along with grand totals matching `DashboardStats`
/// penny-for-penny to ensure PDF reports never drift from UI Dashboard screens.
class AllBorrowersReport {
  final List<BorrowerReport> borrowerReports;
  final Set<String> overdueRecordIds;
  final List<LedgerRecord> records;
  final BusinessInfo businessInfo;
  final double totalPrincipal;
  final double totalInterestAccrued;
  final double totalDue;
  final int totalActiveRecords;
  final DateTime generatedDate;
  final PdfFonts? fonts;

  const AllBorrowersReport({
    required this.borrowerReports,
    this.overdueRecordIds = const <String>{},
    this.records = const [],
    this.businessInfo = const BusinessInfo(),
    required this.totalPrincipal,
    required this.totalInterestAccrued,
    required this.totalDue,
    required this.totalActiveRecords,
    required this.generatedDate,
    this.fonts,
  });

  /// Compatibility getter for legacy callers
  List<CustomerReport> get customerReports => borrowerReports
      .map((b) => CustomerReport(
            customer: b.customer,
            activeRecordCount: b.activeRecordCount,
            totalPrincipal: b.totalPrincipalOut,
            totalInterestAccrued: b.totalInterestAccrued,
            totalDue: b.totalDue,
          ))
      .toList();

  /// Compatibility getter for overdue flags list
  List<bool> get overdueFlags => borrowerReports.map((b) =>
      records.any((r) =>
          r.customerId == b.customer.id &&
          r.isActive &&
          r.isGiven &&
          overdueRecordIds.contains(r.id))).toList();

  /// Builds the [pw.Document] widget tree for all borrowers report (§6.1).
  pw.Document buildDocument([PdfFonts? overrideFonts]) {
    final effectiveFonts = overrideFonts ?? fonts;
    final pdf = pw.Document(theme: effectiveFonts?.toTheme());

    // Prepare table data rows with Overdue Flag [FIX-PDF-OVERDUEFLAG-1]
    final tableData = <List<String>>[];
    for (int i = 0; i < borrowerReports.length; i++) {
      final b = borrowerReports[i];
      final hasOverdue = records.any((r) =>
          r.customerId == b.customer.id &&
          r.isActive &&
          r.isGiven &&
          overdueRecordIds.contains(r.id));
      final overdueFlag = hasOverdue ? 'Yes' : '—';

      tableData.add([
        b.customer.name,
        b.customer.displayId,
        b.activeRecordCount.toString(),
        'Rs. ${b.totalPrincipalOut.toStringAsFixed(2)}',
        'Rs. ${b.totalInterestAccrued.toStringAsFixed(2)}',
        'Rs. ${b.totalDue.toStringAsFixed(2)}',
        overdueFlag,
      ]);
    }

    // Grand Total row (§6.1)
    tableData.add([
      'GRAND TOTAL',
      '-',
      totalActiveRecords.toString(),
      'Rs. ${totalPrincipal.toStringAsFixed(2)}',
      'Rs. ${totalInterestAccrued.toStringAsFixed(2)}',
      'Rs. ${totalDue.toStringAsFixed(2)}',
      '-',
    ]);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // 1. Business Header (§6.1)
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
                    if (businessInfo.address.isNotEmpty)
                      pw.Text(
                        businessInfo.address,
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                      ),
                    if (businessInfo.phone.isNotEmpty)
                      pw.Text(
                        'Phone: ${businessInfo.phone}',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                      ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'ALL BORROWERS REPORT',
                      style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blueGrey800,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Date: ${AppDateFormatter.formatDate(generatedDate)}',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ],
            ),
            pw.Divider(thickness: 1, color: PdfColors.grey400),
            pw.SizedBox(height: 8),

            // Summary Metrics Card
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _buildMetricItem('Total Borrowers', '${borrowerReports.length}'),
                  _buildMetricItem('Active Loans', '$totalActiveRecords'),
                  _buildMetricItem('Total Principal Out', 'Rs. ${totalPrincipal.toStringAsFixed(2)}'),
                  _buildMetricItem('Accrued Interest', 'Rs. ${totalInterestAccrued.toStringAsFixed(2)}'),
                  _buildMetricItem('Total Due to You', 'Rs. ${totalDue.toStringAsFixed(2)}'),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // 2 & 3. Summary Table with Grand Total row (§6.1)
            pw.TableHelper.fromTextArray(
              headers: [
                'Customer Name',
                'Customer ID (displayId)',
                'Active Records (count)',
                'Total Principal Out',
                'Total Interest Accrued',
                'Total Due to You',
                'Overdue Flag',
              ],
              data: tableData,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 8,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blueGrey800,
              ),
              cellStyle: const pw.TextStyle(fontSize: 7.5),
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.center,
              },
            ),
          ];
        },
        // 4. Report Footer (§6.1)
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
                  'Total Customers: ${borrowerReports.length} | Total Active Records: $totalActiveRecords | Generated: ${AppDateFormatter.formatDate(generatedDate)}',
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

  /// Generates the offline PDF document bytes using pure Dart / package:pdf.
  Future<Uint8List> buildPdf([PdfFonts? overrideFonts]) async {
    return buildDocument(overrideFonts).save();
  }

  static pw.Widget _buildMetricItem(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }
}

/// Backwards-compatibility alias for [AllBorrowersReport] (§6.1).
typedef AllCustomersReport = AllBorrowersReport;

/// Generates AllBorrowersReport aggregating borrower-level rollups and overall totals (§5.5, §6.1).
///
/// Mandated by Business Logic Spec §5.5, §6.1, [FIX-ARCH-PDFTEST-1] & [FIX-PDF-OVERDUEFLAG-1]:
/// - Must match monetary totals from `CalculationEngine.getDashboard()` and `getBorrowerReports()` exactly.
/// - Overdue flag: "Yes" when party has >= 1 active record in [overdueRecordIds], else "—".
AllBorrowersReport generateAllBorrowersReport(
  List<Customer> customers,
  List<LedgerRecord> records, [
  Object? arg3,
  Object? arg4,
  Object? arg5,
  Object? arg6,
]) {
  Set<String> overdueRecordIds = const <String>{};
  BusinessInfo businessInfo = const BusinessInfo();
  DateTime? today;
  PdfFonts? resolvedFonts;

  for (final arg in [arg3, arg4, arg5, arg6]) {
    if (arg is Set<String>) {
      overdueRecordIds = arg;
    } else if (arg is BusinessInfo) {
      businessInfo = arg;
    } else if (arg is DateTime) {
      today = arg;
    } else if (arg is PdfFonts) {
      resolvedFonts = arg;
    }
  }

  final now = today ?? DateTime.now();
  final todayDate = now.dateOnly;

  // Use calculation engine functions (§5.5 [FIX-ARCH-PDFTEST-1])
  final borrowerReports = CalculationEngine.getBorrowerReports(
    customers: customers,
    records: records,
    today: todayDate,
  );

  final dashboard = CalculationEngine.getDashboard(records, today: todayDate);
  final totalActiveRecords = records.where((r) => r.isActive && r.isGiven).length;

  return AllBorrowersReport(
    borrowerReports: borrowerReports,
    overdueRecordIds: overdueRecordIds,
    records: records,
    businessInfo: businessInfo,
    totalPrincipal: dashboard.totalPrincipalGiven,
    totalInterestAccrued: dashboard.totalInterestAccruedGiven,
    totalDue: dashboard.totalDueGiven,
    totalActiveRecords: totalActiveRecords,
    generatedDate: now,
    fonts: resolvedFonts,
  );
}

/// Backwards-compatibility alias for [generateAllBorrowersReport].
AllCustomersReport generateAllCustomersReport(
  List<Customer> customers,
  List<LedgerRecord> records, [
  Object? arg3,
  Object? arg4,
  Object? arg5,
  Object? arg6,
]) =>
    generateAllBorrowersReport(customers, records, arg3, arg4, arg5, arg6);

/// Data payload for background isolate All Borrowers PDF generation ([FIX-PDFBGTHREAD-1] & §6.3).
class AllBorrowersJob {
  final List<Customer> customers;
  final List<LedgerRecord> records;
  final Set<String> overdueRecordIds;
  final BusinessInfo businessInfo;
  final PdfFonts? fonts;
  final DateTime? today;

  const AllBorrowersJob(
    this.customers,
    this.records, [
    this.businessInfo = const BusinessInfo(),
    this.fonts,
    this.today,
    this.overdueRecordIds = const <String>{},
  ]);
}

/// Backwards-compatibility alias for [AllBorrowersJob].
typedef AllCustomersJob = AllBorrowersJob;

/// Pure top-level worker function executed on a background isolate via [compute] ([FIX-PDFBGTHREAD-1] & §6.3).
Future<Uint8List> buildAllBorrowersBytes(AllBorrowersJob job) async {
  final report = generateAllBorrowersReport(
    job.customers,
    job.records,
    job.overdueRecordIds,
    job.businessInfo,
    job.fonts,
    job.today,
  );
  return report.buildPdf(job.fonts);
}

/// Backwards-compatibility alias for [buildAllBorrowersBytes].
Future<Uint8List> buildAllCustomersBytes(AllCustomersJob job) =>
    buildAllBorrowersBytes(job);

/// Aggregated Financial Report for all lenders (§5.1, §5.5, §6.1, [FIX-ARCH-PDFTEST-1], [FIX-PDF-OVERDUEFLAG-1]).
///
/// Output structure:
/// 1. Business header.
/// 2. Summary table: Lender Name, Lender ID (displayId), Lender Type (Individual/Institution),
///    Active Records (count), Total Principal Taken, Total Interest Payable, Total Due to Lender, Overdue Flag.
/// 3. Grand total row.
/// 4. Report footer: total lenders, total active records, generated timestamp.
class AllLendersReport {
  final List<LenderReport> lenderReports;
  final Set<String> overdueRecordIds;
  final List<LedgerRecord> records;
  final BusinessInfo businessInfo;
  final double totalPrincipal;
  final double totalInterestAccrued;
  final double totalDue;
  final int totalActiveRecords;
  final DateTime generatedDate;
  final PdfFonts? fonts;

  const AllLendersReport({
    required this.lenderReports,
    this.overdueRecordIds = const <String>{},
    this.records = const [],
    this.businessInfo = const BusinessInfo(),
    required this.totalPrincipal,
    required this.totalInterestAccrued,
    required this.totalDue,
    required this.totalActiveRecords,
    required this.generatedDate,
    this.fonts,
  });

  Future<Uint8List> buildPdf([PdfFonts? overrideFonts]) async {
    final doc = buildDocument(overrideFonts);
    return doc.save();
  }

  pw.Document buildDocument([PdfFonts? overrideFonts]) {
    final effectiveFonts = overrideFonts ?? fonts;
    final pdf = pw.Document(theme: effectiveFonts?.toTheme());

    final tableData = <List<String>>[];
    for (int i = 0; i < lenderReports.length; i++) {
      final r = lenderReports[i];
      final hasOverdue = records.any((rec) =>
          rec.lenderId == r.lender.id &&
          rec.isActive &&
          rec.isTaken &&
          overdueRecordIds.contains(rec.id));
      final overdueFlag = hasOverdue ? 'Yes' : '—';

      tableData.add([
        r.lender.name,
        r.lender.displayId,
        r.lender.lenderType.displayName,
        r.activeRecordCount.toString(),
        'Rs. ${r.totalPrincipalTaken.toStringAsFixed(2)}',
        'Rs. ${r.totalInterestPayable.toStringAsFixed(2)}',
        'Rs. ${r.totalDueToLender.toStringAsFixed(2)}',
        overdueFlag,
      ]);
    }

    // Grand total row (§6.1)
    tableData.add([
      'GRAND TOTAL',
      '-',
      '-',
      totalActiveRecords.toString(),
      'Rs. ${totalPrincipal.toStringAsFixed(2)}',
      'Rs. ${totalInterestAccrued.toStringAsFixed(2)}',
      'Rs. ${totalDue.toStringAsFixed(2)}',
      '-',
    ]);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // 1. Business Header (§6.1)
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    businessInfo.name.isNotEmpty ? businessInfo.name : 'Money Lending',
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                  ),
                  if (businessInfo.address.isNotEmpty)
                    pw.Text(businessInfo.address, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                  if (businessInfo.phone.isNotEmpty)
                    pw.Text('Phone: ${businessInfo.phone}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'ALL LENDERS REPORT',
                    style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Date: ${AppDateFormatter.formatDate(generatedDate)}',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                  ),
                ],
              ),
            ],
          ),
          pw.Divider(thickness: 1, color: PdfColors.grey400),
          pw.SizedBox(height: 8),

          // Summary Metrics Card
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildMetricItem('Total Lenders', '${lenderReports.length}'),
                _buildMetricItem('Active Loans Taken', '$totalActiveRecords'),
                _buildMetricItem('Total Principal Taken', 'Rs. ${totalPrincipal.toStringAsFixed(2)}'),
                _buildMetricItem('Interest Payable', 'Rs. ${totalInterestAccrued.toStringAsFixed(2)}'),
                _buildMetricItem('Total Due to Lender', 'Rs. ${totalDue.toStringAsFixed(2)}'),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // 2 & 3. Summary Table with Grand Total row (§6.1)
          pw.TableHelper.fromTextArray(
            headers: [
              'Lender Name',
              'Lender ID (displayId)',
              'Lender Type (Individual/Institution)',
              'Active Records (count)',
              'Total Principal Taken',
              'Total Interest Payable',
              'Total Due to Lender',
              'Overdue Flag',
            ],
            data: tableData,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellStyle: const pw.TextStyle(fontSize: 7),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.centerRight,
              7: pw.Alignment.center,
            },
          ),
        ],
        // 4. Report Footer (§6.1)
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
                  'Total Lenders: ${lenderReports.length} | Total Active Records: $totalActiveRecords | Generated: ${AppDateFormatter.formatDate(generatedDate)}',
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

  static pw.Widget _buildMetricItem(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        pw.SizedBox(height: 4),
        pw.Text(value, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }
}

/// Generates All Lenders PDF Report model matching §5.1, §5.5, §6.1, [FIX-ARCH-PDFTEST-1] & [FIX-PDF-OVERDUEFLAG-1].
AllLendersReport generateAllLendersReport(
  List<Lender> lenders,
  List<LedgerRecord> records, [
  Object? arg3,
  Object? arg4,
  Object? arg5,
  Object? arg6,
]) {
  Set<String> overdueRecordIds = const <String>{};
  BusinessInfo businessInfo = const BusinessInfo();
  DateTime? today;
  PdfFonts? resolvedFonts;

  for (final arg in [arg3, arg4, arg5, arg6]) {
    if (arg is Set<String>) {
      overdueRecordIds = arg;
    } else if (arg is BusinessInfo) {
      businessInfo = arg;
    } else if (arg is DateTime) {
      today = arg;
    } else if (arg is PdfFonts) {
      resolvedFonts = arg;
    }
  }

  final now = today ?? DateTime.now();
  final todayDate = now.dateOnly;

  // Use calculation engine functions (§5.5 [FIX-ARCH-PDFTEST-1])
  final lenderReports = CalculationEngine.getLenderReports(
    lenders: lenders,
    records: records,
    today: todayDate,
  );

  final dashboard = CalculationEngine.getDashboard(records, today: todayDate);
  final totalActiveRecords = records.where((r) => r.isActive && r.isTaken).length;

  return AllLendersReport(
    lenderReports: lenderReports,
    overdueRecordIds: overdueRecordIds,
    records: records,
    businessInfo: businessInfo,
    totalPrincipal: dashboard.totalPrincipalTaken,
    totalInterestAccrued: dashboard.totalInterestAccruedTaken,
    totalDue: dashboard.totalDueTaken,
    totalActiveRecords: totalActiveRecords,
    generatedDate: now,
    fonts: resolvedFonts,
  );
}

/// Data payload for background isolate All Lenders PDF generation ([FIX-PDFBGTHREAD-1] & §6.3).
class AllLendersJob {
  final List<Lender> lenders;
  final List<LedgerRecord> records;
  final Set<String> overdueRecordIds;
  final BusinessInfo businessInfo;
  final PdfFonts? fonts;
  final DateTime? today;

  const AllLendersJob(
    this.lenders,
    this.records, [
    this.businessInfo = const BusinessInfo(),
    this.fonts,
    this.today,
    this.overdueRecordIds = const <String>{},
  ]);
}

/// Pure top-level worker function executed on a background isolate via [compute] ([FIX-PDFBGTHREAD-1] & §6.3).
Future<Uint8List> buildAllLendersBytes(AllLendersJob job) async {
  final report = generateAllLendersReport(
    job.lenders,
    job.records,
    job.overdueRecordIds,
    job.businessInfo,
    job.fonts,
    job.today,
  );
  return report.buildPdf(job.fonts);
}
