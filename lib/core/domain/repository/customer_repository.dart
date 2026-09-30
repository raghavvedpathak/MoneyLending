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

  /// Alias mirroring [LenderRepository.watchAllLenders] (§4.3 [FIX-LENDER-CODEPATH-1]).
  Stream<List<Customer>> watchAllCustomers() => getAllCustomers();

  /// Convenience mirroring [LenderRepository.addLender] (§4.3 [FIX-LENDER-CODEPATH-1]).
  Future<Customer> addCustomer({
    required String name,
    String? phone,
    String? address,
    required DateTime createdAt,
  }) =>
      insertCustomer(Customer(
        id: '',
        displayId: '',
        name: name,
        phone: phone,
        address: address,
        createdAt: createdAt,
      ));
}
