import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_edit_slip_store.dart' show OrderEditSlipRecord;
import '../print/pos_kitchen_ticket_printer.dart' show PosKitchenPrintOutcome;
import '../state/order_edit_slip_controller.dart';

/// ORDER-EDIT-001F — the cashier's side of the paper change slip (design
/// §7.3): the persistent "Kitchen change slip not printed" banner and the
/// ONE "Print again" handler the banner, the order row and the result
/// toast's action all share ([OrderEditSlipPrintAgain]). Every string is an
/// existing translated key.

/// One banner per unsent slip ([orderEditPendingSlipsProvider]): "Kitchen
/// change slip not printed", the order and "Change N", and Print again.
/// Renders nothing when every slip is on paper.
class OrderEditSlipBanner extends ConsumerWidget {
  const OrderEditSlipBanner({this.maxHeight = double.infinity, super.key});

  /// The most height the banners take together; past it they scroll (the
  /// menu screen bounds it, so the grid below keeps its height).
  final double maxHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(orderEditPendingSlipsProvider);
    if (pending.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final banners = Column(
      key: const Key('order-edit-slip-banners'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final record in pending)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              RestoflowSpacing.lg,
              RestoflowSpacing.sm,
              RestoflowSpacing.lg,
              0,
            ),
            child: RestoflowNoticeBanner(
              key: Key('order-edit-slip-banner-${record.orderEditId}'),
              tone: RestoflowTone.warning,
              icon: Icons.print_disabled_outlined,
              title: l10n.posOrderEditSlipNotPrinted,
              body: orderEditSlipLabel(l10n, record),
              action: TextButton(
                key: Key('order-edit-slip-print-again-${record.orderEditId}'),
                onPressed: () => printOrderEditSlipAgain(
                  context,
                  orderEditId: record.orderEditId,
                ),
                child: Text(l10n.posOrderEditPrintAgain),
              ),
            ),
          ),
      ],
    );
    return ConstrainedBox(
      key: const Key('order-edit-slip-banner-area'),
      constraints: BoxConstraints(maxHeight: maxHeight),
      // Never the page's primary scroll: the menu grid has its own.
      child: SingleChildScrollView(primary: false, child: banners),
    );
  }
}

/// "#A1B2C3 · Change 2" — which slip a banner is about.
String orderEditSlipLabel(AppLocalizations l10n, OrderEditSlipRecord record) =>
    '${record.orderCode} · ${l10n.kitchenEditChangeNumber(record.editNumber)}';

/// "Print again" for the unsent slip [orderEditId], and what it came to:
///
///  * the kitchen-print snacks of the manual kitchen reprint (sent / no
///    printer / failed);
///  * `posOrderEditPendingBlocked` while the order still carries an edit
///    being sent (or this slip is printing right now);
///  * `posReprintKitchenFetchFailed` when the order could not be re-read;
///  * nothing for a slip a void retired (decision D9);
///  * a NEWER edit: `posOrderEditNewerSlipOffer` with "Print latest" /
///    "Cancel" — when there is something to offer (another till's edit, or
///    a newer unsent slip of this till).
///
/// [context] is read only here, before any await ([OrderEditSlipPrintAgain]).
Future<void> printOrderEditSlipAgain(
  BuildContext context, {
  required String orderEditId,
}) => OrderEditSlipPrintAgain.of(context)(orderEditId);

/// The handles "Print again" runs through, captured from a mounted
/// [BuildContext] BEFORE any await: the [ProviderContainer] (which owns the
/// slip controller), the [ScaffoldMessengerState] for the outcome snack, and
/// the root [NavigatorState] whose context shows the newer-edit offer. None
/// of them depends on the element that offered Print again staying mounted:
/// the banner leaves while its slip prints, and the result toast's action
/// outlives the Orders sheet or preview whose row showed it.
class OrderEditSlipPrintAgain {
  OrderEditSlipPrintAgain.of(BuildContext context)
    : _container = ProviderScope.containerOf(context, listen: false),
      _messenger = ScaffoldMessenger.of(context),
      _navigator = Navigator.of(context, rootNavigator: true),
      _l10n = AppLocalizations.of(context);

  final ProviderContainer _container;
  final ScaffoldMessengerState _messenger;
  final NavigatorState _navigator;
  final AppLocalizations _l10n;

  /// See [printOrderEditSlipAgain].
  Future<void> call(String orderEditId) async {
    final slips = _container.read(orderEditSlipControllerProvider.notifier);
    final result = await slips.printAgain(orderEditId);
    if (result.status != OrderEditPrintAgainStatus.newerEdit) {
      _report(_messenger, _l10n, result);
      return;
    }
    // Only the offer needs a live context: the root navigator's (gone only
    // with the app itself).
    if (!result.hasOffer || !_navigator.mounted) return;
    final printLatest = await showDialog<bool>(
      context: _navigator.context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('order-edit-newer-slip-offer'),
        content: Text(_l10n.posOrderEditNewerSlipOffer),
        actions: [
          TextButton(
            key: const Key('order-edit-newer-slip-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_l10n.adminCancel),
          ),
          FilledButton(
            key: const Key('order-edit-newer-slip-print-latest'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_l10n.posOrderEditPrintLatest),
          ),
        ],
      ),
    );
    if (printLatest != true) return;
    final newer = result.newerLocalOrderEditId;
    final orderId = result.orderId;
    final latest = newer != null
        ? await slips.printAgain(newer)
        : orderId == null
        ? null
        : await slips.printLatest(orderId);
    // A second "newer" answer is not offered again: the banner still holds
    // whatever is left.
    if (latest != null) _report(_messenger, _l10n, latest);
  }
}

void _report(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  OrderEditPrintAgainResult result,
) {
  final String? message = switch (result.status) {
    OrderEditPrintAgainStatus.printed => l10n.posKitchenTicketPrintedSnack,
    OrderEditPrintAgainStatus.notPrinted => switch (result.printOutcome) {
      PosKitchenPrintOutcome.noPrinterConfigured ||
      PosKitchenPrintOutcome.unavailable =>
        l10n.posKitchenPrinterNotConfiguredSnack,
      _ => l10n.posKitchenTicketPrintFailedSnack,
    },
    OrderEditPrintAgainStatus.blocked => l10n.posOrderEditPendingBlocked,
    OrderEditPrintAgainStatus.fetchFailed => l10n.posReprintKitchenFetchFailed,
    OrderEditPrintAgainStatus.retired ||
    OrderEditPrintAgainStatus.newerEdit ||
    OrderEditPrintAgainStatus.notFound => null,
  };
  if (message == null || !messenger.mounted) return;
  messenger.showSnackBar(SnackBar(content: Text(message)));
}
