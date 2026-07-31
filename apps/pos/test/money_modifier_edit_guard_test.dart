import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/widgets/modifier_selection_sheet.dart';

/// MONEY-MODIFIER-PRICING-INTEGRITY-001 [D1] — editing a configured cart line
/// must NEVER silently drop a paid modifier.
///
/// The edit path reopens the SAME modifier sheet prefilled from the line. When
/// the live menu cannot supply the authoritative groups, the sheet resolved
/// ZERO initial selections, `_satisfied` was vacuously true over an empty group
/// list, and confirming called `updateLineModifiers(lineId, [])` — which drops
/// the stored snapshots and reprices the line down to its bare base. That is
/// the exact under-charge Saleh reproduced physically.
///
/// Nothing here asserts on strings the user cannot see; every money assertion is
/// an exact integer minor-unit value.

const kBase = 4500;
const k240 = 1500;
const k360 = 2500;

const burger = DemoMenuItem(
  id: 'burger-meat',
  name: 'Burger',
  priceMinor: kBase,
  categoryId: 'food',
  categoryName: 'Food',
);

/// The REAL pricing shape (F3): required, single-select, PAID meat sizes.
const meatGroup = PosModifierGroup(
  id: 'grp-meat',
  menuItemId: 'burger-meat',
  name: 'Meat',
  singleSelect: true,
  isRequired: true,
  options: [
    PosModifierOption(id: 'opt-120', name: '120g', priceDeltaMinor: 0),
    PosModifierOption(id: 'opt-240', name: '240g', priceDeltaMinor: k240),
    PosModifierOption(id: 'opt-360', name: '360g', priceDeltaMinor: k360),
    PosModifierOption(id: 'opt-480', name: '480g', priceDeltaMinor: 3500),
  ],
);

/// The same group with the 240g option REMOVED — models an option deleted in
/// the Dashboard after the line was configured.
const meatGroupWithout240 = PosModifierGroup(
  id: 'grp-meat',
  menuItemId: 'burger-meat',
  name: 'Meat',
  singleSelect: true,
  isRequired: true,
  options: [
    PosModifierOption(id: 'opt-120', name: '120g', priceDeltaMinor: 0),
    PosModifierOption(id: 'opt-360', name: '360g', priceDeltaMinor: k360),
  ],
);

const selected240 = SelectedModifier(
  optionId: 'opt-240',
  groupName: 'Meat',
  optionName: '240g',
  priceDeltaMinor: k240,
);

// An OPTIONAL multi-select paid group — the shape with no accidental minimum
// to hide behind, so a removed option would silently cost real money.
const kBacon = 800;
const kCheese = 300;

const extrasGroupWithoutBacon = PosModifierGroup(
  id: 'grp-extras',
  menuItemId: 'burger-meat',
  name: 'Extras',
  maxSelect: 3,
  options: [
    PosModifierOption(
      id: 'opt-cheese',
      name: 'Cheese',
      priceDeltaMinor: kCheese,
    ),
  ],
);

const selectedBacon = SelectedModifier(
  optionId: 'opt-bacon',
  groupName: 'Extras',
  optionName: 'Bacon',
  priceDeltaMinor: kBacon,
);

const selectedCheese = SelectedModifier(
  optionId: 'opt-cheese',
  groupName: 'Extras',
  optionName: 'Cheese',
  priceDeltaMinor: kCheese,
);

PosMenuData menuWith(List<PosModifierGroup> groups) => PosMenuData(
  categories: const [
    DemoCategory(
      id: 'food',
      name: 'Food',
      icon: Icons.lunch_dining,
      color: Colors.orange,
    ),
  ],
  items: const [burger],
  currencyCode: 'ILS',
  modifierGroups: groups,
);

/// Pumps the real POS screen with a cart line already configured at 240g.
///
/// [menu] null => the provider never completes, i.e. the menu is genuinely
/// unavailable/loading, which is the state that produced the wipe.
Future<ProviderContainer> pumpWithConfiguredLine(
  WidgetTester tester, {
  required PosMenuData? menu,
}) async {
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
      if (menu == null)
        posMenuProvider.overrideWith((ref) => Completer<PosMenuData>().future)
      else
        posMenuProvider.overrideWith((ref) async => menu),
    ],
  );
  addTearDown(container.dispose);
  container.read(cartControllerProvider.notifier).addItemWithModifiers(
    burger,
    const [selected240],
  );

  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const PosMenuScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return container;
}

CartViewState viewOf(ProviderContainer c) => c.read(cartControllerProvider);

Future<void> openEdit(WidgetTester tester, ProviderContainer c) async {
  final lineId = viewOf(c).lines.single.lineId;
  final edit = find.byKey(Key('cart-edit-$lineId'));
  expect(edit, findsOneWidget, reason: 'the cart line offers Edit');
  await tester.ensureVisible(edit);
  await tester.tap(edit);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(ModifierSelectionSheet), findsOneWidget);
}

Finder confirmButton() => find.byKey(const Key('modifier-add-button'));

void main() {
  group('[D1] A. menu unavailable — the edit must be note-only', () {
    testWidgets('A1 confirming an edit while the menu is UNAVAILABLE must not '
        'drop the paid modifier or reprice the line', (tester) async {
      final c = await pumpWithConfiguredLine(tester, menu: null);
      expect(viewOf(c).lines.single.lineTotalMinor, kBase + k240);

      await openEdit(tester, c);
      // Whatever the sheet offers here, confirming it must never be able to
      // erase money that the cashier can still see on the line.
      final confirm = confirmButton();
      if (confirm.evaluate().isNotEmpty) {
        final button = tester.widget<FilledButton>(confirm);
        if (button.onPressed != null) {
          await tester.tap(confirm);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        }
      }

      final line = viewOf(c).lines.single;
      expect(
        line.modifiers,
        hasLength(1),
        reason: 'the stored 240g snapshot must survive an unresolvable edit',
      );
      expect(line.modifiers.single.optionId, 'opt-240');
      expect(line.modifiers.single.priceDeltaMinor, k240);
      expect(
        line.lineTotalMinor,
        kBase + k240,
        reason: 'the line must NOT silently reprice down to base',
      );
      expect(viewOf(c).subtotalMinor, kBase + k240);
    });
  });

  group('[D1] B. a stored option missing from the live menu', () {
    testWidgets('B1 Save is DISABLED while a stored selection cannot be '
        'represented', (tester) async {
      final c = await pumpWithConfiguredLine(
        tester,
        menu: menuWith(const [meatGroupWithout240]),
      );
      await openEdit(tester, c);
      final confirm = confirmButton();
      expect(confirm, findsOneWidget);
      expect(
        tester.widget<FilledButton>(confirm).onPressed,
        isNull,
        reason:
            'saving here would silently replace the 240g surcharge with the '
            'options that happen to still exist',
      );
    });

    testWidgets('B4 a PARTIALLY resolvable OPTIONAL group must not silently '
        'save away the option that disappeared', (tester) async {
      // B1 only blocks because that group is REQUIRED single-select, so its
      // minimum happens to be unmet. An OPTIONAL multi-select has no such
      // accidental guard: one stored option still resolves, `_satisfied` is
      // true, Save is live, and confirming would quietly drop the 8.00 bacon
      // and keep only the 3.00 cheese. This is the real partial-loss case.
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: true),
          ),
          posMenuProvider.overrideWith(
            (ref) async => menuWith(const [extrasGroupWithoutBacon]),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(cartControllerProvider.notifier).addItemWithModifiers(
        burger,
        const [selectedBacon, selectedCheese],
      );
      expect(
        container.read(cartControllerProvider).lines.single.lineTotalMinor,
        kBase + kBacon + kCheese,
      );

      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const PosMenuScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await openEdit(tester, container);

      final confirm = confirmButton();
      expect(confirm, findsOneWidget);
      expect(
        tester.widget<FilledButton>(confirm).onPressed,
        isNull,
        reason:
            'the bacon snapshot cannot be represented, so saving would drop '
            'its 8.00 surcharge while keeping the cheese',
      );

      // And even if it were pressed, the money must not move.
      final line = container.read(cartControllerProvider).lines.single;
      expect(line.modifiers, hasLength(2));
      expect(line.lineTotalMinor, kBase + kBacon + kCheese);
    });

    testWidgets('B3 cancelling leaves every modifier and the money intact', (
      tester,
    ) async {
      final c = await pumpWithConfiguredLine(
        tester,
        menu: menuWith(const [meatGroupWithout240]),
      );
      await openEdit(tester, c);
      await tester.tapAt(const Offset(20, 20)); // dismiss
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final line = viewOf(c).lines.single;
      expect(line.modifiers.single.optionId, 'opt-240');
      expect(line.lineTotalMinor, kBase + k240);
    });
  });

  group('[PERMANENT] C. a fully resolvable edit still works', () {
    testWidgets('C1 changing 240g -> 360g reprices ONLY that line', (
      tester,
    ) async {
      final c = await pumpWithConfiguredLine(
        tester,
        menu: menuWith(const [meatGroup]),
      );
      // A second, independent line that must not move.
      c.read(cartControllerProvider.notifier).addItemWithModifiers(
        burger,
        const [selected240],
      );
      await tester.pump();

      final target = viewOf(c).lines.first.lineId;
      final sibling = viewOf(c).lines.last.lineId;
      final edit = find.byKey(Key('cart-edit-$target'));
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('360g'));
      await tester.pump();
      final confirm = confirmButton();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final lines = viewOf(c).lines;
      final edited = lines.firstWhere((l) => l.lineId == target);
      final other = lines.firstWhere((l) => l.lineId == sibling);
      expect(edited.modifiers.single.optionId, 'opt-360');
      expect(edited.lineTotalMinor, kBase + k360);
      expect(
        other.lineTotalMinor,
        kBase + k240,
        reason: 'the sibling line must be untouched',
      );
      expect(viewOf(c).subtotalMinor, (kBase + k360) + (kBase + k240));
    });
  });
}
