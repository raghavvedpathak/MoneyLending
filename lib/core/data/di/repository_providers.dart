import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/repositories/customer_repository_impl.dart';
import '../../../../data/repositories/item_rate_repository_impl.dart';
import '../../../../data/repositories/record_repository_impl.dart';
import '../../../../data/repositories/settings_repository_impl.dart';
import '../../../../domain/repositories/customer_repository.dart';
import '../../../../domain/repositories/item_rate_repository.dart';
import '../../../../domain/repositories/record_repository.dart';
import '../../../../domain/repositories/settings_repository.dart';
import 'database_provider.dart';

/// Repository Riverpod providers [FIX-ARCH-DB-1] & [FIX-SINGLETON-SCOPE-1].
///
/// Mandated by Data Spec §4.3:
/// - Bound to implementations via separate Riverpod providers.
/// - Plain `Provider` without `.autoDispose` (app-lifetime scoped / keepAlive).
/// - An auto-disposing provider would re-create repository instances and their Lock mutexes,
///   breaking concurrency protection.

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return CustomerRepositoryImpl(db);
});

final recordRepositoryProvider = Provider<RecordRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return RecordRepositoryImpl(db);
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SettingsRepositoryImpl(db);
});

final itemRateRepositoryProvider = Provider<ItemRateRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return ItemRateRepositoryImpl(db);
});
