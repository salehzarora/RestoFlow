import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/order_identity.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosPersistenceException;
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';

/// POS-OPERATIONS-SYNC-001 — the owed-rows-vs-recovery RACE, for NON-EMPTY pages.
///
/// The per-scope owed-write map preserved the unsaved rich rows across A -> B -> A
/// for the EMPTY-page retry. A NON-EMPTY page racing the delayed recovery still
/// reconciled against the (temporarily empty) live state alone: the incoming
/// snapshot was adopted as a lineless shell, the shell was persisted, and the debt
/// was cleared — the D-008 order-time lines, the receipt truth and the payment
/// metadata were discarded within the same process lifetime.
///
/// Every test here drives the REAL controller, the real scope provider and the
/// real applySnapshots/_recover paths, with only TIMING and persistence outcomes
/// controlled from outside.
void main() {
  final t0 = DateTime.utc(2026, 7, 14, 12);

  const ctxA = DeviceContext(
    organizationId: 'org-1',
    restaurantId: 'rest-1',
    branchId: 'branch-A',
    deviceId: 'device-1',
    deviceType: 'pos',
    deviceSessionId: 'ds-A',
  );
  const ctxB = DeviceContext(
    organizationId: 'org-1',
    restaurantId: 'rest-1',
    branchId: 'branch-B',
    deviceId: 'device-1',
    deviceType: 'pos',
    deviceSessionId: 'ds-B',
  );

  SubmittedOrderView richView() => const SubmittedOrderView(
    orderNumber: '#o-1',
    orderType: OrderType.takeaway,
    currencyCode: 'ILS',
    subtotalMinor: 4000,
    orderId: 'o-1',
    localOperationId: 'op-1',
    lines: [
      SubmittedLineView(
        name: 'Burger',
        quantity: 1,
        lineTotalMinor: 4000,
        currencyCode: 'ILS',
      ),
    ],
  );

  CashPayment paymentO1() => CashPayment(
    paymentId: 'pay-1',
    orderId: 'o-1',
    orderNumber: '#o-1',
    deviceId: 'device-1',
    localOperationId: 'pay-op-1',
    method: PaymentMethod.cash,
    status: PaymentStatus.completed,
    amountMinor: 4000,
    tenderedMinor: 4000,
    changeMinor: 0,
    currencyCode: 'ILS',
    receiptNumber: 'R-1',
    paidAt: t0,
  );

  /// The REDUCED SERVER SHELL for the same authoritative order id: authoritative
  /// status/money/revision, but none of the local order-time truth.
  PosOrderSnapshot shell({int revision = 3, int grand = 4000}) =>
      PosOrderSnapshot(
        orderId: 'o-1',
        orderCode: '#o-1',
        revision: revision,
        status: 'served',
        settlement: PosSettlement.paid,
        subtotalMinor: grand,
        discountTotalMinor: 0,
        taxTotalMinor: 0,
        grandTotalMinor: grand,
        createdAt: t0,
        updatedAt: t0,
        syncAt: t0,
        currencyCode: 'ILS',
      );

  ProviderContainer harness(_RaceStore store) {
    final c = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posSyncSessionProvider.overrideWithValue(
          const SyncSession(pinSessionId: 'pin', deviceId: 'device-1'),
        ),
        posRecentOrdersStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.microtask(() {});
    }
  }

  /// Asserts the ONE row for o-1 is the RICH one: order-time lines, local
  /// operation identity, payment/receipt truth, deviceOwned origin — with the
  /// authoritative server fields applied on top.
  void expectRichWithServer(PosRecentOrder row, {required int revision}) {
    expect(row.orderId, 'o-1');
    expect(
      row.order?.lines,
      isNotEmpty,
      reason: 'the D-008 order-time lines are local truth a shell cannot carry',
    );
    expect(
      row.order?.localOperationId,
      'op-1',
      reason: 'the local operation identity survives',
    );
    expect(row.payment, isNotNull, reason: 'the payment marker survives');
    expect(
      row.canReprintReceipt,
      isTrue,
      reason: 'receipt truth = order-time lines + payment; both must remain',
    );
    expect(
      row.origin,
      PosOrderOrigin.deviceOwned,
      reason: 'this till took the order; a shell must not demote it',
    );
    expect(
      row.snapshot?.revision,
      revision,
      reason: 'the AUTHORITATIVE server fields still win for what they own',
    );
    expect(row.settlement, PosSettlement.paid);
    expect(row.serverStatus, 'served');
  }

  // ===========================================================================
  test('THE RACE (server page first, recovery second): a NON-EMPTY shell page '
      'arriving before delayed recovery must NOT erase the owed rich row, and '
      'the debt clears only once the persisted result contains it', () async {
    final store = _RaceStore();
    final c = harness(store);

    // --- Scope A: one RICH deviceOwned order; its durable write FAILS.
    c.read(posDeviceContextProvider.notifier).set(ctxA);
    await settle();
    final orders = c.read(posRecentOrdersControllerProvider.notifier);
    final scopeAKey = 'org-1.rest-1.branch-A.device-1';

    store.failNextPersists = 2;
    orders.recordSubmitted(richView());
    orders.recordPayment(PosOrderIdentity.server('o-1'), paymentO1());
    await settle();
    expect(
      orders.lastPersistFailed,
      isTrue,
      reason: 'A owes a durable write containing the rich row',
    );

    // --- A -> B: neither the row nor the debt crosses.
    c.read(posDeviceContextProvider.notifier).set(ctxB);
    await settle();
    c.read(posRecentOrdersControllerProvider);
    await settle();
    expect(c.read(posRecentOrdersControllerProvider), isEmpty);
    expect(orders.lastPersistFailed, isFalse);

    // --- B -> A, with recovery DELAYED: the load blocks.
    store.gateLoads = true;
    c.read(posDeviceContextProvider.notifier).set(ctxA);
    await settle();
    c.read(posRecentOrdersControllerProvider); // build -> _recover blocks
    await settle();
    expect(
      c.read(posRecentOrdersControllerProvider),
      isEmpty,
      reason: 'precondition: the recovery race window is open',
    );

    // --- The NON-EMPTY page lands INSIDE the window. Persistence now works.
    final ok = await orders.applySnapshots([shell(revision: 3)]);
    expect(ok, isTrue);

    // The owed rich row participated in the reconciliation: what was
    // persisted is the MERGED rich row, not the shell.
    final persisted = store.persisted[scopeAKey]!;
    expect(persisted, hasLength(1));
    expectRichWithServer(persisted.single, revision: 3);
    expect(
      orders.lastPersistFailed,
      isFalse,
      reason:
          'the debt may clear ONLY because the persisted result actually '
          'incorporated the owed rows',
    );

    // --- The delayed recovery finally completes (the disk had nothing).
    store.releaseLoad(scopeAKey, const <PosRecentOrder>[]);
    await settle();

    final rows = c.read(posRecentOrdersControllerProvider);
    expect(rows, hasLength(1), reason: 'no duplicate row for one order id');
    expectRichWithServer(rows.single, revision: 3);

    // --- B remains uncontaminated.
    expect(store.persisted.keys.where((k) => k.contains('branch-B')), isEmpty);
  });

  // ===========================================================================
  test('RECOVERY FIRST, server page second: both orderings converge on the same '
      'rich merged row', () async {
    final store = _RaceStore();
    final c = harness(store);

    c.read(posDeviceContextProvider.notifier).set(ctxA);
    await settle();
    final orders = c.read(posRecentOrdersControllerProvider.notifier);

    store.failNextPersists = 2;
    orders.recordSubmitted(richView());
    orders.recordPayment(PosOrderIdentity.server('o-1'), paymentO1());
    await settle();

    c.read(posDeviceContextProvider.notifier).set(ctxB);
    await settle();
    c.read(posDeviceContextProvider.notifier).set(ctxA);
    await settle();
    // Recovery completes FIRST (unblocked, disk empty -> owed rows recovered).
    c.read(posRecentOrdersControllerProvider);
    await settle();
    expect(
      c.read(posRecentOrdersControllerProvider).single.order?.lines,
      isNotEmpty,
      reason: 'precondition: recovery already restored the owed rich row',
    );

    // THEN the shell page arrives.
    final ok = await orders.applySnapshots([shell(revision: 3)]);
    expect(ok, isTrue);

    final rows = c.read(posRecentOrdersControllerProvider);
    expect(rows, hasLength(1));
    expectRichWithServer(rows.single, revision: 3);
    expect(orders.lastPersistFailed, isFalse);
  });

  // ===========================================================================
  test(
    'THREE-WAY: owed row (richest) + OLDER durable stored row + newer server '
    'snapshot -> local richness from the best local source, server fields '
    'from the snapshot, exactly one row',
    () async {
      final store = _RaceStore();
      final c = harness(store);

      c.read(posDeviceContextProvider.notifier).set(ctxA);
      await settle();
      final orders = c.read(posRecentOrdersControllerProvider.notifier);
      final scopeAKey = 'org-1.rest-1.branch-A.device-1';

      // The OLDER durable version on disk: lines but NO payment yet.
      store.persisted[scopeAKey] = [
        PosRecentOrder(order: richView(), submittedAt: t0),
      ];

      // The in-memory day moves on: the payment lands, then the write FAILS —
      // so the OWED rows are RICHER than the disk.
      orders.recordSubmitted(richView());
      await settle();
      // Exactly ONE failure: the payment write. (recordSubmitted's write above
      // already succeeded, and the merged applySnapshots write below must be
      // allowed to succeed.)
      store.failNextPersists = 1;
      orders.recordPayment(PosOrderIdentity.server('o-1'), paymentO1());
      await settle();
      expect(orders.lastPersistFailed, isTrue);

      // A -> B -> A with recovery DELAYED, then the newer shell page races in.
      c.read(posDeviceContextProvider.notifier).set(ctxB);
      await settle();
      c.read(posRecentOrdersControllerProvider); // B activates
      await settle();
      store.gateLoads = true;
      c.read(posDeviceContextProvider.notifier).set(ctxA);
      await settle();
      c.read(posRecentOrdersControllerProvider); // A recovery starts, BLOCKED
      await settle();
      expect(
        store.hasGateFor(scopeAKey),
        isTrue,
        reason: 'precondition: the delayed-recovery window is genuinely open',
      );

      final ok = await orders.applySnapshots([shell(revision: 4)]);
      expect(ok, isTrue);

      // The delayed recovery now returns the OLDER durable row.
      store.releaseLoad(scopeAKey, [
        PosRecentOrder(order: richView(), submittedAt: t0),
      ]);
      await settle();

      final rows = c.read(posRecentOrdersControllerProvider);
      expect(rows, hasLength(1), reason: 'no duplicate, no shell replacement');
      expectRichWithServer(rows.single, revision: 4);
      expect(
        rows.single.payment,
        isNotNull,
        reason:
            'the OWED version (with the payment) outranks the older durable '
            'one — the best local source wins the local fields',
      );
    },
  );

  // ===========================================================================
  test('FAILED merged persistence: the debt remains, the rich row remains, and '
      'the retry then clears it for A alone', () async {
    final store = _RaceStore();
    final c = harness(store);

    c.read(posDeviceContextProvider.notifier).set(ctxA);
    await settle();
    final orders = c.read(posRecentOrdersControllerProvider.notifier);
    final scopeAKey = 'org-1.rest-1.branch-A.device-1';

    store.failNextPersists = 3; // submit write, payment write, AND the merge
    orders.recordSubmitted(richView());
    orders.recordPayment(PosOrderIdentity.server('o-1'), paymentO1());
    await settle();

    // The shell page arrives; the merged write FAILS too.
    final ok = await orders.applySnapshots([shell(revision: 3)]);
    expect(ok, isFalse, reason: 'a failed write is reported, never masked');
    expect(orders.lastPersistFailed, isTrue, reason: 'the debt remains');
    expectRichWithServer(
      c.read(posRecentOrdersControllerProvider).single,
      revision: 3,
    );
    expect(store.persisted[scopeAKey], isNull, reason: 'nothing durable yet');

    // RETRY (an empty page): the store has healed; the merged rich row lands.
    final okRetry = await orders.applySnapshots(const []);
    expect(okRetry, isTrue);
    expect(orders.lastPersistFailed, isFalse, reason: 'debt cleared for A');
    expectRichWithServer(store.persisted[scopeAKey]!.single, revision: 3);

    // A success in B clears nothing of A's (and vice versa).
    c.read(posDeviceContextProvider.notifier).set(ctxB);
    await settle();
    final okB = await orders.applySnapshots(const []);
    expect(okB, isTrue);
    expect(
      store.persisted[scopeAKey]!.single.order?.lines,
      isNotEmpty,
      reason: "B's activity leaves A's durable day untouched",
    );
  });

  // ===========================================================================
  test(
    'an OLDER write FAILING after newer debt was booked must not overwrite it: '
    'the newer payment metadata survives the failure race and reaches disk',
    () async {
      final store = _RaceStore();
      final c = harness(store);

      c.read(posDeviceContextProvider.notifier).set(ctxA);
      await settle();
      final orders = c.read(posRecentOrdersControllerProvider.notifier);
      final scopeAKey = 'org-1.rest-1.branch-A.device-1';

      // Debt v1: the rich submitted row, write refused.
      store.failNextPersists = 1;
      orders.recordSubmitted(richView());
      await settle();
      expect(orders.lastPersistFailed, isTrue);

      // The OLDER attempt: a shell page reconciles (merged carries the
      // authoritative snapshot) and its write HANGS in flight.
      store.gatePersist = true;
      final older = orders.applySnapshots([shell(revision: 3)]);
      await settle();

      // While it hangs: the NEWER local update — the cashier takes the payment
      // — and ITS write fails too. Debt v2 = rows WITH the payment (and, via
      // the linear state lineage, WITH the snapshot the older attempt merged).
      store.failNextPersists = 1;
      orders.recordPayment(PosOrderIdentity.server('o-1'), paymentO1());
      await settle();
      expect(
        c.read(posRecentOrdersControllerProvider).single.payment,
        isNotNull,
        reason: 'precondition: the newer update is in the live state',
      );

      // NOW the older write completes — WITH FAILURE. Its catch used to run
      // `_owedWrites[scope] = mergedOld` unconditionally, replacing debt v2
      // (payment included) with the older payment-less merge.
      store.releasePersistWithFailure();
      final ok = await older;
      expect(ok, isFalse, reason: 'the older write honestly failed');
      expect(orders.lastPersistFailed, isTrue, reason: 'debt remains owed');

      // THE PROOF that the debt was not downgraded: the debt is the only
      // carrier of the day across a scope round trip (the state resets, the
      // disk has nothing). If the older failure overwrote debt v2, the payment
      // is gone here — permanently.
      c.read(posDeviceContextProvider.notifier).set(ctxB);
      await settle();
      c.read(posRecentOrdersControllerProvider);
      await settle();
      c.read(posDeviceContextProvider.notifier).set(ctxA);
      await settle();
      c.read(posRecentOrdersControllerProvider);
      await settle();

      final rows = c.read(posRecentOrdersControllerProvider);
      expect(rows, hasLength(1), reason: 'no duplication, identity unchanged');
      expectRichWithServer(rows.single, revision: 3);
      expect(
        rows.single.payment,
        isNotNull,
        reason:
            'the NEWER debt (with the payment the disk refused) must survive '
            'the OLDER write completing with failure',
      );

      // RETRY: the store has healed; the NEWEST state lands durably, and only
      // that write pays the debt off.
      final okRetry = await orders.applySnapshots(const []);
      expect(okRetry, isTrue);
      expect(orders.lastPersistFailed, isFalse);
      final persisted = store.persisted[scopeAKey]!;
      expect(persisted, hasLength(1));
      expectRichWithServer(persisted.single, revision: 3);
      expect(
        persisted.single.payment,
        isNotNull,
        reason: 'the durable state contains the newest rich data',
      );
    },
  );

  test('a debt booked WHILE the merged write is in flight survives that write '
      '(clearing an older owed snapshot cannot erase a newer one)', () async {
    final store = _RaceStore();
    final c = harness(store);

    c.read(posDeviceContextProvider.notifier).set(ctxA);
    await settle();
    final orders = c.read(posRecentOrdersControllerProvider.notifier);

    // Book an initial debt.
    store.failNextPersists = 1;
    orders.recordSubmitted(richView());
    await settle();
    expect(orders.lastPersistFailed, isTrue);

    // Gate the NEXT persist (the merged applySnapshots write) so a newer
    // local failure can be booked while it is in flight.
    store.gatePersist = true;
    final pending = orders.applySnapshots([shell(revision: 3)]);
    await settle();

    // While the merged write hangs: a newer local write FAILS -> newer debt.
    store.failNextPersists = 1;
    orders.recordPayment(PosOrderIdentity.server('o-1'), paymentO1());
    await settle();

    // The older merged write now completes successfully.
    store.releasePersist();
    final ok = await pending;
    expect(ok, isTrue);

    expect(
      orders.lastPersistFailed,
      isTrue,
      reason:
          'the NEWER debt (the payment the disk refused) must survive the '
          'completion of the OLDER write',
    );
  });
}

// =============================================================================
// The race store: gated loads, gated/failing persists — timing only.
// =============================================================================

class _RaceStore implements PosRecentOrdersStore {
  final Map<String, List<PosRecentOrder>> persisted = {};
  final Map<String, Completer<List<PosRecentOrder>>> _loadGates = {};

  /// While true, every load blocks until [releaseLoad].
  bool gateLoads = false;

  /// Fail this many upcoming persists (then succeed).
  int failNextPersists = 0;

  /// While true, the next persist BLOCKS until [releasePersist] (then succeeds).
  bool gatePersist = false;
  Completer<void>? _persistGate;

  @override
  Future<List<PosRecentOrder>> load(String scopeKey) {
    if (!gateLoads) {
      return Future.value(
        List.of(persisted[scopeKey] ?? const <PosRecentOrder>[]),
      );
    }
    final gate = _loadGates.putIfAbsent(
      scopeKey,
      Completer<List<PosRecentOrder>>.new,
    );
    return gate.future;
  }

  bool hasGateFor(String scopeKey) => _loadGates.containsKey(scopeKey);

  void releaseLoad(String scopeKey, List<PosRecentOrder> rows) {
    _loadGates.remove(scopeKey)!.complete(rows);
  }

  @override
  Future<void> persist(String scopeKey, List<PosRecentOrder> orders) async {
    if (gatePersist) {
      gatePersist = false;
      final gate = Completer<void>();
      _persistGate = gate;
      await gate.future;
      persisted[scopeKey] = List.of(orders);
      return;
    }
    if (failNextPersists > 0) {
      failNextPersists--;
      throw const PosPersistenceException('write refused');
    }
    persisted[scopeKey] = List.of(orders);
  }

  void releasePersist() => _persistGate!.complete();

  void releasePersistWithFailure() => _persistGate!.completeError(
    const PosPersistenceException('write refused (released as failure)'),
  );
}
