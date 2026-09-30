import 'dart:io';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sqflite/sqflite.dart' show databaseFactorySqflitePlugin;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/di/injection.dart';
import 'core/navigation/app_router.dart';
import 'core/navigation/app_routes.dart';
import 'core/notifications/overdue_notification_service.dart';
import 'core/ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite: FFI for Windows desktop, sqflite plugin for Android / iOS
  if (Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  } else {
    databaseFactory = databaseFactorySqflitePlugin;
  }

  // Initialize central dependency injection container
  await initServiceLocator();

  // [FIX-ALARM-HELPERS-1] Initialize AndroidAlarmManager on Android before scheduling alarms
  if (Platform.isAndroid) {
    await AndroidAlarmManager.initialize();
  }

  // Initialize notification channels and reschedule daily 10:00 AM alarm (§8)
  final notificationService = sl<OverdueNotificationService>();
  await notificationService.initialize();
  await notificationService.scheduleDailyAlarm();

  // Listen to notification deep-links (§5.4 & §8 & [FIX-NAV-PUSH-1])
  OverdueNotificationService.deepLinkStream.listen((payload) {
    if (payload == 'overdue' || payload == const OverdueReportRoute().path) {
      appRouter.go(const OverdueReportRoute().path);
    } else if (payload == 'collection_alerts' ||
        payload == 'overshoot' ||
        payload == const DashboardAlertsRoute().path) {
      appRouter.go(const DashboardAlertsRoute().path);
    } else if (payload.isNotEmpty) {
      appRouter.go(payload);
    }
  });

  runApp(const MoneyLendingApp());

  // Cold start notification handling (§8 [FIX-NAV-PUSH-1])
  // For a cold start, read getNotificationAppLaunchDetails() once after runApp() and route the same way
  if (Platform.isAndroid) {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      final launchDetails = await plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        final payload = launchDetails?.notificationResponse?.payload;
        if (payload != null && payload.isNotEmpty) {
          if (payload == 'overdue' || payload == const OverdueReportRoute().path) {
            appRouter.go(const OverdueReportRoute().path);
          } else if (payload == 'collection_alerts' ||
              payload == 'overshoot' ||
              payload == const DashboardAlertsRoute().path) {
            appRouter.go(const DashboardAlertsRoute().path);
          } else {
            appRouter.go(payload);
          }
        }
      }
    } catch (_) {}
  }
}

class MoneyLendingApp extends StatelessWidget {
  final RouterConfig<Object>? routerConfig;

  const MoneyLendingApp({super.key, this.routerConfig});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: routerConfig ?? appRouter,
      title: 'MoneyLending',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
    );
  }
}
