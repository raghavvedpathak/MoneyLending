import '../../../../domain/models/item_rate.dart';

/// Domain Contract for Item Rate Repository.
///
/// Mandated by Architecture Spec §4.5 & [FIX-ARCH-ITEMRATE-1]:
/// The ItemRateRepository interface must be defined as an abstract class in core/domain
/// (not just as a DAO in core/data). Required because features/dashboard and
/// core/calculations both depend on core/domain, not on core/data directly.
/// Without this interface, the Collection Alert Section and rate lookups cannot be injected cleanly.
abstract class ItemRateRepository {
  /// Latest rate for a category, or null if no rate has been entered.
  Stream<ItemRate?> watchCurrentRate(String category);

  /// Latest rate for every category — used by Rate Management Card.
  Stream<List<ItemRate>> watchCurrentRates();

  /// One-shot rates fetch for the background isolate — see FIX-OVERDUECOLLATERAL-1.
  /// Background tasks must not subscribe to Streams (same rule as getAllActiveRecordsOnce()
  /// in §8/Step 4). computeCollateralOverdue() calls this, never watchCurrentRates().
  Future<List<ItemRate>> getCurrentRatesOnce();

  /// [FIX-RATE-ASOF-1] (v1.16) Latest USABLE rate (ratePerUnit > 0) for [category] whose
  /// effectiveDate is on or before [date] (date-only); null when there is none. Used to
  /// auto-fill the item rate of a backdated record.
  /// SELECT * FROM item_rates WHERE item_category = ? AND effective_date <= ?
  /// AND rate_per_unit > 0 ORDER BY effective_date DESC LIMIT 1
  Future<ItemRate?> getRateAsOf(String category, DateTime date);

  /// All rates for a given ISO date — used for historical lookups.
  Stream<List<ItemRate>> watchRatesForDate(DateTime date);

  /// Upsert a rate for (category, date). Matches on (itemCategory, effectiveDate),
  /// NOT on id. If a row exists for this pair, updates ratePerUnit + updatedAt
  /// while preserving the existing id. If no row exists, inserts with a new UUID id.
  /// Never use replace-mode insert here — it reassigns the id on update.
  Future<void> upsertRate(ItemRate rate);

  // Backward-compatibility aliases for existing callers and tests:
  Stream<ItemRate?> getCurrentRate(String category);
  Future<ItemRate?> getCurrentRateOnce(String category);
  Stream<List<ItemRate>> getCurrentRates();
  Stream<List<ItemRate>> getRatesForDate(String date);
  Future<List<ItemRate>> getRatesForDateOnce(String date);
  Stream<List<ItemRate>> getRatesStream();
}
