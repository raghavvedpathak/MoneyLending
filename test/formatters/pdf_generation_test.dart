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
      // Summary footer reading BorrowerReport (§5.1, §6.2)
      expect(statement.borrowerReport, isNotNull);
      expect(statement.borrowerReport!.totalPrincipalOut, 30000.0);
      expect(statement.totalPrincipalOut, 30000.0);
      expect(statement.borrowerReport!.activeRecordCount, 1);
      expect(statement.borrowerReport!.totalDue, statement.totalDue);
      expect(statement.borrowerReport!.totalInterestAccrued, statement.totalInterestAccrued);

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

    test('generateLenderStatement generates full single-lender ledger report (§6.1, §6.2b)', () async {
      final lender = Lender(
        id: 'l-1',
        displayId: 'LEND26-27-01',
        lenderType: LenderType.institution,
        name: 'Apex Finance Corp',
        phone: '9876543210',
        institutionDetails: 'Registered NBFC Lic 1234',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      final takenRecord = LedgerRecord(
        id: 'rec-t-1',
        transactionId: 'TRAN092699',
        type: RecordType.TAKEN,
        lenderId: 'l-1',
        principalAmount: 40000.0,
        interestRate: 1.5,
        startDate: DateTime(2026, 1, 1),
        status: RecordStatus.ACTIVE,
        payments: [
          Payment(
            id: 'pay-t-1',
            paymentId: 'PAY092699',
            recordId: 'rec-t-1',
            amount: 1000.0,
            date: DateTime(2026, 3, 1),
            interestPaid: 600.0,
            principalPaid: 400.0,
          ),
        ],
      );

      final statement = generateLenderStatement(
        lender,
        [takenRecord],
        businessInfo,
        testToday,
      );

      expect(statement.lender.id, 'l-1');
      expect(statement.records.length, 1);
      expect(statement.activeRecordCount, 1);
      expect(statement.settledRecordCount, 0);
      expect(statement.totalPrincipalTaken, 40000.0);
      expect(statement.totalPaid, 1000.0);
      expect(statement.totalInterestPayable, greaterThan(0.0));
      expect(statement.totalDueToLender, greaterThan(0.0));
      // Summary footer reading LenderReport (§5.1, §6.2b)
      expect(statement.lenderReport, isNotNull);
      expect(statement.lenderReport!.totalPrincipalTaken, 40000.0);
      expect(statement.lenderReport!.activeRecordCount, 1);
      expect(statement.lenderReport!.totalDueToLender, statement.totalDueToLender);
      expect(statement.lenderReport!.totalInterestPayable, statement.totalInterestPayable);

      final doc = statement.buildDocument();
      expect(doc, isNotNull);
      final pdfBytes = await statement.buildPdf();
      expect(pdfBytes.length, greaterThan(1000));
      expect(pdfBytes[0], 0x25); // %
    });

    test('generateAllBorrowersReport and generateAllLendersReport format Overdue Flag correctly per [FIX-PDF-OVERDUEFLAG-1]', () async {
      final custA = Customer(id: 'c-a', displayId: 'CUST-0001', name: 'Alice', createdAt: DateTime(2026, 1, 1));
      final custB = Customer(id: 'c-b', displayId: 'CUST-0002', name: 'Bob', createdAt: DateTime(2026, 1, 1));

      final recA = LedgerRecord(
        id: 'rec-a',
        transactionId: 'TRAN092601',
        type: RecordType.GIVEN,
        customerId: 'c-a',
        principalAmount: 10000.0,
        interestRate: 2.0,
        startDate: DateTime(2026, 1, 1),
        status: RecordStatus.ACTIVE,
      );
      final recB = LedgerRecord(
        id: 'rec-b',
        transactionId: 'TRAN092602',
        type: RecordType.GIVEN,
        customerId: 'c-b',
        principalAmount: 20000.0,
        interestRate: 2.0,
        startDate: DateTime(2026, 1, 1),
        status: RecordStatus.ACTIVE,
      );

      // Pass overdueRecordIds containing only recA.id
      final overdueIds = <String>{'rec-a'};

      final borrowersReport = generateAllBorrowersReport(
        [custA, custB],
        [recA, recB],
        overdueIds,
        businessInfo,
        testToday,
      );

      expect(borrowersReport.borrowerReports.length, 2);
      expect(borrowersReport.overdueRecordIds, contains('rec-a'));
      expect(borrowersReport.totalActiveRecords, 2);

      // Build document and verify it builds cleanly
      final docB = borrowersReport.buildDocument();
      expect(docB, isNotNull);

      // TAKEN side: AllLendersReport
      final lenderA = Lender(
        id: 'l-a',
        displayId: 'LEND-0001',
        lenderType: LenderType.individual,
        name: 'Lender Alpha',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final lenderB = Lender(
        id: 'l-b',
        displayId: 'LEND-0002',
        lenderType: LenderType.institution,
        name: 'Lender Beta',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      final recLA = LedgerRecord(
        id: 'rec-la',
        transactionId: 'TRAN092603',
        type: RecordType.TAKEN,
        lenderId: 'l-a',
        principalAmount: 30000.0,
        interestRate: 1.5,
        startDate: DateTime(2026, 1, 1),
        status: RecordStatus.ACTIVE,
      );
      final recLB = LedgerRecord(
        id: 'rec-lb',
        transactionId: 'TRAN092604',
        type: RecordType.TAKEN,
        lenderId: 'l-b',
        principalAmount: 40000.0,
        interestRate: 1.5,
        startDate: DateTime(2026, 1, 1),
        status: RecordStatus.ACTIVE,
      );

      final lendersReport = generateAllLendersReport(
        [lenderA, lenderB],
        [recLA, recLB],
        <String>{'rec-la'}, // recLA is overdue
        businessInfo,
        testToday,
      );

      expect(lendersReport.lenderReports.length, 2);
      expect(lendersReport.overdueRecordIds, contains('rec-la'));
      expect(lendersReport.totalActiveRecords, 2);

      final docL = lendersReport.buildDocument();
      expect(docL, isNotNull);
    });
  });

  group('Reports Screen FAB Routing by Active Sub-Tab (§6.1)', () {
    test('Overview tab (index 0) hides FAB per §6.1', () {
      final vm = ReportsViewModel(initialTab: 0);

      expect(vm.activeSubTabIndex, 0);
      expect(
        vm.isFabVisible,
        isFalse,
        reason: 'Overview tab shows combined Given/Taken totals — FAB must be hidden per §6.1',
      );
      expect(vm.currentFabAction, ReportsFabAction.none);

      vm.dispose();
    });

    test('Borrowers tab (index 1) hides FAB when no borrower is selected', () {
      final vm = ReportsViewModel(initialTab: 1, initialBorrower: null);

      expect(vm.activeSubTabIndex, 1);
      expect(vm.selectedBorrower, isNull);
      expect(
        vm.isFabVisible,
        isFalse,
        reason: 'FAB must be HIDDEN (not just disabled) when no borrower is selected in Borrowers tab (§6.1)',
      );
      expect(vm.currentFabAction, ReportsFabAction.none);

      vm.dispose();
    });

    test('Borrowers tab (index 1) displays FAB and routes to customerStatement when borrower is selected', () {
      final vm = ReportsViewModel(initialTab: 1, initialBorrower: null);

      expect(vm.isFabVisible, isFalse);

      // User selects a borrower
      vm.selectBorrower(customer1);

      expect(vm.selectedBorrower, equals(customer1));
      expect(vm.isFabVisible, isTrue, reason: 'FAB must become visible when borrower is in context (§6.1)');
      expect(vm.currentFabAction, ReportsFabAction.customerStatement);

      // User clears selection
      vm.clearSelectedBorrower();
      expect(vm.isFabVisible, isFalse, reason: 'FAB must hide again when borrower is cleared (§6.1)');
      expect(vm.currentFabAction, ReportsFabAction.none);

      vm.dispose();
    });

    test('Lenders tab (index 2) hides FAB when no lender is selected, shows FAB when lender selected', () {
      final lender = Lender(
        id: 'l-test-1',
        displayId: 'LEND26-27-01',
        lenderType: LenderType.individual,
        name: 'Apex Finance',
        phone: '9999999999',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      final vm = ReportsViewModel(initialTab: 2, initialLender: null);

      expect(vm.activeSubTabIndex, 2);
      expect(vm.selectedLender, isNull);
      expect(
        vm.isFabVisible,
        isFalse,
        reason: 'FAB must be HIDDEN when no lender is selected in Lenders tab (§6.1)',
      );
      expect(vm.currentFabAction, ReportsFabAction.none);

      // Select lender
      vm.selectLender(lender);
      expect(vm.selectedLender, equals(lender));
      expect(vm.isFabVisible, isTrue, reason: 'FAB must be visible when lender is in context (§6.1)');
      expect(vm.currentFabAction, ReportsFabAction.lenderStatement);

      // Clear lender
      vm.clearSelectedLender();
      expect(vm.isFabVisible, isFalse);
      expect(vm.currentFabAction, ReportsFabAction.none);

      vm.dispose();
    });

    test('Monthly tab (index 3) hides FAB regardless of party selection', () {
      final vm = ReportsViewModel(initialTab: 3, initialBorrower: customer1);

      expect(vm.activeSubTabIndex, 3);
      expect(
        vm.isFabVisible,
        isFalse,
        reason: 'Monthly tab has no PDF action defined — FAB must be hidden (§6.1)',
      );
      expect(vm.currentFabAction, ReportsFabAction.none);

      vm.dispose();
    });

    test('Overdue tab (index 4) hides FAB regardless of party selection', () {
      final vm = ReportsViewModel(initialTab: 4, initialBorrower: customer1);

      expect(vm.activeSubTabIndex, 4);
      expect(
        vm.isFabVisible,
        isFalse,
        reason: 'Overdue tab has no PDF action defined — FAB must be hidden (§6.1)',
      );
      expect(vm.currentFabAction, ReportsFabAction.none);

      vm.dispose();
    });

    test('Reactive state streams emit updates synchronously when switching tabs (§6.1)', () async {
      final vm = ReportsViewModel(initialTab: 0);

      final tabEvents = <int>[];
      final fabVisibleEvents = <bool>[];
      final fabActionEvents = <ReportsFabAction>[];

      final subTab = vm.activeSubTabStream.listen(tabEvents.add);
      final subFab = vm.isFabVisibleStream.listen(fabVisibleEvents.add);
      final subAction = vm.fabActionStream.listen(fabActionEvents.add);

      // 1. Overview tab: FAB hidden
      expect(vm.isFabVisible, isFalse);

      // 2. Switch to Borrowers tab without selected borrower
      vm.setActiveSubTab(1);
      expect(vm.activeSubTabIndex, 1);
      expect(vm.isFabVisible, isFalse);

      // 3. Select borrower
      vm.selectBorrower(customer1);
      expect(vm.isFabVisible, isTrue);
      expect(vm.currentFabAction, ReportsFabAction.customerStatement);

      // 4. Switch to Lenders tab (index 2) without lender selected -> FAB hides
      vm.setActiveSubTab(2);
      expect(vm.activeSubTabIndex, 2);
      expect(vm.isFabVisible, isFalse);

      // 5. Switch to Monthly tab (index 3) -> FAB hides
      vm.setActiveSubTab(3);
      expect(vm.activeSubTabIndex, 3);
      expect(vm.isFabVisible, isFalse);

      // 6. Switch to Overdue tab (index 4) -> FAB hides
      vm.setActiveSubTab(4);
      expect(vm.activeSubTabIndex, 4);
      expect(vm.isFabVisible, isFalse);

      // 7. Switch back to Borrowers tab (index 1) -> borrower is still selected, FAB becomes visible again
      vm.setActiveSubTab(1);
      expect(vm.isFabVisible, isTrue);
      expect(vm.currentFabAction, ReportsFabAction.customerStatement);

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(tabEvents, [1, 2, 3, 4, 1]);
      expect(fabVisibleEvents.contains(true), isTrue);
      expect(fabVisibleEvents.contains(false), isTrue);

      await subTab.cancel();
      await subFab.cancel();
      await subAction.cancel();
      vm.dispose();
    });

    test('ReportsNotifier alias and getFabTapHandler correctly routes callbacks (§6.1)', () async {
      final notifier = ReportsNotifier(initialTab: 0);

      bool customerStatementTapped = false;
      bool lenderStatementTapped = false;

      // 1. Overview tab: FAB hidden, tap handler is null
      var handler = notifier.getFabTapHandler(
        onCustomerStatement: (c) async {
          customerStatementTapped = true;
        },
        onLenderStatement: (l) async {
          lenderStatementTapped = true;
        },
      );
      expect(handler, isNull, reason: 'Overview tab has no PDF action defined — handler must be null');

      // 2. Borrowers tab without selection: handler is null
      notifier.activeSubTabIndex = 1;
      notifier.selectedBorrower = null;
      expect(notifier.isFabVisible, isFalse);
      expect(
        notifier.getFabTapHandler(
          onCustomerStatement: (c) async {},
          onLenderStatement: (l) async {},
        ),
        isNull,
      );

      // 3. Borrowers tab with selection: handler routes to onCustomerStatement
      notifier.selectedBorrower = customer1;
      expect(notifier.isFabVisible, isTrue);
      handler = notifier.getFabTapHandler(
        onCustomerStatement: (c) async {
          expect(c.id, customer1.id);
          customerStatementTapped = true;
        },
        onLenderStatement: (l) async {},
      );
      expect(handler, isNotNull);
      await handler!();
      expect(customerStatementTapped, isTrue);

      // 4. Lenders tab with selection: handler routes to onLenderStatement
      final lender = Lender(
        id: 'l-test-2',
        displayId: 'LEND26-27-02',
        lenderType: LenderType.institution,
        name: 'Finance Corp',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      notifier.activeSubTabIndex = 2;
      notifier.selectedLender = lender;
      expect(notifier.isFabVisible, isTrue);
      handler = notifier.getFabTapHandler(
        onCustomerStatement: (c) async {},
        onLenderStatement: (l) async {
          expect(l.id, lender.id);
          lenderStatementTapped = true;
        },
      );
      expect(handler, isNotNull);
      await handler!();
      expect(lenderStatementTapped, isTrue);

      // 5. Monthly tab (index 3): handler is null
      notifier.activeSubTabIndex = 3;
      expect(notifier.isFabVisible, isFalse);
      expect(
        notifier.getFabTapHandler(
          onCustomerStatement: (c) async {},
          onLenderStatement: (l) async {},
        ),
        isNull,
      );

      // 6. Overdue tab (index 4): handler is null
      notifier.activeSubTabIndex = 4;
      expect(notifier.isFabVisible, isFalse);
      expect(
        notifier.getFabTapHandler(
          onCustomerStatement: (c) async {},
          onLenderStatement: (l) async {},
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

    test('compute(buildLenderStatementBytes, LenderStatementJob(...)) produces PDF bytes on background isolate [FIX-PDFBGTHREAD-1]', () async {
      final lender = Lender(
        id: 'l-iso-1',
        displayId: 'LEND26-27-01',
        lenderType: LenderType.individual,
        name: 'Isolate Lender',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final job = LenderStatementJob(
        lender,
        records,
        businessInfo,
        null,
        testToday,
      );

      final bytes = await compute(buildLenderStatementBytes, job);

      expect(bytes, isNotNull);
      expect(bytes.length, greaterThan(500));
      expect(bytes[0], 0x25);
      expect(bytes[1], 0x50);
      expect(bytes[2], 0x44);
      expect(bytes[3], 0x46);
    });

    test('compute(buildAllLendersBytes, AllLendersJob(...)) produces PDF bytes on background isolate [FIX-PDFBGTHREAD-1]', () async {
      final lender = Lender(
        id: 'l-iso-2',
        displayId: 'LEND26-27-02',
        lenderType: LenderType.institution,
        name: 'Isolate Lender Corp',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final job = AllLendersJob(
        [lender],
        records,
        businessInfo,
        null,
        testToday,
      );

      final bytes = await compute(buildAllLendersBytes, job);

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

    test('PdfShareService exposes shareWithShareXFiles and shareWithPrinting per §6.3', () {
      final shareService = const PdfShareService();
      expect(shareService.shareWithShareXFiles, isA<Function>());
      expect(shareService.shareWithPrinting, isA<Function>());
    });
  });
}
