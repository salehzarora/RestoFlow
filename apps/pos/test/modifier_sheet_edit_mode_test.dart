import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/widgets/modifier_selection_sheet.dart';

/// ORDER-EDIT-001E — the modifier sheet in EDIT MODE (plan §8d; design §6,
/// §7.1 point 3): a SENT line's sheet edits modifiers and note only.
///
///  * no quantity stepper — a sent line's quantity moves only through its own
///    cart stepper;
///  * "Apply to: All N / Just 1" only when the line has two or more units,
///    and "Just 1" is handed back with the selections (and totals ONE unit);
///  * a kept option is shown at the price the line will be charged
///    (`normalizeSelections`), never a live price the customer never pays;
///  * outside edit mode nothing changes.
///
/// Every amount is an independent literal (D-007).

const _item = DemoMenuItem(
  id: 'mi-burger',
  name: 'Burger',
  priceMinor: 4000,
  categoryId: 'cat',
  categoryName: 'Cat',
);

const _groups = <PosModifierGroup>[
  PosModifierGroup(
    id: 'grp-top',
    menuItemId: 'mi-burger',
    name: 'Toppings',
    options: [
      // Live prices: Bacon went up to 700 since the order was sent at 500.
      PosModifierOption(id: 'opt-bacon', name: 'Bacon', priceDeltaMinor: 700),
      PosModifierOption(id: 'opt-cheese', name: 'Cheese', priceDeltaMinor: 300),
    ],
  ),
];

/// The stored Bacon of the sent line — 500 at order time.
const _storedBacon = SelectedModifier(
  optionId: 'opt-bacon',
  groupName: 'Toppings',
  optionName: 'Bacon',
  priceDeltaMinor: 500,
  modifierGroupId: 'grp-top',
);

class _Captured {
  List<SelectedModifier>? selections;
  String? note;
  bool? applyToOne;
  int? quantity;
}

Future<_Captured> _open(
  WidgetTester tester, {
  bool editMode = true,
  int quantity = 3,
  List<SelectedModifier> initial = const <SelectedModifier>[_storedBacon],
  List<SelectedModifier> Function(List<SelectedModifier>)? normalize,
}) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final captured = _Captured();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const Key('open'),
            onPressed: () => ModifierSelectionSheet.show(
              context,
              item: _item,
              groups: _groups,
              currencyCode: 'ILS',
              initialSelections: initial,
              isEdit: true,
              initialQuantity: quantity,
              displayBasePriceMinor: 4000,
              editMode: editMode,
              applyToCount: quantity,
              normalizeSelections: normalize,
              onConfirm: (selections, note, q) {
                captured
                  ..selections = selections
                  ..note = note
                  ..quantity = q;
              },
              onConfirmEdit: editMode
                  ? (selections, note, one) {
                      captured
                        ..selections = selections
                        ..note = note
                        ..applyToOne = one;
                    }
                  : null,
            ),
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
  return captured;
}

Finder _inSheet(String text) => find.descendant(
  of: find.byType(ModifierSelectionSheet),
  matching: find.text(text),
);

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('modifier-add-button')));
  await tester.tap(find.byKey(const Key('modifier-add-button')));
  await tester.pumpAndSettle();
}

/// Bacon back at its STORED 500 — what the cart's normalisation charges.
List<SelectedModifier> _keepStoredBacon(List<SelectedModifier> s) => [
  for (final m in s) m.optionId == 'opt-bacon' ? _storedBacon : m,
];

void main() {
  testWidgets('edit mode: no stepper; "Apply to" for several units', (
    tester,
  ) async {
    await _open(tester);
    expect(find.byKey(const Key('modifier-item-quantity-row')), findsNothing);
    expect(find.byKey(const Key('modifier-apply-to-row')), findsOneWidget);
    expect(_inSheet('Apply to'), findsOneWidget);
    expect(_inSheet('All 3'), findsOneWidget);
    expect(_inSheet('Just 1'), findsOneWidget);
    // All three, untouched Bacon at its stored 500: 3 × 4500.
    expect(_inSheet('₪135.00'), findsOneWidget);
  });

  testWidgets('a single unit: no "Apply to"', (tester) async {
    await _open(tester, quantity: 1);
    expect(find.byKey(const Key('modifier-apply-to-row')), findsNothing);
    expect(find.byKey(const Key('modifier-item-quantity-row')), findsNothing);
  });

  testWidgets('"All 3" hands back the options and applyToOne false', (
    tester,
  ) async {
    final captured = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('modifier-option-opt-cheese')));
    await tester.pumpAndSettle();
    await _save(tester);
    expect(captured.applyToOne, isFalse);
    expect(captured.quantity, isNull); // onConfirm is never called
    expect(captured.selections!.map((s) => s.optionId), [
      'opt-bacon',
      'opt-cheese',
    ]);
  });

  testWidgets('"Just 1" totals ONE unit and is handed back', (tester) async {
    final captured = await _open(tester);
    await tester.tap(find.byKey(const Key('modifier-apply-to-one')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('modifier-option-opt-cheese')));
    await tester.pumpAndSettle();
    // One burger: 4000 + Bacon 500 (stored) + Cheese 300.
    expect(_inSheet('₪48.00'), findsOneWidget);
    await _save(tester);
    expect(captured.applyToOne, isTrue);
  });

  testWidgets('a touched kept option shows its STORED price when the line '
      'normalises it', (tester) async {
    // Deselect and re-pick Bacon: the sheet now prices it LIVE (700)...
    await _open(tester, quantity: 1);
    await tester.tap(find.byKey(const ValueKey('modifier-option-opt-bacon')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('modifier-option-opt-bacon')));
    await tester.pumpAndSettle();
    expect(_inSheet('₪47.00'), findsOneWidget);
  });

  testWidgets('...but with the edit\'s normaliser the total is what the '
      'customer is charged', (tester) async {
    final captured = await _open(
      tester,
      quantity: 1,
      normalize: _keepStoredBacon,
    );
    await tester.tap(find.byKey(const ValueKey('modifier-option-opt-bacon')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('modifier-option-opt-bacon')));
    await tester.pumpAndSettle();
    expect(_inSheet('₪45.00'), findsOneWidget);
    expect(_inSheet('₪47.00'), findsNothing);
    await _save(tester);
    expect(captured.selections!.single.priceDeltaMinor, 500);
  });

  testWidgets('outside edit mode the sheet is unchanged', (tester) async {
    final captured = await _open(tester, editMode: false, quantity: 2);
    expect(find.byKey(const Key('modifier-item-quantity-row')), findsOneWidget);
    expect(find.byKey(const Key('modifier-apply-to-row')), findsNothing);
    await _save(tester);
    expect(captured.quantity, 2);
    expect(captured.applyToOne, isNull);
  });
}
