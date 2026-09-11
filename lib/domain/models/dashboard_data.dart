import 'dashboard_stats.dart';
import 'ledger_record.dart';

/// The Success payload for DashboardViewModel's UiState (§5.1).
///
/// collectionAlerts is intentionally NOT a field here — it is a separate
/// stream in DashboardViewModel so debounce(300L) applies only to rate-driven recomputation.
class DashboardData {
  final List<LedgerRecord> givenRecords;
  final List<LedgerRecord> takenRecords;
  final DashboardStats stats; // Totals for summary cards

  const DashboardData({
    required this.givenRecords,
    required this.takenRecords,
    required this.stats,
  });
}
