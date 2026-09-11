import '../../core/utils/app_date_formatter.dart';
import 'ledger_record.dart';

/// OverdueRecord — a record with no activity (payment or creation) for more than thresholdDays.
///
/// Mandated by Data Spec §5.1 & [FIX-DOMAIN-MODELS-1]:
/// Produced by getOverdue() in :core:calculations. Used by the Overdue tab in :feature:reports.
class OverdueRecord {
  final LedgerRecord record;
  final int daysSinceActivity; // Days between last activity date and today
  final DateTime lastActivityDate; // MAX(payment.date) if payments exist, else record.startDate

  const OverdueRecord({
    required this.record,
    required this.daysSinceActivity,
    required this.lastActivityDate,
  });

  /// Formatted as "10 September 2026"
  String get formattedLastActivityDate => formatDate(lastActivityDate);
}
