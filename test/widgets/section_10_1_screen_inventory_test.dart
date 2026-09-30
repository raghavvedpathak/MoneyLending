import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_lending/core/di/injection.dart';
import 'package:money_lending/core/navigation/app_router.dart';
import 'package:money_lending/core/navigation/app_routes.dart';
import 'package:money_lending/core/ui/formatters/id_formatter.dart';
import 'package:money_lending/domain/domain.dart';
import 'package:money_lending/features/dashboard/dashboard.dart';
import 'package:money_lending/features/lenders/lenders.dart';
import 'package:money_lending/presentation/widgets/add_edit_collateral_dialog.dart';
import '../test_db_helper.dart';

void main() {
  late CustomerRepository customerRepo;
  late LenderRepository lenderRepo;
  late ItemRateRepository rateRepo;
  late RecordRepository recordRepo;

  setUpAll(() async {
    await setupTestDatabase();
    customerRepo = sl<CustomerRepository>();
    lenderRepo = sl<LenderRepository>();
    rateRepo = sl<ItemRateRepository>();
    recordRepo = sl<RecordRepository>();
  });

  tearDownAll(() async {
    await sl.reset();
  });

  group('Section 10.1: Navigation & Peer Entry Points', () {
    test('1. LendersRoute and BorrowersRoute are defined and registered in appRouter', () {
      const lendersRoute = LendersRoute();
      const borrowersRoute = BorrowersRoute();

      expect(lendersRoute.path, '/lenders');
      expect(borrowersRoute.path, '/customers');

      final registeredRoutes = appRouter.configuration.routes
          .whereType<GoRoute>()
          .map((r) => r.path)
          .toList();

      expect(registeredRoutes.contains('/lenders'), isTrue);
    });

    testWidgets('2. CustomersScreen hosts peer entry point to Lenders', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp.router(
            routerConfig: appRouter,
          ),
        );
        appRouter.go('/customers');
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify peer button
      expect(find.text('Borrowers'), findsWidgets);
      expect(find.widgetWithText(TextButton, 'Lenders'), findsOneWidget);
      expect(find.text('New Customer'), findsOneWidget);

      // Tap Lenders peer action
      await tester.tap(find.widgetWithText(TextButton, 'Lenders'));
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Now Lenders view is visible
      expect(find.text('New Lender'), findsOneWidget);

      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('3. LenderListScreen displays lenders with displayId, type badge, and delete guard', (tester) async {
      late Lender lender;
      await tester.runAsync(() async {
        lender = await lenderRepo.addLender(
          lenderType: LenderType.institution,
          name: 'Apex Capital Ltd',
          phone: '9876543210',
          institutionDetails: 'NBFC License 8899',
          createdAt: DateTime(2026, 4, 1),
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: LenderListScreen(),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Apex Capital Ltd'), findsOneWidget);
      expect(find.text(AppIdFormatter.formatLenderId(lender.displayId)), findsOneWidget);
      expect(find.text('Institution'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('NBFC License 8899'), findsOneWidget);

      // Verify delete guard when records exist
      await tester.runAsync(() async {
        await recordRepo.insertRecord(LedgerRecord(
          id: 'rec-lender-1',
          transactionId: 'TRAN042699',
          type: RecordType.TAKEN,
          lenderId: lender.id,
          principalAmount: 50000,
          interestRate: 1.5,
          startDate: DateTime(2026, 4, 1),
          status: RecordStatus.ACTIVE,
        ));
      });

      // Attempt deletion via delete icon
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();

      expect(find.text('Delete Lender'), findsNWidgets(2));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Lender'));
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Error snackbar should mention active/settled records
      expect(find.textContaining('Cannot delete lender with 1 active/settled record(s)'), findsOneWidget);

      await tester.pump(const Duration(seconds: 11));
    });
  });

  group('Section 10.1: [FIX-RATE-ASOF-1] Backdated Collateral Rate Auto-fill', () {
    testWidgets('4. AddEditCollateralDialog auto-fills rate that was in force on backdated recordDate', (tester) async {
      late List<ItemRate> currentRates;
      await tester.runAsync(() async {
        // Historical rate on 2026-08-01: 5500
        await rateRepo.upsertRate(ItemRate(
          id: 'r-aug',
          itemCategory: 'GOLD',
          ratePerUnit: 5500.0,
          effectiveDate: DateTime(2026, 8, 1),
          updatedAt: DateTime(2026, 8, 1),
        ));

        // Current rate today (2026-09-20): 6200
        await rateRepo.upsertRate(ItemRate(
          id: 'r-sep',
          itemCategory: 'GOLD',
          ratePerUnit: 6200.0,
          effectiveDate: DateTime(2026, 9, 20),
          updatedAt: DateTime(2026, 9, 20),
        ));

        currentRates = await rateRepo.getCurrentRatesOnce();

        // Open dialog with backdated recordDate = 2026-08-15
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AddEditCollateralDialog(
                currentRates: currentRates,
                recordDate: DateTime(2026, 8, 15),
                onSave: (_) {},
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify that the rate field auto-filled with 5500 (rate as of August 15), not 6200!
      final rateField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Rate / gram (₹) *'),
      );
      expect(rateField.controller?.text, '5500');

      await tester.pump(const Duration(seconds: 11));
    });
  });

  group('Section 10.1: Tab 1 Dashboard Defaults & Collection Alert Section', () {
    testWidgets('5. DashboardScreen displays record list by default (showRecordList defaults to true)', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        final cust = await customerRepo.insertCustomer(Customer(
          id: 'c-dash-1',
          displayId: 'CUST26-27-01',
          name: 'Dashboard Tester',
          createdAt: DateTime(2026, 9, 1),
        ));

        await recordRepo.insertRecord(LedgerRecord(
          id: 'rec-dash-1',
          transactionId: 'TRAN092677',
          type: RecordType.GIVEN,
          customerId: cust.id,
          customerName: cust.name,
          startDate: DateTime(2026, 9, 15, 11, 0),
          principalAmount: 15000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
        ));

        await tester.pumpWidget(
          const MaterialApp(
            home: DashboardScreen(),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Record list header and item must be visible
      expect(find.text('Active Loans Given'), findsOneWidget);
      expect(find.text('Dashboard Tester'), findsOneWidget);
      expect(find.text('15 September 2026'), findsOneWidget);
      expect(find.text(AppIdFormatter.formatTransactionId('TRAN092677')), findsOneWidget);

      await tester.pump(const Duration(seconds: 11));
    });
  });
}
