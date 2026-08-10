/// GLOBAL-BRAND-DASHBOARD-V2-2 — the Dashboard's closing visual pass, measured.
///
/// Three kinds of claim live here, and they are kept apart on purpose:
///
///  * INTERACTION STATE — the rail's selected / hover / focus feedback. These
///    were invisible, not absent: the code set a hover and a focus colour and
///    Material dutifully painted both underneath an opaque fill. A test that
///    only asserted "a hover colour is configured" would have passed throughout.
///    So these assert the PAINT ORDER and the ring, which is what a person
///    actually sees.
///  * OVERFLOW — a defect that renders as a yellow-and-black bar and is
///    invisible to every assertion that does not look for it. The width matrix
///    below drives real viewports and fails on any RenderFlex overflow.
///  * COMPOSITION — hierarchy and zone rhythm. Asserted as ORDER and RELATIVE
///    spacing rather than exact pixel gaps, because the point is that the eye
///    can find the zone boundaries, not that a constant equals 24.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_comparison_labels.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_window.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_destination.dart';
import 'package:restoflow_dashboard/src/analytics/payment_tender_colors.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/dashboard_shell.dart';
import 'package:restoflow_dashboard/src/printers/printers_repository.dart';
import 'package:restoflow_dashboard/src/printers/printers_screen.dart';
import 'package:restoflow_dashboard/src/staff/staff_repository.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(
  Widget home, {
  Locale locale = const Locale('en'),
  double scale = 1.0,
}) => ProviderScope(
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    theme: restoflowBaseTheme(),
    builder: (context, child) => MediaQuery.withClampedTextScaling(
      minScaleFactor: scale,
      maxScaleFactor: scale,
      child: child!,
    ),
    home: home,
  ),
);

const _member = MembershipContext(
  id: 'm-1',
  organizationId: 'org-1',
  organizationName: 'Org',
  restaurantId: 'rest-1',
  restaurantName: 'Rest',
  branchId: 'branch-1',
  branchName: 'Main',
  role: MembershipRole.orgOwner,
  status: 'active',
);

/// Runs [body] and returns every RenderFlex overflow the renderer reported.
///
/// NOT `tester.takeException()`. A RenderFlex overflow is reported during
/// PAINT through [FlutterError.onError], and in this harness it does NOT reach
/// `takeException` - that getter returns null while the renderer is dumping
/// "overflowed by 52 pixels" to the console. A matrix built on it is therefore
/// green whatever the layout does, which is worse than having no matrix at all,
/// because it reads as coverage. Found while fixing the shared admin devices
/// screen, whose overflow this file's first draft could not see.
///
/// The handler is restored BEFORE the caller's expectation runs: the test
/// binding asserts it owns `FlutterError.onError` by then, and leaving the
/// override installed turns every later failure in the file into an opaque
/// "did not complete".
Future<List<String>> _overflowsDuring(Future<void> Function() body) async {
  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed')) {
      overflows.add(text.split('\n').first.trim());
    } else {
      previous?.call(details);
    }
  };
  await body();
  FlutterError.onError = previous;
  return overflows;
}

void main() {
  // =========================================================================
  // A. SHELL RAIL — selected / hover / focus are actually VISIBLE
  // =========================================================================
  group('A. the rail communicates selection, hover and focus', () {
    Future<void> pumpRail(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
      double scale = 1.0,
    }) async {
      _size(tester, const Size(1280, 1400));
      await tester.pumpWidget(
        _app(const DashboardShell(), locale: locale, scale: scale),
      );
      await tester.pumpAndSettle();
    }

    /// The rail tile whose label is [label], as its interactive [Material].
    ///
    /// The Material is what carries the selection fill after V2.2 — and being
    /// able to name it is the point of the change, because Material paints its
    /// ink layer ABOVE its own colour and below its child.
    Material tileMaterial(WidgetTester tester, String label) =>
        tester.widget<Material>(
          find
              .descendant(
                of: find.byKey(const Key('dashboard-side-rail')),
                matching: find.ancestor(
                  of: find.text(label),
                  matching: find.byType(Material),
                ),
              )
              .first,
        );

    testWidgets('the SELECTED tile paints its fill on the Material, so the ink '
        'layer sits above it', (tester) async {
      await pumpRail(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // Overview is the landing destination.
      expect(
        tileMaterial(tester, l10n.dashboardNavOverview).color,
        kRestoflowSeedColor,
        reason:
            'the selected bed must be the Material surface, not a child '
            'decoration painted over the ink',
      );
      expect(
        tileMaterial(tester, l10n.dashboardNavDevices).color,
        Colors.transparent,
        reason: 'an unselected tile has no bed of its own',
      );
    });

    testWidgets('hover is legible on BOTH the selected and unselected bed', (
      tester,
    ) async {
      await pumpRail(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      InkWell inkOf(String label) => tester.widget<InkWell>(
        find
            .descendant(
              of: find.byKey(const Key('dashboard-side-rail')),
              matching: find.ancestor(
                of: find.text(label),
                matching: find.byType(InkWell),
              ),
            )
            .first,
      );

      final selectedHover = inkOf(l10n.dashboardNavOverview).hoverColor!;
      final unselectedHover = inkOf(l10n.dashboardNavDevices).hoverColor!;

      // On navy, only a light film reads; on white, only a tint does. The two
      // beds therefore CANNOT share one hover colour — which is what the
      // previous single `kRestoflowCanvas` hover tried to do.
      expect(selectedHover, isNot(unselectedHover));
      expect(
        selectedHover.a,
        greaterThan(0.0),
        reason: 'the selected tile must have a real hover overlay',
      );
      // The unselected hover must be a genuine step away from the white rail,
      // not the ~3% canvas wash it used to be.
      double lum(Color c) => c.computeLuminance();
      expect(
        lum(Colors.white) - lum(unselectedHover),
        greaterThan(lum(Colors.white) - lum(kRestoflowCanvas)),
        reason: 'the hover step must be stronger than the old canvas wash',
      );
    });

    testWidgets('keyboard focus draws a RING on the selected tile — the state '
        'that previously showed nothing at all', (tester) async {
      await pumpRail(tester);

      // No ring until something is focused.
      expect(_focusRings(tester), isEmpty);

      // Tab until the rail owns focus. The rail is the first focusable region
      // in the shell, so this reaches it quickly; the loop is bounded so a
      // focus-order change fails loudly instead of hanging.
      var rings = 0;
      for (var i = 0; i < 8 && rings == 0; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        rings = _focusRings(tester).length;
      }
      expect(
        rings,
        greaterThan(0),
        reason: 'tabbing into the rail must produce a visible focus ring',
      );

      // Exactly one tile is focused at a time.
      expect(_focusRings(tester), hasLength(1));
    });

    testWidgets('the focus ring is a SHAPE, not a colour-only signal, and it '
        'does not move the tile', (tester) async {
      await pumpRail(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final before = tester.getRect(
        find
            .ancestor(
              of: find.text(l10n.dashboardNavOverview),
              matching: find.byType(InkWell),
            )
            .first,
      );

      var rings = 0;
      for (var i = 0; i < 8 && rings == 0; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        rings = _focusRings(tester).length;
      }
      expect(rings, 1);

      final ring = _focusRings(tester).single;
      expect(
        ring.border,
        isA<Border>(),
        reason:
            'focus is conveyed by a border, so it survives colour blindness '
            'and forced-colour modes',
      );
      expect((ring.border! as Border).top.width, greaterThanOrEqualTo(2.0));

      final after = tester.getRect(
        find
            .ancestor(
              of: find.text(l10n.dashboardNavOverview),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(
        after,
        before,
        reason: 'a focus indicator that resizes the tile is its own defect',
      );
    });

    testWidgets('tapping a rail tile still navigates (RTL included)', (
      tester,
    ) async {
      await pumpRail(tester, locale: const Locale('ar'));
      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));

      expect(find.byKey(const Key('reports-heading')), findsOneWidget);
      await tester.tap(
        find
            .descendant(
              of: find.byKey(const Key('dashboard-side-rail')),
              matching: find.text(l10n.dashboardNavOrders),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('reports-heading')),
        findsNothing,
        reason: 'navigation must be untouched by the interaction-state work',
      );
    });

    testWidgets('the rail renders without overflow at 2x text scale', (
      tester,
    ) async {
      final overflows = await _overflowsDuring(
        () => pumpRail(tester, scale: 2.0),
      );
      expect(overflows, isEmpty);
      expect(find.byKey(const Key('dashboard-side-rail')), findsOneWidget);
    });
  });

  // =========================================================================
  // B. PRINTERS — the Dashboard-local responsive defect
  // =========================================================================
  group('B. the printers card actions reflow instead of overflowing', () {
    Future<void> pumpPrinters(
      WidgetTester tester,
      Size size, {
      double scale = 1.0,
      Locale locale = const Locale('en'),
    }) async {
      _size(tester, size);
      await tester.pumpWidget(
        _app(
          Scaffold(body: PrintersScreen(repository: InMemoryPrintersStore())),
          locale: locale,
          scale: scale,
        ),
      );
      await tester.pumpAndSettle();
    }

    // 540 is the width the V2.1 browser pass tripped over; 430/390 are the
    // mobile acceptance widths.
    for (final width in [700.0, 540.0, 430.0, 390.0]) {
      testWidgets('no overflow at ${width.toInt()}px', (tester) async {
        final overflows = await _overflowsDuring(
          () => pumpPrinters(tester, Size(width, 1600)),
        );
        expect(
          overflows,
          isEmpty,
          reason: 'the printer action row must reflow, never clip',
        );
      });
    }

    testWidgets('no overflow at 430px, 2x text scale', (tester) async {
      final overflows = await _overflowsDuring(
        () => pumpPrinters(tester, const Size(430, 2400), scale: 2.0),
      );
      expect(overflows, isEmpty);
    });

    testWidgets('no overflow at 430px in Arabic', (tester) async {
      final overflows = await _overflowsDuring(
        () => pumpPrinters(
          tester,
          const Size(430, 1600),
          locale: const Locale('ar'),
        ),
      );
      expect(overflows, isEmpty);
    });

    testWidgets('every printer action survives the reflow', (tester) async {
      await pumpPrinters(tester, const Size(430, 1600));
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      // Two demo printers, each with route + edit + delete + the enable switch.
      expect(find.text(l10n.printersRoute), findsNWidgets(2));
      expect(find.text(l10n.printersEdit), findsNWidgets(2));
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
      expect(find.byType(Switch), findsNWidgets(2));
    });
  });

  // =========================================================================
  // C. OVERVIEW — zone hierarchy and rhythm
  // =========================================================================
  group('C. the Overview reads as zones', () {
    Future<void> pumpOverview(
      WidgetTester tester,
      Size size, {
      double scale = 1.0,
      Locale locale = const Locale('en'),
    }) async {
      _size(tester, size);
      await tester.pumpWidget(
        _app(const DashboardHomeScreen(), locale: locale, scale: scale),
      );
      await tester.pumpAndSettle();
    }

    double topOf(WidgetTester tester, String key) =>
        tester.getTopLeft(find.byKey(Key(key))).dy;

    testWidgets('the trend leads its zone and the comparison follows it', (
      tester,
    ) async {
      await pumpOverview(tester, const Size(1320, 3400));
      // The chart is the primary analytical surface; the comparison strip is
      // related but secondary, so it reads AFTER the thing it compares.
      expect(
        topOf(tester, 'sales-by-hour-card'),
        lessThan(topOf(tester, 'period-comparison-card')),
        reason: 'the chart must lead; the comparison supports it',
      );
      // ...and both stay above the secondary operational cards.
      expect(
        topOf(tester, 'period-comparison-card'),
        lessThan(topOf(tester, 'kpi-cash-sales')),
      );
    });

    testWidgets('zone boundaries breathe more than the gaps inside a zone', (
      tester,
    ) async {
      await pumpOverview(tester, const Size(1320, 3400));
      // Zone 2 -> Zone 3 is a boundary; the KPI grid to the chart therefore
      // gets the wide gap. Measured as a RELATIVE claim: the exact constant is
      // a design decision, the hierarchy is the contract.
      final kpiBottom = tester
          .getBottomLeft(find.byKey(const Key('kpi-gross-sales')))
          .dy;
      final chartTop = topOf(tester, 'sales-by-hour-card');
      final chartBottom = tester
          .getBottomLeft(find.byKey(const Key('sales-by-hour-card')))
          .dy;
      final comparisonTop = topOf(tester, 'period-comparison-card');

      final betweenZones = chartTop - kpiBottom;
      final withinZone = comparisonTop - chartBottom;
      expect(
        betweenZones,
        greaterThan(withinZone),
        reason: 'a zone boundary must be visibly wider than an internal gap',
      );
    });

    testWidgets('no feature was removed from the Overview', (tester) async {
      await pumpOverview(tester, const Size(1320, 4200));
      for (final key in const [
        'kpi-gross-sales',
        'kpi-net-sales',
        'kpi-orders',
        'kpi-avg-ticket',
        'kpi-cash-sales',
        'kpi-completed',
        'kpi-unpaid',
        'sales-by-hour-card',
        'payment-mix-card',
        'period-comparison-card',
        'top-items-card',
        'recent-orders-card',
        'daily-summary-card',
        'payment-summary-card',
      ]) {
        expect(
          find.byKey(Key(key)),
          findsOneWidget,
          reason: '$key must survive the visual pass',
        );
      }
    });
  });

  // =========================================================================
  // D. RESPONSIVE — the full target matrix, no page-level overflow
  // =========================================================================
  group('D. the Overview holds at every target width', () {
    for (final width in [
      1440.0,
      1280.0,
      1024.0,
      834.0,
      700.0,
      540.0,
      430.0,
      390.0,
    ]) {
      testWidgets('no overflow at ${width.toInt()}px', (tester) async {
        _size(tester, Size(width, 3600));
        final overflows = await _overflowsDuring(() async {
          await tester.pumpWidget(_app(const DashboardHomeScreen()));
          await tester.pumpAndSettle();
        });
        expect(overflows, isEmpty);
        // The range selector stays usable at every width (never scrolled off).
        expect(find.byKey(const Key('reports-range-filter')), findsOneWidget);
      });
    }
  });

  // =========================================================================
  // E. TEXT SCALE + DIRECTION
  // =========================================================================
  group('E. 2x text scale and both directions', () {
    for (final locale in const [Locale('en'), Locale('ar'), Locale('he')]) {
      testWidgets('Overview at 1280 / 2x / ${locale.languageCode}', (
        tester,
      ) async {
        _size(tester, const Size(1280, 6000));
        final overflows = await _overflowsDuring(() async {
          await tester.pumpWidget(
            _app(const DashboardHomeScreen(), locale: locale, scale: 2.0),
          );
          await tester.pumpAndSettle();
        });
        expect(overflows, isEmpty);
      });

      testWidgets('Overview at 430 / 2x / ${locale.languageCode}', (
        tester,
      ) async {
        _size(tester, const Size(430, 9000));
        final overflows = await _overflowsDuring(() async {
          await tester.pumpWidget(
            _app(const DashboardHomeScreen(), locale: locale, scale: 2.0),
          );
          await tester.pumpAndSettle();
        });
        expect(overflows, isEmpty);
      });
    }
  });

  // =========================================================================
  // G. TOP ITEMS + RECENT ORDERS stay first-class
  // =========================================================================
  group('G. the strong pair keeps its data path and its states', () {
    testWidgets('both cards mount, load and render their lists', (
      tester,
    ) async {
      _size(tester, const Size(1320, 4200));
      await tester.pumpWidget(_app(const DashboardHomeScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('top-items-list')), findsOneWidget);
      expect(find.byKey(const Key('recent-orders-list')), findsOneWidget);
      // The honest state slots are still wired — none was replaced by a
      // decorative placeholder during the visual pass.
      expect(find.byKey(const Key('top-items-error')), findsNothing);
      expect(find.byKey(const Key('recent-orders-error')), findsNothing);
    });

    testWidgets('the cards follow the committed window', (tester) async {
      _size(tester, const Size(1320, 4200));
      await tester.pumpWidget(_app(const DashboardHomeScreen()));
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // Switching range re-keys both cards; they must still resolve rather
      // than stick on the previous window's rows or fall into an error state.
      await tester.tap(find.byKey(const Key('range-chip-last7')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('top-items-card')), findsOneWidget);
      expect(find.byKey(const Key('recent-orders-card')), findsOneWidget);
      expect(find.byKey(const Key('top-items-error')), findsNothing);
      expect(find.byKey(const Key('recent-orders-error')), findsNothing);
      expect(l10n.dashboardTopItems, isNotEmpty);
    });

    testWidgets('View all is offered ONLY when there is somewhere to go, and '
        'it opens the unfiltered history', (tester) async {
      _size(tester, const Size(1320, 4200));

      // No navigation seam (a bare Overview): no action, rather than a control
      // that does nothing.
      await tester.pumpWidget(_app(const DashboardHomeScreen()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recent-orders-view-all')), findsNothing);

      DashboardDestination? went;
      await tester.pumpWidget(
        _app(DashboardHomeScreen(onNavigate: (d) => went = d)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recent-orders-view-all')), findsOneWidget);

      await tester.tap(find.byKey(const Key('recent-orders-view-all')));
      await tester.pumpAndSettle();
      expect(
        went,
        DashboardDestination.orders,
        reason: 'View all lands on the order history, not a new surface',
      );
    });
  });

  // =========================================================================
  // H. THE ANALYTICAL TRUTH THE VISUAL PASS MUST NOT HAVE TOUCHED
  // =========================================================================
  group('H. analytics semantics survive the visual pass', () {
    testWidgets('a custom N-day window still names its own length', (
      tester,
    ) async {
      _size(tester, const Size(1320, 4200));
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final window = CustomAnalyticsWindow(
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 14),
      );
      // 14 days -> the comparison names FOURTEEN, not the preset the request
      // happened to be built with. Asserted on the shared helper the strip
      // renders, so moving the strip cannot have changed what it says.
      expect(
        analyticsComparisonTitle(l10n, window),
        contains('14'),
        reason: 'a custom window must announce its real length',
      );
    });

    testWidgets('tender colours stay CATEGORICAL, never semantic', (
      tester,
    ) async {
      _size(tester, const Size(1320, 4200));
      await tester.pumpWidget(_app(const DashboardHomeScreen()));
      await tester.pumpAndSettle();
      final context = tester.element(find.byKey(const Key('payment-mix-card')));
      final theme = Theme.of(context);
      final semantic =
          theme.extension<RestoflowSemanticColors>() ??
          RestoflowSemanticColors.of(theme.brightness);
      final forbidden = {semantic.success, semantic.warning, semantic.danger};
      for (final method in const ['cash', 'card', 'bit', 'external', 'wat']) {
        expect(
          forbidden.contains(paymentTenderColorOf(context, method)),
          isFalse,
          reason: '$method must not borrow a status colour as its identity',
        );
      }
      // An unrecognised future token still gets its own distinct swatch.
      expect(
        paymentTenderColorOf(context, 'wat'),
        isNot(paymentTenderColorOf(context, 'cash')),
      );
    });
  });

  // =========================================================================
  // I. THE SHARED DEVICES SCREEN, AS THE DASHBOARD RENDERS IT
  //
  // SHARED-ADMIN-DEVICE-ACTIONS-RESPONSIVE-001. The screen lives in
  // feature_admin and has its own matrix there; this group exists because the
  // defect was only ever OBSERVED here — the Dashboard wraps it in a demo
  // banner column inside the shell, which is a narrower frame than the
  // standalone harness, and that is why the two contexts reported different
  // pixel counts for the same broken row.
  // =========================================================================
  group('I. the Devices destination holds at mobile widths', () {
    Future<List<String>> openDevices(
      WidgetTester tester, {
      required double width,
      Locale locale = const Locale('en'),
    }) async {
      _size(tester, Size(width, 3000));
      return _overflowsDuring(() async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              locale: locale,
              localizationsDelegates: restoflowLocalizationsDelegates,
              supportedLocales: kSupportedLocales,
              theme: restoflowBaseTheme(),
              home: DashboardShell(
                membership: _member,
                deviceRepositoryFor: (_) => _Devices(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // Phone layout at these widths: the bottom nav owns navigation.
        tester
            .widget<NavigationBar>(
              find.byKey(const Key('dashboard-bottom-nav')),
            )
            .onDestinationSelected!(DashboardDestination.devices.tabIndex);
        await tester.pumpAndSettle();
      });
    }

    for (final width in [390.0, 420.0, 430.0]) {
      for (final locale in const [Locale('en'), Locale('ar')]) {
        testWidgets('Devices at ${width.toInt()}px / ${locale.languageCode}', (
          tester,
        ) async {
          final overflows = await openDevices(
            tester,
            width: width,
            locale: locale,
          );
          expect(
            overflows,
            isEmpty,
            reason: 'the Dashboard must render the shared screen cleanly',
          );
          // The destination really opened, and the shell survived it.
          expect(find.byType(AdminDevicesScreen), findsOneWidget);
          expect(find.byKey(const Key('dashboard-bottom-nav')), findsOneWidget);
          expect(find.byKey(const Key('reports-heading')), findsNothing);
        });
      }
    }
  });

  // =========================================================================
  // F. V2.1 IS NOT DISTURBED
  // =========================================================================
  group('F. the V2.1 navigation contract still holds', () {
    testWidgets('leaving a writer still invalidates its setup read model', (
      tester,
    ) async {
      _size(tester, const Size(1280, 2400));
      final devices = _Devices();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            theme: restoflowBaseTheme(),
            home: DashboardShell(
              membership: _member,
              deviceRepositoryFor: (_) => devices,
              printersRepository: InMemoryPrintersStore(),
              staffRepository: InMemoryStaffStore(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      Future<void> go(String label) async {
        await tester.tap(
          find
              .descendant(
                of: find.byKey(const Key('dashboard-side-rail')),
                matching: find.text(label),
              )
              .first,
        );
        await tester.pumpAndSettle();
      }

      final afterMount = devices.loadDevicesCalls;
      await go(l10n.dashboardNavDevices);
      await go(l10n.dashboardNavOverview);
      expect(
        devices.loadDevicesCalls,
        greaterThan(afterMount),
        reason: 'the leave-writer refresh must still run after the rail rework',
      );
      expect(find.byKey(const Key('reports-heading')), findsOneWidget);
    });
  });
}

/// Every focus-ring decoration currently painted by a rail tile.
List<BoxDecoration> _focusRings(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(
      find.descendant(
        of: find.byKey(const Key('dashboard-side-rail')),
        matching: find.byKey(const Key('rail-focus-ring')),
      ),
    )
    .map((box) => box.decoration as BoxDecoration)
    .toList();

class _Devices extends DemoAdminStore {
  _Devices() : super(scope: AdminScope.demo);

  int loadDevicesCalls = 0;

  @override
  Future<AdminResult<List<AdminDevice>>> loadDevices() async {
    loadDevicesCalls++;
    return Success(const [
      AdminDevice(
        id: 'd-1',
        label: 'Counter POS',
        deviceType: 'pos',
        branchLabel: 'Main',
        status: DeviceLifecycleStatus.active,
      ),
    ]);
  }
}
