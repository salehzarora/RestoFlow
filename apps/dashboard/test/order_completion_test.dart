import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/data/demo_order_store.dart';
import 'package:restoflow_dashboard/src/data/order_completion_repository.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/data/order_history_repository.dart';
import 'package:restoflow_dashboard/src/orders/order_complete_action.dart';
import 'package:restoflow_dashboard/src/orders/orders_screen.dart';
import 'package:restoflow_dashboard/src/state/active_orders_providers.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/state/order_completion_providers.dart';
import 'package:restoflow_dashboard/src/state/order_history_providers.dart'
    show demoOrderStoreProvider;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// ORDER-COMPLETION-001 — the safe served -> completed workflow:
/// eligibility (canonical state only), role gating, the D-025 payment policy,
/// confirmation, one-write-per-double-tap, the board draining into History,
/// localized failures, and the read-only guarantees around it.
Future<AppLocalizations> _l(String code) =>
    AppLocalizations.delegate.load(Locale(code));

final DateTime _now = DateTime.utc(2026, 7, 13, 13, 38);
DateTime _clock() => _now;

DemoOrder _order(
  String id, {
  required String status,
  bool paid = true,
  int total = 4600,
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
    payments: paid
        ? [
            OrderPayment(
              method: 'cash',
              status: 'completed',
              amountMinor: total,
            ),
          ]
        : const [],
  ),
);

/// served+PAID (completable), served+UNPAID (blocked by D-025), and one order at
/// every other state (never completable).
List<DemoOrder> _fixtures() => [
  _order('paid-served', status: 'served', minutesAgo: 50),
  _order('unpaid-served', status: 'served', paid: false, minutesAgo: 40),
  _order('ready', status: 'ready', minutesAgo: 30),
  _order('preparing', status: 'preparing', minutesAgo: 20),
  _order('submitted', status: 'submitted', minutesAgo: 10),
];

DemoOrderStore _store() => DemoOrderStore(_fixtures());

Widget _wrap(
  DemoOrderStore store, {
  String locale = 'en',
  MembershipContext? membership,
  OrderCompletionError? forcedError,
}) => ProviderScope(
  overrides: [
    runtimeConfigProvider.overrideWithValue(
      RuntimeConfig.test(isDemoMode: true),
    ),
    demoOrderStoreProvider.overrideWithValue(store),
    activeOrdersClockProvider.overrideWithValue(_clock),
    dashboardMembershipProvider.overrideWithValue(membership),
    if (forcedError != null)
      orderCompletionRepositoryProvider.overrideWithValue(
        DemoOrderCompletionRepository(store, failureError: forcedError),
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

MembershipContext _membership(MembershipRole role) => MembershipContext(
  id: 'm1',
  organizationId: 'org-1',
  organizationName: 'Org 1',
  restaurantId: 'rest-1',
  restaurantName: 'Rest 1',
  branchId: 'branch-1',
  branchName: 'Branch 1',
  role: role,
  status: 'active',
);

/// Opens the detail sheet for one active-board row.
Future<void> _openDetail(WidgetTester tester, String orderId) async {
  await tester.tap(find.byKey(Key('active-order-card-$orderId')));
  await tester.pumpAndSettle();
}

void main() {
  // ===== A. eligibility (the CANONICAL state, never a UI guess) ==============
  testWidgets('A1 the action appears for an eligible PAID served order', (
    tester,
  ) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    await tester.pumpWidget(_wrap(_store()));
    await tester.pumpAndSettle();

    await _openDetail(tester, 'paid-served');
    expect(find.byKey(const Key('order-complete-button')), findsOneWidget);
    expect(find.text(l10n.ordersCompleteAction), findsWidgets);
    // enabled
    final btn = tester.widget<FilledButton>(
      find.byKey(const Key('order-complete-button')),
    );
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('A2 the action is ABSENT for every ineligible status', (
    tester,
  ) async {
    _sized(tester, 1320);
    await tester.pumpWidget(_wrap(_store()));
    await tester.pumpAndSettle();

    for (final id in ['ready', 'preparing', 'submitted']) {
      await _openDetail(tester, id);
      expect(
        find.byKey(const Key('order-complete-button')),
        findsNothing,
        reason: '$id must not be completable',
      );
      await tester.tap(find.byKey(const Key('order-detail-close')));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('A3 a COMPLETED order offers no completion (already terminal)', (
    tester,
  ) async {
    _sized(tester, 1320);
    final store = DemoOrderStore([_order('done', status: 'completed')]);
    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();
    // A completed order is terminal, so it is not on the ACTIVE board at all.
    expect(find.byKey(const Key('active-order-card-done')), findsNothing);
    expect(find.byKey(const Key('active-orders-empty')), findsOneWidget);
  });

  // ===== B. role gating ======================================================
  testWidgets('B1 a settlement role sees the action; kitchen/accountant do not', (
    tester,
  ) async {
    // The client mirrors the SERVER allowlist; the server is authoritative anyway.
    expect(canCompleteOrders(MembershipRole.orgOwner), isTrue);
    expect(canCompleteOrders(MembershipRole.restaurantOwner), isTrue);
    expect(canCompleteOrders(MembershipRole.manager), isTrue);
    expect(canCompleteOrders(MembershipRole.cashier), isTrue);
    expect(canCompleteOrders(MembershipRole.kitchenStaff), isFalse);
    expect(canCompleteOrders(MembershipRole.accountant), isFalse);

    _sized(tester, 1320);
    await tester.pumpWidget(
      _wrap(_store(), membership: _membership(MembershipRole.accountant)),
    );
    await tester.pumpAndSettle();
    await _openDetail(tester, 'paid-served');
    expect(find.byKey(const Key('order-complete-button')), findsNothing);
  });

  testWidgets('B2 a manager DOES see the action', (tester) async {
    _sized(tester, 1320);
    await tester.pumpWidget(
      _wrap(_store(), membership: _membership(MembershipRole.manager)),
    );
    await tester.pumpAndSettle();
    await _openDetail(tester, 'paid-served');
    expect(find.byKey(const Key('order-complete-button')), findsOneWidget);
  });

  // ===== C. D-025 payment policy ============================================
  testWidgets(
    'C1 an UNPAID served order: the action is DISABLED and explained',
    (tester) async {
      _sized(tester, 1320);
      final l10n = await _l('en');
      await tester.pumpWidget(_wrap(_store()));
      await tester.pumpAndSettle();

      await _openDetail(tester, 'unpaid-served');
      expect(
        find.byKey(const Key('order-complete-unpaid-blocked')),
        findsOneWidget,
      );
      expect(find.text(l10n.ordersCompleteBlockedUnpaid), findsOneWidget);
      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('order-complete-button')),
      );
      expect(btn.onPressed, isNull, reason: 'unpaid must not be completable');
    },
  );

  test(
    'C2 the SERVER-side rule is enforced in the store too (not just the UI)',
    () async {
      final store = _store();
      // Even bypassing the disabled button, the repository refuses — the disabled
      // control is a courtesy, never the enforcement.
      final result = await DemoOrderCompletionRepository(
        store,
      ).complete('unpaid-served');
      expect(result, isA<OrderCompletionFailed>());
      expect(
        (result as OrderCompletionFailed).error,
        OrderCompletionError.notPaid,
      );
      expect(result.isRetryable, isFalse);
      // Unchanged, and NO payment was fabricated.
      final order = store.orders.firstWhere(
        (o) => o.detail.orderId == 'unpaid-served',
      );
      expect(order.detail.status, 'served');
      expect(order.detail.completedPayment, isNull);
    },
  );

  // ===== D. confirmation =====================================================
  testWidgets('D1 the confirmation shows the SAFE reference + payment state', (
    tester,
  ) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    await tester.pumpWidget(_wrap(_store()));
    await tester.pumpAndSettle();

    await _openDetail(tester, 'paid-served');
    await tester.tap(find.byKey(const Key('order-complete-button')));
    await tester.pumpAndSettle();

    final dialog = find.byKey(const Key('order-complete-confirm'));
    expect(dialog, findsOneWidget);
    expect(find.text(l10n.ordersCompleteConfirmTitle), findsOneWidget);
    // The safe '#code' reference, never the raw id, and a plain statement that
    // this is NOT a payment.
    expect(
      find.text(l10n.ordersCompleteConfirmBody('#paid-served')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text(l10n.dashboardPaid)),
      findsOneWidget,
    );
  });

  testWidgets('D2 cancelling the confirmation writes NOTHING', (tester) async {
    _sized(tester, 1320);
    final store = _store();
    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    await _openDetail(tester, 'paid-served');
    await tester.tap(find.byKey(const Key('order-complete-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('order-complete-cancel')));
    await tester.pumpAndSettle();

    expect(
      store.orders
          .firstWhere((o) => o.detail.orderId == 'paid-served')
          .detail
          .status,
      'served',
    );
  });

  // ===== E. the happy path: the board drains into History ====================
  testWidgets(
    'E1 completing removes the order from Active and puts it in History',
    (tester) async {
      _sized(tester, 1320);
      final l10n = await _l('en');
      final store = _store();
      await tester.pumpWidget(_wrap(store));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('active-order-card-paid-served')),
        findsOneWidget,
      );

      await _openDetail(tester, 'paid-served');
      await tester.tap(find.byKey(const Key('order-complete-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('order-complete-confirm-cta')));
      await tester.pumpAndSettle();

      // Authoritative success is surfaced.
      expect(find.byKey(const Key('order-complete-success')), findsOneWidget);
      expect(find.text(l10n.ordersCompleteSuccess), findsOneWidget);
      // The store really moved it to the terminal state (no fabrication: the money
      // and the payment are untouched).
      final done = store.orders.firstWhere(
        (o) => o.detail.orderId == 'paid-served',
      );
      expect(done.detail.status, 'completed');
      expect(done.detail.grandTotalMinor, 4600);
      expect(done.detail.completedPayment?.amountMinor, 4600);

      await tester.tap(find.byKey(const Key('order-detail-close')));
      await tester.pumpAndSettle();

      // It has LEFT the active board (it is terminal).
      expect(
        find.byKey(const Key('active-order-card-paid-served')),
        findsNothing,
      );

      // And it is now findable in History.
      await tester.tap(find.byKey(const Key('orders-tab-history')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-card-paid-served')), findsOneWidget);
    },
  );

  testWidgets('E2 the active FILTERS survive a completion', (tester) async {
    _sized(tester, 1320);
    final store = _store();
    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    // Narrow the board to the SERVED stage, then complete from within that filter.
    await tester.tap(find.byKey(const Key('active-summary-served')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('active-order-card-ready')), findsNothing);

    await _openDetail(tester, 'paid-served');
    await tester.tap(find.byKey(const Key('order-complete-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('order-complete-confirm-cta')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('order-detail-close')));
    await tester.pumpAndSettle();

    // Still filtered to served: the completed order is gone, the unpaid one stays,
    // and the ready/preparing orders are still filtered out.
    expect(
      find.byKey(const Key('active-order-card-paid-served')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('active-order-card-unpaid-served')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('active-order-card-ready')), findsNothing);
  });

  // ===== F. one write per double-tap ========================================
  test(
    'F1 a second complete() while one is in flight is IGNORED (one write)',
    () async {
      final store = _store();
      var calls = 0;
      final repo = _CountingRepo(
        DemoOrderCompletionRepository(store),
        () => calls++,
      );
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: true),
          ),
          demoOrderStoreProvider.overrideWithValue(store),
          orderCompletionRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(
        orderCompletionControllerProvider('paid-served').notifier,
      );
      // Fire twice without awaiting the first — the guard must collapse them.
      final a = notifier.complete();
      final b = notifier.complete();
      await Future.wait([a, b]);

      expect(calls, 1, reason: 'a double-tap must produce exactly ONE write');
      expect(
        container
            .read(orderCompletionControllerProvider('paid-served'))
            .completed,
        isTrue,
      );
      // And a THIRD attempt after success is still a no-op.
      await notifier.complete();
      expect(calls, 1);
    },
  );

  testWidgets('F2 the action is DISABLED while submitting', (tester) async {
    _sized(tester, 1320);
    final store = _store();
    final gate = _GatedRepo(DemoOrderCompletionRepository(store));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: true),
          ),
          demoOrderStoreProvider.overrideWithValue(store),
          activeOrdersClockProvider.overrideWithValue(_clock),
          dashboardMembershipProvider.overrideWithValue(null),
          orderCompletionRepositoryProvider.overrideWithValue(gate),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(body: OrdersScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openDetail(tester, 'paid-served');
    await tester.tap(find.byKey(const Key('order-complete-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('order-complete-confirm-cta')));
    await tester.pump(); // in flight

    final btn = tester.widget<FilledButton>(
      find.byKey(const Key('order-complete-button')),
    );
    expect(btn.onPressed, isNull, reason: 'no second write while submitting');
    // The order + its detail are STILL on screen while the write is in flight.
    expect(find.byKey(const Key('order-detail-content')), findsOneWidget);

    gate.release();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('order-complete-success')), findsOneWidget);
  });

  // ===== G. failures ========================================================
  testWidgets('G1 a TRANSPORT failure preserves the order and offers retry', (
    tester,
  ) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    final store = _store();
    await tester.pumpWidget(
      _wrap(store, forcedError: OrderCompletionError.transient),
    );
    await tester.pumpAndSettle();

    await _openDetail(tester, 'paid-served');
    await tester.tap(find.byKey(const Key('order-complete-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('order-complete-confirm-cta')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('order-complete-error')), findsOneWidget);
    expect(find.text(l10n.ordersCompleteErrorTransient), findsOneWidget);
    // Retry IS offered (the server call is idempotent).
    expect(find.byKey(const Key('order-complete-retry')), findsOneWidget);
    // The order is untouched and the detail is still usable.
    expect(
      store.orders
          .firstWhere((o) => o.detail.orderId == 'paid-served')
          .detail
          .status,
      'served',
    );
    expect(find.byKey(const Key('order-detail-content')), findsOneWidget);
  });

  testWidgets('G2 a CONFLICT (stale client) is localized and NOT retryable', (
    tester,
  ) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    await tester.pumpWidget(
      _wrap(_store(), forcedError: OrderCompletionError.conflict),
    );
    await tester.pumpAndSettle();

    await _openDetail(tester, 'paid-served');
    await tester.tap(find.byKey(const Key('order-complete-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('order-complete-confirm-cta')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.ordersCompleteErrorConflict), findsOneWidget);
    // A domain refusal is never blind-retried.
    expect(find.byKey(const Key('order-complete-retry')), findsNothing);
  });

  testWidgets('G3 a permission denial is localized (never a raw error)', (
    tester,
  ) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    await tester.pumpWidget(
      _wrap(_store(), forcedError: OrderCompletionError.permissionDenied),
    );
    await tester.pumpAndSettle();

    await _openDetail(tester, 'paid-served');
    await tester.tap(find.byKey(const Key('order-complete-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('order-complete-confirm-cta')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.ordersCompleteErrorDenied), findsOneWidget);
    expect(find.textContaining('permission_denied'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  });

  // ===== H. nothing else was introduced =====================================
  testWidgets('H1 NO payment / refund / void / discount control is introduced', (
    tester,
  ) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    await tester.pumpWidget(_wrap(_store()));
    await tester.pumpAndSettle();

    await _openDetail(tester, 'paid-served');
    for (final forbidden in <String>[
      l10n.posPayCash,
      l10n.posPayLaterAction,
      l10n.posCancelOrderAction,
      l10n.kdsReadyAction,
      l10n.kdsBumpAction,
    ]) {
      expect(find.text(forbidden), findsNothing);
    }
    // The sheet still offers only its read-only tools + the ONE completion action.
    expect(
      find.byKey(const Key('order-receipt-preview-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('order-kitchen-preview-button')),
      findsOneWidget,
    );
  });

  // ===== I. responsive + RTL/LTR + a11y ====================================
  for (final width in <double>[390, 700, 940, 1320]) {
    testWidgets('I1 the action renders without overflow at ${width}px', (
      tester,
    ) async {
      _sized(tester, width, 3000);
      await tester.pumpWidget(_wrap(_store()));
      await tester.pumpAndSettle();
      await _openDetail(tester, 'paid-served');
      expect(find.byKey(const Key('order-complete-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in <String>['ar', 'he', 'en']) {
    testWidgets('I2 the action + confirmation render in $locale', (
      tester,
    ) async {
      _sized(tester, 1320);
      final l10n = await _l(locale);
      await tester.pumpWidget(_wrap(_store(), locale: locale));
      await tester.pumpAndSettle();

      await _openDetail(tester, 'paid-served');
      expect(find.text(l10n.ordersCompleteAction), findsWidgets);

      final expected = locale == 'en' ? TextDirection.ltr : TextDirection.rtl;
      expect(
        Directionality.of(
          tester.element(find.byKey(const Key('order-complete-button'))),
        ),
        expected,
      );

      await tester.tap(find.byKey(const Key('order-complete-button')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.ordersCompleteConfirmTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('I3 the action is keyboard-activatable with a ≥44dp target', (
    tester,
  ) async {
    _sized(tester, 1320);
    await tester.pumpWidget(_wrap(_store()));
    await tester.pumpAndSettle();
    await _openDetail(tester, 'paid-served');

    final finder = find.byKey(const Key('order-complete-button'));
    expect(tester.widget<FilledButton>(finder).onPressed, isNotNull);
    expect(tester.getSize(finder).height, greaterThanOrEqualTo(44.0));

    // The confirmation's actions are real focusable buttons.
    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('order-complete-confirm-cta')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('order-complete-cancel')))
          .onPressed,
      isNotNull,
    );
  });

  // ===== J. the demo store is honest =======================================
  test(
    'J1 the demo store applies the canonical rules and fabricates nothing',
    () {
      final store = _store();
      expect(store.complete('nope'), DemoCompleteRefusal.notFound);
      expect(store.complete('ready'), DemoCompleteRefusal.invalidTransition);
      expect(store.complete('unpaid-served'), DemoCompleteRefusal.notPaid);
      expect(store.complete('paid-served'), isNull);

      final done = store.orders.firstWhere(
        (o) => o.detail.orderId == 'paid-served',
      );
      expect(done.detail.status, 'completed');
      // Money + payment + identity are carried over untouched.
      expect(done.detail.grandTotalMinor, 4600);
      expect(done.detail.payments.length, 1);
      expect(done.detail.orderCode, '#paid-served');
      // A completed order can never be completed again.
      expect(
        store.complete('paid-served'),
        DemoCompleteRefusal.invalidTransition,
      );
    },
  );
}

/// Counts the writes actually issued to the repository.
class _CountingRepo implements OrderCompletionRepository {
  _CountingRepo(this._inner, this._onCall);

  final OrderCompletionRepository _inner;
  final void Function() _onCall;

  @override
  Future<OrderCompletionResult> complete(
    String orderId, {
    int? expectedRevision,
  }) async {
    _onCall();
    return _inner.complete(orderId, expectedRevision: expectedRevision);
  }
}

/// Holds the write open so the SUBMITTING state is real.
class _GatedRepo implements OrderCompletionRepository {
  _GatedRepo(this._inner);

  final OrderCompletionRepository _inner;
  final Completer<void> _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<OrderCompletionResult> complete(
    String orderId, {
    int? expectedRevision,
  }) async {
    await _gate.future;
    return _inner.complete(orderId, expectedRevision: expectedRevision);
  }
}
