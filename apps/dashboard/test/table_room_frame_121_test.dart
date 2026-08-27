import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/tables/table_models.dart';
import 'package:restoflow_dashboard/src/tables/tables_repository.dart';
import 'package:restoflow_dashboard/src/tables/tables_screen.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show
        FloorPreset,
        TableSectionRoomFramePreset,
        TableVisualMaterial,
        TableVisualPreset,
        floorRoomAspect,
        kFloorStandardAspect;
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminScope;
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// TABLE-ROOM-FRAME-121 — the Dashboard as the control center of the ROOM
/// SIZE/SHAPE: the arrange-mode section header offers the room-frame picker
/// ('standard' + the five presets, each with an aspect-outline card), the
/// choice persists through the DEDICATED setter only (null = Standard
/// clears), and the section's canvas re-projects at the chosen aspect while
/// the OTHER sections keep theirs.
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Object? Function(String fn, Map<String, dynamic> params) _handler;
  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return _handler(function, params);
  }
}

Map<String, dynamic> _listWithFrames() => {
  'ok': true,
  'entity': 'table',
  'tables': [
    {
      'id': 't-1',
      'label': 'T1',
      'status': 'available',
      'branch_id': 'b-1',
      'is_active': true,
    },
  ],
  'sections': [
    {
      'id': 's-1',
      'name': 'Hall',
      'display_order': 0,
      'is_active': true,
      'branch_id': 'b-1',
      'room_frame_preset': 'long_narrow',
    },
    {
      // Legacy row: no key at all => Standard.
      'id': 's-2',
      'name': 'Terrace',
      'display_order': 1,
      'is_active': true,
      'branch_id': 'b-1',
    },
    {
      // A key this client does not know: Standard, never a failure.
      'id': 's-3',
      'name': 'Attic',
      'display_order': 2,
      'is_active': true,
      'branch_id': 'b-1',
      'room_frame_preset': 'dodecagon',
    },
  ],
};

double _canvasAspect(WidgetTester tester, String sectionId) => tester
    .widget<AspectRatio>(
      find.descendant(
        of: find.byKey(Key('floor-canvas-$sectionId')),
        matching: find.byType(AspectRatio),
      ),
    )
    .aspectRatio;

Future<void> _pump(
  WidgetTester tester,
  TablesAdminRepository repo, {
  Locale? locale,
  Size size = const Size(1400, 4600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(body: TablesScreen(repository: repo)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('model + wire decode', () {
    test(
      'a section without the key is Standard; copies carry and clear it',
      () {
        const section = DashboardTableSection(
          id: 's',
          name: 'S',
          displayOrder: 0,
          isActive: true,
          branchId: 'b',
        );
        expect(section.roomFramePreset, isNull);
        final wide = section.copyWith(
          roomFramePreset: TableSectionRoomFramePreset.wide,
        );
        expect(wide.roomFramePreset, TableSectionRoomFramePreset.wide);
        // An unrelated copy keeps the frame (the re-wrap trap).
        expect(
          wide.copyWith(name: 'S2').roomFramePreset,
          TableSectionRoomFramePreset.wide,
        );
        expect(
          wide.copyWith(clearRoomFramePreset: true).roomFramePreset,
          isNull,
        );
      },
    );

    test('load decodes room_frame_preset tolerantly', () async {
      final t = _FakeTransport((fn, p) => _listWithFrames());
      final repo = SupabaseTablesRepository(
        transport: t,
        scope: AdminScope.demo,
        currentUserId: () => 'u',
      );
      final snapshot = (await repo.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      final sections = {for (final s in snapshot.sections) s.id: s};
      expect(
        sections['s-1']!.roomFramePreset,
        TableSectionRoomFramePreset.longNarrow,
      );
      expect(sections['s-2']!.roomFramePreset, isNull);
      expect(sections['s-3']!.roomFramePreset, isNull);
    });

    test(
      'the setter calls the DEDICATED RPC (null clears to Standard)',
      () async {
        final t = _FakeTransport(
          (fn, p) => {'ok': true, 'idempotent_replay': false},
        );
        final repo = SupabaseTablesRepository(
          transport: t,
          scope: AdminScope.demo,
          currentUserId: () => 'u',
        );
        final a = await repo.setSectionRoomFramePreset(
          's-1',
          TableSectionRoomFramePreset.portrait,
        );
        final b = await repo.setSectionRoomFramePreset('s-1', null);
        expect(a.fold((_) => true, (_) => false), isTrue);
        expect(b.fold((_) => true, (_) => false), isTrue);
        expect(t.calls.map((c) => c.$1).toList(), [
          'set_table_section_room_frame_preset',
          'set_table_section_room_frame_preset',
        ]);
        expect(t.calls[0].$2['p_section_id'], 's-1');
        expect(t.calls[0].$2['p_room_frame_preset'], 'portrait');
        expect(t.calls[0].$2['p_client_request_id'], isA<String>());
        expect(t.calls[1].$2['p_room_frame_preset'], isNull);
        // Never through the full-replace upserts.
        expect(t.calls.any((c) => c.$1.startsWith('upsert_')), isFalse);
      },
    );

    test('the in-memory demo store persists and clears the frame', () async {
      final store = InMemoryTablesStore();
      await store.setSectionRoomFramePreset(
        'demo-section-1',
        TableSectionRoomFramePreset.square,
      );
      var saved = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      expect(
        saved.sections
            .firstWhere((s) => s.id == 'demo-section-1')
            .roomFramePreset,
        TableSectionRoomFramePreset.square,
      );
      await store.setSectionRoomFramePreset('demo-section-1', null);
      saved = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      expect(
        saved.sections
            .firstWhere((s) => s.id == 'demo-section-1')
            .roomFramePreset,
        isNull,
      );
    });
  });

  group('TablesScreen room-frame picker', () {
    testWidgets('picks a frame in arrange mode: the DEDICATED setter persists '
        'it and ONLY that section re-projects', (tester) async {
      final store = InMemoryTablesStore();
      await _pump(tester, store);
      // Outside arrange mode there is no picker.
      expect(
        find.byKey(const Key('section-room-frame-demo-section-1')),
        findsNothing,
      );
      expect(_canvasAspect(tester, 'demo-section-1'), kFloorStandardAspect);
      await tester.tap(find.byKey(const Key('tables-arrange-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('section-room-frame-demo-section-1')),
      );
      await tester.pumpAndSettle();
      // All six choices are offered (standard + the five presets).
      for (final wire in const [
        'standard',
        'compact',
        'square',
        'wide',
        'portrait',
        'long_narrow',
      ]) {
        expect(
          find.byKey(Key('room-frame-$wire-demo-section-1')),
          findsOneWidget,
        );
      }
      await tester.tap(
        find.byKey(const Key('room-frame-square-demo-section-1')),
      );
      await tester.pumpAndSettle();
      expect(_canvasAspect(tester, 'demo-section-1'), 1.0);
      // The OTHER section keeps the Standard projection.
      expect(_canvasAspect(tester, 'demo-section-2'), kFloorStandardAspect);
      final saved = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      expect(
        saved.sections
            .firstWhere((s) => s.id == 'demo-section-1')
            .roomFramePreset,
        TableSectionRoomFramePreset.square,
      );
    });

    testWidgets('Standard clears back to null and the legacy projection', (
      tester,
    ) async {
      final store = InMemoryTablesStore();
      await store.setSectionRoomFramePreset(
        'demo-section-1',
        TableSectionRoomFramePreset.wide,
      );
      await _pump(tester, store);
      expect(
        _canvasAspect(tester, 'demo-section-1'),
        floorRoomAspect(TableSectionRoomFramePreset.wide),
      );
      await tester.tap(find.byKey(const Key('tables-arrange-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('section-room-frame-demo-section-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('room-frame-standard-demo-section-1')),
      );
      await tester.pumpAndSettle();
      expect(_canvasAspect(tester, 'demo-section-1'), kFloorStandardAspect);
      final saved = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      expect(
        saved.sections
            .firstWhere((s) => s.id == 'demo-section-1')
            .roomFramePreset,
        isNull,
      );
    });

    testWidgets('RTL (ar): the picker renders localized labels and the room '
        'projection stays PHYSICAL (aspect unchanged)', (tester) async {
      final store = InMemoryTablesStore();
      await store.setSectionRoomFramePreset(
        'demo-section-1',
        TableSectionRoomFramePreset.portrait,
      );
      await _pump(tester, store, locale: const Locale('ar'));
      expect(
        _canvasAspect(tester, 'demo-section-1'),
        floorRoomAspect(TableSectionRoomFramePreset.portrait),
      );
      await tester.tap(find.byKey(const Key('tables-arrange-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('section-room-frame-demo-section-1')),
      );
      await tester.pumpAndSettle();
      // Arabic labels from the l10n bundle (no raw wire keys shown).
      expect(find.text('قياسي'), findsOneWidget);
      expect(find.text('ممر ضيق'), findsOneWidget);
      expect(find.text('long_narrow'), findsNothing);
    });

    testWidgets('phone width (360dp): the header controls wrap instead of '
        'overflowing and the room-frame picker stays reachable', (
      tester,
    ) async {
      // An unhandled RenderFlex overflow fails the test by itself.
      await _pump(tester, InMemoryTablesStore(), size: const Size(360, 5200));
      await tester.tap(find.byKey(const Key('tables-arrange-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('floor-submode-elements')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('section-room-frame-demo-section-1')),
        findsOneWidget,
      );
    });
  });

  group('review fixes: the demo store preserves unrelated fields', () {
    test(
      'rename/toggle and reorder keep the floor preset AND room frame',
      () async {
        final store = InMemoryTablesStore();
        await store.setSectionFloorPreset(
          'demo-section-1',
          FloorPreset.woodDark,
        );
        await store.setSectionRoomFramePreset(
          'demo-section-1',
          TableSectionRoomFramePreset.portrait,
        );
        await store.upsertSection(
          id: 'demo-section-1',
          name: 'Renamed hall',
          isActive: true,
        );
        await store.reorderSections(['demo-section-2', 'demo-section-1']);
        final saved = (await store.load()).fold(
          (s) => s,
          (f) => fail('expected success'),
        );
        final s1 = saved.sections.firstWhere((s) => s.id == 'demo-section-1');
        expect(s1.name, 'Renamed hall');
        expect(s1.displayOrder, 1);
        expect(s1.floorPreset, FloorPreset.woodDark);
        expect(s1.roomFramePreset, TableSectionRoomFramePreset.portrait);
      },
    );

    test('setStatus and upsertTable keep section, placement and the visual '
        'keys', () async {
      final store = InMemoryTablesStore();
      await store.setTableVisualPreset(
        'demo-table-1',
        TableVisualPreset.roundTable,
      );
      await store.setTableVisualMaterial(
        'demo-table-1',
        TableVisualMaterial.rusticWood,
      );
      await store.setStatus('demo-table-1', DiningTableStatus.reserved);
      await store.upsertTable(
        id: 'demo-table-1',
        label: 'T1 renamed',
        seats: 5,
        area: 'Main hall',
        isActive: true,
      );
      final saved = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      final t1 = saved.tables.firstWhere((t) => t.id == 'demo-table-1');
      expect(t1.label, 'T1 renamed');
      expect(t1.status, DiningTableStatus.reserved);
      expect(t1.sectionId, 'demo-section-1');
      expect(t1.layoutX, isNotNull);
      expect(t1.layoutY, isNotNull);
      expect(t1.visualPreset, TableVisualPreset.roundTable);
      expect(t1.visualMaterial, TableVisualMaterial.rusticWood);
    });
  });
}
