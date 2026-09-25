import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/calculations/calculations.dart';
import 'package:money_lending/core/di/injection.dart';
import 'package:money_lending/core/utils/app_date_formatter.dart';
import 'package:money_lending/data/datasources/database_helper.dart';
import 'package:money_lending/data/repositories/customer_repository_impl.dart';
import 'package:money_lending/data/repositories/record_repository_impl.dart';
import 'package:money_lending/domain/domain.dart';
import 'package:money_lending/features/customers/customers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late DatabaseHelper dbHelper;
  late CustomerRepository customerRepo;
  late RecordRepository recordRepo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.createTablesForTesting(db);
    dbHelper = DatabaseHelper.forTesting(db);

    customerRepo = CustomerRepositoryImpl(dbHelper);
    recordRepo = RecordRepositoryImpl(dbHelper);

    if (sl.isRegistered<DatabaseHelper>()) sl.unregister<DatabaseHelper>();
    if (sl.isRegistered<CustomerRepository>()) sl.unregister<CustomerRepository>();
    if (sl.isRegistered<RecordRepository>()) sl.unregister<RecordRepository>();

    sl.registerSingleton<DatabaseHelper>(dbHelper);
    sl.registerSingleton<CustomerRepository>(customerRepo);
    sl.registerSingleton<RecordRepository>(recordRepo);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await db.close();
  });

  group('Section 10.2: Tab 2 Customers & ProfitState Specification Tests', () {
    test('ProfitState sealed class hierarchy behaves correctly with pattern matching', () {
      const ProfitState interim = InterimProfit(250.0);
      const ProfitState net = NetProfit(400.0);
      const ProfitState none = NoProfit();

      expect(interim.label, 'Interim Profit');
      expect(interim.profitAmount, 250.0);

      expect(net.label, 'Net Profit');
      expect(net.profitAmount, 400.0);

      expect(none.label, isNull);
      expect(none.profitAmount, isNull);

      final labelFromSwitch = switch (interim) {
        InterimProfit(:final amount) => 'Interim: $amount',
        NetProfit(:final amount) => 'Net: $amount',
        NoProfit() => 'None',
      };
      expect(labelFromSwitch, 'Interim: 250.0');
    });

    test('CustomerDetailNotifier resolves InterimProfit when linked GIVEN record is ACTIVE', () async {
      final cust = await customerRepo.insertCustomer(Customer(
        id: 'cust-1',
        displayId: 'CUST26-27-01',
        name: 'Alice Borrow',
        createdAt: DateTime(2026, 4, 1),
      ));

      // 1. GIVEN record (Lent ₹10,000 at 3%/mo on 2026-04-01) - ACTIVE
      final givenRec = await recordRepo.insertRecord(LedgerRecord(
        id: 'rec-given-1',
        transactionId: 'TRAN042601',
        type: RecordType.GIVEN,
        customerId: cust.id,
        startDate: DateTime(2026, 4, 1),
        principalAmount: 10000.0,
        interestRate: 3.0,
        status: RecordStatus.ACTIVE,
      ));

      // 2. TAKEN record (Borrowed ₹8,000 at 2%/mo on 2026-04-01) linked to GIVEN - ACTIVE
      await recordRepo.insertRecord(LedgerRecord(
        id: 'rec-taken-1',
        transactionId: 'TRAN042602',
        type: RecordType.TAKEN,
        customerId: cust.id,
        startDate: DateTime(2026, 4, 1),
        principalAmount: 8000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        linkedRecordId: givenRec.id,
      ));

      final notifier = CustomerDetailNotifier(
        customerId: cust.id,
        customerRepository: customerRepo,
        recordRepository: recordRepo,
        clock: () => DateTime(2026, 5, 1), // 1 month elapsed
      );

      // Wait for stream emission
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final state = notifier.state;
      expect(state.customer?.name, 'Alice Borrow');
      expect(state.records.length, 2);

      final takenItem = state.records.firstWhere((r) => r.record.id == 'rec-taken-1');
      expect(takenItem.profitState, isA<InterimProfit>());
      final interim = takenItem.profitState as InterimProfit;

      // Given interest = 300, Taken interest = 160 -> profit spread = 140
      expect(interim.amount, 140.0);
      expect(takenItem.profitState.label, 'Interim Profit');

      final givenItem = state.records.firstWhere((r) => r.record.id == 'rec-given-1');
      expect(givenItem.profitState, isA<NoProfit>());

      notifier.dispose();
    });

    test('CustomerDetailNotifier resolves NetProfit when linked GIVEN record is SETTLED', () async {
      final cust = await customerRepo.insertCustomer(Customer(
        id: 'cust-2',
        displayId: 'CUST26-27-02',
        name: 'Bob Borrow',
        createdAt: DateTime(2026, 4, 1),
      ));

      // GIVEN record settled with calculatedInterest = 600.0
      final givenRec = await recordRepo.insertRecord(LedgerRecord(
        id: 'rec-given-2',
        transactionId: 'TRAN042603',
        type: RecordType.GIVEN,
        customerId: cust.id,
        startDate: DateTime(2026, 4, 1),
        principalAmount: 10000.0,
        interestRate: 3.0,
        status: RecordStatus.SETTLED,
        settledDate: DateTime(2026, 6, 1),
        calculatedInterest: 600.0,
      ));

      // TAKEN record linked to SETTLED GIVEN record
      await recordRepo.insertRecord(LedgerRecord(
        id: 'rec-taken-2',
        transactionId: 'TRAN042604',
        type: RecordType.TAKEN,
        customerId: cust.id,
        startDate: DateTime(2026, 4, 1),
        principalAmount: 8000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        linkedRecordId: givenRec.id,
      ));

      final notifier = CustomerDetailNotifier(
        customerId: cust.id,
        customerRepository: customerRepo,
        recordRepository: recordRepo,
        clock: () => DateTime(2026, 6, 1), // 2 months elapsed
      );

      await Future<void>.delayed(const Duration(milliseconds: 150));

      final state = notifier.state;
      final takenItem = state.records.firstWhere((r) => r.record.id == 'rec-taken-2');
      expect(takenItem.profitState, isA<NetProfit>());
      final netProfit = takenItem.profitState as NetProfit;

      // Given interest snapshot = 600.0, Taken interest for 2 months = 320.0 -> spread = 280.0
      expect(netProfit.amount, 280.0);
      expect(takenItem.profitState.label, 'Net Profit');

      notifier.dispose();
    });

    test('CustomerDetailNotifier never crashes on a broken FK and emits NoProfit (§10.2)', () async {
      final cust = await customerRepo.insertCustomer(Customer(
        id: 'cust-3',
        displayId: 'CUST26-27-03',
        name: 'Charlie Broken FK',
        createdAt: DateTime(2026, 4, 1),
      ));

      // TAKEN record pointing to a non-existent linkedRecordId
      await recordRepo.insertRecord(LedgerRecord(
        id: 'rec-taken-broken',
        transactionId: 'TRAN042605',
        type: RecordType.TAKEN,
        customerId: cust.id,
        startDate: DateTime(2026, 4, 1),
        principalAmount: 5000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        linkedRecordId: 'non-existent-rec-id-999',
      ));

      final notifier = CustomerDetailNotifier(
        customerId: cust.id,
        customerRepository: customerRepo,
        recordRepository: recordRepo,
        clock: () => DateTime(2026, 5, 1),
      );

      await Future<void>.delayed(const Duration(milliseconds: 150));

      final state = notifier.state;
      expect(state.records.length, 1);
      final item = state.records.first;
      expect(item.profitState, isA<NoProfit>());
      expect(item.profitState.label, isNull);

      notifier.dispose();
    });

    test('[FIX-TIMESTAMPCUSTOMERHISTORY-1] (revised v1.15) Record rows and payments format timestamps with formatDate()', () async {
      final cust = await customerRepo.insertCustomer(Customer(
        id: 'cust-4',
        displayId: 'CUST26-27-04',
        name: 'Diana Timestamp',
        createdAt: DateTime(2026, 9, 20),
      ));

      final rec = await recordRepo.insertRecord(LedgerRecord(
        id: 'rec-ts-1',
        transactionId: 'TRAN092601',
        type: RecordType.GIVEN,
        customerId: cust.id,
        startDate: DateTime(2026, 9, 20, 14, 30),
        principalAmount: 15000.0,
        interestRate: 2.5,
        status: RecordStatus.ACTIVE,
      ));

      await recordRepo.addPayment(Payment(
        id: 'pay-ts-1',
        paymentId: 'PAY092601',
        recordId: rec.id,
        amount: 500.0,
        date: DateTime(2026, 10, 5, 9, 15),
        interestPaid: 375.0,
        principalPaid: 125.0,
      ));

      final notifier = CustomerDetailNotifier(
        customerId: cust.id,
        customerRepository: customerRepo,
        recordRepository: recordRepo,
        clock: () => DateTime(2026, 10, 10),
      );

      await Future<void>.delayed(const Duration(milliseconds: 150));

      final state = notifier.state;
      expect(state.records.length, 1);

      final item = state.records.first;
      // Record transaction date formatted with formatDate(startDate) -> "20 September 2026"
      final recordDateStr = AppDateFormatter.formatDate(item.record.startDate);
      expect(recordDateStr, '20 September 2026');
      expect(item.record.transactionId, 'TRAN092601');

      // Payment date formatted with formatDate(payment.date) -> "5 October 2026"
      final payment = item.record.payments.first;
      final paymentDateStr = AppDateFormatter.formatDate(payment.date);
      expect(paymentDateStr, '5 October 2026');
      expect(payment.paymentId, 'PAY092601');

      notifier.dispose();
    });

    test('Customer deletion refuses when records exist and retires displayId on deletion (Addendum G, FIX-ID-REUSE-1)', () async {
      final cust = await customerRepo.insertCustomer(Customer(
        id: 'cust-delete-test',
        displayId: 'CUST26-27-10',
        name: 'Delete Me Customer',
        createdAt: DateTime(2026, 9, 1),
      ));

      final rec = await recordRepo.insertRecord(LedgerRecord(
        id: 'rec-del-1',
        transactionId: 'TRAN092610',
        type: RecordType.GIVEN,
        customerId: cust.id,
        startDate: DateTime(2026, 9, 1),
        principalAmount: 1000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      ));

      // Attempting to delete customer with records throws CustomerHasRecordsException
      expect(
        () => customerRepo.deleteCustomer(cust.id),
        throwsA(isA<CustomerHasRecordsException>()),
      );

      // Force delete record first
      await recordRepo.forceDeleteRecord(rec.id);

      // Now customer deletion succeeds
      await customerRepo.deleteCustomer(cust.id);

      // Verify displayId CUST26-27-10 is recorded in retired_ids
      final retired = await db.query(
        'retired_ids',
        where: 'kind = ? AND displayId = ?',
        whereArgs: ['customer', 'CUST26-27-10'],
      );
      expect(retired.length, 1);

      // Next customer sequence skips retired CUST26-27-10 and assigns 11
      final nextDisplayId = await dbHelper.generateNextCustomerDisplayId(db, DateTime(2026, 9, 2));
      expect(nextDisplayId, 'CUST26-27-11');
    });
  });
}
