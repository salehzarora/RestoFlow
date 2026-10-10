import 'dart:async' show Completer;
import 'dart:convert' show jsonEncode;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport, SyncSession;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/durable_outbox_store.dart';
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/round_print_claim_store.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/print/print_bridge.dart'
    show PosPrintBridge, posPrintBridgeProvider;
import 'package:restoflow_pos/src/print/print_document.dart' show PrintDocument;
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/order_action_row.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

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
  _FakeDetailRepo(this._detail, {this.fail = false, this.pendingDetail});
  final PosOrderDetail _detail;
  final bool fail;
  final Future<PosOrderDetail>? pendingDetail;
  int fetches = 0;
  @override
  Future<PosOrderDetail> fetch(String orderId) async {
    fetches++;
    if (fail) {
      throw const PosOrderDetailException(PosOrderDetailFailure.transport);
    }
    return pendingDetail ?? _detail;
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
  _RecordingKitchen({this.useRealSeam = false});
  final bool useRealSeam;
  final List<SubmittedOrderView> orders = [];
  PosKitchenPrintOutcome outcome = PosKitchenPrintOutcome.printed;
  PosKitchenReprint get seam =>
      ({required container, required order, required labels}) async {
        orders.add(order);
        if (useRealSeam) {
          return printKitchenTicketAndSettleOwedClaims(
            container: container,
            order: order,
            labels: labels,
            printer: _CountingPrinter(container)..outcome = outcome,
          );
        }
        return outcome;
      };
}

Future<(_RecordingBridge, _RecordingKitchen, _FakeDetailRepo)> _pump(
  WidgetTester tester, {
  bool failFetch = false,
  PosRecentOrder? row,
  PosOrderDetail? detail,
  bool demo = false,
  bool allowLocalReprint = false,
  OutboxRepository? outbox,
  PosRoundPrintClaimStore? claims,
  Future<PosOrderDetail>? pendingDetail,
  ValueNotifier<bool>? rowVisible,
}) async {
  tester.view.physicalSize = const Size(1024, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final bridge = _RecordingBridge();
  final kitchen = _RecordingKitchen(useRealSeam: outbox != null);
  final repo = _FakeDetailRepo(
    detail ?? _detail(),
    fail: failFetch,
    pendingDetail: pendingDetail,
  );
  final container = ProviderContainer(
    overrides: [
      // REAL mode: a branch-discovered order may be fetched from the server.
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: demo),
      ),
      posNativePrintingAvailableProvider.overrideWithValue(false),
      posPrintBridgeProvider.overrideWithValue(bridge),
      posKitchenReprintProvider.overrideWithValue(kitchen.seam),
      orderDetailRepositoryProvider.overrideWithValue(repo),
      if (outbox != null) outboxRepositoryProvider.overrideWithValue(outbox),
      if (claims != null)
        posRoundPrintClaimStoreProvider.overrideWithValue(claims),
    ],
  );
  addTearDown(container.dispose);
  final order = row ?? PosRecentOrder.discovered(_snapshot());
  if (outbox != null) container.read(outboxControllerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Builder(
          builder: (ctx) {
            final actionRow = OrderActionRow(
              order: order,
              l10n: AppLocalizations.of(ctx),
              actions: resolveOrderActions(
                order,
              ).copyWith(canOpenReceipt: allowLocalReprint ? true : null),
            );
            return Scaffold(
              body: rowVisible == null
                  ? actionRow
                  : ValueListenableBuilder<bool>(
                      valueListenable: rowVisible,
                      builder: (_, visible, child) =>
                          visible ? child! : const SizedBox(),
                      child: actionRow,
                    ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (outbox != null) {
    expect(
      container
          .read(outboxControllerProvider.notifier)
          .entryById(order.order!.outboxEntryId!),
      isNotNull,
      reason: 'the real SharedPreferences outbox recovered the original submit',
    );
  }
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

  testWidgets('B1. same-till manual reprint merges rounds 1, 2 and 3 into '
      'one complete kitchen ticket', (tester) async {
    final local = _localView();
    final (bridge, kitchen, repo) = await _pump(
      tester,
      detail: _multiRoundDetail(),
      row: PosRecentOrder(
        order: local,
        snapshot: _snapshot(),
        submittedAt: _at,
      ),
    );
    await _tapKitchenReprint(tester);
    expect(repo.fetches, 1);
    expect(kitchen.orders, hasLength(1));
    _expectAllRounds(kitchen.orders.single);
    expect(
      local.lines,
      hasLength(1),
      reason: 'the local snapshot stays intact',
    );
    expect(bridge.documents, isEmpty);
    expect(find.text(l10n.posKitchenTicketPrintedSnack), findsOneWidget);
  });

  testWidgets('same-till unavailable detail still prints the local snapshot', (
    tester,
  ) async {
    final local = _localView();
    final (bridge, kitchen, repo) = await _pump(
      tester,
      failFetch: true,
      row: PosRecentOrder(order: local, snapshot: _snapshot()),
    );
    await _tapKitchenReprint(tester);
    expect(repo.fetches, 1);
    expect(kitchen.orders, hasLength(1));
    expect(kitchen.orders.single, same(local));
    expect(kitchen.orders.single.lines.single.name, 'Classic Burger');
    expect(bridge.documents, isEmpty);
    expect(find.text(l10n.posKitchenTicketPrintedSnack), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing the order row during a slow fetch still completes one '
      'merged manual print', (tester) async {
    final pending = Completer<PosOrderDetail>();
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    final (_, kitchen, repo) = await _pump(
      tester,
      row: PosRecentOrder(order: _localView(), snapshot: _snapshot()),
      pendingDetail: pending.future,
      rowVisible: visible,
    );
    await _tapKitchenReprint(tester);
    expect(repo.fetches, 1);
    expect(kitchen.orders, isEmpty);
    visible.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(OrderActionRow), findsNothing);
    pending.complete(_multiRoundDetail());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(kitchen.orders, hasLength(1));
    _expectAllRounds(kitchen.orders.single);
  });

  testWidgets('branch-discovered manual reprint still includes all rounds', (
    tester,
  ) async {
    final (bridge, kitchen, repo) = await _pump(
      tester,
      detail: _multiRoundDetail(),
    );
    await _tapKitchenReprint(tester);
    expect(repo.fetches, 1);
    expect(kitchen.orders, hasLength(1));
    _expectAllRounds(kitchen.orders.single);
    expect(bridge.documents, isEmpty);
  });

  testWidgets('same-till merged manual reprint remains repeatable', (
    tester,
  ) async {
    final (_, kitchen, repo) = await _pump(
      tester,
      detail: _multiRoundDetail(),
      row: PosRecentOrder(order: _localView(), snapshot: _snapshot()),
    );
    await _tapKitchenReprint(tester);
    await _tapKitchenReprint(tester);
    expect(repo.fetches, 2);
    expect(kitchen.orders, hasLength(2));
    for (final printed in kitchen.orders) {
      _expectAllRounds(printed);
    }
  });

  testWidgets('unedited demo reprint keeps its local lines without fetching', (
    tester,
  ) async {
    final local = _localView();
    final (_, kitchen, repo) = await _pump(
      tester,
      demo: true,
      detail: _multiRoundDetail(),
      row: PosRecentOrder(order: local, snapshot: _snapshot()),
    );
    await _tapKitchenReprint(tester);
    expect(repo.fetches, 0);
    expect(kitchen.orders.single, same(local));
  });

  for (final id in <String?>[null, '', '   ']) {
    testWidgets('manual source without usable server identity ($id) keeps '
        'the local snapshot', (tester) async {
      final local = _localView(orderId: id);
      final (_, kitchen, repo) = await _pump(
        tester,
        row: PosRecentOrder(order: local),
        // Exercise source selection independently of action eligibility:
        // the normal policy can hide the chooser for a missing identity.
        allowLocalReprint: true,
      );
      await _tapKitchenReprint(tester);
      expect(repo.fetches, 0);
      expect(kitchen.orders.single, same(local));
    });
  }

  for (final hasLocal in [false, true]) {
    testWidgets('empty authoritative detail prints nothing (local=$hasLocal)', (
      tester,
    ) async {
      final (bridge, kitchen, repo) = await _pump(
        tester,
        detail: _multiRoundDetail(empty: true),
        row: hasLocal
            ? PosRecentOrder(order: _localView(), snapshot: _snapshot())
            : null,
      );
      await _tapKitchenReprint(tester);
      expect(repo.fetches, 1);
      expect(kitchen.orders, isEmpty, reason: 'no empty or stale document');
      expect(bridge.documents, isEmpty);
      expect(find.text(l10n.posReprintKitchenUnavailable), findsOneWidget);
    });
  }

  testWidgets('same-till detail without prep snapshots retains the existing '
      'counts-unavailable notice', (tester) async {
    final (_, kitchen, _) = await _pump(
      tester,
      row: PosRecentOrder(order: _localView(), snapshot: _snapshot()),
    );
    await _tapKitchenReprint(tester);
    expect(kitchen.orders, hasLength(1));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text(l10n.posReprintKitchenCountsUnavailable), findsOneWidget);
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

  for (final outcome in [
    PosKitchenPrintOutcome.printed,
    PosKitchenPrintOutcome.failed,
  ]) {
    testWidgets('authoritative manual print preserves initial-only durable '
        'claim bookkeeping on $outcome', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final entry = OutboxEntry(
        id: 'outbox-1',
        deviceId: 'device-1',
        localOperationId: 'op-1',
        operationType: 'order.submit',
        targetEntity: 'order',
        targetId: 'order-kiosk-1',
        payloadJson: jsonEncode({'dispatch_mode': 'direct_print'}),
        summary: const OrderSummary(
          orderNumber: '#K10SK1',
          orderType: OrderType.takeaway,
          tableLabel: null,
          itemCount: 2,
          subtotalMinor: 9000,
          currencyCode: 'ILS',
        ),
        syncState: OutboxSyncState.applied,
        clientCreatedAt: _at,
      );
      await SharedPrefsOutboxStore(prefs).persist('device-1', [entry]);
      final claims = SharedPrefsRoundPrintClaimStore(prefs)
        ..scopeKey = 'device-1';
      final localKey = posLocalKitchenDispatchClaimKey(
        deviceId: entry.deviceId,
        localOperationId: entry.localOperationId,
      );
      final initialKey = posInitialKitchenPrintClaimKey(entry.targetId);
      final roundKey = posAdditionKitchenPrintGuardKey(
        orderId: entry.targetId,
        roundId: 'round-2',
      );
      await claims.record(localKey, PosRoundPrintClaimState.failed);
      await claims.record(roundKey, PosRoundPrintClaimState.failed);
      final (_, kitchen, repo) = await _pump(
        tester,
        detail: _multiRoundDetail(),
        row: PosRecentOrder(
          order: _localView(outboxEntryId: entry.id),
          snapshot: _snapshot(),
        ),
        claims: claims,
        outbox: RealOutboxRepository(
          _NoSyncTransport(),
          const SyncSession(pinSessionId: 'pin-1', deviceId: 'device-1'),
          store: SharedPrefsOutboxStore(prefs),
        ),
      );
      kitchen.outcome = outcome;
      await _tapKitchenReprint(tester);
      expect(repo.fetches, 1);
      expect(kitchen.orders, hasLength(1));
      _expectAllRounds(kitchen.orders.single);
      final reloadedClaims = SharedPrefsRoundPrintClaimStore(prefs)
        ..scopeKey = 'device-1';
      final succeeded = outcome == PosKitchenPrintOutcome.printed;
      expect(
        reloadedClaims.claimOf(localKey),
        succeeded
            ? PosRoundPrintClaimState.sent
            : PosRoundPrintClaimState.failed,
      );
      expect(
        reloadedClaims.claimOf(initialKey),
        succeeded ? PosRoundPrintClaimState.sent : null,
      );
      expect(reloadedClaims.claimOf(roundKey), PosRoundPrintClaimState.failed);
      final persisted = await SharedPrefsOutboxStore(prefs).load('device-1');
      expect(persisted.single.toJson(), entry.toJson());
    });
  }

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

SubmittedOrderView _localView({
  String? orderId = 'order-kiosk-1',
  String? outboxEntryId,
}) => SubmittedOrderView(
  orderNumber: '#K10SK1',
  orderType: OrderType.takeaway,
  currencyCode: 'ILS',
  subtotalMinor: 9000,
  orderId: orderId,
  outboxEntryId: outboxEntryId,
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

PosOrderDetail _multiRoundDetail({bool empty = false}) => PosOrderDetail(
  orderId: 'order-kiosk-1',
  orderCode: '#K10SK1',
  orderType: 'takeaway',
  status: 'served',
  revision: 5,
  currencyCode: 'ILS',
  subtotalMinor: empty ? 0 : 14000,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: empty ? 0 : 14000,
  items: empty
      ? const []
      : [
          ..._detail().items,
          const PosOrderDetailItem(
            name: 'Fries',
            quantity: 1,
            unitPriceMinor: 2000,
            lineDiscountMinor: 0,
            lineTotalMinor: 2000,
            modifiers: [],
            notes: 'no salt',
            serviceRoundId: 'round-2',
            roundNumber: 2,
            linePosition: 2,
          ),
          const PosOrderDetailItem(
            name: 'Cola',
            quantity: 3,
            unitPriceMinor: 1000,
            lineDiscountMinor: 0,
            lineTotalMinor: 3000,
            modifiers: [],
            serviceRoundId: 'round-3',
            roundNumber: 3,
            linePosition: 3,
          ),
        ],
  rounds: const [
    PosOrderDetailRound(roundId: 'round-2', roundNumber: 2, status: 'served'),
    PosOrderDetailRound(roundId: 'round-3', roundNumber: 3, status: 'served'),
  ],
);

void _expectAllRounds(SubmittedOrderView printed) {
  expect(printed.orderNumber, '#K10SK1');
  expect(printed.lines, hasLength(3));
  expect(printed.lines.map((line) => line.name), [
    'Classic Burger',
    'Fries',
    'Cola',
  ]);
  expect(printed.lines.map((line) => line.quantity), [2, 1, 3]);
  expect(printed.lines.first.modifiers, ['240g']);
  expect(printed.lines.map((line) => line.note), [
    'well done',
    'no salt',
    null,
  ]);
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
  PosKitchenPrintOutcome outcome = PosKitchenPrintOutcome.printed;
  @override
  Future<PosKitchenPrintOutcome> printKitchenTicket({
    required KdsTicketView ticket,
    required KitchenTicketPrintLabels labels,
  }) async {
    prints++;
    return outcome;
  }
}

class _NoSyncTransport implements SyncRpcTransport {
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async =>
      fail('manual printing must not sync an order');
}
