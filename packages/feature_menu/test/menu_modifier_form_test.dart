import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_feature_menu/testing.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Opens the modifier form over a [ScriptedMenuWriter] so a test can assert
/// whether the write callback was invoked. The optional initial-* parameters
/// open the dialog in EDIT shape (quantity settings tests).
Future<({AppLocalizations l10n, ScriptedMenuWriter writer})> pumpModifierForm(
  WidgetTester tester, {
  String? id,
  String initialSelectionType = 'single',
  bool initialAllowQuantity = false,
  int? initialMaxQuantity,
}) async {
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
                  onPressed: () => showModifierFormDialog(
                    context,
                    menuItemId: 'item-1',
                    id: id,
                    initialSelectionType: initialSelectionType,
                    initialAllowQuantity: initialAllowQuantity,
                    initialMaxQuantity: initialMaxQuantity,
                  ),
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

  // --- Quantity settings (product-rescue sprint): allow_quantity is a
  // multi-select-only per-group toggle; max_quantity caps the units of a
  // single option (blank = no cap). ---

  /// Flips the selection-type dropdown from 'single' to 'multiple'.
  Future<void> selectMultiple(
    WidgetTester tester,
    AppLocalizations l10n,
  ) async {
    await tester.tap(find.text(l10n.menuSelectionSingle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.menuSelectionMultiple).last);
    await tester.pumpAndSettle();
  }

  /// Turns the allow-quantity toggle ON (scrolling it into view first).
  Future<void> enableQuantity(WidgetTester tester) async {
    await tester.ensureVisible(
      find.byKey(const ValueKey('menu-modifier-allow-quantity')),
    );
    await tester.tap(
      find.byKey(const ValueKey('menu-modifier-allow-quantity')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the allow-quantity toggle is hidden for single-select groups '
      'and a single save sends allowQuantity=false', (tester) async {
    final f = await pumpModifierForm(tester);

    expect(
      find.byKey(const ValueKey('menu-modifier-allow-quantity')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('menu-modifier-max-quantity')),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const ValueKey('menu-modifier-name')),
      'Doneness',
    );
    await tester.tap(find.text(f.l10n.menuSaveAction));
    await tester.pumpAndSettle();

    expect(f.writer.lastOperation, 'upsertModifier');
    expect(f.writer.lastAllowQuantity, isFalse);
    expect(f.writer.lastMaxQuantity, isNull);
  });

  testWidgets('the toggle appears for multi-select and turning it ON reveals '
      'the max-per-option field pre-filled with 5', (tester) async {
    final f = await pumpModifierForm(tester);
    await selectMultiple(tester, f.l10n);

    expect(
      find.byKey(const ValueKey('menu-modifier-allow-quantity')),
      findsOneWidget,
    );
    expect(find.text(f.l10n.menuAllowQuantityHelp), findsOneWidget);
    // The cap field stays hidden until the toggle is ON.
    expect(
      find.byKey(const ValueKey('menu-modifier-max-quantity')),
      findsNothing,
    );

    await enableQuantity(tester);
    final maxField = tester.widget<TextField>(
      find.byKey(const ValueKey('menu-modifier-max-quantity')),
    );
    expect(maxField.controller!.text, '5');
  });

  testWidgets('saving with the toggle ON passes allowQuantity=true and the '
      'pre-filled max 5 to the writer', (tester) async {
    final f = await pumpModifierForm(tester);
    await tester.enterText(
      find.byKey(const ValueKey('menu-modifier-name')),
      'Extras',
    );
    await selectMultiple(tester, f.l10n);
    await enableQuantity(tester);
    await tester.tap(find.text(f.l10n.menuSaveAction));
    await tester.pumpAndSettle();

    expect(f.writer.lastOperation, 'upsertModifier');
    expect(f.writer.lastAllowQuantity, isTrue);
    expect(f.writer.lastMaxQuantity, 5);
    expect(
      find.byKey(const ValueKey('menu-modifier-name')),
      findsNothing,
    ); // dialog closed
  });

  testWidgets('a blank max-per-option saves null (no cap)', (tester) async {
    final f = await pumpModifierForm(tester);
    await tester.enterText(
      find.byKey(const ValueKey('menu-modifier-name')),
      'Extras',
    );
    await selectMultiple(tester, f.l10n);
    await enableQuantity(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('menu-modifier-max-quantity')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('menu-modifier-max-quantity')),
      '',
    );
    await tester.tap(find.text(f.l10n.menuSaveAction));
    await tester.pumpAndSettle();

    expect(f.writer.lastOperation, 'upsertModifier');
    expect(f.writer.lastAllowQuantity, isTrue);
    expect(f.writer.lastMaxQuantity, isNull);
  });

  testWidgets('a non-integer or non-positive max-per-option shows the integer '
      'error and does not save', (tester) async {
    final f = await pumpModifierForm(tester);
    await tester.enterText(
      find.byKey(const ValueKey('menu-modifier-name')),
      'Extras',
    );
    await selectMultiple(tester, f.l10n);
    await enableQuantity(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('menu-modifier-max-quantity')),
    );

    await tester.enterText(
      find.byKey(const ValueKey('menu-modifier-max-quantity')),
      'abc',
    );
    await tester.tap(find.text(f.l10n.menuSaveAction));
    await tester.pumpAndSettle();
    expect(find.text(f.l10n.menuErrorAmount), findsOneWidget);
    expect(f.writer.lastOperation, isNull);

    // Zero is an integer but not a valid cap (> 0) — same error, no save.
    await tester.enterText(
      find.byKey(const ValueKey('menu-modifier-max-quantity')),
      '0',
    );
    await tester.tap(find.text(f.l10n.menuSaveAction));
    await tester.pumpAndSettle();
    expect(find.text(f.l10n.menuErrorAmount), findsOneWidget);
    expect(f.writer.lastOperation, isNull);
  });

  testWidgets('editing an existing quantity-enabled group opens with the '
      'toggle ON and its stored max', (tester) async {
    final f = await pumpModifierForm(
      tester,
      id: 'mod-1',
      initialSelectionType: 'multiple',
      initialAllowQuantity: true,
      initialMaxQuantity: 3,
    );

    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('menu-modifier-allow-quantity')),
    );
    expect(toggle.value, isTrue);
    final maxField = tester.widget<TextField>(
      find.byKey(const ValueKey('menu-modifier-max-quantity')),
    );
    expect(maxField.controller!.text, '3');
    expect(f.writer.lastOperation, isNull); // nothing saved yet
  });

  testWidgets('flipping a quantity-enabled group back to single hides the '
      'toggle and saves allowQuantity=false', (tester) async {
    final f = await pumpModifierForm(
      tester,
      id: 'mod-1',
      initialSelectionType: 'multiple',
      initialAllowQuantity: true,
      initialMaxQuantity: 3,
    );
    await tester.tap(find.text(f.l10n.menuSelectionMultiple));
    await tester.pumpAndSettle();
    await tester.tap(find.text(f.l10n.menuSelectionSingle).last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('menu-modifier-allow-quantity')),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const ValueKey('menu-modifier-name')),
      'Extras',
    );
    await tester.tap(find.text(f.l10n.menuSaveAction));
    await tester.pumpAndSettle();

    expect(f.writer.lastOperation, 'upsertModifier');
    expect(f.writer.lastAllowQuantity, isFalse);
    expect(f.writer.lastMaxQuantity, isNull);
  });
}
