import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/printers/printer_models.dart';
import 'package:restoflow_dashboard/src/printers/printers_repository.dart';
import 'package:restoflow_dashboard/src/printers/printers_screen.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminPermissionDenied, AdminScope, AdminValidation;
import 'package:restoflow_l10n/restoflow_l10n.dart';

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Object? Function(String fn, Map<String, dynamic> params) _handler;
  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return _handler(function, params);
  }
}

AdminScope get _scope => AdminScope.demo;

Map<String, dynamic> _listOk() => {
  'ok': true,
  'printers': [
    {
      'id': 'p-1',
      'display_name': 'Front counter',
      'connection_type': 'network',
      'role': 'receipt',
      'paper_width': '80mm',
      'connection_config': {'host': '10.0.0.50', 'port': 9100},
      'is_enabled': true,
      'revision': 1,
    },
  ],
  'routes': [
    {
      'id': 'r-1',
      'station_id': 's-1',
      'printer_device_id': 'p-1',
      'is_enabled': true,
    },
  ],
  'stations': [
    {'id': 's-1', 'name': 'Grill'},
  ],
};

void main() {
  group('SupabasePrintersRepository', () {
    test('load parses printers + routes + stations', () async {
      final t = _FakeTransport((fn, p) => _listOk());
      final repo = SupabasePrintersRepository(
        transport: t,
        scope: _scope,
        currentUserId: () => 'u',
      );
      final result = await repo.load();
      final snapshot = result.fold((s) => s, (f) => fail('expected success'));
      expect(t.calls.single.$1, 'list_printers');
      expect(snapshot.printers.single.displayName, 'Front counter');
      expect(snapshot.printers.single.host, '10.0.0.50');
      expect(snapshot.routes.single.stationId, 's-1');
      expect(snapshot.stations.single.name, 'Grill');
      expect(snapshot.stationsFor('p-1').single.name, 'Grill');
    });

    test('upsert sends the RF-150 params (integer port, wire enums)', () async {
      final t = _FakeTransport(
        (fn, p) => {'ok': true, 'id': 'p-2', 'action': 'created'},
      );
      final repo = SupabasePrintersRepository(
        transport: t,
        scope: _scope,
        currentUserId: () => 'u',
      );
      final result = await repo.upsertPrinter(
        displayName: 'Kitchen pass',
        connectionType: PrinterConnectionType.network,
        role: PrinterRole.kitchen,
        paperWidth: '80mm',
        connectionConfig: const {'host': '10.0.0.51', 'port': 9100},
        isEnabled: true,
      );
      expect(result.isSuccess, isTrue);
      final params = t.calls.single.$2;
      expect(t.calls.single.$1, 'upsert_printer_device');
      expect(params['p_connection_type'], 'network');
      expect(params['p_role'], 'kitchen');
      expect(params['p_is_enabled'], true);
    });

    test('permission_denied maps to a typed failure', () async {
      final t = _FakeTransport(
        (fn, p) => {'ok': false, 'error': 'permission_denied'},
      );
      final repo = SupabasePrintersRepository(
        transport: t,
        scope: _scope,
        currentUserId: () => 'u',
      );
      final result = await repo.load();
      result.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<AdminPermissionDenied>()),
      );
    });

    test('an org-wide (branch-less) scope fails closed on writes', () async {
      final t = _FakeTransport((fn, p) => fail('no backend call'));
      final repo = SupabasePrintersRepository(
        transport: t,
        scope: AdminScope(
          organizationId: 'o',
          organizationName: 'Org',
          restaurantId: null,
          restaurantName: null,
          branchId: null,
          branchName: null,
          currencyCode: 'USD',
          actingRole: AdminScope.demo.actingRole,
        ),
        currentUserId: () => 'u',
      );
      final result = await repo.deletePrinter('p-1');
      result.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<AdminValidation>()),
      );
      expect(t.calls, isEmpty);
    });
  });

  group('PrintersScreen', () {
    Future<void> pump(WidgetTester tester, PrintersRepository repo) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(body: PrintersScreen(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders printers with the honest transport notice', (
      tester,
    ) async {
      await pump(tester, InMemoryPrintersStore());
      expect(find.text('Front counter'), findsOneWidget);
      expect(find.text('Kitchen pass'), findsOneWidget);
      // The honest adapter state: configuration only, no dispatch.
      expect(
        find.text('Configuration only — no print transport yet'),
        findsOneWidget,
      );
      // Never a fake print success anywhere.
      expect(find.textContaining('printed'), findsNothing);
    });

    testWidgets('adds a network printer through the wizard', (tester) async {
      final store = InMemoryPrintersStore();
      await pump(tester, store);
      await tester.tap(find.text('Add printer'));
      await tester.pumpAndSettle();

      // Step 1: purpose (receipt preselected) -> Next.
      expect(find.text('What do you want to print?'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      // Step 2: connection (network preselected) -> Next.
      expect(find.text('How is the printer connected?'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      // Step 3: details — name + host are all a network printer needs.
      expect(find.text('Printer details'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Display name'),
        'Bar printer',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Host / IP address'),
        '10.0.0.60',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final snapshot = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      expect(
        snapshot.printers.any((p) => p.displayName == 'Bar printer'),
        isTrue,
      );
      expect(find.text('Bar printer'), findsOneWidget);
    });

    testWidgets('routes a printer to a station', (tester) async {
      final store = InMemoryPrintersStore();
      await pump(tester, store);
      await tester.tap(find.text('Route to station').first);
      await tester.pumpAndSettle();
      expect(find.text('Route printer to a station'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final snapshot = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      // The first printer now routes to the first station (Grill).
      expect(
        snapshot.stationsFor('demo-printer-receipt').map((s) => s.name),
        contains('Grill'),
      );
    });

    testWidgets('a Bluetooth printer shows the config-only honesty note', (
      tester,
    ) async {
      final store = InMemoryPrintersStore();
      await store.upsertPrinter(
        displayName: 'BT printer',
        connectionType: PrinterConnectionType.bluetooth,
        role: PrinterRole.receipt,
        paperWidth: '58mm',
        connectionConfig: const {'bluetooth_id': 'BT-01'},
        isEnabled: true,
      );
      await pump(tester, store);
      expect(
        find.text('Configuration only — this transport is not installed yet.'),
        findsOneWidget,
      );
    });

    // Sprint UX: the dialog is a guided 3-step wizard (purpose -> connection
    // -> details), hides technical fields under Advanced, and is honest per
    // transport.
    group('guided add wizard', () {
      testWidgets('step titles render in order and Back returns a step', (
        tester,
      ) async {
        await pump(tester, InMemoryPrintersStore());
        await tester.tap(find.text('Add printer'));
        await tester.pumpAndSettle();

        expect(find.text('What do you want to print?'), findsOneWidget);
        expect(find.text('How is the printer connected?'), findsNothing);
        expect(find.text('Printer details'), findsNothing);
        // Save only exists on the last step; Back never on the first.
        expect(find.text('Save'), findsNothing);
        expect(find.text('Back'), findsNothing);

        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('How is the printer connected?'), findsOneWidget);

        // Back returns to step 1 without losing the flow.
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        expect(find.text('What do you want to print?'), findsOneWidget);

        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('Printer details'), findsOneWidget);
        expect(find.text('Next'), findsNothing);
        expect(find.text('Save'), findsOneWidget);
      });

      testWidgets('network: the port is hidden under Advanced (default 9100) '
          'and the dialog says it saves config only', (tester) async {
        await pump(tester, InMemoryPrintersStore());
        await tester.tap(find.text('Add printer'));
        await tester.pumpAndSettle();

        // Purpose tiles carry plain-language hints.
        expect(
          find.text('Bills for customers at the counter.'),
          findsOneWidget,
        );
        expect(find.text('Tickets for the kitchen staff.'), findsOneWidget);
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();

        // Step 2: network is preselected and shows its honest requirement.
        expect(
          find.text(
            'The printer must be on the same Wi-Fi/network as this device.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();

        // Step 3, simple by default: host is asked for, the port is NOT.
        expect(
          find.widgetWithText(TextFormField, 'Host / IP address'),
          findsOneWidget,
        );
        expect(find.widgetWithText(TextFormField, 'Port'), findsNothing);
        // Honest for every type: saving configures, never prints.
        expect(
          find.text(
            'This build saves the printer configuration only — nothing is '
            'printed yet.',
          ),
          findsOneWidget,
        );
        // Never a fake print success.
        expect(find.textContaining('print succeeded'), findsNothing);

        // Advanced reveals the port, pre-filled with the 9100 default.
        await tester.tap(find.text('Advanced'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextFormField, 'Port'), findsOneWidget);
        expect(find.text('9100'), findsOneWidget);
      });

      testWidgets('bluetooth: the selected tile and the details step show the '
          'web-discovery message, no identifier is required, and it still '
          'saves', (tester) async {
        final store = InMemoryPrintersStore();
        await pump(tester, store);
        await tester.tap(find.text('Add printer'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();

        // Selecting the Bluetooth tile surfaces the honest hint under it.
        await tester.tap(find.text('Bluetooth'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Bluetooth discovery is not available in the web app yet. Save '
            'configuration only.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();

        // Step 3 repeats the honesty banner instead of demanding a host.
        expect(
          find.text(
            'Bluetooth discovery is not available in the web app yet. Save '
            'configuration only.',
          ),
          findsOneWidget,
        );
        // No host demanded, no fake scan — a name alone saves the config.
        expect(
          find.widgetWithText(TextFormField, 'Host / IP address'),
          findsNothing,
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Display name'),
          'Belt printer',
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        final snapshot = (await store.load()).fold(
          (s) => s,
          (f) => fail('expected success'),
        );
        final saved = snapshot.printers.singleWhere(
          (p) => p.displayName == 'Belt printer',
        );
        expect(saved.connectionType, PrinterConnectionType.bluetooth);
      });

      testWidgets('usb: shows the native-adapter message', (tester) async {
        await pump(tester, InMemoryPrintersStore());
        await tester.tap(find.text('Add printer'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('USB'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'USB printing requires the desktop/native printer adapter. Save '
            'configuration only.',
          ),
          findsOneWidget,
        );

        // The details step repeats the same honest message.
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'USB printing requires the desktop/native printer adapter. Save '
            'configuration only.',
          ),
          findsOneWidget,
        );
      });
    });

    // Honest per-printer status + the permanently disabled test print.
    group('printer status and test print', () {
      testWidgets('status pills are honest per state', (tester) async {
        final store = InMemoryPrintersStore();
        await store.upsertPrinter(
          displayName: 'Paused printer',
          connectionType: PrinterConnectionType.network,
          role: PrinterRole.receipt,
          paperWidth: '80mm',
          connectionConfig: const {'host': '10.0.0.9', 'port': 9100},
          isEnabled: false,
        );
        await store.upsertPrinter(
          displayName: 'Belt printer',
          connectionType: PrinterConnectionType.bluetooth,
          role: PrinterRole.receipt,
          paperWidth: '58mm',
          connectionConfig: const {'bluetooth_id': 'BT-9'},
          isEnabled: true,
        );
        await pump(tester, store);

        // Both enabled demo network printers: config saved, no adapter.
        expect(find.text('Configured only'), findsNWidgets(2));
        // The enabled Bluetooth printer needs the (absent) print bridge.
        expect(find.text('Requires print bridge'), findsOneWidget);
        // The paused printer: the enabled pill AND the status pill both read
        // Disabled on that one card.
        expect(find.text('Disabled'), findsNWidgets(2));
        // HONESTY: no print adapter is registered in this build, so the
        // "ready" status must be unreachable — never faked.
        expect(find.text('Ready via network adapter'), findsNothing);
      });

      testWidgets('test print is always disabled with an honest explanation', (
        tester,
      ) async {
        await pump(tester, InMemoryPrintersStore());

        // One affordance per card (two demo printers) — all disabled.
        final buttons = tester
            .widgetList<TextButton>(
              find.widgetWithText(TextButton, 'Test print'),
            )
            .toList();
        expect(buttons, hasLength(2));
        for (final button in buttons) {
          expect(button.onPressed, isNull);
        }
        expect(
          find.text(
            'Test print needs the print adapter or bridge — not available in '
            'this web build.',
          ),
          findsNWidgets(2),
        );
        // Never a fake success path anywhere on the page.
        expect(find.textContaining('print succeeded'), findsNothing);
        expect(find.textContaining('printed'), findsNothing);
      });
    });
  });
}
