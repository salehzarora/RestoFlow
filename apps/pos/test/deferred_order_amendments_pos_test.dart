@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_feature_kitchen/kitchen_print.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart' show DemoMenuItem;
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/state/addition_controller.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_auto_print_prefs.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart'
    show posNativePrintingAvailableProvider;
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

/// DEFERRED-ORDER-AMENDMENTS-001 — POS coverage for takeaway amendments and the
/// kitchen ADDITION ticket.
///
///  A. eligibility: TAKEAWAY may now take additions (matching the widened
///     `app.add_order_items` gate), with every OTHER guard still holding and no
///     table required;
///  B. the exactly-once print identity is ROUND-SCOPED — the parent order id
///     alone is not an identity, because the initial ticket already claimed it;
///  C. the real guarded path: an addition prints even though the parent order
///     already printed once (the defect this closes), and each round prints once;
///  D. a print failure leaves the amendment applied and allows a PRINT-only
///     retry — it never resends `order.items_add`;
///  E. the ticket itself: the frozen DELTA only, the parent's preserved
///     identity/type/table, the "Addition · Round N" marker, and no money;
///  F. the applied result carries the print payload built from the FROZEN cart
///     lines + the ONE order-time prep snapshot, and is fail-closed without a
///     round identity.

// ---------------------------------------------------------------------------
// A. eligibility fixtures (the same shapes the PSC-001C suite uses)
// ---------------------------------------------------------------------------

PosRecentOrder _order({
  String status = 'preparing',
  String orderType = 'dine_in',
  PosSettlement settlement = PosSettlement.unpaid,
  String? tableLabel = 'T1',
}) => PosRecentOrder.discovered(
  PosOrderSnapshot(
    orderId: 'o-1',
    orderCode: '#O00001',
    revision: 2,
    status: status,
    settlement: settlement,
    subtotalMinor: 2500,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: 2500,
    createdAt: DateTime.utc(2026, 8, 4, 12),
    updatedAt: DateTime.utc(2026, 8, 4, 12),
    syncAt: DateTime.utc(2026, 8, 4, 12),
    orderType: orderType,
    tableLabel: tableLabel,
    currencyCode: 'ILS',
  ),
);

// ---------------------------------------------------------------------------
// B/C/D. print harness
// ---------------------------------------------------------------------------

class _FakePrintTransport implements pp.PrintTransport {
  _FakePrintTransport(this._result);
  final pp.PrintResult _result;
  final List<Uint8List> sent = [];

  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    sent.add(bytes);
    return _result;
  }

  @override
  Future<void> dispose() async {}
}

class _StubAutoKitchen extends PosAutoPrintKitchenTicketController {
  _StubAutoKitchen(this._value);
  final bool? _value;
  @override
  Future<bool?> build() async => _value;
}

ProviderContainer _printContainer() {
  final c = ProviderContainer(
    overrides: [
      posNativePrintingAvailableProvider.overrideWithValue(true),
      posAutoPrintKitchenTicketProvider.overrideWith(
        () => _StubAutoKitchen(true),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

PosKitchenTicketPrinter _printerTo(
  ProviderContainer c,
  pp.PrintTransport transport,
) => PosKitchenTicketPrinter(
  c,
  targetOverride: ResolvedKitchenPrinter(
    destinationKey: 'kitchen',
    transportFactory: () => transport,
  ),
);

KitchenTicketPrintLabels _labels() => KitchenTicketPrintLabels(
  ticketLabel: 'Ticket',
  previewTitle: 'Kitchen ticket preview',
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

/// The DELTA the cashier added — deliberately NOT the parent order's items.
const _deltaLines = [
  CartLineView(
    lineId: 'l-delta',
    menuItemId: 'm-baklava',
    name: 'Baklava',
    quantity: 2,
    unitPriceMinor: 1200,
    lineTotalMinor: 2400,
    currencyCode: 'ILS',
    note: 'extra syrup',
    modifiers: [
      SelectedModifier(
        optionId: 'o-nuts',
        groupName: 'Nuts',
        optionName: 'Pistachio',
        priceDeltaMinor: 200,
        quantity: 3,
      ),
    ],
  ),
];

KdsTicketView _additionTicket({
  OrderType orderType = OrderType.dineIn,
  String? tableLabel = 'T1',
  String roundId = 'r-9',
  int roundNumber = 2,
}) => kdsTicketViewFromCartLines(
  orderCode: '#O00001',
  orderType: orderType,
  lines: _deltaLines,
  tableLabel: tableLabel,
  roundId: roundId,
  roundNumber: roundNumber,
);

// ---------------------------------------------------------------------------
// F. addition-controller harness
// ---------------------------------------------------------------------------

class _FakeSyncTransport implements SyncRpcTransport {
  _FakeSyncTransport(this._responses);
  final List<Object? Function(Map<String, dynamic>)> _responses;
  final List<Map<String, dynamic>> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function != 'sync_push') return {'ok': false};
    calls.add(params);
    final handler = _responses.length >= calls.length
        ? _responses[calls.length - 1]
        : _responses.last;
    return handler(params);
  }
}

PosOrderDetail _detail({
  String orderType = 'takeaway',
  String? tableLabel,
  List<PosOrderDetailRound> rounds = const [
    PosOrderDetailRound(roundId: 'r-new', roundNumber: 2, status: 'submitted'),
  ],
}) => PosOrderDetail(
  orderId: 'o-1',
  orderCode: '#O00001',
  orderType: orderType,
  status: 'preparing',
  revision: 2,
  currencyCode: 'ILS',
  subtotalMinor: 2500,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 2500,
  tableLabel: tableLabel,
  customerName: 'Dana',
  items: const [],
  rounds: rounds,
);

class _FakeDetailRepo implements OrderDetailRepository {
  _FakeDetailRepo(this._detail);
  final PosOrderDetail _detail;
  @override
  Future<PosOrderDetail> fetch(String orderId) => Future.value(_detail);
}

const _menuItem = DemoMenuItem(
  id: 'm-baklava',
  name: 'Baklava',
  priceMinor: 1200,
  categoryId: 'c1',
  categoryName: 'Sweets',
);

Object? _applied(
  Map<String, dynamic> params, {
  Object? roundId = 'r-new',
  Object? roundNumber = 2,
}) {
  final ops = params['p_operations'] as List;
  final localOp = (ops.single as Map)['local_operation_id'] as String;
  return {
    'ok': true,
    'results': [
      {
        'local_operation_id': localOp,
        'status': 'applied',
        'ok': true,
        'round_id': roundId,
        'round_number': roundNumber,
      },
    ],
  };
}

(ProviderContainer, _FakeSyncTransport) _additionHarness(
  List<Object? Function(Map<String, dynamic>)> responses, {
  PosOrderDetail? detail,
}) {
  final transport = _FakeSyncTransport(responses);
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport),
      posSyncSessionProvider.overrideWithValue(
        const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
      ),
      orderDetailRepositoryProvider.overrideWithValue(
        _FakeDetailRepo(detail ?? _detail()),
      ),
      orderSnapshotRepositoryProvider.overrideWithValue(
        DemoOrderSnapshotRepository(),
      ),
      posSyncPollIntervalProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  return (container, transport);
}

List<String> _texts(PrintDocument doc) => [
  for (final l in doc.lines) l.left ?? '',
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('A. takeaway is an eligible amendment target', () {
    test('A1 an ACTIVE unpaid TAKEAWAY order may take additions', () {
      expect(
        resolveOrderActions(_order(orderType: 'takeaway')).canAddItems,
        isTrue,
      );
      expect(
        resolveOrderActions(
          _order(orderType: 'takeaway', status: 'served'),
        ).canAddItems,
        isTrue,
      );
    });

    test('A2 NO table is required — a takeaway order has none', () {
      expect(
        resolveOrderActions(
          _order(orderType: 'takeaway', tableLabel: null),
        ).canAddItems,
        isTrue,
      );
    });

    test('A3 dine-in is unchanged (widening broke nothing)', () {
      expect(resolveOrderActions(_order()).canAddItems, isTrue);
    });

    test('A4 a TERMINAL takeaway order still refuses additions', () {
      for (final s in ['completed', 'voided', 'cancelled']) {
        expect(
          resolveOrderActions(
            _order(orderType: 'takeaway', status: s),
          ).canAddItems,
          isFalse,
          reason: 'terminal: $s',
        );
      }
    });

    test(
      'A5 a CHARGED takeaway order is still frozen (the payment freeze)',
      () {
        expect(
          resolveOrderActions(
            _order(orderType: 'takeaway', settlement: PosSettlement.paid),
          ).canAddItems,
          isFalse,
        );
      },
    );

    test('A6 in-flight local work still withholds the action', () {
      expect(
        resolveOrderActions(
          _order(orderType: 'takeaway'),
          pending: PosPendingKind.itemsAdd,
        ).canAddItems,
        isFalse,
      );
    });
  });

  group('B. the exactly-once print identity is ROUND-scoped', () {
    test('B1 an addition key is NEVER the bare parent order id', () {
      final key = posAdditionKitchenPrintGuardKey(
        orderId: 'o-1',
        roundId: 'r-9',
      );
      expect(key, isNot('o-1'));
      expect(key, contains('o-1'));
      expect(key, contains('r-9'));
    });

    test('B2 different rounds of the SAME order get different keys', () {
      expect(
        posAdditionKitchenPrintGuardKey(orderId: 'o-1', roundId: 'r-2'),
        isNot(posAdditionKitchenPrintGuardKey(orderId: 'o-1', roundId: 'r-3')),
      );
    });

    test('B3 the SAME round of different orders gets different keys', () {
      expect(
        posAdditionKitchenPrintGuardKey(orderId: 'o-1', roundId: 'r-2'),
        isNot(posAdditionKitchenPrintGuardKey(orderId: 'o-2', roundId: 'r-2')),
      );
    });

    test(
      'B4 the key is stable for the same order+round (a retry joins it)',
      () {
        expect(
          posAdditionKitchenPrintGuardKey(orderId: 'o-1', roundId: 'r-2'),
          posAdditionKitchenPrintGuardKey(orderId: 'o-1', roundId: 'r-2'),
        );
      },
    );
  });

  group('C. the guarded print path', () {
    test('C1 an ADDITION prints even though the parent order already printed '
        '(the parent-keyed guard used to swallow it)', () async {
      final c = _printContainer();
      final transport = _FakePrintTransport(const pp.PrintResult.success());

      // The parent order's INITIAL ticket, guarded on the order id.
      final initial = await runAutoKitchenTicketPrintOnSubmit(
        container: c,
        orderId: 'o-1',
        ticket: kdsTicketViewFromCartLines(
          orderCode: '#O00001',
          orderType: OrderType.takeaway,
          lines: _deltaLines,
        ),
        labels: _labels(),
        printer: _printerTo(c, transport),
      );
      expect(initial, PosKitchenPrintOutcome.printed);
      expect(transport.sent, hasLength(1));

      // The addition for the SAME order, guarded on order+round.
      final addition = await runAutoKitchenTicketPrintOnSubmit(
        container: c,
        orderId: 'o-1',
        guardKey: posAdditionKitchenPrintGuardKey(
          orderId: 'o-1',
          roundId: 'r-9',
        ),
        ticket: _additionTicket(
          orderType: OrderType.takeaway,
          tableLabel: null,
        ),
        labels: _labels(),
        printer: _printerTo(c, transport),
      );
      expect(addition, PosKitchenPrintOutcome.printed);
      expect(
        transport.sent,
        hasLength(2),
        reason: 'the added food reached the kitchen on its own ticket',
      );
    });

    test('C2 the SAME round never prints twice (a re-tap/rebuild joins the one '
        'confirmed send)', () async {
      final c = _printContainer();
      final transport = _FakePrintTransport(const pp.PrintResult.success());
      final key = posAdditionKitchenPrintGuardKey(
        orderId: 'o-1',
        roundId: 'r-9',
      );
      for (var i = 0; i < 3; i++) {
        expect(
          await runAutoKitchenTicketPrintOnSubmit(
            container: c,
            orderId: 'o-1',
            guardKey: key,
            ticket: _additionTicket(),
            labels: _labels(),
            printer: _printerTo(c, transport),
          ),
          PosKitchenPrintOutcome.printed,
        );
      }
      expect(transport.sent, hasLength(1));
    });

    test('C3 two DIFFERENT rounds each print exactly once', () async {
      final c = _printContainer();
      final transport = _FakePrintTransport(const pp.PrintResult.success());
      for (final round in ['r-2', 'r-3']) {
        for (var i = 0; i < 2; i++) {
          await runAutoKitchenTicketPrintOnSubmit(
            container: c,
            orderId: 'o-1',
            guardKey: posAdditionKitchenPrintGuardKey(
              orderId: 'o-1',
              roundId: round,
            ),
            ticket: _additionTicket(roundId: round),
            labels: _labels(),
            printer: _printerTo(c, transport),
          );
        }
      }
      expect(transport.sent, hasLength(2));
    });
  });

  group('D. a print failure is PRINT-only and retryable', () {
    test('D1 a failed round print releases the round, and the retry sends '
        '(no order.items_add is involved at all)', () async {
      final c = _printContainer();
      final failing = _FakePrintTransport(
        const pp.PrintResult.failure(pp.PrinterErrorCategory.unreachable),
      );
      final key = posAdditionKitchenPrintGuardKey(
        orderId: 'o-1',
        roundId: 'r-9',
      );
      expect(
        await runAutoKitchenTicketPrintOnSubmit(
          container: c,
          orderId: 'o-1',
          guardKey: key,
          ticket: _additionTicket(),
          labels: _labels(),
          printer: _printerTo(c, failing),
        ),
        PosKitchenPrintOutcome.failed,
      );
      expect(failing.sent, hasLength(1));

      final ok = _FakePrintTransport(const pp.PrintResult.success());
      expect(
        await runAutoKitchenTicketPrintOnSubmit(
          container: c,
          orderId: 'o-1',
          guardKey: key,
          ticket: _additionTicket(),
          labels: _labels(),
          printer: _printerTo(c, ok),
        ),
        PosKitchenPrintOutcome.printed,
        reason: 'the failure released the round for a legitimate print retry',
      );
      expect(ok.sent, hasLength(1));
    });
  });

  group('E. the printed addition ticket', () {
    test('E1 carries the server round identity, so the shared builder marks it '
        'as an addition', () {
      final ticket = _additionTicket(roundNumber: 3);
      expect(ticket.roundId, 'r-9');
      expect(ticket.roundNumber, 3);
      expect(
        KitchenTicketDocumentKind.forTicket(ticket),
        KitchenTicketDocumentKind.orderAddition,
      );
      final doc = buildKdsTicketPrintDocument(
        ticket: ticket,
        labels: _labels(),
      );
      expect(_texts(doc), contains('Addition · Round 3'));
      expect(_texts(doc), contains('#O00001'));
    });

    test('E2 prints the DELTA only — never the parent order it joins', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _additionTicket(),
        labels: _labels(),
      );
      final texts = _texts(doc);
      expect(texts.any((t) => t.startsWith('2 × Baklava')), isTrue);
      expect(texts, contains('+ Pistachio ×3'));
      expect(texts.any((t) => t.contains('extra syrup')), isTrue);
      // The parent's own items were never added to this view.
      expect(_additionTicket().items, hasLength(1));
    });

    test('E3 a TAKEAWAY addition prints no table; a dine-in one keeps it', () {
      final takeaway = buildKdsTicketPrintDocument(
        ticket: _additionTicket(
          orderType: OrderType.takeaway,
          tableLabel: null,
        ),
        labels: _labels(),
      );
      expect(_texts(takeaway), contains('Takeaway'));
      expect(_texts(takeaway).where((t) => t.startsWith('Table')), isEmpty);

      final dineIn = buildKdsTicketPrintDocument(
        ticket: _additionTicket(),
        labels: _labels(),
      );
      expect(_texts(dineIn), contains('Table T1'));
      expect(_texts(dineIn), contains('Dine-in'));
    });

    test('E4 an INITIAL POS ticket still carries no round identity and no '
        'marker', () {
      final initial = kdsTicketViewFromCartLines(
        orderCode: '#O00001',
        orderType: OrderType.dineIn,
        lines: _deltaLines,
      );
      expect(initial.roundId, isNull);
      expect(initial.roundNumber, isNull);
      final doc = buildKdsTicketPrintDocument(
        ticket: initial,
        labels: _labels(),
      );
      expect(_texts(doc).where((t) => t.contains('Addition')), isEmpty);
    });

    test('E5 the addition ticket is money-free (T-003)', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _additionTicket(),
        labels: _labels(),
      );
      final blob = _texts(doc).join('\n').toLowerCase();
      for (final token in ['1200', '2400', '₪', r'$', 'subtotal', 'tender']) {
        expect(blob, isNot(contains(token)), reason: 'money token: $token');
      }
    });
  });

  group('F. the applied result carries the addition print payload', () {
    test('F1 an applied TAKEAWAY addition returns the frozen delta, the '
        'preserved type, and the server round identity', () async {
      final (container, transport) = _additionHarness([_applied]);
      expect(
        await container
            .read(additionControllerProvider.notifier)
            .enterForOrder('o-1'),
        AdditionEntryResult.entered,
      );
      expect(
        container.read(cartControllerProvider.notifier).addItem(_menuItem),
        CartMutationResult.applied,
      );
      final result = await container
          .read(additionControllerProvider.notifier)
          .submit();

      expect(result.applied, isTrue);
      expect(transport.calls, hasLength(1));
      final payload = result.printPayload;
      expect(payload, isNotNull);
      expect(payload!.orderId, 'o-1');
      expect(payload.orderCode, '#O00001');
      expect(payload.orderTypeWire, 'takeaway');
      expect(payload.orderType, OrderType.takeaway);
      expect(payload.roundId, 'r-new');
      expect(payload.roundNumber, 2);
      expect(payload.tableLabel, isNull, reason: 'takeaway has no table');
      // The DELTA the cashier added, frozen — and it survived the
      // reconciliation that cleared the cart.
      expect(payload.lines, hasLength(1));
      expect(payload.lines.single.menuItemId, 'm-baklava');
      expect(container.read(cartControllerProvider).lines, isEmpty);
    });

    test('F2 a dine-in addition preserves the parent table', () async {
      final (container, _) = _additionHarness([
        _applied,
      ], detail: _detail(orderType: 'dine_in', tableLabel: 'T5'));
      await container
          .read(additionControllerProvider.notifier)
          .enterForOrder('o-1');
      container.read(cartControllerProvider.notifier).addItem(_menuItem);
      final result = await container
          .read(additionControllerProvider.notifier)
          .submit();
      expect(result.printPayload!.orderType, OrderType.dineIn);
      expect(result.printPayload!.tableLabel, 'T5');
    });

    test('F3 FAIL-CLOSED: an applied result WITHOUT a round identity yields no '
        'print payload — the addition stays applied, nothing is printed on a '
        'guess', () async {
      for (final broken in [
        (roundId: null, roundNumber: 2),
        (roundId: 'r-new', roundNumber: null),
      ]) {
        final (container, _) = _additionHarness([
          (p) => _applied(
            p,
            roundId: broken.roundId,
            roundNumber: broken.roundNumber,
          ),
        ]);
        await container
            .read(additionControllerProvider.notifier)
            .enterForOrder('o-1');
        container.read(cartControllerProvider.notifier).addItem(_menuItem);
        final result = await container
            .read(additionControllerProvider.notifier)
            .submit();
        expect(result.applied, isTrue, reason: 'the server DID apply it');
        expect(result.printPayload, isNull, reason: '$broken');
      }
    });

    test('F4 a REJECTED addition yields no print payload at all', () async {
      final (container, _) = _additionHarness([
        (p) {
          final ops = p['p_operations'] as List;
          final localOp = (ops.single as Map)['local_operation_id'] as String;
          return {
            'ok': true,
            'results': [
              {
                'local_operation_id': localOp,
                'status': 'rejected',
                'ok': false,
                'error': 'order_already_settled',
              },
            ],
          };
        },
      ]);
      await container
          .read(additionControllerProvider.notifier)
          .enterForOrder('o-1');
      container.read(cartControllerProvider.notifier).addItem(_menuItem);
      final result = await container
          .read(additionControllerProvider.notifier)
          .submit();
      expect(result.applied, isFalse);
      expect(result.printPayload, isNull);
    });

    test(
      'F5 the payload order type is FAIL-CLOSED on an unknown wire value',
      () {
        const payload = AdditionPrintPayload(
          orderId: 'o-1',
          orderCode: '#O00001',
          orderTypeWire: 'delivery',
          roundId: 'r-1',
          roundNumber: 2,
          lines: [],
          prepByItemId: {},
        );
        expect(
          payload.orderType,
          isNull,
          reason: 'never coerced to dine-in (which would print a wrong type)',
        );
      },
    );
  });
}
