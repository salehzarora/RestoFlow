@TestOn('vm')
library;

import 'dart:convert' show jsonEncode, utf8;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/spool/kitchen_ticket_bytes.dart'
    show renderKitchenTicketBytes;
import 'package:restoflow_pos/src/state/cart_controller.dart'
    show CartLineView, SelectedModifier;
import 'package:restoflow_pos/src/state/pos_auto_print_prefs.dart';
import 'package:restoflow_pos/src/state/pos_network_printer_config.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pos_package_root.dart';

/// KITCHEN-PRINT-DUAL-001 — independent cashier + kitchen printing.
///
/// The two printer PURPOSE slots (customer_receipt / kitchen_ticket) already
/// exist (KITCHEN-MODE-001B); these tests cover the NEW print-time wiring: the
/// money-free kitchen render + send through the INDEPENDENT kitchen slot, the
/// per-device auto-print setting, duplicate protection, and the source
/// boundaries (no pilot flag, no Supabase mode/readiness call).

/// A scripted transport that records the bytes it was handed (no real socket).
class _FakeTransport implements pp.PrintTransport {
  _FakeTransport(this._result);
  final pp.PrintResult _result;
  final List<Uint8List> sent = [];
  bool disposed = false;

  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    sent.add(bytes);
    return _result;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

/// A [PosAutoPrintKitchenTicketController] stub with a fixed stored value, so
/// the auto-print decision can be exercised without a paired device.
class _StubAutoKitchen extends PosAutoPrintKitchenTicketController {
  _StubAutoKitchen(this._value);
  final bool? _value;
  @override
  Future<bool?> build() async => _value;
}

const _moneyTokens = [
  'total',
  'subtotal',
  'tax',
  'discount',
  'payment',
  'tender',
  'price',
  'amount',
  '₪',
  r'$',
  '€',
];

ProviderContainer _container({List<Override> overrides = const []}) {
  final c = ProviderContainer(
    overrides: [
      posNativePrintingAvailableProvider.overrideWithValue(true),
      ...overrides,
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Seeds the per-device printer-slot prefs BEFORE the container is built (so the
/// providers load them via `build()` — no save/build race). Keys mirror the
/// production key builders (customer = legacy empty segment; kitchen =
/// `kitchen_ticket.`; no paired device => the `local` segment).
void _mockSlots({
  ({String host, int port})? kitchenNet,
  String? kitchenBt,
  PosPrinterTransportKind kitchenTransport = PosPrinterTransportKind.network,
  ({String host, int port})? customerNet,
}) {
  final m = <String, Object>{
    'restoflow.printer.selected.pos.kitchen_ticket.local':
        kitchenTransport.name,
  };
  if (kitchenNet != null) {
    m['restoflow.printer.network.pos.kitchen_ticket.local'] = jsonEncode({
      'host': kitchenNet.host,
      'port': kitchenNet.port,
    });
  }
  if (kitchenBt != null) {
    m['restoflow.printer.bluetooth.pos.kitchen_ticket.local'] = jsonEncode({
      'address': kitchenBt,
    });
  }
  if (customerNet != null) {
    m['restoflow.printer.network.pos.local'] = jsonEncode({
      'host': customerNet.host,
      'port': customerNet.port,
    });
  }
  SharedPreferences.setMockInitialValues(m);
}

KitchenTicketInput _input() => const KitchenTicketInput(
  orderCode: '#000042',
  orderType: 'dine_in',
  tableLabel: 'T1',
  lines: [
    KitchenTicketLineInput(
      qty: 2,
      name: 'Falafel',
      note: 'no onion',
      modifiers: ['Laffa', 'Hot ×3'],
    ),
    KitchenTicketLineInput(qty: 1, name: 'Hummus'),
  ],
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('money-free kitchen render (never the receipt renderer)', () {
    test('the rendered bytes carry the items but no money token', () async {
      final bytes = await renderKitchenTicketBytes(input: _input());
      final text = utf8.decode(bytes, allowMalformed: true).toLowerCase();
      expect(text.contains('falafel'), isTrue, reason: 'item present');
      expect(text.contains('hummus'), isTrue);
      for (final token in _moneyTokens) {
        expect(
          text.contains(token.toLowerCase()),
          isFalse,
          reason: 'no money token "$token" on a kitchen ticket',
        );
      }
    });

    test(
      'the cart projection drops every price/total (money-free by shape)',
      () async {
        final input = kitchenTicketInputFromCartLines(
          orderCode: '#000042',
          orderType: OrderType.dineIn,
          lines: [
            CartLineView(
              lineId: 'l1',
              menuItemId: 'm1',
              name: 'Shawarma',
              quantity: 2,
              unitPriceMinor: 1500,
              lineTotalMinor: 3000,
              currencyCode: 'ILS',
              note: 'extra garlic',
              modifiers: const [
                SelectedModifier(
                  optionId: 'o1',
                  groupName: 'Bread',
                  optionName: 'Laffa',
                  priceDeltaMinor: 300,
                  quantity: 1,
                ),
                SelectedModifier(
                  optionId: 'o2',
                  groupName: 'Spice',
                  optionName: 'Hot',
                  priceDeltaMinor: 0,
                  quantity: 3,
                ),
              ],
            ),
          ],
        );
        // Preserves qty/name/note/modifiers…
        expect(input.lines.single.qty, 2);
        expect(input.lines.single.name, 'Shawarma');
        expect(input.lines.single.note, 'extra garlic');
        expect(input.lines.single.modifiers, ['Laffa', 'Hot ×3']);
        // …and renders with NO money (1500/3000/300 never reach the ticket).
        final text = utf8
            .decode(
              await renderKitchenTicketBytes(input: input),
              allowMalformed: true,
            )
            .toLowerCase();
        for (final token in [..._moneyTokens, '1500', '3000', '300']) {
          expect(text.contains(token.toLowerCase()), isFalse);
        }
      },
    );
  });

  group('two independent purpose slots (same-printer supported)', () {
    test(
      'the kitchen slot resolves independently of the customer slot',
      () async {
        // Only the KITCHEN slot is configured; the customer slot is untouched.
        _mockSlots(kitchenNet: (host: '10.0.0.9', port: 9100));
        final target = await resolveKitchenPrinterTarget(_container());
        expect(target, isNotNull);
        expect(
          target!.destinationKey,
          pp.PrinterDestinationSendGate.networkKey('10.0.0.9', 9100),
        );
      },
    );

    test(
      'the SAME physical printer for both purposes shares the gate key',
      () async {
        const host = '10.0.0.5';
        const port = 9100;
        // Both purposes point at the SAME saved printer.
        _mockSlots(
          kitchenNet: (host: host, port: port),
          customerNet: (host: host, port: port),
        );
        final c = _container();
        final kitchen = await resolveKitchenPrinterTarget(c);
        // The kitchen target's gate key equals the customer endpoint's key, so a
        // shared physical printer serializes receipt + kitchen (never interleaved).
        expect(
          kitchen!.destinationKey,
          pp.PrinterDestinationSendGate.networkKey(host, port),
        );
        // The customer slot is still configured (the two slots are independent).
        expect(
          (await c.read(posNetworkPrinterConfigProvider.future))?.host,
          host,
        );
      },
    );

    test(
      'only the CASHIER printer configured => kitchen resolves to null',
      () async {
        _mockSlots(customerNet: (host: '10.0.0.1', port: 9100));
        expect(await resolveKitchenPrinterTarget(_container()), isNull);
      },
    );

    test(
      'only the KITCHEN printer configured (bluetooth) => resolves',
      () async {
        _mockSlots(
          kitchenBt: 'DC:0D:30:AA:BB:CC',
          kitchenTransport: PosPrinterTransportKind.bluetooth,
        );
        final target = await resolveKitchenPrinterTarget(_container());
        expect(target, isNotNull);
        expect(
          target!.destinationKey,
          pp.PrinterDestinationSendGate.bluetoothKey('DC:0D:30:AA:BB:CC'),
        );
      },
    );

    test('NEITHER configured => kitchen resolves to null', () async {
      expect(await resolveKitchenPrinterTarget(_container()), isNull);
    });
  });

  group('kitchen send outcome (honest, never a receipt)', () {
    test(
      'an accepted transport reports printed and disposes the socket',
      () async {
        final c = _container();
        final fake = _FakeTransport(const pp.PrintResult.success());
        final printer = PosKitchenTicketPrinter(
          c,
          targetOverride: ResolvedKitchenPrinter(
            destinationKey: 'k',
            transportFactory: () => fake,
          ),
        );
        final outcome = await printer.printKitchenTicket(input: _input());
        expect(outcome, PosKitchenPrintOutcome.printed);
        expect(fake.sent, hasLength(1), reason: 'exactly one physical send');
        expect(fake.disposed, isTrue);
        // The bytes are a KITCHEN document (money-free).
        final text = utf8
            .decode(fake.sent.single, allowMalformed: true)
            .toLowerCase();
        for (final token in _moneyTokens) {
          expect(text.contains(token.toLowerCase()), isFalse);
        }
      },
    );

    test('a failed transport reports failed (not a fake success)', () async {
      final c = _container();
      final fake = _FakeTransport(
        const pp.PrintResult.failure(pp.PrinterErrorCategory.unreachable),
      );
      final printer = PosKitchenTicketPrinter(
        c,
        targetOverride: ResolvedKitchenPrinter(
          destinationKey: 'k',
          transportFactory: () => fake,
        ),
      );
      expect(
        await printer.printKitchenTicket(input: _input()),
        PosKitchenPrintOutcome.failed,
      );
    });

    test('no kitchen printer => noPrinterConfigured, nothing sent', () async {
      expect(
        await printKitchenTicketForOrder(
          container: _container(),
          input: _input(),
        ),
        PosKitchenPrintOutcome.noPrinterConfigured,
      );
    });

    test(
      'the MANUAL action prints one kitchen ticket (an intentional print)',
      () async {
        final c = _container();
        final fake = _FakeTransport(const pp.PrintResult.success());
        final outcome = await printKitchenTicketForOrder(
          container: c,
          input: _input(),
          printer: PosKitchenTicketPrinter(
            c,
            targetOverride: ResolvedKitchenPrinter(
              destinationKey: 'k',
              transportFactory: () => fake,
            ),
          ),
        );
        expect(outcome, PosKitchenPrintOutcome.printed);
        expect(fake.sent, hasLength(1));
      },
    );
  });

  group('the per-device auto-print setting', () {
    test('defaults OFF (opt-in), and needs a kitchen printer', () {
      expect(
        posAutoPrintKitchenTicketEnabled(stored: null, hasKitchenPrinter: true),
        isFalse,
      );
      expect(
        posAutoPrintKitchenTicketEnabled(stored: true, hasKitchenPrinter: true),
        isTrue,
      );
      expect(
        posAutoPrintKitchenTicketEnabled(
          stored: true,
          hasKitchenPrinter: false,
        ),
        isFalse,
      );
    });

    test(
      'persists locally per device (same mechanism as the receipt one)',
      () async {
        final c = _container();
        c
            .read(posDeviceContextProvider.notifier)
            .set(
              const DeviceContext(
                organizationId: 'org',
                branchId: 'br',
                deviceId: 'dev-1',
              ),
            );
        await c.read(
          posAutoPrintKitchenTicketProvider.future,
        ); // build w/ device
        await c
            .read(posAutoPrintKitchenTicketProvider.notifier)
            .setEnabled(true);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getBool('restoflow.autoprint.pos.kitchenTicket.dev-1'),
          isTrue,
        );
      },
    );

    test(
      'OFF (default) => the auto flow is inert and claims no order',
      () async {
        final c = _container();
        final guard = c.read(posAutoKitchenPrintGuardProvider);
        final outcome = await runAutoKitchenTicketPrintOnSubmit(
          container: c,
          orderId: 'order-1',
          input: _input(),
        );
        expect(outcome, PosKitchenPrintOutcome.noPrinterConfigured);
        // Inert: the order was never claimed, so nothing was attempted.
        expect(guard.claim('order-1'), isTrue);
      },
    );

    test(
      'ON => prints once, and a duplicate callback does not reprint',
      () async {
        final c = _container(
          overrides: [
            posAutoPrintKitchenTicketProvider.overrideWith(
              () => _StubAutoKitchen(true),
            ),
          ],
        );
        await c.read(
          posAutoPrintKitchenTicketProvider.future,
        ); // load AsyncData
        final fake = _FakeTransport(const pp.PrintResult.success());
        final printer = PosKitchenTicketPrinter(
          c,
          targetOverride: ResolvedKitchenPrinter(
            destinationKey: 'k',
            transportFactory: () => fake,
          ),
        );
        final first = await runAutoKitchenTicketPrintOnSubmit(
          container: c,
          orderId: 'order-1',
          input: _input(),
          printer: printer,
        );
        expect(first, PosKitchenPrintOutcome.printed);
        expect(fake.sent, hasLength(1));
        // A second callback for the SAME order does not print again.
        final second = await runAutoKitchenTicketPrintOnSubmit(
          container: c,
          orderId: 'order-1',
          input: _input(),
          printer: printer,
        );
        expect(second, PosKitchenPrintOutcome.printed);
        expect(fake.sent, hasLength(1), reason: 'no duplicate auto print');
      },
    );
  });

  group('duplicate guard', () {
    test('claims an order id exactly once', () {
      final guard = PosAutoKitchenPrintGuard();
      expect(guard.claim('a'), isTrue);
      expect(guard.claim('a'), isFalse);
      expect(guard.claim('b'), isTrue);
    });
  });

  group('source boundaries', () {
    late final String printerSrc;
    late final String bytesSrc;
    late final String allPosSrc;

    setUpAll(() {
      final root = locatePosPackageRoot();
      printerSrc = File(
        p.join(
          root.path,
          'lib',
          'src',
          'print',
          'pos_kitchen_ticket_printer.dart',
        ),
      ).readAsStringSync();
      bytesSrc = File(
        p.join(root.path, 'lib', 'src', 'spool', 'kitchen_ticket_bytes.dart'),
      ).readAsStringSync();
      final buffer = StringBuffer();
      for (final f
          in Directory(p.join(root.path, 'lib'))
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        buffer.writeln(f.readAsStringSync());
      }
      allPosSrc = buffer.toString();
    });

    test('the feature has NO pilot-flag dependency (abandoned pilot)', () {
      expect(printerSrc, isNot(contains('RESTOFLOW_PRINTER_ONLY_PILOT')));
      expect(bytesSrc, isNot(contains('RESTOFLOW_PRINTER_ONLY_PILOT')));
      // The abandoned printer-only pilot flag exists NOWHERE in POS sources.
      expect(allPosSrc, isNot(contains('RESTOFLOW_PRINTER_ONLY_PILOT')));
    });

    test(
      'the feature makes NO Supabase kitchen mode/status/readiness call',
      () {
        for (final rpc in [
          'set_kitchen_workflow_mode',
          'set_branch_kitchen_workflow_mode',
          'report_kitchen_pos_status',
          'report_kitchen_printer_readiness',
          'pull_kitchen_print_dispatches',
          'get_kitchen_workflow_transition_readiness',
        ]) {
          expect(printerSrc, isNot(contains(rpc)));
          expect(bytesSrc, isNot(contains(rpc)));
        }
      },
    );

    test('the print service never mutates order / payment / KDS state', () {
      for (final banned in [
        'paymentController',
        'recordPayment',
        'markVoided',
        'order.void',
        'kdsKitchenPrintController',
        'operation_statuses',
        'markServed',
        'markCompleted',
      ]) {
        expect(
          printerSrc,
          isNot(contains(banned)),
          reason: 'kitchen printing must not touch "$banned"',
        );
      }
    });
  });
}
