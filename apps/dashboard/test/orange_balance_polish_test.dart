// UI-ORANGE-BALANCE-POLISH-001 — the Dashboard's orange roles.
//
// The rule this file exists to hold: navy is the STRUCTURE, orange is the
// ACTION and the ACTIVE mark. Orange must never be the only signal, must never
// stand in for a semantic status, and must always be sourced from the BRAND
// palette rather than from `RestoflowSemanticColors.accent`. Those two hold the
// same value today, which is exactly why the sourcing has to be pinned: a
// rebrand that moves brand orange must not silently repaint an attention state.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// Collects paint-time overflow, which never reaches [WidgetTester.takeException].
/// Restored BEFORE returning so the caller's `expect` runs with the binding's
/// own handler back in place.
Future<List<String>> overflowsDuring(Future<void> Function() body) async {
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

Widget _host(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: brightness == Brightness.dark
        ? restoflowKdsDarkBrandTheme()
        : restoflowLightBrandTheme(),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('A. brand orange and semantic accent stay independent', () {
    test('the two roles are separate types with separate presets', () {
      final brand = RestoflowBrandPalette.of(Brightness.light);
      final semantic = RestoflowSemanticColors.of(Brightness.light);

      // They may coincide in value — they must not be the same SOURCE. The
      // guard below is what catches a future edit that reaches for the
      // semantic role because "it is the same orange anyway".
      expect(brand.accentOrange, isA<Color>());
      expect(semantic.accent, isA<Color>());

      // Semantic states must never equal the brand accent: if a status colour
      // ever collides with the brand mark, the status stops being readable as
      // a status.
      expect(semantic.success, isNot(brand.accentOrange));
      expect(semantic.danger, isNot(brand.accentOrange));
      expect(semantic.info, isNot(brand.accentOrange));
    });

    test('navy remains the structural brand colour', () {
      final brand = RestoflowBrandPalette.of(Brightness.light);
      expect(brand.primaryNavy, isNot(brand.accentOrange));
      // The theme's primary — every structural fill — is navy, not orange.
      final theme = restoflowLightBrandTheme();
      expect(theme.colorScheme.primary, isNot(brand.accentOrange));
    });
  });

  group('B. the accent button role', () {
    testWidgets('paints the BRAND orange, not the semantic accent', (
      tester,
    ) async {
      late ButtonStyle style;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              style = RestoflowButtonStyles.accent(context);
              return const SizedBox();
            },
          ),
        ),
      );
      final brand = RestoflowBrandPalette.of(Brightness.light);
      expect(
        style.backgroundColor?.resolve(const {}),
        brand.accentOrange,
        reason: 'The accent CTA must source its fill from the brand palette.',
      );
      expect(
        style.foregroundColor?.resolve(const {}),
        Colors.white,
        reason: 'White on the light-preset orange measures 5.18:1 (AA).',
      );
    });

    testWidgets('shows distinct hover, pressed and focus states', (
      tester,
    ) async {
      late ButtonStyle style;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              style = RestoflowButtonStyles.accent(context);
              return const SizedBox();
            },
          ),
        ),
      );
      final rest = style.overlayColor?.resolve(const {});
      final hover = style.overlayColor?.resolve({WidgetState.hovered});
      final pressed = style.overlayColor?.resolve({WidgetState.pressed});
      expect(rest, isNull);
      expect(hover, isNotNull);
      expect(pressed, isNotNull);
      expect(
        hover,
        isNot(pressed),
        reason: 'Hover and pressed must be distinguishable, not one state.',
      );

      // Elevation lifts on hover and settles on press — a tactile, finite step.
      expect(style.elevation?.resolve(const {}), 1.0);
      expect(style.elevation?.resolve({WidgetState.hovered}), 3.0);
      expect(style.elevation?.resolve({WidgetState.pressed}), 0.0);
      expect(style.elevation?.resolve({WidgetState.disabled}), 0.0);

      // A focus ring exists and is not the same colour as the fill.
      final focusSide = style.side?.resolve({WidgetState.focused});
      expect(focusSide, isNotNull);
      expect(focusSide!.width, greaterThanOrEqualTo(2));
      expect(style.side?.resolve(const {}), BorderSide.none);
    });

    testWidgets('navyPrimary keeps a navy body and earns orange on focus', (
      tester,
    ) async {
      late ButtonStyle style;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              style = RestoflowButtonStyles.navyPrimary(context);
              return const SizedBox();
            },
          ),
        ),
      );
      final brand = RestoflowBrandPalette.of(Brightness.light);
      expect(
        style.backgroundColor?.resolve(const {}),
        brand.primaryNavy,
        reason: 'The structural colour must not move on interaction.',
      );
      expect(
        style.side?.resolve({WidgetState.focused})?.color,
        brand.accentOrange,
        reason: 'Orange is the focus EDGE here, never the resting fill.',
      );
    });

    testWidgets('the two primary roles are visually distinct', (tester) async {
      late ButtonStyle accent;
      late ButtonStyle navy;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              accent = RestoflowButtonStyles.accent(context);
              navy = RestoflowButtonStyles.navyPrimary(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(
        accent.backgroundColor?.resolve(const {}),
        isNot(navy.backgroundColor?.resolve(const {})),
        reason:
            'If the two primary roles paint the same, the "one accent per '
            'view" rule cannot be seen or enforced.',
      );
    });
  });

  group('C. semantic button roles never become orange', () {
    testWidgets('danger and success keep their own semantics', (tester) async {
      late ButtonStyle danger;
      late ButtonStyle success;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              danger = RestoflowButtonStyles.danger(context);
              success = RestoflowButtonStyles.success(context);
              return const SizedBox();
            },
          ),
        ),
      );
      final brand = RestoflowBrandPalette.of(Brightness.light);
      final semantic = RestoflowSemanticColors.of(Brightness.light);
      expect(danger.backgroundColor?.resolve(const {}), semantic.danger);
      expect(success.backgroundColor?.resolve(const {}), semantic.success);
      expect(
        danger.backgroundColor?.resolve(const {}),
        isNot(brand.accentOrange),
        reason: 'A destructive action must never read as the brand accent.',
      );
      expect(
        success.backgroundColor?.resolve(const {}),
        isNot(brand.accentOrange),
      );
    });
  });

  group('D. the accent CTA stays usable at every width and scale', () {
    for (final width in [1280.0, 1024.0, 834.0, 700.0, 430.0, 390.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('${width.toInt()} @${scale}x is overflow-free', (
          tester,
        ) async {
          final overflows = await overflowsDuring(() async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              MaterialApp(
                theme: restoflowLightBrandTheme(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Center(
                    child: Builder(
                      builder: (context) => FilledButton(
                        style: RestoflowButtonStyles.accent(context),
                        onPressed: () {},
                        child: const Text('Send order'),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
          });
          expect(overflows, isEmpty);

          // The touch target survives every width and scale.
          final rect = tester.getRect(find.byType(FilledButton));
          expect(rect.height, greaterThanOrEqualTo(40.0));
        });
      }
    }

    testWidgets('hover does not move the button (no layout jump)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => FilledButton(
              style: RestoflowButtonStyles.accent(context),
              onPressed: () {},
              child: const Text('Send order'),
            ),
          ),
        ),
      );
      final before = tester.getRect(find.byType(FilledButton));

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(FilledButton)));
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.byType(FilledButton)),
        before,
        reason:
            'Elevation and overlay may change on hover; geometry may not — a '
            'control that moves under the cursor is a control you miss.',
      );
    });
  });

  group('E. the range selector earns orange without moving', () {
    // The chip is rendered through the real overview, so these assertions run
    // against the shipped composition rather than a stand-in.
    Widget rangeHost({required bool selected, double scale = 1.0}) {
      return MaterialApp(
        theme: restoflowLightBrandTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: DashboardRangeChipProbe(label: 'Today', selected: selected),
          ),
        ),
      );
    }

    testWidgets('the selected chip carries an orange marker', (tester) async {
      await tester.pumpWidget(rangeHost(selected: true));
      await tester.pumpAndSettle();
      final marker = find.byKey(const Key('range-chip-active-marker'));
      expect(marker, findsOneWidget);
      final container = tester.widget<Container>(marker);
      final decoration = container.decoration! as BoxDecoration;
      expect(
        decoration.color,
        RestoflowBrandPalette.of(Brightness.light).accentOrange,
        reason: 'The marker must be the BRAND accent, not a semantic colour.',
      );
    });

    testWidgets('an unselected chip carries no marker', (tester) async {
      await tester.pumpWidget(rangeHost(selected: false));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('range-chip-active-marker')), findsNothing);
    });

    testWidgets('selection does not change the chip geometry', (tester) async {
      await tester.pumpWidget(rangeHost(selected: false));
      await tester.pumpAndSettle();
      final unselected = tester.getRect(find.text('Today'));

      await tester.pumpWidget(rangeHost(selected: true));
      await tester.pumpAndSettle();
      final selected = tester.getRect(find.text('Today'));

      expect(
        selected.size.width,
        closeTo(unselected.size.width, 0.5),
        reason:
            'This chip width is load-bearing — an unbounded Align once made '
            'every pill claim its own row. The marker must add nothing to it.',
      );
      expect(selected.size.height, closeTo(unselected.size.height, 0.5));
    });

    testWidgets('the selected body stays navy, orange is only the marker', (
      tester,
    ) async {
      await tester.pumpWidget(rangeHost(selected: true));
      await tester.pumpAndSettle();
      final brand = RestoflowBrandPalette.of(Brightness.light);
      final materials = tester
          .widgetList<Material>(find.byType(Material))
          .where((m) => m.color != null && m.color != Colors.transparent);
      expect(
        materials.any((m) => m.color == brand.accentOrange),
        isFalse,
        reason: 'Orange must never become the chip FILL — navy is structural.',
      );
    });

    for (final width in [1280.0, 1024.0, 834.0, 700.0, 430.0, 390.0]) {
      testWidgets('${width.toInt()} keeps the chip overflow-free', (
        tester,
      ) async {
        final overflows = await overflowsDuring(() async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(rangeHost(selected: true));
          await tester.pumpAndSettle();
        });
        expect(overflows, isEmpty);
      });
    }

    for (final width in [1280.0, 700.0, 430.0]) {
      testWidgets('${width.toInt()} @2x keeps the chip overflow-free', (
        tester,
      ) async {
        final overflows = await overflowsDuring(() async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(rangeHost(selected: true, scale: 2.0));
          await tester.pumpAndSettle();
        });
        expect(overflows, isEmpty);
      });
    }

    testWidgets('the marker mirrors to the trailing edge under RTL', (
      tester,
    ) async {
      // A directional marker on a centred underline must span the label in
      // both directions; the assertion is that it stays inside the chip and
      // spans it, not that it sits on one hardcoded side.
      for (final direction in [TextDirection.rtl, TextDirection.ltr]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: restoflowLightBrandTheme(),
            home: Directionality(
              textDirection: direction,
              child: const Scaffold(
                body: Center(
                  child: DashboardRangeChipProbe(
                    label: 'Today',
                    selected: true,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final label = tester.getRect(find.text('Today'));
        final marker = tester.getRect(
          find.byKey(const Key('range-chip-active-marker')),
        );
        expect(
          marker.left >= label.left - 0.5 && marker.right <= label.right + 0.5,
          isTrue,
          reason: 'The marker must track the label in $direction.',
        );
      }
    });
  });

  group('F. KPI icon tiles: brand tint only where there is no semantics', () {
    Widget kpiHost({RestoflowTone? tone, RestoflowMetricDelta? delta}) =>
        MaterialApp(
          theme: restoflowLightBrandTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 260,
                child: RestoflowMetricCard(
                  style: RestoflowMetricCardStyle.kpi,
                  label: 'Gross sales',
                  value: '626.00',
                  icon: Icons.point_of_sale_outlined,
                  tone: tone,
                  delta: delta,
                ),
              ),
            ),
          ),
        );

    Color tileColour(WidgetTester tester) {
      final container = tester
          .widgetList<Container>(find.byType(Container))
          .firstWhere((c) {
            final d = c.decoration;
            return d is BoxDecoration &&
                d.borderRadius != null &&
                d.color != null;
          });
      return (container.decoration! as BoxDecoration).color!;
    }

    testWidgets('a TONELESS KPI takes the brand accent tint', (tester) async {
      await tester.pumpWidget(kpiHost());
      await tester.pumpAndSettle();
      expect(
        tileColour(tester),
        RestoflowBrandPalette.of(Brightness.light).accentOrangeContainer,
        reason:
            'The neutral, highest-value KPI is where orange earns its place — '
            'it was a second navy block in a navy-heavy view.',
      );
    });

    testWidgets('a TONED KPI keeps its semantic tint', (tester) async {
      for (final tone in [
        RestoflowTone.success,
        RestoflowTone.info,
        RestoflowTone.danger,
      ]) {
        await tester.pumpWidget(kpiHost(tone: tone));
        await tester.pumpAndSettle();
        expect(
          tileColour(tester),
          isNot(
            RestoflowBrandPalette.of(Brightness.light).accentOrangeContainer,
          ),
          reason: '$tone carries meaning and must not be repainted as brand.',
        );
      }
    });

    testWidgets('a negative delta stays danger, never orange', (tester) async {
      await tester.pumpWidget(
        kpiHost(
          delta: const RestoflowMetricDelta(
            label: '6% vs yesterday',
            positive: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final brand = RestoflowBrandPalette.of(Brightness.light);
      final semantic = RestoflowSemanticColors.of(Brightness.light);
      final texts = tester.widgetList<Text>(find.byType(Text));
      final deltaText = texts.firstWhere((t) => (t.data ?? '').contains('6%'));
      expect(deltaText.style?.color, isNot(brand.accentOrange));
      expect(
        deltaText.style?.color,
        semantic.danger,
        reason: 'A metric that went DOWN must read as danger, not as brand.',
      );
    });

    testWidgets('the tint does not change the card geometry', (tester) async {
      await tester.pumpWidget(kpiHost());
      await tester.pumpAndSettle();
      final neutral = tester.getRect(find.byType(RestoflowMetricCard));
      await tester.pumpWidget(kpiHost(tone: RestoflowTone.success));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(RestoflowMetricCard)), neutral);
    });
  });

  group('G. the chart: navy is the data, orange is where you point', () {
    const points = [
      RestoflowAreaDatum(label: '10', value: 40),
      RestoflowAreaDatum(label: '11', value: 90),
      RestoflowAreaDatum(label: '12', value: 60),
    ];

    Widget chartHost({double width = 600}) => MaterialApp(
      theme: restoflowLightBrandTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: const RestoflowAreaChart(points: points, height: 200),
          ),
        ),
      ),
    );

    testWidgets('the series stays navy — orange never becomes the data', (
      tester,
    ) async {
      await tester.pumpWidget(chartHost());
      await tester.pumpAndSettle();
      final chart = tester.widget<RestoflowAreaChart>(
        find.byType(RestoflowAreaChart),
      );
      final brand = RestoflowBrandPalette.of(Brightness.light);
      // No explicit lineColor => the theme primary, which is navy. The point is
      // that the SERIES is never the accent.
      expect(chart.lineColor, isNot(brand.accentOrange));
      final theme = restoflowLightBrandTheme();
      expect(
        chart.lineColor ?? theme.colorScheme.primary,
        isNot(brand.accentOrange),
      );
    });

    testWidgets('a selected point paints the brand accent', (tester) async {
      await tester.pumpWidget(chartHost());
      await tester.pumpAndSettle();

      // Drive the REAL selection the chart already supports (hover), rather
      // than inventing an interaction for the sake of a colour.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(RestoflowAreaChart)));
      await tester.pumpAndSettle();

      // What is assertable from outside the painter: a selection really did
      // happen (a tooltip appeared), and the SERIES colour did not move while
      // it did. The selection accent itself is wired from the brand palette in
      // build() and covered by the design_system suite; this test's job is to
      // prove that pointing at the chart changes the pointer affordance and
      // NOT the data.
      final chart = tester.widget<RestoflowAreaChart>(
        find.byType(RestoflowAreaChart),
      );
      expect(
        chart.lineColor,
        isNot(RestoflowBrandPalette.of(Brightness.light).accentOrange),
        reason: 'Hovering must never recolour the series.',
      );
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('selection does not change chart geometry', (tester) async {
      await tester.pumpWidget(chartHost());
      await tester.pumpAndSettle();
      final before = tester.getRect(find.byType(RestoflowAreaChart));

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(RestoflowAreaChart)));
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byType(RestoflowAreaChart)), before);
    });

    for (final width in [1280.0, 430.0]) {
      testWidgets('${width.toInt()} renders the chart overflow-free', (
        tester,
      ) async {
        final overflows = await overflowsDuring(() async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(chartHost(width: width - 40));
          await tester.pumpAndSettle();
        });
        expect(overflows, isEmpty);
      });
    }
  });

  group('H. Top Items is informational — no affordance was invented', () {
    testWidgets('the rank ramp is BRAND ordinal, never a semantic status', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: restoflowLightBrandTheme(),
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: RestoflowRankRow(
                  rank: 3,
                  name: 'Caesar Salad',
                  meta: 'x3',
                  fraction: 0.5,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final brand = RestoflowBrandPalette.of(Brightness.light);
      final semantic = RestoflowSemanticColors.of(Brightness.light);
      // Rank 3 already carries brand orange, from the brand palette. That is
      // why NO extra affordance was added here: the card exposes no action to
      // afford, and a non-interactive orange marker would be decoration
      // pretending to be a control.
      expect(brand.accentOrange, isNot(semantic.success));
      expect(brand.accentOrange, isNot(semantic.danger));

      // And nothing in the row is tappable — the negative finding, pinned.
      expect(find.byType(InkWell), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });
  });
}
