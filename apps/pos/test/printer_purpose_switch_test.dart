// KITCHEN-MODE-001B correction — purpose-switch state isolation + REAL
// test-print paths, driven through the ACTUAL PrinterSettingsSection UI.
//
// Review HIGH: the stateful transport sections used to keep the previous
// purpose's controllers/selection when the purpose switched (same State
// reused), so the customer endpoint could linger in — and be saved into — the
// kitchen slot. These tests pin the fix (purpose-specific keys + fallbacks):
//
//   * network: customer shows A, kitchen shows B, immediately, both ways;
//     an EMPTY kitchen slot shows EMPTY fields (never the customer endpoint);
//     saving after a switch writes only the visible purpose's slot;
//   * bluetooth: per-purpose saved device shown; stale selection/status reset;
//   * the RECORDED test-print calls prove which endpoint + which document each
//     purpose used: customer = the historical diagnostic (document == null),
//     kitchen = the REAL escPosKitchenTestDocument built by the production
//     action — STRUCTURALLY money-free (line-by-line, plus token scan);
//   * copy stays an explicit one-time action; receipt paths still resolve the
//     customer slot only.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:restoflow_pos/src/state/pos_network_printer_config.dart';
import 'package:restoflow_pos/src/state/pos_printer_purpose.dart';
import 'package:restoflow_pos/src/widgets/printer_settings_section.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

/// One recorded test-print invocation (test-only; nothing is logged anywhere).
class RecordedTestPrint {
  RecordedTestPrint({
    required this.transport,
    required this.endpoint,
    required this.document,
  });

  final String transport; // 'network' | 'bluetooth'
  final String endpoint; // host:port or BT address
  final pp.PrintDocument? document; // null = the historical diagnostic path
}

class _RecordingNetworkTester implements NetworkPrinterTester {
  final List<RecordedTestPrint> calls = [];

  @override
  Future<pp.PrintResult> testPrint(
    NetworkPrinterConfig config, {
    String? deviceLabel,
    pp.PrintDocument? document,
  }) async {
    calls.add(
      RecordedTestPrint(
        transport: 'network',
        endpoint: '${config.host}:${config.port}',
        document: document,
      ),
    );
    return pp.PrintResult.success();
  }
}

class _RecordingBtTester implements BluetoothPrinterTester {
  final List<RecordedTestPrint> calls = [];

  @override
  Future<pp.PrintResult> testPrint(
    BluetoothPrinterConfig config, {
    String? deviceLabel,
    pp.PrintDocument? document,
  }) async {
    calls.add(
      RecordedTestPrint(
        transport: 'bluetooth',
        endpoint: config.address,
        document: document,
      ),
    );
    return pp.PrintResult.success();
  }
}

class _FakeBtConnector implements BluetoothPrinterConnector {
  _FakeBtConnector(this.paired);
  final BluetoothPairedResult paired;

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
  }) async => pp.PrintResult.success();
}

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

String _netJson(String host, {int port = 9100, String? name}) =>
    jsonEncode({'host': host, 'port': port, if (name != null) 'name': name});

String _btJson(String address, {String? name}) =>
    jsonEncode({'address': address, if (name != null) 'name': name});

Future<void> _pump(
  WidgetTester tester, {
  required _RecordingNetworkTester netTester,
  _RecordingBtTester? btTester,
  _FakeBtConnector? connector,
}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        networkPrinterTesterProvider.overrideWithValue(netTester),
        if (btTester != null)
          bluetoothPrinterTesterProvider.overrideWithValue(btTester),
        if (connector != null)
          bluetoothPrinterConnectorProvider.overrideWithValue(connector),
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
}

Future<void> _switchToKitchen(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  await tester.tap(find.text(l10n.posPrinterPurposeKitchen));
  await tester.pumpAndSettle();
}

Future<void> _switchToCustomer(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  await tester.tap(find.text(l10n.posPrinterPurposeCustomer));
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String _ipFieldText(WidgetTester tester, {required bool kitchen}) {
  final key = Key(
    kitchen ? 'network-printer-ip-field-kitchen' : 'network-printer-ip-field',
  );
  return tester.widget<TextField>(find.byKey(key)).controller!.text;
}

/// STRUCTURAL money-free proof over the ACTUAL production-built document:
/// every text line is inspected — no price/subtotal/total/paid/change rows, no
/// currency, no payment method, no customer or order data can hide in it,
/// because the ONLY lines present are the known TEST banner/title/sample/
/// separator/context lines. Token scanning is kept as defence-in-depth.
void _assertKitchenTestDocumentMoneyFree(
  pp.PrintDocument document,
  AppLocalizations l10n, {
  Set<String> allowedContext = const {},
}) {
  final texts = [
    for (final line in document.lines)
      if (line is pp.PrintTextLine) line.text,
  ];
  expect(texts, contains(l10n.posKitchenTestBanner));
  expect(texts, contains(l10n.posKitchenTestTitle));
  expect(texts, contains(l10n.posKitchenTestSampleItem));
  expect(texts, contains(l10n.posKitchenTestSampleModifier));
  expect(texts, contains(l10n.posKitchenTestSampleNote));
  // CLOSED-WORLD structure: nothing outside the known money-free line set.
  final allowed = <String>{
    l10n.posKitchenTestBanner,
    l10n.posKitchenTestTitle,
    l10n.posKitchenTestSampleItem,
    l10n.posKitchenTestSampleModifier,
    l10n.posKitchenTestSampleNote,
    '------------------------------',
    // Declared printer/device context names only (still money-free).
    ...allowedContext,
  };
  for (final text in texts) {
    expect(
      allowed.contains(text) || text.isEmpty,
      isTrue,
      reason:
          'unexpected line in the kitchen TEST document: "$text" — only the '
          'known money-free sample/banner lines (plus optional printer/device '
          'context names) may appear; a price/total/currency/customer row '
          'here is a P0 failure',
    );
  }
  // Defence-in-depth token scan.
  final joined = texts.join('\n').toLowerCase();
  for (final forbidden in [
    '₪',
    'total',
    'paid',
    'change',
    'subtotal',
    'ils',
    'usd',
    'eur',
    'price',
    'amount',
    'cash',
    'card',
  ]) {
    expect(
      joined.contains(forbidden),
      isFalse,
      reason: 'kitchen TEST document must never contain "$forbidden"',
    );
  }
}

void main() {
  group('network purpose isolation (review HIGH)', () {
    testWidgets('customer shows A, kitchen shows B IMMEDIATELY, both ways; '
        'an empty kitchen slot shows EMPTY fields', (tester) async {
      final l10n = await _en();
      SharedPreferences.setMockInitialValues({
        'restoflow.printer.network.pos.local': _netJson('10.0.0.1', name: 'A'),
        'restoflow.printer.network.pos.kitchen_ticket.local': _netJson(
          '10.0.0.2',
          name: 'B',
        ),
      });
      final net = _RecordingNetworkTester();
      await _pump(tester, netTester: net);

      // Customer purpose (default): endpoint A.
      expect(_ipFieldText(tester, kitchen: false), '10.0.0.1');

      // Switch to kitchen: endpoint B is shown IMMEDIATELY — never A.
      await _switchToKitchen(tester, l10n);
      expect(_ipFieldText(tester, kitchen: true), '10.0.0.2');

      // Switch back: A is restored.
      await _switchToCustomer(tester, l10n);
      expect(_ipFieldText(tester, kitchen: false), '10.0.0.1');

      // And kitchen again: still B (kitchen -> customer -> kitchen).
      await _switchToKitchen(tester, l10n);
      expect(_ipFieldText(tester, kitchen: true), '10.0.0.2');
    });

    testWidgets('an EMPTY kitchen slot never inherits the customer endpoint '
        '(the exact reviewed leak)', (tester) async {
      final l10n = await _en();
      SharedPreferences.setMockInitialValues({
        'restoflow.printer.network.pos.local': _netJson('10.0.0.1', name: 'A'),
        // kitchen slot deliberately UNSET.
      });
      final net = _RecordingNetworkTester();
      await _pump(tester, netTester: net);
      expect(_ipFieldText(tester, kitchen: false), '10.0.0.1');

      await _switchToKitchen(tester, l10n);
      // Pre-fix this showed '10.0.0.1' — and Save would have written the
      // customer endpoint into the kitchen slot.
      expect(_ipFieldText(tester, kitchen: true), isEmpty);
      // Nothing was written to either slot by merely switching tabs.
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('restoflow.printer.network.pos.kitchen_ticket.local'),
        isNull,
      );
      expect(
        jsonDecode(
          prefs.getString('restoflow.printer.network.pos.local')!,
        )['host'],
        '10.0.0.1',
      );
    });

    testWidgets('saving after a switch updates ONLY the visible purpose; '
        'clearing kitchen never clears customer', (tester) async {
      final l10n = await _en();
      SharedPreferences.setMockInitialValues({
        'restoflow.printer.network.pos.local': _netJson('10.0.0.1'),
        'restoflow.printer.network.pos.kitchen_ticket.local': _netJson(
          '10.0.0.2',
        ),
      });
      final net = _RecordingNetworkTester();
      await _pump(tester, netTester: net);

      await _switchToKitchen(tester, l10n);
      await tester.enterText(
        find.byKey(const Key('network-printer-ip-field-kitchen')),
        '10.0.0.99',
      );
      await _tapKey(tester, 'network-printer-save-kitchen');

      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(
          prefs.getString(
            'restoflow.printer.network.pos.kitchen_ticket.local',
          )!,
        )['host'],
        '10.0.0.99',
      );
      expect(
        jsonDecode(
          prefs.getString('restoflow.printer.network.pos.local')!,
        )['host'],
        '10.0.0.1',
      );

      // Back on customer: A is still shown and still stored.
      await _switchToCustomer(tester, l10n);
      expect(_ipFieldText(tester, kitchen: false), '10.0.0.1');
    });
  });

  group('REAL test-print paths per purpose (review MEDIUM)', () {
    testWidgets('network: customer test uses endpoint A + the historical '
        'diagnostic (document == null); kitchen test uses endpoint B + the '
        'REAL money-free kitchen document', (tester) async {
      final l10n = await _en();
      SharedPreferences.setMockInitialValues({
        'restoflow.printer.network.pos.local': _netJson('10.0.0.1'),
        'restoflow.printer.network.pos.kitchen_ticket.local': _netJson(
          '10.0.0.2',
        ),
      });
      final net = _RecordingNetworkTester();
      await _pump(tester, netTester: net);

      // A. Customer test.
      await _tapKey(tester, 'network-printer-test');
      expect(net.calls, hasLength(1));
      expect(net.calls[0].transport, 'network');
      expect(net.calls[0].endpoint, '10.0.0.1:9100');
      expect(
        net.calls[0].document,
        isNull,
        reason:
            'the customer purpose keeps the HISTORICAL diagnostic path — no '
            'kitchen document may ever be passed',
      );

      // B. Kitchen test — through the real purpose-switching UI.
      await _switchToKitchen(tester, l10n);
      await _tapKey(tester, 'network-printer-test-kitchen');
      expect(net.calls, hasLength(2));
      expect(net.calls[1].endpoint, '10.0.0.2:9100');
      expect(net.calls[1].document, isNotNull);
      _assertKitchenTestDocumentMoneyFree(net.calls[1].document!, l10n);
    });

    testWidgets('bluetooth: customer test uses device A + the diagnostic; '
        'kitchen test uses device B + the REAL money-free kitchen document; '
        'stale selection resets on switch', (tester) async {
      final l10n = await _en();
      SharedPreferences.setMockInitialValues({
        // Both purposes on the BLUETOOTH transport with different devices.
        'restoflow.printer.selected.pos.local': 'bluetooth',
        'restoflow.printer.selected.pos.kitchen_ticket.local': 'bluetooth',
        'restoflow.printer.bluetooth.pos.local': _btJson(
          'AA:AA:AA:AA:AA:AA',
          name: 'BT-A',
        ),
        'restoflow.printer.bluetooth.pos.kitchen_ticket.local': _btJson(
          'BB:BB:BB:BB:BB:BB',
          name: 'BT-B',
        ),
      });
      final net = _RecordingNetworkTester();
      final bt = _RecordingBtTester();
      final connector = _FakeBtConnector(
        const BluetoothPairedResult.ok([
          BluetoothDeviceInfo(address: 'AA:AA:AA:AA:AA:AA', name: 'BT-A'),
          BluetoothDeviceInfo(address: 'BB:BB:BB:BB:BB:BB', name: 'BT-B'),
        ]),
      );
      await _pump(tester, netTester: net, btTester: bt, connector: connector);

      // C. Customer bluetooth test: the SAVED customer device A is used.
      await _tapKey(tester, 'bluetooth-test');
      expect(bt.calls, hasLength(1));
      expect(bt.calls[0].transport, 'bluetooth');
      expect(bt.calls[0].endpoint, 'AA:AA:AA:AA:AA:AA');
      expect(bt.calls[0].document, isNull);

      // D. Kitchen bluetooth test: the SAVED kitchen device B is used — the
      // in-session customer selection was reset by the purpose switch.
      await _switchToKitchen(tester, l10n);
      await _tapKey(tester, 'bluetooth-test-kitchen');
      expect(bt.calls, hasLength(2));
      expect(bt.calls[1].endpoint, 'BB:BB:BB:BB:BB:BB');
      expect(bt.calls[1].document, isNotNull);
      _assertKitchenTestDocumentMoneyFree(
        bt.calls[1].document!,
        l10n,
        allowedContext: {'BT-B'},
      );

      // E. Back to customer: device A again (no cross-purpose bleed).
      await _switchToCustomer(tester, l10n);
      await _tapKey(tester, 'bluetooth-test');
      expect(bt.calls, hasLength(3));
      expect(bt.calls[2].endpoint, 'AA:AA:AA:AA:AA:AA');
      expect(bt.calls[2].document, isNull);
      // The network tester was never involved.
      expect(net.calls, isEmpty);
    });
  });

  group('copy action + receipt-path regression', () {
    testWidgets('copy customer→kitchen is a ONE-TIME copy through the real '
        'UI; later kitchen edits never modify customer (and vice versa); the '
        'receipt providers keep resolving the CUSTOMER slot', (tester) async {
      final l10n = await _en();
      SharedPreferences.setMockInitialValues({
        'restoflow.printer.network.pos.local': _netJson('10.0.0.1', name: 'A'),
      });
      final net = _RecordingNetworkTester();
      await _pump(tester, netTester: net);

      await _switchToKitchen(tester, l10n);
      await _tapKey(tester, 'kitchen-printer-copy-customer');

      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(
          prefs.getString(
            'restoflow.printer.network.pos.kitchen_ticket.local',
          )!,
        )['host'],
        '10.0.0.1',
      );

      // Edit the kitchen copy: the customer slot must NOT follow.
      await tester.enterText(
        find.byKey(const Key('network-printer-ip-field-kitchen')),
        '10.0.0.55',
      );
      await _tapKey(tester, 'network-printer-save-kitchen');
      expect(
        jsonDecode(
          prefs.getString('restoflow.printer.network.pos.local')!,
        )['host'],
        '10.0.0.1',
      );

      // Edit the customer slot: the kitchen copy must NOT follow.
      await _switchToCustomer(tester, l10n);
      await tester.enterText(
        find.byKey(const Key('network-printer-ip-field')),
        '10.0.0.77',
      );
      await _tapKey(tester, 'network-printer-save');
      expect(
        jsonDecode(
          prefs.getString(
            'restoflow.printer.network.pos.kitchen_ticket.local',
          )!,
        )['host'],
        '10.0.0.55',
      );

      // RECEIPT REGRESSION: the historical provider (watched by the receipt
      // bridges — native_print_bridges.dart — and the auto-print gate) is the
      // CUSTOMER element and reads the customer endpoint, never the kitchen's.
      final element = tester.element(find.byType(PrinterSettingsSection));
      final container = ProviderScope.containerOf(element, listen: false);
      final receiptSlot = await container.read(
        posNetworkPrinterConfigProvider.future,
      );
      expect(receiptSlot?.host, '10.0.0.77');
      expect(
        posNetworkPrinterConfigProvider,
        equals(
          posNetworkPrinterConfigFamily(PosPrinterPurpose.customerReceipt),
        ),
        reason:
            'the historical provider name must stay the customerReceipt '
            'family element — no alias may drift to the kitchen slot',
      );
    });
  });
}
