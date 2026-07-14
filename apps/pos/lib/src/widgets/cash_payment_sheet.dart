import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_identity.dart';
import '../data/payment.dart';
import '../data/payment_repository.dart';
import '../format/cash_input.dart';
import '../format/money_format.dart';
import '../format/payment_method_label.dart';
import '../state/order_sync_controller.dart';
import '../state/payment_controller.dart';
import '../state/recent_orders_controller.dart';

/// The ASCII decimal separator the cash field accepts (mirrors the input
/// formatter's `[0-9.]`). A format character, not user-facing copy.
const String _decimalSeparator = '.';

/// Modal payment entry (RF-116 / RF-117): a TENDER selector (Cash / Card / Bit /
/// External), the amount due, and — for CASH — a cash-received field with an
/// on-screen numeric keypad + quick-cash buttons, LIVE change due, and validation
/// (cash must cover the total). For a NON-CASH tender the cash field/keypad/change
/// are HIDDEN (there is no drawer cash) and an honest note explains that RestoFlow
/// records the tender but processes no card/transfer charge. Confirm records a
/// completed payment via [paymentControllerProvider] and closes the sheet: CASH
/// keeps tendered + change; non-cash records amount = order total, change = 0.
/// Money is integer minor units throughout — no floats.
class CashPaymentSheet extends ConsumerStatefulWidget {
  const CashPaymentSheet({
    required this.identity,
    required this.orderNumber,
    required this.amountMinor,
    required this.currencyCode,
    this.orderId,
    this.expectedRevision,
    super.key,
  });

  /// THE ORDER THIS MONEY IS FOR. Carried explicitly, all the way from the screen that
  /// opened the sheet to the recorded payment, so the money is filed against the order
  /// the cashier is actually looking at — not against whichever order happens to share
  /// its printed code (see [PosOrderIdentity]).
  final PosOrderIdentity identity;

  /// The order's DISPLAY code. Shown, printed, read out — never used to decide which
  /// order this payment belongs to.
  final String orderNumber;
  final int amountMinor;
  final String currencyCode;

  /// POS-OPERATIONS-SYNC-001: the AUTHORITATIVE server revision this payment is
  /// being made against, or null when the client does not know one.
  ///
  /// This finally makes the server's conflict path REACHABLE. Until now the POS
  /// stored no revision and sent none, so `app.record_payment`'s optimistic-
  /// concurrency check could never fire: two tills could each pay an order they both
  /// believed was unpaid, and the loser found out by accident. Now the server can say
  /// "that is not the order you were looking at" — and we refresh instead of retrying.
  final int? expectedRevision;

  /// The server order id (a UUID in real mode) a real `payment.create`
  /// references (RF-130); null/empty on the demo in-memory path (ignored there).
  final String? orderId;

  static Future<void> show(
    BuildContext context, {
    required PosOrderIdentity identity,
    required String orderNumber,
    required int amountMinor,
    required String currencyCode,
    String? orderId,
    int? expectedRevision,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => CashPaymentSheet(
      identity: identity,
      orderNumber: orderNumber,
      amountMinor: amountMinor,
      currencyCode: currencyCode,
      orderId: orderId,
      expectedRevision: expectedRevision,
    ),
  );

  @override
  ConsumerState<CashPaymentSheet> createState() => _CashPaymentSheetState();
}

class _CashPaymentSheetState extends ConsumerState<CashPaymentSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _submitting = false;

  /// DESIGN-001: true after a [PaymentException] — the sheet previously
  /// swallowed the failure and just re-enabled Confirm with ZERO feedback (a
  /// silent dead-end under rush). Renders a pinned danger banner; any new
  /// input or attempt clears it.
  bool _failed = false;

  /// MONEY-SETTLEMENT-CONSISTENCY-001: set ONLY by the server's exact typed
  /// `order_not_chargeable` refusal — a ZERO-TOTAL order owes nothing, so the server
  /// refuses to mint a 0-amount payment or burn a receipt number.
  ///
  /// This is NOT a failure to retry (no retry can ever succeed), so it renders its own
  /// explanatory banner instead of the danger "payment failed" one. It is never inferred
  /// from the order total, a SQLSTATE, or a raw error message.
  bool _notChargeable = false;

  /// POS-OPERATIONS-SYNC-001 (stabilization) — THIS SHEET IS NOW STALE.
  ///
  /// A typed `conflict` means the order moved while this sheet was open: the amount
  /// and the revision it was built from are `widget` fields — immutable for the life
  /// of the sheet — so a second Confirm would re-send THE SAME stale revision and
  /// conflict forever, while the sheet keeps quoting the OLD amount due. The discount
  /// sheet already retires itself on exactly this refusal; this sheet used to flatten
  /// it into the generic "payment failed, check the connection" banner instead — a
  /// false diagnosis over a dead retry button, in front of a cashier who may be
  /// counting out the OLD amount in cash.
  ///
  /// So on a conflict the sheet retires: the row behind it is reconciled, the refusal
  /// is explained in its own words, and Confirm is REPLACED by Close. The next attempt
  /// starts from the refreshed order, which carries the new amount and revision.
  bool _conflictStale = false;

  /// The selected tender (RF-117). Cash is the default; a non-cash tender is
  /// externally recorded (no drawer cash, no change).
  PaymentMethod _method = PaymentMethod.cash;

  /// Clears the RETRYABLE failure banner.
  ///
  /// POS-OPERATIONS-SYNC-001: it deliberately does NOT clear [_notChargeable].
  /// A transport failure is an input-adjacent error — retype, retry, it may work.
  /// `order_not_chargeable` is NOT: the order owes NOTHING, and no tender, amount
  /// or method can change that. It is TERMINAL for this sheet.
  ///
  /// This is the deferred defect from MONEY-SETTLEMENT-CONSISTENCY-001: this method
  /// runs on every keystroke, so clearing the flag here silently re-armed Confirm
  /// and let the cashier fire a second doomed request that the server rejected
  /// again — one useless round trip per keypress.
  void _clearErrors() {
    _failed = false;
  }

  void _selectMethod(PaymentMethod method) {
    if (_method == method) return;
    setState(() {
      _method = method;
      _clearErrors();
    });
  }

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
    setState(_clearErrors);
  }

  /// Keypad wiring (design-polish): the on-screen keypad appends into the SAME
  /// controller behind the cash-received TextField, which stays the single
  /// source of truth (and keeps `tester.enterText` working).
  void _appendChar(String ch) {
    final text = _controller.text + ch;
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
    setState(_clearErrors);
  }

  void _backspace() {
    final text = _controller.text;
    if (text.isEmpty) return;
    final next = text.substring(0, text.length - 1);
    _controller.text = next;
    _controller.selection = TextSelection.collapsed(offset: next.length);
    setState(_clearErrors);
  }

  Future<void> _confirm() async {
    // CASH must physically cover the total; a NON-CASH tender records the exact
    // order total (the server forces tendered = total, change = 0 anyway).
    final int tendered;
    if (_method.isCash) {
      final entered = _tenderedMinor;
      if (entered == null || entered < widget.amountMinor) return;
      tendered = entered;
    } else {
      tendered = widget.amountMinor;
    }
    setState(() {
      _submitting = true;
      _clearErrors();
    });
    final navigator = Navigator.of(context);
    // CAPTURED BEFORE THE AWAIT. The sheet is drag/barrier-dismissible while the push
    // is in flight; touching the WIDGET's `ref` after a dismissal throws, and skipping
    // the reconcile/refusal because the sheet died would leave the row behind it
    // stale. The notifiers outlive the sheet — the work completes either way.
    final payments = ref.read(paymentControllerProvider.notifier);
    final orders = ref.read(posRecentOrdersControllerProvider.notifier);
    final sync = ref.read(posOrderSyncControllerProvider.notifier);
    try {
      await payments.payCash(
        identity: widget.identity,
        orderId: widget.orderId ?? '',
        orderNumber: widget.orderNumber,
        amountMinor: widget.amountMinor,
        tenderedMinor: tendered,
        currencyCode: widget.currencyCode,
        method: _method,
        expectedRevision: widget.expectedRevision,
      );
      // POS-OPERATIONS-SYNC-001: take the AUTHORITATIVE order state after the write.
      // record_payment's envelope carries order_status and auto_completed but NOT the
      // money or the settlement, and a payment that auto-completes a served order
      // changes BOTH. We do not infer completion from "the button worked" — we ask.
      await _reconcile(sync);
      // The sheet is drag/barrier-dismissible while the push is in flight;
      // popping an already-dismissed sheet would pop the ROOT POS route.
      if (mounted) navigator.pop();
    } on PaymentException catch (e) {
      // DESIGN-001: an honest, visible failure — the payment was NOT recorded
      // and the cashier must know. The banner below the sheet body says so;
      // Confirm stays enabled as the retry.
      //
      // MONEY-SETTLEMENT-CONSISTENCY-001: a NON-CHARGEABLE order is NOT a failure to
      // retry — the order owes nothing and no retry can ever succeed. It gets its own
      // banner, driven by the server's EXACT typed code (never by a guess at the total).
      //
      // A CONFLICT retires the sheet outright (see [_conflictStale]): it is neither
      // the retryable danger banner (retrying the same revision cannot ever succeed)
      // nor the non-chargeable one (the order may well still owe money — just not
      // the amount this sheet was opened with).
      if (mounted) {
        setState(() {
          _submitting = false;
          _failed = !e.notChargeable && !e.conflict;
          _notChargeable = e.notChargeable;
          _conflictStale = _conflictStale || e.conflict;
        });
      }
      if (e.conflict) {
        // POS-OPERATIONS-SYNC-001: the order moved under us. NEVER auto-retry -- the
        // amount on this sheet was computed from a state the server has just told us
        // is stale, and re-sending it is how an order gets charged twice. Reconcile
        // and let the cashier decide against the truth.
        await _reconcile(sync);
      }
      if (e.notChargeable) {
        // POS-OPERATIONS-SYNC-001: the refusal means our local total is WRONG — the
        // order was comped somewhere we did not see. Correcting the banner while
        // leaving "40" on the row would explain nothing. Reconcile, so the row shows
        // 0 / No charge and the unpaid badge lets it go.
        orders.recordSyncRefusal(widget.identity, 'order_not_chargeable');
        await _reconcile(sync);
      }
    }
  }

  /// Pulls the authoritative snapshot for THIS order through the CAPTURED coordinator
  /// (never the widget's `ref`, which dies with a dismissed sheet). Never throws: the
  /// coordinator records its own failure, and a failed refresh must not turn a
  /// SUCCESSFUL payment into an error the cashier sees.
  Future<void> _reconcile(PosOrderSyncController sync) async {
    final orderId = widget.orderId;
    if (orderId == null || orderId.isEmpty) return;
    await sync.refreshOrders(<String>[orderId]);
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
    final isCash = _method.isCash;
    final tendered = _tenderedMinor;
    final hasInput = _controller.text.trim().isNotEmpty;
    final invalid = isCash && hasInput && tendered == null;
    final insufficient =
        isCash && tendered != null && tendered < widget.amountMinor;
    // Cash: the tender must cover the total. Non-cash: nothing to type, so the
    // Confirm is enabled as soon as the sheet is not submitting.
    //
    // POS-OPERATIONS-SYNC-001: a NON-CHARGEABLE order disables Confirm outright.
    // The order owes nothing; the server has already refused and will refuse every
    // identical retry. Leaving the button live only lets the cashier manufacture
    // rejected sync operations while believing they are making progress.
    final canConfirm =
        !_notChargeable &&
        !_conflictStale &&
        (isCash
            ? (tendered != null &&
                  tendered >= widget.amountMinor &&
                  !_submitting)
            : !_submitting);
    final changeMinor =
        (isCash && tendered != null && tendered >= widget.amountMinor)
        ? tendered - widget.amountMinor
        : null;

    final String? errorText = invalid
        ? l10n.posCashInvalid
        : (insufficient ? l10n.posCashInsufficient : null);

    return SafeArea(
      // DESIGN-001 (review fix): scrollable body. The tallest configuration
      // is exactly the FAILURE state (banner + keypad + change row); on short
      // POS displays (e.g. 1366×768) a fixed Column clipped the Confirm/retry
      // button the moment the cashier most needed it.
      child: SingleChildScrollView(
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
                  isCash ? l10n.posPaymentTitle : l10n.posExternalPaymentTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: RestoflowSpacing.md),
            // RF-117: the tender selector (Cash / Card / Bit / External).
            _TenderSelector(
              l10n: l10n,
              selected: _method,
              enabled: !_submitting && !_conflictStale,
              onSelect: _selectMethod,
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
            // CASH: the cash-received field + quick-cash + keypad + live change.
            // NON-CASH: hidden (no drawer cash) — an honest external-tender note.
            if (isCash) ...[
              TextField(
                key: const Key('cash-received-field'),
                controller: _controller,
                autofocus: true,
                // TABLET-UX-001 (D): the sheet has its own on-screen numeric
                // keypad, so the device soft keyboard must NOT cover the screen.
                // TextInputType.none suppresses the on-screen keyboard while the
                // field stays focused/editable — the custom keypad appends into
                // the same controller, a hardware keyboard still types, and
                // `tester.enterText` keeps working.
                keyboardType: TextInputType.none,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                // Hardware-keyboard edits clear a stale failure banner too
                // (the on-screen keypad path clears it via _appendChar).
                onChanged: (_) => setState(_clearErrors),
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
                      // Design-polish: >=48dp quick-cash targets.
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(64, 48),
                        textStyle: theme.textTheme.titleSmall,
                      ),
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
              // Design-polish: a large on-screen keypad (touch terminals have no
              // OS keyboard) appending into the same controller as the field.
              RestoflowNumericKeypad(
                onDigit: _appendChar,
                onBackspace: _backspace,
                enabled: !_submitting && !_conflictStale,
                buttonHeight: 52,
                trailingKey: FilledButton.tonal(
                  onPressed: _submitting
                      ? null
                      : () => _appendChar(_decimalSeparator),
                  style: FilledButton.styleFrom(
                    textStyle: theme.textTheme.titleLarge,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text(_decimalSeparator),
                ),
              ),
              const SizedBox(height: RestoflowSpacing.md),
              _ChangeDueRow(
                label: l10n.posChangeDue,
                value: changeMinor == null
                    ? '—'
                    : MoneyFormatter.formatMinor(
                        changeMinor,
                        widget.currencyCode,
                      ),
                hasChange: changeMinor != null,
              ),
            ] else
              _NonCashNote(message: l10n.posNonCashNote),
            if (_notChargeable) ...[
              const SizedBox(height: RestoflowSpacing.md),
              // MONEY-SETTLEMENT-CONSISTENCY-001: the server's typed
              // `order_not_chargeable` refusal. NOT a danger/retry banner — the order
              // owes nothing, so retrying can never succeed. Telling the cashier to
              // "try again" here would be a lie.
              RestoflowNoticeBanner(
                key: const Key('payment-not-chargeable-banner'),
                tone: RestoflowTone.info,
                title: l10n.posNoChargeChip,
                body: l10n.posNoChargeNoPayment,
              ),
            ],
            if (_conflictStale) ...[
              const SizedBox(height: RestoflowSpacing.md),
              // THE ORDER MOVED. Not a danger banner — nothing here is broken to
              // retry — and not "no charge" either: the order may still owe money,
              // just not the amount this sheet was opened with. The refreshed truth
              // is already on the row behind this sheet.
              RestoflowNoticeBanner(
                key: const Key('payment-conflict-banner'),
                tone: RestoflowTone.warning,
                title: l10n.posPaymentFailedTitle,
                body: l10n.posOrdersConflictRefreshed,
              ),
            ],
            if (_failed) ...[
              const SizedBox(height: RestoflowSpacing.md),
              // DESIGN-001: the payment-failure banner — pinned in the sheet
              // (not a transient SnackBar), danger tone, honest about state.
              // Every OTHER failure (transport, malformed envelope, generic rejection)
              // lands here and stays retryable.
              RestoflowNoticeBanner(
                key: const Key('payment-failed-banner'),
                tone: RestoflowTone.danger,
                title: l10n.posPaymentFailedTitle,
                body: l10n.posPaymentFailedBody,
              ),
            ],
            const SizedBox(height: RestoflowSpacing.md),
            SizedBox(
              width: double.infinity,
              child: _conflictStale
                  // RETIRED. There is no Confirm to press: the amount and revision
                  // this sheet holds are the ones the server just refused, and
                  // re-sending them can never succeed. The cashier acknowledges and
                  // acts again from the refreshed order.
                  ? FilledButton.icon(
                      key: const Key('payment-conflict-close-button'),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.posOrdersConflictClose),
                      style: RestoflowButtonStyles.big(context),
                    )
                  : FilledButton.icon(
                      key: const Key('confirm-payment-button'),
                      onPressed: canConfirm ? _confirm : null,
                      // While the push is in flight the button says so (finite:
                      // the spinner exists only between tap and result).
                      icon: _submitting
                          ? const RestoflowInlineSpinner()
                          : const Icon(Icons.check),
                      label: Text(l10n.posConfirmPayment),
                      style: RestoflowButtonStyles.big(context),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The RF-117 tender selector: a Wrap of choice chips (Cash / Card / Bit /
/// External) so the row wraps on a narrow sheet instead of overflowing. Each
/// chip carries a stable Key for tests.
class _TenderSelector extends StatelessWidget {
  const _TenderSelector({
    required this.l10n,
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  final AppLocalizations l10n;
  final PaymentMethod selected;
  final bool enabled;
  final ValueChanged<PaymentMethod> onSelect;

  static const Map<PaymentMethod, String> _keys = <PaymentMethod, String>{
    PaymentMethod.cash: 'tender-cash',
    PaymentMethod.card: 'tender-card',
    PaymentMethod.bit: 'tender-bit',
    PaymentMethod.externalTender: 'tender-external',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.posTenderTypeLabel,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.xs),
        Wrap(
          spacing: RestoflowSpacing.sm,
          runSpacing: RestoflowSpacing.xs,
          children: [
            for (final method in PaymentMethod.values)
              ChoiceChip(
                key: Key(_keys[method]!),
                label: Text(paymentMethodLabel(l10n, method)),
                selected: selected == method,
                onSelected: enabled ? (_) => onSelect(method) : null,
              ),
          ],
        ),
      ],
    );
  }
}

/// The honest non-cash note: RestoFlow records the tender but processes no real
/// charge (RF-117). Neutral info tone, distinct from the change readout.
class _NonCashNote extends StatelessWidget {
  const _NonCashNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('non-cash-note'),
      width: double.infinity,
      padding: const EdgeInsets.all(RestoflowSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: RestoflowIconSizes.sm,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The change-due readout — deliberately the LOUDEST element on the sheet:
/// it is the number the cashier reads aloud while handing coins back. Fills
/// with the true-green SUCCESS tone once the tender covers the total; shows a
/// quiet em-dash placeholder until then (exact text format unchanged).
class _ChangeDueRow extends StatelessWidget {
  const _ChangeDueRow({
    required this.label,
    required this.value,
    required this.hasChange,
  });

  final String label;
  final String value;
  final bool hasChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final success = RestoflowTone.success.styleOf(theme);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.md,
        vertical: RestoflowSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: hasChange
            ? success.container
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              color: hasChange
                  ? success.onContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            key: const Key('change-due-amount'),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: hasChange
                  ? success.onContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    this.emphasised = false,
  });

  final String label;
  final String value;
  final bool emphasised;

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
        Text(value, style: valueStyle),
      ],
    );
  }
}
