import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/parked_carts_store.dart';
import '../format/money_format.dart';
import '../state/parked_carts_controller.dart';

/// PARKED-CARTS-001 — the parked-orders surface.
///
/// Every action here is LOCAL: restoring brings a draft back into the cart and
/// deleting discards a draft. Nothing sends, prints, pays, or claims a table.

/// The cart-header control: a compact button carrying the parked-cart count.
/// Hidden entirely at zero, so the header stays quiet on a till that never parks.
class ParkedOrdersButton extends ConsumerWidget {
  const ParkedOrdersButton({super.key, this.compact = false});

  /// At narrow widths the label is dropped and the tooltip carries the meaning.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final count = ref.watch(parkedCartsCountProvider);
    if (count == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final tooltip = l10n.posParkedOrdersTooltip(count);
    final badge = Container(
      key: const Key('parked-orders-badge'),
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.xs,
        vertical: RestoflowSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(RestoflowRadii.pill),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        key: const Key('parked-orders-button'),
        onPressed: () => showParkedOrdersSheet(context),
        icon: const Icon(Icons.inventory_2_outlined, size: 18),
        label: compact
            ? badge
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      l10n.posParkedOrders,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: RestoflowSpacing.xs),
                  badge,
                ],
              ),
      ),
    );
  }
}

/// Opens the parked-orders sheet.
Future<void> showParkedOrdersSheet(BuildContext context) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const ParkedOrdersSheet(),
    );

class ParkedOrdersSheet extends ConsumerWidget {
  const ParkedOrdersSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(parkedCartsControllerProvider);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          key: const Key('parked-orders-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RestoflowSpacing.lg,
                RestoflowSpacing.lg,
                RestoflowSpacing.sm,
                RestoflowSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: RestoflowSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.posParkedOrders,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: kRestoflowInk,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('parked-orders-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _Body(state: state, l10n: l10n),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state, required this.l10n});

  final ParkedCartsState state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.loading) {
      // A STATIC placeholder on purpose: an indeterminate progress indicator
      // never settles, so a widget test that pumps to settle would hang here.
      return Padding(
        key: const Key('parked-orders-loading'),
        padding: const EdgeInsets.all(RestoflowSpacing.xl),
        child: Center(child: Text(l10n.posParkedOrdersLoading)),
      );
    }
    if (state.loadFailed) {
      return Padding(
        key: const Key('parked-orders-error'),
        padding: const EdgeInsets.all(RestoflowSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: RestoflowTone.danger.styleOf(Theme.of(context)).accent,
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            Text(l10n.posParkedOrdersLoadFailed, textAlign: TextAlign.center),
            const SizedBox(height: RestoflowSpacing.sm),
            FilledButton(
              key: const Key('parked-orders-retry'),
              onPressed: () =>
                  ref.read(parkedCartsControllerProvider.notifier).load(),
              child: Text(l10n.posParkedOrdersRetry),
            ),
          ],
        ),
      );
    }
    if (state.isEmpty) {
      return Padding(
        key: const Key('parked-orders-empty'),
        padding: const EdgeInsets.all(RestoflowSpacing.xl),
        child: Center(child: Text(l10n.posParkedOrdersEmpty)),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
      itemCount: state.carts.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) =>
          _ParkedRow(cart: state.carts[index], l10n: l10n),
    );
  }
}

class _ParkedRow extends ConsumerWidget {
  const _ParkedRow({required this.cart, required this.l10n});

  final ParkedCart cart;
  final AppLocalizations l10n;

  /// The row's display name: the cashier's label / customer name when there is
  /// one, else a neutral fallback. The customer PHONE is deliberately not shown
  /// in the list — it is not needed to tell two drafts apart.
  String get _title =>
      cart.label ?? cart.customerName ?? l10n.posParkedUnnamedOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final typeLabel = cart.orderType == OrderType.dineIn
        ? l10n.posOrderTypeDineIn
        : l10n.posOrderTypeTakeaway;
    final table = cart.table;
    final summary = <String>[
      typeLabel,
      if (cart.orderType == OrderType.dineIn && table != null)
        '${l10n.posTableLabel} ${table.label}',
      l10n.posParkedItemCount(cart.itemCount),
    ].join(' · ');
    final items = cart.draft.lines
        .map((l) => l.quantity > 1 ? '${l.quantity}× ${l.name}' : l.name)
        .join(', ');

    return Padding(
      key: Key('parked-order-${cart.id}'),
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.lg,
        vertical: RestoflowSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              Text(
                MoneyFormatter.formatMinor(
                  cart.subtotalMinor,
                  cart.currencyCode,
                ),
                key: Key('parked-order-total-${cart.id}'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: RestoflowSpacing.xxs),
          Text(
            summary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: kRestoflowInk2),
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: RestoflowSpacing.xxs),
            Text(
              items,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: kRestoflowInk2),
            ),
          ],
          const SizedBox(height: RestoflowSpacing.xxs),
          Text(
            l10n.posParkedAt(_formatTime(context, cart.updatedAt)),
            style: theme.textTheme.bodySmall?.copyWith(color: kRestoflowInk2),
          ),
          const SizedBox(height: RestoflowSpacing.xs),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: Key('parked-order-restore-${cart.id}'),
                  onPressed: () => _restore(context, ref),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text(l10n.posParkedRestore),
                ),
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              TextButton.icon(
                key: Key('parked-order-delete-${cart.id}'),
                onPressed: () => _confirmDelete(context, ref),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(l10n.posParkedDelete),
                style: TextButton.styleFrom(
                  foregroundColor: RestoflowTone.danger.styleOf(theme).accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// A locale-aware, already-formatted local time for the "Parked {time}" row.
  String _formatTime(BuildContext context, DateTime at) =>
      TimeOfDay.fromDateTime(at.toLocal()).format(context);

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final controller = ref.read(parkedCartsControllerProvider.notifier);

    var outcome = await controller.restore(cart.id);
    if (outcome.status == RestoreStatus.activeCartNotEmpty) {
      if (!context.mounted) return;
      // The ONLY two honest choices: park what is on the till and restore, or
      // do nothing. Never merge, overwrite, clear or discard.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const Key('parked-order-replace-dialog'),
          title: Text(l10n.posParkedActiveCartTitle),
          content: Text(l10n.posParkedActiveCartBody),
          actions: [
            TextButton(
              key: const Key('parked-order-replace-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                MaterialLocalizations.of(dialogContext).cancelButtonLabel,
              ),
            ),
            FilledButton(
              key: const Key('parked-order-replace-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.posParkedParkCurrentAndRestore),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      outcome = await controller.restore(cart.id, parkCurrentFirst: true);
    }

    final message = switch (outcome.status) {
      RestoreStatus.restored =>
        outcome.entryRetained
            ? l10n.posParkedCopyRetained
            : (outcome.tableUnavailable
                  ? l10n.posParkedTableUnavailable
                  : (outcome.unavailableItems.isNotEmpty
                        ? '${l10n.posRecoveryUnavailableItems} '
                              '${outcome.unavailableItems.join(', ')}'
                        : null)),
      RestoreStatus.blockedByAddition => l10n.posParkedBlockedByAddition,
      _ => l10n.posParkedRestoreFailed,
    };
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
    if (outcome.ok && navigator.canPop()) navigator.pop();
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('parked-order-delete-dialog'),
        title: Text(l10n.posParkedDeleteTitle),
        // The body NAMES the selected draft, so the cashier can see which one
        // they are about to discard.
        content: Text(l10n.posParkedDeleteBody(_title)),
        actions: [
          TextButton(
            key: const Key('parked-order-delete-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          FilledButton(
            key: const Key('parked-order-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.posParkedDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // Delete by STABLE id — never by list position.
    final result = await ref
        .read(parkedCartsControllerProvider.notifier)
        .delete(cart.id);
    if (result != DeleteResult.deleted) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.posParkedRestoreFailed)),
      );
    }
  }
}
