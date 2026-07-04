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
class PosPinGate extends ConsumerStatefulWidget {
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
  ConsumerState<PosPinGate> createState() => _PosPinGateState();
}

/// RF-118: the gate observes the app lifecycle so a PIN session that has gone
/// stale (inactivity or the absolute max age, per [posPinSessionExpiryPolicyProvider])
/// is ended on the NEXT resume — never mid-order — and the operator is asked to
/// re-enter their PIN. Demo mode never mounts this gate; a normal/smoke session
/// (seconds–minutes, not backgrounded) never trips the policy.
class _PosPinGateState extends ConsumerState<PosPinGate>
    with WidgetsBindingObserver {
  bool _expiredNotice = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ref.read(posSessionControllerProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      final policy = ref.read(posPinSessionExpiryPolicyProvider);
      if (controller.endSessionIfExpired(policy) && mounted) {
        setState(() => _expiredNotice = true);
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      controller.noteAppPaused();
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final session = ref.watch(posSyncSessionProvider);
    if (session != null) {
      // Re-authenticated: clear any stale "expired" notice for the next sign-out.
      if (_expiredNotice) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _expiredNotice = false);
        });
      }
      return widget.child;
    }

    final staff = widget.staffRepository;
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
      // RF-118: a visible client cooldown mirroring the server per-(employee,
      // device) lockout — scope the client counter by deviceId + employee so one
      // operator's mistakes never lock the whole device/restaurant.
      attemptLimiter: ref.watch(pinAttemptLimiterProvider),
      attemptScope: (member) => '$deviceId:${member.employeeProfileId}',
      // RF-118: shown after an inactivity/max-age expiry signed the operator out.
      expiredNotice: _expiredNotice,
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
