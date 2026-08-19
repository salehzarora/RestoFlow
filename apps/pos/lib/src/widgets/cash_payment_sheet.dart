import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_currency/restoflow_currency.dart'
    show CurrencySymbolStyle, formatCurrencyMinor, quickAmountStepsMinor;
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;

import '../data/order_detail_repository.dart'
    show authoritativeReceiptSource, orderDetailRepositoryProvider;
import '../data/order_identity.dart';
import '../data/payment.dart';
import '../data/payment_repository.dart';
import '../format/cash_input.dart';
import '../format/money_format.dart';
import '../format/payment_method_label.dart';
import '../print/native_print_bridges.dart'
    show posActivePrintBridgeReadyProvider, posReceiptReadinessResolverProvider;
import '../print/pos_cash_drawer_service.dart'
    show PosCashDrawerOutcome, posCashDrawerServiceProvider;
import '../state/pos_offline_state.dart'
    show blockPosActionWhileOffline, blockPosPaymentUntilSubmitAccepted;
import '../state/pos_receipt_logo.dart' show posReceiptLogoAssetProvider;
import '../state/order_sync_controller.dart';
import '../state/payment_controller.dart';
import '../state/pos_printer_assignments.dart' show posRestaurantNameProvider;
import '../state/receipt_print_controller.dart';
import '../state/recent_orders_controller.dart';
import 'receipt_print_preview.dart' show buildReceiptDocument;

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

  /// POS-OPEN-ORDER-PAYMENT-DISMISS-019: resolves to TRUE only on the one
  /// authoritative success edge (`payCash` returned and the sheet popped
  /// itself with a result). Every other exit — cancel button, drag/barrier
  /// dismissal, a refused/failed/conflicted attempt the cashier then closes,
  /// or either honest pre-open gate — resolves FALSE, so a caller can dismiss
  /// its own surface after a genuine payment and ONLY then.
  static Future<bool> show(
    BuildContext context, {
    required PosOrderIdentity identity,
    required String orderNumber,
    required int amountMinor,
    required String currencyCode,
    String? orderId,
    int? expectedRevision,
    // [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass B] The central policy's
    // answer to "has the server acknowledged this order's submit?"
    // (`PosOrderActions.submitUnacknowledged`). FALSE BY DEFAULT — unknown is
    // never denied, exactly like the predicate that computes it.
    bool submitUnacknowledged = false,
  }) {
    // [POS-OFFLINE-OPERATIONS-002] C11 — payment is a server-backed action
    // (`record_payment` is authorized + audited server-side), so while the POS
    // provably operates from the offline snapshot the ONE entry point refuses
    // with the honest localized reason instead of opening a sheet whose
    // Confirm can only fail. Gated HERE so every caller (confirmation, orders
    // centre, detail preview) behaves identically; payment logic is untouched.
    if (blockPosActionWhileOffline(context)) return Future.value(false);
    // Pass B — the ORDER-SCOPED sibling of that gate. The till may be perfectly
    // online while THIS order's submit is still queued; `record_payment` would
    // answer `order not found` and the sheet would blame the network for it.
    // Same idiom, different question, its own honest message.
    if (blockPosPaymentUntilSubmitAccepted(
      context,
      submitUnacknowledged: submitUnacknowledged,
    )) {
      return Future.value(false);
    }
    return showModalBottomSheet<bool>(
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
      // A dismissed/cancelled sheet pops with no result — that is NOT success.
    ).then((paid) => paid ?? false);
  }

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

  // OPS-043 Phase 2: the tender's decimals come from the ORDER's currency.
  // With a hardcoded 2 a 1,000 yen note was booked as 100,000 yen.
  int? get _tenderedMinor =>
      parseCashToMinor(_controller.text, currencyCode: widget.currencyCode);

  /// Writes a minor-unit amount back into the text field in MAJOR units.
  ///
  /// This used to be `minor % 100` / `minor ~/ 100`, i.e. two decimals
  /// hardcoded: tapping a quick amount at a JPY till wrote "10.00" for 1000
  /// yen, which then re-parsed to a different number than the button meant.
  /// The shared formatter emits exactly the digits the currency has, and the
  /// parser above accepts exactly that shape, so the round-trip is closed.
  void _setAmount(int minor) {
    _controller.text = formatCurrencyMinor(
      minor,
      widget.currencyCode,
      style: CurrencySymbolStyle.bare,
    );
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
    // DEFERRED-PAYMENT-RECEIPTS-001: the receipt seams, captured on the same
    // rule as the notifiers above — the sheet is dismissible mid-flight, and the
    // paid receipt must still be requested. Reading `ref` after a dismissal
    // throws; these outlive the sheet.
    final receiptRef = ref;
    final l10n = AppLocalizations.of(context);
    // POS-CASH-DRAWER-AUTO-OPEN: the drawer seams, captured on the SAME
    // before-the-await rule. The service outlives the sheet; the messenger is
    // captured so the one failure snackbar can be shown even after the sheet
    // (and its context) are gone.
    final drawer = ref.read(posCashDrawerServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final payment = await payments.payCash(
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
      // DEFERRED-PAYMENT-RECEIPTS-001: THE PAYMENT COMMAND EDGE. `payCash`
      // returning without throwing is authoritative success, so this is the one
      // place a receipt may be requested — never a passive observer of a paid
      // status during hydration, which would reprint on every refresh.
      //
      // On the IMMEDIATE checkout path OrderConfirmation also requests the same
      // receipt; ReceiptPrintController is keyed per order identity and refuses
      // a job that already exists, so whichever fires first wins and the other
      // is a no-op. Exactly one receipt either way.
      //
      // Deliberately AFTER the payment is recorded and BEFORE the pop, and
      // deliberately not awaited into the payment result: a print failure must
      // never roll back a successful payment.
      unawaited(_requestPaidReceipt(receiptRef, l10n));
      // POS-CASH-DRAWER-AUTO-OPEN: the drawer kick fires from the SAME
      // authoritative payment edge as the receipt — never from an observer of
      // a paid status (which would re-pulse on every hydration/refresh). The
      // service itself enforces cash-only (RF-074), the per-device toggle, and
      // the durable claim-before-send at-most-once guarantee; receipt and
      // drawer stay fully independent (neither outcome touches the other, or
      // payment state). Unawaited: the sheet never blocks on hardware. Every
      // skip is silent; only a REAL expected-drawer send failure earns the one
      // non-blocking snackbar, through the pre-await messenger capture.
      unawaited(
        drawer
            .kickForPayment(payment)
            .then((outcome) {
              // PR #205 review N3: the kick can settle after the sheet — or
              // the whole app shell — is gone. A dead messenger silently
              // skips the warning (the payment stayed successful and the
              // cashier has the manual release); it must never surface as an
              // unhandled async error from a SUCCESSFUL payment.
              if (outcome != PosCashDrawerOutcome.sendFailed) return;
              if (!messenger.mounted) return;
              messenger.showSnackBar(
                SnackBar(content: Text(l10n.posCashDrawerOpenFailed)),
              );
            })
            .catchError((_) {}),
      );
      // The sheet is drag/barrier-dismissible while the push is in flight;
      // popping an already-dismissed sheet would pop the ROOT POS route.
      // 019: the pop CARRIES the success result — the one authoritative edge
      // (`payCash` returned) is the only place `true` can ever originate.
      if (mounted) navigator.pop(true);
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
  /// Requests the NORMAL paid customer receipt for the order just paid.
  ///
  /// Uses the canonical [ReceiptPrintController.requestReceipt] lifecycle, so it
  /// inherits the completed printer-readiness work: the authoritative printer
  /// configuration is awaited, the bridge is resolved AFTER readiness (never an
  /// eagerly captured null on a cold start), the first definitive logo outcome is
  /// waited for, a waiting/failed state is visible, and the per-order in-flight
  /// guard makes it exactly-once.
  ///
  /// The document comes from the SAME authoritative source the manual reprint
  /// uses, so a deferred-payment receipt is identical to one printed at checkout.
  /// Every failure here is swallowed: the payment is already recorded and must
  /// never be rolled back because a printer misbehaved.
  Future<void> _requestPaidReceipt(WidgetRef ref, AppLocalizations l10n) async {
    try {
      final record = ref
          .read(posRecentOrdersControllerProvider)
          .where((o) => o.identity.key == widget.identity.key)
          .firstOrNull;
      final source = await authoritativeReceiptSource(
        isDemoMode: ref.read(runtimeConfigProvider).isDemoMode,
        orderId: widget.orderId,
        localView: record?.order,
        localPayment:
            ref
                .read(paymentControllerProvider.notifier)
                .paymentFor(widget.identity) ??
            record?.payment,
        repository: ref.read(orderDetailRepositoryProvider),
      );
      if (source == null) return; // honest: no complete receipt to print
      final isDemo = ref.read(runtimeConfigProvider).isDemoMode;
      await ref
          .read(receiptPrintControllerProvider.notifier)
          .requestReceipt(
            // The SAME key the reprint action uses, so the two can never
            // produce two jobs for one order.
            orderKey: widget.identity.key,
            resolveReadiness: ref.read(posReceiptReadinessResolverProvider),
            awaitLogoReady: () =>
                ref.read(posReceiptLogoAssetProvider.notifier).firstResolution,
            buildDocument: () => buildReceiptDocument(
              l10n,
              source.$1,
              source.$2,
              isDemo: isDemo,
              restaurantName: ref.read(posRestaurantNameProvider),
              branding: ref.read(posReceiptLogoAssetProvider),
            ),
            resolveBridge: () async => (await ref.read(
              posActivePrintBridgeReadyProvider.future,
            ))?.submit,
          );
    } catch (_) {
      // A print problem is never a payment problem.
    }
  }

  Future<void> _reconcile(PosOrderSyncController sync) async {
    final orderId = widget.orderId;
    if (orderId == null || orderId.isEmpty) return;
    await sync.refreshOrders(<String>[orderId]);
  }

  /// Quick-cash suggestions: the exact amount, then round-ups to the next
  /// sensible note above it.
  ///
  /// OPS-043 Phase 2: the ladder comes from the currency instead of the
  /// hardcoded 1000/5000/10000 minor units, which only ever meant ₪10/₪50/₪100
  /// in a 2-decimal currency. At a JPY till those same numbers would have
  /// offered ¥1,000/¥5,000/¥10,000 rounding steps for a ¥480 coffee.
  List<int> get _quickAmounts {
    final set = <int>{widget.amountMinor};
    for (final step in quickAmountStepsMinor(widget.currencyCode)) {
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
/// UI-ORANGE-BALANCE-POLISH-001: reaches the REAL tender selector from a test.
///
/// The selector is private because nothing outside this sheet builds one. The
/// tests that hold its selected-state accent and its non-colour cue still have
/// to exercise the shipped widget rather than a copy of it.
@visibleForTesting
class PosTenderSelectorProbe extends StatelessWidget {
  const PosTenderSelectorProbe({
    required this.selected,
    this.onSelect,
    this.enabled = true,
    super.key,
  });

  final PaymentMethod selected;
  final ValueChanged<PaymentMethod>? onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) => _TenderSelector(
    l10n: AppLocalizations.of(context),
    selected: selected,
    enabled: enabled,
    onSelect: onSelect ?? (_) {},
  );
}

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
    final tenderAccent = RestoflowBrandPalette.of(
      theme.brightness,
    ).accentOrange;
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
            // UI-ORANGE-BALANCE-POLISH-001: the chosen tender gets an orange
            // edge AND a checkmark.
            //
            // The app theme turns Material's chip checkmark off, so before this
            // the selected tender was distinguished by fill colour ALONE — on
            // the one surface where getting the answer wrong means taking money
            // the wrong way. The checkmark restores a non-colour cue; the orange
            // edge is the brand accent marking an active choice.
            //
            // The edge is a COLOUR change at the theme's existing border width,
            // not a thicker one, so selecting a tender cannot resize its chip
            // and shove the neighbouring tenders sideways mid-tap.
            //
            // Orange marks the CHOICE only. It never touches the outcome:
            // approved stays semantic success and declined stays semantic
            // danger, which is what a cashier reads to know whether money
            // actually moved.
            for (final method in PaymentMethod.values)
              ChoiceChip(
                key: Key(_keys[method]!),
                label: Text(paymentMethodLabel(l10n, method)),
                selected: selected == method,
                onSelected: enabled ? (_) => onSelect(method) : null,
                showCheckmark: true,
                checkmarkColor: tenderAccent,
                side: selected == method
                    ? BorderSide(color: tenderAccent)
                    : null,
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
