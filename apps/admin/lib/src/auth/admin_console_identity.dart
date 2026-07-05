import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:flutter/material.dart';

/// DESIGN-002 — the platform-operator "secure console" identity lockup.
///
/// A shield mark + audited-console tagline (and, when a session exists, the
/// signed-in operator account) shown on the sign-in and MFA screens so the
/// privileged console reads as distinct from the tenant apps and the operator
/// can always confirm which account is active. Presentation only — the
/// [email] is NON-secret and reveals no auth state beyond "who is signed in".
/// RTL-safe (Row/Column with directional-agnostic centering).
class AdminConsoleIdentity extends StatelessWidget {
  const AdminConsoleIdentity({this.email, super.key});

  /// The signed-in operator email, or null before sign-in (then only the
  /// shield + tagline show).
  final String? email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final scheme = theme.colorScheme;
    final currentEmail = email;

    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(RestoflowRadii.md),
          ),
          child: Icon(
            Icons.verified_user_outlined,
            size: RestoflowIconSizes.lg,
            color: scheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.sm),
        Text(
          l10n.adminSecureConsoleTagline,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (currentEmail != null && currentEmail.isNotEmpty) ...[
          const SizedBox(height: RestoflowSpacing.xxs),
          Text(
            l10n.adminSignedInAs(currentEmail),
            key: const Key('admin-signed-in-as'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
