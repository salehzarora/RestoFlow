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
}
