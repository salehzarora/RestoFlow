import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../design/kiosk_theme.dart';
import '../state/kiosk_flow_controller.dart';
import '../widgets/kiosk_chrome.dart';

/// 08 · Staff PIN gate — the 560px keypad card over a deep scrim. Wrong PIN
/// shakes the dot row and clears; scrim tap dismisses. PHASE 1 FIXTURE ONLY:
/// the check compares against the artifact's demo PIN — it is a visual shell,
/// not authentication (the real employee PIN session arrives in a later
/// phase). The card stays LTR like the artifact's staff surfaces.
class KioskPinGate extends ConsumerWidget {
  const KioskPinGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(kioskFlowProvider);
    final controller = ref.read(kioskFlowProvider.notifier);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: controller.pinCancel,
            child: const ColoredBox(color: KioskColors.scrimDeep),
          ),
        ),
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            builder: (context, t, child) => Transform.scale(
              scale: .8 + .2 * t,
              child: Opacity(opacity: t, child: child),
            ),
            child: Container(
              width: 560,
              padding: const EdgeInsets.fromLTRB(44, 48, 44, 40),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [KioskColors.sheetTop, KioskColors.pinCardBottom],
                ),
                border: Border.all(color: KioskColors.glass(.14), width: 1.5),
                borderRadius: BorderRadius.circular(36),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x99000000),
                    offset: Offset(0, 40),
                    blurRadius: 100,
                  ),
                ],
              ),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.kioskStaffAccess,
                      style: KioskType.body(31, FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.kioskStaffPinPrompt,
                      textAlign: TextAlign.center,
                      style: KioskType.body(
                        21,
                        FontWeight.w500,
                        color: KioskColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 26),
                    _PinDots(entry: state.pinEntry, error: state.pinError),
                    const SizedBox(height: 26),
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: (472 - 32) / 3 / 96,
                      children: [
                        for (var k = 1; k <= 9; k++)
                          _PinKey(
                            key: Key('kiosk-pin-$k'),
                            label: '$k',
                            onTap: () => controller.pinPress('$k'),
                          ),
                        KioskPressable(
                          onTap: controller.pinCancel,
                          child: Center(
                            child: Text(
                              l10n.kioskCancel,
                              key: const Key('kiosk-pin-cancel'),
                              style: KioskType.body(
                                22,
                                FontWeight.w700,
                                color: KioskColors.textMuted,
                              ),
                            ),
                          ),
                        ),
                        _PinKey(
                          key: const Key('kiosk-pin-0'),
                          label: '0',
                          onTap: () => controller.pinPress('0'),
                        ),
                        KioskPressable(
                          onTap: controller.pinBackspace,
                          child: Container(
                            key: const Key('kiosk-pin-del'),
                            decoration: BoxDecoration(
                              color: KioskColors.glass(.05),
                              border: Border.all(
                                color: KioskColors.glass(.14),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.backspace_outlined,
                                size: 28,
                                color: KioskColors.textMuted,
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
          ),
        ),
      ],
    );
  }
}

class _PinDots extends StatefulWidget {
  const _PinDots({required this.entry, required this.error});
  final String entry;
  final bool error;

  @override
  State<_PinDots> createState() => _PinDotsState();
}

class _PinDotsState extends State<_PinDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  @override
  void didUpdateWidget(covariant _PinDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.error && !oldWidget.error) _shake.forward(from: 0);
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _shake,
    builder: (context, child) {
      final t = _shake.value;
      final dx = t == 0 || t == 1
          ? 0.0
          : 16 *
                (t < .2
                    ? -t / .2
                    : t < .4
                    ? -1 + (t - .2) / .1
                    : t < .6
                    ? 1 - (t - .4) / .1
                    : t < .8
                    ? -1 + (t - .6) / .1
                    : 1 - (t - .8) / .2);
      return Transform.translate(
        offset: Offset(dx.clamp(-16, 16), 0),
        child: child,
      );
    },
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 4; i++)
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < widget.entry.length
                  ? (widget.error ? KioskColors.danger : KioskColors.accentTop)
                  : Colors.transparent,
              border: Border.all(
                color: widget.error
                    ? KioskColors.danger
                    : i < widget.entry.length
                    ? KioskColors.accentTop
                    : KioskColors.frameLineHi,
                width: 3,
              ),
            ),
          ),
      ],
    ),
  );
}

class _PinKey extends StatelessWidget {
  const _PinKey({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KioskPressable(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        color: KioskColors.glass(.05),
        border: Border.all(color: KioskColors.glass(.14), width: 1.5),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Center(
        child: Text(label, style: KioskType.body(32, FontWeight.w800)),
      ),
    ),
  );
}
