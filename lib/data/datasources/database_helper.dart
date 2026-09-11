import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:synchronized/synchronized.dart';

import '../../domain/errors/record_linked_taken_exception.dart';
import '../models/customer_entity.dart';
import '../models/item_rate_entity.dart';
import '../models/ledger_item_entity.dart';
import '../models/payment_entity.dart';
import '../models/record_entity.dart';
import '../models/settings_entity.dart';
import 'daos/customer_dao.dart';
import 'daos/item_rate_dao.dart';
import 'daos/payment_dao.dart';
import 'daos/record_dao.dart';
import 'daos/settings_dao.dart';

/// SQLite Database Manager.
///
/// Mandated by Data Spec §4.1, §4.2, and §4.4:
/// - Cross-platform: Android (native SQLite) + Windows (sqflite_common_ffi).
/// - Thread-safe Customer displayId sequence generator [FIX-DEVCONCURRENCY-1].
/// - Thread-safe Record transactionId sequence generator [FIX-DEV-CONCURRENCY-1].
/// - Anti-footgun: ConflictAlgorithm.abort for records, payments, items.
/// - Single-transaction COUNT guard before deletion [FIX-DEV-TOCTOU-1].
/// - Explicit forceDeleteRecord [FIX-FORCEDELETE-1].
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static final Lock _customerInsertLock = Lock();
  static final Lock _recordInsertLock = Lock();
  static final Lock _rateUpsertLock = Lock();

  DatabaseHelper._init();

  /// Testing constructor for in-memory SQLite isolation.
  DatabaseHelper.forTesting(Database db) {
    _database = db;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('moneylending.db');
    return _database!;
  }

  // DAOs matching §4.3 & §4.4
  Future<RecordDao> get recordDao async => RecordDao(await database);
  Future<PaymentDao> get paymentDao async => PaymentDao(await database);
  Future<CustomerDao> get customerDao async => CustomerDao(await database);
  Future<SettingsDao> get settingsDao async => SettingsDao(await database);
  Future<ItemRateDao> get itemRateDao async => ItemRateDao(await database);

  Future<Database> _initDB(String filePath) async {
    if (Platform.isWindows) {
      if (databaseFactory != databaseFactoryFfi) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
      final docDir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(docDir.path, 'MoneyLending', filePath);
      final dir = Directory(p.dirname(dbPath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: _createDB,
          onConfigure: _onConfigure,
        ),
      );
    } else {
      final dbFolder = await getDatabasesPath();
      final path = p.join(dbFolder, filePath);
      return await openDatabase(
        path,
        version: 1,
        onCreate: _createDB,
        onConfigure: _onConfigure,
      );
    }
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. customers table
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        displayId TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE UNIQUE INDEX idx_customers_displayId ON customers(displayId)');

    // 2. records table
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
        linkedRecordId TEXT,
        FOREIGN KEY (customerId) REFERENCES customers (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE UNIQUE INDEX idx_records_transactionId ON records(transactionId)');
    await db.execute('CREATE INDEX idx_records_customerId ON records(customerId)');

    // 3. ledger_items table
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
        lendableAmount REAL,
        FOREIGN KEY (recordId) REFERENCES records (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_ledger_items_recordId ON ledger_items(recordId)');

    // 4. payments table
    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        recordId TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        notes TEXT,
        interestPaid REAL NOT NULL,
        principalPaid REAL NOT NULL,
        FOREIGN KEY (recordId) REFERENCES records (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_payments_recordId ON payments(recordId)');

    // 5. settings table (single row, id=1)
    await db.execute('''
      CREATE TABLE settings (
        id INTEGER PRIMARY KEY,
        name TEXT,
        phone TEXT,
        address TEXT,
        defaultInterestRate REAL NOT NULL DEFAULT 2.0
      )
    ''');
    await db.insert('settings', const SettingsEntity().toMap());

    // 6. item_rates table
    await db.execute('''
      CREATE TABLE item_rates (
        id TEXT PRIMARY KEY,
        itemCategory TEXT NOT NULL,
        ratePerUnit REAL NOT NULL,
        effectiveDate TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE UNIQUE INDEX idx_item_rates_cat_date ON item_rates(itemCategory, effectiveDate)');
  }

  // ===========================================================================
  // CUSTOMER OPERATIONS & CONCURRENCY-SAFE SEQUENCE [FIX-DEVCONCURRENCY-1]
  // ===========================================================================

  /// Thread-safe generation of next customer displayId (CUST-0001, CUST-0002).
  /// Protected by a Mutex/Lock to prevent race conditions during rapid concurrent inserts.
  Future<String> generateNextCustomerDisplayId(DatabaseExecutor db) async {
    final List<Map<String, dynamic>> result = await db.rawQuery(
      'SELECT MAX(CAST(SUBSTR(displayId, 6) AS INTEGER)) as maxSeq FROM customers',
    );

    int nextSeq = 1;
    if (result.isNotEmpty && result.first['maxSeq'] != null) {
      final currentMax = result.first['maxSeq'] as int;
      nextSeq = currentMax + 1;
    }

    final padded = nextSeq.toString().padLeft(4, '0');
    return 'CUST-$padded';
  }

  /// Inserts a customer with synchronized sequence generation.
  Future<CustomerEntity> insertCustomer(CustomerEntity customer) async {
    return await _customerInsertLock.synchronized(() async {
      final db = await database;
      return await db.transaction((txn) async {
        String effectiveDisplayId = customer.displayId;
        if (effectiveDisplayId.isEmpty) {
          effectiveDisplayId = await generateNextCustomerDisplayId(txn);
        }

        final toInsert = customer.copyWith(displayId: effectiveDisplayId);
        await txn.insert('customers', toInsert.toMap());
        return toInsert;
      });
    });
  }

  Future<List<CustomerEntity>> getAllCustomers() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('customers', orderBy: 'name ASC');
    return maps.map((m) => CustomerEntity.fromMap(m)).toList();
  }

  Future<CustomerEntity?> getCustomerById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return CustomerEntity.fromMap(maps.first);
  }

  // ===========================================================================
  // RECORD OPERATIONS & TRANSACTION ID GENERATION [FIX-DEV-CONCURRENCY-1]
  // ===========================================================================

  /// Thread-safe generation of next transactionId (TXN-000001, TXN-000002).
  /// Protected by Mutex/Lock to avoid race conditions during rapid concurrent inserts.
  Future<String> generateNextTransactionId(DatabaseExecutor db) async {
    final List<Map<String, dynamic>> result = await db.rawQuery(
      'SELECT MAX(CAST(SUBSTR(transactionId, 5) AS INTEGER)) as maxSeq FROM records',
    );

    int nextSeq = 1;
    if (result.isNotEmpty && result.first['maxSeq'] != null) {
      final currentMax = result.first['maxSeq'] as int;
      nextSeq = currentMax + 1;
    }

    final padded = nextSeq.toString().padLeft(6, '0');
    return 'TXN-$padded';
  }

  /// Inserts a Record with synchronized transactionId generation.
  Future<RecordEntity> insertRecord(RecordEntity record) async {
    return await _recordInsertLock.synchronized(() async {
      final db = await database;
      return await db.transaction((txn) async {
        String effectiveTxnId = record.transactionId;
        if (effectiveTxnId.isEmpty) {
          effectiveTxnId = await generateNextTransactionId(txn);
        }

        final toInsert = RecordEntity(
          id: record.id,
          transactionId: effectiveTxnId,
          type: record.type,
          customerId: record.customerId,
          customerName: record.customerName,
          startDate: record.startDate,
          endDate: record.endDate,
          principalAmount: record.principalAmount,
          interestRate: record.interestRate,
          status: record.status,
          settledDate: record.settledDate,
          calculatedInterest: record.calculatedInterest,
          linkedRecordId: record.linkedRecordId,
        );

        await txn.insert('records', toInsert.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);
        return toInsert;
      });
    });
  }

  /// Atomically inserts a record with its ledger items and payments within a single SQLite transaction.
  /// Mandated by §4.4: "Always use @Transaction for multi-table writes: When inserting a new record
  /// with its LedgerItems and Payments atomically, annotate the DAO method with @Transaction.
  /// Without it, a crash midway leaves the DB in a partially-written state."
  Future<RecordEntity> insertRecordWithDetails({
    required RecordEntity record,
    List<LedgerItemEntity> items = const [],
    List<PaymentEntity> payments = const [],
  }) async {
    return await _recordInsertLock.synchronized(() async {
      final db = await database;
      return await db.transaction((txn) async {
        String effectiveTxnId = record.transactionId;
        if (effectiveTxnId.isEmpty) {
          effectiveTxnId = await generateNextTransactionId(txn);
        }

        final toInsert = RecordEntity(
          id: record.id,
          transactionId: effectiveTxnId,
          type: record.type,
          customerId: record.customerId,
          customerName: record.customerName,
          startDate: record.startDate,
          endDate: record.endDate,
          principalAmount: record.principalAmount,
          interestRate: record.interestRate,
          status: record.status,
          settledDate: record.settledDate,
          calculatedInterest: record.calculatedInterest,
          linkedRecordId: record.linkedRecordId,
        );

        await txn.insert('records', toInsert.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);

        for (final item in items) {
          final itemToInsert = item.recordId.isEmpty
              ? LedgerItemEntity(
                  id: item.id,
                  recordId: toInsert.id,
                  name: item.name,
                  itemCategory: item.itemCategory,
                  description: item.description,
                  weight: item.weight,
                  purity: item.purity,
                  rate: item.rate,
                  itemValue: item.itemValue,
                  lendPercentage: item.lendPercentage,
                  lendableAmount: item.lendableAmount,
                )
              : item;
          await txn.insert('ledger_items', itemToInsert.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);
        }

        for (final payment in payments) {
          final paymentToInsert = payment.recordId.isEmpty
              ? PaymentEntity(
                  id: payment.id,
                  recordId: toInsert.id,
                  amount: payment.amount,
                  date: payment.date,
                  notes: payment.notes,
                  interestPaid: payment.interestPaid,
                  principalPaid: payment.principalPaid,
                )
              : payment;
          await txn.insert('payments', paymentToInsert.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);
        }

        return toInsert;
      });
    });
  }

  Future<RecordEntity?> getRecordById(String id) async {
    final db = await database;
    final maps = await db.query(
      'records',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return RecordEntity.fromMap(maps.first);
  }

  Future<List<RecordEntity>> getRecordsByType(String type) async {
    final db = await database;
    final maps = await db.query(
      'records',
      where: 'type = ?',
      whereArgs: [type],
      orderBy: 'startDate DESC',
    );
    return maps.map((m) => RecordEntity.fromMap(m)).toList();
  }

  Future<List<RecordEntity>> getRecordsByCustomer(String customerId) async {
    final db = await database;
    final maps = await db.query(
      'records',
      where: 'customerId = ?',
      whereArgs: [customerId],
      orderBy: 'startDate DESC',
    );
    return maps.map((m) => RecordEntity.fromMap(m)).toList();
  }

  /// Counts how many TAKEN records are linked to this GIVEN record.
  Future<int> countLinkedTakenRecords(String givenRecordId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM records WHERE linkedRecordId = ?',
      [givenRecordId],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// Deletes a record with TOCTOU-safe transaction guard [FIX-DEV-TOCTOU-1].
  /// If dependent TAKEN records exist, throws RecordLinkedTakenException.
  Future<void> deleteRecord(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      final result = await txn.rawQuery(
        'SELECT COUNT(*) as cnt FROM records WHERE linkedRecordId = ?',
        [id],
      );
      final count = (result.first['cnt'] as int?) ?? 0;
      if (count > 0) {
        throw RecordLinkedTakenException(linkedCount: count);
      }
      await txn.delete('records', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Force deletes a record unconditionally skipping the COUNT check [FIX-FORCEDELETE-1].
  /// Called after user confirms the deletion dialog.
  Future<void> forceDeleteRecord(String id) async {
    final db = await database;
    await db.delete('records', where: 'id = ?', whereArgs: [id]);
  }

  // ===========================================================================
  // LEDGER ITEM OPERATIONS
  // ===========================================================================

  Future<void> insertLedgerItem(LedgerItemEntity item) async {
    final db = await database;
    await db.insert('ledger_items', item.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<List<LedgerItemEntity>> getLedgerItemsByRecord(String recordId) async {
    final db = await database;
    final maps = await db.query(
      'ledger_items',
      where: 'recordId = ?',
      whereArgs: [recordId],
    );
    return maps.map((m) => LedgerItemEntity.fromMap(m)).toList();
  }

  // ===========================================================================
  // PAYMENT OPERATIONS
  // ===========================================================================

  Future<void> insertPayment(PaymentEntity payment) async {
    final db = await database;
    await db.insert('payments', payment.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);
  }

  /// Mandated by [FIX-PAYMENTDAO-1]: ORDER BY date ASC
  Future<List<PaymentEntity>> getPaymentsByRecord(String recordId) async {
    final db = await database;
    final maps = await db.query(
      'payments',
      where: 'recordId = ?',
      whereArgs: [recordId],
      orderBy: 'date ASC',
    );
    return maps.map((m) => PaymentEntity.fromMap(m)).toList();
  }

  // ===========================================================================
  // ITEM RATES OPERATIONS (WITH SYNCHRONIZED UPSERT) [FIX-ARCH-ITEMRATE-1]
  // ===========================================================================

  /// Synchronized check-then-branch upsert (§4.5):
  /// - Protected by _rateUpsertLock to eliminate concurrent race condition [FIX-DEVCONCURRENCY-1].
  /// - Checks existing by (itemCategory, effectiveDate) inside a single transaction.
  /// - Preserves the existing UUID id on update (never uses REPLACE).
  Future<void> upsertItemRate(ItemRateEntity rate) async {
    await _rateUpsertLock.synchronized(() async {
      final dao = await itemRateDao;
      await dao.upsert(rate);
    });
  }

  Future<ItemRateEntity?> getLatestRateForCategory(String category) async {
    final dao = await itemRateDao;
    return await dao.getLatestForCategory(category);
  }

  Future<List<ItemRateEntity>> getLatestRatesForEveryCategory() async {
    final dao = await itemRateDao;
    return await dao.getLatestForEveryCategory();
  }

  Future<List<ItemRateEntity>> getRatesForDate(String date) async {
    final dao = await itemRateDao;
    return await dao.getRatesForDate(date);
  }

  // ===========================================================================
  // SETTINGS OPERATIONS [FIX-ARCH-SETTINGS-1]
  // ===========================================================================

  Future<SettingsEntity> getSettings() async {
    final dao = await settingsDao;
    return await dao.getSettings();
  }

  Future<void> updateSettings(SettingsEntity settings) async {
    final dao = await settingsDao;
    await dao.upsertSettings(settings);
  }
}
