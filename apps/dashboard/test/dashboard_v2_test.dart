import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_dashboard/main.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/setup/device_summary_card.dart';
import 'package:restoflow_dashboard/src/state/locale_controller.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Dashboard V2 — composition refinements over RF-132: the full-height rail,
/// the interactive sales-by-hour selection, and the honest device readiness
/// card slot in the lower operational row. All data comes from the existing
/// demo/real sources; nothing here fabricates values.

Widget _wrap({Widget? deviceSummary, Locale locale = const Locale('en')}) =>
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: DashboardHomeScreen(deviceSummary: deviceSummary),
      ),
    );

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// A devices repo stub over the demo store: fixed [loadDevices] payload.
class _DevicesStub extends DemoAdminStore {
  _DevicesStub(this._devices) : super(scope: AdminScope.demo);
  final List<AdminDevice> _devices;

  @override
  Future<AdminResult<List<AdminDevice>>> loadDevices() async =>
      Success(_devices);
}

/// A devices repo stub whose [loadDevices] always fails.
class _FailingDevicesStub extends DemoAdminStore {
  _FailingDevicesStub() : super(scope: AdminScope.demo);

  @override
  Future<AdminResult<List<AdminDevice>>> loadDevices() async =>
      const Failure(AdminNotFound());
}

void main() {
  testWidgets('the side rail runs the full viewport height with the header '
      'bar inside the content column', (tester) async {
    _size(tester, const Size(1320, 900));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialLocaleProvider.overrideWithValue(const Locale('en')),
        ],
        child: const DashboardApp(demoMode: true),
      ),
    );
    await tester.pumpAndSettle();

    final rail = tester.getRect(find.byKey(const Key('dashboard-side-rail')));
    // Full height: the floating panel spans the viewport (small margins only).
    expect(rail.top, lessThanOrEqualTo(16));
    expect(rail.bottom, greaterThanOrEqualTo(900 - 16));
    // The persistent header content (honest mode pill) is still present and
    // now sits INSIDE the content column — i.e. it does not span above the
    // rail: the pill starts after the rail's edge.
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final pill = find.text(l10n.dashboardModeDemoData);
    expect(pill, findsOneWidget);
    expect(
      tester.getTopLeft(pill).dx,
      greaterThan(rail.right),
      reason: 'header bar lives beside (not above) the full-height rail',
    );
  });

  testWidgets('the sales-by-hour chart offers REAL-point selection: tapping '
      'shows an hour + formatted-money tooltip from the demo series', (
    tester,
  ) async {
    _size(tester, const Size(1320, 2600));
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    final chart = find.byKey(const Key('sales-by-hour-chart'));
    expect(chart, findsOneWidget);
    expect(find.textContaining(':00\n'), findsNothing);
    await tester.tap(chart);
    await tester.pumpAndSettle();
    // The tooltip text is `<hour>:00\n<MoneyFormatter amount>` for a real
    // demo point — never an invented figure.
    expect(find.textContaining(RegExp(r'^\d{1,2}:00\n₪')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the device readiness slot joins the operational row below the '
      'analytics; without it the row keeps its three report cards', (
    tester,
  ) async {
    _size(tester, const Size(1320, 3200));
    // Without the slot (demo default): no device card.
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kpi-devices-summary')), findsNothing);
    expect(find.byKey(const Key('kpi-cash-sales')), findsOneWidget);

    // With the slot: the card renders inside the operational row (below the
    // analytics, above the detail sections), alongside the three report cards.
    await tester.pumpWidget(
      _wrap(
        deviceSummary: const RestoflowMetricCard(
          key: Key('kpi-devices-summary'),
          style: RestoflowMetricCardStyle.kpi,
          label: 'Devices',
          value: '1/2',
          icon: Icons.devices_outlined,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final deviceY = tester
        .getTopLeft(find.byKey(const Key('kpi-devices-summary')))
        .dy;
    final chartY = tester
        .getTopLeft(find.byKey(const Key('sales-by-hour-card')))
        .dy;
    final cashY = tester.getTopLeft(find.byKey(const Key('kpi-cash-sales'))).dy;
    final topItemsY = tester
        .getTopLeft(find.byKey(const Key('top-items-card')))
        .dy;
    expect(chartY, lessThan(deviceY));
    expect(deviceY, cashY, reason: 'device card shares the operational row');
    expect(deviceY, lessThan(topItemsY));
  });

  testWidgets('DashboardDeviceSummaryCard shows honest active/configured '
      'counts (revoked excluded) and opens the Devices tab', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: DashboardDeviceSummaryCard(
                repository: _DevicesStub(const [
                  AdminDevice(
                    id: 'd-1',
                    label: 'Counter POS',
                    deviceType: 'pos',
                    branchLabel: 'Main',
                    status: DeviceLifecycleStatus.active,
                  ),
                  AdminDevice(
                    id: 'd-2',
                    label: 'KDS',
                    deviceType: 'kds',
                    branchLabel: 'Main',
                    status: DeviceLifecycleStatus.codeIssued,
                  ),
                  AdminDevice(
                    id: 'd-3',
                    label: 'Old POS',
                    deviceType: 'pos',
                    branchLabel: 'Main',
                    status: DeviceLifecycleStatus.revoked,
                  ),
                ]),
                onOpenDevices: () => opened++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1 active of 2 configured (the revoked device counts nowhere).
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('Active of configured devices'), findsOneWidget);
    // Lifecycle wording only — never an online/offline heartbeat claim.
    expect(find.textContaining('online'), findsNothing);
    expect(find.textContaining('offline'), findsNothing);
    await tester.tap(find.byKey(const Key('kpi-devices-summary')));
    expect(opened, 1);
  });

  testWidgets('a failed device load shows the honest UNAVAILABLE card — '
      'no fake zero, and the Devices action stays reachable', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: DashboardDeviceSummaryCard(
                repository: _FailingDevicesStub(),
                onOpenDevices: () => opened++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final unavailable = find.byKey(const Key('kpi-devices-unavailable'));
    expect(unavailable, findsOneWidget);
    expect(find.byKey(const Key('kpi-devices-summary')), findsNothing);
    expect(find.text('0/0'), findsNothing);
    expect(find.text('n/a'), findsOneWidget);
    expect(find.text('Device status unavailable'), findsOneWidget);
    expect(
      tester.widget<RestoflowMetricCard>(unavailable).tone,
      RestoflowTone.warning,
    );
    await tester.tap(unavailable);
    expect(opened, 1);
  });

  testWidgets('DashboardDeviceSummaryCard reloads when its repository '
      'changes — the old repository counts are never shown for the new one', (
    tester,
  ) async {
    Widget card(DemoAdminStore repository) => MaterialApp(
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: DashboardDeviceSummaryCard(repository: repository),
          ),
        ),
      ),
    );

    const activePos = AdminDevice(
      id: 'a-1',
      label: 'POS A',
      deviceType: 'pos',
      branchLabel: 'Main',
      status: DeviceLifecycleStatus.active,
    );
    const pendingKds = AdminDevice(
      id: 'a-2',
      label: 'KDS A',
      deviceType: 'kds',
      branchLabel: 'Main',
      status: DeviceLifecycleStatus.codeIssued,
    );

    await tester.pumpWidget(card(_DevicesStub(const [activePos, pendingKds])));
    await tester.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);

    // Same widget position, DIFFERENT repository: its own counts load and
    // replace the previous repository's result.
    await tester.pumpWidget(
      card(
        _DevicesStub(const [
          activePos,
          AdminDevice(
            id: 'b-2',
            label: 'KDS B',
            deviceType: 'kds',
            branchLabel: 'Main',
            status: DeviceLifecycleStatus.active,
          ),
          AdminDevice(
            id: 'b-3',
            label: 'POS B',
            deviceType: 'pos',
            branchLabel: 'Main',
            status: DeviceLifecycleStatus.active,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('3/3'), findsOneWidget);
    expect(find.text('1/2'), findsNothing);
  });

  testWidgets('device readiness tone comes from the REAL lifecycle counts', (
    tester,
  ) async {
    AdminDevice device(String id, DeviceLifecycleStatus status) => AdminDevice(
      id: id,
      label: id,
      deviceType: 'pos',
      branchLabel: 'Main',
      status: status,
    );

    Future<void> pumpWith(List<AdminDevice> devices) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                // A fresh key per pump: each scenario is an independent load.
                child: DashboardDeviceSummaryCard(
                  key: UniqueKey(),
                  repository: _DevicesStub(devices),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    RestoflowTone toneOf() => tester
        .widget<RestoflowMetricCard>(
          find.byKey(const Key('kpi-devices-summary')),
        )
        .tone!;

    // All configured devices active => success.
    await pumpWith([
      device('d-1', DeviceLifecycleStatus.active),
      device('d-2', DeviceLifecycleStatus.active),
    ]);
    expect(find.text('2/2'), findsOneWidget);
    expect(toneOf(), RestoflowTone.success);

    // Partially active => warning.
    await pumpWith([
      device('d-1', DeviceLifecycleStatus.active),
      device('d-2', DeviceLifecycleStatus.codeIssued),
    ]);
    expect(find.text('1/2'), findsOneWidget);
    expect(toneOf(), RestoflowTone.warning);

    // Configured but none active => warning.
    await pumpWith([
      device('d-1', DeviceLifecycleStatus.pending),
      device('d-2', DeviceLifecycleStatus.codeIssued),
    ]);
    expect(find.text('0/2'), findsOneWidget);
    expect(toneOf(), RestoflowTone.warning);

    // Nothing configured => neutral (Setup Center pending semantics).
    await pumpWith(const []);
    expect(find.text('0/0'), findsOneWidget);
    expect(toneOf(), RestoflowTone.neutral);
  });

  testWidgets('wide layout: a FAILED device load leaves no ghost fourth grid '
      'slot — the unavailable card fills the operational row', (tester) async {
    _size(tester, const Size(1320, 3200));
    await tester.pumpWidget(
      _wrap(
        deviceSummary: DashboardDeviceSummaryCard(
          repository: _FailingDevicesStub(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final unavailable = find.byKey(const Key('kpi-devices-unavailable'));
    expect(unavailable, findsOneWidget);
    expect(find.text('0/0'), findsNothing);

    // The operational row is a full four-card row: the unavailable card sits
    // ON the row (same top) with the SAME width as the report cards — no
    // blank allocated slot.
    Rect rectOf(String key) => tester.getRect(find.byKey(Key(key)));
    final cash = rectOf('kpi-cash-sales');
    final completed = rectOf('kpi-completed');
    final unpaid = rectOf('kpi-unpaid');
    final device = tester.getRect(unavailable);
    expect(device.top, cash.top);
    expect(device.top, completed.top);
    expect(device.top, unpaid.top);
    expect(device.width, moreOrLessEquals(cash.width, epsilon: 0.5));
  });

  for (final locale in const [Locale('ar'), Locale('he'), Locale('en')]) {
    for (final width in const [390.0, 700.0, 940.0, 1320.0]) {
      testWidgets('V2 composition renders in ${locale.languageCode} at '
          '${width.toInt()}px without overflow', (tester) async {
        _size(tester, Size(width, 3200));
        await tester.pumpWidget(_wrap(locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('kpi-gross-sales')), findsOneWidget);
      });
    }
  }
}
