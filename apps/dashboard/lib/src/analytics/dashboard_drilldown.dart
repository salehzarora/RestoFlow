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
    show
        OrderHistoryQuery,
        OrderHistoryRange,
        OrderStatusFilter,
        OrderTypeFilter,
        PaymentFilter;
import '../orders/orders_screen.dart' show OrdersTab;
import '../state/audit_log_providers.dart' show auditLogQueryProvider;
import '../state/dashboard_providers.dart' show analyticsWindowProvider;
import '../state/order_history_providers.dart'
    show orderHistoryQueryProvider, ordersInitialTabProvider;
import 'analytics_window.dart';
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
    this.orderType = OrderTypeFilter.all,
  });

  /// Unpaid orders — the outstanding-money question.
  const OrdersHistoryDrillDown.unpaid() : this(payment: PaymentFilter.unpaid);

  /// Cash-tendered orders.
  const OrdersHistoryDrillDown.cash() : this(payment: PaymentFilter.cash);

  /// CLIENT-C — the tender methods SERVER-B widened the history RPC to accept.
  ///
  /// WHETHER these may be offered is NOT decided here. This type says what a
  /// drill-down means; whether the deployed server can answer it is a property
  /// of the report the caller is looking at
  /// ([DashboardReport.supportsPaymentMethodHistoryFilters]). Keeping the
  /// capability out of the model means the same drill-down stays valid the
  /// moment the migration is applied, with no model change — and stops a
  /// deployment fact from leaking into a business vocabulary.
  const OrdersHistoryDrillDown.card() : this(payment: PaymentFilter.card);
  const OrdersHistoryDrillDown.bit() : this(payment: PaymentFilter.bit);
  const OrdersHistoryDrillDown.external()
    : this(payment: PaymentFilter.external);

  /// CLIENT-D — the order-type split.
  ///
  /// Ungated, unlike the tender methods: `p_order_type` has been part of
  /// `owner_order_history` since the ORIGINAL ORDERS-HISTORY-001 migration and
  /// is present unchanged in every later definition, so every deployed database
  /// — hosted included — can already answer it. The tokens are the persisted
  /// values the RPC compares against `orders.order_type` directly.
  const OrdersHistoryDrillDown.dineIn()
    : this(orderType: OrderTypeFilter.dineIn);
  const OrdersHistoryDrillDown.takeaway()
    : this(orderType: OrderTypeFilter.takeaway);

  /// Voided orders — their own bucket, never merged with discounts.
  const OrdersHistoryDrillDown.voided()
    : this(status: OrderStatusFilter.voided);

  final PaymentFilter payment;
  final OrderStatusFilter status;
  final OrderTypeFilter orderType;

  @override
  DashboardDestination get destination => DashboardDestination.orders;

  @override
  void applyFilters(WidgetRef ref) {
    ref.read(ordersInitialTabProvider.notifier).state = OrdersTab.history;
    // F2 — THE RANGE TRAVELS WITH THE DRILL-DOWN.
    //
    // A fresh query resets every field the drill-down does not own (see the
    // class comment), and until now the analytics range was one of them — so
    // "1,240 orders over the last 90 days" opened a list of TODAY's orders and
    // silently contradicted the number that was clicked. The committed window is
    // read here rather than stored on the drill-down so there is still exactly
    // one source of truth for "which window am I looking at".
    final window = ref.read(analyticsWindowProvider);
    ref.read(orderHistoryQueryProvider.notifier).state = OrderHistoryQuery(
      payment: payment,
      status: status,
      orderType: orderType,
      // A preset maps to its token; a custom window carries its dates, and the
      // range field is left at its default because the window outranks it.
      range: switch (window) {
        PresetAnalyticsWindow(:final range) => range.asOrderHistoryRange,
        CustomAnalyticsWindow() => OrderHistoryRange.today,
      },
      customWindow: switch (window) {
        PresetAnalyticsWindow() => null,
        final CustomAnalyticsWindow w => w,
      },
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
