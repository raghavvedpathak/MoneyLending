import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/calculations/util/date_extensions.dart';
import 'package:money_lending/domain/domain.dart';
import 'package:money_lending/features/dashboard/viewmodels/dashboard_viewmodel.dart';

class MockRecordRepository implements RecordRepository {
  final StreamController<List<LedgerRecord>> _recordsCtrl =
      StreamController<List<LedgerRecord>>.broadcast();
  final StreamController<List<RecordPaymentTotal>> _totalsCtrl =
      StreamController<List<RecordPaymentTotal>>.broadcast();

  List<LedgerRecord> records = [];
  List<RecordPaymentTotal> totals = [];

  void emit() {
    _recordsCtrl.add(records);
    _totalsCtrl.add(totals);
  }

  @override
  Stream<List<LedgerRecord>> getActiveGivenRecords() => _recordsCtrl.stream;

  @override
  Stream<List<RecordPaymentTotal>> getTotalPaidFlow() => _totalsCtrl.stream;

  @override
  Stream<List<RecordPaymentTotal>> watchTotalPaidFlow() => _totalsCtrl.stream;

  @override
  Stream<List<LedgerRecord>> getAllActiveRecords() => _recordsCtrl.stream;

  @override
  Future<List<LedgerRecord>> getAllActiveRecordsOnce() async => records;

  @override
  Future<List<LedgerRecord>> getAllRecordsOnce() async => records;

  @override
  Future<LedgerRecord?> getRecordById(String id) async =>
      records.where((r) => r.id == id).firstOrNull;

  @override
  Stream<List<LedgerRecord>> getRecordsByCustomer(String customerId) =>
      _recordsCtrl.stream;

  @override
  Future<LedgerRecord> insertRecord(LedgerRecord record) async {
    records.add(record);
    emit();
    return record;
  }

  @override
  Future<void> updateRecord(LedgerRecord record) async {}

  @override
  Future<void> deleteRecord(String id) async {}

  @override
  Future<void> forceDeleteRecord(String id) async {}

  @override
  Future<void> settleRecord(String id, double calculatedInterest) async {}

  @override
  Future<void> addPayment(Payment payment) async {}

  @override
  Future<void> refresh() async => emit();

  @override
  Future<Map<String, DateTime?>> getActiveRecordLastActivityMap() async => {};

  @override
  Future<List<RecordPaymentTotal>> getTotalPaidByRecordIds(List<String> recordIds) async => [];

  @override
  Future<void> importRecordsTransactionally(List<LedgerRecord> records) async {}

  @override
  Future<void> deletePayment(String paymentId) async {}

  @override
  Future<void> restoreBackupTransactionally({
    required List<Map<String, dynamic>> customers,
    required List<Map<String, dynamic>> records,
    required List<Map<String, dynamic>> ledgerItems,
    required List<Map<String, dynamic>> payments,
    List<Map<String, dynamic>> retiredIds = const [],
    Map<String, dynamic>? settings,
    List<Map<String, dynamic>>? itemRates,
  }) async {}
}

class MockItemRateRepository implements ItemRateRepository {
  final StreamController<List<ItemRate>> _ratesCtrl =
      StreamController<List<ItemRate>>.broadcast();

  List<ItemRate> rates = [];

  void emit() => _ratesCtrl.add(rates);

  @override
  Stream<List<ItemRate>> watchCurrentRates() => _ratesCtrl.stream;

  @override
  Stream<List<ItemRate>> getCurrentRates() => _ratesCtrl.stream;

  @override
  Future<List<ItemRate>> getCurrentRatesOnce() async => rates;

  @override
  Stream<ItemRate?> watchCurrentRate(String category) =>
      _ratesCtrl.stream.map((list) =>
          list.where((r) => r.itemCategory == category).firstOrNull);

  @override
  Stream<ItemRate?> getCurrentRate(String category) =>
      watchCurrentRate(category);

  @override
  Future<ItemRate?> getCurrentRateOnce(String category) async =>
      rates.where((r) => r.itemCategory == category).firstOrNull;

  @override
  Future<ItemRate?> getRateAsOf(String category, DateTime date) async {
    final dateOnly = DateTime(date.year, date.month, date.day);
    final matching = rates.where((r) {
      final rDate = DateTime(r.effectiveDate.year, r.effectiveDate.month, r.effectiveDate.day);
      return r.itemCategory == category &&
          !rDate.isAfter(dateOnly) &&
          r.ratePerUnit > 0;
    }).toList()
      ..sort((a, b) => b.effectiveDate.compareTo(a.effectiveDate));
    return matching.firstOrNull;
  }

  @override
  Stream<List<ItemRate>> watchRatesForDate(DateTime date) => _ratesCtrl.stream;

  @override
  Stream<List<ItemRate>> getRatesForDate(String date) => _ratesCtrl.stream;

  @override
  Future<List<ItemRate>> getRatesForDateOnce(String date) async => rates;

  @override
  Stream<List<ItemRate>> getRatesStream() => _ratesCtrl.stream;

  @override
  Future<void> upsertRate(ItemRate rate) async {
    final idx = rates.indexWhere((r) =>
        r.itemCategory.trim().toUpperCase() ==
        rate.itemCategory.trim().toUpperCase());
    if (idx >= 0) {
      rates[idx] = rate;
    } else {
      rates.add(rate);
    }
    emit();
  }
}

void main() {
  late MockRecordRepository recordRepo;
  late MockItemRateRepository rateRepo;
  late DateTime fixedToday;
  late DashboardViewModel viewModel;

  setUp(() {
    recordRepo = MockRecordRepository();
    rateRepo = MockItemRateRepository();
    fixedToday = DateTime(2026, 9, 21);

    viewModel = DashboardViewModel(
      recordRepository: recordRepo,
      itemRateRepository: rateRepo,
      clock: () => fixedToday,
      debounceDuration: const Duration(milliseconds: 10),
    );
  });

  tearDown(() {
    viewModel.dispose();
  });

  group('DashboardViewModel Rate Management & Validation Tests (§10.1)', () {
    test('addCategory rejects blank name with exact error', () async {
      final error = await viewModel.addCategory('   ');
      expect(error, equals('Category name cannot be blank'));
    });

    test('addCategory rejects duplicate category name case-insensitively', () async {
      rateRepo.rates = [
        ItemRate(
          id: '1',
          itemCategory: 'GOLD',
          ratePerUnit: 6000.0,
          effectiveDate: fixedToday,
          updatedAt: fixedToday,
        ),
      ];

      final error = await viewModel.addCategory('gold');
      expect(error, equals('Category already exists'));

      final error2 = await viewModel.addCategory('  GOLD  ');
      expect(error2, equals('Category already exists'));
    });

    test('addCategory creates category with ratePerUnit = 0.0 marker and today date', () async {
      rateRepo.rates = [];

      final error = await viewModel.addCategory('PLATINUM');
      expect(error, isNull);

      expect(rateRepo.rates.length, equals(1));
      final created = rateRepo.rates.first;
      expect(created.itemCategory, equals('PLATINUM'));
      expect(created.ratePerUnit, equals(0.0)); // [FIX-RATE-USABLE-1]
      expect(created.effectiveDate, equals(fixedToday.dateOnly));
    });

    test('updateCategoryRate rejects zero, negative, or blank rates', () async {
      final errorZero = await viewModel.updateCategoryRate('GOLD', 0.0);
      expect(errorZero, equals('Rate must be greater than zero'));

      final errorNeg = await viewModel.updateCategoryRate('GOLD', -150.0);
      expect(errorNeg, equals('Rate must be greater than zero'));
    });

    test('updateCategoryRate successfully upserts positive rate for today', () async {
      final error = await viewModel.updateCategoryRate('GOLD', 6500.0);
      expect(error, isNull);

      expect(rateRepo.rates.length, equals(1));
      final updated = rateRepo.rates.first;
      expect(updated.itemCategory, equals('GOLD'));
      expect(updated.ratePerUnit, equals(6500.0));
      expect(updated.effectiveDate, equals(fixedToday.dateOnly));
    });
  });

  group('DashboardViewModel Stale-Rate Banner & Risk Summary Tests (§10.1)', () {
    test('Stale-rate banner detects older rates and 0.0 "not set" rates', () async {
      final staleDate = DateTime(2026, 9, 15);
      rateRepo.rates = [
        ItemRate(
          id: '1',
          itemCategory: 'GOLD',
          ratePerUnit: 6000.0,
          effectiveDate: staleDate,
          updatedAt: staleDate,
        ),
        ItemRate(
          id: '2',
          itemCategory: 'SILVER',
          ratePerUnit: 75.0,
          effectiveDate: fixedToday,
          updatedAt: fixedToday,
        ),
      ];

      recordRepo.records = [];
      recordRepo.totals = [];

      recordRepo.emit();
      rateRepo.emit();

      await Future.delayed(const Duration(milliseconds: 50));

      expect(viewModel.currentOldestStaleRate, isNotNull);
      expect(viewModel.currentOldestStaleRate!.itemCategory, equals('GOLD'));
      expect(viewModel.currentOldestStaleRate!.effectiveDate, equals(staleDate));
    });

    test('Stale-rate banner is null when all rates are updated today with positive values', () async {
      rateRepo.rates = [
        ItemRate(
          id: '1',
          itemCategory: 'GOLD',
          ratePerUnit: 6000.0,
          effectiveDate: fixedToday,
          updatedAt: fixedToday,
        ),
        ItemRate(
          id: '2',
          itemCategory: 'SILVER',
          ratePerUnit: 75.0,
          effectiveDate: fixedToday,
          updatedAt: fixedToday,
        ),
      ];

      recordRepo.records = [];
      recordRepo.totals = [];

      recordRepo.emit();
      rateRepo.emit();

      await Future.delayed(const Duration(milliseconds: 50));

      expect(viewModel.currentOldestStaleRate, isNull);
    });

    test('Risk Summary header derives at-risk count and total exposure correctly', () async {
      // 1 at-risk record (underwater collateral)
      final record = LedgerRecord(
        id: 'rec-1',
        transactionId: 'TXN-001',
        type: RecordType.GIVEN,
        customerId: 'cust-1',
        customerName: 'Alice',
        startDate: fixedToday.subtract(const Duration(days: 30)),
        principalAmount: 100000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: [
          const LedgerItem(
            id: 'item-1',
            recordId: 'rec-1',
            name: 'Gold Ring',
            itemCategory: 'GOLD',
            weight: 10.0,
            purity: 100.0, // 10g fine weight
            rate: 6000.0,
            itemValue: 60000.0,
          ),
        ],
      );

      // Gold rate dropped to 5000/g -> Collateral value = 50,000, Total due > 100,000 -> AT RISK!
      rateRepo.rates = [
        ItemRate(
          id: '1',
          itemCategory: 'GOLD',
          ratePerUnit: 5000.0,
          effectiveDate: fixedToday,
          updatedAt: fixedToday,
        ),
      ];

      recordRepo.records = [record];
      recordRepo.totals = [const RecordPaymentTotal(recordId: 'rec-1', totalPaid: 0.0)];

      recordRepo.emit();
      rateRepo.emit();

      await Future.delayed(const Duration(milliseconds: 50));

      final summary = viewModel.currentRiskSummary;
      expect(summary.allSafe, isFalse);
      expect(summary.atRiskCount, equals(1));
      expect(summary.totalExposure, greaterThan(100000.0));
    });

    test('Risk Summary header reports allSafe when no records are at risk', () async {
      recordRepo.records = [];
      recordRepo.totals = [];
      rateRepo.rates = [];

      recordRepo.emit();
      rateRepo.emit();

      await Future.delayed(const Duration(milliseconds: 50));

      final summary = viewModel.currentRiskSummary;
      expect(summary.allSafe, isTrue);
      expect(summary.atRiskCount, equals(0));
      expect(summary.totalExposure, equals(0.0));
    });
  });
}
