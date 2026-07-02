import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Regression for the real-mode "Add category hangs forever" bug.
///
/// The dashboard wires the menu providers in a NESTED ProviderScope (per
/// surface), while `showDialog` builds its child under the ROOT navigator —
/// ABOVE that scope. The Consumer form dialogs then resolved against the ROOT
/// container, whose menu providers throw `UnimplementedError`, the save future
/// failed uncaught, and `_submitting` stayed true forever. These tests pump
/// the SAME nesting the dashboard uses (root scope WITHOUT overrides) — they
/// hang/fail without the container bridge in menu_entity_forms.dart.

const _scope = MenuScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  currencyCode: 'ILS',
);

/// A writer that always THROWS (a wiring/programming error, not a Failure) —
/// the save must still surface a visible safe error and re-enable Save.
class _ThrowingWriter extends InMemoryMenuStore {
  @override
  Future<MenuWriteOutcome> upsertCategory({
    required MenuScope scope,
    String? id,
    required String name,
    int displayOrder = 0,
    bool isActive = true,
  }) async {
    throw StateError('secret-internal-detail: writer exploded');
  }
}

Future<AppLocalizations> en() =>
    AppLocalizations.delegate.load(const Locale('en'));

/// The dashboard arrangement: ROOT scope with NO menu overrides; the overrides
/// live in a nested scope INSIDE the MaterialApp, below the root navigator.
Future<void> _pumpNested(
  WidgetTester tester, {
  required MenuReadSource readSource,
  required MenuWriter writer,
}) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        // Mirrors the dashboard: the Scaffold sits ABOVE the nested scope.
        home: Scaffold(
          body: ProviderScope(
            overrides: menuFeatureOverrides(
              scope: _scope,
              readSource: readSource,
              writer: writer,
            ),
            child: const MenuManagementScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openAddCategory(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  await tester.tap(find.text(l10n.menuAddCategory).first);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('menu-category-name')),
    'drinks',
  );
}

void main() {
  testWidgets('Add category from a NESTED provider scope saves, closes the '
      'dialog, and renders the new category', (tester) async {
    final l10n = await en();
    final store = InMemoryMenuStore();
    await _pumpNested(tester, readSource: store, writer: store);
    expect(find.text(l10n.menuEmptyCategories), findsOneWidget);

    await _openAddCategory(tester, l10n);
    await tester.tap(find.text(l10n.menuSaveAction));
    await tester.pumpAndSettle();

    // Dialog closed, category rendered, list refreshed.
    expect(find.byKey(const ValueKey('menu-category-name')), findsNothing);
    expect(find.text('drinks'), findsOneWidget);
    expect(find.text(l10n.menuEmptyCategories), findsNothing);

    // The REAL nested scope (org/restaurant/branch) reached the writer —
    // never a demo/root fallback scope.
    final saved = (await store.load(_scope)).categories.single;
    expect(saved.organizationId, 'org-1');
    expect(saved.restaurantId, 'rest-1');
    expect(saved.branchId, 'branch-1');
    expect(saved.name, 'drinks');
  });

  testWidgets('a THROWING writer shows the safe error in the dialog and '
      're-enables Save (never stuck, never a raw error dump)', (tester) async {
    final l10n = await en();
    await _pumpNested(
      tester,
      readSource: InMemoryMenuStore(),
      writer: _ThrowingWriter(),
    );

    await _openAddCategory(tester, l10n);
    await tester.tap(find.text(l10n.menuSaveAction));
    await tester.pumpAndSettle();

    // Still open, with the GENERIC safe message — no raw internals.
    expect(find.byKey(const ValueKey('menu-category-name')), findsOneWidget);
    expect(find.text(l10n.menuWriteProblem), findsOneWidget);
    expect(find.textContaining('secret-internal-detail'), findsNothing);

    // Save is re-enabled (submitting cleared) and Cancel still works.
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l10n.menuSaveAction),
    );
    expect(save.onPressed, isNotNull);
    await tester.tap(find.text(l10n.menuCancelAction));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-category-name')), findsNothing);
  });

  testWidgets('a permission-denied writer shows its dedicated message and '
      'keeps the dialog usable', (tester) async {
    final l10n = await en();
    await _pumpNested(
      tester,
      readSource: InMemoryMenuStore(),
      writer: InMemoryMenuStore(readOnly: true),
    );

    await _openAddCategory(tester, l10n);
    await tester.tap(find.text(l10n.menuSaveAction));
    await tester.pumpAndSettle();

    expect(find.text(l10n.menuWritePermissionDenied), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l10n.menuSaveAction),
    );
    expect(save.onPressed, isNotNull);
  });
}
