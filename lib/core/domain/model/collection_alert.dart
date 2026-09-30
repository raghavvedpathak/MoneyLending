import 'package:money_lending/domain/models/ledger_record.dart';

/// Sealed class hierarchy for Collection Alerts (§5.3 & [FIX-ARCH-COLLALERT-1]).
///
/// This type is the return value of computeCollectionAlerts() (the derived alert
/// view used by notifications and unit tests); the Dashboard itself consumes RecordRisk.
/// Both types depend only on core/domain, so they live here.
sealed class CollectionAlert {
  const CollectionAlert();

  /// Polymorphic access to the associated record across all alert subtypes.
  LedgerRecord get record;
}

/// Collateral's current live market value has dropped at or below totalDue
/// (principal + accrued interest - payments).
class CollateralDrop extends CollectionAlert {
  const CollateralDrop({
    required this.record,
    required this.currentCollateralValue, // sum of live market values across all items
    required this.totalDue, // from calculateRecordFinancials().totalDue
  });

  @override
  final LedgerRecord record;
  final double currentCollateralValue;
  final double totalDue;

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

/// No rate exists in ItemRateRepository for this item's category — item excluded
/// from collateral sum.
class RateMissing extends CollectionAlert {
  const RateMissing({
    required this.record,
    required this.itemCategory,
  });

  @override
  final LedgerRecord record;
  final String itemCategory; // the category string with no rate on file

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
  const OvershootWarning({
    required this.record,
    required this.projectedOutstanding, // principal + projectedInterest - totalPaid
    required this.itemValueAtLending, // sum of LedgerItem.itemValue snapshots
  });

  @override
  final LedgerRecord record;
  final double projectedOutstanding;
  final double itemValueAtLending;

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

/// [FIX-RISK-VIEWMODEL-1] (v1.14) One entry per ACTIVE GIVEN record — safe records
/// included — carrying every figure the unified Dashboard card and the Risk Summary
/// need. Produced by computeRecordRisks(); computeCollectionAlerts() is derived from it.
class RecordRisk {
  const RecordRisk({
    required this.record,
    required this.currentCollateralValue, // null when any item's category has no usable rate
    required this.missingRateCategories, // categories with no rate on file, or rate <= 0
    required this.totalDue, // calculateRecordFinancials(record, today).totalDue
    required this.projectedOutstanding, // owed at today + 2 months (accrual stops at endDate)
    required this.itemValueAtLending, // sum of LedgerItem.itemValue snapshots
  });

  final LedgerRecord record;
  final double? currentCollateralValue;
  final Set<String> missingRateCategories;
  final double totalDue;
  final double projectedOutstanding;
  final double itemValueAtLending;

  bool get hasCollateral => record.items.isNotEmpty;
  bool get collateralDrop =>
      hasCollateral && currentCollateralValue != null && currentCollateralValue! <= totalDue;
  bool get overshoot => hasCollateral && projectedOutstanding >= itemValueAtLending;
  bool get atRisk => collateralDrop || overshoot;

  @override
  String toString() =>
      'RecordRisk(record: ${record.id}, collateralDrop: $collateralDrop, overshoot: $overshoot, atRisk: $atRisk, missing: $missingRateCategories)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecordRisk &&
          runtimeType == other.runtimeType &&
          record.id == other.record.id &&
          currentCollateralValue == other.currentCollateralValue &&
          totalDue == other.totalDue &&
          projectedOutstanding == other.projectedOutstanding &&
          itemValueAtLending == other.itemValueAtLending;

  @override
  int get hashCode => Object.hash(
        record.id,
        currentCollateralValue,
        totalDue,
        projectedOutstanding,
        itemValueAtLending,
      );
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
