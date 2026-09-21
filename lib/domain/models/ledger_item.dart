/// Pure Domain Entity for LedgerItem.
///
/// Mandated by Data Spec §4.1, §5.1, [FIXLEDGERITEM-NULLABILITY-1],
/// [FIX-ITEM-CUSTODY-1], & [FIX-ITEM-FORM-1]:
/// - name is NOT NULL: String
/// - description is strictly nullable: String?
/// - fineWeight: UI-only derived value, not a DB column.
class LedgerItem {
  final String id;
  final String recordId;
  final String name; // free-text label e.g. "Gold ring with ruby"
  final String itemCategory; // FK-equivalent to ItemRateEntity.itemCategory
  final String? description; // optional notes; nullable — see [FIXLEDGERITEM-NULLABILITY-1]
  final double weight;
  final double purity; // stored as percentage e.g. 92.5
  final double rate; // snapshot at time of lending
  final double itemValue; // snapshot: weight * (purity/100) * rate
  final double lendPercentage; // user-entered % e.g. 80.0
  final double lendableAmount; // snapshot: itemValue * (lendPercentage/100)
  // [FIX-ITEM-CUSTODY-1] added by Step 6.1 — null unless copied via linkselection
  final String? sourceItemId;

  const LedgerItem({
    required this.id,
    required this.recordId,
    required this.name,
    required this.itemCategory,
    this.description,
    this.weight = 0.0,
    this.purity = 0.0,
    this.rate = 0.0,
    this.itemValue = 0.0,
    this.lendPercentage = 0.0,
    this.lendableAmount = 0.0,
    this.sourceItemId,
  });

  /// [FIX-ITEM-FORM-1] UI-only derived value, not a DB column — see the Item Entry Sub-Form Addendum
  double get fineWeight => weight * (purity / 100.0);

  LedgerItem copyWith({
    String? id,
    String? recordId,
    String? name,
    String? itemCategory,
    String? description,
    double? weight,
    double? purity,
    double? rate,
    double? itemValue,
    double? lendPercentage,
    double? lendableAmount,
    String? sourceItemId,
  }) {
    return LedgerItem(
      id: id ?? this.id,
      recordId: recordId ?? this.recordId,
      name: name ?? this.name,
      itemCategory: itemCategory ?? this.itemCategory,
      description: description ?? this.description,
      weight: weight ?? this.weight,
      purity: purity ?? this.purity,
      rate: rate ?? this.rate,
      itemValue: itemValue ?? this.itemValue,
      lendPercentage: lendPercentage ?? this.lendPercentage,
      lendableAmount: lendableAmount ?? this.lendableAmount,
      sourceItemId: sourceItemId ?? this.sourceItemId,
    );
  }
}
