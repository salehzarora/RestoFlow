import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_feature_menu/testing.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Opens the modifier form over a [ScriptedMenuWriter] so a test can assert
/// whether the write callback was invoked.
Future<({AppLocalizations l10n, ScriptedMenuWriter writer})> pumpModifierForm(
  WidgetTester tester,
) async {
  final writer = ScriptedMenuWriter(
    const Success(
      MenuWriteResult(
        entity: MenuEntityType.modifier,
        id: 'm1',
        action: MenuWriteAction.created,
      ),
    ),
  );
  late AppLocalizations l10n;
  await tester.pumpWidget(
    ProviderScope(
      overrides: menuFeatureOverrides(
        scope: demoMenuScope,
        readSource: InMemoryMenuStore(),
        writer: writer,
      ),
      child: MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context);
              return Center(
                child: FilledButton(
                  key: const Key('open'),
                  onPressed: () =>
                      showModifierFormDialog(context, menuItemId: 'item-1'),
                  child: const Icon(Icons.add),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
  return (l10n: l10n, writer: writer);
}

void main() {
  testWidgets('negative min_select shows a validation error and does not save', (
    tester,
  ) async {
    final f = await pumpModifierForm(tester);
    await tester.enterText(
      find.byKey(const ValueKey('menu-modifier-name')),
      'Extras',
    );
    await tester.enterText(
      find.byKey(const ValueKey('menu-modifier-min')),
      '-1',
    );
    await tester.tap(find.text(f.l10n.menuSaveAction));
    await tester.pumpAndSettle();

    // The min field shows a localized error; the value is NOT silently clamped.
    expect(find.text(f.l10n.menuErrorNegativePrice), findsOneWidget);
    expect(f.writer.lastOperation, isNull); // write was NOT called
    expect(
      find.byKey(const ValueKey('menu-modifier-name')),
      findsOneWidget,
    ); // dialog stays open
  });

  testWidgets('non-integer min_select shows an error and does not save', (
    tester,
  ) async {
    final f = await pumpModifierForm(tester);
    await tester.enterText(
      find.byKey(const ValueKey('menu-modifier-name')),
      'Extras',
    );
    await tester.enterText(
      find.byKey(const ValueKey('menu-modifier-min')),
      'abc',
    );
    await tester.tap(find.text(f.l10n.menuSaveAction));
    await tester.pumpAndSettle();

    expect(find.text(f.l10n.menuErrorAmount), findsOneWidget);
    expect(f.writer.lastOperation, isNull);
  });

  testWidgets('valid min_select saves (calls the write)', (tester) async {
    final f = await pumpModifierForm(tester);
    await tester.enterText(
      find.byKey(const ValueKey('menu-modifier-name')),
      'Extras',
    );
    await tester.enterText(
      find.byKey(const ValueKey('menu-modifier-min')),
      '2',
    );
    await tester.tap(find.text(f.l10n.menuSaveAction));
    await tester.pumpAndSettle();

    expect(f.writer.lastOperation, 'upsertModifier');
    expect(
      find.byKey(const ValueKey('menu-modifier-name')),
      findsNothing,
    ); // dialog closed
  });

  testWidgets(
    'max_select below min_select shows a validation error and does not save',
    (tester) async {
      final f = await pumpModifierForm(tester);
      await tester.enterText(
        find.byKey(const ValueKey('menu-modifier-name')),
        'Extras',
      );
      await tester.enterText(
        find.byKey(const ValueKey('menu-modifier-min')),
        '3',
      );
      await tester.enterText(
        find.byKey(const ValueKey('menu-modifier-max')),
        '1',
      );
      await tester.tap(find.text(f.l10n.menuSaveAction));
      await tester.pumpAndSettle();

      expect(find.text(f.l10n.menuErrorMaxLessThanMin), findsOneWidget);
      expect(f.writer.lastOperation, isNull);
    },
  );
}
