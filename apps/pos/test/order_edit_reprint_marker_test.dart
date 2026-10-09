import 'dart:convert' show jsonDecode;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show KitchenChangeSlipLabels, OrderChangeSlipView;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_edit_slip.dart'
    show encodeOrderChangeSlipView, orderNowSlipFromDetail;
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/print/print_bridge.dart'
    show PosPrintBridge, posPrintBridgeProvider;
import 'package:restoflow_pos/src/print/print_document.dart' show PrintDocument;
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/order_action_row.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import 'support/pos_package_root.dart';

/// ORDER-EDIT-001F (decision D6, "R2") — THE REPRINT MARKER.
///
/// Once an order has been edited, its order-time snapshot is stale: removed
/// food would come back on paper. The manual kitchen reprint of an EDITED order
/// (`editCount > 0`) therefore prints the ORDER-NOW change slip — "ORDER
/// CHANGED · Change N", every LIVE line of the AUTHORITATIVE detail, "Replaces
/// earlier tickets" — and never the local snapshot, even when one exists. An
/// unedited order reprints exactly as before (ORDER-REPRINT-CHOOSER-038).
///
/// The detail is a REAL post-edit `pos_order_detail` captured on local
/// PostgreSQL (test/fixtures/order_edit_slip/a_every_op.json).
Map<String, Object?> _fixture() {
  final file = File(
    p.join(
      locatePosPackageRoot().path,
      'test',
      'fixtures',
      'order_edit_slip',
      'a_every_op.json',
    ),
  );
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

final PosOrderDetail _after = PosOrderDetail.fromJson(_fixture()['after'])!;
final String _orderId = _after.orderId;
final String _code = _after.orderCode;
final _at = DateTime.utc(2026, 10, 9, 5, 40);

/// The order-time snapshot THIS till captured at submit — before the edit.
SubmittedOrderView _staleView() => SubmittedOrderView(
  orderNumber: _code,
  orderType: OrderType.dineIn,
  currencyCode: 'ILS',
  subtotalMinor: 9000,
  orderId: _orderId,
  tableLabel: 'T4',
  lines: [
    SubmittedLineView(
      name: 'Stale Burger',
      quantity: 3,
      lineTotalMinor: 9000,
      currencyCode: 'ILS',
    ),
  ],
);

PosOrderSnapshot _snapshot({required int editCount, bool paid = true}) =>
    PosOrderSnapshot(
      orderId: _orderId,
      orderCode: _code,
      revision: 4,
      status: 'served',
      settlement: paid ? PosSettlement.paid : PosSettlement.unpaid,
      subtotalMinor: 9000,
      discountTotalMinor: 0,
      taxTotalMinor: 0,
      grandTotalMinor: 9000,
      createdAt: _at,
      updatedAt: _at,
      syncAt: _at,
      orderType: 'dine_in',
      tableLabel: 'T4',
      currencyCode: 'ILS',
      editCount: editCount,
    );

PosRecentOrder _paidRow({required int editCount}) => PosRecentOrder(
  order: _staleView(),
  snapshot: _snapshot(editCount: editCount),
  status: 'served',
  submittedAt: _at,
  payment: CashPayment(
    paymentId: 'pay-1',
    orderNumber: _code,
    deviceId: 'dev-1',
    localOperationId: 'op-pay-1',
    method: PaymentMethod.cash,
    status: PaymentStatus.completed,
    amountMinor: 9000,
    tenderedMinor: 10000,
    changeMinor: 1000,
    currencyCode: 'ILS',
    receiptNumber: 'R-1',
    paidAt: _at,
    orderId: _orderId,
  ),
);

PosRecentOrder _openRow({required int editCount}) => PosRecentOrder(
  order: _staleView(),
  snapshot: _snapshot(editCount: editCount, paid: false),
  submittedAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
);

class _FakeDetailRepo implements OrderDetailRepository {
  _FakeDetailRepo(this.detail, {this.fail = false});
  final PosOrderDetail detail;
  final bool fail;
  int fetches = 0;
  @override
  Future<PosOrderDetail> fetch(String orderId) async {
    fetches++;
    if (fail) {
      throw const PosOrderDetailException(PosOrderDetailFailure.transport);
    }
    return detail;
  }
}

class _RecordingBridge implements PosPrintBridge {
  final List<PrintDocument> documents = [];
  @override
  Future<pp.BridgeSubmitResult> submit(PrintDocument document) async {
    documents.add(document);
    return const pp.BridgeSubmitResult.sentToPrinter();
  }

  @override
  Future<pp.BridgeHealth> health() async => pp.BridgeHealth.connected;
}

/// The ORDER-TIME ticket seam (ORDER-REPRINT-CHOOSER-038).
class _RecordingTickets {
  final List<SubmittedOrderView> orders = [];
  PosKitchenReprint get seam =>
      ({required container, required order, required labels}) async {
        orders.add(order);
        return PosKitchenPrintOutcome.printed;
      };
}

/// The CHANGE-SLIP seam (ORDER-EDIT-001F).
class _RecordingSlips {
  final List<(OrderChangeSlipView, KitchenChangeSlipLabels)> sent = [];
  PosKitchenPrintOutcome outcome = PosKitchenPrintOutcome.printed;
  PosOrderEditSlipPrint get seam =>
      ({
        required read,
        required slip,
        required labels,
        required changeLabels,
      }) async {
        sent.add((slip, changeLabels));
        return outcome;
      };
}

class _Harness {
  _Harness(this.bridge, this.tickets, this.slips, this.repo);
  final _RecordingBridge bridge;
  final _RecordingTickets tickets;
  final _RecordingSlips slips;
  final _FakeDetailRepo repo;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required PosRecentOrder row,
  bool demo = false,
  bool failFetch = false,
  PosOrderDetail? detail,
  PosKitchenPrintOutcome outcome = PosKitchenPrintOutcome.printed,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1024, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final h = _Harness(
    _RecordingBridge(),
    _RecordingTickets(),
    _RecordingSlips()..outcome = outcome,
    _FakeDetailRepo(detail ?? _after, fail: failFetch),
  );
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: demo),
      ),
      posNativePrintingAvailableProvider.overrideWithValue(false),
      posPrintBridgeProvider.overrideWithValue(h.bridge),
      posKitchenReprintProvider.overrideWithValue(h.tickets.seam),
      posOrderEditSlipPrintProvider.overrideWithValue(h.slips.seam),
      orderDetailRepositoryProvider.overrideWithValue(h.repo),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: OrderActionRow(
              order: row,
              l10n: AppLocalizations.of(ctx),
              actions: resolveOrderActions(row),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

Future<void> _reprintKitchen(WidgetTester tester) async {
  await tester.tap(find.byKey(Key('recent-reprint-$_code')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('reprint-choice-kitchen')));
  await tester.pumpAndSettle();
}

void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('the fixture is a real EDITED order with live lines', () {
    expect(_after.editCount, 1);
    expect(orderNowSlipFromDetail(_after), isNotNull);
  });

  testWidgets('an EDITED order reprints the ORDER-NOW slip from the '
      'authoritative detail — never its stale order-time snapshot', (
    tester,
  ) async {
    final h = await _pump(tester, row: _paidRow(editCount: 1));
    await _reprintKitchen(tester);

    expect(h.repo.fetches, 1);
    expect(h.tickets.orders, isEmpty, reason: 'no order-time ticket');
    expect(h.bridge.documents, isEmpty, reason: 'never a receipt instead');
    final (slip, changeLabels) = h.slips.sent.single;
    // EXACTLY the ORDER-NOW slip of the authoritative detail: "Change 1",
    // no change sections, every live line.
    expect(
      encodeOrderChangeSlipView(slip),
      encodeOrderChangeSlipView(orderNowSlipFromDetail(_after)!),
    );
    expect(slip.editNumber, 1);
    expect(slip.changes, isEmpty);
    expect(slip.orderNow, hasLength(_after.items.length));
    expect(slip.orderNow.map((i) => i.name), isNot(contains('Stale Burger')));
    expect(changeLabels.changeNumber(slip.editNumber), 'Change 1');
    expect(changeLabels.orderChanged, l10n.kitchenChangeSlipTitle);
    expect(find.text(l10n.posKitchenTicketPrintedSnack), findsOneWidget);
  });

  testWidgets('an UNEDITED order is unchanged: its local snapshot through the '
      'ticket seam, no fetch, no slip', (tester) async {
    final h = await _pump(tester, row: _paidRow(editCount: 0));
    await _reprintKitchen(tester);
    expect(h.repo.fetches, 0);
    expect(h.slips.sent, isEmpty);
    expect(h.tickets.orders.single.lines.single.name, 'Stale Burger');
    expect(find.text(l10n.posKitchenTicketPrintedSnack), findsOneWidget);
  });

  testWidgets('the OPEN-order print chooser\'s kitchen option routes the '
      'same way', (tester) async {
    final h = await _pump(tester, row: _openRow(editCount: 1));
    await tester.tap(find.byKey(Key('recent-print-bill-$_code')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('print-choice-kitchen')));
    await tester.pumpAndSettle();
    expect(h.tickets.orders, isEmpty);
    expect(h.slips.sent.single.$1.editNumber, 1);
  });

  testWidgets('a FAILED fetch prints nothing and says so', (tester) async {
    final h = await _pump(tester, row: _paidRow(editCount: 1), failFetch: true);
    await _reprintKitchen(tester);
    expect(h.slips.sent, isEmpty);
    expect(h.tickets.orders, isEmpty, reason: 'no stale fallback');
    expect(find.text(l10n.posReprintKitchenFetchFailed), findsOneWidget);
  });

  testWidgets('a detail with NOTHING live to print prints nothing (honest '
      'unavailable, no stale fallback)', (tester) async {
    final h = await _pump(
      tester,
      row: _paidRow(editCount: 1),
      detail: PosOrderDetail.fromJson({
        ...(_fixture()['after']! as Map).cast<String, Object?>(),
        'items': const <Object?>[],
      })!,
    );
    await _reprintKitchen(tester);
    expect(h.slips.sent, isEmpty);
    expect(h.tickets.orders, isEmpty);
    expect(find.text(l10n.posReprintKitchenUnavailable), findsOneWidget);
  });

  testWidgets('the print outcome maps to the existing kitchen snacks', (
    tester,
  ) async {
    for (final (outcome, message) in [
      (
        PosKitchenPrintOutcome.noPrinterConfigured,
        l10n.posKitchenPrinterNotConfiguredSnack,
      ),
      (PosKitchenPrintOutcome.failed, l10n.posKitchenTicketPrintFailedSnack),
    ]) {
      await _pump(tester, row: _paidRow(editCount: 1), outcome: outcome);
      await _reprintKitchen(tester);
      expect(find.text(message), findsOneWidget, reason: '$outcome');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('DEMO mode (no server) keeps the local snapshot path', (
    tester,
  ) async {
    final h = await _pump(tester, row: _paidRow(editCount: 1), demo: true);
    await _reprintKitchen(tester);
    expect(h.repo.fetches, 0);
    expect(h.slips.sent, isEmpty);
    expect(h.tickets.orders, hasLength(1));
  });

  testWidgets('the slip labels follow the UI language (ar)', (tester) async {
    final ar = await AppLocalizations.delegate.load(const Locale('ar'));
    final h = await _pump(
      tester,
      row: _paidRow(editCount: 1),
      locale: const Locale('ar'),
    );
    await _reprintKitchen(tester);
    final (slip, changeLabels) = h.slips.sent.single;
    expect(changeLabels.orderChanged, ar.kitchenChangeSlipTitle);
    expect(
      changeLabels.changeNumber(slip.editNumber),
      ar.kitchenEditChangeNumber(1),
    );
    expect(find.text(ar.posKitchenTicketPrintedSnack), findsOneWidget);
  });
}
