import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_tables.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/table_operations_repository.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/table_operations_controller.dart';
import 'package:restoflow_pos/src/widgets/table_operations_sheet.dart';
import 'package:restoflow_domain/restoflow_domain.dart';

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Object? Function(String fn, Map<String, dynamic> p) _handler;
  final List<(String, Map<String, dynamic>)> calls = [];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return _handler(function, params);
  }
}

class _FixedId implements ClientIdGenerator {
  @override
  String newId() => 'op-1';
}

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

Map<String, dynamic> _applied() => {
  'ok': true,
  'results': [
    {'local_operation_id': 'op-1', 'status': 'applied', 'ok': true},
  ],
};
Map<String, dynamic> _rejected(String error) => {
  'ok': true,
  'results': [
    {
      'local_operation_id': 'op-1',
      'status': 'rejected',
      'ok': false,
      'error': error,
    },
  ],
};

DemoTable _table(
  String id,
  String label, {
  String manual = 'available',
  String effective = 'available',
  int active = 0,
  String? group,
}) => DemoTable(
  table: DiningTable(
    tableId: id,
    label: label,
    organizationId: 'o',
    restaurantId: 'r',
    branchId: 'b',
  ),
  status: effective == 'available'
      ? TableStatusKind.available
      : (effective == 'out_of_service'
            ? TableStatusKind.blocked
            : TableStatusKind.occupied),
  manualStatus: manual,
  effectiveState: effective,
  activeOrderCount: active,
  groupId: group,
);

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  group('RealTableOperationsRepository', () {
    test('status_set dispatches the op and succeeds', () async {
      final t = _FakeTransport((fn, p) => _applied());
      await RealTableOperationsRepository(
        t,
        _session,
        _FixedId(),
      ).setStatus(tableId: 'tbl-1', status: 'reserved');
      final op = (t.calls.single.$2['p_operations'] as List).single as Map;
      expect(op['operation_type'], 'table.status_set');
      expect((op['payload'] as Map)['status'], 'reserved');
    });

    test('link + unlink dispatch their ops', () async {
      final t = _FakeTransport((fn, p) => _applied());
      final repo = RealTableOperationsRepository(t, _session, _FixedId());
      await repo.link(tableIdA: 'a', tableIdB: 'b');
      expect(
        ((t.calls.last.$2['p_operations'] as List).single
            as Map)['operation_type'],
        'table.link',
      );
      await repo.unlink(tableId: 'a');
      expect(
        ((t.calls.last.$2['p_operations'] as List).single
            as Map)['operation_type'],
        'table.unlink',
      );
    });

    test(
      'typed refusals map to codes; out_of_service-while-occupied = table_in_use',
      () async {
        final t = _FakeTransport((fn, p) => _rejected('table_in_use'));
        expect(
          () => RealTableOperationsRepository(
            t,
            _session,
            _FixedId(),
          ).setStatus(tableId: 'x', status: 'out_of_service'),
          throwsA(
            isA<TableOperationException>().having(
              (e) => e.code,
              'code',
              'table_in_use',
            ),
          ),
        );
      },
    );

    test('OFFLINE: no session throws offline, never fake success', () {
      expect(
        () => RealTableOperationsRepository(
          _FakeTransport((fn, p) => _applied()),
          null,
          _FixedId(),
        ).setStatus(tableId: 'x', status: 'reserved'),
        throwsA(
          isA<TableOperationException>().having(
            (e) => e.code,
            'code',
            'offline',
          ),
        ),
      );
    });
  });

  test('RealTablesRepository parses effective_state + group_id', () async {
    final t = _FakeTransport(
      (fn, p) => {
        'ok': true,
        'tables': [
          {
            'id': 't1',
            'label': 'T1',
            'status': 'available',
            'effective_state': 'occupied',
            'active_order_count': 1,
            'group_id': 'g1',
          },
        ],
      },
    );
    final rows = await RealTablesRepository(t, _session).loadTables();
    final t1 = rows.single;
    expect(t1.manualStatus, 'available');
    expect(t1.effectiveState, 'occupied');
    expect(t1.groupId, 'g1');
    expect(t1.isGrouped, isTrue);
    expect(t1.status, TableStatusKind.occupied); // derived from effective
  });

  group('demo overlay -> tablesProvider', () {
    test(
      'a manual status change is reflected; effective fuses with occupancy',
      () async {
        final c = ProviderContainer(
          overrides: [
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: true),
            ),
          ],
        );
        addTearDown(c.dispose);
        // t1 is free by default -> reserving it makes effective reserved.
        c.read(demoTableOpsProvider.notifier).setStatus('t1', 'reserved');
        var tables = await c.read(tablesProvider.future);
        var t1 = tables.firstWhere((t) => t.tableId == 't1');
        expect(t1.manualStatus, 'reserved');
        expect(t1.effectiveState, 'reserved');

        // Link t1 + t2 -> both grouped.
        c.read(demoTableOpsProvider.notifier).link('t1', 't2');
        tables = await c.read(tablesProvider.future);
        final g1 = tables.firstWhere((t) => t.tableId == 't1').groupId;
        final g2 = tables.firstWhere((t) => t.tableId == 't2').groupId;
        expect(g1, isNotNull);
        expect(g1, g2);

        // Unlink dissolves the group.
        c.read(demoTableOpsProvider.notifier).unlink('t1');
        tables = await c.read(tablesProvider.future);
        expect(tables.firstWhere((t) => t.tableId == 't1').groupId, isNull);
      },
    );
  });

  group('TableOperationsSheet', () {
    Future<void> pump(
      WidgetTester tester, {
      required DemoTable table,
      required List<DemoTable> all,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: true),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(
              body: TableOperationsSheet(table: table, allTables: all),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'shows manual vs effective state distinctly and the mark actions',
      (tester) async {
        final l10n = await _en();
        // Manually available, but effectively occupied by a live order.
        final t = _table(
          't1',
          'T1',
          manual: 'available',
          effective: 'occupied',
          active: 1,
        );
        await pump(tester, table: t, all: [t]);
        expect(find.byKey(const Key('table-ops-effective')), findsOneWidget);
        // The effective row shows Occupied; the manual state is Available.
        expect(find.text(l10n.posTableStateOccupied), findsWidgets);
        expect(find.byKey(const Key('table-ops-available')), findsOneWidget);
        // Out-of-service is disabled while a live order occupies the table.
        final oos = tester.widget<ListTile>(
          find.byKey(const Key('table-ops-out-of-service')),
        );
        expect(oos.enabled, isFalse);
      },
    );

    testWidgets(
      'link mode lists valid candidates (excludes self + out of service)',
      (tester) async {
        final t1 = _table('t1', 'T1');
        final t2 = _table('t2', 'T2');
        final t3 = _table('t3', 'T3', effective: 'out_of_service');
        await pump(tester, table: t1, all: [t1, t2, t3]);
        await tester.tap(find.byKey(const Key('table-ops-link')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('table-link-candidate-t2')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('table-link-candidate-t3')),
          findsNothing, // out of service excluded
        );
        expect(
          find.byKey(const Key('table-link-candidate-t1')),
          findsNothing, // self excluded
        );
      },
    );
  });
}
