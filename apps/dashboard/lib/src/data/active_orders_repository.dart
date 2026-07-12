/// The ACTIVE-ORDERS data SEAM (ACTIVE-ORDERS-001).
///
/// READ-ONLY: the seam exposes exactly one method, and it reads. There is no
/// mutation entry point here, by construction.
///
/// The demo implementation serves the SAME deterministic dataset as
/// [DemoOrderHistoryRepository] ([demoOrderHistory]), so opening an active row
/// and loading its detail resolves through the existing detail path with no
/// second fixture set. The real implementation ([RealActiveOrdersRepository])
/// reads the `public.owner_active_orders` RPC over the same authenticated
/// transport the rest of the real dashboard uses. Same return type, so the UI
/// never branches on the source.
library;

import 'active_orders_models.dart';
import 'audit_log_models.dart' show AuditBranchOption;
import 'order_history_models.dart';
import 'order_history_repository.dart';

/// Loads the active-order board for a scope.
abstract class ActiveOrdersRepository {
  /// The current active board for [query]. Implementations may fail (network,
  /// auth, RLS) — surfaced as an error, never as fabricated or stale-as-live data.
  Future<ActiveOrdersSnapshot> loadActive(ActiveOrdersQuery query);
}

/// A failure loading the active board.
class ActiveOrdersException implements Exception {
  const ActiveOrdersException(this.message);

  final String message;

  @override
  String toString() => 'ActiveOrdersException: $message';
}

/// Serves the active board from the shared deterministic demo dataset — honest
/// demo data, no backend. Filters in memory with the SAME rules as the RPC
/// (canonical active set, scope-only summary, FIFO order, capped page) so the UI
/// behaves exactly as it will against the real backend.
class DemoActiveOrdersRepository implements ActiveOrdersRepository {
  DemoActiveOrdersRepository({
    List<DemoOrder>? orders,
    DateTime Function()? clock,
    this.failureMessage,
    this.limit = 100,
  }) : _orders = orders ?? demoOrderHistory(),
       _clock = clock ?? DateTime.now;

  final List<DemoOrder> _orders;
  final DateTime Function() _clock;

  /// When non-null the load throws an [ActiveOrdersException] with this message
  /// (drives/tests the error state).
  final String? failureMessage;

  /// The demo page cap (mirrors the RPC's bounded board).
  final int limit;

  @override
  Future<ActiveOrdersSnapshot> loadActive(ActiveOrdersQuery query) async {
    final message = failureMessage;
    if (message != null) throw ActiveOrdersException(message);

    final now = _clock();

    // The SCOPE: active orders on the selected branch (or every demo branch).
    final scoped = _orders
        .where((o) => isActiveOrderStatus(o.detail.status))
        .where((o) => _inBranch(o, query.branch))
        .toList();

    final matched = scoped.where((o) => _matches(o, query)).toList()
      ..sort((a, b) {
        // FIFO: oldest first, id breaking ties so equal ages order stably.
        final byAge = _minutesAgo(b).compareTo(_minutesAgo(a));
        if (byAge != 0) return byAge;
        return a.detail.orderId.compareTo(b.detail.orderId);
      });

    final page = matched.take(limit).toList();
    return ActiveOrdersSnapshot(
      rows: [for (final o in page) _rowOf(o, now)],
      summary: _summaryOf(scoped),
      currencyCode: scoped.isEmpty ? 'ILS' : scoped.first.detail.currencyCode,
      matching: matched.length,
      limit: limit,
      truncated: matched.length > page.length,
    );
  }

  bool _inBranch(DemoOrder o, AuditBranchOption? branch) =>
      branch == null || o.branchId == branch.branchId;

  bool _matches(DemoOrder o, ActiveOrdersQuery q) {
    final d = o.detail;
    if (q.stage.wire != null && d.status != q.stage.wire) return false;
    if (q.orderType.wire != null && d.orderType != q.orderType.wire) {
      return false;
    }
    final paid = d.completedPayment != null;
    switch (q.payment) {
      case PaymentFilter.paid:
        if (!paid) return false;
      case PaymentFilter.unpaid:
        if (paid) return false;
      case PaymentFilter.cash:
        if (d.completedPayment?.method != 'cash') return false;
      case PaymentFilter.all:
        break;
    }
    final search = q.searchOrNull;
    if (search != null) {
      final needle = search.toLowerCase().replaceAll('#', '');
      final haystacks = <String?>[
        d.orderCode.toLowerCase().replaceAll('#', ''),
        d.customerName?.toLowerCase(),
        d.tableLabel?.toLowerCase(),
        d.receiptNumber?.toLowerCase(),
      ];
      if (!haystacks.any((h) => h != null && h.contains(needle))) return false;
    }
    return true;
  }

  /// The scope's picture — deliberately ignores the list filters (as the RPC does).
  ActiveOrdersSummary _summaryOf(List<DemoOrder> scoped) {
    final byStatus = <String, int>{for (final s in kActiveOrderStatuses) s: 0};
    var unpaid = 0;
    for (final o in scoped) {
      byStatus[o.detail.status] = (byStatus[o.detail.status] ?? 0) + 1;
      if (o.detail.completedPayment == null) unpaid++;
    }
    return ActiveOrdersSummary(
      total: scoped.length,
      unpaid: unpaid,
      byStatus: byStatus,
    );
  }

  /// The demo age, in minutes. Falls back to the day offset when an order
  /// carries no explicit `minutesAgo`.
  int _minutesAgo(DemoOrder o) => o.minutesAgo ?? o.daysAgo * 24 * 60;

  OrderHistoryRow _rowOf(DemoOrder o, DateTime now) {
    final d = o.detail;
    final pay = d.completedPayment;
    var items = 0;
    for (final it in d.items) {
      items += it.quantity;
    }
    return OrderHistoryRow(
      orderId: d.orderId,
      orderCode: d.orderCode,
      status: d.status,
      orderType: d.orderType,
      createdAtLabel: d.createdAtLabel ?? '',
      // Deterministic: the injected clock minus the fixture's age, so the demo
      // board never depends on the wall clock.
      createdAtUtc: now.toUtc().subtract(Duration(minutes: _minutesAgo(o))),
      branchName: d.branchName,
      itemCount: items,
      grandTotalMinor: d.grandTotalMinor,
      currencyCode: d.currencyCode,
      paid: pay != null,
      receiptNumber: d.receiptNumber,
      customerName: d.customerName,
      tableLabel: d.tableLabel,
      staffName: d.staffName,
      paymentMethod: pay?.method,
      paidAmountMinor: pay?.amountMinor,
    );
  }
}
