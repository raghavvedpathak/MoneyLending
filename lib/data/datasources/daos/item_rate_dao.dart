import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../../core/utils/uuid_generator.dart';
import '../../models/item_rate_entity.dart';

/// DAO for ItemRateEntity.
///
/// Mandated by Data Spec §4.1, §4.4, §4.5 & [FIX-ARCH-ITEMRATE-1]:
/// - Unique index on (itemCategory, effectiveDate).
/// - Never use @Insert(onConflict = OnConflictStrategy.REPLACE) — REPLACE deletes and reinserts
///   the row, reassigning the id UUID.
/// - Check-then-branch: call getByItemCategoryAndDate(category, date) first inside @Transaction;
///   if row exists, call @Update; if not, call @Insert(ABORT).
/// - Preserves the existing id on update, required for correct historical audit trails.
class ItemRateDao {
  final DatabaseExecutor _db;

  const ItemRateDao(this._db);

  /// Queries a specific rate by category and effectiveDate
  Future<ItemRateEntity?> getByItemCategoryAndDate(String category, String date) async {
    final maps = await _db.query(
      'item_rates',
      where: 'itemCategory = ? AND effectiveDate = ?',
      whereArgs: [category, date],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return ItemRateEntity.fromMap(maps.first);
  }

  /// Latest rate for a single category
  Future<ItemRateEntity?> getLatestForCategory(String category) async {
    final maps = await _db.query(
      'item_rates',
      where: 'itemCategory = ?',
      whereArgs: [category],
      orderBy: 'effectiveDate DESC, updatedAt DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return ItemRateEntity.fromMap(maps.first);
  }

  /// Latest rate for every category — used by Rate Management Card (§4.5)
  Future<List<ItemRateEntity>> getLatestForEveryCategory() async {
    final maps = await _db.rawQuery('''
      SELECT ir.* FROM item_rates ir
      INNER JOIN (
        SELECT itemCategory, MAX(effectiveDate) as maxEffectiveDate
        FROM item_rates
        GROUP BY itemCategory
      ) latest ON ir.itemCategory = latest.itemCategory AND ir.effectiveDate = latest.maxEffectiveDate
      ORDER BY ir.itemCategory ASC
    ''');
    return maps.map((m) => ItemRateEntity.fromMap(m)).toList();
  }

  /// All rates for a given ISO date (YYYY-MM-DD) — historical lookups (§4.5)
  Future<List<ItemRateEntity>> getRatesForDate(String date) async {
    final maps = await _db.query(
      'item_rates',
      where: 'effectiveDate = ?',
      whereArgs: [date],
      orderBy: 'itemCategory ASC',
    );
    return maps.map((m) => ItemRateEntity.fromMap(m)).toList();
  }

  /// All item rate records
  Future<List<ItemRateEntity>> getAll() async {
    final maps = await _db.query(
      'item_rates',
      orderBy: 'effectiveDate DESC, updatedAt DESC',
    );
    return maps.map((m) => ItemRateEntity.fromMap(m)).toList();
  }

  /// Inserts a new rate entity strictly with ABORT conflict strategy
  Future<void> insert(ItemRateEntity rate) async {
    await _db.insert(
      'item_rates',
      rate.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Updates ratePerUnit and updatedAt for a specific id
  Future<void> update(ItemRateEntity rate) async {
    await _db.update(
      'item_rates',
      {
        'ratePerUnit': rate.ratePerUnit,
        'updatedAt': rate.updatedAt,
      },
      where: 'id = ?',
      whereArgs: [rate.id],
    );
  }

  /// Upsert a rate for (category, date) per §4.5:
  /// Matches on (itemCategory, effectiveDate), NOT on id.
  /// If a row exists for this pair, updates ratePerUnit + updatedAt while preserving the existing id.
  /// If no row exists, inserts with a new UUID id.
  /// Never uses REPLACE — it reassigns the id on update.
  Future<void> upsert(ItemRateEntity rate) async {
    final executor = _db;
    if (executor is Database) {
      await executor.transaction((txn) async {
        final dao = ItemRateDao(txn);
        final existing = await dao.getByItemCategoryAndDate(rate.itemCategory, rate.effectiveDate);
        if (existing != null) {
          await dao.update(ItemRateEntity(
            id: existing.id,
            itemCategory: rate.itemCategory,
            ratePerUnit: rate.ratePerUnit,
            effectiveDate: rate.effectiveDate,
            updatedAt: rate.updatedAt,
          ));
        } else {
          final effectiveId = rate.id.isNotEmpty ? rate.id : AppUuid.generate();
          await dao.insert(ItemRateEntity(
            id: effectiveId,
            itemCategory: rate.itemCategory,
            ratePerUnit: rate.ratePerUnit,
            effectiveDate: rate.effectiveDate,
            updatedAt: rate.updatedAt,
          ));
        }
      });
    } else {
      final existing = await getByItemCategoryAndDate(rate.itemCategory, rate.effectiveDate);
      if (existing != null) {
        await update(ItemRateEntity(
          id: existing.id,
          itemCategory: rate.itemCategory,
          ratePerUnit: rate.ratePerUnit,
          effectiveDate: rate.effectiveDate,
          updatedAt: rate.updatedAt,
        ));
      } else {
        final effectiveId = rate.id.isNotEmpty ? rate.id : AppUuid.generate();
        await insert(ItemRateEntity(
          id: effectiveId,
          itemCategory: rate.itemCategory,
          ratePerUnit: rate.ratePerUnit,
          effectiveDate: rate.effectiveDate,
          updatedAt: rate.updatedAt,
        ));
      }
    }
  }
}
