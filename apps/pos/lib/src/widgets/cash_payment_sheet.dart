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
import '../data/payment_attempt.dart';
import '../format/cash_input.dart';
import '../format/money_format.dart';
import '../format/payment_method_label.dart';
import '../print/native_print_bridges.dart'
    show posActivePrintBridgeReadyProvider, posReceiptReadinessResolverProvider;
import '../print/pos_cash_drawer_service.dart'
    show
        PosCashDrawerOutcome,
        PosCashDrawerService,
        posCashDrawerServiceProvider;
import '../state/pos_offline_state.dart'
    show blockPosActionWhileOffline, blockPosPaymentUntilSubmitAccepted;
import '../state/pos_receipt_logo.dart' show posReceiptLogoAssetProvider;
import '../state/pos_session.dart' show posSignedInEmployeeProfileIdProvider;
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

  /// STALE-TABLE-ORDER-RECOVERY-001: the server refused because THIS device
  /// has no open shift / active drawer — a precondition, not a failure.
  bool _shiftRequired = false;

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

  // ---------------------------------------------------------------------
  // PAYMENT-ATTEMPT-RECOVERY-001 (BCA-MONEY-001): ONE DURABLE ATTEMPT.
  //
  // The sheet no longer treats "the push threw" as "try again with new
  // money". A lost or unreadable reply leaves ONE durable attempt whose
  // outcome is UNKNOWN; the sheet flips into RECOVERY MODE for it: the frozen
  // tender/amount are shown, Confirm is gone, and the cashier gets exactly
  // three bounded actions — Check status (read-only), Resume same attempt
  // (the same identity and bytes; the server replays the original outcome),
  // Close and resume later (the attempt survives; reopening offers it again).
  // Nothing here ever mints a second identity while one is unresolved, and
  // no automatic receipt/drawer effect fires twice for one attempt.
  // ---------------------------------------------------------------------

  /// True until the durable attempt store has been read for this order. No
  /// Confirm before that: an unread store may hold an unresolved attempt.
  bool _hydrating = true;

  /// The UNRESOLVED attempt this sheet is recovering, or null in normal mode.
  PaymentAttempt? _pending;

  /// Which recovery notice to show for [_pending].
  _RecoveryNotice _notice = _RecoveryNotice.unconfirmed;

  /// The last read-only status check's answer (recovery mode only).
  _StatusNote? _statusNote;

  /// A resumed attempt came back APPLIED: the payment stands, no new money
  /// was taken. The sheet stays open on a success banner with Done.
  bool _recovered = false;

  /// The automatic receipt could not be (re)fired for this resolved attempt,
  /// so the physical outcome is UNKNOWN; the manual reprint path stands.
  bool _receiptUnknown = false;

  /// THIS attempt was refused and the order is settled by another
  /// attempt/device. Not our payment: Close only.
  bool _settledElsewhere = false;

  /// The attempt could not be durably saved; NOTHING was sent. Confirm stays
  /// live: the next tap retries the SAVE (still zero network until it holds).
  bool _saveBlocked = false;

  /// S1-R4 / F004e: the two truths are NO LONGER widget fields. They live in
  /// [PaymentState], rehydrated from the in-process scope register on every
  /// controller build, so closing the sheet or replacing the provider cannot
  /// drop them. This is the sheet's read of that state, refreshed each build.
  PaymentAttemptDisclosure? _disclosure;

  /// A stored attempt that may concern this order cannot be read. Nothing is
  /// sent; a manager must look.
  bool _quarantined = false;

  /// PDR-003: the order's authoritative revision is unknown, so no attempt was
  /// created and nothing was sent. The order must be refreshed first.
  bool _revisionRequired = false;

  /// PDR-007: no identifiable cashier, so no attempt was created.
  bool _actorRequired = false;

  /// Reads the durable store BEFORE offering Confirm (real mode). Demo mode
  /// and hand-written repositories hydrate instantly.
  Future<void> _hydrate() async {
    final payments = ref.read(paymentControllerProvider.notifier);
    await payments.ensureHydrated();
    if (!mounted) return;
    final st = ref.read(paymentControllerProvider);
    final pending = st.pendingAttemptFor(widget.identity);
    setState(() {
      _hydrating = false;
      _pending = pending;
      _notice = pending == null
          ? _RecoveryNotice.unconfirmed
          : _noticeFor(pending, ref.read(posSignedInEmployeeProfileIdProvider));
      _quarantined = st.quarantineBlocks(widget.orderId ?? '');
    });
  }

  static _RecoveryNotice _noticeFor(PaymentAttempt a, String? employee) {
    if (a.employeeProfileId != null &&
        employee != null &&
        a.employeeProfileId != employee) {
      return _RecoveryNotice.otherActor;
    }
    return switch (a.lastOutcome) {
      PaymentAttemptLastOutcome.notApplied => _RecoveryNotice.notApplied,
      PaymentAttemptLastOutcome.authRequired => _RecoveryNotice.authRequired,
      PaymentAttemptLastOutcome.none ||
      PaymentAttemptLastOutcome.unconfirmed ||
      PaymentAttemptLastOutcome.collision => _RecoveryNotice.unconfirmed,
    };
  }

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

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
    _saveBlocked = false;
    _revisionRequired = false;
    _actorRequired = false;
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

  /// Everything a submit/resume needs AFTER its await, captured BEFORE it.
  /// The sheet is drag/barrier-dismissible while the push is in flight;
  /// touching the WIDGET's `ref` after a dismissal throws, and skipping the
  /// reconcile/effects because the sheet died would leave the row behind it
  /// stale. The notifiers outlive the sheet — the work completes either way.
  _Seams _captureSeams() => _Seams(
    navigator: Navigator.of(context),
    orders: ref.read(posRecentOrdersControllerProvider.notifier),
    sync: ref.read(posOrderSyncControllerProvider.notifier),
    // DEFERRED-PAYMENT-RECEIPTS-001: the receipt seams, captured on the same
    // rule as the notifiers above — the paid receipt must still be requested.
    receiptRef: ref,
    l10n: AppLocalizations.of(context),
    // POS-CASH-DRAWER-AUTO-OPEN: the drawer seams, captured on the SAME
    // before-the-await rule. The service outlives the sheet; the messenger is
    // captured so the one failure snackbar can be shown even after the sheet
    // (and its context) are gone.
    drawer: ref.read(posCashDrawerServiceProvider),
    messenger: ScaffoldMessenger.of(context),
  );

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
    final seams = _captureSeams();
    final payments = ref.read(paymentControllerProvider.notifier);
    // FROZEN HERE: the identity, order, total, tender, amount, currency and
    // revision this decision is made with. `submitAttempt` freezes them again
    // into the durable record before its first await; nothing is re-read.
    final outcome = await payments.submitAttempt(
      identity: widget.identity,
      orderId: widget.orderId ?? '',
      orderNumber: widget.orderNumber,
      amountMinor: widget.amountMinor,
      tenderedMinor: tendered,
      currencyCode: widget.currencyCode,
      method: _method,
      expectedRevision: widget.expectedRevision,
    );
    await _handleOutcome(outcome, seams, fromRecovery: false);
  }

  /// RESUME SAME ATTEMPT: the same identity, the same bytes — an explicit
  /// cashier action, never automatic.
  Future<void> _resume() async {
    setState(() {
      _submitting = true;
      _statusNote = null;
    });
    final seams = _captureSeams();
    final payments = ref.read(paymentControllerProvider.notifier);
    final outcome = await payments.resumeAttempt(widget.identity);
    await _handleOutcome(outcome, seams, fromRecovery: true);
  }

  /// CHECK STATUS: read-only. Resolves the attempt from the server's ledger
  /// when it has an answer; otherwise reports honestly that it is still
  /// pending (do not collect again) or that the read failed.
  Future<void> _checkStatus() async {
    setState(() {
      _submitting = true;
      _statusNote = null;
    });
    final seams = _captureSeams();
    final payments = ref.read(paymentControllerProvider.notifier);
    final check = await payments.checkStatus(widget.identity);
    switch (check) {
      case PaymentAttemptStatusResolved(:final outcome):
        await _handleOutcome(outcome, seams, fromRecovery: true);
      case PaymentAttemptStatusStillPending():
        if (mounted) {
          setState(() {
            _submitting = false;
            _statusNote = _StatusNote.stillPending;
          });
        }
      case PaymentAttemptStatusCheckUnavailable():
        if (mounted) {
          setState(() {
            _submitting = false;
            _statusNote = _StatusNote.unavailable;
          });
        }
      case PaymentAttemptStatusNothingPending():
        if (mounted) {
          setState(() {
            _submitting = false;
            _pending = null;
          });
        }
    }
  }

  /// ONE switch over the typed outcome, shared by Confirm, Resume and Check.
  Future<void> _handleOutcome(
    PaymentAttemptOutcome outcome,
    _Seams s, {
    required bool fromRecovery,
  }) async {
    switch (outcome) {
      case PaymentAttemptAccepted(
        :final payment,
        :final replay,
        :final automaticEffectsArmed,
      ):
        // POS-OPERATIONS-SYNC-001: take the AUTHORITATIVE order state after the
        // write. record_payment's envelope carries order_status and auto_completed
        // but NOT the money or the settlement, and a payment that auto-completes a
        // served order changes BOTH. We do not infer completion from "the button
        // worked" — we ask.
        await _reconcile(s.sync);
        // THE PAYMENT COMMAND EDGE — and, now, ONLY when the durable effect
        // reservation for THIS attempt was written in THIS call. A replayed
        // acceptance (a resume after a lost reply, a restart, a late callback)
        // finds the reservation already set and fires NOTHING again: the
        // paper may or may not have printed the first time, and printing it
        // twice is not how to find out. The manual reprint stays available.
        if (automaticEffectsArmed) {
          // DEFERRED-PAYMENT-RECEIPTS-001: the one place a receipt may be
          // requested — never a passive observer of a paid status during
          // hydration, which would reprint on every refresh. On the IMMEDIATE
          // checkout path OrderConfirmation also requests the same receipt;
          // ReceiptPrintController is keyed per order identity and refuses a
          // job that already exists, so exactly one receipt either way.
          // Deliberately not awaited: a print failure must never roll back a
          // successful payment.
          unawaited(_requestPaidReceipt(s.receiptRef, s.l10n));
          // POS-CASH-DRAWER-AUTO-OPEN: the drawer kick fires from the SAME
          // authoritative edge. The service enforces cash-only (RF-074), the
          // per-device toggle, and its own durable claim-before-send
          // at-most-once guarantee (keyed by the SERVER payment id, so a
          // replayed payment can never re-pulse it). Unawaited: never blocks
          // on hardware. Only a REAL expected-drawer send failure earns the
          // one non-blocking snackbar, through the pre-await messenger.
          unawaited(
            s.drawer
                .kickForPayment(payment)
                .then((o) {
                  // PR #205 review N3: the kick can settle after the sheet —
                  // or the whole app shell — is gone.
                  if (o != PosCashDrawerOutcome.sendFailed) return;
                  if (!s.messenger.mounted) return;
                  s.messenger.showSnackBar(
                    SnackBar(content: Text(s.l10n.posCashDrawerOpenFailed)),
                  );
                })
                .catchError((_) {}),
          );
        }
        if (fromRecovery || replay) {
          // RECOVERED: say so, in words, and let the cashier close it.
          if (mounted) {
            setState(() {
              _submitting = false;
              _pending = null;
              _recovered = true;
              _receiptUnknown = !automaticEffectsArmed;
            });
          }
          return;
        }
        // The sheet is drag/barrier-dismissible while the push is in flight;
        // popping an already-dismissed sheet would pop the ROOT POS route.
        // 019: the pop CARRIES the success result — the one authoritative edge
        // is the only place `true` can ever originate.
        if (mounted) s.navigator.pop(true);
      case PaymentAttemptRefused(:final code):
        // DESIGN-001: an honest, visible failure — the payment was NOT recorded
        // and the cashier must know. A NON-CHARGEABLE order is NOT a failure to
        // retry (its own banner, Confirm disabled). A CONFLICT retires the sheet
        // outright (see [_conflictStale]). A precondition (no open shift) gets
        // its own words. Everything else is the plain failure banner, and the
        // NEXT Confirm is a NEW, linked attempt — this identity is spent.
        if (mounted) {
          setState(() {
            _submitting = false;
            _pending = null;
            _shiftRequired = code == PaymentRefusalCode.shiftRequired;
            _notChargeable = code == PaymentRefusalCode.notChargeable;
            _conflictStale =
                _conflictStale || code == PaymentRefusalCode.revisionConflict;
            _failed = !_notChargeable && !_conflictStale && !_shiftRequired;
            // S1-R3 / F004: the server's refusal is exact and is shown as
            // such, AND the cashier is told that this device could not record
            // it. Kept in its own flag — not folded into [_saveBlocked] —
            // because a keystroke must not quietly clear a disclosure about
            // money, the way it clears an ordinary retryable error.
          });
        }
        if (code == PaymentRefusalCode.revisionConflict) {
          // POS-OPERATIONS-SYNC-001: the order moved under us. NEVER auto-retry.
          await _reconcile(s.sync);
        }
        if (code == PaymentRefusalCode.notChargeable) {
          // POS-OPERATIONS-SYNC-001: the refusal means our local total is WRONG —
          // the order was comped somewhere we did not see.
          s.orders.recordSyncRefusal(widget.identity, 'order_not_chargeable');
          await _reconcile(s.sync);
        }
      case PaymentAttemptSettledElsewhere():
        await _reconcile(s.sync);
        if (mounted) {
          setState(() {
            _submitting = false;
            _pending = null;
            _settledElsewhere = true;
          });
        }
      case PaymentAttemptUnconfirmed(:final attempt):
        // The row behind the sheet may already be paid; refresh it (never
        // throws), then hold the attempt for the cashier.
        await _reconcile(s.sync);
        _enterRecovery(attempt, _RecoveryNotice.unconfirmed);
      case PaymentAttemptNotApplied(:final attempt):
        _enterRecovery(attempt, _RecoveryNotice.notApplied);
      case PaymentAttemptAuthRequired(:final attempt):
        _enterRecovery(attempt, _RecoveryNotice.authRequired);
      case PaymentAttemptUnresolved(:final attempt):
        _enterRecovery(attempt, _noticeFor(attempt, null));
      case PaymentAttemptOtherActor(:final attempt):
        _enterRecovery(attempt, _RecoveryNotice.otherActor);
      case PaymentAttemptSaveBlocked():
        if (mounted) {
          setState(() {
            _submitting = false;
            _saveBlocked = true;
          });
        }
      case PaymentAttemptQuarantined():
        if (mounted) {
          setState(() {
            _submitting = false;
            _quarantined = true;
          });
        }
      case PaymentAttemptActorRequired():
        if (mounted) {
          setState(() {
            _submitting = false;
            _actorRequired = true;
          });
        }
      case PaymentAttemptRevisionRequired():
        // Nothing was minted, stored or sent. Refreshing the row behind the
        // sheet is exactly what makes a payment possible again.
        await _reconcile(s.sync);
        if (mounted) {
          setState(() {
            _submitting = false;
            _revisionRequired = true;
          });
        }
      case PaymentAttemptBusy():
        if (mounted) setState(() => _submitting = false);
    }
  }

  void _enterRecovery(PaymentAttempt attempt, _RecoveryNotice notice) {
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _pending = attempt;
      _notice = notice;
    });
  }

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

  /// Pulls the authoritative snapshot for THIS order through the CAPTURED coordinator
  /// (never the widget's `ref`, which dies with a dismissed sheet). Never throws: the
  /// coordinator records its own failure, and a failed refresh must not turn a
  /// SUCCESSFUL payment into an error the cashier sees.
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
    // S1-R4 / F004e: read the two truths from PaymentState on every build, so
    // a sheet opened AFTER the refusal — or after the provider was replaced —
    // shows exactly what a still-mounted one would.
    _disclosure = ref
        .watch(paymentControllerProvider)
        .disclosureFor(widget.identity);
    final pending = _pending;
    if (_recovered) return _recoveredView(l10n, theme);
    if (_settledElsewhere) return _settledElsewhereView(l10n, theme);
    if (_quarantined) return _quarantinedView(l10n, theme);
    if (pending != null) return _recoveryView(l10n, theme, pending);

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
    //
    // PAYMENT-ATTEMPT-RECOVERY-001: and never before the durable store has been
    // read — a new attempt may not start while an unresolved one could exist.
    final busy = _submitting || _hydrating;
    final canConfirm =
        !_notChargeable &&
        !_conflictStale &&
        (isCash
            ? (tendered != null && tendered >= widget.amountMinor && !busy)
            : !busy);
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
            _title(l10n, theme, isCash),
            const SizedBox(height: RestoflowSpacing.md),
            // RF-117: the tender selector (Cash / Card / Bit / External).
            _TenderSelector(
              l10n: l10n,
              selected: _method,
              enabled: !busy && !_conflictStale,
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
                enabled: !busy && !_conflictStale,
                buttonHeight: 52,
                trailingKey: FilledButton.tonal(
                  onPressed: busy ? null : () => _appendChar(_decimalSeparator),
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
            if (_shiftRequired) ...[
              const SizedBox(height: RestoflowSpacing.md),
              RestoflowNoticeBanner(
                key: const Key('payment-no-shift-banner'),
                tone: RestoflowTone.warning,
                title: l10n.posPaymentFailedTitle,
                body: l10n.posPaymentNoOpenShift,
              ),
            ],
            if (_saveBlocked) ...[
              const SizedBox(height: RestoflowSpacing.md),
              // PAYMENT-ATTEMPT-RECOVERY-001: the durable record did not stick,
              // so NOTHING was sent. Confirm stays live: it retries the SAVE.
              RestoflowNoticeBanner(
                key: const Key('payment-save-blocked-banner'),
                tone: RestoflowTone.danger,
                title: l10n.posPaymentSaveBlockedTitle,
                body: l10n.posPaymentSaveBlockedBody,
              ),
            ],
            // S1-R4 / F004e — the SAME builder every other view uses, so the
            // two truths cannot depend on which view happens to be open.
            ..._disclosureBanners(l10n),
            if (_actorRequired) ...[
              const SizedBox(height: RestoflowSpacing.md),
              RestoflowNoticeBanner(
                key: const Key('payment-actor-required-banner'),
                tone: RestoflowTone.warning,
                title: l10n.posPaymentFailedTitle,
                body: l10n.posPaymentActorRequired,
              ),
            ],
            if (_revisionRequired) ...[
              const SizedBox(height: RestoflowSpacing.md),
              // PDR-003: honest about WHY nothing happened. The cashier is
              // told to refresh, not to try the same thing again.
              RestoflowNoticeBanner(
                key: const Key('payment-revision-required-banner'),
                tone: RestoflowTone.warning,
                title: l10n.posPaymentFailedTitle,
                body: l10n.posPaymentRevisionRequired,
              ),
            ],
            if (_failed) ...[
              const SizedBox(height: RestoflowSpacing.md),
              // DESIGN-001: the payment-failure banner — pinned in the sheet
              // (not a transient SnackBar), danger tone, honest about state.
              // A DEFINITIVE server refusal lands here (never a lost reply —
              // that is recovery mode above); the next Confirm is a new attempt.
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
                      icon: busy
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

  Widget _title(AppLocalizations l10n, ThemeData theme, bool isCash) => Row(
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
  );

  Widget _shell(BuildContext context, List<Widget> children) => SafeArea(
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
        children: children,
      ),
    ),
  );

  /// The frozen tender + amount of the attempt under recovery. Money is
  /// formatted from the FROZEN integer minor units, never re-read.
  Widget _previousAttemptLine(
    AppLocalizations l10n,
    ThemeData theme,
    PaymentAttempt a,
  ) => Text(
    l10n.posPaymentPreviousAttempt(
      paymentMethodLabel(l10n, a.method),
      MoneyFormatter.formatMinor(a.amountTenderedMinor, a.currencyCode),
    ),
    key: const Key('payment-previous-attempt'),
    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
  );

  /// RECOVERY MODE. No Confirm, no new money: Check status / Resume same
  /// attempt / Close and resume later.
  Widget _recoveryView(
    AppLocalizations l10n,
    ThemeData theme,
    PaymentAttempt a,
  ) {
    final otherActor = _notice == _RecoveryNotice.otherActor;
    final (
      Key key,
      RestoflowTone tone,
      String title,
      String body,
    ) = switch (_notice) {
      _RecoveryNotice.unconfirmed => (
        const Key('payment-unconfirmed-banner'),
        RestoflowTone.warning,
        l10n.posPaymentUnconfirmedTitle,
        l10n.posPaymentUnconfirmedBody,
      ),
      _RecoveryNotice.notApplied => (
        const Key('payment-not-applied-banner'),
        RestoflowTone.danger,
        l10n.posPaymentFailedTitle,
        l10n.posPaymentNotAppliedBody,
      ),
      _RecoveryNotice.authRequired => (
        const Key('payment-auth-required-banner'),
        RestoflowTone.warning,
        l10n.posPaymentUnconfirmedTitle,
        l10n.posPaymentAuthRequiredBody,
      ),
      _RecoveryNotice.otherActor => (
        const Key('payment-other-actor-banner'),
        RestoflowTone.warning,
        l10n.posPaymentUnconfirmedTitle,
        l10n.posPaymentOtherActorBody,
      ),
    };
    return _shell(context, [
      _title(l10n, theme, a.method.isCash),
      const SizedBox(height: RestoflowSpacing.md),
      _AmountRow(
        label: l10n.posAmountDue,
        value: MoneyFormatter.formatMinor(a.amountMinor, a.currencyCode),
        emphasised: true,
      ),
      const SizedBox(height: RestoflowSpacing.sm),
      _previousAttemptLine(l10n, theme, a),
      const SizedBox(height: RestoflowSpacing.md),
      RestoflowNoticeBanner(key: key, tone: tone, title: title, body: body),
      // S1-R4 / F004e: the exact remote refusal and the failed local save
      // travel with the ATTEMPT, so a recovery view opened long after the
      // sheet that received them still tells the cashier both.
      ..._disclosureBanners(l10n),
      if (_statusNote != null) ...[
        const SizedBox(height: RestoflowSpacing.sm),
        Text(
          _statusNote == _StatusNote.stillPending
              ? l10n.posPaymentStatusStillPending
              : l10n.posPaymentStatusUnavailable,
          key: Key(
            _statusNote == _StatusNote.stillPending
                ? 'payment-status-still-pending'
                : 'payment-status-unavailable',
          ),
          style: theme.textTheme.bodyMedium,
        ),
      ],
      const SizedBox(height: RestoflowSpacing.md),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          key: const Key('payment-check-status-button'),
          onPressed: _submitting ? null : _checkStatus,
          icon: _submitting
              ? const RestoflowInlineSpinner()
              : const Icon(Icons.search),
          label: Text(l10n.posPaymentCheckStatus),
          style: RestoflowButtonStyles.big(context),
        ),
      ),
      if (!otherActor) ...[
        const SizedBox(height: RestoflowSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('payment-resume-attempt-button'),
            onPressed: _submitting ? null : _resume,
            icon: const Icon(Icons.replay),
            label: Text(l10n.posPaymentResumeAttempt),
            style: RestoflowButtonStyles.big(context),
          ),
        ),
      ],
      const SizedBox(height: RestoflowSpacing.sm),
      SizedBox(
        width: double.infinity,
        child: TextButton(
          key: const Key('payment-close-resume-later-button'),
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.posPaymentCloseResumeLater),
        ),
      ),
    ]);
  }

  Widget _recoveredView(AppLocalizations l10n, ThemeData theme) =>
      _shell(context, [
        _title(l10n, theme, true),
        const SizedBox(height: RestoflowSpacing.md),
        RestoflowNoticeBanner(
          key: const Key('payment-recovered-banner'),
          tone: RestoflowTone.success,
          title: l10n.posPaymentRecoveredTitle,
          body: l10n.posPaymentRecoveredBody,
        ),
        if (_receiptUnknown) ...[
          const SizedBox(height: RestoflowSpacing.sm),
          Text(
            l10n.posPaymentReceiptUnknown,
            key: const Key('payment-receipt-unknown'),
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: RestoflowSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('payment-done-button'),
            // The one authoritative success edge: the payment stands.
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.check),
            label: Text(l10n.posPaymentDone),
            style: RestoflowButtonStyles.big(context),
          ),
        ),
      ]);

  Widget _settledElsewhereView(AppLocalizations l10n, ThemeData theme) =>
      _shell(context, [
        _title(l10n, theme, true),
        const SizedBox(height: RestoflowSpacing.md),
        RestoflowNoticeBanner(
          key: const Key('payment-settled-elsewhere-banner'),
          tone: RestoflowTone.info,
          title: l10n.posPaymentSettledElsewhereTitle,
          body: l10n.posPaymentSettledElsewhereBody,
        ),
        const SizedBox(height: RestoflowSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('payment-settled-close-button'),
            // NOT our payment: never `true`.
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            label: Text(l10n.posPaymentCloseResumeLater),
            style: RestoflowButtonStyles.big(context),
          ),
        ),
      ]);

  /// S1-R4 / F004e — the two truths, rendered in WHATEVER view the sheet
  /// opens in.
  ///
  /// A reopened sheet for an unresolved attempt lands in the recovery or
  /// quarantine view, not the tender form, so banners that lived only in the
  /// form disappeared exactly when the cashier most needed them.
  List<Widget> _disclosureBanners(AppLocalizations l10n) {
    final disclosure = _disclosure;
    if (disclosure == null || disclosure.isEmpty) return const <Widget>[];
    final code = disclosure.refusalCode;
    // Defer to the LIVE flag when this sheet is the one that received the
    // refusal: it already renders that banner, and two would be a lie about
    // how many refusals there were.
    return <Widget>[
      if (code == PaymentRefusalCode.shiftRequired && !_shiftRequired) ...[
        const SizedBox(height: RestoflowSpacing.md),
        RestoflowNoticeBanner(
          key: const Key('payment-no-shift-banner'),
          tone: RestoflowTone.warning,
          title: l10n.posPaymentFailedTitle,
          body: l10n.posPaymentNoOpenShift,
        ),
      ] else if (code == PaymentRefusalCode.notChargeable &&
          !_notChargeable) ...[
        const SizedBox(height: RestoflowSpacing.md),
        RestoflowNoticeBanner(
          key: const Key('payment-not-chargeable-banner'),
          tone: RestoflowTone.info,
          title: l10n.posNoChargeChip,
          body: l10n.posNoChargeNoPayment,
        ),
      ] else if (code != null && !_failed && !_conflictStale) ...[
        const SizedBox(height: RestoflowSpacing.md),
        RestoflowNoticeBanner(
          key: const Key('payment-failed-banner'),
          tone: RestoflowTone.danger,
          title: l10n.posPaymentFailedTitle,
          body: l10n.posPaymentFailedBody,
        ),
      ],
      if (disclosure.localSaveFailed) ...[
        const SizedBox(height: RestoflowSpacing.md),
        RestoflowNoticeBanner(
          key: const Key('payment-refusal-save-blocked-banner'),
          tone: RestoflowTone.danger,
          title: l10n.posPaymentSaveBlockedTitle,
          body: l10n.posPaymentSaveBlockedBody,
        ),
      ],
    ];
  }

  Widget _quarantinedView(AppLocalizations l10n, ThemeData theme) =>
      _shell(context, [
        _title(l10n, theme, true),
        const SizedBox(height: RestoflowSpacing.md),
        RestoflowNoticeBanner(
          key: const Key('payment-quarantined-banner'),
          tone: RestoflowTone.danger,
          title: l10n.posPaymentQuarantinedTitle,
          body: l10n.posPaymentQuarantinedBody,
        ),
        ..._disclosureBanners(l10n),
        const SizedBox(height: RestoflowSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('payment-quarantined-close-button'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            label: Text(l10n.posPaymentCloseResumeLater),
            style: RestoflowButtonStyles.big(context),
          ),
        ),
      ]);
}

/// Which recovery-mode notice to show for a pending attempt.
enum _RecoveryNotice { unconfirmed, notApplied, authRequired, otherActor }

/// The last read-only status check's honest answer.
enum _StatusNote { stillPending, unavailable }

/// The seams a submit needs after its await, captured before it.
class _Seams {
  const _Seams({
    required this.navigator,
    required this.orders,
    required this.sync,
    required this.receiptRef,
    required this.l10n,
    required this.drawer,
    required this.messenger,
  });

  final NavigatorState navigator;
  final PosRecentOrdersController orders;
  final PosOrderSyncController sync;
  final WidgetRef receiptRef;
  final AppLocalizations l10n;
  final PosCashDrawerService drawer;
  final ScaffoldMessengerState messenger;
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
