import 'backup_customer.dart';
import 'backup_item_rate.dart';
import 'backup_lender.dart';
import 'backup_record.dart';
import 'backup_retired_id.dart';
import 'backup_settings.dart';

/// Top-level Backup Wrapper DTO (§7.1, [FIX-BACKUP-CONFIG-1], Addendum J.7).
///
/// Mandated by Business Logic Spec §7.1:
/// - [version]: migration key (e.g. "1.4")
/// - [customers]: list of [BackupCustomer]
/// - [lenders]: optional list of [BackupLender] (§4.4, [FIX-LENDER-BACKUP-1], null = key absent in JSON)
/// - [records]: list of [BackupRecord]
/// - [settings]: optional [BackupSettings] (null = leave existing device settings alone)
/// - [itemRates]: optional list of [BackupItemRate] (null = leave existing rates alone)
/// - [retiredIds]: list of [BackupRetiredId] (Addendum G, FIX-ID-REUSE-1)
class BackupWrapper {
  final String version;
  final List<BackupCustomer> customers;
  final List<BackupLender>? lenders;
  final List<BackupRecord> records;
  final BackupSettings? settings;
  final List<BackupItemRate>? itemRates;
  final List<BackupRetiredId> retiredIds;

  const BackupWrapper({
    required this.version,
    required this.customers,
    this.lenders,
    required this.records,
    this.settings,
    this.itemRates,
    this.retiredIds = const [],
  });

  BackupWrapper copyWith({
    String? version,
    List<BackupCustomer>? customers,
    List<BackupLender>? lenders,
    List<BackupRecord>? records,
    BackupSettings? settings,
    List<BackupItemRate>? itemRates,
    List<BackupRetiredId>? retiredIds,
  }) {
    return BackupWrapper(
      version: version ?? this.version,
      customers: customers ?? this.customers,
      lenders: lenders ?? this.lenders,
      records: records ?? this.records,
      settings: settings ?? this.settings,
      itemRates: itemRates ?? this.itemRates,
      retiredIds: retiredIds ?? this.retiredIds,
    );
  }

  factory BackupWrapper.fromJson(Map<String, dynamic> json) {
    final rawCustomers = json['customers'] as List<dynamic>? ?? const [];
    final rawRecords = json['records'] as List<dynamic>? ?? const [];
    final rawRetiredIds = json['retiredIds'] as List<dynamic>? ?? const [];

    List<BackupLender>? parsedLenders;
    if (json.containsKey('lenders')) {
      if (json['lenders'] != null && json['lenders'] is List) {
        parsedLenders = (json['lenders'] as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .map((l) => BackupLender.fromJson(l))
            .toList();
      } else {
        parsedLenders = const [];
      }
    }

    BackupSettings? parsedSettings;
    if (json.containsKey('settings') && json['settings'] != null) {
      if (json['settings'] is Map<String, dynamic>) {
        parsedSettings = BackupSettings.fromJson(json['settings'] as Map<String, dynamic>);
      }
    }

    List<BackupItemRate>? parsedItemRates;
    if (json.containsKey('itemRates') && json['itemRates'] != null) {
      if (json['itemRates'] is List) {
        parsedItemRates = (json['itemRates'] as List)
            .whereType<Map<String, dynamic>>()
            .map((i) => BackupItemRate.fromJson(i))
            .toList();
      }
    }

    return BackupWrapper(
      version: json['version']?.toString() ?? '',
      customers: rawCustomers
          .whereType<Map<String, dynamic>>()
          .map((c) => BackupCustomer.fromJson(c))
          .toList(),
      lenders: parsedLenders,
      records: rawRecords
          .whereType<Map<String, dynamic>>()
          .map((r) => BackupRecord.fromJson(r))
          .toList(),
      settings: parsedSettings,
      itemRates: parsedItemRates,
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
      if (lenders != null) 'lenders': lenders!.map((l) => l.toJson()).toList(),
      'records': records.map((r) => r.toJson()).toList(),
      if (settings != null) 'settings': settings!.toJson(),
      if (itemRates != null) 'itemRates': itemRates!.map((i) => i.toJson()).toList(),
      'retiredIds': retiredIds.map((i) => i.toJson()).toList(),
    };
  }
}
