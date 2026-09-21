import 'backup_item.dart';
import 'backup_payment.dart';

/// Backup DTO for LedgerRecord (§7.1).
///
/// Mandated by Business Logic Spec §7.1:
/// - [FIX-BACKUPRECORD-DEFAULTS-1]: Required defaults for fields that postdate legacy bare-array format:
///   * transactionId: defaults to ''
///   * itemCategory: defaults to 'Unknown'
///   * linkedRecordId: nullable (null)
///   * calculatedInterest: nullable (null)
///   * customerName: nullable (null)
/// - [FIX-BACKUPRECORD-ENDDATE-1]: endDate MUST be declared as nullable String? (never non-nullable).
/// - [FIX-ENUM-CASE-1]: type and status are uppercase strings ('GIVEN'/'TAKEN', 'ACTIVE'/'SETTLED').
/// - [FIX-TIMESTAMP-BACKUP-1]: startDate is an ISO datetime string ("2026-04-23T14:30:00").
class BackupRecord {
  final String id;
  final String transactionId;
  final String type;
  final String status;
  final String customerId;
  final String? customerName;
  final String startDate;
  final String? endDate;
  final double principalAmount;
  final double interestRate;
  final String? settledDate;
  final double? calculatedInterest;
  final String? linkedRecordId;
  final String itemCategory;
  final List<BackupItem> items;
  final List<BackupPayment> payments;

  const BackupRecord({
    required this.id,
    this.transactionId = '',
    required this.type,
    required this.status,
    required this.customerId,
    this.customerName,
    required this.startDate,
    this.endDate,
    required this.principalAmount,
    required this.interestRate,
    this.settledDate,
    this.calculatedInterest,
    this.linkedRecordId,
    this.itemCategory = 'Unknown',
    this.items = const [],
    this.payments = const [],
  });

  BackupRecord copyWith({
    String? id,
    String? transactionId,
    String? type,
    String? status,
    String? customerId,
    String? customerName,
    String? startDate,
    String? endDate,
    double? principalAmount,
    double? interestRate,
    String? settledDate,
    double? calculatedInterest,
    String? linkedRecordId,
    String? itemCategory,
    List<BackupItem>? items,
    List<BackupPayment>? payments,
  }) {
    return BackupRecord(
      id: id ?? this.id,
      transactionId: transactionId ?? this.transactionId,
      type: type ?? this.type,
      status: status ?? this.status,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      principalAmount: principalAmount ?? this.principalAmount,
      interestRate: interestRate ?? this.interestRate,
      settledDate: settledDate ?? this.settledDate,
      calculatedInterest: calculatedInterest ?? this.calculatedInterest,
      linkedRecordId: linkedRecordId ?? this.linkedRecordId,
      itemCategory: itemCategory ?? this.itemCategory,
      items: items ?? this.items,
      payments: payments ?? this.payments,
    );
  }

  factory BackupRecord.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    final rawPayments = json['payments'] as List<dynamic>? ?? const [];

    return BackupRecord(
      id: json['id']?.toString() ?? '',
      transactionId: json['transactionId']?.toString() ?? '',
      type: (json['type']?.toString() ?? 'GIVEN').toUpperCase(),
      status: (json['status']?.toString() ?? 'ACTIVE').toUpperCase(),
      customerId: json['customerId']?.toString() ?? '',
      customerName: json['customerName']?.toString(),
      startDate: json['startDate']?.toString() ?? '',
      endDate: json['endDate']?.toString(),
      principalAmount: (json['principalAmount'] as num?)?.toDouble() ?? 0.0,
      interestRate: (json['interestRate'] as num?)?.toDouble() ?? 0.0,
      settledDate: json['settledDate']?.toString(),
      calculatedInterest: (json['calculatedInterest'] as num?)?.toDouble(),
      linkedRecordId: json['linkedRecordId']?.toString(),
      itemCategory: json['itemCategory']?.toString() ?? 'Unknown',
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map((i) => BackupItem.fromJson(i))
          .toList(),
      payments: rawPayments
          .whereType<Map<String, dynamic>>()
          .map((p) => BackupPayment.fromJson(p))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'transactionId': transactionId,
      'type': type.toUpperCase(),
      'status': status.toUpperCase(),
      'customerId': customerId,
      if (customerName != null) 'customerName': customerName,
      'startDate': startDate,
      'endDate': endDate ?? '',
      'principalAmount': principalAmount,
      'interestRate': interestRate,
      'settledDate': settledDate,
      'calculatedInterest': calculatedInterest,
      'linkedRecordId': linkedRecordId,
      'itemCategory': itemCategory,
      'items': items.map((i) => i.toJson()).toList(),
      'payments': payments.map((p) => p.toJson()).toList(),
    };
  }
}
