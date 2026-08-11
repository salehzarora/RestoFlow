import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'dashboard_auth_repository.dart';
import '../widgets/language_selector.dart';

/// The dashboard real-auth entry (RF-151): a Sign in / Create account form with
/// basic validation and safe, localized loading / error / email-confirmation
/// states.
///
/// It ONLY ever calls the injected [authRepository] — it never fakes a successful
/// sign-in/sign-up and never surfaces a raw provider error (only the safe
/// [AuthErrorKind] mapped to a localized string). A successful sign-in transitions
/// via the auth session stream the parent flow watches; a successful sign-up WITH
/// a session reports the entered restaurant/branch via [onSignedUpWithSession] so
/// the flow can carry them into onboarding.
class LoginSignupScreen extends StatefulWidget {
  const LoginSignupScreen({
    required this.authRepository,
    required this.onSignedUpWithSession,
    super.key,
  });

  final DashboardAuthRepository authRepository;
  final void Function(String restaurantName, String? branchName)
  onSignedUpWithSession;

  @override
  State<LoginSignupScreen> createState() => _LoginSignupScreenState();
}

enum _AuthMode { signIn, signUp }

class _LoginSignupScreenState extends State<LoginSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _restaurant = TextEditingController();
  final _branch = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  bool _busy = false;
  AuthErrorKind? _errorKind;
  bool _confirmationSent = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _restaurant.dispose();
    _branch.dispose();
    super.dispose();
  }

  void _setMode(_AuthMode mode) {
    if (mode == _mode || _busy) return;
    setState(() {
      _mode = mode;
      _errorKind = null;
      _confirmationSent = false;
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
    final outcome = isSignUp
        ? await widget.authRepository.signUp(email: email, password: password)
        : await widget.authRepository.signIn(email: email, password: password);
    if (!mounted) return;
    setState(() => _busy = false);

    switch (outcome) {
      case AuthSignedIn():
        if (isSignUp) {
          final branch = _branch.text.trim();
          widget.onSignedUpWithSession(
            _restaurant.text.trim(),
            branch.isEmpty ? null : branch,
          );
        }
      // Sign-in: the parent flow's session stream drives the transition.
      case AuthConfirmationRequired():
        setState(() => _confirmationSent = true);
      case AuthError(:final kind):
        setState(() => _errorKind = kind);
    }
  }

  String _errorMessage(AppLocalizations l10n, AuthErrorKind kind) {
    final isSignUp = _mode == _AuthMode.signUp;
    return switch (kind) {
      AuthErrorKind.invalidCredentials =>
        isSignUp ? l10n.authSignUpFailed : l10n.authInvalidCredentials,
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
                    title: l10n.authWelcomeTitle,
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
                            if (isSignUp) ...[
                              const SizedBox(height: RestoflowSpacing.md),
                              TextFormField(
                                key: const Key('auth-restaurant'),
                                controller: _restaurant,
                                enabled: !_busy,
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(
                                  labelText: l10n.onboardingRestaurantNameLabel,
                                  prefixIcon: const Icon(
                                    Icons.storefront_outlined,
                                  ),
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? l10n.onboardingRestaurantNameRequired
                                    : null,
                              ),
                              const SizedBox(height: RestoflowSpacing.md),
                              TextFormField(
                                key: const Key('auth-branch'),
                                controller: _branch,
                                enabled: !_busy,
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(
                                  labelText: l10n.onboardingBranchNameLabel,
                                  prefixIcon: const Icon(
                                    Icons.store_mall_directory_outlined,
                                  ),
                                ),
                              ),
                            ],
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
                          tone: RestoflowTone.info,
                          body: l10n.authEmailConfirmationSent,
                        ),
                      ],
                      const SizedBox(height: RestoflowSpacing.lg),
                      FilledButton(
                        key: const Key('auth-submit'),
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const RestoflowInlineSpinner(size: 20)
                            : Text(
                                isSignUp
                                    ? l10n.authCreateAccountTab
                                    : l10n.authSignInAction,
                              ),
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
