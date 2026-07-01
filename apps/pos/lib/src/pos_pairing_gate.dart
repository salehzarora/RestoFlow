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
/// This gate is INJECTED (a [DevicePairingRepository] is supplied). Production
/// POS leaves it dormant until the real device-session repository + secure
/// storage land (RF-154), so real-mode POS keeps its current behaviour and no
/// fake pairing is ever shown.
class PosPairingGate extends StatefulWidget {
  const PosPairingGate({
    required this.repository,
    required this.signedInChild,
    this.initialDevice,
    super.key,
  });

  final DevicePairingRepository repository;

  /// Rendered once a device is paired (the existing POS entry).
  final Widget signedInChild;

  /// A pre-existing paired context (e.g. restored), or null.
  final DeviceContext? initialDevice;

  @override
  State<PosPairingGate> createState() => _PosPairingGateState();
}

class _PosPairingGateState extends State<PosPairingGate> {
  DeviceContext? _device;

  @override
  void initState() {
    super.initState();
    _device = widget.initialDevice;
  }

  @override
  Widget build(BuildContext context) {
    if (_device?.isPaired ?? false) return widget.signedInChild;
    return DevicePairingScreen(
      repository: widget.repository,
      deviceType: 'pos',
      onPaired: (context) => setState(() => _device = context),
    );
  }
}
