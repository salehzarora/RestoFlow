/// Real-mode active-orders repository (ACTIVE-ORDERS-001).
///
/// Reads the `public.owner_active_orders` RPC — GUC-free, financial-read gated,
/// RLS-safe, integer-minor money (D-007/D-008) — over the SAME authenticated
/// anon-key transport the rest of the real dashboard uses (the GoTrue session
/// rides the client; identity and scope are SERVER-derived, never trusted from
/// this payload).
///
/// FAIL-CLOSED: with no transport/scope it throws [RealRepoNotWiredError]; a
/// transport failure or a rejected (`ok != true`) body throws
/// [ActiveOrdersException] — never fabricated data, never a silent demo
/// fallback. A permission / tenant / auth denial stays fail-closed.
library;

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'active_orders_models.dart';
import 'active_orders_repository.dart';
import 'audit_filter_options_repository.dart' show auditCoveredScope;
import 'order_history_models.dart';

/// Reads the active board from the ACTIVE-ORDERS-001 RPC.
class RealActiveOrdersRepository implements ActiveOrdersRepository {
  const RealActiveOrdersRepository(this.config, {this.scope, this.transport});

  /// The validated client runtime config (anon key only). Null when real mode
  /// was selected but the Supabase config was missing/invalid (fail-closed
  /// upstream in `RuntimeConfig`).
  final SupabaseBootstrapConfig? config;

  /// The active membership (org/restaurant/branch) the read is scoped to.
  final MembershipContext? scope;

  /// The AUTHENTICATED transport. Null => not wired (fail-closed).
  final SyncRpcTransport? transport;

  @override
  Future<ActiveOrdersSnapshot> loadActive(
    ActiveOrdersQuery query, {
    String? cursor,
  }) async {
    final t = transport;
    final m = scope;
    if (t == null || m == null) {
      throw const RealRepoNotWiredError(
        'active-orders: no authenticated transport/scope - real read not wired',
      );
    }
    // "All permitted branches" resolves from the caller's ROLE (org_owner ->
    // whole org, restaurant_owner -> whole restaurant, otherwise the one covered
    // branch). A picked branch comes from the scope-safe option list, never a
    // typed UUID. The server intersects whatever we send with the scope it
    // derives itself, so this only shapes the request.
    final covered = auditCoveredScope(m);
    final restaurantId = query.branch?.restaurantId ?? covered.restaurantId;
    final branchId = query.branch?.branchId ?? covered.branchId;

    final Object? raw;
    try {
      raw = await t.invoke('owner_active_orders', <String, dynamic>{
        'p_organization_id': m.organizationId,
        'p_restaurant_id': restaurantId,
        'p_branch_id': branchId,
        'p_status': query.stage.wire,
        'p_order_type': query.orderType.wire,
        'p_payment': query.payment.wire,
        'p_search': query.searchOrNull,
        'p_limit': 100,
        // The QUEUE and the SORT are the SERVER's job (ACTIVE-ORDERS-002): the
        // page is capped, so re-sorting it here would silently omit every
        // matching row the server did not send.
        'p_queue': query.queue.wire,
        'p_sort': query.sort.wire,
        'p_cursor': cursor,
      });
    } on SyncTransportException {
      throw const ActiveOrdersException(
        'owner_active_orders transport failure',
      );
    }
    if (raw is! Map || raw['ok'] != true) {
      throw const ActiveOrdersException('owner_active_orders rejected');
    }

    // FAIL CLOSED on a malformed queue/sort response: if the server did not serve
    // the queue and sort we asked for, these rows are not what the operator is
    // looking at — and silently re-ordering them here would be a lie.
    final servedQueue = _strOrNull(raw['queue']);
    final servedSort = _strOrNull(raw['sort']);
    if (servedQueue != null && servedQueue != query.queue.wire) {
      throw const ActiveOrdersException(
        'owner_active_orders served a different queue than requested',
      );
    }
    if (servedSort != null && servedSort != query.sort.wire) {
      throw const ActiveOrdersException(
        'owner_active_orders served a different sort than requested',
      );
    }

    final currency = (raw['currency_code'] ?? '').toString();
    final ordersRaw = raw['orders'];
    final rows = <OrderHistoryRow>[];
    if (ordersRaw is List) {
      for (final row in ordersRaw) {
        if (row is! Map) continue;
        rows.add(_row(row, currency));
      }
    }
    final hasMore = raw['has_more'] == true || raw['truncated'] == true;
    return ActiveOrdersSnapshot(
      rows: rows,
      summary: _summary(raw['summary']),
      currencyCode: currency,
      // The FULL filtered count the server computed — never the loaded page.
      matching: _int(raw['matching'], fallback: rows.length),
      limit: _int(raw['limit'], fallback: 100),
      truncated: hasMore,
      hasMore: hasMore,
      nextCursor: _strOrNull(raw['next_cursor']),
    );
  }

  ActiveOrdersSummary _summary(Object? raw) {
    if (raw is! Map) return const ActiveOrdersSummary();
    final byStatusRaw = raw['by_status'];
    final byStatus = <String, int>{for (final s in kActiveOrderStatuses) s: 0};
    if (byStatusRaw is Map) {
      for (final status in kActiveOrderStatuses) {
        byStatus[status] = _int(byStatusRaw[status]);
      }
    }
    return ActiveOrdersSummary(
      total: _int(raw['total']),
      unpaid: _int(raw['unpaid']),
      byStatus: byStatus,
    );
  }

  OrderHistoryRow _row(Map row, String currency) => OrderHistoryRow(
    orderId: (row['order_id'] ?? '').toString(),
    orderCode: (row['order_code'] ?? '').toString(),
    status: (row['status'] ?? '').toString(),
    orderType: (row['order_type'] ?? '').toString(),
    createdAtLabel: (row['created_at'] ?? '').toString(),
    // The ABSOLUTE instant, for the elapsed age. An unparseable/absent value
    // leaves the age BLANK rather than fabricating one.
    createdAtUtc: _utcOrNull(row['created_at_utc']),
    branchName: _strOrNull(row['branch_name']),
    itemCount: _int(row['item_count']),
    grandTotalMinor: _int(row['grand_total_minor']),
    currencyCode: currency,
    paid: (row['payment_status'] ?? '').toString() == 'paid',
    receiptNumber: _strOrNull(row['receipt_number']),
    customerName: _strOrNull(row['customer_name']),
    tableLabel: _strOrNull(row['table_label']),
    staffName: _strOrNull(row['staff_name']),
    paymentMethod: _strOrNull(row['payment_method']),
    paidAmountMinor: _intOrNull(row['paid_amount_minor']),
  );

  static DateTime? _utcOrNull(Object? value) {
    final s = _strOrNull(value);
    if (s == null) return null;
    return DateTime.tryParse(s)?.toUtc();
  }

  static int _int(Object? value, {int fallback = 0}) =>
      value is int ? value : int.tryParse('$value') ?? fallback;

  static int? _intOrNull(Object? value) {
    if (value == null) return null;
    return value is int ? value : int.tryParse('$value');
  }

  static String? _strOrNull(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }
}
