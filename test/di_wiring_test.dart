import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/di/injection.dart';
import 'package:money_lending/data/data.dart';
import 'package:money_lending/domain/domain.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DI Wiring & Singleton Scope Tests (§4.3) [FIX-ARCH-DB-1] [FIX-SINGLETON-SCOPE-1]', () {
    setUpAll(() async {
      await initServiceLocator();
    });

    test('DatabaseHelper is registered as a Singleton', () {
      final db1 = sl<DatabaseHelper>();
      final db2 = sl<DatabaseHelper>();
      expect(identical(db1, db2), isTrue);
    });

    test('CustomerRepository is registered as a Singleton', () {
      final repo1 = sl<CustomerRepository>();
      final repo2 = sl<CustomerRepository>();
      expect(identical(repo1, repo2), isTrue);
      expect(repo1, isA<CustomerRepositoryImpl>());
    });

    test('RecordRepository is registered as a Singleton with shared locks', () {
      final repo1 = sl<RecordRepository>();
      final repo2 = sl<RecordRepository>();
      expect(identical(repo1, repo2), isTrue);
      expect(repo1, isA<RecordRepositoryImpl>());
    });

    test('SettingsRepository is registered as a Singleton', () {
      final repo1 = sl<SettingsRepository>();
      final repo2 = sl<SettingsRepository>();
      expect(identical(repo1, repo2), isTrue);
      expect(repo1, isA<SettingsRepositoryImpl>());
    });

    test('ItemRateRepository is registered as a Singleton', () {
      final repo1 = sl<ItemRateRepository>();
      final repo2 = sl<ItemRateRepository>();
      expect(identical(repo1, repo2), isTrue);
      expect(repo1, isA<ItemRateRepositoryImpl>());
    });

    test('RecordPaymentTotal model holds totals correctly', () {
      const total = RecordPaymentTotal(recordId: 'rec-1', totalPaid: 5000.0);
      expect(total.recordId, 'rec-1');
      expect(total.totalPaid, 5000.0);
    });
  });
}
