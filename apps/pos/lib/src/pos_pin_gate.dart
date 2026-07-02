import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'state/pos_session.dart';
import 'widgets/language_selector.dart';

/// The POS staff PIN gate (DECISION D-006): after the device is PAIRED, a
/// personal staff PIN session is required before the POS surface.
///
/// Watches [posSyncSessionProvider]: with a session it renders [child] (the POS
/// surface, whose real submit/payment repositories consume the SAME session);
/// without one it shows the shared, money-free [PinLoginScreen]. Sign-in calls
/// `start_pin_session` with the RESTORED device context's in-memory
/// device-session handle — fail-closed: no session means no POS, and there is
/// no fake or bypass path.
class PosPinGate extends ConsumerWidget {
  const PosPinGate({
    required this.device,
    required this.staffRepository,
    required this.child,
    super.key,
  });

  /// The paired, type-checked device context from the pairing gate.
  final DeviceContext device;

  /// The token-proven staff directory for the PIN pad (null => the transport
  /// was unavailable at boot; an honest error state is shown).
  final DeviceStaffRepository? staffRepository;

  /// The POS surface rendered once a staff session exists.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(posSyncSessionProvider);
    if (session != null) return child;

    final staff = staffRepository;
    final deviceId = device.deviceId;
    final deviceSessionId = device.deviceSessionId;
    if (staff == null || deviceId == null || deviceSessionId == null) {
      // No usable device session handle (e.g. legacy context without one):
      // fail closed with the honest config/unpaired explanation — never enter.
      return const RealModeUnconfiguredView();
    }
    return PinLoginScreen(
      staffRepository: staff,
      // POS wording for the no-staff guidance (cashier/manager PINs).
      surface: AppSurface.pos,
      // Sprint (I): the language switcher is reachable on the PIN screen too.
      appBarActions: const [LanguageSelector()],
      onStartSession: (employeeProfileId, pin) => ref
          .read(posSessionControllerProvider.notifier)
          .signInWithPin(
            deviceId: deviceId,
            deviceSessionId: deviceSessionId,
            employeeProfileId: employeeProfileId,
            pin: pin,
          ),
    );
  }
}
