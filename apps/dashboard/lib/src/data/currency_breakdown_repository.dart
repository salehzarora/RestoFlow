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

/// The answer for one window.
class CurrencyBreakdown {
  const CurrencyBreakdown({required this.totals, required this.available});

  /// The breakdown could not be obtained (RPC not deployed, denied, transport
  /// failure). The caller then renders exactly as it did before Phase 2 — it
  /// must NOT infer "single currency" from this.
  const CurrencyBreakdown.unavailable() : totals = const [], available = false;

  final List<CurrencyTotals> totals;
  final bool available;

  /// True when this window definitively contains more than one currency, so a
  /// single merged monetary total would be a lie.
  bool get isMixed => available && totals.length > 1;

  /// The one currency in play, when there is exactly one.
  String? get singleCurrency =>
      available && totals.length == 1 ? totals.first.currencyCode : null;
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
    } catch (_) {
      // Includes PGRST202 "function not found" on a database that has not taken
      // the migration yet. Unavailable, never "one currency".
      return const CurrencyBreakdown.unavailable();
    }
    if (raw is! Map || raw['ok'] != true) {
      return const CurrencyBreakdown.unavailable();
    }
    final list = raw['by_currency'];
    if (list is! List) return const CurrencyBreakdown.unavailable();
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
