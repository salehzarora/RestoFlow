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
  }) async => throw UnimplementedError();

  @override
  Future<AdminResult<void>> setPin({
    required String employeeProfileId,
    required String pin,
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
}) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
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
    // Four metrics now: menu + devices + printers + staff PINs.
    expect(find.text('0/0'), findsNWidgets(4));
    expect(find.textContaining('No menu items yet'), findsOneWidget);
    expect(find.text('Add your first menu item'), findsOneWidget);
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
    expect(
      find.text('This branch is ready: paired device and staff PIN in place.'),
      findsOneWidget,
    );
    expect(find.textContaining('No device is paired'), findsNothing);
    expect(find.textContaining('No menu items yet'), findsNothing);
    expect(find.textContaining('No POS device yet'), findsNothing);
  });

  testWidgets('metric cards navigate to their tabs (menu included)', (
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
    await tester.tap(find.text('Menu items'));
    await tester.tap(find.text('Devices'));
    await tester.tap(find.text('Printers'));
    await tester.tap(find.text('Staff PINs'));
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
    expect(find.text('0/1'), findsOneWidget); // active / total
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
    expect(
      find.textContaining('No staff member has a PIN yet'),
      findsOneWidget,
    );
    expect(find.text('Create staff PIN'), findsOneWidget);
  });

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
