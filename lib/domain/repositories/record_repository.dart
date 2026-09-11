import '../models/ledger_record.dart';
import '../models/payment.dart';
import '../models/record_payment_total.dart';

/// Domain Contract for Record and Payment Repository.
///
/// Mandated by Architecture Spec §2.1 & §4.3:
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

  /// Reactive stream of total paid amounts aggregated per record
  Stream<List<RecordPaymentTotal>> getTotalPaidFlow();

  /// Map of recordId -> latest payment date (date component only), or null if no payments [FIX-REPO-MISSING-1]
  Future<Map<String, DateTime?>> getActiveRecordLastActivityMap();

  /// Batch query chunked in batches of 500 for SQLite limits [FIX-REPO-MISSING-1]
  Future<List<RecordPaymentTotal>> getTotalPaidByRecordIds(List<String> recordIds);

  /// Transactional all-or-nothing import (§4.4):
  /// When importing a JSON backup of N records, wrap the entire import in a single transaction.
  /// If any record conflicts, roll back the entire import and throw an error.
  Future<void> importRecordsTransactionally(List<LedgerRecord> records);
}
