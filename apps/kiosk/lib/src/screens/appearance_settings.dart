import 'dart:convert' show base64Encode;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kiosk_appearance.dart';
import '../data/kiosk_attract_media.dart';
import '../data/kiosk_logo_picker.dart';
import '../design/kiosk_theme.dart';
import '../widgets/kiosk_chrome.dart';
import 'device_theme_picker.dart';
import 'featured_picker.dart';

/// KIOSK-001-102 §13 — the REAL Appearance section of Device Settings.
///
/// Edits a working copy of [KioskAppearanceSettings]; nothing publishes until
/// the explicit Save (persisted device-locally through the appearance
/// controller). Touch-first: big fields, language tabs for the localized
/// copy, a curated palette + strict hex input for the two brand colors, a
/// live preview card, and a confirmed reset. Presentation only — no order,
/// money or auth state is readable or writable from here.
class KioskAppearanceSection extends ConsumerStatefulWidget {
  const KioskAppearanceSection({super.key});

  @override
  ConsumerState<KioskAppearanceSection> createState() =>
      _KioskAppearanceSectionState();
}

class _KioskAppearanceSectionState
    extends ConsumerState<KioskAppearanceSection> {
  late KioskAppearanceSettings _draft = ref.read(kioskAppearanceProvider);
  String _copyLang = 'ar';
  bool _saved = false;
  String? _logoError;

  void _update(KioskAppearanceSettings next) => setState(() {
    _draft = next;
    _saved = false;
  });

  Future<void> _chooseLogo() async {
    setState(() => _logoError = null);
    if (!kioskLogoPickerSupported) {
      setState(() => _logoError = 'unsupported');
      return;
    }
    final result = await pickKioskLogo();
    if (!mounted || result == null) return; // cancelled
    if (result.bytes == null) {
      setState(() => _logoError = 'invalid');
      return;
    }
    _update(
      _draft.copyWith(logoOverridePngB64: base64EncodeBytes(result.bytes!)),
    );
  }

  Future<void> _save() async {
    await ref.read(kioskAppearanceProvider.notifier).save(_draft);
    if (!mounted) return;
    setState(() => _saved = true);
  }

  // ---- KIOSK-001-103: curated attract media -------------------------------
  String? _mediaStatusKey; // invalid | too-large | too-long | store-failed
  KioskAttractMediaStore? get _mediaStore =>
      ref.read(kioskAttractMediaStoreProvider);
  String? get _mediaDeviceId =>
      ref.read(kioskAppearanceScopeProvider)?.deviceId;

  // ---- KIOSK-001-107: global device UI theme (draft-only until Save) ----
  KioskThemePair get _draftThemePair =>
      KioskThemePair.fromWire(_draft.uiThemeWire);

  Future<void> _editCustomTheme() async {
    final wire = await showDialog<String>(
      context: context,
      builder: (_) => KioskDeviceThemeCustomDialog(initial: _draftThemePair),
    );
    if (!mounted || wire == null) return; // Cancel changes nothing
    _update(_draft.copyWith(uiThemeWire: wire));
  }

  Future<void> _pickFeatured() async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) =>
          KioskFeaturedPickerDialog(initial: _draft.featuredMenuItemIds),
    );
    if (!mounted || result == null) return;
    _update(_draft.copyWith(featuredMenuItemIds: result));
  }

  Future<void> _chooseCustomImage() async {
    setState(() => _mediaStatusKey = null);
    final store = _mediaStore;
    final deviceId = _mediaDeviceId;
    if (store == null || !store.supported || deviceId == null) return;
    final picked = await pickKioskAttractImage();
    if (!mounted || picked == null) return; // cancelled
    if (picked is KioskAttractMediaResult) {
      setState(() => _mediaStatusKey = _statusOf(picked.error!));
      return;
    }
    final previous = _draft.customImageRef;
    final stored = await store.persistImage(
      deviceId: deviceId,
      bytes: picked as Uint8List,
    );
    if (!mounted) return;
    if (stored.ref == null) {
      setState(() => _mediaStatusKey = _statusOf(stored.error!));
      return;
    }
    if (previous != null) {
      await store.delete(deviceId: deviceId, ref: previous);
    }
    _update(_draft.copyWith(customImageRef: stored.ref));
  }

  Future<void> _chooseCustomVideo() async {
    setState(() => _mediaStatusKey = null);
    final store = _mediaStore;
    final deviceId = _mediaDeviceId;
    if (store == null || !store.supported || deviceId == null) return;
    final picked = await pickKioskAttractVideo();
    if (!mounted || picked == null) return; // cancelled
    if (picked is KioskAttractMediaResult) {
      setState(() => _mediaStatusKey = _statusOf(picked.error!));
      return;
    }
    final video = picked as KioskPickedVideo;
    final previous = _draft.customVideoRef;
    final stored = await store.persistVideoFromPath(
      deviceId: deviceId,
      sourcePath: video.sourcePath,
      ext: video.ext,
    );
    if (!mounted) return;
    if (stored.ref == null) {
      setState(() => _mediaStatusKey = _statusOf(stored.error!));
      return;
    }
    // §6: bounded PLAYABLE duration, proven by a real decode when the root
    // wires the probe; an undecodable or over-long file is deleted + refused.
    final probe = ref.read(kioskVideoProbeProvider);
    if (probe != null) {
      final path = await store.absolutePathOf(
        deviceId: deviceId,
        ref: stored.ref!,
      );
      final duration = path == null ? null : await probe(path);
      if (duration == null) {
        await store.delete(deviceId: deviceId, ref: stored.ref!);
        if (mounted) setState(() => _mediaStatusKey = 'invalid');
        return;
      }
      if (duration.inSeconds > KioskAppearanceLimits.attractVideoMaxSeconds) {
        await store.delete(deviceId: deviceId, ref: stored.ref!);
        if (mounted) setState(() => _mediaStatusKey = 'too-long');
        return;
      }
    }
    if (previous != null) {
      await store.delete(deviceId: deviceId, ref: previous);
    }
    if (mounted) _update(_draft.copyWith(customVideoRef: stored.ref));
  }

  Future<void> _removeCustomMedia({required bool image}) async {
    final store = _mediaStore;
    final deviceId = _mediaDeviceId;
    final removedRef = image ? _draft.customImageRef : _draft.customVideoRef;
    if (store != null && deviceId != null && removedRef != null) {
      await store.delete(deviceId: deviceId, ref: removedRef);
    }
    if (!mounted) return;
    _update(
      image
          ? _draft.copyWith(customImageRef: null)
          : _draft.copyWith(customVideoRef: null),
    );
  }

  static String _statusOf(KioskAttractMediaError error) => switch (error) {
    KioskAttractMediaError.tooLarge => 'too-large',
    KioskAttractMediaError.tooLong => 'too-long',
    KioskAttractMediaError.unsupportedPlatform => 'unsupported-platform',
    _ => 'invalid',
  };

  Future<void> _reset() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: KioskColors.sheetTop,
        title: Text(
          l10n.kioskAppearanceResetConfirm,
          style: KioskType.body(24, FontWeight.w700),
        ),
        actions: [
          TextButton(
            key: const Key('kiosk-appearance-reset-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            key: const Key('kiosk-appearance-reset-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.kioskAppearanceReset),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(kioskAppearanceProvider.notifier).resetToDefaults();
    if (!mounted) return;
    setState(() {
      _draft = ref.read(kioskAppearanceProvider);
      _saved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return _Card(
      title: l10n.kioskAppearanceSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- live preview -------------------------------------------------
          _Label(l10n.kioskAppearancePreview),
          const SizedBox(height: 10),
          _PreviewCard(draft: _draft),
          const SizedBox(height: 26),

          // ---- A. identity --------------------------------------------------
          _Label(l10n.kioskAppearanceIdentity),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LogoWell(draft: _draft),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _SmallPill(
                          key: const Key('kiosk-appearance-choose-logo'),
                          label: l10n.kioskAppearanceChooseLogo,
                          onTap: _chooseLogo,
                        ),
                        const SizedBox(width: 12),
                        if (_draft.logoOverridePngB64 != null)
                          _SmallPill(
                            key: const Key('kiosk-appearance-remove-logo'),
                            label: l10n.kioskAppearanceRemoveLogo,
                            onTap: () => _update(
                              _draft.copyWith(logoOverridePngB64: null),
                            ),
                          ),
                      ],
                    ),
                    if (_logoError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _logoError == 'unsupported'
                              ? l10n.kioskAppearanceLogoUnsupported
                              : l10n.kioskAppearanceLogoInvalid,
                          key: const Key('kiosk-appearance-logo-error'),
                          style: KioskType.body(
                            18,
                            FontWeight.w600,
                            color: KioskColors.dangerSoft,
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    _Field(
                      fieldKey: const Key('kiosk-appearance-name'),
                      label: l10n.kioskAppearanceDisplayName,
                      value: _draft.restaurantDisplayName,
                      maxLength: KioskAppearanceLimits.name,
                      onChanged: (v) =>
                          _update(_draft.copyWith(restaurantDisplayName: v)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),

          // ---- B. wordmark --------------------------------------------------
          _Label(l10n.kioskAppearanceWordmark),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Field(
                  fieldKey: const Key('kiosk-appearance-title-primary'),
                  label: l10n.kioskAppearanceTitlePrimary,
                  value: _draft.brandTitlePrimary,
                  maxLength: KioskAppearanceLimits.title,
                  onChanged: (v) =>
                      _update(_draft.copyWith(brandTitlePrimary: v)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _Field(
                  fieldKey: const Key('kiosk-appearance-title-accent'),
                  label: l10n.kioskAppearanceTitleAccent,
                  value: _draft.brandTitleAccent,
                  maxLength: KioskAppearanceLimits.accent,
                  onChanged: (v) =>
                      _update(_draft.copyWith(brandTitleAccent: v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ColorRow(
            label: l10n.kioskAppearancePrimaryColor,
            hexHint: l10n.kioskAppearanceHexHint,
            value: _draft.brandPrimaryColor,
            keyPrefix: 'kiosk-appearance-primary',
            onChanged: (c) => _update(_draft.copyWith(brandPrimaryColor: c)),
          ),
          const SizedBox(height: 12),
          _ColorRow(
            label: l10n.kioskAppearanceAccentColor,
            hexHint: l10n.kioskAppearanceHexHint,
            value: _draft.brandAccentColor,
            keyPrefix: 'kiosk-appearance-accent',
            onChanged: (c) => _update(_draft.copyWith(brandAccentColor: c)),
          ),
          const SizedBox(height: 26),

          // ---- C/D. localized copy ------------------------------------------
          Row(
            children: [
              _Label(l10n.kioskAppearanceMenuCopy),
              const Spacer(),
              for (final lang in const ['ar', 'he', 'en'])
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child: _SmallPill(
                    key: Key('kiosk-appearance-lang-$lang'),
                    label: lang.toUpperCase(),
                    active: _copyLang == lang,
                    onTap: () => setState(() => _copyLang = lang),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _Field(
            fieldKey: Key('kiosk-appearance-tagline-$_copyLang'),
            label: l10n.kioskAppearanceTagline,
            value: _draft.tagline.of2(_copyLang),
            maxLength: KioskAppearanceLimits.tagline,
            onChanged: (v) => _update(
              _draft.copyWith(tagline: _draft.tagline.withLang(_copyLang, v)),
            ),
          ),
          const SizedBox(height: 12),
          _Field(
            fieldKey: Key('kiosk-appearance-headline-$_copyLang'),
            label: l10n.kioskAppearanceMenuHeadline,
            value: _draft.menuHeadline.of2(_copyLang),
            maxLength: KioskAppearanceLimits.headline,
            onChanged: (v) => _update(
              _draft.copyWith(
                menuHeadline: _draft.menuHeadline.withLang(_copyLang, v),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _Field(
            fieldKey: Key('kiosk-appearance-subtitle-$_copyLang'),
            label: l10n.kioskAppearanceMenuSubtitle,
            value: _draft.menuSubtitle.of2(_copyLang),
            maxLength: KioskAppearanceLimits.subtitle,
            onChanged: (v) => _update(
              _draft.copyWith(
                menuSubtitle: _draft.menuSubtitle.withLang(_copyLang, v),
              ),
            ),
          ),
          const SizedBox(height: 26),

          // ---- E. attract media (KIOSK-001-103: curated modes) ---------------
          _Label(l10n.kioskAppearanceMedia),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final mode in KioskAttractMediaMode.values)
                _SmallPill(
                  key: Key('kiosk-attract-mode-${mode.wire}'),
                  label: switch (mode) {
                    KioskAttractMediaMode.selectedMenuPhotos =>
                      l10n.kioskAttractModeMenuPhotos,
                    KioskAttractMediaMode.customImage =>
                      l10n.kioskAttractModeImage,
                    KioskAttractMediaMode.customVideo =>
                      l10n.kioskAttractModeVideo,
                  },
                  active: _draft.attractMediaMode == mode,
                  onTap: () => _update(_draft.copyWith(attractMediaMode: mode)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          switch (_draft.attractMediaMode) {
            KioskAttractMediaMode.selectedMenuPhotos => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${l10n.kioskAppearanceInterval}:',
                      style: KioskType.body(
                        20,
                        FontWeight.w600,
                        color: KioskColors.textSoft,
                      ),
                    ),
                    for (final seconds in KioskAppearanceLimits.intervalChoices)
                      _SmallPill(
                        key: Key('kiosk-appearance-interval-$seconds'),
                        label: '${seconds}s',
                        active: _draft.attractIntervalSeconds == seconds,
                        onTap: () => _update(
                          _draft.copyWith(attractIntervalSeconds: seconds),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _SmallPill(
                      key: const Key('kiosk-featured-pick'),
                      label: l10n.kioskFeaturedPickAction,
                      active: false,
                      onTap: _pickFeatured,
                    ),
                    Text(
                      _draft.featuredMenuItemIds.isEmpty
                          ? l10n.kioskFeaturedAutoNote
                          : '${_draft.featuredMenuItemIds.length}'
                                '/${KioskAppearanceLimits.featuredMax}',
                      key: const Key('kiosk-featured-summary'),
                      style: KioskType.body(
                        19,
                        FontWeight.w600,
                        color: KioskColors.textMuted,
                      ),
                    ),
                    if (_draft.featuredMenuItemIds.isNotEmpty)
                      _SmallPill(
                        key: const Key('kiosk-featured-clear'),
                        label: l10n.kioskFeaturedClear,
                        active: false,
                        onTap: () => _update(
                          _draft.copyWith(
                            featuredMenuItemIds: const <String>[],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            KioskAttractMediaMode.customImage => _CustomMediaControls(
              kindKey: 'image',
              supported: _mediaStore?.supported ?? false,
              hasMedia: _draft.customImageRef != null,
              chooseLabel: l10n.kioskAttractChooseImage,
              onChoose: _chooseCustomImage,
              onRemove: () => _removeCustomMedia(image: true),
              statusKey: _mediaStatusKey,
              l10n: l10n,
            ),
            KioskAttractMediaMode.customVideo => _CustomMediaControls(
              kindKey: 'video',
              supported: _mediaStore?.supported ?? false,
              hasMedia: _draft.customVideoRef != null,
              chooseLabel: l10n.kioskAttractChooseVideo,
              onChoose: _chooseCustomVideo,
              onRemove: () => _removeCustomMedia(image: false),
              statusKey: _mediaStatusKey,
              l10n: l10n,
            ),
          },
          const SizedBox(height: 30),

          // ---- G. GLOBAL device UI theme (KIOSK-001-107) ---------------------
          // A clearly separate section from the wordmark/name colors above:
          // this pair recolors the WHOLE kiosk chrome. Draft-only until the
          // section's Save (the kiosk settings idiom: preview + Apply).
          _Label(l10n.kioskUiThemeSection),
          const SizedBox(height: 6),
          Text(
            l10n.kioskUiThemeExplainer,
            style: KioskType.body(
              19,
              FontWeight.w500,
              color: KioskColors.textMuted,
            ),
          ),
          Text(
            l10n.kioskUiThemeVsWordmarkNote,
            style: KioskType.body(
              17,
              FontWeight.w500,
              color: KioskColors.textGhost,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final preset in KioskThemePair.presets)
                _ThemePresetCard(
                  key: Key('kiosk-uitheme-${preset.wire}'),
                  pair: preset,
                  label: switch (preset.wire) {
                    'navy_ember' => l10n.kioskUiThemePresetNavy,
                    'forest_ember' => l10n.kioskUiThemePresetForest,
                    'aubergine_brick' => l10n.kioskUiThemePresetAubergine,
                    _ => l10n.kioskUiThemePresetCharcoal,
                  },
                  selected: _draft.uiThemeWire == preset.wire,
                  onTap: () =>
                      _update(_draft.copyWith(uiThemeWire: preset.wire)),
                ),
              _ThemePresetCard(
                key: const Key('kiosk-uitheme-custom'),
                pair: _draftThemePair.isCustom
                    ? _draftThemePair
                    : KioskThemePair.navyEmber,
                label: l10n.kioskUiThemeCustom,
                selected: _draftThemePair.isCustom,
                customBadge: true,
                onTap: _editCustomTheme,
              ),
            ],
          ),
          const SizedBox(height: 14),
          KioskThemePreview(pair: _draftThemePair),
          const SizedBox(height: 12),
          if (_draft.uiThemeWire != 'navy_ember')
            _SmallPill(
              key: const Key('kiosk-uitheme-reset'),
              label: l10n.kioskUiThemeReset,
              active: false,
              onTap: () => _update(_draft.copyWith(uiThemeWire: 'navy_ember')),
            ),
          const SizedBox(height: 26),

          // ---- F. save / reset ----------------------------------------------
          // Wrap, not Row: wide-locale measurement (e.g. the EN test font)
          // must fold instead of overflowing; real fonts stay on one line.
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              KioskAccentPill(
                key: const Key('kiosk-appearance-save'),
                onTap: _save,
                height: 84,
                horizontalPadding: 46,
                child: Text(
                  l10n.kioskAppearanceSave,
                  style: KioskType.body(
                    23,
                    FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              if (_saved)
                Text(
                  l10n.kioskAppearanceSaved,
                  key: const Key('kiosk-appearance-saved'),
                  style: KioskType.body(
                    20,
                    FontWeight.w700,
                    color: KioskColors.successTop,
                  ),
                ),
              _SmallPill(
                key: const Key('kiosk-appearance-reset'),
                label: l10n.kioskAppearanceReset,
                onTap: _reset,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

extension on KioskLocalizedCopy {
  /// Raw per-language value for EDITING (no fallback chain — the editor must
  /// show what is stored for the selected tab, not a borrowed translation).
  String of2(String lang) => switch (lang) {
    'ar' => ar,
    'he' => he,
    _ => en,
  };
}

/// Validated picked bytes → the bounded stored representation.
String base64EncodeBytes(List<int> bytes) => base64Encode(bytes);

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.draft});
  final KioskAppearanceSettings draft;

  @override
  Widget build(BuildContext context) {
    final logo = draft.logoOverrideBytes;
    return Container(
      key: const Key('kiosk-appearance-preview'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [KioskColors.canvasTop, KioskColors.canvasBottom],
        ),
        border: Border.all(color: KioskColors.glass(.14), width: 1.5),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KioskColors.canvasTint(0xB8 / 255),
              border: Border.all(color: KioskColors.ring, width: 3),
            ),
            clipBehavior: Clip.antiAlias,
            child: logo != null
                ? Image.memory(logo, fit: BoxFit.cover)
                : Center(
                    child: Text(
                      draft.monogram,
                      style: kioskBrandTitleStyle(
                        draft.monogram,
                        30,
                        color: Colors.white,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: draft.brandTitlePrimary,
                    style: kioskBrandTitleStyle(
                      draft.brandTitlePrimary,
                      44,
                      color: draft.brandPrimaryColor,
                    ),
                    children: [
                      if (draft.brandTitleAccent.isNotEmpty)
                        TextSpan(
                          text: draft.brandTitleAccent,
                          style: TextStyle(color: draft.brandAccentColor),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (draft.restaurantDisplayName.isNotEmpty)
                  Text(
                    draft.restaurantDisplayName.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KioskType.body(
                      19,
                      FontWeight.w700,
                      color: KioskColors.textSoft,
                      letterSpacing:
                          kioskLatinDisplayFits(draft.restaurantDisplayName)
                          ? 3
                          : 0,
                    ),
                  ),
                if (!draft.tagline.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      draft.tagline.of('ar'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KioskType.body(
                        17,
                        FontWeight.w500,
                        color: KioskColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoWell extends StatelessWidget {
  const _LogoWell({required this.draft});
  final KioskAppearanceSettings draft;

  @override
  Widget build(BuildContext context) {
    final logo = draft.logoOverrideBytes;
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: KioskColors.imageWell,
        border: Border.all(color: KioskColors.ring, width: 3),
      ),
      clipBehavior: Clip.antiAlias,
      child: logo != null
          ? Image.memory(logo, fit: BoxFit.cover)
          : Center(
              child: Text(
                draft.monogram,
                style: kioskBrandTitleStyle(
                  draft.monogram,
                  40,
                  color: Colors.white,
                ),
              ),
            ),
    );
  }
}

class _ColorRow extends StatefulWidget {
  const _ColorRow({
    required this.label,
    required this.hexHint,
    required this.value,
    required this.keyPrefix,
    required this.onChanged,
  });
  final String label;
  final String hexHint;
  final Color value;
  final String keyPrefix;
  final ValueChanged<Color> onChanged;

  @override
  State<_ColorRow> createState() => _ColorRowState();
}

class _ColorRowState extends State<_ColorRow> {
  bool _hexInvalid = false;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 10,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SizedBox(
        width: 170,
        child: Text(
          widget.label,
          style: KioskType.body(
            20,
            FontWeight.w600,
            color: KioskColors.textSoft,
          ),
        ),
      ),
      for (final color in kKioskBrandPalette)
        Padding(
          padding: EdgeInsetsDirectional.zero,
          child: GestureDetector(
            key: Key(
              '${widget.keyPrefix}-swatch-'
              '${color.toARGB32().toRadixString(16)}',
            ),
            onTap: () => widget.onChanged(color),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(
                  color: widget.value.toARGB32() == color.toARGB32()
                      ? KioskColors.ring
                      : KioskColors.glass(.2),
                  width: widget.value.toARGB32() == color.toARGB32()
                      ? 3.5
                      : 1.5,
                ),
              ),
            ),
          ),
        ),
      const SizedBox(width: 14),
      SizedBox(
        width: 190,
        height: 64,
        child: TextFormField(
          key: Key('${widget.keyPrefix}-hex'),
          style: KioskType.body(18, FontWeight.w600),
          decoration: InputDecoration(
            hintText: widget.hexHint,
            hintStyle: KioskType.body(
              18,
              FontWeight.w500,
              color: KioskColors.textFaint,
            ),
            filled: true,
            fillColor: KioskColors.glass(.05),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: _hexInvalid
                    ? KioskColors.danger
                    : KioskColors.glass(.14),
                width: 2,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: KioskColors.accentTop, width: 2),
            ),
          ),
          onFieldSubmitted: (raw) {
            final parsed = parseKioskHexColor(raw);
            setState(() => _hexInvalid = parsed == null && raw.isNotEmpty);
            if (parsed != null) widget.onChanged(parsed);
          },
        ),
      ),
    ],
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.maxLength,
    required this.onChanged,
  });
  final Key fieldKey;
  final String label;
  final String value;
  final int maxLength;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: fieldKey,
    initialValue: value,
    maxLength: maxLength,
    style: KioskType.body(21, FontWeight.w600),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: KioskType.body(
        18,
        FontWeight.w600,
        color: KioskColors.textMuted,
      ),
      counterStyle: KioskType.body(
        14,
        FontWeight.w500,
        color: KioskColors.textFaint,
      ),
      filled: true,
      fillColor: KioskColors.glass(.05),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: KioskColors.glass(.14), width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: KioskColors.accentTop, width: 2),
      ),
    ),
    onChanged: (v) => onChanged(v.trim()),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: KioskType.body(24, FontWeight.w800));
}

class _SmallPill extends StatelessWidget {
  const _SmallPill({
    super.key,
    required this.label,
    required this.onTap,
    this.active = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => KioskPressable(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        gradient: active ? kioskAccentGradient : null,
        color: active ? null : KioskColors.glass(.06),
        border: Border.all(
          color: active ? Colors.transparent : KioskColors.glass(.16),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: KioskType.body(19, FontWeight.w700)),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(44, 24, 44, 24),
    padding: const EdgeInsets.fromLTRB(34, 30, 34, 34),
    decoration: BoxDecoration(
      color: KioskColors.cardGlass,
      border: Border.all(color: KioskColors.glass(.12), width: 1.5),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: KioskType.body(28, FontWeight.w800)),
        const SizedBox(height: 20),
        child,
      ],
    ),
  );
}

/// KIOSK-001-103 §5/§6 — choose/remove controls for ONE custom attract image
/// or video. On web the store is honestly unsupported: the pickers hide and
/// the installed-device-only note renders instead.
class _CustomMediaControls extends StatelessWidget {
  const _CustomMediaControls({
    required this.kindKey,
    required this.supported,
    required this.hasMedia,
    required this.chooseLabel,
    required this.onChoose,
    required this.onRemove,
    required this.statusKey,
    required this.l10n,
  });

  final String kindKey;
  final bool supported;
  final bool hasMedia;
  final String chooseLabel;
  final VoidCallback onChoose;
  final VoidCallback onRemove;
  final String? statusKey;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    if (!supported) {
      return Text(
        l10n.kioskAttractMediaWebOnlyNote,
        key: Key('kiosk-attract-$kindKey-unsupported'),
        style: KioskType.body(
          19,
          FontWeight.w500,
          color: KioskColors.textMuted,
        ),
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _SmallPill(
          key: Key('kiosk-attract-$kindKey-choose'),
          label: chooseLabel,
          active: false,
          onTap: onChoose,
        ),
        if (hasMedia) ...[
          Text(
            l10n.kioskAttractMediaSet,
            key: Key('kiosk-attract-$kindKey-set'),
            style: KioskType.body(
              19,
              FontWeight.w600,
              color: const Color(0xFF4ADE80),
            ),
          ),
          _SmallPill(
            key: Key('kiosk-attract-$kindKey-remove'),
            label: l10n.kioskAppearanceRemoveLogo,
            active: false,
            onTap: onRemove,
          ),
        ],
        if (statusKey != null)
          Text(
            switch (statusKey!) {
              'too-large' => l10n.kioskAttractMediaTooLarge,
              'too-long' => l10n.kioskAttractMediaTooLong,
              _ => l10n.kioskAttractMediaInvalid,
            },
            key: Key('kiosk-attract-$kindKey-error'),
            style: KioskType.body(
              19,
              FontWeight.w600,
              color: const Color(0xFFFFB020),
            ),
          ),
      ],
    );
  }
}

/// KIOSK-001-107 — one preset pair card: both colors visible, the selected
/// state carries a ring AND a check (never color-only).
class _ThemePresetCard extends StatelessWidget {
  const _ThemePresetCard({
    super.key,
    required this.pair,
    required this.label,
    required this.selected,
    required this.onTap,
    this.customBadge = false,
  });

  final KioskThemePair pair;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool customBadge;

  @override
  Widget build(BuildContext context) => KioskPressable(
    onTap: onTap,
    child: Container(
      width: 208,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KioskColors.glass(.05),
        border: Border.all(
          color: selected ? KioskColors.ring : KioskColors.glass(.16),
          width: selected ? 3 : 1.5,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [pair.structuralCanvasTop, pair.structuralPanel],
                    ),
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(10),
                    ),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: customBadge
                      ? const Center(
                          child: Icon(
                            Icons.palette_outlined,
                            size: 20,
                            color: Colors.white70,
                          ),
                        )
                      : null,
                ),
              ),
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [pair.actionHi, pair.actionDeep],
                    ),
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KioskType.body(17, FontWeight.w700),
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle,
                  key: const Key('kiosk-uitheme-selected-check'),
                  size: 22,
                  color: KioskColors.ring,
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
