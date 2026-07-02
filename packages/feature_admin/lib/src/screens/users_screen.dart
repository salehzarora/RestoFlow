import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../models/admin_scope.dart';
import '../models/admin_user.dart';
import '../models/role_rank.dart';
import '../state/admin_providers.dart';
import '../widgets/admin_common.dart';

/// The owner Users & Roles surface (RF-113 / RF-112 §4.26). Lists memberships with
/// role/scope/status chips; grant + change-role honour the role-rank guard (D-033)
/// visually (only assignable roles are offered) and via the backend on confirm.
class AdminUsersScreen extends ConsumerWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final users = ref.watch(adminUsersProvider);
    final scope = ref.watch(adminScopeProvider);
    final manage = canManage(scope.actingRole);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminPageHeader(
          title: l10n.adminUsersTitle,
          subtitle: l10n.adminUsersSubtitle,
          icon: Icons.group_outlined,
          actions: [
            FilledButton.icon(
              onPressed: manage
                  ? () => _showGrantDialog(context, ref, scope)
                  : null,
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: Text(l10n.adminGrantUser),
            ),
          ],
        ),
        Expanded(
          child: users.when(
            loading: AdminStateView.loading,
            error: (e, _) => AdminStateView.fromFailure(
              context,
              adminFailureOf(e),
              onRetry: () => ref.invalidate(adminUsersProvider),
            ),
            data: (list) {
              if (list.isEmpty) {
                return AdminStateView(
                  icon: Icons.group_outlined,
                  title: l10n.adminUsersEmptyTitle,
                  body: l10n.adminUsersEmptyBody,
                );
              }
              return ListView(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  RestoflowSpacing.lg,
                  0,
                  RestoflowSpacing.lg,
                  RestoflowSpacing.xxl,
                ),
                children: [
                  _RoleGuardNote(actor: scope.actingRole),
                  const SizedBox(height: RestoflowSpacing.md),
                  for (final u in list)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: RestoflowSpacing.sm,
                      ),
                      child: _UserTile(
                        user: u,
                        canManage:
                            manage &&
                            !u.isSelf &&
                            roleRank(scope.actingRole) > roleRank(u.role),
                        onChangeRole: () =>
                            _showChangeRoleDialog(context, ref, u, scope),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RoleGuardNote extends StatelessWidget {
  const _RoleGuardNote({required this.actor});
  final MembershipRole actor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(RestoflowSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.policy_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Text(
              l10n.adminRoleGuardNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          AdminRoleChip(role: actor),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.canManage,
    required this.onChangeRole,
  });

  final AdminUser user;
  final bool canManage;
  final VoidCallback onChangeRole;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final revoked = user.status == 'revoked';
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.lg),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.md),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: scheme.primaryContainer,
              child: Text(
                _initials(user.displayName),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: RestoflowSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.displayName,
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user.isSelf) ...[
                        const SizedBox(width: RestoflowSpacing.sm),
                        AdminPill(
                          label: l10n.adminSelf,
                          color: scheme.secondary,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: RestoflowSpacing.xxs),
                  Text(
                    user.email,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: RestoflowSpacing.sm),
                  Wrap(
                    spacing: RestoflowSpacing.sm,
                    runSpacing: RestoflowSpacing.xs,
                    children: [
                      AdminRoleChip(role: user.role),
                      AdminPill(
                        label: user.scopeLabel,
                        color: scheme.onSurfaceVariant,
                        icon: Icons.place_outlined,
                      ),
                      AdminPill.tone(
                        label: revoked
                            ? l10n.adminStatusRevoked
                            : l10n.adminStatusActive,
                        tone: revoked
                            ? RestoflowTone.danger
                            : RestoflowTone.success,
                        icon: revoked
                            ? Icons.block
                            : Icons.check_circle_outline,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Actions: change role (allowed) + revoke (deferred to RF-061 wiring).
            PopupMenuButton<String>(
              enabled: canManage,
              onSelected: (v) {
                if (v == 'role') onChangeRole();
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'role', child: Text(l10n.adminChangeRole)),
                PopupMenuItem(
                  value: 'revoke',
                  enabled: false,
                  child: Text('${l10n.adminRevoke} · ${l10n.adminComingSoon}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.characters.take(2).toString().toUpperCase();
  }
  return (parts.first.characters.first + parts.last.characters.first)
      .toUpperCase();
}

// ---------------------------------------------------------------------------
// Grant + change-role dialogs (role-rank guarded: only assignable roles shown).
// ---------------------------------------------------------------------------
Future<void> _showGrantDialog(
  BuildContext context,
  WidgetRef ref,
  AdminScope scope,
) async {
  final roles = assignableRoles(scope.actingRole);
  if (roles.isEmpty) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _GrantDialog(roles: roles, ref: ref),
  );
}

class _GrantDialog extends StatefulWidget {
  const _GrantDialog({required this.roles, required this.ref});
  final List<MembershipRole> roles;
  final WidgetRef ref;
  @override
  State<_GrantDialog> createState() => _GrantDialogState();
}

class _GrantDialogState extends State<_GrantDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  late MembershipRole _role = widget.roles.last;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final result = await widget.ref
        .read(adminControllerProvider)
        .grantMembership(
          displayName: _name.text,
          email: _email.text,
          role: _role,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    final messenger = ScaffoldMessenger.of(context);
    result.fold(
      (u) {
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(content: Text(l10n.adminUserGranted)));
      },
      (f) => messenger.showSnackBar(
        SnackBar(content: Text(adminFailureMessage(l10n, f))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.adminGrantDialogTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                labelText: l10n.adminFieldDisplayName,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? l10n.adminErrName : null,
            ),
            const SizedBox(height: RestoflowSpacing.md),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: l10n.adminFieldEmail,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              validator: (v) =>
                  RegExp(
                    r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                  ).hasMatch((v ?? '').trim())
                  ? null
                  : l10n.adminErrEmail,
            ),
            const SizedBox(height: RestoflowSpacing.md),
            DropdownButtonFormField<MembershipRole>(
              initialValue: _role,
              decoration: InputDecoration(
                labelText: l10n.adminFieldRole,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final r in widget.roles)
                  DropdownMenuItem(
                    value: r,
                    child: Text(adminRoleLabel(l10n, r)),
                  ),
              ],
              onChanged: (v) => setState(() => _role = v ?? _role),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.adminCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(l10n.adminGrant),
        ),
      ],
    );
  }
}

Future<void> _showChangeRoleDialog(
  BuildContext context,
  WidgetRef ref,
  AdminUser user,
  AdminScope scope,
) async {
  final roles = assignableRoles(scope.actingRole);
  if (roles.isEmpty) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _ChangeRoleDialog(user: user, roles: roles, ref: ref),
  );
}

class _ChangeRoleDialog extends StatefulWidget {
  const _ChangeRoleDialog({
    required this.user,
    required this.roles,
    required this.ref,
  });
  final AdminUser user;
  final List<MembershipRole> roles;
  final WidgetRef ref;
  @override
  State<_ChangeRoleDialog> createState() => _ChangeRoleDialogState();
}

class _ChangeRoleDialogState extends State<_ChangeRoleDialog> {
  late MembershipRole _role = widget.roles.contains(widget.user.role)
      ? widget.user.role
      : widget.roles.last;
  bool _busy = false;

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final result = await widget.ref
        .read(adminControllerProvider)
        .updateRole(userId: widget.user.id, newRole: _role);
    if (!mounted) return;
    setState(() => _busy = false);
    final messenger = ScaffoldMessenger.of(context);
    result.fold(
      (u) {
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(content: Text(l10n.adminRoleUpdated)));
      },
      (f) => messenger.showSnackBar(
        SnackBar(content: Text(adminFailureMessage(l10n, f))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.adminChangeRoleTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.user.displayName,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: RestoflowSpacing.md),
          DropdownButtonFormField<MembershipRole>(
            initialValue: _role,
            decoration: InputDecoration(
              labelText: l10n.adminFieldRole,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final r in widget.roles)
                DropdownMenuItem(
                  value: r,
                  child: Text(adminRoleLabel(l10n, r)),
                ),
            ],
            onChanged: (v) => setState(() => _role = v ?? _role),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.adminCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(l10n.adminUpdate),
        ),
      ],
    );
  }
}
