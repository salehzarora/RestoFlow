import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_kds/main.dart';
import 'package:restoflow_kds/src/state/kds_device_context.dart';
import 'package:restoflow_kds/src/state/kds_printer_assignments.dart';
import 'package:restoflow_kds/src/widgets/device_settings_sheet.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A reader returning a canned assignments snapshot (Part B).
class _FakeAssignmentsReader implements DevicePrinterAssignmentsReader {
  _FakeAssignmentsReader(this.assignments);

  final DevicePrinterAssignments assignments;

  @override
  Future<Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>>
  load() async => Success(assignments);
}

DevicePrinterAssignments _kitchenAssignments() => DevicePrinterAssignments(
  fetchedAt: DateTime(2026, 7, 3, 12, 30),
  deviceLabel: 'Kitchen Display',
  deviceType: 'kds',
  restaurantName: 'Falafel House',
  branchName: 'Main branch',
  printers: const [
    AssignedPrinter(
      id: 'prn-k1',
      displayName: 'Kitchen printer',
      role: 'kitchen',
      connectionType: 'network',
      paperWidth: '80mm',
      isEnabled: true,
    ),
  ],
  routes: const [
    PrinterRoute(stationId: 'st-1', printerDeviceId: 'prn-k1', isEnabled: true),
  ],
  stations: const [PrinterStation(id: 'st-1', name: 'Grill')],
);

/// Device settings sprint (Part A): the KDS app bar carries the ⋮ device
/// menu; the settings sheet shows THIS paired display's operational info —
/// staff scope only, money-FREE (T-003), never owner/admin data.

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

class _SeededKdsContext extends KdsDeviceContextController {
  @override
  DeviceContext? build() => const DeviceContext(
    organizationId: 'org-1',
    restaurantId: 'rest-1',
    branchId: 'branch-1',
    deviceId: 'dev-2',
    deviceType: 'kds',
    displayName: 'Kitchen Display',
  );
}

void main() {
  testWidgets('the KDS app bar shows the ⋮ device menu and it opens the '
      'device-settings sheet (demo: honest no-device note)', (tester) async {
    final l10n = await _en();
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const KdsApp(demoMode: true));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('device-settings-menu')), findsOneWidget);
    await tester.tap(find.byKey(const Key('device-settings-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device-settings-item')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('device-settings-sheet')), findsOneWidget);
    expect(find.text(l10n.deviceSettingsDemoNote), findsOneWidget);
    // The kitchen surface stays money-free everywhere (T-003).
    expect(find.textContaining('₪'), findsNothing);
    expect(find.textContaining(r'$'), findsNothing);
  });

  testWidgets('real mode: the sheet shows the paired KDS info and stays '
      'money-free with no owner data', (tester) async {
    final l10n = await _en();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          kdsDeviceContextProvider.overrideWith(_SeededKdsContext.new),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: const Scaffold(body: KdsDeviceSettingsSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.deviceSettingsAppTypeKds), findsOneWidget);
    expect(find.text('Kitchen Display'), findsOneWidget);
    expect(find.text(l10n.deviceSettingsPairingActive), findsOneWidget);
    expect(find.text(l10n.deviceSettingsPinSessionNone), findsOneWidget);
    // Money-free + no raw ids / owner surfaces (T-003).
    expect(find.textContaining('₪'), findsNothing);
    expect(find.textContaining(r'$'), findsNothing);
    expect(find.text('org-1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Part B: the sheet shows THIS display\'s assigned KITCHEN '
      'printer with its routed stations — honest status, money-free', (
    tester,
  ) async {
    final l10n = await _en();
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          kdsDeviceContextProvider.overrideWith(_SeededKdsContext.new),
          kdsPrinterAssignmentsReaderProvider.overrideWithValue(
            _FakeAssignmentsReader(_kitchenAssignments()),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: const Scaffold(body: KdsDeviceSettingsSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Falafel House'), findsOneWidget);
    expect(find.byKey(const Key('printer-prn-k1')), findsOneWidget);
    expect(find.text('Kitchen printer'), findsOneWidget);
    expect(
      find.text(l10n.deviceSettingsRouteStations('Grill')),
      findsOneWidget,
    );
    expect(find.text(l10n.deviceSettingsBridgeRequired), findsOneWidget);
    expect(find.text(l10n.printStatusPrinted), findsNothing);
    // The kitchen surface stays money-free (T-003).
    expect(find.textContaining('₪'), findsNothing);
    expect(find.textContaining(r'$'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Part C: the acknowledge auto-print toggle defaults ON with a '
      'kitchen printer, and a flip persists PER DEVICE', (tester) async {
    SharedPreferences.setMockInitialValues({
      'restoflow.autoprint.kds.onAcknowledge.other-dev': false,
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          kdsDeviceContextProvider.overrideWith(_SeededKdsContext.new),
          kdsPrinterAssignmentsReaderProvider.overrideWithValue(
            _FakeAssignmentsReader(_kitchenAssignments()),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: const Scaffold(body: KdsDeviceSettingsSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final toggle = find.byKey(const Key('auto-print-acknowledge-toggle'));
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('restoflow.autoprint.kds.onAcknowledge.dev-2'), false);
    expect(prefs.getKeys().where((k) => k.contains('token')).toList(), isEmpty);
  });
}
