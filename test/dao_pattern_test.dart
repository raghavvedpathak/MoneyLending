import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/data/data.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late RecordDao recordDao;
  late PaymentDao paymentDao;
  late SettingsDao settingsDao;

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
              principalPaid REAL NOT NULL
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
        },
      ),
    );
    recordDao = RecordDao(db);
    paymentDao = PaymentDao(db);
    settingsDao = SettingsDao(db);
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

    test('RecordDao getByCustomer filters by customerId and orders by startDate DESC', () async {
      const c1Rec1 = RecordEntity(
        id: 'rec-c1-1',
        transactionId: 'TXN-000010',
        type: 'GIVEN',
        customerId: 'c-1',
        startDate: '2026-04-01T10:00:00',
        principalAmount: 5000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      );

      const c1Rec2 = RecordEntity(
        id: 'rec-c1-2',
        transactionId: 'TXN-000011',
        type: 'GIVEN',
        customerId: 'c-1',
        startDate: '2026-04-15T10:00:00',
        principalAmount: 7000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      );

      const c2Rec = RecordEntity(
        id: 'rec-c2',
        transactionId: 'TXN-000012',
        type: 'GIVEN',
        customerId: 'c-2',
        startDate: '2026-04-10T10:00:00',
        principalAmount: 9000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      );

      await recordDao.insert(c1Rec1);
      await recordDao.insert(c1Rec2);
      await recordDao.insert(c2Rec);

      final c1Records = await recordDao.getByCustomer('c-1');
      expect(c1Records.length, 2);
      expect(c1Records.first.id, 'rec-c1-2');
      expect(c1Records.last.id, 'rec-c1-1');
    });

    test('RecordDao getActiveGivenRecords filters status and type properly', () async {
      const activeGiven = RecordEntity(
        id: 'rec-1',
        transactionId: 'TXN-000001',
        type: 'GIVEN',
        customerId: 'c-1',
        startDate: '2026-04-23T10:00:00',
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      );

      const activeTaken = RecordEntity(
        id: 'rec-2',
        transactionId: 'TXN-000002',
        type: 'TAKEN',
        customerId: 'c-1',
        startDate: '2026-04-23T11:00:00',
        principalAmount: 5000.0,
        interestRate: 1.5,
        status: 'ACTIVE',
        linkedRecordId: 'rec-1',
      );

      await recordDao.insert(activeGiven);
      await recordDao.insert(activeTaken);

      final givenRecords = await recordDao.getActiveGivenRecords();
      expect(givenRecords.length, 1);
      expect(givenRecords.first.id, 'rec-1');
      expect(givenRecords.first.type, 'GIVEN');
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

    test('RecordDao deleteById deletes directly via query without loading entity', () async {
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
      await recordDao.insert(record);
      expect(await recordDao.getById('rec-del'), isNotNull);

      await recordDao.deleteById('rec-del');
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

    test('RecordDao importRecordsTransactionally rolls back completely on conflict', () async {
      const existing = RecordEntity(
        id: 'rec-exist',
        transactionId: 'TXN-000030',
        type: 'GIVEN',
        customerId: 'c-1',
        startDate: '2026-04-23T12:00:00',
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      );
      await recordDao.insert(existing);

      const batchRec1 = RecordEntity(
        id: 'rec-batch-1',
        transactionId: 'TXN-000031',
        type: 'GIVEN',
        customerId: 'c-1',
        startDate: '2026-04-23T12:00:00',
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      );

      // batchRec2 conflicts with rec-exist
      const batchRec2 = RecordEntity(
        id: 'rec-exist',
        transactionId: 'TXN-000032',
        type: 'GIVEN',
        customerId: 'c-1',
        startDate: '2026-04-23T12:00:00',
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      );

      expect(
        () => recordDao.importRecordsTransactionally(records: [batchRec1, batchRec2]),
        throwsA(isA<DatabaseException>()),
      );

      // rec-batch-1 must NOT have been saved due to atomic rollback
      final rolledBack = await recordDao.getById('rec-batch-1');
      expect(rolledBack, isNull);
    });

    test('PaymentDao getByRecordId orders chronologically ascending [FIX-PAYMENTDAO-1]', () async {
      const payment1 = PaymentEntity(
        id: 'p-1',
        recordId: 'rec-1',
        amount: 500.0,
        date: '2026-04-23T15:00:00',
        notes: 'Later payment',
        interestPaid: 500.0,
        principalPaid: 0.0,
      );

      const payment2 = PaymentEntity(
        id: 'p-2',
        recordId: 'rec-1',
        amount: 300.0,
        date: '2026-04-23T10:00:00',
        notes: 'Earlier payment',
        interestPaid: 300.0,
        principalPaid: 0.0,
      );

      await paymentDao.insert(payment1);
      await paymentDao.insert(payment2);

      final payments = await paymentDao.getByRecordId('rec-1');
      expect(payments.length, 2);
      expect(payments.first.id, 'p-2'); // Earlier payment first
      expect(payments.last.id, 'p-1');
    });

    test('PaymentDao deleteByRecordId cleans up associated payments', () async {
      const payment = PaymentEntity(
        id: 'p-del',
        recordId: 'rec-del-target',
        amount: 250.0,
        date: '2026-04-23T10:00:00',
        notes: 'Cleanup target',
        interestPaid: 250.0,
        principalPaid: 0.0,
      );
      await paymentDao.insert(payment);
      expect((await paymentDao.getByRecordId('rec-del-target')).length, 1);

      await paymentDao.deleteByRecordId('rec-del-target');
      expect((await paymentDao.getByRecordId('rec-del-target')).isEmpty, isTrue);
    });

    test('SettingsDao safely upserts using REPLACE exception', () async {
      const initial = SettingsEntity(name: 'Initial Shop', phone: '111111');
      await settingsDao.upsertSettings(initial);

      const updated = SettingsEntity(name: 'Updated Shop', phone: '222222');
      await settingsDao.upsertSettings(updated);

      final current = await settingsDao.getSettings();
      expect(current.name, 'Updated Shop');
      expect(current.phone, '222222');
    });
  });
}
