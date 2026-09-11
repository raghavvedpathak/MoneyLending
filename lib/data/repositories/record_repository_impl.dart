import 'dart:async';
import '../../core/utils/app_date_formatter.dart';
import '../../domain/models/ledger_item.dart';
import '../../domain/models/ledger_record.dart';
import '../../domain/models/payment.dart';
import '../../domain/models/record_payment_total.dart';
import '../../domain/models/record_status.dart';
import '../../domain/models/record_type.dart';
import '../../domain/repositories/record_repository.dart';
import '../datasources/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/ledger_item_entity.dart';
import '../models/payment_entity.dart';
import '../models/record_entity.dart';

/// Concrete Data Layer implementation of RecordRepository.
///
/// Mandated by Data Spec §4.3:
/// Implements all record lifecycle methods, payments, and activity queries.
class RecordRepositoryImpl implements RecordRepository {
  final DatabaseHelper _dbHelper;
  late final StreamController<List<LedgerRecord>> _recordsStreamController =
      StreamController<List<LedgerRecord>>.broadcast(onListen: _refreshStreams);
  late final StreamController<List<RecordPaymentTotal>> _totalPaidStreamController =
      StreamController<List<RecordPaymentTotal>>.broadcast(onListen: _refreshStreams);

  RecordRepositoryImpl([DatabaseHelper? dbHelper])
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  Future<void> _refreshStreams() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'records',
      where: 'status = ?',
      whereArgs: [RecordStatus.ACTIVE.name],
      orderBy: 'startDate DESC',
    );
    final summaryRecords = maps.map((m) => toSummaryRecord(RecordEntity.fromMap(m))).toList();
    _recordsStreamController.add(summaryRecords);
    final totals = await _fetchTotalPaid();
    _totalPaidStreamController.add(totals);
  }

  Future<List<RecordPaymentTotal>> _fetchTotalPaid() async {
    final recordDao = await _dbHelper.recordDao;
    final projections = await recordDao.getTotalPaid();
    return projections.map((p) => RecordPaymentTotal(
      recordId: p.recordId,
      totalPaid: p.totalPaid,
    )).toList();
  }

  /// [FIX-PERF-EAGERLOAD-1] DASHBOARD PERFORMANCE — MANDATORY:
  /// Maps a RecordEntity to LedgerRecord with items = emptyList(), payments = emptyList().
  /// Lightweight mapping without loading child rows, used for Dashboard list and Collection Alert.
  LedgerRecord toSummaryRecord(RecordEntity entity) {
    return LedgerRecord(
      id: entity.id,
      transactionId: entity.transactionId,
      type: RecordType.fromString(entity.type) ?? RecordType.GIVEN,
      customerId: entity.customerId,
      customerName: entity.customerName,
      startDate: AppDateFormatter.parseIso(entity.startDate) ?? DateTime.now(),
      endDate: entity.endDate != null ? AppDateFormatter.parseIso(entity.endDate) : null,
      principalAmount: entity.principalAmount,
      interestRate: entity.interestRate,
      status: RecordStatus.fromString(entity.status) ?? RecordStatus.ACTIVE,
      settledDate: entity.settledDate != null ? AppDateFormatter.parseIso(entity.settledDate) : null,
      calculatedInterest: entity.calculatedInterest,
      linkedRecordId: entity.linkedRecordId,
      items: const [],
      payments: const [],
    );
  }

  /// [FIX-PERF-EAGERLOAD-1] Eager-loads all items and payments for details and calculations.
  LedgerRecord toFullRecord(
    RecordEntity entity,
    List<LedgerItemEntity> items,
    List<PaymentEntity> payments,
  ) {
    return LedgerRecord(
      id: entity.id,
      transactionId: entity.transactionId,
      type: RecordType.fromString(entity.type) ?? RecordType.GIVEN,
      customerId: entity.customerId,
      customerName: entity.customerName,
      startDate: AppDateFormatter.parseIso(entity.startDate) ?? DateTime.now(),
      endDate: entity.endDate != null ? AppDateFormatter.parseIso(entity.endDate) : null,
      principalAmount: entity.principalAmount,
      interestRate: entity.interestRate,
      status: RecordStatus.fromString(entity.status) ?? RecordStatus.ACTIVE,
      settledDate: entity.settledDate != null ? AppDateFormatter.parseIso(entity.settledDate) : null,
      calculatedInterest: entity.calculatedInterest,
      linkedRecordId: entity.linkedRecordId,
      items: items.map((i) => LedgerItem(
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
      )).toList(),
      payments: payments.map((p) => Payment(
        id: p.id,
        recordId: p.recordId,
        amount: p.amount,
        date: p.parsedDateTime,
        notes: p.notes,
        interestPaid: p.interestPaid,
        principalPaid: p.principalPaid,
      )).toList(),
    );
  }

  Future<LedgerRecord> _fetchFullRecord(RecordEntity entity) async {
    final itemEntities = await _dbHelper.getLedgerItemsByRecord(entity.id);
    final paymentEntities = await _dbHelper.getPaymentsByRecord(entity.id);
    return toFullRecord(entity, itemEntities, paymentEntities);
  }

  RecordEntity _toEntity(LedgerRecord domain) {
    return RecordEntity(
      id: domain.id,
      transactionId: domain.transactionId,
      type: domain.type.name,
      customerId: domain.customerId,
      customerName: domain.customerName,
      startDate: AppDateFormatter.toIsoDateTime(domain.startDate),
      endDate: domain.endDate != null ? AppDateFormatter.toIsoDate(domain.endDate!) : null,
      principalAmount: domain.principalAmount,
      interestRate: domain.interestRate,
      status: domain.status.name,
      settledDate: domain.settledDate != null ? AppDateFormatter.toIsoDate(domain.settledDate!) : null,
      calculatedInterest: domain.calculatedInterest,
      linkedRecordId: domain.linkedRecordId,
    );
  }

  @override
  Stream<List<LedgerRecord>> getRecordsByCustomer(String customerId) async* {
    final entities = await _dbHelper.getRecordsByCustomer(customerId);
    final records = await Future.wait(entities.map(_fetchFullRecord));
    yield records;
  }

  @override
  Stream<List<LedgerRecord>> getActiveGivenRecords() async* {
    final entities = await _dbHelper.getRecordsByType(RecordType.GIVEN.name);
    final records = entities
        .where((e) => e.status == RecordStatus.ACTIVE.name)
        .map(toSummaryRecord)
        .toList();
    yield records;
  }

  @override
  Stream<List<LedgerRecord>> getAllActiveRecords() {
    _refreshStreams();
    return _recordsStreamController.stream;
  }

  @override
  Future<List<LedgerRecord>> getAllActiveRecordsOnce() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'records',
      where: 'status = ?',
      whereArgs: [RecordStatus.ACTIVE.name],
      orderBy: 'startDate DESC',
    );
    final entities = maps.map((m) => RecordEntity.fromMap(m)).toList();
    return await Future.wait(entities.map(_fetchFullRecord));
  }

  @override
  Future<LedgerRecord?> getRecordById(String id) async {
    final entity = await _dbHelper.getRecordById(id);
    if (entity == null) return null;
    return await _fetchFullRecord(entity);
  }

  @override
  Future<LedgerRecord> insertRecord(LedgerRecord record) async {
    final entity = _toEntity(record);
    final itemEntities = record.items.map((item) => LedgerItemEntity(
      id: item.id,
      recordId: entity.id,
      name: item.name,
      itemCategory: item.itemCategory,
      description: item.description,
      weight: item.weight,
      purity: item.purity,
      rate: item.rate,
      itemValue: item.itemValue,
      lendPercentage: item.lendPercentage,
      lendableAmount: item.lendableAmount,
    )).toList();

    final paymentEntities = record.payments.map((p) => PaymentEntity(
      id: p.id,
      recordId: entity.id,
      amount: p.amount,
      date: AppDateFormatter.toIsoDateTime(p.date),
      notes: p.notes,
      interestPaid: p.interestPaid,
      principalPaid: p.principalPaid,
    )).toList();

    // Multi-table write inside a single atomic SQLite transaction (§4.4)
    final inserted = await _dbHelper.insertRecordWithDetails(
      record: entity,
      items: itemEntities,
      payments: paymentEntities,
    );

    await _refreshStreams();
    return await _fetchFullRecord(inserted);
  }

  @override
  Future<void> updateRecord(LedgerRecord record) async {
    final db = await _dbHelper.database;
    final entity = _toEntity(record);
    await db.update('records', entity.toMap(), where: 'id = ?', whereArgs: [entity.id]);
    await _refreshStreams();
  }

  @override
  Future<void> deleteRecord(String id) async {
    await _dbHelper.deleteRecord(id);
    await _refreshStreams();
  }

  @override
  Future<void> forceDeleteRecord(String id) async {
    await _dbHelper.forceDeleteRecord(id);
    await _refreshStreams();
  }

  @override
  Future<void> settleRecord(String id, double calculatedInterest) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.update(
        'records',
        {
          'status': RecordStatus.SETTLED.name,
          'settledDate': AppDateFormatter.toIsoDate(DateTime.now()),
          'calculatedInterest': calculatedInterest,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    await _refreshStreams();
  }

  @override
  Future<void> addPayment(Payment payment) async {
    final entity = PaymentEntity(
      id: payment.id,
      recordId: payment.recordId,
      amount: payment.amount,
      date: AppDateFormatter.toIsoDateTime(payment.date),
      notes: payment.notes,
      interestPaid: payment.interestPaid,
      principalPaid: payment.principalPaid,
    );
    await _dbHelper.insertPayment(entity);
    await _refreshStreams();
  }

  @override
  Stream<List<RecordPaymentTotal>> getTotalPaidFlow() {
    _refreshStreams();
    return _totalPaidStreamController.stream;
  }

  @override
  Future<Map<String, DateTime?>> getActiveRecordLastActivityMap() async {
    final db = await _dbHelper.database;
    final results = await db.rawQuery('''
      SELECT r.id as recordId, MAX(p.date) as lastPaymentDate
      FROM records r
      LEFT JOIN payments p ON r.id = p.recordId
      WHERE r.status = ?
      GROUP BY r.id
    ''', [RecordStatus.ACTIVE.name]);

    final Map<String, DateTime?> activityMap = {};
    for (final row in results) {
      final recordId = row['recordId'] as String;
      final rawDate = row['lastPaymentDate'] as String?;
      if (rawDate != null && rawDate.isNotEmpty) {
        // Dual format parser handling ISO datetime and legacy date-only
        final parsed = DateTime.tryParse(rawDate);
        if (parsed != null) {
          activityMap[recordId] = DateTime(parsed.year, parsed.month, parsed.day);
        } else {
          activityMap[recordId] = null;
        }
      } else {
        activityMap[recordId] = null;
      }
    }
    return activityMap;
  }

  @override
  Future<List<RecordPaymentTotal>> getTotalPaidByRecordIds(List<String> recordIds) async {
    if (recordIds.isEmpty) return [];
    final recordDao = await _dbHelper.recordDao;
    final List<RecordPaymentTotal> totals = [];

    // Chunk callers in batches of 500 (SQLite 999 bind-var limit) [FIX-REPO-MISSING-1]
    const chunkSize = 500;
    for (var i = 0; i < recordIds.length; i += chunkSize) {
      final chunk = recordIds.sublist(
        i,
        i + chunkSize > recordIds.length ? recordIds.length : i + chunkSize,
      );
      final projections = await recordDao.getTotalPaidByRecordIds(chunk);

      for (final p in projections) {
        totals.add(RecordPaymentTotal(
          recordId: p.recordId,
          totalPaid: p.totalPaid,
        ));
      }
    }

    return totals;
  }

  @override
  Future<void> importRecordsTransactionally(List<LedgerRecord> records) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      for (final r in records) {
        final entity = _toEntity(r);
        await txn.insert('records', entity.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);

        for (final item in r.items) {
          final itemEntity = LedgerItemEntity(
            id: item.id,
            recordId: r.id,
            name: item.name,
            itemCategory: item.itemCategory,
            description: item.description,
            weight: item.weight,
            purity: item.purity,
            rate: item.rate,
            itemValue: item.itemValue,
            lendPercentage: item.lendPercentage,
            lendableAmount: item.lendableAmount,
          );
          await txn.insert('ledger_items', itemEntity.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);
        }

        for (final payment in r.payments) {
          final paymentEntity = PaymentEntity(
            id: payment.id,
            recordId: r.id,
            amount: payment.amount,
            date: AppDateFormatter.toIsoDateTime(payment.date),
            notes: payment.notes,
            interestPaid: payment.interestPaid,
            principalPaid: payment.principalPaid,
          );
          await txn.insert('payments', paymentEntity.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);
        }
      }
    });
    await _refreshStreams();
  }
}
