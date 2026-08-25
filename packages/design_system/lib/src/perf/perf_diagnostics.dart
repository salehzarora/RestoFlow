import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// DEVICE-RUNTIME-LARGE-TABLET-PERF-110 — TEST-BUILD-ONLY device metrics +
/// frame-timing diagnostics, shared by POS and Kiosk.
///
/// Gated by `--dart-define=RESTOFLOW_PERF_DIAGNOSTICS=true`. In ordinary
/// production builds [perfDiagnosticsEnabled] is a compile-time `false`, the
/// recorder is never started and the staff Device Settings entry is absent —
/// the feature is inert, not merely hidden.
///
/// Everything stays ON the device: nothing is logged, persisted or sent. No
/// PII, no order data — only viewport metrics and Flutter `FrameTiming`
/// summaries, so the owner can compare the 16" Acer against a healthy 11"
/// tablet in thirty seconds.
bool perfDiagnosticsEnabled() => const bool.fromEnvironment(
  'RESTOFLOW_PERF_DIAGNOSTICS',
  defaultValue: false,
);

/// One frame's timings in milliseconds.
@immutable
class PerfFrameSample {
  const PerfFrameSample({
    required this.buildMs,
    required this.rasterMs,
    required this.frameMs,
  });
  final double buildMs;
  final double rasterMs;
  final double frameMs;
}

/// Rolling summary of the most recent frames (see [PerfFrameRecorder]).
@immutable
class PerfFrameStats {
  const PerfFrameStats({
    required this.sampleCount,
    required this.averageBuildMs,
    required this.averageRasterMs,
    required this.p95FrameMs,
    required this.jankyFrames,
    required this.severeJankFrames,
  });

  static const empty = PerfFrameStats(
    sampleCount: 0,
    averageBuildMs: 0,
    averageRasterMs: 0,
    p95FrameMs: 0,
    jankyFrames: 0,
    severeJankFrames: 0,
  );

  /// A frame slower than one 60 Hz vsync (16.7 ms) is "janky"; slower than
  /// two (33.3 ms) is "severe".
  static const double jankThresholdMs = 1000 / 60;
  static const double severeJankThresholdMs = 2000 / 60;

  final int sampleCount;
  final double averageBuildMs;
  final double averageRasterMs;
  final double p95FrameMs;
  final int jankyFrames;
  final int severeJankFrames;

  /// Pure aggregation (unit-tested): averages, p95 of total frame time
  /// (nearest-rank), jank counts.
  factory PerfFrameStats.fromSamples(Iterable<PerfFrameSample> samples) {
    final list = samples.toList(growable: false);
    if (list.isEmpty) return empty;
    var build = 0.0;
    var raster = 0.0;
    var janky = 0;
    var severe = 0;
    final totals = List<double>.filled(list.length, 0);
    for (var i = 0; i < list.length; i++) {
      final s = list[i];
      build += s.buildMs;
      raster += s.rasterMs;
      totals[i] = s.frameMs;
      if (s.frameMs > jankThresholdMs) janky++;
      if (s.frameMs > severeJankThresholdMs) severe++;
    }
    totals.sort();
    final rank = (0.95 * totals.length).ceil().clamp(1, totals.length);
    return PerfFrameStats(
      sampleCount: list.length,
      averageBuildMs: build / list.length,
      averageRasterMs: raster / list.length,
      p95FrameMs: totals[rank - 1],
      jankyFrames: janky,
      severeJankFrames: severe,
    );
  }
}

/// Process-wide rolling frame recorder backed by
/// `SchedulerBinding.addTimingsCallback`. Keeps the last [capacity] frames;
/// [reset] empties the window. Silent (no listeners notified per frame): the
/// panel polls it, so recording never adds its own rebuilds.
class PerfFrameRecorder {
  PerfFrameRecorder({this.capacity = 1200});

  static final PerfFrameRecorder instance = PerfFrameRecorder();

  /// ~20 s at 60 Hz — the owner's 30-second samples sit comfortably inside.
  final int capacity;
  final ListQueue<PerfFrameSample> _ring = ListQueue<PerfFrameSample>();
  bool _started = false;
  DateTime? _since;

  bool get isRecording => _started;
  DateTime? get since => _since;
  int get sampleCount => _ring.length;

  void start() {
    if (_started) return;
    _started = true;
    _since = DateTime.now();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void stop() {
    if (!_started) return;
    _started = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  void reset() {
    _ring.clear();
    _since = DateTime.now();
  }

  /// Feeds samples directly (tests / the timings callback).
  @visibleForTesting
  void addSample(PerfFrameSample sample) {
    if (_ring.length >= capacity) _ring.removeFirst();
    _ring.addLast(sample);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      addSample(
        PerfFrameSample(
          buildMs: t.buildDuration.inMicroseconds / 1000,
          rasterMs: t.rasterDuration.inMicroseconds / 1000,
          frameMs: t.totalSpan.inMicroseconds / 1000,
        ),
      );
    }
  }

  PerfFrameStats get stats => PerfFrameStats.fromSamples(_ring);
}

/// A label/value pair an app adds to the panel (layout mode, stage scale…).
typedef PerfDiagnosticsRow = ({String label, String value});

/// The device-metrics + frame-timing panel. Self-refreshing once per second
/// while mounted; the app supplies its identity rows and the localized title
/// / reset copy so this shared widget carries no app strings of its own.
///
/// Metric LABELS are deliberately developer-technical English tokens (this is
/// a test-build instrument, never a production screen); the title and the
/// Reset action are localized by the host.
class PerfDiagnosticsPanel extends StatefulWidget {
  const PerfDiagnosticsPanel({
    super.key,
    required this.appLabel,
    required this.resetLabel,
    this.extraRows = const [],
    this.recorder,
    this.textColor,
    this.mutedColor,
    this.refreshEvery = const Duration(seconds: 1),
  });

  /// "POS" / "Kiosk".
  final String appLabel;

  /// Localized label for the reset-samples button.
  final String resetLabel;

  /// App-specific rows (e.g. POS shell posture, Kiosk stage scale).
  final List<PerfDiagnosticsRow> extraRows;
  final PerfFrameRecorder? recorder;
  final Color? textColor;
  final Color? mutedColor;
  final Duration refreshEvery;

  @override
  State<PerfDiagnosticsPanel> createState() => _PerfDiagnosticsPanelState();
}

class _PerfDiagnosticsPanelState extends State<PerfDiagnosticsPanel> {
  Timer? _timer;

  PerfFrameRecorder get _recorder =>
      widget.recorder ?? PerfFrameRecorder.instance;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.refreshEvery, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _f(double v, [int digits = 1]) => v.toStringAsFixed(digits);

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final dpr = mq.devicePixelRatio;
    final textColor =
        widget.textColor ?? Theme.of(context).colorScheme.onSurface;
    final muted = widget.mutedColor ?? textColor.withValues(alpha: .7);
    final stats = _recorder.stats;
    final orientation = size.width > size.height ? 'landscape' : 'portrait';
    final rows = <PerfDiagnosticsRow>[
      (label: 'app', value: widget.appLabel),
      (label: 'logical', value: '${_f(size.width, 0)} × ${_f(size.height, 0)}'),
      (label: 'devicePixelRatio', value: _f(dpr, 3)),
      (
        label: 'physical',
        value: '${(size.width * dpr).round()} × ${(size.height * dpr).round()}',
      ),
      (label: 'orientation', value: orientation),
      (label: 'textScale', value: _f(mq.textScaler.scale(1.0), 2)),
      (
        label: 'padding',
        value:
            'T${_f(mq.padding.top, 0)} B${_f(mq.padding.bottom, 0)} '
            'L${_f(mq.padding.left, 0)} R${_f(mq.padding.right, 0)}',
      ),
      (
        label: 'viewPadding',
        value:
            'T${_f(mq.viewPadding.top, 0)} B${_f(mq.viewPadding.bottom, 0)} '
            'L${_f(mq.viewPadding.left, 0)} R${_f(mq.viewPadding.right, 0)}',
      ),
      ...widget.extraRows,
      (
        label: 'frames (rolling)',
        value:
            '${stats.sampleCount}'
            '${_recorder.isRecording ? '' : ' (recorder off)'}',
      ),
      (label: 'avg build ms', value: _f(stats.averageBuildMs, 2)),
      (label: 'avg raster ms', value: _f(stats.averageRasterMs, 2)),
      (label: 'p95 frame ms', value: _f(stats.p95FrameMs, 1)),
      (label: 'janky >16.7ms', value: '${stats.jankyFrames}'),
      (label: 'severe >33.3ms', value: '${stats.severeJankFrames}'),
    ];
    return Column(
      key: const Key('perf-diagnostics-panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    r.label,
                    style: TextStyle(color: muted, fontSize: 14),
                  ),
                ),
                Expanded(
                  flex: 6,
                  child: Text(
                    r.value,
                    key: Key('perf-row-${r.label}'),
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('perf-diagnostics-reset'),
          onPressed: () => setState(_recorder.reset),
          icon: const Icon(Icons.restart_alt, size: 18),
          label: Text(widget.resetLabel),
        ),
      ],
    );
  }
}
