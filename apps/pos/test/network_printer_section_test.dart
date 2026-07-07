import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:restoflow_pos/src/print/network_printer_tester.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_network_printer_config.dart';
import 'package:restoflow_pos/src/state/pos_printer_assignments.dart';
import 'package:restoflow_pos/src/widgets/device_settings_sheet.dart';
import 'package:restoflow_pos/src/widgets/network_printer_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ANDROID-002: the on-device network printer setup — enter IP/port, Test print
/// real ESC/POS bytes with no print bridge, save locally, and (on Android) drop
/// the "requires print bridge" wording once a printer is set up.

class _FakeTester implements NetworkPrinterTester {
  _FakeTester(this.result);

  final pp.PrintResult result;
  PosNetworkPrinterConfig? lastConfig;
  String? lastDeviceLabel;
  int calls = 0;

  @override
  Future<pp.PrintResult> testPrint(
    PosNetworkPrinterConfig config, {
    String? deviceLabel,
  }) async {
    calls++;
    lastConfig = config;
    lastDeviceLabel = deviceLabel;
    return result;
  }
}

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pumpSection(
  WidgetTester tester, {
  required NetworkPrinterTester printerTester,
}) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        networkPrinterTesterProvider.overrideWithValue(printerTester),
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
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  testWidgets('renders IP/port/name fields, buttons, and an honest '
      '"not configured" status', (tester) async {
    final l10n = await _en();
    await _pumpSection(
      tester,
      printerTester: _FakeTester(pp.PrintResult.success()),
    );

    expect(find.byKey(const Key('network-printer-ip-field')), findsOneWidget);
    expect(find.byKey(const Key('network-printer-port-field')), findsOneWidget);
    expect(find.byKey(const Key('network-printer-name-field')), findsOneWidget);
    expect(find.byKey(const Key('network-printer-save')), findsOneWidget);
    expect(find.byKey(const Key('network-printer-test')), findsOneWidget);
    expect(
      find.text(l10n.posNetworkPrinterStatusNotConfigured),
      findsOneWidget,
    );
    // Port defaults to 9100 (RAW/JetDirect).
    expect(find.text('9100'), findsOneWidget);
  });

  testWidgets('an invalid IP blocks the test print and shows a validation '
      'error (the tester is never called)', (tester) async {
    final l10n = await _en();
    final fake = _FakeTester(pp.PrintResult.success());
    await _pumpSection(tester, printerTester: fake);

    await tester.enterText(
      find.byKey(const Key('network-printer-ip-field')),
      '999.1', // not a valid IPv4 / host
    );
    await tester.tap(find.byKey(const Key('network-printer-test')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.posNetworkPrinterInvalidIp), findsOneWidget);
    expect(fake.calls, 0);
  });

  testWidgets('a valid IP + Test print sends via the transport, reports '
      'success, and saves the config locally', (tester) async {
    final l10n = await _en();
    final fake = _FakeTester(pp.PrintResult.success());
    await _pumpSection(tester, printerTester: fake);

    await tester.enterText(
      find.byKey(const Key('network-printer-ip-field')),
      '192.168.1.50',
    );
    await tester.tap(find.byKey(const Key('network-printer-test')));
    await tester.pumpAndSettle();

    // The transport received the exact host:port.
    expect(fake.calls, 1);
    expect(fake.lastConfig?.host, '192.168.1.50');
    expect(fake.lastConfig?.port, 9100);
    // Honest success (bytes delivered), with the host:port for the operator.
    expect(
      find.textContaining(l10n.posNetworkPrinterTestSuccess),
      findsOneWidget,
    );
    // Persisted locally under the fallback key (no paired device here).
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(
      '$kPosNetworkPrinterKeyPrefix$kPosNetworkPrinterLocalKey',
    );
    expect(raw, isNotNull);
    expect(jsonDecode(raw!)['host'], '192.168.1.50');
  });

  testWidgets('an unreachable printer surfaces the honest failure message', (
    tester,
  ) async {
    final l10n = await _en();
    final fake = _FakeTester(
      const pp.PrintResult.failure(pp.PrinterErrorCategory.unreachable),
    );
    await _pumpSection(tester, printerTester: fake);

    await tester.enterText(
      find.byKey(const Key('network-printer-ip-field')),
      '10.0.0.99',
    );
    await tester.tap(find.byKey(const Key('network-printer-test')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.posNetworkPrinterTestFailure), findsOneWidget);
  });

  testWidgets('Save persists the config without a test print', (tester) async {
    final fake = _FakeTester(pp.PrintResult.success());
    await _pumpSection(tester, printerTester: fake);

    await tester.enterText(
      find.byKey(const Key('network-printer-ip-field')),
      '192.168.0.10',
    );
    await tester.enterText(
      find.byKey(const Key('network-printer-port-field')),
      '9200',
    );
    await tester.tap(find.byKey(const Key('network-printer-save')));
    await tester.pumpAndSettle();

    expect(fake.calls, 0); // Save never prints.
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(
      '$kPosNetworkPrinterKeyPrefix$kPosNetworkPrinterLocalKey',
    );
    expect(jsonDecode(raw!)['port'], 9200);
  });

  // ---- device-settings integration: the "Requires print bridge" bypass ----

  testWidgets('device settings: NOT native (web) hides the network section '
      'and keeps the bridge messaging', (tester) async {
    final l10n = await _en();
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posNativePrintingAvailableProvider.overrideWithValue(false),
          posDeviceContextProvider.overrideWith(_SeededPosContext.new),
          posPrinterAssignmentsReaderProvider.overrideWithValue(
            _FakeAssignmentsReader(_assignments()),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: const Scaffold(body: PosDeviceSettingsSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('network-printer-section')), findsNothing);
    expect(find.text(l10n.deviceSettingsBridgeRequired), findsOneWidget);
    expect(find.text(l10n.deviceSettingsCapabilityNote), findsOneWidget);
  });

  testWidgets('device settings: on Android with a saved network printer, the '
      'assigned printer drops "Requires print bridge"', (tester) async {
    final l10n = await _en();
    // A network printer already saved for the paired device -> bypass active.
    SharedPreferences.setMockInitialValues({
      '${kPosNetworkPrinterKeyPrefix}dev-1': jsonEncode(const {
        'host': '192.168.1.50',
        'port': 9100,
      }),
    });
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posNativePrintingAvailableProvider.overrideWithValue(true),
          networkPrinterTesterProvider.overrideWithValue(
            _FakeTester(pp.PrintResult.success()),
          ),
          posDeviceContextProvider.overrideWith(_SeededPosContext.new),
          posPrinterAssignmentsReaderProvider.overrideWithValue(
            _FakeAssignmentsReader(_assignments()),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: const Scaffold(body: PosDeviceSettingsSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The native network section is present...
    expect(find.byKey(const Key('network-printer-section')), findsOneWidget);
    // ...and the assigned printer no longer claims a bridge is required.
    expect(find.text(l10n.deviceSettingsBridgeRequired), findsNothing);
    expect(find.text(l10n.deviceSettingsPrinterConfigured), findsOneWidget);
    expect(find.text(l10n.deviceSettingsNativeNetworkNote), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

// --- shared fakes for the device-settings integration tests ---

class _FakeAssignmentsReader implements DevicePrinterAssignmentsReader {
  _FakeAssignmentsReader(this.assignments);

  final DevicePrinterAssignments assignments;

  @override
  Future<Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>>
  load() async => Success(assignments);
}

DevicePrinterAssignments _assignments() => DevicePrinterAssignments(
  fetchedAt: DateTime(2026, 7, 7, 12, 30),
  deviceLabel: 'Front POS',
  deviceType: 'pos',
  restaurantName: 'Falafel House',
  branchName: 'Main branch',
  printers: const [
    AssignedPrinter(
      id: 'prn-1',
      displayName: 'Counter receipt',
      role: 'receipt',
      connectionType: 'network',
      paperWidth: '80mm',
      isEnabled: true,
    ),
  ],
);

class _SeededPosContext extends PosDeviceContextController {
  @override
  DeviceContext? build() => const DeviceContext(
    organizationId: 'org-1',
    restaurantId: 'rest-1',
    branchId: 'branch-1',
    deviceId: 'dev-1',
    deviceType: 'pos',
    displayName: 'Front POS',
  );
}
