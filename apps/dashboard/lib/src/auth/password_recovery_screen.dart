/// AUTH-FLOW-256 — the screen a password-reset link is supposed to reach.
///
/// Its absence was the whole of the reported incident: the operator received a
/// "Reset your password" email, clicked it, and the Dashboard had nothing to
/// show them. Worse, the link DOES establish a session, so without this screen
/// the app treated "clicked the reset link" as "signed in" and dropped them
/// somewhere else entirely — with the password they came to change still in
/// place, and no way to change it.
///
/// The screen therefore owns one job and refuses to be skipped: while the
/// provider says this session is a recovery session, the only ways out are
/// setting a new password or explicitly abandoning it (which signs the recovery
/// session out rather than leaving it usable).
library;

import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../widgets/language_selector.dart';
import 'dashboard_auth_repository.dart';

/// The shortest password this screen will submit.
///
/// The SERVER's policy is authoritative — a rejection still comes back as
/// [AuthErrorKind.weakPassword] and is shown honestly. This floor exists so the
/// obvious case is caught without a round trip, and it is deliberately higher
/// than the project's documented minimum of 6.
const int kMinimumNewPasswordLength = 8;

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({
    required this.authRepository,
    this.onCompleted,
    super.key,
  });

  final DashboardAuthRepository authRepository;

  /// Called once the password has actually been replaced. The parent then lets
  /// the ordinary context gate take over (member → dashboard, no membership →
  /// onboarding).
  final VoidCallback? onCompleted;

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _busy = false;
  bool _done = false;
  AuthErrorKind? _errorKind;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _errorKind = null;
    });

    final outcome = await widget.authRepository.completePasswordRecovery(
      newPassword: _password.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    switch (outcome) {
      case AuthPasswordUpdated():
        setState(() => _done = true);
        widget.onCompleted?.call();
      case AuthError(:final kind):
        setState(() => _errorKind = kind);
      case AuthSignedIn():
      case AuthConfirmationRequired():
      case AuthPasswordResetRequested():
        // None of these are reachable from an update call; treat anything
        // unexpected as a failure rather than silently claiming success.
        setState(() => _errorKind = AuthErrorKind.unknown);
    }
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    await widget.authRepository.cancelPasswordRecovery();
    if (mounted) setState(() => _busy = false);
  }

  String _message(AppLocalizations l10n, AuthErrorKind kind) => switch (kind) {
    AuthErrorKind.weakPassword => l10n.authWeakPassword,
    AuthErrorKind.samePassword => l10n.authSamePassword,
    AuthErrorKind.linkExpired => l10n.authLinkExpiredBody,
    AuthErrorKind.rateLimited => l10n.authRateLimited,
    AuthErrorKind.serviceUnavailable => l10n.authServiceUnavailable,
    AuthErrorKind.accountUnavailable => l10n.authAccountUnavailable,
    AuthErrorKind.emailNotConfirmed => l10n.authEmailNotConfirmed,
    AuthErrorKind.network => l10n.authNetworkError,
    AuthErrorKind.invalidCredentials || AuthErrorKind.unknown => l10n.authError,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // An expired/consumed link cannot be retried here — a new one must be
    // requested — so it gets its own terminal state instead of an error banner
    // above a form that can no longer succeed.
    final expired = _errorKind == AuthErrorKind.linkExpired;

    return Scaffold(
      appBar: AppBar(actions: const [LanguageSelector()]),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(RestoflowSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: RestoflowPanelWidths.dialog,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RestoflowBrandMark(
                    title: l10n.dashboardAppTitle,
                    tagline: l10n.authBrandTagline,
                  ),
                  const SizedBox(height: RestoflowSpacing.xl),
                  if (expired)
                    _expiredCard(l10n)
                  else if (_done)
                    _doneCard(l10n)
                  else
                    _formCard(l10n),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formCard(AppLocalizations l10n) => RestoflowSectionCard(
    key: const Key('recovery-form-card'),
    title: l10n.authNewPasswordTitle,
    children: [
      Text(
        l10n.authNewPasswordBody,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: RestoflowSpacing.lg),
      Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const Key('recovery-password'),
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.authNewPasswordLabel,
                prefixIcon: const Icon(Icons.lock_outline),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return l10n.authPasswordRequired;
                if (v.length < kMinimumNewPasswordLength) {
                  return l10n.authWeakPassword;
                }
                return null;
              },
            ),
            const SizedBox(height: RestoflowSpacing.md),
            TextFormField(
              key: const Key('recovery-confirm'),
              controller: _confirm,
              enabled: !_busy,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.authConfirmPasswordLabel,
                prefixIcon: const Icon(Icons.lock_reset_outlined),
              ),
              validator: (v) =>
                  v == _password.text ? null : l10n.authPasswordsDoNotMatch,
            ),
          ],
        ),
      ),
      if (_errorKind != null) ...[
        const SizedBox(height: RestoflowSpacing.md),
        RestoflowNoticeBanner(
          key: const Key('recovery-error'),
          tone: RestoflowTone.danger,
          body: _message(l10n, _errorKind!),
        ),
      ],
      const SizedBox(height: RestoflowSpacing.lg),
      FilledButton(
        key: const Key('recovery-submit'),
        onPressed: _busy ? null : _submit,
        child: _busy
            ? const RestoflowInlineSpinner(size: 20)
            : Text(l10n.authUpdatePasswordAction),
      ),
      TextButton(
        key: const Key('recovery-cancel'),
        onPressed: _busy ? null : _cancel,
        child: Text(l10n.authBackToSignIn),
      ),
    ],
  );

  Widget _doneCard(AppLocalizations l10n) => RestoflowSectionCard(
    key: const Key('recovery-done-card'),
    title: l10n.authNewPasswordTitle,
    children: [
      RestoflowNoticeBanner(
        key: const Key('recovery-success'),
        tone: RestoflowTone.success,
        body: l10n.authPasswordUpdated,
      ),
      // Deliberately NOT a spinner. The provider's recovery signal has already
      // flipped, so the flow re-routes on its own; a spinner here would keep
      // turning forever if that transition ever stalled, telling the operator
      // to wait for something that is not coming.
    ],
  );

  Widget _expiredCard(AppLocalizations l10n) => RestoflowSectionCard(
    key: const Key('recovery-expired-card'),
    title: l10n.authLinkExpiredTitle,
    children: [
      RestoflowNoticeBanner(
        tone: RestoflowTone.warning,
        body: l10n.authLinkExpiredBody,
      ),
      const SizedBox(height: RestoflowSpacing.lg),
      FilledButton(
        key: const Key('recovery-request-new'),
        // Abandoning drops the recovery session, so the sign-in screen it
        // returns to is a genuinely signed-out one.
        onPressed: _busy ? null : _cancel,
        child: Text(l10n.authRequestNewLink),
      ),
    ],
  );
}
