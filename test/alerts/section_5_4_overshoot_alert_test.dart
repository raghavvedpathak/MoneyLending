import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/calculations/calculations.dart';
import 'package:money_lending/core/notifications/overdue_notification_service.dart';
import 'package:money_lending/core/ui/formatters/currency_formatter.dart';
import 'package:money_lending/domain/domain.dart';

void main() {
  group('Section 5.4 Principal + Interest Overshoot Alert [FIX-FEAT-OVERSHOOT-1]', () {
    final today = DateTime(2026, 9, 23);
    final rates = [
      ItemRate(
        id: 'r-gold',
        itemCategory: 'GOLD_22K',
        ratePerUnit: 6000.0,
        effectiveDate: today,
        updatedAt: today,
      ),
    ];

    test('1. Overshoot calculation strictly uses snapshotted itemValue, NEVER live market rate', () {
      // Loan of 10,000 at 2% monthly rate, 1 month old.
      // Projected due in 2 months (3 months total) = 10,000 + 600 = 10,600.
      // Item has 1g gold (live market value = 6,000).
      // If live rate were used, 10,600 >= 6,000 would trigger.
      // But snapshot at lending was set to 15,000!
      // 10,600 < 15,000 -> Overshoot MUST NOT trigger.
      final rec = LedgerRecord(
        id: 'rec-snap',
        transactionId: 'TRAN092601',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 8, 23),
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-1',
            recordId: 'rec-snap',
            name: 'Gold Ring',
            itemCategory: 'GOLD_22K',
            weight: 1.0, // Live value is only 6,000
            purity: 100.0,
            itemValue: 15000.0, // Snapshotted value at lending
          ),
        ],
      );

      final risks = computeRecordRisks(records: [rec], rates: rates, today: today);
      expect(risks.length, 1);
      final risk = risks.first;
      expect(risk.currentCollateralValue, 6000.0);
      expect(risk.collateralDrop, isTrue, reason: 'Live collateral (6,000) <= totalDue (10,200)');
      expect(risk.itemValueAtLending, 15000.0);
      expect(risk.projectedOutstanding, 10600.0);
      expect(risk.overshoot, isFalse, reason: '10,600 projected outstanding < 15,000 snapshotted value');
    });

    test('2. Exact boundary condition: projectedOutstanding >= itemValueAtLending triggers overshoot', () {
      // 10,000 principal at 2% for 2 months to projection date (Nov 23):
      // Start date: 2026-09-23. Projection date: 2026-11-23 (+2 months).
      // Accrued interest in 2 months = 400 -> projectedDue = 10,400.
      // itemValueAtLending exactly equals 10,400.
      // Condition >= must evaluate to true.
      final recExact = LedgerRecord(
        id: 'rec-exact',
        transactionId: 'TRAN092602',
        type: RecordType.GIVEN,
        customerId: 'c-2',
        startDate: DateTime(2026, 9, 23),
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-exact',
            recordId: 'rec-exact',
            name: 'Gold Bar',
            itemCategory: 'GOLD_22K',
            weight: 5.0, // live collateral = 30,000 (safe)
            purity: 100.0,
            itemValue: 10400.0, // exact boundary
          ),
        ],
      );

      final risks = computeRecordRisks(records: [recExact], rates: rates, today: today);
      final risk = risks.first;
      expect(risk.projectedOutstanding, 10400.0);
      expect(risk.itemValueAtLending, 10400.0);
      expect(risk.overshoot, isTrue);
      expect(risk.collateralDrop, isFalse);
      expect(risk.atRisk, isTrue);
    });

    test('3. SETTLED and TAKEN records are excluded from overshoot check', () {
      final settledRec = LedgerRecord(
        id: 'rec-settled',
        transactionId: 'TRAN092603',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2025, 1, 1),
        principalAmount: 10000.0,
        interestRate: 5.0,
        status: RecordStatus.SETTLED,
        items: const [
          LedgerItem(
            id: 'i-1',
            recordId: 'rec-settled',
            name: 'Item',
            itemCategory: 'GOLD_22K',
            itemValue: 5000.0,
          ),
        ],
      );

      final takenRec = LedgerRecord(
        id: 'rec-taken',
        transactionId: 'TRAN092604',
        type: RecordType.TAKEN,
        customerId: 'c-1',
        startDate: DateTime(2025, 1, 1),
        principalAmount: 10000.0,
        interestRate: 5.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-2',
            recordId: 'rec-taken',
            name: 'Item',
            itemCategory: 'GOLD_22K',
            itemValue: 5000.0,
          ),
        ],
      );

      final risks = computeRecordRisks(
        records: [settledRec, takenRec],
        rates: rates,
        today: today,
      );
      expect(risks, isEmpty);
    });

    test('4. Substantial payments prevent false overshoot flagging via calculateRecordFinancials', () {
      // 10,000 principal at 5% started 10 months ago (projected interest in 2 mos = 12 * 500 = 6,000 -> 16,000)
      // itemValueAtLending = 12,000.
      // But customer has paid 8,000 on record.payments!
      final recWithPayments = LedgerRecord(
        id: 'rec-paid',
        transactionId: 'TRAN092605',
        type: RecordType.GIVEN,
        customerId: 'c-3',
        startDate: DateTime(2025, 11, 23),
        principalAmount: 10000.0,
        interestRate: 5.0,
        status: RecordStatus.ACTIVE,
        payments: [
          Payment(
            id: 'p-1',
            recordId: 'rec-paid',
            amount: 8000.0,
            date: DateTime(2026, 5, 1),
            interestPaid: 3000.0,
            principalPaid: 5000.0,
          ),
        ],
        items: const [
          LedgerItem(
            id: 'i-paid',
            recordId: 'rec-paid',
            name: 'Gold Ornament',
            itemCategory: 'GOLD_22K',
            weight: 5.0,
            purity: 100.0,
            itemValue: 12000.0,
          ),
        ],
      );

      final risks = computeRecordRisks(records: [recWithPayments], rates: rates, today: today);
      final risk = risks.first;
      // 16,000 total due - 8,000 paid = 8,000 projected outstanding < 12,000 item value
      expect(risk.projectedOutstanding, 8000.0);
      expect(risk.overshoot, isFalse);
    });

    test('5. Daily overshoot background notification dispatches on moneylending_overshoot channel', () async {
      final fakeNotifications = _FakeNotificationsPlugin();
      final fakeRecords = _FakeRecordRepository();
      final fakeRates = _FakeRateRepository();

      // Setup an active record that triggers overshoot
      final overshootingRecord = LedgerRecord(
        id: 'rec-alarm-overshoot',
        transactionId: 'TRAN092699',
        type: RecordType.GIVEN,
        customerId: 'c-alarm-1',
        customerName: 'Robert Smith',
        startDate: DateTime(2025, 1, 1),
        principalAmount: 10000.0,
        interestRate: 5.0, // High interest over 20 months -> overshoots
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-alarm',
            recordId: 'rec-alarm-overshoot',
            name: 'Gold Ring',
            itemCategory: 'GOLD_22K',
            weight: 5.0,
            purity: 100.0,
            itemValue: 12000.0, // 12,000 snapshot << projected ~21,000
          ),
        ],
      );

      fakeRecords.activeRecords = [overshootingRecord];
      fakeRates.rates = rates;

      final service = OverdueNotificationService(
        notificationsPlugin: fakeNotifications,
        recordRepository: fakeRecords,
        itemRateRepository: fakeRates,
      );

      final overshootList = await service.checkAndPostOvershootNotifications(today: today);
      expect(overshootList.length, 1);
      expect(overshootList.first.overshoot, isTrue);

      // Verify that notification was posted on moneylending_overshoot channel with collection_alerts payload
      expect(fakeNotifications.postedNotifications.length, 1);
      final posted = fakeNotifications.postedNotifications.first;
      expect(posted.channelId, OverdueNotificationService.overshootChannelId);
      expect(posted.payload, 'collection_alerts');
      expect(posted.title, contains('Robert Smith'));
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

class _FakeRecordRepository extends Fake implements RecordRepository {
  List<LedgerRecord> activeRecords = [];

  @override
  Future<List<LedgerRecord>> getAllActiveRecordsOnce() async => activeRecords;

  @override
  Future<Map<String, DateTime?>> getActiveRecordLastActivityMap() async => {};
}

class _FakeRateRepository extends Fake implements ItemRateRepository {
  List<ItemRate> rates = [];

  @override
  Future<List<ItemRate>> getCurrentRatesOnce() async => rates;
}
