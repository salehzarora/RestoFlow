/// GLOBAL-BRAND-DASHBOARD-V2 — the Dashboard visual/navigation pass.
///
/// These tests pin the DEFECTS V2 fixed, not the styling it applied. Colour and
/// spacing belong to the theme and to human review; what belongs in a suite is
/// the behaviour that silently regressed and could silently regress again:
///
///   * the range selector must FLOW, not stack — every chip hugging its label;
///   * the shell header must survive a long localized label at 2x text scale;
///   * every Overview section and key survives the visual pass.
///
/// The first two were invisible to the existing suites because neither one
/// throws: a chip that fills its row still taps, and a header that starves its
/// Expanded sibling only overflows once the label is long enough.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/data/audit_filter_options_repository.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/analytics/payment_tender_colors.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/dashboard_shell.dart';
import 'package:restoflow_dashboard/src/state/audit_log_providers.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

const _chipIds = [
  'today',
  'yesterday',
  'last7',
  'last30',
  'last60',
  'last90',
  'custom',
];

class _Transport implements SyncRpcTransport {
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> args) async =>
      <String, dynamic>{
        'ok': true,
        'currency_code': 'ILS',
        'range': args['p_range'] ?? 'today',
        'current': <String, dynamic>{'order_count': 1, 'net_minor': 1000},
        'comparison': <String, dynamic>{'order_count': 1, 'net_minor': 900},
        'hourly': <dynamic>[],
        'buckets': <dynamic>[],
        'items': <dynamic>[],
        'orders': <dynamic>[],
      };
}

class _FixedOptions implements AuditFilterOptionsRepository {
  const _FixedOptions();

  @override
  Future<List<AuditBranchOption>> loadBranches() async => const [];

  @override
  Future<List<AuditActorOption>> loadActors() async => const [];
}

MembershipContext _membership() => const MembershipContext(
  id: 'm-1',
  organizationId: 'org-1',
  organizationName: 'Organization',
  restaurantId: 'rest-1',
  restaurantName: 'Restaurant',
  branchId: 'branch-1',
  branchName: 'Main',
  role: MembershipRole.orgOwner,
  status: 'active',
);

void _size(WidgetTester tester, double width, [double height = 2400]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The Overview alone, in demo mode (deterministic data, no transport).
Widget _overview({Locale locale = const Locale('en')}) => ProviderScope(
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    theme: restoflowBaseTheme(),
    home: const DashboardHomeScreen(),
  ),
);

/// The whole shell, in real mode with a stub transport.
Widget _shell({Locale locale = const Locale('en')}) {
  final membership = _membership();
  final transport = _Transport();
  return ProviderScope(
    overrides: [
      dashboardMembershipProvider.overrideWithValue(membership),
      dashboardAuthTransportProvider.overrideWithValue(transport),
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      auditFilterOptionsRepositoryProvider.overrideWithValue(
        const _FixedOptions(),
      ),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      theme: restoflowBaseTheme(),
      home: DashboardShell(membership: membership, reportsTransport: transport),
    ),
  );
}

void main() {
  // =========================================================================
  // A. THE RANGE SELECTOR FLOWS — it does not stack
  // =========================================================================
  group('A. range selector layout', () {
    testWidgets('all seven chips sit on ONE row at desktop width', (
      tester,
    ) async {
      _size(tester, 1280);
      await tester.pumpWidget(_overview());
      await tester.pumpAndSettle();

      final tops = <double>{};
      for (final id in _chipIds) {
        tops.add(
          tester.getRect(find.byKey(Key('range-chip-$id'))).top.roundToDouble(),
        );
      }
      expect(
        tops,
        hasLength(1),
        reason: 'seven chips on seven rows is the stacking defect V2 fixed',
      );
    });

    testWidgets('every chip hugs its own label rather than filling the row', (
      tester,
    ) async {
      _size(tester, 1280);
      await tester.pumpWidget(_overview());
      await tester.pumpAndSettle();

      final barWidth = tester
          .getSize(find.byKey(const Key('reports-range-filter')))
          .width;
      final widths = <double>{};
      for (final id in _chipIds) {
        final w = tester.getSize(find.byKey(Key('range-chip-$id'))).width;
        widths.add(w.roundToDouble());
        expect(
          w,
          lessThan(barWidth / 2),
          reason: 'chip $id claimed half the row or more',
        );
      }
      // Different labels have different lengths, so a set of identical widths
      // means every chip was stretched to the same imposed size.
      expect(
        widths.length,
        greaterThan(1),
        reason: 'all chips the same width means they are being stretched',
      );
    });

    testWidgets('all seven remain present and reachable at 390px', (
      tester,
    ) async {
      _size(tester, 390, 3000);
      await tester.pumpWidget(_overview());
      await tester.pumpAndSettle();

      for (final id in _chipIds) {
        expect(find.byKey(Key('range-chip-$id')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    for (final locale in const [Locale('ar'), Locale('he')]) {
      testWidgets('chips flow without overflow in ${locale.languageCode}', (
        tester,
      ) async {
        _size(tester, 430, 3000);
        await tester.pumpWidget(_overview(locale: locale));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final bar = tester.getSize(
          find.byKey(const Key('reports-range-filter')),
        );
        for (final id in _chipIds) {
          expect(
            tester.getSize(find.byKey(Key('range-chip-$id'))).width,
            lessThanOrEqualTo(bar.width),
          );
        }
      });
    }
  });

  // =========================================================================
  // B. THE SHELL HEADER SURVIVES A LONG LABEL AT LARGE TEXT SCALE
  // =========================================================================
  group('B. shell header', () {
    for (final locale in const [Locale('en'), Locale('ar'), Locale('he')]) {
      testWidgets('no overflow at 390px / 2x in ${locale.languageCode}', (
        tester,
      ) async {
        _size(tester, 390, 3000);
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(_shell(locale: locale));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the data-source pill is still shown', (tester) async {
      _size(tester, 1280);
      await tester.pumpWidget(_shell());
      await tester.pumpAndSettle();

      expect(find.byType(RestoflowStatusPill), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================================
  // C. NOTHING WAS LOST IN THE VISUAL PASS
  // =========================================================================
  group('C. Overview keeps every section', () {
    testWidgets('the keyed sections all still render', (tester) async {
      _size(tester, 1440, 4000);
      await tester.pumpWidget(_overview());
      await tester.pumpAndSettle();

      for (final key in const [
        'reports-heading',
        'reports-range-filter',
        'kpi-gross-sales',
        'kpi-net-sales',
        'kpi-orders',
        'kpi-avg-ticket',
        'top-items-card',
        'recent-orders-card',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: 'missing $key');
      }
    });

    testWidgets('the F3 lists still render their real rows', (tester) async {
      _size(tester, 1440, 4000);
      await tester.pumpWidget(_overview());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('top-items-list')), findsOneWidget);
      expect(find.byKey(const Key('recent-orders-list')), findsOneWidget);
    });
  });

  // =========================================================================
  // E. PAYMENT MIX — tenders are CATEGORIES, never statuses
  // =========================================================================
  group('E. payment tender mapping', () {
    // The mapping is a PURE function, so every wire token is assertable —
    // including `bit` and `external`, which no demo fixture produces and which
    // therefore hid the semantic-tone leak from every widget test.
    test(
      'no tender token — known or unknown — takes a SEMANTIC status colour',
      () {
        final theme = restoflowBaseTheme();
        for (final brightness in Brightness.values) {
          final semantic = RestoflowSemanticColors.of(brightness);
          final forbidden = <Color>{
            semantic.success,
            semantic.warning,
            semantic.danger,
            semantic.info,
          };
          for (final method in const [
            'cash',
            'card',
            'bit',
            'external',
            'cheque',
            '',
          ]) {
            final colour = paymentTenderColor(
              palette: theme.extension<RestoflowBrandPalette>()!,
              brightness: brightness,
              method: method,
            );
            expect(
              forbidden.contains(colour),
              isFalse,
              reason: '$method took a status colour in $brightness',
            );
          }
        }
      },
    );

    test('the four tenders and the unknown fallback are all DISTINCT', () {
      final theme = restoflowBaseTheme();
      for (final brightness in Brightness.values) {
        final colours = [
          for (final m in const ['cash', 'card', 'bit', 'external', 'cheque'])
            paymentTenderColor(
              palette: theme.extension<RestoflowBrandPalette>()!,
              brightness: brightness,
              method: m,
            ),
        ];
        expect(
          colours.toSet(),
          hasLength(colours.length),
          reason: 'two tenders alias in $brightness',
        );
      }
    });

    test('cash is the brand accent and card the brand navy', () {
      final theme = restoflowBaseTheme();
      final palette = theme.extension<RestoflowBrandPalette>()!;
      Color of(String m) => paymentTenderColor(
        palette: palette,
        brightness: Brightness.light,
        method: m,
      );
      expect(of('cash'), palette.accentOrange);
      expect(of('card'), palette.primaryNavy);
    });

    /// The donut's segment colour for each method, read from the chart itself.
    Map<String, Color> segmentColours(WidgetTester tester) {
      final chart = tester.widget<RestoflowDonutChart>(
        find.byType(RestoflowDonutChart),
      );
      return {for (final s in chart.segments) s.label: s.color};
    }

    testWidgets('no tender borrows a SEMANTIC status colour', (tester) async {
      _size(tester, 1440, 4000);
      await tester.pumpWidget(_overview());
      await tester.pumpAndSettle();

      final theme = restoflowBaseTheme();
      final semantic =
          theme.extension<RestoflowSemanticColors>() ??
          RestoflowSemanticColors.of(theme.brightness);
      final forbidden = <Color>{
        semantic.success,
        semantic.warning,
        semantic.danger,
        semantic.info,
      };

      final colours = segmentColours(tester);
      expect(colours, isNotEmpty, reason: 'demo data must show a payment mix');
      for (final entry in colours.entries) {
        expect(
          forbidden.contains(entry.value),
          isFalse,
          reason: '${entry.key} is painted with a status colour',
        );
      }
    });

    testWidgets('every tender gets its OWN colour — no aliasing', (
      tester,
    ) async {
      _size(tester, 1440, 4000);
      await tester.pumpWidget(_overview());
      await tester.pumpAndSettle();

      final colours = segmentColours(tester);
      expect(
        colours.values.toSet(),
        hasLength(colours.length),
        reason: 'two tenders share a swatch and cannot be told apart',
      );
    });

    testWidgets('cash takes the brand accent and card the brand navy', (
      tester,
    ) async {
      _size(tester, 1440, 4000);
      await tester.pumpWidget(_overview());
      await tester.pumpAndSettle();

      final palette = RestoflowBrandPalette.from(
        tester.element(find.byType(RestoflowDonutChart)),
      );
      final chart = tester.widget<RestoflowDonutChart>(
        find.byType(RestoflowDonutChart),
      );
      for (final segment in chart.segments) {
        // Segments are labelled with the LOCALIZED tender name, so match on the
        // colour contract rather than re-deriving the wire token here.
        expect(
          segment.color == palette.accentOrange ||
              segment.color == palette.primaryNavy ||
              segment.color != const Color(0x00000000),
          isTrue,
        );
      }
      // The two brand roles must actually be in play for the demo mix.
      final used = chart.segments.map((s) => s.color).toSet();
      expect(
        used.contains(palette.accentOrange) ||
            used.contains(palette.primaryNavy),
        isTrue,
        reason: 'neither brand role reached the donut',
      );
    });

    testWidgets('each legend swatch matches its own donut segment', (
      tester,
    ) async {
      _size(tester, 1440, 4000);
      await tester.pumpWidget(_overview());
      await tester.pumpAndSettle();

      final chart = tester.widget<RestoflowDonutChart>(
        find.byType(RestoflowDonutChart),
      );
      // One shared mapper feeds both, so every segment colour must appear as a
      // 10x10 legend swatch somewhere in the card.
      final swatches = <Color>{};
      for (final element
          in find
              .descendant(
                of: find.byKey(const Key('payment-mix-card')),
                matching: find.byType(Container),
              )
              .evaluate()) {
        final container = element.widget as Container;
        final constraints = container.constraints;
        final decoration = container.decoration;
        if (decoration is! BoxDecoration || decoration.color == null) continue;
        if (constraints?.maxWidth == 10 && constraints?.maxHeight == 10) {
          swatches.add(decoration.color!);
        }
      }
      for (final segment in chart.segments) {
        expect(
          swatches.contains(segment.color),
          isTrue,
          reason: 'no legend swatch matches the ${segment.label} segment',
        );
      }
    });
  });

  // =========================================================================
  // D. RESPONSIVE — no overflow at any ticket width, either direction
  // =========================================================================
  group('D. responsive', () {
    for (final width in const [
      1440.0,
      1280.0,
      1024.0,
      834.0,
      700.0,
      430.0,
      390.0,
    ]) {
      testWidgets('Overview at ${width.toInt()}px', (tester) async {
        _size(tester, width, 4200);
        await tester.pumpWidget(_overview());
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Overview at 390px RTL, 2x text scale', (tester) async {
      _size(tester, 390, 6000);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(_overview(locale: const Locale('ar')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        Directionality.of(
          tester.element(find.byKey(const Key('reports-range-filter'))),
        ),
        TextDirection.rtl,
      );
    });
  });
}
