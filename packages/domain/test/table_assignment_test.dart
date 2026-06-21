import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

LocalOrder _order({
  String orderId = 'o1',
  String org = 'org-1',
  String rest = 'rest-1',
  String? branch = 'branch-1',
  OrderType type = OrderType.dineIn,
}) {
  final cart =
      Cart(
        orderId: orderId,
        organizationId: org,
        restaurantId: rest,
        branchId: branch,
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

DiningTable _table({
  String id = 't1',
  String org = 'org-1',
  String rest = 'rest-1',
  String branch = 'branch-1',
  bool active = true,
}) => DiningTable(
  tableId: id,
  label: 'Table 1',
  organizationId: org,
  restaurantId: rest,
  branchId: branch,
  isActive: active,
);

void main() {
  group('dine-in / takeaway assignment (RF-035 AC#1)', () {
    test('a dine-in order is assignable to a table', () {
      final placement = TableAssignmentService().assignDineIn(
        order: _order(),
        table: _table(),
      );
      expect(placement.orderId, 'o1');
      expect(placement.orderType, OrderType.dineIn);
      expect(placement.tableId, 't1');
    });

    test('a takeaway order is marked takeaway with no table', () {
      final placement = TableAssignmentService().assignTakeaway(
        order: _order(orderId: 'o2', type: OrderType.takeaway),
      );
      expect(placement.orderId, 'o2');
      expect(placement.orderType, OrderType.takeaway);
      expect(placement.tableId, isNull);
    });

    test('a dine-in placement without a table is rejected', () {
      expect(
        () => OrderPlacement.dineIn('o1', ''),
        throwsA(isA<MissingTableForDineInException>()),
      );
    });

    test('a takeaway placement may not carry a tableId', () {
      // Enforced structurally (no factory accepts a table); the dine-in/takeaway
      // distinction is in OrderPlacement.
      final p = OrderPlacement.takeaway('o2');
      expect(p.tableId, isNull);
    });

    test('assignDineIn rejects a takeaway order (type mismatch)', () {
      expect(
        () => TableAssignmentService().assignDineIn(
          order: _order(type: OrderType.takeaway),
          table: _table(),
        ),
        throwsA(isA<OrderTypeMismatchException>()),
      );
    });

    test('assignTakeaway rejects a dine-in order (type mismatch)', () {
      expect(
        () => TableAssignmentService().assignTakeaway(
          order: _order(type: OrderType.dineIn),
        ),
        throwsA(isA<OrderTypeMismatchException>()),
      );
    });
  });

  group('table tenant fields (RF-035 AC#2)', () {
    test('a DiningTable carries organization/restaurant/branch', () {
      final t = _table();
      expect(t.organizationId, 'org-1');
      expect(t.restaurantId, 'rest-1');
      expect(t.branchId, 'branch-1');
    });

    test('required table fields must be non-empty', () {
      expect(
        () => DiningTable(
          tableId: '',
          label: 'x',
          organizationId: 'o',
          restaurantId: 'r',
          branchId: 'b',
        ),
        throwsA(isA<InvalidDiningTableException>()),
      );
      expect(
        () => DiningTable(
          tableId: 't',
          label: '  ',
          organizationId: 'o',
          restaurantId: 'r',
          branchId: 'b',
        ),
        throwsA(isA<InvalidDiningTableException>()),
      );
    });
  });

  group('tenant-match + active guards (RF-035)', () {
    test('organization mismatch is rejected', () {
      expect(
        () => TableAssignmentService().assignDineIn(
          order: _order(org: 'org-1'),
          table: _table(org: 'org-2'),
        ),
        throwsA(isA<TableTenantMismatchException>()),
      );
    });

    test('restaurant mismatch is rejected', () {
      expect(
        () => TableAssignmentService().assignDineIn(
          order: _order(rest: 'rest-1'),
          table: _table(rest: 'rest-2'),
        ),
        throwsA(isA<TableTenantMismatchException>()),
      );
    });

    test('branch mismatch is rejected', () {
      expect(
        () => TableAssignmentService().assignDineIn(
          order: _order(branch: 'branch-1'),
          table: _table(branch: 'branch-2'),
        ),
        throwsA(isA<TableTenantMismatchException>()),
      );
    });

    test('an inactive table is rejected', () {
      expect(
        () => TableAssignmentService().assignDineIn(
          order: _order(),
          table: _table(active: false),
        ),
        throwsA(isA<InactiveTableException>()),
      );
    });

    test('an order with a null branch is rejected (fail-closed)', () {
      // LocalOrder.branchId is nullable; a table requires a branch, so a
      // null-branch order can never match -> tenant mismatch.
      expect(
        () => TableAssignmentService().assignDineIn(
          order: _order(branch: null),
          table: _table(),
        ),
        throwsA(isA<TableTenantMismatchException>()),
      );
    });
  });

  group('empty orderId on a placement (RF-035)', () {
    test('takeaway with an empty orderId is rejected', () {
      expect(
        () => OrderPlacement.takeaway(''),
        throwsA(isA<InvalidOrderPlacementException>()),
      );
    });

    test(
      'dine-in with an empty orderId is rejected before the table check',
      () {
        expect(
          () => OrderPlacement.dineIn('', 't1'),
          throwsA(isA<InvalidOrderPlacementException>()),
        );
      },
    );
  });

  group('value equality (RF-035)', () {
    test('identical DiningTables are equal; differing fields are not', () {
      expect(_table(), _table());
      expect(_table().hashCode, _table().hashCode);
      expect(
        DiningTable(
          tableId: 't1',
          label: 'Table 1',
          organizationId: 'org-1',
          restaurantId: 'rest-1',
          branchId: 'branch-1',
          seats: 4,
        ),
        isNot(_table()),
      );
    });

    test('OrderPlacement equality distinguishes type and table', () {
      expect(OrderPlacement.dineIn('o', 't'), OrderPlacement.dineIn('o', 't'));
      expect(
        OrderPlacement.dineIn('o', 't1'),
        isNot(OrderPlacement.dineIn('o', 't2')),
      );
      expect(
        OrderPlacement.dineIn('o', 't'),
        isNot(OrderPlacement.takeaway('o')),
      );
    });

    test('TablePolicy equality reflects the flag', () {
      expect(
        const TablePolicy(allowMultipleOpenDineInPerTable: true),
        const TablePolicy(allowMultipleOpenDineInPerTable: true),
      );
      expect(
        const TablePolicy(allowMultipleOpenDineInPerTable: true),
        isNot(const TablePolicy()),
      );
    });
  });
}
