/// Typed exception thrown when attempting to delete a GIVEN record
/// that still has dependent TAKEN records linked to it.
///
/// Mandated by Data Spec §4.2 and [FIX-DEV-TOCTOU-1]:
/// Repositories wrap the COUNT check + conditional delete in a single transaction.
/// If linkedCount > 0, throw RecordLinkedTakenException rather than deleting.
class RecordLinkedTakenException implements Exception {
  final int linkedCount;
  final int paymentCount;

  const RecordLinkedTakenException({
    required this.linkedCount,
    this.paymentCount = 0,
  });

  @override
  String toString() =>
      'RecordLinkedTakenException: Cannot delete record because $linkedCount TAKEN record(s) and $paymentCount payment(s) are linked to it.';
}
