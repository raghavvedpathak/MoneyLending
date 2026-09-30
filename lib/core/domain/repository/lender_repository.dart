import '../../../domain/models/lender.dart';

export '../../../domain/errors/lender_has_records_exception.dart';
export '../../../domain/models/lender.dart';

/// LenderRepository interface [FIX-LENDER-CODEPATH-1] (v1.27)
///
/// The Lender path had a table and a delete guard but no repository contract.
/// Minimum interface (CustomerRepository mirrors it: watchAllCustomers(), getCustomerById(),
/// addCustomer(), updateCustomer(), deleteCustomer()):
abstract class LenderRepository {
  /// Stream of all lenders ordered by name.
  Stream<List<Lender>> watchAllLenders();

  /// Retrieve a lender by unique UUID.
  Future<Lender?> getLenderById(String id);

  /// createdAt = the single clock read the Notifier captured. displayId (LEND26-27-01) is generated
  /// inside insertLenderWithSequence() under the repository's _insertLock (Addendum G.2).
  Future<Lender> addLender({
    required LenderType lenderType,
    required String name,
    String? phone, // required by the form for individual
    String? institutionDetails, // shown / required only for institution
    String? notes,
    required DateTime createdAt,
  });

  /// displayId and createdAt never change.
  Future<void> updateLender(Lender lender);

  /// Throws [LenderHasRecordsException](recordCount) while the lender still has records.
  Future<void> deleteLender(String id);
}
