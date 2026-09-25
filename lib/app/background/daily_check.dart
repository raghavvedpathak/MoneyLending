import 'dart:async';
import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/calculations/calculation_engine.dart';
import '../../core/calculations/util/date_extensions.dart';
import '../../core/notifications/overdue_notification_service.dart';
import '../../data/datasources/database_helper.dart';
import '../../data/repositories/item_rate_repository_impl.dart';
import '../../data/repositories/record_repository_impl.dart';
import '../../domain/domain.dart';

/// AppDatabase alias for background isolate (§4.3 [FIX-BG-DB-1]).
typedef AppDatabase = DatabaseHelper;

/// Opens dedicated background database connection (§4.3 [FIX-BG-DB-1]).
Future<DatabaseHelper> openBackgroundConnection() => DatabaseHelper.openIsolated();

/// Standard Android initialization settings (§8).
const androidInitSettings = InitializationSettings(
  android: AndroidInitializationSettings('@mipmap/ic_launcher'),
);

/// Channel for 30-day overdue & live collateral breach notifications (§8).
const overdueChannel = AndroidNotificationChannel(
  'moneylending_alerts',
  'Overdue Alerts',
  description: 'Notifications for loans overdue by 30+ days or collateral breaches',
  importance: Importance.defaultImportance,
);

/// Channel for 2-month projected overshoot warnings (§5.4 & §8).
const overshootChannel = AndroidNotificationChannel(
  'moneylending_overshoot',
  'Collection Warnings',
  description: 'High-priority alerts for projected collateral overshoots',
  importance: Importance.high,
);

/// Top-level background isolate entry point for daily overdue & overshoot check (§8, [FIX-ALARM-CALLBACK-1]).
///
/// Mandated by Section 8:
/// - @pragma('vm:entry-point') keeps the callback in release builds (prevents tree-shaking).
/// - DartPluginRegistrant.ensureInitialized() registers plugins in background isolate.
/// - Opens its own connection to moneylending.db via DatabaseHelper.openIsolated().
/// - Reads clock ONCE via DateTime.now().dateOnly ([FIX-CLOCK-1]).
/// - Reschedules tomorrow's 10:00 AM alarm in a finally block so one failed run cannot silently end the schedule.
@pragma('vm:entry-point')
Future<void> dailyOverdueCallback() async {
  DartPluginRegistrant.ensureInitialized(); // REQUIRED: plugins in background isolate
  WidgetsFlutterBinding.ensureInitialized();
  final today = DateTime.now().dateOnly; // the ONLY clock read ([FIX-CLOCK-1])
  DatabaseHelper? db;
  try {
    db = await openBackgroundConnection(); // [FIX-BG-DB-1]: own connection
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(settings: androidInitSettings); // same channels as main()

    final records = await RecordRepositoryImpl(db).getAllActiveRecordsOnce();
    final rates = await ItemRateRepositoryImpl(db).getCurrentRatesOnce();
    await runDailyChecks(
      records: records,
      rates: rates,
      today: today,
      plugin: plugin,
    );
  } catch (e, stack) {
    debugPrint('dailyOverdueCallback failed: $e\n$stack');
  } finally {
    if (db != null) {
      await db.close();
    }
    await scheduleNextTenAm(); // always reschedule, even if the check threw
  }
}

/// Runs the daily calculations and posts notifications if candidates qualify (§8 & §5.4):
/// runDailyChecks = getOverdue + computeCollateralOverdue + mergeOverdueRecords
/// + computeRecordRisks (overshoot), each candidate through shouldNotify() (J.8).
Future<void> runDailyChecks({
  required List<LedgerRecord> records,
  required List<ItemRate> rates,
  required DateTime today,
  required FlutterLocalNotificationsPlugin plugin,
  SharedPreferences? prefs,
}) async {
  if (records.isEmpty) return;

  SharedPreferences? sharedPrefs = prefs;
  if (sharedPrefs == null) {
    try {
      sharedPrefs = await SharedPreferences.getInstance();
    } catch (_) {}
  }

  // 1. Activity-based overdue (>= 30 days gap since last payment or startDate) [FIX-LASTACTIVITY-1]
  final activityOverdue = CalculationEngine.getOverdue(
    records: records,
    today: today,
    thresholdDays: 30,
  );

  // 2. Collateral live-rate overdue ([FIX-OVERDUE-COLLATERAL-1] & [FIX-OVERDUE-RATES-1])
  final collateralOverdue = CalculationEngine.computeCollateralOverdue(
    records: records,
    rates: rates,
    today: today,
  );

  // 3. Merge overdue lists
  final mergedOverdue = CalculationEngine.mergeOverdueRecords(activityOverdue, collateralOverdue);

  // 4. Filter overdue candidates through shouldNotify() ([FIX-NOTIFY-THROTTLE-1] & Addendum J.8)
  final overdueCandidatesToNotify = <OverdueRecord>[];
  for (final item in mergedOverdue) {
    final recId = item.record.id;
    final lastDateStr = sharedPrefs?.getString('notif_overdue_date_$recId');
    final lastReasonsList = sharedPrefs?.getStringList('notif_overdue_reasons_$recId');

    final lastDate = lastDateStr != null ? DateTime.tryParse(lastDateStr) : null;
    final lastReasons = lastReasonsList
        ?.map((s) {
          try {
            return OverdueReason.values.byName(s);
          } catch (_) {
            return null;
          }
        })
        .whereType<OverdueReason>()
        .toSet();

    if (CalculationEngine.shouldNotify(
      lastNotifiedDate: lastDate,
      today: today,
      throttleDays: 7,
      lastReasons: lastReasons,
      currentReasons: item.reasons,
    )) {
      overdueCandidatesToNotify.add(item);
    }
  }

  // Post overdue notifications on channel 'moneylending_alerts'
  if (overdueCandidatesToNotify.isNotEmpty) {
    final distinctCustomers = <String, String>{};
    for (final item in overdueCandidatesToNotify) {
      distinctCustomers[item.record.customerId] = item.record.customerName ?? 'Customer';
    }

    final isGrouped = OverdueNotificationService.shouldGroupNotifications(distinctCustomers.length);

    if (isGrouped) {
      const androidDetails = AndroidNotificationDetails(
        'moneylending_alerts',
        'Overdue Alerts',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );
      const notificationDetails = NotificationDetails(android: androidDetails);

      await plugin.show(
        id: 9999,
        title: '${distinctCustomers.length} Loans Overdue',
        body: 'Tap to review all overdue customer accounts.',
        notificationDetails: notificationDetails,
        payload: 'overdue',
      );
    } else {
      for (final entry in distinctCustomers.entries) {
        final customerId = entry.key;
        final customerName = entry.value;

        final customerRecords = overdueCandidatesToNotify.where((o) => o.record.customerId == customerId).toList();
        final primary = customerRecords.first;

        String reasonText = '';
        if (primary.reasons.contains(OverdueReason.noActivity)) {
          reasonText = '${primary.record.transactionId} inactive for ${primary.daysSinceActivity} days';
        } else if (primary.reasons.contains(OverdueReason.collateralBreachedNow)) {
          reasonText = '${primary.record.transactionId} collateral value dropped below balance';
        } else if (primary.reasons.contains(OverdueReason.collateralProjected2Months)) {
          reasonText = '${primary.record.transactionId} collateral projected breach in 2 months';
        }

        const androidDetails = AndroidNotificationDetails(
          'moneylending_alerts',
          'Overdue Alerts',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        );
        const notificationDetails = NotificationDetails(android: androidDetails);

        await plugin.show(
          id: customerId.hashCode,
          title: 'Overdue Loan: $customerName',
          body: reasonText,
          notificationDetails: notificationDetails,
          payload: 'overdue',
        );
      }
    }

    if (sharedPrefs != null) {
      for (final item in overdueCandidatesToNotify) {
        await sharedPrefs.setString('notif_overdue_date_${item.record.id}', today.toIso8601String());
        await sharedPrefs.setStringList(
          'notif_overdue_reasons_${item.record.id}',
          item.reasons.map((r) => r.name).toList(),
        );
      }
    }
  }

  // 5. Overshoot notifications on the same records snapshot (§5.4 & §8)
  final risks = CalculationEngine.computeRecordRisks(
    records: records,
    rates: rates,
    today: today,
  );

  final overshootRisks = risks.where((r) => r.overshoot).toList();
  if (overshootRisks.isNotEmpty) {
    final overshootCandidates = <RecordRisk>[];
    for (final r in overshootRisks) {
      final recId = r.record.id;
      final lastDateStr = sharedPrefs?.getString('notif_overshoot_date_$recId');
      final lastDate = lastDateStr != null ? DateTime.tryParse(lastDateStr) : null;

      if (CalculationEngine.shouldNotify(
        lastNotifiedDate: lastDate,
        today: today,
        throttleDays: 7,
      )) {
        overshootCandidates.add(r);
      }
    }

    if (overshootCandidates.isNotEmpty) {
      final customerRisks = <String, List<RecordRisk>>{};
      for (final r in overshootCandidates) {
        customerRisks.putIfAbsent(r.record.customerId, () => []).add(r);
      }

      for (final entry in customerRisks.entries) {
        final customerId = entry.key;
        final custRisks = entry.value;
        final primary = custRisks.first;
        final customerName = primary.record.customerName ?? 'Customer';

        const androidDetails = AndroidNotificationDetails(
          'moneylending_overshoot',
          'Collection Warnings',
          importance: Importance.high,
          priority: Priority.high,
        );
        const notificationDetails = NotificationDetails(android: androidDetails);

        final String body;
        if (custRisks.length == 1) {
          body = '${primary.record.transactionId} projected balance will exceed collateral in 2 months';
        } else {
          body = '${custRisks.length} loans projected to exceed collateral in 2 months';
        }

        await plugin.show(
          id: (customerId.hashCode ^ 0x0FE5) & 0x7FFFFFFF,
          title: 'Collection Warning: $customerName',
          body: body,
          notificationDetails: notificationDetails,
          payload: 'collection_alerts',
        );
      }

      if (sharedPrefs != null) {
        for (final r in overshootCandidates) {
          await sharedPrefs.setString('notif_overshoot_date_${r.record.id}', today.toIso8601String());
        }
      }
    }
  }
}

/// Schedules or reschedules the next 10:00 AM alarm (§8, [FIX-ALARM-CALLBACK-1]).
Future<void> scheduleNextTenAm([DateTime? now]) async {
  if (!Platform.isAndroid) return;
  final scheduler = OverdueNotificationService();
  final target10Am = OverdueNotificationService.calculateNext10Am(now);
  final canExact = await scheduler.canScheduleExactAlarms();

  await AndroidAlarmManager.oneShotAt(
    target10Am,
    OverdueNotificationService.alarmId,
    dailyOverdueCallback,
    exact: canExact,
    wakeup: true,
    rescheduleOnReboot: true,
  );
}
