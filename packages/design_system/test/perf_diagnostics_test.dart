import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// DEVICE-RUNTIME-LARGE-TABLET-PERF-110 — the shared TEST-BUILD-ONLY perf
/// diagnostics: flag default, stats math, rolling recorder, panel rendering.
void main() {
  test('the flag is compile-time FALSE by default (inert in production)', () {
    expect(perfDiagnosticsEnabled(), isFalse);
  });

  group('PerfFrameStats.fromSamples', () {
    PerfFrameSample s(double total, {double build = 0, double raster = 0}) =>
        PerfFrameSample(buildMs: build, rasterMs: raster, totalMs: total);

    test('empty → zeros', () {
      final st = PerfFrameStats.fromSamples(const []);
      expect(st.sampleCount, 0);
      expect(st.p95TotalMs, 0);
      expect(st.jankyFrames, 0);
      expect(st.severeJankFrames, 0);
    });

    test('averages, nearest-rank p95 and jank thresholds', () {
      final samples = <PerfFrameSample>[
        for (var i = 1; i <= 20; i++)
          s(i.toDouble(), build: i * 0.5, raster: i * 0.25),
      ];
      final st = PerfFrameStats.fromSamples(samples);
      expect(st.sampleCount, 20);
      expect(st.averageBuildMs, closeTo(10.5 * 0.5, 1e-9));
      expect(st.averageRasterMs, closeTo(10.5 * 0.25, 1e-9));
      // nearest rank: ceil(0.95 * 20) = 19 → 19.0
      expect(st.p95TotalMs, 19);
      // > 16.7 ms: 17,18,19,20 → 4 ; > 33.3: none
      expect(st.jankyFrames, 4);
      expect(st.severeJankFrames, 0);
    });

    test('severe jank counted once per frame, also counted as janky', () {
      final st = PerfFrameStats.fromSamples([s(10), s(20), s(40), s(100)]);
      expect(st.jankyFrames, 3);
      expect(st.severeJankFrames, 2);
      expect(st.p95TotalMs, 100);
    });

    test('a single sample is its own p95', () {
      expect(PerfFrameStats.fromSamples([s(7)]).p95TotalMs, 7);
    });
  });

  group('PerfFrameRecorder', () {
    test('rolling window honors capacity and reset empties it', () {
      final r = PerfFrameRecorder(capacity: 3);
      for (var i = 1; i <= 5; i++) {
        r.addSample(
          PerfFrameSample(buildMs: 0, rasterMs: 0, totalMs: i.toDouble()),
        );
      }
      expect(r.sampleCount, 3);
      expect(r.stats.p95TotalMs, 5); // only 3,4,5 remain
      r.reset();
      expect(r.sampleCount, 0);
      expect(r.stats, PerfFrameStats.empty);
      expect(r.isRecording, isFalse);
    });

    testWidgets('start/stop registers and removes the timings callback', (
      tester,
    ) async {
      final r = PerfFrameRecorder(capacity: 10);
      r.start();
      expect(r.isRecording, isTrue);
      r.start(); // idempotent
      r.stop();
      expect(r.isRecording, isFalse);
      r.stop(); // idempotent
    });
  });

  group('PerfDiagnosticsPanel', () {
    testWidgets('renders device metrics, extra rows, frame stats and reset', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final r = PerfFrameRecorder(capacity: 10);
      r.addSample(const PerfFrameSample(buildMs: 4, rasterMs: 6, totalMs: 40));
      r.addSample(const PerfFrameSample(buildMs: 2, rasterMs: 2, totalMs: 8));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PerfDiagnosticsPanel(
                appLabel: 'POS',
                resetLabel: 'Reset',
                recorder: r,
                extraRows: const [(label: 'pos layout mode', value: 'tablet')],
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('perf-diagnostics-panel')), findsOneWidget);
      expect(find.text('POS'), findsOneWidget);
      expect(find.text('1200 × 800'), findsOneWidget); // logical
      expect(find.text('2.000'), findsOneWidget); // dpr
      expect(find.text('2400 × 1600'), findsOneWidget); // physical
      expect(find.text('landscape'), findsOneWidget);
      expect(find.text('tablet'), findsOneWidget);
      // samples — the recorder was never started, and the row says so.
      expect(find.text('2 (recorder off)'), findsOneWidget);
      expect(find.text('3.00'), findsOneWidget); // avg build (4+2)/2
      expect(find.text('4.00'), findsOneWidget); // avg raster (6+2)/2
      expect(find.text('40.0'), findsOneWidget); // p95
      // janky (>16.7) = 1, severe (>33.3) = 1
      expect(find.text('1'), findsNWidgets(2));

      await tester.tap(find.byKey(const Key('perf-diagnostics-reset')));
      await tester.pump();
      expect(r.sampleCount, 0);
      expect(find.text('0.0'), findsOneWidget); // p95 back to 0
    });
  });
}
