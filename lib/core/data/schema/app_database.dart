import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'drift_tables.dart';

/// [FIX-DB-CONN-1] (v1.27) PUBLIC: shared by appDatabaseProvider (UI isolate) and by the alarm
/// callback (section 8). inBackgroundIsolate: true opens the file directly on the calling isolate —
/// the alarm callback already IS a background isolate and must not spawn a second one.
QueryExecutor openAppConnection({
  bool inBackgroundIsolate = false,
  String? customPath,
  bool inMemory = false,
}) {
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
    void setup(dynamic rawDb) {
      rawDb.execute('PRAGMA foreign_keys = ON;');
      rawDb.execute('PRAGMA journal_mode = WAL;');
      rawDb.execute('PRAGMA busy_timeout = 5000;');
    }

    return inBackgroundIsolate
        ? NativeDatabase(file, setup: setup)
        : NativeDatabase.createInBackground(file, setup: setup);
  });
}

/// Backwards-compatible alias for [openAppConnection] (§4.3 [FIX-ARCH-DB-1]).
QueryExecutor openConnection({
  String? customPath,
  bool inMemory = false,
  bool inBackgroundIsolate = false,
}) =>
    openAppConnection(
      inBackgroundIsolate: inBackgroundIsolate,
      customPath: customPath,
      inMemory: inMemory,
    );

/// AppDatabase class schema definition (§4.3 [FIX-ARCH-DB-1]).
///
/// Annotate with @DriftDatabase listing every table:
/// @DriftDatabase(tables: [Customers, Lenders, Records, LedgerItems, Payments, Settings, ItemRates, RetiredIds])
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
  Lenders,
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
    Lenders,
    Records,
    LedgerItems,
    Payments,
    Settings,
    ItemRates,
    RetiredIds,
  ];
}
