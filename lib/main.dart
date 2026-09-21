import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/di/injection.dart';
import 'core/navigation/app_router.dart';
import 'core/notifications/overdue_notification_service.dart';
import 'core/ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite FFI for Windows desktop
  if (Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize central dependency injection container
  await initServiceLocator();

  // Initialize notification channels and reschedule daily 10:00 AM alarm (§8)
  final notificationService = sl<OverdueNotificationService>();
  await notificationService.initialize();
  await notificationService.scheduleDailyAlarm();

  // Listen to notification deep-links
  OverdueNotificationService.deepLinkStream.listen((payload) {
    if (payload == 'overdue') {
      appRouter.go('/overdue');
    }
  });

  runApp(const MoneyLendingApp());
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
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
    );
  }
}
