import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../../core/domain/repository/lender_repository.dart';
import '../../core/utils/app_date_formatter.dart';
import '../../core/utils/uuid_generator.dart';
import '../datasources/database_helper.dart';
import '../models/lender_entity.dart';

/// Concrete Data Layer implementation of [LenderRepository] (§4.3, [FIX-LENDER-CODEPATH-1]).
class LenderRepositoryImpl implements LenderRepository {
  final DatabaseHelper _dbHelper;
  late final StreamController<List<Lender>> _streamController =
      StreamController<List<Lender>>.broadcast(onListen: _refreshStream);

  LenderRepositoryImpl([DatabaseHelper? dbHelper])
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  Future<void> _refreshStream() async {
    final entities = await _dbHelper.getAllLenders();
    _streamController.add(entities.map((e) => e.toDomain()).toList());
  }

  @override
  Stream<List<Lender>> watchAllLenders() {
    _refreshStream();
    return _streamController.stream;
  }

  @override
  Future<Lender?> getLenderById(String id) async {
    final entity = await _dbHelper.getLenderById(id);
    return entity?.toDomain();
  }

  @override
  Future<Lender> addLender({
    required LenderType lenderType,
    required String name,
    String? phone,
    String? institutionDetails,
    String? notes,
    required DateTime createdAt,
  }) async {
    final now = DateTime.now();
    final entity = LenderEntity(
      id: AppUuid.generate(),
      displayId: '', // Generated in DB under _lenderInsertLock
      lenderType: lenderType.name,
      name: name,
      phone: phone,
      institutionDetails: institutionDetails,
      notes: notes,
      createdAt: AppDateFormatter.toIsoDate(createdAt),
      updatedAt: now.toIso8601String(),
    );

    final inserted = await _dbHelper.insertLenderWithSequence(entity);
    await _refreshStream();
    return inserted.toDomain();
  }

  @override
  Future<void> updateLender(Lender lender) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();

    // displayId and createdAt never change per spec §4.3
    await db.update(
      'lenders',
      {
        'lenderType': lender.lenderType.name,
        'name': lender.name,
        'phone': lender.phone,
        'institutionDetails': lender.institutionDetails,
        'notes': lender.notes,
        'updatedAt': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [lender.id],
    );
    await _refreshStream();
  }

  @override
  Future<void> deleteLender(String id) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      // 1. Check if lender has records [FIX-LENDER-CODEPATH-1]
      final res = await txn.rawQuery(
        'SELECT COUNT(*) as cnt FROM records WHERE lenderId = ?',
        [id],
      );
      final count = (res.first['cnt'] as int?) ?? 0;
      if (count > 0) {
        throw LenderHasRecordsException(count, lenderId: id);
      }

      // 2. Retire lender displayId so it is never reissued (Addendum G, FIX-ID-REUSE-1)
      final lenderMaps =
          await txn.query('lenders', where: 'id = ?', whereArgs: [id]);
      if (lenderMaps.isNotEmpty) {
        final displayId = lenderMaps.first['displayId'] as String?;
        if (displayId != null && displayId.isNotEmpty) {
          try {
            await txn.insert(
              'retired_ids',
              {
                'kind': 'lender',
                'displayId': displayId,
                'retiredAt': DateTime.now().toIso8601String(),
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          } catch (_) {}
        }
      }

      // 3. Delete lender
      await txn.delete('lenders', where: 'id = ?', whereArgs: [id]);
    });
    await _refreshStream();
  }
}
