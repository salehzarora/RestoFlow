import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// RF-127 — the additive [RestoflowAreaChart]: renders a caller-supplied integer
/// series in LTR/RTL, exposes an accessible textual summary, renders zero data
/// honestly, and draws nothing for an empty series. Static (pumpAndSettle-safe).

Widget _app(
  Widget child, {
  TextDirection dir = TextDirection.ltr,
  double width = 600,
}) => MaterialApp(
  theme: restoflowBaseTheme(),
  home: Directionality(
    textDirection: dir,
    child: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);

const _points = [
  RestoflowAreaDatum(label: '09', value: 4000),
  RestoflowAreaDatum(label: '12', value: 8000),
  RestoflowAreaDatum(label: '14', value: 13240),
  RestoflowAreaDatum(label: '18', value: 6000),
];

void main() {
  for (final dir in TextDirection.values) {
    final tag = dir == TextDirection.rtl ? 'RTL' : 'LTR';

    testWidgets('renders a series with a peak + summary ($tag)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          dir: dir,
          const RestoflowAreaChart(
            points: _points,
            peakValueLabel: '₪132.40',
            semanticsLabel: 'Sales by hour: ₪132.40',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The accessible textual summary is exposed to screen readers.
      expect(find.bySemanticsLabel(RegExp('Sales by hour')), findsOneWidget);
      handle.dispose();
    });
  }

  testWidgets('an empty series renders nothing (zero height)', (tester) async {
    await tester.pumpWidget(_app(const RestoflowAreaChart(points: [])));
    await tester.pumpAndSettle();
    // SizedBox.shrink() => no vertical extent (the width is forced by the test
    // harness's fixed-width wrapper, so only the height proves "nothing drawn").
    expect(tester.getSize(find.byType(RestoflowAreaChart)).height, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an all-zero series renders honestly without exception', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const RestoflowAreaChart(
          points: [
            RestoflowAreaDatum(label: '09', value: 0),
            RestoflowAreaDatum(label: '10', value: 0),
            RestoflowAreaDatum(label: '11', value: 0),
          ],
          peakValueLabel: '₪0.00',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(RestoflowAreaChart), findsOneWidget);
  });

  testWidgets('a single point renders without exception', (tester) async {
    await tester.pumpWidget(
      _app(
        const RestoflowAreaChart(
          points: [RestoflowAreaDatum(label: '09', value: 4000)],
          peakValueLabel: '₪40.00',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a dense 24-point series lays out without overflow at phone '
      'width', (tester) async {
    await tester.pumpWidget(
      _app(
        width: 360,
        RestoflowAreaChart(
          points: [
            for (var h = 0; h < 24; h++)
              RestoflowAreaDatum(
                label: h.toString().padLeft(2, '0'),
                value: (h % 6) * 1000,
              ),
          ],
          peakValueLabel: '₪50.00',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('repaints when a paint-affecting property changes (regression: '
      'shouldRepaint must cover every input)', (tester) async {
    CustomPainter painterOf() => tester
        .widget<CustomPaint>(
          find
              .descendant(
                of: find.byType(RestoflowAreaChart),
                matching: find.byType(CustomPaint),
              )
              .first,
        )
        .painter!;

    // A STABLE points list across all rebuilds so only the changed property can
    // trigger (or fail to trigger) a repaint.
    await tester.pumpWidget(
      _app(const RestoflowAreaChart(points: _points, maxLabels: 7)),
    );
    final first = painterOf();

    // Identical props => no repaint needed.
    await tester.pumpWidget(
      _app(const RestoflowAreaChart(points: _points, maxLabels: 7)),
    );
    expect(painterOf().shouldRepaint(first), isFalse);

    // A paint-affecting property changed (maxLabels) => MUST repaint (before the
    // fix, shouldRepaint ignored maxLabels and left stale output).
    await tester.pumpWidget(
      _app(const RestoflowAreaChart(points: _points, maxLabels: 3)),
    );
    expect(painterOf().shouldRepaint(first), isTrue);

    // A direct paint-affecting property (line colour) also triggers a repaint.
    await tester.pumpWidget(
      _app(
        const RestoflowAreaChart(
          points: _points,
          maxLabels: 7,
          lineColor: Color(0xFF123456),
        ),
      ),
    );
    expect(painterOf().shouldRepaint(first), isTrue);
  });

  testWidgets('lays out safely at increased text scale (2.5x) at 390px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: restoflowBaseTheme(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2.5)),
            child: const Scaffold(
              body: RestoflowAreaChart(
                points: _points,
                peakValueLabel: '₪132.40',
                semanticsLabel: 'Sales by hour: ₪132.40',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // No exception / overflow at increased text scale on a narrow width.
    expect(tester.takeException(), isNull);
    expect(find.byType(RestoflowAreaChart), findsOneWidget);
  });
}
