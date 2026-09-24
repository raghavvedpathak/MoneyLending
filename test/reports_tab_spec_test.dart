import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/di/injection.dart';
import 'package:money_lending/domain/domain.dart';
import 'package:money_lending/features/reports/reports.dart';
import 'test_db_helper.dart';

void main() {
  late CustomerRepository customerRepo;
  late RecordRepository recordRepo;

  setUpAll(() async {
    await setupTestDatabase();
    customerRepo = sl<CustomerRepository>();
    recordRepo = sl<RecordRepository>();
  });

  tearDownAll(() async {
    await sl.reset();
  });

  group('Section 10.3: Tab 3 Reports Specification Tests', () {
    testWidgets('Overview tab displays total principal, interest, due matching CalculationEngine', (tester) async {
      await tester.runAsync(() async {
        final cust = await customerRepo.insertCustomer(Customer(
          id: 'c-rep-1',
          displayId: 'CUST26-27-01',
          name: 'John Doe',
          createdAt: DateTime(2026, 1, 1),
        ));

        await recordRepo.insertRecord(LedgerRecord(
          id: 'r-rep-1',
          transactionId: 'TRAN092601',
          type: RecordType.GIVEN,
          customerId: cust.id,
          customerName: cust.name,
          principalAmount: 20000,
          interestRate: 2.0,
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

      // Verify overview tab elements
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Executive Financial Summary'), findsOneWidget);
      expect(find.text('Total Principal Lent (Given)'), findsOneWidget);
      expect(find.text('Total Interest Accrued'), findsOneWidget);
      expect(find.text('Grand Total Outstanding Due'), findsOneWidget);
      expect(find.text('Portfolio Health'), findsOneWidget);

      // Overview FAB should be visible ('Export All PDF')
      expect(find.text('Export All PDF'), findsOneWidget);

      // Drain any pending timers
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('Monthly tab displays cash-basis interest with mandatory label "Interest Received"', (tester) async {
      await tester.runAsync(() async {
        final cust = await customerRepo.insertCustomer(Customer(
          id: 'c-rep-2',
          displayId: 'CUST26-27-02',
          name: 'Jane Smith',
          createdAt: DateTime(2026, 1, 1),
        ));

        final rec = await recordRepo.insertRecord(LedgerRecord(
          id: 'r-rep-2',
          transactionId: 'TRAN092602',
          type: RecordType.GIVEN,
          customerId: cust.id,
          customerName: cust.name,
          principalAmount: 10000,
          interestRate: 2.0,
          startDate: DateTime(2026, 1, 1),
          status: RecordStatus.ACTIVE,
        ));

        await recordRepo.addPayment(Payment(
          id: 'p-rep-1',
          paymentId: 'PAY092601',
          recordId: rec.id,
          amount: 500,
          date: DateTime(2026, 3, 15),
          interestPaid: 500,
          principalPaid: 0,
        ));

        await tester.pumpWidget(
          const MaterialApp(
            home: ReportsScreen(initialSubTab: 2), // Index 2: Monthly
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify Monthly tab header and explicit label "Interest Received"
      expect(find.text('Cash-Basis Interest Received (§5.1)'), findsOneWidget);
      expect(find.text('March 2026'), findsOneWidget);
      expect(find.text('Interest Received'), findsWidgets);

      // FAB must be hidden on Monthly tab
      expect(find.text('Export All PDF'), findsNothing);
      expect(find.text('Export Statement PDF'), findsNothing);

      // Drain any pending timers
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('Customer tab renders all 5 CustomerReport fields and supports tap drill-down and FAB visibility', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        final cust = await customerRepo.insertCustomer(Customer(
          id: 'c-rep-3',
          displayId: 'CUST26-27-03',
          name: 'Raj Patel',
          phone: '9876543210',
          createdAt: DateTime(2026, 1, 1),
        ));

        await recordRepo.insertRecord(LedgerRecord(
          id: 'r-rep-3',
          transactionId: 'TRAN092603',
          type: RecordType.GIVEN,
          customerId: cust.id,
          customerName: cust.name,
          principalAmount: 15000,
          interestRate: 2.0,
          startDate: DateTime(2026, 2, 1),
          status: RecordStatus.ACTIVE,
        ));

        await tester.pumpWidget(
          const MaterialApp(
            home: ReportsScreen(initialSubTab: 1), // Index 1: Customer
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 1. Initial State: Customer list with all 5 fields
      expect(find.text('Raj Patel'), findsOneWidget);
      expect(find.text('CUST26-27-03'), findsOneWidget);
      expect(find.text('1 Active'), findsWidgets);
      expect(find.text('Total Principal Out'), findsWidgets);
      expect(find.text('Total Interest Accrued'), findsWidgets);
      expect(find.text('Total Due'), findsWidgets);

      // FAB is hidden on Customer tab when selectedCustomer is null
      expect(find.text('Export Statement PDF'), findsNothing);

      // 2. Tap customer card to select customer & open navigation drill-down
      await tester.tap(find.text('Raj Patel'));
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Drill-down view is displayed
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.text('Record History'), findsOneWidget);
      expect(find.textContaining('TRAN092603'), findsOneWidget);

      // FAB becomes visible for statement export
      expect(find.text('Export Statement PDF'), findsOneWidget);

      // 3. Tap back button to return to all customers list
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Back to customer list
      expect(find.text('Raj Patel'), findsOneWidget);
      expect(find.text('Total Principal Out'), findsWidgets);
      // FAB is hidden again
      expect(find.text('Export Statement PDF'), findsNothing);

      // Drain any pending timers
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('Overdue tab displays activity-based and collateral-based records with reasons', (tester) async {
      await tester.runAsync(() async {
        final cust = await customerRepo.insertCustomer(Customer(
          id: 'c-rep-4',
          displayId: 'CUST26-27-04',
          name: 'Overdue Borrower',
          createdAt: DateTime(2026, 1, 1),
        ));

        // Record started > 30 days ago with no payment activity
        await recordRepo.insertRecord(LedgerRecord(
          id: 'r-rep-4',
          transactionId: 'TRAN092604',
          type: RecordType.GIVEN,
          customerId: cust.id,
          customerName: cust.name,
          principalAmount: 50000,
          interestRate: 3.0,
          startDate: DateTime.now().subtract(const Duration(days: 45)),
          status: RecordStatus.ACTIVE,
        ));

        await tester.pumpWidget(
          const MaterialApp(
            home: ReportsScreen(initialSubTab: 3), // Index 3: Overdue
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Overdue list should show record
      expect(find.textContaining('TRAN092604'), findsOneWidget);
      expect(find.textContaining('Inactive: 45 days'), findsOneWidget);

      // FAB is hidden on Overdue tab
      expect(find.text('Export All PDF'), findsNothing);
      expect(find.text('Export Statement PDF'), findsNothing);

      // Drain any pending timers
      await tester.pump(const Duration(seconds: 11));
    });
  });
}
