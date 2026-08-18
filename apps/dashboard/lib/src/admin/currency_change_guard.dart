/// OPS-043 D3 — the SAFETY GATE in front of an operating-currency change.
///
/// Changing the currency while orders are still open or a cash drawer is still
/// running produces mixed live accounting: a ticket taken in ILS settled after
/// the flip, a shift whose expected cash is half in one denomination. So the
/// change is refused until the affected restaurant has no open orders and no
/// open cash shift.
///
/// THREE properties matter more than the happy path:
///
///  1. It asks about the RESTAURANT, not a branch and not the whole
///     organization: `(p_restaurant_id: X, p_branch_id: null)`. The dashboard's
///     `ActiveOrdersRepository` cannot express that scope — it derives the
///     scope from the picked branch or the role, so it either over-blocks on a
///     sibling restaurant or under-blocks by missing sibling branches. Hence
///     this small dedicated reader over the same RPC.
///  2. It reads the SCOPE-WIDE summary count, which has no date window and is
///     independent of the caller's filters and of the 100-row page cap. A
///     report's `open_count` would be wrong here: it is
///     `order_count - completed_count` INSIDE the selected date range, so an
///     order opened three days ago and still `served` would be invisible.
///  3. It FAILS CLOSED. Any transport error, denial, malformed envelope, or
///     missing count is [CurrencyChangeGate.unknown] — never "nothing open".
///     A gate that treats "I could not check" as "all clear" is not a gate.
///
/// It is best-effort by construction: an order still sitting in a POS outbox
/// has not reached the server and cannot be seen from here. That is recorded
/// in the phase report as the argument for an additive server-side guard.
library;

import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// What the gate found.
enum CurrencyChangeGateStatus {
  /// Nothing open — the change may be confirmed.
  clear,

  /// Open orders and/or an open cash shift exist in this restaurant.
  blocked,

  /// The check could not be completed. Treated exactly like [blocked].
  unknown,
}

/// The gate result, with the counts needed to say WHY it blocked.
class CurrencyChangeGate {
  const CurrencyChangeGate._(
    this.status, {
    this.openOrders = 0,
    this.openShifts = 0,
  });

  const CurrencyChangeGate.clear() : this._(CurrencyChangeGateStatus.clear);

  const CurrencyChangeGate.blocked({int openOrders = 0, int openShifts = 0})
    : this._(
        CurrencyChangeGateStatus.blocked,
        openOrders: openOrders,
        openShifts: openShifts,
      );

  const CurrencyChangeGate.unknown() : this._(CurrencyChangeGateStatus.unknown);

  final CurrencyChangeGateStatus status;

  /// Non-terminal orders in the restaurant (submitted/accepted/preparing/
  /// ready/served). Zero when the block came from shifts alone.
  final int openOrders;

  /// Cash shifts in the restaurant that are opening/open/closing right now.
  final int openShifts;

  /// True unless the gate is definitively [CurrencyChangeGateStatus.clear] —
  /// the single predicate every caller should branch on, so "unknown" can
  /// never be mistaken for permission.
  bool get blocksChange => status != CurrencyChangeGateStatus.clear;
}

/// Reads the two live signals a currency change must respect.
abstract interface class CurrencyChangeGuard {
  Future<CurrencyChangeGate> check();
}

/// The real guard: `owner_active_orders` for open orders and
/// `owner_report_range` (falling back to `owner_daily_report`) for the
/// point-in-time open cash-shift count, both scoped to one restaurant.
class SupabaseCurrencyChangeGuard implements CurrencyChangeGuard {
  SupabaseCurrencyChangeGuard({
    required SyncRpcTransport transport,
    required this.organizationId,
    required this.restaurantId,
  }) : _t = transport;

  final SyncRpcTransport _t;
  final String organizationId;
  final String restaurantId;

  @override
  Future<CurrencyChangeGate> check() async {
    final orders = await _openOrderCount();
    if (orders == null) return const CurrencyChangeGate.unknown();
    final shifts = await _openShiftCount();
    if (shifts == null) return const CurrencyChangeGate.unknown();
    if (orders == 0 && shifts == 0) return const CurrencyChangeGate.clear();
    return CurrencyChangeGate.blocked(openOrders: orders, openShifts: shifts);
  }

  /// Scope-wide, date-window-free count of non-terminal orders. Null = unknown.
  Future<int?> _openOrderCount() async {
    final Object? raw;
    try {
      raw = await _t.invoke('owner_active_orders', <String, dynamic>{
        'p_organization_id': organizationId,
        // The restaurant, ALL its branches.
        'p_restaurant_id': restaurantId,
        'p_branch_id': null,
        // The smallest page the RPC will give us: we want the summary, not
        // the rows.
        'p_limit': 1,
        'p_cursor': null,
      });
    } catch (_) {
      return null;
    }
    if (raw is! Map || raw['ok'] != true) return null;
    final summary = raw['summary'];
    if (summary is! Map) return null;
    return _int(summary['total']);
  }

  /// Point-in-time count of shifts in opening/open/closing. Null = unknown,
  /// which INCLUDES the compatibility fallbacks that carry no shift block at
  /// all — "the payload did not tell me" is not "zero".
  Future<int?> _openShiftCount() async {
    for (final rpc in const ['owner_report_range', 'owner_daily_report']) {
      final Object? raw;
      try {
        raw = await _t.invoke(rpc, <String, dynamic>{
          'p_organization_id': organizationId,
          'p_restaurant_id': restaurantId,
          'p_branch_id': null,
        });
      } catch (_) {
        continue; // a missing/failing RPC: try the next shape
      }
      if (raw is! Map || raw['ok'] != true) continue;
      final cash = raw['shift_cash'];
      if (cash is! Map) continue;
      final count = _int(cash['open_shift_count']);
      if (count != null) return count;
    }
    return null;
  }

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}');
  }
}
