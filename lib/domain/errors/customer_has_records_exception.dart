/// Thrown when attempting to delete a customer that still has records (Addendum G, FIX-ID-REUSE-1).
class CustomerHasRecordsException implements Exception {
  final String customerId;
  final int recordCount;

  const CustomerHasRecordsException({
    required this.customerId,
    required this.recordCount,
  });

  @override
  String toString() =>
      'CustomerHasRecordsException: Cannot delete customer $customerId because $recordCount record(s) are associated with this customer.';
}
