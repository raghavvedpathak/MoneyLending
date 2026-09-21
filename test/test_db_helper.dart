import 'package:money_lending/core/di/injection.dart';
import 'package:money_lending/data/datasources/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Centralized in-memory database and DI setup for widget & integration tests.
Future<DatabaseHelper> setupTestDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await DatabaseHelper.createTablesForTesting(db);
      },
    ),
  );

  final helper = DatabaseHelper.forTesting(db);
  if (!sl.isRegistered<DatabaseHelper>()) {
    sl.registerSingleton<DatabaseHelper>(helper);
  }
  await initServiceLocator();
  return helper;
}
