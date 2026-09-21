import 'dart:math' as math;
import '../../../domain/domain.dart';
import '../calculation_engine.dart';
import '../util/date_extensions.dart';

/// [FIX-RATE-USABLE-1] A rate is usable only if a row exists for the category AND
/// ratePerUnit > 0 (the "Add Category" row stores 0.0 meaning "not set yet").
/// Shared by computeRecordRisks() and computeCollateralOverdue() (Addendum F).
double? usableRate(List<ItemRate> rates, String category) {
  for (final r in rates) {
    if (r.itemCategory == category && r.ratePerUnit > 0.0) return r.ratePerUnit;
  }
  final normCategory = category.trim().toUpperCase();
  for (final r in rates) {
    if (r.itemCategory.trim().toUpperCase() == normCategory && r.ratePerUnit > 0.0) {
      return r.ratePerUnit;
    }
  }
  return null;
}

/// computeRecordRisks() — the single pure function behind the Dashboard card, the Risk
/// Summary and the daily overshoot notification (§5.3 & [FIX-RISK-VIEWMODEL-1]).
///
/// [FIX-CLOCK-1] `today` is injected (already .dateOnly) — the function never reads the clock.
/// [FIX-COLLALERT-TOTALPAID-1] [totalPaidMap] defaults to const {} as a test safety net.
List<RecordRisk> computeRecordRisks({
  required List<LedgerRecord> records, // ACTIVE GIVEN records, FULL ([FIX-PERF-EAGERLOAD-2])
  required List<ItemRate> rates,
  required DateTime today,
  Map<String, double> totalPaidMap = const {},
}) {
  // IMPORTANT: totalPaid is always sourced from the totalPaidMap parameter.
  // Do NOT sum record.payments directly here — it would bypass the precomputed
  // aggregates and break the background-task path (which passes a pre-fetched
  // map).
  final todayDate = today.dateOnly;
  final projectedTarget = addMonths(todayDate, 2);

  final group1 = <({RecordRisk risk, double maxGap})>[];
  final group2 = <({RecordRisk risk, double gap})>[];
  final group3 = <({RecordRisk risk, double gap})>[];
  final group4 = <RecordRisk>[];
  final group5 = <RecordRisk>[];

  for (final record in records) {
    if (!record.isActive || !record.isGiven) continue;

    double? currentCollateralValue;
    final missingRateCategories = <String>{};

    if (record.items.isNotEmpty) {
      double totalCurrentCollateralValue = 0.0;
      for (final item in record.items) {
        final rate = usableRate(rates, item.itemCategory);
        if (rate == null) {
          missingRateCategories.add(item.itemCategory);
        } else {
          totalCurrentCollateralValue += item.fineWeight * rate;
        }
      }

      // [FIX-RATE-USABLE-1] If any item's category has no usable rate,
      // currentCollateralValue is null — NOT a partial sum.
      if (missingRateCategories.isEmpty) {
        currentCollateralValue = totalCurrentCollateralValue;
      } else {
        currentCollateralValue = null;
      }
    } else {
      // Unsecured record: no items
      currentCollateralValue = null;
    }

    final financials = calculateRecordFinancials(record, todayDate);
    final totalDue = financials.totalDue;

    final itemValueAtLending = record.items.fold<double>(
      0.0,
      (s, i) => s + (i.itemValue > 0 ? i.itemValue : calculateItemValue(i)),
    );

    // Projected outstanding at today + 2 months (accrual stops at endDate via accrualEndDate)
    final effectiveProjectedTarget = accrualEndDate(record, projectedTarget);
    final projectedInterest = calculateInterestForPeriod(
      principal: record.principalAmount,
      rate: record.interestRate,
      start: record.startDate.dateOnly,
      end: effectiveProjectedTarget,
    );

    final totalPaid = totalPaidMap[record.id] ?? 0.0;

    final projectedOutstanding =
        math.max(0.0, record.principalAmount + projectedInterest - totalPaid);

    final risk = RecordRisk(
      record: record,
      currentCollateralValue: currentCollateralValue,
      missingRateCategories: missingRateCategories,
      totalDue: totalDue,
      projectedOutstanding: projectedOutstanding,
      itemValueAtLending: itemValueAtLending,
    );

    // Authoritative 5-group classification:
    if (risk.overshoot && risk.collateralDrop) {
      // Group 1: Both OvershootWarning and CollateralDrop triggered simultaneously
      final dropGap = totalDue - currentCollateralValue!;
      final overshootGap = projectedOutstanding - itemValueAtLending;
      final maxGap = math.max(dropGap, overshootGap);
      group1.add((risk: risk, maxGap: maxGap));
    } else if (risk.overshoot) {
      // Group 2: Overshoot only (no collateral drop)
      final overshootGap = projectedOutstanding - itemValueAtLending;
      group2.add((risk: risk, gap: overshootGap));
    } else if (risk.collateralDrop) {
      // Group 3: Collateral drop only (no overshoot)
      final dropGap = totalDue - currentCollateralValue!;
      group3.add((risk: risk, gap: dropGap));
    } else if (risk.missingRateCategories.isNotEmpty) {
      // Group 4: Records with missing rates (informational)
      group4.add(risk);
    } else {
      // Group 5: Safe records (ordered by transactionId)
      group5.add(risk);
    }
  }

  // (1) Sort Group 1 by maxGap descending
  group1.sort((a, b) => b.maxGap.compareTo(a.maxGap));

  // (2) Sort Group 2 by shortfall gap descending
  group2.sort((a, b) => b.gap.compareTo(a.gap));

  // (3) Sort Group 3 by drop gap descending
  group3.sort((a, b) => b.gap.compareTo(a.gap));

  // (5) Sort Group 5 by transactionId
  group5.sort((a, b) => a.record.transactionId.compareTo(b.record.transactionId));

  return [
    ...group1.map((e) => e.risk),
    ...group2.map((e) => e.risk),
    ...group3.map((e) => e.risk),
    ...group4,
    ...group5,
  ];
}

/// Pure projection of the risk list into the alert view: same order as computeRecordRisks(),
/// safe records omitted, records with only a missing rate kept (informational RateMissing).
List<CollectionAlert> alertsFromRisks(List<RecordRisk> risks) => [
  for (final r in risks)
    if (r.atRisk || r.missingRateCategories.isNotEmpty) ...[
      if (r.collateralDrop)
        CollateralDrop(
          record: r.record,
          currentCollateralValue: r.currentCollateralValue!,
          totalDue: r.totalDue,
        ),
      if (r.overshoot)
        OvershootWarning(
          record: r.record,
          projectedOutstanding: r.projectedOutstanding,
          itemValueAtLending: r.itemValueAtLending,
        ),
      for (final c in r.missingRateCategories)
        RateMissing(record: r.record, itemCategory: c),
    ],
];

/// Derived view for notifications and unit tests: one CollateralDrop / OvershootWarning /
/// RateMissing per triggered condition, in the same sort order. Safe records are omitted.
List<CollectionAlert> computeCollectionAlerts({
  required List<LedgerRecord> records,
  required List<ItemRate> rates,
  required DateTime today,
  Map<String, double> totalPaidMap = const {},
}) =>
    alertsFromRisks(computeRecordRisks(
      records: records,
      rates: rates,
      today: today,
      totalPaidMap: totalPaidMap,
    ));
