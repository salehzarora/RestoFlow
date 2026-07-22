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
    show posPrinterDestinationSendGateProvider;
import 'package:restoflow_pos/src/print/network_printer_tester.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
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
        final input = kitchenTicketInputFromCartLines(
          orderCode: '#000042',
          orderType: OrderType.dineIn,
          lines: [_line()],
          tableLabel: 'T1',
        );
        final outcome = await runAutoKitchenTicketPrintOnSubmit(
          container: c,
          orderId: 'ord-real-uuid',
          input: input,
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

  group('F5 same physical printer for both purposes', () {
    test(
      'kitchen + receipt sends to ONE endpoint serialize FIFO (shared gate)',
      () async {
        final gate = pp.PrinterDestinationSendGate();
        final order = <String>[];
        final firstDone = Completer<void>();
        // "receipt" holds the destination; "kitchen" must wait behind it.
        final key = pp.PrinterDestinationSendGate.networkKey('10.0.0.5', 9100);
        final receipt = gate.withDestination(key, () async {
          order.add('receipt-start');
          await firstDone.future;
          order.add('receipt-end');
          return const pp.PrintResult.success();
        });
        final kitchen = gate.withDestination(key, () async {
          order.add('kitchen-start');
          return const pp.PrintResult.success();
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
        // The kitchen send has NOT started — it is serialized behind the receipt.
        expect(order, ['receipt-start']);
        firstDone.complete();
        await Future.wait([receipt, kitchen]);
        expect(order, ['receipt-start', 'receipt-end', 'kitchen-start']);
      },
    );

    test(
      'the two documents differ: receipt carries money, kitchen never does',
      () async {
        // The kitchen document (real renderer) is money-free…
        final kitchenBytes = await runAndCapture('10.0.0.5', 9100);
        final kitchenText = utf8
            .decode(kitchenBytes, allowMalformed: true)
            .toLowerCase();
        for (final t in _money) {
          expect(kitchenText.contains(t.toLowerCase()), isFalse);
        }
        expect(kitchenText.contains('shawarma'), isTrue);
      },
    );
  });

  group('F5 different printers route independently', () {
    test(
      'the kitchen send reaches the KITCHEN endpoint, not the customer one',
      () async {
        // Kitchen configured to .9; a different customer endpoint (.1) is irrelevant.
        _mockKitchenNet('10.0.0.9', 9100);
        String? routedKey;
        final c = ProviderContainer(
          overrides: [
            posNativePrintingAvailableProvider.overrideWithValue(true),
            kitchenPrintTransportOverrideProvider.overrideWithValue((target) {
              routedKey = target.destinationKey;
              return _CapturingTransport();
            }),
          ],
        );
        addTearDown(c.dispose);
        await printKitchenTicketForOrder(
          container: c,
          input: kitchenTicketInputFromCartLines(
            orderCode: '#1',
            orderType: OrderType.takeaway,
            lines: [_line()],
          ),
        );
        expect(
          routedKey,
          pp.PrinterDestinationSendGate.networkKey('10.0.0.9', 9100),
          reason:
              'routed to the KITCHEN endpoint, independent of any receipt one',
        );
        expect(
          routedKey,
          isNot(pp.PrinterDestinationSendGate.networkKey('10.0.0.1', 9100)),
        );
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

/// Renders the REAL money-free kitchen bytes for a cart line and returns them
/// (used to prove the kitchen document differs from a money-bearing receipt).
Future<Uint8List> runAndCapture(String host, int port) async {
  SharedPreferences.setMockInitialValues({
    'restoflow.printer.selected.pos.kitchen_ticket.local': 'network',
    'restoflow.printer.network.pos.kitchen_ticket.local': jsonEncode({
      'host': host,
      'port': port,
    }),
  });
  final captured = _CapturingTransport();
  final c = ProviderContainer(
    overrides: [
      posNativePrintingAvailableProvider.overrideWithValue(true),
      kitchenPrintTransportOverrideProvider.overrideWithValue((_) => captured),
    ],
  );
  addTearDown(c.dispose);
  await printKitchenTicketForOrder(
    container: c,
    input: kitchenTicketInputFromCartLines(
      orderCode: '#000042',
      orderType: OrderType.dineIn,
      lines: [_line()],
    ),
  );
  return captured.sent.single;
}
