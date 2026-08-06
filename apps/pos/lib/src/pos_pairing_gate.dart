import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show UpgradableSyncTransport;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'state/pos_device_context.dart';
import 'widgets/language_selector.dart';

/// RF-153 POS device-pairing gate: in real mode, require a paired device before
/// the POS surface.
///
/// Shows the shared [DevicePairingScreen] until a device is paired
/// (backend-verified via [repository]), then renders [signedInChild]. Holds the
/// paired [DeviceContext] in memory only (org/branch/station/device ids + display
/// name — NO device secret/session token; secure persistence is RF-154). Absent
/// by default; never fabricates a paired device.
///
/// This gate is INJECTED (a [DevicePairingRepository] is supplied). When the
/// injected repository is also a [DeviceSessionManager] (the real RF-161
/// `SupabaseDevicePairingRepository`), the gate RESTORES a previously-paired device
/// session on launch (fail-closed: an invalid/absent session shows the pairing
/// screen). A plain pairing repository (tests / dormant) keeps the prior behaviour.
class PosPairingGate extends ConsumerStatefulWidget {
  const PosPairingGate({
    required this.repository,
    this.signedInChild,
    this.signedInBuilder,
    this.initialDevice,
    this.upgradeSignal,
    super.key,
  }) : assert(
         signedInChild != null || signedInBuilder != null,
         'provide signedInChild or signedInBuilder',
       );

  final DevicePairingRepository repository;

  /// Rendered once a device is paired (the existing POS entry). Ignored when
  /// [signedInBuilder] is provided.
  final Widget? signedInChild;

  /// Builds the paired surface WITH the validated [DeviceContext] (so the next
  /// gate can consume the in-memory device-session handle). Takes precedence
  /// over [signedInChild].
  final Widget Function(BuildContext context, DeviceContext device)?
  signedInBuilder;

  /// A pre-existing paired context (e.g. restored), or null.
  final DeviceContext? initialDevice;

  /// [POS-OFFLINE-OPERATIONS-002] Pass A: the DEGRADED boot's hold-mode
  /// transport, or null (normal boot). The gate subscribes to its single
  /// upgrade event and re-runs the restore so the server re-verifies the
  /// cached pairing (rotating/republishing the authoritative context) the
  /// moment the boot retry reconnects — silently, with no spinner and no
  /// subtree teardown, so an in-progress cart survives the reconnection.
  final UpgradableSyncTransport? upgradeSignal;

  @override
  ConsumerState<PosPairingGate> createState() => _PosPairingGateState();
}

class _PosPairingGateState extends ConsumerState<PosPairingGate> {
  /// The only device type this surface accepts (a restored KDS session must
  /// NEVER unlock the POS — fail closed to the pairing screen).
  static const String _expectedDeviceType = 'pos';

  DeviceContext? _device;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _device = widget.initialDevice;
    // PRINT-STARTUP-REPRINT-001: a device-context publish is now PENDING (this
    // frame for an injected device, or after the async restore). Device-scoped
    // preference providers must WAIT for it rather than resolve a transient
    // null to the legacy `local` namespace — see [posPrinterScopeProvider].
    // Marked synchronously here, before any POS subtree can build.
    // Marked WITHOUT touching a provider: writes are illegal while the tree is
    // building (see _publish), and this must land before the POS subtree builds.
    if (_device != null || widget.repository is DeviceSessionManager) {
      markPosDeviceRestorePending();
    }
    if (_device != null) _publish(_device);
    // Real mode: re-derive a previously-paired session from secure storage.
    if (widget.repository case final DeviceSessionManager manager
        when _device == null) {
      _restoring = true;
      _restore(manager);
    }
    // [POS-OFFLINE-OPERATIONS-002] Pass A: on a DEGRADED offline boot, the
    // single transport-upgrade event triggers a silent server re-verification
    // of the cached pairing (no spinner — the mounted subtree must survive).
    widget.upgradeSignal?.addOnUpgrade(_onTransportUpgraded);
  }

  @override
  void dispose() {
    widget.upgradeSignal?.removeOnUpgrade(_onTransportUpgraded);
    // A gate torn down before it ever published must not leave a pending mark
    // behind for the next composition to wait on.
    clearPosDeviceRestorePendingMark();
    super.dispose();
  }

  /// Mirrors the gate's device into [posDeviceContextProvider] (device
  /// settings sprint) so the ⋮ settings sheet can read it. Deferred a frame:
  /// provider writes are illegal while the tree is building.
  void _publish(DeviceContext? device) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(posDeviceContextProvider.notifier).set(device);
    });
  }

  Future<void> _restore(DeviceSessionManager manager) async {
    DeviceContext? restored;
    if (manager is DeviceSessionOutcomeManager) {
      // [POS-OFFLINE-OPERATIONS-002] Pass A: the TYPED restore keeps a server
      // verdict apart from transport-level offline. On `offline` with a
      // cached scope for the stored secret (transient evidence only, device
      // id + surface type already verified by the repository) the gate enters
      // the offline surface on that DURABLE server-verified pairing; the
      // build-time type guard below still re-checks it. A null cache — and
      // every rejected verdict — fails closed to the pairing screen as today.
      restored = switch (await manager.restoreOutcome(
        expectedDeviceType: _expectedDeviceType,
      )) {
        DeviceSessionRestored(:final context) => context,
        DeviceSessionRestoreOffline(:final cachedContext) => cachedContext,
        DeviceSessionRestoreRejected() => null,
      };
    } else {
      restored = await manager.restore(expectedDeviceType: _expectedDeviceType);
    }
    if (!mounted) return;
    setState(() {
      _device = restored;
      _restoring = false;
    });
    _publish(restored);
  }

  /// [POS-OFFLINE-OPERATIONS-002] Pass A: the degraded boot's transport was
  /// upgraded — the server is reachable again. Re-verify WITHOUT a spinner.
  void _onTransportUpgraded() {
    if (!mounted) return;
    // Typed as Object so the `is` check PROMOTES (the outcome manager is a
    // sibling interface of the pairing repository, not a subtype of it).
    final Object repository = widget.repository;
    if (repository is! DeviceSessionOutcomeManager) return;
    unawaited(_reverifyAfterUpgrade(repository));
  }

  /// Server re-verification after the in-place transport upgrade. Three exits:
  ///  * restored with the SAME pairing scope → keep the live tree (and the
  ///    bound PIN session) untouched — republishing an identical scope would
  ///    only churn the session controller for zero information;
  ///  * restored with a DIFFERENT scope → publish it (a genuine pairing
  ///    transition; downstream gates re-bind fail-closed as they always do);
  ///  * rejected → unpair locally (secret + cached scope already cleared by
  ///    the repository) and fall back to the pairing screen;
  ///  * still offline/transient → keep the cached pairing as-is and let the
  ///    boot gate's retry loop try again.
  Future<void> _reverifyAfterUpgrade(
    DeviceSessionOutcomeManager manager,
  ) async {
    final outcome = await manager.restoreOutcome(
      expectedDeviceType: _expectedDeviceType,
    );
    if (!mounted) return;
    switch (outcome) {
      case DeviceSessionRestored(:final context):
        final current = _device;
        if (current != null && _sameScope(current, context)) return;
        setState(() => _device = context);
        _publish(context);
      case DeviceSessionRestoreRejected():
        setState(() => _device = null);
        _publish(null);
      case DeviceSessionRestoreOffline():
        break;
    }
  }

  /// Whether two contexts name the SAME operational pairing — every component
  /// the PIN-session binding and the sync scope consume. Display-only fields
  /// are deliberately excluded (a cosmetic rename must not drop a session).
  static bool _sameScope(DeviceContext a, DeviceContext b) =>
      a.organizationId == b.organizationId &&
      a.restaurantId == b.restaurantId &&
      a.branchId == b.branchId &&
      a.deviceId == b.deviceId &&
      a.deviceType == b.deviceType &&
      a.deviceSessionId == b.deviceSessionId;

  @override
  Widget build(BuildContext context) {
    // Device settings sprint (Part G): when the settings sheet UNPAIRS this
    // device it clears the published context; the gate returns to the pairing
    // screen. Guarded on `_device != null` so the gate's own publishes (which
    // never null once paired) can't loop.
    ref.listen<DeviceContext?>(posDeviceContextProvider, (previous, next) {
      if (next == null && _device != null) {
        setState(() => _device = null);
      }
    });
    if (_restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // Enter ONLY for a paired device of THIS surface's type; the repo enforces
    // this on restore too, but the gate re-checks so an injected/restored
    // context of the wrong type can never unlock the POS.
    final device = _device;
    if (device != null &&
        device.isPaired &&
        device.deviceType == _expectedDeviceType) {
      return widget.signedInBuilder?.call(context, device) ??
          widget.signedInChild!;
    }
    return DevicePairingScreen(
      repository: widget.repository,
      deviceType: _expectedDeviceType,
      onPaired: (context) {
        setState(() => _device = context);
        _publish(context);
      },
      // LIVE-DEVICE-001: prefill the code from a hosted `…/pos?pair=CODE` link
      // (or a QR that encodes it) so staff don't type it by hand; null off-web.
      initialCode: pairingCodeFromUrl(),
      // Sprint (I): the language switcher is reachable before pairing too.
      appBarActions: const [LanguageSelector()],
    );
  }
}
