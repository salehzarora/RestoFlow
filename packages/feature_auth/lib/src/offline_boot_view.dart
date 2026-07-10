import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// PILOT-OFFLINE-BOOT-001: the friendly, restaurant-facing "no connection"
/// screen shown when POS/KDS launch (or relaunch after a tablet reboot) and the
/// venue Wi‑Fi / Supabase is unreachable.
///
/// It looks like the app (themed, dark-mode + RTL aware), speaks the staff's
/// language (ar/he/en, D-014), and NEVER shows a stack trace or developer
/// config text to a cashier/chef. [onRetry] re-runs the device-auth bootstrap
/// in place — no app restart. Null [onRetry] hides the button (a defensive
/// fallback path that cannot re-run the bootstrap). When [autoReconnecting] is
/// set, a reassuring "keep this screen open" line is shown.
class OfflineBootView extends StatelessWidget {
  const OfflineBootView({
    this.onRetry,
    this.autoReconnecting = false,
    super.key,
  });

  /// Re-runs the failed bootstrap. Null hides the Retry button.
  final VoidCallback? onRetry;

  /// Whether the boot gate is also auto-retrying in the background.
  final bool autoReconnecting;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: RestoflowPanelWidths.helpPanel,
          ),
          child: Padding(
            padding: const EdgeInsets.all(RestoflowSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.wifi_off_rounded,
                  size: RestoflowIconSizes.hero,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: RestoflowSpacing.lg),
                Text(
                  l10n.offlineBootTitle,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: RestoflowSpacing.sm),
                Text(
                  l10n.offlineBootMessage,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (autoReconnecting) ...[
                  const SizedBox(height: RestoflowSpacing.md),
                  Text(
                    l10n.offlineBootAutoReconnect,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (onRetry != null) ...[
                  const SizedBox(height: RestoflowSpacing.xl),
                  FilledButton.icon(
                    key: const Key('offline-boot-retry'),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.offlineBootRetry),
                    style: RestoflowButtonStyles.big(context),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
