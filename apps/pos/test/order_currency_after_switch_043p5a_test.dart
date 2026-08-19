import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';

/// OPS-043 Phase 5A (coverage-only) — WHAT CURRENCY A NEW ORDER IS TAKEN IN.
///
/// Phase 5 recorded this as an untested gap: nothing anywhere asserted that an
/// order started AFTER the owner changes the operating currency is booked in
/// the new one. The whole currency programme rests on it — the reports, the
/// receipts and the breakdown all read a currency the cart decided.
///
/// The behaviour already exists (`CartController._activeCurrency` reads the
/// menu, and `addItem` re-binds an EMPTY cart before its first line). These
/// tests pin it, including the half that is easy to lose: a cart that ALREADY
/// has lines must NOT be re-denominated underneath the cashier.
void main() {
  final menuSource = StateProvider<PosMenuData>((ref) => _menu('ILS'));

  ProviderContainer containerWith() => ProviderContainer(
    overrides: [posMenuProvider.overrideWith((ref) => ref.watch(menuSource))],
  );

  const burger = DemoMenuItem(
    id: 'burger',
    name: 'Burger',
    priceMinor: 4200,
    categoryId: 'mains',
    categoryName: 'Mains',
  );

  test('a cart started while the menu is JOD is a JOD cart', () {
    final container = containerWith();
    addTearDown(container.dispose);
    container.read(menuSource.notifier).state = _menu('JOD');
    // Force the menu to resolve before the cart reads it.
    container.read(posMenuProvider);

    final controller = container.read(cartControllerProvider.notifier);
    controller.addItem(burger);

    expect(container.read(cartControllerProvider).currencyCode, 'JOD');
  });

  test('an EMPTY cart re-binds to the new operating currency before its first '
      'line — the order the cashier is about to take is in the new one', () {
    final container = containerWith();
    addTearDown(container.dispose);
    container.read(posMenuProvider);
    final controller = container.read(cartControllerProvider.notifier);

    // The cart exists, built while the restaurant was on ILS.
    expect(container.read(cartControllerProvider).currencyCode, 'ILS');

    // The owner switches the operating currency; the menu reloads.
    container.read(menuSource.notifier).state = _menu('JOD');
    container.read(posMenuProvider);

    controller.addItem(burger);
    expect(
      container.read(cartControllerProvider).currencyCode,
      'JOD',
      reason: 'a new order after the switch must be taken in the NEW currency',
    );
  });

  test('a cart that ALREADY has lines is NOT re-denominated underneath the '
      'cashier', () {
    final container = containerWith();
    addTearDown(container.dispose);
    container.read(posMenuProvider);
    final controller = container.read(cartControllerProvider.notifier);

    controller.addItem(burger);
    expect(container.read(cartControllerProvider).currencyCode, 'ILS');

    // Mid-order switch. The lines were priced in ILS; relabelling them JOD
    // would silently restate the money already on the ticket.
    container.read(menuSource.notifier).state = _menu('JOD');
    container.read(posMenuProvider);
    controller.addItem(burger);

    expect(
      container.read(cartControllerProvider).currencyCode,
      'ILS',
      reason: 'an open ticket keeps the currency its lines were priced in',
    );
  });

  test('clearing the cart lets the next order pick up the new currency', () {
    final container = containerWith();
    addTearDown(container.dispose);
    container.read(posMenuProvider);
    final controller = container.read(cartControllerProvider.notifier);

    controller.addItem(burger);
    container.read(menuSource.notifier).state = _menu('JOD');
    container.read(posMenuProvider);

    controller.clear();
    controller.addItem(burger);

    expect(container.read(cartControllerProvider).currencyCode, 'JOD');
  });
}

PosMenuData _menu(String currencyCode) => PosMenuData(
  categories: const [
    DemoCategory(
      id: 'mains',
      name: 'Mains',
      icon: Icons.lunch_dining,
      color: Colors.orange,
    ),
  ],
  items: const [
    DemoMenuItem(
      id: 'burger',
      name: 'Burger',
      priceMinor: 4200,
      categoryId: 'mains',
      categoryName: 'Mains',
    ),
  ],
  currencyCode: currencyCode,
  modifierGroups: const <PosModifierGroup>[],
);
