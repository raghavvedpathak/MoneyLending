import 'customer.dart';

/// BorrowerReport — per-party aggregate for the Reports screen (§5.1).
///
/// One row per Borrower (GIVEN side) — produced by getBorrowerReports() in core/calculations.
class BorrowerReport {
  const BorrowerReport({
    required this.customer,
    required this.activeRecordCount,
    required this.totalPrincipalOut, // sum of principalAmount across ACTIVE GIVEN records for this borrower
    required this.totalInterestAccrued, // sum of calculateRecordFinancials(r, today).totalInterest, ACTIVE GIVEN
    required this.totalDue, // sum of calculateRecordFinancials(r, today).totalDue, ACTIVE GIVEN
  });

  final Customer customer;
  final int activeRecordCount;
  final double totalPrincipalOut;
  final double totalInterestAccrued;
  final double totalDue;

  /// Alias for backward-compatibility with CustomerReport (§5.1)
  double get totalPrincipal => totalPrincipalOut;
}
