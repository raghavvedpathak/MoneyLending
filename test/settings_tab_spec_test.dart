import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/di/injection.dart';
import 'package:money_lending/data/datasources/database_helper.dart';
import 'package:money_lending/domain/domain.dart';
import 'package:money_lending/features/settings/settings.dart';
import 'test_db_helper.dart';

void main() {
  late DatabaseHelper dbHelper;
  late SettingsRepository settingsRepo;
  late CustomerRepository customerRepo;
  late RecordRepository recordRepo;

  setUpAll(() async {
    dbHelper = await setupTestDatabase();
    settingsRepo = sl<SettingsRepository>();
    customerRepo = sl<CustomerRepository>();
    recordRepo = sl<RecordRepository>();
  });

  tearDownAll(() async {
    await sl.reset();
  });

  group('Section 10.4: Tab 4 Settings Specification Tests', () {
    testWidgets('Business info form & default interest rate field persist updates', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        await dbHelper.clearAllData();
        // Set initial settings
        await settingsRepo.updateSettings(const Settings(
          id: 1,
          name: 'Original Firm',
          phone: '9876543210',
          address: '123 Market St',
          defaultInterestRate: 2.0,
        ));

        await tester.pumpWidget(
          const MaterialApp(
            home: SettingsScreen(),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 1. Verify initial form fields loaded
      expect(find.text('Original Firm'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('123 Market St'), findsOneWidget);
      expect(find.text('2.0'), findsOneWidget);
      expect(find.text('% / month'), findsOneWidget);

      // 2. Edit business info form fields
      await tester.enterText(find.byKey(const Key('settings_shop_name_field')), 'Supreme Jewelers & Finance');
      await tester.enterText(find.byKey(const Key('settings_phone_field')), '+91 99988 77766');
      await tester.enterText(find.byKey(const Key('settings_address_field')), '456 Bullion Plaza, Mumbai');
      await tester.enterText(find.byKey(const Key('settings_default_rate_field')), '3.5');

      // Unfocus keyboard to stop blinking cursor timer
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      // 3. Scroll down and save Settings inside runAsync
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('settings_save_button')), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('settings_save_button')));
        await Future<void>.delayed(const Duration(milliseconds: 400));

        // 4. Verify persisted in SettingsRepository
        final updated = await settingsRepo.getSettingsOnce();
        expect(updated.name, 'Supreme Jewelers & Finance');
        expect(updated.phone, '+91 99988 77766');
        expect(updated.address, '456 Bullion Plaza, Mumbai');
        expect(updated.defaultInterestRate, 3.5);
      });

      // Dispose widget to cleanly close all active timers
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('JSON export and import buttons are rendered and accessible per §7', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        await dbHelper.clearAllData();
        await tester.pumpWidget(
          const MaterialApp(
            home: SettingsScreen(),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Scroll to JSON Backup & Restore section
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('JSON Backup & Restore'), findsOneWidget);
      expect(find.byKey(const Key('settings_export_button')), findsOneWidget);
      expect(find.byKey(const Key('settings_restore_button')), findsOneWidget);

      // Buttons are enabled and interactable
      final exportBtn = tester.widget<OutlinedButton>(
        find.byKey(const Key('settings_export_button')),
      );
      final restoreBtn = tester.widget<OutlinedButton>(
        find.byKey(const Key('settings_restore_button')),
      );
      expect(exportBtn.onPressed, isNotNull);
      expect(restoreBtn.onPressed, isNotNull);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Clear-all-data confirmation dialog dismisses on Cancel', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        await dbHelper.clearAllData();
        // Seed customer
        await customerRepo.insertCustomer(Customer(
          id: 'cust-cancel-test',
          displayId: 'CUST26-27-01',
          name: 'Retained Customer',
          createdAt: DateTime(2026, 4, 1),
        ));

        await tester.pumpWidget(
          const MaterialApp(
            home: SettingsScreen(),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 1. Scroll to Danger Zone and tap Clear All Data
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('settings_clear_data_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings_clear_data_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 2. Confirmation dialog is shown
      expect(find.text('Clear All Data?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.byKey(const Key('settings_confirm_clear_button')), findsOneWidget);

      // 3. Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Dialog is dismissed and customer remains
      expect(find.text('Clear All Data?'), findsNothing);

      await tester.runAsync(() async {
        final customers = await customerRepo.getAllCustomersOnce();
        expect(customers.any((c) => c.id == 'cust-cancel-test'), isTrue);
      });

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Clear-all-data confirmation clears tables, empties retired_ids, and restarts ID sequences at 01', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        await dbHelper.clearAllData();

        // 1. Seed customer, record, payment, and retire IDs
        final cust = await customerRepo.insertCustomer(Customer(
          id: 'c-wipe-1',
          displayId: 'CUST26-27-01',
          name: 'Borrower One',
          createdAt: DateTime(2026, 4, 1),
        ));

        await recordRepo.insertRecord(LedgerRecord(
          id: 'r-wipe-1',
          transactionId: 'TRAN092601',
          type: RecordType.GIVEN,
          customerId: cust.id,
          customerName: cust.name,
          principalAmount: 50000,
          interestRate: 2.0,
          startDate: DateTime(2026, 9, 1),
          status: RecordStatus.ACTIVE,
        ));

        // Insert retired IDs to simulate retired numbers that advance sequence
        final db = await dbHelper.database;
        await db.insert('retired_ids', {
          'kind': 'customer',
          'displayId': 'CUST26-27-02',
          'retiredAt': DateTime.now().toIso8601String(),
        });
        await db.insert('retired_ids', {
          'kind': 'transaction',
          'displayId': 'TRAN092602',
          'retiredAt': DateTime.now().toIso8601String(),
        });
        await db.insert('retired_ids', {
          'kind': 'payment',
          'displayId': 'PAY092602',
          'retiredAt': DateTime.now().toIso8601String(),
        });

        // Verify that before clear, next IDs would be 03
        final nextCustBefore = await dbHelper.generateNextCustomerDisplayId(db, DateTime(2026, 4, 1));
        final nextTxnBefore = await dbHelper.generateNextTransactionId(db, DateTime(2026, 9, 1));
        final nextPayBefore = await dbHelper.generateNextPaymentId(db, DateTime(2026, 9, 1));
        expect(nextCustBefore, 'CUST26-27-03');
        expect(nextTxnBefore, 'TRAN092603');
        expect(nextPayBefore, 'PAY092603');

        await tester.pumpWidget(
          const MaterialApp(
            home: SettingsScreen(),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 2. Open confirmation dialog and confirm Clear Everything
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('settings_clear_data_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings_clear_data_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Clear All Data?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings_confirm_clear_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 500));

        // 3. Verify all tables and retired_ids are emptied
        final db = await dbHelper.database;
        final customers = await customerRepo.getAllCustomersOnce();
        final records = await recordRepo.getAllRecordsOnce();
        final retired = await dbHelper.getAllRetiredIds();

        expect(customers, isEmpty);
        expect(records, isEmpty);
        expect(retired, isEmpty);

        // 4. Verify ID sequences restart at 01
        final nextCustAfter = await dbHelper.generateNextCustomerDisplayId(db, DateTime(2026, 4, 1));
        final nextTxnAfter = await dbHelper.generateNextTransactionId(db, DateTime(2026, 9, 1));
        final nextPayAfter = await dbHelper.generateNextPaymentId(db, DateTime(2026, 9, 1));

        expect(nextCustAfter, 'CUST26-27-01');
        expect(nextTxnAfter, 'TRAN092601');
        expect(nextPayAfter, 'PAY092601');
      });

      await tester.pumpWidget(const SizedBox());
    });
  });
}
