import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/customer_entity.dart';

/// DAO for CustomerEntity.
///
/// Mandated by Data Spec §4.4:
/// - insert: ConflictAlgorithm.abort.
/// - update: Standard update.
/// - deleteById: Standard delete with cascading deletes on records.
class CustomerDao {
  final DatabaseExecutor _db;

  const CustomerDao(this._db);

  Future<List<CustomerEntity>> getAll() async {
    final maps = await _db.query('customers', orderBy: 'name ASC');
    return maps.map((m) => CustomerEntity.fromMap(m)).toList();
  }

  Future<CustomerEntity?> getById(String id) async {
    final maps = await _db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return CustomerEntity.fromMap(maps.first);
  }

  Future<CustomerEntity?> getByDisplayId(String displayId) async {
    final maps = await _db.query(
      'customers',
      where: 'displayId = ?',
      whereArgs: [displayId],
    );
    if (maps.isEmpty) return null;
    return CustomerEntity.fromMap(maps.first);
  }

  Future<void> insert(CustomerEntity customer) async {
    await _db.insert(
      'customers',
      customer.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(CustomerEntity customer) async {
    await _db.update(
      'customers',
      customer.toMap(),
      where: 'id = ?',
      whereArgs: [customer.id],
    );
  }

  Future<void> deleteById(String id) async {
    await _db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }
}
