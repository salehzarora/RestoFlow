import 'package:flutter/material.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'role_label.dart';

/// The shared membership picker (RF-108).
///
/// Lists the caller's memberships by NAME (organization, and restaurant/branch
/// when present) plus the role label, and reports the chosen membership id via
/// [onSelect]. Multi-membership (D-004); never assumes a global role; shows NO
/// raw UUIDs (ids are used only for the callback) and NO money. RTL is automatic
/// via the app `Directionality`/l10n.
class MembershipPickerView extends StatelessWidget {
  const MembershipPickerView({
    required this.memberships,
    required this.onSelect,
    super.key,
  });

  final List<MembershipContext> memberships;

  /// Called with the selected `MembershipContext.id`.
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(RestoflowSpacing.lg),
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            bottom: RestoflowSpacing.md,
          ),
          child: Text(
            l10n.authChooseLocation,
            style: theme.textTheme.titleLarge,
          ),
        ),
        for (final membership in memberships)
          _MembershipTile(
            membership: membership,
            onTap: () => onSelect(membership.id),
          ),
      ],
    );
  }
}

class _MembershipTile extends StatelessWidget {
  const _MembershipTile({required this.membership, required this.onTap});

  final MembershipContext membership;
  final VoidCallback onTap;

  /// First grapheme of the organization NAME (data derivation, never copy;
  /// uppercasing is a no-op for Arabic/Hebrew).
  static String _monogram(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: RestoflowSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        child: Padding(
          padding: const EdgeInsets.all(RestoflowSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Org monogram — derived from the name, never an id.
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(RestoflowRadii.md),
                ),
                child: Text(
                  _monogram(membership.organizationName),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: RestoflowSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Names only - never the membership UUID.
                    Text(
                      membership.organizationName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (membership.restaurantName != null ||
                        membership.branchName != null)
                      const SizedBox(height: RestoflowSpacing.xs),
                    if (membership.restaurantName != null)
                      _LabeledValue(
                        label: l10n.authRestaurant,
                        value: membership.restaurantName!,
                      ),
                    if (membership.branchName != null)
                      _LabeledValue(
                        label: l10n.authBranch,
                        value: membership.branchName!,
                      ),
                    const SizedBox(height: RestoflowSpacing.sm),
                    RestoflowStatusPill(
                      label: membershipRoleLabel(l10n, membership.role),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              // Auto-mirrors under RTL.
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabeledValue extends StatelessWidget {
  const _LabeledValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
