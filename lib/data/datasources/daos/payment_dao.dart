import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/payment_entity.dart';

/// DAO for PaymentEntity.
///
/// Mandated by Data Spec §4.4 & [FIX-PAYMENTDAO-1]:
/// - Defined in :core:data alongside RecordDao.
/// - getByRecordId(recordId): ORDER BY date ASC (ISO datetime strings sort lexicographically).
/// - insert: ConflictAlgorithm.abort.
/// - deleteByRecordId: Used by forceDeleteRecord cleanup.
/// - Consumed internally by RecordRepositoryImpl, never injected into ViewModels directly.
class PaymentDao {
  final DatabaseExecutor _db;

  const PaymentDao(this._db);

  /// Queries payments for a record, sorted chronologically ascending
  Future<List<PaymentEntity>> getByRecordId(String recordId) async {
    final maps = await _db.query(
      'payments',
      where: 'recordId = ?',
      whereArgs: [recordId],
      orderBy: 'date ASC',
    );
    return maps.map((m) => PaymentEntity.fromMap(m)).toList();
  }

  /// Inserts a new payment row. Strictly ABORT on conflict.
  Future<void> insert(PaymentEntity payment) async {
    await _db.insert(
      'payments',
      payment.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Deletes all payments associated with a record ID (cleanup hook)
  Future<void> deleteByRecordId(String recordId) async {
    await _db.delete(
      'payments',
      where: 'recordId = ?',
      whereArgs: [recordId],
    );
  }
}
