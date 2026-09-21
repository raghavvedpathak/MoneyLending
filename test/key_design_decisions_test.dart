import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/calculations/calculations.dart';
import 'package:money_lending/data/data.dart';
import 'package:money_lending/domain/domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('Key Room Design Decisions Tests (§4.2)', () {
    test('RecordType string conversion matches spec', () {
      expect(RecordType.GIVEN.name, 'GIVEN');
      expect(RecordType.TAKEN.name, 'TAKEN');
      expect(RecordType.fromString('GIVEN'), RecordType.GIVEN);
      expect(RecordType.fromString('TAKEN'), RecordType.TAKEN);
      expect(RecordType.fromString('INVALID'), isNull);
    });

    test('RecordStatus string conversion matches spec', () {
      expect(RecordStatus.ACTIVE.name, 'ACTIVE');
      expect(RecordStatus.SETTLED.name, 'SETTLED');
      expect(RecordStatus.fromString('ACTIVE'), RecordStatus.ACTIVE);
      expect(RecordStatus.fromString('SETTLED'), RecordStatus.SETTLED);
      expect(RecordStatus.fromString('UNKNOWN'), isNull);
    });

    test('DeleteConfirmationState model adheres to [FIX-DELETESTATE-1]', () {
      const state = DeleteConfirmationState(
        recordId: 'rec-123',
        linkedCount: 3,
        paymentCount: 2,
      );

      expect(state.recordId, 'rec-123');
      expect(state.linkedCount, 3);
      expect(state.paymentCount, 2);
      expect(
        state,
        const DeleteConfirmationState(recordId: 'rec-123', linkedCount: 3, paymentCount: 2),
      );
    });

    test('RecordLinkedTakenException adheres to [FIX-DEV-TOCTOU-1] and [FIX-ID-DELETE-1]', () {
      const exception = RecordLinkedTakenException(linkedCount: 2, paymentCount: 4);
      expect(exception.linkedCount, 2);
      expect(exception.paymentCount, 4);
      expect(exception.toString(), contains('2 TAKEN record(s)'));
      expect(exception.toString(), contains('4 payment(s)'));
    });

    test('StaleRecordException and ItemPledgedException contracts', () {
      const stale = StaleRecordException('rec-999');
      expect(stale.recordId, 'rec-999');
      expect(stale.toString(), contains('rec-999'));

      const pledged = ItemPledgedException(
        itemId: 'item-1',
        holdingRecordId: 'rec-taken-1',
        holdingCustomerName: 'Suresh Patel',
      );
      expect(pledged.itemId, 'item-1');
      expect(pledged.holdingRecordId, 'rec-taken-1');
      expect(pledged.holdingCustomerName, 'Suresh Patel');
      expect(pledged.toString(), contains('Suresh Patel'));
    });

    test('Date converters contract [FIX-TIMESTAMP-TYPECONVERTERS-1]', () {
      const dateOnlyConverter = DateOnlyConverter();
      const localDateTimeConverter = LocalDateTimeConverter();

      // (1) LocalDateTimeConverter round-trips 2026-04-23T14:30:00 exactly
      final dt = DateTime(2026, 4, 23, 14, 30, 0);
      final sqlDt = localDateTimeConverter.toSql(dt);
      expect(sqlDt, '2026-04-23T14:30:00');
      final roundTripped = localDateTimeConverter.fromSql(sqlDt);
      expect(roundTripped, dt);

      // (2) DateOnlyConverter produces bare YYYY-MM-DD and parses to local midnight
      final sqlDate = dateOnlyConverter.toSql(DateTime(2026, 9, 20, 15, 45, 12));
      expect(sqlDate, '2026-09-20');
      final parsedDate = dateOnlyConverter.fromSql(sqlDate);
      expect(parsedDate, DateTime(2026, 9, 20, 0, 0, 0));
      expect(parsedDate.hour, 0);
      expect(parsedDate.minute, 0);
      expect(parsedDate.second, 0);

      // (3) Stored strings sort chronologically as text
      final dates = [
        '2026-01-01',
        '2026-04-23T09:00:00',
        '2026-04-23T14:30:00',
        '2026-09-20',
        '2027-01-15T18:00:00',
      ];
      final sorted = List<String>.from(dates)..sort();
      expect(sorted, dates);
    });

    test('calculateNetProfit uses accrual-based gross interest spread [FIX-PROFIT-SCOPE-1]', () {
      // GIVEN: principal 50000, 2% pm, 2 months -> totalInterest = 2000, customer made 1500 payment
      const givenFin = Financials(
        principal: 50000.0,
        totalInterest: 2000.0,
        totalPaid: 1500.0,
        interestPaid: 1500.0,
        principalPaid: 0.0,
        outstandingInterest: 500.0,
        outstandingPrincipal: 50000.0,
        totalDue: 50500.0,
      );

      // TAKEN: principal 40000, 1.5% pm, 2 months -> totalInterest = 1200, paid 600
      const takenFin = Financials(
        principal: 40000.0,
        totalInterest: 1200.0,
        totalPaid: 600.0,
        interestPaid: 600.0,
        principalPaid: 0.0,
        outstandingInterest: 600.0,
        outstandingPrincipal: 40000.0,
        totalDue: 40600.0,
      );

      // netProfit = givenFinancials.totalInterest - takenFinancials.totalInterest
      // 2000 - 1200 = 800 (NOT cash-adjusted for payments)
      final profit = calculateNetProfit(givenFin, takenFin);
      expect(profit, 800.0);
    });

    test('Android configuration adheres to [FIX-APPID-1] and [FIX-TARGETSDK-1]', () {
      final buildGradle = File('android/app/build.gradle.kts');
      expect(buildGradle.existsSync(), isTrue);
      final content = buildGradle.readAsStringSync();

      expect(content.contains('namespace = "com.moneylending"'), isTrue);
      expect(content.contains('applicationId = "com.moneylending"'), isTrue);
      expect(content.contains('minSdk = 26'), isTrue);
      expect(content.contains('targetSdk = 36'), isTrue);
      expect(content.contains('compileSdk = 36'), isTrue);
    });
  });

  group('Database & Repository §4.2 Integration Tests', () {
    late Database db;
    late DatabaseHelper dbHelper;
    late RecordRepositoryImpl recordRepo;
    late CustomerRepositoryImpl customerRepo;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          await DatabaseHelper.createTablesForTesting(db);
        },
      );
      dbHelper = DatabaseHelper.forTesting(db);
      recordRepo = RecordRepositoryImpl(dbHelper);
      customerRepo = CustomerRepositoryImpl(dbHelper);
    });

    tearDown(() async {
      await db.close();
    });

    test('Date-only fields are midnight-truncated immediately on repository read (§4.2)', () async {
      // 1. Insert customer with createdAt containing time component string
      await db.insert('customers', {
        'id': 'c-dt-1',
        'displayId': 'CUST26-27-01',
        'name': 'Test Truncation',
        'phone': '9876543210',
        'address': 'Test',
        'createdAt': '2026-04-23T14:30:00', // Non-midnight string
      });

      final customer = (await customerRepo.getAllCustomers().first).first;
      expect(customer.createdAt.hour, 0);
      expect(customer.createdAt.minute, 0);
      expect(customer.createdAt.second, 0);

      // 2. Insert record with endDate containing time component
      await db.insert('records', {
        'id': 'r-dt-1',
        'transactionId': 'TRAN092601',
        'type': 'GIVEN',
        'customerId': 'c-dt-1',
        'startDate': '2026-04-23T14:30:00', // Datetime must NOT be truncated
        'endDate': '2026-06-23T18:45:00',   // Date-only must be truncated
        'principalAmount': 10000.0,
        'interestRate': 2.0,
        'status': 'ACTIVE',
        'settledDate': '2026-07-01T12:00:00',
      });

      final record = await recordRepo.getRecordById('r-dt-1');
      expect(record, isNotNull);
      // startDate carries time
      expect(record!.startDate.hour, 14);
      expect(record.startDate.minute, 30);
      // endDate is midnight-truncated
      expect(record.endDate!.hour, 0);
      expect(record.endDate!.minute, 0);
      // settledDate is midnight-truncated
      expect(record.settledDate!.hour, 0);
      expect(record.settledDate!.minute, 0);
    });

    test('deleteRecord throws RecordLinkedTakenException when payments exist [FIX-ID-DELETE-1]', () async {
      await db.insert('customers', {
        'id': 'c-del-1',
        'displayId': 'CUST26-27-02',
        'name': 'Customer 2',
        'phone': '111',
        'address': 'Addr',
        'createdAt': '2026-04-01',
      });

      await db.insert('records', {
        'id': 'r-del-1',
        'transactionId': 'TRAN092602',
        'type': 'GIVEN',
        'customerId': 'c-del-1',
        'startDate': '2026-09-01T10:00:00',
        'principalAmount': 5000.0,
        'interestRate': 2.0,
        'status': 'ACTIVE',
      });

      await db.insert('payments', {
        'id': 'p-del-1',
        'recordId': 'r-del-1',
        'amount': 500.0,
        'date': '2026-09-10T10:00:00',
        'interestPaid': 100.0,
        'principalPaid': 400.0,
        'paymentId': 'PAY092601',
      });

      // Attempting to delete record with payment throws RecordLinkedTakenException
      expect(
        () async => await recordRepo.deleteRecord('r-del-1'),
        throwsA(isA<RecordLinkedTakenException>().having((e) => e.paymentCount, 'paymentCount', 1)),
      );
    });

    test('forceDeleteRecord deletes record and retires transactionId and paymentId (Addendum G)', () async {
      await db.insert('customers', {
        'id': 'c-force-1',
        'displayId': 'CUST26-27-03',
        'name': 'Customer 3',
        'phone': '222',
        'address': 'Addr',
        'createdAt': '2026-04-01',
      });

      await db.insert('records', {
        'id': 'r-force-1',
        'transactionId': 'TRAN092603',
        'type': 'GIVEN',
        'customerId': 'c-force-1',
        'startDate': '2026-09-01T10:00:00',
        'principalAmount': 5000.0,
        'interestRate': 2.0,
        'status': 'ACTIVE',
      });

      await db.insert('payments', {
        'id': 'p-force-1',
        'recordId': 'r-force-1',
        'amount': 500.0,
        'date': '2026-09-10T10:00:00',
        'interestPaid': 100.0,
        'principalPaid': 400.0,
        'paymentId': 'PAY092605',
      });

      // Force delete
      await recordRepo.forceDeleteRecord('r-force-1');

      // Verify record and payment are deleted
      final recordAfter = await recordRepo.getRecordById('r-force-1');
      expect(recordAfter, isNull);

      // Verify transactionId and paymentId are retired in retired_ids
      final retiredTxn = await db.query(
        'retired_ids',
        where: 'kind = ? AND displayId = ?',
        whereArgs: ['transaction', 'TRAN092603'],
      );
      expect(retiredTxn.length, 1);

      final retiredPay = await db.query(
        'retired_ids',
        where: 'kind = ? AND displayId = ?',
        whereArgs: ['payment', 'PAY092605'],
      );
      expect(retiredPay.length, 1);
    });

    test('CustomerRepository.deleteCustomer refuses deletion when customer has records (Addendum G)', () async {
      await db.insert('customers', {
        'id': 'c-guard-1',
        'displayId': 'CUST26-27-04',
        'name': 'Customer Guard',
        'phone': '333',
        'address': 'Addr',
        'createdAt': '2026-04-01',
      });

      await db.insert('records', {
        'id': 'r-guard-1',
        'transactionId': 'TRAN092604',
        'type': 'GIVEN',
        'customerId': 'c-guard-1',
        'startDate': '2026-09-01T10:00:00',
        'principalAmount': 5000.0,
        'interestRate': 2.0,
        'status': 'ACTIVE',
      });

      // Refuses to delete customer who still has records
      expect(
        () async => await customerRepo.deleteCustomer('c-guard-1'),
        throwsA(isA<CustomerHasRecordsException>().having((e) => e.recordCount, 'recordCount', 1)),
      );

      // If record is removed, customer deletion succeeds
      await recordRepo.forceDeleteRecord('r-guard-1');
      await customerRepo.deleteCustomer('c-guard-1');

      final customers = await customerRepo.getAllCustomers().first;
      expect(customers.any((c) => c.id == 'c-guard-1'), isFalse);
    });
  });
}
