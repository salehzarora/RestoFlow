import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_destination.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_drilldown.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/state/audit_log_providers.dart';
import 'package:restoflow_dashboard/src/state/order_history_providers.dart';

/// DASHBOARD-OWNER-ANALYTICS-F0.3 / F0.7 — the typed drill-down seam.
///
/// What these tests defend: an owner taps a number and lands on a list that
/// answers THAT number. The old seam (`_select(7)`) could only change the tab,
/// so the destination showed whatever filters were left over from a previous
/// visit — an answer-shaped screen showing a different question.
///
/// Runs a callback with a live WidgetRef inside its own ProviderScope, so each
/// case starts from genuinely fresh provider state.
///
/// The ref is CAPTURED during build and the body runs afterwards. Riverpod
/// forbids writing a provider while the tree is building, and a drill-down is
/// by nature a write — it happens in response to a tap, never inside a build.
/// Invoking it after the pump models the real call site accurately.
Future<void> withRef(
  WidgetTester tester,
  void Function(WidgetRef ref) body, {
  List<Override> overrides = const [],
}) async {
  late WidgetRef captured;
  // A UNIQUE key per invocation. Without it Flutter reuses the element
  // (same widget type in the same slot) and the 'new' ProviderScope is the
  // SAME container — which would make a scope-isolation test pass
  // vacuously by never creating a second scope at all.
  _scopeSeq++;
  await tester.pumpWidget(
    ProviderScope(
      key: ValueKey('drilldown-scope-$_scopeSeq'),
      overrides: overrides,
      child: Consumer(
        builder: (context, ref, _) {
          captured = ref;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  body(captured);
  await tester.pump();
}

int _scopeSeq = 0;

void main() {
  group('F0.3 DashboardDestination', () {
    test('records the shell tab order exactly, without renumbering it', () {
      expect(DashboardDestination.overview.tabIndex, 0);
      expect(DashboardDestination.menu.tabIndex, 1);
      expect(DashboardDestination.devices.tabIndex, 2);
      expect(DashboardDestination.printers.tabIndex, 3);
      expect(DashboardDestination.staff.tabIndex, 4);
      expect(DashboardDestination.tables.tabIndex, 5);
      expect(DashboardDestination.users.tabIndex, 6);
      expect(DashboardDestination.orders.tabIndex, 7);
      expect(DashboardDestination.activity.tabIndex, 8);
      expect(DashboardDestination.settings.tabIndex, 9);
    });

    test(
      'tab indexes are unique — two names cannot resolve to one surface',
      () {
        final seen = DashboardDestination.values.map((d) => d.tabIndex).toSet();
        expect(seen.length, DashboardDestination.values.length);
      },
    );

    test('fromIndex round-trips every destination', () {
      for (final d in DashboardDestination.values) {
        expect(DashboardDestination.fromIndex(d.tabIndex), d);
      }
    });

    test('an UNKNOWN index resolves to settings, mirroring the shell default '
        'arm rather than crashing', () {
      // The shell's switch has no explicit `9 =>`; Settings is the `_ =>`
      // default. This pins that behaviour so a future edit cannot change what
      // an out-of-range index does without a failing test.
      expect(DashboardDestination.fromIndex(99), DashboardDestination.settings);
      expect(DashboardDestination.fromIndex(-1), DashboardDestination.settings);
    });
  });

  group('F0.3 drill-down destinations', () {
    test('each drill-down names its own destination', () {
      expect(
        const OrdersHistoryDrillDown.unpaid().destination,
        DashboardDestination.orders,
      );
      expect(
        const OrdersActiveDrillDown().destination,
        DashboardDestination.orders,
      );
      expect(
        const ActivityDrillDown.discounts().destination,
        DashboardDestination.activity,
      );
    });
  });

  group('F0.7 filters are written exactly', () {
    testWidgets('unpaid -> Orders History with payment=unpaid', (tester) async {
      await withRef(tester, (ref) {
        const OrdersHistoryDrillDown.unpaid().applyFilters(ref);
        expect(ref.read(ordersInitialTabProvider), OrdersTab.history);
        final q = ref.read(orderHistoryQueryProvider);
        expect(q.payment, PaymentFilter.unpaid);
        expect(q.status, OrderStatusFilter.all);
      });
    });

    testWidgets('voided -> Orders History with status=voided', (tester) async {
      await withRef(tester, (ref) {
        const OrdersHistoryDrillDown.voided().applyFilters(ref);
        expect(ref.read(ordersInitialTabProvider), OrdersTab.history);
        final q = ref.read(orderHistoryQueryProvider);
        expect(q.status, OrderStatusFilter.voided);
        // Voids are their own bucket — never expressed as a payment filter.
        expect(q.payment, PaymentFilter.all);
      });
    });

    testWidgets('cash -> Orders History with payment=cash', (tester) async {
      await withRef(tester, (ref) {
        const OrdersHistoryDrillDown.cash().applyFilters(ref);
        expect(ref.read(orderHistoryQueryProvider).payment, PaymentFilter.cash);
      });
    });

    testWidgets('active -> Orders Active, and does NOT touch history filters', (
      tester,
    ) async {
      await withRef(tester, (ref) {
        // A user-chosen history filter that the Active drill-down must not eat.
        ref.read(orderHistoryQueryProvider.notifier).state =
            const OrderHistoryQuery(status: OrderStatusFilter.completed);
        const OrdersActiveDrillDown().applyFilters(ref);
        expect(ref.read(ordersInitialTabProvider), OrdersTab.active);
        expect(
          ref.read(orderHistoryQueryProvider).status,
          OrderStatusFilter.completed,
        );
      });
    });

    testWidgets('discounts -> Activity category=discounts', (tester) async {
      await withRef(tester, (ref) {
        const ActivityDrillDown.discounts().applyFilters(ref);
        expect(
          ref.read(auditLogQueryProvider).category,
          AuditCategory.discounts,
        );
      });
    });
  });

  group('F0.7 stale-filter safety', () {
    testWidgets(
      'a history drill-down RESETS unrelated leftover filters, so the '
      'list cannot silently contradict the number that opened it',
      (tester) async {
        await withRef(tester, (ref) {
          // Simulate a previous visit: the owner narrowed to completed takeaway
          // orders and typed a search. Left in place, "unpaid" would open a list
          // that is unpaid AND completed AND takeaway AND matching "burger" —
          // almost certainly a different count from the KPI just tapped.
          ref
              .read(orderHistoryQueryProvider.notifier)
              .state = const OrderHistoryQuery(
            range: OrderHistoryRange.last30,
            search: 'burger',
            status: OrderStatusFilter.completed,
            orderType: OrderTypeFilter.takeaway,
            payment: PaymentFilter.paid,
          );

          const OrdersHistoryDrillDown.unpaid().applyFilters(ref);

          final q = ref.read(orderHistoryQueryProvider);
          expect(q.payment, PaymentFilter.unpaid, reason: 'the owned filter');
          expect(q.status, OrderStatusFilter.all, reason: 'reset');
          expect(q.orderType, OrderTypeFilter.all, reason: 'reset');
          expect(q.search, '', reason: 'reset');
          expect(q.range, OrderHistoryRange.today, reason: 'reset to default');
        });
      },
    );

    testWidgets('an Activity drill-down PRESERVES the visible surrounding '
        'controls it does not own', (tester) async {
      await withRef(tester, (ref) {
        ref.read(auditLogQueryProvider.notifier).state = const AuditQuery(
          range: AuditRange.last7,
          category: AuditCategory.staff,
          sensitiveOnly: true,
        );

        const ActivityDrillDown.discounts().applyFilters(ref);

        final q = ref.read(auditLogQueryProvider);
        expect(q.category, AuditCategory.discounts, reason: 'the owned filter');
        // Unlike history, these are visibly presented on the Activity screen,
        // so preserving them cannot mislead about what is being shown.
        expect(q.range, AuditRange.last7);
        expect(q.sensitiveOnly, isTrue);
      });
    });

    testWidgets('separate ProviderScopes do not bleed state into each other', (
      tester,
    ) async {
      await withRef(tester, (ref) {
        const OrdersHistoryDrillDown.unpaid().applyFilters(ref);
        expect(
          ref.read(orderHistoryQueryProvider).payment,
          PaymentFilter.unpaid,
        );
      });
      // A brand-new scope must start from the documented defaults, not from the
      // previous scope's drill-down.
      await withRef(tester, (ref) {
        expect(ref.read(orderHistoryQueryProvider).payment, PaymentFilter.all);
        expect(ref.read(ordersInitialTabProvider), OrdersTab.active);
      });
    });

    testWidgets('the default Orders landing view is unchanged (active)', (
      tester,
    ) async {
      await withRef(tester, (ref) {
        expect(ref.read(ordersInitialTabProvider), OrdersTab.active);
      });
    });
  });

  group('F0.7 ordering + tenant safety', () {
    testWidgets('filters are applied BEFORE navigation', (tester) async {
      await withRef(tester, (ref) {
        final events = <String>[];
        runDashboardDrillDown(
          ref: ref,
          drillDown: const OrdersHistoryDrillDown.unpaid(),
          navigate: (d) {
            // By the time navigation runs, the target state must already be in
            // place — otherwise the destination renders the old list for a
            // frame before correcting itself.
            expect(
              ref.read(orderHistoryQueryProvider).payment,
              PaymentFilter.unpaid,
            );
            events.add('navigate:${d.name}');
          },
        );
        expect(events, ['navigate:orders']);
      });
    });

    test('no drill-down payload can express tenant scope', () {
      // Enforced by construction: these are the only fields that exist. If a
      // future edit adds an org/restaurant/branch field, this test is the place
      // that should stop it.
      const history = OrdersHistoryDrillDown.unpaid();
      expect(history.payment, isA<PaymentFilter>());
      expect(history.status, isA<OrderStatusFilter>());
      const activity = ActivityDrillDown.discounts();
      expect(activity.category, isA<AuditCategory>());
    });

    testWidgets('a drill-down writes ONLY its target providers', (
      tester,
    ) async {
      await withRef(tester, (ref) {
        final auditBefore = ref.read(auditLogQueryProvider);
        const OrdersHistoryDrillDown.unpaid().applyFilters(ref);
        // An Orders drill-down must not disturb the Activity surface.
        expect(ref.read(auditLogQueryProvider).category, auditBefore.category);
        expect(ref.read(auditLogQueryProvider).range, auditBefore.range);
      });
    });
  });
}
