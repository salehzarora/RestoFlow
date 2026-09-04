import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'dashboard_auth_repository.dart';
import '../widgets/language_selector.dart';

/// The dashboard real-auth entry (RF-151): Sign in / Create account, plus the
/// AUTH-256 password-reset request, with safe localized loading / error /
/// email-confirmation states.
///
/// It ONLY ever calls the injected [authRepository] — it never fakes a
/// successful sign-in/sign-up and never surfaces a raw provider error (only the
/// safe [AuthErrorKind] mapped to a localized string). A successful sign-in
/// transitions via the auth session stream the parent flow watches.
///
/// AUTH-256 removed the restaurant/branch fields from SIGN-UP. They were
/// collected before the confirmation email was even sent, and then discarded:
/// the values only ever reached onboarding when the project auto-confirmed and a
/// session existed immediately. On a project that requires confirmation —
/// which production does — the operator typed their restaurant name, went to
/// their inbox, came back through a fresh page load, and it was gone. Onboarding
/// asks for them after confirmation, where the answer can actually be used, and
/// nothing about a half-finished sign-up has to be persisted anywhere.
class LoginSignupScreen extends StatefulWidget {
  const LoginSignupScreen({required this.authRepository, super.key});

  final DashboardAuthRepository authRepository;

  @override
  State<LoginSignupScreen> createState() => _LoginSignupScreenState();
}

enum _AuthMode { signIn, signUp }

class _LoginSignupScreenState extends State<LoginSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;

  /// AUTH-256: the "forgot password" sub-mode. Deliberately NOT a third
  /// [_AuthMode] value so the two-segment control stays a two-segment control
  /// (its width/clip behaviour under Arabic is load-bearing — see build()).
  bool _resetMode = false;
  bool _busy = false;
  AuthErrorKind? _errorKind;
  bool _confirmationSent = false;
  bool _resetSent = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _clearStatus() {
    _errorKind = null;
    _confirmationSent = false;
    _resetSent = false;
  }

  void _setMode(_AuthMode mode) {
    if ((mode == _mode && !_resetMode) || _busy) return;
    setState(() {
      _mode = mode;
      _resetMode = false;
      _clearStatus();
    });
  }

  void _setResetMode(bool on) {
    if (_busy) return;
    setState(() {
      _resetMode = on;
      _clearStatus();
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _errorKind = null;
      _confirmationSent = false;
    });

    final email = _email.text.trim();
    final password = _password.text;
    final isSignUp = _mode == _AuthMode.signUp;
    final outcome = _resetMode
        ? await widget.authRepository.requestPasswordReset(email: email)
        : isSignUp
        ? await widget.authRepository.signUp(email: email, password: password)
        : await widget.authRepository.signIn(email: email, password: password);
    if (!mounted) return;
    setState(() => _busy = false);

    switch (outcome) {
      case AuthSignedIn():
        // The parent flow's session stream drives the transition. A fresh
        // sign-up with no tenant yet lands in onboarding, which is where the
        // restaurant and branch are now asked for.
        break;
      case AuthConfirmationRequired():
        setState(() => _confirmationSent = true);
      case AuthPasswordResetRequested():
        setState(() => _resetSent = true);
      case AuthPasswordUpdated():
        // Unreachable here: recovery completes on its own screen.
        break;
      case AuthError(:final kind):
        setState(() => _errorKind = kind);
    }
  }

  String _errorMessage(AppLocalizations l10n, AuthErrorKind kind) {
    final isSignUp = _mode == _AuthMode.signUp && !_resetMode;
    return switch (kind) {
      AuthErrorKind.invalidCredentials =>
        isSignUp ? l10n.authSignUpFailed : l10n.authInvalidCredentials,
      // AUTH-256: every one of these used to render as "Incorrect email or
      // password", which is the one explanation guaranteed to waste the
      // operator's time when the password was never the problem.
      AuthErrorKind.emailNotConfirmed => l10n.authEmailNotConfirmed,
      AuthErrorKind.accountUnavailable => l10n.authAccountUnavailable,
      AuthErrorKind.rateLimited => l10n.authRateLimited,
      AuthErrorKind.serviceUnavailable => l10n.authServiceUnavailable,
      AuthErrorKind.weakPassword => l10n.authWeakPassword,
      AuthErrorKind.samePassword => l10n.authSamePassword,
      AuthErrorKind.linkExpired => l10n.authLinkExpiredBody,
      AuthErrorKind.network => l10n.authNetworkError,
      AuthErrorKind.unknown =>
        isSignUp ? l10n.authSignUpFailed : l10n.authError,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isSignUp = _mode == _AuthMode.signUp;
    return Scaffold(
      // Sprint (I): the language switcher is reachable BEFORE sign-in too.
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
                  // Brand hero: the product identity above the form card.
                  RestoflowBrandMark(
                    title: l10n.dashboardAppTitle,
                    tagline: l10n.authBrandTagline,
                  ),
                  const SizedBox(height: RestoflowSpacing.xl),
                  RestoflowSectionCard(
                    title: _resetMode
                        ? l10n.authResetTitle
                        : l10n.authWelcomeTitle,
                    children: [
                      // THE SEGMENTS TAKE THE CARD'S WIDTH; THEY USED TO
                      // SHRINK TO THEIR OWN TEXT AND CLIP IT.
                      //
                      // SegmentedButton sizes every segment to the widest
                      // segment's MAX INTRINSIC width, then caps that at an
                      // equal share of whatever width it is given. Left to
                      // itself it is therefore shrink-to-content, so the card's
                      // spare width goes unused — and a segment only gets as
                      // much room as the intrinsic measurement claims it needs.
                      //
                      // For Arabic that measurement comes up short of the
                      // shaped line. Measured on a real-font web build, every
                      // segment was 125.7px wide while the card offered
                      // 220 / 199 / 179 at 1280 / 430 / 390. At 125.7 the
                      // shaped "تسجيل الدخول" plus its check icon no longer fit
                      // on one line, so the label wrapped to two — but the
                      // segment box had already been sized for one (32px), and
                      // the second line was clipped by the control's own
                      // bottom edge. That is a silent clip: nothing overflows,
                      // no RenderFlex error is reported, and the entry surface
                      // of the product renders a half-cut word.
                      //
                      // Stretching to the full width fixes the cause rather
                      // than the symptom: each segment gets the card's equal
                      // share, the label fits on one line in every locale, and
                      // there is nothing left to wrap or clip. English is
                      // unaffected in height (it already fit) and simply fills
                      // the card, which is also what the surrounding
                      // stretch-aligned form does.
                      if (_resetMode)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: RestoflowSpacing.sm,
                          ),
                          child: Text(
                            l10n.authResetBody,
                            key: const Key('auth-reset-body'),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<_AuthMode>(
                            segments: [
                              ButtonSegment(
                                value: _AuthMode.signIn,
                                label: Text(l10n.authSignInTab),
                                // Icons.login is NOT auto-mirrored; flip under RTL
                                // so the arrow points into the door.
                                icon: Transform.flip(
                                  flipX:
                                      Directionality.of(context) ==
                                      TextDirection.rtl,
                                  child: const Icon(Icons.login),
                                ),
                              ),
                              ButtonSegment(
                                value: _AuthMode.signUp,
                                label: Text(l10n.authCreateAccountTab),
                                icon: const Icon(Icons.person_add_alt),
                              ),
                            ],
                            selected: {_mode},
                            onSelectionChanged: _busy
                                ? null
                                : (selection) => _setMode(selection.first),
                          ),
                        ),
                      const SizedBox(height: RestoflowSpacing.lg),
                      Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              key: const Key('auth-email'),
                              controller: _email,
                              enabled: !_busy,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: InputDecoration(
                                labelText: l10n.authEmailLabel,
                                prefixIcon: const Icon(Icons.mail_outline),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? l10n.authEmailRequired
                                  : null,
                            ),
                            if (!_resetMode) ...[
                              const SizedBox(height: RestoflowSpacing.md),
                              TextFormField(
                                key: const Key('auth-password'),
                                controller: _password,
                                enabled: !_busy,
                                obscureText: true,
                                decoration: InputDecoration(
                                  labelText: l10n.authPasswordLabel,
                                  prefixIcon: const Icon(Icons.lock_outline),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return l10n.authPasswordRequired;
                                  }
                                  if (isSignUp && v.length < 6) {
                                    return l10n.authPasswordTooShort;
                                  }
                                  return null;
                                },
                              ),
                            ],
                            // AUTH-256: "Forgot password?" sits with the
                            // password field, where someone who has just failed
                            // to remember one is actually looking.
                            if (!_resetMode && !isSignUp)
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: TextButton(
                                  key: const Key('auth-forgot-password'),
                                  onPressed: _busy
                                      ? null
                                      : () => _setResetMode(true),
                                  child: Text(l10n.authForgotPassword),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_errorKind != null) ...[
                        const SizedBox(height: RestoflowSpacing.md),
                        RestoflowNoticeBanner(
                          tone: RestoflowTone.danger,
                          body: _errorMessage(l10n, _errorKind!),
                        ),
                      ],
                      if (_confirmationSent) ...[
                        const SizedBox(height: RestoflowSpacing.md),
                        RestoflowNoticeBanner(
                          key: const Key('auth-confirmation-sent'),
                          tone: RestoflowTone.info,
                          body: l10n.authEmailConfirmationSent,
                        ),
                      ],
                      if (_resetSent) ...[
                        const SizedBox(height: RestoflowSpacing.md),
                        RestoflowNoticeBanner(
                          key: const Key('auth-reset-sent'),
                          tone: RestoflowTone.info,
                          // Deliberately identical whether or not the address
                          // has an account — see AuthPasswordResetRequested.
                          body: l10n.authResetSent,
                        ),
                      ],
                      const SizedBox(height: RestoflowSpacing.lg),
                      FilledButton(
                        key: const Key('auth-submit'),
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const RestoflowInlineSpinner(size: 20)
                            : Text(
                                _resetMode
                                    ? l10n.authResetSend
                                    : isSignUp
                                    ? l10n.authCreateAccountTab
                                    : l10n.authSignInAction,
                              ),
                      ),
                      if (_resetMode)
                        TextButton(
                          key: const Key('auth-back-to-sign-in'),
                          onPressed: _busy ? null : () => _setResetMode(false),
                          child: Text(l10n.authBackToSignIn),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
