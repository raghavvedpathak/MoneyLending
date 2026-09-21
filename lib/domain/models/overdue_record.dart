import '../../core/utils/app_date_formatter.dart';
import 'ledger_record.dart';

/// OverdueReason — why a record appears on the Overdue tab (§5.1 & [FIX-OVERDUE-COLLATERAL-1]).
///
/// A record can carry more than one reason (e.g. no payment activity in 30+ days
/// AND collateral value has also fallen below the amount owed).
enum OverdueReason {
  noActivity,
  collateralBreachedNow,
  collateralProjected2Months,
}

/// OverdueRecord — a record flagged on the Overdue tab in features/reports (§5.1 & [FIX-DOMAIN-MODELS-1]).
///
/// Produced by getOverdue() (noActivity — activity-based, unchanged) and
/// computeCollateralOverdue() (collateralBreachedNow / collateralProjected2Months —
/// live-rate based, GIVEN + TAKEN — see FIX-OVERDUE-COLLATERAL-1), then merged by
/// mergeOverdueRecords() in the caller — never inside core/calculations.
class OverdueRecord {
  final LedgerRecord record;
  final Set<OverdueReason> reasons; // non-empty Set<OverdueReason>
  final int? daysSinceActivity; // set only when reasons contains noActivity
  final DateTime? lastActivityDate; // set only when reasons contains noActivity
  final double? currentCollateralValue; // set only when reasons contains a collateral* reason
  final double? currentObligation; // set only when reasons contains a collateral* reason
  final double? projectedObligationIn2Months; // set only when reasons contains collateralProjected2Months

  const OverdueRecord({
    required this.record,
    this.reasons = const {OverdueReason.noActivity},
    this.daysSinceActivity,
    this.lastActivityDate,
    this.currentCollateralValue,
    this.currentObligation,
    this.projectedObligationIn2Months,
  });

  /// Formatted as "10 September 2026"
  String get formattedLastActivityDate =>
      lastActivityDate != null ? formatDate(lastActivityDate!) : '—';

  OverdueRecord copyWith({
    LedgerRecord? record,
    Set<OverdueReason>? reasons,
    int? daysSinceActivity,
    DateTime? lastActivityDate,
    double? currentCollateralValue,
    double? currentObligation,
    double? projectedObligationIn2Months,
  }) {
    return OverdueRecord(
      record: record ?? this.record,
      reasons: reasons ?? this.reasons,
      daysSinceActivity: daysSinceActivity ?? this.daysSinceActivity,
      lastActivityDate: lastActivityDate ?? this.lastActivityDate,
      currentCollateralValue: currentCollateralValue ?? this.currentCollateralValue,
      currentObligation: currentObligation ?? this.currentObligation,
      projectedObligationIn2Months: projectedObligationIn2Months ?? this.projectedObligationIn2Months,
    );
  }
}
