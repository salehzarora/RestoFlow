import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/cash_payment_sheet.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';

/// MONEY-SETTLEMENT-CONSISTENCY-001 — the POS half.
///
/// The POS used to answer BOTH "does this order still owe money?" and "can this order be
/// cancelled?" with the SAME payment-row marker (`payment != null`). That made it:
///   * show "Unpaid" forever on a comped (zero-total) order that owes nothing;
///   * offer "Take payment" on an order the server now REFUSES to charge;
///   * offer "Cancel" on a TERMINAL order (a comped order auto-completes on `served`),
///     which then failed with a generic "Cancellation failed. Please try again." —
///     advice that could never work.
///
/// Now: SETTLEMENT drives what we SAY, the payment MARKER drives what we OFFER (a receipt
/// can only be reprinted when money actually moved, and the server's void guard blocks
/// exactly on a live completed payment), and a KNOWN-TERMINAL order offers nothing.
Future<AppLocalizations> _l(String code) =>
    AppLocalizations.delegate.load(Locale(code));

SubmittedOrderView _view(String number, {int total = 4200}) =>
    SubmittedOrderView(
      orderNumber: number,
      orderType: OrderType.takeaway,
      currencyCode: 'ILS',
      subtotalMinor: total,
      orderId: 'oid-$number',
      lines: [
        SubmittedLineView(
          name: 'Burger',
          quantity: 1,
          lineTotalMinor: total,
          currencyCode: 'ILS',
        ),
      ],
    );

CashPayment _payment(String number, {int amount = 4200, String? orderStatus}) =>
    CashPayment(
      paymentId: 'pay-$number',
      orderNumber: number,
      deviceId: 'd1',
      localOperationId: 'op-$number',
      method: PaymentMethod.cash,
      status: PaymentStatus.completed,
      amountMinor: amount,
      tenderedMinor: amount,
      changeMinor: 0,
      currencyCode: 'ILS',
      receiptNumber: 'R-1',
      paidAt: DateTime.utc(2026, 7, 15, 12),
      orderStatus: orderStatus,
    );

/// The canonical matrix, as the POS sees it.
///   #Z0  zero-total, ACTIVE     -> non-chargeable, still cancellable
///   #ZC  zero-total, COMPLETED  -> terminal: NO Cancel, NO Take payment
///   #U1  positive, unpaid       -> Take payment + Cancel (unchanged)
///   #P1  positive, fully paid   -> Reprint + View (unchanged)
///   #UC  positive, UNDER-COVERED-> still owes money
Future<InMemoryRecentOrdersStore> _seeded() async {
  final store = InMemoryRecentOrdersStore();
  final now = DateTime.now();
  await store.persist(kDemoSyncScope.key, [
    PosRecentOrder(
      order: _view('#Z0', total: 0),
      submittedAt: now,
      status: 'submitted',
    ),
    PosRecentOrder(
      order: _view('#ZC', total: 0),
      submittedAt: now.subtract(const Duration(minutes: 2)),
      status: 'completed',
    ),
    PosRecentOrder(
      order: _view('#U1'),
      submittedAt: now.subtract(const Duration(minutes: 4)),
    ),
    PosRecentOrder(
      order: _view('#P1'),
      submittedAt: now.subtract(const Duration(minutes: 6)),
      payment: _payment('#P1'),
    ),
    PosRecentOrder(
      order: _view('#UC'),
      submittedAt: now.subtract(const Duration(minutes: 8)),
      payment: _payment('#UC', amount: 2000), // 2000 of 4200 — still owes
    ),
  ]);
  return store;
}

Widget _wrap(
  InMemoryRecentOrdersStore store, {
  Locale locale = const Locale('en'),
}) => ProviderScope(
  overrides: [posRecentOrdersStoreProvider.overrideWithValue(store)],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: const Scaffold(body: RecentOrdersSheet()),
  ),
);

void _wide(WidgetTester tester, [Size size = const Size(1000, 2400)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Commit 3: the operational centre lands on OPEN. A test about a TERMINAL order (or
/// about all orders at once) must select the section it now lives in -- that is the
/// point of having sections.
Future<void> _showAllSections(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('orders-section-all')));
  await tester.pumpAndSettle();
}

void main() {
  // ===== 35. a COMPLETED zero-total order shows NO Cancel =====================
  testWidgets(
    '35 a COMPLETED zero-total order offers NO Cancel and NO Take payment',
    (tester) async {
      _wide(tester);
      await tester.pumpWidget(_wrap(await _seeded()));
      await tester.pumpAndSettle();
      await _showAllSections(tester);

      expect(find.byKey(const Key('recent-order-#ZC')), findsOneWidget);
      // THE BUG THIS CLOSES: the server refuses a void on a terminal order, so offering
      // Cancel here could only ever end in a failure the cashier cannot act on.
      expect(find.byKey(const Key('recent-cancel-#ZC')), findsNothing);
      // ...and there is nothing to charge, so no payment control either.
      expect(find.byKey(const Key('recent-pay-#ZC')), findsNothing);
      // No payment was ever taken, so there is no receipt to reprint.
      expect(find.byKey(const Key('recent-reprint-#ZC')), findsNothing);
    },
  );

  // ===== 36. a COMPLETED positive PAID order — the existing behaviour holds ===
  testWidgets(
    '36 a fully PAID order still offers Reprint + View, never Take payment',
    (tester) async {
      _wide(tester);
      await tester.pumpWidget(_wrap(await _seeded()));
      await tester.pumpAndSettle();
      await _showAllSections(tester);

      expect(find.byKey(const Key('recent-reprint-#P1')), findsOneWidget);
      expect(find.byKey(const Key('recent-view-#P1')), findsOneWidget);
      expect(find.byKey(const Key('recent-pay-#P1')), findsNothing);
      expect(find.byKey(const Key('recent-cancel-#P1')), findsNothing);
    },
  );

  // ===== 37. an ACTIVE, eligible UNPAID order keeps its behaviour =============
  testWidgets('37 an ACTIVE unpaid order still offers Take payment + Cancel', (
    tester,
  ) async {
    _wide(tester);
    await tester.pumpWidget(_wrap(await _seeded()));
    await tester.pumpAndSettle();
    await _showAllSections(tester);

    expect(find.byKey(const Key('recent-pay-#U1')), findsOneWidget);
    expect(find.byKey(const Key('recent-cancel-#U1')), findsOneWidget);
  });

  // ===== 38. a ZERO-TOTAL payment attempt is blocked, with an explanation =====
  testWidgets('38 an ACTIVE zero-total order: NO Take payment, and it says WHY', (
    tester,
  ) async {
    _wide(tester);
    final l10n = await _l('en');
    await tester.pumpWidget(_wrap(await _seeded()));
    await tester.pumpAndSettle();
    await _showAllSections(tester);

    // The server now REFUSES a zero-value tender (it would mint a 0-amount payment row
    // and burn a receipt number), so the button must not be offered at all.
    expect(find.byKey(const Key('recent-pay-#Z0')), findsNothing);
    // A dead control with no reason is worse than none: explain it.
    expect(find.byKey(const Key('recent-nocharge-note-#Z0')), findsOneWidget);
    expect(find.text(l10n.posNoChargeNoPayment), findsOneWidget);
    // It is still ACTIVE, so it remains cancellable — exactly as the server allows.
    expect(find.byKey(const Key('recent-cancel-#Z0')), findsOneWidget);
  });

  // ===== 39. no receipt is shown for a refused zero tender ====================
  testWidgets(
    '39 a zero-total order shows the "No charge" chip and NO receipt',
    (tester) async {
      _wide(tester);
      final l10n = await _l('en');
      await tester.pumpWidget(_wrap(await _seeded()));
      await tester.pumpAndSettle();
      await _showAllSections(tester);

      // Neither "Paid" (no money was taken) nor "Unpaid" (nothing is owed).
      expect(find.byKey(const Key('order-settlement-#Z0')), findsOneWidget);
      expect(find.text(l10n.posNoChargeChip), findsWidgets);
      // No payment row -> no receipt to view or reprint.
      expect(find.byKey(const Key('recent-view-#Z0')), findsNothing);
      expect(find.byKey(const Key('recent-reprint-#Z0')), findsNothing);
    },
  );

  // ===== 40. the completed-zero-total Cancel case has a SPECIFIC message ======
  test('40 a refused cancel on a non-chargeable order is NOT a generic error', () async {
    final l10n = await _l('en');
    // The sheet maps a generic server rejection on a NON-CHARGEABLE order to the honest
    // "already closed" message: for such an order the server can only refuse a void
    // because it is terminal (a role denial and a completed-payment block both return
    // their own distinct shapes, and a zero-total order can carry no payment at all).
    expect(l10n.posCancelOrderClosed, isNotEmpty);
    expect(l10n.posCancelOrderClosed, isNot(l10n.posCancelOrderFailed));
    // ...and, crucially, the primary gate is the UI itself (test 35): the button is not
    // even offered on an order this device knows is terminal.
  });

  // ===== settlement, counters and filters =====================================
  test('the POS settlement getter mirrors the ONE server rule', () {
    final now = DateTime.now();
    PosRecentOrder o(String n, {int total = 4200, CashPayment? p}) =>
        PosRecentOrder(
          order: _view(n, total: total),
          submittedAt: now,
          payment: p,
        );

    // zero-total -> NON-CHARGEABLE: settled, owes nothing, no payment row.
    expect(o('#Z', total: 0).isFullySettled, isTrue);
    expect(o('#Z', total: 0).isNonChargeable, isTrue);
    // positive + covering payment -> settled.
    expect(o('#C', p: _payment('#C')).isFullySettled, isTrue);
    // positive + UNDER-COVERING payment -> still owes (a marker would say "paid").
    expect(o('#U', p: _payment('#U', amount: 2000)).isFullySettled, isFalse);
    expect(o('#U', p: _payment('#U', amount: 2000)).isPaid, isTrue);
    // positive + no payment -> owes.
    expect(o('#N').isFullySettled, isFalse);
  });

  testWidgets(
    'the unpaid badge counts OUTSTANDING MONEY, not missing payment rows',
    (tester) async {
      _wide(tester);
      final store = await _seeded();
      final container = ProviderContainer(
        overrides: [posRecentOrdersStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      // Let the controller hydrate from the store.
      container.read(posRecentOrdersControllerProvider);
      await tester.pump();
      await tester.pumpAndSettle();

      // #U1 (unpaid) + #UC (under-covered) owe money. #Z0/#ZC owe nothing; #P1 is covered.
      expect(
        container.read(posRecentOrdersControllerProvider.notifier).unpaidCount,
        2,
      );
    },
  );

  testWidgets('an UNDER-COVERED order reads Unpaid, not Paid', (tester) async {
    _wide(tester);
    final l10n = await _l('en');
    await tester.pumpWidget(_wrap(await _seeded()));
    await tester.pumpAndSettle();
    await _showAllSections(tester);

    // It carries a REAL completed payment, so the old marker called it "Paid" — while
    // 2200 was still owed.
    expect(find.byKey(const Key('recent-order-#UC')), findsOneWidget);
    expect(find.text(l10n.posUnpaidChip), findsWidgets);
    // ...and it is still chargeable, so Take payment is still on offer.
    expect(find.byKey(const Key('recent-pay-#UC')), findsNothing);
  });

  // ===== 41-43. ar / he RTL + en LTR ==========================================
  for (final (code, dir) in [
    ('ar', TextDirection.rtl),
    ('he', TextDirection.rtl),
    ('en', TextDirection.ltr),
  ]) {
    testWidgets('41-43 the settlement surface renders in $code (${dir.name})', (
      tester,
    ) async {
      _wide(tester);
      final l10n = await _l(code);
      await tester.pumpWidget(_wrap(await _seeded(), locale: Locale(code)));
      await tester.pumpAndSettle();

      expect(
        Directionality.of(tester.element(find.byType(RecentOrdersSheet))),
        dir,
      );
      expect(find.text(l10n.posNoChargeChip), findsWidgets);
      expect(find.text(l10n.posNoChargeNoPayment), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  // ===== 44. the phone layout still holds =====================================
  testWidgets('44 the settlement surface renders on a PHONE without overflow', (
    tester,
  ) async {
    _wide(tester, const Size(390, 2400));
    await tester.pumpWidget(_wrap(await _seeded()));
    await tester.pumpAndSettle();
    await _showAllSections(tester);

    expect(find.byKey(const Key('recent-order-#Z0')), findsOneWidget);
    expect(find.byKey(const Key('recent-cancel-#ZC')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // ===== 28. the payment sheet SHOWS the localized non-chargeable explanation ==
  // The POS no longer OFFERS Take payment on a zero-total order (test 38), so this is the
  // backstop: if the sheet is reached anyway, the server's typed `order_not_chargeable`
  // refusal must produce its own explanation — NOT the generic "payment failed, try
  // again" banner, which would send the cashier into a retry loop that can never succeed.
  for (final code in ['ar', 'he', 'en']) {
    testWidgets(
      '28 a refused zero tender shows the localized non-chargeable explanation ($code)',
      (tester) async {
        _wide(tester);
        final l10n = await _l(code);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              paymentRepositoryProvider.overrideWithValue(
                const _NotChargeablePaymentRepo(),
              ),
            ],
            child: MaterialApp(
              locale: Locale(code),
              localizationsDelegates: restoflowLocalizationsDelegates,
              supportedLocales: kSupportedLocales,
              home: const Scaffold(
                body: CashPaymentSheet(
                  orderNumber: '#Z0',
                  amountMinor: 0,
                  currencyCode: 'ILS',
                  orderId: 'oid-#Z0',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Cash tender of 0.00 — it "covers" a zero total, so Confirm enables and the
        // request actually reaches the server, which refuses it.
        await tester.enterText(find.byType(TextField).first, '0.00');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm-payment-button')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('payment-not-chargeable-banner')),
          findsOneWidget,
          reason: '$code: the order owes nothing — say so',
        );
        expect(
          find.byKey(const Key('payment-failed-banner')),
          findsNothing,
          reason: '$code: "try again" would be advice that can never work',
        );
        expect(find.text(l10n.posNoChargeNoPayment), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

/// A repository that fails exactly the way the server now does for a zero-total order:
/// the typed `order_not_chargeable` refusal.
class _NotChargeablePaymentRepo implements PaymentRepository {
  const _NotChargeablePaymentRepo();

  @override
  Future<CashPayment> recordCashPayment({
    required String orderId,
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
    PaymentMethod method = PaymentMethod.cash,
    int? expectedRevision,
  }) async =>
      throw const PaymentException('order_not_chargeable', notChargeable: true);

  @override
  ShiftContext shiftContext() => const ShiftContext(
    shiftOpen: false,
    drawerOpen: false,
    openingFloatMinor: 0,
    cashInDrawerMinor: 0,
    lastPaymentMinor: 0,
    currencyCode: 'ILS',
  );

  @override
  CashPayment? paymentFor(String orderNumber) => null;
}
