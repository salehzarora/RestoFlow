import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  CartViewState state() => container.read(cartControllerProvider);
  CartController controller() =>
      container.read(cartControllerProvider.notifier);

  const burger = DemoMenuItem(
    id: 'burger',
    name: 'Burger',
    priceMinor: 4200,
    categoryId: 'mains',
    categoryName: 'Mains',
  );
  const cola = DemoMenuItem(
    id: 'cola',
    name: 'Cola',
    priceMinor: 900,
    categoryId: 'drinks',
    categoryName: 'Drinks',
  );

  test('starts empty with a zero ILS subtotal', () {
    expect(state().isEmpty, isTrue);
    expect(state().subtotalMinor, 0);
    expect(state().currencyCode, kDemoCurrencyCode);
    expect(state().subtotal.amountMinor, 0);
  });

  test('addItem adds a line and updates the subtotal', () {
    controller().addItem(burger);
    expect(state().lines.length, 1);
    expect(state().lines.single.quantity, 1);
    expect(state().subtotalMinor, 4200);
  });

  test(
    'adding the same item twice increments quantity (no duplicate line)',
    () {
      controller().addItem(burger);
      controller().addItem(burger);
      expect(state().lines.length, 1);
      expect(state().lines.single.quantity, 2);
      expect(state().subtotalMinor, 8400);
      expect(state().itemCount, 2);
    },
  );

  test('different items create separate lines and sum the subtotal', () {
    controller().addItem(burger);
    controller().addItem(cola);
    expect(state().lines.length, 2);
    expect(state().subtotalMinor, 5100);
  });

  test('increase then decrease quantity adjusts the line and subtotal', () {
    controller().addItem(burger);
    final lineId = state().lines.single.lineId;
    controller().increaseQuantity(lineId);
    expect(state().lines.single.quantity, 2);
    expect(state().subtotalMinor, 8400);
    controller().decreaseQuantity(lineId);
    expect(state().lines.single.quantity, 1);
    expect(state().subtotalMinor, 4200);
  });

  test('decreasing a quantity-1 line removes it', () {
    controller().addItem(cola);
    final lineId = state().lines.single.lineId;
    controller().decreaseQuantity(lineId);
    expect(state().isEmpty, isTrue);
    expect(state().subtotalMinor, 0);
  });

  test('removeLine drops the targeted line only', () {
    controller().addItem(burger);
    controller().addItem(cola);
    final lineId = state().lines.first.lineId;
    controller().removeLine(lineId);
    expect(state().lines.length, 1);
    expect(state().lines.single.name, 'Cola');
  });

  test('clear empties the cart', () {
    controller().addItem(burger);
    controller().addItem(cola);
    controller().clear();
    expect(state().isEmpty, isTrue);
    expect(state().subtotalMinor, 0);
  });

  test(
    'submitOrder snapshots the order, empties the cart, numbers DEMO-0001',
    () {
      controller().addItem(burger);
      controller().addItem(burger);
      controller().addItem(cola);
      controller().submitOrder();

      final submitted = state().submittedOrder;
      expect(submitted, isNotNull);
      expect(submitted!.orderNumber, 'DEMO-0001');
      expect(submitted.subtotalMinor, 9300); // 2*4200 + 900
      expect(submitted.itemCount, 3);
      expect(submitted.lines.length, 2);
      // The cart itself is now empty; the confirmation stands on its own.
      expect(state().isEmpty, isTrue);
      expect(state().hasSubmittedOrder, isTrue);
    },
  );

  test('submitOrder is a no-op on an empty cart', () {
    controller().submitOrder();
    expect(state().submittedOrder, isNull);
  });

  test('a second submitted order increments the demo number', () {
    controller().addItem(burger);
    controller().submitOrder();
    controller().startNewOrder();
    controller().addItem(cola);
    controller().submitOrder();
    expect(state().submittedOrder!.orderNumber, 'DEMO-0002');
  });

  test('startNewOrder clears the confirmation back to an empty cart', () {
    controller().addItem(burger);
    controller().submitOrder();
    controller().startNewOrder();
    expect(state().hasSubmittedOrder, isFalse);
    expect(state().isEmpty, isTrue);
  });

  test('adding an item after submit dismisses the confirmation', () {
    controller().addItem(burger);
    controller().submitOrder();
    controller().addItem(cola);
    expect(state().hasSubmittedOrder, isFalse);
    expect(state().lines.single.name, 'Cola');
    expect(state().subtotalMinor, 900);
  });

  // ---- TABLET-UX-001 (A): editing a cart line in place. ----

  const cheese = SelectedModifier(
    optionId: 'opt-cheese',
    groupName: 'Toppings',
    optionName: 'Cheese',
    priceDeltaMinor: 300,
  );
  const extraPatty = SelectedModifier(
    optionId: 'opt-patty',
    groupName: 'Extras',
    optionName: 'Extra patty',
    priceDeltaMinor: 900,
  );

  test('updateLineModifiers replaces the line in place (no duplicate) and '
      'recomputes the total', () {
    controller().addItemWithModifiers(burger, const [cheese]);
    expect(state().lines.length, 1);
    final lineId = state().lines.single.lineId;
    expect(state().subtotalMinor, 4500); // 4200 + 300

    // Edit: swap Cheese -> Extra patty. Same line, price recomputes.
    controller().updateLineModifiers(lineId, const [extraPatty]);
    expect(state().lines.length, 1); // NOT a duplicate
    expect(state().lines.single.lineId, lineId); // same line
    expect(state().lines.single.modifiers.single.optionName, 'Extra patty');
    expect(state().subtotalMinor, 5100); // 4200 + 900
  });

  test('updateLineModifiers preserves the line quantity', () {
    controller().addItemWithModifiers(burger, const [cheese]);
    final lineId = state().lines.single.lineId;
    controller().increaseQuantity(lineId); // qty 2
    expect(state().lines.single.quantity, 2);

    controller().updateLineModifiers(lineId, const [extraPatty]);
    expect(state().lines.single.quantity, 2); // preserved
    // 2 × 4200 + 900 (one patty, once per line) = 9300.
    expect(state().subtotalMinor, 9300);
  });

  test('updateLineModifiers can clear modifiers + set/clear a note', () {
    controller().addItemWithModifiers(burger, const [cheese], note: 'no salt');
    final lineId = state().lines.single.lineId;
    expect(state().lines.single.note, 'no salt');

    // Clear the modifier, change the note.
    controller().updateLineModifiers(lineId, const [], note: '  extra hot  ');
    expect(state().lines.single.modifiers, isEmpty);
    expect(state().lines.single.note, 'extra hot'); // trimmed
    expect(state().subtotalMinor, 4200); // base only

    // Clear the note too (blank).
    controller().updateLineModifiers(lineId, const [], note: '   ');
    expect(state().lines.single.note, isNull);
  });

  test('updateLineModifiers is a no-op for an unknown line', () {
    controller().addItem(burger);
    controller().updateLineModifiers('nope', const [cheese]);
    expect(state().lines.single.modifiers, isEmpty);
    expect(state().subtotalMinor, 4200);
  });
}
