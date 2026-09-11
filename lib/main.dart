import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/di/injection.dart';
import 'core/ui/theme/app_theme.dart';
import 'features/entry/screens/add_entry_screen.dart';
import 'presentation/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite FFI for Windows desktop
  if (Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize central dependency injection container
  await initServiceLocator();

  runApp(const MoneyLendingApp());
}

class MoneyLendingApp extends StatelessWidget {
  const MoneyLendingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ByajBook - Money Lending Ledger',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const AppShell(),
      routes: {
        'dashboard': (_) => const AppShell(initialTabIndex: 0),
        'customers': (_) => const AppShell(initialTabIndex: 1),
        'reports': (_) => const AppShell(initialTabIndex: 2),
        'settings': (_) => const AppShell(initialTabIndex: 3),
        'entry/add': (_) => const AddEntryScreen(),
      },
    );
  }
}
