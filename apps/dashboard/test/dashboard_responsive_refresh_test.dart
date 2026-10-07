import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_destination.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/data/owner_top_items.dart';
import 'package:restoflow_dashboard/src/format/money_format.dart';
import 'package:restoflow_dashboard/src/setup/setup_center.dart';
import 'package:restoflow_dashboard/src/staff/staff_models.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/state/setup_device_providers.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

// BIZBOT-DASHBOARD-REFRESH-001. Real finite viewports, including every scroll
// position: a tall test surface alone hides page-level overflow regressions.
// Optional local evidence, never a golden baseline for CI:
// flutter test test/dashboard_responsive_refresh_test.dart
//   --dart-define=OVERVIEW_SCREENSHOTS=true --update-goldens
const _screenshots = bool.fromEnvironment('OVERVIEW_SCREENSHOTS');
const _evidenceDir = String.fromEnvironment(
  'OVERVIEW_EVIDENCE_DIR',
  defaultValue: '../build/overview-refresh-evidence',
);
const _captureKey = Key('overview-capture');
const _amount = 987654321;
const _longName =
    'فرع المطعم الرئيسي — סניף המסעדה הראשי — Main restaurant branch';

const _devices = [
  AdminDevice(
    id: 'pos',
    label: 'POS',
    deviceType: 'pos',
    branchLabel: _longName,
    status: DeviceLifecycleStatus.active,
  ),
  AdminDevice(
    id: 'kds',
    label: 'KDS',
    deviceType: 'kds',
    branchLabel: _longName,
    status: DeviceLifecycleStatus.active,
  ),
];
const _staff = [
  StaffMember(
    employeeProfileId: 'staff',
    displayName: 'Fixture employee',
    role: MembershipRole.cashier,
    hasPin: true,
    employmentStatus: 'active',
  ),
];

DashboardReport _report({int amount = _amount}) => DashboardReport(
  currencyCode: 'JOD',
  businessDateLabel: '2026-10-06',
  grossSalesMinor: amount,
  netSalesMinor: amount,
  discountTotalMinor: 0,
  collectedMinor: amount,
  cashSalesMinor: amount,
  lastCashPaymentMinor: amount,
  orderCount: amount == 0 ? 0 : 10,
  completedOrderCount: amount == 0 ? 0 : 6,
  openOrderCount: amount == 0 ? 0 : 4,
  unpaidOrderCount: amount == 0 ? 0 : 4,
  voidCount: 0,
  voidTotalMinor: 0,
  openingFloatMinor: 0,
  expectedCashMinor: amount,
  countedCashMinor: amount,
  shiftStatus: 'closed',
  branches: [
    BranchSales(
      branchName: _longName,
      orderCount: 10,
      netSalesMinor: amount,
      currencyCode: 'JOD',
    ),
  ],
  topItems: const [],
  recentOrders: const [],
  paymentMethods: [
    PaymentMethodLine(
      method: 'cash',
      count: 6,
      totalMinor: amount,
      currencyCode: 'JOD',
    ),
    const PaymentMethodLine(
      method: 'card',
      count: 1,
      totalMinor: 0,
      currencyCode: 'JOD',
    ),
  ],
  hourlyNetSales: [
    const HourlyNetSales(hourLabel: '09:00', netSalesMinor: 0),
    HourlyNetSales(hourLabel: '12:00', netSalesMinor: amount),
    const HourlyNetSales(hourLabel: '18:00', netSalesMinor: 0),
  ],
  // No comparison: the UI must not manufacture a percentage.
  shiftCash: ShiftCash(
    closedShiftCount: 1,
    openShiftCount: 0,
    expectedCashMinor: amount,
    countedCashMinor: amount,
    varianceMinor: 0,
  ),
);

enum _Scenario { demo, large, low, zero, errors, empty, unavailable }

Widget _app(
  String locale,
  double scale,
  _Scenario scenario,
  List<String> opened, {
  void Function(DashboardDestination)? onNavigate,
}) {
  final edge = scenario != _Scenario.demo;
  return RepaintBoundary(
    key: _captureKey,
    child: ProviderScope(
      overrides: [
        setupDevicesProvider.overrideWith((ref, key) async => _devices),
        setupStaffProvider.overrideWith((ref, key) async => edge ? [] : _staff),
        setupMenuSourceProvider.overrideWithValue(
          buildDemoMenuStore(readOnly: true),
        ),
        setupMenuScopeProvider.overrideWithValue(demoMenuScope),
        if (edge) ...[
          dashboardReportProvider.overrideWith((ref) async {
            if (scenario == _Scenario.unavailable) {
              return DashboardReport.rangeUnavailable(
                range: ReportRange.last90,
                currencyCode: 'JOD',
              );
            }
            return _report(
              amount: switch (scenario) {
                _Scenario.low => 1,
                _Scenario.zero => 0,
                _ => _amount,
              },
            );
          }),
          ownerTopItemsForKeyProvider.overrideWith((ref, key) async {
            if (scenario == _Scenario.errors) throw StateError('fixture error');
            return OwnerTopItems(
              currencyCode: 'JOD',
              rangeWire: 'today',
              items: [
                if (scenario != _Scenario.empty)
                  for (var i = 0; i < 10; i++)
                    TopItem(
                      menuItemId: 'item-$i',
                      name: 'صنف طويل — פריט ארוך — Long item $i',
                      quantity: 9000 - i,
                      lineRevenueMinor: _amount - i * 1000,
                      currencyCode: 'JOD',
                      orderCount: 100 - i,
                    ),
              ],
            );
          }),
          overviewRecentOrdersForKeyProvider.overrideWith((ref, key) async {
            if (scenario == _Scenario.errors) throw StateError('fixture error');
            return OrderHistoryPage(
              rows: [
                if (scenario != _Scenario.empty)
                  for (var i = 0; i < 8; i++)
                    OrderHistoryRow(
                      orderId: 'order-$i',
                      orderCode: '#LONG-IDENTIFIER-00000$i',
                      status: [
                        'completed',
                        'preparing',
                        'cancelled',
                        'pending',
                      ][i % 4],
                      orderType: i.isEven ? 'dine_in' : 'takeaway',
                      createdAtLabel: '2026-10-06 18:30',
                      itemCount: 12,
                      grandTotalMinor: _amount,
                      currencyCode: 'JOD',
                      settlement: i.isEven
                          ? SettlementState.paid
                          : SettlementState.unpaid,
                      tableLabel: i.isEven ? 'Table / طاولة / שולחן 123' : null,
                    ),
              ],
            );
          }),
        ],
      ],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        debugShowCheckedModeBanner: false,
        theme: restoflowLightBrandTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: DashboardHomeScreen(
          onNavigate: onNavigate,
          setupPanel: DashboardSetupCenter(
            onOpenMenu: () => opened.add('menu'),
            onOpenDevices: () => opened.add('devices'),
            onOpenPrinters: () => opened.add('printers'),
            onOpenStaff: () => opened.add('staff'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (!_screenshots) return;
  await expectLater(
    find.byKey(_captureKey),
    matchesGoldenFile('$_evidenceDir/$name.png'),
  );
}

Future<void> _walk(WidgetTester tester) async {
  final scroll = tester.state<ScrollableState>(
    find
        .descendant(
          of: find.byKey(const Key('overview-scroll')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  for (
    var offset = 0.0;
    offset < scroll.position.maxScrollExtent;
    offset += 600
  ) {
    scroll.position.jumpTo(offset);
    await tester.pump();
  }
  scroll.position.jumpTo(scroll.position.maxScrollExtent);
  await tester.pumpAndSettle();
}

Future<void> _verify(
  WidgetTester tester,
  double width,
  String locale,
  double scale,
  _Scenario scenario,
) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) {
      overflows.add(details.exceptionAsString());
    } else {
      previous?.call(details);
    }
  };
  try {
    final opened = <String>[];
    await tester.pumpWidget(_app(locale, scale, scenario, opened));
    await tester.pumpAndSettle();
    final name = '${scenario.name}-${width.toInt()}-$locale-${scale.toInt()}x';
    expect(
      Directionality.of(
        tester.element(find.byKey(const Key('reports-heading'))),
      ),
      locale == 'en' ? TextDirection.ltr : TextDirection.rtl,
    );
    await _shot(tester, '$name-top');
    // Every real readiness action retains its touch target and callback.
    for (final destination in ['menu', 'devices', 'staff']) {
      final action = find.byKey(Key('setup-stat-$destination'));
      await tester.scrollUntilVisible(
        action,
        400,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('overview-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(action).width, greaterThanOrEqualTo(44));
      await tester.tap(action);
    }
    expect(opened, ['menu', 'devices', 'staff']);
    // Readable-font evidence also verifies the owner's density requirement.
    // Ahem (normal CI tests) has different glyph metrics, so it is not a
    // meaningful baseline for this visual height budget.
    if (_screenshots &&
        scenario == _Scenario.demo &&
        scale == 1 &&
        width >= 1440) {
      final metrics = [
        for (final key in [
          'gross-sales',
          'net-sales',
          'orders',
          'avg-ticket',
          'cash-sales',
          'completed',
        ])
          tester.getRect(find.byKey(Key('kpi-$key'))),
      ];
      expect(metrics.map((rect) => rect.top).toSet(), hasLength(1));
      expect(metrics.map((rect) => rect.height).toSet(), hasLength(1));
      expect(metrics.first.height, lessThanOrEqualTo(132));
      expect(metrics.first.height, inInclusiveRange(108, 124));
      expect(
        tester.getSize(find.byKey(const Key('overview-readiness-card'))).height,
        // The owner's revision explicitly replaces the compact strip with a
        // stronger operational hero. Its height still has a bounded budget.
        inInclusiveRange(128, 160),
      );
    }
    await _walk(tester);
    // Bounds and complete monetary text are ordinary CI assertions as well as
    // screenshot checks; enlarged text may increase height or reduce columns.
    for (final key in [
      'gross-sales',
      'net-sales',
      'avg-ticket',
      'cash-sales',
    ]) {
      final finder = find.byKey(Key('kpi-$key'));
      if (finder.evaluate().isEmpty) continue;
      final metric = tester.widget<RestoflowMetricCard>(finder);
      final value = find.descendant(
        of: finder,
        matching: find.text(metric.value),
      );
      final text = tester.widget<Text>(value);
      expect(text.maxLines, isNull);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      final cardBounds = tester.getRect(finder);
      final valueBounds = tester.getRect(value);
      expect(valueBounds.left, greaterThanOrEqualTo(cardBounds.left));
      expect(valueBounds.right, lessThanOrEqualTo(cardBounds.right));
      expect(valueBounds.bottom, lessThanOrEqualTo(cardBounds.bottom));
    }
    if (scenario == _Scenario.large) {
      final metric = tester.widget<RestoflowMetricCard>(
        find.byKey(const Key('kpi-gross-sales')),
      );
      expect(metric.value, MoneyFormatter.formatMinor(_amount, 'JOD'));
      expect(metric.delta, isNull);
      expect(
        find.byWidgetPredicate((widget) => widget is RestoflowRankRow),
        findsNWidgets(10),
      );
    }
    if (scenario == _Scenario.errors || scenario == _Scenario.empty) {
      final state = scenario == _Scenario.errors ? 'error' : 'empty';
      expect(find.byKey(Key('top-items-$state')), findsOneWidget);
      expect(find.byKey(Key('recent-orders-$state')), findsOneWidget);
    }
    if (scenario != _Scenario.unavailable) {
      for (final entry in {
        'analytics': 'sales-by-hour-card',
        'orders': 'recent-orders-card',
      }.entries) {
        final card = find.byKey(Key(entry.value));
        expect(card, findsOneWidget);
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        await _shot(tester, '$name-${entry.key}');
      }
    } else {
      expect(
        find.byKey(const Key('reports-range-unavailable')),
        findsOneWidget,
      );
    }
    expect(overflows, isEmpty, reason: name);
    expect(tester.takeException(), isNull, reason: name);
  } finally {
    FlutterError.onError = previous;
  }
}

Future<void> _loadFonts() async {
  // Optional evidence uses readable local fonts; ordinary tests remain portable.
  // No assets, font declarations, shared packages or manifests are changed.
  const root = String.fromEnvironment(
    'OVERVIEW_FONT_DIR',
    defaultValue: 'C:/Windows/Fonts',
  );
  final font = FontLoader('Roboto');
  for (final name in ['segoeui.ttf', 'segoeuib.ttf']) {
    font.addFont(
      Future.value(
        ByteData.sublistView(await File('$root/$name').readAsBytes()),
      ),
    );
  }
  await font.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File(
              '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes(),
          ),
        ),
      );
    await icons.load();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (_screenshots) setUpAll(_loadFonts);
  for (final locale in ['ar', 'he', 'en']) {
    testWidgets('Overview navigation action $locale at 320px 2x', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final destinations = <DashboardDestination>[];
      await tester.pumpWidget(
        _app(locale, 2, _Scenario.demo, [], onNavigate: destinations.add),
      );
      await tester.pumpAndSettle();
      await _walk(tester);
      final viewAll = find.byKey(const Key('recent-orders-view-all'));
      await tester.ensureVisible(viewAll);
      await tester.pumpAndSettle();
      expect(tester.getSize(viewAll).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(viewAll).width, greaterThanOrEqualTo(44));
      await tester.tap(viewAll);
      expect(destinations, [DashboardDestination.orders]);
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [
    320.0,
    375.0,
    390.0,
    430.0,
    768.0,
    1024.0,
    1440.0,
    1920.0,
  ]) {
    for (final locale in ['ar', 'he', 'en']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'Overview ${width.toInt()}px $locale ${scale}x fits and scrolls',
          (tester) => _verify(tester, width, locale, scale, _Scenario.demo),
        );
      }
    }
  }
  for (final scenario in _Scenario.values.skip(1)) {
    for (final locale in ['ar', 'he', 'en']) {
      testWidgets(
        'Overview ${scenario.name} $locale compact 2x',
        (tester) => _verify(tester, 320, locale, 2, scenario),
      );
    }
  }
}
