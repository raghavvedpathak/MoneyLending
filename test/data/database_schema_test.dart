import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/data/schema/drift_tables.dart' as schema;
import 'package:money_lending/data/data.dart';
import 'package:money_lending/domain/domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('Data Layer Entity & Schema Tests (§4.1)', () {
    test('CustomerEntity serialization and displayId integrity [FIX-DEVCONCURRENCY-1]', () {
      const customer = CustomerEntity(
        id: 'cust-uuid-1',
        displayId: 'CUST-0001',
        name: 'Ramesh Kumar',
        phone: '9876543210',
        address: 'Bazaar Road',
        createdAt: '2026-04-23',
      );

      final map = customer.toMap();
      expect(map['displayId'], 'CUST-0001');
      expect(map['createdAt'], '2026-04-23');

      final deserialized = CustomerEntity.fromMap(map);
      expect(deserialized.id, customer.id);
      expect(deserialized.displayId, 'CUST-0001');
      expect(deserialized.name, 'Ramesh Kumar');
      expect(deserialized.formattedCreatedAt, '23 April 2026');
    });

    test('RecordEntity enforces ISO datetime [FIX-TIMESTAMPRECORD-1]', () {
      const record = RecordEntity(
        id: 'rec-uuid-1',
        transactionId: 'TXN-0001',
        type: 'GIVEN',
        customerId: 'cust-uuid-1',
        startDate: '2026-04-23T14:30:00',
        endDate: null,
        principalAmount: 50000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
        settledDate: null,
        calculatedInterest: null,
        linkedRecordId: null,
      );

      final map = record.toMap();
      expect(map['startDate'], '2026-04-23T14:30:00');
      expect(map['endDate'], isNull);

      final fromMap = RecordEntity.fromMap(map);
      expect(fromMap.startDate, '2026-04-23T14:30:00');
      expect(fromMap.endDate, isNull);
      expect(fromMap.formattedStartDate, '23 April 2026');
      expect(fromMap.formattedStartDateTime, '23 April 2026, 02:30 PM');
    });

    test('LedgerItemEntity nullability guarantees [FIXLEDGERITEM-NULLABILITY-1]', () {
      const item = LedgerItemEntity(
        id: 'item-uuid-1',
        recordId: 'rec-uuid-1',
        name: 'Gold Ring with Ruby',
        itemCategory: 'Gold 22K',
        description: null, // Strictly nullable
        weight: 10.5,
        purity: 91.6,
        rate: 7200.0,
        itemValue: 69249.6,
        lendPercentage: 80.0,
        lendableAmount: 55399.68,
      );

      final map = item.toMap();
      expect(map['name'], 'Gold Ring with Ruby');
      expect(map['description'], isNull);

      final fromMap = LedgerItemEntity.fromMap(map);
      expect(fromMap.name, 'Gold Ring with Ruby');
      expect(fromMap.description, isNull);
    });

    test('PaymentEntity ISO datetime parsing with legacy fallback [FIX-TIMESTAMP-PAYMENT-1]', () {
      const paymentIso = PaymentEntity(
        id: 'pay-uuid-1',
        recordId: 'rec-uuid-1',
        amount: 1000.0,
        date: '2026-04-23T14:30:00',
        notes: 'Cash payment',
        interestPaid: 1000.0,
        principalPaid: 0.0,
      );

      expect(paymentIso.parsedDateTime.year, 2026);
      expect(paymentIso.parsedDateTime.hour, 14);
      expect(paymentIso.formattedDate, '23 April 2026');
      expect(paymentIso.formattedDateTime, '23 April 2026, 02:30 PM');

      // Legacy date-only fallback test
      const legacyPayment = PaymentEntity(
        id: 'pay-uuid-2',
        recordId: 'rec-uuid-1',
        amount: 1000.0,
        date: '2026-04-23',
        notes: 'Legacy record',
        interestPaid: 1000.0,
        principalPaid: 0.0,
      );

      expect(legacyPayment.parsedDateTime.year, 2026);
      expect(legacyPayment.parsedDateTime.month, 4);
      expect(legacyPayment.parsedDateTime.day, 23);
    });

    test('ItemRateEntity upsert mapping preserves market rate snapshot separation', () {
      const rate = ItemRateEntity(
        id: 'rate-uuid-1',
        itemCategory: 'Gold 22K',
        ratePerUnit: 7250.0,
        effectiveDate: '2026-04-23',
        updatedAt: '2026-04-23T10:00:00',
      );

      final map = rate.toMap();
      expect(map['itemCategory'], 'Gold 22K');
      expect(map['ratePerUnit'], 7250.0);

      final fromMap = ItemRateEntity.fromMap(map);
      expect(fromMap.ratePerUnit, 7250.0);
    });

    test('PaymentEntity paymentId serialization [FIX-ID-FORMAT-1]', () {
      const payment = PaymentEntity(
        id: 'pay-uuid-3',
        recordId: 'rec-uuid-1',
        amount: 5000.0,
        date: '2026-09-20T15:30:00',
        notes: 'September EMI',
        interestPaid: 1000.0,
        principalPaid: 4000.0,
        paymentId: 'PAY092601',
      );

      final map = payment.toMap();
      expect(map['paymentId'], 'PAY092601');

      final fromMap = PaymentEntity.fromMap(map);
      expect(fromMap.paymentId, 'PAY092601');
    });

    test('RetiredIdEntity mapping and structure (Addendum G, FIX-ID-REUSE-1)', () {
      const retired = RetiredIdEntity(
        kind: 'customer',
        displayId: 'CUST26-27-01',
        retiredAt: '2026-09-20T12:00:00',
      );

      final map = retired.toMap();
      expect(map['kind'], 'customer');
      expect(map['displayId'], 'CUST26-27-01');
      expect(map['retiredAt'], '2026-09-20T12:00:00');

      final fromMap = RetiredIdEntity.fromMap(map);
      expect(fromMap.kind, 'customer');
      expect(fromMap.displayId, 'CUST26-27-01');
      expect(fromMap.retiredAt, '2026-09-20T12:00:00');
    });
  });

  group('Drift Schema & Prefix-Scoped ID Generation Tests (§4.1)', () {
    late Database db;
    late DatabaseHelper dbHelper;

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
    });

    tearDown(() async {
      await db.close();
    });

    test('Customer displayId format CUST26-27-01 with FY reset on 1 April [FIX-ID-FORMAT-1]', () async {
      // 1. April 2026 -> FY 26-27, seq 01
      final id1 = await dbHelper.generateNextCustomerDisplayId(db, DateTime(2026, 4, 15));
      expect(id1, 'CUST26-27-01');

      // Insert customer with CUST26-27-01
      await db.insert('customers', {
        'id': 'cust-1',
        'displayId': id1,
        'name': 'Test User 1',
        'phone': '1234567890',
        'address': 'Test',
        'createdAt': '2026-04-15',
      });

      // 2. March 2027 (same FY 26-27) -> seq 02
      final id2 = await dbHelper.generateNextCustomerDisplayId(db, DateTime(2027, 3, 31));
      expect(id2, 'CUST26-27-02');

      // 3. 1 April 2027 (new FY 27-28) -> seq resets automatically to 01
      final id3 = await dbHelper.generateNextCustomerDisplayId(db, DateTime(2027, 4, 1));
      expect(id3, 'CUST27-28-01');
    });

    test('Customer sequence respects retired IDs and never reissues (Addendum G, FIX-ID-REUSE-1)', () async {
      // Insert a retired ID for FY 26-27
      await db.insert('retired_ids', {
        'kind': 'customer',
        'displayId': 'CUST26-27-05',
        'retiredAt': '2026-05-01T10:00:00',
      });

      // Sequence must jump past retired ID 05 to 06
      final nextId = await dbHelper.generateNextCustomerDisplayId(db, DateTime(2026, 6, 1));
      expect(nextId, 'CUST26-27-06');
    });

    test('Transaction ID format TRAN092601 and retired IDs check', () async {
      final txnId1 = await dbHelper.generateNextTransactionId(db, DateTime(2026, 9, 20));
      expect(txnId1, 'TRAN092601');

      // Insert into retired_ids
      await db.insert('retired_ids', {
        'kind': 'transaction',
        'displayId': 'TRAN092601',
        'retiredAt': '2026-09-20T10:00:00',
      });

      final txnId2 = await dbHelper.generateNextTransactionId(db, DateTime(2026, 9, 20));
      expect(txnId2, 'TRAN092602');
    });

    test('Payment ID format PAY092601 and retired IDs check', () async {
      final payId1 = await dbHelper.generateNextPaymentId(db, DateTime(2026, 9, 20));
      expect(payId1, 'PAY092601');

      await db.insert('retired_ids', {
        'kind': 'payment',
        'displayId': 'PAY092603',
        'retiredAt': '2026-09-20T10:00:00',
      });

      final payId2 = await dbHelper.generateNextPaymentId(db, DateTime(2026, 9, 20));
      expect(payId2, 'PAY092604');
    });

    test('Unique constraints on displayId, transactionId, paymentId and composite retired_ids', () async {
      // 1. customers displayId unique
      await db.insert('customers', {
        'id': 'c-1',
        'displayId': 'CUST26-27-01',
        'name': 'A',
        'phone': '1',
        'address': 'A',
        'createdAt': '2026-04-01',
      });
      expect(
        () async => await db.insert('customers', {
          'id': 'c-2',
          'displayId': 'CUST26-27-01',
          'name': 'B',
          'phone': '2',
          'address': 'B',
          'createdAt': '2026-04-01',
        }),
        throwsA(isA<DatabaseException>()),
      );

      // 2. records transactionId unique
      await db.insert('records', {
        'id': 'r-1',
        'transactionId': 'TRAN092601',
        'type': 'GIVEN',
        'customerId': 'c-1',
        'startDate': '2026-09-20T10:00:00',
        'principalAmount': 1000.0,
        'interestRate': 2.0,
        'status': 'ACTIVE',
      });
      expect(
        () async => await db.insert('records', {
          'id': 'r-2',
          'transactionId': 'TRAN092601',
          'type': 'TAKEN',
          'customerId': 'c-1',
          'startDate': '2026-09-20T10:00:00',
          'principalAmount': 2000.0,
          'interestRate': 2.0,
          'status': 'ACTIVE',
        }),
        throwsA(isA<DatabaseException>()),
      );

      // 3. payments paymentId unique
      await db.insert('payments', {
        'id': 'p-1',
        'recordId': 'r-1',
        'amount': 500.0,
        'date': '2026-09-20T10:00:00',
        'interestPaid': 100.0,
        'principalPaid': 400.0,
        'paymentId': 'PAY092601',
      });
      expect(
        () async => await db.insert('payments', {
          'id': 'p-2',
          'recordId': 'r-1',
          'amount': 500.0,
          'date': '2026-09-20T10:00:00',
          'interestPaid': 100.0,
          'principalPaid': 400.0,
          'paymentId': 'PAY092601',
        }),
        throwsA(isA<DatabaseException>()),
      );

      // 4. retired_ids composite primary key (kind, displayId)
      await db.insert('retired_ids', {
        'kind': 'customer',
        'displayId': 'CUST26-27-01',
        'retiredAt': '2026-09-20T10:00:00',
      });
      expect(
        () async => await db.insert('retired_ids', {
          'kind': 'customer',
          'displayId': 'CUST26-27-01',
          'retiredAt': '2026-09-20T11:00:00',
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('Drift DSL Table Mapping Verification (§4.1)', () {
    test('Drift table instances expose correct table names matching §4.1', () {
      final customers = schema.Customers();
      expect(customers.tableName, 'customers');

      final records = schema.Records();
      expect(records.tableName, 'records');

      final ledgerItems = schema.LedgerItems();
      expect(ledgerItems.tableName, 'ledger_items');

      final payments = schema.Payments();
      expect(payments.tableName, 'payments');

      final settings = schema.Settings();
      expect(settings.tableName, 'settings');

      final itemRates = schema.ItemRates();
      expect(itemRates.tableName, 'item_rates');

      final retiredIds = schema.RetiredIds();
      expect(retiredIds.tableName, 'retired_ids');
    });

    test('LedgerItemEntity sourceItemId & copyWith serialization [FIX-ITEM-CUSTODY-2]', () {
      const entity = LedgerItemEntity(
        id: 'item-custody-1',
        recordId: 'rec-1',
        name: 'Gold Necklace',
        itemCategory: 'Gold 22K',
        description: '22K hallmark',
        weight: 15.0,
        purity: 91.6,
        rate: 7000.0,
        itemValue: 96180.0,
        lendPercentage: 75.0,
        lendableAmount: 72135.0,
        sourceItemId: 'original-item-0',
      );

      expect(entity.sourceItemId, 'original-item-0');
      final map = entity.toMap();
      expect(map['sourceItemId'], 'original-item-0');

      final fromMap = LedgerItemEntity.fromMap(map);
      expect(fromMap.sourceItemId, 'original-item-0');

      final copied = entity.copyWith(sourceItemId: 'updated-source-item');
      expect(copied.sourceItemId, 'updated-source-item');
      expect(copied.name, 'Gold Necklace');
    });

    test('RecordRepositoryImpl toFullRecord preserves paymentId and sourceItemId', () {
      final repo = RecordRepositoryImpl();
      const recEntity = RecordEntity(
        id: 'rec-repo-1',
        transactionId: 'TRAN092601',
        type: 'GIVEN',
        customerId: 'cust-1',
        startDate: '2026-09-20T10:00:00',
        principalAmount: 50000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      );

      const itemEntity = LedgerItemEntity(
        id: 'item-repo-1',
        recordId: 'rec-repo-1',
        name: 'Gold Ring',
        itemCategory: 'Gold 22K',
        sourceItemId: 'source-item-xyz',
      );

      const paymentEntity = PaymentEntity(
        id: 'pay-repo-1',
        recordId: 'rec-repo-1',
        amount: 2000.0,
        date: '2026-09-21T12:00:00',
        interestPaid: 1000.0,
        principalPaid: 1000.0,
        paymentId: 'PAY092601',
      );

      final fullRecord = repo.toFullRecord(recEntity, [itemEntity], [paymentEntity]);
      expect(fullRecord.items.first.sourceItemId, 'source-item-xyz');
      expect(fullRecord.payments.first.paymentId, 'PAY092601');
    });
  });
}

