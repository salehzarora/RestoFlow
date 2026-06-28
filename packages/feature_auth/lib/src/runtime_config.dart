import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

import 'auth_context_fetcher.dart' show authDemoModeEnabled;

/// Immutable client runtime mode - the single composition point that decides
/// whether the app runs against the in-memory Demo* repositories (the DEFAULT)
/// or the real Supabase-backed Real* repositories (RF M7 real-wiring).
///
/// It is composed from the TWO primitives that already read the compile-time
/// `--dart-define` values and introduces NO new env names:
/// - [authDemoModeEnabled] - the SOLE audit point for `RESTOFLOW_DEMO_MODE`
///   (re-used here, not re-read), which DEFAULTS TO TRUE so existing dev/local
///   run commands keep working in demo mode without any Supabase config; and
/// - [SupabaseBootstrapConfig.fromEnvironment] - the validated, fail-closed
///   reader of `RESTOFLOW_SUPABASE_URL` / `RESTOFLOW_SUPABASE_ANON_KEY` that
///   already rejects placeholders and service-role-looking keys (DECISION
///   D-011: clients use the PUBLIC anon key only; no secret in source).
///
/// FAIL-CLOSED contract: in demo mode [supabase] is null. In real mode
/// [supabase] is the validated config, or null when the config was
/// missing/invalid/service-role - in which case Real* repositories must surface
/// a clear 'real mode not yet wired / unconfigured' error rather than touching a
/// backend or silently falling back to a fake-live screen. Real mode never
/// bypasses auth and never crashes the app at this layer.
class RuntimeConfig {
  const RuntimeConfig._(this.isDemoMode, this.supabase);

  /// Whether the app runs the in-memory Demo* repositories (the DEFAULT).
  final bool isDemoMode;

  /// The validated Supabase connection config (anon key only). It is null in
  /// demo mode, and also null in real mode when the `--dart-define` config was
  /// missing/invalid/service-role (fail-closed): Real* repos then error out
  /// instead of contacting a backend.
  final SupabaseBootstrapConfig? supabase;

  /// Real mode is simply the negation of demo mode (single source of truth).
  bool get isRealMode => !isDemoMode;

  /// Builds the runtime config from the existing compile-time `--dart-define`
  /// reads. [demoModeOverride] lets a host force the mode (e.g. tests) without
  /// re-reading any env value; when omitted, the audited [authDemoModeEnabled]
  /// read decides, defaulting to demo.
  factory RuntimeConfig.fromEnvironment({bool? demoModeOverride}) {
    final demo = demoModeOverride ?? authDemoModeEnabled();
    if (demo) {
      return const RuntimeConfig._(true, null);
    }
    try {
      return RuntimeConfig._(false, SupabaseBootstrapConfig.fromEnvironment());
    } on SupabaseConfigException {
      // Fail-closed: real mode with missing/invalid/service-role config yields a
      // config-less RuntimeConfig so Real* repos error clearly. Never bypass,
      // never crash, never echo the offending value.
      return const RuntimeConfig._(false, null);
    }
  }

  /// Test seam: build an explicit config WITHOUT reading any `--dart-define`.
  /// Lets pure `ProviderContainer` tests force demo/real selection (and, in real
  /// mode, supply or omit a [supabase] config) with no SupabaseClient and no
  /// network.
  factory RuntimeConfig.test({
    required bool isDemoMode,
    SupabaseBootstrapConfig? supabase,
  }) => RuntimeConfig._(isDemoMode, supabase);
}

/// The global swap point every repository seam watches to choose Demo* (default)
/// or Real*. Apps and tests override this with
/// `runtimeConfigProvider.overrideWithValue(...)` to force a mode; by default it
/// composes the mode from the existing audited dart-define reads.
final runtimeConfigProvider = Provider<RuntimeConfig>(
  (ref) => RuntimeConfig.fromEnvironment(),
);
