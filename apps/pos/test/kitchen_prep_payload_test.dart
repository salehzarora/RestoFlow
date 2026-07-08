import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';

/// KITCHEN-PREP-001: the POS snapshots each item's configured prep components
/// into the order payload (order_items[].prep_snapshot) — emitted ONLY when
/// present so the pre-feature wire shape + idempotency fingerprint are unchanged.
void main() {
  OrderSubmissionItem itemWithPrep(List<KitchenPrepComponent> prep) =>
      OrderSubmissionItem(
        menuItemId: 'm1',
        nameSnapshot: 'Cheeseburger',
        quantity: 2,
        unitPriceMinorSnapshot: 4800,
        lineTotalMinor: 9600,
        prepComponents: prep,
      );

  test('toJson emits prep_snapshot as {name,quantity,unit} when present', () {
    final json = itemWithPrep(const [
      KitchenPrepComponent(name: 'لحم برجر', quantity: 1, unit: 'قطع'),
      KitchenPrepComponent(name: 'Bun', quantity: 1),
    ]).toJson();

    expect(json['prep_snapshot'], [
      {'name': 'لحم برجر', 'quantity': 1, 'unit': 'قطع'},
      {'name': 'Bun', 'quantity': 1, 'unit': ''},
    ]);
    // Non-money: the prep snapshot never carries a *_minor key.
    for (final row in (json['prep_snapshot'] as List).cast<Map>()) {
      expect(row.keys.any((k) => '$k'.contains('minor')), isFalse);
    }
  });

  test('toJson OMITS prep_snapshot when there is no prep (wire unchanged)', () {
    final json = itemWithPrep(const []).toJson();
    expect(json.containsKey('prep_snapshot'), isFalse);
    // The pre-feature key set is otherwise intact.
    expect(
      json.keys,
      containsAll(<String>[
        'menu_item_id',
        'menu_item_name_snapshot',
        'quantity',
        'unit_price_minor_snapshot',
        'line_total_minor',
      ]),
    );
  });

  test('DemoMenuItem.prepComponents parses the attributes bag', () {
    const item = DemoMenuItem(
      id: 'x',
      name: 'Burger',
      priceMinor: 4200,
      categoryId: 'burgers',
      categoryName: 'Burgers',
      attributes: <String, dynamic>{
        'prep_components': [
          {'name': 'Patty', 'quantity': 2, 'unit': 'pcs'},
        ],
      },
    );
    expect(item.prepComponents, const [
      KitchenPrepComponent(name: 'Patty', quantity: 2, unit: 'pcs'),
    ]);
  });

  test('the demo Cheeseburger ships configured prep (visible demo)', () {
    final cheeseburger = kDemoMenu.firstWhere((i) => i.id == 'cheeseburger');
    expect(cheeseburger.prepComponents, isNotEmpty);
    expect(
      cheeseburger.prepComponents.map((c) => c.name),
      contains('Beef patty'),
    );
  });
}
