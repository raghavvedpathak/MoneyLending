import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../domain/repositories/customer_repository.dart';
import '../../../domain/repositories/record_repository.dart';
import '../../di/injection.dart';
import 'backup_serializer.dart';
import 'models/backup_retired_id.dart';
import 'models/backup_wrapper.dart';

/// Exception thrown when backup content fails validation (§7.2).
class BackupValidationException implements Exception {
  final String message;
  final String? offendingId;

  const BackupValidationException(this.message, [this.offendingId]);

  @override
  String toString() => message;
}

/// Service managing JSON Backup Export and Restore (§7.2).
///
/// Mandated by Business Logic Spec §7.2:
/// - Uses [FilePicker] for both export and import (cross-platform equivalent of Storage Access Framework).
/// - [backupStamp]: yyyyMMdd_HHmmss built strictly with padLeft (never toIso8601String or DateFormat).
/// - Export filename: 'moneylending_backup_${backupStamp(DateTime.now())}.json'.
/// - Structured serialization with generated json_serializable classes (AOT & tree-shaking safe).
/// - Transactional replace-all restore wrapped in a single db.transaction().
/// - Validates for duplicate displayId, transactionId, paymentId, identifying offending IDs.
/// - Complete rollback on failure leaving device data 100% untouched.
class BackupService {
  final DatabaseHelper _dbHelper;
  final CustomerRepository _customerRepository;
  final RecordRepository _recordRepository;

  BackupService({
    DatabaseHelper? dbHelper,
    CustomerRepository? customerRepository,
    RecordRepository? recordRepository,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _customerRepository = customerRepository ?? sl<CustomerRepository>(),
        _recordRepository = recordRepository ?? sl<RecordRepository>();

  /// Formats a DateTime as yyyyMMdd_HHmmss using padLeft (§7.2).
  ///
  /// Spec requirements:
  /// - toIso8601String() contains ":" characters that Android/FAT storage rejects or rewrites.
  /// - DateFormat could emit non-ASCII digits on some device locales.
  /// - Built strictly with padLeft (e.g. 20260920_101530).
  static String backupStamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y$m${d}_$h$min$s';
  }

  /// Builds the canonical backup filename: 'moneylending_backup_${backupStamp(DateTime.now())}.json'.
  static String generateBackupFileName([DateTime? dt]) {
    final stamp = backupStamp(dt ?? DateTime.now());
    return 'moneylending_backup_$stamp.json';
  }

  /// Pure duplicate ID and integrity validator (§7.2, Addendum G, FIX-ID-BACKUP-1).
  ///
  /// Checks for duplicate displayId, transactionId, or paymentId inside the backup file
  /// and surfaces a clear error message identifying the offending ID.
  static void validateBackup(BackupWrapper wrapper) {
    // 1. Customer IDs and displayIds
    final customerIds = <String>{};
    final customerDisplayIds = <String>{};

    for (final c in wrapper.customers) {
      if (c.id.isNotEmpty && !customerIds.add(c.id)) {
        throw BackupValidationException(
          'Backup file contains duplicate customer ID: "${c.id}". Import aborted.',
          c.id,
        );
      }
      if (c.displayId.isNotEmpty && !customerDisplayIds.add(c.displayId)) {
        throw BackupValidationException(
          'Backup file contains duplicate customer displayId: "${c.displayId}". Import aborted.',
          c.displayId,
        );
      }
    }

    // 2. Records, transactionIds, and child payments/items
    final recordIds = <String>{};
    final transactionIds = <String>{};
    final itemIds = <String>{};
    final paymentIds = <String>{};
    final paymentDisplayIds = <String>{};

    for (final r in wrapper.records) {
      if (r.id.isNotEmpty && !recordIds.add(r.id)) {
        throw BackupValidationException(
          'Backup file contains duplicate record ID: "${r.id}". Import aborted.',
          r.id,
        );
      }
      if (r.transactionId.isNotEmpty && !transactionIds.add(r.transactionId)) {
        throw BackupValidationException(
          'Backup file contains duplicate transactionId: "${r.transactionId}". Import aborted.',
          r.transactionId,
        );
      }

      for (final item in r.items) {
        if (item.id.isNotEmpty && !itemIds.add(item.id)) {
          throw BackupValidationException(
            'Backup file contains duplicate item ID: "${item.id}". Import aborted.',
            item.id,
          );
        }
      }

      for (final p in r.payments) {
        if (p.id.isNotEmpty && !paymentIds.add(p.id)) {
          throw BackupValidationException(
            'Backup file contains duplicate payment ID: "${p.id}". Import aborted.',
            p.id,
          );
        }
        if (p.paymentId.isNotEmpty && !paymentDisplayIds.add(p.paymentId)) {
          throw BackupValidationException(
            'Backup file contains duplicate paymentId: "${p.paymentId}". Import aborted.',
            p.paymentId,
          );
        }
      }
    }
  }

  /// Generates the raw JSON string representation of all active and historical data in the database.
  Future<String> generateBackupJson() async {
    final customers = await _customerRepository.getAllCustomersOnce();
    final records = await _recordRepository.getAllRecordsOnce();
    final retiredIdMaps = await _dbHelper.getAllRetiredIds();

    final retiredIds = retiredIdMaps.map((m) => BackupRetiredId(
      kind: m['kind'] as String? ?? '',
      displayId: m['displayId'] as String? ?? '',
      retiredAt: m['retiredAt'] as String? ?? '',
    )).toList();

    final wrapper = BackupSerializer.fromDomain(
      customers: customers,
      records: records,
      retiredIds: retiredIds,
    );

    return BackupSerializer.encode(wrapper);
  }

  /// Exports full database backup to a JSON file using FilePicker (§7.2).
  ///
  /// On Android, internally uses ACTION_CREATE_DOCUMENT (no MANAGE_EXTERNAL_STORAGE needed).
  /// Returns the saved file path if chosen, or null if cancelled.
  Future<String?> exportBackup() async {
    final jsonString = await generateBackupJson();
    final bytes = utf8.encode(jsonString);
    final fileName = generateBackupFileName();

    final resultUri = await FilePickerPlatform.instance.saveFile(
      dialogTitle: 'Save MoneyLending Backup',
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/json',
    );

    if (resultUri != null) {
      try {
        final file = resultUri.isScheme('file')
            ? File.fromUri(resultUri)
            : File(resultUri.toFilePath());
        if (!await file.exists() || (await file.length()) == 0) {
          await file.writeAsBytes(bytes);
        }
        return file.path;
      } catch (_) {
        return resultUri.toString();
      }
    }

    return null;
  }

  /// Parses and validates JSON string backup into a [BackupWrapper] (§7.2).
  static BackupWrapper parseAndValidateBackup(String jsonContent) {
    final decodedWrapper = BackupSerializer.decode(jsonContent);
    validateBackup(decodedWrapper);
    return decodedWrapper;
  }

  /// Prompts user to pick a JSON backup file via FilePicker and parses/validates it (§7.2).
  ///
  /// On Android, uses ACTION_OPEN_DOCUMENT internally.
  /// Returns validated [BackupWrapper], or null if cancelled by user.
  Future<BackupWrapper?> pickAndValidateBackup() async {
    final result = await FilePickerPlatform.instance.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result.isEmpty) {
      return null;
    }

    final file = result.single;
    final path = file.path;
    if (path == null || path.isEmpty) {
      throw const FormatException('Could not determine selected backup file path');
    }

    final content = await File(path).readAsString();
    return parseAndValidateBackup(content);
  }

  /// Transactional replace-all restore into database (§7.2, Addendum G, FIX-ID-BACKUP-1).
  ///
  /// Wraps the entire import in a single db.transaction() (replace-all).
  /// On ANY failure — including duplicate displayId, transactionId or paymentId —
  /// rolls back the full import, leaving existing data untouched,
  /// and surfaces a clear error message identifying the offending ID.
  Future<void> restoreBackup(BackupWrapper wrapper) async {
    // 1. Pre-validate duplicate IDs
    validateBackup(wrapper);

    // 2. Prepare SQLite rows
    final customerMaps = wrapper.customers.map((c) => {
      'id': c.id,
      'displayId': c.displayId,
      'name': c.name,
      'phone': c.phone.isNotEmpty ? c.phone : null,
      'address': c.address,
      'createdAt': c.createdAt,
    }).toList();

    final recordMaps = <Map<String, dynamic>>[];
    final itemMaps = <Map<String, dynamic>>[];
    final paymentMaps = <Map<String, dynamic>>[];

    for (final r in wrapper.records) {
      recordMaps.add({
        'id': r.id,
        'transactionId': r.transactionId,
        'type': r.type.toUpperCase(),
        'customerId': r.customerId,
        'customerName': r.customerName,
        'startDate': r.startDate,
        'endDate': r.endDate != null && r.endDate!.trim().isNotEmpty ? r.endDate : null,
        'principalAmount': r.principalAmount,
        'interestRate': r.interestRate,
        'status': r.status.toUpperCase(),
        'settledDate': r.settledDate,
        'calculatedInterest': r.calculatedInterest,
        'linkedRecordId': r.linkedRecordId,
      });

      for (final item in r.items) {
        itemMaps.add({
          'id': item.id,
          'recordId': r.id,
          'name': item.name,
          'itemCategory': item.itemCategory,
          'description': item.description,
          'weight': item.weight,
          'purity': item.purity,
          'rate': item.rate,
          'itemValue': item.itemValue,
          'lendPercentage': item.lendPercentage,
          'lendableAmount': item.lendableAmount,
        });
      }

      for (final p in r.payments) {
        paymentMaps.add({
          'id': p.id,
          'recordId': r.id,
          'amount': p.amount,
          'date': p.date,
          'notes': p.notes,
          'interestPaid': p.interestPaid,
          'principalPaid': p.principalPaid,
          'paymentId': p.paymentId.isNotEmpty ? p.paymentId : null,
        });
      }
    }

    final retiredMaps = wrapper.retiredIds.map((ret) => {
      'kind': ret.kind,
      'displayId': ret.displayId,
      'retiredAt': ret.retiredAt,
    }).toList();

    // 3. Atomically restore into database (replace-all inside single transaction)
    await _dbHelper.restoreBackupTransactionally(
      customers: customerMaps,
      records: recordMaps,
      ledgerItems: itemMaps,
      payments: paymentMaps,
      retiredIds: retiredMaps,
    );

    // 4. Refresh reactive streams across UI
    await _customerRepository.refresh();
    await _recordRepository.refresh();
  }
}
