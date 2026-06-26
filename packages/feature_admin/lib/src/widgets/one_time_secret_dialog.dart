import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// A modal that shows a server-generated one-time secret (an enrollment code or a
/// device session token) EXACTLY ONCE, with a clear "you won't see this again"
/// warning and a copy affordance. The plaintext is held only for the lifetime of
/// this dialog (the store never persisted it); once dismissed it is gone — there
/// is no way to re-reveal it (a re-issue / new session would mint a fresh one).
class OneTimeSecretDialog extends StatefulWidget {
  const OneTimeSecretDialog({
    required this.title,
    required this.subtitle,
    required this.secret,
    required this.icon,
    this.footnote,
    super.key,
  });

  final String title;
  final String subtitle;
  final String secret;
  final IconData icon;
  final String? footnote;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String secret,
    required IconData icon,
    String? footnote,
  }) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => OneTimeSecretDialog(
      title: title,
      subtitle: subtitle,
      secret: secret,
      icon: icon,
      footnote: footnote,
    ),
  );

  @override
  State<OneTimeSecretDialog> createState() => _OneTimeSecretDialogState();
}

class _OneTimeSecretDialogState extends State<OneTimeSecretDialog> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AlertDialog(
      icon: Icon(widget.icon, color: scheme.primary),
      title: Text(widget.title, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: RestoflowSpacing.lg),
          // The secret, mono-spaced, in a tonal box.
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: RestoflowSpacing.md,
              vertical: RestoflowSpacing.md,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(RestoflowRadii.md),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    widget.secret,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.adminCopy,
                  icon: Icon(_copied ? Icons.check : Icons.copy_outlined),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: widget.secret));
                    if (context.mounted) setState(() => _copied = true);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: RestoflowSpacing.md),
          // The "shown once" warning.
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
              const SizedBox(width: RestoflowSpacing.sm),
              Expanded(
                child: Text(
                  l10n.adminShownOnce,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (widget.footnote != null) ...[
            const SizedBox(height: RestoflowSpacing.sm),
            Text(
              widget.footnote!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.adminDone),
        ),
      ],
    );
  }
}
