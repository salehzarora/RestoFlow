import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../widgets/language_selector.dart';
import 'admin_auth.dart';
import 'admin_console_identity.dart';

/// RF-119-b — the platform-operator MFA screen, shown ONLY to an account that
/// holds an active platform-admin grant but whose session is not yet aal2
/// (server-derived; the gate never enters here on its own). It self-resolves the
/// factor state via [AdminAuthService.assurance]:
///  - a verified TOTP factor exists  -> CHALLENGE (enter the 6-digit code);
///  - none                            -> ENROL a new TOTP factor (show the setup
///    key + otpauth URI ONCE — never stored) then verify the 6-digit code.
///
/// On a successful verify the client holds an aal2 session; [onVerified] tells
/// the parent flow to RE-FETCH `get_my_context`, so entry is gated on the
/// SERVER-derived assurance, never this screen's own state. Wrong codes show a
/// safe generic error and NO platform data is ever shown here. Sign out is
/// always available. This is the PLATFORM panel, not the restaurant Dashboard.
class AdminMfaScreen extends StatefulWidget {
  const AdminMfaScreen({
    required this.authService,
    required this.onVerified,
    required this.onSignOut,
    super.key,
  });

  final AdminAuthService authService;
  final VoidCallback onVerified;
  final VoidCallback onSignOut;

  @override
  State<AdminMfaScreen> createState() => _AdminMfaScreenState();
}

enum _MfaMode { enroll, challenge }

class _AdminMfaScreenState extends State<AdminMfaScreen> {
  bool _loading = true;
  bool _initError = false;
  _MfaMode? _mode;
  AdminTotpEnrollment? _enrollment;
  String? _factorId;

  final _code = TextEditingController();
  bool _verifying = false;
  AdminMfaVerifyError? _verifyError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _initError = false;
    });
    try {
      final assurance = await widget.authService.assurance();
      if (!mounted) return;
      if (assurance.isAal2) {
        // Defensive: already aal2 (e.g. a race) — let the parent re-check. Clear
        // the loading flag first so a reused State is not stuck spinning.
        if (mounted) setState(() => _loading = false);
        widget.onVerified();
        return;
      }
      if (assurance.hasVerifiedFactor && assurance.verifiedFactorId != null) {
        setState(() {
          _mode = _MfaMode.challenge;
          _factorId = assurance.verifiedFactorId;
          _loading = false;
        });
        return;
      }
      // No verified factor: begin a fresh TOTP enrolment.
      final enrollment = await widget.authService.enrollTotp();
      if (!mounted) return;
      setState(() {
        _mode = _MfaMode.enroll;
        _enrollment = enrollment;
        _factorId = enrollment.factorId;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _initError = true;
      });
    }
  }

  Future<void> _verify() async {
    final factorId = _factorId;
    if (_verifying || factorId == null) return;
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      setState(() => _verifyError = AdminMfaVerifyError.invalidCode);
      return;
    }
    setState(() {
      _verifying = true;
      _verifyError = null;
    });
    final error = await widget.authService.verifyTotp(
      factorId: factorId,
      code: _code.text,
    );
    if (!mounted) return;
    if (error == null) {
      // Session upgraded to aal2 — the parent re-fetches get_my_context and
      // swaps this screen out once the SERVER confirms the assurance. Re-enable
      // the form first: if that re-fetch still returns non-aal2 (assurance-claim
      // propagation lag) and this State is reused, the operator can retry inline.
      if (mounted) setState(() => _verifying = false);
      widget.onVerified();
      return;
    }
    setState(() {
      _verifying = false;
      _verifyError = error;
    });
  }

  String? _verifyErrorText(AppLocalizations l10n) => switch (_verifyError) {
    null => null,
    AdminMfaVerifyError.invalidCode => l10n.adminMfaVerifyFailed,
    AdminMfaVerifyError.network => l10n.authNetworkError,
    AdminMfaVerifyError.unknown => l10n.authError,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminAppTitle),
        actions: [
          const LanguageSelector(),
          TextButton.icon(
            key: const Key('admin-mfa-signout'),
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout, size: RestoflowIconSizes.sm),
            label: Text(l10n.authSignOut),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: RestoflowPanelWidths.helpPanel,
            ),
            child: _loading
                ? const RestoflowStateView(showSpinner: true)
                : _initError
                ? _errorState(context, l10n)
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(RestoflowSpacing.xl),
                    children: [
                      // DESIGN-002: a "secure console" identity + the signed-in
                      // account, so the operator can trust the surface and
                      // confirm which account is being MFA-verified. currentEmail
                      // is NON-secret (see AdminAuthService).
                      AdminConsoleIdentity(
                        email: widget.authService.currentEmail,
                      ),
                      const SizedBox(height: RestoflowSpacing.lg),
                      RestoflowNoticeBanner(
                        tone: RestoflowTone.warning,
                        icon: Icons.security_outlined,
                        title: l10n.adminMfaRequiredTitle,
                        // DESIGN-002: the CORRECT MFA body (was adminGateNotOwner,
                        // which described the panel, not why MFA is required).
                        body: l10n.adminMfaRequiredBody,
                      ),
                      const SizedBox(height: RestoflowSpacing.lg),
                      if (_mode == _MfaMode.enroll)
                        ..._enrollSection(context, l10n, theme)
                      else
                        ..._challengeSection(context, l10n, theme),
                      const SizedBox(height: RestoflowSpacing.lg),
                      TextField(
                        key: const Key('admin-mfa-code'),
                        controller: _code,
                        enabled: !_verifying,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall,
                        onSubmitted: (_) => _verify(),
                        decoration: InputDecoration(
                          labelText: l10n.adminMfaCodeLabel,
                          counterText: '',
                          errorText: _verifyErrorText(l10n),
                        ),
                      ),
                      const SizedBox(height: RestoflowSpacing.md),
                      FilledButton(
                        key: const Key('admin-mfa-verify'),
                        onPressed: _verifying ? null : _verify,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: _verifying
                            ? const RestoflowInlineSpinner()
                            : Text(l10n.adminMfaVerifyAction),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  List<Widget> _enrollSection(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    final enrollment = _enrollment!;
    return [
      Text(l10n.adminMfaEnrollTitle, style: theme.textTheme.titleMedium),
      const SizedBox(height: RestoflowSpacing.sm),
      Text(
        l10n.adminMfaEnrollBody,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: RestoflowSpacing.md),
      // DESIGN-002: render the one-time otpauth:// URI as a scannable QR
      // *locally* (qr_flutter = pure-Dart `qr` encoder + CustomPaint). No
      // network, no external QR API — the URI is only painted in memory during
      // enrolment and is never stored or logged. A light card keeps the QR
      // scannable regardless of theme.
      Center(
        child: Container(
          padding: const EdgeInsets.all(RestoflowSpacing.md),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(RestoflowRadii.md),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: QrImageView(
            key: const Key('admin-mfa-qr'),
            data: enrollment.uri,
            version: QrVersions.auto,
            size: 180,
            backgroundColor: Colors.white,
            semanticsLabel: l10n.adminMfaScanInstruction,
          ),
        ),
      ),
      const SizedBox(height: RestoflowSpacing.sm),
      Text(
        l10n.adminMfaScanInstruction,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: RestoflowSpacing.md),
      RestoflowSectionCard(
        title: l10n.adminMfaSetupKey,
        children: [
          const SizedBox(height: RestoflowSpacing.sm),
          // The manual-entry fallback: the setup key (short) + the otpauth URI
          // (long), shown ONCE for enrolment and never persisted or logged.
          // Both are FORCED LTR so the machine strings keep their order under
          // ar/he (the code block already forces LTR; the URI's SelectableText
          // now does too — DESIGN-002 fixes an RTL misrendering of the URI).
          RestoflowCodeBlock(lines: [enrollment.secret]),
          const SizedBox(height: RestoflowSpacing.sm),
          SelectableText(
            enrollment.uri,
            textDirection: TextDirection.ltr,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _challengeSection(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    return [
      Text(l10n.adminMfaChallengeTitle, style: theme.textTheme.titleMedium),
      const SizedBox(height: RestoflowSpacing.sm),
      Text(
        l10n.adminMfaChallengeBody,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  Widget _errorState(BuildContext context, AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.all(RestoflowSpacing.xl),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RestoflowNoticeBanner(
          tone: RestoflowTone.danger,
          icon: Icons.error_outline,
          body: l10n.adminMfaEnrollError,
        ),
        const SizedBox(height: RestoflowSpacing.lg),
        FilledButton.tonalIcon(
          key: const Key('admin-mfa-retry'),
          onPressed: _init,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.authTryAgain),
        ),
      ],
    ),
  );
}
