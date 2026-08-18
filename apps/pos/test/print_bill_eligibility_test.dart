@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/receipt_print_controller.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// DEFERRED-PAYMENT-RECEIPTS-001 (Scenario C) — Print bill ELIGIBILITY in the
/// real Orders sheet.
///
/// The earlier suite proved the print CHAIN but not the UI wiring, because a bare
/// `recordSubmitted` fixture does not satisfy `PosOrderActions.canPay`, so the
/// sheet never builds an action row at all. This builds a REALISTIC
/// [PosRecentOrder] — a server snapshot with a positive total, a non-terminal
/// status and no completed payment — seeded through the canonical
/// [InMemoryRecentOrdersStore] seam the other Orders tests use.
///
/// Each test asserts `resolveOrderActions(...).canPay` FIRST, so a failure can
/// never be mistaken for an invalid fixture: fixture correctness and UI
/// correctness are separated by construction.

const _code = '#EL0001';
const _orderId = 'oid-EL0001';

SubmittedOrderView _view() => const SubmittedOrderView(
  orderNumber: _code,
  orderType: OrderType.dineIn,
  tableLabel: 'T5',
  currencyCode: 'ILS',
  subtotalMinor: 5400,
  orderId: _orderId,
  customerName: 'Dana',
  lines: [
    SubmittedLineView(
      name: 'Classic Burger',
      quantity: 1,
      lineTotalMinor: 5400,
      currencyCode: 'ILS',
      modifiers: ['Extra meat ×2'],
    ),
  ],
);

/// The server row as the Orders screen receives it. `status` and `settlement` are
/// the authoritative axes `canPay` reads.
PosOrderSnapshot _snapshot({
  required PosSettlement settlement,
  String status = 'served',
  int grand = 5400,
  int revision = 2,
}) {
  // The recent-orders surface only shows a TODAY+YESTERDAY window, so a
  // hard-coded calendar date silently rots the moment the clock passes it —
  // these fixtures were written on 2026-07-30 and began failing on 2026-08-01
  // for that reason alone. Anchored to `now` so the window always contains
  // them; the exact instant is irrelevant to every assertion here.
  final at = DateTime.now().toUtc().subtract(const Duration(hours: 2));
  return PosOrderSnapshot(
    orderId: _orderId,
    orderCode: _code,
    revision: revision,
    status: status,
    settlement: settlement,
    subtotalMinor: grand,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: grand,
    createdAt: at,
    updatedAt: at,
    syncAt: at,
    orderType: 'dine_in',
    tableLabel: 'T5',
    currencyCode: 'ILS',
  );
}

CashPayment _completedPayment() => CashPayment(
  paymentId: 'pay-EL0001',
  orderNumber: _code,
  deviceId: 'd1',
  localOperationId: 'op1',
  method: PaymentMethod.cash,
  status: PaymentStatus.completed,
  amountMinor: 5400,
  tenderedMinor: 5400,
  changeMinor: 0,
  currencyCode: 'ILS',
  receiptNumber: 'R-1',
  paidAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
);

/// An UNPAID, payable order: non-terminal status, positive total, no payment.
PosRecentOrder _unpaidOrder() => PosRecentOrder(
  order: _view(),
  snapshot: _snapshot(settlement: PosSettlement.unpaid),
  submittedAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
);

/// The SAME order after authoritative full payment.
PosRecentOrder _paidOrder() => PosRecentOrder(
  order: _view(),
  snapshot: _snapshot(settlement: PosSettlement.paid),
  payment: _completedPayment(),
  submittedAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
);

/// A CANCELLED (terminal) order.
PosRecentOrder _cancelledOrder() => PosRecentOrder(
  order: _view(),
  snapshot: _snapshot(settlement: PosSettlement.unpaid, status: 'cancelled'),
  submittedAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
);

Future<InMemoryRecentOrdersStore> _store(PosRecentOrder order) async {
  final store = InMemoryRecentOrdersStore();
  await store.persist(kDemoSyncScope.key, [order]);
  return store;
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  InMemoryRecentOrdersStore store,
) async {
  SharedPreferences.setMockInitialValues(const {});
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [posRecentOrdersStoreProvider.overrideWithValue(store)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(body: RecentOrdersSheet()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder get _bill => find.byKey(const Key('recent-print-bill-$_code'));
Finder get _pay => find.byKey(const Key('recent-pay-$_code'));
Finder get _reprint => find.byKey(const Key('recent-reprint-$_code'));

/// 040: the open-order print control now opens a chooser. Tap it, then pick
/// the CUSTOMER BILL — the pre-bill behaviour asserted below is unchanged,
/// only the path to it.
Future<void> tapPrintBill(WidgetTester tester, Finder button) async {
  await tester.tap(button);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('print-choice-bill')));
  await tester.pumpAndSettle();
}

void main() {
  test('FIXTURE CONTRACT: the unpaid fixture satisfies canPay and the paid one '
      'does not', () {
    final unpaid = resolveOrderActions(_unpaidOrder());
    final paid = resolveOrderActions(_paidOrder());
    final cancelled = resolveOrderActions(_cancelledOrder());

    expect(unpaid.canPay, isTrue, reason: 'the unpaid fixture IS payable');
    expect(paid.canPay, isFalse, reason: 'a paid order is not payable');
    expect(
      cancelled.canPay,
      isFalse,
      reason: 'a terminal order is not payable',
    );
    // The paid order keeps the receipt path; that is what reprint hangs off.
    expect(paid.canOpenReceipt, isTrue);
  });

  testWidgets('A. an ELIGIBLE unpaid order shows Print bill ALONGSIDE Collect '
      'payment', (tester) async {
    await _pump(tester, await _store(_unpaidOrder()));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(_pay, findsOneWidget, reason: 'the action row builds');
    expect(_bill, findsOneWidget);
    // Scoped to THIS order's button: the demo branch also lists other unpaid
    // orders, which legitimately show their own Print bill action.
    expect(
      find.descendant(of: _bill, matching: find.text(l10n.posPrintAction)),
      findsOneWidget,
    );
    // Print bill does not replace or masquerade as the paid-receipt reprint.
    expect(_reprint, findsNothing);
  });

  testWidgets('A. tapping Print bill reaches the real production chain and '
      'creates the bill job', (tester) async {
    final container = await _pump(tester, await _store(_unpaidOrder()));

    await tapPrintBill(tester, _bill);

    final job = container
        .read(receiptPrintControllerProvider.notifier)
        .jobFor('bill:${_unpaidOrder().identity.key}');
    expect(
      job,
      isNotNull,
      reason: 'the button is wired to the real bill request',
    );
    // No printer is configured here, so it must NOT claim a send.
    expect(job!.status, isNot(PrintJobStatus.sentToPrinter));
  });

  testWidgets(
    'B. a PAID order hides Print bill and keeps the receipt reprint',
    (tester) async {
      await _pump(tester, await _store(_paidOrder()));
      expect(_bill, findsNothing, reason: 'no bill action for a paid order');
      expect(_pay, findsNothing, reason: 'a paid order is not payable again');
      expect(
        _reprint,
        findsOneWidget,
        reason: 'the paid receipt reprint stays available',
      );
    },
  );

  testWidgets('C. a CANCELLED order exposes neither Print bill nor Collect '
      'payment', (tester) async {
    await _pump(tester, await _store(_cancelledOrder()));

    expect(_bill, findsNothing);
    expect(_pay, findsNothing);
  });

  testWidgets('D. when the order becomes PAID, Print bill disappears and '
      'nothing prints from the rebuild alone', (tester) async {
    final store = await _store(_unpaidOrder());
    final container = await _pump(tester, store);
    expect(_bill, findsOneWidget);

    // Publish the PAID state the way the SERVER reports it: through the
    // canonical snapshot reconciler the Orders screen already uses.
    await container
        .read(posRecentOrdersControllerProvider.notifier)
        .applySnapshots([
          // A HIGHER revision: the reconciler is revision-first, so a
          // same-revision snapshot is correctly a no-op.
          _snapshot(settlement: PosSettlement.paid, revision: 3),
        ]);
    await tester.pumpAndSettle();

    expect(_bill, findsNothing, reason: 'eligibility follows the paid state');
    // Hydration alone must never print anything.
    expect(
      container.read(receiptPrintControllerProvider),
      isEmpty,
      reason: 'a rebuild is not a print trigger',
    );
  });

  testWidgets('E. the action key is stable and the label comes from ARB (ar)', (
    tester,
  ) async {
    final store = await _store(_unpaidOrder());
    SharedPreferences.setMockInitialValues(const {});
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [posRecentOrdersStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('ar'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(body: RecentOrdersSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final ar = await AppLocalizations.delegate.load(const Locale('ar'));
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    // Same key in Arabic, different localized text — nothing is hardcoded.
    expect(_bill, findsOneWidget);
    expect(
      find.descendant(of: _bill, matching: find.text(ar.posPrintAction)),
      findsOneWidget,
    );
    expect(ar.posPrintAction, isNot(en.posPrintAction));
    expect(tester.takeException(), isNull, reason: 'no RTL overflow');
  });
}
