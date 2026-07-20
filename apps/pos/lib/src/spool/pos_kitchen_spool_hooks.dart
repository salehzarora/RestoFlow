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
