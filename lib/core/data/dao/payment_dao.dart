import 'dart:async';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../../../data/models/payment_entity.dart';

/// DAO for PaymentEntity.
///
/// Mandated by Data Spec §4.4 & [FIX-PAYMENTDAO-1]:
/// - Defined in :core:data alongside RecordDao.
/// - watchByRecordId(recordId): ORDER BY date ASC (ISO datetime strings sort lexicographically).
/// - insertPayment: ConflictAlgorithm.abort.
/// - paymentIdsByRecordId: Reads payment IDs before deleteByRecordId so forceDeleteRecord can retire them (v1.13 / Addendum G).
/// - deleteByRecordId: WHERE-clause delete used by forceDeleteRecord cleanup.
/// - Consumed internally by RecordRepositoryImpl, never injected into Notifiers or feature widgets directly.
class PaymentDao {
  final DatabaseExecutor _db;
  static final StreamController<void> _paymentChanges = StreamController<void>.broadcast();

  const PaymentDao(this._db);

  /// ISO datetime strings sort correctly lexicographically — ORDER BY date ASC is
  /// safe with the datetime storage convention from §4.2.
  Stream<List<PaymentEntityData>> watchByRecordId(String recordId) async* {
    yield await getByRecordId(recordId);
    await for (final _ in _paymentChanges.stream) {
      yield await getByRecordId(recordId);
    }
  }

  /// Inserts a payment companion/entity. Strictly ABORT on conflict.
  Future<int> insertPayment(PaymentEntity entry) async {
    final res = await _db.insert(
      'payments',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    _paymentChanges.add(null);
    return res;
  }

  /// Inserts a new payment row.
  Future<void> insert(PaymentEntity payment) async {
    await insertPayment(payment);
  }

  /// v1.13: forceDeleteRecord reads these BEFORE deleteByRecordId
  /// so it can retire them.
  Future<List<String>> paymentIdsByRecordId(String recordId) async =>
      (await _db.query(
        'payments',
        columns: ['paymentId'],
        where: 'recordId = ?',
        whereArgs: [recordId],
      ))
          .map((p) => p['paymentId'] as String?)
          .where((pid) => pid != null && pid.isNotEmpty)
          .cast<String>()
          .toList();

  /// Used by forceDeleteRecord cleanup (§4.4: WHERE-clause delete)
  Future<int> deleteByRecordId(String recordId) async {
    final count = await _db.delete(
      'payments',
      where: 'recordId = ?',
      whereArgs: [recordId],
    );
    _paymentChanges.add(null);
    return count;
  }

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
}
