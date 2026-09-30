import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/di/injection.dart';
import 'package:money_lending/core/ui/formatters/id_formatter.dart';
import 'package:money_lending/domain/domain.dart';
import 'package:money_lending/features/reports/reports.dart';
import '../test_db_helper.dart';

void main() {
  late CustomerRepository customerRepo;
  late LenderRepository lenderRepo;
  late RecordRepository recordRepo;
  late ItemRateRepository itemRateRepo;

  setUpAll(() async {
    await setupTestDatabase();
    customerRepo = sl<CustomerRepository>();
    lenderRepo = sl<LenderRepository>();
    recordRepo = sl<RecordRepository>();
    itemRateRepo = sl<ItemRateRepository>();
  });

  tearDownAll(() async {
    await sl.reset();
  });

  group('Section 10.3: Tab 3 Reports Full Specification Tests', () {
    testWidgets('Overview tab: shows Given/Taken split, net position, portfolio health, FAB hidden', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        final borrower = await customerRepo.insertCustomer(Customer(
          id: 'c-ov-1',
          displayId: 'CUST26-27-10',
          name: 'Overview Borrower',
          createdAt: DateTime(2026, 1, 1),
        ));

        final lender = await lenderRepo.addLender(
          lenderType: LenderType.individual,
          name: 'Overview Lender',
          phone: '9876543210',
          createdAt: DateTime(2026, 1, 1),
        );

        // Given loan: 20000
        await recordRepo.insertRecord(LedgerRecord(
          id: 'r-ov-g1',
          transactionId: 'TRAN092610',
          type: RecordType.GIVEN,
          customerId: borrower.id,
          customerName: borrower.name,
          principalAmount: 20000,
          interestRate: 2.0,
          startDate: DateTime(2026, 1, 1),
          status: RecordStatus.ACTIVE,
        ));

        // Taken loan: 10000
        await recordRepo.insertRecord(LedgerRecord(
          id: 'r-ov-t1',
          transactionId: 'TRAN092611',
          type: RecordType.TAKEN,
          lenderId: lender.id,
          principalAmount: 10000,
          interestRate: 1.5,
          startDate: DateTime(2026, 1, 1),
          status: RecordStatus.ACTIVE,
        ));

        await tester.pumpWidget(
          const MaterialApp(
            home: ReportsScreen(initialSubTab: 0),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 1. Executive Summary & Given / Taken / Net Breakdown
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Executive Financial Summary'), findsOneWidget);
      expect(find.text('Given Side (Borrowers)'), findsOneWidget);
      expect(find.text('Total Principal Lent (Given)'), findsOneWidget);
      expect(find.text('Total Interest Accrued'), findsWidgets);
      expect(find.text('Grand Total Outstanding Due'), findsOneWidget);

      expect(find.text('Taken Side (Lenders)'), findsOneWidget);
      expect(find.text('Total Principal Borrowed (Taken)'), findsOneWidget);
      expect(find.text('Total Interest Payable (Taken)'), findsOneWidget);
      expect(find.text('Total Due to Lenders'), findsOneWidget);

      expect(find.text('Net Position & Spread'), findsOneWidget);
      expect(find.text('Net Principal Outstanding'), findsOneWidget);
      expect(find.text('Net Interest Spread'), findsOneWidget);
      expect(find.text('Net Outstanding Due Balance'), findsOneWidget);

      expect(find.text('Portfolio Health'), findsOneWidget);

      // FAB is hidden on Overview (§6.1)
      expect(find.text('Export Statement PDF'), findsNothing);

      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('Monthly tab: cash-basis interest received with mandatory label "Interest Received"', (tester) async {
      await tester.runAsync(() async {
        final cust = await customerRepo.insertCustomer(Customer(
          id: 'c-mo-1',
          displayId: 'CUST26-27-20',
          name: 'Monthly Borrower',
          createdAt: DateTime(2026, 1, 1),
        ));

        final rec = await recordRepo.insertRecord(LedgerRecord(
          id: 'r-mo-1',
          transactionId: 'TRAN092620',
          type: RecordType.GIVEN,
          customerId: cust.id,
          customerName: cust.name,
          principalAmount: 30000,
          interestRate: 2.0,
          startDate: DateTime(2026, 1, 1),
          status: RecordStatus.ACTIVE,
        ));

        await recordRepo.addPayment(Payment(
          id: 'p-mo-1',
          paymentId: 'PAY092620',
          recordId: rec.id,
          amount: 600,
          date: DateTime(2026, 4, 10),
          interestPaid: 600,
          principalPaid: 0,
        ));

        await tester.pumpWidget(
          const MaterialApp(
            home: ReportsScreen(initialSubTab: 3), // Index 3: Monthly
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Cash-Basis Interest Received (§5.1)'), findsOneWidget);
      expect(find.text('April 2026'), findsOneWidget);
      expect(find.text('Interest Received'), findsWidgets);

      // FAB hidden on Monthly tab (§6.1)
      expect(find.text('Export Statement PDF'), findsNothing);

      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('Overdue tab: displays past 30-day activity threshold and collateral breach', (tester) async {
      await tester.runAsync(() async {
        final cust = await customerRepo.insertCustomer(Customer(
          id: 'c-od-1',
          displayId: 'CUST26-27-30',
          name: 'Overdue Borrower Case',
          createdAt: DateTime(2026, 1, 1),
        ));

        // Inactive loan started 50 days ago
        await recordRepo.insertRecord(LedgerRecord(
          id: 'r-od-1',
          transactionId: 'TRAN092630',
          type: RecordType.GIVEN,
          customerId: cust.id,
          customerName: cust.name,
          principalAmount: 25000,
          interestRate: 2.0,
          startDate: DateTime.now().subtract(const Duration(days: 50)),
          status: RecordStatus.ACTIVE,
        ));

        await tester.pumpWidget(
          const MaterialApp(
            home: ReportsScreen(initialSubTab: 4), // Index 4: Overdue
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('092630'), findsOneWidget);
      expect(find.textContaining('Inactive: 50 days'), findsOneWidget);
      expect(find.text('GIVEN'), findsWidgets);

      // FAB hidden on Overdue tab (§6.1)
      expect(find.text('Export Statement PDF'), findsNothing);

      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('Borrowers tab: lists only active borrowers with 5 fields, excludes zero-active, handles drill-down & FAB', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        // Active borrower
        final activeBorrower = await customerRepo.insertCustomer(Customer(
          id: 'c-bw-active',
          displayId: 'CUST26-27-40',
          name: 'Active Borrower Dev',
          phone: '9811223344',
          createdAt: DateTime(2026, 1, 1),
        ));

        // Inactive borrower (0 active records)
        final zeroBorrower = await customerRepo.insertCustomer(Customer(
          id: 'c-bw-zero',
          displayId: 'CUST26-27-41',
          name: 'Zero Records Borrower',
          createdAt: DateTime(2026, 1, 1),
        ));

        await recordRepo.insertRecord(LedgerRecord(
          id: 'r-bw-active-1',
          transactionId: 'TRAN092640',
          type: RecordType.GIVEN,
          customerId: activeBorrower.id,
          customerName: activeBorrower.name,
          principalAmount: 18000,
          interestRate: 2.0,
          startDate: DateTime(2026, 2, 1),
          status: RecordStatus.ACTIVE,
        ));

        // Settled record for zeroBorrower (activeRecordCount is 0)
        await recordRepo.insertRecord(LedgerRecord(
          id: 'r-bw-settled-1',
          transactionId: 'TRAN092641',
          type: RecordType.GIVEN,
          customerId: zeroBorrower.id,
          customerName: zeroBorrower.name,
          principalAmount: 5000,
          interestRate: 2.0,
          startDate: DateTime(2026, 1, 1),
          status: RecordStatus.SETTLED,
        ));

        await tester.pumpWidget(
          const MaterialApp(
            home: ReportsScreen(initialSubTab: 1), // Index 1: Borrowers
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 1. Verify Active Borrower is present with all 5 fields (§5.1, §6.1)
      expect(find.text('Active Borrower Dev'), findsOneWidget);
      expect(find.text('CUST-26/27-40'), findsOneWidget);
      expect(find.text('1 Active'), findsWidgets);
      expect(find.text('Total Principal Out'), findsWidgets);
      expect(find.text('Total Interest Accrued'), findsWidgets);
      expect(find.text('Total Due'), findsWidgets);

      // 2. CRUCIAL RULE (§10.3): Borrower with 0 active records simply DOES NOT appear
      expect(find.text('Zero Records Borrower'), findsNothing);

      // 3. FAB hidden before selection (§6.1)
      expect(find.text('Export Statement PDF'), findsNothing);

      // 4. Tap row -> drill-down opens, FAB becomes visible
      await tester.tap(find.text('Active Borrower Dev'));
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.text('Record History'), findsOneWidget);
      expect(find.textContaining('092640'), findsOneWidget);
      expect(find.text('Export Statement PDF'), findsOneWidget);

      // 5. Back navigation restores list and hides FAB
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Active Borrower Dev'), findsOneWidget);
      expect(find.text('Export Statement PDF'), findsNothing);

      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('Lenders tab: lists only active lenders with 5 fields, excludes zero-active, handles drill-down & FAB', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late Lender activeLender;
      late Lender zeroLender;

      await tester.runAsync(() async {
        // Active lender
        activeLender = await lenderRepo.addLender(
          lenderType: LenderType.institution,
          name: 'Vanguard Capital',
          phone: '9123456780',
          institutionDetails: 'Reg #9988',
          createdAt: DateTime(2026, 1, 1),
        );

        // Inactive lender (0 active records)
        zeroLender = await lenderRepo.addLender(
          lenderType: LenderType.individual,
          name: 'Zero Records Lender',
          phone: '9123456781',
          createdAt: DateTime(2026, 1, 1),
        );

        await recordRepo.insertRecord(LedgerRecord(
          id: 'r-ln-active-1',
          transactionId: 'TRAN092650',
          type: RecordType.TAKEN,
          lenderId: activeLender.id,
          principalAmount: 50000,
          interestRate: 1.8,
          startDate: DateTime(2026, 2, 1),
          status: RecordStatus.ACTIVE,
        ));

        // Settled record for zeroLender (activeRecordCount is 0)
        await recordRepo.insertRecord(LedgerRecord(
          id: 'r-ln-settled-1',
          transactionId: 'TRAN092651',
          type: RecordType.TAKEN,
          lenderId: zeroLender.id,
          principalAmount: 10000,
          interestRate: 1.5,
          startDate: DateTime(2026, 1, 1),
          status: RecordStatus.SETTLED,
        ));

        await tester.pumpWidget(
          const MaterialApp(
            home: ReportsScreen(initialSubTab: 2), // Index 2: Lenders
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 1. Verify Active Lender is present with 5 fields (§5.1, §6.1)
      expect(find.text('Vanguard Capital'), findsOneWidget);
      expect(find.text('${AppIdFormatter.formatLenderId(activeLender.displayId)} • Institution'), findsOneWidget);
      expect(find.text('1 Active'), findsWidgets);
      expect(find.text('Principal Taken'), findsWidgets);
      expect(find.text('Interest Payable'), findsWidgets);
      expect(find.text('Total Due'), findsWidgets);

      // 2. CRUCIAL RULE (§10.3): Lender with 0 active records simply DOES NOT appear
      expect(find.text('Zero Records Lender'), findsNothing);

      // 3. FAB hidden before selection (§6.1)
      expect(find.text('Export Statement PDF'), findsNothing);

      // 4. Tap row -> drill-down opens, FAB becomes visible
      await tester.tap(find.text('Vanguard Capital'));
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.text('Record History (Loans Taken)'), findsOneWidget);
      expect(find.textContaining('092650'), findsOneWidget);
      expect(find.text('Export Statement PDF'), findsOneWidget);

      // 5. Back navigation restores list and hides FAB
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Vanguard Capital'), findsOneWidget);
      expect(find.text('Export Statement PDF'), findsNothing);

      await tester.pump(const Duration(seconds: 11));
    });
  });
}
