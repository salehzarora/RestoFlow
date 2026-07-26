import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_feature_menu/testing.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// MENU-ORDER-001 (Codex correction) — the Dashboard drag-reorder guards:
///   * an in-flight latch so two overlapping drags never issue two writes off a
///     stale base order (#2/#3);
///   * exact rollback (snapshot invalidation) + a visible error on failure (#3);
///   * selection stability — a category reorder never drifts the items panel to
///     a different category (#3);
///   * the numeric display-order field is gone for drag-reorderable entities and
///     an edit PRESERVES the entity's current display_order (#4/#6).

/// A writer that counts reorder calls and can be gated on a [Completer], so a
/// test can hold a reorder "in flight" while it attempts a second one.
class _GatedMenuWriter extends ScriptedMenuWriter {
  _GatedMenuWriter()
    : super(
        const Success(
          MenuWriteResult(
            entity: MenuEntityType.category,
            id: 'x',
            action: MenuWriteAction.updated,
          ),
        ),
      );

  int reorderCalls = 0;
  Completer<void>? _gate;

  void gate() => _gate = Completer<void>();
  void release() => _gate?.complete();

  @override
  Future<MenuWriteOutcome> reorder({
    required String organizationId,
    required MenuEntityType entity,
    required List<String> orderedIds,
  }) async {
    reorderCalls++;
    lastReorderEntity = entity;
    lastReorderIds = orderedIds;
    final gate = _gate;
    if (gate != null) await gate.future;
    return outcome;
  }
}

MenuCategory _cat(String id, String name, int order) => MenuCategory(
  id: id,
  organizationId: demoMenuScope.organizationId,
  restaurantId: demoMenuScope.restaurantId,
  branchId: null,
  name: name,
  displayOrder: order,
  isActive: true,
);

MenuItem _item(String id, String categoryId, String name, int order) => MenuItem(
  id: id,
  organizationId: demoMenuScope.organizationId,
  restaurantId: demoMenuScope.restaurantId,
  branchId: null,
  menuCategoryId: categoryId,
  name: name,
  description: null,
  basePriceMinor: 500,
  currencyCode: demoMenuScope.currencyCode,
  defaultStationId: null,
  displayOrder: order,
  isActive: true,
);

Future<AppLocalizations> _pump(
  WidgetTester tester, {
  required MenuReadSource readSource,
  required MenuWriter writer,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  late AppLocalizations l10n;
  await tester.pumpWidget(
    ProviderScope(
      overrides: menuFeatureOverrides(
        scope: demoMenuScope,
        readSource: readSource,
        writer: writer,
      ),
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context);
              return const MenuManagementScreen();
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return l10n;
}

void main() {
  testWidgets(
    'MENU-ORDER-001: a second drag while one reorder is in flight is IGNORED '
    '(single write, no stale-base race)',
    (tester) async {
      final read = buildDemoMenuStore();
      final writer = _GatedMenuWriter()..gate();
      await _pump(tester, readSource: read, writer: writer);

      final handle = find.byIcon(Icons.drag_indicator).first;

      // First drag -> the reorder starts and blocks on the gate (latch held).
      await tester.drag(handle, const Offset(0, 160));
      await tester.pump();
      expect(writer.reorderCalls, 1);

      // Second drag WHILE the first is in flight -> the latch swallows it.
      await tester.drag(find.byIcon(Icons.drag_indicator).first, const Offset(0, 160));
      await tester.pump();
      expect(
        writer.reorderCalls,
        1,
        reason: 'the in-flight latch ignored the overlapping second drag',
      );

      // Release the first; the surface refreshes and the latch clears.
      writer.release();
      await tester.pumpAndSettle();
      expect(writer.reorderCalls, 1);
    },
  );

  testWidgets(
    'MENU-ORDER-001: a FAILED reorder shows the write-problem message and '
    'rolls back (reloads the authoritative snapshot)',
    (tester) async {
      // A load-counting read source proves the failure path invalidates.
      final backing = buildDemoMenuStore();
      final read = _CountingReadSource(backing);
      final writer = ScriptedMenuWriter(
        const Failure(MenuServerFailure()),
      );
      final l10n = await _pump(tester, readSource: read, writer: writer);
      final loadsAfterFirstRender = read.loads;

      await tester.drag(
        find.byIcon(Icons.drag_indicator).first,
        const Offset(0, 160),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.menuWriteProblem), findsOneWidget);
      expect(
        read.loads,
        greaterThan(loadsAfterFirstRender),
        reason: 'the failure branch invalidated -> the snapshot reloaded (rollback)',
      );
    },
  );

  testWidgets(
    'MENU-ORDER-001: reordering categories does NOT drift the items panel to a '
    'different category (selection stability)',
    (tester) async {
      final store = InMemoryMenuStore(
        categories: [
          _cat('c-a', 'Cat A', 1),
          _cat('c-b', 'Cat B', 2),
          _cat('c-c', 'Cat C', 3),
        ],
        items: [
          _item('i-alpha', 'c-a', 'Alpha', 1),
          _item('i-beta', 'c-b', 'Beta', 1),
          _item('i-gamma', 'c-c', 'Gamma', 1),
        ],
      );
      await _pump(tester, readSource: store, writer: store);

      // Cat A is the auto-selected first category -> its item shows in the detail.
      expect(find.text('Alpha'), findsWidgets);

      // Drag the first category (A) down so it is no longer at the front.
      await tester.drag(
        find.byIcon(Icons.drag_indicator).first,
        const Offset(0, 220),
      );
      await tester.pumpAndSettle();

      // A is no longer first, but the selection stays PINNED on A -> Alpha still
      // shows (it did NOT jump to whatever category is now at the front).
      expect(
        (await store.load(demoMenuScope)).visibleCategories().first.id,
        isNot('c-a'),
        reason: 'the reorder really moved Cat A away from the front',
      );
      expect(
        find.text('Alpha'),
        findsWidgets,
        reason: 'selection stayed on Cat A (did not jump to the new first category)',
      );
    },
  );

  testWidgets(
    'MENU-ORDER-001: the category edit dialog has NO display-order field and an '
    'edit PRESERVES the current display_order',
    (tester) async {
      final store = InMemoryMenuStore(
        categories: [_cat('c-7', 'Sevens', 7)],
      );
      final l10n = await _pump(tester, readSource: store, writer: store);

      // Open the category's edit dialog via its row menu.
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.menuEditAction).last);
      await tester.pumpAndSettle();

      // The numeric display-order field is gone (drag owns ordering now).
      expect(find.text(l10n.menuDisplayOrderLabel), findsNothing);

      // Rename and save; the display_order must be untouched (still 7, not 0).
      await tester.enterText(
        find.byKey(const ValueKey('menu-category-name')),
        'Renamed',
      );
      await tester.tap(find.text(l10n.menuSaveAction));
      await tester.pumpAndSettle();

      final saved = (await store.load(demoMenuScope))
          .visibleCategories()
          .firstWhere((c) => c.id == 'c-7');
      expect(saved.name, 'Renamed');
      expect(
        saved.displayOrder,
        7,
        reason: 'a details-save preserved the current display_order (no reset)',
      );
    },
  );
}

/// A read source that delegates to [inner] and counts [load] calls, so a test
/// can prove the failure-rollback path re-loaded the authoritative snapshot.
class _CountingReadSource implements MenuReadSource {
  _CountingReadSource(this.inner);
  final MenuReadSource inner;
  int loads = 0;

  @override
  Future<MenuSnapshot> load(MenuScope scope) {
    loads++;
    return inner.load(scope);
  }
}
