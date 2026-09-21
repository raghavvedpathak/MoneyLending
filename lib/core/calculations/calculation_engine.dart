import 'dart:math';
import '../../domain/domain.dart';
import 'interest/accrual_end_date.dart';
import 'interest/allocate_payment.dart' as alloc;
import 'interest/collection_alerts.dart' as coll_alerts;
import 'interest/months_between.dart' as mb;
import 'interest/months_between.dart' show addMonths;
import 'util/date_extensions.dart';

export 'interest/accrual_end_date.dart';
export 'interest/allocate_payment.dart';
export 'interest/collection_alerts.dart';
export 'interest/months_between.dart';

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
    if (item.itemValue > 0) return item.itemValue;
    return item.weight * (item.purity / 100.0) * item.rate;
  }

  /// Computes total collateral value across all items in a record (§5.1)
  static double calculateTotalItemValue(List<LedgerItem> items) {
    return items.fold<double>(
      0.0,
      (sum, item) => sum + (item.itemValue > 0 ? item.itemValue : calculateItemValue(item)),
    );
  }

  /// Two-branch half-month rounding (§5.2).
  /// Canonical implementation in interest/months_between.dart.
  /// Both parameters MUST already be .dateOnly-truncated at the call site.
  static double getMonthsBetween(DateTime start, DateTime end) =>
      mb.getMonthsBetween(start, end);

  /// Simple interest calculation for period: principal * rate * months / 100 (§5.1)
  static double calculateInterestForPeriod({
    required double principal,
    required double rate,
    required DateTime start,
    required DateTime end,
  }) {
    final months = getMonthsBetween(start, end);
    return (principal * rate * months) / 100.0;
  }

  /// Splits a payment amount into interest and principal portions using interest-first rule (§5.2.4).
  ///
  /// Outstanding interest is extinguished before any principal is reduced (§5.2.4).
  /// [paymentAmount] The amount the customer is paying now.
  /// [outstandingInterest] Current accrued interest minus interest already paid.
  /// Compute via calculateRecordFinancials(record, today).outstandingInterest.
  ///
  /// Returns [PaymentAllocation] Pair(interestPaid, principalPaid).
  static (double interestPaid, double principalPaid) allocatePayment(
    double paymentAmount,
    double outstandingInterest,
  ) =>
      alloc.allocatePayment(
        paymentAmount: paymentAmount,
        outstandingInterest: outstandingInterest,
      );

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
          overpaymentAmount: max(0.0, principalPaid - record.principalAmount),
          principal: record.principalAmount,
          months: months,
        );
      }

      // 2. Edge case: settled with null calculatedInterest (legacy backup import)
      // record.settledDate is DateTime? in the domain model — no string parsing needed.
      // Just use the value directly; null means no settledDate on file.
      final settledTarget = record.settledDate;
      if (settledTarget == null) {
        final principalPaidSoFar =
            record.payments.fold(0.0, (s, p) => s + p.principalPaid);
        // [FIX-FINANCIALS-OVERPAY-1] compute the raw (unfloored) delta once so
        // both outstandingPrincipal and overpaymentAmount derive from the same number —
        // flooring it twice in two different directions must never drift apart.
        final rawOutstandingPrincipal = record.principalAmount - principalPaidSoFar;
        return Financials(
          totalInterest: 0.0,
          totalPaid: record.payments.fold(0.0, (s, p) => s + p.amount),
          // BLK-10 FIX equivalent: all 8 fields must be supplied
          interestPaid: record.payments.fold(0.0, (s, p) => s + p.interestPaid),
          principalPaid: principalPaidSoFar,
          outstandingInterest: 0.0,
          outstandingPrincipal: max(0.0, rawOutstandingPrincipal),
          totalDue: max(0.0, rawOutstandingPrincipal),
          overpaymentAmount: max(0.0, -rawOutstandingPrincipal),
          principal: record.principalAmount,
          months: 0.0,
        ); // never use DateTime.now() for settled records
      }

      // 3. Settled with null calculatedInterest but non-null settledDate:
      // If settledDate is non-null, use it as targetDate. (Never use DateTime.now())
      final months = getMonthsBetween(record.startDate, settledTarget);
      final totalInterest = calculateInterestForPeriod(
        principal: record.principalAmount,
        rate: record.interestRate,
        start: record.startDate,
        end: settledTarget,
      );
      final remainingInterest = max(0.0, totalInterest - interestPaid);
      final rawOutstandingPrincipal = record.principalAmount - principalPaid;
      final remainingPrincipal = max(0.0, rawOutstandingPrincipal);
      final totalDue = remainingPrincipal + remainingInterest;

      return Financials(
        totalInterest: totalInterest,
        totalPaid: totalPaid,
        interestPaid: interestPaid,
        principalPaid: principalPaid,
        outstandingInterest: remainingInterest,
        outstandingPrincipal: remainingPrincipal,
        totalDue: totalDue,
        overpaymentAmount: max(0.0, -rawOutstandingPrincipal),
        principal: record.principalAmount,
        months: months,
      );
    }

    // =========================================================================
    // ACTIVE RECORDS (§5.2.2 Full Algorithm)
    // =========================================================================
    // Step 1: Determine effective target date. [FIX-ACCRUAL-END-1] (v1.14) One
    // min(endDate, targetDate) rule for every caller via the shared helper — no hidden
    // DateTime.now(), so this function is pure and projections respect endDate too.
    final targetDateOnly = targetDate.dateOnly;
    final effectiveTarget = accrualEndDate(record, targetDateOnly);

    // Step 2: Calculate total accrued interest.
    final totalInterest = calculateInterestForPeriod(
      principal: record.principalAmount,
      rate: record.interestRate,
      start: record.startDate.dateOnly, // ⚠️ [FIX-TIMESTAMP-CALC-1] startDate is a "datetime" field — truncate to date-only for interest period calculation
      end: effectiveTarget,
    );

    // Step 3: Sum payments (already split by interest-first allocation at recording time).
    // interestPaid, principalPaid, and totalPaid are aggregated above.

    // Step 4: Outstanding amounts. ⚠️ [FIX-FINANCIALS-OVERPAY-1] Each raw delta is
    // floored at zero individually for outstandingInterest/outstandingPrincipal (an
    // amount "still owed" can never display as negative) — but summing those two
    // already-floored components can never reveal that the customer overpaid, because
    // each floor discards its own negative remainder before the sum happens. Keep the
    // raw deltas around so overpaymentAmount can be derived from them directly.
    final rawOutstandingInterest = totalInterest - interestPaid;
    final rawOutstandingPrincipal = record.principalAmount - principalPaid;
    final outstandingInterest = max(0.0, rawOutstandingInterest);
    final outstandingPrincipal = max(0.0, rawOutstandingPrincipal);

    // [FIX-FINANCIALS-NET-1] (v1.14) totalDue nets the two raw deltas BEFORE flooring, so
    // interest paid in excess of interest accrued (e.g. after the rate is edited down)
    // credits against principal still owed. Only the SUM is floored at zero.
    final netOutstanding = rawOutstandingInterest + rawOutstandingPrincipal;
    final overpaymentAmount = max(0.0, -netOutstanding);

    return Financials(
      totalInterest: totalInterest,
      totalPaid: totalPaid,
      interestPaid: interestPaid,
      principalPaid: principalPaid,
      outstandingInterest: outstandingInterest,
      outstandingPrincipal: outstandingPrincipal,
      totalDue: max(0.0, netOutstanding),
      overpaymentAmount: overpaymentAmount,
      principal: record.principalAmount,
      months: getMonthsBetween(record.startDate.dateOnly, effectiveTarget),
    );
  }

  /// Aggregates summary cards statistics across all active records (§5.1).
  /// [FIX-CLOCK-1] targetDate = the injected today (already .dateOnly).
  /// calculateRecordFinancials() applies the endDate cap itself through accrualEndDate() (§5.2.2),
  /// so getDashboard needs no per-caller targetDate logic and never reads the clock.
  static DashboardStats getDashboard(
    List<LedgerRecord> records, {
    required DateTime today,
  }) {
    final todayDate = DateTime(today.year, today.month, today.day);

    double totalPrincipalGiven = 0.0;
    double totalInterestAccruedGiven = 0.0;
    double totalDueGiven = 0.0;

    double totalPrincipalTaken = 0.0;
    double totalInterestAccruedTaken = 0.0;
    double totalDueTaken = 0.0;

    for (final r in records) {
      if (!r.isActive) continue;

      final fin = calculateRecordFinancials(r, todayDate);

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
    List<LedgerRecord> records, {
    required DateTime today,
  }) {
    final todayDate = DateTime(today.year, today.month, today.day);

    return customers.map((customer) {
      final customerRecords = records
          .where((r) => r.customerId == customer.id && r.isActive && r.isGiven)
          .toList();

      double totalPrincipal = 0.0;
      double totalInterest = 0.0;
      double totalDue = 0.0;

      for (final r in customerRecords) {
        final fin = calculateRecordFinancials(r, todayDate);
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
        month: DateTime(year, month, 1),
        interestReceived: earningsMap[key] ?? 0.0,
      );
    }).toList();
  }

  /// Activity-based overdue records (§5.1 & §8).
  /// Threshold in days (defaults to 30).
  /// Falls back to record.startDate if no payment exists.
  ///
  /// Mandated by §4.4 & §8: Always guard for null endDate in overdue queries:
  /// open-ended loans have endDate = null. The overdue query must NOT use endDate
  /// at all — uses activity-based overdue logic instead.
  static List<OverdueRecord> getOverdue({
    required List<LedgerRecord> records,
    required Map<String, DateTime?> latestPaymentDates,
    required DateTime today,
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

      // Flag as overdue if that gap >= thresholdDays (30) (§8)
      if (daysSinceActivity >= thresholdDays) {
        overdueList.add(OverdueRecord(
          record: r,
          reasons: const {OverdueReason.noActivity},
          daysSinceActivity: daysSinceActivity,
          lastActivityDate: lastActivityDate,
        ));
      }
    }

    // Sort descending by days of inactivity
    overdueList.sort((a, b) => (b.daysSinceActivity ?? 0).compareTo(a.daysSinceActivity ?? 0));
    return overdueList;
  }

  /// [FIX-OVERDUECOLLATERAL-1] Live-rate based overdue calculation across ALL ACTIVE records (GIVEN + TAKEN).
  ///
  /// Evaluates:
  /// - collateralBreachedNow: currentCollateralValue < financials.totalDue.
  /// - collateralProjected2Months: currentCollateralValue < projected financials.totalDue in 2 months.
  ///
  /// [FIX-OVERDUE-RATES-1] Records with no items, or with ANY item whose category has no usable rate
  /// (missing or 0.0), are skipped — not flagged.
  static List<OverdueRecord> computeCollateralOverdue({
    required List<LedgerRecord> records,
    required List<ItemRate> rates,
    required DateTime today,
  }) {
    final todayDate = DateTime(today.year, today.month, today.day);
    final projectedTarget = addMonths(todayDate, 2);

    final result = <OverdueRecord>[];

    for (final record in records) {
      if (!record.isActive) continue;

      // [FIX-OVERDUE-RATES-1]: Skip records with no items
      if (record.items.isEmpty) continue;

      double totalCurrentCollateralValue = 0.0;
      bool hasUnusableRate = false;

      for (final item in record.items) {
        final rate = coll_alerts.usableRate(rates, item.itemCategory);
        if (rate == null || rate <= 0.0) {
          hasUnusableRate = true;
          break;
        }
        totalCurrentCollateralValue += item.fineWeight * rate;
      }

      // [FIX-OVERDUE-RATES-1]: Skip records if any item category lacks a usable rate (> 0.0)
      if (hasUnusableRate) continue;

      final finNow = calculateRecordFinancials(record, todayDate);
      final finProjected = calculateRecordFinancials(record, projectedTarget);

      final reasons = <OverdueReason>{};
      if (totalCurrentCollateralValue < finNow.totalDue) {
        reasons.add(OverdueReason.collateralBreachedNow);
      }
      if (totalCurrentCollateralValue < finProjected.totalDue) {
        reasons.add(OverdueReason.collateralProjected2Months);
      }

      if (reasons.isNotEmpty) {
        result.add(OverdueRecord(
          record: record,
          reasons: reasons,
          currentCollateralValue: totalCurrentCollateralValue,
          currentObligation: finNow.totalDue,
          projectedObligationIn2Months: reasons.contains(OverdueReason.collateralProjected2Months)
              ? finProjected.totalDue
              : null,
        ));
      }
    }

    return result;
  }

  /// [FIX-OVERDUECOLLATERAL-1] Composition helper: unions reasons per record.id.
  static List<OverdueRecord> mergeOverdueRecords(
    List<OverdueRecord> activityBased,
    List<OverdueRecord> collateralBased,
  ) {
    final Map<String, OverdueRecord> map = {};

    for (final a in activityBased) {
      map[a.record.id] = a;
    }

    for (final c in collateralBased) {
      final existing = map[c.record.id];
      if (existing != null) {
        final mergedReasons = {...existing.reasons, ...c.reasons};
        map[c.record.id] = OverdueRecord(
          record: existing.record,
          reasons: mergedReasons,
          daysSinceActivity: existing.daysSinceActivity,
          lastActivityDate: existing.lastActivityDate,
          currentCollateralValue: c.currentCollateralValue,
          currentObligation: c.currentObligation,
          projectedObligationIn2Months: c.projectedObligationIn2Months,
        );
      } else {
        map[c.record.id] = c;
      }
    }

    return map.values.toList();
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
  /// Computes Collection Alerts for ACTIVE GIVEN records (§5.3 & [FIX-ARCH-COLLALERT-1]).
  static List<CollectionAlert> computeCollectionAlerts(
    List<LedgerRecord> records,
    List<ItemRate> rates, [
    Map<String, double> totalPaidMap = const {},
    DateTime? today,
  ]) {
    final now = today ?? DateTime.now();
    return coll_alerts.computeCollectionAlerts(
      records: records,
      rates: rates,
      today: now,
      totalPaidMap: totalPaidMap,
    );
  }

  /// Single pure function behind Dashboard card and Risk Summary (§5.3 & [FIX-RISK-VIEWMODEL-1]).
  static List<RecordRisk> computeRecordRisks({
    required List<LedgerRecord> records,
    required List<ItemRate> rates,
    required DateTime today,
    Map<String, double> totalPaidMap = const {},
  }) =>
      coll_alerts.computeRecordRisks(
        records: records,
        rates: rates,
        today: today,
        totalPaidMap: totalPaidMap,
      );

  /// Computes Unified Collection Alert Card models for all ACTIVE GIVEN records (§5.4).
  static List<CollectionAlertCardData> computeCollectionAlertCards(
    List<LedgerRecord> records,
    List<ItemRate> rates, [
    Map<String, double> totalPaidMap = const {},
    DateTime? today,
  ]) {
    final now = today ?? DateTime.now();
    final risks = coll_alerts.computeRecordRisks(
      records: records,
      rates: rates,
      today: now,
      totalPaidMap: totalPaidMap,
    );
    return risks
        .map((r) => CollectionAlertCardData(
              record: r.record,
              currentCollateralValue: r.currentCollateralValue,
              totalDue: r.totalDue,
              isCollateralUnderwater: r.collateralDrop,
              projectedOutstanding: r.projectedOutstanding,
              itemValueAtLending: r.itemValueAtLending,
              isOvershoot: r.overshoot,
              hasMissingRate: r.missingRateCategories.isNotEmpty,
              missingRateCategories: r.missingRateCategories.toList(),
            ))
        .toList();
  }

  /// Computes gross interest spread for paired GIVEN and TAKEN records (§4.2):
  // INTENTIONAL: accrual-based profit (gross interest spread), not
  // cash-adjusted for payments.
  // netProfit = givenFinancials.totalInterest - takenFinancials.totalInterest
  // Do NOT change to use outstandingInterest — that alters semantics.
  // See spec §4.1/§4.2 for rationale.
  static double calculateNetProfit(Financials givenFinancials, Financials takenFinancials) {
    return givenFinancials.totalInterest - takenFinancials.totalInterest;
  }
}

// Top-level function exports for clean idiomatic usage
double calculateItemValue(LedgerItem item) => CalculationEngine.calculateItemValue(item);
double calculateTotalItemValue(List<LedgerItem> items) => CalculationEngine.calculateTotalItemValue(items);
double calculateInterestForPeriod({
  required double principal,
  required double rate,
  required DateTime start,
  required DateTime end,
}) =>
    CalculationEngine.calculateInterestForPeriod(
      principal: principal,
      rate: rate,
      start: start,
      end: end,
    );
Financials calculateRecordFinancials(LedgerRecord record, DateTime targetDate, [DateTime? today]) =>
    CalculationEngine.calculateRecordFinancials(record, targetDate, today);
double calculateNetProfit(Financials givenFinancials, Financials takenFinancials) =>
    CalculationEngine.calculateNetProfit(givenFinancials, takenFinancials);
DashboardStats getDashboard(List<LedgerRecord> records, {required DateTime today}) =>
    CalculationEngine.getDashboard(records, today: today);
List<CustomerReport> getCustomerReport(
  List<Customer> customers,
  List<LedgerRecord> records, {
  required DateTime today,
}) =>
    CalculationEngine.getCustomerReport(customers, records, today: today);
List<MonthlyEarning> getMonthlyInterest(List<LedgerRecord> records) =>
    CalculationEngine.getMonthlyInterest(records);
List<OverdueRecord> getOverdue({
  required List<LedgerRecord> records,
  required Map<String, DateTime?> latestPaymentDates,
  required DateTime today,
  int thresholdDays = 30,
}) =>
    CalculationEngine.getOverdue(
      records: records,
      latestPaymentDates: latestPaymentDates,
      today: today,
      thresholdDays: thresholdDays,
    );
List<OverdueRecord> computeCollateralOverdue({
  required List<LedgerRecord> records,
  required List<ItemRate> rates,
  required DateTime today,
}) =>
    CalculationEngine.computeCollateralOverdue(
      records: records,
      rates: rates,
      today: today,
    );
List<OverdueRecord> mergeOverdueRecords(
  List<OverdueRecord> activityBased,
  List<OverdueRecord> collateralBased,
) =>
    CalculationEngine.mergeOverdueRecords(activityBased, collateralBased);
List<CollectionAlertCardData> computeCollectionAlertCards(
  List<LedgerRecord> records,
  List<ItemRate> rates, [
  Map<String, double> totalPaidMap = const {},
  DateTime? today,
]) =>
    CalculationEngine.computeCollectionAlertCards(records, rates, totalPaidMap, today);
