import 'package:flutter/material.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'storefront_content_models.dart';
import 'storefront_copy.dart';

/// Presentation over the existing draft and published editorial library.
/// Saving, upload identity, permissions and CAS remain in the parent editor.
class StorefrontMenuBannerEditor extends StatelessWidget {
  const StorefrontMenuBannerEditor({
    required this.appearance,
    required this.media,
    required this.editable,
    required this.onChanged,
    this.publicUrlFor,
    this.onUpload,
    super.key,
  });
  final Map? appearance;
  final List<StorefrontContentMediaRow> media;
  final bool editable;
  final void Function(String, Object?) onChanged;
  final Uri Function(String)? publicUrlFor;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    String c(String key) =>
        storefrontContentCopy(AppLocalizations.of(context), key);
    final id = appearance?['menu_banner_media_id'] as String?;
    final available = media.where((row) => row.media.isLive).toList();
    final selected = available.where((row) => row.media.id == id).firstOrNull;
    final x = appearance?['menu_banner_focal_x'] as int? ?? 50;
    final y = appearance?['menu_banner_focal_y'] as int? ?? 50;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(c('menuBannerHelp')),
        SwitchListTile(
          key: const Key('content-menu-banner-enabled'),
          title: Text(c('menuBannerEnabled')),
          value: appearance?['menu_banner_enabled'] == true,
          onChanged: editable
              ? (value) => onChanged('menu_banner_enabled', value)
              : null,
        ),
        SwitchListTile(
          key: const Key('content-menu-intro-visible'),
          title: Text(c('menuIntroVisible')),
          value: appearance?['menu_intro_visible'] != false,
          onChanged: editable
              ? (value) => onChanged('menu_intro_visible', value)
              : null,
        ),
        DropdownButtonFormField<String>(
          key: ValueKey('content-menu-banner-media-${id ?? ''}'),
          initialValue: selected != null ? id : '',
          isExpanded: true,
          decoration: InputDecoration(labelText: c('menuBannerImage')),
          items: [
            DropdownMenuItem(value: '', child: Text(c('menuBannerNone'))),
            for (final row in available)
              DropdownMenuItem(
                value: row.media.id,
                child: Text(
                  '${row.media.width}×${row.media.height} · ${row.media.id.substring(0, 8)}',
                  textDirection: TextDirection.ltr,
                ),
              ),
          ],
          onChanged: editable
              ? (value) => onChanged(
                  'menu_banner_media_id',
                  value == '' ? null : value,
                )
              : null,
        ),
        Wrap(
          spacing: 12,
          children: [
            TextButton.icon(
              key: const Key('content-menu-banner-upload'),
              onPressed: onUpload,
              icon: const Icon(Icons.upload_outlined),
              label: Text(c('menuBannerUpload')),
            ),
            TextButton.icon(
              key: const Key('content-menu-banner-clear'),
              onPressed: editable && id != null
                  ? () => onChanged('menu_banner_media_id', null)
                  : null,
              icon: const Icon(Icons.clear),
              label: Text(c('menuBannerClear')),
            ),
          ],
        ),
        if (selected != null) ...[
          for (final axis in ['x', 'y']) ...[
            Text(
              '${c(axis == 'x' ? 'menuBannerFocusX' : 'menuBannerFocusY')} — ${axis == 'x' ? x : y}%',
            ),
            Slider(
              key: ValueKey('content-menu-banner-focal-$axis'),
              value: (axis == 'x' ? x : y).toDouble(),
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: editable
                  ? (value) =>
                        onChanged('menu_banner_focal_$axis', value.round())
                  : null,
            ),
          ],
          Text(c('menuBannerPreview')),
          if (publicUrlFor != null && TickerMode.valuesOf(context).enabled)
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final ratio in [2.35, 3.2])
                    SizedBox(
                      width: (constraints.maxWidth - 12) / 2,
                      child: AspectRatio(
                        aspectRatio: ratio,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            publicUrlFor!(selected.media.objectKey).toString(),
                            fit: BoxFit.cover,
                            alignment: Alignment(x / 50 - 1, y / 50 - 1),
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.image_not_supported_outlined),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
