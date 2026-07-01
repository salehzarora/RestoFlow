import 'package:flutter/material.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

/// RF-153 KDS device-pairing gate. Money-FREE (a kitchen device never sees money
/// — SECURITY T-003): the shared [DevicePairingScreen] shows no money, and the
/// paired [DeviceContext] carries none.
///
/// Same pattern as the POS gate: shows the pairing screen until a KDS device is
/// paired (backend-verified via [repository]), then renders [signedInChild]. Holds
/// the paired context in memory only (ids + display name; NO device secret /
/// session token — secure persistence is RF-161). Absent by default; never
/// fabricates a paired device. When the injected repository is also a
/// [DeviceSessionManager] (the real RF-161 repo), the gate restores a
/// previously-paired session on launch (fail-closed).
class KdsPairingGate extends StatefulWidget {
  const KdsPairingGate({
    required this.repository,
    required this.signedInChild,
    this.initialDevice,
    super.key,
  });

  final DevicePairingRepository repository;

  /// Rendered once a KDS device is paired (the existing KDS entry).
  final Widget signedInChild;

  final DeviceContext? initialDevice;

  @override
  State<KdsPairingGate> createState() => _KdsPairingGateState();
}

class _KdsPairingGateState extends State<KdsPairingGate> {
  DeviceContext? _device;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _device = widget.initialDevice;
    if (widget.repository case final DeviceSessionManager manager
        when _device == null) {
      _restoring = true;
      _restore(manager);
    }
  }

  Future<void> _restore(DeviceSessionManager manager) async {
    final restored = await manager.restore();
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
    if (_device?.isPaired ?? false) return widget.signedInChild;
    return DevicePairingScreen(
      repository: widget.repository,
      deviceType: 'kds',
      onPaired: (context) => setState(() => _device = context),
    );
  }
}
