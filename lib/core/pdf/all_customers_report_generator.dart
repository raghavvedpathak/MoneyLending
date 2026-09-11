import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../domain/domain.dart';
import '../calculations/calculation_engine.dart';
import '../calculations/util/date_extensions.dart';
import '../utils/app_date_formatter.dart';

/// Aggregated Financial Report for all customers (§5.1, §5.5, §6.1 & [FIX-ARCH-PDFTEST-1]).
///
/// Output structure mandated by §6.1:
/// 1. Business header (from [businessInfo]).
/// 2. One row per customer in summary table: Customer Name, Customer ID (displayId),
///    Active Records (count), Total Principal Out, Total Interest Accrued, Total Due, Overdue Flag.
/// 3. Grand total row.
/// 4. Report footer: total customers, total active records, generated timestamp.
///
/// Captures customer breakdown along with grand totals matching `DashboardStats`
/// penny-for-penny to ensure PDF reports never drift from UI Dashboard screens.
class AllCustomersReport {
  final List<CustomerReport> customerReports;
  final List<bool> overdueFlags;
  final BusinessInfo businessInfo;
  final double totalPrincipal;
  final double totalInterestAccrued;
  final double totalDue;
  final int totalActiveRecords;
  final DateTime generatedDate;

  const AllCustomersReport({
    required this.customerReports,
    this.overdueFlags = const [],
    this.businessInfo = const BusinessInfo(),
    required this.totalPrincipal,
    required this.totalInterestAccrued,
    required this.totalDue,
    required this.totalActiveRecords,
    required this.generatedDate,
  });

  /// Generates the offline PDF document bytes using pure Dart / package:pdf.
  /// Fully independent of platform channels and 100% testable on JVM/VM.
  Future<Uint8List> buildPdf() async {
    final pdf = pw.Document();

    // Prepare table data rows with Overdue Flag
    final tableData = <List<String>>[];
    for (int i = 0; i < customerReports.length; i++) {
      final r = customerReports[i];
      final isOverdue = i < overdueFlags.length ? overdueFlags[i] : false;
      tableData.add([
        r.customer.name,
        r.customer.displayId,
        r.activeRecordCount.toString(),
        'Rs. ${r.totalPrincipal.toStringAsFixed(2)}',
        'Rs. ${r.totalInterestAccrued.toStringAsFixed(2)}',
        'Rs. ${r.totalDue.toStringAsFixed(2)}',
        isOverdue ? 'OVERDUE' : 'CURRENT',
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
                      'ALL CUSTOMERS FINANCIAL REPORT',
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
                  _buildMetricItem('Total Customers', '${customerReports.length}'),
                  _buildMetricItem('Active Loans', '$totalActiveRecords'),
                  _buildMetricItem('Total Principal', 'Rs. ${totalPrincipal.toStringAsFixed(2)}'),
                  _buildMetricItem('Accrued Interest', 'Rs. ${totalInterestAccrued.toStringAsFixed(2)}'),
                  _buildMetricItem('Total Due', 'Rs. ${totalDue.toStringAsFixed(2)}'),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // 2 & 3. Customer Summary Table with Grand Total row (§6.1)
            pw.TableHelper.fromTextArray(
              headers: [
                'Customer Name',
                'Customer ID',
                'Active Loans',
                'Principal Out',
                'Accrued Interest',
                'Total Due',
                'Status',
              ],
              data: tableData,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 8.5,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blueGrey800,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
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
                  'Customers: ${customerReports.length} | Active Loans: $totalActiveRecords | Generated: ${AppDateFormatter.formatDateTime(generatedDate)}',
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

    return pdf.save();
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

/// Generates AllCustomersReport aggregating customer-level rollups and overall totals (§5.5, §6.1).
///
/// Mandated by Business Logic Spec §5.5, §6.1 & [FIX-ARCH-PDFTEST-1]:
/// Must match monetary totals from `CalculationEngine.getDashboard()` penny-for-penny.
AllCustomersReport generateAllCustomersReport(
  List<Customer> customers,
  List<LedgerRecord> records, [
  Object? businessInfoOrDate,
  DateTime? today,
  Map<String, DateTime?>? latestPaymentDates,
]) {
  final BusinessInfo businessInfo = businessInfoOrDate is BusinessInfo
      ? businessInfoOrDate
      : const BusinessInfo();

  final DateTime? effectiveToday = businessInfoOrDate is DateTime
      ? businessInfoOrDate
      : today;

  final now = effectiveToday ?? DateTime.now();
  final todayDate = DateTime(now.year, now.month, now.day);
  final customerReports = CalculationEngine.getCustomerReport(customers, records, now);

  final totalPrincipal = customerReports.fold<double>(
    0.0,
    (sum, r) => sum + r.totalPrincipal,
  );
  final totalInterestAccrued = customerReports.fold<double>(
    0.0,
    (sum, r) => sum + r.totalInterestAccrued,
  );
  final totalDue = customerReports.fold<double>(
    0.0,
    (sum, r) => sum + r.totalDue,
  );
  final totalActiveRecords = customerReports.fold<int>(
    0,
    (sum, r) => sum + r.activeRecordCount,
  );

  // Compute overdue flags per customer (§6.1)
  final overdueFlags = customers.map((customer) {
    final activeGiven = records.where((r) => r.customerId == customer.id && r.isActive && r.isGiven);
    if (activeGiven.isEmpty) return false;

    for (final rec in activeGiven) {
      DateTime? lastActivity = latestPaymentDates != null ? latestPaymentDates[rec.id] : null;
      if (lastActivity == null && rec.payments.isNotEmpty) {
        // Fall back to most recent payment date
        DateTime? maxDate;
        for (final p in rec.payments) {
          if (maxDate == null || p.date.isAfter(maxDate)) {
            maxDate = p.date;
          }
        }
        lastActivity = maxDate;
      }
      lastActivity ??= rec.startDate;

      final lastActivityDate = DateTime(lastActivity.year, lastActivity.month, lastActivity.day);
      if (daysBetween(lastActivityDate, todayDate) > 30) {
        return true; // Overdue
      }
    }
    return false;
  }).toList();

  return AllCustomersReport(
    customerReports: customerReports,
    overdueFlags: overdueFlags,
    businessInfo: businessInfo,
    totalPrincipal: totalPrincipal,
    totalInterestAccrued: totalInterestAccrued,
    totalDue: totalDue,
    totalActiveRecords: totalActiveRecords,
    generatedDate: now,
  );
}
