import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/data/data.dart';
import 'package:money_lending/domain/domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late RecordDao recordDao;
  late PaymentDao paymentDao;
  late SettingsDao settingsDao;
  late DatabaseHelper dbHelper;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE customers (
              id TEXT PRIMARY KEY,
              displayId TEXT NOT NULL UNIQUE,
              name TEXT NOT NULL,
              phone TEXT NOT NULL,
              address TEXT,
              createdAt TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE records (
              id TEXT PRIMARY KEY,
              transactionId TEXT NOT NULL UNIQUE,
              type TEXT NOT NULL,
              customerId TEXT NOT NULL,
              customerName TEXT,
              startDate TEXT NOT NULL,
              endDate TEXT,
              principalAmount REAL NOT NULL,
              interestRate REAL NOT NULL,
              status TEXT NOT NULL,
              settledDate TEXT,
              calculatedInterest REAL,
              linkedRecordId TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE ledger_items (
              id TEXT PRIMARY KEY,
              recordId TEXT NOT NULL,
              name TEXT NOT NULL,
              itemCategory TEXT NOT NULL,
              description TEXT,
              weight REAL,
              purity REAL,
              rate REAL,
              itemValue REAL,
              lendPercentage REAL,
              lendableAmount REAL
            )
          ''');
          await db.execute('''
            CREATE TABLE payments (
              id TEXT PRIMARY KEY,
              recordId TEXT NOT NULL,
              amount REAL NOT NULL,
              date TEXT NOT NULL,
              notes TEXT,
              interestPaid REAL NOT NULL,
              principalPaid REAL NOT NULL,
              paymentId TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE settings (
              id INTEGER PRIMARY KEY,
              name TEXT,
              phone TEXT,
              address TEXT,
              defaultInterestRate REAL NOT NULL DEFAULT 2.0
            )
          ''');
          await db.execute('''
            CREATE TABLE item_rates (
              itemCategory TEXT PRIMARY KEY,
              rate REAL NOT NULL,
              updatedAt TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE retired_ids (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              kind TEXT NOT NULL,
              displayId TEXT NOT NULL,
              retiredAt TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    recordDao = RecordDao(db);
    paymentDao = PaymentDao(db);
    settingsDao = SettingsDao(db);
    dbHelper = DatabaseHelper.forTesting(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('DAO Pattern Tests (§4.4)', () {
    test('RecordDao getByStatus orders by startDate DESC lexicographically', () async {
      const olderRecord = RecordEntity(
        id: 'rec-old',
        transactionId: 'TXN-000001',
        type: 'GIVEN',
        customerId: 'c-1',
        startDate: '2026-04-20T10:00:00',
        endDate: null,
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      );

      const newerRecord = RecordEntity(
        id: 'rec-new',
        transactionId: 'TXN-000002',
        type: 'GIVEN',
        customerId: 'c-1',
        startDate: '2026-04-25T10:00:00',
        endDate: null,
        principalAmount: 20000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      );

      await recordDao.insert(olderRecord);
      await recordDao.insert(newerRecord);

      final active = await recordDao.getByStatus('ACTIVE');
      expect(active.length, 2);
      expect(active.first.id, 'rec-new');
      expect(active.last.id, 'rec-old');
    });

    test('RecordDao watchByStatus streams records ordered by startDate DESC', () async {
      const older = RecordEntity(
        id: 'rec-w-1',
        transactionId: 'TXN-000101',
        type: 'GIVEN',
        customerId: 'c-1',
        startDate: '2026-04-10T10:00:00',
        principalAmount: 5000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      );
      const newer = RecordEntity(
        id: 'rec-w-2',
        transactionId: 'TXN-000102',
        type: 'GIVEN',
        customerId: 'c-1',
        startDate: '2026-04-20T10:00:00',
        principalAmount: 7000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      );

      await recordDao.insertRecord(older);
      await recordDao.insertRecord(newer);

      final stream = recordDao.watchByStatus(RecordStatus.active);
      final initialList = await stream.first;
      expect(initialList.length, 2);
      expect(initialList.first.id, 'rec-w-2');
      expect(initialList.last.id, 'rec-w-1');
    });

    test('RecordDao watchByCustomer filters by customerId and orders by startDate DESC', () async {
      const c1Rec = RecordEntity(
        id: 'rec-c1',
        transactionId: 'TXN-000110',
        type: 'GIVEN',
        customerId: 'c-10',
        startDate: '2026-04-01T10:00:00',
        principalAmount: 5000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      );
      const c2Rec = RecordEntity(
        id: 'rec-c2',
        transactionId: 'TXN-000111',
        type: 'GIVEN',
        customerId: 'c-20',
        startDate: '2026-04-15T10:00:00',
        principalAmount: 7000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      );

      await recordDao.insert(c1Rec);
      await recordDao.insert(c2Rec);

      final c1List = await recordDao.watchByCustomer('c-10').first;
      expect(c1List.length, 1);
      expect(c1List.first.id, 'rec-c1');
    });

    test('RecordDao watchActiveGivenRecords and typed equalsValue() [FIX-ENUM-CASE-1] & [FIX-PERF-EAGERLOAD-2]', () async {
      const activeGivenUpper = RecordEntity(
        id: 'rec-ag-1',
        transactionId: 'TXN-000120',
        type: 'GIVEN',
        customerId: 'c-1',
        startDate: '2026-04-23T10:00:00',
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      );

      const activeGivenLower = RecordEntity(
        id: 'rec-ag-2',
        transactionId: 'TXN-000121',
        type: 'given',
        customerId: 'c-1',
        startDate: '2026-04-24T10:00:00',
        principalAmount: 12000.0,
        interestRate: 2.0,
        status: 'active',
      );

      const activeTaken = RecordEntity(
        id: 'rec-at',
        transactionId: 'TXN-000122',
        type: 'TAKEN',
        customerId: 'c-1',
        startDate: '2026-04-23T11:00:00',
        principalAmount: 5000.0,
        interestRate: 1.5,
        status: 'ACTIVE',
      );

      await recordDao.insert(activeGivenUpper);
      await recordDao.insert(activeGivenLower);
      await recordDao.insert(activeTaken);

      final givenRecords = await recordDao.watchActiveGivenRecords().first;
      expect(givenRecords.length, 2);
      expect(givenRecords.first.id, 'rec-ag-2'); // Newer first
      expect(givenRecords.last.id, 'rec-ag-1');
    });

    test('RecordDao enforces ConflictAlgorithm.abort on duplicate insert (Anti-Footgun)', () async {
      const record = RecordEntity(
        id: 'rec-duplicate',
        transactionId: 'TXN-000003',
        type: 'GIVEN',
        customerId: 'c-1',
        startDate: '2026-04-23T12:00:00',
        principalAmount: 15000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      );

      await recordDao.insert(record);
      // Duplicate insertion should throw DatabaseException rather than wiping child rows
      expect(() => recordDao.insert(record), throwsA(isA<DatabaseException>()));
    });

    test('RecordDao safe upsert branches cleanly between insert and update', () async {
      const record = RecordEntity(
        id: 'rec-upsert',
        transactionId: 'TXN-000004',
        type: 'GIVEN',
        customerId: 'c-1',
        startDate: '2026-04-23T12:00:00',
        principalAmount: 15000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      );

      // First upsert inserts
      await recordDao.upsert(record);
      var fetched = await recordDao.getById('rec-upsert');
      expect(fetched, isNotNull);
      expect(fetched!.principalAmount, 15000.0);

      // Second upsert updates
      const updated = RecordEntity(
        id: 'rec-upsert',
        transactionId: 'TXN-000004',
        type: 'GIVEN',
        customerId: 'c-1',
        startDate: '2026-04-23T12:00:00',
        principalAmount: 18000.0,
        interestRate: 2.5,
        status: 'ACTIVE',
      );
      await recordDao.upsert(updated);
      fetched = await recordDao.getById('rec-upsert');
      expect(fetched!.principalAmount, 18000.0);
      expect(fetched.interestRate, 2.5);
    });

    test('RecordDao insertRecord, updateRecord, and deleteById work with WHERE-clause deletes', () async {
      const record = RecordEntity(
        id: 'rec-del',
        transactionId: 'TXN-000005',
        type: 'GIVEN',
        customerId: 'c-1',
        startDate: '2026-04-23T12:00:00',
        principalAmount: 5000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      );
      final insertRes = await recordDao.insertRecord(record);
      expect(insertRes, greaterThan(0));

      const updated = RecordEntity(
        id: 'rec-del',
        transactionId: 'TXN-000005',
        type: 'GIVEN',
        customerId: 'c-1',
        startDate: '2026-04-23T12:00:00',
        principalAmount: 6000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      );
      final updateRes = await recordDao.updateRecord(updated);
      expect(updateRes, isTrue);

      final deletedRows = await recordDao.deleteById('rec-del');
      expect(deletedRows, 1);
      expect(await recordDao.getById('rec-del'), isNull);
    });

    test('RecordDao insertWithDetails atomically writes record and items in a single transaction', () async {
      const record = RecordEntity(
        id: 'rec-atomic',
        transactionId: 'TXN-000020',
        type: 'GIVEN',
        customerId: 'c-1',
        startDate: '2026-04-23T12:00:00',
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      );

      final item = {
        'id': 'item-1',
        'recordId': 'rec-atomic',
        'name': 'Gold Ring',
        'itemCategory': 'GOLD_22K',
        'weight': 10.0,
        'purity': 91.6,
        'rate': 6000.0,
        'itemValue': 54960.0,
        'lendPercentage': 80.0,
        'lendableAmount': 43968.0,
      };

      await recordDao.insertWithDetails(
        record: record,
        items: [item],
      );

      final fetchedRecord = await recordDao.getById('rec-atomic');
      expect(fetchedRecord, isNotNull);

      final items = await db.query('ledger_items', where: 'recordId = ?', whereArgs: ['rec-atomic']);
      expect(items.length, 1);
      expect(items.first['name'], 'Gold Ring');
    });

    test('PaymentDao watchByRecordId orders chronologically ascending [FIX-PAYMENTDAO-1]', () async {
      const payment1 = PaymentEntity(
        id: 'p-1',
        recordId: 'rec-1',
        amount: 500.0,
        date: '2026-04-23T15:00:00',
        notes: 'Later payment',
        interestPaid: 500.0,
        principalPaid: 0.0,
        paymentId: 'PAY042601',
      );

      const payment2 = PaymentEntity(
        id: 'p-2',
        recordId: 'rec-1',
        amount: 300.0,
        date: '2026-04-23T10:00:00',
        notes: 'Earlier payment',
        interestPaid: 300.0,
        principalPaid: 0.0,
        paymentId: 'PAY042602',
      );

      await paymentDao.insertPayment(payment1);
      await paymentDao.insertPayment(payment2);

      final payments = await paymentDao.watchByRecordId('rec-1').first;
      expect(payments.length, 2);
      expect(payments.first.id, 'p-2'); // Earlier payment first
      expect(payments.last.id, 'p-1');
    });

    test('PaymentDao paymentIdsByRecordId and deleteByRecordId [FIX-PAYMENTDAO-1]', () async {
      const payment1 = PaymentEntity(
        id: 'p-pids-1',
        recordId: 'rec-pids',
        amount: 200.0,
        date: '2026-04-20T10:00:00',
        interestPaid: 200.0,
        principalPaid: 0.0,
        paymentId: 'PAY042610',
      );
      const payment2 = PaymentEntity(
        id: 'p-pids-2',
        recordId: 'rec-pids',
        amount: 300.0,
        date: '2026-04-21T10:00:00',
        interestPaid: 300.0,
        principalPaid: 0.0,
        paymentId: 'PAY042611',
      );

      await paymentDao.insert(payment1);
      await paymentDao.insert(payment2);

      final ids = await paymentDao.paymentIdsByRecordId('rec-pids');
      expect(ids, containsAll(['PAY042610', 'PAY042611']));

      final deletedCount = await paymentDao.deleteByRecordId('rec-pids');
      expect(deletedCount, 2);
      expect(await paymentDao.getByRecordId('rec-pids'), isEmpty);
    });

    test('forceDeleteRecord retires paymentId and transactionId using PaymentDao.paymentIdsByRecordId before cleanup', () async {
      await db.insert('records', {
        'id': 'rec-force-1',
        'transactionId': 'TRAN042699',
        'type': 'GIVEN',
        'customerId': 'c-1',
        'startDate': '2026-04-20T10:00:00',
        'principalAmount': 10000.0,
        'interestRate': 2.0,
        'status': 'ACTIVE',
      });

      await paymentDao.insert(const PaymentEntity(
        id: 'pay-force-1',
        recordId: 'rec-force-1',
        amount: 500.0,
        date: '2026-04-22T10:00:00',
        interestPaid: 500.0,
        principalPaid: 0.0,
        paymentId: 'PAY042699',
      ));

      await dbHelper.forceDeleteRecord('rec-force-1');

      // Check records and payments deleted
      expect(await recordDao.getById('rec-force-1'), isNull);
      expect(await paymentDao.getByRecordId('rec-force-1'), isEmpty);

      // Check retired_ids contains both transaction and payment display IDs
      final retired = await db.query('retired_ids');
      final retiredDisplayIds = retired.map((r) => r['displayId']).toList();
      expect(retiredDisplayIds, contains('TRAN042699'));
      expect(retiredDisplayIds, contains('PAY042699'));
    });

    test('Transactional replace-all backup restore [FIX-ID-BACKUP-1] preserves settings and item_rates, and rolls back on failure', () async {
      // 1. Existing data
      await settingsDao.upsertSettings(const SettingsEntity(id: 1, name: 'Original Shop', phone: '999999'));
      await db.insert('item_rates', {
        'itemCategory': 'GOLD_22K',
        'rate': 5500.0,
        'updatedAt': '2026-04-01T10:00:00',
      });
      await db.insert('customers', {
        'id': 'c-prev',
        'displayId': 'CUST26-27-01',
        'name': 'Old Customer',
        'phone': '1234567890',
        'createdAt': '2026-04-01',
      });
      await db.insert('records', {
        'id': 'rec-prev',
        'transactionId': 'TRAN042601',
        'type': 'GIVEN',
        'customerId': 'c-prev',
        'startDate': '2026-04-01T10:00:00',
        'principalAmount': 10000.0,
        'interestRate': 2.0,
        'status': 'ACTIVE',
      });

      // 2. Successful replace-all backup restore
      final backupCustomers = [
        {
          'id': 'c-new',
          'displayId': 'CUST26-27-02',
          'name': 'Restored Customer',
          'phone': '9876543210',
          'createdAt': '2026-04-10',
        }
      ];
      final backupRecords = [
        {
          'id': 'rec-new',
          'transactionId': 'TRAN042602',
          'type': 'GIVEN',
          'customerId': 'c-new',
          'startDate': '2026-04-10T10:00:00',
          'principalAmount': 20000.0,
          'interestRate': 2.0,
          'status': 'ACTIVE',
        }
      ];
      final backupItems = [
        {
          'id': 'item-new',
          'recordId': 'rec-new',
          'name': 'Gold Chain',
          'itemCategory': 'GOLD_22K',
          'weight': 10.0,
          'purity': 91.6,
          'rate': 5500.0,
          'itemValue': 50000.0,
          'lendPercentage': 75.0,
          'lendableAmount': 37500.0,
        }
      ];
      final backupPayments = [
        {
          'id': 'pay-new',
          'recordId': 'rec-new',
          'amount': 1000.0,
          'date': '2026-04-15T10:00:00',
          'interestPaid': 1000.0,
          'principalPaid': 0.0,
          'paymentId': 'PAY042605',
        }
      ];

      await dbHelper.restoreBackupTransactionally(
        customers: backupCustomers,
        records: backupRecords,
        ledgerItems: backupItems,
        payments: backupPayments,
      );

      // Old customer and record wiped (replace-all)
      expect(await db.query('customers', where: 'id = ?', whereArgs: ['c-prev']), isEmpty);
      expect(await db.query('records', where: 'id = ?', whereArgs: ['rec-prev']), isEmpty);

      // New data restored
      expect((await db.query('customers')).length, 1);
      expect((await db.query('records')).length, 1);
      expect((await db.query('ledger_items')).length, 1);
      expect((await db.query('payments')).length, 1);

      // Settings and item_rates preserved and never touched!
      final settings = await settingsDao.getSettings();
      expect(settings.name, 'Original Shop');
      final rates = await db.query('item_rates');
      expect(rates.first['rate'], 5500.0);

      // 3. Rollback on failure test
      final faultyCustomers = [
        {
          'id': 'c-faulty-1',
          'displayId': 'CUST26-27-99',
          'name': 'Faulty 1',
          'phone': '0000',
          'createdAt': '2026-04-10',
        },
        {
          'id': 'c-faulty-2',
          'displayId': 'CUST26-27-99', // duplicate displayId triggers SQLite constraint error
          'name': 'Faulty 2',
          'phone': '0000',
          'createdAt': '2026-04-10',
        },
      ];

      expect(
        () => dbHelper.restoreBackupTransactionally(
          customers: faultyCustomers,
          records: backupRecords,
          ledgerItems: backupItems,
          payments: backupPayments,
        ),
        throwsA(isA<DatabaseException>()),
      );

      // Data before the failed restore is preserved due to complete atomic rollback
      final postFailureCusts = await db.query('customers');
      expect(postFailureCusts.first['id'], 'c-new');
    });

    test('@DataClassName typedefs match Data Spec §4.4', () {
      expect(RecordEntityData, RecordEntity);
      expect(PaymentEntityData, PaymentEntity);
      expect(CustomerEntityData, CustomerEntity);
      expect(LedgerItemEntityData, LedgerItemEntity);
      expect(SettingsEntityData, SettingsEntity);
      expect(ItemRateEntityData, ItemRateEntity);
      expect(RetiredIdEntityData, RetiredIdEntity);
    });
  });
}
