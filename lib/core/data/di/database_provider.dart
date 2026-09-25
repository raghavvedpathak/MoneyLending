import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/datasources/database_helper.dart';

export '../schema/app_database.dart' show openConnection;

/// Drift AppDatabase type representation (§4.3 [FIX-ARCH-DB-1]).
///
/// In this architecture, DatabaseHelper manages the underlying SQLite connection pool,
/// WAL journal mode, 5000ms busy timeout, and thread-safe locks.
typedef AppDatabase = DatabaseHelper;

/// Single, app-lifetime-scoped Riverpod provider for AppDatabase (§4.3 [FIX-ARCH-DB-1]).
///
/// Mandated by Data Spec §4.3:
/// - Plain `Provider<AppDatabase>` with NO `.autoDispose` (app-lifetime scoped / keepAlive).
/// - Never instantiate directly inside a Notifier or widget; doing so creates multiple
///   database instances, each with its own connection and WAL file, causing data inconsistency.
/// - Direct equivalent of the Kotlin spec's Hilt @Singleton requirement.
/// - Properly closes the database on provider disposal via ref.onDispose(db.close).
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = DatabaseHelper.instance;
  ref.onDispose(db.close);
  return db;
});
