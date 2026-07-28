// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap A) test support.
//
// Real-mode ORDER-FLOW tests render `PosMenuScreen` WITHOUT the
// `PosSyncLifecycle` wrapper, so the kitchen-mode readiness heartbeat never
// constructs and the Gap-A readiness gate stays `Loading` (Send blocked) — the
// correct production default for a freshly launched, still-unverified native
// POS. Those tests are not about the mode gate; they need the app in the state
// production reaches once startup verification has resolved the branch mode as
// the normal KDS workflow. This override injects exactly that resolved state so
// the unrelated flow under test can reach the real Send path.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/data/kitchen_mode_readiness.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';

final class _VerifiedKdsReadiness extends PosKitchenModeReadinessController {
  @override
  PosKitchenModeReadiness build() {
    // Finding 1: resolve to verified-KDS FOR THE ACTIVE DEVICE SCOPE so the
    // submit-time scope check (Finding 1E) matches. When the flow test switches
    // scope, this rebuilds and re-resolves for the new scope (these tests are not
    // themselves exercising the cross-scope race — the real controller covers it).
    final scope = PosKitchenModeScopeKey.fromContext(
      ref.watch(posDeviceContextProvider),
    );
    return KitchenModeReadinessResolved(
      KitchenModeVerifiedKds(verifiedAt: DateTime.utc(2026, 1, 1)),
      scope,
    );
  }
}

/// A `ProviderScope` override that resolves the POS kitchen-mode readiness to
/// verified-KDS, simulating a POS whose startup lifecycle already verified the
/// branch mode. Use in real-mode flow tests that do not render
/// `PosSyncLifecycle` and are not themselves exercising the readiness gate.
Override verifiedKdsReadinessOverride() =>
    posKitchenModeReadinessProvider.overrideWith(_VerifiedKdsReadiness.new);
