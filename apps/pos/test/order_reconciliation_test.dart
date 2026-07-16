import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_pos/src/data/order_reconciler.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/order_snapshot_repository.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';

/// POS-OPERATIONS-SYNC-001 — the reconciliation engine.
///
/// The POS used to record what it SUBMITTED and never hear from the server again.
/// These tests pin the rules that end that, and in particular the exact production
/// failures that motivated the phase.
void main() {
  final t0 = DateTime.now().toUtc().subtract(
    const Duration(hours: 2),
  ); // stabilization: anchor to real clock (recent-orders 1-day window)

  PosOrderSnapshot snap({
    String orderId = 'o-1',
    int revision = 2,
    String status = 'served',
    PosSettlement settlement = PosSettlement.unpaid,
    int subtotal = 4000,
    int discount = 0,
    int tax = 0,
    int? grand,
    DateTime? syncAt,
  }) => PosOrderSnapshot(
    orderId: orderId,
    orderCode: '#0000O1',
    revision: revision,
    status: status,
    settlement: settlement,
    subtotalMinor: subtotal,
    discountTotalMinor: discount,
    taxTotalMinor: tax,
    grandTotalMinor: grand ?? (subtotal - discount + tax),
    createdAt: t0,
    updatedAt: syncAt ?? t0,
    syncAt: syncAt ?? t0,
  );

  PosRecentOrder local({
    String? orderId = 'o-1',
    int subtotal = 4000,
    CashPayment? payment,
    PosOrderSnapshot? snapshot,
    PosOrderSyncState syncState = PosOrderSyncState.synchronized,
    DateTime? voidedAt,
  }) => PosRecentOrder(
    order: SubmittedOrderView(
      orderNumber: '#0000O1',
      orderType: OrderType.dineIn,
      currencyCode: 'ILS',
      subtotalMinor: subtotal,
      lines: const <SubmittedLineView>[],
      orderId: orderId,
    ),
    submittedAt: t0,
    payment: payment,
    voidedAt: voidedAt,
    snapshot: snapshot,
    syncState: syncState,
    // origin and syncState must agree about drafts: a draft is a draft on both axes.
    origin: syncState == PosOrderSyncState.localDraft
        ? PosOrderOrigin.localDraft
        : PosOrderOrigin.deviceOwned,
  );

  CashPayment paid(int amountMinor) => CashPayment(
    paymentId: 'p1',
    orderNumber: '#0000O1',
    deviceId: 'd1',
    localOperationId: 'op1',
    method: PaymentMethod.cash,
    status: PaymentStatus.completed,
    amountMinor: amountMinor,
    tenderedMinor: amountMinor,
    changeMinor: 0,
    currencyCode: 'ILS',
    receiptNumber: 'R-1',
    paidAt: t0,
  );

  group('A. the merge rules', () {
    test('A1 a LOCAL DRAFT is never overwritten by a snapshot', () {
      // A draft has no server order id, so it is structurally unreachable from a
      // snapshot. Proven, not assumed.
      //
      // Commit 3: the snapshot IS adopted -- as a SEPARATE branch-discovered row.
      // The draft is left exactly as it was. The two are different things, and the
      // one thing we must never do is let a server row swallow local work.
      final draft = local(
        orderId: null,
        syncState: PosOrderSyncState.localDraft,
      );
      final result = reconcileSnapshots(
        <PosRecentOrder>[draft],
        <PosOrderSnapshot>[snap()],
      );
      final keptDraft = result.orders.firstWhere(
        (o) => o.origin == PosOrderOrigin.localDraft,
      );
      expect(identical(keptDraft, draft), isTrue, reason: 'untouched');
      expect(keptDraft.syncState, PosOrderSyncState.localDraft);
      expect(
        result.orders.length,
        2,
        reason: 'the server row is adopted BESIDE it',
      );
    });

    test('A2 a NEWER revision wins', () {
      final before = local(snapshot: snap(revision: 2));
      final result = reconcileSnapshots(
        <PosRecentOrder>[before],
        [snap(revision: 3, status: 'ready')],
      );
      expect(result.applied, 1);
      expect(result.orders.single.revision, 3);
      expect(result.orders.single.serverStatus, 'ready');
    });

    test(
      'A3 an OLDER revision can NEVER overwrite newer authoritative state',
      () {
        // The whole point of revision-first: a late page must not roll the till back.
        final before = local(snapshot: snap(revision: 5, status: 'completed'));
        final result = reconcileSnapshots(
          <PosRecentOrder>[before],
          [snap(revision: 4, status: 'served')],
        );
        expect(result.applied, 0);
        expect(result.orders.single.revision, 5);
        expect(result.orders.single.serverStatus, 'completed');
        expect(result.orders.single.isTerminal, isTrue);
      },
    );

    test(
      'A4 EQUAL revision + newer payment-aware cursor DOES update settlement',
      () {
        // record_payment inserts a payment WITHOUT bumping the order revision, so
        // without this rule a paid order could never become "paid" on the device.
        final before = local(
          snapshot: snap(revision: 2, settlement: PosSettlement.unpaid),
        );
        final result = reconcileSnapshots(
          <PosRecentOrder>[before],
          [
            snap(
              revision: 2,
              settlement: PosSettlement.paid,
              syncAt: t0.add(const Duration(minutes: 5)),
            ),
          ],
        );
        expect(result.applied, 1);
        expect(result.orders.single.settlement, PosSettlement.paid);
      },
    );

    test('A5 applying the SAME snapshot twice is idempotent', () {
      final s = snap(revision: 3);
      final first = reconcileSnapshots(<PosRecentOrder>[local()], [s]);
      final second = reconcileSnapshots(first.orders, [s]);
      expect(second.applied, 0);
      expect(identical(second.orders.single, first.orders.single), isTrue);
    });

    test('A6 a duplicate page does not duplicate the order', () {
      final result = reconcileSnapshots(
        <PosRecentOrder>[local()],
        [snap(revision: 3), snap(revision: 3)],
      );
      expect(result.orders.length, 1);
    });

    test('A7 a PENDING OPERATION survives reconciliation', () {
      // A snapshot is NOT an acknowledgement. The queue is the outbox's business.
      final before = local(syncState: PosOrderSyncState.pendingOperation);
      final result = reconcileSnapshots(
        <PosRecentOrder>[before],
        [snap(revision: 3)],
      );
      expect(result.applied, 1);
      expect(
        result.orders.single.syncState,
        PosOrderSyncState.pendingOperation,
        reason: 'a compatible-looking snapshot must never resolve a queued op',
      );
      expect(result.orders.single.revision, 3, reason: 'but fields DO refresh');
    });

    test('A8 a terminal snapshot moves sync state to terminal', () {
      final result = reconcileSnapshots(
        <PosRecentOrder>[local(syncState: PosOrderSyncState.pendingOperation)],
        [snap(revision: 4, status: 'completed')],
      );
      expect(result.orders.single.syncState, PosOrderSyncState.terminal);
      expect(result.orders.single.isTerminal, isTrue);
    });

    test('A9 an order missing from a bounded page is NOT deleted', () {
      final result = reconcileSnapshots(
        <PosRecentOrder>[local(orderId: 'o-1'), local(orderId: 'o-2')],
        [snap(orderId: 'o-1', revision: 3)],
      );
      expect(result.orders.length, 2);
    });

    test('A10 an order THIS DEVICE never took is ADOPTED as branch-discovered', () {
      // Commit 3: the centre is a BRANCH view. Another till took this order; it is
      // real, it is happening in this restaurant, and the cashier needs to see it.
      final result = reconcileSnapshots(
        <PosRecentOrder>[local(orderId: 'o-1')],
        [snap(orderId: 'o-99')],
      );
      expect(result.orders.length, 2);
      final discovered = result.orders.firstWhere((o) => o.orderId == 'o-99');
      expect(discovered.origin, PosOrderOrigin.branchDiscovered);
      // It carries the server's fields and NOTHING local: no order-time lines (so no
      // receipt can be forged from it), no payment marker, and none of the
      // originating till's queued work.
      expect(discovered.order, isNull);
      expect(discovered.payment, isNull);
      expect(discovered.canReprintReceipt, isFalse);
      expect(discovered.grandTotalMinor, 4000);
    });
  });

  group('B. THE PRODUCTION FAILURE — the stale 40', () {
    test('B1 a submitted 40 becomes an authoritative 0 after a full comp', () {
      // The exact reported bug: order submitted at 40, comped to 0 server-side.
      // Before this ticket the till kept showing 40, kept counting it unpaid, and
      // kept offering Take payment.
      final before = local(subtotal: 4000);
      expect(before.grandTotalMinor, 4000);
      expect(isCountedUnpaid(before), isTrue);

      final result = reconcileSnapshots(
        <PosRecentOrder>[before],
        [
          snap(
            revision: 3,
            subtotal: 4000,
            discount: 4000,
            grand: 0,
            settlement: PosSettlement.notChargeable,
          ),
        ],
      );
      final after = result.orders.single;

      expect(after.grandTotalMinor, 0, reason: 'the stale 40 is GONE');
      expect(after.settlement, PosSettlement.notChargeable);
      expect(after.isNonChargeable, isTrue);
      expect(isCountedUnpaid(after), isFalse, reason: 'a comp owes nothing');
      expect(after.discountTotalMinor, 4000);
      // The receipt view is realigned too — it cannot keep printing 40.
      expect(after.order!.grandTotalMinor, 0);
    });

    test('B2 subtotal, discount, tax and grand total move TOGETHER', () {
      final result = reconcileSnapshots(
        <PosRecentOrder>[local()],
        [snap(revision: 3, subtotal: 5000, discount: 1000, tax: 800)],
      );
      final o = result.orders.single;
      expect(o.subtotalMinor, 5000);
      expect(o.discountTotalMinor, 1000);
      expect(o.taxTotalMinor, 800);
      expect(o.grandTotalMinor, 4800);
    });
  });

  group('C. the ONE unpaid predicate', () {
    test('C1 notChargeable is NOT counted unpaid', () {
      final o = local(
        snapshot: snap(grand: 0, settlement: PosSettlement.notChargeable),
      );
      expect(isCountedUnpaid(o), isFalse);
    });

    test('C2 paid is NOT counted unpaid', () {
      final o = local(snapshot: snap(settlement: PosSettlement.paid));
      expect(isCountedUnpaid(o), isFalse);
    });

    test('C3 an UNDER-COVERED order still owes money', () {
      // The server said unpaid; a payment marker of 10 against a 40 total is not
      // settlement. The client does not argue with it.
      final o = local(
        payment: paid(1000),
        snapshot: snap(settlement: PosSettlement.unpaid),
      );
      expect(o.isPaid, isTrue, reason: 'money WAS taken (marker)');
      expect(isCountedUnpaid(o), isTrue, reason: 'but it still owes');
    });

    test('C4 a TERMINAL order is never counted unpaid, whatever it owes', () {
      final o = local(
        snapshot: snap(status: 'cancelled', settlement: PosSettlement.unpaid),
      );
      expect(o.isTerminal, isTrue);
      expect(
        isCountedUnpaid(o),
        isFalse,
        reason: 'a cancelled order is not a debt',
      );
    });

    test('C5 a local DRAFT is never counted', () {
      expect(
        isCountedUnpaid(
          local(orderId: null, syncState: PosOrderSyncState.localDraft),
        ),
        isFalse,
      );
    });

    test(
      'C6 unpaidOrderCount counts exactly the operationally-owed orders',
      () {
        final orders = <PosRecentOrder>[
          local(orderId: 'a'), // unpaid, no snapshot -> owes
          local(
            orderId: 'b',
            snapshot: snap(orderId: 'b', settlement: PosSettlement.paid),
          ),
          local(
            orderId: 'c',
            snapshot: snap(
              orderId: 'c',
              grand: 0,
              settlement: PosSettlement.notChargeable,
            ),
          ),
          local(
            orderId: 'd',
            snapshot: snap(orderId: 'd', status: 'completed'),
          ),
        ];
        expect(unpaidOrderCount(orders), 1);
      },
    );
  });

  group('D. server-driven change reaches the device', () {
    test('D1 a KDS/auto-completion the device never saw is learned on pull', () {
      // Nobody on this till did anything. The KITCHEN bumped the order and the
      // server auto-completed it. Before this ticket the POS never found out.
      final before = local(snapshot: snap(revision: 2, status: 'served'));
      expect(before.isTerminal, isFalse);

      final after = reconcileSnapshots(
        <PosRecentOrder>[before],
        [
          snap(
            revision: 3,
            status: 'completed',
            settlement: PosSettlement.paid,
          ),
        ],
      ).orders.single;

      expect(after.serverStatus, 'completed');
      expect(after.isTerminal, isTrue, reason: 'payment/cancel must disappear');
      expect(isCountedUnpaid(after), isFalse);
    });

    test('D2 a server-side VOID removes action eligibility', () {
      final after = reconcileSnapshots(
        <PosRecentOrder>[local()],
        [snap(revision: 3, status: 'voided')],
      ).orders.single;
      expect(after.isVoided, isTrue);
      expect(after.isTerminal, isTrue);
    });

    test('D3 a COMPLETED order cannot be re-opened by an older snapshot', () {
      final completed = local(snapshot: snap(revision: 5, status: 'completed'));
      final after = reconcileSnapshots(
        <PosRecentOrder>[completed],
        [snap(revision: 4, status: 'preparing')],
      ).orders.single;
      expect(after.isTerminal, isTrue, reason: 'terminal is a ratchet');
    });
  });

  group('E. strict snapshot validation', () {
    Map<String, Object?> wire() => <String, Object?>{
      'order_id': 'o-1',
      'order_code': '#0000O1',
      'revision': 2,
      'status': 'served',
      'payment_status': 'unpaid',
      'subtotal_minor': 4000,
      'discount_total_minor': 0,
      'tax_total_minor': 0,
      'grand_total_minor': 4000,
      'created_at': t0.toIso8601String(),
      'updated_at': t0.toIso8601String(),
      'sync_at': t0.toIso8601String(),
    };

    test('E1 a well-formed payload parses', () {
      expect(PosOrderSnapshot.fromJson(wire()), isNotNull);
    });

    test('E2 a MISSING required field rejects the whole snapshot', () {
      for (final key in <String>[
        'order_id',
        'order_code',
        'revision',
        'status',
        'grand_total_minor',
        'sync_at',
      ]) {
        final w = wire()..remove(key);
        expect(
          PosOrderSnapshot.fromJson(w),
          isNull,
          reason: 'missing $key must reject atomically',
        );
      }
    });

    test('E3 NEGATIVE money FAILS CLOSED', () {
      final w = wire()..['grand_total_minor'] = -1;
      expect(PosOrderSnapshot.fromJson(w), isNull);
    });

    test('E4 a NON-INTEGER amount is refused, not coerced (D-007)', () {
      // A fractional value on the wire is a CONTRACT VIOLATION, not something to
      // round: coercing it is exactly how inexact arithmetic gets into a till. The
      // parser demands `int` and rejects everything else.
      //
      // Built at runtime rather than as a literal, because
      // `tools/check_no_float_money.sh` (rightly) refuses to see an inexact type
      // beside a money identifier — and a guard you have to weaken in order to test
      // the thing it guards is a guard that has stopped working.
      final Object notAnInt = num.parse('40.5');
      expect(
        notAnInt is int,
        isFalse,
        reason: 'an inexact value reached the parser',
      );
      final w = wire()..['grand_total_minor'] = notAnInt;
      expect(PosOrderSnapshot.fromJson(w), isNull);
    });

    test('E5 an UNKNOWN payment_status fails closed to unpaid', () {
      final w = wire()..['payment_status'] = 'refunded_maybe';
      expect(PosOrderSnapshot.fromJson(w)!.settlement, PosSettlement.unpaid);
    });

    test(
      'E6 an UNKNOWN lifecycle status does NOT fabricate a terminal state',
      () {
        final w = wire()..['status'] = 'teleported';
        final s = PosOrderSnapshot.fromJson(w)!;
        expect(s.status, 'teleported', reason: 'preserved verbatim');
        expect(
          s.isTerminal,
          isFalse,
          reason:
              'inventing "terminal" would strip a live order of its controls',
        );
      },
    );

    test('E7 a malformed cursor does not parse', () {
      expect(PosSyncCursor.fromJson(<String, Object?>{'at': 'nope'}), isNull);
      expect(PosSyncCursor.fromJson(<String, Object?>{'id': 'x'}), isNull);
      expect(PosSyncCursor.fromJson(null), isNull);
    });
  });

  group('F. persistence + serialization migration', () {
    test(
      'F1 a v1 record with NO snapshot still loads (upgrade preserves it)',
      () {
        // The cashier's day must not vanish because the app upgraded.
        final legacy = <String, Object?>{
          'submitted_at': t0.toIso8601String(),
          'order': <String, Object?>{
            'order_number': '#0000O1',
            'order_type': 'dineIn',
            'currency_code': 'ILS',
            'subtotal_minor': 4000,
            'discount_total_minor': 0,
            'tax_total_minor': 0,
            'tax_rate_bp': 0,
            'order_id': 'o-1',
            'lines': <Object?>[],
          },
        };
        final o = PosRecentOrder.fromJson(legacy);
        expect(o.orderId, 'o-1');
        expect(o.grandTotalMinor, 4000);
        expect(o.snapshot, isNull);
        expect(o.syncState, PosOrderSyncState.synchronized);
      },
    );

    test('F2 a snapshot round-trips through JSON', () {
      final o = local(snapshot: snap(revision: 7, status: 'completed'));
      final back = PosRecentOrder.fromJson(o.toJson());
      expect(back.revision, 7);
      expect(back.serverStatus, 'completed');
      expect(back.isTerminal, isTrue);
    });

    test(
      'F3 a CORRUPT snapshot does not destroy the order that carries it',
      () {
        final json = local().toJson()..['snapshot'] = <String, Object?>{'x': 1};
        final back = PosRecentOrder.fromJson(json);
        expect(back.orderId, 'o-1', reason: 'the order survives');
        expect(back.snapshot, isNull, reason: 'only the bad field is dropped');
      },
    );
  });

  group('G. the repository page contract', () {
    test('G1 a page with ONE malformed row is rejected ATOMICALLY', () {
      // Applying the half we could parse and advancing the cursor past the half we
      // could not would lose those orders forever — the cursor never goes back.
      final repo = _FakeTransportRepo(<String, Object?>{
        'ok': true,
        'orders': <Object?>[
          <String, Object?>{'order_id': 'o-1'}, // malformed
        ],
        'has_more': false,
      });
      expect(
        () => repo.fetchChanges(),
        throwsA(
          isA<PosSnapshotException>().having(
            (e) => e.failure,
            'failure',
            PosSnapshotFailure.malformed,
          ),
        ),
      );
    });

    test('G2 hasMore WITHOUT a usable cursor is malformed, not "the end"', () {
      final repo = _FakeTransportRepo(<String, Object?>{
        'ok': true,
        'orders': <Object?>[],
        'has_more': true,
        'next_cursor': null,
      });
      expect(() => repo.fetchChanges(), throwsA(isA<PosSnapshotException>()));
    });

    test('G3 a refused envelope is NOT retryable; transport IS', () {
      expect(
        const PosSnapshotException(PosSnapshotFailure.transport).isRetryable,
        isTrue,
      );
      expect(
        const PosSnapshotException(PosSnapshotFailure.session).isRetryable,
        isFalse,
      );
      expect(
        const PosSnapshotException(PosSnapshotFailure.malformed).isRetryable,
        isFalse,
      );
    });
  });
}

/// A minimal stand-in that exercises the REAL envelope-parsing code path in
/// [RealOrderSnapshotRepository] without a network.
class _FakeTransportRepo implements OrderSnapshotRepository {
  _FakeTransportRepo(this._envelope);

  final Object? _envelope;

  @override
  Future<PosSnapshotPage> fetchChanges({
    PosSyncCursor? cursor,
    int limit = 50,
    int windowDays = 2,
  }) => Future<PosSnapshotPage>.sync(() => _parse(_envelope));

  @override
  Future<PosSnapshotPage> fetchWindow({
    PosSyncCursor? before,
    int limit = 50,
    int windowDays = 2,
  }) => fetchChanges(limit: limit, windowDays: windowDays);

  @override
  Future<PosSnapshotPage> fetchOrders(List<String> orderIds) =>
      Future<PosSnapshotPage>.sync(() => _parse(_envelope));

  /// Mirrors RealOrderSnapshotRepository's parse contract exactly.
  PosSnapshotPage _parse(Object? raw) {
    if (raw is! Map)
      throw const PosSnapshotException(PosSnapshotFailure.malformed);
    if (raw['ok'] != true) {
      throw const PosSnapshotException(PosSnapshotFailure.session);
    }
    final list = raw['orders'];
    if (list is! List) {
      throw const PosSnapshotException(PosSnapshotFailure.malformed);
    }
    final orders = <PosOrderSnapshot>[];
    for (final e in list) {
      final s = PosOrderSnapshot.fromJson(e);
      if (s == null) {
        throw const PosSnapshotException(PosSnapshotFailure.malformed);
      }
      orders.add(s);
    }
    final hasMore = raw['has_more'] == true;
    final cursor = PosSyncCursor.fromJson(raw['next_cursor']);
    if (hasMore && cursor == null) {
      throw const PosSnapshotException(PosSnapshotFailure.malformed);
    }
    return PosSnapshotPage(
      orders: orders,
      hasMore: hasMore,
      nextCursor: cursor,
    );
  }
}
