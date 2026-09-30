import 'lender.dart';

/// LenderReport is the TAKEN-side mirror of BorrowerReport, one row per Lender (§5.1).
///
/// Produced by getLenderReports() in core/calculations.
class LenderReport {
  const LenderReport({
    required this.lender,
    required this.activeRecordCount,
    required this.totalPrincipalTaken, // sum of principalAmount across ACTIVE TAKEN records for this lender
    required this.totalInterestPayable, // sum of calculateRecordFinancials(r, today).totalInterest, ACTIVE TAKEN
    required this.totalDueToLender, // sum of calculateRecordFinancials(r, today).totalDue, ACTIVE TAKEN
  });

  final Lender lender;
  final int activeRecordCount;
  final double totalPrincipalTaken;
  final double totalInterestPayable;
  final double totalDueToLender;
}
