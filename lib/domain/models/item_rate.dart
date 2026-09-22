import '../../core/domain/util/date_format.dart';

/// Pure Domain Entity for Item Market Rate.
///
/// Mandated by Data Spec §4.1:
/// Market rate snapshot for precious metals/items per unit.
class ItemRate {
  final String id;
  final String itemCategory;
  final double ratePerUnit;
  final DateTime effectiveDate;
  final DateTime updatedAt;

  const ItemRate({
    required this.id,
    required this.itemCategory,
    required this.ratePerUnit,
    required this.effectiveDate,
    required this.updatedAt,
  });

  /// Formatted as "10 September 2026"
  String get formattedEffectiveDate => formatDate(effectiveDate);

  /// Formatted as "10 September 2026, 02:30 PM"
  String get formattedUpdatedAt => formatDateTime(updatedAt);
}
