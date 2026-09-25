import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:money_lending/core/di/injection.dart';
import 'package:money_lending/domain/domain.dart';
import 'package:money_lending/features/dashboard/screens/dashboard_screen.dart';

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
  Stream<List<LedgerRecord>> getActiveGivenRecords() async* {
    yield records.where((r) => r.isGiven).toList();
    yield* _recordsCtrl.stream;
  }

  @override
  Stream<List<RecordPaymentTotal>> getTotalPaidFlow() async* {
    yield totals;
    yield* _totalsCtrl.stream;
  }

  @override
  Stream<List<RecordPaymentTotal>> watchTotalPaidFlow() async* {
    yield totals;
    yield* _totalsCtrl.stream;
  }

  @override
  Stream<List<LedgerRecord>> getAllActiveRecords() async* {
    yield records;
    yield* _recordsCtrl.stream;
  }

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
  Future<void> updateRecord(LedgerRecord record) async {
    final idx = records.indexWhere((r) => r.id == record.id);
    if (idx != -1) {
      records[idx] = record;
      emit();
    }
  }

  @override
  Future<void> deleteRecord(String id) async {
    records.removeWhere((r) => r.id == id);
    emit();
  }

  @override
  Future<void> forceDeleteRecord(String id) async {
    records.removeWhere((r) => r.id == id);
    emit();
  }

  @override
  Future<void> settleRecord(String id, double calculatedInterest) async {}

  @override
  Future<void> addPayment(Payment payment) async {}

  @override
  Future<void> refresh() async => emit();

  @override
  Future<Map<String, DateTime?>> getActiveRecordLastActivityMap() async => {};

  @override
  Future<List<RecordPaymentTotal>> getTotalPaidByRecordIds(
          List<String> recordIds) async =>
      [];

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
  Stream<List<ItemRate>> watchCurrentRates() async* {
    yield rates;
    yield* _ratesCtrl.stream;
  }

  @override
  Stream<List<ItemRate>> getCurrentRates() async* {
    yield rates;
    yield* _ratesCtrl.stream;
  }

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



class MockSettingsRepository implements SettingsRepository {
  Settings settings = const Settings(
    id: 1,
    name: 'Test Shop',
    phone: '9876543210',
    address: '123 Market St',
    defaultInterestRate: 2.0,
  );

  @override
  Stream<Settings> watchSettings() => Stream.value(settings);

  @override
  Stream<Settings> getSettings() => Stream.value(settings);

  @override
  Future<Settings> getSettingsOnce() async => settings;

  @override
  Future<void> updateSettings(Settings newSettings) async {
    settings = newSettings;
  }
}

class MockCustomerRepository implements CustomerRepository {
  final List<Customer> customers = [];

  @override
  Stream<List<Customer>> getAllCustomers() => Stream.value(customers);

  @override
  Future<List<Customer>> getAllCustomersOnce() async => customers;

  @override
  Stream<Customer?> getCustomerById(String id) => Stream.value(
      customers.where((c) => c.id == id).firstOrNull);

  @override
  Future<Customer> insertCustomer(Customer customer) async {
    customers.add(customer);
    return customer;
  }

  @override
  Future<void> updateCustomer(Customer customer) async {}

  @override
  Future<void> deleteCustomer(String id) async {}

  @override
  Future<void> refresh() async {}
}

void main() {
  late MockRecordRepository mockRecordRepo;
  late MockItemRateRepository mockItemRateRepo;
  late MockSettingsRepository mockSettingsRepo;
  late MockCustomerRepository mockCustomerRepo;

  setUp(() async {
    await sl.reset();

    mockRecordRepo = MockRecordRepository();
    mockItemRateRepo = MockItemRateRepository();
    mockSettingsRepo = MockSettingsRepository();
    mockCustomerRepo = MockCustomerRepository();

    sl.registerSingleton<RecordRepository>(mockRecordRepo);
    sl.registerSingleton<ItemRateRepository>(mockItemRateRepo);
    sl.registerSingleton<SettingsRepository>(mockSettingsRepo);
    sl.registerSingleton<CustomerRepository>(mockCustomerRepo);
  });

  tearDown(() async {
    await sl.reset();
  });

  group('Record List Timestamp Tests ([FIX-TIMESTAMP-RECORDLIST-1] revised v1.15)', () {
    testWidgets(
        'Dashboard record list displays transaction date with formatDate(startDate) — e.g. "23 April 2026"',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 23/04/2026 at 14:30
      final specificStartDate = DateTime(2026, 4, 23, 14, 30);
      final expectedDateString = formatDate(specificStartDate);
      expect(expectedDateString, equals('23 April 2026'));

      final record = LedgerRecord(
        id: 'rec-test-1',
        transactionId: 'TRAN042601',
        type: RecordType.GIVEN,
        customerId: 'cust-1',
        customerName: 'Ramesh Patel',
        startDate: specificStartDate,
        principalAmount: 25000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );

      mockRecordRepo.records = [record];
      mockRecordRepo.totals = [
        const RecordPaymentTotal(
          recordId: 'rec-test-1',
          totalPaid: 0.0,
        ),
      ];

      await tester.pumpWidget(
        const MaterialApp(
          home: DashboardScreen(showRecordList: true),
        ),
      );

      await tester.pumpAndSettle();

      // Verify that the record row displays '23 April 2026'
      expect(find.textContaining('23 April 2026'), findsOneWidget);
      expect(find.text('Ramesh Patel'), findsOneWidget);
      expect(find.text('TRAN-042601'), findsOneWidget);
    });

    testWidgets(
        'Morning date: 05/10/2026 at 09:05 displays formatDate(startDate) as "5 October 2026"',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final morningDate = DateTime(2026, 10, 5, 9, 5);
      final expectedDateString = formatDate(morningDate);
      expect(expectedDateString, equals('5 October 2026'));

      final record = LedgerRecord(
        id: 'rec-test-2',
        transactionId: 'TRAN102602',
        type: RecordType.GIVEN,
        customerId: 'cust-2',
        customerName: 'Suresh Kumar',
        startDate: morningDate,
        principalAmount: 15000.0,
        interestRate: 2.5,
        status: RecordStatus.ACTIVE,
      );

      mockRecordRepo.records = [record];
      mockRecordRepo.totals = [
        const RecordPaymentTotal(
          recordId: 'rec-test-2',
          totalPaid: 0.0,
        ),
      ];

      await tester.pumpWidget(
        const MaterialApp(
          home: DashboardScreen(showRecordList: true),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('5 October 2026'), findsOneWidget);
      expect(find.text('Suresh Kumar'), findsOneWidget);
      expect(find.text('TRAN-102602'), findsOneWidget);
    });
  });
}
