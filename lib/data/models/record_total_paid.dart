// DAO PROJECTION — internal to :core:data. Never expose outside this module.
// Maps to: RecordPaymentTotal (domain type in :core:domain).

/// DAO projection for SQLite aggregate query:
/// SELECT recordId, SUM(principalPaid + interestPaid) AS totalPaid FROM payments GROUP BY recordId
///
/// Mandated by Data Spec §5.3 & §5.4 [FIX-DEV-COMBINESUSPEND-1] [FIX-NAMING-CONVENTION].
class RecordTotalPaid {
  final String recordId;
  final double totalPaid;

  const RecordTotalPaid({
    required this.recordId,
    required this.totalPaid,
  });

  factory RecordTotalPaid.fromMap(Map<String, dynamic> map) {
    return RecordTotalPaid(
      recordId: map['recordId'] as String,
      totalPaid: (map['totalPaid'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() => {
    'recordId': recordId,
    'totalPaid': totalPaid,
  };
}
