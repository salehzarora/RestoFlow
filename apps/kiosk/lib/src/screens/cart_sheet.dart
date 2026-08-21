import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kiosk_fixtures.dart';
import '../data/kiosk_menu_data.dart';
import '../data/kiosk_order_submit.dart';
import '../design/kiosk_theme.dart';
import '../state/kiosk_flow_controller.dart';
import '../widgets/kiosk_chrome.dart';

/// 06 · Cart sheet — line rows (thumb · name · chosen modifiers · note ·
/// stepper · line total · remove; tapping a row re-opens the item sheet
/// pre-filled), then the optional name/phone "for the counter call", the
/// service/table chip with Change, the fixed total + PLACE ORDER footer and
/// the pay-at-counter reassurance. Empty state invites back to the menu.
/// Phase 1: Place order only transitions to the fixture confirmation.
class KioskCartSheet extends ConsumerWidget {
  const KioskCartSheet({super.key});

  static String modifierSummary(
    KioskMenuData menu,
    KioskCartLine line,
    String lang,
  ) {
    final item = menu.tryItem(line.itemId);
    if (item == null) return '';
    final parts = <String>[];
    for (final gid in item.groupIds) {
      final group = menu.group(gid);
      if (group == null) continue;
      for (final oid in line.selected[gid] ?? const <String>[]) {
        // V2 rule: the included default weight is not repeated in summaries.
        if (gid == 'weight' && oid == kioskIncludedWeightOptionId) continue;
        for (final o in group.options) {
          if (o.id == oid) parts.add(o.name.of(lang));
        }
      }
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(kioskFlowProvider);
    final controller = ref.read(kioskFlowProvider.notifier);
    final menu = ref.watch(kioskMenuDataProvider);
    final rtl = state.rtl;
    final serviceBase = switch (state.service) {
      KioskServiceType.dineIn => l10n.kioskDineIn,
      KioskServiceType.takeaway => l10n.kioskTakeaway,
      null => '—',
    };
    final serviceChip = state.selectedTable != null
        ? '$serviceBase · ${state.selectedTable}'
        : serviceBase;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: controller.closeCart,
            child: const ColoredBox(color: KioskColors.scrim),
          ),
        ),
        Positioned.fill(
          top: 270,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 1, end: 0),
            duration: KioskMotion.sheetRise,
            curve: KioskMotion.curve,
            builder: (context, t, child) => Transform.translate(
              offset: Offset(0, t * 0.06 * 1650),
              child: Opacity(opacity: 1 - t, child: child),
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: kioskSheetGradient,
                border: Border(
                  top: BorderSide(color: KioskColors.glass(.13), width: 1.5),
                  left: BorderSide(color: KioskColors.glass(.13), width: 1.5),
                  right: BorderSide(color: KioskColors.glass(.13), width: 1.5),
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(44),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(52, 36, 52, 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.kioskYourOrder,
                            style: KioskType.display(rtl, 52),
                          ),
                        ),
                        KioskPressable(
                          onTap: controller.closeCart,
                          child: Container(
                            key: const Key('kiosk-cart-close'),
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
                              child: Icon(
                                Icons.close,
                                size: 34,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (state.cart.isEmpty)
                    Expanded(child: _EmptyCart(onBrowse: controller.closeCart))
                  else ...[
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(52, 10, 52, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (state.cartStale)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 18),
                                child: Container(
                                  key: const Key('kiosk-cart-stale'),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 26,
                                    vertical: 20,
                                  ),
                                  decoration: BoxDecoration(
                                    color: KioskColors.danger.withValues(
                                      alpha: .12,
                                    ),
                                    border: Border.all(
                                      color: KioskColors.danger.withValues(
                                        alpha: .5,
                                      ),
                                      width: 1.5,
                                    ),
                                    borderRadius: BorderRadius.circular(26),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              l10n.kioskCartStaleTitle,
                                              style: KioskType.body(
                                                24,
                                                FontWeight.w800,
                                                color: KioskColors.dangerSoft,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              l10n.kioskCartStaleBody,
                                              style: KioskType.body(
                                                20,
                                                FontWeight.w500,
                                                color: KioskColors.textMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 18),
                                      KioskPressable(
                                        key: const Key(
                                          'kiosk-cart-stale-refresh',
                                        ),
                                        onTap:
                                            controller.refreshCartAgainstMenu,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 28,
                                            vertical: 16,
                                          ),
                                          decoration: BoxDecoration(
                                            color: KioskColors.danger
                                                .withValues(alpha: .2),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Text(
                                            l10n.kioskCartStaleRefresh,
                                            style: KioskType.body(
                                              21,
                                              FontWeight.w800,
                                              color: KioskColors.dangerSoft,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (state.submitPhase ==
                                KioskSubmitPhase.unconfirmed)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 18),
                                child: _CartNotice(
                                  key: const Key('kiosk-submit-unconfirmed'),
                                  title: l10n.kioskSubmitUnconfirmedTitle,
                                  body: l10n.kioskSubmitUnconfirmedBody,
                                  actionKey: const Key('kiosk-submit-retry'),
                                  actionLabel: l10n.kioskSubmitRetry,
                                  onAction: controller.retrySubmit,
                                ),
                              ),
                            if (state.submitErrorKey != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 18),
                                child: _CartNotice(
                                  key: const Key('kiosk-submit-error'),
                                  title: switch (state.submitErrorKey) {
                                    'phone-invalid' =>
                                      l10n.kioskPhoneInvalidMsg,
                                    'tax-unavailable' =>
                                      l10n.kioskTaxUnavailableMsg,
                                    _ => l10n.kioskSubmitFailed,
                                  },
                                ),
                              ),
                            for (final line in state.cart)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 18),
                                child: _CartRow(
                                  line: line,
                                  menu: menu,
                                  lang: state.lang,
                                  onEdit: () =>
                                      controller.editCartLine(line.lineId),
                                  onInc: () =>
                                      controller.incrementLine(line.lineId),
                                  onDec: () =>
                                      controller.decrementLine(line.lineId),
                                  onRemove: () =>
                                      controller.removeLine(line.lineId),
                                ),
                              ),
                            const SizedBox(height: 10),
                            Text.rich(
                              TextSpan(
                                text: l10n.kioskForCounterCall,
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
                              style: KioskType.body(25, FontWeight.w800),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _IdentityField(
                                    key: const Key('kiosk-cust-name'),
                                    hint: l10n.kioskNameOptional,
                                    initialValue: state.customerName,
                                    onChanged: controller.setCustomerName,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _IdentityField(
                                    key: const Key('kiosk-cust-phone'),
                                    hint: l10n.kioskPhoneOptional,
                                    initialValue: state.customerPhone,
                                    onChanged: controller.setCustomerPhone,
                                    ltr: true,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 28,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: KioskColors.glass(.06),
                                    border: Border.all(
                                      color: KioskColors.glass(.12),
                                      width: 1.5,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    serviceChip,
                                    style: KioskType.body(21, FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                KioskPressable(
                                  onTap: controller.changeService,
                                  child: Text(
                                    l10n.kioskChange,
                                    key: const Key('kiosk-change-service'),
                                    style:
                                        KioskType.body(
                                          21,
                                          FontWeight.w700,
                                          color: KioskColors.accentTop,
                                        ).copyWith(
                                          decoration: TextDecoration.underline,
                                          decorationColor:
                                              KioskColors.accentTop,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(52, 22, 52, 40),
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
                          // 092: with a live tax policy the summary shows the
                          // EXACT figures the server will validate — integer
                          // minor units, no float, no hidden add-on.
                          if (state.branchTax?.addsTax ?? false) ...[
                            _SummaryRow(
                              label: l10n.kioskSubtotal,
                              valueKey: const Key('kiosk-cart-subtotal'),
                              value: context.money(state.cartTotalMinor),
                            ),
                            const SizedBox(height: 6),
                            _SummaryRow(
                              label: state.branchTax!.isInclusive
                                  ? l10n.kioskTaxIncludedNote
                                  : l10n.kioskTax,
                              valueKey: const Key('kiosk-cart-tax'),
                              value: context.money(
                                kioskTaxMinor(
                                  state.cartTotalMinor,
                                  state.branchTax!,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                l10n.kioskTotal,
                                style: KioskType.body(28, FontWeight.w800),
                              ),
                              Text(
                                context.money(
                                  state.branchTax == null
                                      ? state.cartTotalMinor
                                      : kioskGrandMinor(
                                          state.cartTotalMinor,
                                          state.branchTax!,
                                        ),
                                ),
                                key: const Key('kiosk-cart-total'),
                                textDirection: TextDirection.ltr,
                                style: KioskType.body(44, FontWeight.w900),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          KioskPressable(
                            // 092 single-flight: an in-flight submit disables
                            // the CTA (double tap can never submit twice).
                            onTap:
                                state.submitPhase == KioskSubmitPhase.inFlight
                                ? null
                                : controller.placeOrder,
                            pressedScale: .98,
                            child: Container(
                              key: const Key('kiosk-place-order'),
                              height: 122,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: kioskAccentGradient,
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: [
                                  BoxShadow(
                                    color: KioskColors.ring.withValues(
                                      alpha: .4,
                                    ),
                                    blurRadius: 44,
                                    offset: const Offset(0, 16),
                                  ),
                                ],
                              ),
                              child:
                                  state.submitPhase == KioskSubmitPhase.inFlight
                                  ? const SizedBox(
                                      key: Key('kiosk-place-order-busy'),
                                      width: 40,
                                      height: 40,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 4,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          l10n.kioskPlaceOrder.toUpperCase(),
                                          style: KioskType.body(
                                            31,
                                            FontWeight.w900,
                                            color: Colors.white,
                                            letterSpacing: .5,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Icon(
                                          rtl
                                              ? Icons.arrow_back_rounded
                                              : Icons.arrow_forward_rounded,
                                          size: 34,
                                          color: Colors.white,
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            l10n.kioskPayNote,
                            style: KioskType.body(
                              21,
                              FontWeight.w600,
                              color: KioskColors.textFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart({required this.onBrowse});
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KioskColors.glass(.06),
              border: Border.all(color: KioskColors.glass(.12), width: 1.5),
            ),
            child: const Center(
              child: Icon(
                Icons.shopping_cart_outlined,
                size: 56,
                color: KioskColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(l10n.kioskCartEmpty, style: KioskType.body(30, FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            l10n.kioskCartEmptySub,
            style: KioskType.body(
              22,
              FontWeight.w500,
              color: KioskColors.textMuted,
            ),
          ),
          const SizedBox(height: 24),
          KioskAccentPill(
            onTap: onBrowse,
            height: 96,
            horizontalPadding: 52,
            child: Text(
              l10n.kioskBrowseMenu.toUpperCase(),
              style: KioskType.body(26, FontWeight.w800, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({
    required this.line,
    required this.menu,
    required this.lang,
    required this.onEdit,
    required this.onInc,
    required this.onDec,
    required this.onRemove,
  });
  final KioskCartLine line;
  final KioskMenuData menu;
  final String lang;
  final VoidCallback onEdit;
  final VoidCallback onInc;
  final VoidCallback onDec;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final item = menu.tryItem(line.itemId);
    if (item == null) return const SizedBox.shrink();
    final mods = KioskCartSheet.modifierSummary(menu, line, lang);

    return GestureDetector(
      onTap: onEdit,
      child: Container(
        key: Key('kiosk-cart-line-${line.lineId}'),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: KioskColors.glass(.05),
          border: Border.all(color: KioskColors.glass(.1), width: 1.5),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Row(
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KioskColors.imageWell,
                border: Border.all(color: KioskColors.glass(.1), width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: item.imageAsset != null
                  ? KioskFixtureImage(
                      asset: item.imageAsset,
                      fallback: const ColoredBox(color: KioskColors.imageWell),
                    )
                  : Center(
                      child: Text(
                        item.name.of(lang).characters.first,
                        style: KioskType.body(
                          34,
                          FontWeight.w900,
                          color: KioskColors.accentTop,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name.of(lang),
                    style: KioskType.body(25, FontWeight.w800),
                  ),
                  if (mods.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      mods,
                      style: KioskType.body(
                        19,
                        FontWeight.w500,
                        color: KioskColors.textMuted,
                      ),
                    ),
                  ],
                  if (line.note.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      '“${line.note}”',
                      style: KioskType.body(
                        19,
                        FontWeight.w500,
                        color: KioskColors.accentTop,
                      ).copyWith(fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 14),
            GestureDetector(
              // The stepper cluster must not trigger the row's edit tap.
              onTap: () {},
              child: Row(
                children: [
                  _SmallRound(
                    key: Key('kiosk-line-dec-${line.lineId}'),
                    icon: Icons.remove,
                    filled: false,
                    onTap: onDec,
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${line.quantity}',
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.ltr,
                      style: KioskType.body(26, FontWeight.w900),
                    ),
                  ),
                  _SmallRound(
                    key: Key('kiosk-line-inc-${line.lineId}'),
                    icon: Icons.add,
                    filled: true,
                    onTap: onInc,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 110,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    kioskFormatMinor(line.lineTotalMinor, lang),
                    textDirection: TextDirection.ltr,
                    style: KioskType.body(25, FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  KioskPressable(
                    onTap: onRemove,
                    child: Text(
                      l10n.kioskRemove,
                      key: Key('kiosk-line-remove-${line.lineId}'),
                      style:
                          KioskType.body(
                            19,
                            FontWeight.w600,
                            color: KioskColors.textFaint,
                          ).copyWith(
                            decoration: TextDecoration.underline,
                            decorationColor: KioskColors.textFaint,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallRound extends StatelessWidget {
  const _SmallRound({
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
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: filled ? kioskAccentGradient : null,
        color: filled ? null : KioskColors.glass(.05),
        border: filled
            ? null
            : Border.all(color: KioskColors.glass(.18), width: 2),
      ),
      child: Center(child: Icon(icon, size: 28, color: Colors.white)),
    ),
  );
}

class _IdentityField extends StatelessWidget {
  const _IdentityField({
    super.key,
    required this.hint,
    required this.initialValue,
    required this.onChanged,
    this.ltr = false,
  });
  final String hint;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final bool ltr;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 96,
    child: TextFormField(
      initialValue: initialValue,
      onChanged: onChanged,
      textDirection: ltr ? TextDirection.ltr : null,
      keyboardType: ltr ? TextInputType.phone : TextInputType.name,
      style: KioskType.body(23, FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: KioskType.body(
          23,
          FontWeight.w500,
          color: KioskColors.textFaint,
        ),
        filled: true,
        fillColor: KioskColors.glass(.05),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: KioskColors.glass(.14), width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: KioskColors.accentTop, width: 2),
        ),
      ),
    ),
  );
}

/// 092: one summary line above the total (subtotal / tax), V2-toned.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value, this.valueKey});
  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: KioskType.body(
          22,
          FontWeight.w600,
          color: KioskColors.textMuted,
        ),
      ),
      Text(
        value,
        key: valueKey,
        textDirection: TextDirection.ltr,
        style: KioskType.body(
          26,
          FontWeight.w800,
          color: KioskColors.textMuted,
        ),
      ),
    ],
  );
}

/// 092: a customer-facing recovery notice in the cart (same visual family as
/// the stale banner) with an optional action pill (e.g. retry).
class _CartNotice extends StatelessWidget {
  const _CartNotice({
    super.key,
    required this.title,
    this.body,
    this.actionKey,
    this.actionLabel,
    this.onAction,
  });
  final String title;
  final String? body;
  final Key? actionKey;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
    decoration: BoxDecoration(
      color: KioskColors.danger.withValues(alpha: .12),
      border: Border.all(
        color: KioskColors.danger.withValues(alpha: .5),
        width: 1.5,
      ),
      borderRadius: BorderRadius.circular(26),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: KioskType.body(
                  24,
                  FontWeight.w800,
                  color: KioskColors.dangerSoft,
                ),
              ),
              if (body != null) ...[
                const SizedBox(height: 6),
                Text(
                  body!,
                  style: KioskType.body(
                    20,
                    FontWeight.w500,
                    color: KioskColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null) ...[
          const SizedBox(width: 18),
          KioskPressable(
            key: actionKey,
            onTap: onAction,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              decoration: BoxDecoration(
                color: KioskColors.danger.withValues(alpha: .2),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                actionLabel!,
                style: KioskType.body(
                  21,
                  FontWeight.w800,
                  color: KioskColors.dangerSoft,
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
