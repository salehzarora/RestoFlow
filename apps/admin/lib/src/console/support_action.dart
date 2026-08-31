/// ADMIN-126B — the "Open Dashboard" action and its typed-reason confirmation.
///
/// This is NOT a login shortcut. Pressing it asks the server for a short-lived,
/// audited, read-only support session against one named tenant; the operator
/// stays themselves throughout, and the tenant's own credentials are neither
/// used nor needed. The dialog says so in as many words, because an operator who
/// believes they are "logging in as the owner" will eventually behave as though
/// they were.
///
/// The reason is mandatory and free text. It is stored on the session and copied
/// into the audit event, so the platform log answers "why was this restaurant's
/// dashboard opened on Tuesday" with a sentence rather than a timestamp.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/platform_admin_repository.dart';
import '../state/platform_admin_providers.dart';

/// Opens a read-only support session for one tenant.
class OpenDashboardButton extends ConsumerStatefulWidget {
  const OpenDashboardButton({
    required this.organizationId,
    required this.organizationName,
    this.restaurantId,
    this.restaurantName,
    this.compact = true,
    this.openUrl,
    this.dashboardUrl,
    super.key,
  });

  final String organizationId;
  final String organizationName;

  /// Narrows the session to one restaurant. Null supports the whole
  /// organization, which is what the subscriber page offers.
  final String? restaurantId;
  final String? restaurantName;

  /// Icon-only in a dense list row; a full labelled button on a detail page.
  final bool compact;

  /// Injectable for tests, so a test never opens a real browser tab.
  final void Function(String url)? openUrl;

  /// Injectable for tests; production resolves `RESTOFLOW_DASHBOARD_URL`.
  final String? dashboardUrl;

  @override
  ConsumerState<OpenDashboardButton> createState() =>
      _OpenDashboardButtonState();
}

class _OpenDashboardButtonState extends ConsumerState<OpenDashboardButton> {
  bool _busy = false;

  Future<void> _start() async {
    final l10n = AppLocalizations.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => SupportReasonDialog(
        organizationName: widget.organizationName,
        restaurantName: widget.restaurantName,
      ),
    );
    if (reason == null || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final handoff = await ref
          .read(platformSupportLauncherProvider)
          .start(
            organizationId: widget.organizationId,
            restaurantId: widget.restaurantId,
            reason: reason,
          );
      // Straight from the response into the launch URL. The token is never
      // written to state, never rendered, and never logged — the only place it
      // exists on this device is the tab that consumes it.
      final url = handoff.launchUrl(
        widget.dashboardUrl ?? ref.read(dashboardUrlProvider),
      );
      final void Function(String) open =
          widget.openUrl ?? ref.read(supportUrlOpenerProvider);
      open(url);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          key: const Key('support-started-snack'),
          content: Text(l10n.adminSupportStarted),
        ),
      );
    } on PlatformAdminException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          key: const Key('support-failed-snack'),
          // The developer-facing message never reaches the operator; only the
          // distinction between "demo mode" and "refused" is useful to them.
          content: Text(
            e.kind == PlatformAdminErrorKind.notConfigured
                ? l10n.adminSupportUnavailable
                : l10n.adminSupportFailed,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onPressed = _busy ? null : _start;
    if (!widget.compact) {
      return FilledButton.tonalIcon(
        key: Key('open-dashboard-${widget.organizationId}'),
        onPressed: onPressed,
        icon: const Icon(Icons.open_in_new, size: RestoflowIconSizes.sm),
        label: Text(l10n.adminOpenDashboard),
      );
    }
    return IconButton(
      key: Key(
        'open-dashboard-${widget.restaurantId ?? widget.organizationId}',
      ),
      onPressed: onPressed,
      tooltip: l10n.adminOpenDashboard,
      icon: const Icon(Icons.open_in_new, size: RestoflowIconSizes.md),
    );
  }
}

/// Asks for the mandatory reason and states plainly what is about to happen.
class SupportReasonDialog extends StatefulWidget {
  const SupportReasonDialog({
    required this.organizationName,
    this.restaurantName,
    super.key,
  });

  final String organizationName;
  final String? restaurantName;

  @override
  State<SupportReasonDialog> createState() => _SupportReasonDialogState();
}

class _SupportReasonDialogState extends State<SupportReasonDialog> {
  final TextEditingController _reason = TextEditingController();
  bool _showEmptyError = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _reason.text.trim();
    if (value.isEmpty) {
      setState(() => _showEmptyError = true);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final target = (widget.restaurantName?.isNotEmpty ?? false)
        ? '${widget.organizationName} · ${widget.restaurantName}'
        : widget.organizationName;
    return AlertDialog(
      key: const Key('support-reason-dialog'),
      title: Text(l10n.adminSupportDialogTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: RestoflowPanelWidths.helpPanel,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              target,
              key: const Key('support-dialog-target'),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            Text(l10n.adminSupportDialogBody),
            const SizedBox(height: RestoflowSpacing.lg),
            TextField(
              key: const Key('support-reason-field'),
              controller: _reason,
              autofocus: true,
              maxLines: 2,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: l10n.adminSupportReasonLabel,
                hintText: l10n.adminSupportReasonHint,
                errorText: _showEmptyError
                    ? l10n.adminSupportReasonRequired
                    : null,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('support-reason-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.adminCancel),
        ),
        FilledButton(
          key: const Key('support-reason-confirm'),
          onPressed: _submit,
          child: Text(l10n.adminSupportDialogTitle),
        ),
      ],
    );
  }
}
