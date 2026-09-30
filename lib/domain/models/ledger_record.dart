import '../../core/domain/util/date_format.dart';
import 'ledger_item.dart';
import 'payment.dart';
import 'record_status.dart';
import 'record_type.dart';

/// Pure Domain Entity for Loan Record.
///
/// Mandated by Data Spec §4.1 & §4.2:
/// - startDate: [FIX-TIMESTAMPRECORD-1] exact moment money given/taken
/// - endDate: null for open-ended loans
/// - linkedRecordId: directional link (TAKEN points to GIVEN)
class LedgerRecord {
  final String id;
  final String transactionId;
  final String? customerId;
  final String? lenderId;
  final RecordType type;
  final RecordStatus status;
  final DateTime startDate;
  final DateTime? endDate;
  final double principalAmount;
  final double interestRate;
  final DateTime? settledDate;
  final double? calculatedInterest;
  final String? linkedRecordId;
  final String? customerName;
  final List<LedgerItem> items;
  final List<Payment> payments;

  const LedgerRecord({
    required this.id,
    required this.transactionId,
    this.customerId,
    this.lenderId,
    required this.type,
    required this.status,
    required this.startDate,
    this.endDate,
    required this.principalAmount,
    required this.interestRate,
    this.settledDate,
    this.calculatedInterest,
    this.linkedRecordId,
    this.customerName,
    this.items = const [],
    this.payments = const [],
  });

  /// Formatted as "10 September 2026"
  String get formattedStartDate => formatDate(startDate);

  /// Formatted as "10 September 2026, 02:30 PM"
  String get formattedStartDateTime => formatDateTime(startDate);

  /// Formatted as "10 September 2026" or null
  String? get formattedEndDate => endDate != null ? formatDate(endDate!) : null;

  /// Formatted as "10 September 2026" or null
  String? get formattedSettledDate => settledDate != null ? formatDate(settledDate!) : null;

  bool get isActive => status == RecordStatus.ACTIVE;
  bool get isSettled => status == RecordStatus.SETTLED;
  bool get isGiven => type == RecordType.GIVEN;
  bool get isTaken => type == RecordType.TAKEN;

  /// Whether the 'Mark as Settled' action is permissible (§5.2.4).
  /// Always available for any ACTIVE record (full payoff or early collateral release).
  bool get canBeSettled => isActive;

  /// [FIX-CHECKPAYMENT-DRAFT-1] (v1.27) used by the checkPaymentInsert() / reallocatePayments() dry runs.
  LedgerRecord copyWith({
    String? id,
    String? transactionId,
    RecordType? type,
    String? customerId,
    String? lenderId,
    String? customerName,
    DateTime? startDate,
    DateTime? endDate,
    double? principalAmount,
    double? interestRate,
    RecordStatus? status,
    DateTime? settledDate,
    double? calculatedInterest,
    String? linkedRecordId,
    bool clearLinkedRecord = false,
    List<LedgerItem>? items,
    List<Payment>? payments,
  }) {
    return LedgerRecord(
      id: id ?? this.id,
      transactionId: transactionId ?? this.transactionId,
      customerId: customerId ?? this.customerId,
      lenderId: lenderId ?? this.lenderId,
      type: type ?? this.type,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      principalAmount: principalAmount ?? this.principalAmount,
      interestRate: interestRate ?? this.interestRate,
      settledDate: settledDate ?? this.settledDate,
      calculatedInterest: calculatedInterest ?? this.calculatedInterest,
      linkedRecordId: clearLinkedRecord ? null : (linkedRecordId ?? this.linkedRecordId),
      customerName: customerName ?? this.customerName,
      items: items ?? this.items,
      payments: payments ?? this.payments,
    );
  }
}
