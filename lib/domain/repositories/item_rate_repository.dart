import '../models/item_rate.dart';

/// Domain Contract for Item Rate Repository.
///
/// Mandated by Architecture Spec §4.5 & [FIX-ARCH-ITEMRATE-1]:
/// The ItemRateRepository interface must be defined in :core:domain (not just as a DAO in :core:data).
/// Required because :feature:dashboard and :core:calculations both depend on :core:domain,
/// not on :core:data directly. Without this interface, the Collection Alert Section and rate lookups
/// cannot be injected cleanly.
abstract class ItemRateRepository {
  /// Latest rate for a category as a reactive Stream, or emits null if no rate has been entered.
  Stream<ItemRate?> getCurrentRate(String category);

  /// One-shot query for the latest rate for a category.
  Future<ItemRate?> getCurrentRateOnce(String category);

  /// Latest rate for every category — used by Rate Management Card.
  Stream<List<ItemRate>> getCurrentRates();

  /// One-shot query for latest rate for every category.
  Future<List<ItemRate>> getCurrentRatesOnce();

  /// All rates for a given ISO date (YYYY-MM-DD) — used for historical lookups.
  Stream<List<ItemRate>> getRatesForDate(String date);

  /// One-shot query for all rates for a given ISO date.
  Future<List<ItemRate>> getRatesForDateOnce(String date);

  /// Legacy stream accessor for backwards compatibility.
  Stream<List<ItemRate>> getRatesStream();

  /// Upsert a rate for (category, date). Matches on (itemCategory, effectiveDate),
  /// NOT on id. If a row exists for this pair, updates ratePerUnit + updatedAt
  /// while preserving the existing id. If no row exists, inserts with a new UUID id.
  /// Never use @Insert(REPLACE) here — it reassigns the id on update.
  Future<void> upsertRate(ItemRate rate);
}
