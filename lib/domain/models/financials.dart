/// Per-record financial calculation snapshot (§5.1, §5.2.1, & §5.2.2).
///
/// Mandated by BLK-10 FIX & [FIX-FINANCIALS-OVERPAY-1]:
/// All 8 canonical financial fields must be supplied:
/// - totalInterest
/// - totalPaid
/// - interestPaid
/// - principalPaid
/// - outstandingInterest
/// - outstandingPrincipal
/// - totalDue
/// - overpaymentAmount
class Financials {
  final double totalInterest;
  final double totalPaid;
  final double interestPaid;
  final double principalPaid;
  final double outstandingInterest;
  final double outstandingPrincipal;
  final double totalDue;
  final double overpaymentAmount;
  final double principal;
  final double months;

  const Financials({
    required this.totalInterest,
    required this.totalPaid,
    required this.interestPaid,
    required this.principalPaid,
    required this.outstandingInterest,
    required this.outstandingPrincipal,
    required this.totalDue,
    this.overpaymentAmount = 0.0,
    this.principal = 0.0,
    this.months = 0.0,
  });

  // Semantic aliases for remaining balances
  double get remainingPrincipal => outstandingPrincipal;
  double get remainingInterest => outstandingInterest;

  /// True when cumulative principalPaid covers or exceeds principalAmount (§5.2.4).
  bool get isPrincipalFullyPaid => principal > 0 && principalPaid >= principal;

  static const zero = Financials(
    totalInterest: 0.0,
    totalPaid: 0.0,
    interestPaid: 0.0,
    principalPaid: 0.0,
    outstandingInterest: 0.0,
    outstandingPrincipal: 0.0,
    totalDue: 0.0,
    overpaymentAmount: 0.0,
    principal: 0.0,
    months: 0.0,
  );
}
