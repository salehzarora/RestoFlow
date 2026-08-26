import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_dashboard/src/tables/table_models.dart';
import 'package:restoflow_dashboard/src/tables/tables_repository.dart';
import 'package:restoflow_dashboard/src/tables/tables_screen.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show TableVisualPreset;
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminResult, AdminScope, AdminTransient;
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// TABLE-118B — the table dialog binds the chosen visual preset to the
/// AUTHORITATIVE table id returned by `upsert_table` (server-minted on
/// create, echoed on update). No snapshot diff, no label-based candidate
/// search: a concurrently created table can never receive another owner's
/// preset, and a failed preset write reloads the authoritative list before
/// the honest error is shown (the just-created table is never left hidden).
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

/// The demo store with the WIRE-SHAPED behaviours the real backend has:
/// `upsertTable` returns an id the client did NOT choose, `load()` may carry
/// tables created by someone else, and the preset setter may fail.
class _Store extends InMemoryTablesStore {
  _Store({this.mintedId, this.presetFailure = false, this.intruder});

  /// The id the "server" reports for a CREATE (null = the store's own id).
  final String? mintedId;

  /// Whether `setTableVisualPreset` fails (after a successful upsert).
  final bool presetFailure;

  /// A table another admin created concurrently — injected into every
  /// `load()` result, with the SAME label the owner is about to use.
  final DashboardTable? intruder;

  final presetWrites = <(String, TableVisualPreset)>[];
  int loads = 0;
  int upserts = 0;

  @override
  Future<AdminResult<TablesFloorSnapshot>> load() async {
    loads++;
    final base = await super.load();
    final extra = intruder;
    if (extra == null) return base;
    return base.fold(
      (s) => Success(
        TablesFloorSnapshot(
          tables: [...s.tables, extra],
          sections: s.sections,
          floorElements: s.floorElements,
        ),
      ),
      (f) => Failure(f),
    );
  }

  @override
  Future<AdminResult<String>> upsertTable({
    String? id,
    required String label,
    int? seats,
    String? area,
    required bool isActive,
  }) async {
    upserts++;
    final result = await super.upsertTable(
      id: id,
      label: label,
      seats: seats,
      area: area,
      isActive: isActive,
    );
    if (id == null && mintedId != null) {
      return result.fold((_) => Success(mintedId!), (f) => Failure(f));
    }
    return result;
  }

  @override
  Future<AdminResult<void>> setTableVisualPreset(
    String tableId,
    TableVisualPreset preset,
  ) async {
    presetWrites.add((tableId, preset));
    if (presetFailure) return const Failure(AdminTransient());
    // The store may not know a server-minted id; the WRITE is what we pin.
    final result = await super.setTableVisualPreset(tableId, preset);
    return result.fold((_) => const Success(null), (_) => const Success(null));
  }
}

Future<void> _pump(WidgetTester tester, TablesAdminRepository repo) async {
  tester.view.physicalSize = const Size(1400, 4600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(body: TablesScreen(repository: repo)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _createTable(
  WidgetTester tester, {
  required String label,
  String? presetLabel,
}) async {
  await tester.tap(find.text('Add table'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Table name / number'),
    label,
  );
  if (presetLabel != null) {
    await tester.tap(find.byKey(const Key('table-visual-preset-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(presetLabel).last);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const Key('table-dialog-save')));
  await tester.pumpAndSettle();
}

const _intruder = DashboardTable(
  id: 'someone-elses-T9',
  label: 'T9',
  status: DiningTableStatus.available,
  isActive: true,
  branchId: 'demo-branch',
);

void main() {
  group('repository: upsertTable returns the authoritative id', () {
    test('a CREATE returns the server-minted id', () async {
      final t = _FakeTransport(
        (fn, p) => {'ok': true, 'id': 'srv-minted-42', 'action': 'created'},
      );
      final repo = SupabaseTablesRepository(
        transport: t,
        scope: AdminScope.demo,
        currentUserId: () => 'u',
      );
      final result = await repo.upsertTable(
        label: 'T9',
        seats: 4,
        area: null,
        isActive: true,
      );
      expect(result.fold((id) => id, (_) => null), 'srv-minted-42');
    });

    test('an UPDATE returns the echoed id (falls back to the passed id when '
        'an older backend omits it)', () async {
      final t = _FakeTransport((fn, p) => {'ok': true, 'action': 'updated'});
      final repo = SupabaseTablesRepository(
        transport: t,
        scope: AdminScope.demo,
        currentUserId: () => 'u',
      );
      final result = await repo.upsertTable(
        id: 't-1',
        label: 'T1',
        seats: 2,
        area: null,
        isActive: true,
      );
      expect(result.fold((id) => id, (_) => null), 't-1');
    });

    test('a CREATE without an id in the envelope fails closed (never a '
        'guessed id)', () async {
      final t = _FakeTransport((fn, p) => {'ok': true, 'action': 'created'});
      final repo = SupabaseTablesRepository(
        transport: t,
        scope: AdminScope.demo,
        currentUserId: () => 'u',
      );
      final result = await repo.upsertTable(
        label: 'T9',
        seats: null,
        area: null,
        isActive: true,
      );
      expect(result.isSuccess, isFalse);
    });

    test('the demo store returns its own minted id', () async {
      final store = InMemoryTablesStore();
      final result = await store.upsertTable(
        label: 'T9',
        seats: null,
        area: null,
        isActive: true,
      );
      final id = result.fold((id) => id, (_) => null);
      expect(id, isNotNull);
      final saved = (await store.load()).fold((s) => s, (_) => null)!;
      expect(saved.tables.any((t) => t.id == id && t.label == 'T9'), isTrue);
    });
  });

  group('dialog save binds the preset to the returned id', () {
    testWidgets('A. new table + non-default preset: the EXACT returned id is '
        'written, with no discovery load', (tester) async {
      final store = _Store(mintedId: 'srv-minted-42');
      await _pump(tester, store);
      final loadsBefore = store.loads;
      await _createTable(tester, label: 'T9', presetLabel: 'Round table');
      expect(store.upserts, 1);
      expect(store.presetWrites, [
        ('srv-minted-42', TableVisualPreset.roundTable),
      ]);
      // Exactly ONE load: the post-save refresh. No before/after diff loads.
      expect(store.loads - loadsBefore, 1);
      expect(find.text('Table saved'), findsOneWidget);
    });

    testWidgets('B. a concurrently created table with the SAME label cannot '
        'steal or block the preset', (tester) async {
      final store = _Store(mintedId: 'srv-minted-42', intruder: _intruder);
      await _pump(tester, store);
      await _createTable(tester, label: 'T9', presetLabel: 'Booth');
      expect(store.presetWrites, [
        ('srv-minted-42', TableVisualPreset.boothTable),
      ]);
      expect(
        store.presetWrites.any((w) => w.$1 == 'someone-elses-T9'),
        isFalse,
      );
    });

    testWidgets('C. preset write fails after a successful create: the list is '
        'reloaded, the new table is visible, the error is honest', (
      tester,
    ) async {
      final store = _Store(presetFailure: true);
      await _pump(tester, store);
      final loadsBefore = store.loads;
      await _createTable(tester, label: 'T9', presetLabel: 'Round table');
      expect(store.presetWrites, hasLength(1));
      // Reloaded exactly once after the failure.
      expect(store.loads - loadsBefore, 1);
      // Honest failure copy, never the success snackbar.
      expect(find.text('Table saved'), findsNothing);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(TablesScreen)),
      );
      expect(find.text(l10n.adminActionProblem), findsOneWidget);
      // The created table is on screen (card + floor strip tile).
      expect(find.text('T9'), findsWidgets);
    });

    testWidgets('D. editing an existing table uses its authoritative id '
        'directly', (tester) async {
      final store = _Store();
      await _pump(tester, store);
      await tester.tap(find.byKey(const Key('table-edit-demo-table-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('table-visual-preset-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Table with barrels').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('table-dialog-save')));
      await tester.pumpAndSettle();
      expect(store.upserts, 1);
      expect(store.presetWrites, [
        ('demo-table-1', TableVisualPreset.tableWithBarrels),
      ]);
      expect(find.text('Table saved'), findsOneWidget);
    });

    testWidgets('E. the default preset needs no setter call (create and '
        'unchanged edit)', (tester) async {
      final store = _Store(mintedId: 'srv-minted-42');
      await _pump(tester, store);
      await _createTable(tester, label: 'T9');
      expect(store.upserts, 1);
      expect(store.presetWrites, isEmpty);
      expect(find.text('Table saved'), findsOneWidget);
      // Edit without touching the shape: still no setter call.
      await tester.tap(find.byKey(const Key('table-edit-demo-table-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('table-dialog-save')));
      await tester.pumpAndSettle();
      expect(store.upserts, 2);
      expect(store.presetWrites, isEmpty);
    });
  });
}
