import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/core.dart';
import 'package:money_lending/core/pdf/pdf.dart';
import 'package:money_lending/features/reports/reports.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  final testToday = DateTime(2026, 6, 1);

  final businessInfo = const BusinessInfo(
    name: 'Sri Krishna Finance & Jewel Loans',
    phone: '+91 98450 12345',
    address: '42 Main Bazaar, Bengaluru',
  );

  final customer1 = Customer(
    id: 'c-1',
    displayId: 'CUST-0001',
    name: 'Ramesh Sharma',
    phone: '9876543210',
    address: '12 Market Road',
    createdAt: DateTime(2026, 1, 1),
  );

  final customer2 = Customer(
    id: 'c-2',
    displayId: 'CUST-0002',
    name: 'Suresh Verma',
    phone: '9123456780',
    createdAt: DateTime(2026, 1, 15),
  );

  final itemGold = const LedgerItem(
    id: 'it-1',
    recordId: 'rec-1',
    name: 'Gold Necklace',
    itemCategory: 'GOLD_22K',
    weight: 20.0,
    purity: 91.6,
    rate: 6000.0,
  );

  final rec1 = LedgerRecord(
    id: 'rec-1',
    transactionId: 'TXN-000101',
    type: RecordType.GIVEN,
    customerId: 'c-1',
    customerName: 'Ramesh Sharma',
    startDate: DateTime(2026, 1, 1),
    principalAmount: 25000.0,
    interestRate: 2.0,
    status: RecordStatus.ACTIVE,
    items: [itemGold],
    payments: [
      Payment(
        id: 'pay-1',
        recordId: 'rec-1',
        amount: 1000.0,
        date: DateTime(2026, 2, 1),
        interestPaid: 500.0,
        principalPaid: 500.0,
        notes: 'First installment',
      ),
    ],
  );

  final rec2 = LedgerRecord(
    id: 'rec-2',
    transactionId: 'TXN-000102',
    type: RecordType.GIVEN,
    customerId: 'c-1',
    customerName: 'Ramesh Sharma',
    startDate: DateTime(2026, 2, 1),
    settledDate: DateTime(2026, 4, 1),
    principalAmount: 10000.0,
    interestRate: 2.0,
    status: RecordStatus.SETTLED,
    calculatedInterest: 400.0,
    payments: [
      Payment(
        id: 'pay-2',
        recordId: 'rec-2',
        amount: 10400.0,
        date: DateTime(2026, 4, 1),
        interestPaid: 400.0,
        principalPaid: 10000.0,
        notes: 'Full settlement',
      ),
    ],
  );

  final rec3 = LedgerRecord(
    id: 'rec-3',
    transactionId: 'TXN-000103',
    type: RecordType.GIVEN,
    customerId: 'c-2',
    customerName: 'Suresh Verma',
    startDate: DateTime(2026, 3, 1),
    principalAmount: 15000.0,
    interestRate: 1.5,
    status: RecordStatus.ACTIVE,
    payments: const [],
  );

  final customers = [customer1, customer2];
  final records = [rec1, rec2, rec3];

  group('PDF Generation & Structure (§6.1)', () {
    test('generateCustomerStatement builds full single-customer ledger report with PDF bytes', () async {
      final statement = generateCustomerStatement(
        customer1,
        records,
        businessInfo,
        testToday,
      );

      // Customer metadata
      expect(statement.customer.id, 'c-1');
      expect(statement.customer.name, 'Ramesh Sharma');
      expect(statement.customer.displayId, 'CUST-0001');
      expect(statement.businessInfo.name, 'Sri Krishna Finance & Jewel Loans');

      // Records belonging to customer1: rec1 (active) and rec2 (settled)
      expect(statement.records.length, 2);
      expect(statement.activeRecordCount, 1);
      expect(statement.settledRecordCount, 1);

      // Totals
      expect(statement.totalPrincipal, 35000.0); // 25k + 10k
      expect(statement.totalPaid, 11400.0); // 1,000 + 10,400

      // Financials breakdown
      expect(statement.totalInterestAccrued, greaterThan(0.0));
      expect(statement.totalDue, greaterThan(0.0));

      // PDF Document and byte generation (§6.1)
      final doc = statement.buildDocument();
      expect(doc, isNotNull);
      final pdfBytes = await statement.buildPdf();
      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(500));
      // Standard %PDF header
      expect(pdfBytes[0], 0x25); // %
      expect(pdfBytes[1], 0x50); // P
      expect(pdfBytes[2], 0x44); // D
      expect(pdfBytes[3], 0x46); // F
    });

    test('Customer statement adheres strictly to §6.2 output structure and [FIX-TIMESTAMP-PDF-1]', () async {
      // 1. Transaction ID header surfaced for every record row (e.g. TRAN092601)
      // 2. Exact timestamp formatted as "dd/MM/yyyy, HH:mm" on startDate (e.g. "23/04/2026, 14:30")
      // 3. Payment ID (e.g. PAY092601) and payment date with exact timestamp
      // 4. Customer ID format (e.g. CUST26-27-01)
      final customerWithFmt = customer1.copyWith(displayId: 'CUST26-27-01');
      final exactStart = DateTime(2026, 4, 23, 14, 30);
      final exactPaymentDate = DateTime(2026, 5, 10, 16, 45);

      final recWithExactTimes = LedgerRecord(
        id: 'rec-exact-time',
        transactionId: 'TRAN092601',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        customerName: 'Ramesh Sharma',
        startDate: exactStart,
        principalAmount: 30000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: [itemGold],
        payments: [
          Payment(
            id: 'pay-exact',
            paymentId: 'PAY092601',
            recordId: 'rec-exact-time',
            amount: 600.0,
            date: exactPaymentDate,
            interestPaid: 600.0,
            principalPaid: 0.0,
            notes: 'Monthly interest installment',
          ),
        ],
      );

      // Verify formatDate output per [FIX-TIMESTAMP-PDF-1] (revised v1.15):
      // Every date in the PDF is printed with formatDate() ("5 August 2026"); no times are printed.
      expect(AppDateFormatter.formatDate(exactStart), '23 April 2026');
      expect(AppDateFormatter.formatDate(exactPaymentDate), '10 May 2026');

      final statement = generateCustomerStatement(
        customerWithFmt,
        [recWithExactTimes],
        businessInfo,
        DateTime(2026, 6, 1),
      );

      expect(statement.customer.displayId, 'CUST26-27-01');
      expect(statement.records.first.transactionId, 'TRAN092601');
      expect(statement.records.first.payments.first.paymentId, 'PAY092601');
      expect(statement.records.first.payments.first.interestPaid, 600.0);
      expect(statement.totalPrincipal, 30000.0);
      expect(statement.totalInterestAccrued, greaterThan(0.0));
      expect(statement.totalDue, greaterThan(0.0));

      // Build Document and PDF
      final doc = statement.buildDocument();
      expect(doc, isNotNull);
      final pdfBytes = await statement.buildPdf();
      expect(pdfBytes.length, greaterThan(1000));
      expect(pdfBytes[0], 0x25); // %
      expect(pdfBytes[1], 0x50); // P
      expect(pdfBytes[2], 0x44); // D
      expect(pdfBytes[3], 0x46); // F
    });

    test('generateAllCustomersReport generates summary with business header, grand totals, and footer', () async {
      final report = generateAllCustomersReport(
        customers,
        records,
        businessInfo,
        testToday,
      );

      // 1. Business Header & metadata
      expect(report.businessInfo.name, 'Sri Krishna Finance & Jewel Loans');
      expect(report.businessInfo.phone, '+91 98450 12345');
      expect(report.businessInfo.address, '42 Main Bazaar, Bengaluru');
      expect(report.generatedDate, testToday);

      // 2. One row per customer with exact fields
      expect(report.customerReports.length, 2);
      final r1 = report.customerReports.firstWhere((c) => c.customer.id == 'c-1');
      expect(r1.customer.name, 'Ramesh Sharma');
      expect(r1.customer.displayId, 'CUST-0001');
      expect(r1.activeRecordCount, 1); // rec1 is active, rec2 is settled
      expect(r1.totalPrincipal, 25000.0);

      final r2 = report.customerReports.firstWhere((c) => c.customer.id == 'c-2');
      expect(r2.customer.name, 'Suresh Verma');
      expect(r2.customer.displayId, 'CUST-0002');
      expect(r2.activeRecordCount, 1);
      expect(r2.totalPrincipal, 15000.0);

      // Overdue flags
      expect(report.overdueFlags.length, 2);

      // 3. Grand Total values
      expect(report.totalPrincipal, 40000.0); // 25k + 15k
      expect(report.totalActiveRecords, 2);

      // 4. [FIX-ARCH-PDFTEST-1] Exact match with getDashboard()
      final dashboard = CalculationEngine.getDashboard(records, today: testToday);
      expect(report.totalPrincipal, equals(dashboard.totalPrincipalGiven));
      expect(report.totalInterestAccrued, equals(dashboard.totalInterestAccruedGiven));
      expect(report.totalDue, equals(dashboard.totalDueGiven));

      // 5. Offline PDF Document build (§6.1)
      final doc = report.buildDocument();
      expect(doc, isNotNull);
      final pdfBytes = await report.buildPdf();
      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(500));
      expect(pdfBytes[0], 0x25);
      expect(pdfBytes[1], 0x50);
      expect(pdfBytes[2], 0x44);
      expect(pdfBytes[3], 0x46);
    });

    test('generateCustomerStatement supports [FIX-PDF-FONT-1] PdfFonts signature', () async {
      final customFonts = PdfFonts(
        regular: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      );

      final statement = generateCustomerStatement(
        customer1,
        records,
        businessInfo,
        customFonts,
      );

      expect(statement.fonts, equals(customFonts));
      final theme = statement.fonts!.toTheme();
      expect(theme, isNotNull);

      final doc = statement.buildDocument();
      expect(doc, isNotNull);

      final bytes = await statement.buildPdf();
      expect(bytes.length, greaterThan(500));
      expect(bytes[0], 0x25); // %
    });

    test('generateAllCustomersReport supports [FIX-PDF-FONT-1] PdfFonts signature', () async {
      final customFonts = PdfFonts(
        regular: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      );

      final report = generateAllCustomersReport(
        customers,
        records,
        businessInfo,
        customFonts,
      );

      expect(report.fonts, equals(customFonts));
      final theme = report.fonts!.toTheme();
      expect(theme, isNotNull);

      final doc = report.buildDocument();
      expect(doc, isNotNull);

      final bytes = await report.buildPdf();
      expect(bytes.length, greaterThan(500));
      expect(bytes[0], 0x25); // %
    });
  });

  group('Reports Screen FAB Routing by Active Sub-Tab (§6.1)', () {
    test('Overview tab (index 0) displays FAB and routes to allCustomersReport', () {
      final vm = ReportsViewModel(initialTab: 0);

      expect(vm.activeSubTabIndex, 0);
      expect(vm.isFabVisible, isTrue, reason: 'FAB must be visible on Overview tab');
      expect(vm.currentFabAction, ReportsFabAction.allCustomersReport);

      vm.dispose();
    });

    test('Customer tab (index 1) hides FAB when no customer is selected', () {
      final vm = ReportsViewModel(initialTab: 1, initialCustomer: null);

      expect(vm.activeSubTabIndex, 1);
      expect(vm.selectedCustomer, isNull);
      expect(
        vm.isFabVisible,
        isFalse,
        reason: 'FAB must be HIDDEN (not just disabled) when no customer is selected in Customer tab',
      );
      expect(vm.currentFabAction, ReportsFabAction.none);

      vm.dispose();
    });

    test('Customer tab (index 1) displays FAB and routes to customerStatement when customer is selected', () {
      final vm = ReportsViewModel(initialTab: 1, initialCustomer: null);

      expect(vm.isFabVisible, isFalse);

      // User selects a customer
      vm.selectCustomer(customer1);

      expect(vm.selectedCustomer, equals(customer1));
      expect(vm.isFabVisible, isTrue, reason: 'FAB must become visible when customer is in context');
      expect(vm.currentFabAction, ReportsFabAction.customerStatement);

      // User clears selection
      vm.clearSelectedCustomer();
      expect(vm.isFabVisible, isFalse, reason: 'FAB must hide again when customer is cleared');
      expect(vm.currentFabAction, ReportsFabAction.none);

      vm.dispose();
    });

    test('Monthly tab (index 2) hides FAB regardless of customer selection', () {
      final vm = ReportsViewModel(initialTab: 2, initialCustomer: customer1);

      expect(vm.activeSubTabIndex, 2);
      expect(
        vm.isFabVisible,
        isFalse,
        reason: 'Monthly tab has no PDF action defined — FAB must be hidden',
      );
      expect(vm.currentFabAction, ReportsFabAction.none);

      vm.dispose();
    });

    test('Overdue tab (index 3) hides FAB regardless of customer selection', () {
      final vm = ReportsViewModel(initialTab: 3, initialCustomer: customer1);

      expect(vm.activeSubTabIndex, 3);
      expect(
        vm.isFabVisible,
        isFalse,
        reason: 'Overdue tab has no PDF action defined — FAB must be hidden',
      );
      expect(vm.currentFabAction, ReportsFabAction.none);

      vm.dispose();
    });

    test('Reactive state streams emit updates synchronously when switching tabs', () async {
      final vm = ReportsViewModel(initialTab: 0);

      final tabEvents = <int>[];
      final fabVisibleEvents = <bool>[];
      final fabActionEvents = <ReportsFabAction>[];

      final subTab = vm.activeSubTabStream.listen(tabEvents.add);
      final subFab = vm.isFabVisibleStream.listen(fabVisibleEvents.add);
      final subAction = vm.fabActionStream.listen(fabActionEvents.add);

      // 1. Switch to Customer tab without selected customer
      vm.setActiveSubTab(1);
      expect(vm.activeSubTabIndex, 1);
      expect(vm.isFabVisible, isFalse);

      // 2. Select customer
      vm.selectCustomer(customer1);
      expect(vm.isFabVisible, isTrue);
      expect(vm.currentFabAction, ReportsFabAction.customerStatement);

      // 3. Switch to Monthly tab (index 2)
      vm.setActiveSubTab(2);
      expect(vm.isFabVisible, isFalse);

      // 4. Switch to Overdue tab (index 3)
      vm.setActiveSubTab(3);
      expect(vm.isFabVisible, isFalse);

      // 5. Switch back to Overview tab (index 0)
      vm.setActiveSubTab(0);
      expect(vm.isFabVisible, isTrue);
      expect(vm.currentFabAction, ReportsFabAction.allCustomersReport);

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(tabEvents, [1, 2, 3, 0]);
      expect(fabVisibleEvents.contains(true), isTrue);
      expect(fabVisibleEvents.contains(false), isTrue);

      await subTab.cancel();
      await subFab.cancel();
      await subAction.cancel();
      vm.dispose();
    });

    test('ReportsNotifier alias and getFabTapHandler correctly routes callbacks (§6.1)', () async {
      final notifier = ReportsNotifier(initialTab: 0);

      bool allCustomersTapped = false;
      bool customerStatementTapped = false;

      // 1. Overview tab: tap handler is non-null and triggers allCustomersReport
      var handler = notifier.getFabTapHandler(
        onAllCustomersReport: () async {
          allCustomersTapped = true;
        },
        onCustomerStatement: (c) async {
          customerStatementTapped = true;
        },
      );
      expect(handler, isNotNull);
      await handler!();
      expect(allCustomersTapped, isTrue);

      // 2. Customer tab without selection: handler is null
      notifier.activeSubTabIndex = 1;
      notifier.selectedCustomer = null;
      expect(notifier.isFabVisible, isFalse);
      expect(
        notifier.getFabTapHandler(
          onAllCustomersReport: () async {},
          onCustomerStatement: (c) async {},
        ),
        isNull,
      );

      // 3. Customer tab with selection: handler routes to onCustomerStatement with selectedCustomer
      notifier.selectedCustomer = customer1;
      expect(notifier.isFabVisible, isTrue);
      handler = notifier.getFabTapHandler(
        onAllCustomersReport: () async {},
        onCustomerStatement: (c) async {
          expect(c.id, customer1.id);
          customerStatementTapped = true;
        },
      );
      expect(handler, isNotNull);
      await handler!();
      expect(customerStatementTapped, isTrue);

      // 4. Monthly tab (index 2): handler is null
      notifier.activeSubTabIndex = 2;
      expect(notifier.isFabVisible, isFalse);
      expect(
        notifier.getFabTapHandler(
          onAllCustomersReport: () async {},
          onCustomerStatement: (c) async {},
        ),
        isNull,
      );

      // 5. Overdue tab (index 3): handler is null
      notifier.activeSubTabIndex = 3;
      expect(notifier.isFabVisible, isFalse);
      expect(
        notifier.getFabTapHandler(
          onAllCustomersReport: () async {},
          onCustomerStatement: (c) async {},
        ),
        isNull,
      );

      notifier.dispose();
    });
  });

  group('PDF Background Generation & Sharing Pipeline (§6.3)', () {
    test('compute(buildStatementBytes, StatementJob(...)) produces PDF bytes on background isolate [FIX-PDFBGTHREAD-1]', () async {
      final job = StatementJob(
        customer1,
        records,
        businessInfo,
        null,
        testToday,
      );

      final bytes = await compute(buildStatementBytes, job);

      expect(bytes, isNotNull);
      expect(bytes.length, greaterThan(500));
      // %PDF header
      expect(bytes[0], 0x25);
      expect(bytes[1], 0x50);
      expect(bytes[2], 0x44);
      expect(bytes[3], 0x46);
    });

    test('compute(buildAllCustomersBytes, AllCustomersJob(...)) produces PDF bytes on background isolate [FIX-PDFBGTHREAD-1]', () async {
      final job = AllCustomersJob(
        customers,
        records,
        businessInfo,
        null,
        testToday,
      );

      final bytes = await compute(buildAllCustomersBytes, job);

      expect(bytes, isNotNull);
      expect(bytes.length, greaterThan(500));
      expect(bytes[0], 0x25);
      expect(bytes[1], 0x50);
      expect(bytes[2], 0x44);
      expect(bytes[3], 0x46);
    });

    test('PdfShareService saves PDF to temp dir under pdfs/ matching §6.3 file path specification', () async {
      final tempDir = Directory.systemTemp.createTempSync('pdf_share_test_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final shareService = PdfShareService(overrideDirectory: tempDir);
      final dummyBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x31]); // %PDF1
      final fileName = '${customer1.displayId}_statement.pdf';

      final savedFile = await shareService.savePdfFile(
        bytes: dummyBytes,
        fileName: fileName,
      );

      expect(savedFile.existsSync(), isTrue);
      expect(savedFile.path.replaceAll('\\', '/'), endsWith('pdfs/${customer1.displayId}_statement.pdf'));
      expect(savedFile.readAsBytesSync(), equals(dummyBytes));
    });

    test('loadPdfFonts is exported and callable on UI isolate per [FIX-PDF-FONT-1] & §6.3', () {
      expect(loadPdfFonts, isA<Function>());
    });
  });
}
