import '../../../domain/models/customer.dart';

/// Domain Contract for Customer Repository.
///
/// Mandated by Architecture Spec §2.1 & §4.3 [FIX-ARCH-DB-1]:
/// Pure Dart interface defined in :core:domain (zero Flutter/Drift imports).
abstract class CustomerRepository {
  Stream<List<Customer>> getAllCustomers();
  Stream<Customer?> getCustomerById(String id);
  Future<List<Customer>> getAllCustomersOnce();
  Future<Customer> insertCustomer(Customer customer);
  Future<void> updateCustomer(Customer customer);
  Future<void> deleteCustomer(String id);
  Future<void> refresh();
}
