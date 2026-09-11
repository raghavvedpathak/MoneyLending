import 'customer.dart';

/// CustomerReport — per-customer aggregate for the Reports screen Overview tab.
///
/// Mandated by Data Spec §5.1 & [FIX-DOMAIN-MODELS-1]:
/// Produced by getCustomerReport() in :core:calculations. One row per customer.
class CustomerReport {
  final Customer customer;
  final int activeRecordCount;
  final double totalPrincipal; // sum of principalAmount across ACTIVE records for this customer
  final double totalInterestAccrued; // sum of calculateRecordFinancials(r, today).totalInterest
  final double totalDue; // sum of calculateRecordFinancials(r, today).totalDue

  const CustomerReport({
    required this.customer,
    required this.activeRecordCount,
    required this.totalPrincipal,
    required this.totalInterestAccrued,
    required this.totalDue,
  });
}
