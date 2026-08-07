/// DASHBOARD-OWNER-ANALYTICS-F0.3 — the typed drill-down contract.
///
/// An analytics tile that wants to say "show me the orders behind this number"
/// previously had no way to say it. The only tool was `_select(7)`, which
/// changes the tab and nothing else, so the owner landed on whatever filters
/// happened to be left over from their last visit — a number on the Overview
/// and a list on Orders that do not describe the same thing. That is worse than
/// no drill-down, because it looks like an answer.
///
/// A [DashboardDrillDown] is a complete instruction: WHERE to go and WHAT the
/// target must be showing when it arrives. It is a sealed hierarchy rather than
/// a `Map<String, dynamic>` so a typo cannot compile and so every target's
/// required filters are visible in one place.
///
/// TENANT SAFETY. A drill-down carries BUSINESS filters only — never
/// organization, restaurant, branch or membership. Scope stays owned by the
/// authenticated context, so a drill-down can never widen what its originator
/// was allowed to see. This is enforced by construction: none of the payloads
/// below has a field capable of expressing scope.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/audit_log_models.dart' show AuditCategory, AuditQuery;
import '../data/order_history_models.dart'
    show OrderHistoryQuery, OrderStatusFilter, PaymentFilter;
import '../orders/orders_screen.dart' show OrdersTab;
import '../state/audit_log_providers.dart' show auditLogQueryProvider;
import '../state/order_history_providers.dart'
    show orderHistoryQueryProvider, ordersInitialTabProvider;
import 'dashboard_destination.dart';

/// An instruction to move the owner to a surface with specific filters applied.
sealed class DashboardDrillDown {
  const DashboardDrillDown();

  /// The surface to land on.
  DashboardDestination get destination;

  /// Writes this drill-down's filters into the target's providers.
  ///
  /// Called BEFORE the destination is selected, so the target subtree reads the
  /// intended state on its very first build rather than flashing stale results
  /// and then correcting itself.
  void applyFilters(WidgetRef ref);
}

/// Land on Orders → History with an explicit filter set.
///
/// FILTER SEMANTICS (deliberate, and tested): the drill-down writes a FRESH
/// [OrderHistoryQuery] rather than `copyWith`-ing whatever the owner last left
/// behind. A leftover status or search from an earlier visit would silently
/// narrow the very list this number promised to explain — "12 unpaid" opening a
/// list of 3 because a stale `takeaway` filter survived. Every field the
/// drill-down does not own is therefore reset to its documented default, and
/// only the fields named here are set.
final class OrdersHistoryDrillDown extends DashboardDrillDown {
  const OrdersHistoryDrillDown({
    this.payment = PaymentFilter.all,
    this.status = OrderStatusFilter.all,
  });

  /// Unpaid orders — the outstanding-money question.
  const OrdersHistoryDrillDown.unpaid() : this(payment: PaymentFilter.unpaid);

  /// Cash-tendered orders. Only `cash` is expressible today; card / bit /
  /// external are Phase-A server work and deliberately absent here.
  const OrdersHistoryDrillDown.cash() : this(payment: PaymentFilter.cash);

  /// Voided orders — their own bucket, never merged with discounts.
  const OrdersHistoryDrillDown.voided()
    : this(status: OrderStatusFilter.voided);

  final PaymentFilter payment;
  final OrderStatusFilter status;

  @override
  DashboardDestination get destination => DashboardDestination.orders;

  @override
  void applyFilters(WidgetRef ref) {
    ref.read(ordersInitialTabProvider.notifier).state = OrdersTab.history;
    // A fresh query, not copyWith: see the class comment.
    ref.read(orderHistoryQueryProvider.notifier).state = OrderHistoryQuery(
      payment: payment,
      status: status,
    );
  }
}

/// Land on Orders → Active, the live operations view.
///
/// Carries no filters: the Active surface owns its own stage/queue controls and
/// this drill-down deliberately does not disturb them. Its whole job is to make
/// "open orders" on the Overview reach the screen that answers it, through the
/// same typed seam as everything else.
final class OrdersActiveDrillDown extends DashboardDrillDown {
  const OrdersActiveDrillDown();

  @override
  DashboardDestination get destination => DashboardDestination.orders;

  @override
  void applyFilters(WidgetRef ref) {
    ref.read(ordersInitialTabProvider.notifier).state = OrdersTab.active;
  }
}

/// Land on the Activity log filtered to one category.
///
/// Only `category` is written. Range, branch, actor and the sensitive-only
/// toggle stay as the owner left them: unlike the history case these cannot
/// make the destination misleading, because the category IS the claim being
/// explained and the remaining controls are visibly presented on that screen.
final class ActivityDrillDown extends DashboardDrillDown {
  const ActivityDrillDown(this.category);

  /// Discount events — the Overview's discount total.
  const ActivityDrillDown.discounts() : this(AuditCategory.discounts);

  final AuditCategory category;

  @override
  DashboardDestination get destination => DashboardDestination.activity;

  @override
  void applyFilters(WidgetRef ref) {
    final current = ref.read(auditLogQueryProvider);
    ref.read(auditLogQueryProvider.notifier).state = AuditQuery(
      range: current.range,
      category: category,
      sensitiveOnly: current.sensitiveOnly,
      branch: current.branch,
      actor: current.actor,
    );
  }
}

/// Executes a drill-down: apply filters, THEN navigate.
///
/// The ordering is the whole point and is asserted by test. The shell rebuilds
/// each tab inside a fresh `KeyedSubtree`, so writing filters first means the
/// target's very first build already reads the intended state. Navigating first
/// would show the previous list for a frame and then correct itself — a visible
/// flash of the wrong answer to the question the owner just asked.
///
/// [navigate] is injected rather than reaching into the shell, so this stays
/// pure enough to unit test and so the shell keeps sole ownership of its tab
/// state. F0.4 will pass the shell's named `_goTo` here when the KPI cards gain
/// their tap handlers.
void runDashboardDrillDown({
  required WidgetRef ref,
  required DashboardDrillDown drillDown,
  required void Function(DashboardDestination destination) navigate,
}) {
  drillDown.applyFilters(ref);
  navigate(drillDown.destination);
}
