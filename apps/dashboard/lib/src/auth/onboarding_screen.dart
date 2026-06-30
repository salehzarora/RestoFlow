import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'onboarding_repository.dart';

/// The restaurant onboarding screen (RF-151): shown to an authenticated owner who
/// has no organization yet. Collects a restaurant name (+ optional branch) and
/// calls [OnboardingRepository.createOrganization] (the RF-150
/// `public.create_organization` wrapper). Honest states only — it never fakes a
/// created organization; a failure shows a safe, localized error and lets the
/// owner retry or sign out.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.onboardingRepository,
    required this.onCreated,
    this.onSignOut,
    this.initialRestaurantName,
    this.initialBranchName,
    super.key,
  });

  final OnboardingRepository onboardingRepository;

  /// Called after a successful create (the flow reloads the auth context).
  final VoidCallback onCreated;

  /// Signs out (null hides the action — e.g. legacy tests with no auth repo).
  final VoidCallback? onSignOut;

  final String? initialRestaurantName;
  final String? initialBranchName;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _restaurant = TextEditingController(
    text: widget.initialRestaurantName ?? '',
  );
  late final _branch = TextEditingController(
    text: widget.initialBranchName ?? '',
  );

  bool _busy = false;
  OnboardingErrorKind? _errorKind;

  @override
  void dispose() {
    _restaurant.dispose();
    _branch.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _errorKind = null;
    });

    final branch = _branch.text.trim();
    final outcome = await widget.onboardingRepository.createOrganization(
      restaurantName: _restaurant.text.trim(),
      branchName: branch.isEmpty ? null : branch,
    );
    if (!mounted) return;

    if (outcome is OnboardingSucceeded) {
      widget.onCreated();
      return;
    }
    setState(() {
      _busy = false;
      _errorKind = (outcome as OnboardingFailed).kind;
    });
  }

  String _errorMessage(AppLocalizations l10n, OnboardingErrorKind kind) =>
      kind == OnboardingErrorKind.network
      ? l10n.authNetworkError
      : l10n.onboardingFailed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(RestoflowSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: RestoflowSectionCard(
                title: l10n.onboardingTitle,
                subtitle: l10n.onboardingIntro,
                children: [
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          key: const Key('onboarding-restaurant'),
                          controller: _restaurant,
                          enabled: !_busy,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: l10n.onboardingRestaurantNameLabel,
                            prefixIcon: const Icon(Icons.storefront_outlined),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? l10n.onboardingRestaurantNameRequired
                              : null,
                        ),
                        const SizedBox(height: RestoflowSpacing.md),
                        TextFormField(
                          key: const Key('onboarding-branch'),
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
                    key: const Key('onboarding-submit'),
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_business_outlined),
                    label: Text(l10n.onboardingCreateAction),
                  ),
                  if (widget.onSignOut != null) ...[
                    const SizedBox(height: RestoflowSpacing.sm),
                    TextButton(
                      key: const Key('onboarding-signout'),
                      onPressed: _busy ? null : widget.onSignOut,
                      child: Text(l10n.authSignOut),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
