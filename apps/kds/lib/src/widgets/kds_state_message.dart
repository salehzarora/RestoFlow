import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// A centered icon (or spinner) plus a localized message, used for the KDS
/// loading / error / re-auth / empty states so each state reads clearly from a
/// distance instead of being an unexplained icon.
class KdsStateMessage extends StatelessWidget {
  const KdsStateMessage({
    required this.message,
    this.icon,
    this.showSpinner = false,
    super.key,
  }) : assert(
         icon != null || showSpinner,
         'KdsStateMessage needs an icon or a spinner',
       );

  final String message;
  final IconData? icon;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSpinner)
              const CircularProgressIndicator()
            else
              Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: RestoflowSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
