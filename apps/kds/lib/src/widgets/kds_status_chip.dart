import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';

/// A colour-coded status chip for a kitchen ticket.
///
/// RF-102 is restyle-only: the chip's VISIBLE TEXT is the raw
/// [KitchenTicketStatus] `canonicalName` (data) — it is not localized or
/// altered, and no status value/transition is added (DECISION D-018; RF-103
/// owns transitions). Only colour/shape are added for at-a-glance readability.
class KdsStatusChip extends StatelessWidget {
  const KdsStatusChip({required this.status, super.key});

  final KitchenTicketStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _paletteFor(status, theme.colorScheme);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.sm,
        vertical: RestoflowSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(RestoflowRadii.pill),
      ),
      child: Text(
        status.canonicalName,
        style: theme.textTheme.labelLarge?.copyWith(
          color: palette.foreground,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _ChipPalette {
  const _ChipPalette(this.background, this.foreground);
  final Color background;
  final Color foreground;
}

_ChipPalette _paletteFor(KitchenTicketStatus status, ColorScheme scheme) {
  switch (status) {
    case KitchenTicketStatus.newTicket:
      return _ChipPalette(scheme.surfaceContainerHighest, scheme.onSurface);
    case KitchenTicketStatus.acknowledged:
      return const _ChipPalette(Color(0xFFE0E7FF), Color(0xFF3730A3));
    case KitchenTicketStatus.inPreparation:
      return const _ChipPalette(Color(0xFFFEF3C7), Color(0xFF92400E));
    case KitchenTicketStatus.ready:
      return const _ChipPalette(Color(0xFFDCFCE7), Color(0xFF166534));
    case KitchenTicketStatus.bumped:
      return _ChipPalette(scheme.surfaceContainerHigh, scheme.onSurfaceVariant);
    case KitchenTicketStatus.cancelled:
      return _ChipPalette(scheme.errorContainer, scheme.onErrorContainer);
  }
}
