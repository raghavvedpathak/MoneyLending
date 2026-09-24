import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../../core/calculations/util/date_extensions.dart';
import '../../core/utils/app_date_formatter.dart';
import '../../domain/errors/customer_has_records_exception.dart';
import '../../domain/models/customer.dart';
import '../../domain/repositories/customer_repository.dart';
import '../datasources/database_helper.dart';
import '../models/customer_entity.dart';

/// Concrete Data Layer implementation of CustomerRepository.
///
/// Mandated by Data Spec §4.3:
/// Implements domain interface, acts as single source of truth for customers.
class CustomerRepositoryImpl implements CustomerRepository {
  final DatabaseHelper _dbHelper;
  late final StreamController<List<Customer>> _customerStreamController =
      StreamController<List<Customer>>.broadcast(onListen: _refreshStream);

  CustomerRepositoryImpl([DatabaseHelper? dbHelper])
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  Future<void> _refreshStream() async {
    final entities = await _dbHelper.getAllCustomers();
    _customerStreamController.add(entities.map(_toDomain).toList());
  }

  Customer _toDomain(CustomerEntity entity) {
    final parsed = AppDateFormatter.parseIso(entity.createdAt) ?? DateTime.now();
    return Customer(
      id: entity.id,
      displayId: entity.displayId,
      name: entity.name,
      phone: entity.phone,
      address: entity.address,
      createdAt: parsed.dateOnly,
    );
  }

  CustomerEntity _toEntity(Customer domain) {
    return CustomerEntity(
      id: domain.id,
      displayId: domain.displayId,
      name: domain.name,
      phone: domain.phone,
      address: domain.address,
      createdAt: AppDateFormatter.toIsoDate(domain.createdAt),
    );
  }

  @override
  Stream<List<Customer>> getAllCustomers() {
    _refreshStream();
    return _customerStreamController.stream;
  }

  @override
  Future<List<Customer>> getAllCustomersOnce() async {
    final entities = await _dbHelper.getAllCustomers();
    return entities.map(_toDomain).toList();
  }

  @override
  Future<void> refresh() => _refreshStream();

  @override
  Stream<Customer?> getCustomerById(String id) async* {
    final entity = await _dbHelper.getCustomerById(id);
    yield entity != null ? _toDomain(entity) : null;
  }

  @override
  Future<Customer> insertCustomer(Customer customer) async {
    final entity = _toEntity(customer);
    final inserted = await _dbHelper.insertCustomer(entity);
    await _refreshStream();
    return _toDomain(inserted);
  }

  @override
  Future<void> updateCustomer(Customer customer) async {
    final db = await _dbHelper.database;
    final entity = _toEntity(customer);
    await db.update(
      'customers',
      entity.toMap(),
      where: 'id = ?',
      whereArgs: [entity.id],
    );
    await _refreshStream();
  }

  @override
  Future<void> deleteCustomer(String id) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      final res = await txn.rawQuery(
        'SELECT COUNT(*) as cnt FROM records WHERE customerId = ?',
        [id],
      );
      final count = (res.first['cnt'] as int?) ?? 0;
      if (count > 0) {
        throw CustomerHasRecordsException(customerId: id, recordCount: count);
      }

      // Retire customer displayId so it is never reissued (Addendum G, FIX-ID-REUSE-1)
      final custMaps = await txn.query('customers', where: 'id = ?', whereArgs: [id]);
      if (custMaps.isNotEmpty) {
        final displayId = custMaps.first['displayId'] as String?;
        if (displayId != null && displayId.isNotEmpty) {
          try {
            await txn.insert(
              'retired_ids',
              {
                'kind': 'customer',
                'displayId': displayId,
                'retiredAt': DateTime.now().toIso8601String(),
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          } catch (_) {}
        }
      }

      await txn.delete('customers', where: 'id = ?', whereArgs: [id]);
    });
    await _refreshStream();
  }
}

