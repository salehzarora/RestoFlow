import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kiosk/src/data/kiosk_fixtures.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';

/// KIOSK-001 Phase 1 — fixture pricing in integer minor units.
///
/// The MANDATORY fixture: burger base 40.00 ILS; required weight group
/// 120g included · 240g +15.00 · 360g +25.00 (MONEY spec §9 shape:
/// unit = base + Σ deltas, line = unit × qty).
void main() {
  final burger = kioskItemById('b1');

  group('unit price', () {
    test('base 40.00 with the included 120g stays 4000 minor', () {
      expect(
        kioskUnitPriceMinor(burger, {
          'weight': ['w120'],
        }),
        4000,
      );
    });

    test('240g adds exactly +1500 minor', () {
      expect(
        kioskUnitPriceMinor(burger, {
          'weight': ['w240'],
        }),
        5500,
      );
    });

    test('360g adds exactly +2500 minor', () {
      expect(
        kioskUnitPriceMinor(burger, {
          'weight': ['w360'],
        }),
        6500,
      );
    });

    test('multi add-ons sum their signed deltas', () {
      expect(
        kioskUnitPriceMinor(burger, {
          'weight': ['w240'],
          'addons': ['a2', 'a4'], // +600 +600
          'remove': ['r1'], // ±0
        }),
        4000 + 1500 + 600 + 600,
      );
    });
  });

  group('required validation', () {
    test('missing weight is reported as unmet', () {
      expect(kioskUnmetRequiredGroups(burger, {}), ['weight']);
    });

    test('optional groups never block', () {
      expect(
        kioskUnmetRequiredGroups(burger, {
          'weight': ['w120'],
        }),
        isEmpty,
      );
    });

    test('meal reports every unmet required group in menu order', () {
      final meal = kioskItemById('m1');
      expect(
        kioskUnmetRequiredGroups(meal, {
          'weight': ['w120'],
        }),
        ['side', 'drink'],
      );
    });
  });

  group('cart totals through the controller', () {
    late ProviderContainer container;
    late KioskFlowController controller;

    setUp(() {
      container = ProviderContainer();
      controller = container.read(kioskFlowProvider.notifier);
      addTearDown(container.dispose);
    });

    test('line total scales the unit by quantity', () {
      controller.openItem('b1');
      controller.toggleOption('weight', 'w360');
      controller.setDraftQuantity(3);
      expect(controller.submitDraft(), isTrue);
      final state = container.read(kioskFlowProvider);
      expect(state.cart.single.lineTotalMinor, 6500 * 3);
      expect(state.cartTotalMinor, 6500 * 3);
    });

    test('order total sums the lines', () {
      controller.openItem('b1');
      controller.toggleOption('weight', 'w240');
      expect(controller.submitDraft(), isTrue); // 5500
      controller.openItem('d1');
      controller.setDraftQuantity(2);
      expect(controller.submitDraft(), isTrue); // 2000
      expect(container.read(kioskFlowProvider).cartTotalMinor, 5500 + 2000);
    });

    test('a blocked draft never reaches the cart', () {
      controller.openItem('m1'); // side + drink required, only weight preset
      expect(controller.submitDraft(), isFalse);
      final state = container.read(kioskFlowProvider);
      expect(state.cart, isEmpty);
      expect(state.draft?.showRequiredError, isTrue);
    });
  });

  group('money formatting (the artifact fmt)', () {
    test('whole amounts drop decimals', () {
      expect(kioskFormatMinor(4000, 'en'), '₪40');
      expect(kioskFormatMinor(4000, 'ar'), '40 ₪');
    });

    test('fractional amounts keep two decimals', () {
      expect(kioskFormatMinor(4150, 'en'), '₪41.50');
      expect(kioskFormatMinor(4150, 'he'), '41.50 ₪');
    });

    test('deltas are signed', () {
      expect(kioskFormatDeltaMinor(1500, 'en'), '+₪15');
      expect(kioskFormatDeltaMinor(1500, 'ar'), '+15 ₪');
    });
  });
}
