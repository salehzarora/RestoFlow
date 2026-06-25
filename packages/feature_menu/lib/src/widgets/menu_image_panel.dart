import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/menu_image_path.dart';
import '../models/menu_item.dart';

/// The GATED item-image panel (RF-111). It does NOT upload or persist an image:
/// there is no authenticated session yet (D1) and no backend pointer for the
/// "current image of an item" (D2 / D-032). It honestly explains the deferral and
/// shows the RF-110 storage object-key the upload WILL use, proving the path
/// builder is wired without making any false production claim.
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.menuImageHeading, style: theme.textTheme.titleMedium),
        const SizedBox(height: RestoflowSpacing.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(RestoflowSpacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(RestoflowRadii.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.image_outlined,
                    size: 20,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: RestoflowSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.menuImageDeferredTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RestoflowSpacing.sm),
              Text(
                l10n.menuImageDeferredBody,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(height: RestoflowSpacing.md),
              SelectableText(
                pathPreview,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
