/// The read-only Activity-log detail dialog (AUDIT-LOG-DASHBOARD-001).
///
/// A centered [Dialog] (the order-detail pattern) showing ONLY the normalized,
/// safe [AuditEventView] fields — actor, time, scope, device, reason, and the
/// allowlisted before→after change rows. There is NO edit / delete / retry
/// action and NO raw-JSON view: the timeline is strictly immutable (D-013) and
/// this is a viewer, not a console.
library;

import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/audit_log_presentation.dart';

/// Opens the read-only detail dialog for [view].
Future<void> showActivityDetailDialog(
  BuildContext context,
  AuditEventView view,
  AppLocalizations l10n,
) => showDialog<void>(
  context: context,
  builder: (context) => ActivityDetailDialog(view: view, l10n: l10n),
);

class ActivityDetailDialog extends StatelessWidget {
  const ActivityDetailDialog({
    required this.view,
    required this.l10n,
    super.key,
  });

  final AuditEventView view;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = view.tone.styleOf(theme);
    return Dialog(
      key: const Key('activity-detail-dialog'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(RestoflowSpacing.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: style.container,
                      borderRadius: BorderRadius.circular(RestoflowRadii.sm),
                    ),
                    alignment: Alignment.center,
                    child: Icon(view.icon, color: style.onContainer),
                  ),
                  const SizedBox(width: RestoflowSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(view.title, style: theme.textTheme.titleMedium),
                        const SizedBox(height: RestoflowSpacing.xxs),
                        Wrap(
                          spacing: RestoflowSpacing.xs,
                          runSpacing: RestoflowSpacing.xs,
                          children: [
                            RestoflowStatusPill(
                              label: view.categoryLabel,
                              tone: view.tone,
                              dense: true,
                            ),
                            if (view.isDenied)
                              RestoflowStatusPill(
                                label: l10n.activityLogDenied,
                                tone: RestoflowTone.warning,
                                icon: Icons.block_outlined,
                                dense: true,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('activity-detail-close'),
                    tooltip: l10n.activityLogClose,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.all(RestoflowSpacing.lg),
                shrinkWrap: true,
                children: [
                  _row(theme, l10n.activityLogFieldWhen, view.occurredAtLabel),
                  _row(theme, l10n.activityLogFieldActor, view.actorLabel),
                  if (view.scopeLabel != null)
                    _row(
                      theme,
                      l10n.activityLogFieldScopeLocation,
                      view.scopeLabel!,
                    ),
                  if (view.deviceLabel != null)
                    _row(theme, l10n.activityLogFieldDevice, view.deviceLabel!),
                  if (view.reason != null)
                    _row(theme, l10n.activityLogFieldReason, view.reason!),
                  if (view.changes.isNotEmpty) ...[
                    const SizedBox(height: RestoflowSpacing.md),
                    Text(
                      l10n.activityLogChangesHeading,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: kRestoflowInk2,
                      ),
                    ),
                    const SizedBox(height: RestoflowSpacing.sm),
                    for (final change in view.changes)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          bottom: RestoflowSpacing.sm,
                        ),
                        child: _ChangeRow(change: change, l10n: l10n),
                      ),
                  ],
                  if (!view.isKnownAction)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        top: RestoflowSpacing.md,
                      ),
                      child: Text(
                        l10n.activityLogGenericNote,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: kRestoflowInk3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, String label, String value) => Padding(
    padding: const EdgeInsetsDirectional.only(bottom: RestoflowSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: kRestoflowInk3),
          ),
        ),
        const SizedBox(width: RestoflowSpacing.sm),
        Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
      ],
    ),
  );
}

/// One before→after change row: "Label   old → new" (or just "new" when there is
/// no prior value). Localized "→" direction stays LTR-neutral via an arrow icon.
class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change, required this.l10n});

  final AuditChange change;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            change.label,
            style: theme.textTheme.bodySmall?.copyWith(color: kRestoflowInk3),
          ),
        ),
        const SizedBox(width: RestoflowSpacing.sm),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: RestoflowSpacing.xs,
            children: [
              if (change.oldValue != null) ...[
                Text(
                  change.oldValue!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: kRestoflowInk3,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                Icon(
                  Icons.arrow_forward,
                  size: RestoflowIconSizes.xs,
                  color: kRestoflowInk3,
                ),
              ],
              Text(
                change.newValue,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
