/// Typed exception thrown when attempting to delete a GIVEN record
/// that still has dependent TAKEN records linked to it.
///
/// Mandated by Data Spec §4.2 and [FIX-DEV-TOCTOU-1]:
/// Repositories wrap the COUNT check + conditional delete in a single transaction.
/// If linkedCount > 0, throw RecordLinkedTakenException rather than deleting.
class RecordLinkedTakenException implements Exception {
  final int linkedCount;

  const RecordLinkedTakenException({required this.linkedCount});

  @override
  String toString() =>
      'RecordLinkedTakenException: Cannot delete GIVEN record because $linkedCount TAKEN record(s) are linked to it.';
}
