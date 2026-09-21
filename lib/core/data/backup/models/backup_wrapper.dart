import 'backup_customer.dart';
import 'backup_record.dart';
import 'backup_retired_id.dart';

/// Top-level Backup Wrapper DTO (§7.1).
///
/// Mandated by Business Logic Spec §7.1:
/// - [version]: migration key (e.g. "1.4")
/// - [customers]: list of [BackupCustomer]
/// - [records]: list of [BackupRecord]
/// - [retiredIds]: list of [BackupRetiredId] (Addendum G, FIX-ID-REUSE-1)
class BackupWrapper {
  final String version;
  final List<BackupCustomer> customers;
  final List<BackupRecord> records;
  final List<BackupRetiredId> retiredIds;

  const BackupWrapper({
    required this.version,
    required this.customers,
    required this.records,
    this.retiredIds = const [],
  });

  BackupWrapper copyWith({
    String? version,
    List<BackupCustomer>? customers,
    List<BackupRecord>? records,
    List<BackupRetiredId>? retiredIds,
  }) {
    return BackupWrapper(
      version: version ?? this.version,
      customers: customers ?? this.customers,
      records: records ?? this.records,
      retiredIds: retiredIds ?? this.retiredIds,
    );
  }

  factory BackupWrapper.fromJson(Map<String, dynamic> json) {
    final rawCustomers = json['customers'] as List<dynamic>? ?? const [];
    final rawRecords = json['records'] as List<dynamic>? ?? const [];
    final rawRetiredIds = json['retiredIds'] as List<dynamic>? ?? const [];

    return BackupWrapper(
      version: json['version']?.toString() ?? '',
      customers: rawCustomers
          .whereType<Map<String, dynamic>>()
          .map((c) => BackupCustomer.fromJson(c))
          .toList(),
      records: rawRecords
          .whereType<Map<String, dynamic>>()
          .map((r) => BackupRecord.fromJson(r))
          .toList(),
      retiredIds: rawRetiredIds
          .whereType<Map<String, dynamic>>()
          .map((i) => BackupRetiredId.fromJson(i))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'customers': customers.map((c) => c.toJson()).toList(),
      'records': records.map((r) => r.toJson()).toList(),
      'retiredIds': retiredIds.map((i) => i.toJson()).toList(),
    };
  }
}
