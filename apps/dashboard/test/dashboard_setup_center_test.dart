import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_dashboard/src/printers/printer_models.dart';
import 'package:restoflow_dashboard/src/printers/printers_repository.dart';
import 'package:restoflow_dashboard/src/setup/setup_center.dart';
import 'package:restoflow_dashboard/src/staff/staff_models.dart';
import 'package:restoflow_dashboard/src/staff/staff_repository.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// A devices repo stub: only [loadDevices] matters for the setup center.
class _DevicesStub extends DemoAdminStore {
  _DevicesStub(this._devices) : super(scope: AdminScope.demo);
  final List<AdminDevice> _devices;

  @override
  Future<AdminResult<List<AdminDevice>>> loadDevices() async =>
      Success(_devices);
}

class _EmptyPrinters implements PrintersRepository {
  @override
  Future<AdminResult<PrintersSnapshot>> load() async =>
      const Success(PrintersSnapshot(printers: [], routes: [], stations: []));

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

/// A printers stub with a fixed snapshot (the setup center only loads).
class _PrintersStub extends _EmptyPrinters {
  _PrintersStub(this._snapshot);
  final PrintersSnapshot _snapshot;

  @override
  Future<AdminResult<PrintersSnapshot>> load() async => Success(_snapshot);
}

class _MenuStub implements MenuReadSource {
  _MenuStub(this._snapshot);
  final MenuSnapshot _snapshot;

  @override
  Future<MenuSnapshot> load(MenuScope scope) async => _snapshot;
}

MenuItem _menuItem({required bool isActive}) => MenuItem(
  id: 'item-$isActive',
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: null,
  menuCategoryId: 'cat-1',
  name: 'Item',
  description: null,
  basePriceMinor: 1200,
  currencyCode: 'USD',
  defaultStationId: null,
  displayOrder: 0,
  isActive: isActive,
);

Future<void> _pump(
  WidgetTester tester, {
  required List<AdminDevice> devices,
  required List<StaffMember> staff,
  List<MenuItem>? menuItems,
  PrintersSnapshot? printers,
  void Function(String)? onOpen,
  Locale? locale,
}) async {
  tester.view.physicalSize = const Size(1400, 2200);
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
          child: DashboardSetupCenter(
            devicesRepository: _DevicesStub(devices),
            printersRepository: printers == null
                ? _EmptyPrinters()
                : _PrintersStub(printers),
            staffRepository: _StaffStub(staff),
            menuReadSource: menuItems == null
                ? null
                : _MenuStub(MenuSnapshot(items: menuItems)),
            menuScope: menuItems == null ? null : demoMenuScope,
            onOpenMenu: () => onOpen?.call('menu'),
            onOpenDevices: () => onOpen?.call('devices'),
            onOpenPrinters: () => onOpen?.call('printers'),
            onOpenStaff: () => onOpen?.call('staff'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _activeDevice = AdminDevice(
  id: 'd-1',
  label: 'Counter POS',
  deviceType: 'pos',
  branchLabel: 'Main',
  status: DeviceLifecycleStatus.active,
);

const _staffWithPin = StaffMember(
  employeeProfileId: 'e-1',
  displayName: 'Amira K.',
  role: MembershipRole.cashier,
  hasPin: true,
  employmentStatus: 'active',
);

const _activeKds = AdminDevice(
  id: 'd-2',
  label: 'Kitchen display',
  deviceType: 'kds',
  branchLabel: 'Main',
  status: DeviceLifecycleStatus.active,
);

const _onePrinter = PrintersSnapshot(
  printers: [
    PrinterDevice(
      id: 'p-1',
      displayName: 'Front counter',
      connectionType: PrinterConnectionType.network,
      role: PrinterRole.receipt,
      paperWidth: '80mm',
      connectionConfig: {'host': '10.0.0.50', 'port': 9100},
      isEnabled: true,
    ),
  ],
  routes: [],
  stations: [],
);

void main() {
  testWidgets('empty workspace: a guided checklist with a fixing action per '
      'step (menu, POS, KDS, printer)', (tester) async {
    await _pump(
      tester,
      devices: const [],
      staff: const [],
      menuItems: const [],
    );
    expect(find.text('Setup'), findsOneWidget);
    // Four readiness stat chips now: menu + devices + printers + staff PINs.
    expect(find.textContaining('0/0'), findsNWidgets(4));
    // RF-132: the first step is the prominent warning; the rest live behind
    // the compact disclosure — expand it to reach every remaining step.
    expect(find.textContaining('No menu items yet'), findsOneWidget);
    expect(find.text('Add your first menu item'), findsOneWidget);
    await tester.tap(find.byKey(const Key('setup-more-steps')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No POS device yet'), findsOneWidget);
    expect(find.text('Create POS device'), findsOneWidget);
    expect(find.textContaining('No kitchen display yet'), findsOneWidget);
    expect(find.text('Create kitchen display'), findsOneWidget);
    expect(find.textContaining('No printers configured yet'), findsOneWidget);
    expect(find.text('Add printer'), findsOneWidget);
  });

  testWidgets('unpaired devices raise the pairing warning AND explain how '
      'to pair', (tester) async {
    await _pump(
      tester,
      devices: const [
        AdminDevice(
          id: 'd-1',
          label: 'Counter POS',
          deviceType: 'pos',
          branchLabel: 'Main',
          status: DeviceLifecycleStatus.codeIssued,
        ),
      ],
      staff: const [_staffWithPin],
    );
    // The pairing step sits behind the disclosure (the missing kitchen
    // display is the higher-priority prominent warning) — expand to it.
    await tester.tap(find.byKey(const Key('setup-more-steps')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No device is paired yet'), findsOneWidget);
    // The concrete instruction the owner asked for.
    expect(
      find.textContaining('enter the pairing code from the Devices tab'),
      findsOneWidget,
    );
  });

  testWidgets('a fully set-up branch shows the ready banner and no steps', (
    tester,
  ) async {
    await _pump(
      tester,
      devices: const [_activeDevice, _activeKds],
      staff: const [_staffWithPin],
      menuItems: [_menuItem(isActive: true)],
      printers: _onePrinter,
    );
    expect(find.text('Branch ready for service'), findsOneWidget);
    expect(find.textContaining('No device is paired'), findsNothing);
    expect(find.textContaining('No menu items yet'), findsNothing);
    expect(find.textContaining('No POS device yet'), findsNothing);
  });

  testWidgets('readiness stat chips navigate to their tabs (menu included)', (
    tester,
  ) async {
    final opened = <String>[];
    await _pump(
      tester,
      devices: const [_activeDevice, _activeKds],
      staff: const [_staffWithPin],
      menuItems: [_menuItem(isActive: true)],
      printers: _onePrinter,
      onOpen: opened.add,
    );
    await tester.tap(find.byKey(const Key('setup-stat-menu')));
    await tester.tap(find.byKey(const Key('setup-stat-devices')));
    await tester.tap(find.byKey(const Key('setup-stat-printers')));
    await tester.tap(find.byKey(const Key('setup-stat-staff')));
    expect(opened, ['menu', 'devices', 'printers', 'staff']);
  });

  testWidgets('checklist buttons navigate to the fixing tab', (tester) async {
    final opened = <String>[];
    await _pump(
      tester,
      devices: const [],
      staff: const [],
      menuItems: const [],
      onOpen: opened.add,
    );
    // RF-132: expand the disclosure so every remaining step's action is
    // reachable, then verify each original callback still fires.
    await tester.tap(find.byKey(const Key('setup-more-steps')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add your first menu item'));
    await tester.tap(find.text('Create POS device'));
    await tester.tap(find.text('Create kitchen display'));
    await tester.tap(find.text('Add printer'));
    expect(opened, ['menu', 'devices', 'devices', 'printers']);
  });

  testWidgets('a menu of ONLY disabled items still warns (nothing to sell)', (
    tester,
  ) async {
    await _pump(
      tester,
      devices: const [_activeDevice, _activeKds],
      staff: const [_staffWithPin],
      menuItems: [_menuItem(isActive: false)],
      printers: _onePrinter,
    );
    expect(find.textContaining('0/1'), findsOneWidget); // active / total
    expect(find.textContaining('No menu items yet'), findsOneWidget);
  });

  testWidgets('no staff with a PIN blocks the order loop (warning + action)', (
    tester,
  ) async {
    await _pump(
      tester,
      devices: const [_activeDevice, _activeKds],
      staff: const [
        StaffMember(
          employeeProfileId: 'e-2',
          displayName: 'No Pin',
          role: MembershipRole.cashier,
          hasPin: false,
          employmentStatus: 'active',
        ),
      ],
    );
    // The missing printers are the prominent warning; the staff-PIN step sits
    // behind the disclosure — expand to it.
    await tester.tap(find.byKey(const Key('setup-more-steps')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No staff member has a PIN yet'),
      findsOneWidget,
    );
    expect(find.text('Create staff PIN'), findsOneWidget);
  });

  // ── RF-132 (Codex review): the pending-steps disclosure ────────────────────

  testWidgets('RF-132: only the first pending step is prominent; the '
      'disclosure names the exact remaining count', (tester) async {
    // Empty workspace => 5 pending steps: menu, POS, KDS, printers, staff PIN.
    await _pump(
      tester,
      devices: const [],
      staff: const [],
      menuItems: const [],
    );
    // Prominent: ONLY the first (menu) step.
    expect(find.textContaining('No menu items yet'), findsOneWidget);
    expect(find.textContaining('No POS device yet'), findsNothing);
    expect(find.textContaining('No kitchen display yet'), findsNothing);
    expect(find.textContaining('No printers configured yet'), findsNothing);
    expect(find.textContaining('No staff member has a PIN yet'), findsNothing);
    // The disclosure is present and its count is exact (4 remaining).
    expect(find.byKey(const Key('setup-more-steps')), findsOneWidget);
    expect(find.text('4 more setup steps'), findsOneWidget);
  });

  testWidgets('RF-132: expanding the disclosure exposes EVERY remaining step '
      'in the original order and every callback still fires', (tester) async {
    final opened = <String>[];
    await _pump(
      tester,
      devices: const [],
      staff: const [],
      menuItems: const [],
      onOpen: opened.add,
    );
    await tester.tap(find.byKey(const Key('setup-more-steps')));
    await tester.pumpAndSettle();

    // All four remaining steps are now exposed…
    final remaining = <String>[
      'No POS device yet',
      'No kitchen display yet',
      'No printers configured yet',
      'No staff member has a PIN yet',
    ];
    for (final title in remaining) {
      expect(find.textContaining(title), findsOneWidget);
    }
    // …in their original order (top to bottom).
    double topOf(String title) =>
        tester.getTopLeft(find.textContaining(title)).dy;
    for (var i = 1; i < remaining.length; i++) {
      expect(
        topOf(remaining[i - 1]),
        lessThan(topOf(remaining[i])),
        reason: '"${remaining[i - 1]}" precedes "${remaining[i]}"',
      );
    }
    // Every original action still navigates (prominent + all disclosed).
    await tester.tap(find.text('Add your first menu item'));
    await tester.tap(find.text('Create POS device'));
    await tester.tap(find.text('Create kitchen display'));
    await tester.tap(find.text('Add printer'));
    await tester.ensureVisible(find.text('Create staff PIN'));
    await tester.tap(find.text('Create staff PIN'));
    expect(opened, ['menu', 'devices', 'devices', 'printers', 'staff']);
  });

  testWidgets('RF-132: a single pending step shows only its warning — no '
      'disclosure', (tester) async {
    // Only the menu step is pending (everything else is satisfied).
    await _pump(
      tester,
      devices: const [_activeDevice, _activeKds],
      staff: const [_staffWithPin],
      menuItems: [_menuItem(isActive: false)],
      printers: _onePrinter,
    );
    expect(find.textContaining('No menu items yet'), findsOneWidget);
    expect(find.byKey(const Key('setup-more-steps')), findsNothing);
  });

  testWidgets('RF-132: a fully ready branch shows no warnings and no '
      'disclosure', (tester) async {
    await _pump(
      tester,
      devices: const [_activeDevice, _activeKds],
      staff: const [_staffWithPin],
      menuItems: [_menuItem(isActive: true)],
      printers: _onePrinter,
    );
    expect(find.text('Branch ready for service'), findsOneWidget);
    expect(find.byKey(const Key('setup-more-steps')), findsNothing);
    expect(find.textContaining('No menu items yet'), findsNothing);
  });

  for (final locale in const [Locale('ar'), Locale('he'), Locale('en')]) {
    testWidgets('RF-132: the prominent warning + expanded disclosure render in '
        '${locale.languageCode} without overflow', (tester) async {
      await _pump(
        tester,
        devices: const [],
        staff: const [],
        menuItems: const [],
        locale: locale,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('setup-more-steps')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('setup-more-steps')), findsOneWidget);
    });
  }

  testWidgets('LIVE-UX-001: a REVOKED-only POS does not satisfy setup — it '
      'still prompts to create a POS (revoked is not counted)', (tester) async {
    await _pump(
      tester,
      devices: const [
        AdminDevice(
          id: 'd-rev',
          label: 'Old POS',
          deviceType: 'pos',
          branchLabel: 'Main',
          status: DeviceLifecycleStatus.revoked,
        ),
        _activeKds,
      ],
      staff: const [_staffWithPin],
    );
    // The revoked POS must NOT count as a usable POS.
    expect(find.textContaining('No POS device yet'), findsOneWidget);
    expect(find.text('Create POS device'), findsOneWidget);
    // And it must NOT inflate the device total: 1 live device (the KDS), so the
    // devices card is "1/1", never "1/2" (which is what a counted revoke gives).
    expect(find.text('1/2'), findsNothing);
  });
}
