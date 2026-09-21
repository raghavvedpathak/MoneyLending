import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/datasources/database_helper.dart';

/// Single, app-lifetime-scoped Riverpod provider for DatabaseHelper [FIX-ARCH-DB-1].
///
/// Mandated by Data Spec §4.3:
/// - KeepAlive / no autoDispose so a single connection pool & WAL exists.
/// - Never instantiate directly in a Notifier or widget.
final appDatabaseProvider = Provider<DatabaseHelper>((ref) {
  return DatabaseHelper.instance;
});
