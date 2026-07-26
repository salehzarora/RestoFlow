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
    required String restaurantId,
    required String? branchId,
    required MenuEntityType entity,
    required List<String> orderedIds,
  }) async {
    reorderCalls++;
    lastReorderEntity = entity;
    lastReorderIds = orderedIds;
    lastReorderRestaurantId = restaurantId;
    lastReorderBranchId = branchId;
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

MenuItem _item(String id, String categoryId, String name, int order) =>
    MenuItem(
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
  group(
    'MenuReorderScope (Codex #5: distinct lists get distinct latch keys)',
    () {
      const itemsOfCatA = MenuReorderScope(
        organizationId: 'o',
        restaurantId: 'r',
        branchId: null,
        entity: MenuEntityType.item,
        parentId: 'cat-A',
      );
      test('an identical scope is equal (one shared latch)', () {
        expect(
          itemsOfCatA,
          const MenuReorderScope(
            organizationId: 'o',
            restaurantId: 'r',
            branchId: null,
            entity: MenuEntityType.item,
            parentId: 'cat-A',
          ),
        );
        expect(
          itemsOfCatA.hashCode,
          const MenuReorderScope(
            organizationId: 'o',
            restaurantId: 'r',
            branchId: null,
            entity: MenuEntityType.item,
            parentId: 'cat-A',
          ).hashCode,
        );
      });
      test(
        'another category\'s items are a DIFFERENT scope (independent latch)',
        () {
          expect(
            itemsOfCatA ==
                const MenuReorderScope(
                  organizationId: 'o',
                  restaurantId: 'r',
                  branchId: null,
                  entity: MenuEntityType.item,
                  parentId: 'cat-B',
                ),
            isFalse,
          );
        },
      );
      test('a different entity kind is a different scope', () {
        expect(
          itemsOfCatA ==
              const MenuReorderScope(
                organizationId: 'o',
                restaurantId: 'r',
                branchId: null,
                entity: MenuEntityType.category,
                parentId: 'cat-A',
              ),
          isFalse,
        );
      });
      test('a different branch is a different scope', () {
        expect(
          itemsOfCatA ==
              const MenuReorderScope(
                organizationId: 'o',
                restaurantId: 'r',
                branchId: 'b2',
                entity: MenuEntityType.item,
                parentId: 'cat-A',
              ),
          isFalse,
        );
      });
    },
  );

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
      await tester.drag(
        find.byIcon(Icons.drag_indicator).first,
        const Offset(0, 160),
      );
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
      final writer = ScriptedMenuWriter(const Failure(MenuServerFailure()));
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
        reason:
            'the failure branch invalidated -> the snapshot reloaded (rollback)',
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
        reason:
            'selection stayed on Cat A (did not jump to the new first category)',
      );
    },
  );

  testWidgets(
    'MENU-ORDER-001: the category edit dialog has NO display-order field and an '
    'edit PRESERVES the current display_order',
    (tester) async {
      final store = InMemoryMenuStore(categories: [_cat('c-7', 'Sevens', 7)]);
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

      final saved = (await store.load(
        demoMenuScope,
      )).visibleCategories().firstWhere((c) => c.id == 'c-7');
      expect(saved.name, 'Renamed');
      expect(
        saved.displayOrder,
        7,
        reason:
            'a details-save (client sends NULL) preserved display_order — the '
            'demo store keeps the existing value; the real DB guard trigger does '
            'the same server-side (Codex #6)',
      );
    },
  );

  testWidgets(
    'MENU-ORDER-001 (Codex #4): disposing the menu MID-REORDER throws no '
    'exception and never leaks the scope latch (a later reorder still works)',
    (tester) async {
      final gated = _GatedMenuWriter()..gate();
      await _pump(tester, readSource: buildDemoMenuStore(), writer: gated);

      // Start a gated reorder — now in flight (latch held on the container).
      await tester.drag(
        find.byIcon(Icons.drag_indicator).first,
        const Offset(0, 160),
      );
      await tester.pump();
      expect(gated.reorderCalls, 1);

      // Navigate AWAY mid-flight: the whole menu ProviderScope is torn down.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // Complete the RPC AFTER disposal. The controller owns the lifecycle on the
      // provider Ref; its reads/invalidate/release run on the now-disposed
      // container and are swallowed — no WidgetRef-after-await exception, no stuck
      // latch.
      gated.release();
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason:
            'no disposed-container / WidgetRef-after-await exception surfaced',
      );

      // Re-open a FRESH menu (new ProviderScope + container): its scope latch
      // defaults false, so a new reorder executes normally.
      final gated2 = _GatedMenuWriter();
      await _pump(tester, readSource: buildDemoMenuStore(), writer: gated2);
      await tester.drag(
        find.byIcon(Icons.drag_indicator).first,
        const Offset(0, 160),
      );
      await tester.pumpAndSettle();
      expect(
        gated2.reorderCalls,
        1,
        reason: 'the latch did not leak — a later reorder still runs',
      );
    },
  );

  testWidgets(
    'MENU-ORDER-001 (Codex #5): the ADD control is disabled while its scope '
    'reorder is in flight (zero add writes), re-enabled after release',
    (tester) async {
      final store = buildDemoMenuStore();
      final l10n = await _pump(tester, readSource: store, writer: store);

      FilledButton addButton() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, l10n.menuAddCategory),
      );
      // The "Add category" toolbar control (OUTSIDE the category list's
      // IgnorePointer) is enabled before any reorder.
      expect(addButton().onPressed, isNotNull);

      // Hold the CATEGORY sibling scope latch, exactly as a persisting reorder
      // does (reorderScoped sets this synchronously before its RPC).
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MenuManagementScreen)),
      );
      final categoryScope = MenuReorderScope(
        organizationId: demoMenuScope.organizationId,
        restaurantId: demoMenuScope.restaurantId,
        branchId: demoMenuScope.branchId,
        entity: MenuEntityType.category,
        parentId: demoMenuScope.restaurantId,
      );
      container
              .read(menuReorderInFlightProvider(categoryScope).notifier)
              .state =
          true;
      await tester.pump();

      // Add is now DISABLED (onPressed null) — a new category cannot race the
      // 1..N rewrite. A disabled button fires no callback, so zero write calls.
      expect(addButton().onPressed, isNull);

      // After the reorder completes + the latch releases, Add is re-enabled.
      container
              .read(menuReorderInFlightProvider(categoryScope).notifier)
              .state =
          false;
      await tester.pump();
      expect(addButton().onPressed, isNotNull);
    },
  );

  testWidgets(
    'MENU-ORDER-001 (Codex 4th pass): a category edit dialog left OPEN when a '
    'reorder starts issues ZERO writes on Save — the CONTROLLER guard, not just '
    'the list IgnorePointer, refuses it (the exact overlay bypass)',
    (tester) async {
      final store = InMemoryMenuStore(categories: [_cat('c-7', 'Sevens', 7)]);
      // A writer that would "succeed" if reached — so a non-zero lastOperation
      // proves the guard leaked.
      final writer = ScriptedMenuWriter(
        const Success(
          MenuWriteResult(
            entity: MenuEntityType.category,
            id: 'c-7',
            action: MenuWriteAction.updated,
          ),
        ),
      );
      final l10n = await _pump(tester, readSource: store, writer: writer);

      // Open the edit dialog — a ROOT-navigator overlay ABOVE the list's
      // IgnorePointer (the documented bypass) — and stage a rename.
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.menuEditAction).last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('menu-category-name')),
        'Renamed',
      );

      // A category reorder STARTS while the dialog is open (latch held).
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MenuManagementScreen)),
      );
      final categoryScope = MenuReorderScope(
        organizationId: demoMenuScope.organizationId,
        restaurantId: demoMenuScope.restaurantId,
        branchId: demoMenuScope.branchId,
        entity: MenuEntityType.category,
        parentId: demoMenuScope.restaurantId,
      );
      container
              .read(menuReorderInFlightProvider(categoryScope).notifier)
              .state =
          true;
      await tester.pump();

      // Tapping Save now routes through the controller guard -> refused.
      await tester.tap(find.text(l10n.menuSaveAction));
      await tester.pumpAndSettle();
      expect(
        writer.lastOperation,
        isNull,
        reason:
            'the open dialog Save reached the controller guard and was '
            'refused — no upsertCategory hit the writer',
      );
      // The category still carries its original name (nothing persisted).
      expect(
        (await store.load(demoMenuScope)).visibleCategories().single.name,
        'Sevens',
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
