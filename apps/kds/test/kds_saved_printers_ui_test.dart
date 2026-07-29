@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kds/src/print/kds_native_printer.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WIFI-PRINTER-PROFILE-LISTS-001 — the KDS "Saved printers" settings UI.
///
/// Drives the REAL production [NativePrinterSettingsSection] (the widget the KDS
/// device-settings sheet builds) over the REAL KDS profile provider and real
/// prefs — never SavedPrintersSection in isolation. KDS stays kitchen-only.

const _kdsLegacyKey = 'restoflow.printer.network.kds.local';
const _posListKey = 'restoflow.printer.network_profiles.pos.local';

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

ProviderContainer _kdsContainer() {
  final c = ProviderContainer(
    overrides: [
      nativePrintingAvailableProvider.overrideWithValue(true),
      nativePrinterNamespaceProvider.overrideWithValue('kds'),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  ProviderContainer? container,
}) async {
  tester.view.physicalSize = const Size(1000, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final c = container ?? _kdsContainer();
  final l10n = await _en();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
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
  return c;
}

/// Seeds two profiles through the REAL KDS provider and selects the first.
Future<String> _seedTwo(ProviderContainer c) async {
  final ctrl = c.read(networkPrinterProfilesProvider.notifier);
  final a = await ctrl.addProfile(
    name: 'Kitchen printer',
    config: const NetworkPrinterConfig(host: '10.0.0.14', port: 9100),
  );
  await ctrl.addProfile(
    name: 'Pass printer',
    config: const NetworkPrinterConfig(host: '10.0.0.20', port: 9101),
  );
  await ctrl.selectProfile(a!.id);
  return a.id;
}

String _fieldText(WidgetTester tester, String key) =>
    (tester.widget(find.byKey(Key(key))) as TextField).controller!.text;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  testWidgets('1. the KDS list renders name and host:port, and marks ONLY the '
      'active row', (tester) async {
    final c = _kdsContainer();
    await _seedTwo(c);
    await _pump(tester, container: c);
    final l10n = await _en();

    expect(find.text(l10n.printerProfilesHeading), findsOneWidget);
    expect(find.text('Kitchen printer'), findsOneWidget);
    expect(find.text('Pass printer'), findsOneWidget);
    expect(find.text('10.0.0.14:9100'), findsOneWidget);
    expect(find.text('10.0.0.20:9101'), findsOneWidget);
    expect(find.text(l10n.printerProfilesActiveBadge), findsOneWidget);
  });

  testWidgets('2. tapping an inactive row selects it, repoints the canonical '
      'KDS config, populates the fields, and prints nothing', (tester) async {
    final c = _kdsContainer();
    await _seedTwo(c);
    await _pump(tester, container: c);

    await tester.tap(find.text('Pass printer'));
    await tester.pumpAndSettle();

    final canonical = await c.read(networkPrinterConfigProvider.future);
    expect(canonical!.host, '10.0.0.20');
    expect(canonical.port, 9101);
    expect(_fieldText(tester, 'network-printer-ip-field'), '10.0.0.20');
    expect(_fieldText(tester, 'network-printer-port-field'), '9101');

    // Selection alone never starts a test print.
    final l10n = await _en();
    expect(find.text(l10n.posNetworkPrinterTesting), findsNothing);
  });

  testWidgets('3. Add persists a profile, makes it active and updates the '
      'canonical config', (tester) async {
    final c = await _pump(tester);
    final l10n = await _en();

    await tester.tap(find.byKey(const Key('saved-printers-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('saved-printer-name-field')),
      'Grill',
    );
    await tester.enterText(
      find.byKey(const Key('saved-printer-host-field')),
      '10.0.0.31',
    );
    await tester.enterText(
      find.byKey(const Key('saved-printer-port-field')),
      '9100',
    );
    await tester.tap(find.byKey(const Key('saved-printer-save')));
    await tester.pumpAndSettle();

    final state = await c.read(networkPrinterProfilesProvider.future);
    expect(state.profiles, hasLength(1));
    expect(state.profiles.single.name, 'Grill');
    expect(state.activeId, state.profiles.single.id);
    final canonical = await c.read(networkPrinterConfigProvider.future);
    expect(canonical!.host, '10.0.0.31');
    expect(find.text(l10n.printerProfilesActiveBadge), findsOneWidget);
  });

  testWidgets('4/12. Edit keeps the stable id, updates the canonical config, '
      'and survives process recreation', (tester) async {
    final c = _kdsContainer();
    final activeId = await _seedTwo(c);
    await _pump(tester, container: c);

    await tester.tap(find.byKey(Key('saved-printer-edit-$activeId')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('saved-printer-host-field')),
      '10.0.0.77',
    );
    await tester.tap(find.byKey(const Key('saved-printer-save')));
    await tester.pumpAndSettle();

    final after = await c.read(networkPrinterProfilesProvider.future);
    expect(after.activeId, activeId, reason: 'the id is stable');
    expect(after.active!.config.host, '10.0.0.77');
    expect(
      (await c.read(networkPrinterConfigProvider.future))!.host,
      '10.0.0.77',
    );

    // Force-stop + relaunch: a brand-new container over the same prefs.
    final fresh = _kdsContainer();
    final restored = await fresh.read(networkPrinterProfilesProvider.future);
    expect(restored.profiles, hasLength(2), reason: 'no duplicate migration');
    expect(restored.activeId, activeId);
    expect(restored.active!.config.host, '10.0.0.77');
    expect(
      (await fresh.read(networkPrinterConfigProvider.future))!.host,
      '10.0.0.77',
    );
  });

  testWidgets('5. an INVALID edit shows localized validation and changes '
      'nothing', (tester) async {
    final c = _kdsContainer();
    final activeId = await _seedTwo(c);
    await _pump(tester, container: c);
    final l10n = await _en();

    await tester.tap(find.byKey(Key('saved-printer-edit-$activeId')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('saved-printer-host-field')),
      '   ',
    );
    await tester.tap(find.byKey(const Key('saved-printer-save')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.posNetworkPrinterInvalidIp), findsOneWidget);
    final after = await c.read(networkPrinterProfilesProvider.future);
    expect(after.active!.config.host, '10.0.0.14', reason: 'unchanged');
    expect(
      (await c.read(networkPrinterConfigProvider.future))!.host,
      '10.0.0.14',
    );
  });

  testWidgets('6. removing an INACTIVE profile needs confirmation and leaves '
      'the active selection alone', (tester) async {
    final c = _kdsContainer();
    final activeId = await _seedTwo(c);
    final state = await c.read(networkPrinterProfilesProvider.future);
    final inactive = state.profiles.firstWhere((p) => p.id != activeId);
    await _pump(tester, container: c);
    final l10n = await _en();

    await tester.tap(find.byKey(Key('saved-printer-delete-${inactive.id}')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.printerProfilesDeleteConfirmTitle), findsOneWidget);
    await tester.tap(find.byKey(const Key('saved-printer-delete-confirm')));
    await tester.pumpAndSettle();

    final after = await c.read(networkPrinterProfilesProvider.future);
    expect(after.profiles, hasLength(1));
    expect(after.activeId, activeId, reason: 'active selection unchanged');
  });

  testWidgets('7. removing the ACTIVE profile names it, then leaves the KDS '
      'honestly unconfigured', (tester) async {
    final c = _kdsContainer();
    final activeId = await _seedTwo(c);
    await _pump(tester, container: c);

    await tester.tap(find.byKey(Key('saved-printer-delete-$activeId')));
    await tester.pumpAndSettle();
    // The confirmation names the printer being removed.
    expect(find.textContaining('Kitchen printer'), findsWidgets);
    expect(
      (await c.read(networkPrinterProfilesProvider.future)).profiles,
      hasLength(2),
      reason: 'nothing is removed before confirmation',
    );

    await tester.tap(find.byKey(const Key('saved-printer-delete-confirm')));
    await tester.pumpAndSettle();

    final after = await c.read(networkPrinterProfilesProvider.future);
    expect(after.profiles, hasLength(1));
    expect(
      after.activeId,
      isNull,
      reason: 'no unrelated profile is silently promoted',
    );
  });

  testWidgets('8. a DUPLICATE endpoint is rejected with a localized message', (
    tester,
  ) async {
    final c = _kdsContainer();
    await _seedTwo(c);
    await _pump(tester, container: c);
    final l10n = await _en();

    await tester.tap(find.byKey(const Key('saved-printers-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('saved-printer-name-field')),
      'Same kitchen',
    );
    await tester.enterText(
      find.byKey(const Key('saved-printer-host-field')),
      ' 10.0.0.14 ',
    );
    await tester.enterText(
      find.byKey(const Key('saved-printer-port-field')),
      '9100',
    );
    await tester.tap(find.byKey(const Key('saved-printer-save')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.printerProfilesDuplicateError), findsOneWidget);
    expect(
      (await c.read(networkPrinterProfilesProvider.future)).profiles,
      hasLength(2),
      reason: 'only the two logical profiles remain',
    );
  });

  testWidgets('9. an unnamed MIGRATED profile gets the localized default name '
      'once, and a rebuild does not rewrite it', (tester) async {
    SharedPreferences.setMockInitialValues({
      _kdsLegacyKey: jsonEncode(const {'host': '10.0.0.9', 'port': 9100}),
    });
    final c = await _pump(tester);
    final l10n = await _en();

    expect(find.text(l10n.printerProfilesDefaultName), findsOneWidget);
    final state = await c.read(networkPrinterProfilesProvider.future);
    expect(state.profiles.single.name, l10n.printerProfilesDefaultName);

    final firstId = state.profiles.single.id;
    await tester.pumpAndSettle();
    final again = await c.read(networkPrinterProfilesProvider.future);
    expect(again.profiles, hasLength(1));
    expect(again.profiles.single.id, firstId);
    expect(again.profiles.single.name, l10n.printerProfilesDefaultName);
  });

  testWidgets('9b. an explicitly NAMED profile is never renamed', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      _kdsLegacyKey: jsonEncode(const {
        'host': '10.0.0.9',
        'port': 9100,
        'name': 'Grill line',
      }),
    });
    final c = await _pump(tester);
    final l10n = await _en();
    // The stored name appears in the saved row AND in the prefilled name field.
    expect(find.text('Grill line'), findsWidgets);
    final state = await c.read(networkPrinterProfilesProvider.future);
    expect(state.profiles.single.name, 'Grill line');
    expect(
      find.text(l10n.printerProfilesDefaultName),
      findsNothing,
      reason: 'an explicitly named profile is never renamed to the default',
    );
  });

  testWidgets('10. the empty state offers Add and is never shown as a false '
      'empty while loading', (tester) async {
    await _pump(tester);
    final l10n = await _en();
    expect(find.text(l10n.printerProfilesEmpty), findsOneWidget);
    expect(find.byKey(const Key('saved-printers-add')), findsOneWidget);
    // A perpetual animation here would hang pumpAndSettle; it already settled.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('11. a provider rebuild does not overwrite typed endpoint text; '
      'cancelling Add mutates nothing', (tester) async {
    final c = await _pump(tester);

    await tester.enterText(
      find.byKey(const Key('network-printer-ip-field')),
      '10.0.0.55',
    );
    await tester.pump();

    await c
        .read(networkPrinterProfilesProvider.notifier)
        .addProfile(
          name: 'Other',
          config: const NetworkPrinterConfig(host: '10.0.0.99'),
        );
    await tester.pumpAndSettle();
    expect(
      _fieldText(tester, 'network-printer-ip-field'),
      '10.0.0.55',
      reason: 'a rebuild never overwrites what the user typed',
    );

    // Cancelling the Add form changes nothing.
    final before = (await c.read(
      networkPrinterProfilesProvider.future,
    )).profiles.length;
    await tester.tap(find.byKey(const Key('saved-printers-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('saved-printer-host-field')),
      '10.0.0.123',
    );
    await tester.tap(find.byKey(const Key('saved-printer-cancel')));
    await tester.pumpAndSettle();
    expect(
      (await c.read(networkPrinterProfilesProvider.future)).profiles.length,
      before,
    );
  });

  testWidgets('13. the KDS surface never shows POS profiles', (tester) async {
    SharedPreferences.setMockInitialValues({
      _posListKey: jsonEncode([
        {
          'id': 'p1',
          'name': 'POS counter',
          'config': {'host': '10.0.0.250', 'port': 9100},
        },
      ]),
    });
    final c = await _pump(tester);
    expect(find.text('POS counter'), findsNothing);
    expect(
      (await c.read(networkPrinterProfilesProvider.future)).profiles,
      isEmpty,
    );
  });
}
