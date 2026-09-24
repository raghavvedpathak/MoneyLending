import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'drift_tables.dart';

/// Opens a connection to moneylending.db with the required SQLite PRAGMAs (§4.3 [FIX-ARCH-DB-1] & [FIX-BG-DB-1]).
///
/// Mandated settings:
/// - PRAGMA foreign_keys = ON;
/// - PRAGMA journal_mode = WAL;
/// - PRAGMA busy_timeout = 5000;
QueryExecutor openConnection({String? customPath, bool inMemory = false}) {
  if (inMemory) {
    return NativeDatabase.memory(
      setup: (rawDb) {
        rawDb.execute('PRAGMA foreign_keys = ON;');
        rawDb.execute('PRAGMA journal_mode = WAL;');
        rawDb.execute('PRAGMA busy_timeout = 5000;');
      },
    );
  }

  return LazyDatabase(() async {
    final File file;
    if (customPath != null) {
      file = File(customPath);
    } else {
      final dbFolder = await getApplicationDocumentsDirectory();
      file = File(p.join(dbFolder.path, 'moneylending.db'));
    }
    return NativeDatabase.createInBackground(
      file,
      setup: (rawDb) {
        rawDb.execute('PRAGMA foreign_keys = ON;');
        rawDb.execute('PRAGMA journal_mode = WAL;');
        rawDb.execute('PRAGMA busy_timeout = 5000;');
      },
    );
  });
}

/// AppDatabase class schema definition (§4.3 [FIX-ARCH-DB-1]).
///
/// Annotate with @DriftDatabase listing every table:
/// @DriftDatabase(tables: [Customers, Records, LedgerItems, Payments, Settings, ItemRates, RetiredIds])
///
/// Schema version and migration rules:
/// - Schema version starts at 1.
/// - When making a schema change:
///   1. Bump schemaVersion to 2.
///   2. Add a MigrationStrategy with onUpgrade stepping through versions:
///      onUpgrade: (m, from, to) async {
///        if (from < 2) { await m.addColumn(records, records.someNewColumn); }
///      }
///   3. Never call m.deleteTable / recreate-from-scratch as a shortcut —
///      that is the Drift equivalent of Room's forbidden fallbackToDestructiveMigration().
@DriftDatabase(tables: [
  Customers,
  Records,
  LedgerItems,
  Payments,
  Settings,
  ItemRates,
  RetiredIds,
])
class AppDatabaseSchema {
  static const int currentSchemaVersion = 1;
  static const String databaseFileName = 'moneylending.db';

  static const List<Type> allTables = [
    Customers,
    Records,
    LedgerItems,
    Payments,
    Settings,
    ItemRates,
    RetiredIds,
  ];
}
