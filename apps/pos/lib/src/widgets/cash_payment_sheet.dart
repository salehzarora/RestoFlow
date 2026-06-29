import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/payment_repository.dart';
import '../format/cash_input.dart';
import '../format/money_format.dart';
import '../state/payment_controller.dart';

/// Modal cash-payment entry (RF-116): amount due, a cash-received field with
/// quick-cash buttons, LIVE change due, and validation (cash must cover the
/// total; reject empty / invalid / insufficient). Confirm records a completed
/// cash payment via [paymentControllerProvider] and closes the sheet. Money is
/// integer minor units throughout — no floats.
class CashPaymentSheet extends ConsumerStatefulWidget {
  const CashPaymentSheet({
    required this.orderNumber,
    required this.amountMinor,
    required this.currencyCode,
    this.orderId,
    super.key,
  });

  final String orderNumber;
  final int amountMinor;
  final String currencyCode;

  /// The server order id (a UUID in real mode) a real `payment.create`
  /// references (RF-130); null/empty on the demo in-memory path (ignored there).
  final String? orderId;

  static Future<void> show(
    BuildContext context, {
    required String orderNumber,
    required int amountMinor,
    required String currencyCode,
    String? orderId,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => CashPaymentSheet(
      orderNumber: orderNumber,
      amountMinor: amountMinor,
      currencyCode: currencyCode,
      orderId: orderId,
    ),
  );

  @override
  ConsumerState<CashPaymentSheet> createState() => _CashPaymentSheetState();
}

class _CashPaymentSheetState extends ConsumerState<CashPaymentSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? get _tenderedMinor =>
      parseCashToMinor(_controller.text, fractionDigits: 2);

  void _setAmount(int minor) {
    final digits = minor % 100;
    final text = '${minor ~/ 100}.${digits.toString().padLeft(2, '0')}';
    _controller.text = text;
    setState(() {});
  }

  Future<void> _confirm() async {
    final tendered = _tenderedMinor;
    if (tendered == null || tendered < widget.amountMinor) return;
    setState(() => _submitting = true);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(paymentControllerProvider.notifier)
          .payCash(
            orderId: widget.orderId ?? '',
            orderNumber: widget.orderNumber,
            amountMinor: widget.amountMinor,
            tenderedMinor: tendered,
            currencyCode: widget.currencyCode,
          );
      navigator.pop();
    } on PaymentException {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Quick-cash suggestions: the exact amount, then round-ups to ₪10 / ₪50 /
  /// ₪100 above it.
  List<int> get _quickAmounts {
    final set = <int>{widget.amountMinor};
    for (final step in <int>[1000, 5000, 10000]) {
      final up = ((widget.amountMinor + step - 1) ~/ step) * step;
      if (up > widget.amountMinor) set.add(up);
    }
    final list = set.toList()..sort();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tendered = _tenderedMinor;
    final hasInput = _controller.text.trim().isNotEmpty;
    final invalid = hasInput && tendered == null;
    final insufficient = tendered != null && tendered < widget.amountMinor;
    final canConfirm =
        tendered != null && tendered >= widget.amountMinor && !_submitting;
    final changeMinor = (tendered != null && tendered >= widget.amountMinor)
        ? tendered - widget.amountMinor
        : null;

    final String? errorText = invalid
        ? l10n.posCashInvalid
        : (insufficient ? l10n.posCashInsufficient : null);

    return SafeArea(
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          RestoflowSpacing.lg,
          0,
          RestoflowSpacing.lg,
          RestoflowSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payments_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: RestoflowSpacing.sm),
                Text(
                  l10n.posPaymentTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: RestoflowSpacing.md),
            _AmountRow(
              label: l10n.posAmountDue,
              value: MoneyFormatter.formatMinor(
                widget.amountMinor,
                widget.currencyCode,
              ),
              emphasised: true,
            ),
            const SizedBox(height: RestoflowSpacing.md),
            TextField(
              key: const Key('cash-received-field'),
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.posCashReceived,
                border: const OutlineInputBorder(),
                errorText: errorText,
              ),
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            Wrap(
              spacing: RestoflowSpacing.sm,
              runSpacing: RestoflowSpacing.sm,
              children: [
                for (final amount in _quickAmounts)
                  OutlinedButton(
                    key: amount == widget.amountMinor
                        ? const Key('quick-cash-exact')
                        : null,
                    onPressed: () => _setAmount(amount),
                    child: Text(
                      amount == widget.amountMinor
                          ? l10n.posCashExact
                          : MoneyFormatter.formatMinor(
                              amount,
                              widget.currencyCode,
                            ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: RestoflowSpacing.md),
            _AmountRow(
              label: l10n.posChangeDue,
              value: changeMinor == null
                  ? '—'
                  : MoneyFormatter.formatMinor(
                      changeMinor,
                      widget.currencyCode,
                    ),
              valueKey: const Key('change-due-amount'),
            ),
            const SizedBox(height: RestoflowSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('confirm-payment-button'),
                onPressed: canConfirm ? _confirm : null,
                icon: const Icon(Icons.check),
                label: Text(l10n.posConfirmPayment),
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

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    this.emphasised = false,
    this.valueKey,
  });

  final String label;
  final String value;
  final bool emphasised;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = emphasised
        ? theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          )
        : theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.titleMedium),
        Text(value, key: valueKey, style: valueStyle),
      ],
    );
  }
}
