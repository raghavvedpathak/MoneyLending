import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/record_entity.dart';
import '../../models/record_total_paid.dart';

/// DAO for RecordEntity.
///
/// Mandated by Data Spec §4.4:
/// - getByStatus(status): ORDER BY startDate DESC (lexicographical ISO datetime sort).
/// - getByCustomer(customerId): ORDER BY startDate DESC.
/// - getActiveGivenRecords(): Required by §5.3 Collection Alert Section.
/// - insert: ConflictAlgorithm.abort (NEVER ConflictAlgorithm.replace to avoid CASCADE DELETE footgun).
/// - update: Standard update by id.
/// - deleteById: Direct DELETE query without loading full entity.
class RecordDao {
  final DatabaseExecutor _db;

  const RecordDao(this._db);

  /// Queries records by status, sorted chronologically descending
  Future<List<RecordEntity>> getByStatus(String status) async {
    final maps = await _db.query(
      'records',
      where: 'status = ?',
      whereArgs: [status],
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
  Future<List<RecordEntity>> getActiveGivenRecords() async {
    final maps = await _db.rawQuery('''
      SELECT * FROM records
      WHERE status = 'ACTIVE' AND type = 'GIVEN'
      ORDER BY startDate DESC
    ''');
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

  /// Inserts a new record. Strictly ABORTS on conflict to prevent deleting child rows.
  Future<void> insert(RecordEntity record) async {
    await _db.insert(
      'records',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Updates an existing record.
  Future<void> update(RecordEntity record) async {
    await _db.update(
      'records',
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  /// Safe upsert pattern mandated by §4.4:
  /// Check existence first; then branch — update if exists, insert(ABORT) if not.
  Future<void> upsert(RecordEntity record) async {
    final existing = await getById(record.id);
    if (existing != null) {
      await update(record);
    } else {
      await insert(record);
    }
  }

  /// Deletes a record by ID directly via SQL query (§4.4: Prefer query deletes over loading full entity)
  Future<void> deleteById(String id) async {
    await _db.delete('records', where: 'id = ?', whereArgs: [id]);
  }

  /// Multi-table write inside a single atomic SQLite transaction (§4.4):
  /// "Always use @Transaction for multi-table writes: When inserting a new record with its
  /// LedgerItems and Payments atomically, annotate the DAO method with @Transaction.
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
  }

  /// Transactional all-or-nothing import (§4.4):
  /// "When importing a JSON backup of N records, wrap the entire import in a single
  /// @Transaction. If any record conflicts, roll back the entire import and surface a clear error."
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
}
