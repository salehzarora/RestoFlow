import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/data/active_orders_models.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/audit_log_presentation.dart';
import 'package:restoflow_dashboard/src/data/demo_order_store.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/data/active_orders_repository.dart';
import 'package:restoflow_dashboard/src/data/order_history_repository.dart';
import 'package:restoflow_dashboard/src/orders/orders_screen.dart';
import 'package:restoflow_dashboard/src/state/active_orders_providers.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/state/order_history_providers.dart'
    show demoOrderStoreProvider;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// MONEY-SETTLEMENT-CONSISTENCY-001 — the Dashboard half.
///
/// ONE settlement rule everywhere: a ZERO-TOTAL order is NON-CHARGEABLE (settled, owes
/// nothing, no payment row), a positive total is settled only when a completed payment
/// COVERS it, and an UNDER-COVERED order stays visibly unsettled. No screen, counter,
/// badge or filter may use the payment-row MARKER any more.
Future<AppLocalizations> _l(String code) =>
    AppLocalizations.delegate.load(Locale(code));

final DateTime _now = DateTime.utc(2026, 7, 15, 13, 38);
DateTime _clock() => _now;

DemoOrder _order(
  String id, {
  required String status,
  int total = 4600,
  int? paidAmount,
  int minutesAgo = 20,
}) => DemoOrder(
  daysAgo: 0,
  minutesAgo: minutesAgo,
  detail: OrderDetail(
    orderId: id,
    orderCode: '#$id',
    status: status,
    orderType: 'dine_in',
    currencyCode: 'ILS',
    subtotalMinor: total,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: total,
    createdAtLabel: '12:43',
    branchName: 'Downtown',
    items: [
      OrderDetailItem(name: 'Lamb Chops', quantity: 1, lineTotalMinor: total),
    ],
    payments: paidAmount == null
        ? const []
        : [
            OrderPayment(
              method: 'cash',
              status: 'completed',
              amountMinor: paidAmount,
            ),
          ],
  ),
);

/// The canonical matrix: comped, covered, under-covered, unpaid.
List<DemoOrder> _fixtures() => [
  _order('zero', status: 'served', total: 0, minutesAgo: 50),
  _order('covered', status: 'served', total: 4600, paidAmount: 4600),
  _order('under', status: 'served', total: 4600, paidAmount: 2000),
  _order('unpaid', status: 'served', total: 4600, minutesAgo: 10),
  _order('zero-ready', status: 'ready', total: 0, minutesAgo: 5),
];

DemoOrderStore _store() => DemoOrderStore(_fixtures());

OrderDetail _detail(DemoOrderStore store, String id) =>
    store.orders.firstWhere((o) => o.detail.orderId == id).detail;

const ActiveOrdersQuery _allActive = ActiveOrdersQuery(
  queue: ActiveOrderQueue.allActive,
  sort: ActiveOrdersSort.oldest,
);

Widget _wrap(DemoOrderStore store, {String locale = 'en'}) => ProviderScope(
  overrides: [
    runtimeConfigProvider.overrideWithValue(
      RuntimeConfig.test(isDemoMode: true),
    ),
    demoOrderStoreProvider.overrideWithValue(store),
    activeOrdersClockProvider.overrideWithValue(_clock),
    activeOrdersQueryProvider.overrideWith((ref) => _allActive),
    activeOrdersPollIntervalProvider.overrideWithValue(null),
    dashboardMembershipProvider.overrideWithValue(
      const MembershipContext(
        id: 'm1',
        organizationId: 'org-1',
        organizationName: 'Org 1',
        restaurantId: 'rest-1',
        restaurantName: 'Rest 1',
        branchId: 'branch-1',
        branchName: 'Branch 1',
        role: MembershipRole.manager,
        status: 'active',
      ),
    ),
  ],
  child: MaterialApp(
    locale: Locale(locale),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: const Scaffold(body: OrdersScreen()),
  ),
);

void _sized(WidgetTester tester, double width, [double height = 2600]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  // ===== 28. the unpaid COUNTER excludes an order that owes nothing ============
  test(
    '28 unpaid_count excludes zero-total orders and includes under-covered',
    () async {
      final repo = DemoActiveOrdersRepository(store: _store(), clock: _clock);
      final snap = await repo.loadActive(_allActive);

      // `unpaid` = OUTSTANDING MONEY. Only `under` and `unpaid` still owe.
      expect(snap.summary.unpaid, 2);
    },
  );

  // ===== 29. a zero-total order is LABELLED non-chargeable ====================
  test(
    '29 a ZERO-TOTAL order is non_chargeable — never Paid, never Unpaid',
    () {
      final d = _detail(_store(), 'zero');

      expect(d.grandTotalMinor, 0);
      expect(d.completedPayment, isNull);
      expect(d.settlement, SettlementState.notChargeable);
      expect(d.settlement.isSettled, isTrue, reason: 'it owes nothing');
      expect(d.settlement, isNot(SettlementState.paid));
      expect(d.settlement, isNot(SettlementState.unpaid));
    },
  );

  // ===== P2. a NEGATIVE total FAILS CLOSED — it is never "No charge" ==========
  test('a NEGATIVE total fails closed: not settled, and NOT non-chargeable', () {
    // Unlike the POS view (which clamps at zero), OrderDetail carries the server's total
    // verbatim — so this is the model where a corrupt negative is actually reachable.
    // A negative total is a MONEY DEFECT, not "nothing to pay". Rendering it as
    // "No charge" would hide it behind a reassuring chip; the canonical rule fails closed.
    final store = DemoOrderStore([
      _order('negative', status: 'served', total: -1),
    ]);
    final d = _detail(store, 'negative');

    expect(
      d.isFullySettled,
      isFalse,
      reason: 'never settle an impossible total',
    );
    expect(d.settlement, SettlementState.unpaid);
    expect(d.settlement, isNot(SettlementState.notChargeable));
    expect(d.settlement.isSettled, isFalse);
    // ...and it therefore cannot be completed.
    expect(store.complete('negative'), DemoCompleteRefusal.notPaid);
  });

  // ===== 30. an UNDER-COVERED order stays visibly unsettled ===================
  test(
    '30 an UNDER-COVERED order is unpaid, not paid (marker would have lied)',
    () {
      final d = _detail(_store(), 'under');

      expect(d.completedPayment, isNotNull, reason: 'a real payment exists');
      expect(d.settlement, SettlementState.unpaid);
      expect(d.settlement.isSettled, isFalse);
    },
  );

  test('30b a fully COVERED order is paid', () {
    expect(_detail(_store(), 'covered').settlement, SettlementState.paid);
  });

  // ===== 31. the payment FILTER follows canonical settlement ==================
  test(
    '31 the paid/unpaid filter follows SETTLEMENT, not the payment marker',
    () async {
      final repo = DemoActiveOrdersRepository(store: _store(), clock: _clock);

      final unpaid = await repo.loadActive(
        _allActive.copyWith(payment: PaymentFilter.unpaid),
      );
      final unpaidIds = unpaid.rows.map((r) => r.orderId).toSet();
      expect(unpaidIds, {
        'under',
        'unpaid',
      }, reason: 'only orders that STILL OWE money');
      expect(
        unpaidIds.contains('zero'),
        isFalse,
        reason: 'a comped order owes nothing — it is not unpaid work',
      );

      final paid = await repo.loadActive(
        _allActive.copyWith(payment: PaymentFilter.paid),
      );
      final paidIds = paid.rows.map((r) => r.orderId).toSet();
      expect(paidIds, {'zero', 'covered', 'zero-ready'});
      expect(
        paidIds.contains('under'),
        isFalse,
        reason: 'an under-covered order is NOT settled',
      );
    },
  );

  // ===== 32. the completion confirmation follows canonical settlement =========
  testWidgets(
    '32 the Complete action follows settlement (zero-total is completable)',
    (tester) async {
      _sized(tester, 1320);
      await tester.pumpWidget(_wrap(_store()));
      await tester.pumpAndSettle();

      // A comped served order owes nothing -> it is settled -> completable.
      await tester.tap(find.byKey(const Key('active-order-card-zero')));
      await tester.pumpAndSettle();
      final zeroBtn = tester.widget<FilledButton>(
        find.byKey(const Key('order-complete-button')),
      );
      expect(zeroBtn.onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('order-detail-close')));
      await tester.pumpAndSettle();

      // An UNDER-COVERED order still owes -> blocked (the server would refuse it).
      await tester.tap(find.byKey(const Key('active-order-card-under')));
      await tester.pumpAndSettle();
      final underBtn = tester.widget<FilledButton>(
        find.byKey(const Key('order-complete-button')),
      );
      expect(underBtn.onPressed, isNull);
      expect(
        find.byKey(const Key('order-complete-unpaid-blocked')),
        findsOneWidget,
      );
    },
  );

  // ===== 33. HISTORY renders a zero-total order correctly =====================
  testWidgets('33 History renders a zero-total order as "No charge"', (
    tester,
  ) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    final store = _store();
    // Complete it so it lands in history (settled + served -> the manual recovery path).
    expect(store.complete('zero'), isNull);

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('orders-tab-history')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.dashboardNoCharge), findsWidgets);
  });

  // ===== 34. the manual recovery action is offered only when settled + served ==
  test('34 the manual completion requires SETTLED and SERVED', () {
    final store = _store();

    // settled (comped) + served -> allowed
    expect(store.complete('zero'), isNull);
    // settled (covered) + served -> allowed
    expect(store.complete('covered'), isNull);
    // under-covered + served -> refused (D-025, the hardened gate)
    expect(store.complete('under'), DemoCompleteRefusal.notPaid);
    // settled but NOT served (still in the kitchen) -> refused
    expect(store.complete('zero-ready'), DemoCompleteRefusal.invalidTransition);
  });

  // ===== the demo store mirrors the server's zero-tender refusal ==============
  test(
    '34b the demo REFUSES a payment on a non-chargeable order (as the server does)',
    () {
      final store = _store();
      final outcome = store.recordPayment('zero-ready');

      expect(
        outcome.applied,
        isFalse,
        reason: 'the server rejects a zero tender',
      );
      expect(_detail(store, 'zero-ready').payments, isEmpty);
    },
  );

  // ===== the Activity Log now says WHY a discount was denied ==================
  test(
    '34c a discount denial renders a localized REASON (never a raw token)',
    () async {
      for (final code in ['en', 'ar', 'he']) {
        final l10n = await _l(code);
        final view = AuditEventPresenter(l10n, 'ILS').present(
          const AuditEvent(
            eventId: 'ae-dd',
            action: 'order.discount_denied',
            category: 'discounts',
            occurredAtLabel: '2026-07-15 14:05',
            actorName: 'Manager M.',
            oldValues: {},
            newValues: {
              'attempted_action': 'apply_discount',
              'order_code': '#AFE002',
              'role': 'manager',
              'denied_reason': 'order_has_completed_payment',
            },
          ),
        );

        String? valueFor(String label) {
          for (final c in view.changes) {
            if (c.label == label) return c.newValue;
          }
          return null;
        }

        expect(
          view.categoryLabel,
          l10n.activityLogCategoryDiscounts,
          reason: code,
        );
        expect(
          view.categoryLabel,
          isNot(l10n.activityLogCategoryOther),
          reason: code,
        );
        expect(
          valueFor(l10n.activityLogFieldDeniedReason),
          l10n.activityLogDeniedOrderHasPayment,
          reason: '$code: the owner is TOLD why, in words, not a raw token',
        );
        expect(
          valueFor(l10n.activityLogFieldOrderCode),
          '#AFE002',
          reason: code,
        );
        // Money-free (T-003) and identifier-free.
        for (final c in view.changes) {
          expect(c.newValue, isNot(contains('₪')));
        }
      }
    },
  );
}
