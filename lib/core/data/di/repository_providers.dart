import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/repositories/customer_repository_impl.dart';
import '../../../../data/repositories/item_rate_repository_impl.dart';
import '../../../../data/repositories/lender_repository_impl.dart';
import '../../../../data/repositories/record_repository_impl.dart';
import '../../../../data/repositories/settings_repository_impl.dart';
import '../../domain/domain.dart';
import 'database_provider.dart';

/// Repository Riverpod providers [FIX-ARCH-DB-1] & [FIX-SINGLETON-SCOPE-1].
///
/// Mandated by Data Spec §4.3:
/// - Bound to implementations via separate Riverpod providers.
/// - Plain `Provider` without `.autoDispose` (app-lifetime scoped / keepAlive).
/// - An auto-disposing provider would re-create repository instances and their Lock mutexes,
///   breaking concurrency protection.

/// Functional accessors matching @Riverpod(keepAlive: true) spec signatures (§4.3):
CustomerRepository customerRepository(Ref ref) =>
    CustomerRepositoryImpl(ref.watch(appDatabaseProvider));

LenderRepository lenderRepository(Ref ref) =>
    LenderRepositoryImpl(ref.watch(appDatabaseProvider));

RecordRepository recordRepository(Ref ref) =>
    RecordRepositoryImpl(ref.watch(appDatabaseProvider));

SettingsRepository settingsRepository(Ref ref) =>
    SettingsRepositoryImpl(ref.watch(appDatabaseProvider));

ItemRateRepository itemRateRepository(Ref ref) =>
    ItemRateRepositoryImpl(ref.watch(appDatabaseProvider));

final customerRepositoryProvider =
    Provider<CustomerRepository>((ref) => customerRepository(ref));

final lenderRepositoryProvider =
    Provider<LenderRepository>((ref) => lenderRepository(ref));

final recordRepositoryProvider =
    Provider<RecordRepository>((ref) => recordRepository(ref));

final settingsRepositoryProvider =
    Provider<SettingsRepository>((ref) => settingsRepository(ref));

final itemRateRepositoryProvider =
    Provider<ItemRateRepository>((ref) => itemRateRepository(ref));

/// Reactive StreamProvider exposing settings [FIX-ARCH-SETTINGS-1].
/// Never null — emits default settings on first access and updates reactively.
final settingsStreamProvider = StreamProvider<Settings>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return repo.watchSettings();
});
