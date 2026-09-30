import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/di/injection.dart';
import 'package:money_lending/core/ui/formatters/id_formatter.dart';
import 'package:money_lending/core/utils/app_date_formatter.dart';
import 'package:money_lending/data/datasources/database_helper.dart';
import 'package:money_lending/data/repositories/customer_repository_impl.dart';
import 'package:money_lending/data/repositories/item_rate_repository_impl.dart';
import 'package:money_lending/data/repositories/lender_repository_impl.dart';
import 'package:money_lending/data/repositories/record_repository_impl.dart';
import 'package:money_lending/domain/domain.dart';
import 'package:money_lending/features/customers/customers.dart';
import 'package:money_lending/features/lenders/lenders.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late DatabaseHelper dbHelper;
  late CustomerRepository customerRepo;
  late LenderRepository lenderRepo;
  late RecordRepository recordRepo;
  late ItemRateRepository rateRepo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.createTablesForTesting(db);
    dbHelper = DatabaseHelper.forTesting(db);

    customerRepo = CustomerRepositoryImpl(dbHelper);
    lenderRepo = LenderRepositoryImpl(dbHelper);
    recordRepo = RecordRepositoryImpl(dbHelper);
    rateRepo = ItemRateRepositoryImpl(dbHelper);

    if (sl.isRegistered<DatabaseHelper>()) sl.unregister<DatabaseHelper>();
    if (sl.isRegistered<CustomerRepository>()) sl.unregister<CustomerRepository>();
    if (sl.isRegistered<LenderRepository>()) sl.unregister<LenderRepository>();
    if (sl.isRegistered<RecordRepository>()) sl.unregister<RecordRepository>();
    if (sl.isRegistered<ItemRateRepository>()) sl.unregister<ItemRateRepository>();

    sl.registerSingleton<DatabaseHelper>(dbHelper);
    sl.registerSingleton<CustomerRepository>(customerRepo);
    sl.registerSingleton<LenderRepository>(lenderRepo);
    sl.registerSingleton<RecordRepository>(recordRepo);
    sl.registerSingleton<ItemRateRepository>(rateRepo);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await db.close();
  });

  Widget createTestWidget(Widget child) {
    return MaterialApp(
      home: child,
    );
  }

  group('Section 10.2: Tab 2 Borrowers & Lenders Comprehensive Specification Tests', () {
    testWidgets('1. CustomersScreen displays borrower ID under name & search works correctly', (tester) async {
      await tester.runAsync(() async {
        await customerRepo.insertCustomer(Customer(
          id: 'c1',
          displayId: 'CUST26-27-01',
          name: 'Ramesh Patel',
          phone: '9876543210',
          createdAt: DateTime(2026, 4, 1),
        ));

        await customerRepo.insertCustomer(Customer(
          id: 'c2',
          displayId: 'CUST26-27-02',
          name: 'Suresh Kumar',
          phone: '9123456780',
          createdAt: DateTime(2026, 4, 2),
        ));

        await tester.pumpWidget(createTestWidget(const CustomersScreen()));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      // Verify Borrower list shows both names and IDs
      expect(find.text('Ramesh Patel'), findsOneWidget);
      expect(find.text('Suresh Kumar'), findsOneWidget);
      expect(find.text(AppIdFormatter.formatCustomerId('CUST26-27-01')), findsOneWidget);
      expect(find.text(AppIdFormatter.formatCustomerId('CUST26-27-02')), findsOneWidget);

      // Search by ID or name
      await tester.enterText(find.byType(TextField), 'Ramesh');
      await tester.pumpAndSettle();
      expect(find.text('Ramesh Patel'), findsOneWidget);
      expect(find.text('Suresh Kumar'), findsNothing);

      await tester.enterText(find.byType(TextField), 'CUST-26/27-02');
      await tester.pumpAndSettle();
      expect(find.text('Ramesh Patel'), findsNothing);
      expect(find.text('Suresh Kumar'), findsOneWidget);
    });

    testWidgets('2. AddEditCustomerDialog title reads "Add/Edit Borrower"', (tester) async {
      await tester.pumpWidget(createTestWidget(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => AddEditCustomerDialog.show(context),
            child: const Text('Open Dialog'),
          ),
        ),
      ));

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Add/Edit Borrower'), findsOneWidget);
      expect(find.text('Save Borrower'), findsOneWidget);
    });

    testWidgets('3. CustomerDetailScreen shows "Delete borrower", GIVEN-only history, TRAN... and PAY... IDs', (tester) async {
      late Customer cust;
      await tester.runAsync(() async {
        cust = await customerRepo.insertCustomer(Customer(
          id: 'cust-10',
          displayId: 'CUST26-27-10',
          name: 'Mahesh Sharma',
          phone: '9988776655',
          createdAt: DateTime(2026, 4, 1),
        ));

        // GIVEN record
        await recordRepo.insertRecord(LedgerRecord(
          id: 'rec-g-1',
          transactionId: 'TRAN042601',
          type: RecordType.GIVEN,
          customerId: cust.id,
          startDate: DateTime(2026, 9, 20),
          principalAmount: 15000.0,
          interestRate: 2.5,
          status: RecordStatus.ACTIVE,
          payments: [
            Payment(
              id: 'pay-1',
              paymentId: 'PAY092601',
              recordId: 'rec-g-1',
              amount: 500.0,
              principalPaid: 200.0,
              interestPaid: 300.0,
              date: DateTime(2026, 9, 25),
            ),
          ],
        ));

        // TAKEN record (should NOT appear in Borrower ledger per §10.2)
        await recordRepo.insertRecord(LedgerRecord(
          id: 'rec-t-1',
          transactionId: 'TRAN042602',
          type: RecordType.TAKEN,
          customerId: cust.id,
          startDate: DateTime(2026, 9, 21),
          principalAmount: 5000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
        ));

        await tester.pumpWidget(createTestWidget(CustomerDetailScreen(customerId: cust.id)));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();

      // Header shows name + borrower ID
      expect(find.text('Mahesh Sharma'), findsWidgets);
      expect(find.text(AppIdFormatter.formatCustomerId('CUST26-27-10')), findsWidgets);

      // Overflow menu has "Delete borrower"
      final overflowBtn = find.byIcon(Icons.more_vert);
      expect(overflowBtn, findsOneWidget);
      await tester.tap(overflowBtn);
      await tester.pumpAndSettle();
      expect(find.text('Delete borrower'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10)); // Dismiss menu
      await tester.pumpAndSettle();

      // Per-borrower ledger history is GIVEN-only:
      // TRAN042601 (GIVEN) is shown; TRAN042602 (TAKEN) is NOT shown in borrower ledger
      expect(find.text(AppIdFormatter.formatTransactionId('TRAN042601')), findsOneWidget);
      expect(find.text(AppIdFormatter.formatTransactionId('TRAN042602')), findsNothing);

      // Payment row shows payment ID (PAY...) and formatDate()
      expect(find.text(AppIdFormatter.formatPaymentId('PAY092601')), findsOneWidget);
      expect(find.text(AppDateFormatter.formatDate(DateTime(2026, 9, 25))), findsOneWidget);
    });

    testWidgets('4. LenderListScreen shows lender ID, type badge, search, and AddEditLenderDialog', (tester) async {
      await tester.runAsync(() async {
        await lenderRepo.addLender(
          lenderType: LenderType.individual,
          name: 'Anil Gupta',
          phone: '9876500000',
          createdAt: DateTime(2025, 4, 1),
        );

        await lenderRepo.addLender(
          lenderType: LenderType.institution,
          name: 'Apex Finance NBFC',
          institutionDetails: 'NBFC Lic #12345',
          phone: '0112345678',
          createdAt: DateTime(2025, 4, 2),
        );

        await tester.pumpWidget(createTestWidget(const LenderListScreen()));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      // Both lenders shown with their types
      expect(find.text('Anil Gupta'), findsOneWidget);
      expect(find.text('Apex Finance NBFC'), findsOneWidget);
      expect(find.text('Individual'), findsOneWidget);
      expect(find.text('Institution'), findsOneWidget);

      // Search filters correctly
      await tester.enterText(find.byType(TextField), 'Apex');
      await tester.pumpAndSettle();
      expect(find.text('Apex Finance NBFC'), findsOneWidget);
      expect(find.text('Anil Gupta'), findsNothing);

      // Clear search
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      // Open AddEditLenderDialog
      await tester.tap(find.text('New Lender'));
      await tester.pumpAndSettle();

      // Validate toggle between Individual and Institution
      expect(find.text('Add New Lender'), findsOneWidget);
      expect(find.text('Institution Details *'), findsNothing); // Individual by default

      // Switch to Institution
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Institution')));
      await tester.pumpAndSettle();
      expect(find.text('Institution Details *'), findsOneWidget);

      // Cancel dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('5. LenderDetailScreen & LenderDetailNotifier handle TAKEN-only, ProfitState, and Delete lender', (tester) async {
      late Lender lender;
      await tester.runAsync(() async {
        lender = await lenderRepo.addLender(
          lenderType: LenderType.individual,
          name: 'Vikram Seth',
          phone: '9898989898',
          createdAt: DateTime(2025, 5, 1),
        );

        final cust = await customerRepo.insertCustomer(Customer(
          id: 'cust-backing',
          displayId: 'CUST26-27-20',
          name: 'Backing Borrower',
          createdAt: DateTime(2026, 4, 1),
        ));

        // 1. Linked GIVEN loan (Active)
        final givenLoan = await recordRepo.insertRecord(LedgerRecord(
          id: 'rec-g-linked',
          transactionId: 'TRAN042610',
          type: RecordType.GIVEN,
          customerId: cust.id,
          startDate: DateTime(2026, 9, 1),
          principalAmount: 20000.0,
          interestRate: 3.0,
          status: RecordStatus.ACTIVE,
        ));

        // 2. TAKEN loan borrowed from Vikram Seth, linked to givenLoan
        await recordRepo.insertRecord(LedgerRecord(
          id: 'rec-t-lender',
          transactionId: 'TRAN042611',
          type: RecordType.TAKEN,
          lenderId: lender.id,
          startDate: DateTime(2026, 9, 1),
          principalAmount: 18000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
          linkedRecordId: givenLoan.id,
          payments: [
            Payment(
              id: 'pay-lender-1',
              paymentId: 'PAY092620',
              recordId: 'rec-t-lender',
              amount: 360.0,
              principalPaid: 0.0,
              interestPaid: 360.0,
              date: DateTime(2026, 9, 28),
            ),
          ],
        ));

        // Test LenderDetailNotifier logic directly first
        final notifier = LenderDetailNotifier(
          lenderId: lender.id,
          lenderRepository: lenderRepo,
          recordRepository: recordRepo,
          customerRepository: customerRepo,
          clock: () => DateTime(2026, 10, 1),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(notifier.state.records.length, 1);
        final item = notifier.state.records.first;
        expect(item.record.isTaken, isTrue);
        // Because linked givenLoan is ACTIVE, ProfitState must be InterimProfit
        expect(item.profitState, isA<InterimProfit>());
        expect(item.profitState.label, 'Interim Profit');

        // Test LenderDetailScreen widget
        await tester.pumpWidget(createTestWidget(LenderDetailScreen(lenderId: lender.id)));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        notifier.dispose();
      });
      await tester.pumpAndSettle();

      // Header shows name + lender ID
      expect(find.text('Vikram Seth'), findsWidgets);
      expect(find.text(AppIdFormatter.formatLenderId(lender.displayId)), findsWidgets);

      // Overflow menu has "Delete lender"
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Delete lender'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10)); // Dismiss menu
      await tester.pumpAndSettle();

      // Per-lender ledger displays TAKEN record, TRAN ID, PAY ID, and Interim Profit label
      expect(find.text(AppIdFormatter.formatTransactionId('TRAN042611')), findsOneWidget);
      expect(find.text(AppIdFormatter.formatPaymentId('PAY092620')), findsOneWidget);
      expect(find.text('Interim Profit'), findsOneWidget);
    });

    testWidgets('6. RecordDetailScreen shows party ID + transactionId header, Edit, and Delete action', (tester) async {
      late LedgerRecord rec;
      await tester.runAsync(() async {
        final cust = await customerRepo.insertCustomer(Customer(
          id: 'cust-rec-detail',
          displayId: 'CUST26-27-30',
          name: 'Sunita Roy',
          phone: '9811223344',
          createdAt: DateTime(2026, 4, 1),
        ));

        rec = await recordRepo.insertRecord(LedgerRecord(
          id: 'rec-detail-1',
          transactionId: 'TRAN092630',
          type: RecordType.GIVEN,
          customerId: cust.id,
          startDate: DateTime(2026, 9, 10),
          principalAmount: 25000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
          payments: [
            Payment(
              id: 'pay-det-1',
              paymentId: 'PAY092631',
              recordId: 'rec-detail-1',
              amount: 1000.0,
              principalPaid: 500.0,
              interestPaid: 500.0,
              date: DateTime(2026, 9, 20),
            ),
          ],
        ));

        await tester.pumpWidget(createTestWidget(RecordDetailScreen(recordId: rec.id, record: rec)));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();

      // Header shows party ID + transactionId (CUST-26/27-30 • TRAN-092630)
      final formattedCustId = AppIdFormatter.formatCustomerId('CUST26-27-30');
      final formattedTranId = AppIdFormatter.formatTransactionId('TRAN092630');
      expect(find.text('$formattedCustId • $formattedTranId'), findsOneWidget);

      // AppBar Edit action is visible when ACTIVE
      expect(find.byIcon(Icons.edit), findsOneWidget);

      // AppBar overflow menu has "Delete Record"
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Delete Record'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10)); // Dismiss menu
      await tester.pumpAndSettle();

      // Payment history row shows PAY... ID and date
      expect(find.text(AppIdFormatter.formatPaymentId('PAY092631')), findsOneWidget);
      expect(find.text(AppDateFormatter.formatDate(DateTime(2026, 9, 20))), findsOneWidget);
    });
  });
}
