import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'storefront_color_picker.dart';
import 'storefront_copy.dart';

class StorefrontSceneChoice {
  const StorefrontSceneChoice(this.preset);
  final String? preset;
}

/// A bounded scene-treatment comparison of the same draft photo and palette.
/// This is a miniature sample, not a replacement for the full Storefront
/// preview. It never publishes or changes the underlying editor on dismissal.
class StorefrontScenePresetDialog extends StatefulWidget {
  const StorefrontScenePresetDialog({
    super.key,
    required this.currentPreset,
    required this.sample,
    required this.backgroundUrl,
    required this.customBackground,
    required this.dim,
    required this.headline,
  });
  final String? currentPreset;
  final StorefrontColorSample sample;
  final Uri? backgroundUrl;
  final bool customBackground;
  final int dim;
  final String headline;

  @override
  State<StorefrontScenePresetDialog> createState() => _SceneDialogState();
}

class _SceneDialogState extends State<StorefrontScenePresetDialog> {
  String? _selected = 'reference_dark';

  String c(String key) =>
      storefrontContentCopy(AppLocalizations.of(context), key);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 880, maxHeight: size.height * .9),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            key: const Key('storefront-scene-dialog'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                c('sceneTitle'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(c('sceneHelp')),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            key: const Key('storefront-scene-reference'),
                            selected: _selected == 'reference_dark',
                            label: Text(c('sceneReference')),
                            onSelected: (_) =>
                                setState(() => _selected = 'reference_dark'),
                          ),
                          ChoiceChip(
                            key: const Key('storefront-scene-legacy'),
                            selected: _selected == null,
                            label: Text(c('sceneLegacy')),
                            onSelected: (_) => setState(() => _selected = null),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        c(
                          'menuBackgroundDim',
                        ).replaceAll('{percent}', '${widget.dim}'),
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          Widget panel(bool reference) => _preview(reference);
                          if (constraints.maxWidth < 600) {
                            return Column(
                              children: [
                                panel(false),
                                const SizedBox(height: 16),
                                panel(true),
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: panel(false)),
                              const SizedBox(width: 16),
                              Expanded(child: panel(true)),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(c('scenePreviewNote')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    key: const Key('storefront-scene-cancel'),
                    onPressed: () => Navigator.pop(context),
                    child: Text(c('colorCancel')),
                  ),
                  FilledButton(
                    key: const Key('storefront-scene-apply'),
                    onPressed: () => Navigator.pop(
                      context,
                      StorefrontSceneChoice(_selected),
                    ),
                    child: Text(c('colorApply')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview(bool reference) {
    final key = reference ? 'reference' : 'legacy';
    final current = (widget.currentPreset == 'reference_dark') == reference;
    final selected = (_selected == 'reference_dark') == reference;
    final palette = reference
        ? widget.sample.withColor(StorefrontColorRole.background, '#151515')
        : widget.sample;
    final primary = palette.color(StorefrontColorRole.background);
    final text = palette.color(StorefrontColorRole.text);
    final glass = reference ? const Color(0xff151515) : primary;
    final surface = reference ? const Color(0xff252525) : primary;
    final fallback = !widget.customBackground;
    final uri = widget.backgroundUrl;
    Widget? photograph;
    if (uri != null) {
      photograph = Image.network(
        uri.toString(),
        key: Key('scene-$key-photo'),
        width: double.infinity,
        height: double.infinity,
        fit: reference || fallback || MediaQuery.sizeOf(context).width > 650
            ? BoxFit.cover
            : BoxFit.fill,
        errorBuilder: (_, _, _) => ColoredBox(
          color: primary,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                c('sceneImageUnavailable'),
                style: TextStyle(color: text),
              ),
            ),
          ),
        ),
      );
      if (!reference && fallback) {
        photograph = Opacity(
          opacity: .18,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Transform.scale(scale: 1.08, child: photograph),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          c(reference ? 'sceneReference' : 'sceneLegacy'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Wrap(
          spacing: 8,
          children: [
            if (current) Text(c('sceneCurrent')),
            if (selected) Text(c('sceneSelected')),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            key: Key('scene-$key-preview'),
            height: 260,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: primary),
                if (photograph != null) photograph,
                if (reference || !fallback)
                  ColoredBox(
                    key: Key('scene-$key-dim'),
                    color: (reference ? Colors.black : primary).withValues(
                      alpha: widget.dim / 100,
                    ),
                  ),
                if (!reference && fallback)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x40000000)],
                      ),
                    ),
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      key: Key('scene-$key-navigation'),
                      color: glass.withValues(alpha: reference ? .76 : .94),
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        c('sceneMenu'),
                        style: TextStyle(color: text),
                        maxLines: 1,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (uri == null)
                              Expanded(
                                child: Center(
                                  child: Text(
                                    c('sceneNoImage'),
                                    style: TextStyle(color: text),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            else
                              const Spacer(),
                            Container(
                              color: surface.withValues(
                                alpha: reference ? .8 : .96,
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    widget.headline,
                                    style: TextStyle(color: text),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  ColoredBox(
                                    color: palette.color(
                                      StorefrontColorRole.accent,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(
                                        c('colorPreviewButton'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: palette.color(
                                            StorefrontColorRole.buttonText,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
