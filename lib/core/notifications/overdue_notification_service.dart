import 'dart:async';
import 'dart:io';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/background/daily_check.dart';
import '../../domain/domain.dart';
import '../calculations/calculation_engine.dart';
import '../calculations/util/date_extensions.dart';
import '../di/injection.dart';

export '../../app/background/daily_check.dart'
    show dailyOverdueCallback, runDailyChecks, scheduleNextTenAm;

/// Top-level background isolate entry point for AndroidAlarmManager (§8, §4.3 [FIX-BG-DB-1], & [FIX-ALARM-CALLBACK-1]).
///
/// Mandated by AndroidAlarmManager, [FIX-BG-DB-1], & [FIX-ALARM-CALLBACK-1]:
/// Delegates to [dailyOverdueCallback] in `lib/app/background/daily_check.dart`.
@pragma('vm:entry-point')
void overdueAlarmCallback() async {
  await dailyOverdueCallback();
}

/// Service managing daily 10:00 AM alarms, notification channels, and overdue checks (§8).
class OverdueNotificationService {
  static const int alarmId = 1001;
  static const String alertsChannelId = 'moneylending_alerts';
  static const String alertsChannelName = 'Overdue Alerts';
  static const String overshootChannelId = 'moneylending_overshoot';
  static const String overshootChannelName = 'Collection Warnings';

  static const MethodChannel _exactAlarmChannel =
      MethodChannel('com.moneylending/exact_alarm');

  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  final RecordRepository? _recordRepository;
  final ItemRateRepository? _itemRateRepository;

  // Stream controller for notification deep links
  static final StreamController<String> _deepLinkController =
      StreamController<String>.broadcast();
  static Stream<String> get deepLinkStream => _deepLinkController.stream;

  OverdueNotificationService({
    FlutterLocalNotificationsPlugin? notificationsPlugin,
    this._recordRepository,
    this._itemRateRepository,
  })  : _notificationsPlugin =
            notificationsPlugin ?? FlutterLocalNotificationsPlugin();

  RecordRepository get _records =>
      _recordRepository ?? sl<RecordRepository>();
  ItemRateRepository get _rates =>
      _itemRateRepository ?? sl<ItemRateRepository>();

  /// Calculates the next 10:00 AM target DateTime from [now] (§8).
  static DateTime calculateNext10Am([DateTime? now]) {
    final current = now ?? DateTime.now();
    final today10Am = DateTime(current.year, current.month, current.day, 10, 0, 0);
    if (current.isBefore(today10Am)) {
      return today10Am;
    } else {
      return DateTime(current.year, current.month, current.day + 1, 10, 0, 0);
    }
  }

  /// Evaluates whether notifications should be grouped into a single summary.
  static bool shouldGroupNotifications(int distinctCustomerCount) {
    return distinctCustomerCount > 3;
  }

  /// Initializes notification channels and plugin listeners during app startup (§8).
  Future<void> initialize() async {
    if (!Platform.isAndroid) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _deepLinkController.add(payload);
        }
      },
    );

    // Create notification channels idempotently on Android (API 26+)
    if (Platform.isAndroid) {
      const overdueChannel = AndroidNotificationChannel(
        alertsChannelId,
        alertsChannelName,
        description: 'Notifications for loans overdue by 30+ days or collateral breaches',
        importance: Importance.defaultImportance,
      );

      const overshootChannel = AndroidNotificationChannel(
        overshootChannelId,
        overshootChannelName,
        description: 'High-priority alerts for projected collateral overshoots',
        importance: Importance.high,
      );

      final androidImpl = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(overdueChannel);
      await androidImpl?.createNotificationChannel(overshootChannel);
    }
  }

  /// Requests Android 13+ (API 33) POST_NOTIFICATIONS permission.
  Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    final androidImpl = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await androidImpl?.requestNotificationsPermission();
    return granted ?? true;
  }

  /// Checks whether exact alarms can be scheduled on Android 12+ (API 31+).
  Future<bool> canScheduleExactAlarms() async {
    if (!Platform.isAndroid) return true;
    try {
      final canExact = await _exactAlarmChannel.invokeMethod<bool>('canScheduleExactAlarms');
      return canExact ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Prompts the user and opens the exact alarm system settings screen.
  Future<void> openExactAlarmSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _exactAlarmChannel.invokeMethod('openExactAlarmSettings');
    } catch (_) {}
  }

  /// Checks permissions and prompts user on first launch or missing exact alarm permission (§8).
  Future<void> checkPermissionsAndPrompt(BuildContext context) async {
    if (!Platform.isAndroid) return;

    await requestNotificationPermission();

    final canExact = await canScheduleExactAlarms();
    if (!canExact && context.mounted) {
      // One-time prompt explaining exact alarm requirement before settings redirect
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Exact Daily Reminders'),
          content: const Text(
            'MoneyLending schedules exact 10:00 AM daily alerts for overdue loans. '
            'To ensure reminders fire precisely on time without drifting, please allow '
            'exact alarms in system settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );

      if (proceed == true) {
        await openExactAlarmSettings();
      }
    }
  }

  /// Static convenience helper to schedule or reschedule the next 10:00 AM alarm (§8, [FIX-ALARM-CALLBACK-1]).
  static Future<void> scheduleNextTenAm([DateTime? now]) async {
    final scheduler = OverdueNotificationService();
    await scheduler.scheduleDailyAlarm(nowOverride: now);
  }

  /// Schedules or reschedules the exact daily 10:00 AM alarm (§8).
  ///
  /// Re-verified unconditionally on every app launch for idempotency.
  Future<void> scheduleDailyAlarm({DateTime? nowOverride}) async {
    if (!Platform.isAndroid) return;

    final target10Am = calculateNext10Am(nowOverride);
    final canExact = await canScheduleExactAlarms();

    await AndroidAlarmManager.oneShotAt(
      target10Am,
      alarmId,
      overdueAlarmCallback,
      exact: canExact,
      wakeup: true,
      rescheduleOnReboot: true,
    );
  }

  /// Evaluates overdue status and posts local notifications.
  ///
  /// Combines:
  /// 1. Activity-based overdue (>= 30 days gap since last payment or startDate) [FIX-LASTACTIVITY-1]
  /// 2. Collateral live-rate overdue ([FIX-OVERDUE-COLLATERAL-1] & [FIX-OVERDUE-RATES-1])
  /// 3. Filters candidates via shouldNotify() ([FIX-NOTIFY-THROTTLE-1] & Addendum J.8)
  Future<List<OverdueRecord>> checkAndPostOverdueNotifications({
    DateTime? todayOverride,
    List<LedgerRecord>? recordsOverride,
    List<ItemRate>? ratesOverride,
    SharedPreferences? prefsOverride,
  }) async {
    final today = (todayOverride ?? DateTime.now()).dateOnly;

    final records = recordsOverride ?? await _records.getAllActiveRecordsOnce();
    if (records.isEmpty) return [];

    final rates = ratesOverride ?? await _rates.getCurrentRatesOnce();

    // [FIX-LASTACTIVITY-1] Derives last activity in memory from full records (no extra query)
    final activityOverdue = CalculationEngine.getOverdue(
      records: records,
      today: today,
      thresholdDays: 30,
    );

    final collateralOverdue = CalculationEngine.computeCollateralOverdue(
      records: records,
      rates: rates,
      today: today,
    );

    final merged = CalculationEngine.mergeOverdueRecords(activityOverdue, collateralOverdue);

    // [FIX-NOTIFY-THROTTLE-1] (v1.16 & Addendum J.8):
    // The same record re-notifies only when its set of reasons changes or 7 days have passed.
    SharedPreferences? prefs = prefsOverride;
    if (prefs == null) {
      try {
        prefs = await SharedPreferences.getInstance();
      } catch (_) {}
    }

    final candidatesToNotify = <OverdueRecord>[];
    for (final item in merged) {
      final recId = item.record.id;
      final lastDateStr = prefs?.getString('notif_overdue_date_$recId');
      final lastReasonsList = prefs?.getStringList('notif_overdue_reasons_$recId');

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
        candidatesToNotify.add(item);
      }
    }

    if (candidatesToNotify.isNotEmpty) {
      // Count distinct customer IDs among candidates to notify
      final distinctCustomers = <String, String>{};
      for (final item in candidatesToNotify) {
        distinctCustomers[item.record.customerId] = item.record.customerName ?? 'Customer';
      }

      final isGrouped = shouldGroupNotifications(distinctCustomers.length);

      if (isGrouped) {
        // Grouped summary notification
        const androidDetails = AndroidNotificationDetails(
          alertsChannelId,
          alertsChannelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        );
        const notificationDetails = NotificationDetails(android: androidDetails);

        await _notificationsPlugin.show(
          id: 9999,
          title: '${distinctCustomers.length} Loans Overdue',
          body: 'Tap to review all overdue customer accounts.',
          notificationDetails: notificationDetails,
          payload: 'overdue',
        );
      } else {
        // Individual notification per customer
        for (final entry in distinctCustomers.entries) {
          final customerId = entry.key;
          final customerName = entry.value;

          // Customer's highest-risk or most inactive record
          final customerRecords = candidatesToNotify.where((o) => o.record.customerId == customerId).toList();
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
            alertsChannelId,
            alertsChannelName,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          );
          const notificationDetails = NotificationDetails(android: androidDetails);

          await _notificationsPlugin.show(
            id: customerId.hashCode,
            title: 'Overdue Loan: $customerName',
            body: reasonText,
            notificationDetails: notificationDetails,
            payload: 'overdue',
          );
        }
      }

      // Record throttle timestamp and reasons for all notified records
      if (prefs != null) {
        for (final item in candidatesToNotify) {
          await prefs.setString('notif_overdue_date_${item.record.id}', today.toIso8601String());
          await prefs.setStringList(
            'notif_overdue_reasons_${item.record.id}',
            item.reasons.map((r) => r.name).toList(),
          );
        }
      }
    }

    // Daily push notification for overshoot (§5.4 & §8 Step 11):
    // After the existing 30-day overdue check, call computeRecordRisks() (same function,
    // same getAllActiveRecordsOnce() snapshot) and notify for every risk with overshoot == true.
    // Post a separate flutter_local_notifications notification per affected customer on channel
    // moneylending_overshoot. Tapping navigates to Dashboard Collection Alert Section.
    await checkAndPostOvershootNotifications(
      records: records,
      rates: rates,
      today: today,
      prefsOverride: prefs,
    );

    return merged;
  }

  /// Evaluates 2-month projected overshoot and posts high-priority notifications
  /// on channel [overshootChannelId] ('moneylending_overshoot') (§5.4 & [FIX-FEAT-OVERSHOOT-1]).
  Future<List<RecordRisk>> checkAndPostOvershootNotifications({
    List<LedgerRecord>? records,
    List<ItemRate>? rates,
    DateTime? today,
    SharedPreferences? prefsOverride,
  }) async {
    final effectiveToday = (today ?? DateTime.now()).dateOnly;
    final effectiveRecords = records ?? await _records.getAllActiveRecordsOnce();
    if (effectiveRecords.isEmpty) return [];

    final effectiveRates = rates ?? await _rates.getCurrentRatesOnce();

    final risks = CalculationEngine.computeRecordRisks(
      records: effectiveRecords,
      rates: effectiveRates,
      today: effectiveToday,
    );

    final overshootRisks = risks.where((r) => r.overshoot).toList();
    if (overshootRisks.isEmpty) return [];

    SharedPreferences? prefs = prefsOverride;
    if (prefs == null) {
      try {
        prefs = await SharedPreferences.getInstance();
      } catch (_) {}
    }

    // Filter candidates through shouldNotify() with 7-day throttle
    final candidatesToNotify = <RecordRisk>[];
    for (final r in overshootRisks) {
      final recId = r.record.id;
      final lastDateStr = prefs?.getString('notif_overshoot_date_$recId');
      final lastDate = lastDateStr != null ? DateTime.tryParse(lastDateStr) : null;

      if (CalculationEngine.shouldNotify(
        lastNotifiedDate: lastDate,
        today: effectiveToday,
        throttleDays: 7,
      )) {
        candidatesToNotify.add(r);
      }
    }

    if (candidatesToNotify.isNotEmpty) {
      // Group by customer ID so each affected customer receives a distinct notification
      final customerRisks = <String, List<RecordRisk>>{};
      for (final r in candidatesToNotify) {
        customerRisks.putIfAbsent(r.record.customerId, () => []).add(r);
      }

      for (final entry in customerRisks.entries) {
        final customerId = entry.key;
        final custRisks = entry.value;
        final primary = custRisks.first;
        final customerName = primary.record.customerName ?? 'Customer';

        const androidDetails = AndroidNotificationDetails(
          overshootChannelId,
          overshootChannelName,
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

        await _notificationsPlugin.show(
          id: (customerId.hashCode ^ 0x0FE5) & 0x7FFFFFFF,
          title: 'Collection Warning: $customerName',
          body: body,
          notificationDetails: notificationDetails,
          payload: 'collection_alerts',
        );
      }

      if (prefs != null) {
        for (final r in candidatesToNotify) {
          await prefs.setString('notif_overshoot_date_${r.record.id}', effectiveToday.toIso8601String());
        }
      }
    }

    return overshootRisks;
  }
}
