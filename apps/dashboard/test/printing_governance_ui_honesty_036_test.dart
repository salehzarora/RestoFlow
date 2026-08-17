import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_dashboard/src/admin/branch_kitchen_workflow_repository.dart';
import 'package:restoflow_dashboard/src/printers/printer_models.dart';
import 'package:restoflow_dashboard/src/printers/printers_repository.dart';
import 'package:restoflow_dashboard/src/printers/printers_screen.dart';
import 'package:restoflow_dashboard/src/setup/setup_center.dart';
import 'package:restoflow_dashboard/src/staff/staff_models.dart';
import 'package:restoflow_dashboard/src/staff/staff_repository.dart';
import 'package:restoflow_dashboard/src/state/setup_device_providers.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// PRINTING-GOVERNANCE-UI-HONESTY-036.
///
/// The Overview used to present `enabled server printer rows / total rows` as
/// a readiness dimension with equal weight, which reads as physical printer
/// health. It is not: it proves nothing about power, pairing, bridge status or
/// reachability. These tests pin the honest replacement —
///
///   * printing configuration is a readiness dimension ONLY for `printer_only`
///     branches, where a qualifying server record really is a prerequisite;
///   * the qualification MIRRORS the server (`get_device_printer_assignments`):
///     a live row whose role serves kitchen tickets. `paper_width` is NOT a
///     server qualification and must not be invented as one here;
///   * a KDS-mode branch is never penalised and never nagged;
///   * no wording anywhere claims a printer is online/reachable.
///
/// …and the Printing page reframe: the dead Test Print control and the inert
/// endpoint fields are gone, while the write path and legacy stored data are
/// untouched.

// ---------------------------------------------------------------------------
// Overview harness
// ---------------------------------------------------------------------------

class _DevicesStub extends DemoAdminStore {
  _DevicesStub(this._devices) : super(scope: AdminScope.demo);
  final List<AdminDevice> _devices;

  @override
  Future<AdminResult<List<AdminDevice>>> loadDevices() async =>
      Success(_devices);
}

class _PrintersStub implements PrintersRepository {
  _PrintersStub(this._snapshot);
  final PrintersSnapshot _snapshot;

  @override
  Future<AdminResult<PrintersSnapshot>> load() async => Success(_snapshot);

  @override
  Future<AdminResult<void>> upsertPrinter({
    String? id,
    required String displayName,
    required PrinterConnectionType connectionType,
    required PrinterRole role,
    required String paperWidth,
    required Map<String, Object?> connectionConfig,
    required bool isEnabled,
  }) async => const Success(null);

  @override
  Future<AdminResult<void>> setRoute({
    required String stationId,
    required String printerDeviceId,
    required bool isEnabled,
  }) async => const Success(null);

  @override
  Future<AdminResult<void>> deletePrinter(String id) async =>
      const Success(null);
}

class _StaffStub implements StaffRepository {
  _StaffStub(this._staff);
  final List<StaffMember> _staff;

  @override
  Future<AdminResult<List<StaffMember>>> load() async => Success(_staff);

  @override
  Future<AdminResult<StaffMember>> create({
    required String displayName,
    required MembershipRole role,
    StaffCapabilities? capabilities,
    String? clientRequestId,
  }) async => throw UnimplementedError();

  @override
  Future<AdminResult<void>> setPin({
    required String employeeProfileId,
    required String pin,
  }) async => throw UnimplementedError();

  @override
  Future<AdminResult<void>> setCapabilities({
    required String employeeProfileId,
    required StaffCapabilities capabilities,
  }) async => throw UnimplementedError();
}

class _WorkflowStub implements BranchKitchenWorkflowRepository {
  _WorkflowStub(this._mode);
  final KitchenWorkflowMode? _mode;

  @override
  Future<KitchenWorkflowMode?> read() async => _mode;

  @override
  Future<KitchenWorkflowWriteResult> setMode(KitchenWorkflowMode mode) async =>
      throw UnimplementedError();
}

const _activePos = AdminDevice(
  id: 'd-pos',
  label: 'Counter POS',
  deviceType: 'pos',
  branchLabel: 'Main',
  status: DeviceLifecycleStatus.active,
);
const _activeKds = AdminDevice(
  id: 'd-kds',
  label: 'Kitchen',
  deviceType: 'kds',
  branchLabel: 'Main',
  status: DeviceLifecycleStatus.active,
);
const _staffWithPin = StaffMember(
  employeeProfileId: 'e-1',
  displayName: 'Cashier',
  role: MembershipRole.cashier,
  hasPin: true,
  employmentStatus: 'active',
);

PrinterDevice _printer({
  required String id,
  required PrinterRole role,
  bool isEnabled = true,
  String paperWidth = '80mm',
}) => PrinterDevice(
  id: id,
  displayName: 'Printer $id',
  connectionType: PrinterConnectionType.network,
  role: role,
  paperWidth: paperWidth,
  connectionConfig: const {'host': '10.0.0.50', 'port': 9100},
  isEnabled: isEnabled,
);

PrintersSnapshot _snapshot(List<PrinterDevice> printers) =>
    PrintersSnapshot(printers: printers, routes: const [], stations: const []);

Future<void> _pumpOverview(
  WidgetTester tester, {
  required KitchenWorkflowMode? mode,
  required List<PrinterDevice> printers,
  Locale? locale,
  List<String>? opened,
}) async {
  tester.view.physicalSize = const Size(1440, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProviderScope(
            overrides: [
              setupDevicesRepositoryProvider.overrideWithValue(
                _DevicesStub(const [_activePos, _activeKds]),
              ),
              setupPrintersRepositoryProvider.overrideWithValue(
                _PrintersStub(_snapshot(printers)),
              ),
              setupStaffRepositoryProvider.overrideWithValue(
                _StaffStub(const [_staffWithPin]),
              ),
              setupKitchenWorkflowRepositoryProvider.overrideWithValue(
                _WorkflowStub(mode),
              ),
            ],
            child: DashboardSetupCenter(
              onOpenMenu: () => opened?.add('menu'),
              onOpenDevices: () => opened?.add('devices'),
              onOpenPrinters: () => opened?.add('printers'),
              onOpenStaff: () => opened?.add('staff'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The readiness percentage the strip is currently showing.
int _percent(WidgetTester tester) {
  final match = RegExp(r'(\d+)\s*%');
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final data = text.data;
    if (data == null) continue;
    final m = match.firstMatch(data);
    if (m != null) return int.parse(m.group(1)!);
  }
  fail('no percentage rendered');
}

// ---------------------------------------------------------------------------
// Printing page harness
// ---------------------------------------------------------------------------

class _RecordingTransport implements SyncRpcTransport {
  _RecordingTransport(this._handler);
  final Object? Function(String fn, Map<String, dynamic> params) _handler;
  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return _handler(function, params);
  }
}

/// One LEGACY row carrying endpoint data the wizard no longer shows.
Map<String, dynamic> _legacyList() => {
  'ok': true,
  'printers': [
    {
      'id': 'p-legacy',
      'display_name': 'Front counter',
      'connection_type': 'network',
      'role': 'receipt',
      'paper_width': '80mm',
      // The exact blob that must survive an edit untouched.
      'connection_config': {
        'host': '10.0.0.50',
        'port': 9100,
        'legacy_note': 'set before the endpoint fields were removed',
      },
      'is_enabled': true,
      'revision': 1,
    },
  ],
  'routes': <Map<String, dynamic>>[],
  'stations': [
    {'id': 's-1', 'name': 'Grill'},
  ],
};

Future<_RecordingTransport> _pumpPrinting(
  WidgetTester tester, {
  Locale? locale,
  Size size = const Size(1440, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final transport = _RecordingTransport((fn, p) {
    if (fn == 'list_printers') return _legacyList();
    return {'ok': true};
  });
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      // A Scaffold ancestor is required: a successful write shows a SnackBar
      // through ScaffoldMessenger, which asserts without one.
      home: Scaffold(
        body: PrintersScreen(
          repository: SupabasePrintersRepository(
            transport: transport,
            scope: AdminScope.demo,
            currentUserId: () => 'u-1',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return transport;
}

void main() {
  // =========================================================================
  group('A. Overview — printing CONFIGURATION, never printer health', () {
    testWidgets('A1. printer_only + an enabled kitchen printer: the printing '
        'dimension PASSES and is labelled as configuration', (tester) async {
      await _pumpOverview(
        tester,
        mode: KitchenWorkflowMode.printerOnly,
        printers: [_printer(id: 'k1', role: PrinterRole.kitchen)],
      );
      expect(find.byKey(const Key('setup-stat-printers')), findsOneWidget);
      expect(find.text('Printing'), findsOneWidget);
      // Everything else in this fixture is ready, so a passing printing
      // dimension is the difference between 100% and not.
      expect(_percent(tester), 100);
      // …and no next step nags about printers.
      expect(
        find.textContaining('No live kitchen printer configured'),
        findsNothing,
      );
    });

    testWidgets('A2. printer_only: a `both`-role printer also qualifies — it '
        'is kitchen-capable', (tester) async {
      await _pumpOverview(
        tester,
        mode: KitchenWorkflowMode.printerOnly,
        printers: [_printer(id: 'b1', role: PrinterRole.both)],
      );
      expect(_percent(tester), 100);
    });

    testWidgets('A3. printer_only: a 58mm kitchen printer STILL qualifies — '
        'paper width is not a server qualification', (tester) async {
      await _pumpOverview(
        tester,
        mode: KitchenWorkflowMode.printerOnly,
        printers: [
          _printer(id: 'k58', role: PrinterRole.kitchen, paperWidth: '58mm'),
        ],
      );
      expect(
        _percent(tester),
        100,
        reason: 'a working 58mm printer_only branch must not be failed',
      );
    });

    testWidgets('A4. printer_only + NO qualifying printer: the dimension '
        'fails and the next step names the real gap', (tester) async {
      final opened = <String>[];
      await _pumpOverview(
        tester,
        mode: KitchenWorkflowMode.printerOnly,
        // A receipt-only printer is NOT kitchen-capable.
        printers: [_printer(id: 'r1', role: PrinterRole.receipt)],
        opened: opened,
      );
      expect(_percent(tester), lessThan(100));
      expect(
        find.textContaining('No live kitchen printer configured'),
        findsOneWidget,
      );
      await tester.tap(find.text('Add printer'));
      await tester.pumpAndSettle();
      expect(opened, ['printers']);
    });

    testWidgets('A5. printer_only: a DISABLED kitchen printer does not '
        'qualify', (tester) async {
      await _pumpOverview(
        tester,
        mode: KitchenWorkflowMode.printerOnly,
        printers: [
          _printer(id: 'k1', role: PrinterRole.kitchen, isEnabled: false),
        ],
      );
      expect(_percent(tester), lessThan(100));
    });

    testWidgets('A6. NOT printer_only: the printing tile is HIDDEN, readiness '
        'is not penalised, and no "Add printer" step appears', (tester) async {
      await _pumpOverview(
        tester,
        mode: KitchenWorkflowMode.kds,
        printers: const [],
      );
      expect(find.byKey(const Key('setup-stat-printers')), findsNothing);
      expect(find.text('Printing'), findsNothing);
      expect(
        find.textContaining('No live kitchen printer configured'),
        findsNothing,
      );
      expect(find.textContaining('No printers configured'), findsNothing);
      expect(find.text('Add printer'), findsNothing);
      // The denominator dropped with the dimension: zero printer rows leave a
      // KDS branch fully ready.
      expect(_percent(tester), 100);
    });

    testWidgets('A7. NOT printer_only: even WITH printer rows the tile stays '
        'out of readiness', (tester) async {
      await _pumpOverview(
        tester,
        mode: KitchenWorkflowMode.kds,
        printers: [_printer(id: 'k1', role: PrinterRole.kitchen)],
      );
      expect(find.byKey(const Key('setup-stat-printers')), findsNothing);
      expect(_percent(tester), 100);
    });

    testWidgets('A8. an UNREADABLE workflow mode is not treated as '
        'printer_only — a transport blip cannot invent a failing dimension', (
      tester,
    ) async {
      await _pumpOverview(tester, mode: null, printers: const []);
      expect(find.byKey(const Key('setup-stat-printers')), findsNothing);
      expect(_percent(tester), 100);
    });

    testWidgets('A9. the copy NEVER claims a printer is online, reachable or '
        'connected', (tester) async {
      await _pumpOverview(
        tester,
        mode: KitchenWorkflowMode.printerOnly,
        printers: [_printer(id: 'k1', role: PrinterRole.kitchen)],
      );
      final help = tester.widget<Text>(
        find.byKey(const Key('setup-printing-config-help')),
      );
      final copy = help.data!;
      expect(copy, contains('does not check'));
      for (final claim in const [
        'online',
        'reachable',
        'connected to',
        'printer is ready',
      ]) {
        expect(
          copy.toLowerCase().contains(claim.toLowerCase()) &&
              !copy.toLowerCase().contains('does not'),
          isFalse,
          reason: 'help copy must not assert "$claim"',
        );
      }
      // The label itself is configuration wording, not hardware wording.
      expect(find.text('Printers'), findsNothing);
    });

    for (final (locale, label) in const [
      (Locale('ar'), 'إعداد الطباعة'),
      (Locale('he'), 'הגדרת הדפסה'),
    ]) {
      testWidgets('A10. ${locale.languageCode}: the printing dimension renders '
          'its localized configuration label', (tester) async {
        final overflows = <String>[];
        final prior = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.exceptionAsString().contains('overflowed')) {
            overflows.add(details.toString());
          } else {
            prior?.call(details);
          }
        };
        await _pumpOverview(
          tester,
          mode: KitchenWorkflowMode.printerOnly,
          printers: [_printer(id: 'k1', role: PrinterRole.kitchen)],
          locale: locale,
        );
        FlutterError.onError = prior;
        expect(find.text(label), findsOneWidget);
        expect(
          overflows.where((o) => o.contains('setup_center.dart')),
          isEmpty,
        );
      });
    }
  });

  // =========================================================================
  group('B. Printing page — reframed, write path intact', () {
    testWidgets('B1. the dead Test Print control is absent', (tester) async {
      await _pumpPrinting(tester);
      expect(find.textContaining('Test print'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Test print'), findsNothing);
    });

    testWidgets('B2. the page is titled and framed as printing configuration, '
        'and points physical setup at the device', (tester) async {
      await _pumpPrinting(tester);
      expect(find.text('Printing setup'), findsWidgets);
      expect(
        find.textContaining('Each POS/KDS device configures its own physical'),
        findsWidgets,
      );
    });

    testWidgets('B3. no endpoint fields anywhere in the create wizard', (
      tester,
    ) async {
      await _pumpPrinting(tester);
      await tester.tap(find.text('Add printer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      for (final label in const [
        'Host / IP address',
        'Port',
        'Bluetooth identifier',
        'USB path',
      ]) {
        expect(
          find.widgetWithText(TextFormField, label),
          findsNothing,
          reason: '$label must not be asked for on the Dashboard',
        );
      }
      expect(find.text('Advanced'), findsNothing);
    });

    testWidgets('B4. CREATE sends the RPC contract default {} for '
        'connection_config', (tester) async {
      final t = await _pumpPrinting(tester);
      await tester.tap(find.text('Add printer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Display name'),
        'New printer',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final upsert = t.calls.lastWhere((c) => c.$1 == 'upsert_printer_device');
      expect(upsert.$2['p_connection_config'], isEmpty);
      expect(upsert.$2['p_display_name'], 'New printer');
      // The rest of the contract is unchanged.
      expect(upsert.$2.containsKey('p_role'), isTrue);
      expect(upsert.$2.containsKey('p_paper_width'), isTrue);
      expect(upsert.$2.containsKey('p_is_enabled'), isTrue);
    });

    testWidgets('B5. EDIT preserves the legacy connection_config VERBATIM — '
        'hiding a field must never destroy stored data', (tester) async {
      final t = await _pumpPrinting(tester);
      await tester.tap(find.text('Edit').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Display name'),
        'Renamed counter',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final upsert = t.calls.lastWhere((c) => c.$1 == 'upsert_printer_device');
      expect(upsert.$2['p_display_name'], 'Renamed counter');
      expect(upsert.$2['p_connection_config'], {
        'host': '10.0.0.50',
        'port': 9100,
        'legacy_note': 'set before the endpoint fields were removed',
      });
    });

    testWidgets('B6. EDIT preserves the stored config even when the '
        'connection TYPE changes — deletion is never the fallback', (
      tester,
    ) async {
      final t = await _pumpPrinting(tester);
      await tester.tap(find.text('Edit').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      // network -> bluetooth
      await tester.tap(find.text('Bluetooth'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final upsert = t.calls.lastWhere((c) => c.$1 == 'upsert_printer_device');
      expect(upsert.$2['p_connection_type'], 'bluetooth');
      expect(
        upsert.$2['p_connection_config'],
        {
          'host': '10.0.0.50',
          'port': 9100,
          'legacy_note': 'set before the endpoint fields were removed',
        },
        reason: 'the owner can no longer see or retype this — never drop it',
      );
    });

    testWidgets('B7. the governance write path is intact: enable/disable and '
        'station routing still reach their RPCs', (tester) async {
      final t = await _pumpPrinting(tester);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(
        t.calls.any((c) => c.$1 == 'upsert_printer_device'),
        isTrue,
        reason: 'enable/disable must still write',
      );

      await tester.tap(find.text('Route to station').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(t.calls.any((c) => c.$1 == 'set_printer_route'), isTrue);
    });

    for (final locale in const [Locale('ar'), Locale('he')]) {
      testWidgets('B8. ${locale.languageCode}: the reframed page renders '
          'without overflow at 1024x600', (tester) async {
        final overflows = <String>[];
        final prior = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.exceptionAsString().contains('overflowed')) {
            overflows.add(details.toString());
          } else {
            prior?.call(details);
          }
        };
        await _pumpPrinting(
          tester,
          locale: locale,
          size: const Size(1024, 600),
        );
        FlutterError.onError = prior;
        expect(
          overflows.where((o) => o.contains('printers_screen.dart')),
          isEmpty,
        );
      });
    }
  });
}
