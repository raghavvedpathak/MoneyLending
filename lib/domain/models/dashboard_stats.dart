/// Totals for the summary cards across all records (§5.1).
///
/// Financials is per-record; DashboardStats is the aggregate across all records.
class DashboardStats {
  final double totalPrincipalGiven;
  final double totalInterestAccruedGiven;
  final double totalDueGiven;
  final double totalPrincipalTaken;
  final double totalInterestAccruedTaken;
  final double totalDueTaken;

  const DashboardStats({
    required this.totalPrincipalGiven,
    required this.totalInterestAccruedGiven,
    required this.totalDueGiven,
    required this.totalPrincipalTaken,
    required this.totalInterestAccruedTaken,
    required this.totalDueTaken,
  });

  static const empty = DashboardStats(
    totalPrincipalGiven: 0.0,
    totalInterestAccruedGiven: 0.0,
    totalDueGiven: 0.0,
    totalPrincipalTaken: 0.0,
    totalInterestAccruedTaken: 0.0,
    totalDueTaken: 0.0,
  );
}
