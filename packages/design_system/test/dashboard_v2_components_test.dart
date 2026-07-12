import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// Dashboard V2 — the interactive area-chart additions: monotone smoothing
/// (opt-in), pointer/keyboard point selection with a REAL-point tooltip, and
/// unchanged display-only defaults. Exercised under LTR and RTL.

Widget _app(Widget child, TextDirection direction) => MaterialApp(
  theme: restoflowBaseTheme(),
  home: Directionality(
    textDirection: direction,
    child: Scaffold(body: Center(child: child)),
  ),
);

const _points = [
  RestoflowAreaDatum(label: '08', value: 0),
  RestoflowAreaDatum(label: '12', value: 9000),
  RestoflowAreaDatum(label: '16', value: 13240),
  RestoflowAreaDatum(label: '20', value: 4000),
];

String _tooltip(RestoflowAreaDatum d) => '${d.label}:00\n₪${d.value}';

void main() {
  for (final dir in TextDirection.values) {
    final tag = dir == TextDirection.rtl ? 'RTL' : 'LTR';

    testWidgets('interactive chart: tap selects the nearest REAL point and '
        'shows its tooltip; keyboard moves it; Escape clears ($tag)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 600,
            child: RestoflowAreaChart(
              points: _points,
              peakValueLabel: '₪132.40',
              smooth: true,
              tooltipBuilder: _tooltip,
            ),
          ),
          dir,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(':00'), findsNothing);

      // Tap the chart's horizontal centre: 600px / 3 gaps => nearest = index 2.
      await tester.tap(find.byType(RestoflowAreaChart));
      await tester.pumpAndSettle();
      expect(find.text('16:00\n₪13240'), findsOneWidget);

      // The tap took focus, so arrows continue from the selection…
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('20:00\n₪4000'), findsOneWidget);
      // …and clamp at the series end (no phantom point).
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('20:00\n₪4000'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('16:00\n₪13240'), findsOneWidget);

      // Escape clears the selection (and its tooltip).
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.textContaining(':00'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('replacing the series with a SHORTER one clears the selection '
        'instead of crashing or showing a stale tooltip ($tag)', (
      tester,
    ) async {
      Widget chart(List<RestoflowAreaDatum> points) => _app(
        SizedBox(
          width: 600,
          child: RestoflowAreaChart(
            points: points,
            smooth: true,
            tooltipBuilder: _tooltip,
          ),
        ),
        dir,
      );

      await tester.pumpWidget(chart(_points));
      await tester.pumpAndSettle();
      // Select a high index (last point) via keyboard from the tapped point.
      await tester.tap(find.byType(RestoflowAreaChart));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('20:00\n₪4000'), findsOneWidget);

      // Same widget position, SHORTER series: no RangeError, no stale tooltip.
      const shorter = [
        RestoflowAreaDatum(label: '09', value: 100),
        RestoflowAreaDatum(label: '11', value: 200),
      ];
      await tester.pumpWidget(chart(shorter));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining(':00'), findsNothing);

      // Selection still works on the NEW series.
      await tester.tap(find.byType(RestoflowAreaChart));
      await tester.pumpAndSettle();
      expect(find.text('11:00\n₪200'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an EMPTY series followed by a shorter series renders and '
        'selects safely ($tag)', (tester) async {
      Widget chart(List<RestoflowAreaDatum> points) => _app(
        SizedBox(
          width: 600,
          child: RestoflowAreaChart(
            points: points,
            smooth: true,
            tooltipBuilder: _tooltip,
          ),
        ),
        dir,
      );

      await tester.pumpWidget(chart(const []));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      const shorter = [
        RestoflowAreaDatum(label: '09', value: 100),
        RestoflowAreaDatum(label: '11', value: 200),
      ];
      await tester.pumpWidget(chart(shorter));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(RestoflowAreaChart));
      await tester.pumpAndSettle();
      expect(find.text('11:00\n₪200'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('losing the tooltipBuilder clears the selection with the '
        'interactivity ($tag)', (tester) async {
      Widget chart({required bool interactive}) => _app(
        SizedBox(
          width: 600,
          child: RestoflowAreaChart(
            points: _points,
            smooth: true,
            tooltipBuilder: interactive ? _tooltip : null,
          ),
        ),
        dir,
      );

      await tester.pumpWidget(chart(interactive: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(RestoflowAreaChart));
      await tester.pumpAndSettle();
      expect(find.text('16:00\n₪13240'), findsOneWidget);

      await tester.pumpWidget(chart(interactive: false));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining(':00'), findsNothing);
    });

    testWidgets('display-only chart stays non-interactive: no gesture layer, '
        'no tooltip on tap ($tag)', (tester) async {
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 600,
            child: RestoflowAreaChart(points: _points, smooth: true),
          ),
          dir,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(RestoflowAreaChart),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
      await tester.tap(find.byType(RestoflowAreaChart), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.textContaining(':00'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('smooth monotone rendering handles dense, flat, and two-point '
        'series without exceptions ($tag)', (tester) async {
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RestoflowAreaChart(
                  height: 120,
                  smooth: true,
                  points: [
                    for (var h = 0; h < 24; h++)
                      RestoflowAreaDatum(label: '$h', value: (h * 37) % 500),
                  ],
                ),
                const RestoflowAreaChart(
                  height: 80,
                  smooth: true,
                  points: [
                    RestoflowAreaDatum(label: '0', value: 0),
                    RestoflowAreaDatum(label: '1', value: 0),
                    RestoflowAreaDatum(label: '2', value: 0),
                  ],
                ),
                const RestoflowAreaChart(
                  height: 80,
                  smooth: true,
                  points: [
                    RestoflowAreaDatum(label: '0', value: 5),
                    RestoflowAreaDatum(label: '1', value: 9),
                  ],
                ),
              ],
            ),
          ),
          dir,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('interactive tooltip stays inside the chart at text scale 2.0 '
        '($tag)', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 320,
            child: RestoflowAreaChart(
              points: _points,
              smooth: true,
              tooltipBuilder: _tooltip,
            ),
          ),
          dir,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(RestoflowAreaChart));
      await tester.pumpAndSettle();
      expect(find.text('16:00\n₪13240'), findsOneWidget);
      // The bubble is clamped inside the chart bounds.
      final chartRect = tester.getRect(find.byType(RestoflowAreaChart));
      final tooltipRect = tester.getRect(
        find
            .ancestor(
              of: find.text('16:00\n₪13240'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(tooltipRect.left, greaterThanOrEqualTo(chartRect.left - 0.01));
      expect(tooltipRect.right, lessThanOrEqualTo(chartRect.right + 0.01));
      expect(tester.takeException(), isNull);
    });
  }
}
