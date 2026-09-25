import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/app/background/daily_check.dart';
import 'package:money_lending/core/calculations/calculation_engine.dart';
import 'package:money_lending/core/data/dao/record_activity_row.dart';
import 'package:money_lending/core/notifications/overdue_notification_service.dart';
import 'package:money_lending/data/datasources/daos/record_dao.dart';
import 'package:money_lending/data/datasources/database_helper.dart';
import 'package:money_lending/data/models/customer_entity.dart';
import 'package:money_lending/data/models/payment_entity.dart';
import 'package:money_lending/data/models/record_entity.dart';
import 'package:money_lending/data/repositories/record_repository_impl.dart';
import 'package:money_lending/domain/domain.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('8. Overdue Notifications — Unit & Calculation Strategy Tests', () {
    test('1. Activity-based overdue boundary check: gap >= thresholdDays (30)', () {
      final today = DateTime(2026, 6, 1);

      // Record 1: Exactly 30 days inactive (2026-05-02 to 2026-06-01) -> OVERDUE (>= 30)
      final rec30Days = LedgerRecord(
        id: 'rec-30',
        transactionId: 'TXN-30',
        type: RecordType.GIVEN,
        customerId: 'cust-1',
        startDate: DateTime(2026, 5, 2),
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );

      // Record 2: 29 days inactive (2026-05-03 to 2026-06-01) -> NOT overdue (< 30)
      final rec29Days = LedgerRecord(
        id: 'rec-29',
        transactionId: 'TXN-29',
        type: RecordType.GIVEN,
        customerId: 'cust-2',
        startDate: DateTime(2026, 5, 3),
        principalAmount: 5000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );

      // Record 3: 31 days inactive (2026-05-01 to 2026-06-01) -> OVERDUE (>= 30)
      final rec31Days = LedgerRecord(
        id: 'rec-31',
        transactionId: 'TXN-31',
        type: RecordType.GIVEN,
        customerId: 'cust-3',
        startDate: DateTime(2026, 5, 1),
        principalAmount: 8000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );

      final latestPayments = <String, DateTime?>{
        'rec-30': null,
        'rec-29': null,
        'rec-31': null,
      };

      final overdueList = CalculationEngine.getOverdue(
        records: [rec30Days, rec29Days, rec31Days],
        latestPaymentDates: latestPayments,
        today: today,
        thresholdDays: 30,
      );

      expect(overdueList.length, 2);
      expect(overdueList.any((o) => o.record.id == 'rec-30'), isTrue);
      expect(overdueList.any((o) => o.record.id == 'rec-31'), isTrue);
      expect(overdueList.any((o) => o.record.id == 'rec-29'), isFalse);
    });

    test('2. Activity-based overdue uses latest payment date when present', () {
      final today = DateTime(2026, 6, 1);

      // Started 100 days ago, but had a payment 10 days ago -> NOT overdue
      final recWithRecentPayment = LedgerRecord(
        id: 'rec-pay-recent',
        transactionId: 'TXN-PAY-RECENT',
        type: RecordType.GIVEN,
        customerId: 'cust-1',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 20000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );

      // Started 100 days ago, had a payment 35 days ago -> OVERDUE
      final recWithOldPayment = LedgerRecord(
        id: 'rec-pay-old',
        transactionId: 'TXN-PAY-OLD',
        type: RecordType.GIVEN,
        customerId: 'cust-2',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 15000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );

      final latestPayments = <String, DateTime?>{
        'rec-pay-recent': DateTime(2026, 5, 22), // 10 days ago
        'rec-pay-old': DateTime(2026, 4, 27), // 35 days ago
      };

      final overdueList = CalculationEngine.getOverdue(
        records: [recWithRecentPayment, recWithOldPayment],
        latestPaymentDates: latestPayments,
        today: today,
        thresholdDays: 30,
      );

      expect(overdueList.length, 1);
      expect(overdueList.first.record.id, 'rec-pay-old');
      expect(overdueList.first.daysSinceActivity, 35);
    });

    test('3. [FIX-OVERDUE-RATES-1] computeCollateralOverdue skips records with no items or unusable rates', () {
      final today = DateTime(2026, 6, 1);

      final liveRates = [
        ItemRate(
          id: 'rate-1',
          itemCategory: 'GOLD',
          ratePerUnit: 5000.0,
          effectiveDate: today,
          updatedAt: today,
        ),
        ItemRate(
          id: 'rate-2',
          itemCategory: 'SILVER',
          ratePerUnit: 0.0, // 0.0 means "not set yet" -> UNUSABLE
          effectiveDate: today,
          updatedAt: today,
        ),
      ];

      // A: Record with no items -> must be skipped (§8 [FIX-OVERDUE-RATES-1])
      final recNoItems = LedgerRecord(
        id: 'rec-no-items',
        transactionId: 'TXN-NO-ITEMS',
        type: RecordType.GIVEN,
        customerId: 'cust-1',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [],
      );

      // B: Record with item whose category has NO rate entered -> must be skipped
      final recMissingRate = LedgerRecord(
        id: 'rec-missing-rate',
        transactionId: 'TXN-MISSING-RATE',
        type: RecordType.GIVEN,
        customerId: 'cust-2',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'item-plat',
            recordId: 'rec-missing-rate',
            name: 'Platinum Ring',
            itemCategory: 'PLATINUM', // No rate in liveRates
            weight: 10.0,
            purity: 100.0,
            rate: 4000.0,
            itemValue: 40000.0,
            lendPercentage: 80.0,
            lendableAmount: 32000.0,
          ),
        ],
      );

      // C: Record with item whose category rate is 0.0 -> must be skipped
      final recZeroRate = LedgerRecord(
        id: 'rec-zero-rate',
        transactionId: 'TXN-ZERO-RATE',
        type: RecordType.GIVEN,
        customerId: 'cust-3',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'item-silv',
            recordId: 'rec-zero-rate',
            name: 'Silver Bar',
            itemCategory: 'SILVER', // rate is 0.0
            weight: 500.0,
            purity: 100.0,
            rate: 80.0,
            itemValue: 40000.0,
            lendPercentage: 80.0,
            lendableAmount: 32000.0,
          ),
        ],
      );

      // D: Record with usable rate where collateral has dropped -> MUST BE FLAGGED
      final recUsableBreached = LedgerRecord(
        id: 'rec-usable',
        transactionId: 'TXN-USABLE',
        type: RecordType.GIVEN,
        customerId: 'cust-4',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 50000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'item-gold',
            recordId: 'rec-usable',
            name: 'Gold Ring',
            itemCategory: 'GOLD',
            weight: 5.0, // 5g * 5000/g = 25,000 collateral. Amount owed is >50,000 -> breached!
            purity: 100.0,
            rate: 6000.0,
            itemValue: 30000.0,
            lendPercentage: 80.0,
            lendableAmount: 24000.0,
          ),
        ],
      );

      final result = CalculationEngine.computeCollateralOverdue(
        records: [recNoItems, recMissingRate, recZeroRate, recUsableBreached],
        rates: liveRates,
        today: today,
      );

      expect(result.length, 1);
      expect(result.first.record.id, 'rec-usable');
      expect(result.first.reasons.contains(OverdueReason.collateralBreachedNow), isTrue);
    });

    test('4. [FIX-OVERDUE-COLLATERAL-1] Evaluates both GIVEN and TAKEN records', () {
      final today = DateTime(2026, 6, 1);

      final liveRates = [
        ItemRate(
          id: 'rate-1',
          itemCategory: 'GOLD',
          ratePerUnit: 3000.0,
          effectiveDate: today,
          updatedAt: today,
        ),
      ];

      final recGiven = LedgerRecord(
        id: 'rec-g',
        transactionId: 'TXN-G',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 30000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-1',
            recordId: 'rec-g',
            name: 'Gold',
            itemCategory: 'GOLD',
            weight: 5.0, // 15,000 value vs 30,000 principal -> breached!
            purity: 100.0,
            rate: 5000.0,
            itemValue: 25000.0,
            lendPercentage: 80.0,
            lendableAmount: 20000.0,
          ),
        ],
      );

      final recTaken = LedgerRecord(
        id: 'rec-t',
        transactionId: 'TXN-T',
        type: RecordType.TAKEN,
        customerId: 'c-2',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 30000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-2',
            recordId: 'rec-t',
            name: 'Gold',
            itemCategory: 'GOLD',
            weight: 5.0, // 15,000 value vs 30,000 principal -> breached!
            purity: 100.0,
            rate: 5000.0,
            itemValue: 25000.0,
            lendPercentage: 80.0,
            lendableAmount: 20000.0,
          ),
        ],
      );

      final result = CalculationEngine.computeCollateralOverdue(
        records: [recGiven, recTaken],
        rates: liveRates,
        today: today,
      );

      expect(result.length, 2);
      expect(result.any((o) => o.record.id == 'rec-g'), isTrue);
      expect(result.any((o) => o.record.id == 'rec-t'), isTrue);
    });

    test('5. mergeOverdueRecords unifies activity-based and collateral-based reasons', () {
      final rec = LedgerRecord(
        id: 'rec-1',
        transactionId: 'TXN-001',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );

      final activityOverdue = [
        OverdueRecord(
          record: rec,
          reasons: const {OverdueReason.noActivity},
          daysSinceActivity: 45,
          lastActivityDate: DateTime(2026, 4, 15),
        ),
      ];

      final collateralOverdue = [
        OverdueRecord(
          record: rec,
          reasons: const {OverdueReason.collateralBreachedNow},
          currentCollateralValue: 8000.0,
          currentObligation: 10500.0,
        ),
      ];

      final merged = CalculationEngine.mergeOverdueRecords(activityOverdue, collateralOverdue);
      expect(merged.length, 1);
      final item = merged.first;
      expect(item.reasons.contains(OverdueReason.noActivity), isTrue);
      expect(item.reasons.contains(OverdueReason.collateralBreachedNow), isTrue);
      expect(item.daysSinceActivity, 45);
      expect(item.currentCollateralValue, 8000.0);
    });

    test('6. OverdueNotificationService calculateNext10Am schedules for today if before 10 AM, or tomorrow if past', () {
      // Scenario A: 8:30 AM on 2026-09-20 -> target is 2026-09-20 10:00:00
      final morning = DateTime(2026, 9, 20, 8, 30, 0);
      final targetA = OverdueNotificationService.calculateNext10Am(morning);
      expect(targetA, DateTime(2026, 9, 20, 10, 0, 0));

      // Scenario B: 10:00:00 AM exact on 2026-09-20 -> target is next day 2026-09-21 10:00:00
      final exactly10 = DateTime(2026, 9, 20, 10, 0, 0);
      final targetB = OverdueNotificationService.calculateNext10Am(exactly10);
      expect(targetB, DateTime(2026, 9, 21, 10, 0, 0));

      // Scenario C: 3:45 PM on 2026-09-20 -> target is 2026-09-21 10:00:00
      final afternoon = DateTime(2026, 9, 20, 15, 45, 0);
      final targetC = OverdueNotificationService.calculateNext10Am(afternoon);
      expect(targetC, DateTime(2026, 9, 21, 10, 0, 0));
    });

    test('7. OverdueNotificationService shouldGroupNotifications branches at > 3 distinct customers', () {
      expect(OverdueNotificationService.shouldGroupNotifications(1), isFalse);
      expect(OverdueNotificationService.shouldGroupNotifications(2), isFalse);
      expect(OverdueNotificationService.shouldGroupNotifications(3), isFalse);
      expect(OverdueNotificationService.shouldGroupNotifications(4), isTrue);
      expect(OverdueNotificationService.shouldGroupNotifications(10), isTrue);
    });
  });

  group('8. Data Layer & SQLite DAO Projection Tests', () {
    late Database db;
    late DatabaseHelper dbHelper;
    late RecordDao recordDao;
    late RecordRepositoryImpl recordRepo;

    setUp(() async {
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (d, v) => DatabaseHelper.createTablesForTesting(d),
      );
      dbHelper = DatabaseHelper.forTesting(db);
      recordDao = RecordDao(db);
      recordRepo = RecordRepositoryImpl(dbHelper);

      // Insert customer
      await db.insert('customers', CustomerEntity(
        id: 'c-100',
        displayId: 'CUST-100',
        name: 'Jane Doe',
        phone: '9876543210',
        createdAt: '2026-01-01',
      ).toMap());
    });

    tearDown(() async {
      await db.close();
    });

    test('8. RecordDao getActiveRecordLastActivityDates uses single JOIN and aggregates MAX(p.date)', () async {
      // Insert 2 active records and 1 settled record
      await db.insert('records', RecordEntity(
        id: 'rec-act-1',
        transactionId: 'TXN-ACT-1',
        type: 'GIVEN',
        customerId: 'c-100',
        startDate: '2026-01-01T10:00:00',
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      ).toMap());

      await db.insert('records', RecordEntity(
        id: 'rec-act-2',
        transactionId: 'TXN-ACT-2',
        type: 'GIVEN',
        customerId: 'c-100',
        startDate: '2026-01-01T10:00:00',
        principalAmount: 20000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      ).toMap());

      await db.insert('records', RecordEntity(
        id: 'rec-settled',
        transactionId: 'TXN-SETTLED',
        type: 'GIVEN',
        customerId: 'c-100',
        startDate: '2026-01-01T10:00:00',
        principalAmount: 5000.0,
        interestRate: 2.0,
        status: 'SETTLED',
      ).toMap());

      // Payments for rec-act-1 (two payments: latest is 2026-03-15)
      await db.insert('payments', PaymentEntity(
        id: 'pay-1',
        recordId: 'rec-act-1',
        amount: 500.0,
        date: '2026-02-15T14:00:00',
        interestPaid: 500.0,
        principalPaid: 0.0,
      ).toMap());

      await db.insert('payments', PaymentEntity(
        id: 'pay-2',
        recordId: 'rec-act-1',
        amount: 500.0,
        date: '2026-03-15T16:30:00',
        interestPaid: 500.0,
        principalPaid: 0.0,
      ).toMap());

      // Query via RecordDao
      final rows = await recordDao.getActiveRecordLastActivityDates();

      // Only active records should be present
      expect(rows.length, 2);

      final row1 = rows.firstWhere((r) => r.recordId == 'rec-act-1');
      expect(row1.lastPaymentDate, '2026-03-15T16:30:00');

      final row2 = rows.firstWhere((r) => r.recordId == 'rec-act-2');
      expect(row2.lastPaymentDate, isNull);

      // Verify RecordRepository.getActiveRecordLastActivityMap converts to dateOnly
      final activityMap = await recordRepo.getActiveRecordLastActivityMap();
      expect(activityMap['rec-act-1'], DateTime(2026, 3, 15));
      expect(activityMap['rec-act-2'], isNull);
      expect(activityMap.containsKey('rec-settled'), isFalse);
    });

    test('9. RecordActivityRow fromMap maps snake_case and camelCase column aliases', () {
      final snakeMap = {'record_id': 'r-1', 'last_payment_date': '2026-04-20T10:00:00'};
      final rowSnake = RecordActivityRow.fromMap(snakeMap);
      expect(rowSnake.recordId, 'r-1');
      expect(rowSnake.lastPaymentDate, '2026-04-20T10:00:00');

      final camelMap = {'recordId': 'r-2', 'lastPaymentDate': null};
      final rowCamel = RecordActivityRow.fromMap(camelMap);
      expect(rowCamel.recordId, 'r-2');
      expect(rowCamel.lastPaymentDate, isNull);
    });

    test('10. [FIX-NOTIFY-THROTTLE-1] (Addendum J.8) shouldNotify throttling: 7-day wait vs immediate trigger on reason change', () {
      final baseDate = DateTime(2026, 9, 1);

      // Scenario A: Never notified before -> should notify immediately
      expect(
        CalculationEngine.shouldNotify(
          lastNotifiedDate: null,
          today: baseDate,
          throttleDays: 7,
        ),
        isTrue,
      );

      // Scenario B: Same reasons, 3 days elapsed (< 7) -> throttled (false)
      final day3 = DateTime(2026, 9, 4);
      expect(
        CalculationEngine.shouldNotify(
          lastNotifiedDate: baseDate,
          today: day3,
          throttleDays: 7,
          lastReasons: const {OverdueReason.noActivity},
          currentReasons: const {OverdueReason.noActivity},
        ),
        isFalse,
      );

      // Scenario C: Same reasons, 7 days elapsed (>= 7) -> allowed (true)
      final day7 = DateTime(2026, 9, 8);
      expect(
        CalculationEngine.shouldNotify(
          lastNotifiedDate: baseDate,
          today: day7,
          throttleDays: 7,
          lastReasons: const {OverdueReason.noActivity},
          currentReasons: const {OverdueReason.noActivity},
        ),
        isTrue,
      );

      // Scenario D: Reasons changed, only 1 day elapsed -> MUST re-notify immediately
      final day1 = DateTime(2026, 9, 2);
      expect(
        CalculationEngine.shouldNotify(
          lastNotifiedDate: baseDate,
          today: day1,
          throttleDays: 7,
          lastReasons: const {OverdueReason.noActivity},
          currentReasons: const {OverdueReason.noActivity, OverdueReason.collateralBreachedNow},
        ),
        isTrue,
      );
    });

    test('11. Section 8 Notification channels and daily_check exports verification', () {
      // Channel 1: Overdue Alerts (moneylending_alerts, Importance.defaultImportance)
      expect(overdueChannel.id, 'moneylending_alerts');
      expect(overdueChannel.name, 'Overdue Alerts');
      expect(overdueChannel.importance, Importance.defaultImportance);

      // Channel 2: Collection Warnings (moneylending_overshoot, Importance.high)
      expect(overshootChannel.id, 'moneylending_overshoot');
      expect(overshootChannel.name, 'Collection Warnings');
      expect(overshootChannel.importance, Importance.high);
    });

    test('12. runDailyChecks processes records and respects SharedPreferences throttling', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime(2026, 9, 20);

      final rec = LedgerRecord(
        id: 'rec-throttle-1',
        transactionId: 'TXN-THROTTLE-1',
        type: RecordType.GIVEN,
        customerId: 'cust-throttle',
        customerName: 'Alice',
        startDate: DateTime(2026, 8, 1), // 50 days ago -> overdue
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );

      final plugin = _FakeNotificationsPlugin();

      // First run: should execute, post notification on moneylending_alerts and record throttle date
      await runDailyChecks(
        records: [rec],
        rates: [],
        today: today,
        plugin: plugin,
        prefs: prefs,
      );

      expect(plugin.postedNotifications.length, 1);
      expect(plugin.postedNotifications.first.channelId, 'moneylending_alerts');
      expect(plugin.postedNotifications.first.payload, 'overdue');
      expect(prefs.getString('notif_overdue_date_rec-throttle-1'), today.toIso8601String());
      expect(prefs.getStringList('notif_overdue_reasons_rec-throttle-1'), contains('noActivity'));

      // Second run same day: should be throttled (no new notification posted)
      await runDailyChecks(
        records: [rec],
        rates: [],
        today: today,
        plugin: plugin,
        prefs: prefs,
      );
      expect(plugin.postedNotifications.length, 1);
    });

    test('13. runDailyChecks groups notifications when >3 distinct customers and separates overshoot channel', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime(2026, 9, 20);

      // Create 4 distinct overdue customers (>3)
      final records = List.generate(4, (i) {
        return LedgerRecord(
          id: 'rec-overdue-$i',
          transactionId: 'TXN-00$i',
          type: RecordType.GIVEN,
          customerId: 'cust-00$i',
          customerName: 'Customer $i',
          startDate: DateTime(2026, 8, 1), // 50 days ago -> overdue
          principalAmount: 10000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
        );
      });

      final plugin = _FakeNotificationsPlugin();

      await runDailyChecks(
        records: records,
        rates: [],
        today: today,
        plugin: plugin,
        prefs: prefs,
      );

      // Distinct customers = 4 (> 3) -> should post 1 grouped summary notification (id: 9999)
      final overdueNotifs = plugin.postedNotifications.where((n) => n.channelId == 'moneylending_alerts').toList();
      expect(overdueNotifs.length, 1);
      expect(overdueNotifs.first.id, 9999);
      expect(overdueNotifs.first.title, '4 Loans Overdue');
    });
  });
}

class _PostedNotification {
  final int id;
  final String? title;
  final String? body;
  final String? payload;
  final String channelId;

  _PostedNotification({
    required this.id,
    this.title,
    this.body,
    this.payload,
    required this.channelId,
  });
}

class _FakeNotificationsPlugin extends Fake implements FlutterLocalNotificationsPlugin {
  final List<_PostedNotification> postedNotifications = [];

  @override
  Future<void> show({
    int id = 0,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    final channelId = notificationDetails?.android?.channelId ?? '';
    postedNotifications.add(_PostedNotification(
      id: id,
      title: title,
      body: body,
      payload: payload,
      channelId: channelId,
    ));
  }
}
