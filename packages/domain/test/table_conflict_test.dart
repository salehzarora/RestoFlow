import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

const _auth = OrderActionAuthorization(canVoid: true, actorId: 'manager-1');

LocalOrder _order(String orderId, {OrderType type = OrderType.dineIn}) {
  final cart =
      Cart(
        orderId: orderId,
        organizationId: 'org-1',
        restaurantId: 'rest-1',
        branchId: 'branch-1',
        currencyCode: 'ILS',
      )..addLine(
        CartLine.snapshot(
          lineId: 'l1',
          menuItemId: 'm1',
          itemNameSnapshot: 'Item',
          basePriceMinorSnapshot: 1000,
          currencyCodeSnapshot: 'ILS',
        ),
      );
  return LocalOrder.submitFromCart(cart, orderType: type);
}

DiningTable _table() => DiningTable(
  tableId: 't1',
  label: 'Table 1',
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
);

void main() {
  group('one open dine-in order per table by default (RF-035 AC#3)', () {
    test('a second open dine-in order on the same table is rejected', () {
      final service = TableAssignmentService();
      final table = _table();
      service.assignDineIn(order: _order('a'), table: table);
      expect(
        () => service.assignDineIn(order: _order('b'), table: table),
        throwsA(isA<TableOccupiedException>()),
      );
    });

    test('re-assigning the same order to its table is not a conflict', () {
      final service = TableAssignmentService();
      final table = _table();
      final a = _order('a');
      service.assignDineIn(order: a, table: table);
      // Same order again — idempotent, not an occupancy conflict.
      expect(
        () => service.assignDineIn(order: a, table: table),
        returnsNormally,
      );
    });
  });

  group(
    'config allows multiple open dine-in orders per table (RF-035 AC#3)',
    () {
      test(
        'with allowMultipleOpenDineInPerTable, a second order is allowed',
        () {
          final service = TableAssignmentService(
            policy: const TablePolicy(allowMultipleOpenDineInPerTable: true),
          );
          final table = _table();
          service.assignDineIn(order: _order('a'), table: table);
          expect(
            () => service.assignDineIn(order: _order('b'), table: table),
            returnsNormally,
          );
        },
      );
    },
  );

  group('terminal orders free the table (RF-035)', () {
    test('a completed order frees the table', () {
      final service = TableAssignmentService();
      final table = _table();
      final a = _order('a')
        ..accept()
        ..startPreparing()
        ..markReady()
        ..serve()
        ..complete(paymentSettled: true);
      service.assignDineIn(order: a, table: table);
      expect(a.status, OrderStatus.completed);
      expect(
        () => service.assignDineIn(order: _order('b'), table: table),
        returnsNormally,
      );
    });

    test('a cancelled order frees the table', () {
      final service = TableAssignmentService();
      final table = _table();
      final a = _order('a')..cancel(reason: 'customer left');
      service.assignDineIn(order: a, table: table);
      expect(
        () => service.assignDineIn(order: _order('b'), table: table),
        returnsNormally,
      );
    });

    test('a voided order frees the table', () {
      final service = TableAssignmentService();
      final table = _table();
      final a = _order('a')..voidOrder(reason: 'error', authorization: _auth);
      service.assignDineIn(order: a, table: table);
      expect(
        () => service.assignDineIn(order: _order('b'), table: table),
        returnsNormally,
      );
    });
  });

  group('occupancy reads the LIVE order status (RF-035)', () {
    test('an OPEN order holds the table until it is driven terminal', () {
      final service = TableAssignmentService();
      final table = _table();
      final a = _order('a'); // submitted -> open
      service.assignDineIn(order: a, table: table);

      // While 'a' is open, a second order is rejected...
      expect(
        () => service.assignDineIn(order: _order('b'), table: table),
        throwsA(isA<TableOccupiedException>()),
      );

      // ...then drive the SAME assigned instance to terminal AFTER assignment;
      // the guard reads isTerminal live, so the table frees up.
      a
        ..accept()
        ..startPreparing()
        ..markReady()
        ..serve()
        ..complete(paymentSettled: true);
      expect(a.status, OrderStatus.completed);
      expect(
        () => service.assignDineIn(order: _order('b'), table: table),
        returnsNormally,
      );
    });

    test(
      'two distinct instances sharing an orderId are the same logical order',
      () {
        // Occupancy de-dup is by orderId STRING (not object identity).
        final service = TableAssignmentService();
        final table = _table();
        service.assignDineIn(order: _order('dup'), table: table);
        expect(
          () => service.assignDineIn(order: _order('dup'), table: table),
          returnsNormally,
        );
      },
    );
  });

  group('takeaway + draft do not occupy a table (RF-035)', () {
    test(
      'takeaway is allowed under a permissive policy and carries no table',
      () {
        final service = TableAssignmentService(
          policy: const TablePolicy(allowMultipleOpenDineInPerTable: true),
        );
        final placement = service.assignTakeaway(
          order: _order('ta', type: OrderType.takeaway),
        );
        expect(placement.tableId, isNull);
      },
    );

    test('takeaway orders never occupy a table', () {
      final service = TableAssignmentService();
      final table = _table();
      service.assignTakeaway(order: _order('ta', type: OrderType.takeaway));
      service.assignTakeaway(order: _order('tb', type: OrderType.takeaway));
      // A dine-in order can still take the table — takeaways did not occupy it.
      expect(
        () => service.assignDineIn(order: _order('a'), table: table),
        returnsNormally,
      );
    });

    test(
      'a draft cart never reaches the service; only submitted orders occupy',
      () {
        final service = TableAssignmentService();
        final table = _table();
        // A draft cart exists but is never assigned (the service takes LocalOrder).
        Cart(
          orderId: 'draft-1',
          organizationId: 'org-1',
          restaurantId: 'rest-1',
          branchId: 'branch-1',
          currencyCode: 'ILS',
        );
        service.assignDineIn(order: _order('a'), table: table);
        // The unsubmitted cart does not free the table occupied by order 'a'.
        expect(
          () => service.assignDineIn(order: _order('b'), table: table),
          throwsA(isA<TableOccupiedException>()),
        );
      },
    );
  });
}
