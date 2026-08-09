/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-C) — per-method payment analytics.
///
/// The Overview already knew each tender's amount and count. What it could not
/// answer was the two questions an owner actually asks of a payment mix: how
/// much of the money that came in did this method carry, and how big is a
/// typical one.
///
/// Both are computed here, in INTEGER arithmetic only (D-007), from figures the
/// server already returned. Nothing is fetched, nothing is estimated, and no
/// value is divided into a double on the way to the screen.
///
/// SCOPE OF THE CLAIM. These are RECORDED tenders — the completed payment rows
/// RestoFlow stored. They are not processor approvals, not acquirer settlement
/// and not a reconciliation. The platform has no acquirer integration, so any
/// wording built on top of these numbers must stay inside that claim.
library;

import '../data/demo_report.dart' show PaymentMethodLine;

/// One payment method's analytics for a window.
class PaymentMethodAnalytics {
  const PaymentMethodAnalytics({
    required this.method,
    required this.amountMinor,
    required this.count,
    required this.shareBps,
    required this.averageMinor,
  });

  /// Builds the analytics for one tender line against the window's total
  /// collected money.
  ///
  /// [totalCollectedMinor] is the COLLECTED total — the money that actually
  /// came in — because that is the only denominator under which the shares of
  /// the methods describe one whole. Billed sales would be the wrong divisor:
  /// an unpaid order raises billed without any tender existing, so every share
  /// would silently shrink for a reason that has nothing to do with payments.
  factory PaymentMethodAnalytics.of(
    PaymentMethodLine line, {
    required int totalCollectedMinor,
  }) {
    return PaymentMethodAnalytics(
      method: line.method,
      amountMinor: line.totalMinor,
      count: line.count,
      shareBps: shareBasisPoints(line.totalMinor, totalCollectedMinor),
      averageMinor: averagePaymentMinor(line.totalMinor, line.count),
    );
  }

  /// Builds the analytics for every line in a window.
  static List<PaymentMethodAnalytics> forLines(
    List<PaymentMethodLine> lines, {
    required int totalCollectedMinor,
  }) => [
    for (final line in lines)
      PaymentMethodAnalytics.of(line, totalCollectedMinor: totalCollectedMinor),
  ];

  /// The wire token (`cash` / `card` / `bit` / `external`, or an unrecognised
  /// future one) — kept verbatim; display is resolved by `paymentMethodLabel`.
  final String method;

  /// Recorded completed tender, integer minor units.
  final int amountMinor;

  /// Number of completed payment rows.
  final int count;

  /// Share of the window's collected money, in BASIS POINTS (1% = 100 bps), or
  /// null when there is nothing collected to take a share of.
  ///
  /// Basis points rather than a percentage so the value survives as an integer
  /// at the precision a small tender needs — 0.4% is 40 bps, where a whole
  /// percent would round it to nothing and imply the method carried no money.
  final int? shareBps;

  /// Mean recorded payment, integer minor units, or null when there are no
  /// payments to average.
  ///
  /// NOT average order value: one order may be settled by one payment of a
  /// method, so this describes the size of a TENDER, not of a sale.
  final int? averageMinor;

  /// True when a share can be shown at all.
  bool get hasShare => shareBps != null;

  /// Share of the collected total, in basis points, or null when the window
  /// collected nothing.
  ///
  /// A zero denominator yields null rather than 0: "no money came in" is not
  /// "this method carried none of it", and a 0% beside a real amount would be a
  /// contradiction on screen.
  static int? shareBasisPoints(int amountMinor, int totalCollectedMinor) {
    if (totalCollectedMinor <= 0) return null;
    return (amountMinor * 10000) ~/ totalCollectedMinor;
  }

  /// Mean recorded payment in integer minor units, or null with no payments.
  ///
  /// Truncating integer division. A zero AMOUNT across a positive count is a
  /// real, valid 0 (a fully-discounted order settled by a zero tender); only a
  /// zero COUNT has nothing to average.
  static int? averagePaymentMinor(int amountMinor, int count) {
    if (count <= 0) return null;
    return amountMinor ~/ count;
  }
}

/// Renders a basis-point share as a one-decimal percent string, e.g. `3421` ->
/// `"34.2"`.
///
/// Integer math throughout — the string is assembled from the quotient and the
/// remainder, so no floating-point value is created to be rounded. One decimal
/// because a whole percent hides every method under 0.5% behind a `0`.
String formatShareBps(int bps) {
  final negative = bps < 0;
  final abs = bps.abs();
  final whole = abs ~/ 100;
  final tenths = (abs % 100) ~/ 10;
  return '${negative ? '-' : ''}$whole.$tenths';
}

/// Rounds a basis-point share to a whole percent, without floating point.
///
/// Used where the surface has room for one number only (the donut centre). The
/// `+ 50` is half a percent in basis points, so this rounds half-up exactly as
/// the previous `(amount * 100 / total).round()` did — but the intermediate is
/// an int, not a double.
int roundedPercentFromBps(int bps) => (bps + 50) ~/ 100;
