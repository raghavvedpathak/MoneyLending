import '../../core/domain/util/date_format.dart';

/// Pure Domain Entity for Payment.
///
/// Mandated by Data Spec §4.1, [FIX-TIMESTAMP-PAYMENT-1], and [FIX-ID-FORMAT-1]:
/// - date captures the exact moment payment was received.
/// - paymentId: [FIX-ID-FORMAT-1] PAY + month (2 digits) + year (2 digits) + sequence (2 digits)
class Payment {
  final String id;
  final String recordId;
  final double amount;
  final DateTime date;
  final String? notes;
  final double interestPaid;
  final double principalPaid;
  final String paymentId; // PAY + MMYY + sequence

  const Payment({
    required this.id,
    required this.recordId,
    required this.amount,
    required this.date,
    this.notes,
    required this.interestPaid,
    required this.principalPaid,
    this.paymentId = '',
  });

  /// Formatted as "10 September 2026"
  String get formattedDate => formatDate(date);

  /// Formatted as "10 September 2026, 02:30 PM"
  String get formattedDateTime => formatDateTime(date);

  Payment copyWith({
    String? id,
    String? recordId,
    double? amount,
    DateTime? date,
    String? notes,
    double? interestPaid,
    double? principalPaid,
    String? paymentId,
  }) {
    return Payment(
      id: id ?? this.id,
      recordId: recordId ?? this.recordId,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      notes: notes ?? this.notes,
      interestPaid: interestPaid ?? this.interestPaid,
      principalPaid: principalPaid ?? this.principalPaid,
      paymentId: paymentId ?? this.paymentId,
    );
  }
}
