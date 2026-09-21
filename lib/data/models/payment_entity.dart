import '../../core/utils/app_date_formatter.dart';

/// Data Layer Entity for 'payments' table.
///
/// Mandated by Data Spec §4.1, [FIX-TIMESTAMP-PAYMENT-1], and [FIX-ID-FORMAT-1]:
/// - id: UUID String (Primary Key)
/// - recordId: Foreign key referencing records.id
/// - amount: Total payment amount received
/// - date: [FIX-TIMESTAMP-PAYMENT-1] ISO datetime string YYYY-MM-DDTHH:MM:SS
/// - notes: Optional payment remarks
/// - interestPaid: Portion of payment allocated to outstanding interest
/// - principalPaid: Portion of payment allocated to principal reduction
/// - paymentId: [FIX-ID-FORMAT-1] PAY + month (2 digits) + year (2 digits) + sequence (2 digits)
class PaymentEntity {
  final String id;
  final String recordId;
  final double amount;
  final String date; // ISO Datetime YYYY-MM-DDTHH:MM:SS
  final String? notes;
  final double interestPaid;
  final double principalPaid;
  final String paymentId; // PAY + MMYY + sequence

  const PaymentEntity({
    required this.id,
    required this.recordId,
    required this.amount,
    required this.date,
    this.notes,
    required this.interestPaid,
    required this.principalPaid,
    this.paymentId = '',
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': id,
      'recordId': recordId,
      'amount': amount,
      'date': date,
      'notes': notes,
      'interestPaid': interestPaid,
      'principalPaid': principalPaid,
    };
    if (paymentId.isNotEmpty) {
      map['paymentId'] = paymentId;
    }
    return map;
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
      paymentId: (map['paymentId'] as String?) ?? '',
    );
  }

  PaymentEntity copyWith({
    String? id,
    String? recordId,
    double? amount,
    String? date,
    String? notes,
    double? interestPaid,
    double? principalPaid,
    String? paymentId,
  }) {
    return PaymentEntity(
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

/// Drift/DAO alias mandated by Data Spec §4.4 (@DataClassName('PaymentEntityData'))
typedef PaymentEntityData = PaymentEntity;
