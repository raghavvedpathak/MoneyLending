// DOMAIN TYPE — defined in :core:domain. Used by RecordRepository interface and DashboardViewModel.
// Mapped from: RecordTotalPaid (DAO projection in :core:data).
/// Domain representation of total payments aggregated per record.
///
/// Mandated by Data Spec §4.3 & §5.3 [FIX-DEV-COMBINESUSPEND-1]:
/// Required by combine() in DashboardViewModel §5.3 and Worker §11.
class RecordPaymentTotal {
  final String recordId;
  final double totalPaid;

  const RecordPaymentTotal({
    required this.recordId,
    required this.totalPaid,
  });

  @override
  String toString() => 'RecordPaymentTotal(recordId: $recordId, totalPaid: $totalPaid)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecordPaymentTotal &&
          runtimeType == other.runtimeType &&
          recordId == other.recordId &&
          totalPaid == other.totalPaid;

  @override
  int get hashCode => Object.hash(recordId, totalPaid);
}
