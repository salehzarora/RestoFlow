import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'offline_boot_view.dart';

/// PILOT-OFFLINE-BOOT-001: the retryable device-auth boot gate for POS/KDS.
///
/// Runs [bootstrap] (the app's real-mode anonymous device sign-in). Until it
/// settles it shows a themed loading screen; if the result [isOffline] (the
/// venue Wi‑Fi / Supabase is unreachable), it shows a friendly, localized
/// [OfflineBootView] with a working Retry that RE-RUNS [bootstrap] in place — no
/// app restart. When the network returns, [builder] renders the real app
/// (which rebuilds its own ProviderScope with the fresh seams). Any NON-offline
/// result (configured / unconfigured / sign-in-disabled) is passed straight to
/// [builder], preserving the existing honest states.
///
/// The loading + offline screens live OUTSIDE the app's ProviderScope — they
/// need only the locale + theme — which is precisely why [builder] is free to
/// (re)build the ProviderScope with new seams on a successful retry.
///
/// Generic over the bootstrap result type [R] so POS and KDS (whose result
/// records differ) share one gate.
class DeviceBootGate<R> extends StatefulWidget {
  const DeviceBootGate({
    required this.bootstrap,
    required this.isOffline,
    required this.builder,
    required this.locale,
    this.brightness = Brightness.light,
    this.autoRetryInterval,
    super.key,
  });

  /// Runs the device-auth bootstrap once. Expected to classify its own failures
  /// (return an offline/config result) rather than throw; a thrown error is
  /// treated defensively as offline so the retry loop stays alive.
  final Future<R> Function() bootstrap;

  /// Whether a settled [bootstrap] result means "offline — show the retry
  /// screen" (vs a result the app should render itself).
  final bool Function(R result) isOffline;

  /// Builds the real app from a NON-offline [bootstrap] result.
  final Widget Function(R result) builder;

  /// The locale for the loading + offline screens (the persisted choice, or the
  /// Arabic default) — so they are localized + RTL before the app mounts.
  final Locale locale;

  /// The theme brightness for the boot screens (POS light, KDS dark) so they
  /// look like the app that follows.
  final Brightness brightness;

  /// Gentle auto-retry cadence while offline; backs off (×1,2,4,8, capped at
  /// 30s) so a long outage never hammers Supabase. Null (the default, and
  /// tests) disables auto-retry so a pending timer never blocks
  /// `pumpAndSettle`; the real app opts in.
  final Duration? autoRetryInterval;

  @override
  State<DeviceBootGate<R>> createState() => _DeviceBootGateState<R>();
}

class _DeviceBootGateState<R> extends State<DeviceBootGate<R>> {
  late Future<R> _future;
  Timer? _autoRetryTimer;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  /// Starts (or restarts) the bootstrap and, once it settles, re-arms the gentle
  /// auto-retry if it is still offline.
  void _run() {
    _autoRetryTimer?.cancel();
    final future = widget.bootstrap();
    // Block body: an arrow closure would RETURN the Future (assignment value),
    // which setState rejects.
    setState(() {
      _future = future;
    });
    future
        .then((result) {
          if (!mounted || !identical(_future, future)) return;
          if (widget.isOffline(result)) {
            _scheduleAutoRetry();
          } else {
            _autoRetryTimer?.cancel();
          }
        })
        .catchError((Object _) {
          // bootstrap should classify its own failures; if it threw, keep the
          // retry loop alive (the FutureBuilder shows the offline screen).
          if (mounted && identical(_future, future)) _scheduleAutoRetry();
        });
  }

  void _scheduleAutoRetry() {
    final interval = widget.autoRetryInterval;
    if (interval == null) return;
    _autoRetryTimer?.cancel();
    final steps = _attempt.clamp(0, 3); // ×1, ×2, ×4, ×8
    final backoff = interval * (1 << steps);
    const cap = Duration(seconds: 30);
    final delay = backoff > cap ? cap : backoff;
    _attempt++;
    _autoRetryTimer = Timer(delay, () {
      if (mounted) _run();
    });
  }

  /// Manual Retry: reset the backoff and try again immediately.
  void _manualRetry() {
    _attempt = 0;
    _run();
  }

  @override
  void dispose() {
    _autoRetryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<R>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _shell(const _BootLoading());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _shell(_offlineView());
        }
        final result = snapshot.data as R;
        if (widget.isOffline(result)) {
          return _shell(_offlineView());
        }
        return widget.builder(result);
      },
    );
  }

  OfflineBootView _offlineView() => OfflineBootView(
    onRetry: _manualRetry,
    autoReconnecting: widget.autoRetryInterval != null,
  );

  Widget _shell(Widget child) => MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    locale: widget.locale,
    localeResolutionCallback: restoflowResolveLocale,
    theme: restoflowBaseTheme(brightness: widget.brightness),
    home: child,
  );
}

/// The brief themed splash while the bootstrap runs (replaces the frozen native
/// splash — the first frame now belongs to the app).
class _BootLoading extends StatelessWidget {
  const _BootLoading();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
