import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'state/kds_session.dart';

/// The KDS staff PIN gate (DECISION D-006): after the device is PAIRED, a
/// personal staff PIN session is required before the kitchen board.
///
/// Watches [kdsSyncSessionProvider]: with a session it renders [child] (the app
/// root then mounts the LIVE board off the same session); without one it shows
/// the shared, MONEY-FREE [PinLoginScreen] (SECURITY T-003 — nothing on this
/// surface ever renders money). Fail-closed: no session means no board, and
/// there is no fake or bypass path.
class KdsPinGate extends ConsumerWidget {
  const KdsPinGate({
    required this.device,
    required this.staffRepository,
    required this.child,
    super.key,
  });

  /// The paired, type-checked KDS device context from the pairing gate.
  final DeviceContext device;

  /// The token-proven staff directory for the PIN pad (null => the transport
  /// was unavailable at boot; an honest error state is shown).
  final DeviceStaffRepository? staffRepository;

  /// Rendered once a staff session exists.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(kdsSyncSessionProvider);
    if (session != null) return child;

    final staff = staffRepository;
    final deviceId = device.deviceId;
    final deviceSessionId = device.deviceSessionId;
    if (staff == null || deviceId == null || deviceSessionId == null) {
      // No usable device-session handle: fail closed with the honest
      // configuration explanation — never enter, never fake.
      return const RealModeUnconfiguredView();
    }
    return PinLoginScreen(
      staffRepository: staff,
      // KDS wording for the no-staff guidance (kitchen staff/manager PINs).
      surface: AppSurface.kds,
      onStartSession: (employeeProfileId, pin) => ref
          .read(kdsSessionControllerProvider.notifier)
          .signInWithPin(
            deviceId: deviceId,
            deviceSessionId: deviceSessionId,
            employeeProfileId: employeeProfileId,
            pin: pin,
          ),
    );
  }
}
