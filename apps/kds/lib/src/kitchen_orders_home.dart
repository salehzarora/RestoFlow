import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'state/kitchen_orders_controller.dart';
import 'widgets/kds_state_message.dart';
import 'widgets/kitchen_board.dart';
import 'widgets/kitchen_demo_banner.dart';
import 'widgets/language_selector.dart';

/// The RF-117 KDS home: a live (demo) kitchen order board with status columns
/// and kitchen actions. Watches [kitchenOrdersControllerProvider] (loading /
/// error / empty / data). Elapsed times are computed from the submitted time at
/// build and refresh whenever the board rebuilds (e.g. on a kitchen action). The
/// demo banner keeps it honest: this is a local feed, not backend-synced.
class KitchenOrdersHome extends ConsumerWidget {
  const KitchenOrdersHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ordersAsync = ref.watch(kitchenOrdersControllerProvider);
    final controller = ref.read(kitchenOrdersControllerProvider.notifier);
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.kitchen_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: RestoflowSpacing.sm),
            Text(l10n.kdsAppTitle),
          ],
        ),
        actions: const [LanguageSelector()],
      ),
      body: Column(
        children: [
          const KitchenDemoBanner(),
          Expanded(
            child: ordersAsync.when(
              loading: () => KdsStateMessage(
                message: l10n.kdsLoadingState,
                showSpinner: true,
              ),
              error: (_, _) => KdsStateMessage(
                icon: Icons.error_outline,
                tone: RestoflowTone.danger,
                message: l10n.kdsErrorState,
              ),
              data: (tickets) => tickets.isEmpty
                  ? KdsStateMessage(
                      icon: Icons.restaurant_outlined,
                      message: l10n.kdsEmptyState,
                    )
                  : KitchenBoard(
                      tickets: tickets,
                      now: now,
                      onStart: controller.start,
                      onMarkReady: controller.markReady,
                      onComplete: controller.complete,
                      onRecall: controller.recall,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
