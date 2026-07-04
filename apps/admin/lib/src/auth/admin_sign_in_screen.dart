import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../widgets/language_selector.dart';
import 'admin_auth.dart';

/// RF-119-b — the platform-operator sign-in screen (email + password ONLY: no
/// sign-up and no onboarding — platform-admin access is provisioned manually,
/// D-026). It ONLY ever calls the injected [AdminAuthService]; it never fakes a
/// sign-in, never grants platform-admin, and never surfaces a raw provider error
/// (only a safe, localized message). A successful sign-in flips the auth session
/// stream the parent [AdminAuthFlow] watches, which then resolves the context.
///
/// It clearly states this is the PLATFORM panel, not the restaurant Dashboard.
class AdminSignInScreen extends StatefulWidget {
  const AdminSignInScreen({required this.authService, super.key});

  final AdminAuthService authService;

  @override
  State<AdminSignInScreen> createState() => _AdminSignInScreenState();
}

class _AdminSignInScreenState extends State<AdminSignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  AdminSignInError? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.authService.signInWithPassword(
      email: _email.text,
      password: _password.text,
    );
    if (!mounted) return;
    // On success the parent's session stream swaps this screen out; on failure we
    // stay and show a safe message.
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  String? _errorText(AppLocalizations l10n) => switch (_error) {
    null => null,
    AdminSignInError.invalidCredentials => l10n.adminSignInInvalid,
    AdminSignInError.network => l10n.authNetworkError,
    AdminSignInError.unknown => l10n.authError,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminAppTitle),
        actions: const [LanguageSelector()],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: RestoflowPanelWidths.formPanel,
            ),
            child: Form(
              key: _formKey,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(RestoflowSpacing.xl),
                children: [
                  Center(child: RestoflowBrandMark(title: l10n.adminAppTitle)),
                  const SizedBox(height: RestoflowSpacing.lg),
                  Text(
                    l10n.adminSignInTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: RestoflowSpacing.xs),
                  // This is the PLATFORM panel, not the restaurant Dashboard.
                  Text(
                    l10n.adminGateNotOwner,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: RestoflowSpacing.xl),
                  TextFormField(
                    key: const Key('admin-signin-email'),
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    decoration: InputDecoration(
                      labelText: l10n.authEmailLabel,
                      prefixIcon: const Icon(Icons.mail_outline),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l10n.authEmailLabel
                        : null,
                  ),
                  const SizedBox(height: RestoflowSpacing.md),
                  TextFormField(
                    key: const Key('admin-signin-password'),
                    controller: _password,
                    enabled: !_busy,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: l10n.authPasswordLabel,
                      prefixIcon: const Icon(Icons.lock_outline),
                      errorText: _errorText(l10n),
                    ),
                    validator: (v) => (v == null || v.isEmpty)
                        ? l10n.authPasswordLabel
                        : null,
                  ),
                  const SizedBox(height: RestoflowSpacing.lg),
                  FilledButton(
                    key: const Key('admin-signin-submit'),
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: _busy
                        ? const RestoflowInlineSpinner()
                        : Text(l10n.authSignInAction),
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
