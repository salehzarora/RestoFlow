import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext, DeviceSessionCredential, DeviceSessionSecretStore;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show
        KitchenModePrinterOnlyWithRevision,
        KitchenModeResult,
        KitchenModeVerifiedKds;

import 'pos_kitchen_spool_runtime.dart' show sessionFingerprint;
import 'pos_secure_kitchen_mode_cache.dart';

/// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap A) — the OFFLINE readiness seed.
///
/// Reads the FRESH, TRUSTED secure-cached kitchen mode for the CURRENT scope (or
/// null), so a returning cashier's printer_only/kds mode resolves the submission
/// readiness BEFORE any network verification — a printer_only branch can then emit
/// direct_print offline. A stale/expired/untrusted, scope-mismatched, or
/// credential-less record returns null (fail-closed → submission stays blocked
/// until the heartbeat verifies). NATIVE-only (the secure cache does not exist on
/// web); never logs the token/scope, and returns only a typed mode.
Future<KitchenModeResult?> readVerifiedCachedMode({
  required PosSecureKitchenModeCache cache,
  required DeviceSessionSecretStore secretStore,
  required DeviceContext? context,
  DateTime Function()? now,
}) async {
  if (context == null) return null;
  final restaurantId = context.restaurantId;
  final deviceId = context.deviceId;
  if (restaurantId == null || deviceId == null) return null;
  DeviceSessionCredential? cred;
  try {
    cred = await secretStore.read();
  } on Object {
    return null;
  }
  if (cred == null) return null;
  final record = await cache.read(
    organizationId: context.organizationId,
    restaurantId: restaurantId,
    branchId: context.branchId,
    deviceId: deviceId,
    sessionFingerprint: sessionFingerprint(cred.sessionToken),
  );
  if (record == null) return null;
  // Only a FRESH record (<=10 min) is trusted to allow a dispatch decision; a
  // stale/expired one is used elsewhere only to REFUSE work, never here.
  final clock = now ?? DateTime.now;
  if (kitchenModeCacheFreshness(record, clock()) !=
      KitchenModeCacheFreshness.fresh) {
    return null;
  }
  final revision = record.modeRevision;
  switch (record.mode) {
    case 'printer_only':
      // D1: printer_only is trusted for direct_print ONLY with a positive revision.
      return revision == null
          ? null
          : KitchenModePrinterOnlyWithRevision(
              revision: revision,
              verifiedAt: record.verifiedAt,
            );
    case 'kds':
      return KitchenModeVerifiedKds(
        verifiedAt: record.verifiedAt,
        revision: revision,
      );
    default:
      return null;
  }
}
