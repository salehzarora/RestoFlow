import 'package:flutter/material.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'storefront_content_models.dart';
import 'storefront_copy.dart';
import 'storefront_banner_preview.dart';

/// Presentation over the existing draft and published editorial library.
/// Saving, upload identity, permissions and CAS remain in the parent editor.
class StorefrontMenuBannerEditor extends StatefulWidget {
  const StorefrontMenuBannerEditor({
    required this.appearance,
    required this.media,
    required this.editable,
    required this.onChanged,
    this.publicUrlFor,
    this.onUpload,
    this.onDesktopUpload,
    this.desktopQualityMessage,
    this.previewIdentity = '',
    this.previewDataFor,
    this.loadPreview,
    super.key,
  });
  final Map? appearance;
  final List<StorefrontContentMediaRow> media;
  final bool editable;
  final void Function(String, Object?) onChanged;
  final Uri Function(String)? publicUrlFor;
  final VoidCallback? onUpload, onDesktopUpload;
  final String? desktopQualityMessage;

  final String previewIdentity;
  final Map<String, Object?> Function(Map<String, dynamic>?)? previewDataFor;
  final Future<Map<String, dynamic>?> Function()? loadPreview;

  @override
  State<StorefrontMenuBannerEditor> createState() => _BannerEditorState();
}

class _BannerEditorState extends State<StorefrontMenuBannerEditor> {
  int _phoneWidth = 390;
  bool _editingPhone = true;
  int _readGeneration = 0;
  bool _readStarted = false, _reading = false;
  Map<String, dynamic>? _published;
  StorefrontBannerCrop? _phoneCrop, _desktopCrop;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _readIfVisible();
  }

  @override
  void didUpdateWidget(covariant StorefrontMenuBannerEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.previewIdentity != widget.previewIdentity) {
      _readGeneration++;
      _readStarted = false;
      _published = null;
      _phoneCrop = _desktopCrop = null;
    }
    _readIfVisible();
  }

  void _readIfVisible() {
    if (_readStarted ||
        widget.loadPreview == null ||
        !TickerMode.valuesOf(context).enabled)
      return;
    _readStarted = true;
    _reading = true;
    final generation = ++_readGeneration;
    // One public read per editor scope/version, never per focal movement.
    Future<Map<String, dynamic>?>.sync(widget.loadPreview!).then(
      (value) {
        if (!mounted || generation != _readGeneration) return;
        setState(() {
          _published = value;
          _reading = false;
        });
      },
      onError: (Object _) {
        if (!mounted || generation != _readGeneration) return;
        setState(() {
          _published = null;
          _reading = false;
        });
      },
    );
  }

  void _crop(bool phone, StorefrontBannerCrop value) {
    if (value.sameAs(phone ? _phoneCrop : _desktopCrop)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || value.sameAs(phone ? _phoneCrop : _desktopCrop)) return;
      setState(() {
        if (phone) {
          _phoneCrop = value;
        } else {
          _desktopCrop = value;
        }
      });
    });
  }

  String c(String key) =>
      storefrontContentCopy(AppLocalizations.of(context), key);

  Widget _heightControl(bool phone) {
    final device = phone ? 'mobile' : 'desktop';
    final field = 'menu_banner_${device}_height_px';
    final value = widget.appearance?[field] as int?;
    final low = phone ? 320 : 240, high = phone ? 640 : 560;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(
            'content-menu-banner-$device-height-mode-${value == null}',
          ),
          isExpanded: true,
          initialValue: value == null ? 'auto' : 'custom',
          decoration: InputDecoration(
            labelText: c(phone ? 'bannerPhoneHeight' : 'bannerDesktopHeight'),
          ),
          items: [
            for (final mode in ['auto', 'custom'])
              DropdownMenuItem(
                value: mode,
                child: Text(c('bannerHeight$mode')),
              ),
          ],
          onChanged: widget.editable
              ? (mode) => widget.onChanged(
                  field,
                  mode == 'custom' ? (phone ? 520 : 400) : null,
                )
              : null,
        ),
        if (value != null) ...[
          Text('$value CSS px', textDirection: TextDirection.ltr),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Slider(
              key: ValueKey('content-menu-banner-$device-height'),
              value: value.toDouble(),
              min: low.toDouble(),
              max: high.toDouble(),
              divisions: high - low,
              label: '$value CSS px',
              semanticFormatterCallback: (v) => '${v.round()} CSS px',
              onChanged: widget.editable
                  ? (v) => widget.onChanged(field, v.round())
                  : null,
            ),
          ),
          Row(
            // Physical low-to-high order matches the LTR slider in every locale.
            textDirection: TextDirection.ltr,
            children: [
              for (final (label, stop) in [
                ('bannerHeightLow', low),
                ('bannerHeightMedium', (low + high) ~/ 2),
                ('bannerHeightHigh', high),
              ])
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        c(label),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text('$stop px', textDirection: TextDirection.ltr),
                    ],
                  ),
                ),
            ],
          ),
          TextButton(
            key: ValueKey('content-menu-banner-$device-height-reset'),
            onPressed: widget.editable
                ? () => widget.onChanged(field, null)
                : null,
            child: Text(c('bannerHeightReset')),
          ),
        ],
        Text(
          c('bannerHeightHelp'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _desktopControls(List<StorefrontContentMediaRow> available) {
    final id = widget.appearance?['menu_banner_desktop_media_id'] as String?;
    final selected = available.any((row) => row.media.id == id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          c('bannerDesktopImage'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        DropdownButtonFormField<String>(
          key: ValueKey('content-menu-banner-desktop-media-${id ?? ''}'),
          initialValue: selected ? id : '',
          isExpanded: true,
          decoration: InputDecoration(labelText: c('bannerDesktopImage')),
          items: [
            DropdownMenuItem(
              value: '',
              child: Text(c('bannerDesktopFallback')),
            ),
            for (final row in available)
              DropdownMenuItem(
                value: row.media.id,
                child: Text(
                  '${row.media.width}×${row.media.height} · ${row.media.id.substring(0, 8)}',
                  textDirection: TextDirection.ltr,
                ),
              ),
          ],
          onChanged: widget.editable
              ? (value) => widget.onChanged(
                  'menu_banner_desktop_media_id',
                  value == '' ? null : value,
                )
              : null,
        ),
        Wrap(
          spacing: 12,
          children: [
            TextButton.icon(
              key: const Key('content-menu-banner-desktop-upload'),
              onPressed: widget.onDesktopUpload,
              icon: const Icon(Icons.upload_outlined),
              label: Text(c('bannerDesktopUpload')),
            ),
            TextButton.icon(
              key: const Key('content-menu-banner-desktop-clear'),
              onPressed: widget.editable && id != null
                  ? () => widget.onChanged('menu_banner_desktop_media_id', null)
                  : null,
              icon: const Icon(Icons.clear),
              label: Text(c('bannerDesktopClear')),
            ),
          ],
        ),
        Text(
          c('bannerDesktopHelp'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (widget.desktopQualityMessage != null)
          Text(
            widget.desktopQualityMessage!,
            key: const Key('content-desktop-banner-quality-status'),
          ),
        for (final axis in ['x', 'y']) ...[
          Text(
            '${c(axis == 'x' ? 'menuBannerFocusX' : 'menuBannerFocusY')} — ${widget.appearance?['menu_banner_desktop_focal_$axis'] ?? 50}%',
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Slider(
              key: ValueKey('content-menu-banner-desktop-focal-$axis'),
              value:
                  ((widget.appearance?['menu_banner_desktop_focal_$axis']
                              as int?) ??
                          50)
                      .toDouble(),
              min: 0,
              max: 100,
              divisions: 100,
              semanticFormatterCallback: (v) => '${v.round()}%',
              onChanged: widget.editable
                  ? (v) => widget.onChanged(
                      'menu_banner_desktop_focal_$axis',
                      v.round(),
                    )
                  : null,
            ),
          ),
        ],
        _heightControl(false),
      ],
    );
  }

  Widget _frame(bool phone, Map<String, Object?> data, int x, int y) {
    final crop = phone ? _phoneCrop : _desktopCrop;
    final desktop = !phone && data['layout'] == 'responsive';
    final hasDesktopImage = desktop && data['desktopImageUrl'] is String;
    final resolved = <String, Object?>{
      ...data,
      'imageUrl': hasDesktopImage ? data['desktopImageUrl'] : data['imageUrl'],
      'imageWidth': hasDesktopImage
          ? data['desktopImageWidth']
          : data['imageWidth'],
      'imageHeight': hasDesktopImage
          ? data['desktopImageHeight']
          : data['imageHeight'],
      'heightPx': desktop ? data['desktopHeightPx'] : data['mobileHeightPx'],
      'device': phone ? 'phone' : 'desktop',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${c(phone ? 'bannerPhone' : 'bannerDesktop')} — ${phone ? _phoneWidth : 1280}px',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        StorefrontBannerPreviewFrame(
          key: ValueKey(phone ? 'banner-phone-frame' : 'banner-desktop-frame'),
          data: resolved,
          focalX: x,
          focalY: y,
          logicalWidth: (phone ? _phoneWidth : 1280).toDouble(),
          onCrop: (value) => _crop(phone, value),
        ),
        if (crop != null && crop.imageLoaded) ...[
          Text(
            '${crop.naturalWidth.round()}×${crop.naturalHeight.round()} → '
            '${crop.viewWidth.round()}×${crop.viewHeight.toStringAsFixed(1)} CSS px',
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final axis in ['x', 'y'])
            Text(
              '${c(axis == 'x' ? 'menuBannerFocusX' : 'menuBannerFocusY')}: '
              '${(axis == 'x' ? crop.clippedX : crop.clippedY) < .01 ? c('bannerAxisComplete') : c('bannerAxisCropped')}',
              key: ValueKey('banner-${phone ? 'phone' : 'desktop'}-axis-$axis'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    String c(String key) =>
        storefrontContentCopy(AppLocalizations.of(context), key);
    final id = widget.appearance?['menu_banner_media_id'] as String?;
    final available = widget.media.where((row) => row.media.isLive).toList();
    final selected = available.where((row) => row.media.id == id).firstOrNull;
    final x = widget.appearance?['menu_banner_focal_x'] as int? ?? 50;
    final y = widget.appearance?['menu_banner_focal_y'] as int? ?? 50;
    final responsive = widget.appearance?['menu_banner_layout'] == 'responsive';
    final desktopId =
        widget.appearance?['menu_banner_desktop_media_id'] as String?;
    final desktop = available
        .where((row) => row.media.id == desktopId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(c('menuBannerHelp')),
        SwitchListTile(
          key: const Key('content-menu-banner-layout'),
          title: Text(c('bannerResponsiveLayout')),
          subtitle: Text(c('bannerResponsiveHelp')),
          value: responsive,
          onChanged: widget.editable
              ? (enabled) {
                  setState(() => _editingPhone = true);
                  widget.onChanged(
                    'menu_banner_layout',
                    enabled ? 'responsive' : null,
                  );
                }
              : null,
        ),
        SwitchListTile(
          key: const Key('content-menu-banner-enabled'),
          title: Text(c('menuBannerEnabled')),
          value: widget.appearance?['menu_banner_enabled'] == true,
          onChanged: widget.editable
              ? (value) => widget.onChanged('menu_banner_enabled', value)
              : null,
        ),
        SwitchListTile(
          key: const Key('content-menu-intro-visible'),
          title: Text(c('menuIntroVisible')),
          value: widget.appearance?['menu_intro_visible'] != false,
          onChanged: widget.editable
              ? (value) => widget.onChanged('menu_intro_visible', value)
              : null,
        ),
        if (responsive)
          Wrap(
            spacing: 8,
            children: [
              for (final phone in [true, false])
                ChoiceChip(
                  key: ValueKey(
                    'content-menu-banner-device-${phone ? 'phone' : 'desktop'}',
                  ),
                  label: Text(
                    c(phone ? 'bannerEditPhone' : 'bannerEditDesktop'),
                  ),
                  selected: _editingPhone == phone,
                  onSelected: (_) => setState(() => _editingPhone = phone),
                ),
            ],
          ),
        if (!responsive || _editingPhone) ...[
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
            onChanged: widget.editable
                ? (value) => widget.onChanged(
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
                onPressed: widget.onUpload,
                icon: const Icon(Icons.upload_outlined),
                label: Text(c('menuBannerUpload')),
              ),
              TextButton.icon(
                key: const Key('content-menu-banner-clear'),
                onPressed: widget.editable && id != null
                    ? () => widget.onChanged('menu_banner_media_id', null)
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
              Directionality(
                textDirection: TextDirection.ltr,
                child: Slider(
                  key: ValueKey('content-menu-banner-focal-$axis'),
                  value: (axis == 'x' ? x : y).toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '${axis == 'x' ? x : y}%',
                  semanticFormatterCallback: (value) => '${value.round()}%',
                  onChanged: widget.editable
                      ? (value) => widget.onChanged(
                          'menu_banner_focal_$axis',
                          value.round(),
                        )
                      : null,
                ),
              ),
            ],
          ],
          if (responsive) _heightControl(true),
        ],
        if (responsive && !_editingPhone) _desktopControls(available),
        const SizedBox(height: 12),
        Text(c('menuBannerPreview')),
        Text(
          c('bannerPreviewScope'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_reading) Text(c('bannerStateLoading')),
        if (!_reading && _published == null) Text(c('bannerStateUnavailable')),
        Wrap(
          spacing: 8,
          children: [
            for (final width in [360, 390, 430])
              ChoiceChip(
                key: ValueKey('banner-preview-width-$width'),
                label: Text(
                  c('bannerWidth').replaceFirst('{width}', width.toString()),
                  textDirection: TextDirection.ltr,
                ),
                selected: _phoneWidth == width,
                onSelected: (_) => setState(() {
                  _phoneWidth = width;
                  _phoneCrop = null;
                }),
              ),
          ],
        ),
        if (TickerMode.valuesOf(context).enabled)
          Builder(
            builder: (context) {
              final data = <String, Object?>{
                ...?widget.previewDataFor?.call(_published),
                'imageUrl': selected == null
                    ? null
                    : widget.publicUrlFor
                          ?.call(selected.media.objectKey)
                          .toString(),
                'enabled': widget.appearance?['menu_banner_enabled'] == true,
                'showIntro': widget.appearance?['menu_intro_visible'] != false,
                'layout': responsive ? 'responsive' : null,
                'imageWidth': selected?.media.width,
                'imageHeight': selected?.media.height,
                'desktopImageUrl': desktop == null
                    ? null
                    : widget.publicUrlFor
                          ?.call(desktop.media.objectKey)
                          .toString(),
                'desktopImageWidth': desktop?.media.width,
                'desktopImageHeight': desktop?.media.height,
                'mobileHeightPx':
                    widget.appearance?['menu_banner_mobile_height_px'],
                'desktopHeightPx':
                    widget.appearance?['menu_banner_desktop_height_px'],
              };
              final imageUrl = data['imageUrl'];
              final resolved = imageUrl is String
                  ? Uri.tryParse(imageUrl)
                  : Uri.tryParse(data['logoUrl'] as String? ?? '');
              if (resolved?.hasAuthority == true)
                data['mediaOrigin'] = resolved!.origin;
              final hero = data['hero'];
              if (hero is Map &&
                  hero['photo'] is String &&
                  imageUrl is String) {
                final photo = hero['photo'] as String;
                final origin = Uri.tryParse(imageUrl);
                if (photo.startsWith('/storage/v1/object/public/') &&
                    origin?.hasAuthority == true) {
                  data['hero'] = <String, Object?>{
                    ...Map<String, Object?>.from(hero),
                    'photo': origin!.resolve(photo).toString(),
                  };
                }
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  final width = wide
                      ? (constraints.maxWidth - 20) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    children: [
                      SizedBox(width: width, child: _frame(true, data, x, y)),
                      SizedBox(
                        width: width,
                        child: _frame(
                          false,
                          data,
                          responsive
                              ? (widget.appearance?['menu_banner_desktop_focal_x']
                                        as int? ??
                                    50)
                              : x,
                          responsive
                              ? (widget.appearance?['menu_banner_desktop_focal_y']
                                        as int? ??
                                    50)
                              : y,
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
      ],
    );
  }
}
