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

/// A reader returning a canned assignments snapshot (Part B), counting loads
/// so the Part G Refresh control can be proven to re-read.
class _FakeAssignmentsReader implements DevicePrinterAssignmentsReader {
  _FakeAssignmentsReader(this.assignments);

  final DevicePrinterAssignments assignments;
  int loadCount = 0;

  @override
  Future<Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>>
  load() async {
    loadCount++;
    return Success(assignments);
  }
}

/// A fake device-session manager (Part G): records the local unpair. Restore
/// is never exercised here (the sheet only calls unpair).
class _FakeManager implements DeviceSessionManager {
  bool unpaired = false;

  @override
  Future<void> unpair() async => unpaired = true;

  @override
  Future<DeviceContext?> restore({String? expectedDeviceType}) async => null;
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

  Future<ProviderContainer> pumpWithManager(
    WidgetTester tester, {
    required DevicePrinterAssignmentsReader reader,
    DeviceSessionManager? manager,
  }) async {
    SharedPreferences.setMockInitialValues(const {});
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posDeviceContextProvider.overrideWith(_SeededPosContext.new),
        posPrinterAssignmentsReaderProvider.overrideWithValue(reader),
        if (manager != null)
          posDeviceSessionManagerProvider.overrideWithValue(manager),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: const Scaffold(body: PosDeviceSettingsSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('Part G: Refresh reloads the printer assignments', (
    tester,
  ) async {
    final reader = _FakeAssignmentsReader(_assignments());
    await pumpWithManager(tester, reader: reader);
    expect(reader.loadCount, 1); // initial

    await tester.tap(find.byKey(const Key('device-refresh-button')));
    await tester.pumpAndSettle();

    expect(reader.loadCount, 2); // Refresh re-ran the token-proven read
  });

  testWidgets('Part G: Unpair confirms, clears the local session via the '
      'manager, and clears the published device context (-> pairing)', (
    tester,
  ) async {
    final l10n = await _en();
    final manager = _FakeManager();
    final container = await pumpWithManager(
      tester,
      reader: _FakeAssignmentsReader(_assignments()),
      manager: manager,
    );

    await tester.tap(find.byKey(const Key('device-unpair-button')));
    await tester.pumpAndSettle();
    // The confirm dialog warns before doing anything.
    expect(find.text(l10n.deviceUnpairWarning), findsOneWidget);
    expect(manager.unpaired, isFalse);

    await tester.tap(find.byKey(const Key('device-unpair-confirm')));
    await tester.pumpAndSettle();

    // Local session cleared (best-effort server self-revoke) + gate reset.
    expect(manager.unpaired, isTrue);
    expect(container.read(posDeviceContextProvider), isNull);
  });

  testWidgets('Part G: with no session manager (demo/unconfigured) there is '
      'NO unpair control — Refresh only', (tester) async {
    await pumpWithManager(
      tester,
      reader: _FakeAssignmentsReader(_assignments()),
    );

    expect(find.byKey(const Key('device-refresh-button')), findsOneWidget);
    expect(find.byKey(const Key('device-unpair-button')), findsNothing);
  });
}
