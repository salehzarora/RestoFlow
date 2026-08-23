import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kiosk_appearance.dart';
import '../data/kiosk_fixtures.dart';
import '../design/kiosk_theme.dart';
import '../state/kiosk_live_runtime.dart';
import '../widgets/kiosk_chrome.dart';

/// KIOSK-001-103 §4 — the FULL-MENU featured-photo picker.
///
/// The operator explicitly chooses which 4–8 live products headline the
/// attract screen: the whole live menu in a grid (photo + name + category),
/// category filter chips, name search, an order-numbered selection capped at
/// [KioskAppearanceLimits.featuredMax], and a reorderable selected strip.
/// When the entire menu has fewer than [KioskAppearanceLimits.featuredMin]
/// usable photos, saving all usable ones is allowed with an honest warning.
/// Presentation only — menu data is never modified; stored output is stable
/// item IDS in the chosen order (never paths or signed URLs).
class KioskFeaturedPickerDialog extends ConsumerStatefulWidget {
  const KioskFeaturedPickerDialog({super.key, required this.initial});

  final List<String> initial;

  @override
  ConsumerState<KioskFeaturedPickerDialog> createState() =>
      _KioskFeaturedPickerDialogState();
}

class _KioskFeaturedPickerDialogState
    extends ConsumerState<KioskFeaturedPickerDialog> {
  late final List<String> _selected = [...widget.initial];
  String _query = '';
  String? _categoryId;
  bool _capFlash = false;

  bool _usable(KioskFixtureItem item, Map<String, String> urls) =>
      item.available &&
      item.imagePath != null &&
      urls.containsKey(item.imagePath);

  void _toggle(String id) {
    setState(() {
      _capFlash = false;
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else if (_selected.length >= KioskAppearanceLimits.featuredMax) {
        _capFlash = true; // the 9th pick is refused, visibly
      } else {
        _selected.add(id);
      }
    });
  }

  void _move(String id, int delta) {
    final index = _selected.indexOf(id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= _selected.length) return;
    setState(() {
      _selected.removeAt(index);
      _selected.insert(target, id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final live = ref.watch(kioskLiveProvider);
    final menu = live.menu;
    final urls = live.imageUrls;
    final lang = Localizations.localeOf(context).languageCode;

    final categories = menu?.categories ?? const <KioskFixtureCategory>[];
    final itemsById = <String, KioskFixtureItem>{
      for (final category in categories)
        for (final item in category.items) item.id: item,
    };
    final categoryOf = <String, KioskFixtureCategory>{
      for (final category in categories)
        for (final item in category.items) item.id: category,
    };
    final usableTotal = itemsById.values.where((i) => _usable(i, urls)).length;
    final fewUsable = usableTotal < KioskAppearanceLimits.featuredMin;
    // §3 save rule: a normal menu requires an explicit 4–8; a menu with
    // fewer than 4 usable photos may save ALL its usable ones (>=1).
    final saveEnabled = fewUsable
        ? _selected.isNotEmpty && _selected.length <= usableTotal
        : _selected.length >= KioskAppearanceLimits.featuredMin &&
              _selected.length <= KioskAppearanceLimits.featuredMax;

    final query = _query.trim().toLowerCase();
    final visible = [
      for (final category in categories)
        if (_categoryId == null || category.id == _categoryId)
          for (final item in category.items)
            if (query.isEmpty ||
                item.name.of(lang).toLowerCase().contains(query) ||
                item.name.en.toLowerCase().contains(query))
              item,
    ];

    return Dialog(
      backgroundColor: KioskColors.sheetBottom,
      insetPadding: const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.kioskFeaturedTitle,
                    style: KioskType.body(28, FontWeight.w800),
                  ),
                ),
                Text(
                  '${_selected.length}/${KioskAppearanceLimits.featuredMax}',
                  key: const Key('kiosk-featured-counter'),
                  style: KioskType.body(
                    24,
                    FontWeight.w800,
                    color: _capFlash
                        ? const Color(0xFFF87171)
                        : KioskColors.accentTop,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              fewUsable ? l10n.kioskFeaturedFewWarning : l10n.kioskFeaturedHint,
              key: Key(
                fewUsable
                    ? 'kiosk-featured-few-warning'
                    : 'kiosk-featured-hint',
              ),
              style: KioskType.body(
                18,
                FontWeight.w500,
                color: fewUsable
                    ? const Color(0xFFFFB020)
                    : KioskColors.textMuted,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('kiosk-featured-search'),
              style: KioskType.body(20, FontWeight.w600),
              decoration: InputDecoration(
                labelText: l10n.kioskFeaturedSearch,
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: _CategoryChip(
                      key: const Key('kiosk-featured-cat-all'),
                      label: l10n.kioskFeaturedAllCategories,
                      active: _categoryId == null,
                      onTap: () => setState(() => _categoryId = null),
                    ),
                  ),
                  for (final category in categories)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: _CategoryChip(
                        key: Key('kiosk-featured-cat-${category.id}'),
                        label: category.name.of(lang),
                        active: _categoryId == category.id,
                        onTap: () => setState(() => _categoryId = category.id),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: .92,
                ),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final item = visible[index];
                  final usable = _usable(item, urls);
                  final order = _selected.indexOf(item.id);
                  return _ItemTile(
                    key: Key('kiosk-featured-item-${item.id}'),
                    item: item,
                    lang: lang,
                    categoryName: categoryOf[item.id]?.name.of(lang) ?? '',
                    url: item.imagePath == null ? null : urls[item.imagePath],
                    usable: usable,
                    order: order < 0 ? null : order + 1,
                    noPhotoLabel: l10n.kioskFeaturedNoPhoto,
                    onTap: usable ? () => _toggle(item.id) : null,
                  );
                },
              ),
            ),
            if (_selected.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 58,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final id in _selected)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: _SelectedChip(
                          key: Key('kiosk-featured-strip-$id'),
                          label: itemsById[id]?.name.of(lang) ?? id,
                          stale: !_usable(
                            itemsById[id] ??
                                const KioskFixtureItem(
                                  id: '',
                                  name: KioskText3.same(''),
                                  description: KioskText3.same(''),
                                  basePriceMinor: 0,
                                  groupIds: [],
                                  available: false,
                                ),
                            urls,
                          ),
                          staleLabel: l10n.kioskFeaturedStale,
                          onBack: () => _move(id, -1),
                          onForward: () => _move(id, 1),
                          onRemove: () => _toggle(id),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                KioskAccentPill(
                  key: const Key('kiosk-featured-save'),
                  onTap: saveEnabled
                      ? () => Navigator.of(
                          context,
                        ).pop(List<String>.unmodifiable(_selected))
                      : null,
                  height: 72,
                  horizontalPadding: 38,
                  child: Text(
                    l10n.kioskAppearanceSave,
                    style: KioskType.body(
                      21,
                      FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                TextButton(
                  key: const Key('kiosk-featured-cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    l10n.kioskCancel,
                    style: KioskType.body(
                      20,
                      FontWeight.w600,
                      color: KioskColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KioskPressable(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        color: active ? KioskColors.accentTop : KioskColors.glass(.07),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: KioskType.body(
          18,
          FontWeight.w700,
          color: active ? Colors.white : KioskColors.textSoft,
        ),
      ),
    ),
  );
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    super.key,
    required this.item,
    required this.lang,
    required this.categoryName,
    required this.url,
    required this.usable,
    required this.order,
    required this.noPhotoLabel,
    required this.onTap,
  });

  final KioskFixtureItem item;
  final String lang;
  final String categoryName;
  final String? url;
  final bool usable;
  final int? order;
  final String noPhotoLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final selected = order != null;
    return KioskPressable(
      onTap: onTap,
      child: Opacity(
        opacity: usable ? 1 : .38,
        child: Container(
          decoration: BoxDecoration(
            color: KioskColors.glass(.05),
            border: Border.all(
              color: selected ? KioskColors.accentTop : KioskColors.glass(.14),
              width: selected ? 3 : 1.5,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (url != null)
                      Image.network(
                        url!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            ColoredBox(color: KioskColors.canvasBottom),
                      )
                    else
                      Center(
                        child: Text(
                          noPhotoLabel,
                          style: KioskType.body(
                            15,
                            FontWeight.w600,
                            color: KioskColors.textGhost,
                          ),
                        ),
                      ),
                    if (selected)
                      PositionedDirectional(
                        top: 8,
                        end: 8,
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: KioskColors.accentTop,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$order',
                            style: KioskType.body(
                              19,
                              FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name.of(lang),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KioskType.body(18, FontWeight.w700),
                    ),
                    Text(
                      categoryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KioskType.body(
                        15,
                        FontWeight.w500,
                        color: KioskColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedChip extends StatelessWidget {
  const _SelectedChip({
    super.key,
    required this.label,
    required this.stale,
    required this.staleLabel,
    required this.onBack,
    required this.onForward,
    required this.onRemove,
  });

  final String label;
  final bool stale;
  final String staleLabel;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsetsDirectional.only(start: 16, end: 6),
    decoration: BoxDecoration(
      color: KioskColors.glass(.07),
      border: Border.all(
        color: stale ? const Color(0xFFFFB020) : KioskColors.glass(.16),
      ),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          stale ? '$label · $staleLabel' : label,
          style: KioskType.body(
            17,
            FontWeight.w600,
            color: stale ? const Color(0xFFFFB020) : KioskColors.textSoft,
          ),
        ),
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.chevron_left, color: Colors.white70),
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          onPressed: onForward,
          icon: const Icon(Icons.chevron_right, color: Colors.white70),
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          onPressed: onRemove,
          icon: const Icon(Icons.close, color: Colors.white70),
          visualDensity: VisualDensity.compact,
        ),
      ],
    ),
  );
}
