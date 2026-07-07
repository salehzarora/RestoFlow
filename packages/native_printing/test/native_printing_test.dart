import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

/// ANDROID-004: the SHARED native printing layer reused by POS + KDS. Config
/// models + host validation, the device+namespace-scoped config store, the
/// transport resolver (web-safe: never native off Android), and the honest
/// ESC/POS send path. Money-free: no test builds or asserts any money value.

/// A fake transport that records the sent bytes and returns a canned result.
class _FakeTransport implements pp.PrintTransport {
  _FakeTransport(this.result);
  final pp.PrintResult result;
  Uint8List? sent;
  int disposed = 0;
  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    sent = bytes;
    return result;
  }

  @override
  Future<void> dispose() async => disposed++;
}

/// A fake Bluetooth connector (no real Bluetooth in tests).
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
    Duration timeout = const Duration(seconds: 8),
  }) async => const pp.PrintResult.success();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  group('config models', () {
    test('NetworkPrinterConfig round-trips + defaults the port to 9100', () {
      const c = NetworkPrinterConfig(host: '192.168.1.50', name: 'Kitchen');
      expect(c.port, 9100);
      final back = NetworkPrinterConfig.fromJson(c.toJson());
      expect(back?.host, '192.168.1.50');
      expect(back?.port, 9100);
      expect(back?.name, 'Kitchen');
    });

    test('NetworkPrinterConfig.fromJson rejects a blank host / bad port', () {
      expect(NetworkPrinterConfig.fromJson(const {'host': ''}), isNull);
      expect(
        NetworkPrinterConfig.fromJson(const {'host': 'x', 'port': 0}),
        isNull,
      );
      expect(
        NetworkPrinterConfig.fromJson(const {'host': 'x', 'port': 99999}),
        isNull,
      );
    });

    test('BluetoothPrinterConfig round-trips + rejects a blank address', () {
      const c = BluetoothPrinterConfig(address: 'DC:0D:30:AA:BB:CC');
      expect(BluetoothPrinterConfig.fromJson(c.toJson())?.address, c.address);
      expect(BluetoothPrinterConfig.fromJson(const {'address': ' '}), isNull);
    });

    test('isValidPrinterHost accepts IPv4/hostnames, rejects junk', () {
      expect(isValidPrinterHost('192.168.1.50'), isTrue);
      expect(isValidPrinterHost('printer-1.local'), isTrue);
      expect(isValidPrinterHost('999.1'), isFalse);
      expect(isValidPrinterHost('has space'), isFalse);
      expect(isValidPrinterHost(''), isFalse);
    });
  });

  group('device+namespace-scoped config store', () {
    test('reads/writes under restoflow.printer.<kind>.<ns>.<device>', () async {
      SharedPreferences.setMockInitialValues({
        'restoflow.printer.network.kds.dev-9': jsonEncode(const {
          'host': '10.0.0.5',
          'port': 9100,
        }),
      });
      final c = ProviderContainer(
        overrides: [
          nativePrinterNamespaceProvider.overrideWithValue('kds'),
          nativePrinterDeviceIdProvider.overrideWithValue('dev-9'),
        ],
      );
      addTearDown(c.dispose);
      final loaded = await c.read(networkPrinterConfigProvider.future);
      expect(loaded?.host, '10.0.0.5');

      await c
          .read(networkPrinterConfigProvider.notifier)
          .save(const NetworkPrinterConfig(host: '10.0.0.9', port: 9100));
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(
          prefs.getString('restoflow.printer.network.kds.dev-9')!,
        )['host'],
        '10.0.0.9',
      );
    });

    test('no device id falls back to the stable `local` segment', () async {
      final c = ProviderContainer(
        overrides: [nativePrinterNamespaceProvider.overrideWithValue('kds')],
      );
      addTearDown(c.dispose);
      await c
          .read(bluetoothPrinterConfigProvider.notifier)
          .save(const BluetoothPrinterConfig(address: 'AA:BB:CC:DD:EE:FF'));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('restoflow.printer.bluetooth.kds.local'),
        isNotNull,
      );
    });
  });

  group('NativeEscPosSender', () {
    test(
      'maps a delivered transport write to sentToPrinter + disposes',
      () async {
        final transport = _FakeTransport(const pp.PrintResult.success());
        final sender = NativeEscPosSender(transportFactory: () => transport);
        final result = await sender.send(
          pp.PrintDocument(const [pp.PrintTextLine('KITCHEN')]),
        );
        expect(result.outcome, pp.BridgeSubmitOutcome.sentToPrinter);
        expect(transport.sent, isNotNull); // real ESC/POS bytes were encoded
        expect(transport.disposed, 1);
      },
    );

    test(
      'maps a transport failure to failed + preserves the category',
      () async {
        final sender = NativeEscPosSender(
          transportFactory: () => _FakeTransport(
            const pp.PrintResult.failure(pp.PrinterErrorCategory.unreachable),
          ),
        );
        final result = await sender.send(pp.PrintDocument(const []));
        expect(result.outcome, pp.BridgeSubmitOutcome.failed);
        expect(result.category, pp.PrinterErrorCategory.unreachable);
      },
    );
  });

  group('transport resolver + hasNativePrinter', () {
    Future<ProviderContainer> container({
      required bool native,
      required PrinterTransportKind selected,
      NetworkPrinterConfig? network,
      BluetoothPrinterConfig? bluetooth,
    }) async {
      SharedPreferences.setMockInitialValues({
        'restoflow.printer.selected.test.local': selected.name,
        if (network != null)
          'restoflow.printer.network.test.local': jsonEncode(network.toJson()),
        if (bluetooth != null)
          'restoflow.printer.bluetooth.test.local': jsonEncode(
            bluetooth.toJson(),
          ),
      });
      final c = ProviderContainer(
        overrides: [
          nativePrinterNamespaceProvider.overrideWithValue('test'),
          nativePrintingAvailableProvider.overrideWithValue(native),
          bluetoothPrinterConnectorProvider.overrideWithValue(
            _FakeBtConnector(),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(selectedPrinterTransportProvider.future);
      await c.read(networkPrinterConfigProvider.future);
      await c.read(bluetoothPrinterConfigProvider.future);
      return c;
    }

    test('native + network configured -> a TCP transport factory', () async {
      final c = await container(
        native: true,
        selected: PrinterTransportKind.network,
        network: const NetworkPrinterConfig(host: '192.168.1.50'),
      );
      final factory = c.read(activeNativeTransportFactoryProvider);
      expect(factory, isNotNull);
      expect(factory!(), isA<pp.NetworkTcpPrintTransport>());
      expect(c.read(hasNativePrinterProvider), isTrue);
    });

    test(
      'native + bluetooth configured -> a Bluetooth transport factory',
      () async {
        final c = await container(
          native: true,
          selected: PrinterTransportKind.bluetooth,
          bluetooth: const BluetoothPrinterConfig(address: 'DC:0D:30:AA:BB:CC'),
        );
        final factory = c.read(activeNativeTransportFactoryProvider);
        expect(factory, isNotNull);
        expect(factory!(), isA<BluetoothClassicPrintTransport>());
        expect(c.read(hasNativePrinterProvider), isTrue);
      },
    );

    test(
      'native but nothing configured -> null (job stays prepared)',
      () async {
        final c = await container(
          native: true,
          selected: PrinterTransportKind.network,
        );
        expect(c.read(activeNativeTransportFactoryProvider), isNull);
        expect(c.read(hasNativePrinterProvider), isFalse);
      },
    );

    test(
      'WEB (not native) -> null even with a saved config (no native path)',
      () async {
        final c = await container(
          native: false,
          selected: PrinterTransportKind.network,
          network: const NetworkPrinterConfig(host: '192.168.1.50'),
        );
        expect(c.read(activeNativeTransportFactoryProvider), isNull);
        expect(c.read(hasNativePrinterProvider), isFalse);
      },
    );
  });
}
