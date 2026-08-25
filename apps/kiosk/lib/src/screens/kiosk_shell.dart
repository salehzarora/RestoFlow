import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kiosk_appearance.dart';
import '../design/kiosk_theme.dart';
import '../state/kiosk_flow_controller.dart';
import '../widgets/kiosk_chrome.dart';
import 'attract_screen.dart';
import 'cart_sheet.dart';
import 'confirm_screen.dart';
import 'item_sheet.dart';
import 'menu_screen.dart';
import 'pin_gate.dart';
import 'service_screen.dart';
import 'settings_screen.dart';
import 'staff_pin_sheet.dart';
import 'tables_screen.dart';

/// The kiosk shell: state-driven screen stack inside the 1080×1920 stage.
/// Screens crossfade 350ms; sheets/PIN/idle/toast overlay the active screen
/// exactly like the artifact's layered frame. A root [Listener] feeds every
/// pointer-down to the idle engine.
class KioskShell extends ConsumerWidget {
  const KioskShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // PERF-110: the root composes ONLY from these four facts. Watching the
    // whole KioskState made the 1-second idle clock (`secondsSinceActivity`)
    // rebuild the entire 1080×1920 stage — menu grid, wheel, images, text —
    // once per second with nothing visible changing. Records compare by
    // value, so this subtree now rebuilds only when the composition changes.
    final state = ref.watch(
      kioskFlowProvider.select(
        (s) => (
          screen: s.screen,
          sheet: s.sheet,
          idleWarningVisible: s.idleSecondsLeft != null,
          toastVisible: s.toast != null,
        ),
      ),
    );
    final controller = ref.read(kioskFlowProvider.notifier);
    // KIOSK-001-107: bind the GLOBAL device theme before any child builds —
    // the watch makes the whole shell rebuild when the owner APPLIES a new
    // pair, so every `KioskColors.*` identity role resolves consistently.
    // Bare tests / demo without a saved theme keep the locked Navy+Ember.
    KioskColors.pair = ref.watch(kioskUiThemeProvider);

    return Listener(
      onPointerDown: (_) => controller.touch(),
      behavior: HitTestBehavior.translucent,
      child: KioskStage(
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: KioskMotion.screenFade,
              child: KeyedSubtree(
                key: ValueKey(state.screen),
                child: switch (state.screen) {
                  KioskScreen.attract => const KioskAttractScreen(),
                  KioskScreen.service => const KioskServiceScreen(),
                  KioskScreen.tables => const KioskTablesScreen(),
                  KioskScreen.menu => const KioskMenuScreen(),
                  KioskScreen.confirm => const KioskConfirmScreen(),
                  KioskScreen.settings => const KioskSettingsScreen(),
                },
              ),
            ),
            // The fixed bottom action bar lives above the menu only.
            if (state.screen == KioskScreen.menu)
              const Align(
                alignment: Alignment.bottomCenter,
                // PERF-110: the glowing bar lives in its own layer so grid
                // scrolling never re-rasters its blur.
                child: RepaintBoundary(child: KioskBottomBar()),
              ),
            if (state.sheet == KioskSheet.item) const KioskItemSheet(),
            if (state.sheet == KioskSheet.cart) const KioskCartSheet(),
            if (state.sheet == KioskSheet.pin) const KioskPinGate(),
            if (state.sheet == KioskSheet.staffPin) const KioskStaffPinSheet(),
            if (state.idleWarningVisible) const _IdleWarningOverlay(),
            if (state.toastVisible) const _KioskToast(),
          ],
        ),
      ),
    );
  }
}

/// The "Still there?" overlay — pulsing countdown, I'm-still-here / Start
/// over. Shown during the final warning seconds before the idle reset.
class _IdleWarningOverlay extends ConsumerWidget {
  const _IdleWarningOverlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // The warning countdown is the ONE legitimately per-second surface.
    final state = ref.watch(
      kioskFlowProvider.select(
        (s) => (idleSecondsLeft: s.idleSecondsLeft, rtl: s.rtl),
      ),
    );
    final controller = ref.read(kioskFlowProvider.notifier);
    final rtl = state.rtl;

    return ColoredBox(
      color: const Color(0xD903060C),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              key: ValueKey(state.idleSecondsLeft),
              tween: Tween(begin: 1.05, end: 1),
              duration: const Duration(milliseconds: 500),
              builder: (context, s, child) =>
                  Transform.scale(scale: s, child: child),
              child: Text(
                '${state.idleSecondsLeft}',
                key: const Key('kiosk-idle-count'),
                textDirection: TextDirection.ltr,
                style: KioskType.display(rtl, 150, height: 1).copyWith(
                  color: KioskColors.accentTop,
                  shadows: [
                    Shadow(
                      color: KioskColors.ring.withValues(alpha: .5),
                      blurRadius: 60,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              l10n.kioskStillThere,
              style: KioskType.body(40, FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.kioskStillThereSub,
              textAlign: TextAlign.center,
              style: KioskType.body(
                24,
                FontWeight.w500,
                color: KioskColors.textMuted,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                KioskAccentPill(
                  key: const Key('kiosk-im-here'),
                  onTap: controller.dismissIdleWarning,
                  horizontalPadding: 60,
                  child: Text(
                    l10n.kioskImStillHere.toUpperCase(),
                    style: KioskType.body(
                      28,
                      FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                KioskPressable(
                  onTap: controller.reset,
                  child: Container(
                    key: const Key('kiosk-start-over'),
                    height: 110,
                    padding: const EdgeInsets.symmetric(horizontal: 44),
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
                      l10n.kioskStartOver.toUpperCase(),
                      style: KioskType.body(26, FontWeight.w800),
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

/// Bottom toast (added-to-order confirmation + staff fixture toasts).
class _KioskToast extends ConsumerWidget {
  const _KioskToast();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final toast = ref.watch(kioskFlowProvider.select((s) => s.toast));
    // Semantic tokens → localized copy; anything else is a staff fixture
    // string shown verbatim (settings shell only).
    final text = switch (toast) {
      'added' => l10n.kioskAddedToOrder,
      'ordering-unavailable' => l10n.kioskOrderingUnavailable,
      'cart-stale' => l10n.kioskCartStaleTitle,
      'table-taken' => l10n.kioskTableNoLongerAvailable,
      final other => other!,
    };

    return Positioned(
      bottom: 170,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            decoration: BoxDecoration(
              color: KioskColors.cardTint(0xEB / 255),
              border: Border.all(
                color: KioskColors.ring.withValues(alpha: .55),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                const BoxShadow(
                  color: Color(0x80000000),
                  offset: Offset(0, 20),
                  blurRadius: 50,
                ),
                BoxShadow(
                  color: KioskColors.ring.withValues(alpha: .2),
                  blurRadius: 40,
                ),
              ],
            ),
            constraints: const BoxConstraints(maxWidth: 900),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_rounded,
                  size: 26,
                  color: KioskColors.accentTop,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    text,
                    key: const Key('kiosk-toast'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: KioskType.body(23, FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
