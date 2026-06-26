import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/menu_image_path.dart';
import '../models/menu_item.dart';
import 'menu_badges.dart';
import 'menu_components.dart';

/// The GATED item-image panel (RF-111). It does NOT upload or persist an image:
/// there is no authenticated session yet (D1) and no backend pointer for the
/// "current image of an item" (D2 / D-032). It honestly explains the deferral,
/// shows a polished placeholder, and previews the RF-110 object-key the upload
/// WILL use — proving the path builder is wired without any false claim.
class MenuImagePanel extends StatelessWidget {
  const MenuImagePanel({required this.item, super.key});

  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pathPreview = buildMenuImageObjectKey(
      organizationId: item.organizationId,
      restaurantId: item.restaurantId,
      branchId: item.branchId,
      menuItemId: item.id,
      imageId: '{image_id}',
      extension: 'png',
    );

    final placeholder = Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 34,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          Text(
            l10n.menuImageEmptyHint,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    final explanation = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.menuImageDeferredTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: RestoflowSpacing.xs),
        Text(
          l10n.menuImageDeferredBody,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.md),
        MenuCodeBlock(pathPreview),
      ],
    );

    return MenuSectionCard(
      title: l10n.menuImageHeading,
      icon: Icons.image_outlined,
      trailing: MenuPill(
        label: l10n.menuComingSoonBadge,
        icon: Icons.schedule,
        background: theme.colorScheme.tertiaryContainer,
        foreground: theme.colorScheme.onTertiaryContainer,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                placeholder,
                const SizedBox(height: RestoflowSpacing.md),
                explanation,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              placeholder,
              const SizedBox(width: RestoflowSpacing.lg),
              Expanded(child: explanation),
            ],
          );
        },
      ),
    );
  }
}
