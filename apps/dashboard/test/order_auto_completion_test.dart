import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/data/active_orders_models.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/audit_log_presentation.dart';
import 'package:restoflow_dashboard/src/data/demo_order_store.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/data/order_history_repository.dart';
import 'package:restoflow_dashboard/src/orders/orders_screen.dart';
import 'package:restoflow_dashboard/src/state/active_orders_providers.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/state/order_history_providers.dart'
    show demoOrderStoreProvider;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// ORDER-AUTO-COMPLETION-001 — a SERVED order that is FULLY PAID completes itself.
///
/// Both trigger directions, the amount-aware settlement test, the manual action
/// reframed as a RECOVERY step, and the Activity Log's automatic-vs-manual record.
Future<AppLocalizations> _l(String code) =>
    AppLocalizations.delegate.load(Locale(code));

final DateTime _now = DateTime.utc(2026, 7, 13, 13, 38);
DateTime _clock() => _now;

/// [paidAmount] is the amount of the completed payment, in integer minor units.
/// It is deliberately independent of [total] so an UNDER-COVERED order (a payment
/// that no longer covers a re-based total) can be expressed at all.
DemoOrder _order(
  String id, {
  required String status,
  int total = 4600,
  int? paidAmount,
  String paymentStatus = 'completed',
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
              status: paymentStatus,
              amountMinor: paidAmount,
            ),
          ],
  ),
);

/// One order at every state that matters to the rule.
List<DemoOrder> _fixtures() => [
  // direction A: ready + already PAID -> serving it must close it
  _order('ready-paid', status: 'ready', paidAmount: 4600, minutesAgo: 55),
  // direction A: ready + UNPAID -> serving it must leave it ACTIVE
  _order('ready-unpaid', status: 'ready', minutesAgo: 50),
  // direction B: already SERVED + unpaid -> paying it must close it
  _order('served-unpaid', status: 'served', minutesAgo: 45),
  // direction B: still in the kitchen -> paying it must NOT close it
  _order('submitted-unpaid', status: 'submitted', minutesAgo: 40),
  // the ANOMALY the manual recovery action exists for: served + fully paid, open
  _order('served-paid', status: 'served', paidAmount: 4600, minutesAgo: 35),
  // the discount re-base: a real completed payment that no longer covers the total
  _order('served-under', status: 'served', total: 4600, paidAmount: 2000),
  // ZERO-TOTAL (comped / 100%-discounted) = NON-CHARGEABLE: owes nothing, carries no
  // payment row, and none is ever created for it.
  _order('zero-ready', status: 'ready', total: 0, minutesAgo: 30),
  _order('zero-served', status: 'served', total: 0, minutesAgo: 25),
  // terminal
  _order('completed', status: 'completed', paidAmount: 4600),
  _order('voided', status: 'voided'),
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

Future<void> _openDetail(WidgetTester tester, String orderId) async {
  await tester.tap(find.byKey(Key('active-order-card-$orderId')));
  await tester.pumpAndSettle();
}

/// An AUTOMATIC completion exactly as the server's `app.audit_safe_detail`
/// allowlist projects it (pgTAP pins the payload; this pins the rendering).
AuditEvent _autoEvent({String trigger = 'order_served'}) => AuditEvent(
  eventId: 'ae-auto',
  action: 'order.status_updated',
  category: 'orders',
  occurredAtLabel: '2026-07-14 14:05',
  actorName: 'Kitchen K.',
  restaurantName: 'Rest A1',
  branchName: 'Downtown',
  oldValues: const {'status': 'served'},
  newValues: {
    'status': 'completed',
    'order_code': '#0AC001',
    'payment_status': 'paid',
    'role': 'kitchen_staff',
    'completion_mode': 'automatic',
    'completion_trigger': trigger,
  },
);

/// The MANUAL recovery completion: mode=manual and NO trigger (a human chose it).
AuditEvent _manualEvent() => const AuditEvent(
  eventId: 'ae-manual',
  action: 'order.status_updated',
  category: 'orders',
  occurredAtLabel: '2026-07-14 14:06',
  actorName: 'Amira K.',
  restaurantName: 'Rest A1',
  branchName: 'Downtown',
  oldValues: {'status': 'served'},
  newValues: {
    'status': 'completed',
    'order_code': '#0AC006',
    'payment_status': 'paid',
    'role': 'manager',
    'completion_mode': 'manual',
  },
);

String? _valueFor(AuditEventView view, String label) {
  for (final c in view.changes) {
    if (c.label == label) return c.newValue;
  }
  return null;
}

void main() {
  // ===== A. TRIGGER DIRECTION A — the order is served and was ALREADY paid =====
  test('A1 serving an ALREADY-PAID order completes it automatically', () {
    final store = _store();
    final outcome = store.markServed('ready-paid');

    expect(outcome.applied, isTrue);
    expect(
      outcome.autoCompleted,
      isTrue,
      reason: 'served + fully paid must close itself',
    );
    expect(_detail(store, 'ready-paid').status, 'completed');
  });

  test('A2 serving an UNPAID order leaves it SERVED and ACTIVE', () {
    final store = _store();
    final outcome = store.markServed('ready-unpaid');

    expect(outcome.applied, isTrue, reason: 'the serve itself always stands');
    expect(outcome.autoCompleted, isFalse);
    expect(
      _detail(store, 'ready-unpaid').status,
      'served',
      reason: 'an unpaid served order is a real exception and stays visible',
    );
  });

  test('A3 the automatic completion FABRICATES NO payment', () {
    final store = _store();
    store.markServed('ready-unpaid');

    expect(_detail(store, 'ready-unpaid').payments, isEmpty);
    expect(_detail(store, 'ready-unpaid').completedPayment, isNull);
  });

  test('A4 the automatic completion moves NO money', () {
    final store = _store();
    final before = _detail(store, 'ready-paid');
    store.markServed('ready-paid');
    final after = _detail(store, 'ready-paid');

    expect(after.grandTotalMinor, before.grandTotalMinor);
    expect(after.subtotalMinor, before.subtotalMinor);
    expect(after.discountTotalMinor, before.discountTotalMinor);
    expect(after.taxTotalMinor, before.taxTotalMinor);
    expect(after.completedPayment!.amountMinor, 4600);
  });

  test(
    'A5 an order that is not `ready` cannot be served (no state skipping)',
    () {
      final store = _store();
      final outcome = store.markServed('submitted-unpaid');

      expect(outcome.applied, isFalse);
      expect(outcome.autoCompleted, isFalse);
      expect(_detail(store, 'submitted-unpaid').status, 'submitted');
    },
  );

  test('A6 serving is IDEMPOTENT — the rule never fires twice', () {
    final store = _store();
    expect(store.markServed('ready-paid').autoCompleted, isTrue);

    // The order is now `completed`, so a replayed serve is refused outright and
    // the automatic rule cannot re-fire.
    final replay = store.markServed('ready-paid');
    expect(replay.applied, isFalse);
    expect(replay.autoCompleted, isFalse);
    expect(_detail(store, 'ready-paid').status, 'completed');
  });

  // ===== B. TRIGGER DIRECTION B — the order was ALREADY served and is paid =====
  test('B1 paying an ALREADY-SERVED order completes it automatically', () {
    final store = _store();
    final outcome = store.recordPayment('served-unpaid');

    expect(outcome.applied, isTrue);
    expect(outcome.autoCompleted, isTrue);
    expect(_detail(store, 'served-unpaid').status, 'completed');
  });

  test('B2 paying an order still in the KITCHEN does NOT complete it', () {
    final store = _store();
    final outcome = store.recordPayment('submitted-unpaid');

    expect(outcome.applied, isTrue, reason: 'the payment itself succeeds');
    expect(
      outcome.autoCompleted,
      isFalse,
      reason: 'payment is not fulfillment (D-025)',
    );
    expect(_detail(store, 'submitted-unpaid').status, 'submitted');
  });

  test('B3 a non-firing rule NEVER fails the payment', () {
    final store = _store();
    store.recordPayment('submitted-unpaid');

    // The payment is still there, completed, and covers the order exactly.
    final detail = _detail(store, 'submitted-unpaid');
    expect(detail.completedPayment, isNotNull);
    expect(detail.completedPayment!.amountMinor, detail.grandTotalMinor);
    expect(detail.isFullySettled, isTrue);
  });

  test('B4 the payment amount is the order total — no money is invented', () {
    final store = _store();
    store.recordPayment('served-unpaid');

    final detail = _detail(store, 'served-unpaid');
    expect(detail.completedPayment!.amountMinor, 4600);
    expect(detail.grandTotalMinor, 4600);
  });

  test('B5 a TERMINAL order is never paid again and never revived', () {
    final store = _store();
    for (final id in ['completed', 'voided']) {
      final outcome = store.recordPayment(id);
      expect(outcome.applied, isFalse, reason: id);
      expect(outcome.autoCompleted, isFalse, reason: id);
    }
    expect(_detail(store, 'completed').status, 'completed');
    expect(_detail(store, 'voided').status, 'voided');
  });

  test('B6 at most ONE completed payment per order (a replay is refused)', () {
    final store = _store();
    expect(store.recordPayment('served-unpaid').applied, isTrue);

    final replay = store.recordPayment('served-unpaid');
    expect(replay.applied, isFalse);
    expect(
      _detail(store, 'served-unpaid').payments.where((p) => p.isCompleted),
      hasLength(1),
    );
  });

  // ===== C. THE SETTLEMENT TEST — amount-aware, not a marker ==================
  test('C1 a payment covering the CURRENT total settles the order', () {
    expect(_detail(_store(), 'served-paid').isFullySettled, isTrue);
  });

  test('C2 an UNDER-COVERING payment does NOT settle it', () {
    // 2000 paid against a 4600 total: a real completed payment exists, so a bare
    // "has a completed payment" MARKER would wrongly call this paid.
    final detail = _detail(_store(), 'served-under');
    expect(detail.completedPayment, isNotNull);
    expect(detail.isFullySettled, isFalse);
  });

  test('C3 no payment at all is not settled', () {
    expect(_detail(_store(), 'served-unpaid').isFullySettled, isFalse);
  });

  test('C4 a NON-COMPLETED payment does not settle it', () {
    final store = DemoOrderStore([
      _order(
        'pending',
        status: 'served',
        paidAmount: 4600,
        paymentStatus: 'pending',
      ),
    ]);
    expect(_detail(store, 'pending').isFullySettled, isFalse);
  });

  test('C5 an OVER-covering payment settles it (>= the total)', () {
    final store = DemoOrderStore([
      _order('over', status: 'served', total: 4600, paidAmount: 5000),
    ]);
    expect(_detail(store, 'over').isFullySettled, isTrue);
  });

  // ===== D. THE MANUAL PATH — a RECOVERY step, with the SAME gate =============
  test('D1 the manual completion still closes a served + fully-paid order', () {
    final store = _store();
    expect(store.complete('served-paid'), isNull);
    expect(_detail(store, 'served-paid').status, 'completed');
  });

  test(
    'D2 the manual completion REFUSES an under-covered order (hardened D-025)',
    () {
      final store = _store();
      expect(store.complete('served-under'), DemoCompleteRefusal.notPaid);
      expect(
        _detail(store, 'served-under').status,
        'served',
        reason: 'it stays ACTIVE — a part-settled order is a real exception',
      );
    },
  );

  test('D3 the manual completion never creates a payment', () {
    final store = _store();
    store.complete('served-unpaid'); // refused (unpaid)
    expect(_detail(store, 'served-unpaid').payments, isEmpty);
  });

  // ===== E. THE UI — the manual action reads as a RECOVERY step ===============
  testWidgets('E1 a served + PAID order shows the RECOVERY note', (
    tester,
  ) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    await tester.pumpWidget(_wrap(_store()));
    await tester.pumpAndSettle();
    await _openDetail(tester, 'served-paid');

    expect(
      find.byKey(const Key('order-complete-recovery-note')),
      findsOneWidget,
    );
    expect(find.text(l10n.ordersCompleteRecoveryNote), findsOneWidget);
    // ...and the action is still offered (recovery is possible, just not routine).
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('order-complete-button')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets(
    'E2 an UNPAID served order shows the D-025 block, NOT the recovery note',
    (tester) async {
      _sized(tester, 1320);
      await tester.pumpWidget(_wrap(_store()));
      await tester.pumpAndSettle();
      await _openDetail(tester, 'served-unpaid');

      expect(
        find.byKey(const Key('order-complete-unpaid-blocked')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('order-complete-recovery-note')),
        findsNothing,
      );
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('order-complete-button')),
      );
      expect(button.onPressed, isNull, reason: 'an unpaid order cannot close');
    },
  );

  testWidgets(
    'E3 an UNDER-COVERED order is treated as unpaid (settlement, not marker)',
    (tester) async {
      _sized(tester, 1320);
      await tester.pumpWidget(_wrap(_store()));
      await tester.pumpAndSettle();
      await _openDetail(tester, 'served-under');

      // It carries a completed payment, so a MARKER test would have enabled this
      // button — and the server would then have refused the write.
      expect(
        find.byKey(const Key('order-complete-unpaid-blocked')),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('order-complete-button')),
      );
      expect(button.onPressed, isNull);
    },
  );

  testWidgets('E4 the Awaiting-close explainer states the automatic rule', (
    tester,
  ) async {
    _sized(tester, 1320);
    for (final code in ['en', 'ar', 'he']) {
      final l10n = await _l(code);
      // The copy must tell the operator that a served order closes itself once
      // paid — otherwise this queue reads as a normal backlog instead of an
      // exception list.
      expect(
        l10n.ordersAwaitingCloseExplainer.trim(),
        isNotEmpty,
        reason: code,
      );
      expect(
        l10n.ordersAwaitingCloseExplainer,
        isNot(contains('can be completed from its details')),
        reason: '$code: the pre-rule copy must be gone',
      );
      expect(
        l10n.ordersAwaitingCloseBacklog(9).trim(),
        isNotEmpty,
        reason: code,
      );
    }
  });

  // ===== F. THE ACTIVITY LOG — automatic vs manual, in every language ========
  test(
    'F1 an AUTOMATIC completion renders localized mode + trigger VALUES',
    () async {
      for (final code in ['en', 'ar', 'he']) {
        final l10n = await _l(code);
        final view = AuditEventPresenter(l10n, 'ILS').present(_autoEvent());

        expect(
          view.categoryLabel,
          l10n.activityLogCategoryOrders,
          reason: code,
        );
        expect(
          _valueFor(view, l10n.activityLogFieldCompletionMode),
          l10n.activityLogCompletionModeAutomatic,
          reason:
              '$code: the VALUE is localized, not the raw `automatic` token',
        );
        expect(
          _valueFor(view, l10n.activityLogFieldCompletionTrigger),
          l10n.activityLogCompletionTriggerOrderServed,
          reason: code,
        );
        // ...and it still says WHAT happened and to WHICH order.
        expect(
          _valueFor(view, l10n.activityLogFieldStatus),
          'completed',
          reason: code,
        );
        expect(
          _valueFor(view, l10n.activityLogFieldOrderCode),
          '#0AC001',
          reason: code,
        );
      }
    },
  );

  test(
    'F2 a PAYMENT-triggered completion names the payment as the cause',
    () async {
      final l10n = await _l('en');
      final view = AuditEventPresenter(
        l10n,
        'ILS',
      ).present(_autoEvent(trigger: 'payment_recorded'));

      expect(
        _valueFor(view, l10n.activityLogFieldCompletionTrigger),
        l10n.activityLogCompletionTriggerPaymentRecorded,
      );
    },
  );

  test(
    'F3 a MANUAL completion is distinguishable and carries NO trigger',
    () async {
      for (final code in ['en', 'ar', 'he']) {
        final l10n = await _l(code);
        final view = AuditEventPresenter(l10n, 'ILS').present(_manualEvent());

        expect(
          _valueFor(view, l10n.activityLogFieldCompletionMode),
          l10n.activityLogCompletionModeManual,
          reason: code,
        );
        expect(
          _valueFor(view, l10n.activityLogFieldCompletionMode),
          isNot(l10n.activityLogCompletionModeAutomatic),
          reason: '$code: a recovery completion must never read as automatic',
        );
        expect(
          _valueFor(view, l10n.activityLogFieldCompletionTrigger),
          isNull,
          reason: '$code: a human chose it — there is no trigger',
        );
      }
    },
  );

  test(
    'F4 the automatic payload stays MONEY-FREE and identifier-free',
    () async {
      final l10n = await _l('en');
      final view = AuditEventPresenter(l10n, 'ILS').present(_autoEvent());

      for (final change in view.changes) {
        expect(change.newValue, isNot(contains('₪')));
        expect(change.newValue, isNot(contains('46.00')));
      }
      // The order UUID, revision and op id are dropped server-side and have no
      // client label either — nothing can surface them.
      expect(view.changes.map((c) => c.label), isNot(contains('order_id')));
      expect(view.changes.map((c) => c.label), isNot(contains('revision')));
    },
  );

  test(
    'F5 an UNKNOWN mode/trigger value degrades honestly (no confident mislabel)',
    () async {
      final l10n = await _l('en');
      final view = AuditEventPresenter(l10n, 'ILS').present(
        const AuditEvent(
          eventId: 'ae-x',
          action: 'order.status_updated',
          category: 'orders',
          occurredAtLabel: '2026-07-14 14:07',
          oldValues: {'status': 'served'},
          newValues: {'status': 'completed', 'completion_mode': 'future_mode'},
        ),
      );

      expect(
        _valueFor(view, l10n.activityLogFieldCompletionMode),
        'future_mode',
        reason:
            'an unknown value is shown raw, never guessed as automatic/manual',
      );
    },
  );

  // ===== G. ZERO-TOTAL = NON-CHARGEABLE = SETTLED ============================
  // The human decision: a zero-total order owes nothing, so it is settled WITHOUT a
  // payment row and NONE is ever created for it. `OrderDetail.isFullySettled` is the
  // client mirror of the ONE server predicate `app.order_is_fully_settled` — there is
  // no second zero-total exception in the completion action or the demo store, so
  // correcting the predicate corrects every client path at once.
  test('G1 a ZERO-TOTAL order is SETTLED with no payment row at all', () {
    final detail = _detail(_store(), 'zero-served');

    expect(detail.grandTotalMinor, 0);
    expect(detail.payments, isEmpty);
    expect(detail.completedPayment, isNull);
    expect(
      detail.isFullySettled,
      isTrue,
      reason: 'non-chargeable: it owes nothing, so nothing is outstanding',
    );
  });

  test('G2 a NEGATIVE total FAILS CLOSED (never settled)', () {
    // Unreachable through the DB (orders CHECK: grand_total_minor >= 0), but a
    // negative total is a money defect and must never close an order.
    final store = DemoOrderStore([
      _order('negative', status: 'served', total: -1),
    ]);
    expect(_detail(store, 'negative').isFullySettled, isFalse);
  });

  test(
    'G3 serving a ZERO-TOTAL order auto-completes it and creates NO payment',
    () {
      final store = _store();
      final outcome = store.markServed('zero-ready');

      expect(outcome.applied, isTrue);
      expect(outcome.autoCompleted, isTrue);
      final detail = _detail(store, 'zero-ready');
      expect(detail.status, 'completed');
      expect(
        detail.payments,
        isEmpty,
        reason: 'a zero-value payment is NEVER fabricated to force a closure',
      );
      expect(detail.grandTotalMinor, 0, reason: 'no money moved');
    },
  );

  test(
    'G4 MANUAL and AUTOMATIC agree: the manual path completes a zero-total order',
    () {
      final store = _store();
      // With the old marker predicate this returned `notPaid` — the manual recovery
      // path could not close it either, so the order was permanently STUCK.
      expect(store.complete('zero-served'), isNull);
      expect(_detail(store, 'zero-served').status, 'completed');
      expect(_detail(store, 'zero-served').payments, isEmpty);
    },
  );

  test('G5 DEMO matches REAL: one settlement rule across the whole matrix', () {
    // The exact matrix the server's app.order_is_fully_settled pgTAP pins.
    final cases = <String, bool>{
      'zero-served': true, //    total 0, no payment   -> non-chargeable
      'served-paid': true, //    4600 of 4600          -> covered
      'served-under': false, //  2000 of 4600          -> under-covered
      'served-unpaid': false, // 4600 owed, no payment -> unpaid
    };
    final store = _store();
    for (final entry in cases.entries) {
      expect(
        _detail(store, entry.key).isFullySettled,
        entry.value,
        reason: '${entry.key} must settle exactly as the server decides',
      );
    }
    // ...and an over-covering payment settles, like the server's `>=`.
    final over = DemoOrderStore([
      _order('over', status: 'served', total: 4600, paidAmount: 5000),
    ]);
    expect(_detail(over, 'over').isFullySettled, isTrue);
  });

  test('G6 a ZERO-TOTAL completion renders "nothing to pay", never "Paid"', () async {
    // The server audits payment_status=not_chargeable for a comped order (it was
    // completed with NO payment row). Rendering that as "Paid" would repeat the lie
    // the server refused to tell — and a raw `not_chargeable` token would be worse.
    for (final code in ['en', 'ar', 'he']) {
      final l10n = await _l(code);
      final view = AuditEventPresenter(l10n, 'ILS').present(
        const AuditEvent(
          eventId: 'ae-zero',
          action: 'order.status_updated',
          category: 'orders',
          occurredAtLabel: '2026-07-14 14:08',
          oldValues: {'status': 'served'},
          newValues: {
            'status': 'completed',
            'order_code': '#0AC008',
            'payment_status': 'not_chargeable',
            'completion_mode': 'automatic',
            'completion_trigger': 'order_served',
          },
        ),
      );

      final shown = _valueFor(view, l10n.activityLogFieldPaymentStatus);
      expect(shown, l10n.activityLogPaymentNotChargeable, reason: code);
      expect(
        shown,
        isNot(l10n.dashboardPaid),
        reason: '$code: an order that was never paid must NOT read as "Paid"',
      );
      expect(
        shown,
        isNot('not_chargeable'),
        reason: '$code: never a raw token',
      );
    }
  });

  // The confirm dialog must never contradict its own gate — AND must never overstate.
  // The first version of this test asserted "Paid" for a ZERO-TOTAL order, because the
  // pill was driven by a BOOLEAN (`settled ? Paid : Unpaid`). That was wrong: the order
  // owes nothing, but NO PAYMENT WAS EVER TAKEN — the server itself audits it as
  // `not_chargeable` and refuses to charge it. Two states cannot express three, so the
  // dialog now renders the canonical THREE-VALUED settlement state.
  testWidgets(
    'G7 the confirm dialog shows NO CHARGE for a zero-total order — never Paid (ar/he/en)',
    (tester) async {
      _sized(tester, 1320);
      for (final code in ['ar', 'he', 'en']) {
        final l10n = await _l(code);
        await tester.pumpWidget(_wrap(_store(), locale: code));
        await tester.pumpAndSettle();

        await _openDetail(tester, 'zero-served');
        await tester.tap(find.byKey(const Key('order-complete-button')));
        await tester.pumpAndSettle();

        final dialog = find.byKey(const Key('order-complete-confirm'));
        expect(dialog, findsOneWidget, reason: code);
        expect(
          find.descendant(
            of: dialog,
            matching: find.text(l10n.dashboardNoCharge),
          ),
          findsOneWidget,
          reason: '$code: nothing was ever paid, and nothing is owed',
        );
        expect(
          find.descendant(of: dialog, matching: find.text(l10n.dashboardPaid)),
          findsNothing,
          reason:
              '$code: claiming "Paid" would assert a payment that never happened',
        );
        expect(
          find.descendant(
            of: dialog,
            matching: find.text(l10n.dashboardUnpaid),
          ),
          findsNothing,
          reason: '$code: claiming "Unpaid" would imply money is owed',
        );
      }
    },
  );

  testWidgets('G7b the confirm dialog shows PAID for a genuinely paid order', (
    tester,
  ) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    await tester.pumpWidget(_wrap(_store()));
    await tester.pumpAndSettle();

    await _openDetail(tester, 'served-paid');
    await tester.tap(find.byKey(const Key('order-complete-button')));
    await tester.pumpAndSettle();

    final dialog = find.byKey(const Key('order-complete-confirm'));
    expect(
      find.descendant(of: dialog, matching: find.text(l10n.dashboardPaid)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text(l10n.dashboardNoCharge)),
      findsNothing,
    );
  });

  testWidgets('G7c an UNDER-COVERED order reads UNPAID and cannot be completed', (
    tester,
  ) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    await tester.pumpWidget(_wrap(_store()));
    await tester.pumpAndSettle();

    // It carries a REAL completed payment, so a marker would have said "Paid" — while
    // money is still owed. The button stays gated by the canonical settlement state, so
    // the dialog is unreachable; the DETAIL SHEET must still tell the truth.
    await _openDetail(tester, 'served-under');
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('order-complete-button')),
    );
    expect(button.onPressed, isNull, reason: 'D-025: it still owes money');

    // Scoped to the SHEET — the board behind it legitimately shows other orders'
    // badges, including "No charge" on the comped ones.
    final sheet = find.byKey(const Key('order-detail-sheet'));
    // It carries a real payment, so the sheet shows that payment's row; the "money is
    // still owed" signal is the D-025 block, which must be present.
    expect(
      find.descendant(
        of: sheet,
        matching: find.byKey(const Key('order-complete-unpaid-blocked')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text(l10n.dashboardNoCharge)),
      findsNothing,
      reason: 'money IS owed — this is not a non-chargeable order',
    );
    expect(
      find.descendant(of: sheet, matching: find.text(l10n.dashboardPaid)),
      findsNothing,
      reason: 'a marker would have called this PAID while 26.00 is still owed',
    );
  });

  testWidgets(
    'G8 Active Orders drops the zero-total order after an authoritative refresh',
    (tester) async {
      _sized(tester, 1320);
      final store = _store();
      await tester.pumpWidget(_wrap(store));
      await tester.pumpAndSettle();

      // It starts on the board (ready, still in the kitchen).
      expect(
        find.byKey(const Key('active-order-card-zero-ready')),
        findsOneWidget,
      );

      // The kitchen serves it (the KDS bump arriving over sync). Being
      // non-chargeable it is already settled, so the rule closes it — no operator
      // action, no payment.
      expect(store.markServed('zero-ready').autoCompleted, isTrue);

      // An AUTHORITATIVE refresh re-reads the store; the UI never guesses.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OrdersScreen)),
      );
      await container.read(activeOrdersControllerProvider.notifier).refresh();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('active-order-card-zero-ready')),
        findsNothing,
        reason:
            'a completed order is terminal — it must leave the active board',
      );
      // The genuinely-unpaid served order is STILL there: it is a real exception.
      expect(
        find.byKey(const Key('active-order-card-served-unpaid')),
        findsOneWidget,
      );
    },
  );
}
