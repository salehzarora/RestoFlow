import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';

import 'state/kds_session.dart';
import 'widgets/language_selector.dart';

/// RF-118: the KDS staff PIN-session expiry LIFECYCLE observer, mounted at the
/// app ROOT (above the live/non-live `home` swap).
///
/// WHY app-level (not inside the gate, unlike the POS): the KDS routes the LIVE
/// board (`KdsSyncedHome`) as a SIBLING of the PIN gate — `home: live ? board :
/// nonLiveHome` — so the gate is UNMOUNTED the instant a staff session goes live.
/// An observer inside the gate would therefore be torn down exactly when expiry
/// matters (during an active session). Wrapping the whole `home` keeps ONE
/// observer alive across the swap. On resume it ends a stale session (per
/// [kdsPinSessionExpiryPolicyProvider], inactivity or max age) — which flips the
/// session null, so the app root re-mounts the gate — and raises
/// [kdsExpiredNoticeProvider] so the re-mounted gate shows the "enter PIN again"
/// notice; a new session clears it. The KDS surface stays MONEY-FREE throughout.
class KdsSessionLifecycleObserver extends ConsumerStatefulWidget {
  const KdsSessionLifecycleObserver({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<KdsSessionLifecycleObserver> createState() =>
      _KdsSessionLifecycleObserverState();
}

class _KdsSessionLifecycleObserverState
    extends ConsumerState<KdsSessionLifecycleObserver>
    with WidgetsBindingObserver {
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
    final controller = ref.read(kdsSessionControllerProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      final policy = ref.read(kdsPinSessionExpiryPolicyProvider);
      if (controller.endSessionIfExpired(policy)) {
        ref.read(kdsExpiredNoticeProvider.notifier).show();
        return; // session legitimately expired -> PIN gate; nothing to resume
      }
      // PILOT-OPERATIONS-CORRECTIONS-001: the PIN session survived the background.
      // Trigger the sync coordinator to re-evaluate reachability and pull fresh,
      // un-latching any transient terminal stop caused by the outage — so the
      // board recovers on resume instead of staying stuck until a full app
      // restart. Only when a live sync session exists (the board is up); the
      // source provider is unavailable otherwise, so guard fail-soft.
      if (ref.read(kdsSyncSessionProvider) != null) {
        try {
          unawaited(ref.read(kdsRepositoryProvider).resume());
        } catch (_) {
          // No sync source in this context (e.g. not the live board) — nothing
          // to resume; the honest state is unchanged.
        }
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      controller.noteAppPaused();
    }
  }

  @override
  Widget build(BuildContext context) {
    // A newly established session clears any stale "expired" notice (the gate is
    // re-mounted only when a session is null, so clearing here is enough).
    ref.listen(kdsSyncSessionProvider, (previous, next) {
      if (next != null) {
        ref.read(kdsExpiredNoticeProvider.notifier).clear();
      }
    });
    return widget.child;
  }
}

/// The KDS staff PIN gate (DECISION D-006): after the device is PAIRED, a
/// personal staff PIN session is required before the kitchen board.
///
/// Watches [kdsSyncSessionProvider]: with a session it renders [child] (the app
/// root then mounts the LIVE board off the same session); without one it shows
/// the shared, MONEY-FREE [PinLoginScreen] (SECURITY T-003 — nothing on this
/// surface ever renders money). Fail-closed: no session means no board, and
/// there is no fake or bypass path. RF-118: the session-expiry LIFECYCLE lives in
/// [KdsSessionLifecycleObserver] at the app root (the gate is torn down when the
/// live board mounts); this gate just SHOWS the expiry notice via
/// [kdsExpiredNoticeProvider] when it re-appears.
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
      // Sprint (I): the language switcher is reachable on the PIN screen too.
      appBarActions: const [LanguageSelector()],
      // RF-118: the same visible client cooldown as the POS, scoped per
      // (device, employee) to mirror the server lockout (money-free surface).
      attemptLimiter: ref.watch(pinAttemptLimiterProvider),
      attemptScope: (member) => '$deviceId:${member.employeeProfileId}',
      // RF-118: shown after an inactivity/max-age expiry signed the operator out
      // (raised by KdsSessionLifecycleObserver at the app root).
      expiredNotice: ref.watch(kdsExpiredNoticeProvider),
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
