/// The Dashboard ORDERS area (ACTIVE-ORDERS-001).
///
/// ONE navigation destination holding two views, rather than a duplicate nav
/// entry:
///   * Active orders  — the read-only operations centre (what is open NOW).
///   * History        — the existing paginated, filterable order history.
///
/// The page header and its refresh action live here, once, and dispatch to the
/// selected view; each view supplies only its body. Every existing history
/// behaviour (filters, search, pagination, detail sheet, receipt / money-free
/// kitchen previews, browser print, copy) is untouched.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../state/active_orders_providers.dart';
import '../state/order_history_providers.dart';
import 'active_orders_screen.dart';
import 'order_history_screen.dart';

/// The two views of the Orders area.
enum OrdersTab { active, history }

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  /// The operations centre is the landing view: the question an owner opens the
  /// Orders area to answer is "what is happening right now".
  OrdersTab _tab = OrdersTab.active;

  void _refresh() {
    if (_tab == OrdersTab.active) {
      ref.read(activeOrdersControllerProvider.notifier).refresh();
    } else {
      ref.read(orderHistoryControllerProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isActive = _tab == OrdersTab.active;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RestoflowPageHeader(
          bordered: true,
          padding: const EdgeInsetsDirectional.fromSTEB(
            RestoflowSpacing.lg,
            RestoflowSpacing.md,
            RestoflowSpacing.lg,
            RestoflowSpacing.md,
          ),
          icon: Icons.receipt_long_outlined,
          title: isActive ? l10n.ordersActiveTitle : l10n.ordersHistoryTitle,
          // Say what each surface IS: Active holds orders still open in
          // operations; finished ones move to History.
          subtitle: isActive
              ? l10n.ordersActiveSubtitleV2
              : l10n.ordersHistorySubtitle,
          actions: [
            IconButton(
              key: const Key('orders-refresh'),
              tooltip: l10n.ordersRefresh,
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RestoflowSpacing.lg,
            RestoflowSpacing.md,
            RestoflowSpacing.lg,
            0,
          ),
          // On a phone the two labels do not fit side by side at their natural
          // width, so the segments SHARE the available width (the control's
          // `expand` mode) instead of overflowing; on wider layouts the bar hugs
          // its content at the reading start, as before.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow =
                  constraints.maxWidth < RestoflowBreakpoints.compact;
              final control = RestoflowSegmentedControl<OrdersTab>(
                segments: [
                  RestoflowSegment(
                    key: const Key('orders-tab-active'),
                    value: OrdersTab.active,
                    label: l10n.ordersTabActive,
                    icon: Icons.local_fire_department_outlined,
                  ),
                  RestoflowSegment(
                    key: const Key('orders-tab-history'),
                    value: OrdersTab.history,
                    label: l10n.ordersTabHistory,
                    icon: Icons.history,
                  ),
                ],
                selected: _tab,
                expand: narrow,
                onSelected: (tab) {
                  if (tab == _tab) return;
                  // Switching tabs MOUNTS/UNMOUNTS the view below, and the active
                  // board reports its own visibility from that lifecycle — so its
                  // polling stops on History with no bookkeeping here. Each view
                  // keeps its OWN filter state; neither is reset by the switch.
                  setState(() => _tab = tab);
                },
              );
              if (narrow) return control;
              return Align(
                alignment: AlignmentDirectional.centerStart,
                child: control,
              );
            },
          ),
        ),
        Expanded(
          child: isActive ? const ActiveOrdersView() : const OrderHistoryView(),
        ),
      ],
    );
  }
}
