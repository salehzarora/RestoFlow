import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/round_print_claim_store.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/print/print_bridge.dart'
    show PosPrintBridge, posPrintBridgeProvider;
import 'package:restoflow_pos/src/print/print_document.dart' show PrintDocument;
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/order_action_row.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// KIOSK-PRINT-114B.5A — Bug B: the POS manual KITCHEN reprint for a
/// BRANCH-DISCOVERED order (a kiosk order, or one taken on another till).
///
/// Such a row has no device-local order-time snapshot (`PosRecentOrder.order`
/// is null), so the kitchen tile used to refuse and nothing printed. It now
/// resolves the printable view from the AUTHORITATIVE `pos_order_detail` (the
/// same source the receipt reprint trusts) and prints through the SAME manual
/// seam — no auto-print guard, no dispatch claim/ack, no order mutation; a
/// second explicit press prints a second copy. The detail carries no prep/meat
/// snapshots until 114B.5B, so the ticket prints WITHOUT the count block and
/// the operator is told so.
final _at = DateTime.utc(2026, 8, 25, 12, 30);

PosOrderSnapshot _snapshot() => PosOrderSnapshot(
  orderId: 'order-kiosk-1',
  orderCode: '#K10SK1',
  revision: 3,
  status: 'served',
  settlement: PosSettlement.paid,
  subtotalMinor: 9000,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 9000,
  createdAt: _at,
  updatedAt: _at,
  syncAt: _at,
  orderType: 'takeaway',
  currencyCode: 'ILS',
);

PosOrderDetail _detail() => const PosOrderDetail(
  orderId: 'order-kiosk-1',
  orderCode: '#K10SK1',
  orderType: 'takeaway',
  status: 'served',
  revision: 3,
  currencyCode: 'ILS',
  subtotalMinor: 9000,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 9000,
  customerName: 'Saleh',
  items: [
    PosOrderDetailItem(
      name: 'Classic Burger',
      quantity: 2,
      unitPriceMinor: 4500,
      lineDiscountMinor: 0,
      lineTotalMinor: 9000,
      notes: 'well done',
      modifiers: [
        PosOrderDetailModifier(
          optionName: '240g',
          priceMinor: 0,
          quantity: 1,
          modifierName: 'Size',
        ),
      ],
      linePosition: 1,
    ),
  ],
  rounds: [],
);

class _FakeDetailRepo implements OrderDetailRepository {
  _FakeDetailRepo(this._detail, {this.fail = false});
  final PosOrderDetail _detail;
  final bool fail;
  int fetches = 0;
  @override
  Future<PosOrderDetail> fetch(String orderId) async {
    fetches++;
    if (fail) {
      throw const PosOrderDetailException(PosOrderDetailFailure.transport);
    }
    return _detail;
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

class _RecordingKitchen {
  final List<SubmittedOrderView> orders = [];
  PosKitchenPrintOutcome outcome = PosKitchenPrintOutcome.printed;
  PosKitchenReprint get seam =>
      ({required container, required order, required labels}) async {
        orders.add(order);
        return outcome;
      };
}

Future<(_RecordingBridge, _RecordingKitchen, _FakeDetailRepo)> _pump(
  WidgetTester tester, {
  bool failFetch = false,
  PosRecentOrder? row,
}) async {
  tester.view.physicalSize = const Size(1024, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final bridge = _RecordingBridge();
  final kitchen = _RecordingKitchen();
  final repo = _FakeDetailRepo(_detail(), fail: failFetch);
  final container = ProviderContainer(
    overrides: [
      // REAL mode: a branch-discovered order may be fetched from the server.
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posNativePrintingAvailableProvider.overrideWithValue(false),
      posPrintBridgeProvider.overrideWithValue(bridge),
      posKitchenReprintProvider.overrideWithValue(kitchen.seam),
      orderDetailRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  final order = row ?? PosRecentOrder.discovered(_snapshot());
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: OrderActionRow(
              order: order,
              l10n: AppLocalizations.of(ctx),
              actions: resolveOrderActions(order),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (bridge, kitchen, repo);
}

Future<void> _tapKitchenReprint(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('recent-reprint-#K10SK1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('reprint-choice-kitchen')));
  await tester.pumpAndSettle();
}

void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('B2. a branch-discovered (kiosk) order reprints EXACTLY one '
      'kitchen document from the authoritative detail', (tester) async {
    final (bridge, kitchen, repo) = await _pump(tester);
    await _tapKitchenReprint(tester);
    expect(repo.fetches, 1);
    expect(kitchen.orders, hasLength(1));
    final printed = kitchen.orders.single;
    expect(printed.orderNumber, '#K10SK1');
    expect(printed.customerName, 'Saleh');
    expect(printed.lines.single.name, 'Classic Burger');
    expect(printed.lines.single.quantity, 2);
    expect(printed.lines.single.modifiers, ['240g']);
    expect(printed.lines.single.note, 'well done');
    // Never a receipt instead.
    expect(bridge.documents, isEmpty);
    expect(find.text(l10n.posKitchenTicketPrintedSnack), findsOneWidget);
    expect(find.text(l10n.posReprintKitchenUnavailable), findsNothing);
  });

  testWidgets('B9. the detail-sourced reprint prints WITHOUT counts and says '
      'so (counts-unavailable notice, after the print outcome)', (
    tester,
  ) async {
    final (_, kitchen, _) = await _pump(tester);
    await _tapKitchenReprint(tester);
    final printed = kitchen.orders.single;
    expect(printed.lines.every((l) => l.kitchenMeats.isEmpty), isTrue);
    expect(printed.lines.every((l) => l.prepComponents.isEmpty), isTrue);
    // The mapper omits the count block honestly (nothing re-derived).
    expect(kdsTicketViewFromSubmittedOrder(printed).kitchenCounts, isEmpty);
    // The second snack queues behind the print outcome; let it surface.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text(l10n.posReprintKitchenCountsUnavailable), findsOneWidget);
  });

  testWidgets('B5. a second explicit press prints a SECOND copy', (
    tester,
  ) async {
    final (_, kitchen, repo) = await _pump(tester);
    await _tapKitchenReprint(tester);
    await _tapKitchenReprint(tester);
    expect(kitchen.orders, hasLength(2));
    expect(repo.fetches, 2);
  });

  testWidgets('B8. a failed detail fetch is an honest KITCHEN-only failure — '
      'nothing prints anywhere', (tester) async {
    final (bridge, kitchen, repo) = await _pump(tester, failFetch: true);
    await _tapKitchenReprint(tester);
    expect(repo.fetches, 1);
    expect(kitchen.orders, isEmpty);
    expect(bridge.documents, isEmpty);
    expect(find.text(l10n.posReprintKitchenFetchFailed), findsOneWidget);
  });

  testWidgets('B7. no kitchen printer => the configured-printer message, '
      'never a silent no-op', (tester) async {
    final (bridge, kitchen, _) = await _pump(tester);
    kitchen.outcome = PosKitchenPrintOutcome.noPrinterConfigured;
    await _tapKitchenReprint(tester);
    expect(kitchen.orders, hasLength(1));
    expect(bridge.documents, isEmpty);
    expect(find.text(l10n.posKitchenPrinterNotConfiguredSnack), findsOneWidget);
  });

  testWidgets('B1. a DEVICE-OWNED order keeps its local snapshot path — the '
      'detail is never fetched', (tester) async {
    final local = SubmittedOrderView(
      orderNumber: '#K10SK1',
      orderType: OrderType.takeaway,
      currencyCode: 'ILS',
      subtotalMinor: 9000,
      orderId: 'order-kiosk-1',
      lines: const [
        SubmittedLineView(
          name: 'Classic Burger',
          quantity: 2,
          lineTotalMinor: 9000,
          currencyCode: 'ILS',
          modifiers: ['240g'],
        ),
      ],
    );
    final (_, kitchen, repo) = await _pump(
      tester,
      row: PosRecentOrder(
        order: local,
        snapshot: _snapshot(),
        submittedAt: _at,
      ),
    );
    await _tapKitchenReprint(tester);
    expect(repo.fetches, 0);
    expect(kitchen.orders.single, same(local));
  });

  group('authoritativeKitchenSource', () {
    test('demo mode never fetches; local or nothing', () async {
      final repo = _FakeDetailRepo(_detail());
      expect(
        await authoritativeKitchenSource(
          isDemoMode: true,
          orderId: 'order-kiosk-1',
          localView: null,
          repository: repo,
        ),
        isNull,
      );
      expect(repo.fetches, 0);
    });

    test('a local view wins without a fetch', () async {
      final repo = _FakeDetailRepo(_detail());
      final local = SubmittedOrderView(
        orderNumber: '#L',
        orderType: OrderType.takeaway,
        currencyCode: 'ILS',
        subtotalMinor: 0,
        lines: const [],
      );
      expect(
        await authoritativeKitchenSource(
          isDemoMode: false,
          orderId: 'order-kiosk-1',
          localView: local,
          repository: repo,
        ),
        same(local),
      );
      expect(repo.fetches, 0);
    });

    test('no server identity => nothing to fetch', () async {
      final repo = _FakeDetailRepo(_detail());
      expect(
        await authoritativeKitchenSource(
          isDemoMode: false,
          orderId: null,
          localView: null,
          repository: repo,
        ),
        isNull,
      );
      expect(repo.fetches, 0);
    });
  });

  group('B3/B4. the manual seam bypasses the AUTO guard and touches no '
      'dispatch ownership', () {
    test(
      'a durable `sent` auto claim does NOT suppress the manual print',
      () async {
        final claims = InMemoryRoundPrintClaimStore();
        await claims.record('order-kiosk-1', PosRoundPrintClaimState.sent);
        await claims.record(
          posInitialKitchenPrintClaimKey('order-kiosk-1'),
          PosRoundPrintClaimState.sent,
        );
        final container = ProviderContainer(
          overrides: [
            posRoundPrintClaimStoreProvider.overrideWithValue(claims),
            posNativePrintingAvailableProvider.overrideWithValue(true),
          ],
        );
        addTearDown(container.dispose);
        final printer = _CountingPrinter(container);
        final view = submittedOrderViewFromDetail(_detail());
        final first = await printKitchenTicketAndSettleOwedClaims(
          container: container,
          order: view,
          labels: _labels(),
          printer: printer,
        );
        final second = await printKitchenTicketAndSettleOwedClaims(
          container: container,
          order: view,
          labels: _labels(),
          printer: printer,
        );
        expect(first, PosKitchenPrintOutcome.printed);
        expect(second, PosKitchenPrintOutcome.printed);
        expect(printer.prints, 2);
        // The auto guard's own records are untouched by a deliberate reprint of
        // a branch-discovered order (no outbox entry => nothing to settle).
        expect(claims.claimOf('order-kiosk-1'), PosRoundPrintClaimState.sent);
      },
    );
  });
}

KitchenTicketPrintLabels _labels() => KitchenTicketPrintLabels(
  ticketLabel: 'Ticket',
  previewTitle: 'Kitchen ticket',
  dineIn: 'Dine-in',
  takeaway: 'Takeaway',
  tableLabel: 'Table',
  customerLabel: 'Customer',
  customerPhoneLabel: 'Phone',
  stationLabel: 'Station',
  noteLabel: 'Note',
  kitchenTotal: (count, unit) => 'Kitchen total: $count $unit',
  additionLabel: 'Addition',
  roundLabel: (n) => 'Round $n',
);

/// Counts physical print attempts without any transport/printer resolution.
final class _CountingPrinter extends PosKitchenTicketPrinter {
  _CountingPrinter(super.container);
  int prints = 0;
  @override
  Future<PosKitchenPrintOutcome> printKitchenTicket({
    required KdsTicketView ticket,
    required KitchenTicketPrintLabels labels,
  }) async {
    prints++;
    return PosKitchenPrintOutcome.printed;
  }
}
