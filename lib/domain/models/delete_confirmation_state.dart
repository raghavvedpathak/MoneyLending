/// Business-layer signal for records deletion confirmation.
///
/// Mandated by Data Spec §4.2 and [FIX-DELETESTATE-1]:
/// Defined in :core:domain (it is a business-layer signal, not a UI detail).
/// Minimum definition: val recordId: String, val linkedCount: Int.
/// The ViewModel sets `ValueNotifier<DeleteConfirmationState?>`.
/// Null means no pending confirmation; non-null triggers confirmation dialog.
class DeleteConfirmationState {
  final String recordId;
  // TAKEN records whose linkedRecordId points at this record.
  final int linkedCount;
  // v1.13: payments that will be deleted together with the record.
  final int paymentCount;

  const DeleteConfirmationState({
    required this.recordId,
    required this.linkedCount,
    this.paymentCount = 0,
  });

  @override
  String toString() =>
      'DeleteConfirmationState(recordId: $recordId, linkedCount: $linkedCount, paymentCount: $paymentCount)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeleteConfirmationState &&
          runtimeType == other.runtimeType &&
          recordId == other.recordId &&
          linkedCount == other.linkedCount &&
          paymentCount == other.paymentCount;

  @override
  int get hashCode => Object.hash(recordId, linkedCount, paymentCount);
}
