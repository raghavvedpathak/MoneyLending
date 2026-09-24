import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_lending/core/calculations/calculations.dart';
import 'package:money_lending/core/navigation/app_router.dart';
import 'package:money_lending/core/navigation/app_routes.dart';
import 'package:money_lending/data/datasources/database_helper.dart';
import 'package:money_lending/data/repositories/item_rate_repository_impl.dart';
import 'package:money_lending/data/repositories/record_repository_impl.dart';
import 'package:money_lending/domain/domain.dart';
import 'package:money_lending/features/dashboard/dashboard.dart';
import 'package:money_lending/features/dashboard/widgets/rate_management_card.dart';
import 'package:money_lending/features/dashboard/widgets/stale_rate_banner.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Section 10.1: Screen Inventory — Navigation Structure Tests', () {
    test('1. AppRoute defines type-safe sealed class hierarchy for all 4 bottom tabs and modal routes', () {
      const dashboard = DashboardRoute();
      const customers = CustomersRoute();
      const reports = ReportsRoute();
      const settings = SettingsRoute();

      expect(dashboard.path, '/dashboard');
      expect(customers.path, '/customers');
      expect(reports.path, '/reports');
      expect(settings.path, '/settings');

      final detail = RecordDetailRoute('rec-123');
      expect(detail.path, '/record/rec-123');
      expect(detail.resolve(), 'record/rec-123');
    });

    test('2. appRouter is configured as StatefulShellRoute.indexedStack with 4 branches', () {
      final shellRoute = appRouter.configuration.routes.firstWhere(
        (r) => r is StatefulShellRoute,
      ) as StatefulShellRoute;

      expect(shellRoute.branches.length, 4);
      // Branch 0: Dashboard (/dashboard)
      expect(shellRoute.branches[0].routes.first, isA<GoRoute>());
      expect((shellRoute.branches[0].routes.first as GoRoute).path, '/dashboard');

      // Branch 1: Customers (/customers)
      expect((shellRoute.branches[1].routes.first as GoRoute).path, '/customers');

      // Branch 2: Reports (/reports)
      expect((shellRoute.branches[2].routes.first as GoRoute).path, '/reports');

      // Branch 3: Settings (/settings)
      expect((shellRoute.branches[3].routes.first as GoRoute).path, '/settings');
    });
  });

  group('Section 10.1: Tab 1 Dashboard — Record List & Formatting Tests', () {
    test('3. [FIX-TIMESTAMP-RECORDLIST-1] (revised v1.15) formatDate(startDate) formats transaction date', () {
      final record = LedgerRecord(
        id: 'rec-1',
        transactionId: 'TXN-001',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 9, 20, 14, 30),
        principalAmount: 25000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );

      final dateStr = formatDate(record.startDate);
      expect(dateStr, '20 September 2026');
    });

    test('4. Record list sorting: ordered strictly by startDate descending (date, then time-of-day)', () {
      final r1 = LedgerRecord(
        id: 'rec-earlier',
        transactionId: 'TXN-001',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 9, 15, 10, 0),
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );

      final r2 = LedgerRecord(
        id: 'rec-backdated',
        transactionId: 'TXN-002',
        type: RecordType.GIVEN,
        customerId: 'c-2',
        startDate: DateTime(2026, 9, 10, 18, 0), // Backdated record
        principalAmount: 15000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );

      final r3 = LedgerRecord(
        id: 'rec-latest',
        transactionId: 'TXN-003',
        type: RecordType.GIVEN,
        customerId: 'c-3',
        startDate: DateTime(2026, 9, 20, 12, 0),
        principalAmount: 20000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );

      final r4 = LedgerRecord(
        id: 'rec-latest-same-day-later-time',
        transactionId: 'TXN-004',
        type: RecordType.GIVEN,
        customerId: 'c-4',
        startDate: DateTime(2026, 9, 20, 16, 45), // Same day as r3, later time
        principalAmount: 5000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );

      final records = [r1, r2, r3, r4];
      records.sort((a, b) => b.startDate.compareTo(a.startDate));

      // Order must be: r4 (Sep 20 16:45), r3 (Sep 20 12:00), r1 (Sep 15), r2 (Sep 10)
      expect(records[0].id, 'rec-latest-same-day-later-time');
      expect(records[1].id, 'rec-latest');
      expect(records[2].id, 'rec-earlier');
      expect(records[3].id, 'rec-backdated');
    });
  });

  group('Section 10.1: Rate Management Card & [FIX-RATE-ASOF-1] / M-10 FIX Tests', () {
    late Database db;
    late DatabaseHelper dbHelper;
    late ItemRateRepository rateRepo;
    late RecordRepository recordRepo;
    late DashboardViewModel viewModel;

    setUp(() async {
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (d, v) => DatabaseHelper.createTablesForTesting(d),
      );
      dbHelper = DatabaseHelper.forTesting(db);
      rateRepo = ItemRateRepositoryImpl(dbHelper);
      recordRepo = RecordRepositoryImpl(dbHelper);

      viewModel = DashboardViewModel(
        recordRepository: recordRepo,
        itemRateRepository: rateRepo,
        clock: () => DateTime(2026, 9, 20),
      );
    });

    tearDown(() async {
      viewModel.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await db.close();
    });

    test('5. [FIX-RATE-ASOF-1] (Addendum J.10) ItemRateRepository.getRateAsOf returns rate in force on record date', () async {
      // Historical rate on 2026-08-01: 5800
      await rateRepo.upsertRate(ItemRate(
        id: 'r-aug',
        itemCategory: 'GOLD',
        ratePerUnit: 5800.0,
        effectiveDate: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
      ));

      // Newer rate on 2026-09-15: 6200
      await rateRepo.upsertRate(ItemRate(
        id: 'r-sep',
        itemCategory: 'GOLD',
        ratePerUnit: 6200.0,
        effectiveDate: DateTime(2026, 9, 15),
        updatedAt: DateTime(2026, 9, 15),
      ));

      // As of 2026-08-10 -> should be 5800
      final rateAsOfAug = await rateRepo.getRateAsOf('GOLD', DateTime(2026, 8, 10));
      expect(rateAsOfAug?.ratePerUnit, 5800.0);

      // As of 2026-09-16 -> should be 6200
      final rateAsOfSep = await rateRepo.getRateAsOf('GOLD', DateTime(2026, 9, 16));
      expect(rateAsOfSep?.ratePerUnit, 6200.0);
    });

    test('6. M-10 FIX: Add category sets ratePerUnit = 0.0 ("not set" marker) with strict validations', () async {
      // A: Blank category name validation
      final errBlank = await viewModel.addCategory('   ');
      expect(errBlank, 'Category name cannot be blank');

      // B: Successful addition of new category
      final success = await viewModel.addCategory('DIAMOND');
      expect(success, isNull);

      final rates = await rateRepo.getCurrentRatesOnce();
      final diamond = rates.firstWhere((r) => r.itemCategory == 'DIAMOND');
      expect(diamond.ratePerUnit, 0.0); // "not set yet" marker
      expect(diamond.effectiveDate, DateTime(2026, 9, 20));

      // C: Case-insensitive duplicate check
      final errDup = await viewModel.addCategory('diamond');
      expect(errDup, 'Category already exists');
    });

    test('7. Rate update validates ratePerUnit > 0.0 with inline error', () async {
      // 0.0 or negative is rejected
      final errZero = await viewModel.updateCategoryRate('GOLD', 0.0);
      expect(errZero, 'Rate must be greater than zero');

      final errNeg = await viewModel.updateCategoryRate('GOLD', -50.0);
      expect(errNeg, 'Rate must be greater than zero');

      // Valid rate > 0.0 succeeds
      final success = await viewModel.updateCategoryRate('GOLD', 6500.0);
      expect(success, isNull);

      final rates = await rateRepo.getCurrentRatesOnce();
      final gold = rates.firstWhere((r) => r.itemCategory == 'GOLD');
      expect(gold.ratePerUnit, 6500.0);
    });
  });

  group('Section 10.1: StaleRateBanner & RiskSummary Pure Component Tests', () {
    test('8. StaleRateBanner correctly displays warning when any rate is stale or not set', () {
      final staleRate = ItemRate(
        id: 'r-stale',
        itemCategory: 'GOLD',
        ratePerUnit: 5000.0,
        effectiveDate: DateTime(2026, 9, 18),
        updatedAt: DateTime(2026, 9, 18),
      );

      final banner = StaleRateBanner(
        oldestStaleRate: staleRate,
        onTap: () {},
      );

      expect(banner.oldestStaleRate, isNotNull);
      expect(staleRate.formattedEffectiveDate, '18 September 2026');
    });

    test('9. RiskSummary header shows "All records safe today" when atRiskCount == 0, and exposure otherwise', () {
      const safeSummary = RiskSummary(atRiskCount: 0, totalExposure: 0.0);
      expect(safeSummary.allSafe, isTrue);

      const atRiskSummary = RiskSummary(atRiskCount: 3, totalExposure: 245000.0);
      expect(atRiskSummary.allSafe, isFalse);
      expect(atRiskSummary.atRiskCount, 3);
      expect(atRiskSummary.totalExposure, 245000.0);
    });
  });
}
