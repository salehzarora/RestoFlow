import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_center_view.dart';
import 'package:restoflow_pos/src/data/order_reconciler.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/staff_capabilities.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';

/// POS-OPERATIONS-SYNC-001 (Commit 3) — the operational orders centre.
///
/// The surface stopped being a device diary and became a BRANCH view. These pin the
/// three things that makes hard: which orders appear, which section they land in,
/// and — above all — which actions are offered on them.
void main() {
  final t0 = DateTime.now().toUtc().subtract(
    const Duration(hours: 2),
  ); // stabilization: anchor to real clock (recent-orders 1-day window)

  PosOrderSnapshot snap({
    String id = 'o-1',
    String status = 'submitted',
    PosSettlement settlement = PosSettlement.unpaid,
    int grand = 4000,
    int revision = 2,
    int minutesAgo = 0,
  }) {
    final at = t0.subtract(Duration(minutes: minutesAgo));
    return PosOrderSnapshot(
      orderId: id,
      orderCode: '#${id.toUpperCase()}',
      revision: revision,
      status: status,
      settlement: settlement,
      subtotalMinor: grand,
      discountTotalMinor: 0,
      taxTotalMinor: 0,
      grandTotalMinor: grand,
      createdAt: at,
      updatedAt: at,
      syncAt: at,
    );
  }

  PosRecentOrder owned(
    PosOrderSnapshot s, {
    CashPayment? payment,
    PosOrderSyncState sync = PosOrderSyncState.synchronized,
  }) => PosRecentOrder(
    order: SubmittedOrderView(
      orderNumber: s.orderCode,
      orderType: OrderType.dineIn,
      currencyCode: 'ILS',
      subtotalMinor: s.subtotalMinor,
      lines: const <SubmittedLineView>[],
      orderId: s.orderId,
    ),
    submittedAt: s.createdAt,
    snapshot: s,
    payment: payment,
    syncState: sync,
  );

  CashPayment paidFor(PosOrderSnapshot s, {int? amountMinor}) => CashPayment(
    paymentId: 'p-${s.orderId}',
    orderNumber: s.orderCode,
    deviceId: 'd1',
    localOperationId: 'op',
    method: PaymentMethod.cash,
    status: PaymentStatus.completed,
    amountMinor: amountMinor ?? s.grandTotalMinor,
    tenderedMinor: amountMinor ?? s.grandTotalMinor,
    changeMinor: 0,
    currencyCode: 'ILS',
    receiptNumber: 'R1',
    paidAt: t0,
  );

  group('A. sections', () {
    final open = <String>[
      'submitted',
      'accepted',
      'preparing',
      'ready',
      'served',
    ];

    test('A1 Open contains every live stage and NO terminal one', () {
      for (final s in open) {
        expect(
          sectionContains(PosOrderSection.open, owned(snap(status: s))),
          isTrue,
          reason: '$s is live work',
        );
      }
      for (final s in <String>['completed', 'cancelled', 'voided']) {
        expect(
          sectionContains(PosOrderSection.open, owned(snap(status: s))),
          isFalse,
          reason: '$s is finished',
        );
      }
    });

    test('A2 Needs payment = unpaid AND still operationally relevant', () {
      // unpaid + live -> yes
      expect(
        sectionContains(
          PosOrderSection.needsPayment,
          owned(snap(status: 'served')),
        ),
        isTrue,
      );
      // paid -> no
      expect(
        sectionContains(
          PosOrderSection.needsPayment,
          owned(snap(settlement: PosSettlement.paid)),
        ),
        isFalse,
      );
      // COMPED -> no. It owes nothing; it is not a debt.
      expect(
        sectionContains(
          PosOrderSection.needsPayment,
          owned(snap(grand: 0, settlement: PosSettlement.notChargeable)),
        ),
        isFalse,
      );
      // TERMINAL, whatever it owes -> no. A cancelled order is not a debt either.
      for (final s in <String>['completed', 'cancelled', 'voided']) {
        expect(
          sectionContains(PosOrderSection.needsPayment, owned(snap(status: s))),
          isFalse,
          reason: '$s must never sit in Needs payment',
        );
      }
    });

    test('A3 Completed recently holds completed / cancelled / voided', () {
      for (final s in <String>['completed', 'cancelled', 'voided']) {
        expect(
          sectionContains(
            PosOrderSection.completedRecently,
            owned(snap(status: s)),
          ),
          isTrue,
        );
      }
      expect(
        sectionContains(
          PosOrderSection.completedRecently,
          owned(snap(status: 'ready')),
        ),
        isFalse,
      );
    });

    test('A4 a LOCAL DRAFT is in NO server section', () {
      final draft = PosRecentOrder(
        order: SubmittedOrderView(
          orderNumber: '#DRAFT',
          orderType: OrderType.dineIn,
          currencyCode: 'ILS',
          subtotalMinor: 1000,
          lines: const <SubmittedLineView>[],
        ),
        submittedAt: t0,
        origin: PosOrderOrigin.localDraft,
        syncState: PosOrderSyncState.localDraft,
      );
      for (final s in PosOrderSection.values) {
        expect(
          sectionContains(s, draft),
          isFalse,
          reason: 'a draft was never submitted; the server knows nothing of it',
        );
      }
    });
  });

  group('B. branch adoption + dedupe', () {
    test('B1 an order another till took is ADOPTED and visible', () {
      final result = reconcileSnapshots(<PosRecentOrder>[], <PosOrderSnapshot>[
        snap(id: 'foreign'),
      ]);
      final row = result.orders.single;
      expect(row.origin, PosOrderOrigin.branchDiscovered);
      expect(sectionContains(PosOrderSection.open, row), isTrue);
    });

    test('B2 a discovered row inherits NOTHING local from the other till', () {
      final row = reconcileSnapshots(<PosRecentOrder>[], <PosOrderSnapshot>[
        snap(id: 'foreign'),
      ]).orders.single;
      expect(row.order, isNull, reason: 'we never saw its lines');
      expect(row.payment, isNull, reason: 'its payment is not ours to claim');
      expect(
        row.canReprintReceipt,
        isFalse,
        reason: 'a forged receipt is a forgery',
      );
      expect(row.syncState.hasPendingWork, isFalse, reason: "not our queue");
    });

    test('B3 a device-owned order is NEVER duplicated by its own snapshot', () {
      final s = snap(id: 'mine');
      final mine = owned(s, sync: PosOrderSyncState.pendingOperation);
      final result = reconcileSnapshots(
        <PosRecentOrder>[mine],
        <PosOrderSnapshot>[snap(id: 'mine', revision: 5, status: 'ready')],
      );
      expect(result.orders.length, 1, reason: 'dedupe is by SERVER ORDER ID');
      final row = result.orders.single;
      expect(row.origin, PosOrderOrigin.deviceOwned, reason: 'still ours');
      expect(row.order, isNotNull, reason: 'we still hold its lines');
      expect(
        row.syncState,
        PosOrderSyncState.pendingOperation,
        reason: 'our queued work survives the merge',
      );
      expect(row.revision, 5, reason: 'but the server fields DO refresh');
    });

    test('B4 the same page twice cannot produce two rows', () {
      var orders = <PosRecentOrder>[];
      for (var i = 0; i < 3; i++) {
        orders = reconcileSnapshots(orders, <PosOrderSnapshot>[
          snap(id: 'x'),
        ]).orders;
      }
      expect(orders.length, 1);
    });
  });

  group('C. filters are EXACT', () {
    final unpaid = owned(snap(id: 'u'));
    final paid = owned(snap(id: 'p', settlement: PosSettlement.paid));
    final comp = owned(
      snap(id: 'c', grand: 0, settlement: PosSettlement.notChargeable),
    );
    final all = <PosRecentOrder>[unpaid, paid, comp];

    test('C1 "Paid" means PAID — it does NOT include a comp', () {
      // Nobody handed over money for a comped order. Folding it into "Paid" would
      // send a cashier reconciling a drawer hunting for cash that never existed.
      final rows = viewOrders(
        all,
        section: PosOrderSection.all,
        settlement: PosSettlementFilter.paid,
      );
      expect(rows.map((o) => o.orderId), <String>['p']);
    });

    test('C2 "No charge" means notChargeable ONLY', () {
      final rows = viewOrders(
        all,
        section: PosOrderSection.all,
        settlement: PosSettlementFilter.noCharge,
      );
      expect(rows.map((o) => o.orderId), <String>['c']);
    });

    test('C3 "Needs payment" means unpaid ONLY', () {
      final rows = viewOrders(
        all,
        section: PosOrderSection.all,
        settlement: PosSettlementFilter.needsPayment,
      );
      expect(rows.map((o) => o.orderId), <String>['u']);
    });

    test('C4 the status filter selects exactly one lifecycle stage', () {
      final rows = viewOrders(
        <PosRecentOrder>[
          owned(snap(id: 'a', status: 'ready')),
          owned(snap(id: 'b', status: 'served')),
        ],
        section: PosOrderSection.all,
        status: 'ready',
      );
      expect(rows.map((o) => o.orderId), <String>['a']);
    });
  });

  group('D. search + sort', () {
    final rows = <PosRecentOrder>[
      owned(snap(id: 'aaa111', minutesAgo: 30)),
      owned(snap(id: 'bbb222', minutesAgo: 5)),
    ];

    test('D1 search by order code, tolerant of # and case', () {
      for (final q in <String>['#AAA111', 'aaa111', ' aaa111 ']) {
        final found = viewOrders(rows, section: PosOrderSection.all, query: q);
        expect(found.single.orderId, 'aaa111', reason: 'query: $q');
      }
    });

    test('D2 an empty query restores every row', () {
      expect(
        viewOrders(rows, section: PosOrderSection.all, query: '').length,
        2,
      );
    });

    test('D3 newest first is the default; oldest first is available', () {
      final newest = viewOrders(rows, section: PosOrderSection.all);
      expect(newest.first.orderId, 'bbb222');
      final oldest = viewOrders(
        rows,
        section: PosOrderSection.all,
        sort: PosOrderSort.oldestFirst,
      );
      expect(oldest.first.orderId, 'aaa111');
    });

    test('D4 section counts are of the LOADED set, and honest about it', () {
      final counts = sectionCounts(<PosRecentOrder>[
        owned(snap(id: '1', status: 'ready')),
        owned(
          snap(id: '2', status: 'completed', settlement: PosSettlement.paid),
        ),
      ]);
      expect(counts[PosOrderSection.open], 1);
      expect(counts[PosOrderSection.completedRecently], 1);
      expect(counts[PosOrderSection.needsPayment], 1);
      expect(counts[PosOrderSection.all], 2);
    });
  });

  group('E. action eligibility — one policy, no lies', () {
    const manager = PosStaffCapabilities(
      applyDiscount: true,
      applyFullComp: true,
    );
    const cashier = PosStaffCapabilities(
      applyDiscount: true,
      applyFullComp: false,
    );
    const nothing = PosStaffCapabilities(
      applyDiscount: false,
      applyFullComp: false,
    );

    test('E1 a valid positive UNPAID order can be paid', () {
      final a = resolveOrderActions(owned(snap()), capabilities: manager);
      expect(a.canPay, isTrue);
      expect(a.canVoid, isTrue);
      expect(a.canDiscount, isTrue);
    });

    test('E2 PAID / NOT-CHARGEABLE / TERMINAL can never be paid', () {
      expect(
        resolveOrderActions(
          owned(snap(settlement: PosSettlement.paid)),
          capabilities: manager,
        ).canPay,
        isFalse,
      );
      expect(
        resolveOrderActions(
          owned(snap(grand: 0, settlement: PosSettlement.notChargeable)),
          capabilities: manager,
        ).canPay,
        isFalse,
      );
      for (final s in <String>['completed', 'cancelled', 'voided']) {
        expect(
          resolveOrderActions(
            owned(snap(status: s)),
            capabilities: manager,
          ).canPay,
          isFalse,
          reason: '$s accepts no mutation',
        );
      }
    });

    test('E3 a TERMINAL order offers no discount and no void', () {
      final a = resolveOrderActions(
        owned(snap(status: 'completed', settlement: PosSettlement.paid)),
        capabilities: manager,
      );
      expect(a.canDiscount, isFalse);
      expect(a.canVoid, isFalse);
      expect(a.canPay, isFalse);
    });

    test('E4 discount is FROZEN once the order has been charged', () {
      final s = snap(settlement: PosSettlement.paid);
      final a = resolveOrderActions(
        owned(s, payment: paidFor(s)),
        capabilities: manager,
      );
      expect(
        a.canDiscount,
        isFalse,
        reason: 'a post-payment re-price is a refund',
      );
      expect(a.canVoid, isFalse, reason: 'paid void/refund is deferred');
      expect(
        a.canOpenReceipt,
        isTrue,
        reason: 'a receipt exists and can be read',
      );
    });

    test('E5 full comp needs apply_full_comp AND apply_discount', () {
      expect(
        resolveOrderActions(owned(snap()), capabilities: manager).canFullComp,
        isTrue,
      );
      expect(
        resolveOrderActions(owned(snap()), capabilities: cashier).canFullComp,
        isFalse,
        reason: 'a cashier without the grant may discount but not comp',
      );
      // A comp grant must NOT smuggle a cashier past the general discount gate.
      const compOnly = PosStaffCapabilities(
        applyDiscount: false,
        applyFullComp: true,
      );
      final a = resolveOrderActions(owned(snap()), capabilities: compOnly);
      expect(a.canDiscount, isFalse);
      expect(a.canFullComp, isFalse, reason: 'the discount gate refuses first');
    });

    test('E6 no discount right -> no discount control', () {
      expect(
        resolveOrderActions(owned(snap()), capabilities: nothing).canDiscount,
        isFalse,
      );
    });

    test('E7 UNKNOWN capabilities are NOT denied', () {
      // A failed probe must not silently strip a manager of the discount button.
      final a = resolveOrderActions(owned(snap()), capabilities: null);
      expect(a.canDiscount, isTrue);
      expect(a.canFullComp, isTrue);
    });

    test(
      'E8 an UNDER-COVERED order cannot be paid again (the server would refuse)',
      () {
        // payments_one_completed_per_order_uidx permits ONE completed payment per
        // order. It still reads Unpaid — which is the truth — but the button would
        // fail, so it is not drawn. Collecting the shortfall needs split payment.
        final s = snap(grand: 4000, settlement: PosSettlement.unpaid);
        final a = resolveOrderActions(
          owned(s, payment: paidFor(s, amountMinor: 1000)),
          capabilities: manager,
        );
        expect(a.canPay, isFalse);
        expect(
          isCountedUnpaid(owned(s, payment: paidFor(s, amountMinor: 1000))),
          isTrue,
        );
      },
    );

    test('E9 a pending payment blocks a second one', () {
      final a = resolveOrderActions(
        owned(snap()),
        capabilities: manager,
        pending: PosPendingKind.payment,
      );
      expect(a.canPay, isFalse);
      expect(a.pendingKind, PosPendingKind.payment);
      expect(a.hasPending, isTrue);
    });

    test('E10 an active order_not_chargeable refusal blocks payment', () {
      final row = owned(snap()).copyWith(lastSyncError: 'order_not_chargeable');
      expect(
        resolveOrderActions(row, capabilities: manager).canPay,
        isFalse,
        reason: 'the server already refused; no retry can succeed',
      );
    });

    test('E11 an UNKNOWN status does NOT invent terminality or actions', () {
      final a = resolveOrderActions(
        owned(snap(status: 'teleported')),
        capabilities: manager,
      );
      // Not terminal -> the controls stay. We do not strip a live order because we
      // failed to recognise a token.
      expect(a.canPay, isTrue);
      expect(a.canVoid, isTrue);
    });

    test('E12 a LOCAL DRAFT offers nothing at all', () {
      final draft = PosRecentOrder(
        order: SubmittedOrderView(
          orderNumber: '#D',
          orderType: OrderType.dineIn,
          currencyCode: 'ILS',
          subtotalMinor: 1000,
          lines: const <SubmittedLineView>[],
        ),
        submittedAt: t0,
        origin: PosOrderOrigin.localDraft,
        syncState: PosOrderSyncState.localDraft,
      );
      expect(resolveOrderActions(draft).isEmpty, isTrue);
    });

    test(
      'E13 a BRANCH-DISCOVERED order can still be acted on — no weaker path',
      () {
        // Visibility does not grant permission, and it does not remove it either. The
        // SERVER decides; the row is not special-cased just because another till
        // opened it.
        final row = PosRecentOrder.discovered(snap(id: 'foreign'));
        final a = resolveOrderActions(row, capabilities: manager);
        expect(a.canPay, isTrue);
        expect(a.canVoid, isTrue);
        // ...but it has no lines, so there is no receipt to print.
        expect(a.canOpenReceipt, isFalse);
      },
    );

    test('E14 unknown settlement token fails closed to unpaid', () {
      expect(PosSettlement.fromWire('who_knows'), PosSettlement.unpaid);
      expect(PosSettlement.fromWire(null), PosSettlement.unpaid);
    });
  });
}
