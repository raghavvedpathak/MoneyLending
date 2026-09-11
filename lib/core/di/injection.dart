import 'package:get_it/get_it.dart';

import '../../data/datasources/database_helper.dart';
import '../../data/repositories/customer_repository_impl.dart';
import '../../data/repositories/item_rate_repository_impl.dart';
import '../../data/repositories/record_repository_impl.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../domain/repositories/customer_repository.dart';
import '../../domain/repositories/item_rate_repository.dart';
import '../../domain/repositories/record_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../pdf/pdf.dart';

/// Central Dependency Injection container.
///
/// Mandated by Architecture Spec §2.3, §4.3, [FIX-ARCH-DB-1], and [FIX-SINGLETON-SCOPE-1]:
/// - DatabaseHelper is registered as @Singleton so only one connection pool & WAL exists.
/// - All repositories are registered as @Singleton so Mutex & single-threaded locks are shared.
final GetIt sl = GetIt.instance;

Future<void> initServiceLocator() async {
  // 1. Data Layer: Database Helper Singleton [FIX-ARCH-DB-1]
  if (!sl.isRegistered<DatabaseHelper>()) {
    sl.registerSingleton<DatabaseHelper>(DatabaseHelper.instance);
  }

  // 2. Data Layer: Repository Singletons [FIX-SINGLETON-SCOPE-1]
  if (!sl.isRegistered<CustomerRepository>()) {
    sl.registerLazySingleton<CustomerRepository>(
      () => CustomerRepositoryImpl(sl<DatabaseHelper>()),
    );
  }

  if (!sl.isRegistered<RecordRepository>()) {
    sl.registerLazySingleton<RecordRepository>(
      () => RecordRepositoryImpl(sl<DatabaseHelper>()),
    );
  }

  if (!sl.isRegistered<SettingsRepository>()) {
    sl.registerLazySingleton<SettingsRepository>(
      () => SettingsRepositoryImpl(sl<DatabaseHelper>()),
    );
  }

  if (!sl.isRegistered<ItemRateRepository>()) {
    sl.registerLazySingleton<ItemRateRepository>(
      () => ItemRateRepositoryImpl(sl<DatabaseHelper>()),
    );
  }

  // 3. Core Services: PDF Sharing Service
  if (!sl.isRegistered<PdfShareService>()) {
    sl.registerLazySingleton<PdfShareService>(
      () => PdfShareService(),
    );
  }
}
