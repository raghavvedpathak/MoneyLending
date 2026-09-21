/// Backup DTO for Payment (§7.1).
///
/// Mandated by Data Spec §4.1 and [FIX-TIMESTAMP-BACKUP-1]:
/// - [date]: ISO datetime string ("2026-04-23T14:30:00")
/// - [paymentId]: formatted identifier (e.g. PAY092601) added in v1.4; defaults to '' on older versions.
class BackupPayment {
  final String id;
  final String paymentId;
  final String recordId;
  final double amount;
  final String date;
  final double interestPaid;
  final double principalPaid;
  final String? notes;

  const BackupPayment({
    required this.id,
    this.paymentId = '',
    this.recordId = '',
    required this.amount,
    required this.date,
    this.interestPaid = 0.0,
    this.principalPaid = 0.0,
    this.notes,
  });

  BackupPayment copyWith({
    String? id,
    String? paymentId,
    String? recordId,
    double? amount,
    String? date,
    double? interestPaid,
    double? principalPaid,
    String? notes,
  }) {
    return BackupPayment(
      id: id ?? this.id,
      paymentId: paymentId ?? this.paymentId,
      recordId: recordId ?? this.recordId,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      interestPaid: interestPaid ?? this.interestPaid,
      principalPaid: principalPaid ?? this.principalPaid,
      notes: notes ?? this.notes,
    );
  }

  factory BackupPayment.fromJson(Map<String, dynamic> json) {
    return BackupPayment(
      id: json['id']?.toString() ?? '',
      paymentId: json['paymentId']?.toString() ?? '',
      recordId: json['recordId']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      date: json['date']?.toString() ?? '',
      interestPaid: (json['interestPaid'] as num?)?.toDouble() ?? 0.0,
      principalPaid: (json['principalPaid'] as num?)?.toDouble() ?? 0.0,
      notes: json['notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'paymentId': paymentId,
      'recordId': recordId,
      'amount': amount,
      'date': date,
      'interestPaid': interestPaid,
      'principalPaid': principalPaid,
      if (notes != null) 'notes': notes,
    };
  }
}
