/// DAO query projection for getActiveRecordLastActivityDates (§8).
///
/// ⚠️ BLK-7 FIX equivalent: RecordActivityRow is a DAO query projection (like
/// RecordTotalPaid in §5.4). Defined in core/data alongside RecordDao — NOT in
/// core/domain and NOT in app/. It is an internal DB-shaped type and must never be
/// exported outside core/data.
class RecordActivityRow {
  const RecordActivityRow({
    required this.recordId,
    required this.lastPaymentDate,
  });

  final String recordId;
  final String? lastPaymentDate;

  factory RecordActivityRow.fromMap(Map<String, dynamic> map) {
    return RecordActivityRow(
      recordId: (map['record_id'] ?? map['recordId']) as String,
      lastPaymentDate: (map['last_payment_date'] ?? map['lastPaymentDate']) as String?,
    );
  }
}
