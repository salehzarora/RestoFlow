import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kiosk_fixtures.dart';
import '../design/kiosk_theme.dart';
import '../state/kiosk_flow_controller.dart';
import '../widgets/kiosk_chrome.dart';

/// 02 · Service type — one question, two 380px-tall glass cards inside a
/// radius-44 card, the pay-at-counter pill. Selection navigates immediately.
class KioskServiceScreen extends ConsumerWidget {
  const KioskServiceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(kioskFlowProvider);
    final controller = ref.read(kioskFlowProvider.notifier);

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(kioskAttractAssets.first, fit: BoxFit.cover),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, .45, 1],
              colors: [Color(0xE6070E1B), Color(0x9E070E1B), Color(0xF2070E1B)],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(56),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const KioskBrandBadge(),
                  Row(
                    children: [
                      KioskLanguageCapsule(
                        lang: state.lang,
                        onSelect: controller.setLanguage,
                      ),
                      const SizedBox(width: 12),
                      KioskBackPill(onTap: controller.backToAttract),
                    ],
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(52, 60, 52, 60),
                    decoration: BoxDecoration(
                      color: KioskColors.cardGlass,
                      border: Border.all(
                        color: KioskColors.glass(.13),
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(44),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x8C000000),
                          offset: Offset(0, 40),
                          blurRadius: 90,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.kioskHow,
                          textAlign: TextAlign.center,
                          style: KioskType.display(state.rtl, 64, height: 1.08),
                        ),
                        const SizedBox(height: 10),
                        const KioskUnderline(width: 240),
                        const SizedBox(height: 44),
                        Row(
                          children: [
                            Expanded(
                              child: _ServiceCard(
                                key: const Key('kiosk-service-dine'),
                                icon: Icons.restaurant_outlined,
                                title: l10n.kioskDineIn,
                                subtitle: l10n.kioskDineInSub,
                                onTap: () => controller.pickService(
                                  KioskServiceType.dineIn,
                                ),
                              ),
                            ),
                            const SizedBox(width: 28),
                            Expanded(
                              child: _ServiceCard(
                                key: const Key('kiosk-service-take'),
                                icon: Icons.shopping_bag_outlined,
                                title: l10n.kioskTakeaway,
                                subtitle: l10n.kioskTakeawaySub,
                                onTap: () => controller.pickService(
                                  KioskServiceType.takeaway,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 44),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
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
                            l10n.kioskPayNote,
                            style: KioskType.body(
                              22,
                              FontWeight.w600,
                              color: KioskColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KioskPressable(
    onTap: onTap,
    child: Container(
      height: 380,
      decoration: BoxDecoration(
        color: KioskColors.glass(.05),
        border: Border.all(color: KioskColors.glass(.12), width: 2.5),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 104, color: KioskColors.textPrimary),
          const SizedBox(height: 26),
          Text(title, style: KioskType.body(33, FontWeight.w800)),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: KioskType.body(
              22,
              FontWeight.w500,
              color: KioskColors.textMuted,
            ),
          ),
        ],
      ),
    ),
  );
}
