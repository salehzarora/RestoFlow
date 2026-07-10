import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/print/kds_native_printer.dart';
import 'package:restoflow_kds/src/print/kds_ticket_document.dart';
import 'package:restoflow_kds/src/print/print_document.dart';
import 'package:restoflow_kds/src/state/kds_auto_print_prefs.dart';
import 'package:restoflow_kds/src/state/kds_kitchen_print_controller.dart';
import 'package:restoflow_kds/src/state/kds_printer_assignments.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

/// ANDROID-004: the KDS wires its kitchen-ticket print trigger to the SHARED
/// native printing layer. The active-bridge resolver picks the native local
/// printer when configured (else the loopback bridge); a native printer prints
/// even without a server assignment; the payload stays MONEY-FREE (T-003); and
/// web KDS never selects a native transport.

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

/// A failed assignment read == the demo / unconfigured / failed path (no server
/// kitchen-printer). ANDROID-004 must still print to a device-local printer.
class _FailReader implements DevicePrinterAssignmentsReader {
  @override
  Future<Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>>
  load() async => const Failure(DevicePrinterAssignmentsFailure.network);
}

KdsTicketView _ticket() => KdsTicketView(
  kitchenTicketId: 'kt-1',
  stationId: 'grill',
  orderId: 'o1',
  orderNumber: '#3F7A2C',
  orderType: 'dine_in',
  tableLabel: 'T2',
  notes: 'rush order',
  items: [
    KdsItemView(
      name: 'برجر كلاسيك',
      quantity: 1,
      modifiers: const ['وسط', 'جبنة إضافية ×2'],
      note: 'بدون بصل',
    ),
  ],
  status: KitchenTicketStatus.acknowledged,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  group('kdsActivePrintBridgeProvider (transport resolver)', () {
    test('a configured native transport -> a NativeKdsPrintBridge', () {
      final c = ProviderContainer(
        overrides: [
          activeNativeTransportFactoryProvider.overrideWithValue(
            () => _FakeTransport(const pp.PrintResult.success()),
          ),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(kdsActivePrintBridgeProvider), isA<NativeKdsPrintBridge>());
    });

    test('no native transport -> falls back to the loopback bridge (null)', () {
      final c = ProviderContainer(
        overrides: [
          activeNativeTransportFactoryProvider.overrideWithValue(null),
        ],
      );
      addTearDown(c.dispose);
      // The loopback kdsPrintBridgeProvider is null by default (dormant).
      expect(c.read(kdsActivePrintBridgeProvider), isNull);
    });
  });

  group('NativeKdsPrintBridge', () {
    test('encodes the kitchen ticket + delivers it as sentToPrinter', () async {
      final l10n = await _en();
      final transport = _FakeTransport(const pp.PrintResult.success());
      final bridge = NativeKdsPrintBridge(
        NativeEscPosSender(transportFactory: () => transport),
      );
      final result = await bridge.submit(
        buildKdsTicketDocument(l10n, _ticket()),
      );
      expect(result.outcome, pp.BridgeSubmitOutcome.sentToPrinter);
      expect(transport.sent, isNotNull); // real ESC/POS bytes were encoded
    });
  });

  group('prepareOnAcknowledge with a device-local native printer', () {
    test('prints via the native bridge even with NO server assignment, and the '
        'payload is money-free', () async {
      final l10n = await _en();
      final transport = _FakeTransport(const pp.PrintResult.success());
      final bridge = NativeKdsPrintBridge(
        NativeEscPosSender(transportFactory: () => transport),
      );
      final c = ProviderContainer(
        overrides: [
          // A FAILED assignment read == the demo/unconfigured path.
          kdsPrinterAssignmentsReaderProvider.overrideWithValue(_FailReader()),
        ],
      );
      addTearDown(c.dispose);
      await c.read(kdsPrinterAssignmentsProvider.future);
      await c.read(kdsAutoPrintAcknowledgeProvider.future);
      final controller = c.read(kdsKitchenPrintControllerProvider.notifier);

      await controller.prepareOnAcknowledge(
        _ticket(),
        buildDocument: () => buildKdsTicketDocument(l10n, _ticket()),
        submitToBridge: bridge.submit,
        nativePrinterConfigured: true,
      );

      final job = controller.jobFor(_ticket())!;
      expect(job.status, KdsPrintJobStatus.sentToPrinter);
      expect(job.status, isNot(KdsPrintJobStatus.printed));
      expect(transport.sent, isNotNull);
      // Money-free (T-003): the kitchen payload never carries any money.
      final html = documentToHtml(job.document!);
      expect(html.contains('₪'), isFalse);
      expect(html.toLowerCase().contains('minor'), isFalse);
    });

    test('WITHOUT a native printer (default) + no assignment -> nothing '
        '(prior behavior preserved)', () async {
      final c = ProviderContainer(
        overrides: [
          kdsPrinterAssignmentsReaderProvider.overrideWithValue(_FailReader()),
        ],
      );
      addTearDown(c.dispose);
      await c.read(kdsPrinterAssignmentsProvider.future);
      await c.read(kdsAutoPrintAcknowledgeProvider.future);
      final controller = c.read(kdsKitchenPrintControllerProvider.notifier);

      await controller.prepareOnAcknowledge(
        _ticket(),
        buildDocument: () => throw 'never built',
      );

      expect(controller.jobFor(_ticket()), isNull);
    });
  });

  group('KDS printer settings section (shared UI + KDS labels)', () {
    testWidgets('renders the transport toggle + network fields, and switches '
        'to the Bluetooth pair hint', (tester) async {
      final l10n = await _en();
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
            home: Scaffold(
              body: SingleChildScrollView(
                child: NativePrinterSettingsSection(
                  strings: kdsNativePrinterStrings(l10n),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('printer-transport-toggle')), findsOneWidget);
      expect(find.byKey(const Key('network-printer-section')), findsOneWidget);
      expect(find.byKey(const Key('network-printer-ip-field')), findsOneWidget);
      // The KDS-specific test-print label is wired through.
      expect(find.text(l10n.kdsPrinterTestPrint), findsWidgets);

      await tester.tap(find.text(l10n.kdsPrinterTransportBluetooth));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('bluetooth-printer-section')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('network-printer-section')), findsNothing);
    });

    // PRINT-BLUETOOTH-RECOVERY-001: a failed KDS Bluetooth test print reports
    // WHAT failed — not one generic "print failed" for everything — and shows
    // the raw diagnostic on a small secondary line. Success stays success.
    testWidgets('Bluetooth test-print failures map to category-specific '
        'messages; success clears them (money-free)', (tester) async {
      final l10n = await _en();
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final flaky = _ScriptedBtTester([
        const pp.PrintResult.failure(
          pp.PrinterErrorCategory.notPaired,
          'device AA is not paired/bonded',
        ),
        const pp.PrintResult.failure(
          pp.PrinterErrorCategory.unreachable,
          'secure: timed out; insecure: timed out',
        ),
        const pp.PrintResult.success(),
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bluetoothPrinterConnectorProvider.overrideWithValue(
              _PairedBtConnector(),
            ),
            bluetoothPrinterTesterProvider.overrideWithValue(flaky),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: NativePrinterSettingsSection(
                  strings: kdsNativePrinterStrings(l10n),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.kdsPrinterTransportBluetooth));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('bluetooth-device-AA:BB:CC:DD:EE:FF')),
      );
      await tester.pumpAndSettle();

      // 1st: not paired -> the pair-again guidance (NOT the generic failure).
      await tester.tap(find.byKey(const Key('bluetooth-test')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.posBluetoothNotPaired), findsOneWidget);
      expect(find.text(l10n.kdsPrinterPrintFailed), findsNothing);
      expect(find.byKey(const Key('bluetooth-failure-detail')), findsOneWidget);

      // 2nd: connect failure -> the Bluetooth connect copy (distinct from the
      // Wi-Fi failure copy).
      await tester.tap(find.byKey(const Key('bluetooth-test')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.posBluetoothConnectFailed), findsOneWidget);

      // 3rd: success -> success copy; every stale failure/message is gone.
      await tester.tap(find.byKey(const Key('bluetooth-test')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.kdsPrinterTicketSent), findsOneWidget);
      expect(find.text(l10n.posBluetoothConnectFailed), findsNothing);
      expect(find.byKey(const Key('bluetooth-failure-detail')), findsNothing);
      // The KDS settings surface stays money-free (T-003).
      expect(find.textContaining('₪'), findsNothing);
    });
  });
}

/// A connector with one bonded printer (for selecting in the shared section).
class _PairedBtConnector implements BluetoothPrinterConnector {
  @override
  bool get isSupported => true;
  @override
  Future<bool> ensurePermissions() async => true;
  @override
  Future<BluetoothPairedResult> pairedDevices() async =>
      const BluetoothPairedResult.ok([
        BluetoothDeviceInfo(address: 'AA:BB:CC:DD:EE:FF', name: 'Printer001'),
      ]);
  @override
  Future<pp.PrintResult> send({
    required String address,
    required Uint8List bytes,
    Duration timeout = const Duration(seconds: 8),
  }) async => const pp.PrintResult.success();
}

/// Returns scripted results in order (the last repeats).
class _ScriptedBtTester implements BluetoothPrinterTester {
  _ScriptedBtTester(this.results);
  final List<pp.PrintResult> results;
  int calls = 0;
  @override
  Future<pp.PrintResult> testPrint(
    BluetoothPrinterConfig config, {
    String? deviceLabel,
  }) async {
    final result = results[calls < results.length ? calls : results.length - 1];
    calls++;
    return result;
  }
}
