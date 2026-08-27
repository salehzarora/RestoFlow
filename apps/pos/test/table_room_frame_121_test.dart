import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show
        DiningTable,
        OrderType,
        TableSectionRoomFramePreset,
        TableVisualMaterial,
        floorRoomAspect,
        kFloorStandardAspect;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_tables.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/widgets/table_picker_sheet.dart';

/// TABLE-ROOM-FRAME-121 — the POS is a READ-ONLY consumer of the section's
/// room frame: tolerant decode from `pos_tables` rows, first-non-default-wins
/// aggregation in [splitTablesBySection] (the wire ships no section catalog),
/// and the group projection keeps the key. No write path exists.
void main() {
  Map<String, dynamic> envelope() => {
    'ok': true,
    'entity': 'tables',
    'tables': [
      {
        'id': 't-1',
        'label': 'T1',
        'status': 'available',
        'effective_state': 'available',
        'section_id': 's-1',
        'section_name': 'Hall',
        'section_display_order': 0,
        'section_room_frame_preset': 'long_narrow',
      },
      {
        'id': 't-2',
        'label': 'T2',
        'status': 'available',
        'effective_state': 'available',
        // no key at all (legacy hosted) => Standard
      },
      {
        'id': 't-3',
        'label': 'T3',
        'status': 'available',
        'effective_state': 'available',
        'section_room_frame_preset': 'oval', // unknown => Standard, no failure
      },
    ],
  };

  DemoTable t(
    String id, {
    String? sectionId,
    TableSectionRoomFramePreset? frame,
    TableVisualMaterial? material,
    int? x,
    int? y,
  }) => DemoTable(
    table: DiningTable(
      tableId: id,
      label: id,
      organizationId: 'o',
      restaurantId: 'r',
      branchId: 'b',
      seats: 4,
    ),
    status: TableStatusKind.available,
    sectionId: sectionId,
    sectionName: sectionId,
    sectionDisplayOrder: 0,
    layoutX: x,
    layoutY: y,
    visualMaterial: material,
    sectionRoomFramePreset: frame,
  );

  test('pos_tables rows decode section_room_frame_preset tolerantly', () async {
    final repo = RealTablesRepository(
      _StubTransport(envelope()),
      const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
    );
    final snapshot = await repo.loadFloorSnapshot();
    final byId = {for (final x in snapshot.tables) x.table.tableId: x};
    expect(
      byId['t-1']!.sectionRoomFramePreset,
      TableSectionRoomFramePreset.longNarrow,
    );
    expect(byId['t-2']!.sectionRoomFramePreset, isNull);
    expect(byId['t-3']!.sectionRoomFramePreset, isNull);
  });

  test('splitTablesBySection carries the frame (first non-default wins; '
      'all-default = Standard)', () {
    final split = splitTablesBySection([
      t('a1', sectionId: 's1'),
      t('a2', sectionId: 's1', frame: TableSectionRoomFramePreset.square),
      t('b1', sectionId: 's2'),
    ]);
    final byId = {for (final s in split.sections) s.sectionId: s};
    expect(byId['s1']!.roomFramePreset, TableSectionRoomFramePreset.square);
    expect(byId['s2']!.roomFramePreset, isNull);
  });

  test('the group projection keeps the frame AND the material '
      '(copyWithGroupState carries every presentation key)', () {
    final copy =
        t(
          'a1',
          sectionId: 's1',
          frame: TableSectionRoomFramePreset.wide,
          material: TableVisualMaterial.rusticWood,
        ).copyWithGroupState(
          effectiveState: 'occupied',
          activeOrderCount: 1,
          status: TableStatusKind.occupied,
        );
    expect(copy.sectionRoomFramePreset, TableSectionRoomFramePreset.wide);
    // The deliberate 120-defect fix: the material survives the projection
    // (dropping the carry line in copyWithGroupState must fail HERE).
    expect(copy.visualMaterial, TableVisualMaterial.rusticWood);
  });

  testWidgets('the picker section canvas projects at the section frame '
      '(Standard sections keep the legacy ratio)', (tester) async {
    tester.view.physicalSize = const Size(900, 1700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rows = [
      t(
        'a1',
        sectionId: 's1',
        frame: TableSectionRoomFramePreset.compact,
        x: 1000,
        y: 1000,
      ),
      t('b1', sectionId: 's2', x: 8000, y: 8000),
    ];
    final container = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: true),
        ),
        tablesRepositoryProvider.overrideWithValue(_FakeTablesRepo(rows)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: const _Launcher(),
        ),
      ),
    );
    container
        .read(orderSetupControllerProvider.notifier)
        .setOrderType(OrderType.dineIn);
    await tester.tap(find.byKey(const Key('open-picker')));
    await tester.pumpAndSettle();
    double aspectOf(String sectionId) => tester
        .widget<AspectRatio>(
          find.descendant(
            of: find.byKey(Key('table-section-canvas-$sectionId')),
            matching: find.byType(AspectRatio),
          ),
        )
        .aspectRatio;
    expect(
      aspectOf('s1'),
      floorRoomAspect(TableSectionRoomFramePreset.compact),
    );
    expect(aspectOf('s2'), kFloorStandardAspect);
  });
}

class _FakeTablesRepo extends TablesRepository {
  _FakeTablesRepo(this.rows);
  final List<DemoTable> rows;
  @override
  Future<List<DemoTable>> loadTables() async => rows;
  @override
  Future<PosFloorSnapshot> loadFloorSnapshot() async =>
      PosFloorSnapshot(tables: rows, floorElements: const []);
}

class _Launcher extends StatelessWidget {
  const _Launcher();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        key: const Key('open-picker'),
        onPressed: () => TablePickerSheet.show(context),
        child: const SizedBox.shrink(),
      ),
    ),
  );
}

class _StubTransport implements SyncRpcTransport {
  _StubTransport(this.result);
  final Object? result;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    expect(function, 'pos_tables');
    return result;
  }
}
