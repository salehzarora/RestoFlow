import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kiosk_fixtures.dart';
import '../data/kiosk_menu_data.dart';
import '../design/kiosk_theme.dart';
import '../state/kiosk_flow_controller.dart';
import '../widgets/kiosk_chrome.dart';

/// 07 · Confirmation — green success pop, "Order sent!", the fixture daily
/// number huge in orange, service/table chips, and the printed-slip facsimile
/// (the WHITE surface: brand header, dashed rules, lines with modifiers,
/// total, the rotated PAY AT COUNTER stamp, RestoFlow footer) that doubles
/// as the receipt spec. Auto-returns to attract (tick-driven); "New order"
/// resets immediately. No printer in Phase 1.
class KioskConfirmScreen extends ConsumerWidget {
  const KioskConfirmScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(kioskFlowProvider);
    final controller = ref.read(kioskFlowProvider.notifier);
    final menu = ref.watch(kioskMenuDataProvider);
    final order = state.lastOrder;
    if (order == null) return const SizedBox.shrink();
    final rtl = state.rtl;
    final lang = state.lang;
    final numberText = '#${order.number.toString().padLeft(3, '0')}';
    final serviceText = order.service == KioskServiceType.dineIn
        ? l10n.kioskDineIn
        : l10n.kioskTakeaway;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(70, 80, 70, 60),
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 550),
            curve: const Cubic(.2, 1.4, .4, 1),
            builder: (context, t, child) =>
                Transform.scale(scale: .3 + .7 * t, child: child),
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                gradient: kioskSuccessGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: KioskColors.successTop.withValues(alpha: .4),
                    blurRadius: 70,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.check_rounded, size: 84, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 26),
          Text(
            l10n.kioskOrderSent,
            textAlign: TextAlign.center,
            style: KioskType.display(rtl, 86, height: 1),
          ),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Text(
              l10n.kioskShowNumber,
              textAlign: TextAlign.center,
              style: KioskType.body(
                26,
                FontWeight.w500,
                color: KioskColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            numberText,
            key: const Key('kiosk-confirm-number'),
            textDirection: TextDirection.ltr,
            style: KioskType.display(rtl, 190, height: 1).copyWith(
              color: KioskColors.accentTop,
              shadows: [
                Shadow(
                  color: KioskColors.ring.withValues(alpha: .45),
                  blurRadius: 80,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: KioskColors.glass(.06),
                  border: Border.all(color: KioskColors.glass(.14), width: 1.5),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  serviceText,
                  style: KioskType.body(23, FontWeight.w700),
                ),
              ),
              if (order.table != null) ...[
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: KioskColors.ring.withValues(alpha: .12),
                    border: Border.all(
                      color: KioskColors.ring.withValues(alpha: .45),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${l10n.kioskTableLabel} ${order.table}',
                    style: KioskType.body(
                      23,
                      FontWeight.w700,
                      color: KioskColors.accentTop,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 26),
          // ---- the slip facsimile (receipt spec) ----
          Container(
            width: 640,
            padding: const EdgeInsets.fromLTRB(46, 44, 46, 36),
            decoration: BoxDecoration(
              color: KioskColors.slipPaper,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x8C000000),
                  offset: Offset(0, 40),
                  blurRadius: 100,
                ),
              ],
            ),
            child: Column(
              children: [
                Text.rich(
                  TextSpan(
                    text: KioskBrand.wordmark,
                    children: [
                      TextSpan(
                        text: KioskBrand.wordmarkSuffix,
                        style: const TextStyle(color: KioskColors.slipAccent),
                      ),
                    ],
                  ),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontFamily: KioskType.latinDisplayFamily,
                    fontWeight: FontWeight.w400,
                    fontSize: 42,
                    letterSpacing: .5,
                    color: KioskColors.slipInk,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  KioskBrand.subtitle,
                  textDirection: TextDirection.ltr,
                  style: KioskType.body(
                    18,
                    FontWeight.w600,
                    color: KioskColors.slipSoft,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.kioskMadeFresh,
                  style: KioskType.body(
                    17,
                    FontWeight.w500,
                    color: KioskColors.slipFaint,
                  ),
                ),
                const _DashedRule(),
                _SlipRow(
                  label: l10n.kioskOrderNumberLabel,
                  value: numberText,
                  valueStyle: KioskType.body(
                    24,
                    FontWeight.w900,
                    color: KioskColors.slipInk,
                  ),
                ),
                _SlipRow(label: l10n.kioskServiceLabel, value: serviceText),
                if (order.table != null)
                  _SlipRow(
                    label: l10n.kioskTableLabel,
                    value: '${l10n.kioskTableLabel} ${order.table}',
                  ),
                if (order.customerName.isNotEmpty)
                  _SlipRow(
                    label: l10n.kioskNameLabel,
                    value: order.customerName,
                  ),
                const _DashedRule(),
                for (final line in order.lines) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${line.quantity}×',
                              textDirection: TextDirection.ltr,
                              style: KioskType.body(
                                21,
                                FontWeight.w600,
                                color: KioskColors.slipFaint,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                menu.tryItem(line.itemId)?.name.of(lang) ?? '',
                                style: KioskType.body(
                                  21,
                                  FontWeight.w700,
                                  color: KioskColors.slipInk,
                                ),
                              ),
                            ),
                            Text(
                              kioskFormatMinor(line.lineTotalMinor, lang),
                              textDirection: TextDirection.ltr,
                              style: KioskType.body(
                                21,
                                FontWeight.w700,
                                color: KioskColors.slipInk,
                              ),
                            ),
                          ],
                        ),
                        if (KioskCartSheetSummary.of(
                          menu,
                          line,
                          lang,
                        ).isNotEmpty)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(
                              start: 38,
                              top: 2,
                            ),
                            child: Text(
                              KioskCartSheetSummary.of(menu, line, lang),
                              style: KioskType.body(
                                18,
                                FontWeight.w500,
                                color: KioskColors.slipSoft,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const _DashedRule(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.kioskTotal,
                      style: KioskType.body(
                        25,
                        FontWeight.w800,
                        color: KioskColors.slipInk,
                      ),
                    ),
                    Text(
                      kioskFormatMinor(order.totalMinor, lang),
                      key: const Key('kiosk-slip-total'),
                      textDirection: TextDirection.ltr,
                      style: KioskType.body(
                        34,
                        FontWeight.w900,
                        color: KioskColors.slipInk,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Transform.rotate(
                  angle: -6 * 3.1415926535 / 180,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 26,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: KioskColors.slipAccent,
                        width: 3.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      l10n.kioskPayAtCounter.toUpperCase(),
                      style: KioskType.body(
                        26,
                        FontWeight.w900,
                        color: KioskColors.slipAccent,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${l10n.kioskPrintingSlip} · Powered by RestoFlow',
                  style: KioskType.body(
                    16,
                    FontWeight.w500,
                    color: KioskColors.slipFaint,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              KioskPressable(
                onTap: controller.newOrder,
                child: Container(
                  key: const Key('kiosk-new-order'),
                  height: 98,
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: KioskColors.glass(.06),
                    border: Border.all(
                      color: KioskColors.glass(.2),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    l10n.kioskNewOrder.toUpperCase(),
                    style: KioskType.body(26, FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Text(
                l10n.kioskBackToStartIn(state.confirmSecondsLeft),
                key: const Key('kiosk-confirm-countdown'),
                style: KioskType.body(
                  22,
                  FontWeight.w600,
                  color: KioskColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shared modifier-summary helper (same rule the cart rows use).
abstract final class KioskCartSheetSummary {
  static String of(KioskMenuData menu, KioskCartLine line, String lang) {
    final item = menu.tryItem(line.itemId);
    if (item == null) return '';
    final parts = <String>[];
    for (final gid in item.groupIds) {
      final group = menu.group(gid);
      if (group == null) continue;
      for (final oid in line.selected[gid] ?? const <String>[]) {
        if (gid == 'weight' && oid == kioskIncludedWeightOptionId) continue;
        for (final o in group.options) {
          if (o.id == oid) parts.add(o.name.of(lang));
        }
      }
    }
    return parts.join(' · ');
  }
}

class _DashedRule extends StatelessWidget {
  const _DashedRule();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          for (var x = 0.0; x < constraints.maxWidth - 14; x += 14)
            Container(
              width: 8,
              height: 2.5,
              margin: const EdgeInsets.only(right: 6),
              color: KioskColors.slipHairline,
            ),
        ],
      ),
    ),
  );
}

class _SlipRow extends StatelessWidget {
  const _SlipRow({required this.label, required this.value, this.valueStyle});
  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: KioskType.body(
            20,
            FontWeight.w600,
            color: KioskColors.slipSoft,
          ),
        ),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style:
              valueStyle ??
              KioskType.body(20, FontWeight.w700, color: KioskColors.slipInk),
        ),
      ],
    ),
  );
}
