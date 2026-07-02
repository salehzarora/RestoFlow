import 'package:flutter/material.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'widgets/language_selector.dart';

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
    this.signedInChild,
    this.signedInBuilder,
    this.initialDevice,
    super.key,
  }) : assert(
         signedInChild != null || signedInBuilder != null,
         'provide signedInChild or signedInBuilder',
       );

  final DevicePairingRepository repository;

  /// Rendered once a KDS device is paired (the existing KDS entry). Ignored
  /// when [signedInBuilder] is provided.
  final Widget? signedInChild;

  /// Builds the paired surface WITH the validated [DeviceContext] (so the PIN
  /// gate can consume the in-memory device-session handle). Takes precedence
  /// over [signedInChild]. Money-free like everything on this surface.
  final Widget Function(BuildContext context, DeviceContext device)?
  signedInBuilder;

  final DeviceContext? initialDevice;

  @override
  State<KdsPairingGate> createState() => _KdsPairingGateState();
}

class _KdsPairingGateState extends State<KdsPairingGate> {
  /// The only device type this surface accepts (a restored POS session must
  /// NEVER unlock the KDS — fail closed to the pairing screen).
  static const String _expectedDeviceType = 'kds';

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
      // Branded session-restore state (design-polish sprint): the first thing
      // a real kitchen device shows on every boot is the product, not a bare
      // spinner. Still exactly ONE progress indicator on screen.
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RestoflowBrandMark(
                title: AppLocalizations.of(context).kdsAppTitle,
              ),
              const SizedBox(height: RestoflowSpacing.xl),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }
    // Enter ONLY for a paired device of THIS surface's type; the repo enforces
    // this on restore too, but the gate re-checks so an injected/restored
    // context of the wrong type can never unlock the kitchen board.
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
      // Sprint (I): the language switcher is reachable before pairing too.
      appBarActions: const [LanguageSelector()],
    );
  }
}
