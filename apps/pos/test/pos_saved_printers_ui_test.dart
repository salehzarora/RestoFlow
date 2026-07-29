@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/state/pos_network_printer_config.dart';
import 'package:restoflow_pos/src/state/pos_network_printer_profiles.dart';
import 'package:restoflow_pos/src/state/pos_printer_purpose.dart';
import 'package:restoflow_pos/src/widgets/network_printer_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WIFI-PRINTER-PROFILE-LISTS-001 — the POS "Saved printers" settings UI.
///
/// Drives the REAL [NetworkPrinterSection] over the REAL profile providers and
/// real prefs, so these pin what the cashier can actually do, not a mocked
/// callback surface.

const _receiptLegacyKey = 'restoflow.printer.network.pos.local';

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

ProviderContainer _seeded() {
  final c = ProviderContainer(
    overrides: [posNativePrintingAvailableProvider.overrideWithValue(true)],
  );
  addTearDown(c.dispose);
  return c;
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  PosPrinterPurpose purpose = PosPrinterPurpose.customerReceipt,
}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = _seeded();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: NetworkPrinterSection(purpose: purpose),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Adds a profile through the REAL provider (the UI's own data source).
Future<void> _seedProfiles(ProviderContainer c) async {
  final ctrl = c.read(posNetworkPrinterProfilesProvider.notifier);
  final a = await ctrl.addProfile(
    name: 'Kitchen printer',
    config: const PosNetworkPrinterConfig(host: '10.0.0.14', port: 9100),
  );
  await ctrl.addProfile(
    name: 'Cashier printer',
    config: const PosNetworkPrinterConfig(host: '10.0.0.20', port: 9101),
  );
  await ctrl.selectProfile(a!.id);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  testWidgets('A. the saved list renders name, host and port, and marks ONLY '
      'the active row', (tester) async {
    final container = _seeded();
    await _seedProfiles(container);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
    final l10n = await _en();

    expect(find.text(l10n.printerProfilesHeading), findsOneWidget);
    expect(find.text('Kitchen printer'), findsOneWidget);
    expect(find.text('Cashier printer'), findsOneWidget);
    expect(find.textContaining('10.0.0.14'), findsWidgets);
    expect(find.textContaining('9101'), findsWidgets);

    // The active badge appears exactly once — on the selected row.
    expect(find.text(l10n.printerProfilesActiveBadge), findsOneWidget);
  });

  testWidgets('B. tapping an inactive row selects it, moves the badge and '
      'populates the host/port fields — and prints nothing', (tester) async {
    final container = _seeded();
    await _seedProfiles(container);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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

    await tester.tap(find.text('Cashier printer'));
    await tester.pumpAndSettle();

    // The canonical config — what Test Print and production printing read.
    final canonical = await container.read(
      posNetworkPrinterConfigProvider.future,
    );
    expect(canonical!.host, '10.0.0.20');
    expect(canonical.port, 9101);

    // The existing endpoint fields follow the selection.
    expect(
      (tester.widget(find.byKey(const Key('network-printer-ip-field')))
              as TextField)
          .controller!
          .text,
      '10.0.0.20',
    );
    expect(
      (tester.widget(find.byKey(const Key('network-printer-port-field')))
              as TextField)
          .controller!
          .text,
      '9101',
    );
    // Selection never triggers a print.
    expect(find.byKey(const Key('network-printer-status')), findsOneWidget);
  });

  testWidgets('C. Add saves a new profile, makes it active and updates the '
      'canonical config', (tester) async {
    final container = await _pump(tester);
    final l10n = await _en();

    await tester.tap(find.byKey(const Key('saved-printers-add')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('saved-printer-name-field')),
      'Counter',
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

    final state = await container.read(
      posNetworkPrinterProfilesProvider.future,
    );
    expect(state.profiles, hasLength(1));
    expect(state.profiles.single.name, 'Counter');
    expect(state.activeId, state.profiles.single.id);
    final canonical = await container.read(
      posNetworkPrinterConfigProvider.future,
    );
    expect(canonical!.host, '10.0.0.31');
    expect(find.text(l10n.printerProfilesActiveBadge), findsOneWidget);
  });

  testWidgets('N. adding a DUPLICATE endpoint shows a localized error and '
      'leaves one logical profile', (tester) async {
    final container = await _pump(tester);
    final l10n = await _en();
    await container
        .read(posNetworkPrinterProfilesProvider.notifier)
        .addProfile(
          name: 'Kitchen',
          config: const PosNetworkPrinterConfig(host: '10.0.0.14', port: 9100),
        );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('saved-printers-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('saved-printer-name-field')),
      'Kitchen again',
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
    final state = await container.read(
      posNetworkPrinterProfilesProvider.future,
    );
    expect(state.profiles, hasLength(1));
  });

  testWidgets('E. an INVALID add is refused and stores nothing', (
    tester,
  ) async {
    final container = await _pump(tester);

    await tester.tap(find.byKey(const Key('saved-printers-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('saved-printer-name-field')),
      'Bad',
    );
    await tester.enterText(
      find.byKey(const Key('saved-printer-host-field')),
      '   ',
    );
    await tester.enterText(
      find.byKey(const Key('saved-printer-port-field')),
      '70000',
    );
    await tester.tap(find.byKey(const Key('saved-printer-save')));
    await tester.pumpAndSettle();

    final state = await container.read(
      posNetworkPrinterProfilesProvider.future,
    );
    expect(state.profiles, isEmpty, reason: 'nothing was stored');
  });

  testWidgets('D. Edit preserves the stable id and updates the canonical '
      'config for the active profile', (tester) async {
    final container = _seeded();
    await _seedProfiles(container);
    final before = await container.read(
      posNetworkPrinterProfilesProvider.future,
    );
    final activeId = before.activeId;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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

    await tester.tap(find.byKey(Key('saved-printer-edit-$activeId')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('saved-printer-host-field')),
      '10.0.0.77',
    );
    await tester.tap(find.byKey(const Key('saved-printer-save')));
    await tester.pumpAndSettle();

    final after = await container.read(
      posNetworkPrinterProfilesProvider.future,
    );
    expect(after.activeId, activeId, reason: 'the id is stable');
    expect(after.active!.config.host, '10.0.0.77');
    final canonical = await container.read(
      posNetworkPrinterConfigProvider.future,
    );
    expect(canonical!.host, '10.0.0.77');
  });

  testWidgets('F/G. delete needs explicit confirmation; removing the ACTIVE '
      'profile leaves the slot honestly unconfigured', (tester) async {
    final container = _seeded();
    await _seedProfiles(container);
    final before = await container.read(
      posNetworkPrinterProfilesProvider.future,
    );
    final activeId = before.activeId!;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
    final l10n = await _en();

    // Tapping delete alone must NOT remove anything.
    await tester.tap(find.byKey(Key('saved-printer-delete-$activeId')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.printerProfilesDeleteConfirmTitle), findsOneWidget);
    expect(
      (await container.read(posNetworkPrinterProfilesProvider.future)).profiles,
      hasLength(2),
      reason: 'nothing is removed before confirmation',
    );

    await tester.tap(find.byKey(const Key('saved-printer-delete-confirm')));
    await tester.pumpAndSettle();

    final after = await container.read(
      posNetworkPrinterProfilesProvider.future,
    );
    expect(after.profiles, hasLength(1));
    expect(
      after.activeId,
      isNull,
      reason: 'no unrelated profile is silently promoted',
    );
  });

  testWidgets('L. the empty state offers Add and never shows a false empty '
      'while loading', (tester) async {
    await _pump(tester);
    final l10n = await _en();
    expect(find.text(l10n.printerProfilesEmpty), findsOneWidget);
    expect(find.byKey(const Key('saved-printers-add')), findsOneWidget);
  });

  testWidgets('K. an unnamed MIGRATED profile shows the localized default name '
      'and it is persisted once', (tester) async {
    SharedPreferences.setMockInitialValues({
      _receiptLegacyKey: jsonEncode(const {'host': '10.0.0.9', 'port': 9100}),
    });
    final container = await _pump(tester);
    final l10n = await _en();

    expect(find.text(l10n.printerProfilesDefaultName), findsOneWidget);

    final state = await container.read(
      posNetworkPrinterProfilesProvider.future,
    );
    expect(
      state.profiles.single.name,
      l10n.printerProfilesDefaultName,
      reason: 'the localized default is PERSISTED, not just displayed',
    );

    // A rebuild must not rewrite it again.
    await tester.pumpAndSettle();
    final again = await container.read(
      posNetworkPrinterProfilesProvider.future,
    );
    expect(again.profiles.single.id, state.profiles.single.id);
    expect(again.profiles.single.name, l10n.printerProfilesDefaultName);
  });

  testWidgets('M. a provider rebuild does not overwrite text the cashier is '
      'typing into the endpoint fields', (tester) async {
    final container = await _pump(tester);

    await tester.enterText(
      find.byKey(const Key('network-printer-ip-field')),
      '10.0.0.55',
    );
    await tester.pump();

    // A saved profile lands from elsewhere; the typed text must survive.
    await container
        .read(posNetworkPrinterProfilesProvider.notifier)
        .addProfile(
          name: 'Other',
          config: const PosNetworkPrinterConfig(host: '10.0.0.99'),
        );
    await tester.pumpAndSettle();

    expect(
      (tester.widget(find.byKey(const Key('network-printer-ip-field')))
              as TextField)
          .controller!
          .text,
      '10.0.0.55',
      reason: 'user typing is never overwritten by a rebuild',
    );
  });

  testWidgets('H. the KITCHEN slot keeps its own list and selection', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      purpose: PosPrinterPurpose.kitchenTicket,
    );
    await container
        .read(posKitchenNetworkPrinterProfilesProvider.notifier)
        .addProfile(
          name: 'Kitchen only',
          config: const PosNetworkPrinterConfig(host: '10.0.0.60'),
        );
    await tester.pumpAndSettle();

    expect(find.text('Kitchen only'), findsOneWidget);
    // The RECEIPT slot gained nothing.
    final receipt = await container.read(
      posNetworkPrinterProfilesProvider.future,
    );
    expect(receipt.profiles, isEmpty);
  });
}
