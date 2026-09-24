import '../../../domain/models/ledger_record.dart';
import '../../../domain/models/payment.dart';
import '../../../domain/models/record_payment_total.dart';

/// Domain Contract for Record and Payment Repository.
///
/// Mandated by Architecture Spec §2.1 & §4.3 [FIX-ARCH-DB-1]:
/// Pure Dart interface defined in :core:domain (zero Flutter/Drift imports).
/// - Single repository for records and child payments.
/// - Concurrency-guarded deletion and TOCTOU protection [FIX-DEV-TOCTOU-1].
/// - Unconditional deletion hook [FIX-FORCEDELETE-1].
/// - Settled record and payment insertion hooks (BLK-5, BLK-6).
/// - Batch total paid and activity queries [FIX-REPO-MISSING-1].
abstract class RecordRepository {
  /// Reactive stream of records belonging to a customer
  Stream<List<LedgerRecord>> getRecordsByCustomer(String customerId);

  /// Reactive stream of active GIVEN records
  Stream<List<LedgerRecord>> getActiveGivenRecords();

  /// Reactive stream of all active records for Dashboard/ViewModel observers
  Stream<List<LedgerRecord>> getAllActiveRecords();

  /// One-shot fetch for Worker/background processes (NOT a Stream)
  Future<List<LedgerRecord>> getAllActiveRecordsOnce();

  /// One-shot fetch for all records (both active and settled) for export and reporting
  Future<List<LedgerRecord>> getAllRecordsOnce();

  /// Refreshes all record and payment reactive streams
  Future<void> refresh();

  /// One-shot fetch for stale-record checks (NOT a Stream)
  Future<LedgerRecord?> getRecordById(String id);

  /// Inserts a new record with atomic transactionId generation
  Future<LedgerRecord> insertRecord(LedgerRecord record);

  /// Updates an existing record
  Future<void> updateRecord(LedgerRecord record);

  /// Deletes a record, throwing RecordLinkedTakenException if linked TAKEN records exist [FIX-DEV-TOCTOU-1]
  Future<void> deleteRecord(String id);

  /// Force deletes a record unconditionally, skipping the COUNT check [FIX-FORCEDELETE-1]
  Future<void> forceDeleteRecord(String id);

  /// Settles a record, writing status=SETTLED, settledDate, and calculatedInterest (BLK-6 FIX)
  Future<void> settleRecord(String id, double calculatedInterest);

  /// Inserts a payment child row inside a transaction (BLK-5 FIX)
  Future<void> addPayment(Payment payment);

  /// Deletes a payment child row (§4.4 [FIX-PAYMENT-DELETE-1])
  Future<void> deletePayment(String paymentId);

  /// Reactive stream of total paid amounts aggregated per record
  Stream<List<RecordPaymentTotal>> getTotalPaidFlow();

  /// Reactive stream of total paid amounts aggregated per record (§5.4 [FIX-FEAT-OVERSHOOT-1]).
  Stream<List<RecordPaymentTotal>> watchTotalPaidFlow();

  /// Map of recordId -> latest payment date (date component only), or null if no payments [FIX-REPO-MISSING-1]
  Future<Map<String, DateTime?>> getActiveRecordLastActivityMap();

  /// Batch query chunked in batches of 500 for SQLite limits [FIX-REPO-MISSING-1]
  Future<List<RecordPaymentTotal>> getTotalPaidByRecordIds(List<String> recordIds);

  /// Transactional all-or-nothing import (§4.4):
  /// When importing a JSON backup of N records, wrap the entire import in a single transaction.
  /// If any record conflicts, roll back the entire import and throw an error.
  Future<void> importRecordsTransactionally(List<LedgerRecord> records);

  /// Transactional all-or-nothing backup restore [FIX-ID-BACKUP-1] & [FIX-BACKUPCONFIG-1]:
  /// Restoring a JSON backup is a replace-all, not a merge. Inside a single db.transaction(),
  /// delete payments, ledger_items, records, customers and retired_ids explicitly
  /// (child tables first — do not lean on the FK cascade), then insert everything from the backup.
  /// settings and item_rates are part of the 1.4 backup ([FIX-BACKUPCONFIG-1]): when the file
  /// carries them they are replaced too (settings row overwritten, item_rates deleted and re-inserted);
  /// when it does not (1.1–1.3), they are left untouched.
  /// If anything fails, roll the whole transaction back so the device keeps its previous
  /// data, and surface a clear error.
  Future<void> restoreBackupTransactionally({
    required List<Map<String, dynamic>> customers,
    required List<Map<String, dynamic>> records,
    required List<Map<String, dynamic>> ledgerItems,
    required List<Map<String, dynamic>> payments,
    List<Map<String, dynamic>> retiredIds = const [],
    Map<String, dynamic>? settings,
    List<Map<String, dynamic>>? itemRates,
  });
}
