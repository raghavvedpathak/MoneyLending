import '../../core/utils/app_date_formatter.dart';

/// Data Layer Entity for 'payments' table.
///
/// Mandated by Data Spec §4.1 and [FIX-TIMESTAMP-PAYMENT-1]:
/// - id: UUID String (Primary Key)
/// - recordId: Foreign key referencing records.id
/// - amount: Total payment amount received
/// - date: [FIX-TIMESTAMP-PAYMENT-1] ISO datetime string YYYY-MM-DDTHH:MM:SS
/// - notes: Optional payment remarks
/// - interestPaid: Portion of payment allocated to outstanding interest
class PaymentEntity {
  final String id;
  final String recordId;
  // DO NOT CHANGE TO INTEGER — switching to paise storage requires a Room schema migration; see §4.2 for full rationale.
  final double amount;
  final String date; // ISO Datetime YYYY-MM-DDTHH:MM:SS
  final String? notes;
  final double interestPaid;
  final double principalPaid;

  const PaymentEntity({
    required this.id,
    required this.recordId,
    required this.amount,
    required this.date,
    this.notes,
    required this.interestPaid,
    required this.principalPaid,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'recordId': recordId,
      'amount': amount,
      'date': date,
      'notes': notes,
      'interestPaid': interestPaid,
      'principalPaid': principalPaid,
    };
  }

  factory PaymentEntity.fromMap(Map<String, dynamic> map) {
    return PaymentEntity(
      id: map['id'] as String,
      recordId: map['recordId'] as String,
      amount: (map['amount'] as num).toDouble(),
      date: map['date'] as String,
      notes: map['notes'] as String?,
      interestPaid: (map['interestPaid'] as num).toDouble(),
      principalPaid: (map['principalPaid'] as num).toDouble(),
    );
  }

  /// Safe date parser handling both ISO datetime (YYYY-MM-DDTHH:MM:SS)
  /// and legacy ISO date-only strings (YYYY-MM-DD) per [FIX-TIMESTAMP-PAYMENT-1].
  DateTime get parsedDateTime {
    try {
      return DateTime.parse(date);
    } catch (_) {
      return DateTime.now();
    }
  }

  /// Formatted as "10 September 2026"
  String get formattedDate => AppDateFormatter.formatDate(parsedDateTime);

  /// Formatted as "10 September 2026, 02:30 PM"
  String get formattedDateTime => AppDateFormatter.formatDateTime(parsedDateTime);
}
