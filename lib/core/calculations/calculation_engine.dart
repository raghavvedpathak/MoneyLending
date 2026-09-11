import 'dart:math';
import '../../domain/domain.dart';
import 'util/date_extensions.dart';

/// Pure Kotlin / Dart calculation engine (:core:calculations).
///
/// Zero Flutter UI dependencies — 100% deterministic and unit-testable.
/// Mandated by Business Logic Spec §5.1 & §5.2.
class CalculationEngine {
  CalculationEngine._();

  /// Computes itemValue and lendableAmount snapshot (§5.1):
  /// itemValue = weight * (purity / 100) * rate
  /// lendableAmount = itemValue * (lendPercentage / 100)
  static double calculateItemValue(LedgerItem item) {
    if (item.itemValue != null) return item.itemValue!;
    final weight = item.weight ?? 0.0;
    final purity = item.purity ?? 0.0;
    final rate = item.rate ?? 0.0;
    return weight * (purity / 100.0) * rate;
  }

  /// Computes total collateral value across all items in a record
  static double calculateTotalItemValue(List<LedgerItem> items) {
    return items.fold<double>(
      0.0,
      (sum, item) => sum + (item.itemValue ?? calculateItemValue(item)),
    );
  }

  /// Two-branch half-month rounding (§5.2):
  /// - When endDay >= startDay (positive dayDiff):
  ///   * dayDiff > 15 -> +1.0 month
  ///   * dayDiff > 0 -> +0.5 month
  ///   * else -> +0.0 month
  /// - When endDay < startDay (negative dayDiff, month rollover):
  ///   * totalMonths is decremented by 1
  ///   * daysInPrevMonth is computed AFTER totalMonths -= 1 decrement
  ///   * adjustedDays = daysInPrevMonth - startDay + endDay
  ///   * adjustedDays > 15 -> +1.0 month
  ///   * adjustedDays > 0 -> +0.5 month
  ///   * else -> +0.0 month
  static double getMonthsBetween(DateTime start, DateTime end) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);

    if (e.isBefore(s)) return 0.0;

    final years = e.year - s.year;
    final months = e.month - s.month;
    var totalMonths = (years * 12 + months).toDouble();
    final startDay = s.day;
    final endDay = e.day;
    final dayDiff = endDay - startDay;

    if (dayDiff < 0) {
      totalMonths -= 1;
      // daysInPrevMonth must be computed as start.plusMonths(totalMonths) AFTER the decrement:
      final targetMonthIndex = (s.year * 12 + (s.month - 1)) + totalMonths.toInt();
      final targetYear = targetMonthIndex ~/ 12;
      final targetMonth = (targetMonthIndex % 12) + 1;
      final daysInPrevMonth = DateTime(targetYear, targetMonth + 1, 0).day;

      final adjustedDays = daysInPrevMonth - startDay + endDay;
      if (adjustedDays > 15) {
        totalMonths += 1.0;
      } else if (adjustedDays > 0) {
        totalMonths += 0.5;
      }
    } else {
      if (dayDiff > 15) {
        totalMonths += 1.0;
      } else if (dayDiff > 0) {
        totalMonths += 0.5;
      }
    }

    return max(0.0, totalMonths);
  }

  /// Simple interest calculation for period: principal * rate * months / 100
  static double calculateInterestForPeriod(
    double principal,
    double rate,
    DateTime start,
    DateTime end,
  ) {
    final months = getMonthsBetween(start, end);
    return (principal * rate * months) / 100.0;
  }

  /// Splits a payment amount into interest and principal portions using interest-first rule (§5.2.4).
  ///
  /// Outstanding interest is extinguished before any principal is reduced.
  /// [paymentAmount] The amount the customer is paying now (must be > 0).
  /// [outstandingInterest] Current accrued interest minus interest already paid.
  /// Compute via calculateRecordFinancials(record, today).outstandingInterest.
  ///
  /// Returns [PaymentAllocation] Pair(interestPaid, principalPaid).
  static PaymentAllocation allocatePayment(
    double paymentAmount,
    double outstandingInterest,
  ) {
    final safePayment = max(0.0, paymentAmount);
    final safeInterest = max(0.0, outstandingInterest);
    final interestPaid = min(safePayment, safeInterest);
    final principalPaid = safePayment - interestPaid;
    return PaymentAllocation(
      interestPaid: interestPaid,
      principalPaid: principalPaid,
    );
  }

  /// Core ledger engine (§5.1, §5.2.1, & §5.2.2).
  /// Computes financial totals, payments applied, and outstanding balances.
  static Financials calculateRecordFinancials(
    LedgerRecord record,
    DateTime targetDate, [
    DateTime? today,
  ]) {
    final totalPaid = record.payments.fold<double>(
      0.0,
      (sum, p) => sum + p.amount,
    );
    final interestPaid = record.payments.fold<double>(
      0.0,
      (sum, p) => sum + p.interestPaid,
    );
    final principalPaid = record.payments.fold<double>(
      0.0,
      (sum, p) => sum + p.principalPaid,
    );

    // =========================================================================
    // SETTLED FAST-PATH (§5.2.1)
    // =========================================================================
    if (record.isSettled) {
      // 1. Primary fast-path: snapshotted calculatedInterest
      if (record.calculatedInterest != null) {
        final effectiveEnd = record.settledDate ?? targetDate;
        final months = getMonthsBetween(record.startDate, effectiveEnd);
        return Financials(
          totalInterest: record.calculatedInterest!,
          totalPaid: totalPaid,
          interestPaid: interestPaid,
          principalPaid: principalPaid,
          outstandingInterest: 0.0,
          outstandingPrincipal: 0.0,
          totalDue: 0.0,
          principal: record.principalAmount,
          months: months,
        );
      }

      // 2. Edge case: settled with null calculatedInterest (legacy backup import)
      // If settledDate is also null, return zeroed snapshot. NEVER use DateTime.now() in any settled fallback!
      if (record.settledDate == null) {
        final outstandingPrincipal = max(0.0, record.principalAmount - principalPaid);
        return Financials(
          totalInterest: 0.0,
          totalPaid: totalPaid,
          interestPaid: interestPaid,
          principalPaid: principalPaid,
          outstandingInterest: 0.0,
          outstandingPrincipal: outstandingPrincipal,
          totalDue: outstandingPrincipal,
          principal: record.principalAmount,
          months: 0.0,
        );
      }

      // 3. Settled with null calculatedInterest but non-null settledDate:
      // Recalculate using settledDate as targetDate. (Never use DateTime.now())
      final settledTarget = record.settledDate!;
      final months = getMonthsBetween(record.startDate, settledTarget);
      final totalInterest = calculateInterestForPeriod(
        record.principalAmount,
        record.interestRate,
        record.startDate,
        settledTarget,
      );
      final remainingInterest = max(0.0, totalInterest - interestPaid);
      final remainingPrincipal = max(0.0, record.principalAmount - principalPaid);
      final totalDue = remainingPrincipal + remainingInterest;

      return Financials(
        totalInterest: totalInterest,
        totalPaid: totalPaid,
        interestPaid: interestPaid,
        principalPaid: principalPaid,
        outstandingInterest: remainingInterest,
        outstandingPrincipal: remainingPrincipal,
        totalDue: totalDue,
        principal: record.principalAmount,
        months: months,
      );
    }

    // =========================================================================
    // ACTIVE RECORDS (§5.2.2 Full Algorithm)
    // =========================================================================
    // Step 1: Determine effective target date.
    // Use endDate?.takeIf { !it.isAfter(LocalDate.now()) } since endDate is LocalDate? in domain model.
    final now = today ?? DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final targetDateOnly = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final effectiveTarget = (record.endDate != null && !record.endDate!.isAfter(todayDate))
        ? DateTime(record.endDate!.year, record.endDate!.month, record.endDate!.day)
        : targetDateOnly;

    // Step 2: Calculate total accrued interest [FIX-TIMESTAMP-CALC-1]
    // startDate is LocalDateTime — extract date component for interest period calculation
    final startDateOnly = DateTime(record.startDate.year, record.startDate.month, record.startDate.day);
    final months = getMonthsBetween(startDateOnly, effectiveTarget);
    final totalInterest = calculateInterestForPeriod(
      record.principalAmount,
      record.interestRate,
      startDateOnly,
      effectiveTarget,
    );

    // Step 3: Sum payments (already split by interest-first allocation at recording time).
    // interestPaid, principalPaid, and totalPaid are aggregated above.

    // Step 4: Derive outstanding amounts (floored at 0 — no negative balances).
    final outstandingInterest = max(0.0, totalInterest - interestPaid);
    final outstandingPrincipal = max(0.0, record.principalAmount - principalPaid);
    final totalDue = outstandingPrincipal + outstandingInterest;

    return Financials(
      totalInterest: totalInterest,
      totalPaid: totalPaid,
      interestPaid: interestPaid,
      principalPaid: principalPaid,
      outstandingInterest: outstandingInterest,
      outstandingPrincipal: outstandingPrincipal,
      totalDue: totalDue,
      principal: record.principalAmount,
      months: months,
    );
  }

  /// Aggregates summary cards statistics across all active records (§5.1).
  /// TargetDate logic: record.endDate?.takeIf { !it.isAfter(today) } ?: today
  static DashboardStats getDashboard(
    List<LedgerRecord> records, [
    DateTime? today,
  ]) {
    final now = today ?? DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    double totalPrincipalGiven = 0.0;
    double totalInterestAccruedGiven = 0.0;
    double totalDueGiven = 0.0;

    double totalPrincipalTaken = 0.0;
    double totalInterestAccruedTaken = 0.0;
    double totalDueTaken = 0.0;

    for (final r in records) {
      if (!r.isActive) continue;

      final targetDate = (r.endDate != null && !r.endDate!.isAfter(todayDate))
          ? r.endDate!
          : todayDate;

      final fin = calculateRecordFinancials(r, targetDate);

      if (r.isGiven) {
        totalPrincipalGiven += r.principalAmount;
        totalInterestAccruedGiven += fin.totalInterest;
        totalDueGiven += fin.totalDue;
      } else if (r.isTaken) {
        totalPrincipalTaken += r.principalAmount;
        totalInterestAccruedTaken += fin.totalInterest;
        totalDueTaken += fin.totalDue;
      }
    }

    return DashboardStats(
      totalPrincipalGiven: totalPrincipalGiven,
      totalInterestAccruedGiven: totalInterestAccruedGiven,
      totalDueGiven: totalDueGiven,
      totalPrincipalTaken: totalPrincipalTaken,
      totalInterestAccruedTaken: totalInterestAccruedTaken,
      totalDueTaken: totalDueTaken,
    );
  }

  /// Per-customer rollup for the Reports screen Overview tab (§5.1).
  static List<CustomerReport> getCustomerReport(
    List<Customer> customers,
    List<LedgerRecord> records, [
    DateTime? today,
  ]) {
    final now = today ?? DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    return customers.map((customer) {
      final customerRecords = records
          .where((r) => r.customerId == customer.id && r.isActive && r.isGiven)
          .toList();

      double totalPrincipal = 0.0;
      double totalInterest = 0.0;
      double totalDue = 0.0;

      for (final r in customerRecords) {
        final target = (r.endDate != null && !r.endDate!.isAfter(todayDate))
            ? r.endDate!
            : todayDate;
        final fin = calculateRecordFinancials(r, target);
        totalPrincipal += r.principalAmount;
        totalInterest += fin.totalInterest;
        totalDue += fin.totalDue;
      }

      return CustomerReport(
        customer: customer,
        activeRecordCount: customerRecords.length,
        totalPrincipal: totalPrincipal,
        totalInterestAccrued: totalInterest,
        totalDue: totalDue,
      );
    }).toList();
  }

  /// CASH-BASIS: counts only interest actually PAID (payment.interestPaid > 0), not accrued (§5.1).
  /// Groups payments by calendar month. UI label MUST say "Interest Received" not "Interest Accrued".
  /// [FIX-TIMESTAMP-MONTHLYINTEREST-1]: Derives year and month from payment.date component.
  static List<MonthlyEarning> getMonthlyInterest(List<LedgerRecord> records) {
    final Map<String, double> earningsMap = {};

    for (final r in records) {
      for (final p in r.payments) {
        if (p.interestPaid > 0) {
          final key = '${p.date.year}-${p.date.month.toString().padLeft(2, '0')}';
          earningsMap[key] = (earningsMap[key] ?? 0.0) + p.interestPaid;
        }
      }
    }

    final sortedKeys = earningsMap.keys.toList()..sort();

    return sortedKeys.map((key) {
      final parts = key.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      return MonthlyEarning(
        year: year,
        month: month,
        interestReceived: earningsMap[key] ?? 0.0,
      );
    }).toList();
  }

  /// Activity-based overdue records (§5.1 & §8).
  /// Threshold in days (defaults to 30).
  /// Falls back to record.startDate if no payment exists.
  static List<OverdueRecord> getOverdue(
    List<LedgerRecord> records,
    Map<String, DateTime?> latestPaymentDates,
    DateTime today, {
    int thresholdDays = 30,
  }) {
    final todayDate = DateTime(today.year, today.month, today.day);
    final overdueList = <OverdueRecord>[];

    for (final r in records) {
      if (!r.isActive) continue;

      final rawLast = latestPaymentDates[r.id];
      final DateTime lastActivityDate = rawLast != null
          ? DateTime(rawLast.year, rawLast.month, rawLast.day)
          : DateTime(r.startDate.year, r.startDate.month, r.startDate.day);

      // ChronoUnit.DAYS.between(lastActivityDate, todayDate) equivalent (§5.2.3)
      final daysSinceActivity = daysBetween(lastActivityDate, todayDate);

      if (daysSinceActivity > thresholdDays) {
        overdueList.add(OverdueRecord(
          record: r,
          daysSinceActivity: daysSinceActivity,
          lastActivityDate: lastActivityDate,
        ));
      }
    }

    // Sort descending by days of inactivity
    overdueList.sort((a, b) => b.daysSinceActivity.compareTo(a.daysSinceActivity));
    return overdueList;
  }

  /// Computes Collection Alerts for ACTIVE GIVEN records (§5.3).
  ///
  /// Evaluates:
  /// - CollateralDrop: currentCollateralValue <= financials.totalDue.
  /// - OvershootWarning: projectedOutstanding in 2 months > itemValueAtLending.
  /// - RateMissing: item category with no rate on file (excluded from collateral sum).
  ///
  /// [FIX-COLLALERT-TOTALPAID-1]: [totalPaidMap] defaults to emptyMap for unit test convenience,
  /// but MUST be supplied by production call sites (DashboardViewModel and Worker).
  ///
  /// Sort order:
  /// 1. Both OvershootWarning & CollateralDrop triggered, sorted by max(overshootGap, dropGap) descending.
  /// 2. OvershootWarning only, sorted by shortfall gap descending.
  /// 3. CollateralDrop only, sorted by drop gap descending.
  /// 4. RateMissing last (informational).
  static List<CollectionAlert> computeCollectionAlerts(
    List<LedgerRecord> records,
    List<ItemRate> rates, [
    Map<String, double> totalPaidMap = const {},
    DateTime? today,
  ]) {
    final now = today ?? DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    // IMPORTANT: totalPaid is always sourced from the totalPaidMap parameter.
    // Do NOT use record.payments.sumOf{} here — it would bypass the pre-computed
    // aggregates and break the Worker path (which passes a pre-fetched map).

    // Map rates by uppercase category string for fast lookups
    final rateMap = <String, ItemRate>{};
    for (final rate in rates) {
      rateMap[rate.itemCategory.trim().toUpperCase()] = rate;
    }

    final group1 = <({LedgerRecord record, List<CollectionAlert> alerts, double maxGap})>[];
    final group2 = <({LedgerRecord record, OvershootWarning alert, double gap})>[];
    final group3 = <({LedgerRecord record, CollateralDrop alert, double gap})>[];
    final group4 = <RateMissing>[];

    for (final record in records) {
      if (!record.isActive || !record.isGiven) continue;

      double totalCurrentCollateralValue = 0.0;
      double itemValueAtLending = 0.0;
      final recordRateMissing = <RateMissing>[];

      int pricedItemCount = 0;

      for (final item in record.items) {
        itemValueAtLending += (item.itemValue ?? calculateItemValue(item));
        final normCategory = item.itemCategory.trim().toUpperCase();
        final rate = rateMap[normCategory];

        if (rate == null) {
          recordRateMissing.add(RateMissing(
            record: record,
            itemCategory: item.itemCategory,
          ));
          // Exclude item from numeric sum rather than zeroing it silently (§5.3)
        } else {
          pricedItemCount++;
          final weight = item.weight ?? 0.0;
          final purity = item.purity ?? 0.0;
          final ratePerUnit = rate.ratePerUnit;
          totalCurrentCollateralValue += weight * (purity / 100.0) * ratePerUnit;
        }
      }

      group4.addAll(recordRateMissing);

      final fin = calculateRecordFinancials(record, todayDate, todayDate);

      // Alert 1: Collateral Drop
      // Compare totalCurrentCollateralValue <= financials.totalDue — NOT record.principalAmount!
      // Evaluated only when there are priced items (otherwise rate missing is reported, not false drop)
      final hasCollateralDrop = pricedItemCount > 0 &&
          (totalCurrentCollateralValue <= fin.totalDue);
      final dropGap = fin.totalDue - totalCurrentCollateralValue;
      final dropAlert = hasCollateralDrop
          ? CollateralDrop(
              record: record,
              currentCollateralValue: totalCurrentCollateralValue,
              totalDue: fin.totalDue,
            )
          : null;

      // Alert 3: Overshoot Warning (in 2 months)
      final projectedTarget = DateTime(todayDate.year, todayDate.month + 2, todayDate.day);
      final projectedInterest = calculateInterestForPeriod(
        record.principalAmount,
        record.interestRate,
        record.startDate,
        projectedTarget,
      );
      // [FIX-TOTALPAID-SOURCE]: totalPaid is strictly sourced from totalPaidMap, defaulting to 0.0
      final totalPaid = totalPaidMap[record.id] ?? 0.0;
      final projectedOutstanding = record.principalAmount + projectedInterest - totalPaid;

      // Overshoot condition (§5.4): projectedOutstanding >= itemValueAtLending
      final hasOvershoot = itemValueAtLending > 0 && (projectedOutstanding >= itemValueAtLending);
      final overshootGap = projectedOutstanding - itemValueAtLending;
      final overshootAlert = hasOvershoot
          ? OvershootWarning(
              record: record,
              projectedOutstanding: projectedOutstanding,
              itemValueAtLending: itemValueAtLending,
            )
          : null;

      if (hasOvershoot && hasCollateralDrop) {
        // Group 1: Both triggered simultaneously
        final maxGap = max(overshootGap, dropGap);
        group1.add((
          record: record,
          alerts: [overshootAlert!, dropAlert!],
          maxGap: maxGap,
        ));
      } else if (hasOvershoot) {
        // Group 2: Overshoot only
        group2.add((
          record: record,
          alert: overshootAlert!,
          gap: overshootGap,
        ));
      } else if (hasCollateralDrop) {
        // Group 3: Collateral drop only
        group3.add((
          record: record,
          alert: dropAlert!,
          gap: dropGap,
        ));
      }
    }

    // Sort Group 1 by maxGap descending
    group1.sort((a, b) => b.maxGap.compareTo(a.maxGap));

    // Sort Group 2 by shortfall gap descending
    group2.sort((a, b) => b.gap.compareTo(a.gap));

    // Sort Group 3 by drop gap descending
    group3.sort((a, b) => b.gap.compareTo(a.gap));

    final result = <CollectionAlert>[];
    for (final item in group1) {
      result.addAll(item.alerts);
    }
    for (final item in group2) {
      result.add(item.alert);
    }
    for (final item in group3) {
      result.add(item.alert);
    }
    result.addAll(group4);

    return result;
  }

  /// Computes Unified Collection Alert Card models for all ACTIVE GIVEN records (§5.4).
  ///
  /// Each card contains both the live collateral-drop evaluation AND the 2-month
  /// forward overshoot projection side-by-side on a single card.
  /// Records are sorted with triggered cards first (following 4-group risk ordering),
  /// followed by safe cards.
  static List<CollectionAlertCardData> computeCollectionAlertCards(
    List<LedgerRecord> records,
    List<ItemRate> rates, [
    Map<String, double> totalPaidMap = const {},
    DateTime? today,
  ]) {
    final now = today ?? DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    final rateMap = <String, ItemRate>{};
    for (final rate in rates) {
      rateMap[rate.itemCategory.trim().toUpperCase()] = rate;
    }

    final cardDataList = <CollectionAlertCardData>[];

    for (final record in records) {
      if (!record.isActive || !record.isGiven) continue;

      double totalCurrentCollateralValue = 0.0;
      double itemValueAtLending = 0.0;
      final missingCategories = <String>[];
      int pricedItemCount = 0;

      for (final item in record.items) {
        itemValueAtLending += (item.itemValue ?? calculateItemValue(item));
        final normCategory = item.itemCategory.trim().toUpperCase();
        final rate = rateMap[normCategory];

        if (rate == null) {
          missingCategories.add(item.itemCategory);
        } else {
          pricedItemCount++;
          final weight = item.weight ?? 0.0;
          final purity = item.purity ?? 0.0;
          final ratePerUnit = rate.ratePerUnit;
          totalCurrentCollateralValue += weight * (purity / 100.0) * ratePerUnit;
        }
      }

      final fin = calculateRecordFinancials(record, todayDate, todayDate);

      final isCollateralUnderwater = pricedItemCount > 0 &&
          (totalCurrentCollateralValue <= fin.totalDue);

      final projectedTarget = DateTime(todayDate.year, todayDate.month + 2, todayDate.day);
      final projectedInterest = calculateInterestForPeriod(
        record.principalAmount,
        record.interestRate,
        record.startDate,
        projectedTarget,
      );
      final totalPaid = totalPaidMap[record.id] ?? 0.0;
      final projectedOutstanding = record.principalAmount + projectedInterest - totalPaid;

      final isOvershoot = itemValueAtLending > 0 && (projectedOutstanding >= itemValueAtLending);

      cardDataList.add(CollectionAlertCardData(
        record: record,
        currentCollateralValue: totalCurrentCollateralValue,
        totalDue: fin.totalDue,
        isCollateralUnderwater: isCollateralUnderwater,
        projectedOutstanding: projectedOutstanding,
        itemValueAtLending: itemValueAtLending,
        isOvershoot: isOvershoot,
        hasMissingRate: missingCategories.isNotEmpty,
        missingRateCategories: missingCategories,
      ));
    }

    // Sort cards: triggered first, followed by safe
    cardDataList.sort((a, b) {
      if (a.isTriggered && !b.isTriggered) return -1;
      if (!a.isTriggered && b.isTriggered) return 1;

      // When both triggered, rank by largest severity gap
      if (a.isTriggered && b.isTriggered) {
        final aGap = max(a.totalDue - a.currentCollateralValue, a.projectedOutstanding - a.itemValueAtLending);
        final bGap = max(b.totalDue - b.currentCollateralValue, b.projectedOutstanding - b.itemValueAtLending);
        return bGap.compareTo(aGap);
      }

      return 0;
    });

    return cardDataList;
  }
}

// Top-level function exports for clean idiomatic usage
double calculateItemValue(LedgerItem item) => CalculationEngine.calculateItemValue(item);
double calculateTotalItemValue(List<LedgerItem> items) => CalculationEngine.calculateTotalItemValue(items);
double getMonthsBetween(DateTime start, DateTime end) => CalculationEngine.getMonthsBetween(start, end);
double calculateInterestForPeriod(double principal, double rate, DateTime start, DateTime end) =>
    CalculationEngine.calculateInterestForPeriod(principal, rate, start, end);
Financials calculateRecordFinancials(LedgerRecord record, DateTime targetDate, [DateTime? today]) =>
    CalculationEngine.calculateRecordFinancials(record, targetDate, today);
DashboardStats getDashboard(List<LedgerRecord> records, [DateTime? today]) =>
    CalculationEngine.getDashboard(records, today);
List<CustomerReport> getCustomerReport(List<Customer> customers, List<LedgerRecord> records, [DateTime? today]) =>
    CalculationEngine.getCustomerReport(customers, records, today);
List<MonthlyEarning> getMonthlyInterest(List<LedgerRecord> records) =>
    CalculationEngine.getMonthlyInterest(records);
List<OverdueRecord> getOverdue(
  List<LedgerRecord> records,
  Map<String, DateTime?> latestPaymentDates,
  DateTime today, {
  int thresholdDays = 30,
}) =>
    CalculationEngine.getOverdue(records, latestPaymentDates, today, thresholdDays: thresholdDays);
PaymentAllocation allocatePayment(double paymentAmount, double outstandingInterest) =>
    CalculationEngine.allocatePayment(paymentAmount, outstandingInterest);
List<CollectionAlert> computeCollectionAlerts(
  List<LedgerRecord> records,
  List<ItemRate> rates, [
  Map<String, double> totalPaidMap = const {},
  DateTime? today,
]) =>
    CalculationEngine.computeCollectionAlerts(records, rates, totalPaidMap, today);
List<CollectionAlertCardData> computeCollectionAlertCards(
  List<LedgerRecord> records,
  List<ItemRate> rates, [
  Map<String, double> totalPaidMap = const {},
  DateTime? today,
]) =>
    CalculationEngine.computeCollectionAlertCards(records, rates, totalPaidMap, today);

/// Result of interest-first payment allocation (§5.2.4).
///
/// Implements `Pair<Double, Double>` contract:
/// - [interestPaid]: Portion of payment applied to outstanding accrued interest.
/// - [principalPaid]: Portion of payment applied to outstanding principal.
class PaymentAllocation {
  final double interestPaid;
  final double principalPaid;

  const PaymentAllocation({
    required this.interestPaid,
    required this.principalPaid,
  });

  /// Pair / tuple compatibility: val (interestPaid, principalPaid) = allocatePayment(...)
  double get first => interestPaid;
  double get second => principalPaid;

  /// Dart 3 record representation: (interestPaid, principalPaid)
  (double, double) get asRecord => (interestPaid, principalPaid);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentAllocation &&
          runtimeType == other.runtimeType &&
          interestPaid == other.interestPaid &&
          principalPaid == other.principalPaid;

  @override
  int get hashCode => Object.hash(interestPaid, principalPaid);

  @override
  String toString() => 'PaymentAllocation(interestPaid: $interestPaid, principalPaid: $principalPaid)';
}
