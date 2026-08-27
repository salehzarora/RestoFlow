import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/tables/table_models.dart';
import 'package:restoflow_dashboard/src/tables/tables_repository.dart';
import 'package:restoflow_dashboard/src/tables/tables_screen.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart'
    show RestoflowFloorFixture, RestoflowTableShapePainter;
import 'package:restoflow_domain/restoflow_domain.dart'
    show TableVisualMaterial, kFloorElementStyleRegistry;
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// TABLE-VISUAL-CONFIGURATION-120C — the OWNER-facing configuration UX:
/// material swatch cards in the table dialog (live shared-renderer preview,
/// Auto = null), a per-kind fixture Style picker in the floor editor, both
/// persisting ONLY through the dedicated 120A writers with honest failures,
/// localized ar/he/en, and zero geometry side effects.
class _RecordingStore extends InMemoryTablesStore {
  final materialCalls = <(String, TableVisualMaterial?)>[];
  final presetCalls = <String>[];
  final styleCalls = <(String, String?)>[];
  bool failMaterial = false;
  bool failPreset = false;
  bool failStyle = false;
  int loads = 0;

  @override
  Future<AdminResult<void>> setTableVisualPreset(
    String tableId,
    covariant preset,
  ) async {
    presetCalls.add(tableId);
    if (failPreset) return const Failure(AdminTransient());
    return super.setTableVisualPreset(tableId, preset);
  }

  @override
  Future<AdminResult<TablesFloorSnapshot>> load() {
    loads++;
    return super.load();
  }

  @override
  Future<AdminResult<void>> setTableVisualMaterial(
    String tableId,
    TableVisualMaterial? material,
  ) async {
    materialCalls.add((tableId, material));
    if (failMaterial) return const Failure(AdminTransient());
    return super.setTableVisualMaterial(tableId, material);
  }

  @override
  Future<AdminResult<void>> setFloorElementStyle(
    String elementId,
    String? style,
  ) async {
    styleCalls.add((elementId, style));
    if (failStyle) return const Failure(AdminTransient());
    return super.setFloorElementStyle(elementId, style);
  }
}

Future<void> _pump(
  WidgetTester tester,
  TablesAdminRepository repo, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1400, 4600);
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

Finder _materialCard(String key) =>
    find.byKey(Key('table-visual-material-$key'));

Future<void> _openFirstTableDialog(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const Key('table-edit-demo-table-1')).hitTestable(),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectMaterialCard(WidgetTester tester, String wire) async {
  await tester.scrollUntilVisible(
    _materialCard(wire),
    80,
    scrollable: find.descendant(
      of: find.byKey(const Key('table-visual-material-row')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.ensureVisible(_materialCard(wire));
  await tester.pumpAndSettle();
  await tester.tap(_materialCard(wire));
  await tester.pumpAndSettle();
}

RestoflowTableShapePainter _previewPainter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byKey(const Key('table-visual-preset-preview')),
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is CustomPaint &&
                      w.painter is RestoflowTableShapePainter,
                ),
              ),
            )
            .painter!
        as RestoflowTableShapePainter;

void main() {
  group('A. table material selector', () {
    testWidgets('all seven choices render; Auto is selected for a table '
        'without a material; picking updates the LIVE preview', (tester) async {
      final store = _RecordingStore();
      await _pump(tester, store);
      await _openFirstTableDialog(tester);
      for (final wire in [
        'auto',
        'wood',
        'dark_wood',
        'light_wood',
        'rustic_wood',
        'plastic',
        'neutral_modern',
      ]) {
        await tester.scrollUntilVisible(
          _materialCard(wire),
          80,
          scrollable: find.descendant(
            of: find.byKey(const Key('table-visual-material-row')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(_materialCard(wire), findsOneWidget, reason: wire);
      }
      // The demo table has no persisted material: Auto preview = the 119D
      // deterministic mapping for its preset + section floor.
      final auto = _previewPainter(tester).material;
      expect(auto, isNotNull);
      // Pick Rustic Wood: the MAIN preview updates live.
      await tester.scrollUntilVisible(
        _materialCard('rustic_wood'),
        -80,
        scrollable: find.descendant(
          of: find.byKey(const Key('table-visual-material-row')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(_materialCard('rustic_wood'));
      await tester.pumpAndSettle();
      expect(_previewPainter(tester).material, TableVisualMaterial.rusticWood);
    });

    testWidgets('localized labels resolve (no raw wire keys shown)', (
      tester,
    ) async {
      final store = _RecordingStore();
      await _pump(tester, store);
      await _openFirstTableDialog(tester);
      expect(find.text('rustic_wood'), findsNothing);
      expect(find.text('neutral_modern'), findsNothing);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.tablesVisualMaterialRusticWood), findsOneWidget);
      expect(find.text(l10n.tablesVisualAuto), findsOneWidget);
      final ar = await AppLocalizations.delegate.load(const Locale('ar'));
      final he = await AppLocalizations.delegate.load(const Locale('he'));
      expect(ar.tablesVisualMaterialRusticWood, isNot(''));
      expect(he.tablesVisualMaterialRusticWood, isNot(''));
      expect(
        ar.tablesVisualMaterialRusticWood,
        isNot(l10n.tablesVisualMaterialRusticWood),
      );
    });
  });

  group('B. table save flow', () {
    testWidgets('unchanged material => NO setter call; explicit change => '
        'exactly one dedicated call with the enum', (tester) async {
      final store = _RecordingStore();
      await _pump(tester, store);
      await _openFirstTableDialog(tester);
      // Save untouched: no material call.
      await tester.tap(find.byKey(const Key('table-dialog-save')));
      await tester.pumpAndSettle();
      expect(store.materialCalls, isEmpty);
      // Re-open, pick Dark Wood, save: exactly one dedicated call.
      await _openFirstTableDialog(tester);
      await tester.scrollUntilVisible(
        _materialCard('dark_wood'),
        80,
        scrollable: find.descendant(
          of: find.byKey(const Key('table-visual-material-row')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(_materialCard('dark_wood'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('table-dialog-save')));
      await tester.pumpAndSettle();
      expect(store.materialCalls, [
        ('demo-table-1', TableVisualMaterial.darkWood),
      ]);
      // Geometry untouched by the material edit.
      final snapshot = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      final t = snapshot.tables.firstWhere((t) => t.id == 'demo-table-1');
      expect(t.visualMaterial, TableVisualMaterial.darkWood);
      // Geometry/placement identity untouched by the material edit.
      expect(t.sectionId, isNot('mutated'));
    });

    testWidgets('explicit -> Auto persists NULL through the setter', (
      tester,
    ) async {
      final store = _RecordingStore();
      await store.setTableVisualMaterial(
        'demo-table-1',
        TableVisualMaterial.plastic,
      );
      store.materialCalls.clear();
      await _pump(tester, store);
      await _openFirstTableDialog(tester);
      await tester.scrollUntilVisible(
        _materialCard('auto'),
        -80,
        scrollable: find.descendant(
          of: find.byKey(const Key('table-visual-material-row')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(_materialCard('auto'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('table-dialog-save')));
      await tester.pumpAndSettle();
      expect(store.materialCalls, [('demo-table-1', null)]);
    });

    testWidgets('a failed material write reloads and surfaces the honest '
        'error', (tester) async {
      final store = _RecordingStore()..failMaterial = true;
      await _pump(tester, store);
      final loadsBefore = store.loads;
      await _openFirstTableDialog(tester);
      await tester.scrollUntilVisible(
        _materialCard('wood'),
        80,
        scrollable: find.descendant(
          of: find.byKey(const Key('table-visual-material-row')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(_materialCard('wood'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('table-dialog-save')));
      await tester.pumpAndSettle();
      expect(store.materialCalls, hasLength(1));
      expect(store.loads, greaterThan(loadsBefore), reason: 'honest reload');
    });
  });

  group('C+D. fixture style picker + save', () {
    Future<void> openStyle(WidgetTester tester, _RecordingStore store) async {
      // Arrange mode -> elements submode -> long-press menu of the demo
      // element is heavy; the picker is driven through the editor's element
      // menu. The demo store seeds elements; use the first one.
      final snapshot = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      final element = snapshot.floorElements.first;
      await tester.tap(find.byKey(Key('floor-element-drag-${element.id}')));
      await tester.pumpAndSettle();
    }

    testWidgets('the picker lists ONLY the kind\'s variants + Auto, with real '
        'fixture previews; saving calls the dedicated setter', (tester) async {
      final store = _RecordingStore();
      await _pump(tester, store);
      final snapshot = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      final element = snapshot.floorElements.first;
      // Enter arrange -> elements submode.
      await tester.tap(find.byKey(const Key('tables-arrange-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('floor-submode-elements')));
      await tester.pumpAndSettle();
      await openStyle(tester, store);
      await tester.tap(find.byKey(const Key('floor-element-style')));
      await tester.pumpAndSettle();
      final styles = kFloorElementStyleRegistry[element.kind]!;
      expect(find.byKey(const Key('floor-element-style-auto')), findsOneWidget);
      for (final s in styles) {
        expect(
          find.byKey(Key('floor-element-style-$s')),
          findsOneWidget,
          reason: s,
        );
      }
      // Cross-kind options never appear.
      final foreign = kFloorElementStyleRegistry.entries
          .where((e) => e.key != element.kind)
          .expand((e) => e.value)
          .toSet()
          .difference(styles.toSet());
      for (final s in foreign) {
        expect(find.byKey(Key('floor-element-style-$s')), findsNothing);
      }
      // Real previews: the option cards mount actual fixtures of this kind.
      expect(
        find.descendant(
          of: find.byKey(Key('floor-element-style-${styles.first}')),
          matching: find.byWidgetPredicate(
            (w) => w is RestoflowFloorFixture && w.kind == element.kind,
          ),
        ),
        findsOneWidget,
      );
      // Pick the first style: exactly one dedicated call.
      await tester.tap(find.byKey(Key('floor-element-style-${styles.first}')));
      await tester.pumpAndSettle();
      expect(store.styleCalls, [(element.id, styles.first)]);
      // Geometry/orientation untouched.
      final after = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      final e2 = after.floorElements.firstWhere((e) => e.id == element.id);
      expect(e2.layoutX, element.layoutX);
      expect(e2.orientationQuarterTurns, element.orientationQuarterTurns);
      expect(e2.visualStyle, styles.first);
    });

    testWidgets('Auto persists NULL; unchanged selection makes no call', (
      tester,
    ) async {
      final store = _RecordingStore();
      final snapshot = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      final element = snapshot.floorElements.first;
      await store.setFloorElementStyle(
        element.id,
        kFloorElementStyleRegistry[element.kind]!.first,
      );
      store.styleCalls.clear();
      await _pump(tester, store);
      await tester.tap(find.byKey(const Key('tables-arrange-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('floor-submode-elements')));
      await tester.pumpAndSettle();
      await openStyle(tester, store);
      await tester.tap(find.byKey(const Key('floor-element-style')));
      await tester.pumpAndSettle();
      // Tapping the CURRENT style is a no-op (no setter call).
      await tester.tap(
        find.byKey(
          Key(
            'floor-element-style-${kFloorElementStyleRegistry[element.kind]!.first}',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.styleCalls, isEmpty);
      // Re-open and clear to Auto: NULL rides the setter.
      await openStyle(tester, store);
      await tester.tap(find.byKey(const Key('floor-element-style')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('floor-element-style-auto')));
      await tester.pumpAndSettle();
      expect(store.styleCalls, [(element.id, null)]);
    });
  });

  group('E. LOW follow-up: the dialog main preview carries the EDITED '
      'material', () {
    testWidgets('picking plastic drives the main preview painter', (
      tester,
    ) async {
      final store = _RecordingStore();
      await _pump(tester, store);
      await _openFirstTableDialog(tester);
      await tester.scrollUntilVisible(
        _materialCard('plastic'),
        80,
        scrollable: find.descendant(
          of: find.byKey(const Key('table-visual-material-row')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(_materialCard('plastic'));
      await tester.pumpAndSettle();
      expect(_previewPainter(tester).material, TableVisualMaterial.plastic);
    });
  });

  group('B2. combined shape+material save (the 120C chain)', () {
    Future<void> pickRound(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('table-visual-preset-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Round table').last);
      await tester.pumpAndSettle();
    }

    testWidgets('both changed => both dedicated setters fire once and the '
        'owner sees exactly ONE confirmation', (tester) async {
      final store = _RecordingStore();
      await _pump(tester, store);
      await _openFirstTableDialog(tester);
      await pickRound(tester);
      await _selectMaterialCard(tester, 'rustic_wood');
      expect(
        _previewPainter(tester).material,
        TableVisualMaterial.rusticWood,
        reason: 'the selection must stick before saving',
      );
      await tester.tap(find.byKey(const Key('table-dialog-save')));
      await tester.pumpAndSettle();
      expect(store.presetCalls, ['demo-table-1']);
      expect(store.materialCalls, [
        ('demo-table-1', TableVisualMaterial.rusticWood),
      ]);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        find.text(l10n.tablesSaved),
        findsOneWidget,
        reason: 'ONE confirmation for one logical save',
      );
    });

    testWidgets('a failed PRESET write stops the chain: the material setter '
        'is never called and no success confirmation shows', (tester) async {
      final store = _RecordingStore()..failPreset = true;
      await _pump(tester, store);
      final loadsBefore = store.loads;
      await _openFirstTableDialog(tester);
      await pickRound(tester);
      await _selectMaterialCard(tester, 'plastic');
      expect(
        _previewPainter(tester).material,
        TableVisualMaterial.plastic,
        reason: 'the selection must stick before saving',
      );
      await tester.tap(find.byKey(const Key('table-dialog-save')));
      await tester.pumpAndSettle();
      expect(store.presetCalls, hasLength(1));
      expect(
        store.materialCalls,
        isEmpty,
        reason: 'the chain stops after the failed preset write',
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        find.text(l10n.tablesSaved),
        findsNothing,
        reason: 'no false success',
      );
      expect(store.loads, greaterThan(loadsBefore), reason: 'honest reload');
    });
  });

  group('D2. fixture style failure + localization guard', () {
    testWidgets('a failed style write reloads honestly', (tester) async {
      final store = _RecordingStore()..failStyle = true;
      await _pump(tester, store);
      final loadsBefore = store.loads;
      final snapshot = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      final element = snapshot.floorElements.first;
      await tester.tap(find.byKey(const Key('tables-arrange-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('floor-submode-elements')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('floor-element-drag-${element.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('floor-element-style')));
      await tester.pumpAndSettle();
      final style = kFloorElementStyleRegistry[element.kind]!.first;
      await tester.tap(find.byKey(Key('floor-element-style-$style')));
      await tester.pumpAndSettle();
      expect(store.styleCalls, hasLength(1));
      expect(store.loads, greaterThan(loadsBefore), reason: 'honest reload');
    });

    testWidgets('the picker shows LOCALIZED names, never raw wire keys', (
      tester,
    ) async {
      final store = _RecordingStore();
      await _pump(tester, store);
      final snapshot = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      final element = snapshot.floorElements.first;
      await tester.tap(find.byKey(const Key('tables-arrange-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('floor-submode-elements')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('floor-element-drag-${element.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('floor-element-style')));
      await tester.pumpAndSettle();
      for (final wire in kFloorElementStyleRegistry[element.kind]!) {
        if (wire.contains('_')) {
          expect(find.text(wire), findsNothing, reason: wire);
        }
      }
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.tablesVisualAuto), findsWidgets);
    });
  });

  group('F. RTL', () {
    testWidgets('the swatch row renders in Arabic without raw keys and the '
        'cards stay tappable', (tester) async {
      final store = _RecordingStore();
      await _pump(tester, store, locale: const Locale('ar'));
      await _openFirstTableDialog(tester);
      expect(
        find.byKey(const Key('table-visual-material-row')),
        findsOneWidget,
      );
      expect(find.text('rustic_wood'), findsNothing);
      await tester.scrollUntilVisible(
        _materialCard('dark_wood'),
        80,
        scrollable: find.descendant(
          of: find.byKey(const Key('table-visual-material-row')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(_materialCard('dark_wood'));
      await tester.pumpAndSettle();
      expect(_previewPainter(tester).material, TableVisualMaterial.darkWood);
    });
  });
}
