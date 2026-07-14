/// POS-OPERATIONS-SYNC-001 — THE canonical operational scope, as a WATCHABLE value.
///
/// Everything that caches per-branch data must key on the SAME scope, and must REACT
/// when it changes. Both halves matter:
///
///   * The recent-order store used to key on the **device id alone**, while the sync
///     cursor keyed on organization + restaurant + branch + device. A device
///     re-paired into another branch therefore kept the SAME storage key — so branch
///     A's orders were served up as branch B's. Same till, different restaurant,
///     yesterday's orders.
///
///   * It also resolved that key with `ref.read`, once, and never looked again. Even
///     the right key would have been frozen at whatever the scope happened to be when
///     the controller first built.
///
/// So the scope is a PROVIDER, it is WATCHED, and there is exactly one definition of
/// it. A controller that watches this rebuilds when the branch changes — which is the
/// only reliable way to stop showing the previous branch's orders.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;

import '../data/sync_cursor_store.dart';
import 'outbox_controller.dart' show kDemoDeviceId, kDemoOrgId, kDemoBranchId;
import 'pos_device_context.dart';
import 'pos_session.dart';

/// The DEMO till's fixed scope. Exposed so demo/tests key their caches on the SAME
/// canonical key production uses, instead of a hand-rolled guess that can drift away
/// from it (which is how the device-only key survived unnoticed for so long).
const PosSyncScope kDemoSyncScope = PosSyncScope(
  organizationId: kDemoOrgId,
  restaurantId: 'demo-restaurant',
  branchId: kDemoBranchId,
  deviceId: kDemoDeviceId,
);

/// The device's current operational scope, or null when it is not yet paired.
///
/// WATCH this. Do not re-derive it, and do not key a cache on any subset of it.
final posSyncScopeProvider = Provider<PosSyncScope?>((ref) {
  // Demo mode has one fixed, self-consistent scope so the demo behaves like a real
  // paired till rather than like an unpaired one.
  if (ref.watch(runtimeConfigProvider).isDemoMode) return kDemoSyncScope;

  final session = ref.watch(posSyncSessionProvider);
  final ctx = ref.watch(posDeviceContextProvider);
  if (ctx == null) return null;

  // A SESSION FROM ANOTHER PAIRING DOES NOT NAME THIS TILL'S SCOPE. The PIN-session
  // lifecycle is not bound to the pairing lifecycle: an unpair clears the device
  // context but leaves an established in-memory session standing (its best-effort
  // server revoke can fail offline, and nothing client-side ends it). Re-pair the
  // till into another branch and, without this check, the scope became a HYBRID —
  // the NEW pairing's organization/branch with the OLD session's device id — and
  // every pull made under it ran on the OLD branch's server session: branch A's
  // orders, displayed and durably persisted on a till standing in branch B. A
  // mismatch is therefore REFUSED outright: no scope, no sync, no cache, until the
  // operator signs in on the pairing the till actually has.
  final sessionDeviceId = session?.deviceId;
  final pairedDeviceId = ctx.deviceId;
  if (sessionDeviceId != null &&
      pairedDeviceId != null &&
      pairedDeviceId.isNotEmpty &&
      sessionDeviceId != pairedDeviceId) {
    return null;
  }

  // The device id may be known from the pairing before a PIN session exists, so a
  // paired-but-not-signed-in till still reads its OWN branch's cache rather than
  // falling back to a shared one.
  final deviceId = sessionDeviceId ?? pairedDeviceId;
  if (deviceId == null || deviceId.isEmpty) return null;

  return PosSyncScope(
    organizationId: ctx.organizationId,
    restaurantId: ctx.restaurantId ?? '',
    branchId: ctx.branchId,
    deviceId: deviceId,
  );
});
