import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:restoflow_pos/src/print/bluetooth_printer.dart';
import 'package:restoflow_pos/src/print/bluetooth_printer_tester.dart';
import 'package:restoflow_pos/src/print/native_print_bridges.dart';
import 'package:restoflow_pos/src/print/print_bridge.dart'
    show posPrintBridgeProvider;
import 'package:restoflow_pos/src/print/print_document.dart' as app;
import 'package:restoflow_pos/src/state/pos_bluetooth_printer_config.dart';
import 'package:restoflow_pos/src/state/pos_network_printer_config.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';
import 'package:restoflow_pos/src/widgets/bluetooth_printer_section.dart';
import 'package:restoflow_pos/src/widgets/printer_settings_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ANDROID-003: native POS printing — the transport resolver routes receipts to
/// the configured network/Bluetooth printer, the native bridge maps outcomes
/// honestly, and the UI drives the config. Web-safe: the resolver never picks a
/// native transport off Android.

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

/// A fake transport that records the sent bytes and returns a canned result.
class _FakeTransport implements pp.PrintTransport {
  _FakeTransport(this.result);
  final pp.PrintResult result;
  Uint8List? sent;
  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    sent = bytes;
    return result;
  }

  @override
  Future<void> dispose() async {}
}

/// A fake Bluetooth connector for widget/unit tests (no real Bluetooth).
class _FakeBtConnector implements BluetoothPrinterConnector {
  _FakeBtConnector({this.paired = const BluetoothPairedResult.ok([])});
  final BluetoothPairedResult paired;
  String? lastAddress;
  Uint8List? lastBytes;

  @override
  bool get isSupported => true;
  @override
  Future<bool> ensurePermissions() async => true;
  @override
  Future<BluetoothPairedResult> pairedDevices() async => paired;
  @override
  Future<pp.PrintResult> send({
    required String address,
    required Uint8List bytes,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    lastAddress = address;
    lastBytes = bytes;
    return const pp.PrintResult.success();
  }
}

class _FakeBtTester implements BluetoothPrinterTester {
  _FakeBtTester(this.result);
  final pp.PrintResult result;
  int calls = 0;
  PosBluetoothPrinterConfig? lastConfig;
  @override
  Future<pp.PrintResult> testPrint(
    PosBluetoothPrinterConfig config, {
    String? deviceLabel,
  }) async {
    calls++;
    lastConfig = config;
    return result;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  group('NativeTransportPrintBridge', () {
    test('maps a delivered transport write to sentToPrinter', () async {
      final transport = _FakeTransport(const pp.PrintResult.success());
      final bridge = NativeTransportPrintBridge(
        transportFactory: () => transport,
      );
      final result = await bridge.submit(
        app.PrintDocument(
          title: 'r',
          lines: [app.PrintLine.title('RestoFlow')],
        ),
      );
      expect(result.outcome, pp.BridgeSubmitOutcome.sentToPrinter);
      expect(transport.sent, isNotNull); // real ESC/POS bytes were encoded
    });

    test('maps a transport failure to a failed outcome + category', () async {
      final bridge = NativeTransportPrintBridge(
        transportFactory: () => _FakeTransport(
          const pp.PrintResult.failure(pp.PrinterErrorCategory.unreachable),
        ),
      );
      final result = await bridge.submit(
        app.PrintDocument(title: 'r', lines: const []),
      );
      expect(result.outcome, pp.BridgeSubmitOutcome.failed);
      expect(result.category, pp.PrinterErrorCategory.unreachable);
    });
  });

  group('BluetoothClassicPrintTransport', () {
    test('delegates the send to the connector for the address', () async {
      final connector = _FakeBtConnector();
      final transport = BluetoothClassicPrintTransport(
        connector: connector,
        address: 'DC:0D:30:AA:BB:CC',
      );
      final result = await transport.send(Uint8List.fromList([1, 2, 3]));
      expect(result.ok, isTrue);
      expect(connector.lastAddress, 'DC:0D:30:AA:BB:CC');
      expect(connector.lastBytes, [1, 2, 3]);
    });
  });

  group('posActivePrintBridgeProvider (transport resolver)', () {
    Future<ProviderContainer> container({
      required bool native,
      required PosPrinterTransportKind selected,
      PosNetworkPrinterConfig? network,
      PosBluetoothPrinterConfig? bluetooth,
    }) async {
      SharedPreferences.setMockInitialValues({
        '${kPosPrinterTransportKeyPrefix}local': selected.name,
        if (network != null)
          '${kPosNetworkPrinterKeyPrefix}local': jsonEncode(network.toJson()),
        if (bluetooth != null)
          '${kPosBluetoothPrinterKeyPrefix}local': jsonEncode(
            bluetooth.toJson(),
          ),
      });
      final c = ProviderContainer(
        overrides: [
          posNativePrintingAvailableProvider.overrideWithValue(native),
          bluetoothPrinterConnectorProvider.overrideWithValue(
            _FakeBtConnector(),
          ),
        ],
      );
      addTearDown(c.dispose);
      // Resolve the async configs so the sync resolver sees their values.
      await c.read(posSelectedPrinterTransportProvider.future);
      await c.read(posNetworkPrinterConfigProvider.future);
      await c.read(posBluetoothPrinterConfigProvider.future);
      return c;
    }

    test(
      'network selected + configured -> a native bridge is active',
      () async {
        final c = await container(
          native: true,
          selected: PosPrinterTransportKind.network,
          network: const PosNetworkPrinterConfig(host: '192.168.1.50'),
        );
        expect(
          c.read(posActivePrintBridgeProvider),
          isA<NativeTransportPrintBridge>(),
        );
        expect(c.read(posHasNativePrinterProvider), isTrue);
      },
    );

    test(
      'bluetooth selected + configured -> a native bridge is active',
      () async {
        final c = await container(
          native: true,
          selected: PosPrinterTransportKind.bluetooth,
          bluetooth: const PosBluetoothPrinterConfig(
            address: 'DC:0D:30:AA:BB:CC',
          ),
        );
        expect(
          c.read(posActivePrintBridgeProvider),
          isA<NativeTransportPrintBridge>(),
        );
        expect(c.read(posHasNativePrinterProvider), isTrue);
      },
    );

    test('native but nothing configured -> falls back to the loopback bridge '
        '(null by default), no native printer', () async {
      final c = await container(
        native: true,
        selected: PosPrinterTransportKind.network,
      );
      expect(c.read(posActivePrintBridgeProvider), isNull);
      expect(c.read(posHasNativePrinterProvider), isFalse);
    });

    test('WEB (not native) -> the print-bridge path only; never a native '
        'transport, even with a saved config', () async {
      final c = await container(
        native: false,
        selected: PosPrinterTransportKind.network,
        network: const PosNetworkPrinterConfig(host: '192.168.1.50'),
      );
      // On web the resolver returns posPrintBridgeProvider (null here) — the
      // bridge path is unchanged; a native transport is NEVER chosen.
      expect(c.read(posActivePrintBridgeProvider), isNull);
      expect(
        c.read(posActivePrintBridgeProvider),
        c.read(posPrintBridgeProvider),
      );
      expect(c.read(posHasNativePrinterProvider), isFalse);
    });
  });

  group('Bluetooth printer section UI', () {
    Future<void> pump(
      WidgetTester tester, {
      required BluetoothPrinterConnector connector,
      BluetoothPrinterTester? tester_,
    }) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bluetoothPrinterConnectorProvider.overrideWithValue(connector),
            if (tester_ != null)
              bluetoothPrinterTesterProvider.overrideWithValue(tester_),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const Scaffold(
              body: SingleChildScrollView(child: BluetoothPrinterSection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists paired devices; selecting + Save persists the printer', (
      tester,
    ) async {
      final connector = _FakeBtConnector(
        paired: const BluetoothPairedResult.ok([
          BluetoothDeviceInfo(address: 'DC:0D:30:AA:BB:CC', name: 'POS-58'),
        ]),
      );
      final fakeTester = _FakeBtTester(pp.PrintResult.success());
      await pump(tester, connector: connector, tester_: fakeTester);

      expect(find.text('POS-58'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('bluetooth-device-DC:0D:30:AA:BB:CC')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bluetooth-save')));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('${kPosBluetoothPrinterKeyPrefix}local');
      expect(raw, isNotNull);
      expect(jsonDecode(raw!)['address'], 'DC:0D:30:AA:BB:CC');
    });

    testWidgets('Test print delegates to the tester', (tester) async {
      final connector = _FakeBtConnector(
        paired: const BluetoothPairedResult.ok([
          BluetoothDeviceInfo(address: 'AA:BB:CC:DD:EE:FF', name: 'Printer'),
        ]),
      );
      final fakeTester = _FakeBtTester(pp.PrintResult.success());
      await pump(tester, connector: connector, tester_: fakeTester);

      await tester.tap(
        find.byKey(const Key('bluetooth-device-AA:BB:CC:DD:EE:FF')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bluetooth-test')));
      await tester.pumpAndSettle();

      expect(fakeTester.calls, 1);
      expect(fakeTester.lastConfig?.address, 'AA:BB:CC:DD:EE:FF');
    });

    testWidgets('permission denied shows the localized recovery message', (
      tester,
    ) async {
      final l10n = await _en();
      await pump(
        tester,
        connector: _FakeBtConnector(
          paired: const BluetoothPairedResult.failed(
            BluetoothPrinterError.permissionDenied,
          ),
        ),
      );
      expect(find.text(l10n.posBluetoothPermissionRequired), findsOneWidget);
    });

    testWidgets('no paired devices shows the pair-first hint', (tester) async {
      final l10n = await _en();
      await pump(
        tester,
        connector: _FakeBtConnector(paired: const BluetoothPairedResult.ok([])),
      );
      expect(find.text(l10n.posBluetoothNoDevices), findsOneWidget);
    });
  });

  group('PrinterSettingsSection transport toggle', () {
    testWidgets('shows the toggle + the network section by default, and '
        'switches to the Bluetooth section', (tester) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bluetoothPrinterConnectorProvider.overrideWithValue(
              _FakeBtConnector(),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const Scaffold(
              body: SingleChildScrollView(child: PrinterSettingsSection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('printer-transport-toggle')), findsOneWidget);
      // Default: the network section is shown.
      expect(find.byKey(const Key('network-printer-section')), findsOneWidget);
      expect(find.byKey(const Key('bluetooth-printer-section')), findsNothing);

      // Switch to Bluetooth.
      final l10n = await _en();
      await tester.tap(find.text(l10n.posPrinterTransportBluetooth));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('bluetooth-printer-section')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('network-printer-section')), findsNothing);
    });
  });
}
