import '../../core/domain/util/date_format.dart';

/// MonthlyEarning — cash-basis interest received in a given calendar month (§5.1 & [FIX-DOMAIN-MODELS-1]).
///
/// Produced by getMonthlyInterest() in core/calculations. Used by the Earnings chart in features/reports.
/// "Cash-basis" means: use Payment.interestPaid grouped by payment date's (year, month) — not accrual.
/// The chart label is "Interest Received" (not "Interest Accrued").
class MonthlyEarning {
  final DateTime month; // always the 1st of the month, time truncated
  final double interestReceived; // sum of Payment.interestPaid for all payments in this month

  const MonthlyEarning({
    required this.month,
    required this.interestReceived,
  });

  /// Year component of [month]
  int get year => month.year;

  /// Month component (1..12) of [month]
  int get monthNumber => month.month;

  /// Formatted as "September 2026"
  String get formattedMonth => formatMonthYear(month);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MonthlyEarning &&
          runtimeType == other.runtimeType &&
          month.year == other.month.year &&
          month.month == other.month.month &&
          interestReceived == other.interestReceived;

  @override
  int get hashCode => Object.hash(month.year, month.month, interestReceived);
}
