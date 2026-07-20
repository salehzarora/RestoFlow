import 'package:restoflow_data_local/restoflow_data_local.dart';

/// KITCHEN-MODE-001C2B — the bounded runtime key-capability flow (LOCKED D3).
///
///  * missing key + ZERO spool rows  -> explicit provisioning permitted
///  * missing key + ANY spool row    -> BLOCKED (restore mismatch; never
///    regenerate — a new key would strand the existing ciphertext)
///  * corrupted key                  -> BLOCKED
///  * unavailable secure storage     -> BLOCKED
///  * rows are NEVER wiped; keys are NEVER silently replaced
///
/// The flow never provisions merely because the database opened; the runtime
/// calls [provisionIfEligible] explicitly and only when policy permits.
sealed class KitchenSpoolKeyCapability {
  const KitchenSpoolKeyCapability();
}

final class KitchenSpoolKeyReady extends KitchenSpoolKeyCapability {
  const KitchenSpoolKeyReady();
}

final class KitchenSpoolKeyMissingProvisionable
    extends KitchenSpoolKeyCapability {
  const KitchenSpoolKeyMissingProvisionable();
}

final class KitchenSpoolKeyMissingWithRows extends KitchenSpoolKeyCapability {
  const KitchenSpoolKeyMissingWithRows(this.totalRows);

  final int totalRows;
}

final class KitchenSpoolKeyCorrupted extends KitchenSpoolKeyCapability {
  const KitchenSpoolKeyCorrupted();
}

final class KitchenSpoolKeyUnavailable extends KitchenSpoolKeyCapability {
  const KitchenSpoolKeyUnavailable();
}

final class PosKitchenSpoolKeyFlow {
  PosKitchenSpoolKeyFlow({
    required KitchenSpoolKeyManager keyManager,
    required KitchenSpoolStore store,
  }) : _keyManager = keyManager,
       _store = store;

  final KitchenSpoolKeyManager _keyManager;
  final KitchenSpoolStore _store;

  /// Evaluates the capability WITHOUT mutating anything: metadata row counts
  /// only (never a decryption), then the key manager's non-throwing state.
  Future<KitchenSpoolKeyCapability> evaluate() async {
    final state = await _keyManager.inspectState();
    switch (state) {
      case KitchenSpoolKeyState.present:
        return const KitchenSpoolKeyReady();
      case KitchenSpoolKeyState.corrupted:
        return const KitchenSpoolKeyCorrupted();
      case KitchenSpoolKeyState.unavailable:
        return const KitchenSpoolKeyUnavailable();
      case KitchenSpoolKeyState.missing:
        final totalRows = await _store.countTotalRows();
        return totalRows == 0
            ? const KitchenSpoolKeyMissingProvisionable()
            : KitchenSpoolKeyMissingWithRows(totalRows);
    }
  }

  /// EXPLICIT provisioning — permitted only in the missing-with-zero-rows
  /// state; every other state returns its capability unchanged (no wipe, no
  /// silent replacement, no regeneration over rows).
  Future<KitchenSpoolKeyCapability> provisionIfEligible() async {
    final capability = await evaluate();
    if (capability is! KitchenSpoolKeyMissingProvisionable) return capability;
    await _keyManager.provisionKey();
    return const KitchenSpoolKeyReady();
  }
}
