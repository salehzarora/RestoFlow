import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

/// MENU-ORDER-001 — the shared canonical print-order sort helper.
void main() {
  group('sortByMenuPrintOrder', () {
    test(
      'orders by the ascending key tuple (category -> item -> position)',
      () {
        final input = <({String name, int cat, int item, int pos})>[
          (name: 'Cola', cat: 3, item: 2, pos: 1),
          (name: 'Burger A', cat: 1, item: 2, pos: 2),
          (name: 'Fries', cat: 2, item: 1, pos: 3),
          (name: 'Fanta', cat: 3, item: 1, pos: 4),
          (name: 'Burger B', cat: 1, item: 1, pos: 5),
        ];
        final sorted = sortByMenuPrintOrder(
          input,
          (r) => [r.cat, r.item, r.pos],
        );
        expect(
          [for (final r in sorted) r.name],
          const ['Burger B', 'Burger A', 'Fries', 'Fanta', 'Cola'],
        );
      },
    );

    test(
      'is STABLE — equal tuples (incl. all-zero legacy) keep input order',
      () {
        final input = <({String name, int cat, int item, int pos})>[
          (name: 'a', cat: 0, item: 0, pos: 0),
          (name: 'b', cat: 0, item: 0, pos: 0),
          (name: 'c', cat: 0, item: 0, pos: 0),
        ];
        final sorted = sortByMenuPrintOrder(
          input,
          (r) => [r.cat, r.item, r.pos],
        );
        expect([for (final r in sorted) r.name], const ['a', 'b', 'c']);
      },
    );

    test('a partial tie breaks on the next key, then the input index', () {
      final input = <({String name, int cat, int item, int pos})>[
        (name: 'a', cat: 1, item: 0, pos: 0),
        (name: 'b', cat: 1, item: 2, pos: 0),
        (name: 'c', cat: 1, item: 1, pos: 0),
      ];
      final sorted = sortByMenuPrintOrder(input, (r) => [r.cat, r.item, r.pos]);
      expect([for (final r in sorted) r.name], const ['a', 'c', 'b']);
    });

    test('does not mutate the input list', () {
      final input = <({String name, int cat, int item, int pos})>[
        (name: 'x', cat: 2, item: 0, pos: 0),
        (name: 'y', cat: 1, item: 0, pos: 0),
      ];
      sortByMenuPrintOrder(input, (r) => [r.cat, r.item, r.pos]);
      expect([for (final r in input) r.name], const ['x', 'y']);
    });

    test('menuPrintOrderInt is a tolerant int-or-0 pluck', () {
      expect(menuPrintOrderInt(5), 5);
      expect(menuPrintOrderInt('7'), 7);
      expect(menuPrintOrderInt(null), 0);
      expect(menuPrintOrderInt('nope'), 0);
      expect(menuPrintOrderInt(2.0), 0); // non-int, non-parseable-as-int text
    });
  });
}
