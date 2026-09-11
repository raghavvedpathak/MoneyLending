import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/di/injection.dart';
import 'package:money_lending/data/datasources/database_helper.dart';
import 'package:money_lending/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          // Create schema for in-memory widget test
          await db.execute('''
            CREATE TABLE customers (
              id TEXT PRIMARY KEY,
              displayId TEXT NOT NULL UNIQUE,
              name TEXT NOT NULL,
              phone TEXT,
              address TEXT,
              createdAt TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE records (
              id TEXT PRIMARY KEY,
              transactionId TEXT NOT NULL UNIQUE,
              type TEXT NOT NULL,
              customerId TEXT NOT NULL,
              customerName TEXT,
              startDate TEXT NOT NULL,
              endDate TEXT,
              principalAmount REAL NOT NULL,
              interestRate REAL NOT NULL,
              status TEXT NOT NULL,
              settledDate TEXT,
              calculatedInterest REAL,
              linkedRecordId TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE ledger_items (
              id TEXT PRIMARY KEY,
              recordId TEXT NOT NULL,
              name TEXT NOT NULL,
              itemCategory TEXT NOT NULL,
              description TEXT,
              weight REAL,
              purity REAL,
              rate REAL,
              itemValue REAL,
              lendPercentage REAL,
              lendableAmount REAL
            )
          ''');
          await db.execute('''
            CREATE TABLE payments (
              id TEXT PRIMARY KEY,
              recordId TEXT NOT NULL,
              amount REAL NOT NULL,
              date TEXT NOT NULL,
              notes TEXT,
              interestPaid REAL NOT NULL,
              principalPaid REAL NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE settings (
              id INTEGER PRIMARY KEY,
              name TEXT,
              phone TEXT,
              address TEXT,
              defaultInterestRate REAL NOT NULL DEFAULT 2.0
            )
          ''');
          await db.insert('settings', {
            'id': 1,
            'name': 'Money Lending Ledger',
            'phone': '9999999999',
            'address': 'Test Shop, Market Road',
            'defaultInterestRate': 2.0,
          });
          await db.execute('''
            CREATE TABLE item_rates (
              id TEXT PRIMARY KEY,
              itemCategory TEXT NOT NULL,
              ratePerUnit REAL NOT NULL,
              effectiveDate TEXT NOT NULL,
              updatedAt TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    final helper = DatabaseHelper.forTesting(db);
    if (!sl.isRegistered<DatabaseHelper>()) {
      sl.registerSingleton<DatabaseHelper>(helper);
    }
    await initServiceLocator();
  });

  testWidgets('MoneyLendingApp smoke test mounts navigation tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const MoneyLendingApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Customers'), findsWidgets);
    expect(find.text('Reports'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);

    // Drain any pending timers (sqflite lock warning & debounce)
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('Responsive layout adapts cleanly between Smartphone (<720dp) and Tablet (>=720dp)', (WidgetTester tester) async {
    // 1. Smartphone form-factor (400 x 800)
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MoneyLendingApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Bottom NavigationBar on Smartphone
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    // 2. Tablet form-factor (1024 x 768)
    tester.view.physicalSize = const Size(1024, 768);
    await tester.pumpWidget(const MoneyLendingApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Side NavigationRail on Tablet
    expect(find.byType(NavigationRail), findsOneWidget);

    await tester.pump(const Duration(seconds: 11));
  });
}
