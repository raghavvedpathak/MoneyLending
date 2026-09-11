import '../../core/utils/app_date_formatter.dart';

/// MonthlyEarning — cash-basis interest received in a given calendar month.
///
/// Mandated by Data Spec §5.1, [FIX-DOMAIN-MODELS-1], & [FIX-TIMESTAMP-MONTHLYINTEREST-1]:
/// Produced by getMonthlyInterest() in :core:calculations. Used by the Earnings chart in :feature:reports.
/// "Cash-basis" means: use PaymentEntity.interestPaid grouped by payment date month — not accrual.
/// The chart label is "Interest Received" (not "Interest Accrued").
class MonthlyEarning {
  final int year;
  final int month;
  final double interestReceived; // sum of Payment.interestPaid for all payments in this month

  const MonthlyEarning({
    required this.year,
    required this.month,
    required this.interestReceived,
  });

  /// Formatted as "September 2026"
  String get formattedMonth => AppDateFormatter.formatMonthYear(DateTime(year, month, 1));
}
