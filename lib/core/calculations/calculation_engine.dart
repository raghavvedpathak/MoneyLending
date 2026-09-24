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
  /// itemValue = roundMoney(weight * (purity / 100) * rate);
  /// lendableAmount = roundMoney(itemValue * (lendPercentage / 100)).
  /// Both computed at save time and stored as snapshots (2 decimals).
  /// Never recompute from live market rate after save. [FIX-MONEY-1]
  static double calculateItemValue(LedgerItem item) {
    if (item.itemValue > 0) return item.itemValue;
    return roundMoney(item.weight * (item.purity / 100.0) * item.rate);
  }

  /// Computes total collateral value across all items in a record (§5.1)
  /// sumMoney(items.map(calculateItemValue))
  static double calculateTotalItemValue(List<LedgerItem> items) =>
      sumMoney(items.map((item) => item.itemValue > 0 ? item.itemValue : calculateItemValue(item)));

  /// [FIX-MONEY-1] (v1.16)
  /// One formula for an item's value at a live rate, used by computeRecordRisks(),
  /// computeCollateralOverdue() and RecordDetailScreen (Addendum J.1).
  static double liveItemValue(LedgerItem item, double rate) =>
      roundMoney(item.fineWeight * rate);

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
    final totalPaid = sumMoney(record.payments.map((p) => p.amount));
    final interestPaid = sumMoney(record.payments.map((p) => p.interestPaid));
    final principalPaid = sumMoney(record.payments.map((p) => p.principalPaid));

    // =========================================================================
    // SETTLED FAST-PATH (§5.2.1)
    // =========================================================================
    if (record.isSettled) {
      // 1. Primary fast-path: snapshotted calculatedInterest
      if (record.calculatedInterest != null) {
        final effectiveEnd = record.settledDate ?? targetDate;
        final months = getMonthsBetween(record.startDate.dateOnly, effectiveEnd.dateOnly);
        final calculatedInterest = record.calculatedInterest!;

        // [FIX-FINANCIALS-OVERPAY-1] & [FIX-SETTLED-WRITEOFF-1] (v1.16)
        // The snapshot uses the same formulas as the active path with one difference:
        // totalInterest is the stored calculatedInterest and nothing accrues.
        // net = (calculatedInterest − interestPaid) + (principalAmount − principalPaid);
        // totalDue = roundMoney(max(0, net));
        // overpaymentAmount = roundMoney(max(0, −net)).
        // On a SETTLED record a positive totalDue is the amount that was WRITTEN OFF
        // when the record was settled (0.00 when it was paid in full — Addendum J.3).
        final rawOutstandingInterest = calculatedInterest - interestPaid;
        final rawOutstandingPrincipal = record.principalAmount - principalPaid;
        final outstandingInterest = max(0.0, rawOutstandingInterest);
        final outstandingPrincipal = max(0.0, rawOutstandingPrincipal);

        final net = rawOutstandingInterest + rawOutstandingPrincipal;
        final totalDue = roundMoney(max(0.0, net));
        final overpaymentAmount = roundMoney(max(0.0, -net));

        return Financials(
          totalInterest: calculatedInterest,
          totalPaid: totalPaid,
          interestPaid: interestPaid,
          principalPaid: principalPaid,
          outstandingInterest: outstandingInterest,
          outstandingPrincipal: outstandingPrincipal,
          totalDue: totalDue,
          overpaymentAmount: overpaymentAmount,
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
            sumMoney(record.payments.map((p) => p.principalPaid));
        // [FIX-FINANCIALS-OVERPAY-1] compute the raw (unfloored) delta once so
        // both outstandingPrincipal and overpaymentAmount derive from the same number —
        // flooring it twice in two different directions must never drift apart.
        final rawOutstandingPrincipal = roundMoney(record.principalAmount - principalPaidSoFar);
        return Financials(
          totalInterest: 0.0,
          totalPaid: sumMoney(record.payments.map((p) => p.amount)),
          // BLK-10 FIX equivalent: all 8 fields must be supplied
          interestPaid: sumMoney(record.payments.map((p) => p.interestPaid)),
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
      final months = getMonthsBetween(record.startDate.dateOnly, settledTarget.dateOnly);
      final totalInterest = calculateInterestForPeriod(
        principal: record.principalAmount,
        rate: record.interestRate,
        start: record.startDate.dateOnly,
        end: settledTarget.dateOnly,
      );
      final rawOutstandingInterest = totalInterest - interestPaid;
      final rawOutstandingPrincipal = record.principalAmount - principalPaid;
      final outstandingInterest = max(0.0, rawOutstandingInterest);
      final outstandingPrincipal = max(0.0, rawOutstandingPrincipal);
      final net = rawOutstandingInterest + rawOutstandingPrincipal;
      final totalDue = roundMoney(max(0.0, net));
      final overpaymentAmount = roundMoney(max(0.0, -net));

      return Financials(
        totalInterest: totalInterest,
        totalPaid: totalPaid,
        interestPaid: interestPaid,
        principalPaid: principalPaid,
        outstandingInterest: outstandingInterest,
        outstandingPrincipal: outstandingPrincipal,
        totalDue: totalDue,
        overpaymentAmount: overpaymentAmount,
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
    final rawOutstandingInterest = roundMoney(totalInterest - interestPaid);
    final rawOutstandingPrincipal = roundMoney(record.principalAmount - principalPaid);
    final outstandingInterest = max(0.0, rawOutstandingInterest);
    final outstandingPrincipal = max(0.0, rawOutstandingPrincipal);

    // [FIX-FINANCIALS-NET-1] (v1.14) totalDue nets the two raw deltas BEFORE flooring, so
    // interest paid in excess of interest accrued (e.g. after the rate is edited down)
    // credits against principal still owed. Only the SUM is floored at zero.
    final netOutstanding = roundMoney(rawOutstandingInterest + rawOutstandingPrincipal);
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
  /// Every sum is re-rounded with sumMoney().
  static List<CustomerReport> getCustomerReport(
    List<Customer> customers,
    List<LedgerRecord> records, {
    required DateTime today,
  }) {
    final todayDate = today.dateOnly;

    return customers.map((customer) {
      final customerRecords = records
          .where((r) => r.customerId == customer.id && r.isActive && r.isGiven)
          .toList();

      final totalPrincipal = sumMoney(customerRecords.map((r) => r.principalAmount));
      final financials = customerRecords.map((r) => calculateRecordFinancials(r, todayDate)).toList();
      final totalInterest = sumMoney(financials.map((f) => f.totalInterest));
      final totalDue = sumMoney(financials.map((f) => f.totalDue));

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

  /// [FIX-LASTACTIVITY-1] (v1.16)
  /// Derives last activity date from the full record itself:
  /// latest payment.date (.dateOnly) if payments exist, else record.startDate.dateOnly.
  static DateTime lastActivityDate(LedgerRecord record) {
    if (record.payments.isNotEmpty) {
      return record.payments
          .map((p) => p.date.dateOnly)
          .reduce((a, b) => a.isAfter(b) ? a : b);
    }
    return record.startDate.dateOnly;
  }

  /// Activity-based overdue records (§5.1, §8, & [FIX-LASTACTIVITY-1]).
  /// Threshold in days (defaults to 30).
  ///
  /// [FIX-LASTACTIVITY-1] (v1.16): getOverdue() no longer requires a map of latest
  /// payment dates. Every record is FULL, so the last activity is computed from the record
  /// itself by the pure helper lastActivityDate(r). An optional latestPaymentDates map
  /// is supported for legacy callers.
  static List<OverdueRecord> getOverdue({
    required List<LedgerRecord> records,
    required DateTime today,
    int thresholdDays = 30,
    Map<String, DateTime?>? latestPaymentDates,
  }) {
    final todayDate = today.dateOnly;
    final overdueList = <OverdueRecord>[];

    for (final r in records) {
      if (!r.isActive) continue;

      final DateTime lastAct = (latestPaymentDates != null && latestPaymentDates.containsKey(r.id))
          ? (latestPaymentDates[r.id]?.dateOnly ?? r.startDate.dateOnly)
          : lastActivityDate(r);

      // ChronoUnit.DAYS.between(lastActivityDate, todayDate) equivalent (§5.2.3)
      final daysSinceActivity = daysBetween(lastAct, todayDate);

      // Flag as overdue if that gap >= thresholdDays (30) (§8)
      if (daysSinceActivity >= thresholdDays) {
        overdueList.add(OverdueRecord(
          record: r,
          reasons: const {OverdueReason.noActivity},
          daysSinceActivity: daysSinceActivity,
          lastActivityDate: lastAct,
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
    Map<String, double>? totalPaidMap,
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
    Map<String, double>? totalPaidMap,
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

  /// [FIX-REPLAY-1] (v1.16 / Addendum J.2)
  /// Replays every payment oldest-first and returns the payments with a
  /// recalculated interest/principal split.
  static List<Payment> reallocatePayments(LedgerRecord record) {
    if (record.payments.isEmpty) return const [];

    final sortedPayments = List<Payment>.from(record.payments)
      ..sort((a, b) {
        final cmp = a.date.compareTo(b.date);
        if (cmp != 0) return cmp;
        return a.paymentId.compareTo(b.paymentId);
      });

    final result = <Payment>[];
    double accumulatedInterestPaid = 0.0;

    for (final p in sortedPayments) {
      final effectivePaymentDate = accrualEndDate(record, p.date.dateOnly);
      final totalInterestAtDate = calculateInterestForPeriod(
        principal: record.principalAmount,
        rate: record.interestRate,
        start: record.startDate.dateOnly,
        end: effectivePaymentDate,
      );
      final outstandingInterest = max(0.0, totalInterestAtDate - accumulatedInterestPaid);
      final (interestPaid, principalPaid) = allocatePayment(
        p.amount,
        outstandingInterest,
      );
      accumulatedInterestPaid += interestPaid;
      result.add(p.withSplit(interestPaid, principalPaid));
    }

    return result;
  }

  /// Dry-run validation of a new payment or refund (§5.1 & Addendum J.3).
  ///
  /// Returns `(bool isValid, String? error)`.
  /// - Loan must be ACTIVE.
  /// - Payment amount cannot be 0.0.
  /// - Payment date cannot be before record.startDate.dateOnly.
  /// - For refunds (amount < 0.0):
  ///   - Cannot refund if no payments exist.
  ///   - Refund amount cannot exceed total payments received.
  ///   - Backdated refund cannot be dated before the payment(s) it refunds (Addendum J.3).
  static (bool isValid, String? error) checkPaymentInsert({
    required LedgerRecord record,
    required double amount,
    required DateTime date,
  }) {
    if (!record.isActive) {
      return (false, 'Cannot add payment to a settled record');
    }
    if (amount == 0.0) {
      return (false, 'Payment amount cannot be zero');
    }
    if (date.dateOnly.isBefore(record.startDate.dateOnly)) {
      return (false, 'Payment date cannot be before record start date');
    }
    if (amount < 0.0) {
      final totalPaid = record.payments.fold<double>(0.0, (s, p) => s + p.amount);
      if (totalPaid <= 0.0) {
        return (false, 'Cannot refund when no payments exist');
      }
      if (amount.abs() > totalPaid) {
        return (false, 'Refund amount cannot exceed total payments received');
      }
      if (record.payments.isNotEmpty) {
        final earliestPaymentDate = record.payments
            .map((p) => p.date.dateOnly)
            .reduce((a, b) => a.isBefore(b) ? a : b);
        if (date.dateOnly.isBefore(earliestPaymentDate)) {
          return (false, 'Refund date cannot be earlier than the payment it refunds');
        }
      }
    }
    return (true, null);
  }

  /// Repeat-notification throttle helper (§5.1, §8, & Addendum J.8 [FIX-NOTIFY-THROTTLE-1]).
  ///
  /// Returns true if a notification should be fired on [today], given [lastNotifiedDate].
  /// If never notified ([lastNotifiedDate] is null), returns true.
  /// If [lastReasons] and [currentReasons] are provided, returns true if reasons changed.
  /// Otherwise returns true only if the difference in days is >= [throttleDays] (defaults to 1, 7 for weekly repeat).
  static bool shouldNotify({
    required DateTime? lastNotifiedDate,
    required DateTime today,
    int throttleDays = 1,
    Set<OverdueReason>? lastReasons,
    Set<OverdueReason>? currentReasons,
  }) {
    if (lastNotifiedDate == null) return true;
    if (lastReasons != null && currentReasons != null) {
      final reasonsChanged = lastReasons.length != currentReasons.length ||
          !lastReasons.containsAll(currentReasons);
      if (reasonsChanged) return true;
    }
    final diffDays = today.dateOnly.difference(lastNotifiedDate.dateOnly).inDays;
    return diffDays >= throttleDays;
  }
}

// Top-level function exports for clean idiomatic usage
double calculateItemValue(LedgerItem item) => CalculationEngine.calculateItemValue(item);
double calculateTotalItemValue(List<LedgerItem> items) => CalculationEngine.calculateTotalItemValue(items);
double liveItemValue(LedgerItem item, double rate) => CalculationEngine.liveItemValue(item, rate);
DateTime lastActivityDate(LedgerRecord record) => CalculationEngine.lastActivityDate(record);
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
  required DateTime today,
  int thresholdDays = 30,
  Map<String, DateTime?>? latestPaymentDates,
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
List<Payment> reallocatePayments(LedgerRecord record) => CalculationEngine.reallocatePayments(record);
(bool isValid, String? error) checkPaymentInsert({
  required LedgerRecord record,
  required double amount,
  required DateTime date,
}) =>
    CalculationEngine.checkPaymentInsert(record: record, amount: amount, date: date);
bool shouldNotify({
  required DateTime? lastNotifiedDate,
  required DateTime today,
  int throttleDays = 1,
  Set<OverdueReason>? lastReasons,
  Set<OverdueReason>? currentReasons,
}) =>
    CalculationEngine.shouldNotify(
      lastNotifiedDate: lastNotifiedDate,
      today: today,
      throttleDays: throttleDays,
      lastReasons: lastReasons,
      currentReasons: currentReasons,
    );

