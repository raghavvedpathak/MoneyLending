import 'ledger_record.dart';

/// Sealed hierarchy for Collection Alerts (§5.3 & [FIX-ARCH-COLLALERT-1]).
///
/// Mandated by Architecture Spec §5.3 & [FIX-NAMING-ALERTS-1]:
/// Use CamelCase names: CollateralDrop, RateMissing, OvershootWarning.
sealed class CollectionAlert {
  final LedgerRecord record;

  const CollectionAlert(this.record);
}

/// Collateral's current live market value has dropped at or below totalDue
/// (principal + accrued interest - payments).
class CollateralDrop extends CollectionAlert {
  /// Sum of live market values across all items in record with rates on file.
  final double currentCollateralValue;

  /// From calculateRecordFinancials().totalDue.
  final double totalDue;

  const CollateralDrop({
    required LedgerRecord record,
    required this.currentCollateralValue,
    required this.totalDue,
  }) : super(record);

  /// Gap between total due and collateral value: totalDue - currentCollateralValue.
  double get gap => totalDue - currentCollateralValue;

  @override
  String toString() =>
      'CollateralDrop(record: ${record.id}, currentCollateralValue: $currentCollateralValue, totalDue: $totalDue, gap: $gap)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CollateralDrop &&
          runtimeType == other.runtimeType &&
          record.id == other.record.id &&
          currentCollateralValue == other.currentCollateralValue &&
          totalDue == other.totalDue;

  @override
  int get hashCode => Object.hash(record.id, currentCollateralValue, totalDue);
}

/// No rate exists in ItemRateRepository for this item's category.
/// The item is excluded from the collateral sum rather than zeroed silently.
class RateMissing extends CollectionAlert {
  /// The category string with no rate on file (looked up by itemCategory, never name).
  final String itemCategory;

  const RateMissing({
    required LedgerRecord record,
    required this.itemCategory,
  }) : super(record);

  @override
  String toString() => 'RateMissing(record: ${record.id}, itemCategory: $itemCategory)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RateMissing &&
          runtimeType == other.runtimeType &&
          record.id == other.record.id &&
          itemCategory == other.itemCategory;

  @override
  int get hashCode => Object.hash(record.id, itemCategory);
}

/// Projected outstanding in 2 months will exceed item value at time of lending.
class OvershootWarning extends CollectionAlert {
  /// principal + projectedInterest (in 2 months) - totalPaid.
  final double projectedOutstanding;

  /// Sum of LedgerItem.itemValue snapshots at the time of lending.
  final double itemValueAtLending;

  const OvershootWarning({
    required LedgerRecord record,
    required this.projectedOutstanding,
    required this.itemValueAtLending,
  }) : super(record);

  /// Shortfall gap: projectedOutstanding - itemValueAtLending.
  double get gap => projectedOutstanding - itemValueAtLending;

  @override
  String toString() =>
      'OvershootWarning(record: ${record.id}, projectedOutstanding: $projectedOutstanding, itemValueAtLending: $itemValueAtLending, gap: $gap)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OvershootWarning &&
          runtimeType == other.runtimeType &&
          record.id == other.record.id &&
          projectedOutstanding == other.projectedOutstanding &&
          itemValueAtLending == other.itemValueAtLending;

  @override
  int get hashCode => Object.hash(record.id, projectedOutstanding, itemValueAtLending);
}

/// Data model for Unified Collection Alert Card (§5.4).
///
/// Displays both collateral-drop status and 2-month overshoot status side-by-side
/// on a single card for an ACTIVE GIVEN record.
class CollectionAlertCardData {
  final LedgerRecord record;
  final double? currentCollateralValue;
  final double totalDue;
  final bool isCollateralUnderwater;
  final double projectedOutstanding;
  final double itemValueAtLending;
  final bool isOvershoot;
  final bool hasMissingRate;
  final List<String> missingRateCategories;

  const CollectionAlertCardData({
    required this.record,
    this.currentCollateralValue,
    required this.totalDue,
    required this.isCollateralUnderwater,
    required this.projectedOutstanding,
    required this.itemValueAtLending,
    required this.isOvershoot,
    this.hasMissingRate = false,
    this.missingRateCategories = const [],
  });

  /// True when record has pledged collateral items.
  bool get hasCollateral => record.items.isNotEmpty;

  /// True when either collateral is underwater or 2-month overshoot triggers (§5.4).
  /// UI renders action line "Contact customer now." in bold red and tinted background.
  bool get isTriggered => isCollateralUnderwater || isOvershoot;

  /// True when both collateral and projection are safe (neutral card surface).
  bool get isSafe => !isTriggered;
}

/// [FIX-RISK-VIEWMODEL-1] (v1.14) One entry per ACTIVE GIVEN record — safe records
/// included — carrying every figure the unified Dashboard card and the Risk Summary
/// need. Produced by computeRecordRisks(); computeCollectionAlerts() is derived from it.
class RecordRisk {
  const RecordRisk({
    required this.record,
    required this.currentCollateralValue,
    required this.missingRateCategories,
    required this.totalDue,
    required this.projectedOutstanding,
    required this.itemValueAtLending,
  });

  final LedgerRecord record;
  final double? currentCollateralValue; // null when any item's category has no usable rate
  final Set<String> missingRateCategories; // categories with no rate on file, or rate <= 0
  final double totalDue; // calculateRecordFinancials(record, today).totalDue
  final double projectedOutstanding; // owed at today + 2 months (accrual stops at endDate)
  final double itemValueAtLending; // sum of LedgerItem.itemValue snapshots

  bool get hasCollateral => record.items.isNotEmpty;
  bool get collateralDrop =>
      hasCollateral && currentCollateralValue != null && currentCollateralValue! <= totalDue;
  bool get overshoot => hasCollateral && projectedOutstanding >= itemValueAtLending;
  bool get atRisk => collateralDrop || overshoot;
}

