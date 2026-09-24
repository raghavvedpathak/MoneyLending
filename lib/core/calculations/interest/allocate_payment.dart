import '../../domain/util/money.dart';

/// Returns (interestPaid, principalPaid) for a single payment, allocated
/// interest-first. A negative paymentAmount is a refund/payback of an
/// overpayment — see case (5) [FIX-ALLOCATE-NEGATIVE-1].
(double interestPaid, double principalPaid) allocatePayment({
  required double paymentAmount,
  required double outstandingInterest,
}) {
  if (paymentAmount < 0.0) {
    // case (5) [FIX-ALLOCATE-NEGATIVE-1]: refund of an overpayment. Without this
    // branch a negative paymentAmount falls through to the interest-first case
    // below and is returned as (paymentAmount, 0.0) — a negative interestPaid,
    // which corrupts every future outstandingInterest calculation for this record.
    // Refunds always reduce principal, never interest: interest is allocated first
    // on every prior payment, so by the time an overpayment exists outstandingInterest
    // is already 0.0 — there is nothing left in interest to un-allocate.
    return (0.0, paymentAmount);
  }
  if (outstandingInterest <= 0.0) {
    // case (3): outstandingInterest == 0.0 — all goes to principal
    return (0.0, paymentAmount);
  }
  if (paymentAmount >= outstandingInterest) {
    // case (1) payment > outstandingInterest, and case (4) payment ==
    // outstandingInterest exactly — interest fully covered, remainder (possibly
    // zero) goes to principal
    return (outstandingInterest, roundMoney(paymentAmount - outstandingInterest));
  }
  // case (2): payment < outstandingInterest — all goes to interest, zero principal
  return (paymentAmount, 0.0);
}

/// Compatibility extension providing named getters on the Dart 3 record tuple.
extension PaymentRecordExtension on (double, double) {
  double get interestPaid => $1;
  double get principalPaid => $2;
  double get first => $1;
  double get second => $2;
  (double, double) get asRecord => this;
}

/// Type alias matching Kotlin `Pair<Double, Double>` / Dart 3 record.
typedef PaymentAllocation = (double interestPaid, double principalPaid);
