import 'dart:convert';
import '../../../domain/domain.dart';
import 'backup_migration.dart';
import 'models/backup_customer.dart';
import 'models/backup_item.dart';
import 'models/backup_payment.dart';
import 'models/backup_record.dart';
import 'models/backup_retired_id.dart';
import 'models/backup_wrapper.dart';

/// Exception thrown when encountering an unrecognized backup version string (§7.1).
class UnsupportedBackupVersionException implements Exception {
  final String message;
  const UnsupportedBackupVersionException([
    this.message = 'This backup was created by a newer version of MoneyLending. Please update the app before importing.',
  ]);

  @override
  String toString() => message;
}

/// Central Backup Serializer & Version Manager (:core:data:backup).
///
/// Mandated by Business Logic Spec §7.1:
/// - Single source of truth for [backupVersion] ('1.4').
/// - Encodes domain data to [BackupWrapper] JSON.
/// - Decodes versioned (1.1, 1.2, 1.3, 1.4) and legacy bare-array JSON.
/// - Strict exact-string matching on version, rejecting unrecognized versions.
class BackupSerializer {
  BackupSerializer._();

  /// Single source of truth for the backup format version string.
  /// Bump this constant when ANY field at ANY nesting level changes — see version bump rules in §7.1.
  ///
  /// Version history:
  /// - 1.1: Original versioned format.
  /// - 1.2: BackupRecord.startDate and BackupPayment.date changed to ISO datetime strings ([FIX-TIMESTAMP-BACKUP-1]).
  /// - 1.3: LedgerItemEntity.sourceItemId added ([FIX-ITEM-CUSTODY-MIGRATION-1]).
  /// - 1.4: Display-ID scheme (Addendum G, [FIX-ID-BACKUP-1]), BackupPayment.paymentId, retiredIds top-level array.
  static const backupVersion = '1.4';

  /// Encodes a BackupWrapper to a JSON string.
  /// All exports go through this method — never call jsonEncode directly on a raw Map.
  static String encode(BackupWrapper wrapper) => jsonEncode(wrapper.toJson());

  /// Decodes and migrates a JSON backup string into a validated, normalized [BackupWrapper].
  ///
  /// Handles:
  /// 1. Legacy bare-array format (pre-versioned List).
  /// 2. Version "1.1" -> runs [migrate1_1To1_2] and assigns display IDs.
  /// 3. Version "1.2", "1.3", "1.4" -> decodes directly with defaulted keys and assigns missing display IDs.
  /// 4. Unknown version -> throws [UnsupportedBackupVersionException].
  static BackupWrapper decode(String jsonString) {
    final dynamic decoded = jsonDecode(jsonString);

    if (decoded is List) {
      // Legacy bare-array format (predates version wrapper, just [...])
      return _decodeLegacyBareArray(decoded);
    } else if (decoded is Map<String, dynamic>) {
      final version = decoded['version']?.toString();
      if (version == null) {
        throw const UnsupportedBackupVersionException();
      }

      switch (version) {
        case '1.1':
          final wrapper = BackupWrapper.fromJson(decoded);
          final migrated = migrate1_1To1_2(wrapper);
          return assignMissingDisplayIds(migrated);
        case '1.2':
        case '1.3':
        case '1.4':
          final wrapper = BackupWrapper.fromJson(decoded);
          return assignMissingDisplayIds(wrapper);
        default:
          throw const UnsupportedBackupVersionException();
      }
    } else {
      throw const FormatException('Invalid backup JSON: Root must be either a JSON Object or a JSON Array');
    }
  }

  /// Decodes legacy bare-array format into a modernized v1.4 [BackupWrapper].
  static BackupWrapper _decodeLegacyBareArray(List<dynamic> list) {
    final records = <BackupRecord>[];
    final customersMap = <String, BackupCustomer>{};

    for (final raw in list) {
      if (raw is! Map<String, dynamic>) continue;
      final record = BackupRecord.fromJson(raw);
      records.add(record);

      // Synthesize customer from record.customerId and record.customerName if not already tracked
      if (record.customerId.isNotEmpty && !customersMap.containsKey(record.customerId)) {
        customersMap[record.customerId] = BackupCustomer(
          id: record.customerId,
          name: record.customerName ?? 'Customer',
          phone: '',
          address: null,
          createdAt: record.startDate.isNotEmpty ? record.startDate : DateTime.now().toIso8601String(),
          displayId: '', // To be assigned by assignMissingDisplayIds()
        );
      }
    }

    final initialWrapper = BackupWrapper(
      version: '1.1',
      customers: customersMap.values.toList(),
      records: records,
      retiredIds: const [],
    );

    // Apply pre-versioned -> v1.1 display ID assignment
    final assigned = assignMissingDisplayIds(initialWrapper);

    // Apply 1.1 -> 1.2 datetime coercion (appending T00:00:00)
    return migrate1_1To1_2(assigned);
  }

  // ===========================================================================
  // DOMAIN <-> DTO MAPPERS (§7.1)
  // ===========================================================================

  /// Maps domain models into a [BackupWrapper] tagged with [backupVersion].
  static BackupWrapper fromDomain({
    required List<Customer> customers,
    required List<LedgerRecord> records,
    List<BackupRetiredId> retiredIds = const [],
  }) {
    final backupCustomers = customers.map((c) {
      return BackupCustomer(
        id: c.id,
        displayId: c.displayId,
        name: c.name,
        phone: c.phone ?? '',
        address: c.address,
        createdAt: c.createdAt.toIso8601String(),
      );
    }).toList();

    final backupRecords = records.map((r) {
      final items = r.items.map((i) {
        return BackupItem(
          id: i.id,
          recordId: i.recordId,
          name: i.name,
          itemCategory: i.itemCategory,
          description: i.description,
          weight: i.weight,
          purity: i.purity,
          rate: i.rate,
          itemValue: i.itemValue,
          lendPercentage: i.lendPercentage,
          lendableAmount: i.lendableAmount,
          fineWeight: i.fineWeight,
          sourceItemId: i.sourceItemId,
        );
      }).toList();

      final payments = r.payments.map((p) {
        return BackupPayment(
          id: p.id,
          paymentId: p.paymentId,
          recordId: p.recordId,
          amount: p.amount,
          date: p.date.toIso8601String(),
          interestPaid: p.interestPaid,
          principalPaid: p.principalPaid,
          notes: p.notes,
        );
      }).toList();

      return BackupRecord(
        id: r.id,
        transactionId: r.transactionId,
        type: r.type.name.toUpperCase(), // [FIX-ENUM-CASE-1]
        status: r.status.name.toUpperCase(), // [FIX-ENUM-CASE-1]
        customerId: r.customerId,
        customerName: r.customerName,
        startDate: r.startDate.toIso8601String(),
        endDate: r.endDate != null ? r.endDate!.toIso8601String() : '', // Export maps null -> "" (§4.2)
        principalAmount: r.principalAmount,
        interestRate: r.interestRate,
        settledDate: r.settledDate?.toIso8601String(),
        calculatedInterest: r.calculatedInterest,
        linkedRecordId: r.linkedRecordId,
        itemCategory: items.isNotEmpty ? items.first.itemCategory : 'Unknown',
        items: items,
        payments: payments,
      );
    }).toList();

    return BackupWrapper(
      version: backupVersion,
      customers: backupCustomers,
      records: backupRecords,
      retiredIds: retiredIds,
    );
  }

  /// Maps a normalized [BackupWrapper] into domain entities.
  static ({
    List<Customer> customers,
    List<LedgerRecord> records,
    List<BackupRetiredId> retiredIds,
  }) toDomain(BackupWrapper wrapper) {
    final customers = wrapper.customers.map((c) {
      return Customer(
        id: c.id,
        displayId: c.displayId,
        name: c.name,
        phone: c.phone.isNotEmpty ? c.phone : null,
        address: c.address,
        createdAt: DateTime.tryParse(c.createdAt) ?? DateTime.now(),
      );
    }).toList();

    final records = wrapper.records.map((r) {
      // Coerce endDate: "" -> null (§4.2 endDate contract) and null -> null (open-ended loan)
      DateTime? parsedEndDate;
      if (r.endDate != null && r.endDate!.trim().isNotEmpty) {
        parsedEndDate = DateTime.tryParse(r.endDate!);
      }

      final items = r.items.map<LedgerItem>((i) {
        return LedgerItem(
          id: i.id,
          recordId: i.recordId,
          name: i.name,
          itemCategory: i.itemCategory,
          description: i.description,
          weight: i.weight,
          purity: i.purity,
          rate: i.rate,
          itemValue: i.itemValue,
          lendPercentage: i.lendPercentage,
          lendableAmount: i.lendableAmount,
          sourceItemId: i.sourceItemId,
        );
      }).toList();

      final payments = r.payments.map<Payment>((p) {
        return Payment(
          id: p.id,
          paymentId: p.paymentId,
          recordId: p.recordId,
          amount: p.amount,
          date: DateTime.tryParse(p.date) ?? DateTime.now(),
          interestPaid: p.interestPaid,
          principalPaid: p.principalPaid,
          notes: p.notes,
        );
      }).toList();

      // [FIX-ENUM-CASE-1] Convert UPPERCASE string to Dart enum with clear rejection on unknown value
      final RecordType recordType;
      try {
        recordType = RecordType.values.firstWhere(
          (e) => e.name.toUpperCase() == r.type.toUpperCase(),
        );
      } catch (_) {
        throw FormatException('Unknown RecordType in backup: ${r.type}');
      }

      final RecordStatus recordStatus;
      try {
        recordStatus = RecordStatus.values.firstWhere(
          (e) => e.name.toUpperCase() == r.status.toUpperCase(),
        );
      } catch (_) {
        throw FormatException('Unknown RecordStatus in backup: ${r.status}');
      }

      return LedgerRecord(
        id: r.id,
        transactionId: r.transactionId,
        type: recordType,
        status: recordStatus,
        customerId: r.customerId,
        customerName: r.customerName,
        startDate: DateTime.tryParse(r.startDate) ?? DateTime.now(),
        endDate: parsedEndDate,
        principalAmount: r.principalAmount,
        interestRate: r.interestRate,
        settledDate: r.settledDate != null ? DateTime.tryParse(r.settledDate!) : null,
        calculatedInterest: r.calculatedInterest,
        linkedRecordId: r.linkedRecordId,
        items: items,
        payments: payments,
      );
    }).toList();

    return (
      customers: customers,
      records: records,
      retiredIds: wrapper.retiredIds,
    );
  }
}
