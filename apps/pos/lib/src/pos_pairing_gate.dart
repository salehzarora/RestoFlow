import 'package:flutter/material.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

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
class PosPairingGate extends StatefulWidget {
  const PosPairingGate({
    required this.repository,
    this.signedInChild,
    this.signedInBuilder,
    this.initialDevice,
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

  @override
  State<PosPairingGate> createState() => _PosPairingGateState();
}

class _PosPairingGateState extends State<PosPairingGate> {
  /// The only device type this surface accepts (a restored KDS session must
  /// NEVER unlock the POS — fail closed to the pairing screen).
  static const String _expectedDeviceType = 'pos';

  DeviceContext? _device;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _device = widget.initialDevice;
    // Real mode: re-derive a previously-paired session from secure storage.
    if (widget.repository case final DeviceSessionManager manager
        when _device == null) {
      _restoring = true;
      _restore(manager);
    }
  }

  Future<void> _restore(DeviceSessionManager manager) async {
    final restored = await manager.restore(
      expectedDeviceType: _expectedDeviceType,
    );
    if (!mounted) return;
    setState(() {
      _device = restored;
      _restoring = false;
    });
  }

  @override
  Widget build(BuildContext context) {
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
      onPaired: (context) => setState(() => _device = context),
    );
  }
}
