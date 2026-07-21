/// KITCHEN-MODE-001C2B — the WEB-SAFE lifecycle-facing surface of the
/// kitchen-spool runtime.
///
/// This file must stay importable by the Flutter WEB compiler: pure Dart,
/// zero imports — no dart:io, no drift/NativeDatabase, no path_provider, no
/// secure storage, no data_local. The [PosSyncLifecycle] hook and the
/// composition provider see ONLY this surface; the full native runtime
/// (which implements it) lives behind a `dart.library.io` conditional
/// import and never enters the web compile graph.
abstract interface class PosKitchenSpoolLifecycleHooks {
  /// Startup post-frame hook (LOCKED D4 cadence).
  Future<Object?> onStartup();

  /// App-resume hook (LOCKED D4 cadence).
  Future<Object?> onResume();
}

/// KITCHEN-MODE-001C3A — the WEB-SAFE lifecycle surface of the READINESS
/// heartbeat (same zero-import rule as above). Readiness-only: none of these
/// hooks may ever reach the print worker, the dispatch drain, a transport
/// send, key provisioning, or database creation.
abstract interface class PosKitchenReadinessLifecycle {
  /// Startup post-frame: arm the foreground heartbeat + report immediately.
  void onStartup();

  /// App resume: re-arm + report immediately.
  void onResume();

  /// App backgrounded/hidden: stop the periodic heartbeat.
  void onPaused();
}
