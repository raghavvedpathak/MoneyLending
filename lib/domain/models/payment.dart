import '../../core/utils/app_date_formatter.dart';

/// Pure Domain Entity for Payment.
///
/// Mandated by Data Spec §4.1 & [FIX-TIMESTAMP-PAYMENT-1]:
/// - date captures the exact moment payment was received.
class Payment {
  final String id;
  final String recordId;
  final double amount;
  final DateTime date;
  final String? notes;
  final double interestPaid;
  final double principalPaid;

  const Payment({
    required this.id,
    required this.recordId,
    required this.amount,
    required this.date,
    this.notes,
    required this.interestPaid,
    required this.principalPaid,
  });

  /// Formatted as "10 September 2026"
  String get formattedDate => formatDate(date);

  /// Formatted as "10 September 2026, 02:30 PM"
  String get formattedDateTime => formatDateTime(date);
}
