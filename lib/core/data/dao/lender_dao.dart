import 'dart:async';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../../../data/models/lender_entity.dart';

/// DAO for LenderEntity (§4.4).
class LenderDao {
  final DatabaseExecutor _db;
  static final StreamController<void> _lenderChanges = StreamController<void>.broadcast();

  const LenderDao(this._db);

  /// Streams all lenders ordered by name ASC
  Stream<List<LenderEntityData>> watchAllLenders() async* {
    yield await getAll();
    await for (final _ in _lenderChanges.stream) {
      yield await getAll();
    }
  }

  /// Streams a single lender by ID
  Stream<LenderEntityData?> watchLenderById(String id) async* {
    yield await getById(id);
    await for (final _ in _lenderChanges.stream) {
      yield await getById(id);
    }
  }

  Future<List<LenderEntity>> getAll() async {
    final maps = await _db.query('lenders', orderBy: 'name ASC');
    return maps.map((m) => LenderEntity.fromMap(m)).toList();
  }

  Future<LenderEntity?> getById(String id) async {
    final maps = await _db.query(
      'lenders',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return LenderEntity.fromMap(maps.first);
  }

  Future<LenderEntity?> getByDisplayId(String displayId) async {
    final maps = await _db.query(
      'lenders',
      where: 'displayId = ?',
      whereArgs: [displayId],
    );
    if (maps.isEmpty) return null;
    return LenderEntity.fromMap(maps.first);
  }

  Future<int> insert(LenderEntity lender) async {
    final res = await _db.insert(
      'lenders',
      lender.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    _lenderChanges.add(null);
    return res;
  }

  Future<int> insertLender(LenderEntity lender) => insert(lender);

  Future<bool> update(LenderEntity lender) async {
    final count = await _db.update(
      'lenders',
      lender.toMap(),
      where: 'id = ?',
      whereArgs: [lender.id],
    );
    _lenderChanges.add(null);
    return count > 0;
  }

  Future<bool> updateLender(LenderEntity lender) => update(lender);

  Future<int> deleteById(String id) async {
    final count = await _db.delete('lenders', where: 'id = ?', whereArgs: [id]);
    _lenderChanges.add(null);
    return count;
  }
}
