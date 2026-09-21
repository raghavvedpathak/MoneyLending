/// Thrown when an operation is attempted on a record that was deleted
/// or is no longer ACTIVE [FIX-STALE-RECORD-1].
class StaleRecordException implements Exception {
  final String recordId;

  const StaleRecordException(this.recordId);

  @override
  String toString() =>
      'StaleRecordException: Record $recordId was deleted or is no longer ACTIVE.';
}
