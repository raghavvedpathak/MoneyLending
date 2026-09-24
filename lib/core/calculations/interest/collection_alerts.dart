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

/// [FIX-SORT-1] (Addendum J.9) Compares transaction IDs by their numeric sequence
/// rather than lexicographical text so that "TRAN092699" sorts before "TRAN0926100"
/// and "TXN-005" sorts before "TXN-010".
int compareTransactionSequence(String a, String b) {
  // If transaction IDs follow the canonical TRAN<MM><YY><SEQ> pattern (>= 9 chars)
  if (a.startsWith('TRAN') && b.startsWith('TRAN') && a.length >= 9 && b.length >= 9) {
    final prefixA = a.substring(0, 8); // "TRANMMYY"
    final prefixB = b.substring(0, 8);
    if (prefixA == prefixB) {
      final seqA = int.tryParse(a.substring(8));
      final seqB = int.tryParse(b.substring(8));
      if (seqA != null && seqB != null) {
        return seqA.compareTo(seqB);
      }
    }
  }

  // General format: compare prefix and trailing integer sequence (e.g. TXN-005 vs TXN-010)
  final matchA = RegExp(r'^(.*?)(\d+)$').firstMatch(a);
  final matchB = RegExp(r'^(.*?)(\d+)$').firstMatch(b);
  if (matchA != null && matchB != null) {
    final prefixA = matchA.group(1);
    final prefixB = matchB.group(1);
    if (prefixA == prefixB) {
      final numA = int.tryParse(matchA.group(2)!);
      final numB = int.tryParse(matchB.group(2)!);
      if (numA != null && numB != null) {
        return numA.compareTo(numB);
      }
    }
  }

  return a.compareTo(b);
}

/// computeRecordRisks() — the single pure function behind the Dashboard card, the Risk
/// Summary and the daily overshoot notification (§5.3 & [FIX-RISK-VIEWMODEL-1]).
///
/// [FIX-CLOCK-1] `today` is injected (already .dateOnly) — the function never reads the clock.
/// [FIX-REMOVE-TOTALPAID-1] (v1.16) Every record is FULL ([FIX-PERF-EAGERLOAD-2]),
/// so projectedOutstanding reads calculateRecordFinancials(record, projectionDate).totalDue.
/// Optional [totalPaidMap] is retained for backward compatibility with isolated unit tests.
List<RecordRisk> computeRecordRisks({
  required List<LedgerRecord> records, // ACTIVE GIVEN records, FULL ([FIX-PERF-EAGERLOAD-2])
  required List<ItemRate> rates,
  required DateTime today,
  Map<String, double>? totalPaidMap,
}) {
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
      final itemMarketValues = <double>[];
      for (final item in record.items) {
        final rate = usableRate(rates, item.itemCategory);
        if (rate == null) {
          missingRateCategories.add(item.itemCategory);
        } else {
          // [FIX-MONEY-1] liveItemValue(item, rate) = roundMoney(item.weight * (item.purity / 100) * rate)
          itemMarketValues.add(liveItemValue(item, rate));
        }
      }

      // [FIX-RATE-USABLE-1] If any item's category has no usable rate,
      // currentCollateralValue is null — NOT a partial sum.
      if (missingRateCategories.isEmpty) {
        currentCollateralValue = sumMoney(itemMarketValues);
      } else {
        currentCollateralValue = null;
      }
    } else {
      // Unsecured record: no items
      currentCollateralValue = null;
    }

    final financials = calculateRecordFinancials(record, todayDate);
    final totalDue = financials.totalDue;

    final itemValueAtLending = sumMoney(
      record.items.map((i) => i.itemValue > 0 ? i.itemValue : calculateItemValue(i)),
    );

    // [FIX-REMOVE-TOTALPAID-1] (v1.16)
    // If totalPaidMap is supplied (e.g. legacy/isolated unit test), use it.
    // Otherwise, calculateRecordFinancials(record, projectedTarget).totalDue is the single source of truth.
    final double projectedOutstanding;
    if (totalPaidMap != null) {
      final effectiveProjectedTarget = accrualEndDate(record, projectedTarget);
      final projectedInterest = calculateInterestForPeriod(
        principal: record.principalAmount,
        rate: record.interestRate,
        start: record.startDate.dateOnly,
        end: effectiveProjectedTarget,
      );
      final totalPaid = totalPaidMap[record.id] ?? 0.0;
      projectedOutstanding = roundMoney(
        math.max(0.0, record.principalAmount + projectedInterest - totalPaid),
      );
    } else {
      projectedOutstanding = calculateRecordFinancials(record, projectedTarget).totalDue;
    }

    final risk = RecordRisk(
      record: record,
      currentCollateralValue: currentCollateralValue,
      missingRateCategories: missingRateCategories,
      totalDue: totalDue,
      projectedOutstanding: projectedOutstanding,
      itemValueAtLending: itemValueAtLending,
    );

    // Authoritative 5-group classification (§5.3):
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
      // Group 5: Safe records (ordered by startDate ascending, then transaction sequence)
      group5.add(risk);
    }
  }

  // (1) Sort Group 1 by maxGap descending
  group1.sort((a, b) => b.maxGap.compareTo(a.maxGap));

  // (2) Sort Group 2 by shortfall gap descending
  group2.sort((a, b) => b.gap.compareTo(a.gap));

  // (3) Sort Group 3 by drop gap descending
  group3.sort((a, b) => b.gap.compareTo(a.gap));

  // (5) Sort Group 5: oldest first (startDate ascending), then numeric sequence ([FIX-SORT-1], Addendum J.9)
  group5.sort((a, b) {
    final dateCmp = a.record.startDate.compareTo(b.record.startDate);
    if (dateCmp != 0) return dateCmp;
    return compareTransactionSequence(a.record.transactionId, b.record.transactionId);
  });

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
  Map<String, double>? totalPaidMap,
}) =>
    alertsFromRisks(computeRecordRisks(
      records: records,
      rates: rates,
      today: today,
      totalPaidMap: totalPaidMap,
    ));
