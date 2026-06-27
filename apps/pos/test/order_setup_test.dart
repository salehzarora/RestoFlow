import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_pos/src/data/demo_tables.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/widgets/table_picker_sheet.dart';

DemoTable _demoTable(
  String id, {
  TableStatusKind status = TableStatusKind.available,
  bool isActive = true,
}) => DemoTable(
  table: DiningTable(
    tableId: id,
    label: id.toUpperCase(),
    organizationId: 'demo-org',
    restaurantId: 'demo-restaurant',
    branchId: 'demo-branch',
    seats: 4,
    isActive: isActive,
  ),
  status: status,
);

void main() {
  group('DemoTablesStore (demo rules mirror the domain)', () {
    test('seeds 8–12 tables with a realistic status mix', () async {
      final tables = await DemoTablesStore().loadTables();

      expect(tables.length, inInclusiveRange(8, 12));
      final occupied = tables.where(
        (t) => t.status == TableStatusKind.occupied,
      );
      final blocked = tables.where((t) => t.status == TableStatusKind.blocked);
      final available = tables.where(
        (t) => t.status == TableStatusKind.available,
      );
      // At least two occupied (per the active-order demo brief), plus a blocked
      // and several available tables.
      expect(occupied.length, greaterThanOrEqualTo(2));
      expect(blocked, isNotEmpty);
      expect(available, isNotEmpty);
    });

    test('only available tables are assignable', () async {
      final tables = await DemoTablesStore().loadTables();
      for (final t in tables) {
        expect(t.isAssignable, t.status == TableStatusKind.available);
      }
    });

    test('a blocked table is inactive (not merely occupied)', () async {
      final tables = await DemoTablesStore().loadTables();
      final blocked = tables.firstWhere(
        (t) => t.status == TableStatusKind.blocked,
      );
      expect(blocked.table.isActive, isFalse);
    });

    test(
      'an occupied table is active but already has an open dine-in',
      () async {
        final tables = await DemoTablesStore().loadTables();
        final occupied = tables.firstWhere(
          (t) => t.status == TableStatusKind.occupied,
        );
        expect(occupied.table.isActive, isTrue);
        expect(occupied.isAssignable, isFalse);
      },
    );

    test(
      'groupTablesByArea orders Main then Patio and keeps every table',
      () async {
        final tables = await DemoTablesStore().loadTables();
        final groups = groupTablesByArea(tables);

        expect(groups.map((g) => g.areaKey).toList(), <String>[
          'Main',
          'Patio',
        ]);
        // No table is dropped or duplicated across the zones.
        final ids = groups
            .expand((g) => g.tables)
            .map((t) => t.tableId)
            .toSet();
        expect(ids.length, tables.length);
        // Tables land in the correct zone (membership, not just order/count).
        final mainIds = groups
            .firstWhere((g) => g.areaKey == 'Main')
            .tables
            .map((t) => t.tableId);
        final patioIds = groups
            .firstWhere((g) => g.areaKey == 'Patio')
            .tables
            .map((t) => t.tableId);
        expect(
          mainIds,
          containsAll(<String>['t1', 't2', 't3', 't4', 't5', 't6']),
        );
        expect(patioIds, containsAll(<String>['t7', 't8', 't9', 't10']));
      },
    );
  });

  group('OrderSetupController', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    OrderSetupState state() => container.read(orderSetupControllerProvider);
    OrderSetupController controller() =>
        container.read(orderSetupControllerProvider.notifier);

    test('defaults to takeaway with no table and is ready to submit', () {
      expect(state().orderType, OrderType.takeaway);
      expect(state().hasTable, isFalse);
      expect(state().requiresTable, isFalse);
      expect(state().isReadyToSubmit, isTrue);
      expect(state().needsTableWarning, isFalse);
    });

    test('selecting dine-in requires a table and is not yet submittable', () {
      controller().setOrderType(OrderType.dineIn);
      expect(state().requiresTable, isTrue);
      expect(state().hasTable, isFalse);
      expect(state().isReadyToSubmit, isFalse);
      expect(state().needsTableWarning, isTrue);
    });

    test('assigning an available table to a dine-in order makes it ready', () {
      controller().setOrderType(OrderType.dineIn);
      controller().assignTable(_demoTable('t1'));
      expect(state().hasTable, isTrue);
      expect(state().assignedTable!.tableId, 't1');
      expect(state().isReadyToSubmit, isTrue);
      expect(state().needsTableWarning, isFalse);
    });

    test('switching dine-in→takeaway clears the assigned table', () {
      controller().setOrderType(OrderType.dineIn);
      controller().assignTable(_demoTable('t1'));
      controller().setOrderType(OrderType.takeaway);
      expect(state().orderType, OrderType.takeaway);
      expect(state().hasTable, isFalse);
    });

    test('a takeaway order ignores table assignment', () {
      controller().assignTable(_demoTable('t1'));
      expect(state().hasTable, isFalse);
    });

    test('occupied / blocked tables cannot be assigned', () {
      controller().setOrderType(OrderType.dineIn);
      controller().assignTable(
        _demoTable('busy', status: TableStatusKind.occupied),
      );
      expect(state().hasTable, isFalse);
      controller().assignTable(
        _demoTable('dead', status: TableStatusKind.blocked, isActive: false),
      );
      expect(state().hasTable, isFalse);
    });

    test('clearTable unassigns the table but keeps dine-in', () {
      controller().setOrderType(OrderType.dineIn);
      controller().assignTable(_demoTable('t1'));
      controller().clearTable();
      expect(state().orderType, OrderType.dineIn);
      expect(state().hasTable, isFalse);
      expect(state().needsTableWarning, isTrue);
    });

    test('reset returns to the takeaway default', () {
      controller().setOrderType(OrderType.dineIn);
      controller().assignTable(_demoTable('t1'));
      controller().reset();
      expect(state().orderType, OrderType.takeaway);
      expect(state().hasTable, isFalse);
    });
  });
}
