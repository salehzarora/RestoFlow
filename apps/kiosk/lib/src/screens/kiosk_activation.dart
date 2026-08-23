import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show pairingCodeFromUrl;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kiosk_fixtures.dart';
import '../design/kiosk_theme.dart';
import '../state/kiosk_live_runtime.dart';
import '../widgets/kiosk_chrome.dart';

/// KIOSK-001 Phase 3 — the STAFF/deployment device gate around the customer
/// shell (real mode only; demo mode never mounts this).
///
/// Launch order (§owner spec): restore the stored device session through the
/// canonical `restore_device_session` path with `expectedDeviceType: 'kiosk'`
/// — Restored enters the customer attract flow; Rejected (missing/revoked/
/// expired/wrong-type; the repository has already CLEARED the local
/// credential) lands on the branded activation screen; Offline shows the
/// V2 reconnect state with retry (ONLINE-REQUIRED: a kiosk never enters the
/// customer flow on stale evidence, and no device is ever created here —
/// provisioning stays a manager duty in the Dashboard).
///
/// Mid-session, any live read that proves the session dead raises
/// [KioskLiveState.sessionInvalid]; the gate re-validates and falls back to
/// activation the same way.
class KioskPairingGate extends ConsumerStatefulWidget {
  const KioskPairingGate({
    super.key,
    required this.outcomes,
    required this.pairing,
    required this.shellBuilder,
    this.onActivated,
  });

  /// The shared session manager (restore + clear-on-reject) and pairing
  /// repository (redeem) — one object in production.
  final DeviceSessionOutcomeManager outcomes;
  final DevicePairingRepository pairing;
  final WidgetBuilder shellBuilder;

  /// Fires once whenever a live kiosk session is (re)established.
  final void Function(DeviceContext context)? onActivated;

  static const String expectedDeviceType = 'kiosk';

  @override
  ConsumerState<KioskPairingGate> createState() => _KioskPairingGateState();
}

enum _GatePhase { restoring, needsActivation, offline, active }

class _KioskPairingGateState extends ConsumerState<KioskPairingGate> {
  _GatePhase _phase = _GatePhase.restoring;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    setState(() => _phase = _GatePhase.restoring);
    final outcome = await widget.outcomes.restoreOutcome(
      expectedDeviceType: KioskPairingGate.expectedDeviceType,
    );
    if (!mounted) return;
    switch (outcome) {
      case DeviceSessionRestored(:final context):
        widget.onActivated?.call(context);
        setState(() => _phase = _GatePhase.active);
      case DeviceSessionRestoreRejected():
        setState(() => _phase = _GatePhase.needsActivation);
      case DeviceSessionRestoreOffline():
        // ONLINE-REQUIRED: no cached entry into the customer flow.
        setState(() => _phase = _GatePhase.offline);
    }
  }

  void _onPaired(DeviceContext context) {
    widget.onActivated?.call(context);
    setState(() => _phase = _GatePhase.active);
  }

  @override
  Widget build(BuildContext context) {
    // A live read proved the session dead → re-validate (the repository
    // clears rejected credentials, landing back on activation).
    ref.listen(kioskLiveProvider.select((s) => s.sessionInvalid), (
      prev,
      invalid,
    ) {
      if (invalid && _phase == _GatePhase.active) {
        ref.read(kioskLiveProvider.notifier).acknowledgeSessionInvalid();
        _restore();
      }
    });

    return switch (_phase) {
      _GatePhase.active => widget.shellBuilder(context),
      _GatePhase.restoring => const _KioskGateScaffold(
        child: _KioskGateSpinner(),
      ),
      _GatePhase.offline => _KioskGateScaffold(
        child: _KioskReconnectPanel(onRetry: _restore),
      ),
      _GatePhase.needsActivation => KioskActivationScreen(
        pairing: widget.pairing,
        onPaired: _onPaired,
        // KIOSK-001-DEVICE-088: the Dashboard link/QR opens
        // `/kiosk?pair=CODE` — PREFILL only (shared LIVE-DEVICE-001 seam);
        // the operator still confirms activation, never an auto-redeem.
        initialCode: pairingCodeFromUrl(),
      ),
    };
  }
}

/// The staff-only first-run activation screen: branded dark V2 styling, the
/// enrollment code entry, and the typed error states. The device type is
/// HARDCODED to `kiosk` — this surface can never claim a POS/KDS identity —
/// and the code is redeemed through the shared repository, which persists
/// only `{device_id, session token}` into the platform secret store and
/// never logs or re-shows either.
class KioskActivationScreen extends StatefulWidget {
  const KioskActivationScreen({
    super.key,
    required this.pairing,
    required this.onPaired,
    this.initialCode,
  });

  final DevicePairingRepository pairing;
  final void Function(DeviceContext context) onPaired;

  /// Optional enrollment-code PREFILL (from the `?pair=` URL the Dashboard
  /// generates). Editable, never auto-submitted, never logged.
  final String? initialCode;

  @override
  State<KioskActivationScreen> createState() => _KioskActivationScreenState();
}

class _KioskActivationScreenState extends State<KioskActivationScreen> {
  late final TextEditingController _code = TextEditingController(
    text: widget.initialCode ?? '',
  );
  bool _busy = false;
  PairingFailureKind? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.pairing.pairWithCode(
      code: code,
      deviceType: KioskPairingGate.expectedDeviceType,
    );
    if (!mounted) return;
    switch (result) {
      case Success<DeviceContext, PairingFailure>(:final value):
        widget.onPaired(value); // keep _busy: the parent swaps the tree.
      case Failure<DeviceContext, PairingFailure>(:final failure):
        setState(() {
          _busy = false;
          _error = failure.kind;
        });
    }
  }

  String _errorText(AppLocalizations l10n, PairingFailureKind kind) =>
      switch (kind) {
        PairingFailureKind.invalidCode ||
        PairingFailureKind.denied => l10n.kioskActivationErrorInvalid,
        PairingFailureKind.expired => l10n.kioskActivationErrorExpired,
        PairingFailureKind.wrongScope => l10n.kioskActivationErrorWrongType,
        PairingFailureKind.lockedOut => l10n.kioskActivationErrorLocked,
        PairingFailureKind.network => l10n.kioskActivationErrorNetwork,
        PairingFailureKind.unknown => l10n.kioskActivationErrorUnknown,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _KioskGateScaffold(
      child: KioskGlass(
        radius: 40,
        padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const KioskBrandBadge(),
            const SizedBox(height: 44),
            Text(
              l10n.kioskActivationTitle,
              textAlign: TextAlign.center,
              style: KioskType.body(40, FontWeight.w900),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.kioskActivationSubtitle,
              textAlign: TextAlign.center,
              style: KioskType.body(
                24,
                FontWeight.w500,
                color: KioskColors.textMuted,
              ),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: 520,
              child: TextField(
                key: const Key('kiosk-activation-code'),
                controller: _code,
                enabled: !_busy,
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                enableSuggestions: false,
                style: KioskType.body(38, FontWeight.w800, letterSpacing: 6),
                decoration: InputDecoration(
                  hintText: l10n.kioskActivationCodeLabel,
                  hintStyle: KioskType.body(
                    26,
                    FontWeight.w600,
                    color: KioskColors.textDisabled,
                  ),
                  filled: true,
                  fillColor: KioskColors.glass(.06),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 26,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: KioskColors.glass(.16),
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: KioskColors.ring, width: 2),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 24),
              Text(
                _errorText(l10n, _error!),
                key: const Key('kiosk-activation-error'),
                textAlign: TextAlign.center,
                style: KioskType.body(
                  23,
                  FontWeight.w700,
                  color: KioskColors.dangerSoft,
                ),
              ),
            ],
            const SizedBox(height: 40),
            KioskAccentPill(
              key: const Key('kiosk-activation-submit'),
              onTap: _submit,
              enabled: !_busy,
              child: _busy
                  ? const SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      l10n.kioskActivationSubmit.toUpperCase(),
                      style: KioskType.body(
                        28,
                        FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: .5,
                      ),
                    ),
            ),
            const SizedBox(height: 34),
            Text(
              KioskBrand.deviceLabel,
              style: KioskType.body(
                19,
                FontWeight.w600,
                color: KioskColors.textDisabled,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared dark scaffold for every gate surface (staff-facing, V2 palette).
class _KioskGateScaffold extends StatelessWidget {
  const _KioskGateScaffold({required this.child});
  final Widget child;

  @override
  // Material(transparency) so the TextField works without a Scaffold —
  // the same rule KioskStage applies for the customer shell. Scrollable so
  // the staff surface stays usable at ANY viewport, never clipped.
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: ColoredBox(
      color: KioskColors.canvasBottom,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(60),
          child: child,
        ),
      ),
    ),
  );
}

class _KioskGateSpinner extends StatelessWidget {
  const _KioskGateSpinner();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const KioskBrandBadge(),
        const SizedBox(height: 46),
        SizedBox(
          width: 64,
          height: 64,
          child: CircularProgressIndicator(
            strokeWidth: 5,
            color: KioskColors.accentTop,
          ),
        ),
        const SizedBox(height: 30),
        Text(
          l10n.kioskBootRestoring,
          style: KioskType.body(
            26,
            FontWeight.w600,
            color: KioskColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _KioskReconnectPanel extends StatelessWidget {
  const _KioskReconnectPanel({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KioskGlass(
      radius: 40,
      padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 72),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            size: 92,
            color: KioskColors.textMuted,
          ),
          const SizedBox(height: 34),
          Text(
            l10n.kioskReconnectTitle,
            textAlign: TextAlign.center,
            style: KioskType.body(36, FontWeight.w800),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.kioskReconnectBody,
            textAlign: TextAlign.center,
            style: KioskType.body(
              24,
              FontWeight.w500,
              color: KioskColors.textMuted,
            ),
          ),
          const SizedBox(height: 38),
          KioskAccentPill(
            key: const Key('kiosk-reconnect-retry'),
            onTap: onRetry,
            child: Text(
              l10n.kioskRetry.toUpperCase(),
              style: KioskType.body(
                28,
                FontWeight.w900,
                color: Colors.white,
                letterSpacing: .5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
