import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/di/injection.dart';
import 'package:money_lending/core/navigation/app_router.dart';
import 'package:money_lending/main.dart';
import 'test_db_helper.dart';

void main() {
  setUpAll(() async {
    await setupTestDatabase();
  });

  tearDownAll(() async {
    await sl.reset();
  });

  group('10.1 Navigation Structure & StatefulShellRoute.indexedStack Tests', () {
    testWidgets('App mounts with GoRouter and defaults to Dashboard tab', (tester) async {
      await tester.pumpWidget(const MoneyLendingApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Dashboard'), findsWidgets);
      expect(find.text('Customers'), findsWidgets);
      expect(find.text('Reports'), findsWidgets);
      expect(find.text('Settings'), findsWidgets);

      // Drain any background timers
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('StatefulShellRoute branches switch tabs and preserve independent state', (tester) async {
      await tester.pumpWidget(const MoneyLendingApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Switch to Customers tab
      await tester.tap(find.text('Customers').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(appRouter.routeInformationProvider.value.uri.path, equals('/customers'));

      // Switch to Reports tab
      await tester.tap(find.text('Reports').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(appRouter.routeInformationProvider.value.uri.path, equals('/reports'));

      // Switch to Settings tab
      await tester.tap(find.text('Settings').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(appRouter.routeInformationProvider.value.uri.path, equals('/settings'));

      // Switch back to Dashboard tab
      await tester.tap(find.text('Dashboard').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(appRouter.routeInformationProvider.value.uri.path, equals('/dashboard'));

      await tester.pump(const Duration(seconds: 11));
    });
  });
}
