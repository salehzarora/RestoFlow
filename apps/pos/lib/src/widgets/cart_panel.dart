import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../format/money_format.dart';
import '../state/cart_controller.dart';
import 'order_confirmation.dart';

/// The live cart/order panel: a header with item count + clear, the list of
/// cart lines with quantity steppers + remove, and a footer with the subtotal
/// and a Send Order action. After a local submit (RF-101) it shows the
/// in-place [OrderConfirmation] instead of the cart.
///
/// Reads/mutates the in-memory [cartControllerProvider]. Chrome is localized;
/// item names are data; amounts are formatted integer minor-unit money. Send
/// Order builds an in-memory demo order only — NO backend, kitchen, or printer.
class CartPanel extends ConsumerWidget {
  const CartPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cart = ref.watch(cartControllerProvider);
    final controller = ref.read(cartControllerProvider.notifier);

    final submittedOrder = cart.submittedOrder;
    if (submittedOrder != null) {
      return OrderConfirmation(
        order: submittedOrder,
        onNewOrder: controller.startNewOrder,
      );
    }

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          _CartHeader(
            l10n: l10n,
            itemCount: cart.itemCount,
            onClear: cart.isEmpty ? null : controller.clear,
          ),
          const Divider(height: 1),
          Expanded(
            child: cart.isEmpty
                ? _EmptyCart(message: l10n.posCartEmpty)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      vertical: RestoflowSpacing.sm,
                    ),
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final line = cart.lines[index];
                      return _CartLineTile(
                        line: line,
                        l10n: l10n,
                        onIncrease: () =>
                            controller.increaseQuantity(line.lineId),
                        onDecrease: () =>
                            controller.decreaseQuantity(line.lineId),
                        onRemove: () => controller.removeLine(line.lineId),
                      );
                    },
                  ),
          ),
          _CartFooter(
            l10n: l10n,
            subtotalText: MoneyFormatter.format(cart.subtotal),
            onSend: cart.isEmpty ? null : controller.submitOrder,
          ),
        ],
      ),
    );
  }
}

class _CartHeader extends StatelessWidget {
  const _CartHeader({
    required this.l10n,
    required this.itemCount,
    required this.onClear,
  });

  final AppLocalizations l10n;
  final int itemCount;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final countText = itemCount.toString();

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.lg,
        RestoflowSpacing.md,
        RestoflowSpacing.sm,
        RestoflowSpacing.md,
      ),
      child: Row(
        children: [
          Icon(Icons.shopping_cart_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: RestoflowSpacing.sm),
          Text(
            l10n.posCartTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (itemCount > 0) ...[
            const SizedBox(width: RestoflowSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: RestoflowSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(RestoflowRadii.pill),
              ),
              child: Text(
                countText,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (onClear != null)
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: Text(l10n.posClearCart),
            ),
        ],
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.remove_shopping_cart_outlined,
              size: 40,
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: RestoflowSpacing.lg),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    required this.line,
    required this.l10n,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
  });

  final CartLineView line;
  final AppLocalizations l10n;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unitPriceText = MoneyFormatter.format(line.unitPrice);
    final lineTotalText = MoneyFormatter.format(line.lineTotal);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.lg,
        RestoflowSpacing.sm,
        RestoflowSpacing.sm,
        RestoflowSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  unitPriceText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _QuantityStepper(
            quantity: line.quantity,
            l10n: l10n,
            onIncrease: onIncrease,
            onDecrease: onDecrease,
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          SizedBox(
            width: 76,
            child: Text(
              lineTotalText,
              textAlign: TextAlign.end,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: l10n.posRemoveItem,
            color: theme.colorScheme.error,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.l10n,
    required this.onIncrease,
    required this.onDecrease,
  });

  final int quantity;
  final AppLocalizations l10n;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quantityText = quantity.toString();

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(RestoflowRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            icon: Icons.remove,
            tooltip: l10n.posDecreaseQuantity,
            onPressed: onDecrease,
          ),
          SizedBox(
            width: 28,
            child: Text(
              quantityText,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add,
            tooltip: l10n.posIncreaseQuantity,
            onPressed: onIncrease,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      iconSize: 18,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _CartFooter extends StatelessWidget {
  const _CartFooter({
    required this.l10n,
    required this.subtotalText,
    required this.onSend,
  });

  final AppLocalizations l10n;
  final String subtotalText;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: theme.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.all(RestoflowSpacing.lg),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.posCartSubtotal, style: theme.textTheme.titleMedium),
                Text(
                  subtotalText,
                  key: const Key('cart-subtotal'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: RestoflowSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onSend,
                icon: const Icon(Icons.send),
                label: Text(l10n.posSendOrder),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
