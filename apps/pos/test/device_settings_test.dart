import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/widgets/device_settings_sheet.dart';

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
}
