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

Future<void> _pump(
  WidgetTester tester, {
  required List<AdminDevice> devices,
  required List<StaffMember> staff,
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
            printersRepository: _EmptyPrinters(),
            staffRepository: _StaffStub(staff),
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

void main() {
  testWidgets('empty branch: next-step guidance for devices/printers/staff', (
    tester,
  ) async {
    await _pump(tester, devices: const [], staff: const []);
    expect(find.text('Setup'), findsOneWidget);
    expect(find.text('0/0'), findsNWidgets(3));
    expect(find.textContaining('No devices yet'), findsOneWidget);
    expect(find.textContaining('No printers configured yet'), findsOneWidget);
  });

  testWidgets('unpaired devices raise the pairing warning', (tester) async {
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
  });

  testWidgets('a ready branch shows the ready banner', (tester) async {
    await _pump(
      tester,
      devices: const [_activeDevice],
      staff: const [_staffWithPin],
    );
    expect(find.text('1/1'), findsNWidgets(2)); // devices + staff metrics
    expect(find.textContaining('No device is paired'), findsNothing);
    expect(find.textContaining('ready'), findsWidgets);
  });

  testWidgets('metric cards navigate to their tabs', (tester) async {
    final opened = <String>[];
    await _pump(
      tester,
      devices: const [_activeDevice],
      staff: const [_staffWithPin],
      onOpen: opened.add,
    );
    await tester.tap(find.text('Devices'));
    await tester.tap(find.text('Printers'));
    await tester.tap(find.text('Staff PINs'));
    expect(opened, ['devices', 'printers', 'staff']);
  });

  testWidgets('no staff with a PIN blocks the order loop (warning)', (
    tester,
  ) async {
    await _pump(
      tester,
      devices: const [_activeDevice],
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
  });
}
