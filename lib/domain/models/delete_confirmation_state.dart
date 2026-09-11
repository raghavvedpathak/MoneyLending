/// Business-layer signal for records deletion confirmation.
///
/// Mandated by Data Spec §4.2 and [FIX-DELETESTATE-1]:
/// Defined in :core:domain (it is a business-layer signal, not a UI detail).
/// Minimum definition: val recordId: String, val linkedCount: Int.
/// The ViewModel sets `ValueNotifier<DeleteConfirmationState?>`.
/// Null means no pending confirmation; non-null triggers confirmation dialog.
class DeleteConfirmationState {
  final String recordId;
  final int linkedCount;

  const DeleteConfirmationState({
    required this.recordId,
    required this.linkedCount,
  });

  @override
  String toString() =>
      'DeleteConfirmationState(recordId: $recordId, linkedCount: $linkedCount)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeleteConfirmationState &&
          runtimeType == other.runtimeType &&
          recordId == other.recordId &&
          linkedCount == other.linkedCount;

  @override
  int get hashCode => Object.hash(recordId, linkedCount);
}
