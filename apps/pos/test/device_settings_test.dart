import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_printer_assignments.dart';
import 'package:restoflow_pos/src/widgets/device_settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A reader returning a canned assignments snapshot (Part B).
class _FakeAssignmentsReader implements DevicePrinterAssignmentsReader {
  _FakeAssignmentsReader(this.assignments);

  final DevicePrinterAssignments assignments;

  @override
  Future<Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>>
  load() async => Success(assignments);
}

DevicePrinterAssignments _assignments({List<AssignedPrinter>? printers}) =>
    DevicePrinterAssignments(
      fetchedAt: DateTime(2026, 7, 3, 12, 30),
      deviceLabel: 'Front POS',
      deviceType: 'pos',
      restaurantName: 'Falafel House',
      branchName: 'Main branch',
      printers:
          printers ??
          const [
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

/// Device settings sprint (Part A): the POS app bar carries the ⋮ device
/// menu; the settings sheet shows THIS paired station's operational info —
/// staff scope only, never owner/admin data.

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

/// A context controller pre-seeded with a paired POS device (what the
/// pairing gate publishes after restore/pair).
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

void main() {
  testWidgets('the POS app bar shows the ⋮ device menu and it opens the '
      'device-settings sheet (demo: honest no-device note)', (tester) async {
    final l10n = await _en();
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: const PosMenuScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('device-settings-menu')), findsOneWidget);
    await tester.tap(find.byKey(const Key('device-settings-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('device-settings-item')), findsOneWidget);
    await tester.tap(find.byKey(const Key('device-settings-item')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('device-settings-sheet')), findsOneWidget);
    // Demo mode is honest: no paired device is claimed.
    expect(find.text(l10n.deviceSettingsDemoNote), findsOneWidget);
  });

  testWidgets('real mode: the sheet shows the paired device info (app type, '
      'label, pairing + staff-session status) and no owner data', (
    tester,
  ) async {
    final l10n = await _en();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posDeviceContextProvider.overrideWith(_SeededPosContext.new),
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

    expect(find.text(l10n.deviceSettingsAppTypePos), findsOneWidget);
    expect(find.text('Front POS'), findsOneWidget);
    expect(find.text(l10n.deviceSettingsPairingActive), findsOneWidget);
    // No PIN session in this harness -> honestly "not signed in".
    expect(find.text(l10n.deviceSettingsPinSessionNone), findsOneWidget);
    // Operational scope only: no raw ids, no demo note, no owner surfaces.
    expect(find.text('org-1'), findsNothing);
    expect(find.text(l10n.deviceSettingsDemoNote), findsNothing);
    expect(tester.takeException(), isNull);
  });

  Future<void> pumpSheetWith(
    WidgetTester tester,
    DevicePrinterAssignmentsReader reader,
  ) async {
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
          posDeviceContextProvider.overrideWith(_SeededPosContext.new),
          posPrinterAssignmentsReaderProvider.overrideWithValue(reader),
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
  }

  testWidgets('Part B: the sheet shows THIS station\'s assigned receipt '
      'printer with an HONEST bridge-required status (never "Ready")', (
    tester,
  ) async {
    final l10n = await _en();
    await pumpSheetWith(tester, _FakeAssignmentsReader(_assignments()));

    // Names from the token-proven read fill the identity rows.
    expect(find.text('Falafel House'), findsOneWidget);
    expect(find.text('Main branch'), findsOneWidget);
    // The assigned printer renders with safe metadata + honest status.
    expect(find.byKey(const Key('printer-prn-1')), findsOneWidget);
    expect(find.text('Counter receipt'), findsOneWidget);
    expect(find.text(l10n.deviceSettingsBridgeRequired), findsOneWidget);
    expect(find.text(l10n.deviceSettingsCapabilityNote), findsOneWidget);
    expect(find.text(l10n.deviceSettingsLastRefresh('12:30')), findsOneWidget);
    expect(find.text(l10n.printStatusPrinted), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Part B: no assigned printer -> the ask-a-manager empty state', (
    tester,
  ) async {
    final l10n = await _en();
    await pumpSheetWith(
      tester,
      _FakeAssignmentsReader(_assignments(printers: const [])),
    );

    expect(find.byKey(const Key('no-printer-banner')), findsOneWidget);
    expect(find.text(l10n.deviceSettingsNoPrinter), findsOneWidget);
  });

  testWidgets('Part C: the auto-print toggle defaults ON with a printer, '
      'persists a flip PER DEVICE, and stores only a plain bool', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      // Another station's stored OFF must NOT leak into dev-1.
      'restoflow.autoprint.pos.receiptOnPaid.other-dev': false,
    });
    await pumpSheetWith(tester, _FakeAssignmentsReader(_assignments()));

    final toggle = find.byKey(const Key('auto-print-receipt-toggle'));
    expect(toggle, findsOneWidget);
    // dev-1 never chose -> default ON (printer configured).
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    // Persisted under THIS device's key; no token/secret-looking values.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('restoflow.autoprint.pos.receiptOnPaid.dev-1'), false);
    expect(prefs.getKeys().where((k) => k.contains('token')).toList(), isEmpty);
  });

  testWidgets('Part C: no printer -> the toggle is DISABLED with the why '
      '(a toggle that could never print would be a lie)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final l10n = await _en();
    await pumpSheetWith(
      tester,
      _FakeAssignmentsReader(_assignments(printers: const [])),
    );

    final toggle = find.byKey(const Key('auto-print-receipt-toggle'));
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.text(l10n.autoPrintNoPrinterNote), findsOneWidget);
  });
}
