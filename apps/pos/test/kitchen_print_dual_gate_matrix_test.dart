import 'dart:async' show Completer;
import 'dart:convert' show jsonEncode;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show
        BluetoothPairedResult,
        BluetoothPrinterConfig,
        BluetoothPrinterConnector,
        NetworkPrinterConfig,
        bluetoothPrinterConnectorProvider,
        bluetoothPrinterTesterProvider,
        networkPrinterTesterProvider;
import 'package:restoflow_native_printing/src/printer_testers.dart'
    show BluetoothPrinterTester, NetworkPrinterTester;
import 'package:restoflow_pos/src/print/native_print_bridges.dart'
    show posPrinterDestinationSendGateProvider;
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart' show CartLineView;
import 'package:restoflow_pos/src/state/pos_printer_purpose.dart';
import 'package:restoflow_pos/src/widgets/bluetooth_printer_section.dart';
import 'package:restoflow_pos/src/widgets/network_printer_section.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

/// KITCHEN-PRINT-DUAL-001 (F4) — the Test-print gate MATRIX. Proves ACTUAL
/// ordering (never just equal keys): both Test actions, and an automatic kitchen
/// send, serialize FIFO through the SAME shared gate + canonical destination key
/// used in production; different endpoints do not block each other; and each
/// Test keeps its own document/purpose.

/// A network tester that records call order + peak concurrency, optionally
/// blocking inside the gate until released.
class _NetTester implements NetworkPrinterTester {
  _NetTester({this.block});
  final Completer<void>? block;
  int calls = 0;
  int inFlight = 0;
  int maxInFlight = 0;
  final List<pp.PrintDocument?> documents = [];
  @override
  Future<pp.PrintResult> testPrint(
    NetworkPrinterConfig config, {
    String? deviceLabel,
    pp.PrintDocument? document,
  }) async {
    calls++;
    documents.add(document);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    if (block != null) await block!.future;
    inFlight--;
    return const pp.PrintResult.success();
  }
}

class _BtTester implements BluetoothPrinterTester {
  _BtTester({this.block});
  final Completer<void>? block;
  int calls = 0;
  int inFlight = 0;
  int maxInFlight = 0;
  @override
  Future<pp.PrintResult> testPrint(
    BluetoothPrinterConfig config, {
    String? deviceLabel,
    pp.PrintDocument? document,
  }) async {
    calls++;
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    if (block != null) await block!.future;
    inFlight--;
    return const pp.PrintResult.success();
  }
}

class _FakeBtConnector implements BluetoothPrinterConnector {
  @override
  bool get isSupported => true;
  @override
  Future<bool> ensurePermissions() async => true;
  @override
  Future<BluetoothPairedResult> pairedDevices() async =>
      const BluetoothPairedResult.ok([]);
  @override
  Future<pp.PrintResult> send({
    required String address,
    required Uint8List bytes,
    Duration timeout = const Duration(seconds: 6),
  }) async => const pp.PrintResult.success();
}

/// A blocking transport for the automatic-kitchen-send occupant.
class _BlockingTransport implements pp.PrintTransport {
  _BlockingTransport(this._release);
  final Completer<void> _release;
  int sends = 0;
  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    sends++;
    await _release.future;
    return const pp.PrintResult.success();
  }

  @override
  Future<void> dispose() async {}
}

Future<void> _pumpNet(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                NetworkPrinterSection(),
                NetworkPrinterSection(purpose: PosPrinterPurpose.kitchenTicket),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

CartLineView _line() => const CartLineView(
  lineId: 'l1',
  menuItemId: 'm1',
  name: 'Shawarma',
  quantity: 2,
  unitPriceMinor: 4500,
  lineTotalMinor: 9000,
  currencyCode: 'ILS',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  group('F4 network Test-send gate matrix', () {
    testWidgets(
      'customer Test + kitchen Test on the SAME endpoint serialize FIFO',
      (tester) async {
        final gate = pp.PrinterDestinationSendGate();
        final block = Completer<void>();
        final t = _NetTester(block: block);
        await _pumpNet(
          tester,
          overrides: [
            posNativePrintingAvailableProvider.overrideWithValue(true),
            posPrinterDestinationSendGateProvider.overrideWithValue(gate),
            networkPrinterTesterProvider.overrideWithValue(t),
          ],
        );
        await tester.enterText(
          find.byKey(const Key('network-printer-ip-field')),
          '10.0.0.9',
        );
        await tester.enterText(
          find.byKey(const Key('network-printer-ip-field-kitchen')),
          '10.0.0.9',
        );
        // Customer Test occupies the endpoint.
        await tester.tap(find.byKey(const Key('network-printer-test')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        expect(t.calls, 1);
        // Kitchen Test to the SAME endpoint is queued behind (FIFO).
        await tester.tap(find.byKey(const Key('network-printer-test-kitchen')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        expect(
          t.calls,
          1,
          reason: 'kitchen Test queued behind the customer Test',
        );
        expect(t.maxInFlight, 1);
        block.complete();
        await tester.pumpAndSettle();
        expect(t.calls, 2);
        expect(
          t.maxInFlight,
          1,
          reason: 'never concurrent — FIFO through one key',
        );
        // Each Test keeps its own document/purpose: customer = classic diagnostic
        // (null document), kitchen = the money-free kitchen test document.
        expect(t.documents[0], isNull);
        expect(t.documents[1], isNotNull);
      },
    );

    testWidgets('DIFFERENT endpoints do not block each other', (tester) async {
      final gate = pp.PrinterDestinationSendGate();
      final block = Completer<void>();
      final t = _NetTester(block: block);
      await _pumpNet(
        tester,
        overrides: [
          posNativePrintingAvailableProvider.overrideWithValue(true),
          posPrinterDestinationSendGateProvider.overrideWithValue(gate),
          networkPrinterTesterProvider.overrideWithValue(t),
        ],
      );
      await tester.enterText(
        find.byKey(const Key('network-printer-ip-field')),
        '10.0.0.1',
      );
      await tester.enterText(
        find.byKey(const Key('network-printer-ip-field-kitchen')),
        '10.0.0.9',
      );
      await tester.tap(find.byKey(const Key('network-printer-test')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('network-printer-test-kitchen')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      // Different keys → BOTH reach the tester concurrently (no cross-blocking).
      expect(t.calls, 2);
      expect(t.maxInFlight, 2, reason: 'different endpoints run independently');
      block.complete();
      await tester.pumpAndSettle();
    });
  });

  group('F4 Test + automatic kitchen send serialize on one endpoint', () {
    testWidgets(
      'a kitchen Test waits behind an in-flight AUTOMATIC kitchen send',
      (tester) async {
        final gate = pp.PrinterDestinationSendGate();
        // An automatic kitchen send occupies 10.0.0.9 (blocked).
        final release = Completer<void>();
        SharedPreferences.setMockInitialValues({
          'restoflow.printer.selected.pos.kitchen_ticket.local': 'network',
          'restoflow.printer.network.pos.kitchen_ticket.local': jsonEncode({
            'host': '10.0.0.9',
            'port': 9100,
          }),
        });
        final autoContainer = ProviderContainer(
          overrides: [
            posNativePrintingAvailableProvider.overrideWithValue(true),
            posPrinterDestinationSendGateProvider.overrideWithValue(gate),
            kitchenPrintTransportOverrideProvider.overrideWithValue(
              (_) => _BlockingTransport(release),
            ),
          ],
        );
        addTearDown(autoContainer.dispose);

        // The kitchen Test section shares the SAME gate + endpoint.
        final t = _NetTester();
        await _pumpNet(
          tester,
          overrides: [
            posNativePrintingAvailableProvider.overrideWithValue(true),
            posPrinterDestinationSendGateProvider.overrideWithValue(gate),
            networkPrinterTesterProvider.overrideWithValue(t),
          ],
        );

        // Fire the automatic kitchen send; pump so it reaches the (blocked)
        // transport and occupies the destination BEFORE the Test is tapped.
        final autoFuture = printKitchenTicketForOrder(
          container: autoContainer,
          input: kitchenTicketInputFromCartLines(
            orderCode: '#1',
            orderType: OrderType.dineIn,
            lines: [_line()],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));

        await tester.enterText(
          find.byKey(const Key('network-printer-ip-field-kitchen')),
          '10.0.0.9',
        );
        await tester.tap(find.byKey(const Key('network-printer-test-kitchen')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        expect(
          t.calls,
          0,
          reason: 'the Test waits behind the in-flight automatic kitchen send',
        );
        release.complete();
        await tester.pumpAndSettle();
        await autoFuture;
        expect(t.calls, 1, reason: 'the Test ran after the auto send (FIFO)');
      },
    );
  });

  group('F4 bluetooth Test-send gate matrix', () {
    testWidgets(
      'customer Test + kitchen Test on the SAME bluetooth endpoint serialize FIFO',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'restoflow.printer.bluetooth.pos.local': jsonEncode({
            'address': 'DC:0D:30:AA:BB:CC',
          }),
          'restoflow.printer.bluetooth.pos.kitchen_ticket.local': jsonEncode({
            'address': 'DC:0D:30:AA:BB:CC',
          }),
        });
        final gate = pp.PrinterDestinationSendGate();
        final block = Completer<void>();
        final t = _BtTester(block: block);
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              posNativePrintingAvailableProvider.overrideWithValue(true),
              posPrinterDestinationSendGateProvider.overrideWithValue(gate),
              bluetoothPrinterTesterProvider.overrideWithValue(t),
              bluetoothPrinterConnectorProvider.overrideWithValue(
                _FakeBtConnector(),
              ),
            ],
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: restoflowLocalizationsDelegates,
              supportedLocales: kSupportedLocales,
              home: const Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      BluetoothPrinterSection(),
                      BluetoothPrinterSection(
                        purpose: PosPrinterPurpose.kitchenTicket,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Both sections prefill their saved address → Test enabled.
        await tester.tap(find.byKey(const Key('bluetooth-test')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        expect(t.calls, 1);
        await tester.tap(find.byKey(const Key('bluetooth-test-kitchen')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        expect(
          t.calls,
          1,
          reason: 'kitchen BT Test queued behind customer (same MAC)',
        );
        expect(t.maxInFlight, 1);
        block.complete();
        await tester.pumpAndSettle();
        expect(t.calls, 2);
        expect(
          t.maxInFlight,
          1,
          reason: 'never concurrent — FIFO through one key',
        );
      },
    );
  });
}
