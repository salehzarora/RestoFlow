import 'package:flutter/material.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// The shared POS/KDS device pairing screen (RF-153): enter the enrollment code
/// created in the dashboard, pair via [repository], and hand the resulting
/// backend-verified [DeviceContext] to [onPaired].
///
/// Honest states only — it NEVER fabricates a paired device, and surfaces only
/// safe, localized errors (never a raw provider message, code, or session token).
/// Money-free, so it is safe on a KDS (kitchen) device. RTL is automatic via the
/// app `Directionality`.
class DevicePairingScreen extends StatefulWidget {
  const DevicePairingScreen({
    required this.repository,
    required this.deviceType,
    required this.onPaired,
    this.appBarActions = const <Widget>[],
    super.key,
  });

  final DevicePairingRepository repository;

  /// `pos` or `kds`.
  final String deviceType;

  /// Called with the backend-verified context on a successful pair.
  final void Function(DeviceContext context) onPaired;

  /// Host-provided app-bar actions (sprint I: the language switcher must be
  /// reachable on EVERY page, including pre-pairing).
  final List<Widget> appBarActions;

  @override
  State<DevicePairingScreen> createState() => _DevicePairingScreenState();
}

class _DevicePairingScreenState extends State<DevicePairingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  bool _busy = false;
  PairingFailureKind? _errorKind;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _errorKind = null;
    });
    final result = await widget.repository.pairWithCode(
      code: _code.text.trim(),
      deviceType: widget.deviceType,
    );
    if (!mounted) return;
    switch (result) {
      case Success<DeviceContext, PairingFailure>(:final value):
        widget.onPaired(value); // the parent transitions away; keep _busy true.
      case Failure<DeviceContext, PairingFailure>(:final failure):
        setState(() {
          _busy = false;
          _errorKind = failure.kind;
        });
    }
  }

  String _errorMessage(AppLocalizations l10n, PairingFailureKind kind) =>
      switch (kind) {
        PairingFailureKind.invalidCode ||
        PairingFailureKind.denied => l10n.pairingInvalidCode,
        PairingFailureKind.expired => l10n.pairingExpired,
        PairingFailureKind.wrongScope => l10n.pairingWrongScope,
        PairingFailureKind.network => l10n.authNetworkError,
        PairingFailureKind.unknown => l10n.pairingFailed,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: widget.appBarActions.isEmpty
          ? null
          : AppBar(actions: widget.appBarActions),
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
                  // Brand hero: this is the device's first impression of the
                  // product, so it should feel like real device setup.
                  RestoflowBrandMark(
                    title: l10n.appName,
                    tagline: l10n.authBrandTagline,
                  ),
                  const SizedBox(height: RestoflowSpacing.xl),
                  RestoflowSectionCard(
                    title: l10n.pairingTitle,
                    subtitle: l10n.pairingIntro,
                    children: [
                      const SizedBox(height: RestoflowSpacing.sm),
                      Form(
                        key: _formKey,
                        child: TextFormField(
                          key: const Key('pairing-code'),
                          controller: _code,
                          enabled: !_busy,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          textAlign: TextAlign.center,
                          // Bigger, code-like type. Deliberately NO
                          // letterSpacing (Arabic-safe) and NO case/character
                          // transformation of the entered value.
                          style: theme.textTheme.headlineSmall,
                          decoration: InputDecoration(
                            labelText: l10n.pairingCodeLabel,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? l10n.pairingCodeRequired
                              : null,
                        ),
                      ),
                      const SizedBox(height: RestoflowSpacing.sm),
                      Text(
                        l10n.pairingWhereCode,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_errorKind != null) ...[
                        const SizedBox(height: RestoflowSpacing.md),
                        RestoflowNoticeBanner(
                          tone: RestoflowTone.danger,
                          body: _errorMessage(l10n, _errorKind!),
                        ),
                      ],
                      const SizedBox(height: RestoflowSpacing.lg),
                      FilledButton.icon(
                        key: const Key('pairing-submit'),
                        onPressed: _busy ? null : _submit,
                        style: RestoflowButtonStyles.big(context),
                        icon: _busy
                            ? const RestoflowInlineSpinner()
                            : const Icon(Icons.link),
                        label: Text(l10n.pairingPairAction),
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
