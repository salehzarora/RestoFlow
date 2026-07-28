@TestOn('vm')
library;

import 'dart:async' show Completer;
import 'dart:convert' show jsonEncode, utf8;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_l10n/restoflow_l10n.dart' show AppLocalizations;
import 'package:restoflow_pos/src/data/order_submission.dart'
    show kPermanentRejectionCodes;
import 'package:restoflow_pos/src/print/kitchen_ticket_render.dart'
    show renderKitchenTicketBytes;
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
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

/// Cold-start simulation: the persisted value resolves only AFTER a delay (i.e.
/// the provider is momentarily AsyncLoading), and is never primed before the
/// first submit — a SYNC read would wrongly see null/false.
class _SlowAutoKitchen extends PosAutoPrintKitchenTicketController {
  _SlowAutoKitchen(this._value);
  final bool _value;
  @override
  Future<bool?> build() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return _value;
  }
}

/// A storage read that fails — the setting future completes with an error.
class _ThrowingAutoKitchen extends PosAutoPrintKitchenTicketController {
  @override
  Future<bool?> build() async => throw StateError('prefs read error');
}

/// A transport whose send blocks on a gate so an in-flight attempt can be
/// observed by a concurrent duplicate callback.
class _BlockingTransport implements pp.PrintTransport {
  final Completer<void> _release = Completer<void>();
  int sends = 0;
  void release() => _release.complete();
  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    sends++;
    await _release.future;
    return const pp.PrintResult.success();
  }

  @override
  Future<void> dispose() async {}
}

PosKitchenTicketPrinter _printerTo(
  ProviderContainer c,
  pp.PrintTransport transport,
) => PosKitchenTicketPrinter(
  c,
  targetOverride: ResolvedKitchenPrinter(
    destinationKey: 'k',
    transportFactory: () => transport,
  ),
);

ProviderContainer _onContainer() => _container(
  overrides: [
    posAutoPrintKitchenTicketProvider.overrideWith(
      () => _StubAutoKitchen(true),
    ),
  ],
);

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

/// The representative kitchen ticket — built through the REAL cart projection
/// [kdsTicketViewFromCartLines] (the SAME shared KdsTicketView the KDS renders):
/// Falafel ×2 with Laffa + Hot ×3 and a "no onion" note, plus Hummus ×1.
KdsTicketView _ticket() => kdsTicketViewFromCartLines(
  orderCode: '#000042',
  orderType: OrderType.dineIn,
  tableLabel: 'T1',
  lines: const [
    CartLineView(
      lineId: 'l1',
      menuItemId: 'm1',
      name: 'Falafel',
      quantity: 2,
      unitPriceMinor: 1500,
      lineTotalMinor: 3000,
      currencyCode: 'ILS',
      note: 'no onion',
      modifiers: [
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
    CartLineView(
      lineId: 'l2',
      menuItemId: 'm2',
      name: 'Hummus',
      quantity: 1,
      unitPriceMinor: 1000,
      lineTotalMinor: 1000,
      currencyCode: 'ILS',
    ),
  ],
);

/// A plain en labels fixture (these tests exercise render/routing/guard, not
/// chrome — the chrome parity with the KDS is proven in the parity suite).
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
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('money-free kitchen render (never the receipt renderer)', () {
    test('the rendered bytes carry the items but no money token', () async {
      final bytes = await renderKitchenTicketBytes(
        ticket: _ticket(),
        labels: _labels(),
      );
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
        final ticket = kdsTicketViewFromCartLines(
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
        expect(ticket.items.single.quantity, 2);
        expect(ticket.items.single.name, 'Shawarma');
        expect(ticket.items.single.note, 'extra garlic');
        expect(ticket.items.single.modifiers, ['Laffa', 'Hot ×3']);
        // …and renders with NO money (1500/3000/300 never reach the ticket).
        final text = utf8
            .decode(
              await renderKitchenTicketBytes(ticket: ticket, labels: _labels()),
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
        final outcome = await printer.printKitchenTicket(
          ticket: _ticket(),
          labels: _labels(),
        );
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
        await printer.printKitchenTicket(ticket: _ticket(), labels: _labels()),
        PosKitchenPrintOutcome.failed,
      );
    });

    test('no kitchen printer => noPrinterConfigured, nothing sent', () async {
      expect(
        await printKitchenTicketForOrder(
          container: _container(),
          ticket: _ticket(),
          labels: _labels(),
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
          ticket: _ticket(),
          labels: _labels(),
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

    test('OFF (default) => the auto flow is inert (no send)', () async {
      final c = _container();
      final fake = _FakeTransport(const pp.PrintResult.success());
      final outcome = await runAutoKitchenTicketPrintOnSubmit(
        container: c,
        orderId: 'order-1',
        ticket: _ticket(),
        labels: _labels(),
        printer: _printerTo(c, fake),
      );
      expect(outcome, PosKitchenPrintOutcome.noPrinterConfigured);
      expect(fake.sent, isEmpty);
    });

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
          ticket: _ticket(),
          labels: _labels(),
          printer: printer,
        );
        expect(first, PosKitchenPrintOutcome.printed);
        expect(fake.sent, hasLength(1));
        // A second callback for the SAME order does not print again.
        final second = await runAutoKitchenTicketPrintOnSubmit(
          container: c,
          orderId: 'order-1',
          ticket: _ticket(),
          labels: _labels(),
          printer: printer,
        );
        expect(second, PosKitchenPrintOutcome.printed);
        expect(fake.sent, hasLength(1), reason: 'no duplicate auto print');
      },
    );
  });

  group('cold-start setting read (F1)', () {
    // These use _SlowAutoKitchen (the value resolves AFTER a delay) WITHOUT ever
    // priming the provider — proving the auto path AWAITS the resolved value.
    test(
      'persisted true + cold start + immediate first submit => one send',
      () async {
        final c = _container(
          overrides: [
            posAutoPrintKitchenTicketProvider.overrideWith(
              () => _SlowAutoKitchen(true),
            ),
          ],
        );
        final fake = _FakeTransport(const pp.PrintResult.success());
        final outcome = await runAutoKitchenTicketPrintOnSubmit(
          container: c,
          orderId: 'order-1',
          ticket: _ticket(),
          labels: _labels(),
          printer: _printerTo(c, fake),
        );
        expect(outcome, PosKitchenPrintOutcome.printed);
        expect(fake.sent, hasLength(1));
      },
    );

    test('persisted false + cold start => zero sends', () async {
      final c = _container(
        overrides: [
          posAutoPrintKitchenTicketProvider.overrideWith(
            () => _SlowAutoKitchen(false),
          ),
        ],
      );
      final fake = _FakeTransport(const pp.PrintResult.success());
      final outcome = await runAutoKitchenTicketPrintOnSubmit(
        container: c,
        orderId: 'order-1',
        ticket: _ticket(),
        labels: _labels(),
        printer: _printerTo(c, fake),
      );
      expect(outcome, PosKitchenPrintOutcome.noPrinterConfigured);
      expect(fake.sent, isEmpty);
    });

    test(
      'a storage read error => zero sends, fail closed (order unaffected)',
      () async {
        final c = _container(
          overrides: [
            posAutoPrintKitchenTicketProvider.overrideWith(
              () => _ThrowingAutoKitchen(),
            ),
          ],
        );
        final fake = _FakeTransport(const pp.PrintResult.success());
        final outcome = await runAutoKitchenTicketPrintOnSubmit(
          container: c,
          orderId: 'order-1',
          ticket: _ticket(),
          labels: _labels(),
          printer: _printerTo(c, fake),
        );
        expect(outcome, PosKitchenPrintOutcome.failed);
        expect(fake.sent, isEmpty);
      },
    );
  });

  group('retry-safe guard (F2)', () {
    test(
      'concurrent duplicate callbacks share the in-flight attempt => one send',
      () async {
        final c = _onContainer();
        final blocking = _BlockingTransport();
        final printer = _printerTo(c, blocking);
        final f1 = runAutoKitchenTicketPrintOnSubmit(
          container: c,
          orderId: 'o',
          ticket: _ticket(),
          labels: _labels(),
          printer: printer,
        );
        final f2 = runAutoKitchenTicketPrintOnSubmit(
          container: c,
          orderId: 'o',
          ticket: _ticket(),
          labels: _labels(),
          printer: printer,
        );
        // Let both reach the (blocked) send; the second must SHARE the first.
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          blocking.sends,
          1,
          reason: 'the duplicate shared the in-flight send',
        );
        blocking.release();
        expect(await Future.wait([f1, f2]), [
          PosKitchenPrintOutcome.printed,
          PosKitchenPrintOutcome.printed,
        ]);
        expect(blocking.sends, 1, reason: 'exactly one physical send');
      },
    );

    test(
      'first NO-PRINTER failure releases => after configuring, second sends once',
      () async {
        final c = _onContainer();
        // First: no printer override + no config => resolver null => noPrinter.
        final first = await runAutoKitchenTicketPrintOnSubmit(
          container: c,
          orderId: 'o',
          ticket: _ticket(),
          labels: _labels(),
        );
        expect(first, PosKitchenPrintOutcome.noPrinterConfigured);
        // Second: a printer is now available => sends exactly once (not blocked).
        final fake = _FakeTransport(const pp.PrintResult.success());
        final second = await runAutoKitchenTicketPrintOnSubmit(
          container: c,
          orderId: 'o',
          ticket: _ticket(),
          labels: _labels(),
          printer: _printerTo(c, fake),
        );
        expect(second, PosKitchenPrintOutcome.printed);
        expect(fake.sent, hasLength(1));
      },
    );

    test(
      'first TRANSPORT failure releases => second attempt sends once',
      () async {
        final c = _onContainer();
        final failing = _FakeTransport(
          const pp.PrintResult.failure(pp.PrinterErrorCategory.unreachable),
        );
        expect(
          await runAutoKitchenTicketPrintOnSubmit(
            container: c,
            orderId: 'o',
            ticket: _ticket(),
            labels: _labels(),
            printer: _printerTo(c, failing),
          ),
          PosKitchenPrintOutcome.failed,
        );
        expect(failing.sent, hasLength(1));
        final ok = _FakeTransport(const pp.PrintResult.success());
        expect(
          await runAutoKitchenTicketPrintOnSubmit(
            container: c,
            orderId: 'o',
            ticket: _ticket(),
            labels: _labels(),
            printer: _printerTo(c, ok),
          ),
          PosKitchenPrintOutcome.printed,
        );
        expect(ok.sent, hasLength(1));
      },
    );

    test('a RENDER exception releases => later recovery succeeds', () async {
      final c = _onContainer();
      final fake = _FakeTransport(const pp.PrintResult.success());
      final throwing = PosKitchenTicketPrinter(
        c,
        buildBytes:
            ({
              required ticket,
              required labels,
              rasterizer,
              mediaProfile,
              restaurantName,
            }) => Future<Uint8List>.error(StateError('boom')),
        targetOverride: ResolvedKitchenPrinter(
          destinationKey: 'k',
          transportFactory: () => fake,
        ),
      );
      expect(
        await runAutoKitchenTicketPrintOnSubmit(
          container: c,
          orderId: 'o',
          ticket: _ticket(),
          labels: _labels(),
          printer: throwing,
        ),
        PosKitchenPrintOutcome.failed,
      );
      expect(fake.sent, isEmpty, reason: 'render threw before any send');
      expect(
        await runAutoKitchenTicketPrintOnSubmit(
          container: c,
          orderId: 'o',
          ticket: _ticket(),
          labels: _labels(),
          printer: _printerTo(c, fake),
        ),
        PosKitchenPrintOutcome.printed,
      );
      expect(fake.sent, hasLength(1));
    });

    test('a confirmed success suppresses a later duplicate callback', () async {
      final c = _onContainer();
      final fake = _FakeTransport(const pp.PrintResult.success());
      expect(
        await runAutoKitchenTicketPrintOnSubmit(
          container: c,
          orderId: 'o',
          ticket: _ticket(),
          labels: _labels(),
          printer: _printerTo(c, fake),
        ),
        PosKitchenPrintOutcome.printed,
      );
      expect(
        await runAutoKitchenTicketPrintOnSubmit(
          container: c,
          orderId: 'o',
          ticket: _ticket(),
          labels: _labels(),
          printer: _printerTo(c, fake),
        ),
        PosKitchenPrintOutcome.printed,
      );
      expect(
        fake.sent,
        hasLength(1),
        reason: 'no reprint after a confirmed send',
      );
    });

    test('the returned outcome always matches the real send result', () async {
      final c = _onContainer();
      final ok = _FakeTransport(const pp.PrintResult.success());
      expect(
        await runAutoKitchenTicketPrintOnSubmit(
          container: c,
          orderId: 'a',
          ticket: _ticket(),
          labels: _labels(),
          printer: _printerTo(c, ok),
        ),
        PosKitchenPrintOutcome.printed,
      );
      final bad = _FakeTransport(
        const pp.PrintResult.failure(pp.PrinterErrorCategory.unreachable),
      );
      expect(
        await runAutoKitchenTicketPrintOnSubmit(
          container: c,
          orderId: 'b',
          ticket: _ticket(),
          labels: _labels(),
          printer: _printerTo(c, bad),
        ),
        PosKitchenPrintOutcome.failed,
      );
    });
  });

  group('guard synchronous-throw safety (final F1)', () {
    test(
      'a SYNCHRONOUS throw releases the order; a retry succeeds (calls==2)',
      () async {
        final guard = PosAutoKitchenPrintGuard();
        var calls = 0;
        // A NON-async attempt that throws SYNCHRONOUSLY (before returning a
        // Future) on the first call, then returns success on the retry.
        Future<PosKitchenPrintOutcome> attempt() {
          calls++;
          if (calls == 1) throw StateError('sync boom');
          return Future.value(PosKitchenPrintOutcome.printed);
        }

        expect(
          await guard.runGuarded('o', attempt),
          PosKitchenPrintOutcome.failed,
        );
        expect(
          await guard.runGuarded('o', attempt),
          PosKitchenPrintOutcome.printed,
        );
        expect(
          calls,
          2,
          reason: 'the sync-throw order was released for a retry',
        );
      },
    );

    test(
      'an ASYNCHRONOUS failure releases the order; a retry succeeds',
      () async {
        final guard = PosAutoKitchenPrintGuard();
        var calls = 0;
        Future<PosKitchenPrintOutcome> attempt() async {
          calls++;
          return calls == 1
              ? PosKitchenPrintOutcome.failed
              : PosKitchenPrintOutcome.printed;
        }

        expect(
          await guard.runGuarded('o', attempt),
          PosKitchenPrintOutcome.failed,
        );
        expect(
          await guard.runGuarded('o', attempt),
          PosKitchenPrintOutcome.printed,
        );
        expect(calls, 2);
      },
    );

    test(
      'concurrent callers during the first attempt share ONE future',
      () async {
        final guard = PosAutoKitchenPrintGuard();
        final release = Completer<void>();
        var calls = 0;
        Future<PosKitchenPrintOutcome> attempt() async {
          calls++;
          await release.future;
          return PosKitchenPrintOutcome.printed;
        }

        final f1 = guard.runGuarded('o', attempt);
        final f2 = guard.runGuarded('o', attempt);
        expect(
          identical(f1, f2),
          isTrue,
          reason: 'the duplicate shares the future',
        );
        release.complete();
        expect(await Future.wait([f1, f2]), [
          PosKitchenPrintOutcome.printed,
          PosKitchenPrintOutcome.printed,
        ]);
        expect(calls, 1, reason: 'exactly one attempt for concurrent callers');
      },
    );

    test(
      'a confirmed success suppresses later duplicates; failure never lies',
      () async {
        final guard = PosAutoKitchenPrintGuard();
        var calls = 0;
        Future<PosKitchenPrintOutcome> succeed() async {
          calls++;
          return PosKitchenPrintOutcome.printed;
        }

        expect(
          await guard.runGuarded('a', succeed),
          PosKitchenPrintOutcome.printed,
        );
        expect(
          await guard.runGuarded('a', succeed),
          PosKitchenPrintOutcome.printed,
        );
        expect(
          calls,
          1,
          reason: 'success suppressed the duplicate — no re-send',
        );
        // A failed order NEVER reports printed.
        expect(
          await guard.runGuarded(
            'b',
            () async => PosKitchenPrintOutcome.failed,
          ),
          PosKitchenPrintOutcome.failed,
        );
      },
    );
  });

  group('order eligibility (F3)', () {
    test('a real accepted order id is eligible', () {
      expect(
        isOrderEligibleForKitchenPrint(
          orderId: 'ord-real-uuid',
          isDemoMode: false,
        ),
        isTrue,
      );
    });

    test('demo mode / demo-placeholder / blank ids are ineligible', () {
      expect(
        isOrderEligibleForKitchenPrint(orderId: 'ord-real', isDemoMode: true),
        isFalse,
      );
      for (final id in ['demo-order', 'demo-order-7', '', '   ', null]) {
        expect(
          isOrderEligibleForKitchenPrint(orderId: id, isDemoMode: false),
          isFalse,
          reason: 'id "$id"',
        );
      }
    });

    test('EVERY permanent rejection code is ineligible', () {
      expect(kPermanentRejectionCodes, isNotEmpty);
      for (final code in kPermanentRejectionCodes) {
        expect(
          isOrderEligibleForKitchenPrint(
            orderId: 'ord-real',
            isDemoMode: false,
            rejectionCode: code,
          ),
          isFalse,
          reason: code,
        );
      }
    });

    test('a NON-permanent error code stays eligible', () {
      expect(
        isOrderEligibleForKitchenPrint(
          orderId: 'ord-real',
          isDemoMode: false,
          rejectionCode: 'malformed_response',
        ),
        isTrue,
      );
    });

    test(
      'the auto path sends NOTHING for each permanent rejection code',
      () async {
        for (final code in kPermanentRejectionCodes) {
          final c = _onContainer();
          final fake = _FakeTransport(const pp.PrintResult.success());
          final outcome = await runAutoKitchenTicketPrintOnSubmit(
            container: c,
            orderId: 'ord-real',
            isDemoMode: false,
            rejectionCode: code,
            ticket: _ticket(),
            labels: _labels(),
            printer: _printerTo(c, fake),
          );
          expect(outcome, PosKitchenPrintOutcome.ineligibleOrder, reason: code);
          expect(fake.sent, isEmpty, reason: code);
        }
      },
    );

    test('a demo order sends nothing on the auto path', () async {
      final c = _onContainer();
      final fake = _FakeTransport(const pp.PrintResult.success());
      final outcome = await runAutoKitchenTicketPrintOnSubmit(
        container: c,
        orderId: 'demo-order-1',
        isDemoMode: true,
        ticket: _ticket(),
        labels: _labels(),
        printer: _printerTo(c, fake),
      );
      expect(outcome, PosKitchenPrintOutcome.ineligibleOrder);
      expect(fake.sent, isEmpty);
    });
  });

  group('localization terminology (F7)', () {
    test(
      'the kitchen toggle uses تذكرة (ticket), never فاتورة (invoice)',
      () async {
        final ar = await AppLocalizations.delegate.load(const Locale('ar'));
        expect(
          ar.posAutoPrintKitchenTicketToggle,
          'طباعة تذكرة المطبخ تلقائيًا',
        );
        expect(ar.posAutoPrintKitchenTicketToggle, isNot(contains('فاتورة')));
        // Kitchen-document strings say تذكرة المطبخ, not a customer فاتورة.
        expect(ar.autoPrintKitchenNoPrinterNote, contains('تذكرة المطبخ'));
        expect(ar.autoPrintKitchenNoPrinterNote, isNot(contains('فاتورة')));
        expect(ar.posKitchenTicketPrintedSnack, contains('تذكرة المطبخ'));
      },
    );

    test(
      'the kitchen-printer notice no longer claims auto printing is unavailable',
      () async {
        final en = await AppLocalizations.delegate.load(const Locale('en'));
        // Obsolete contradictory wording is GONE…
        expect(
          en.posKitchenPrinterPreparationBody,
          isNot(contains('not printed automatically')),
        );
        // …replaced by: the toggle controls it, a kitchen printer is required,
        // and manual printing stays available.
        expect(
          en.posKitchenPrinterPreparationBody,
          contains('Automatically print kitchen ticket'),
        );
        expect(
          en.posKitchenPrinterPreparationBody,
          contains('kitchen printer'),
        );
        expect(en.posKitchenPrinterPreparationBody, contains('manual'));
        final ar = await AppLocalizations.delegate.load(const Locale('ar'));
        expect(
          ar.posKitchenPrinterPreparationBody,
          isNot(contains('لا تُطبع تذاكر المطبخ تلقائيًا بعد')),
        );
        expect(ar.posKitchenPrinterPreparationBody, contains('تذكرة المطبخ'));
        expect(ar.posKitchenPrinterPreparationBody, isNot(contains('فاتورة')));
        final he = await AppLocalizations.delegate.load(const Locale('he'));
        expect(he.posKitchenPrinterPreparationBody, contains('מדפסת מטבח'));
        expect(
          he.posKitchenPrinterPreparationBody,
          isNot(contains('אינם מודפסים אוטומטית')),
        );
      },
    );

    test(
      'the scoped no-printer notes are distinct + correctly worded',
      () async {
        final en = await AppLocalizations.delegate.load(const Locale('en'));
        expect(en.autoPrintReceiptNoPrinterNote, contains('receipt printer'));
        // The kitchen note clarifies the toggle controls it + needs a printer
        // (not the old "unavailable" wording).
        expect(en.autoPrintKitchenNoPrinterNote, contains('kitchen printer'));
        expect(
          en.autoPrintReceiptNoPrinterNote,
          isNot(en.autoPrintKitchenNoPrinterNote),
        );
        final he = await AppLocalizations.delegate.load(const Locale('he'));
        expect(he.posAutoPrintKitchenTicketToggle, contains('כרטיס מטבח'));
        expect(he.autoPrintKitchenNoPrinterNote, contains('מדפסת מטבח'));
      },
    );
  });

  group('source boundaries', () {
    late final String printerSrc;
    late final String renderSrc;
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
      // 001B: the ACTIVE kitchen bytes builder (the drift spool renderer is now
      // dormant, confined to lib/src/spool).
      renderSrc = File(
        p.join(root.path, 'lib', 'src', 'print', 'kitchen_ticket_render.dart'),
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
      expect(renderSrc, isNot(contains('RESTOFLOW_PRINTER_ONLY_PILOT')));
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
          expect(renderSrc, isNot(contains(rpc)));
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
