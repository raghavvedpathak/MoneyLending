import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show databaseFactorySqflitePlugin;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:synchronized/synchronized.dart';

import '../../core/utils/uuid_generator.dart';
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
  static final Lock _paymentInsertLock = Lock();

  DatabaseHelper._init();

  Database? _isolatedDb;

  DatabaseHelper._isolated(Database db) : _isolatedDb = db;

  /// Testing constructor for in-memory SQLite isolation.
  DatabaseHelper.forTesting(Database db) {
    _database = db;
    _isolatedDb = db;
  }

  /// Opens a dedicated, isolated database connection for background isolates (§4.3 [FIX-BG-DB-1]).
  ///
  /// The background isolate running the exact-alarm callback has no ProviderScope and
  /// cannot read appDatabaseProvider. It opens its own connection to moneylending.db with
  /// identical PRAGMAs (foreign_keys = ON, journal_mode = WAL, busy_timeout = 5000),
  /// constructs repositories by hand, reads them, and closes this connection in a finally block.
  static Future<DatabaseHelper> openIsolated({String filePath = 'moneylending.db'}) async {
    final rawDb = await instance._openRawDatabase(filePath, singleInstance: false);
    return DatabaseHelper._isolated(rawDb);
  }

  /// Closes the database connection (§4.3 [FIX-ARCH-DB-1] & [FIX-BG-DB-1]).
  Future<void> close() async {
    if (_isolatedDb != null) {
      await _isolatedDb!.close();
      _isolatedDb = null;
    } else if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  /// Creates all Drift/SQLite tables for testing environments.
  static Future<void> createTablesForTesting(Database db) async {
    await instance._createDB(db, 1);
  }

  Future<Database> get database async {
    if (_isolatedDb != null) return _isolatedDb!;
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
    return _openRawDatabase(filePath);
  }

  Future<Database> _openRawDatabase(String filePath, {bool singleInstance = true}) async {
    if (Platform.isWindows) {
      final docDir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(docDir.path, 'MoneyLending', filePath);
      final dir = Directory(p.dirname(dbPath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          singleInstance: singleInstance,
          onCreate: _createDB,
          onConfigure: _onConfigure,
        ),
      );
    } else {
      try {
        databaseFactory;
      } catch (_) {
        databaseFactory = databaseFactorySqflitePlugin;
      }
      final dbFolder = await getDatabasesPath();
      final path = p.join(dbFolder, filePath);
      return await openDatabase(
        path,
        version: 1,
        singleInstance: singleInstance,
        onCreate: _createDB,
        onConfigure: _onConfigure,
      );
    }
  }

  Future<void> _onConfigure(Database db) async {
    try {
      await db.execute('PRAGMA foreign_keys = ON');
    } catch (_) {}
    try {
      await db.rawQuery('PRAGMA journal_mode = WAL');
    } catch (_) {
      try {
        await db.execute('PRAGMA journal_mode = WAL');
      } catch (_) {}
    }
    try {
      await db.execute('PRAGMA busy_timeout = 5000');
    } catch (_) {}
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
    // DO NOT CHANGE TO INTEGER — switching to paise storage requires a Drift schema migration; money is a REAL rounded to 2 decimals with roundMoney(); see §4.2 and Addendum J.1.
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
    // DO NOT CHANGE TO INTEGER — switching to paise storage requires a Drift schema migration; money is a REAL rounded to 2 decimals with roundMoney(); see §4.2 and Addendum J.1.
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
    // DO NOT CHANGE TO INTEGER — switching to paise storage requires a Drift schema migration; money is a REAL rounded to 2 decimals with roundMoney(); see §4.2 and Addendum J.1.
    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        recordId TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        notes TEXT,
        interestPaid REAL NOT NULL,
        principalPaid REAL NOT NULL,
        paymentId TEXT,
        FOREIGN KEY (recordId) REFERENCES records (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_payments_recordId ON payments(recordId)');
    await db.execute("CREATE UNIQUE INDEX idx_payments_paymentId ON payments(paymentId) WHERE paymentId IS NOT NULL AND paymentId != ''");

    // 5. settings table (single row, id=1)
    // DO NOT CHANGE TO INTEGER — switching to paise storage requires a Drift schema migration; money is a REAL rounded to 2 decimals with roundMoney(); see §4.2 and Addendum J.1.
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
    // DO NOT CHANGE TO INTEGER — switching to paise storage requires a Drift schema migration; money is a REAL rounded to 2 decimals with roundMoney(); see §4.2 and Addendum J.1.
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

    // 7. retired_ids table (Addendum G, FIX-ID-REUSE-1)
    await db.execute('''
      CREATE TABLE retired_ids (
        kind TEXT NOT NULL,
        displayId TEXT NOT NULL,
        retiredAt TEXT NOT NULL,
        PRIMARY KEY (kind, displayId)
      )
    ''');
  }

  // ===========================================================================
  // CUSTOMER OPERATIONS & CONCURRENCY-SAFE SEQUENCE [FIX-DEVCONCURRENCY-1]
  // ===========================================================================

  /// Thread-safe generation of next customer displayId in the format CUST26-27-01 [FIX-ID-FORMAT-1].
  /// Format: CUST + FY start year (2 digits) + - + FY end year (2 digits) + - + sequence (2 digits).
  /// Respects retired customer displayIds (Addendum G, FIX-ID-REUSE-1).
  Future<String> generateNextCustomerDisplayId(DatabaseExecutor db, [DateTime? date]) async {
    final refDate = date ?? DateTime.now();
    final year = refDate.year;
    final month = refDate.month;
    final startYear = (month >= 4 ? year : year - 1) % 100;
    final endYear = (month >= 4 ? year + 1 : year) % 100;
    final prefix = 'CUST${startYear.toString().padLeft(2, '0')}-${endYear.toString().padLeft(2, '0')}-';

    final result = await db.rawQuery(
      'SELECT MAX(CAST(SUBSTR(displayId, ?) AS INTEGER)) as maxSeq FROM customers WHERE displayId LIKE ?',
      [prefix.length + 1, '$prefix%'],
    );

    int maxCust = 0;
    if (result.isNotEmpty && result.first['maxSeq'] != null) {
      maxCust = (result.first['maxSeq'] as num).toInt();
    }

    int maxRetired = 0;
    try {
      final retiredResult = await db.rawQuery(
        'SELECT MAX(CAST(SUBSTR(displayId, ?) AS INTEGER)) as maxSeq FROM retired_ids WHERE kind = ? AND displayId LIKE ?',
        [prefix.length + 1, 'customer', '$prefix%'],
      );
      if (retiredResult.isNotEmpty && retiredResult.first['maxSeq'] != null) {
        maxRetired = (retiredResult.first['maxSeq'] as num).toInt();
      }
    } catch (_) {}

    final nextSeq = (maxCust > maxRetired ? maxCust : maxRetired) + 1;
    final padded = nextSeq.toString().padLeft(2, '0');
    return '$prefix$padded';
  }

  /// Inserts a customer with synchronized sequence generation.
  Future<CustomerEntity> insertCustomer(CustomerEntity customer) async {
    return await _customerInsertLock.synchronized(() async {
      final db = await database;
      return await db.transaction((txn) async {
        String effectiveDisplayId = customer.displayId;
        if (effectiveDisplayId.isEmpty) {
          DateTime? createdDate;
          try {
            createdDate = DateTime.parse(customer.createdAt);
          } catch (_) {}
          effectiveDisplayId = await generateNextCustomerDisplayId(txn, createdDate);
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

  /// Thread-safe generation of next transactionId in the format TRAN092601 [FIX-ID-FORMAT-1].
  /// Format: TRAN + month (2 digits) + year (2 digits) + sequence (2 digits).
  /// Respects retired transactionIds (Addendum G, FIX-ID-REUSE-1).
  Future<String> generateNextTransactionId(DatabaseExecutor db, [DateTime? date]) async {
    final refDate = date ?? DateTime.now();
    final month = refDate.month.toString().padLeft(2, '0');
    final year = (refDate.year % 100).toString().padLeft(2, '0');
    final prefix = 'TRAN$month$year';

    final result = await db.rawQuery(
      'SELECT MAX(CAST(SUBSTR(transactionId, ?) AS INTEGER)) as maxSeq FROM records WHERE transactionId LIKE ?',
      [prefix.length + 1, '$prefix%'],
    );

    int maxRecord = 0;
    if (result.isNotEmpty && result.first['maxSeq'] != null) {
      maxRecord = (result.first['maxSeq'] as num).toInt();
    }

    int maxRetired = 0;
    try {
      final retiredResult = await db.rawQuery(
        'SELECT MAX(CAST(SUBSTR(displayId, ?) AS INTEGER)) as maxSeq FROM retired_ids WHERE kind = ? AND displayId LIKE ?',
        [prefix.length + 1, 'transaction', '$prefix%'],
      );
      if (retiredResult.isNotEmpty && retiredResult.first['maxSeq'] != null) {
        maxRetired = (retiredResult.first['maxSeq'] as num).toInt();
      }
    } catch (_) {}

    final nextSeq = (maxRecord > maxRetired ? maxRecord : maxRetired) + 1;
    final padded = nextSeq.toString().padLeft(2, '0');
    return '$prefix$padded';
  }

  /// Thread-safe generation of next paymentId in the format PAY092601 [FIX-ID-FORMAT-1].
  /// Format: PAY + month (2 digits) + year (2 digits) + sequence (2 digits).
  /// Respects retired paymentIds (Addendum G, FIX-ID-REUSE-1).
  Future<String> generateNextPaymentId(DatabaseExecutor db, [DateTime? date]) async {
    final refDate = date ?? DateTime.now();
    final month = refDate.month.toString().padLeft(2, '0');
    final year = (refDate.year % 100).toString().padLeft(2, '0');
    final prefix = 'PAY$month$year';

    int maxPayment = 0;
    try {
      final result = await db.rawQuery(
        'SELECT MAX(CAST(SUBSTR(paymentId, ?) AS INTEGER)) as maxSeq FROM payments WHERE paymentId LIKE ?',
        [prefix.length + 1, '$prefix%'],
      );

      if (result.isNotEmpty && result.first['maxSeq'] != null) {
        maxPayment = (result.first['maxSeq'] as num).toInt();
      }
    } catch (_) {}

    int maxRetired = 0;
    try {
      final retiredResult = await db.rawQuery(
        'SELECT MAX(CAST(SUBSTR(displayId, ?) AS INTEGER)) as maxSeq FROM retired_ids WHERE kind = ? AND displayId LIKE ?',
        [prefix.length + 1, 'payment', '$prefix%'],
      );
      if (retiredResult.isNotEmpty && retiredResult.first['maxSeq'] != null) {
        maxRetired = (retiredResult.first['maxSeq'] as num).toInt();
      }
    } catch (_) {}

    final nextSeq = (maxPayment > maxRetired ? maxPayment : maxRetired) + 1;
    final padded = nextSeq.toString().padLeft(2, '0');
    return '$prefix$padded';
  }

  /// Inserts a Record with synchronized transactionId generation.
  Future<RecordEntity> insertRecord(RecordEntity record) async {
    return await _recordInsertLock.synchronized(() async {
      final db = await database;
      return await db.transaction((txn) async {
        String effectiveTxnId = record.transactionId;
        if (effectiveTxnId.isEmpty) {
          effectiveTxnId = await generateNextTransactionId(txn, record.parsedStartDate);
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
          effectiveTxnId = await generateNextTransactionId(txn, record.parsedStartDate);
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
          String effectivePaymentId = payment.paymentId;
          if (effectivePaymentId.isEmpty) {
            effectivePaymentId = await generateNextPaymentId(txn, payment.parsedDateTime);
          }
          final paymentToInsert = payment.recordId.isEmpty
              ? PaymentEntity(
                  id: payment.id,
                  recordId: toInsert.id,
                  amount: payment.amount,
                  date: payment.date,
                  notes: payment.notes,
                  interestPaid: payment.interestPaid,
                  principalPaid: payment.principalPaid,
                  paymentId: effectivePaymentId,
                )
              : payment.copyWith(paymentId: effectivePaymentId);
          try {
            await txn.insert('payments', paymentToInsert.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);
          } catch (_) {
            final fallbackMap = paymentToInsert.toMap()..remove('paymentId');
            await txn.insert('payments', fallbackMap, conflictAlgorithm: ConflictAlgorithm.abort);
          }
        }

        return toInsert;
      });
    });
  }

  /// Atomically updates a record and its collateral items within a single SQLite transaction.
  Future<void> updateRecordWithDetails({
    required RecordEntity record,
    List<LedgerItemEntity> items = const [],
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'records',
        record.toMap(),
        where: 'id = ?',
        whereArgs: [record.id],
      );

      // Re-sync collateral items for this record
      await txn.delete(
        'ledger_items',
        where: 'recordId = ?',
        whereArgs: [record.id],
      );

      for (final item in items) {
        final itemToInsert = item.recordId.isEmpty
            ? LedgerItemEntity(
                id: item.id.isEmpty ? AppUuid.generate() : item.id,
                recordId: record.id,
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
  /// [FIX-ID-DELETE-1] (v1.13) Fires when record has dependent TAKEN records OR payments.
  Future<void> deleteRecord(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      final linkedResult = await txn.rawQuery(
        'SELECT COUNT(*) as cnt FROM records WHERE linkedRecordId = ?',
        [id],
      );
      final linkedCount = (linkedResult.first['cnt'] as int?) ?? 0;

      final paymentResult = await txn.rawQuery(
        'SELECT COUNT(*) as cnt FROM payments WHERE recordId = ?',
        [id],
      );
      final paymentCount = (paymentResult.first['cnt'] as int?) ?? 0;

      if (linkedCount > 0 || paymentCount > 0) {
        throw RecordLinkedTakenException(
          linkedCount: linkedCount,
          paymentCount: paymentCount,
        );
      }
      await txn.delete('records', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Force deletes a record unconditionally skipping the COUNT check [FIX-FORCEDELETE-1].
  /// Additionally retires the deleted record's transactionId and each of its payments' paymentId
  /// so those numbers are never reissued (Addendum G, FIX-ID-REUSE-1).
  /// Uses PaymentDao.paymentIdsByRecordId and PaymentDao.deleteByRecordId as mandated by [FIX-PAYMENTDAO-1].
  Future<void> forceDeleteRecord(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      // 1. Fetch record for transactionId
      final recMaps = await txn.query('records', where: 'id = ?', whereArgs: [id]);
      if (recMaps.isNotEmpty) {
        final txnId = recMaps.first['transactionId'] as String?;
        if (txnId != null && txnId.isNotEmpty) {
          try {
            await txn.insert(
              'retired_ids',
              {
                'kind': 'transaction',
                'displayId': txnId,
                'retiredAt': DateTime.now().toIso8601String(),
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          } catch (_) {}
        }
      }

      // 2. Fetch payments for paymentId via PaymentDao [FIX-PAYMENTDAO-1]
      // v1.13: forceDeleteRecord reads these BEFORE deleteByRecordId so it can retire them.
      final paymentDao = PaymentDao(txn);
      final pIds = await paymentDao.paymentIdsByRecordId(id);
      for (final pId in pIds) {
        try {
          await txn.insert(
            'retired_ids',
            {
              'kind': 'payment',
              'displayId': pId,
              'retiredAt': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        } catch (_) {}
      }

      // 3. Delete dependent children then record (§4.4 WHERE-clause delete)
      await paymentDao.deleteByRecordId(id);
      await txn.delete('ledger_items', where: 'recordId = ?', whereArgs: [id]);
      await RecordDao(txn).deleteById(id);
    });
  }

  Future<List<Map<String, dynamic>>> getAllRetiredIds() async {
    final db = await database;
    return await db.query('retired_ids');
  }

  /// Clears all customers, records, items, payments, and empties retired_ids table.
  /// Mandated by Settings Screen spec (Tab 4):
  /// "Clear-all-data (with confirmation dialog) — also empties retired_ids;
  /// every ID sequence restarts at 01 because no data remains"
  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('payments');
      await txn.delete('ledger_items');
      await txn.delete('records');
      await txn.delete('customers');
      await txn.delete('retired_ids');
    });
  }

  /// Transactional all-or-nothing backup restore [FIX-ID-BACKUP-1] & [FIX-BACKUPCONFIG-1]:
  /// Restoring a JSON backup is a replace-all, not a merge. Inside a single db.transaction(),
  /// delete payments, ledger_items, records, customers and retired_ids explicitly
  /// (child tables first — do not lean on the FK cascade), then insert everything from the backup.
  /// settings and item_rates are part of the 1.4 backup ([FIX-BACKUPCONFIG-1]): when the file
  /// carries them they are replaced too (settings row overwritten, item_rates deleted and re-inserted);
  /// when it does not (1.1–1.3), they are left untouched.
  /// If anything fails, roll the whole transaction back so the device keeps its previous
  /// data, and surface a clear error.
  Future<void> restoreBackupTransactionally({
    required List<Map<String, dynamic>> customers,
    required List<Map<String, dynamic>> records,
    required List<Map<String, dynamic>> ledgerItems,
    required List<Map<String, dynamic>> payments,
    List<Map<String, dynamic>> retiredIds = const [],
    Map<String, dynamic>? settings,
    List<Map<String, dynamic>>? itemRates,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      // 1. Child tables first (do not lean on FK cascade)
      await txn.delete('payments');
      await txn.delete('ledger_items');
      await txn.delete('records');
      await txn.delete('customers');
      await txn.delete('retired_ids');

      // 2. Settings and item_rates replaced only when present in backup [FIX-BACKUPCONFIG-1]
      if (settings != null) {
        await txn.insert('settings', settings, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      if (itemRates != null) {
        await txn.delete('item_rates');
        for (final r in itemRates) {
          await txn.insert('item_rates', r, conflictAlgorithm: ConflictAlgorithm.abort);
        }
      }

      // 3. Insert everything from backup with abort conflict algorithm
      for (final c in customers) {
        await txn.insert('customers', c, conflictAlgorithm: ConflictAlgorithm.abort);
      }
      for (final r in records) {
        await txn.insert('records', r, conflictAlgorithm: ConflictAlgorithm.abort);
      }
      for (final i in ledgerItems) {
        await txn.insert('ledger_items', i, conflictAlgorithm: ConflictAlgorithm.abort);
      }
      for (final p in payments) {
        await txn.insert('payments', p, conflictAlgorithm: ConflictAlgorithm.abort);
      }
      for (final ret in retiredIds) {
        await txn.insert('retired_ids', ret, conflictAlgorithm: ConflictAlgorithm.abort);
      }
    });
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

  Future<PaymentEntity> insertPayment(PaymentEntity payment) async {
    return await _paymentInsertLock.synchronized(() async {
      final db = await database;
      return await db.transaction((txn) async {
        String effectivePaymentId = payment.paymentId;
        if (effectivePaymentId.isEmpty) {
          effectivePaymentId = await generateNextPaymentId(txn, payment.parsedDateTime);
        }

        final toInsert = payment.copyWith(paymentId: effectivePaymentId);
        try {
          await txn.insert('payments', toInsert.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);
        } catch (_) {
          final fallbackMap = toInsert.toMap()..remove('paymentId');
          await txn.insert('payments', fallbackMap, conflictAlgorithm: ConflictAlgorithm.abort);
        }
        return toInsert;
      });
    });
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

  /// Deletes a payment by ID (§4.4 [FIX-PAYMENT-DELETE-1]).
  Future<int> deletePayment(String id) async {
    final dao = await paymentDao;
    return await dao.deleteById(id);
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

  /// [FIX-RATE-ASOF-1] (v1.16) Latest USABLE rate (ratePerUnit > 0) for [category] whose
  /// effectiveDate is on or before [dateOnly]; null when there is none.
  Future<ItemRateEntity?> getRateAsOf(String category, String dateOnly) async {
    final dao = await itemRateDao;
    return await dao.getRateAsOf(category, dateOnly);
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
