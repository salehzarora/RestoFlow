import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kiosk_fixtures.dart';
import '../data/kiosk_menu_data.dart';
import '../design/kiosk_theme.dart';
import '../state/kiosk_flow_controller.dart';
import '../widgets/kiosk_chrome.dart';

/// 05 · Item customization sheet — rises 380ms over a scrim; the product is a
/// 380px circular hero overlapping the sheet edge with an 8px orange rim.
/// Content order is fixed law: name → base price → quantity → REQUIRED groups
/// first (full-width radio rows, green "Included" / orange "+₪15") → optional
/// add-ons (2-col toggles, "Up to N") → removals → kitchen note. The footer
/// carries the price-math line and ONE CTA with the live line total; unmet
/// required groups grey the CTA and a blocked tap shakes a red hint naming
/// the missing group while tinting its badge red.
class KioskItemSheet extends ConsumerWidget {
  const KioskItemSheet({super.key});

  static String groupLabel(AppLocalizations l10n, String groupId) =>
      switch (groupId) {
        'weight' => l10n.kioskGroupWeight,
        'side' => l10n.kioskGroupSide,
        'drink' => l10n.kioskGroupDrink,
        'sauce' => l10n.kioskGroupSauce,
        'addons' => l10n.kioskGroupAddons,
        _ => l10n.kioskGroupRemovals,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(kioskFlowProvider);
    final controller = ref.read(kioskFlowProvider.notifier);
    final draft = state.draft;
    if (draft == null) return const SizedBox.shrink();
    final menu = ref.watch(kioskMenuDataProvider);
    final item = menu.tryItem(draft.itemId);
    // A live refresh can remove the drafted item mid-sheet — close honestly.
    if (item == null) return const SizedBox.shrink();
    final lang = state.lang;
    final unmet = draft.unmetRequiredIn(menu);

    // Price-math line: base + every positive selected delta (V2 dBreak).
    final parts = <String>[kioskFormatMinor(item.basePriceMinor, lang)];
    for (final gid in item.groupIds) {
      final group = menu.group(gid);
      if (group == null) continue;
      for (final oid in draft.selected[gid] ?? const <String>[]) {
        for (final o in group.options) {
          if (o.id == oid && o.priceDeltaMinor > 0) {
            parts.add(kioskFormatDeltaMinor(o.priceDeltaMinor, lang));
          }
        }
      }
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: controller.closeItemSheet,
            child: const ColoredBox(color: KioskColors.scrim),
          ),
        ),
        Positioned.fill(
          top: 210,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 1, end: 0),
            duration: KioskMotion.sheetRise,
            curve: KioskMotion.curve,
            builder: (context, t, child) => Transform.translate(
              offset: Offset(0, t * 0.06 * 1710),
              child: Opacity(opacity: 1 - t, child: child),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: kioskSheetGradient,
                    border: Border(
                      top: BorderSide(
                        color: KioskColors.glass(.13),
                        width: 1.5,
                      ),
                      left: BorderSide(
                        color: KioskColors.glass(.13),
                        width: 1.5,
                      ),
                      right: BorderSide(
                        color: KioskColors.glass(.13),
                        width: 1.5,
                      ),
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(44),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(52, 250, 52, 30),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Column(
                                children: [
                                  Text(
                                    item.name.of(lang),
                                    textAlign: TextAlign.center,
                                    style: KioskType.display(
                                      state.rtl,
                                      52,
                                      height: 1.05,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 640,
                                    ),
                                    child: Text(
                                      item.description.of(lang),
                                      textAlign: TextAlign.center,
                                      style: KioskType.body(
                                        23,
                                        FontWeight.w500,
                                        color: KioskColors.textMuted,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        context.money(item.basePriceMinor),
                                        textDirection: TextDirection.ltr,
                                        style: KioskType.body(
                                          42,
                                          FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        l10n.kioskBasePrice,
                                        style: KioskType.body(
                                          20,
                                          FontWeight.w600,
                                          color: KioskColors.textFaint,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _QtyButton(
                                        key: const Key('kiosk-qty-dec'),
                                        icon: Icons.remove,
                                        filled: false,
                                        onTap: () =>
                                            controller.setDraftQuantity(
                                              draft.quantity - 1,
                                            ),
                                      ),
                                      SizedBox(
                                        width: 96,
                                        child: Text(
                                          '${draft.quantity}',
                                          textAlign: TextAlign.center,
                                          textDirection: TextDirection.ltr,
                                          style: KioskType.body(
                                            40,
                                            FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      _QtyButton(
                                        key: const Key('kiosk-qty-inc'),
                                        icon: Icons.add,
                                        filled: true,
                                        onTap: () =>
                                            controller.setDraftQuantity(
                                              draft.quantity + 1,
                                            ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 34),
                              for (final gid in item.groupIds)
                                if (menu.group(gid) case final group?) ...[
                                  _GroupSection(
                                    group: group,
                                    draft: draft,
                                    lang: lang,
                                    showError:
                                        draft.showRequiredError &&
                                        unmet.contains(gid),
                                    onToggle: (oid) =>
                                        controller.toggleOption(gid, oid),
                                  ),
                                  const SizedBox(height: 34),
                                ],
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text.rich(
                                    TextSpan(
                                      text: l10n.kioskKitchenNote,
                                      children: [
                                        TextSpan(
                                          text: ' · ${l10n.kioskOptional}',
                                          style: KioskType.body(
                                            20,
                                            FontWeight.w600,
                                            color: KioskColors.textFaint,
                                          ),
                                        ),
                                      ],
                                    ),
                                    style: KioskType.body(27, FontWeight.w800),
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    key: const Key('kiosk-note-field'),
                                    initialValue: draft.note,
                                    onChanged: controller.setDraftNote,
                                    maxLines: 2,
                                    style: KioskType.body(22, FontWeight.w500),
                                    decoration: InputDecoration(
                                      hintText: l10n.kioskKitchenNoteHint,
                                      hintStyle: KioskType.body(
                                        22,
                                        FontWeight.w500,
                                        color: KioskColors.textFaint,
                                      ),
                                      filled: true,
                                      fillColor: KioskColors.glass(.05),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 24,
                                            vertical: 20,
                                          ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        borderSide: BorderSide(
                                          color: KioskColors.glass(.14),
                                          width: 2,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        borderSide: const BorderSide(
                                          color: KioskColors.accentTop,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Footer: error line, price math, one CTA.
                      Container(
                        padding: const EdgeInsets.fromLTRB(52, 24, 52, 40),
                        decoration: BoxDecoration(
                          color: const Color(0xB3080F1C),
                          border: Border(
                            top: BorderSide(
                              color: KioskColors.glass(.09),
                              width: 1.5,
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            if (draft.showRequiredError && unmet.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _ShakeOnRebuild(
                                  child: Text(
                                    l10n.kioskPleaseChoose(
                                      unmet
                                          .map((g) => groupLabel(l10n, g))
                                          .join(' · '),
                                    ),
                                    key: const Key('kiosk-required-error'),
                                    textAlign: TextAlign.center,
                                    style: KioskType.body(
                                      21,
                                      FontWeight.w700,
                                      color: KioskColors.dangerSoft,
                                    ),
                                  ),
                                ),
                              ),
                            if (parts.length > 1)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  parts.join('  +  '),
                                  textDirection: TextDirection.ltr,
                                  style: KioskType.body(
                                    20,
                                    FontWeight.w600,
                                    color: KioskColors.textFaint,
                                  ),
                                ),
                              ),
                            KioskPressable(
                              onTap: controller.submitDraft,
                              pressedScale: .98,
                              child: Container(
                                key: const Key('kiosk-item-cta'),
                                height: 118,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  gradient: unmet.isEmpty
                                      ? kioskAccentGradient
                                      : null,
                                  color: unmet.isEmpty
                                      ? null
                                      : KioskColors.glass(.08),
                                  borderRadius: BorderRadius.circular(999),
                                  boxShadow: unmet.isEmpty
                                      ? [
                                          BoxShadow(
                                            color: KioskColors.ring.withValues(
                                              alpha: .4,
                                            ),
                                            blurRadius: 44,
                                            offset: const Offset(0, 16),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Text.rich(
                                  TextSpan(
                                    text:
                                        '${(draft.editingLineId != null ? l10n.kioskUpdateItem : l10n.kioskAddToOrder).toUpperCase()} · ',
                                    children: [
                                      TextSpan(
                                        text: context.money(
                                          draft.totalMinorIn(menu),
                                        ),
                                      ),
                                    ],
                                  ),
                                  style: KioskType.body(
                                    30,
                                    FontWeight.w900,
                                    color: unmet.isEmpty
                                        ? Colors.white
                                        : KioskColors.textDisabled,
                                    letterSpacing: .5,
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
                // Circular hero overlapping the top edge (V2: 380px, top −150).
                Positioned(
                  top: -150,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 380,
                      height: 380,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: KioskColors.imageWell,
                        boxShadow: [
                          BoxShadow(
                            color: KioskColors.ring.withValues(alpha: .85),
                            spreadRadius: 8,
                          ),
                          BoxShadow(
                            color: KioskColors.ring.withValues(alpha: .35),
                            blurRadius: 80,
                          ),
                          const BoxShadow(
                            color: Color(0x99000000),
                            offset: Offset(0, 30),
                            blurRadius: 70,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: item.imageAsset != null
                          ? KioskFixtureImage(
                              asset: item.imageAsset,
                              fallback: const ColoredBox(
                                color: KioskColors.imageWell,
                              ),
                            )
                          : Center(
                              child: Text(
                                item.name.of(lang),
                                textAlign: TextAlign.center,
                                style: KioskType.body(
                                  28,
                                  FontWeight.w800,
                                  color: KioskColors.textDisabled,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                // Close ✕.
                PositionedDirectional(
                  top: 26,
                  end: 26,
                  child: KioskPressable(
                    onTap: controller.closeItemSheet,
                    child: Container(
                      key: const Key('kiosk-item-close'),
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: KioskColors.glass(.07),
                        border: Border.all(
                          color: KioskColors.glass(.16),
                          width: 1.5,
                        ),
                      ),
                      child: const Center(
                        child: Icon(Icons.close, size: 34, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({
    super.key,
    required this.icon,
    required this.filled,
    required this.onTap,
  });
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KioskPressable(
    onTap: onTap,
    child: Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: filled ? kioskAccentGradient : null,
        color: filled ? null : KioskColors.glass(.05),
        border: filled
            ? null
            : Border.all(color: KioskColors.glass(.18), width: 2),
        boxShadow: filled
            ? [
                BoxShadow(
                  color: KioskColors.ring.withValues(alpha: .4),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Center(child: Icon(icon, size: 40, color: Colors.white)),
    ),
  );
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.group,
    required this.draft,
    required this.lang,
    required this.showError,
    required this.onToggle,
  });
  final KioskFixtureGroup group;
  final KioskItemDraft draft;
  final String lang;
  final bool showError;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groupId = group.id;
    final selectedIds = draft.selected[groupId] ?? const [];
    final single = group.type == KioskGroupType.single;
    // Single-select groups render full-width rows; multi are two columns.
    final twoColumns = !single;

    final badgeText = group.isRequired
        ? '${l10n.kioskRequired} · ${l10n.kioskChooseOne}'
        : '${l10n.kioskOptional} · ${l10n.kioskUpTo(group.maxSelect ?? 99)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                // LIVE groups carry the tenant name; fixtures keep the l10n
                // heading keyed by the fixture group id.
                group.displayName?.of(lang) ??
                    KioskItemSheet.groupLabel(l10n, groupId),
                style: KioskType.body(27, FontWeight.w800),
              ),
            ),
            Container(
              key: Key('kiosk-group-badge-$groupId'),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              decoration: BoxDecoration(
                color: showError
                    ? KioskColors.danger.withValues(alpha: .16)
                    : group.isRequired
                    ? KioskColors.ring.withValues(alpha: .14)
                    : KioskColors.glass(.06),
                border: Border.all(
                  color: showError
                      ? KioskColors.danger
                      : group.isRequired
                      ? KioskColors.ring.withValues(alpha: .45)
                      : KioskColors.glass(.13),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badgeText,
                style: KioskType.body(
                  19,
                  FontWeight.w700,
                  color: showError
                      ? KioskColors.dangerSoft
                      : group.isRequired
                      ? KioskColors.accentTop
                      : KioskColors.textMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (twoColumns)
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final option in group.options)
                  SizedBox(
                    width: (constraints.maxWidth - 14) / 2,
                    child: _OptionRow(
                      option: option,
                      group: group,
                      selected: selectedIds.contains(option.id),
                      lang: lang,
                      onTap: () => onToggle(option.id),
                    ),
                  ),
              ],
            ),
          )
        else
          Column(
            children: [
              for (final option in group.options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _OptionRow(
                    option: option,
                    group: group,
                    selected: selectedIds.contains(option.id),
                    lang: lang,
                    onTap: () => onToggle(option.id),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.group,
    required this.selected,
    required this.lang,
    required this.onTap,
  });
  final KioskFixtureOption option;
  final KioskFixtureGroup group;
  final bool selected;
  final String lang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final single = group.type == KioskGroupType.single;
    final isRemoval = group.id == 'remove';
    final deltaText = option.priceDeltaMinor == 0
        ? (isRemoval ? '' : l10n.kioskIncluded)
        : kioskFormatDeltaMinor(option.priceDeltaMinor, lang);

    return KioskPressable(
      onTap: onTap,
      child: Container(
        key: Key('kiosk-option-${option.id}'),
        constraints: const BoxConstraints(minHeight: 94),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? KioskColors.ring.withValues(alpha: .15)
              : KioskColors.glass(.05),
          border: Border.all(
            color: selected ? KioskColors.ring : KioskColors.glass(.11),
            width: 2.5,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: KioskColors.ring.withValues(alpha: .22),
                    blurRadius: 26,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: single ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: single ? null : BorderRadius.circular(10),
                color: selected ? KioskColors.ring : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? KioskColors.accentTop
                      : KioskColors.glass(.3),
                  width: 3,
                ),
              ),
              child: selected
                  ? const Center(
                      child: Icon(Icons.check, size: 20, color: Colors.white),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                option.name.of(lang),
                style: KioskType.body(24, FontWeight.w700),
              ),
            ),
            if (deltaText.isNotEmpty)
              Text(
                deltaText,
                textDirection: TextDirection.ltr,
                style: KioskType.body(
                  23,
                  FontWeight.w800,
                  color: option.priceDeltaMinor == 0
                      ? KioskColors.tableFree
                      : KioskColors.accentTop,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Runs the V2 shake (±16px, 400ms) every time it is (re)built into the tree.
class _ShakeOnRebuild extends StatefulWidget {
  const _ShakeOnRebuild({required this.child});
  final Widget child;

  @override
  State<_ShakeOnRebuild> createState() => _ShakeOnRebuildState();
}

class _ShakeOnRebuildState extends State<_ShakeOnRebuild>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: KioskMotion.shake,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      final t = _controller.value;
      final dx = switch ((t * 5).floor()) {
        0 => -16.0 * (t * 5),
        1 => -16 + 32.0 * (t * 5 - 1),
        2 => 16 - 32.0 * (t * 5 - 2),
        3 => -16 + 32.0 * (t * 5 - 3),
        _ => 16 * (1 - (t * 5 - 4).clamp(0.0, 1.0)),
      };
      return Transform.translate(offset: Offset(dx, 0), child: child);
    },
    child: widget.child,
  );
}
