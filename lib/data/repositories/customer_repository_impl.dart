import 'dart:async';
import '../../core/utils/app_date_formatter.dart';
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
    return Customer(
      id: entity.id,
      displayId: entity.displayId,
      name: entity.name,
      phone: entity.phone,
      address: entity.address,
      createdAt: AppDateFormatter.parseIso(entity.createdAt) ?? DateTime.now(),
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
    await db.delete('customers', where: 'id = ?', whereArgs: [id]);
    await _refreshStream();
  }
}
