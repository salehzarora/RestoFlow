// BIZBOT-DASHBOARD-REFRESH-001. Full DashboardShell, not an Overview stand-in.
// Exported images use synthetic fixtures in live-mode chrome. No backend is
// contacted; financial values come from the existing computed demo dataset.
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_dashboard/src/dashboard_shell.dart';
import 'package:restoflow_dashboard/src/support/support_mode_scope.dart';
import 'package:restoflow_dashboard/src/data/audit_filter_options_repository.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/currency_breakdown_repository.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/data/owner_top_items_repository.dart';
import 'package:restoflow_dashboard/src/data/order_history_repository.dart';
import 'package:restoflow_dashboard/src/printers/printers_repository.dart';
import 'package:restoflow_dashboard/src/staff/staff_repository.dart';
import 'package:restoflow_dashboard/src/staff/staff_models.dart';
import 'package:restoflow_dashboard/src/state/audit_log_providers.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/state/order_history_providers.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

const _screenshots = bool.fromEnvironment('SHELL_SCREENSHOTS');
// Only the isolated baseline replay opts out of the NEW visual budgets.
const _baselineCapture = bool.fromEnvironment('FIDELITY_BASELINE');
// Owner's revision gate exports only one top frame per selected test.
// Normal regression and the full evidence harness remain available later.
const _ownerReviewTopOnly = bool.fromEnvironment('OWNER_REVIEW_TOP_ONLY');
const _mobileDensityReview = bool.fromEnvironment('MOBILE_DENSITY_REVIEW');
// Supplemental evidence keeps both ends of a tall enlarged-text KPI grid
// readable, without changing the ordinary regression or core capture path.
const _kpiEvidenceOnly = bool.fromEnvironment('SHELL_KPI_EVIDENCE_ONLY');
const _evidenceDir = String.fromEnvironment(
  'SHELL_EVIDENCE_DIR',
  defaultValue: '../build/dashboard-phase5-shell-evidence',
);
const _capture = Key('full-shell-capture');
const _member = MembershipContext(
  id: 'fixture-member',
  organizationId: 'fixture-org',
  organizationName: 'BIZBOT',
  restaurantId: 'fixture-restaurant',
  restaurantName: 'مطعم الزيتون',
  branchId: 'fixture-branch',
  branchName: 'كفرمندا',
  role: MembershipRole.orgOwner,
  status: 'active',
);

class _Devices extends DemoAdminStore {
  _Devices({this.warningHeavy = false})
    : super(scope: dashboardAdminScopeFor(_member, currencyCode: 'ILS'));
  final bool warningHeavy;
  int reads = 0;
  @override
  Future<AdminResult<List<AdminDevice>>> loadDevices() async {
    reads++;
    if (warningHeavy) {
      return const Success([
        AdminDevice(
          id: 'unpaired-kiosk',
          label: 'Fixture kiosk',
          deviceType: 'kiosk',
          branchLabel: 'Main',
          status: DeviceLifecycleStatus.codeIssued,
        ),
      ]);
    }
    return const Success([
      AdminDevice(
        id: 'pos',
        label: 'Counter POS',
        deviceType: 'pos',
        branchLabel: 'Main',
        status: DeviceLifecycleStatus.active,
      ),
      AdminDevice(
        id: 'kds',
        label: 'Kitchen display',
        deviceType: 'kds',
        branchLabel: 'Main',
        status: DeviceLifecycleStatus.active,
      ),
    ]);
  }
}

class _EmptyStaff extends InMemoryStaffStore {
  @override
  Future<AdminResult<List<StaffMember>>> load() async => const Success([]);
}

class _Options implements AuditFilterOptionsRepository {
  const _Options();
  @override
  Future<List<AuditActorOption>> loadActors() async => const [];
  @override
  Future<List<AuditBranchOption>> loadBranches() async => const [
    AuditBranchOption(
      organizationId: 'fixture-org',
      restaurantId: 'fixture-restaurant',
      branchId: 'fixture-branch',
      label: 'كفرمندا',
    ),
    AuditBranchOption(
      organizationId: 'fixture-org',
      restaurantId: 'fixture-restaurant',
      branchId: 'fixture-branch-2',
      label: 'الناصرة',
    ),
  ];
}

Widget _app(
  String locale,
  double scale, {
  bool demo = false,
  _Devices? devices,
  VoidCallback? onSignOut,
  bool unavailable = false,
  bool longNames = false,
  bool warningHeavy = false,
}) {
  final member = longNames
      ? MembershipContext(
          id: _member.id,
          organizationId: _member.organizationId,
          organizationName:
              'مجموعة المطاعم الرئيسية — קבוצת המסעדות — Restaurant group',
          restaurantId: _member.restaurantId,
          restaurantName: _member.restaurantName,
          branchId: _member.branchId,
          branchName: 'الفرع الرئيسي — הסניף הראשי — Main restaurant branch',
          role: _member.role,
          status: _member.status,
        )
      : _member;
  final scope = dashboardMenuScopeFor(member, currencyCode: 'ILS')!;
  final menu = warningHeavy
      ? InMemoryMenuStore(readOnly: true)
      : buildDemoMenuStore(scope: scope, readOnly: true);
  return RepaintBoundary(
    key: _capture,
    child: ProviderScope(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: demo),
        ),
        auditFilterOptionsRepositoryProvider.overrideWithValue(
          const _Options(),
        ),
        dashboardCurrencyGuardProvider.overrideWith(
          (ref) async => const ReportCurrencyGuard.single('ILS'),
        ),
        ownerReportsRepositoryProvider.overrideWithValue(
          DemoOwnerReportsRepository(
            failureMessage: unavailable ? 'Fixture unavailable' : null,
          ),
        ),
        ownerTopItemsRepositoryProvider.overrideWithValue(
          const DemoOwnerTopItemsRepository(),
        ),
        orderHistoryRepositoryProvider.overrideWithValue(
          DemoOrderHistoryRepository(),
        ),
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
        home: DashboardShell(
          key: ValueKey(
            dashboardShellIdentity(demo ? null : member, currencyCode: 'ILS'),
          ),
          membership: demo ? null : member,
          currencyCode: 'ILS',
          deviceRepositoryFor: demo ? null : (_) => devices ?? _Devices(),
          menuReadSource: demo ? null : menu,
          menuWriter: demo ? null : menu,
          printersRepository: demo ? null : InMemoryPrintersStore(),
          staffRepository: demo
              ? null
              : warningHeavy
              ? _EmptyStaff()
              : InMemoryStaffStore(),
          onSignOut: demo ? null : () async => onSignOut?.call(),
        ),
      ),
    ),
  );
}

void _size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(
    width,
    width == 768
        ? 1024
        : width == 1024
        ? 768
        : 900,
  );
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (_screenshots) {
    tester
        .renderObject<RenderRepaintBoundary>(find.byKey(_capture))
        .markNeedsPaint();
    await tester.pump();
    await expectLater(
      find.byKey(_capture),
      matchesGoldenFile('$_evidenceDir/$name.png'),
    );
    final scrollables = find.descendant(
      of: find.byKey(const Key('overview-scroll')),
      matching: find.byType(Scrollable),
    );
    final position = scrollables.evaluate().isEmpty
        ? null
        : tester.state<ScrollableState>(scrollables.first).position;
    final file = File('test/$_evidenceDir/$name.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({
        'name': name,
        'viewport': {
          'width': tester.view.physicalSize.width,
          'height': tester.view.physicalSize.height,
        },
        'scrollOffset': position?.pixels,
        'maxScrollExtent': position?.maxScrollExtent,
        'headerBounds': tester
            .getRect(find.byKey(const Key('dashboard-persistent-header')))
            .toString(),
        'layoutBounds': {
          for (final key in [
            'dashboard-persistent-header',
            'reports-heading',
            'reports-range-filter',
            'overview-readiness-card',
            'kpi-gross-sales',
            'kpi-net-sales',
            'kpi-orders',
            'kpi-avg-ticket',
            'kpi-cash-sales',
            'kpi-completed',
            'sales-by-hour-card',
            'dashboard-bottom-nav',
          ])
            if (find.byKey(Key(key)).evaluate().isNotEmpty)
              key: {
                'top': tester.getRect(find.byKey(Key(key))).top,
                'bottom': tester.getRect(find.byKey(Key(key))).bottom,
                'height': tester.getRect(find.byKey(Key(key))).height,
              },
        },
      }),
    );
  }
}

Future<void> _matrix(
  WidgetTester tester,
  double width,
  String locale,
  double scale, {
  bool warningHeavy = false,
}) async {
  _size(tester, width);
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) {
      errors.add(details.exceptionAsString());
    } else {
      previous?.call(details);
    }
  };
  try {
    await tester.pumpWidget(
      _app(
        locale,
        scale,
        devices: _Devices(warningHeavy: warningHeavy),
        warningHeavy: warningHeavy,
      ),
    );
    await tester.pumpAndSettle();
    if (_screenshots) {
      // Decoding bundled artwork is asynchronous outside the fake test clock.
      // Wait for both official assets before the first evidence frame.
      final context = tester.element(find.byType(DashboardShell));
      await tester.runAsync(
        () => Future.wait([
          for (final asset in [
            RestoflowBrandMark.symbolAsset,
            RestoflowBrandMark.wordmarkLatinAsset,
          ])
            precacheImage(
              AssetImage(asset, package: RestoflowBrandMark.package),
              context,
            ),
        ]),
      );
      await tester.pumpAndSettle();
    }
    final name =
        '${warningHeavy ? 'warnings' : 'healthy'}-${width.toInt()}-$locale-${scale.toInt()}x';
    if (_kpiEvidenceOnly) {
      for (final entry in {
        'kpis': 'kpi-gross-sales',
        'kpis-end': 'kpi-completed',
      }.entries) {
        await tester.scrollUntilVisible(
          find.byKey(Key(entry.value)),
          350,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('overview-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(
          tester.element(find.byKey(Key(entry.value))),
          alignment: entry.key == 'kpis-end' ? 1 : 0,
        );
        await tester.pumpAndSettle();
        await _shot(tester, '$name-${entry.key}');
      }
      expect(errors, isEmpty, reason: name);
      expect(tester.takeException(), isNull, reason: name);
      return;
    }
    expect(
      find.byKey(const Key('dashboard-persistent-header')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        Key(width >= 560 ? 'dashboard-side-rail' : 'dashboard-bottom-nav'),
      ),
      findsOneWidget,
    );
    await _shot(tester, '$name-top');
    final header = tester.getRect(
      find.byKey(const Key('dashboard-persistent-header')),
    );
    expect(header.top, 0);
    expect(header.left, greaterThanOrEqualTo(0));
    expect(header.right, lessThanOrEqualTo(width));
    if (!_baselineCapture && scale == 1 && width >= 1440) {
      expect(header.height, inInclusiveRange(64, 100));
    }
    if (!_baselineCapture) {
      final selector = find.byKey(const Key('overview-scope-selector'));
      expect(selector, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('dashboard-persistent-header')),
          matching: selector,
        ),
        findsOneWidget,
      );
    }
    if (_ownerReviewTopOnly) {
      if (_mobileDensityReview && scale == 1 && width < 560) {
        final navigation = tester.getRect(
          find.byKey(const Key('dashboard-bottom-nav')),
        );
        expect(header.height, lessThanOrEqualTo(116));
        for (final key in [
          'kpi-gross-sales',
          'kpi-net-sales',
          'kpi-orders',
          'kpi-avg-ticket',
          'kpi-cash-sales',
          'kpi-completed',
        ]) {
          expect(
            tester.getRect(find.byKey(Key(key))).bottom,
            lessThanOrEqualTo(navigation.top + 8),
            reason: '$key is visible in the first fold',
          );
        }
        expect(
          tester.getRect(find.byKey(const Key('sales-by-hour-card'))).top,
          lessThanOrEqualTo(navigation.top + 24),
          reason: 'sales chart starts at the first-fold boundary',
        );
      }
      expect(errors, isEmpty, reason: name);
      expect(tester.takeException(), isNull, reason: name);
      return;
    }
    await tester.scrollUntilVisible(
      find.byKey(const Key('overview-readiness-card')),
      350,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('overview-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('overview-readiness-card'))),
      alignment: 0,
    );
    await tester.pumpAndSettle();
    await _shot(tester, '$name-readiness');
    final scroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('overview-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    // Literal matched offsets complement the semantic-anchor captures below.
    // They allow before/after comparison at exactly the same scroll position.
    for (final entry in {
      'readiness': 120.0,
      'analytics': 600.0,
      'orders': 1000.0,
    }.entries) {
      scroll.position.jumpTo(
        entry.value.clamp(0, scroll.position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
      await _shot(tester, '$name-offset-${entry.key}');
    }
    for (
      var offset = 0.0;
      offset < scroll.position.maxScrollExtent;
      offset += 500
    ) {
      scroll.position.jumpTo(offset);
      await tester.pump();
    }
    for (final entry in {
      'analytics': 'sales-by-hour-card',
      'top-items': 'top-items-card',
      'orders': 'recent-orders-card',
    }.entries) {
      await Scrollable.ensureVisible(
        tester.element(find.byKey(Key(entry.value))),
        alignment: 0,
      );
      await tester.pumpAndSettle();
      await _shot(tester, '$name-${entry.key}');
      if (!_baselineCapture &&
          entry.key == 'analytics' &&
          scale == 1 &&
          width >= 1440) {
        final sales = tester.getRect(
          find.byKey(const Key('sales-by-hour-card')),
        );
        final payments = tester.getRect(
          find.byKey(const Key('payment-mix-card')),
        );
        final cash = tester.getRect(find.byKey(const Key('shift-cash-card')));
        expect(payments.right, lessThan(sales.left));
        expect(sales.right, lessThan(cash.left));
        expect(sales.width, closeTo(payments.width * 2, 1));
        expect(cash.width, closeTo(payments.width, 1));
        expect(payments.top, closeTo(sales.top, 1));
        expect(cash.top, closeTo(sales.top, 1));
        expect(payments.bottom, closeTo(sales.bottom, 1));
        expect(cash.bottom, closeTo(sales.bottom, 1));
      }
    }
    // Scroll all the genuine phone destinations into view without leaving
    // Overview, so the final image also records the trailing navigation items.
    if (width < 560) {
      await tester.ensureVisible(find.byKey(const Key('dashboard-nav-9')));
      await tester.pumpAndSettle();
      await _shot(tester, '$name-navigation-end');
    }
    if (warningHeavy) {
      // Existing visibility semantics: only the first setup warning is open.
      scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      final disclosure = find.byKey(const Key('setup-more-steps'));
      await tester.scrollUntilVisible(
        disclosure,
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('overview-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(disclosure, findsOneWidget);
      final tile = tester.widget<ExpansionTile>(disclosure);
      expect(tile.initiallyExpanded, isFalse);
      await Scrollable.ensureVisible(tester.element(disclosure), alignment: 0);
      await tester.pumpAndSettle();
      await tester.tap(disclosure);
      await tester.pumpAndSettle();
      await _shot(tester, '$name-warnings-expanded');
    }
    expect(errors, isEmpty, reason: name);
    expect(tester.takeException(), isNull, reason: name);
  } finally {
    FlutterError.onError = previous;
  }
}

Future<void> _loadFonts() async {
  // Optional evidence uses readable local fonts; ordinary tests remain portable.
  // No assets, font declarations, shared packages or manifests are changed.
  const root = String.fromEnvironment(
    'SHELL_FONT_DIR',
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
  testWidgets(
    'V002 header branch filter preserves selection across resize and tabs',
    (tester) async {
      _size(tester, 1440);
      await tester.pumpWidget(_app('en', 1));
      await tester.pumpAndSettle();
      final selector = find.byKey(const Key('overview-scope-selector'));
      final header = find.byKey(const Key('dashboard-persistent-header'));
      expect(selector, findsOneWidget);
      expect(find.descendant(of: header, matching: selector), findsOneWidget);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('الناصرة').last);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(selector));
      expect(
        container.read(selectedAnalyticsBranchProvider)?.branchId,
        'fixture-branch-2',
      );
      tester.view.physicalSize = const Size(390, 900);
      await tester.pumpAndSettle();
      expect(
        ProviderScope.containerOf(tester.element(selector)),
        same(container),
      );
      expect(find.descendant(of: header, matching: selector), findsOneWidget);
      expect(
        container.read(selectedAnalyticsBranchProvider)?.branchId,
        'fixture-branch-2',
      );
      for (final index in [2, 0]) {
        final nav = find.byKey(Key('dashboard-nav-$index'));
        await tester.ensureVisible(nav);
        await tester.pumpAndSettle();
        await tester.tap(nav);
        await tester.pumpAndSettle();
        expect(
          container.read(selectedAnalyticsBranchProvider)?.branchId,
          'fixture-branch-2',
        );
        expect(selector, index == 0 ? findsOneWidget : findsNothing);
      }
      expect(
        ProviderScope.containerOf(tester.element(selector)),
        same(container),
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final locale in ['ar', 'he', 'en']) {
    for (final width in [390.0, 430.0, 768.0, 1024.0, 1440.0, 1920.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'full shell ${width.toInt()} $locale ${scale}x',
          (tester) => _matrix(tester, width, locale, scale),
        );
        testWidgets(
          'full shell warnings ${width.toInt()} $locale ${scale}x',
          (tester) => _matrix(tester, width, locale, scale, warningHeavy: true),
        );
      }
    }
    testWidgets(
      'full shell 320 $locale 2x',
      (tester) => _matrix(tester, 320, locale, 2),
    );
    for (final width in [390.0, 1024.0, 1440.0]) {
      testWidgets('every real destination reachable at $width $locale', (
        tester,
      ) async {
        _size(tester, width);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(_app(locale, 1, demo: true));
        await tester.pumpAndSettle();
        for (final index in [1, 2, 4, 5, 6, 7, 8, 9, 0]) {
          final target = find.byKey(Key('dashboard-nav-$index'));
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          expect(tester.getSize(target).width, greaterThanOrEqualTo(44));
          expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
          expect(target.hitTestable(), findsOneWidget);
          // All targets are reachable; exercise representative actual pages.
          // Each destination's content has its own independent test suite.
          if (![1, 9, 0].contains(index)) continue;
          await tester.tap(target);
          await tester.pumpAndSettle();
          expect(find.byKey(ValueKey('dashboard-tab-$index')), findsOneWidget);
          if (width < 560) {
            final nav = tester.widget<NavigationBar>(
              find.byKey(const Key('dashboard-bottom-nav')),
            );
            expect(nav.selectedIndex, index <= 2 ? index : index - 1);
          } else {
            expect(
              tester.getSemantics(
                find.descendant(
                  of: target,
                  matching: find.byWidgetPredicate(
                    (w) => w is Semantics && w.properties.selected == true,
                  ),
                ),
              ),
              isSemantics(isSelected: true, isButton: true),
            );
          }
        }
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }
    testWidgets('long context, source and sign-out survive 320px $locale 2x', (
      tester,
    ) async {
      _size(tester, 320);
      var signOuts = 0;
      await tester.pumpWidget(
        _app(locale, 2, longNames: true, onSignOut: () => signOuts++),
      );
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(Locale(locale));
      final signOut = find.byTooltip(l10n.authSignOut);
      expect(tester.getSize(signOut).width, greaterThanOrEqualTo(44));
      await tester.tap(signOut);
      expect(signOuts, 1);
      expect(
        find.byTooltip(
          'مجموعة المطاعم الرئيسية — קבוצת המסעדות — Restaurant group · الفرع الرئيسي — הסניף הראשי — Main restaurant branch',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
  for (final locale in ['ar', 'en']) {
    testWidgets('phone gesture and automatic selected reveal $locale', (
      tester,
    ) async {
      _size(tester, 390);
      await tester.pumpWidget(_app(locale, 1, demo: true));
      await tester.pumpAndSettle();
      final viewport = find.byKey(
        const Key('dashboard-phone-navigation-scroll'),
      );
      final rect = tester.getRect(viewport);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(390));
      await tester.drag(viewport, Offset(locale == 'ar' ? 400 : -400, 0));
      await tester.pumpAndSettle();
      final settings = find.byKey(const Key('dashboard-nav-9'));
      expect(settings.hitTestable(), findsOneWidget);
      await tester.tap(settings);
      await tester.pumpAndSettle();
      for (final width in [1024.0, 1440.0, 390.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('dashboard-tab-9')), findsOneWidget);
        expect(
          settings.hitTestable(),
          findsOneWidget,
          reason:
              'selected destination is automatically revealed after resizing',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('support phone keeps exactly its five authorized destinations', (
    tester,
  ) async {
    _size(tester, 390);
    await tester.pumpWidget(
      SupportModeScope(active: true, child: _app('en', 1, demo: true)),
    );
    await tester.pumpAndSettle();
    final nav = find.byKey(const Key('dashboard-bottom-nav'));
    expect(tester.widget<NavigationBar>(nav).destinations, hasLength(5));
    for (final index in [0, 1, 2, 5, 9]) {
      expect(
        find.byKey(Key('dashboard-nav-$index')).hitTestable(),
        findsOneWidget,
      );
    }
    for (final index in [3, 4, 6, 7, 8]) {
      expect(find.byKey(Key('dashboard-nav-$index')), findsNothing);
    }
    await tester.tap(find.byKey(const Key('dashboard-nav-9')));
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(nav).selectedIndex, 4);
    expect(find.byKey(const ValueKey('dashboard-tab-9')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('resize retains shell scope and cached readiness', (
    tester,
  ) async {
    _size(tester, 1440);
    final devices = _Devices();
    await tester.pumpWidget(_app('ar', 1, devices: devices));
    await tester.pumpAndSettle();
    final shell = tester.state(find.byType(DashboardShell));
    final reads = devices.reads;
    for (final width in [1024.0, 390.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(DashboardShell)), same(shell));
      expect(devices.reads, reads);
    }
    expect(tester.takeException(), isNull);
  });
  for (final demo in [true, false]) {
    testWidgets('honest source chrome demo=$demo', (tester) async {
      _size(tester, 390);
      await tester.pumpWidget(_app('en', 1, demo: demo, unavailable: !demo));
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        find.text(
          demo ? l10n.dashboardModeDemoData : l10n.dashboardModeLiveData,
        ),
        findsWidgets,
      );
      await _shot(tester, demo ? 'demo-390-en-top' : 'unavailable-390-en-top');
      expect(tester.takeException(), isNull);
    });
  }
}
