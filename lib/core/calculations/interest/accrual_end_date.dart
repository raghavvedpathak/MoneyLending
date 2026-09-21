import '../../../domain/models/ledger_record.dart';

/// [FIX-ACCRUAL-END-1] (v1.14) Interest stops accruing at endDate. The single source of
/// truth for calculateRecordFinancials(), the §5.4 overshoot projection and Addendum F.
/// Pure: min(endDate, target). No clock.
DateTime accrualEndDate(LedgerRecord record, DateTime target) {
  final end = record.endDate;
  return (end != null && end.isBefore(target)) ? end : target;
}
