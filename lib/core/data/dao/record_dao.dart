import 'dart:async';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../../../data/models/record_entity.dart';
import '../../../../data/models/record_total_paid.dart';
import 'record_activity_row.dart';
import '../../../domain/models/record_status.dart';
import '../../../domain/models/record_type.dart';

/// DAO for RecordEntity.
///
/// Mandated by Data Spec §4.4:
/// - watchByStatus(status): ORDER BY startDate DESC (lexicographical ISO datetime sort).
/// - watchByCustomer(customerId): Filter by customerId.
/// - watchActiveGivenRecords(): Required by §5.3 Collection Alert Section [FIX-ENUM-CASE-1] & [FIX-PERF-EAGERLOAD-2].
/// - insertRecord / insert: ConflictAlgorithm.abort (NEVER ConflictAlgorithm.replace to avoid CASCADE DELETE footgun).
/// - updateRecord / update: Standard update by id.
/// - deleteById: WHERE-clause delete directly via SQL query without loading full entity.
/// - Safe upsert: Check existence first; branch update if exists, insert(abort) if not.
/// - insertWithDetails: Multi-table write inside a single atomic SQLite transaction.
/// - restoreBackupTransactionally: Transactional replace-all import [FIX-ID-BACKUP-1].
class RecordDao {
  final DatabaseExecutor _db;
  static final StreamController<void> _recordChanges = StreamController<void>.broadcast();

  const RecordDao(this._db);

  /// ISO datetime strings sort correctly lexicographically — ORDER BY start_date DESC
  /// is safe with the datetime storage convention from §4.2.
  Stream<List<RecordEntityData>> watchByStatus(RecordStatus status) async* {
    yield await getByStatus(status.name);
    await for (final _ in _recordChanges.stream) {
      yield await getByStatus(status.name);
    }
  }

  /// Watch records by customer ID
  Stream<List<RecordEntityData>> watchByCustomer(String customerId) async* {
    yield await getByCustomer(customerId);
    await for (final _ in _recordChanges.stream) {
      yield await getByCustomer(customerId);
    }
  }

  /// Required by §5.3 Collection Alert Section — do NOT inline this query in
  /// DashboardNotifier. [FIX-ENUM-CASE-1] typed equalsValue(), never string literals.
  /// [FIX-PERF-EAGERLOAD-2] this raw records-only stream is an INPUT to the
  /// repository’s combined watch; it must not be exposed to Notifiers on its own.
  Stream<List<RecordEntityData>> watchActiveGivenRecords() async* {
    yield await getActiveGivenRecords();
    await for (final _ in _recordChanges.stream) {
      yield await getActiveGivenRecords();
    }
  }

  /// Queries records by status, sorted chronologically descending
  Future<List<RecordEntity>> getByStatus(dynamic status) async {
    final statusStr = status is RecordStatus ? status.name : status.toString();
    final maps = await _db.query(
      'records',
      where: 'UPPER(status) = UPPER(?)',
      whereArgs: [statusStr],
      orderBy: 'startDate DESC',
    );
    return maps.map((m) => RecordEntity.fromMap(m)).toList();
  }

  /// Queries records for a given customer, sorted chronologically descending
  Future<List<RecordEntity>> getByCustomer(String customerId) async {
    final maps = await _db.query(
      'records',
      where: 'customerId = ?',
      whereArgs: [customerId],
      orderBy: 'startDate DESC',
    );
    return maps.map((m) => RecordEntity.fromMap(m)).toList();
  }

  /// Required by §5.3 Collection Alert Section — do NOT inline this query in ViewModel
  /// Uses typed case-insensitive checks to prevent enum case mismatches [FIX-ENUM-CASE-1].
  Future<List<RecordEntity>> getActiveGivenRecords() async {
    final activeStatus = RecordStatus.active.name;
    final givenType = RecordType.given.name;
    final maps = await _db.rawQuery('''
      SELECT * FROM records
      WHERE UPPER(status) = UPPER(?) AND UPPER(type) = UPPER(?)
      ORDER BY startDate DESC
    ''', [activeStatus, givenType]);
    return maps.map((m) => RecordEntity.fromMap(m)).toList();
  }

  /// Gets a record by ID
  Future<RecordEntity?> getById(String id) async {
    final maps = await _db.query(
      'records',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return RecordEntity.fromMap(maps.first);
  }

  /// Inserts a new record companion/entity. Strictly ABORTS on conflict to prevent deleting child rows.
  Future<int> insertRecord(RecordEntity entry) async {
    final res = await _db.insert(
      'records',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    _recordChanges.add(null);
    return res;
  }

  /// Inserts a new record. Strictly ABORTS on conflict to prevent deleting child rows.
  Future<void> insert(RecordEntity record) async {
    await insertRecord(record);
  }

  /// Updates an existing record.
  Future<bool> updateRecord(RecordEntity entry) async {
    final count = await _db.update(
      'records',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
    _recordChanges.add(null);
    return count > 0;
  }

  /// Updates an existing record.
  Future<void> update(RecordEntity record) async {
    await updateRecord(record);
  }

  /// Safe upsert pattern mandated by §4.4:
  /// Check existence first; then branch — update if exists, insert(ABORT) if not.
  /// Never use replace-mode when child rows must survive (CASCADE DELETE footgun).
  Future<void> upsert(RecordEntity record) async {
    final existing = await getById(record.id);
    if (existing != null) {
      await update(record);
    } else {
      await insert(record);
    }
  }

  /// Deletes a record by ID directly via SQL query (§4.4: Prefer WHERE-clause delete over loading full entity)
  Future<int> deleteById(String id) async {
    final count = await _db.delete('records', where: 'id = ?', whereArgs: [id]);
    _recordChanges.add(null);
    return count;
  }

  /// Multi-table write inside a single atomic SQLite transaction (§4.4):
  /// "Always wrap multi-table writes in db.transaction(): when inserting a new
  /// record with its LedgerItems and Payments atomically, wrap the whole sequence.
  /// Without it, a crash midway leaves the DB in a partially-written state."
  Future<void> insertWithDetails({
    required RecordEntity record,
    List<Map<String, dynamic>> items = const [],
    List<Map<String, dynamic>> payments = const [],
  }) async {
    final executor = _db;
    if (executor is Database) {
      await executor.transaction((txn) async {
        await txn.insert('records', record.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);
        for (final item in items) {
          await txn.insert('ledger_items', item, conflictAlgorithm: ConflictAlgorithm.abort);
        }
        for (final payment in payments) {
          await txn.insert('payments', payment, conflictAlgorithm: ConflictAlgorithm.abort);
        }
      });
    } else {
      await executor.insert('records', record.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);
      for (final item in items) {
        await executor.insert('ledger_items', item, conflictAlgorithm: ConflictAlgorithm.abort);
      }
      for (final payment in payments) {
        await executor.insert('payments', payment, conflictAlgorithm: ConflictAlgorithm.abort);
      }
    }
    _recordChanges.add(null);
  }

  /// Transactional all-or-nothing import (§4.4):
  /// When importing a batch of records, wrap the entire import in a single transaction.
  Future<void> importRecordsTransactionally({
    required List<RecordEntity> records,
    List<Map<String, dynamic>> items = const [],
    List<Map<String, dynamic>> payments = const [],
  }) async {
    final executor = _db;
    if (executor is Database) {
      await executor.transaction((txn) async {
        for (final r in records) {
          await txn.insert('records', r.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);
        }
        for (final i in items) {
          await txn.insert('ledger_items', i, conflictAlgorithm: ConflictAlgorithm.abort);
        }
        for (final p in payments) {
          await txn.insert('payments', p, conflictAlgorithm: ConflictAlgorithm.abort);
        }
      });
    } else {
      for (final r in records) {
        await executor.insert('records', r.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);
      }
      for (final i in items) {
        await executor.insert('ledger_items', i, conflictAlgorithm: ConflictAlgorithm.abort);
      }
      for (final p in payments) {
        await executor.insert('payments', p, conflictAlgorithm: ConflictAlgorithm.abort);
      }
    }
    _recordChanges.add(null);
  }

  /// Transactional all-or-nothing backup restore [FIX-ID-BACKUP-1] & [FIX-BACKUPCONFIG-1]:
  /// Restoring a JSON backup is a replace-all, not a merge. Inside a single db.transaction(),
  /// delete payments, ledger_items, records, customers, and retired_ids explicitly
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
    final executor = _db;
    if (executor is Database) {
      await executor.transaction((txn) async {
        // Child tables first:
        await txn.delete('payments');
        await txn.delete('ledger_items');
        await txn.delete('records');
        await txn.delete('customers');
        await txn.delete('retired_ids');

        if (settings != null) {
          await txn.insert('settings', settings, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        if (itemRates != null) {
          await txn.delete('item_rates');
          for (final r in itemRates) {
            await txn.insert('item_rates', r, conflictAlgorithm: ConflictAlgorithm.abort);
          }
        }

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
    } else {
      await executor.delete('payments');
      await executor.delete('ledger_items');
      await executor.delete('records');
      await executor.delete('customers');
      await executor.delete('retired_ids');

      if (settings != null) {
        await executor.insert('settings', settings, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      if (itemRates != null) {
        await executor.delete('item_rates');
        for (final r in itemRates) {
          await executor.insert('item_rates', r, conflictAlgorithm: ConflictAlgorithm.abort);
        }
      }

      for (final c in customers) {
        await executor.insert('customers', c, conflictAlgorithm: ConflictAlgorithm.abort);
      }
      for (final r in records) {
        await executor.insert('records', r, conflictAlgorithm: ConflictAlgorithm.abort);
      }
      for (final i in ledgerItems) {
        await executor.insert('ledger_items', i, conflictAlgorithm: ConflictAlgorithm.abort);
      }
      for (final p in payments) {
        await executor.insert('payments', p, conflictAlgorithm: ConflictAlgorithm.abort);
      }
      for (final ret in retiredIds) {
        await executor.insert('retired_ids', ret, conflictAlgorithm: ConflictAlgorithm.abort);
      }
    }
    _recordChanges.add(null);
  }

  /// Backing query for getTotalPaidFlow() (§5.3 / [FIX-DEV-COMBINESUSPEND-1]).
  /// Query: SELECT recordId, SUM(principalPaid + interestPaid) AS totalPaid FROM payments GROUP BY recordId
  Future<List<RecordTotalPaid>> getTotalPaid() async {
    final maps = await _db.rawQuery('''
      SELECT recordId, SUM(principalPaid + interestPaid) AS totalPaid
      FROM payments
      GROUP BY recordId
    ''');
    return maps.map((m) => RecordTotalPaid.fromMap(m)).toList();
  }

  /// Batch query for total payments by record IDs (§5.4).
  /// Query: SELECT recordId, SUM(principalPaid + interestPaid) AS totalPaid FROM payments WHERE recordId IN (:recordIds) GROUP BY recordId
  Future<List<RecordTotalPaid>> getTotalPaidByRecordIds(List<String> recordIds) async {
    if (recordIds.isEmpty) return [];
    final placeholders = List.filled(recordIds.length, '?').join(',');
    final maps = await _db.rawQuery('''
      SELECT recordId, SUM(principalPaid + interestPaid) AS totalPaid
      FROM payments
      WHERE recordId IN ($placeholders)
      GROUP BY recordId
    ''', recordIds);
    return maps.map((m) => RecordTotalPaid.fromMap(m)).toList();
  }

  /// Single JOIN query for latest payment date per active record (§8).
  ///
  /// ⚠️ This DAO method must be a one-shot Future (not a Stream) because the background
  /// task fetches the data once per run and does not need to observe changes. Using a
  /// Stream here would require subscribing and cancelling inside the background isolate,
  /// which adds unnecessary complexity and risk of leaking the subscription.
  ///
  /// Avoids N+1 queries by aggregating MAX(p.date) in a single SQLite query.
  Future<List<RecordActivityRow>> getActiveRecordLastActivityDates() async {
    final maps = await _db.rawQuery('''
      SELECT r.id AS record_id, MAX(p.date) AS last_payment_date
      FROM records r
      LEFT JOIN payments p ON p.recordId = r.id
      WHERE LOWER(r.status) = 'active'
      GROUP BY r.id
    ''');
    return maps.map((m) => RecordActivityRow.fromMap(m)).toList();
  }
}
