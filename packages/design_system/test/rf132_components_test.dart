import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// RF-132 — the visual-fidelity additions to the design system: the cohesive
/// [RestoflowSegmentedControl], the [RestoflowMetricCardStyle.kpi] tile with
/// its equal-height trend slot, the recomposed [RestoflowReadinessStrip] stat
/// boxes, and the [RestoflowAreaChart] optional y-axis. All additive; every
/// test runs under LTR and RTL.

Widget _app(Widget child, TextDirection direction) => MaterialApp(
  theme: restoflowBaseTheme(),
  home: Directionality(
    textDirection: direction,
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  for (final dir in TextDirection.values) {
    final tag = dir == TextDirection.rtl ? 'RTL' : 'LTR';

    testWidgets('RestoflowSegmentedControl renders one cohesive group and '
        'reports taps ($tag)', (tester) async {
      String? tapped;
      await tester.pumpWidget(
        _app(
          RestoflowSegmentedControl<String>(
            selected: 'today',
            onSelected: (v) => tapped = v,
            segments: const [
              RestoflowSegment(
                value: 'today',
                label: 'Today',
                icon: Icons.calendar_today,
                key: Key('seg-today'),
              ),
              RestoflowSegment(
                value: 'yesterday',
                label: 'Yesterday',
                key: Key('seg-yesterday'),
              ),
              RestoflowSegment(
                value: 'last7',
                label: 'Last 7 days',
                key: Key('seg-last7'),
              ),
            ],
          ),
          dir,
        ),
      );
      await tester.pumpAndSettle();

      // Every option renders inside ONE control with its stable key.
      expect(find.byType(RestoflowSegmentedControl<String>), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Last 7 days'), findsOneWidget);
      expect(find.byKey(const Key('seg-today')), findsOneWidget);
      expect(find.byKey(const Key('seg-yesterday')), findsOneWidget);
      expect(find.byKey(const Key('seg-last7')), findsOneWidget);
      // The decorative icon renders only on the selected segment.
      expect(find.byIcon(Icons.calendar_today), findsOneWidget);

      // Tapping an unselected segment reports its value to the caller.
      await tester.tap(find.byKey(const Key('seg-last7')));
      await tester.pumpAndSettle();
      expect(tapped, 'last7');
      expect(tester.takeException(), isNull);
    });

    testWidgets('RestoflowSegmentedControl announces button + selection '
        'semantics ($tag)', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          RestoflowSegmentedControl<int>(
            selected: 1,
            onSelected: (_) {},
            segments: const [
              RestoflowSegment(value: 1, label: 'Active option'),
              RestoflowSegment(value: 2, label: 'Other option'),
            ],
          ),
          dir,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Active option')),
        matchesSemantics(
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          label: 'Active option',
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Other option')),
        matchesSemantics(
          isButton: true,
          isSelected: false,
          hasSelectedState: true,
          label: 'Other option',
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('RestoflowSegmentedControl expand mode fits narrow widths '
        'without overflowing ($tag)', (tester) async {
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 320,
            child: RestoflowSegmentedControl<int>(
              expand: true,
              selected: 0,
              onSelected: (_) {},
              segments: const [
                RestoflowSegment(value: 0, label: 'Today'),
                RestoflowSegment(value: 1, label: 'Yesterday'),
                RestoflowSegment(value: 2, label: 'Last 7 days'),
                RestoflowSegment(value: 3, label: 'Last 30 days'),
              ],
            ),
          ),
          dir,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Last 30 days'), findsOneWidget);
    });

    testWidgets('RestoflowMetricCard kpi style keeps one height with and '
        'without a delta, and fabricates no trend ($tag)', (tester) async {
      await tester.pumpWidget(
        _app(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              SizedBox(
                width: 220,
                child: RestoflowMetricCard(
                  key: Key('kpi-with-delta'),
                  style: RestoflowMetricCardStyle.kpi,
                  tone: RestoflowTone.info,
                  label: 'Orders',
                  value: '15',
                  icon: Icons.receipt_long_outlined,
                  delta: RestoflowMetricDelta(
                    label: '9% vs yesterday',
                    positive: true,
                  ),
                ),
              ),
              SizedBox(
                width: 220,
                child: RestoflowMetricCard(
                  key: Key('kpi-no-delta'),
                  style: RestoflowMetricCardStyle.kpi,
                  label: 'Avg. order value',
                  value: '₪88.57',
                  icon: Icons.trending_up,
                ),
              ),
            ],
          ),
          dir,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('15'), findsOneWidget);
      expect(find.text('₪88.57'), findsOneWidget);
      // The delta renders only where the caller provided one (never invented).
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsNothing);
      expect(find.text('9% vs yesterday'), findsOneWidget);
      // The empty trend slot keeps both KPI tiles at ONE height.
      final withDelta = tester.getSize(find.byKey(const Key('kpi-with-delta')));
      final noDelta = tester.getSize(find.byKey(const Key('kpi-no-delta')));
      expect(noDelta.height, withDelta.height);
      expect(tester.takeException(), isNull);
    });

    testWidgets('RestoflowReadinessStrip stat boxes stay tappable and stack '
        'on narrow widths ($tag)', (tester) async {
      var taps = 0;
      Widget strip() => RestoflowReadinessStrip(
        ready: false,
        readyLabel: 'Branch ready for service',
        pendingLabel: 'Setup',
        percent: 75,
        stats: [
          RestoflowReadinessStat(
            icon: Icons.print_outlined,
            label: 'Printers',
            done: 0,
            total: 0,
            onTap: () => taps++,
            tapKey: const Key('strip-stat-printers'),
          ),
        ],
      );

      // Wide: single-row composition.
      await tester.pumpWidget(_app(SizedBox(width: 900, child: strip()), dir));
      await tester.pumpAndSettle();
      expect(find.text('Setup'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('Printers'), findsOneWidget);
      expect(find.text('0/0'), findsOneWidget);
      await tester.tap(find.byKey(const Key('strip-stat-printers')));
      expect(taps, 1);

      // Narrow: the stacked composition still renders everything, no overflow.
      await tester.pumpWidget(_app(SizedBox(width: 360, child: strip()), dir));
      await tester.pumpAndSettle();
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('0/0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('RestoflowAreaChart renders the optional y-axis and repaints '
        'when its ticks change ($tag)', (tester) async {
      const points = [
        RestoflowAreaDatum(label: '08', value: 0),
        RestoflowAreaDatum(label: '12', value: 9000),
        RestoflowAreaDatum(label: '16', value: 13240),
        RestoflowAreaDatum(label: '20', value: 4000),
      ];
      String labelOf(int v) => '₪$v';

      Widget chart(List<int>? ticks) => SizedBox(
        width: 600,
        child: RestoflowAreaChart(
          points: points,
          peakValueLabel: '₪132.40',
          yAxisTicks: ticks,
          yAxisLabelBuilder: labelOf,
        ),
      );

      await tester.pumpWidget(
        _app(chart(const [5000, 10000, 15000, 20000]), dir),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final first = _chartPainter(tester);

      await tester.pumpWidget(
        _app(chart(const [10000, 20000, 30000, 40000]), dir),
      );
      await tester.pumpAndSettle();
      final second = _chartPainter(tester);
      expect(second.shouldRepaint(first), isTrue);

      // Without ticks the original rendering still works (default unchanged).
      await tester.pumpWidget(_app(chart(null), dir));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

/// Reads the area chart's painter (the first descendant CustomPaint carrying
/// one) so repaint behavior can be asserted across pumps.
CustomPainter _chartPainter(WidgetTester tester) {
  final paints = tester.widgetList<CustomPaint>(
    find.descendant(
      of: find.byType(RestoflowAreaChart),
      matching: find.byType(CustomPaint),
    ),
  );
  return paints.firstWhere((p) => p.painter != null).painter!;
}
