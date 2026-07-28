@TestOn('vm')
library;

import 'dart:async' show Completer;
import 'dart:convert' show jsonEncode, utf8;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/print/native_print_bridges.dart'
    show NativeTransportPrintBridge, posPrinterDestinationSendGateProvider;
import 'package:restoflow_pos/src/print/network_printer_tester.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/print/print_document.dart' as app;
import 'package:restoflow_pos/src/state/cart_controller.dart'
    show CartLineView, SelectedModifier;
import 'package:restoflow_pos/src/state/pos_auto_print_prefs.dart';
import 'package:restoflow_pos/src/widgets/network_printer_section.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

/// KITCHEN-PRINT-DUAL-001 — REAL-PATH coverage (F4 test-print gate, F5 real
/// render/routing). These drive the real renderer and real send gate and
/// CAPTURE the routed endpoint + bytes — never a "helper was called" mock.

const _money = [
  'total',
  'subtotal',
  'tax',
  'discount',
  'payment',
  'tender',
  'price',
  'amount',
  '4500',
  '9000',
  '₪',
];

/// Records the bytes + the resolved destination key it was routed to.
class _CapturingTransport implements pp.PrintTransport {
  final List<Uint8List> sent = [];
  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    sent.add(bytes);
    return const pp.PrintResult.success();
  }

  @override
  Future<void> dispose() async {}
}

/// Records both the bytes and the send START/END order (optionally blocking on
/// [block]) — to prove ACTUAL FIFO serialization through the shared gate.
class _RecordingTransport implements pp.PrintTransport {
  _RecordingTransport(this.label, this.order, {this.block});
  final String label;
  final List<String> order;
  final Completer<void>? block;
  final List<Uint8List> sent = [];
  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    sent.add(bytes);
    order.add('$label-start');
    if (block != null) await block!.future;
    order.add('$label-end');
    return const pp.PrintResult.success();
  }

  @override
  Future<void> dispose() async {}
}

/// A REAL money-bearing receipt document (the customer_receipt path renders this
/// through NativeTransportPrintBridge → receiptToEscPosDocument).
app.PrintDocument _receiptDoc() => app.PrintDocument(
  title: 'Receipt',
  lines: [
    app.PrintLine.title('RESTOFLOW'),
    app.PrintLine.item('2 x Shawarma', '90.00'),
    app.PrintLine.rule(),
    app.PrintLine.kv('Total', '₪90.00', emphasised: true),
    app.PrintLine.kv('Paid', '₪90.00'),
  ],
);

/// A container whose kitchen slot resolves to [host]:[port], routing its send
/// through [gate] and capturing via [transport].
ProviderContainer _kitchenContainer(
  String host,
  int port,
  pp.PrinterDestinationSendGate gate,
  pp.PrintTransport transport,
) {
  SharedPreferences.setMockInitialValues({
    'restoflow.printer.selected.pos.kitchen_ticket.local': 'network',
    'restoflow.printer.network.pos.kitchen_ticket.local': jsonEncode({
      'host': host,
      'port': port,
    }),
  });
  final c = ProviderContainer(
    overrides: [
      posNativePrintingAvailableProvider.overrideWithValue(true),
      posPrinterDestinationSendGateProvider.overrideWithValue(gate),
      kitchenPrintTransportOverrideProvider.overrideWithValue((_) => transport),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> _sendKitchen(ProviderContainer c) => printKitchenTicketForOrder(
  container: c,
  ticket: kdsTicketViewFromCartLines(
    orderCode: '#000042',
    orderType: OrderType.dineIn,
    lines: [_line()],
  ),
  labels: _kdsLabels(),
);

/// A plain en labels fixture (this suite exercises routing/bytes, not chrome).
KitchenTicketPrintLabels _kdsLabels() => KitchenTicketPrintLabels(
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
);

class _StubAutoKitchen extends PosAutoPrintKitchenTicketController {
  _StubAutoKitchen(this._v);
  final bool _v;
  @override
  Future<bool?> build() async => _v;
}

/// A network tester that blocks inside the gate until released, recording when
/// it is actually invoked — to prove ACTUAL ordering, not just equal keys.
class _BlockingTester implements NetworkPrinterTester {
  final Completer<void> _release = Completer<void>();
  int calls = 0;
  void release() => _release.complete();
  @override
  Future<pp.PrintResult> testPrint(
    config, {
    String? deviceLabel,
    pp.PrintDocument? document,
  }) async {
    calls++;
    await _release.future;
    return const pp.PrintResult.success();
  }
}

void _mockKitchenNet(String host, int port) =>
    SharedPreferences.setMockInitialValues({
      'restoflow.printer.selected.pos.kitchen_ticket.local': 'network',
      'restoflow.printer.network.pos.kitchen_ticket.local': jsonEncode({
        'host': host,
        'port': port,
      }),
    });

CartLineView _line() => const CartLineView(
  lineId: 'l1',
  menuItemId: 'm1',
  name: 'Shawarma',
  quantity: 2,
  unitPriceMinor: 4500,
  lineTotalMinor: 9000,
  currencyCode: 'ILS',
  note: 'extra garlic',
  modifiers: [
    SelectedModifier(
      optionId: 'o1',
      groupName: 'Bread',
      optionName: 'Laffa',
      priceDeltaMinor: 300,
      quantity: 1,
    ),
  ],
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  group('F5 automatic path — real render routed to the KITCHEN endpoint', () {
    test(
      'one money-free kitchen send to the kitchen slot, purpose-correct',
      () async {
        _mockKitchenNet('10.0.0.9', 9100);
        final captured = _CapturingTransport();
        String? routedKey;
        final c = ProviderContainer(
          overrides: [
            posNativePrintingAvailableProvider.overrideWithValue(true),
            posAutoPrintKitchenTicketProvider.overrideWith(
              () => _StubAutoKitchen(true),
            ),
            kitchenPrintTransportOverrideProvider.overrideWithValue((target) {
              routedKey = target.destinationKey;
              return captured;
            }),
          ],
        );
        addTearDown(c.dispose);

        // The REAL projection CartPanel uses, from a REAL cart line (with prices).
        final ticket = kdsTicketViewFromCartLines(
          orderCode: '#000042',
          orderType: OrderType.dineIn,
          lines: [_line()],
          tableLabel: 'T1',
        );
        final outcome = await runAutoKitchenTicketPrintOnSubmit(
          container: c,
          orderId: 'ord-real-uuid',
          ticket: ticket,
          labels: _kdsLabels(),
        );

        expect(outcome, PosKitchenPrintOutcome.printed);
        expect(captured.sent, hasLength(1), reason: 'exactly one send');
        // Purpose = kitchen_ticket slot: the routed key is the KITCHEN endpoint.
        expect(
          routedKey,
          pp.PrinterDestinationSendGate.networkKey('10.0.0.9', 9100),
        );
        // The bytes are the REAL kitchen renderer output — item present, NO money.
        final text = utf8
            .decode(captured.sent.single, allowMalformed: true)
            .toLowerCase();
        expect(text.contains('shawarma'), isTrue);
        for (final t in _money) {
          expect(
            text.contains(t.toLowerCase()),
            isFalse,
            reason: 'no money "$t"',
          );
        }
      },
    );
  });

  group('F3 same physical printer — REAL receipt + REAL kitchen sends', () {
    test('the two real documents differ + use the correct renderers', () async {
      final gate = pp.PrinterDestinationSendGate();
      final key = pp.PrinterDestinationSendGate.networkKey('10.0.0.5', 9100);
      // REAL receipt render+send through the PRODUCTION NativeTransportPrintBridge
      // (receiptToEscPosDocument), captured.
      final receiptCapture = _CapturingTransport();
      await NativeTransportPrintBridge(
        transportFactory: () => receiptCapture,
        sendGate: gate,
        destinationKey: key,
      ).submit(_receiptDoc());
      final receiptBytes = receiptCapture.sent.single;
      // REAL kitchen render+send through the kitchen service (KitchenTicketRenderer)
      // to the SAME endpoint, captured.
      final kitchenCapture = _CapturingTransport();
      await _sendKitchen(
        _kitchenContainer('10.0.0.5', 9100, gate, kitchenCapture),
      );
      final kitchenBytes = kitchenCapture.sent.single;

      // Distinct documents.
      expect(receiptBytes, isNot(equals(kitchenBytes)));
      final receiptText = utf8
          .decode(receiptBytes, allowMalformed: true)
          .toLowerCase();
      final kitchenText = utf8
          .decode(kitchenBytes, allowMalformed: true)
          .toLowerCase();
      // Receipt uses the RECEIPT renderer → carries money.
      expect(receiptText.contains('total'), isTrue);
      expect(receiptText.contains('90.00'), isTrue);
      // Kitchen uses KitchenTicketRenderer → NEVER money.
      for (final t in _money) {
        expect(kitchenText.contains(t.toLowerCase()), isFalse);
      }
      expect(kitchenText.contains('shawarma'), isTrue);
    });

    test(
      'a receipt + a kitchen send to ONE endpoint serialize FIFO (real bridges)',
      () async {
        final gate = pp.PrinterDestinationSendGate();
        final key = pp.PrinterDestinationSendGate.networkKey('10.0.0.5', 9100);
        final order = <String>[];
        final receiptBlock = Completer<void>();
        // The receipt occupies the destination through the REAL bridge.
        final receiptFuture = NativeTransportPrintBridge(
          transportFactory: () =>
              _RecordingTransport('receipt', order, block: receiptBlock),
          sendGate: gate,
          destinationKey: key,
        ).submit(_receiptDoc());
        // The kitchen send targets the SAME endpoint through the SAME gate.
        final kitchenFuture = _sendKitchen(
          _kitchenContainer(
            '10.0.0.5',
            9100,
            gate,
            _RecordingTransport('kitchen', order),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        // The kitchen send is serialized BEHIND the receipt (FIFO through the key).
        expect(order, ['receipt-start']);
        receiptBlock.complete();
        await Future.wait([receiptFuture, kitchenFuture]);
        expect(order, [
          'receipt-start',
          'receipt-end',
          'kitchen-start',
          'kitchen-end',
        ]);
      },
    );
  });

  group('F3 different printers route independently (no crossover)', () {
    test(
      'the receipt reaches the customer endpoint, the kitchen the kitchen one',
      () async {
        final gate = pp.PrinterDestinationSendGate();
        final custKey = pp.PrinterDestinationSendGate.networkKey(
          '10.0.0.1',
          9100,
        );
        final kitKey = pp.PrinterDestinationSendGate.networkKey(
          '10.0.0.9',
          9100,
        );

        // REAL receipt → the CUSTOMER endpoint.
        final receiptCapture = _CapturingTransport();
        await NativeTransportPrintBridge(
          transportFactory: () => receiptCapture,
          sendGate: gate,
          destinationKey: custKey,
        ).submit(_receiptDoc());

        // REAL kitchen → the KITCHEN endpoint (resolved from the kitchen slot).
        _mockKitchenNet('10.0.0.9', 9100);
        String? kitchenRoutedKey;
        final c = ProviderContainer(
          overrides: [
            posNativePrintingAvailableProvider.overrideWithValue(true),
            posPrinterDestinationSendGateProvider.overrideWithValue(gate),
            kitchenPrintTransportOverrideProvider.overrideWithValue((target) {
              kitchenRoutedKey = target.destinationKey;
              return _CapturingTransport();
            }),
          ],
        );
        addTearDown(c.dispose);
        await _sendKitchen(c);

        // No crossover: each document reached ITS intended, distinct endpoint.
        expect(receiptCapture.sent, hasLength(1), reason: 'receipt delivered');
        expect(
          kitchenRoutedKey,
          kitKey,
          reason: 'kitchen reached the kitchen slot',
        );
        expect(
          kitchenRoutedKey,
          isNot(custKey),
          reason: 'no assignment crossover',
        );
        expect(custKey, isNot(kitKey));
      },
    );
  });

  group('F4 test-print serializes through the shared gate', () {
    testWidgets(
      'the Test action waits behind a busy destination (FIFO order)',
      (tester) async {
        SharedPreferences.setMockInitialValues(const {});
        tester.view.physicalSize = const Size(1000, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final gate = pp.PrinterDestinationSendGate();
        final blockingTester = _BlockingTester();
        // Occupy the SAME destination the Test will target.
        final key = pp.PrinterDestinationSendGate.networkKey('10.0.0.9', 9100);
        final held = Completer<void>();
        final occupied = gate.withDestination(key, () => held.future);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              posPrinterDestinationSendGateProvider.overrideWithValue(gate),
              networkPrinterTesterProvider.overrideWithValue(blockingTester),
            ],
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: restoflowLocalizationsDelegates,
              supportedLocales: kSupportedLocales,
              home: const Scaffold(
                body: SingleChildScrollView(child: NetworkPrinterSection()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('network-printer-ip-field')),
          '10.0.0.9',
        );
        await tester.tap(find.byKey(const Key('network-printer-test')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        // The Test's send is queued BEHIND the busy destination — not yet run.
        expect(
          blockingTester.calls,
          0,
          reason: 'the Test send is serialized behind the occupied gate',
        );

        held.complete(); // free the destination
        await tester.pumpAndSettle();
        expect(
          blockingTester.calls,
          1,
          reason: 'the Test ran once the gate freed (FIFO)',
        );
        blockingTester.release();
        await tester.pumpAndSettle();
        await occupied;
      },
    );
  });
}
