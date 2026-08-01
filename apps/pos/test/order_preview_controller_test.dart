@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_preview_model.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/state/order_preview_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/receipt_print_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/order_detail_preview.dart';

/// ORDER-DETAIL-PREVIEW-001 — C/D/E/F/H/I/J/K/L. the controller's fencing and
/// failure honesty, plus the rendered preview across paid/unpaid/terminal,
/// service rounds, offline, RTL and four widths.

const _code = '#PV1';
const _orderId = 'oid-PV1';
const _paymentUuid = '0a911111-2222-4333-8444-555566667777';

// ---------------------------------------------------------------------------
// fixtures
// ---------------------------------------------------------------------------

PosOrderDetailItem _item({
  String name = 'Classic Burger',
  int quantity = 1,
  int unitPriceMinor = 5400,
  int lineTotalMinor = 5400,
  List<PosOrderDetailModifier> modifiers = const [
    PosOrderDetailModifier(
      optionName: 'Extra meat',
      priceMinor: 700,
      quantity: 2,
      modifierName: 'Extras',
    ),
  ],
  String? notes = 'no onion',
  String? serviceRoundId,
  int? roundNumber,
  int linePosition = 1,
}) => PosOrderDetailItem(
  name: name,
  quantity: quantity,
  unitPriceMinor: unitPriceMinor,
  lineDiscountMinor: 0,
  lineTotalMinor: lineTotalMinor,
  modifiers: modifiers,
  notes: notes,
  serviceRoundId: serviceRoundId,
  roundNumber: roundNumber,
  linePosition: linePosition,
);

PosOrderDetail _detail({
  String status = 'served',
  List<PosOrderDetailItem>? items,
  List<PosOrderDetailRound> rounds = const [],
  PosOrderDetailPayment? payment,
  int grand = 5400,
}) => PosOrderDetail(
  orderId: _orderId,
  orderCode: _code,
  orderType: 'dine_in',
  status: status,
  revision: 2,
  currencyCode: 'ILS',
  subtotalMinor: grand,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: grand,
  tableLabel: 'T5',
  customerName: 'Dana',
  customerPhone: '0591234567',
  items: items ?? [_item()],
  rounds: rounds,
  payment: payment,
);

PosOrderDetailPayment _serverPayment() => PosOrderDetailPayment(
  paymentId: _paymentUuid,
  status: PaymentStatus.completed,
  method: PaymentMethod.card,
  amountMinor: 5400,
  tenderedMinor: 6000,
  changeMinor: 600,
  paidAt: DateTime.utc(2026, 7, 30, 11),
  receiptNumber: 'R-9',
);

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
      note: 'no onion',
    ),
  ],
);

PosRecentOrder _order({
  PosSettlement settlement = PosSettlement.unpaid,
  String status = 'served',
  CashPayment? payment,
  String orderId = _orderId,
}) {
  final at = DateTime.utc(2026, 7, 30, 10);
  return PosRecentOrder(
    order: _view(),
    snapshot: PosOrderSnapshot(
      orderId: orderId,
      orderCode: _code,
      revision: 2,
      status: status,
      settlement: settlement,
      subtotalMinor: 5400,
      discountTotalMinor: 0,
      taxTotalMinor: 0,
      grandTotalMinor: 5400,
      createdAt: at,
      updatedAt: at,
      syncAt: at,
      orderType: 'dine_in',
      tableLabel: 'T5',
      currencyCode: 'ILS',
    ),
    submittedAt: at,
    payment: payment,
  );
}

class _CountingRepo implements OrderDetailRepository {
  _CountingRepo(this._detail);
  final PosOrderDetail _detail;
  int fetches = 0;
  @override
  Future<PosOrderDetail> fetch(String orderId) async {
    fetches++;
    return _detail;
  }
}

class _ThrowingRepo implements OrderDetailRepository {
  int fetches = 0;
  @override
  Future<PosOrderDetail> fetch(String orderId) async {
    fetches++;
    throw const PosOrderDetailException(PosOrderDetailFailure.transport);
  }
}

class _GatedRepo implements OrderDetailRepository {
  final List<Completer<PosOrderDetail>> gates = [];
  int fetches = 0;
  @override
  Future<PosOrderDetail> fetch(String orderId) {
    fetches++;
    final gate = Completer<PosOrderDetail>();
    gates.add(gate);
    return gate.future;
  }
}

ProviderContainer _container(OrderDetailRepository repo) {
  final c = ProviderContainer(
    overrides: [
      // The detail repository is demo-gated in production, so a REAL-mode
      // config is required to exercise the authoritative path at all.
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      orderDetailRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Keeps the autoDispose family alive for the test and returns its state.
///
/// The family is keyed on the ORDER OBJECT, which is stable in production (the
/// preview route captures one instance for its whole life) but must be held
/// explicitly here, or each read would key a brand-new controller.
OrderPreviewState _watch(ProviderContainer c, PosRecentOrder order) {
  final sub = c.listen(
    orderPreviewControllerProvider(order),
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(sub.close);
  return sub.read();
}

Future<void> _tick() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Future<void> _pumpPreview(
  WidgetTester tester,
  ProviderContainer container,
  PosRecentOrder order, {
  Locale locale = const Locale('en'),
  Size size = const Size(1400, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: OrderDetailPreview(
            order: order,
            actions: resolveOrderActions(order),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('H. loading, error and retry', () {
    test(
      'H1 a real order fetches the authoritative detail EXACTLY once',
      () async {
        final repo = _CountingRepo(_detail());
        final c = _container(repo);
        final order = _order();
        _watch(c, order);
        await _tick();

        expect(repo.fetches, 1);
        final state = c.read(orderPreviewControllerProvider(order));
        expect(state.isReady, isTrue);
        expect(state.model!.source, OrderPreviewSource.authoritative);
        expect(state.staleLocalCopy, isFalse);
      },
    );

    test(
      'H2 Retry performs exactly ONE additional fetch and no other call',
      () async {
        final repo = _CountingRepo(_detail());
        final c = _container(repo);
        final order = _order();
        _watch(c, order);
        await _tick();
        expect(repo.fetches, 1);

        await c.read(orderPreviewControllerProvider(order).notifier).load();
        await _tick();

        expect(repo.fetches, 2);
        // Nothing else moved: no payment, no print, no queued operation.
        expect(c.read(outboxControllerProvider), isEmpty);
        expect(c.read(receiptPrintControllerProvider), isEmpty);
      },
    );

    test('H3 a CLOSED preview ignores a late response', () async {
      final repo = _GatedRepo();
      final c = _container(repo);
      final order = _order();
      final sub = c.listen(
        orderPreviewControllerProvider(order),
        (_, _) {},
        fireImmediately: true,
      );
      await _tick();
      expect(repo.gates, hasLength(1));

      // The preview closes BEFORE the server answers.
      sub.close();
      await _tick();
      repo.gates.single.complete(_detail());
      await _tick();
      // Nothing threw, and nothing was published into a disposed notifier.
      expect(repo.fetches, 1);
    });

    test('H4 a SUPERSEDED response is dropped: the newest load wins', () async {
      final repo = _GatedRepo();
      final c = _container(repo);
      final order = _order();
      _watch(c, order);
      final notifier = c.read(orderPreviewControllerProvider(order).notifier);
      await _tick();
      expect(repo.gates, hasLength(1));

      // A Retry supersedes the first request.
      unawaited(notifier.load());
      await _tick();
      expect(repo.gates, hasLength(2));

      // The STALE first response lands last and must not win.
      repo.gates[1].complete(_detail(status: 'completed'));
      await _tick();
      repo.gates[0].complete(_detail(status: 'served'));
      await _tick();

      expect(
        c.read(orderPreviewControllerProvider(order)).model!.status,
        'completed',
        reason: 'the superseded response must not overwrite the newer one',
      );
    });

    test('H5 two DIFFERENT orders never publish into each other', () async {
      final repo = _CountingRepo(_detail());
      final c = _container(repo);
      final a = _order();
      final b = _order(orderId: 'oid-OTHER');
      _watch(c, a);
      _watch(c, b);
      await _tick();
      // A family provider keeps one controller per order.
      expect(
        c.read(orderPreviewControllerProvider(a)).model,
        isNot(same(c.read(orderPreviewControllerProvider(b)).model)),
      );
    });
  });

  group('I. offline / local copy', () {
    test('I1 a failed read with usable local lines degrades to a LABELLED '
        'local copy and stays retryable', () async {
      final repo = _ThrowingRepo();
      final c = _container(repo);
      final order = _order();
      _watch(c, order);
      await _tick();

      final state = c.read(orderPreviewControllerProvider(order));
      expect(state.isReady, isTrue);
      expect(state.staleLocalCopy, isTrue);
      expect(state.model!.source, OrderPreviewSource.localCopy);
      expect(state.model!.isAuthoritative, isFalse);
      expect(state.model!.lines, isNotEmpty);
      // Retry is a plain re-read.
      await c.read(orderPreviewControllerProvider(order).notifier).load();
      await _tick();
      expect(repo.fetches, 2);
      expect(c.read(outboxControllerProvider), isEmpty);
    });

    testWidgets('I2 the local-copy warning is VISIBLE and offers Retry', (
      tester,
    ) async {
      final c = _container(_ThrowingRepo());
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await _pumpPreview(tester, c, _order());

      expect(
        find.byKey(const Key('order-detail-preview-local-copy')),
        findsOneWidget,
      );
      expect(find.text(l10n.posOrderPreviewLocalCopy), findsOneWidget);
      expect(
        find.byKey(const Key('order-detail-preview-retry')),
        findsOneWidget,
      );
    });

    test('I3 a failed read with NO usable local lines fails honestly rather '
        'than showing an empty order', () async {
      final repo = _ThrowingRepo();
      final c = _container(repo);
      final bare = PosRecentOrder(
        snapshot: _order().snapshot,
        submittedAt: DateTime.utc(2026, 7, 30, 10),
      );
      _watch(c, bare);
      await _tick();
      final state = c.read(orderPreviewControllerProvider(bare));
      expect(state.isFailed, isTrue);
      expect(state.model, isNull);
    });

    testWidgets('I4 that failure renders a title, body and Retry - never a '
        'perpetual spinner', (tester) async {
      final c = _container(_ThrowingRepo());
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final bare = PosRecentOrder(
        snapshot: _order().snapshot,
        submittedAt: DateTime.utc(2026, 7, 30, 10),
      );
      await _pumpPreview(tester, c, bare);

      expect(
        find.byKey(const Key('order-detail-preview-error')),
        findsOneWidget,
      );
      expect(find.text(l10n.posOrderPreviewLoadFailedTitle), findsOneWidget);
      expect(find.text(l10n.posOrderPreviewLoadFailedBody), findsOneWidget);
      expect(
        find.byKey(const Key('order-detail-preview-retry')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('C/D. unpaid and paid presentation', () {
    testWidgets(
      'C1 an UNPAID order shows the amount due and NO payment facts',
      (tester) async {
        final c = _container(_CountingRepo(_detail()));
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final order = _order();
        await _pumpPreview(tester, c, order);

        expect(
          find.byKey(const Key('order-detail-preview-amount-due')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('order-detail-preview-paid')),
          findsNothing,
        );
        expect(find.text(l10n.posPaymentMethodLabel), findsNothing);
        expect(find.text(l10n.posReceiptChange), findsNothing);
        // Items, modifiers and the note are all present.
        expect(find.textContaining('Classic Burger'), findsWidgets);
        expect(find.textContaining('Extra meat'), findsWidgets);
        expect(find.textContaining('no onion'), findsWidgets);
        // The eligible actions are offered under the preview prefix.
        expect(find.byKey(const Key('preview-pay-$_code')), findsOneWidget);
        expect(
          find.byKey(const Key('preview-print-bill-$_code')),
          findsOneWidget,
        );
      },
    );

    testWidgets('D1 a PAID order shows the authoritative payment facts and no '
        'collect-payment action', (tester) async {
      final c = _container(_CountingRepo(_detail(payment: _serverPayment())));
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final order = _order(
        settlement: PosSettlement.paid,
        status: 'completed',
        payment: CashPayment(
          paymentId: 'local-1',
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
          paidAt: DateTime.utc(2026, 7, 30, 11),
        ),
      );
      await _pumpPreview(tester, c, order);

      expect(
        find.byKey(const Key('order-detail-preview-paid')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('order-detail-preview-amount-due')),
        findsNothing,
      );
      expect(find.textContaining(l10n.posPaymentMethodLabel), findsWidgets);
      expect(find.text(l10n.posReceiptChange), findsWidgets);
      expect(
        find.textContaining('R-9'),
        findsWidgets,
        reason: 'the AUTHORITATIVE receipt number wins over the local one',
      );
      // Collect payment and the unpaid bill are both gone.
      expect(find.byKey(const Key('preview-pay-$_code')), findsNothing);
      expect(find.byKey(const Key('preview-print-bill-$_code')), findsNothing);
      // The receipt actions are offered instead.
      expect(find.byKey(const Key('preview-view-$_code')), findsOneWidget);
    });
  });

  group('E. service rounds in the rendered preview', () {
    testWidgets('E1 original and round lines both appear, and ONLY the round '
        'line is tagged', (tester) async {
      final c = _container(
        _CountingRepo(
          _detail(
            items: [
              _item(),
              _item(
                name: 'Baklava',
                unitPriceMinor: 1200,
                lineTotalMinor: 1200,
                modifiers: const [],
                notes: null,
                serviceRoundId: 'r-2',
                roundNumber: 2,
                linePosition: 2,
              ),
            ],
            rounds: const [
              PosOrderDetailRound(
                roundId: 'r-2',
                roundNumber: 2,
                status: 'submitted',
              ),
            ],
            grand: 6600,
          ),
        ),
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await _pumpPreview(tester, c, _order());

      expect(find.textContaining('Classic Burger'), findsWidgets);
      expect(find.textContaining('Baklava'), findsWidgets);
      final tag = '${l10n.kdsAdditionLabel} · ${l10n.kdsRoundLabel(2)}';
      expect(
        find.text(tag),
        findsOneWidget,
        reason: 'only the round line carries the addition tag',
      );
    });
  });

  group('F. terminal states', () {
    testWidgets('F1 a CANCELLED order keeps its history and offers no '
        'payment or add-items action', (tester) async {
      final c = _container(_CountingRepo(_detail(status: 'cancelled')));
      final order = _order(status: 'cancelled');
      final actions = resolveOrderActions(order);
      expect(actions.canPay, isFalse);
      expect(actions.canAddItems, isFalse);

      await _pumpPreview(tester, c, order);

      // The historical contents are still readable.
      expect(find.textContaining('Classic Burger'), findsWidgets);
      expect(
        find.byKey(const Key('order-detail-preview-total')),
        findsOneWidget,
      );
      // And nothing mutating is offered.
      expect(find.byKey(const Key('preview-pay-$_code')), findsNothing);
      expect(find.byKey(const Key('preview-add-items-$_code')), findsNothing);
      expect(find.byKey(const Key('preview-cancel-$_code')), findsNothing);
    });
  });

  group('L. responsive and RTL', () {
    for (final width in <double>[390, 700, 940, 1320]) {
      testWidgets('L-$width renders without overflow and keeps the total and '
          'the actions reachable', (tester) async {
        final c = _container(
          _CountingRepo(
            _detail(
              items: [
                for (var i = 0; i < 12; i++)
                  _item(
                    name: 'صحن شاورما دجاج مع بطاطا مقلية وسلطة $i',
                    modifiers: const [
                      PosOrderDetailModifier(
                        optionName: 'תוספת בשר מיוחדת עם רוטב שום',
                        priceMinor: 700,
                        quantity: 2,
                        modifierName: 'תוספות',
                      ),
                    ],
                    linePosition: i + 1,
                  ),
              ],
            ),
          ),
        );
        await _pumpPreview(
          tester,
          c,
          _order(),
          locale: const Locale('ar'),
          size: Size(width, 1400),
        );

        expect(tester.takeException(), isNull);
        expect(
          Directionality.of(
            tester.element(find.byKey(const Key('order-detail-preview'))),
          ),
          TextDirection.rtl,
        );
        // The body scrolls, so the total is reachable however many items there
        // are, and the pinned actions never leave the screen.
        await tester.drag(
          find.byKey(const Key('order-detail-preview-body')),
          const Offset(0, -4000),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('order-detail-preview-total')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('preview-pay-$_code')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('L-he Hebrew renders RTL with no overflow', (tester) async {
      final c = _container(_CountingRepo(_detail()));
      await _pumpPreview(
        tester,
        c,
        _order(),
        locale: const Locale('he'),
        size: const Size(390, 1400),
      );
      expect(tester.takeException(), isNull);
      expect(
        Directionality.of(
          tester.element(find.byKey(const Key('order-detail-preview'))),
        ),
        TextDirection.rtl,
      );
    });
  });

  group('K. action delegation', () {
    testWidgets('K1 the preview reuses the SAME eligibility object and emits '
        'preview-prefixed keys, leaving the Orders keys untouched', (
      tester,
    ) async {
      final c = _container(_CountingRepo(_detail()));
      final order = _order();
      final actions = resolveOrderActions(order);
      await _pumpPreview(tester, c, order);

      // Present iff the central policy says so.
      expect(actions.canPay, isTrue);
      expect(find.byKey(const Key('preview-pay-$_code')), findsOneWidget);
      expect(
        find.byKey(const Key('preview-print-bill-$_code')),
        findsOneWidget,
      );
      // The Orders-sheet namespace is NOT emitted by the preview.
      expect(find.byKey(const Key('recent-pay-$_code')), findsNothing);
      expect(find.byKey(const Key('recent-print-bill-$_code')), findsNothing);
    });

    testWidgets('K2 opening and closing the preview runs no handler at all', (
      tester,
    ) async {
      final c = _container(_CountingRepo(_detail()));
      await _pumpPreview(tester, c, _order());
      await tester.pumpAndSettle();

      expect(c.read(outboxControllerProvider), isEmpty);
      expect(c.read(receiptPrintControllerProvider), isEmpty);
    });
  });
}
