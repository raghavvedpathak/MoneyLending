import '../../core/utils/app_date_formatter.dart';

/// Data Layer Entity for 'records' table.
///
/// Mandated by Data Spec §4.1:
/// - id: UUID String (Primary Key)
/// - transactionId: Unique transaction identifier string
/// - type: 'GIVEN' or 'TAKEN'
/// - customerId: Foreign key referencing customers.id
/// - customerName: Backward-compatibility display name
/// - startDate: [FIX-TIMESTAMPRECORD-1] ISO datetime YYYY-MM-DDTHH:MM:SS
/// - endDate: Optional ISO date/datetime (null for open-ended loans)
/// - principalAmount: Principal sum lent/borrowed
/// - interestRate: Interest rate percentage
/// - status: Loan status ('ACTIVE', 'SETTLED', etc.)
/// - settledDate: ISO datetime when settled (null while active)
/// - calculatedInterest: Snapshotted interest at settle time
class RecordEntity {
  final String id;
  final String transactionId;
  final String type; // 'GIVEN' | 'TAKEN'
  final String customerId;
  final String? customerName;
  final String startDate; // ISO Datetime YYYY-MM-DDTHH:MM:SS
  final String? endDate; // null for open-ended
  // DO NOT CHANGE TO INTEGER — switching to paise storage requires a Room schema migration; see §4.2 for full rationale.
  final double principalAmount;
  final double interestRate;
  final String status; // 'ACTIVE' | 'SETTLED'
  final String? settledDate;
  final double? calculatedInterest;
  final String? linkedRecordId;

  const RecordEntity({
    required this.id,
    required this.transactionId,
    required this.type,
    required this.customerId,
    this.customerName,
    required this.startDate,
    this.endDate,
    required this.principalAmount,
    required this.interestRate,
    required this.status,
    this.settledDate,
    this.calculatedInterest,
    this.linkedRecordId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'transactionId': transactionId,
      'type': type,
      'customerId': customerId,
      'customerName': customerName,
      'startDate': startDate,
      'endDate': (endDate != null && endDate!.isNotEmpty) ? endDate : null,
      'principalAmount': principalAmount,
      'interestRate': interestRate,
      'status': status,
      'settledDate': settledDate,
      'calculatedInterest': calculatedInterest,
      'linkedRecordId': linkedRecordId,
    };
  }

  factory RecordEntity.fromMap(Map<String, dynamic> map) {
    final rawEndDate = map['endDate'] as String?;
    return RecordEntity(
      id: map['id'] as String,
      transactionId: map['transactionId'] as String,
      type: map['type'] as String,
      customerId: map['customerId'] as String,
      customerName: map['customerName'] as String?,
      startDate: map['startDate'] as String,
      endDate: (rawEndDate != null && rawEndDate.isNotEmpty) ? rawEndDate : null,
      principalAmount: (map['principalAmount'] as num).toDouble(),
      interestRate: (map['interestRate'] as num).toDouble(),
      status: map['status'] as String,
      settledDate: map['settledDate'] as String?,
      calculatedInterest: (map['calculatedInterest'] as num?)?.toDouble(),
      linkedRecordId: map['linkedRecordId'] as String?,
    );
  }

  /// Safe start date parser handling ISO datetime (YYYY-MM-DDTHH:MM:SS) per [FIX-TIMESTAMP-RECORD-1].
  DateTime get parsedStartDate {
    try {
      return DateTime.parse(startDate);
    } catch (_) {
      return DateTime.now();
    }
  }

  /// Formatted as "10 September 2026"
  String get formattedStartDate => AppDateFormatter.formatDateString(startDate);

  /// Formatted as "10 September 2026, 02:30 PM"
  String get formattedStartDateTime => AppDateFormatter.formatDateTimeString(startDate);

  /// Formatted as "10 September 2026" or null
  String? get formattedEndDate =>
      endDate != null ? AppDateFormatter.formatDateString(endDate) : null;
}

/// Drift/DAO alias mandated by Data Spec §4.4 (@DataClassName('RecordEntityData'))
typedef RecordEntityData = RecordEntity;
