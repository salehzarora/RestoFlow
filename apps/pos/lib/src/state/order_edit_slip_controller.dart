import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show KitchenImportAckStatus, SupabaseKitchenDispatchAckRepository;
import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show
        OrderChangeSlipView,
        kitchenChangeSlipLabelsForLanguageCode,
        kitchenTicketPrintLabelsForLanguageCode;

import '../data/order_detail_repository.dart';
import '../data/order_edit_read_model.dart'
    show PosKitchenChannel, PosOrderDetailEdit;
import '../data/order_edit_response.dart' show OrderEditApplied;
import '../data/order_edit_slip.dart';
import '../data/order_edit_slip_store.dart';
import '../data/recent_order.dart' show PosRecentOrder;
import '../data/round_print_claim_store.dart';
import '../print/pos_kitchen_ticket_printer.dart'
    show
        PosKitchenPrintOutcome,
        posAutoKitchenPrintGuardProvider,
        posOrderEditSlipPrintProvider,
        posRoundPrintClaimStoreProvider;
import 'locale_controller.dart' show localeControllerProvider;
import 'order_edit_controller.dart'
    show OrderEditAttempt, orderEditControllerProvider;
import 'pos_kitchen_dispatch_ack.dart' show posKitchenDispatchAckProvider;
import 'pos_session.dart'
    show
        posSignedInEmployeeProfileIdProvider,
        posSignedInStaffNameProvider,
        posSyncSessionProvider;
import 'recent_orders_controller.dart' show posRecentOrdersControllerProvider;

/// ORDER-EDIT-001F — THE AWAITED, EXACTLY-ONCE PAPER CHANGE SLIP (design §7.3).
///
/// On a printer-only branch the kitchen hears about a sent-order edit through
/// ONE piece of paper: the change slip. `app.edit_order` answers a paper edit
/// with an `order_edit` kitchen dispatch that is BORN CLAIMED by this till, and
/// this controller puts the slip on paper directly — hand-built
/// (`order_edit_slip.dart`), awaited by the edit flow so the toast can say
/// "printed" or "saved" honestly — and reports the dispatch back.
///
/// THE EXACTLY-ONCE RULES:
///  * RECORD BEFORE PRINT: [recordApplied] persists the slip record (the
///    "durable backup") before anything is sent, then writes the SPOOL MIRROR
///    claim (`edit-dispatch:<dispatchId>`) as `claimed` — the key the spool's
///    import consult reads, because a pulled dispatch carries no
///    `order_edit_id`. An UNBUILT slip (no proven detail) is written `failed`
///    instead, so the next drain imports the dispatch and the spool prints the
///    server's own slip (decision D3);
///  * CLAIM BEFORE SEND: [printRecorded] sends through
///    `PosAutoKitchenPrintGuard.runGuarded` under
///    `<orderId>|edit:<orderEditId>`, which writes `claimed` before the bytes
///    leave and settles `sent` / `failed` after. It runs only for a recorded,
///    built, `pending` slip whose mirror durably reads `claimed`;
///  * AMBIGUOUS IS NEVER AUTOMATIC: a guard claim left `claimed` by an earlier
///    process (a crash mid-print) prints nothing automatically — the banner
///    offers Print again, the deliberate re-entry ([printAgain],
///    `runPreclaimed`);
///  * IN FLIGHT IS SKIPPED (decision D11): from [recordApplied] until the
///    print settles, the dispatch is in flight in memory, and the spool's
///    consult ([isDispatchInFlight]) leaves it alone — no import, no
///    acknowledgement — instead of parking it in a `possibly_printed` hold;
///  * ACKNOWLEDGED, NEVER RELIED ON: `transport_accepted` when the bytes were
///    accepted, else `failed_retryable` with a safe code. Every answer
///    (terminal or transient) is ignored: the dispatch is this till's claim, so
///    the next drain re-serves it and the consult converges it;
///  * A NEWER EDIT RETIRES OLDER SLIPS, and an edit already superseded on the
///    server (a newer edit, a void) prints nothing.
///
/// MONEY-FREE (SECURITY T-003, D-007): every record, claim and evidence entry
/// is money-free; the frozen request payload is read for its slip lines only.
///
/// A KDS edit never reaches this controller.
enum OrderEditSlipOutcome {
  /// The slip reached the kitchen printer's transport (never "paper came
  /// out", which no transport reports).
  printed,

  /// It did not — no printer, unavailable, a failed send, an UNBUILT slip, or
  /// an earlier attempt whose outcome is unknown. The record stays and its
  /// banner offers Print again.
  notPrinted,

  /// The spool owns it (it imported the dispatch and prints the server slip).
  handedOver,

  /// A newer edit or a void superseded it before it printed.
  superseded,

  /// Not a paper slip this till recorded (a KDS edit, or no record).
  notApplicable,
}

/// What a deliberate "Print again" (or "Print latest") came to.
enum OrderEditPrintAgainStatus {
  /// The slip reached the printer's transport (or already had: nothing was
  /// sent twice).
  printed,

  /// It did not; see [OrderEditPrintAgainResult.printOutcome]. The record
  /// stays, with its banner.
  notPrinted,

  /// The order still carries an unresolved edit (`posOrderEditPendingBlocked`),
  /// or this very slip is printing right now.
  blocked,

  /// The authoritative detail could not be read (`posReprintKitchenFetchFailed`).
  /// Nothing printed; the record stays.
  fetchFailed,

  /// The order was voided or cancelled: the VOID supersedes the slip, and the
  /// record is retired silently (decision D9).
  retired,

  /// The order has a NEWER edit: the record is retired. The result says
  /// whether there is something to offer (`posOrderEditNewerSlipOffer`).
  newerEdit,

  /// Nothing to print (already printed, handed over or retired; or the order
  /// has no live line for an ORDER-NOW slip).
  notFound,
}

class OrderEditPrintAgainResult {
  const OrderEditPrintAgainResult(
    this.status, {
    this.orderId,
    this.printOutcome,
    this.newerLocalOrderEditId,
    this.offerLatest = false,
  });

  final OrderEditPrintAgainStatus status;

  /// The order the slip belongs to.
  final String? orderId;

  /// The transport's answer, when a send was attempted.
  final PosKitchenPrintOutcome? printOutcome;

  /// [OrderEditPrintAgainStatus.newerEdit]: a newer UNSENT slip of this till —
  /// "Print latest" prints THAT record again.
  final String? newerLocalOrderEditId;

  /// [OrderEditPrintAgainStatus.newerEdit]: the newer edit is ANOTHER till's —
  /// "Print latest" prints the ORDER-NOW slip of the order (decision D5).
  final bool offerLatest;

  /// Whether the newer-slip offer has anything to offer.
  bool get hasOffer => newerLocalOrderEditId != null || offerLatest;
}

/// The controller's published state.
class OrderEditSlipsState {
  const OrderEditSlipsState({
    this.hydrated = false,
    this.records = const <String, OrderEditSlipRecord>{},
    this.inFlight = const <String>{},
  });

  /// The durable store has been read (or there is none).
  final bool hydrated;

  /// Every unsent slip of this till, by `order_edit_id`.
  final Map<String, OrderEditSlipRecord> records;

  /// The `order_edit_id`s whose print is in flight right now.
  final Set<String> inFlight;

  OrderEditSlipsState copyWith({
    bool? hydrated,
    Map<String, OrderEditSlipRecord>? records,
    Set<String>? inFlight,
  }) => OrderEditSlipsState(
    hydrated: hydrated ?? this.hydrated,
    records: records ?? this.records,
    inFlight: inFlight ?? this.inFlight,
  );
}

/// Injected clock (tests pin the time).
final orderEditSlipClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

bool _orderIsDead(String status) => status == 'voided' || status == 'cancelled';

PosOrderDetailEdit? _editOf(PosOrderDetail detail, String orderEditId) {
  final id = orderEditId.toLowerCase();
  for (final e in detail.edits ?? const <PosOrderDetailEdit>[]) {
    if (e.orderEditId.toLowerCase() == id) return e;
  }
  return null;
}

class OrderEditSlipController extends Notifier<OrderEditSlipsState> {
  bool _disposed = false;
  Future<void> _ready = Future<void>.value();

  /// Store I/O is serialized (two interleaved load-modify-persist cycles would
  /// lose a write), exactly like the edit journal.
  Future<void> _tail = Future<void>.value();

  Map<String, OrderEditSlipRecord> _records =
      const <String, OrderEditSlipRecord>{};

  /// In flight: `order_edit_id` -> its dispatch id (null when none).
  final Map<String, String?> _inFlight = {};

  /// Single-flight automatic prints, by `order_edit_id`.
  final Map<String, Future<OrderEditSlipOutcome>> _printing = {};

  /// The `order_edit_id`s a deliberate Print again is running for — their
  /// in-flight mark belongs to it, never to an automatic print.
  final Set<String> _againRunning = {};

  /// Edits this session already decided (printed, handed over, superseded):
  /// a repeat call answers from here and never records again.
  final Map<String, OrderEditSlipOutcome> _decided = {};

  @override
  OrderEditSlipsState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    _records = const <String, OrderEditSlipRecord>{};
    _inFlight.clear();
    _printing.clear();
    _againRunning.clear();
    _decided.clear();
    final store = ref.read(orderEditSlipStoreProvider);
    if (store == null || _scope.isEmpty) {
      _ready = Future<void>.value();
      return const OrderEditSlipsState(hydrated: true);
    }
    _ready = Future<void>.microtask(() => _restore(store));
    return const OrderEditSlipsState();
  }

  /// The store is keyed by THIS device: one till never prints another's slip.
  String get _scope => ref.read(posSyncSessionProvider)?.deviceId ?? '';

  DateTime _now() => ref.read(orderEditSlipClockProvider)();

  void _publish() {
    if (_disposed) return;
    state = OrderEditSlipsState(
      hydrated: state.hydrated,
      records: _records,
      inFlight: Set<String>.unmodifiable(_inFlight.keys),
    );
  }

  Future<void> _restore(OrderEditSlipStore store) async {
    if (_disposed) return;
    final scope = _scope;
    Map<String, OrderEditSlipRecord> loaded;
    try {
      loaded = await _serialized(() => store.load(scope));
    } catch (_) {
      loaded = <String, OrderEditSlipRecord>{}; // load never throws by contract
    }
    if (_disposed) return;
    _records = Map<String, OrderEditSlipRecord>.unmodifiable({
      ...loaded,
      ..._records,
    });
    state = state.copyWith(hydrated: true);
    _publish();
  }

  Future<T> _serialized<T>(Future<T> Function() op) {
    final run = _tail.then((_) => op());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// Applies [change] to the in-memory index (published at once) and to the
  /// durable store (load, change, persist — so a record the store holds but
  /// memory does not is never lost). False when the write did not stick: the
  /// in-memory record then holds for this session, and the storage-health
  /// indicator shows the refused write.
  Future<bool> _mutate(
    void Function(Map<String, OrderEditSlipRecord> records) change,
  ) async {
    if (_disposed) return false;
    final next = Map<String, OrderEditSlipRecord>.of(_records);
    change(next);
    _records = Map<String, OrderEditSlipRecord>.unmodifiable(next);
    _publish();
    final store = ref.read(orderEditSlipStoreProvider);
    final scope = _scope;
    if (store == null || scope.isEmpty) return true;
    try {
      await _serialized(() async {
        final existing = await store.load(scope);
        change(existing);
        await store.persist(scope, existing);
      });
      return true;
    } catch (_) {
      // Includes PosPersistenceException from a refused write.
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // The automatic path (driven by the edit flow).
  // -------------------------------------------------------------------------

  /// Records the PAPER change slip of [applied] — idempotent by
  /// `order_edit_id` — BEFORE the edit flow closes its journal record.
  ///
  /// [fresh] is the authoritative detail that PROVED the edit, or null when
  /// none did (the slip is then recorded UNBUILT and handed to the spool via
  /// a `failed` mirror). A KDS edit is ignored.
  Future<void> recordApplied({
    required OrderEditAttempt attempt,
    required OrderEditApplied applied,
    PosOrderDetail? fresh,
  }) async {
    if (applied.kitchenChannel != PosKitchenChannel.paper) return;
    await _ready;
    if (_disposed) return;
    final id = applied.orderEditId;
    if (_records.containsKey(id) || _decided.containsKey(id)) return;

    final dispatchId = applied.kitchenDispatch?.id;
    final claims = ref.read(posRoundPrintClaimStoreProvider);
    final guard = ref.read(posAutoKitchenPrintGuardProvider);
    final guardKey = posOrderEditKitchenPrintGuardKey(
      orderId: attempt.orderId,
      orderEditId: id,
    );
    final mirrorKey = dispatchId == null
        ? null
        : posOrderEditDispatchClaimKey(dispatchId);
    // A repeat after a restart whose journal close did not stick: the slip
    // already went out under its guard key, or the spool already took the
    // dispatch over (its mirror `claimed` with no guard claim of ours).
    final guarded = guard.effectiveClaimOf(guardKey);
    if (guarded == PosRoundPrintClaimState.sent) {
      _decided[id] = OrderEditSlipOutcome.printed;
      return;
    }
    if (guarded == null &&
        mirrorKey != null &&
        claims?.claimOf(mirrorKey) == PosRoundPrintClaimState.claimed) {
      _decided[id] = OrderEditSlipOutcome.handedOver;
      return;
    }

    // A newer edit retires every older unsent slip of the order.
    await _retireOlder(attempt.orderId, applied.editNumber);
    if (_disposed) return;

    // Already superseded on the server (a newer edit's dispatch, or a void):
    // nothing to print and nothing to acknowledge.
    if (fresh != null &&
        (fresh.editCount > applied.editNumber || _orderIsDead(fresh.status))) {
      _decided[id] = OrderEditSlipOutcome.superseded;
      return;
    }

    final lines =
        orderEditSlipLines(applied: applied, payload: attempt.payload) ??
        const <OrderEditSlipLine>[];
    final was = attempt.slipWas ?? const <String, OrderEditSlipItem>{};
    // The slip names the worker who made the edit: the signed-in worker only
    // when it is the one who froze the attempt (a cart-free replay may run
    // under someone else — no staff line then, never a wrong name).
    final sameWorker =
        attempt.employeeProfileId ==
        ref.read(posSignedInEmployeeProfileIdProvider);
    final staff = sameWorker ? ref.read(posSignedInStaffNameProvider) : null;
    final slip = fresh == null
        ? null
        : buildOrderEditChangeSlipFromLines(
            orderCode: attempt.orderCode,
            orderEditId: id,
            editNumber: applied.editNumber,
            lines: lines,
            was: was,
            fresh: fresh,
            staffDisplayName: staff,
          );
    final record = OrderEditSlipRecord(
      orderEditId: id,
      orderId: attempt.orderId,
      orderCode: attempt.orderCode,
      editNumber: applied.editNumber,
      dispatchId: dispatchId,
      editCreatedAt: fresh == null ? null : _editOf(fresh, id)?.createdAt,
      slip: slip,
      was: was,
      lines: lines,
      staffFirstName: orderEditSlipStaffFirstName(staff),
      updatedAt: _now(),
    );
    // In flight from here until the print settles: the spool's consult skips
    // it (D11). An unbuilt slip is the spool's, so it is never marked.
    if (slip != null) _inFlight[id] = dispatchId;
    await _mutate((m) => m[id] = record);
    if (_disposed) return;
    if (mirrorKey != null && claims != null) {
      try {
        await claims.record(
          mirrorKey,
          slip != null
              ? PosRoundPrintClaimState.claimed
              : PosRoundPrintClaimState.failed,
        );
      } catch (_) {
        // A mirror that does not durably read `claimed` withholds the
        // automatic print (see [printRecorded]); the spool may take it.
      }
    }
  }

  /// Prints the recorded slip of [orderEditId] — AWAITED by the edit flow,
  /// single-flight, and exactly once (see the rules above).
  Future<OrderEditSlipOutcome> printRecorded(String orderEditId) {
    final running = _printing[orderEditId];
    if (running != null) return running;
    final run = _printRecorded(orderEditId);
    _printing[orderEditId] = run;
    run.whenComplete(() {
      if (identical(_printing[orderEditId], run)) {
        _printing.remove(orderEditId);
      }
    });
    return run;
  }

  Future<OrderEditSlipOutcome> _printRecorded(String id) async {
    await _ready;
    // A deliberate Print again owns this slip right now (and its mark).
    if (_againRunning.contains(id)) return OrderEditSlipOutcome.notPrinted;
    try {
      if (_disposed) return OrderEditSlipOutcome.notApplicable;
      final decided = _decided[id];
      if (decided != null) return decided;
      final record = _records[id];
      if (record == null) return OrderEditSlipOutcome.notApplicable;
      final slip = record.slip;
      if (slip == null || record.state != OrderEditSlipState.pending) {
        return OrderEditSlipOutcome.notPrinted;
      }
      final claims = ref.read(posRoundPrintClaimStoreProvider);
      final guard = ref.read(posAutoKitchenPrintGuardProvider);
      final guardKey = posOrderEditKitchenPrintGuardKey(
        orderId: record.orderId,
        orderEditId: id,
      );
      switch (guard.effectiveClaimOf(guardKey)) {
        case PosRoundPrintClaimState.sent:
          // The bytes already went out under this identity (a process that
          // died before it settled): settle, never send twice.
          await _settle(id, PosKitchenPrintOutcome.printed);
          return OrderEditSlipOutcome.printed;
        case PosRoundPrintClaimState.claimed:
          // An earlier attempt's outcome is unknown: a slip may already be at
          // the printer. Never automatic — the banner offers Print again.
          return OrderEditSlipOutcome.notPrinted;
        case PosRoundPrintClaimState.failed:
        case null:
          break;
      }
      final dispatchId = record.dispatchId;
      if (dispatchId != null &&
          claims != null &&
          claims.claimOf(posOrderEditDispatchClaimKey(dispatchId)) !=
              PosRoundPrintClaimState.claimed) {
        // The mirror could not be claimed: the spool may import this
        // dispatch, so the till must not print it too.
        return OrderEditSlipOutcome.notPrinted;
      }
      _inFlight[id] = dispatchId;
      _publish();
      final outcome = await guard.runGuarded(guardKey, () => _print(slip));
      if (_disposed) {
        return outcome == PosKitchenPrintOutcome.printed
            ? OrderEditSlipOutcome.printed
            : OrderEditSlipOutcome.notPrinted;
      }
      await _settle(id, outcome);
      return outcome == PosKitchenPrintOutcome.printed
          ? OrderEditSlipOutcome.printed
          : OrderEditSlipOutcome.notPrinted;
    } finally {
      _release(id);
    }
  }

  // -------------------------------------------------------------------------
  // The deliberate path (the banner, the row, the toast's action).
  // -------------------------------------------------------------------------

  /// "Print again" for the unsent slip of [orderEditId]: re-reads the order,
  /// retires the slip when a void or a newer edit superseded it, builds an
  /// unbuilt slip now, and otherwise re-sends the STORED document under the
  /// SAME guard key (a deliberate re-entry: `runPreclaimed`).
  Future<OrderEditPrintAgainResult> printAgain(String orderEditId) async {
    await _ready;
    if (_disposed) {
      return const OrderEditPrintAgainResult(
        OrderEditPrintAgainStatus.notFound,
      );
    }
    final record = _records[orderEditId];
    if (record == null) {
      return const OrderEditPrintAgainResult(
        OrderEditPrintAgainStatus.notFound,
      );
    }
    final orderId = record.orderId;
    OrderEditPrintAgainResult result(
      OrderEditPrintAgainStatus status, {
      PosKitchenPrintOutcome? outcome,
    }) => OrderEditPrintAgainResult(
      status,
      orderId: orderId,
      printOutcome: outcome,
    );
    if (_inFlight.containsKey(orderEditId)) {
      return result(OrderEditPrintAgainStatus.blocked);
    }
    final edits = ref.read(orderEditControllerProvider);
    if (edits.startupBlocked || edits.hasUnresolvedEditFor(orderId)) {
      return result(OrderEditPrintAgainStatus.blocked);
    }
    _inFlight[orderEditId] = record.dispatchId;
    _againRunning.add(orderEditId);
    _publish();
    try {
      final PosOrderDetail detail;
      try {
        detail = await ref.read(orderDetailRepositoryProvider).fetch(orderId);
      } catch (_) {
        return result(OrderEditPrintAgainStatus.fetchFailed);
      }
      if (_disposed) return result(OrderEditPrintAgainStatus.notFound);
      var current = _records[orderEditId];
      if (current == null || detail.orderId != orderId) {
        return result(OrderEditPrintAgainStatus.notFound);
      }
      if (_orderIsDead(detail.status)) {
        await _retire(orderEditId, OrderEditSlipOutcome.superseded);
        return result(OrderEditPrintAgainStatus.retired);
      }
      if (detail.editCount > current.editNumber) {
        await _retire(orderEditId, OrderEditSlipOutcome.superseded);
        return _newerEdit(detail, current);
      }
      var slip = current.slip;
      if (slip == null) {
        // Built now from the frozen inputs, else (a 001E-format record, or a
        // line the detail no longer shows) the ORDER-NOW slip of THIS edit —
        // honest paper either way, never a partial change list.
        slip =
            buildOrderEditChangeSlipFromLines(
              orderCode: current.orderCode,
              orderEditId: orderEditId,
              editNumber: current.editNumber,
              lines: current.lines,
              was: current.was,
              fresh: detail,
              staffDisplayName: current.staffFirstName,
            ) ??
            orderNowSlipFromDetail(detail);
        if (slip == null || slip.editNumber != current.editNumber) {
          return result(OrderEditPrintAgainStatus.notFound);
        }
        current = current.copyWith(
          slip: slip,
          editCreatedAt: _editOf(detail, orderEditId)?.createdAt,
          updatedAt: _now(),
        );
        final built = current;
        await _mutate((m) => m[orderEditId] = built);
        if (_disposed) return result(OrderEditPrintAgainStatus.notFound);
      }
      final claims = ref.read(posRoundPrintClaimStoreProvider);
      final guard = ref.read(posAutoKitchenPrintGuardProvider);
      final guardKey = posOrderEditKitchenPrintGuardKey(
        orderId: orderId,
        orderEditId: orderEditId,
      );
      // CLAIM, THEN SEND: the mirror first (so the spool's consult cannot
      // import the dispatch meanwhile), then the guard key. A claim that does
      // not stick sends nothing.
      if (claims != null) {
        try {
          if (current.dispatchId case final d?) {
            await claims.record(
              posOrderEditDispatchClaimKey(d),
              PosRoundPrintClaimState.claimed,
            );
          }
          await claims.record(guardKey, PosRoundPrintClaimState.claimed);
        } catch (_) {
          return result(
            OrderEditPrintAgainStatus.notPrinted,
            outcome: PosKitchenPrintOutcome.failed,
          );
        }
      }
      if (_disposed) return result(OrderEditPrintAgainStatus.notFound);
      final document = slip;
      final outcome = await guard.runPreclaimed(
        guardKey,
        () => _print(document),
      );
      if (_disposed) return result(OrderEditPrintAgainStatus.notFound);
      await _settle(orderEditId, outcome);
      return result(
        outcome == PosKitchenPrintOutcome.printed
            ? OrderEditPrintAgainStatus.printed
            : OrderEditPrintAgainStatus.notPrinted,
        outcome: outcome,
      );
    } finally {
      _againRunning.remove(orderEditId);
      _release(orderEditId);
    }
  }

  /// "Print latest" for another till's newer edit (decision D5): the ORDER-NOW
  /// slip of the order's current lines, headed by its latest edit. Deliberate:
  /// unguarded and unacknowledged — that edit's own dispatch is the other
  /// till's.
  Future<OrderEditPrintAgainResult> printLatest(String orderId) async {
    final PosOrderDetail detail;
    try {
      detail = await ref.read(orderDetailRepositoryProvider).fetch(orderId);
    } catch (_) {
      return OrderEditPrintAgainResult(
        OrderEditPrintAgainStatus.fetchFailed,
        orderId: orderId,
      );
    }
    if (_disposed) {
      return const OrderEditPrintAgainResult(
        OrderEditPrintAgainStatus.notFound,
      );
    }
    final slip = detail.orderId == orderId && !_orderIsDead(detail.status)
        ? orderNowSlipFromDetail(detail)
        : null;
    if (slip == null) {
      return OrderEditPrintAgainResult(
        OrderEditPrintAgainStatus.notFound,
        orderId: orderId,
      );
    }
    final outcome = await _print(slip);
    return OrderEditPrintAgainResult(
      outcome == PosKitchenPrintOutcome.printed
          ? OrderEditPrintAgainStatus.printed
          : OrderEditPrintAgainStatus.notPrinted,
      orderId: orderId,
      printOutcome: outcome,
    );
  }

  Future<OrderEditPrintAgainResult> _newerEdit(
    PosOrderDetail detail,
    OrderEditSlipRecord retired,
  ) async {
    OrderEditSlipRecord? local;
    for (final r in _records.values) {
      if (r.orderId != retired.orderId ||
          r.editNumber <= retired.editNumber ||
          _inFlight.containsKey(r.orderEditId)) {
        continue;
      }
      if (local == null || r.editNumber > local.editNumber) local = r;
    }
    if (local != null) {
      return OrderEditPrintAgainResult(
        OrderEditPrintAgainStatus.newerEdit,
        orderId: retired.orderId,
        newerLocalOrderEditId: local.orderEditId,
      );
    }
    final edits = detail.edits;
    final latest = edits == null || edits.isEmpty ? null : edits.last;
    final mine = latest != null && await _sentHere(retired.orderId, latest);
    return OrderEditPrintAgainResult(
      OrderEditPrintAgainStatus.newerEdit,
      orderId: retired.orderId,
      // This till already printed the newer slip: nothing to offer.
      offerLatest: !mine && !_isInFlightFor(retired.orderId),
    );
  }

  bool _isInFlightFor(String orderId) =>
      _inFlight.keys.any((id) => _records[id]?.orderId == orderId);

  /// Whether THIS till put [edit]'s slip on paper (this session, or the
  /// bounded direct-print evidence).
  Future<bool> _sentHere(String orderId, PosOrderDetailEdit edit) async {
    if (_decided[edit.orderEditId] == OrderEditSlipOutcome.printed) {
      return true;
    }
    final created = edit.createdAt;
    if (created == null) return false;
    for (final e in await evidence()) {
      if (e.orderId == orderId && e.editCreatedAt.isAtSameMomentAs(created)) {
        return true;
      }
    }
    return false;
  }

  // -------------------------------------------------------------------------
  // The spool's hooks (called only from its composition callbacks).
  // -------------------------------------------------------------------------

  /// Whether the direct print of [dispatchId] is in flight right now: the
  /// consult then skips the row — no import, no acknowledgement (D11).
  bool isDispatchInFlight(String dispatchId) =>
      _inFlight.values.contains(dispatchId);

  /// The spool imported [dispatchId] and prints the server's slip: the mirror
  /// reads `claimed` from now on and the till forgets its own record (the
  /// banner hides).
  Future<void> handOverToSpool(String dispatchId) async {
    await _ready;
    if (_disposed) return;
    final claims = ref.read(posRoundPrintClaimStoreProvider);
    if (claims != null) {
      try {
        await claims.record(
          posOrderEditDispatchClaimKey(dispatchId),
          PosRoundPrintClaimState.claimed,
        );
      } catch (_) {
        // The spool holds the job either way.
      }
    }
    final ids = [
      for (final r in _records.values)
        if (r.dispatchId == dispatchId) r.orderEditId,
    ];
    for (final id in ids) {
      _decided[id] = OrderEditSlipOutcome.handedOver;
    }
    if (ids.isNotEmpty) await _mutate((m) => ids.forEach(m.remove));
  }

  /// This till's live direct-print evidence (the local supersession sweep's
  /// external input), oldest first. Never throws.
  Future<List<OrderEditSlipEvidence>> evidence() async {
    if (_disposed) return const <OrderEditSlipEvidence>[];
    final store = ref.read(orderEditSlipStoreProvider);
    final scope = _scope;
    if (store == null || scope.isEmpty) return const <OrderEditSlipEvidence>[];
    try {
      return await store.loadEvidence(scope, now: _now());
    } catch (_) {
      return const <OrderEditSlipEvidence>[];
    }
  }

  // -------------------------------------------------------------------------
  // Helpers.
  // -------------------------------------------------------------------------

  Future<PosKitchenPrintOutcome> _print(OrderChangeSlipView slip) {
    // The UI language, as for every direct kitchen ticket.
    final code = ref.read(localeControllerProvider).languageCode;
    return ref.read(posOrderEditSlipPrintProvider)(
      read: ref.read,
      slip: slip,
      labels: kitchenTicketPrintLabelsForLanguageCode(code),
      changeLabels: kitchenChangeSlipLabelsForLanguageCode(code),
    );
  }

  /// Settles the attempt for [id]: `printed` sets the mirror `sent`, removes
  /// the record and appends the direct-print evidence; anything else sets the
  /// mirror `failed` (the next drain may import it, D3) and keeps the record
  /// `failed` with its banner. Then acknowledges the dispatch.
  Future<void> _settle(String id, PosKitchenPrintOutcome outcome) async {
    if (_disposed) return;
    final record = _records[id];
    if (record == null) return; // handed over or retired meanwhile
    final claims = ref.read(posRoundPrintClaimStoreProvider);
    final dispatchId = record.dispatchId;
    final mirrorKey = dispatchId == null
        ? null
        : posOrderEditDispatchClaimKey(dispatchId);
    final printed = outcome == PosKitchenPrintOutcome.printed;
    final ack = dispatchId == null
        ? null
        : ref.read(posKitchenDispatchAckProvider);
    if (mirrorKey != null && claims != null) {
      try {
        await claims.record(
          mirrorKey,
          printed
              ? PosRoundPrintClaimState.sent
              : PosRoundPrintClaimState.failed,
        );
      } catch (_) {
        // The mirror stays `claimed`, which errs toward NOT printing again.
      }
    }
    if (_disposed) return;
    final now = _now();
    if (printed) {
      _decided[id] = OrderEditSlipOutcome.printed;
      await _mutate((m) => m.remove(id));
      final created = record.editCreatedAt;
      if (_disposed) return;
      final store = ref.read(orderEditSlipStoreProvider);
      final scope = _scope;
      if (created != null && store != null && scope.isNotEmpty) {
        try {
          await store.appendEvidence(
            scope,
            OrderEditSlipEvidence(
              orderId: record.orderId,
              dispatchId: dispatchId,
              editCreatedAt: created,
              recordedAt: now,
            ),
            now: now,
          );
        } catch (_) {
          // Advisory: without it the local sweep only KEEPS a job.
        }
      }
    } else if (_records.containsKey(id)) {
      final failed = (_records[id] ?? record).copyWith(
        state: OrderEditSlipState.failed,
        attempts: record.attempts + 1,
        updatedAt: now,
      );
      await _mutate((m) => m[id] = failed);
    }
    if (ack != null && dispatchId != null) {
      unawaited(_acknowledge(ack, dispatchId, outcome));
    }
  }

  /// Reports the direct print. Every answer is ignored — terminal
  /// (`not_claim_owner`, `conflict`, `not_found`, `ambiguous_print_hold`) or
  /// transient: the dispatch is this till's claim, so the next drain
  /// re-serves it and the consult acknowledges it from the mirror.
  Future<void> _acknowledge(
    SupabaseKitchenDispatchAckRepository ack,
    String dispatchId,
    PosKitchenPrintOutcome outcome,
  ) async {
    final (status, code) = switch (outcome) {
      PosKitchenPrintOutcome.printed => (
        KitchenImportAckStatus.transportAccepted,
        null,
      ),
      PosKitchenPrintOutcome.noPrinterConfigured => (
        KitchenImportAckStatus.failedRetryable,
        'pos_slip_no_printer',
      ),
      PosKitchenPrintOutcome.unavailable => (
        KitchenImportAckStatus.failedRetryable,
        'pos_slip_unavailable',
      ),
      PosKitchenPrintOutcome.failed || PosKitchenPrintOutcome.ineligibleOrder =>
        (KitchenImportAckStatus.failedRetryable, 'pos_slip_send_failed'),
    };
    try {
      await ack.acknowledge(
        dispatchId: dispatchId,
        status: status,
        errorCode: code,
      );
    } catch (_) {
      // Ignored by design (see above).
    }
  }

  /// Removes every unsent slip of [orderId] older than [editNumber] (a newer
  /// edit's dispatch superseded them server-side). One in flight is left to
  /// settle.
  Future<void> _retireOlder(String orderId, int editNumber) async {
    final ids = [
      for (final r in _records.values)
        if (r.orderId == orderId &&
            r.editNumber < editNumber &&
            !_inFlight.containsKey(r.orderEditId))
          r.orderEditId,
    ];
    if (ids.isEmpty) return;
    for (final id in ids) {
      _decided[id] = OrderEditSlipOutcome.superseded;
    }
    await _mutate((m) => ids.forEach(m.remove));
  }

  Future<void> _retire(String id, OrderEditSlipOutcome why) async {
    _decided[id] = why;
    await _mutate((m) => m.remove(id));
  }

  void _release(String id) {
    _inFlight.remove(id);
    _publish();
  }
}

final orderEditSlipControllerProvider =
    NotifierProvider<OrderEditSlipController, OrderEditSlipsState>(
      OrderEditSlipController.new,
    );

/// The unsent slips a banner (and an order row) offers Print again for:
/// every recorded slip that is not printing right now, minus the ones the
/// order's server snapshot already shows superseded — a newer edit
/// (`edit_count` past its number) or a voided / cancelled order.
final orderEditPendingSlipsProvider = Provider<List<OrderEditSlipRecord>>((
  ref,
) {
  final slips = ref.watch(orderEditSlipControllerProvider);
  final orders = ref.watch(posRecentOrdersControllerProvider);
  final byOrder = <String, PosRecentOrder>{
    for (final o in orders)
      if (o.orderId case final id?) id: o,
  };
  final pending = <OrderEditSlipRecord>[
    for (final r in slips.records.values)
      if (!slips.inFlight.contains(r.orderEditId) &&
          !_supersededBySnapshot(byOrder[r.orderId], r))
        r,
  ];
  pending.sort((a, b) {
    final c = a.updatedAt.compareTo(b.updatedAt);
    return c != 0 ? c : a.orderEditId.compareTo(b.orderEditId);
  });
  return List<OrderEditSlipRecord>.unmodifiable(pending);
});

bool _supersededBySnapshot(PosRecentOrder? order, OrderEditSlipRecord r) {
  if (order == null) return false;
  return order.editCount > r.editNumber ||
      order.isVoided ||
      order.serverStatus == 'cancelled';
}
