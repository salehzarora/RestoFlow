import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/customer_phone.dart';
import '../data/durable_outbox_store.dart';
import '../data/ids.dart';
import '../data/order_identity.dart';
import '../data/order_submission.dart';
import '../data/outbox_repository.dart';
import 'cart_controller.dart';
import 'pos_device_context.dart';
import 'pos_menu_provider.dart';
import 'pos_session.dart';
import 'recent_orders_controller.dart';

/// Demo tenant/device scope for submitted orders (DECISION D-001/D-002/D-022).
/// Self-consistent demo values — NOT wired to real auth/org/device context.
const String kDemoOrgId = 'demo-org';
const String kDemoRestaurantId = 'demo-restaurant';
const String kDemoBranchId = 'demo-branch';
const String kDemoDeviceId = 'demo-device';

/// The result of a successful [OutboxController.submit]: the created outbox
/// entry plus the provisional order number to show on the confirmation.
class OrderSubmitResult {
  const OrderSubmitResult({required this.entry, required this.orderNumber});
  final OutboxEntry entry;
  final String orderNumber;
}

/// Owns the client outbox (RF-115): builds a structured order-submission
/// payload from the active cart, enqueues it (real outbox seam), and drives the
/// demo sync lifecycle (push / retry). State is the recent entries, most recent
/// first. In-memory demo only — honestly labelled; no backend.
class OutboxController extends Notifier<List<OutboxEntry>> {
  late OutboxRepository _repo;
  int _seq = 0;
  bool _disposed = false;
  bool _sweeping = false;

  /// Auto-retry cap for a transiently-FAILED entry before it waits for a manual
  /// retry (so a persistently-rejecting backend is not spammed).
  static const int _maxAutoAttempts = 5;

  @override
  List<OutboxEntry> build() {
    _repo = ref.watch(outboxRepositoryProvider);
    ref.onDispose(() => _disposed = true);
    // RF-114: load any orders queued before a refresh / tab close / app restart
    // (the durable outbox) and best-effort deliver them. Fire-and-forget so
    // build() stays synchronous; state updates when the async load completes.
    _recover();
    // Optional periodic sweep so queued / transiently-failed orders sync once
    // connectivity/backend recovers (no connectivity dependency). OFF unless an
    // interval is provided — main.dart enables it for the real app; tests leave
    // it null so `pumpAndSettle` terminates (a periodic timer never settles).
    final interval = ref.read(outboxAutoSweepIntervalProvider);
    if (interval != null) {
      final timer = Timer.periodic(interval, (_) => _sweep());
      ref.onDispose(timer.cancel);
    }
    return const <OutboxEntry>[];
  }

  /// Loads the durable queue on start and delivers whatever is not yet applied.
  /// Fail-closed: if the real outbox has no session/transport yet it throws, so
  /// we simply skip — a later rebuild (after PIN sign-in) re-runs this.
  Future<void> _recover() async {
    final List<OutboxEntry> loaded;
    try {
      loaded = await _repo.recentEntries();
    } catch (_) {
      return;
    }
    if (_disposed || loaded.isEmpty) return;
    state = loaded;
    await _sweep();
  }

  /// Best-effort delivery of queued orders: re-queue + push transiently-FAILED
  /// entries (up to [_maxAutoAttempts]) and push still-PENDING ones. Retries are
  /// idempotent (`(deviceId, localOperationId)`, D-022) so a re-push after a
  /// restart never creates a duplicate. Single-flight; aborts on session loss.
  Future<void> _sweep() async {
    if (_sweeping || _disposed) return;
    _sweeping = true;
    try {
      final failed = <String>[
        for (final e in state)
          // REVIEW B2: a permanent business rejection replays its stored
          // verdict forever — sweeping it would burn attempts on a foregone
          // conclusion and imply the order might still go through.
          if (e.syncState.isFailed &&
              !e.hasDefinitiveVerdict &&
              e.attemptCount < _maxAutoAttempts)
            e.id,
      ];
      final pending = <String>[
        for (final e in state)
          if (e.syncState.isPending) e.id,
      ];
      for (final id in failed) {
        if (_disposed) return;
        try {
          await retryEntry(id);
        } catch (_) {
          return; // session/transport lost — stop; a later sweep resumes.
        }
      }
      for (final id in pending) {
        if (_disposed) return;
        final cur = entryById(id);
        if (cur == null || !cur.syncState.isPending) continue;
        try {
          await pushEntry(id);
        } catch (_) {
          return;
        }
      }
    } finally {
      _sweeping = false;
    }
  }

  /// POS-OPERATIONS-SYNC-001: push whatever is queued, now.
  ///
  /// The reconnect/startup sequence is PUSH-then-PULL: queued work is delivered and
  /// its acknowledgements/rejections processed BEFORE an authoritative pull, so the
  /// pull observes a server that has already seen this device's writes. Pulling
  /// first would hand us a snapshot that predates our own queued payment and invite
  /// the UI to "correct" itself back to a state we are in the middle of changing.
  ///
  /// Re-entrancy is already guarded inside [_sweep]; a second caller is a no-op
  /// rather than a second concurrent push.
  Future<void> pushQueued() => _sweep();

  /// How many failures are TERMINAL and provably created nothing on the server,
  /// so an operator may clear them — see
  /// [OutboxEntry.isDismissibleResolvedFailure].
  int get dismissibleFailureCount =>
      state.where((e) => e.isDismissibleResolvedFailure).length;

  /// Removes the resolved (terminal, never-applied) failures and returns how
  /// many went. The removal is DURABLE-OR-NOTHING: a device whose storage
  /// refuses the write keeps every entry and throws, rather than showing a
  /// cleared queue that repopulates on the next start. It touches nothing else — no shift, no order, no payment, no
  /// server call. Everything uncertain, retryable, conflicted or unreadable
  /// stays exactly where it is.
  Future<int> dismissResolvedFailures() async {
    final Object repo = _repo;
    // A repository that stores nothing has nothing to retire (the demo/test
    // doubles). Learning that is the honest outcome — never a silent success.
    if (repo is! PosOutboxFailureDismissal) return 0;
    final removed = await repo.dismissResolvedFailures();
    if (removed > 0 && !_disposed) {
      state = await _repo.recentEntries();
    }
    return removed;
  }

  /// Manually re-queues + pushes every RETRYABLE failed entry ("Sync failed —
  /// retry all"). REVIEW B2: definitively-refused operations are excluded —
  /// their verdict exists and replay cannot change it.
  ///
  /// 024: the test is now [OutboxEntry.hasDefinitiveVerdict], not the narrower
  /// code allowlist. A typed `auth` refusal and a structured refusal carrying an
  /// unrecognised code were both being re-pushed forever, once per sweep, for an
  /// answer that could not change.
  Future<void> retryAllFailed() async {
    final failed = <String>[
      for (final e in state)
        if (e.syncState.isFailed && !e.hasDefinitiveVerdict) e.id,
    ];
    for (final id in failed) {
      try {
        await retryEntry(id);
      } catch (_) {
        break;
      }
    }
  }

  /// POS-SUBMIT-GUARD-001: a submit already running on THIS controller. The
  /// controller (a Notifier) outlives any cart widget, so this lock holds even
  /// when the phone cart sheet is dismissed and reopened mid-submit — the case
  /// that would otherwise drop [CartPanelContent]'s widget-local guard and let a
  /// second Send tap mint a duplicate order with fresh idempotency keys.
  Future<OrderSubmitResult>? _inFlightSubmit;

  /// Builds + enqueues an order submission from the current cart snapshot.
  /// Throws [OrderSubmissionException] for an empty cart or a dine-in order
  /// without a table (defence-in-depth — the Send button is also gated).
  ///
  /// POS-SUBMIT-GUARD-001: while a submit is in flight, a repeat call JOINS it
  /// (returns the same future / the same order) instead of enqueuing a second
  /// `order.submit` op. This is the correctness boundary; the Send-button
  /// spinner is the UX layer on top.
  Future<OrderSubmitResult> submit({
    required List<CartLineView> lines,
    required int subtotalMinor,
    required String currencyCode,
    required OrderType orderType,
    String? tableId,
    String? tableLabel,
    int taxTotalMinor = 0,
    String? customerName,
    String? customerPhone,
    OrderDispatchMode dispatchMode = OrderDispatchMode.kds,
    Map<String, List<KitchenPrepComponent>>? prepByItemId,
    Future<bool> Function(
      String orderId,
      String localOperationId,
      String entryId,
    )?
    beforeDispatch,
  }) {
    final existing = _inFlightSubmit;
    if (existing != null) return existing;
    final future = _runSubmit(
      lines: lines,
      subtotalMinor: subtotalMinor,
      currencyCode: currencyCode,
      orderType: orderType,
      tableId: tableId,
      tableLabel: tableLabel,
      taxTotalMinor: taxTotalMinor,
      customerName: customerName,
      customerPhone: customerPhone,
      dispatchMode: dispatchMode,
      prepByItemId: prepByItemId,
      beforeDispatch: beforeDispatch,
    );
    _inFlightSubmit = future;
    // Release the lock once the submit settles (success OR failure) so the next
    // order can go; clear only if a newer submit has not already replaced it.
    // `.ignore()` (not the returned original `future`, which the caller handles)
    // keeps a rejected submit from surfacing as an unhandled async error here.
    future.whenComplete(() {
      if (identical(_inFlightSubmit, future)) _inFlightSubmit = null;
    }).ignore();
    return future;
  }

  Future<OrderSubmitResult> _runSubmit({
    required List<CartLineView> lines,
    required int subtotalMinor,
    required String currencyCode,
    required OrderType orderType,
    String? tableId,
    String? tableLabel,
    int taxTotalMinor = 0,
    String? customerName,
    String? customerPhone,
    OrderDispatchMode dispatchMode = OrderDispatchMode.kds,
    Map<String, List<KitchenPrepComponent>>? prepByItemId,
    Future<bool> Function(
      String orderId,
      String localOperationId,
      String entryId,
    )?
    beforeDispatch,
  }) async {
    if (lines.isEmpty) {
      throw const OrderSubmissionException('cannot submit an empty cart');
    }
    if (orderType == OrderType.dineIn &&
        (tableId == null || tableId.trim().isEmpty)) {
      throw const OrderSubmissionException('dine-in order requires a table');
    }
    // ORDER-CUSTOMER-001: normalize the OPTIONAL customer name at this single
    // choke point (covers demo + real). Trim + empty->null + 80-char cap; never
    // gates submit. The server re-normalizes identically.
    final normalizedCustomerName = normalizeCustomerName(customerName);
    // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: normalize the OPTIONAL phone at the
    // same choke point — trim + empty->null; an invalid value becomes null here
    // (the Send button already blocks a non-empty malformed phone, and the server
    // re-validates). Never gates submit.
    final normalizedCustomerPhone = normalizeCustomerPhone(customerPhone);

    _seq++;
    final n = _seq.toString().padLeft(4, '0');
    final isDemo = ref.read(runtimeConfigProvider).isDemoMode;
    // A REAL submission carries CLIENT-GENERATED UUIDs (DECISION D-010 / D-022):
    // the [orderId] and [localOperationId] are sent to `public.sync_push` and
    // MUST be valid UUIDs, never the demo `demo-order-*` / `demo-op-*` labels.
    // Demo mode keeps its deterministic, clearly-labelled ids (no backend - the
    // ids are never transmitted). The [orderNumber] stays a provisional display
    // label (`DEMO-$n`); it is NOT part of the transport body.
    final ids = isDemo ? null : ref.read(clientIdGeneratorProvider);
    final orderId = isDemo ? 'demo-order-$n' : ids!.newId();
    final localOperationId = isDemo ? 'demo-op-$n' : ids!.newId();
    final entryId = isDemo ? 'demo-outbox-$n' : ids!.newId();
    // Demo keeps the honest DEMO-nnnn label; a REAL order shows the shared
    // display code derived from its uuid — the KDS derives the SAME code from
    // the pulled order id, so cashier and kitchen talk about one number.
    final orderNumber = isDemo ? 'DEMO-$n' : displayOrderCode(orderId);
    final createdAt = DateTime.now();

    // RF-114 scope binding: a REAL order is bound to the CURRENT paired device +
    // tenant scope (never a demo placeholder). deviceId comes from the active
    // sync session (the authoritative device identity, also used as the durable
    // store key); org/restaurant/branch come from the paired device context (for
    // defensive replay metadata). On replay the outbox refuses to submit an order
    // whose deviceId != the current session's device (survives unpair/re-pair).
    final session = isDemo ? null : ref.read(posSyncSessionProvider);
    final ctx = isDemo ? null : ref.read(posDeviceContextProvider);
    final deviceId = isDemo
        ? kDemoDeviceId
        : (session?.deviceId ?? ctx?.deviceId ?? kDemoDeviceId);
    final organizationId = isDemo
        ? kDemoOrgId
        : (ctx?.organizationId ?? kDemoOrgId);
    final restaurantId = isDemo
        ? kDemoRestaurantId
        : (ctx?.restaurantId ?? kDemoRestaurantId);
    final branchId = isDemo ? kDemoBranchId : (ctx?.branchId ?? kDemoBranchId);

    // KITCHEN-PREP-001: the ORDER-TIME (D-008) prep snapshot. Each line carries
    // its menu item's configured PER-UNIT prep components, looked up by
    // menuItemId from the live menu the POS is selling from. Non-money; empty
    // for unconfigured items. Snapshotted into the payload so the outbox
    // preserves it and the KDS can aggregate a prep summary offline.
    //
    // KITCHEN-PRINT-DUAL-001B (snapshot-race fix): when the caller captured this
    // map BEFORE the first await (CartPanel does, and reuses the SAME map for the
    // POS kitchen ticket), use it verbatim so the authoritative payload and the
    // printed ticket consume ONE immutable snapshot — a menu/prep edit while the
    // submit is in flight can never make them disagree. Only fall back to reading
    // the live menu here when no snapshot was supplied (other callers / tests).
    final resolvedPrepByItemId =
        prepByItemId ??
        () {
          final menuData = ref.read(posMenuProvider).valueOrNull;
          return <String, List<KitchenPrepComponent>>{
            if (menuData != null)
              for (final item in menuData.items)
                if (item.prepComponents.isNotEmpty)
                  item.id: item.prepComponents,
          };
        }();

    final items = lines
        .map((l) {
          // 020 (Codex BLOCKER #1): the complete, immutable set of option ids
          // selected on THIS line — computed ONCE per line and shared by every
          // modifier snapshot below, so each option's classifier is answered
          // against the same authoritative selection.
          final lineSelectedOptionIds = selectedOptionIdsOf(l.modifiers);
          return OrderSubmissionItem(
            menuItemId: l.menuItemId,
            nameSnapshot: l.name,
            quantity: l.quantity,
            unitPriceMinorSnapshot: l.unitPriceMinor,
            // Already includes the line's modifier deltas × quantities, inside
            // the per-unit multiplication — the server recomputes
            // qty × (unit + Σ(delta × modifier_qty)) and must match
            // (MONEY-PRICING-FORMULA-002A). The wire still carries the BARE
            // unit price and the UNIT delta; only this total is multiplied.
            lineTotalMinor: l.lineTotalMinor,
            notes: l.note,
            // KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016: the prep snapshot with
            // its classification resolved against THIS line's selected options,
            // so `order_items.prep_snapshot` carries the order-time answer (D-008)
            // and the KDS splits the resource without re-deriving anything.
            prepComponents: classifiedPrepForLine(
              resolvedPrepByItemId[l.menuItemId] ??
                  const <KitchenPrepComponent>[],
              l.modifiers,
            ),
            modifiers: [
              for (final m in l.modifiers)
                OrderSubmissionModifier(
                  modifierOptionId: m.optionId,
                  optionNameSnapshot: m.optionName,
                  modifierNameSnapshot: m.groupName,
                  priceMinorSnapshot: m.priceDeltaMinor,
                  quantity: m.quantity,
                  // KITCHEN-MEAT-001: snapshot the option's meat contribution.
                  // 020 (Codex BLOCKER #1): the AUTHORITATIVE order-time
                  // snapshot, not raw menu configuration. It carries the
                  // per-unit quantity/unit plus classifier_selected, resolved
                  // from the complete set of options selected on THIS line, so
                  // the server and the KDS receive a decided answer instead of
                  // an unresolved config. The option units stay in the
                  // adjacent quantity field and are applied downstream once.
                  meatSnapshot: resolveOrderTimeMeatSnapshot(
                    m.kitchenMeat,
                    lineSelectedOptionIds,
                  ),
                ),
            ],
          );
        })
        .toList(growable: false);
    final itemCount = lines.fold<int>(0, (sum, l) => sum + l.quantity);

    final payload = OrderSubmissionPayload(
      orderId: orderId,
      localOperationId: localOperationId,
      deviceId: deviceId,
      organizationId: organizationId,
      restaurantId: restaurantId,
      branchId: branchId,
      orderType: orderType,
      tableId: tableId,
      currencyCode: currencyCode,
      subtotalMinor: subtotalMinor,
      // RF-117: tax computed client-side from the owner's per-branch setting
      // (0 when disabled). Discount stays 0 at submit (it is applied post-submit,
      // server-authoritative). The server validates grand = subtotal − discount
      // + tax and grand >= 0 (integer minor units, D-007).
      taxTotalMinor: taxTotalMinor,
      grandTotalMinor: subtotalMinor + taxTotalMinor,
      items: items,
      clientCreatedAt: createdAt,
      customerName: normalizedCustomerName,
      customerPhone: normalizedCustomerPhone,
      dispatchMode: dispatchMode,
    );

    final entry = OutboxEntry(
      id: entryId,
      deviceId: deviceId,
      organizationId: organizationId,
      restaurantId: restaurantId,
      branchId: branchId,
      localOperationId: localOperationId,
      operationType: 'order.submit',
      targetEntity: 'order',
      targetId: orderId,
      payloadJson: jsonEncode(payload.toJson()),
      summary: OrderSummary(
        orderNumber: orderNumber,
        orderType: orderType,
        tableLabel: tableLabel,
        itemCount: itemCount,
        subtotalMinor: subtotalMinor,
        currencyCode: currencyCode,
        customerName: normalizedCustomerName,
        customerPhone: normalizedCustomerPhone,
      ),
      syncState: OutboxSyncState.pending,
      clientCreatedAt: createdAt,
    );

    // MENU-ORDER-001 (Codex correction-ownership §4): pre-dispatch association hook. A
    // CORRECTION submit uses this to durably LINK the source recovery to THIS submit's
    // EXACT ids — the very [orderId] / [localOperationId] / [entryId] built above, never
    // a second id minted in a deeper layer — BEFORE the order is enqueued or pushed. It
    // runs inside the single-flight [submit] latch, so a concurrent second corrected
    // submit joins this future instead of re-linking. A false/throw result ABORTS the
    // submit before ANY durable enqueue or network push, so the correction association is
    // never left in-memory-only and no order is ever sent while its link failed to
    // persist (the caller surfaces the honest failure and keeps the cart for a retry).
    if (beforeDispatch != null) {
      final linked = await beforeDispatch(orderId, localOperationId, entryId);
      if (!linked) {
        throw const OrderSubmissionException(
          'correction link could not be persisted; order not sent',
        );
      }
    }
    final stored = await _repo.enqueue(entry);
    state = await _repo.recentEntries();
    if (!isDemo) {
      // REAL mode sends immediately (no manual "sync now"): push the entry so
      // the backend has the order — the KDS poll then picks it up on its own,
      // and a cash payment can reference the order server-side. A failed push
      // stays visible on the confirmation with an honest error + Retry; the
      // order itself is never lost (it remains queued in the outbox).
      await pushEntry(stored.id);
    }
    return OrderSubmitResult(entry: stored, orderNumber: orderNumber);
  }

  /// Demo-pushes [entryId]: shows "Sending…" then the delivered/failed result.
  Future<void> pushEntry(String entryId) async {
    // POS-DEFINITIVE-REJECTION-PUSH-BOUNDARY-FIX-025 — THE PUSH BOUNDARY ITSELF.
    //
    // 024 closed `retryEntry`, `retryAllFailed` and the automatic sweep, but
    // this is a PUBLIC controller method and stayed open. Anything reaching it
    // directly — the "Sync now" callback captured while the entry was still
    // retryable, a future call site, a sweep variant — could flip a
    // definitively-refused entry back to `inFlight`, spend another transport
    // attempt, and overwrite the recorded verdict with a fresh one.
    //
    // The guard re-reads the CURRENT entry by id rather than trusting anything
    // the caller holds: the stale-callback case is precisely a caller carrying
    // an entry object captured BEFORE the verdict landed. Current state wins.
    //
    // Failing closed means returning without a repository call, without a state
    // transition and without a transport attempt — the rejected shell, its
    // error code, its error kind, its attempt count and its operation identity
    // are all left exactly as the verdict recorded them. Nothing throws: this
    // controller uses typed refusals rather than exceptions for guarded
    // commands, and a caller that has been overtaken by a server verdict has
    // done nothing wrong.
    //
    // Everything uncertain still pushes — pending, in-flight, transient, server,
    // unknown, an unreadable reply and a legacy row we cannot classify. Only a
    // PROVEN verdict closes the door, so offline reconciliation is untouched.
    if (entryById(entryId)?.hasDefinitiveVerdict ?? false) return;
    // [POS-OFFLINE-OPERATIONS-002] AUTH_HOLD closes this boundary too: a held
    // entry re-enters the lifecycle ONLY through [releaseAuthHold] (a fresh
    // online sign-in), never through a direct push that would spend another
    // attempt on a session the server already refused. Fails closed silently,
    // exactly like the 025 verdict guard above — the caller did nothing wrong.
    if (entryById(entryId)?.syncState == OutboxSyncState.authHold) return;
    state = [
      for (final e in state)
        if (e.id == entryId)
          e.copyWith(syncState: OutboxSyncState.inFlight)
        else
          e,
    ];
    await _repo.push(entryId);
    state = await _repo.recentEntries();
    // [POS-OFFLINE-OPERATIONS-002] The push we just recorded may have landed a
    // batch-level auth refusal (AUTH_HOLD) — the ONE failure that is also a
    // verdict about the PIN SESSION itself. Signal the session seam exactly
    // once per push (guarded; the controller no-ops when no session is live)
    // so the PIN gate reappears, while the queued entries stay held — never
    // deleted, never swept — until the fresh sign-in releases them.
    for (final e in state) {
      if (e.id == entryId && e.syncState == OutboxSyncState.authHold) {
        try {
          ref
              .read(posSessionControllerProvider.notifier)
              .handleServerAuthRefusal();
        } catch (_) {
          // Contained: a torn-down container mid-push must not throw here.
        }
      }
    }
    // [POS-OFFLINE-OPERATIONS-002] Reconnect revalidation: a STRUCTURED server
    // answer for this operation (applied, or any per-op verdict) proves the
    // authenticated `sync_push` round-trip worked — the ONE clean seam that
    // says "this session is live online right now". Throttled inside the
    // session controller (>5 min between persisted verifications).
    for (final e in state) {
      if (e.id == entryId &&
          (e.syncState == OutboxSyncState.applied ||
              e.lastErrorKind == kServerVerdictErrorKind)) {
        try {
          ref.read(posSessionControllerProvider.notifier).noteOnlineVerified();
        } catch (_) {
          // Contained — verification is an enhancement, never load-bearing.
        }
      }
    }
    // RESTAURANT-OPERATIONS-V1-001: the server refusing an item as unavailable
    // means OUR menu is stale — a manager flipped availability after our last
    // load. Reload it so the grid greys the item out before the cashier
    // re-enters the corrected order. Availability only travels with the menu
    // (there is no realtime push), so this is the honest refresh point.
    //
    // 022 (Codex MEDIUM): the same is true of a stale PREPARATION snapshot, and
    // the test for it is now the ONE shared policy rather than a code compared
    // here — the initial push and the Add-items refusal must not be able to
    // disagree about what "our menu is stale" means. Invalidated exactly once,
    // for the one entry whose verdict we just recorded: the provider refetches
    // on the next read, so there is no loop and no eager round trip.
    for (final e in state) {
      if (e.id == entryId && e.isDefinitiveNoServerOrder) {
        if (shouldRefreshMenuForSubmissionError(e.lastErrorCode)) {
          ref.invalidate(posMenuProvider);
        }
        // PILOT-OPERATIONS-CORRECTIONS-001 (A3): the submit created NO server order.
        // Retire the phantom recent-order row to a non-actionable rejected shell so it
        // never offers payment/void/receipt for an order that does not exist. Matched
        // by the SAME identity the submit row was recorded under (target order id).
        ref
            .read(posRecentOrdersControllerProvider.notifier)
            .markLocallyRejected(
              PosOrderIdentity.of(
                orderId: e.targetId,
                localOperationId: e.localOperationId,
                outboxEntryId: e.id,
                orderNumber: e.summary.orderNumber,
              ),
            );
      }
    }
  }

  /// Re-queues a failed [entryId] and pushes it again.
  ///
  /// 024: FAILS CLOSED for a definitively-refused operation. Withdrawing the
  /// button is not enough — the command is reachable from the retry-all sweep,
  /// a stale widget still holding a callback, and any future caller. Re-pushing
  /// an operation the server has already answered cannot change the answer; it
  /// only burns an attempt and, for an `order.submit`, re-asks about an order
  /// that provably does not exist.
  Future<void> retryEntry(String entryId) async {
    for (final e in state) {
      if (e.id == entryId && e.hasDefinitiveVerdict) return;
    }
    await _repo.retry(entryId);
    state = await _repo.recentEntries();
    await pushEntry(entryId);
  }

  /// The current entry for [entryId], or null if it is unknown.
  OutboxEntry? entryById(String? entryId) {
    if (entryId == null) return null;
    for (final e in state) {
      if (e.id == entryId) return e;
    }
    return null;
  }

  /// Count of entries still queued locally (pending / created).
  int get pendingCount => state.where((e) => e.syncState.isPending).length;

  /// [POS-OFFLINE-OPERATIONS-002] Count of entries held for re-authentication.
  int get authHoldCount =>
      state.where((e) => e.syncState == OutboxSyncState.authHold).length;

  /// [POS-OFFLINE-OPERATIONS-002] Releases every AUTH_HOLD entry back to
  /// `pending` and runs a NORMAL sweep, so the released operations resubmit
  /// with the SAME `(deviceId, localOperationId)` identity (D-022 — the server
  /// replays idempotently if any had actually been applied). Called by
  /// [PosSessionController] on a successful ONLINE establish; a repository
  /// that cannot hold auth-held work (demo/test doubles) reports 0 honestly.
  Future<int> releaseAuthHold() async {
    final Object repo = _repo;
    if (repo is! PosOutboxAuthHoldRelease) return 0;
    final int released;
    try {
      released = await repo.releaseAuthHold();
    } catch (_) {
      // A refused durable write keeps every entry held (durable-or-nothing);
      // the next successful sign-in tries again. Never a throw into the
      // establish path that triggered the release.
      return 0;
    }
    if (released > 0 && !_disposed) {
      state = await _repo.recentEntries();
      await _sweep();
    }
    return released;
  }
}

/// The client outbox repository. Selects by client runtime mode (M7): the
/// in-memory [DemoOutboxStore] in demo mode (the DEFAULT), or the real
/// [RealOutboxRepository] in real mode, which posts `order.submit` ops to the
/// RF-126 `public.sync_push` wrapper. The real repo is built from the shared
/// validated anon-key transport ([posAuthTransportProvider]; no service-role key,
/// D-011) and the current [posSyncSessionProvider] session (RF-131); with no
/// transport (missing/invalid config) or no session it fails closed (no backend
/// contact). Tests can override this provider, [runtimeConfigProvider],
/// [posAuthTransportProvider], or [posSyncSessionProvider] to force a mode.
final outboxRepositoryProvider = Provider<OutboxRepository>((ref) {
  final cfg = ref.watch(runtimeConfigProvider);
  if (cfg.isDemoMode) return DemoOutboxStore();
  final transport = ref.watch(posAuthTransportProvider);
  return RealOutboxRepository(
    transport,
    ref.watch(posSyncSessionProvider),
    // RF-114: durable persistence so queued orders survive refresh/restart.
    store: ref.watch(durableOutboxStoreProvider),
  );
});

/// RF-114: the durable outbox store (localStorage-backed on web). Null by
/// default => in-memory only (demo mode / tests). Overridden in `main.dart` for
/// the real app with a [SharedPrefsOutboxStore] built on the shared
/// SharedPreferences instance.
final durableOutboxStoreProvider = Provider<DurableOutboxStore?>((ref) => null);

/// RF-114: the periodic auto-sweep interval that re-delivers queued/failed
/// orders once the backend recovers. Null by default => NO periodic timer (so
/// widget-test `pumpAndSettle` terminates). `main.dart` enables it for the real
/// app; recovery-on-start + manual retry work regardless of this.
final outboxAutoSweepIntervalProvider = Provider<Duration?>((ref) => null);

/// The POS outbox controller (recent entries, most recent first).
final outboxControllerProvider =
    NotifierProvider<OutboxController, List<OutboxEntry>>(OutboxController.new);
