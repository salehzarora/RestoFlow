/// OPS-043 Phase 2 (D3) — the per-currency breakdown behind the report totals.
///
/// The report RPCs return ONE merged total labelled with ONE currency. That is
/// correct for the single-currency case and dangerous otherwise: adding
/// ₪1,000 to $700 produces a number that means nothing, and it looks exactly
/// like a number that means something.
///
/// So the dashboard asks a second, purely additive question — "which currencies
/// are actually in this window, and what does each of them total?" — and
/// refuses to render a single merged figure when the answer names more than
/// one. Nothing is converted; the currencies are shown side by side.
///
/// It is deliberately a SEPARATE call rather than a new key on the existing
/// report envelope: every pre-existing key of every report RPC keeps its exact
/// shape and meaning, and a database that has not yet taken the migration
/// simply answers "not deployed", which degrades to today's single-currency
/// rendering instead of breaking the page.
library;

import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// One currency's totals inside a report window. All money is integer minor
/// units of THIS currency (DECISION D-007) — never a converted or merged value.
class CurrencyTotals {
  const CurrencyTotals({
    required this.currencyCode,
    required this.orderCount,
    required this.grossMinor,
    required this.discountMinor,
    required this.netMinor,
    required this.collectedMinor,
    required this.cashMinor,
  });

  final String currencyCode;
  final int orderCount;
  final int grossMinor;
  final int discountMinor;
  final int netMinor;
  final int collectedMinor;
  final int cashMinor;
}

/// WHY the breakdown could not be established.
///
/// REPORT-123: these were once one undifferentiated `catch (_)`, which made a
/// server-side ACL failure indistinguishable from "this database has not taken
/// the migration". Production spent the outage reporting the second while
/// suffering the first. The distinction is not cosmetic — a `denied` or
/// `transport` failure is transient and worth retrying on the owner's next
/// refresh, whereas `notDeployed` genuinely describes the deployment.
enum CurrencyBreakdownFailure {
  /// No failure: the breakdown was obtained.
  none,

  /// PostgREST could not find the function (PGRST202), or its schema cache is
  /// stale. Recoverable: a later call may well succeed.
  notDeployed,

  /// The function exists and refused this caller (SQLSTATE 42501) — either a
  /// genuine authorization refusal or, as in REPORT-123, a missing EXECUTE
  /// grant on the inner implementation.
  denied,

  /// Network/transport trouble, or a reply this build could not parse.
  transport,
}

/// The answer for one window.
class CurrencyBreakdown {
  const CurrencyBreakdown({
    required this.totals,
    required this.available,
    this.failure = CurrencyBreakdownFailure.none,
  });

  /// The breakdown could not be obtained. The caller then renders exactly as it
  /// did before Phase 2 — it must NOT infer "single currency" from this.
  const CurrencyBreakdown.unavailable([
    this.failure = CurrencyBreakdownFailure.transport,
  ]) : totals = const [],
       available = false;

  final List<CurrencyTotals> totals;
  final bool available;

  /// Why it is unavailable; [CurrencyBreakdownFailure.none] when it is not.
  final CurrencyBreakdownFailure failure;

  /// True when this window definitively contains more than one currency, so a
  /// single merged monetary total would be a lie.
  bool get isMixed => available && totals.length > 1;

  /// The one currency in play, when there is exactly one.
  String? get singleCurrency =>
      available && totals.length == 1 ? totals.first.currencyCode : null;
}

/// Maps a thrown transport/database error onto [CurrencyBreakdownFailure].
///
/// Kept at library level, and deliberately string-based: the transport seam is
/// intentionally neutral, so the concrete Postgrest exception type is not
/// visible here. Matching on the codes it carries is what the rest of this
/// repository already does, and it is what lets a stale schema-cache 404 be
/// told apart from a permission refusal.
CurrencyBreakdownFailure classifyBreakdownFailure(Object error) {
  final text = error.toString().toUpperCase();
  // PGRST202 = "could not find the function"; PGRST204/205 accompany a stale
  // schema cache. All three describe the deployment, not the caller.
  if (text.contains('PGRST202') ||
      text.contains('PGRST204') ||
      text.contains('PGRST205') ||
      text.contains('COULD NOT FIND THE FUNCTION')) {
    return CurrencyBreakdownFailure.notDeployed;
  }
  // 42501 is PostgreSQL's insufficient_privilege — REPORT-123's signature.
  if (text.contains('42501') ||
      text.contains('PERMISSION DENIED') ||
      text.contains('PERMISSION_DENIED')) {
    return CurrencyBreakdownFailure.denied;
  }
  return CurrencyBreakdownFailure.transport;
}

/// Reads the per-currency breakdown for an explicit window.
abstract interface class CurrencyBreakdownRepository {
  /// [start] / [end] are the branch-local `YYYY-MM-DD` bounds the report itself
  /// reported, so the split always describes the same window as the headline.
  Future<CurrencyBreakdown> load({required String start, required String end});
}

class SupabaseCurrencyBreakdownRepository
    implements CurrencyBreakdownRepository {
  SupabaseCurrencyBreakdownRepository({
    required SyncRpcTransport transport,
    required this.organizationId,
    this.restaurantId,
    this.branchId,
  }) : _t = transport;

  final SyncRpcTransport _t;
  final String organizationId;
  final String? restaurantId;
  final String? branchId;

  @override
  Future<CurrencyBreakdown> load({
    required String start,
    required String end,
  }) async {
    final Object? raw;
    try {
      raw = await _t
          .invoke('owner_report_currency_breakdown', <String, dynamic>{
            'p_organization_id': organizationId,
            'p_restaurant_id': restaurantId,
            'p_branch_id': branchId,
            'p_start': start,
            'p_end': end,
          });
    } catch (e) {
      // REPORT-123: classify. Never "one currency", but WHY it is unavailable
      // decides whether a later refresh is worth anything.
      return CurrencyBreakdown.unavailable(classifyBreakdownFailure(e));
    }
    if (raw is! Map || raw['ok'] != true) {
      // A DEPLOYED function that refused this caller. `ok:false` is the
      // envelope form of a refusal; the raised form is handled above.
      return const CurrencyBreakdown.unavailable(
        CurrencyBreakdownFailure.denied,
      );
    }
    final list = raw['by_currency'];
    if (list is! List) {
      return const CurrencyBreakdown.unavailable(
        CurrencyBreakdownFailure.transport,
      );
    }
    final totals = <CurrencyTotals>[];
    for (final entry in list) {
      if (entry is! Map) continue;
      final code = (entry['currency_code'] ?? '').toString();
      if (code.isEmpty) continue;
      totals.add(
        CurrencyTotals(
          currencyCode: code,
          orderCount: _int(entry['order_count']),
          grossMinor: _int(entry['gross_minor']),
          discountMinor: _int(entry['discount_minor']),
          netMinor: _int(entry['net_minor']),
          collectedMinor: _int(entry['collected_minor']),
          cashMinor: _int(entry['cash_minor']),
        ),
      );
    }
    return CurrencyBreakdown(totals: totals, available: true);
  }

  /// Lenient on purpose: a malformed figure must not take the whole Overview
  /// down, and the caller only ever compares these against each other.
  static int _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}') ?? 0;
  }
}

/// What the Overview is allowed to do with the report's money, for one window.
enum ReportMoneyMode {
  /// Exactly one currency is in play: render every total exactly as before.
  single,

  /// More than one currency is in play. A merged total would be a fiction, so
  /// the money is rendered per currency instead.
  mixed,

  /// We could not establish how many currencies are in play. Merged money is
  /// SUPPRESSED — "I could not check" must never be rendered as "one currency".
  unknown,
}

/// The gate every money widget on the Overview passes through.
///
/// It exists because the failure it prevents is silent: a range holding ₪1,000
/// and $700 has no single total, but a screen will happily print `₪1,700` and
/// nobody can tell by looking. So the decision is made ONCE, here, and the
/// widgets ask this object rather than each deciding for themselves.
class ReportCurrencyGuard {
  const ReportCurrencyGuard._(
    this.mode, {
    this.displayCurrency,
    this.totals = const [],
  });

  /// One currency, named. Everything renders as it always has.
  const ReportCurrencyGuard.single(String currency)
    : this._(ReportMoneyMode.single, displayCurrency: currency);

  /// Several currencies, each with its own totals.
  const ReportCurrencyGuard.mixed(List<CurrencyTotals> totals)
    : this._(ReportMoneyMode.mixed, totals: totals);

  /// Not established. Money is hidden.
  const ReportCurrencyGuard.unknown() : this._(ReportMoneyMode.unknown);

  final ReportMoneyMode mode;

  /// The currency every merged figure is labelled with, in [ReportMoneyMode
  /// .single] only.
  ///
  /// LABEL AUTHORITY: this is the currency the WINDOW's money is actually in,
  /// taken from the breakdown, not the organization default. A range of
  /// historical ILS orders stays labelled ILS even after the restaurant has
  /// moved to USD — relabelling a past range with today's currency is exactly
  /// the lie D3 forbids.
  final String? displayCurrency;

  /// Per-currency totals, in [ReportMoneyMode.mixed] only.
  final List<CurrencyTotals> totals;

  /// True only when a single merged monetary figure is honest.
  bool get canRenderMergedMoney => mode == ReportMoneyMode.single;

  /// Decides the mode from a breakdown plus what the report itself reported.
  ///
  /// [envelopeCurrency] is the report's own `currency_code`; it is used only as
  /// the LABEL for a window that has no money to mislabel. [orderCount] is the
  /// independent evidence the ticket allows: a window with no billed orders has
  /// nothing to sum, so zeros may render even when the breakdown is missing.
  factory ReportCurrencyGuard.resolve({
    required CurrencyBreakdown breakdown,
    required String envelopeCurrency,
    required int orderCount,
  }) {
    if (breakdown.available) {
      if (breakdown.totals.length > 1) {
        return ReportCurrencyGuard.mixed(breakdown.totals);
      }
      final single = breakdown.singleCurrency;
      if (single != null) return ReportCurrencyGuard.single(single);
      // Available and empty: the window genuinely holds no money.
      return ReportCurrencyGuard.single(envelopeCurrency);
    }
    // UNAVAILABLE. The one safe exception: a window with no orders at all has
    // no unlike currencies to add together, so its zeros are honest.
    if (orderCount == 0) return ReportCurrencyGuard.single(envelopeCurrency);
    return const ReportCurrencyGuard.unknown();
  }
}
