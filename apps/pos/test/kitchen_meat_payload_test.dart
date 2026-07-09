import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';

/// KITCHEN-MEAT-001: the POS snapshots a selected option's meat metadata into
/// the order payload (order_item_modifiers[].meat_snapshot) — emitted ONLY when
/// present so the pre-feature wire shape + idempotency fingerprint are unchanged.
void main() {
  test('OrderSubmissionModifier.toJson emits meat_snapshot when present', () {
    final json = const OrderSubmissionModifier(
      modifierOptionId: 'opt-1',
      optionNameSnapshot: 'Double',
      priceMinorSnapshot: 0,
      quantity: 1,
      meatSnapshot: KitchenMeat(quantity: 2, unit: 'قطع'),
    ).toJson();

    expect(json['meat_snapshot'], {'quantity': 2, 'unit': 'قطع'});
    expect(
      (json['meat_snapshot'] as Map).keys.any((k) => '$k'.contains('minor')),
      isFalse,
    );
  });

  test(
    'toJson OMITS meat_snapshot when the option has no meat (wire unchanged)',
    () {
      final json = const OrderSubmissionModifier(
        modifierOptionId: 'opt-1',
        optionNameSnapshot: 'No onion',
        priceMinorSnapshot: 0,
        quantity: 1,
      ).toJson();
      expect(json.containsKey('meat_snapshot'), isFalse);
      expect(
        json.keys,
        containsAll(<String>[
          'modifier_option_id',
          'option_name_snapshot',
          'price_minor_snapshot',
          'quantity',
        ]),
      );
    },
  );

  test('PosModifierOption carries a parsed kitchenMeat', () {
    const option = PosModifierOption(
      id: 'opt-1',
      name: 'Double',
      priceDeltaMinor: 0,
      kitchenMeat: KitchenMeat(quantity: 2, unit: 'patties'),
    );
    expect(option.kitchenMeat, const KitchenMeat(quantity: 2, unit: 'patties'));
  });

  test('the demo Extra patty option ships configured meat (visible demo)', () {
    final extraPatty = kDemoModifierGroups
        .expand((g) => g.options)
        .firstWhere((o) => o.id == 'demo-opt-extra-patty');
    expect(extraPatty.kitchenMeat, isNotNull);
    expect(extraPatty.kitchenMeat!.quantity, 1);
  });
}
