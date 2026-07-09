import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_feature_menu/testing.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// KITCHEN-MEAT-001: the modifier-OPTION editor's optional meat-summary section
/// (toggle + quantity + unit), saved as the p_kitchen_meat RPC arg. The shared
/// size/variant dialog never shows it.

/// An [InMemoryMenuStore] recording the last upsertModifierOption meat arg.
class _RecordingOptionStore extends InMemoryMenuStore {
  int optionCalls = 0;
  Map<String, dynamic>? lastKitchenMeat;

  @override
  Future<MenuWriteOutcome> upsertModifierOption({
    required MenuScope scope,
    String? id,
    required String modifierId,
    required String name,
    int priceDeltaMinor = 0,
    int displayOrder = 0,
    bool isActive = true,
    Map<String, dynamic>? kitchenMeat,
  }) {
    optionCalls++;
    lastKitchenMeat = kitchenMeat;
    return super.upsertModifierOption(
      scope: scope,
      id: id,
      modifierId: modifierId,
      name: name,
      priceDeltaMinor: priceDeltaMinor,
      displayOrder: displayOrder,
      isActive: isActive,
      kitchenMeat: kitchenMeat,
    );
  }
}

Future<({AppLocalizations l10n, _RecordingOptionStore store})> _pump(
  WidgetTester tester, {
  PricedChildKind kind = PricedChildKind.option,
  String? id,
  bool initialKitchenMeatEnabled = false,
  num? initialKitchenMeatQuantity,
  String initialKitchenMeatUnit = '',
}) async {
  final store = _RecordingOptionStore();
  late AppLocalizations l10n;
  await tester.pumpWidget(
    ProviderScope(
      overrides: menuFeatureOverrides(
        scope: demoMenuScope,
        readSource: store,
        writer: store,
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
                  onPressed: () => showPricedChildFormDialog(
                    context,
                    kind: kind,
                    parentId: 'mod-1',
                    currencyCode: 'ILS',
                    id: id,
                    initialKitchenMeatEnabled: initialKitchenMeatEnabled,
                    initialKitchenMeatQuantity: initialKitchenMeatQuantity,
                    initialKitchenMeatUnit: initialKitchenMeatUnit,
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
  return (l10n: l10n, store: store);
}

void main() {
  testWidgets('the option dialog shows the meat-summary section', (
    tester,
  ) async {
    final f = await _pump(tester);
    expect(find.text(f.l10n.menuKitchenMeatSection), findsOneWidget);
    expect(
      find.byKey(const ValueKey('menu-option-meat-enabled')),
      findsOneWidget,
    );
    // The quantity/unit fields appear only after enabling.
    expect(
      find.byKey(const ValueKey('menu-option-meat-quantity')),
      findsNothing,
    );
  });

  testWidgets('the size dialog does NOT show the meat section', (tester) async {
    final f = await _pump(tester, kind: PricedChildKind.size);
    expect(find.text(f.l10n.menuKitchenMeatSection), findsNothing);
  });

  testWidgets('enabling meat + quantity + unit saves kitchen_meat', (
    tester,
  ) async {
    final f = await _pump(tester);
    await tester.enterText(
      find.byKey(const ValueKey('menu-child-name')),
      'Double',
    );
    await tester.tap(find.byKey(const ValueKey('menu-option-meat-enabled')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('menu-option-meat-quantity')),
      '2',
    );
    await tester.enterText(
      find.byKey(const ValueKey('menu-option-meat-unit')),
      'patties',
    );
    await tester.tap(find.text(f.l10n.menuSaveAction));
    await tester.pumpAndSettle();

    expect(f.store.optionCalls, 1);
    expect(f.store.lastKitchenMeat, {'quantity': 2, 'unit': 'patties'});
  });

  testWidgets('a disabled meat toggle saves null kitchen_meat', (tester) async {
    final f = await _pump(tester);
    await tester.enterText(
      find.byKey(const ValueKey('menu-child-name')),
      'Plain',
    );
    await tester.tap(find.text(f.l10n.menuSaveAction));
    await tester.pumpAndSettle();

    expect(f.store.optionCalls, 1);
    expect(f.store.lastKitchenMeat, isNull);
  });

  testWidgets('an enabled meat with an invalid quantity blocks the save', (
    tester,
  ) async {
    final f = await _pump(tester);
    await tester.enterText(
      find.byKey(const ValueKey('menu-child-name')),
      'Double',
    );
    await tester.tap(find.byKey(const ValueKey('menu-option-meat-enabled')));
    await tester.pumpAndSettle();
    // Leave quantity blank (invalid).
    await tester.tap(find.text(f.l10n.menuSaveAction));
    await tester.pumpAndSettle();

    expect(f.store.optionCalls, 0);
    expect(find.text(f.l10n.menuErrorAmount), findsOneWidget);
  });

  testWidgets('the edit dialog pre-fills the option meat metadata', (
    tester,
  ) async {
    final f = await _pump(
      tester,
      id: 'opt-1',
      initialKitchenMeatEnabled: true,
      initialKitchenMeatQuantity: 2,
      initialKitchenMeatUnit: 'قطع',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('menu-option-meat-quantity')),
          )
          .controller!
          .text,
      '2',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('menu-option-meat-unit')),
          )
          .controller!
          .text,
      'قطع',
    );
    expect(f.store.optionCalls, 0);
  });
}
