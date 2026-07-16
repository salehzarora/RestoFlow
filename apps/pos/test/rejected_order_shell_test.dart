import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_center_view.dart';
import 'package:restoflow_pos/src/data/order_reconciler.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';

/// PILOT-OPERATIONS-CORRECTIONS-001 — A3 regressions.
///
/// A submit is recorded in Recent Orders immediately with a NON-NULL locally-generated
/// order id and origin deviceOwned. When the server PERMANENTLY rejects it
/// (item_unavailable) no server order exists — yet the old policy blocked only
/// localDraft / null-order-id rows, so the phantom exposed pay / discount / void /
/// receipt. These tests lock the fix: a rejected shell fails closed for every
/// accepted-order action and is excluded from every operational surface.

SubmittedOrderView _view() => const SubmittedOrderView(
  orderNumber: 'DEMO-1',
  orderType: OrderType.dineIn,
  currencyCode: 'ILS',
  subtotalMinor: 4200,
  lines: [
    SubmittedLineView(
      name: 'Onion rings',
      quantity: 1,
      lineTotalMinor: 4200,
      currencyCode: 'ILS',
    ),
  ],
  // A NON-NULL locally-generated order id — NOT proof of server acceptance.
  orderId: 'local-order-1',
  outboxEntryId: 'e1',
  localOperationId: 'op-1',
  tableLabel: 'T4',
);

PosRecentOrder _rejectedShell() => PosRecentOrder(
  order: _view(),
  submittedAt: DateTime.utc(2026, 7, 16),
).copyWith(neverCreated: true);

PosRecentOrder _acceptedOrder() =>
    PosRecentOrder(order: _view(), submittedAt: DateTime.utc(2026, 7, 16));

void main() {
  group('A3 central action policy fails closed for a rejected shell', () {
    test('1. it is a rejected shell, not a server order', () {
      expect(_rejectedShell().isNeverCreated, isTrue);
      // Its local order id is non-null — the trap the old policy fell into.
      expect(_rejectedShell().orderId, 'local-order-1');
    });

    test('2-8. no pay/discount/comp/void/move/receipt/lifecycle actions', () {
      final a = resolveOrderActions(_rejectedShell());
      expect(a.canPay, isFalse);
      expect(a.canDiscount, isFalse);
      expect(a.canFullComp, isFalse);
      expect(a.canVoid, isFalse);
      expect(a.canMoveTable, isFalse);
      expect(a.canOpenReceipt, isFalse);
      expect(a.isEmpty, isTrue);
    });

    test('14. an accepted order remains fully actionable', () {
      // Same view WITHOUT the rejected flag: a normal unpaid dine-in order keeps its
      // controls (proving the guard is specific to the rejected shell).
      final a = resolveOrderActions(_acceptedOrder());
      expect(a.canPay, isTrue);
      expect(a.canMoveTable, isTrue); // active dine-in
      expect(a.canVoid, isTrue);
    });
  });

  group('A3 the shell is excluded from every operational surface', () {
    test('9. it does not appear in Needs payment / unpaid count', () {
      final shell = _rejectedShell();
      expect(isCountedUnpaid(shell), isFalse);
      expect(unpaidOrderCount([shell]), 0);
      expect(sectionContains(PosOrderSection.needsPayment, shell), isFalse);
    });

    test('10/11. it is not open work and not completed (no KDS/occupancy)', () {
      final shell = _rejectedShell();
      expect(sectionContains(PosOrderSection.open, shell), isFalse);
      expect(
        sectionContains(PosOrderSection.completedRecently, shell),
        isFalse,
      );
    });

    test('1. it stays visible only under "All", clearly a non-order', () {
      final shell = _rejectedShell();
      expect(sectionContains(PosOrderSection.all, shell), isTrue);
    });

    test('an accepted order DOES appear in the operational sections', () {
      final ok = _acceptedOrder();
      expect(sectionContains(PosOrderSection.open, ok), isTrue);
      expect(sectionContains(PosOrderSection.needsPayment, ok), isTrue);
      expect(unpaidOrderCount([ok]), 1);
    });
  });

  group('A3 persistence keeps a shell non-actionable across restart', () {
    test('never_created round-trips through toJson/fromJson', () {
      final shell = _rejectedShell();
      final reloaded = PosRecentOrder.fromJson(shell.toJson());
      expect(reloaded.isNeverCreated, isTrue);
      expect(resolveOrderActions(reloaded).isEmpty, isTrue);
    });

    test('a snapshot on the row overrides the flag (an order exists)', () {
      // Defensive: never_created must not survive alongside a server snapshot.
      final withFlag = _rejectedShell();
      final json = withFlag.toJson()
        ..['snapshot'] = <String, Object?>{
          'order_id': 'srv-1',
          'order_code': '#000001',
          'revision': 1,
          'status': 'submitted',
          'payment_status': 'unpaid',
          'subtotal_minor': 4200,
          'discount_total_minor': 0,
          'tax_total_minor': 0,
          'grand_total_minor': 4200,
          'created_at': '2026-07-16T00:00:00.000Z',
          'updated_at': '2026-07-16T00:00:00.000Z',
          'sync_at': '2026-07-16T00:00:00.000Z',
        };
      final reloaded = PosRecentOrder.fromJson(json);
      expect(reloaded.isNeverCreated, isFalse);
    });
  });
}
