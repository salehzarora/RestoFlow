import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show KitchenMeat;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';

/// MONEY-LOCAL-ATOMICITY-003A [A] — the cart restore must be TRANSACTIONAL.
///
/// `restoreDraft` replaces the live `Cart` and clears all four side maps BEFORE
/// a single incoming line has been validated, then adds lines one at a time.
/// The domain refuses a duplicate line id by THROWING
/// (`Cart.addLine` -> `DuplicateLineException`), so a draft whose 3rd of 5 lines
/// repeats an id destroys the cashier's active cart and leaves a shorter,
/// cheaper one behind — or an exception escaping into the UI.
///
/// The contract this suite pins: build and validate a complete replacement
/// first, then swap it in once. On ANY failure the previous cart, its money and
/// every side map stay exactly as they were, and the caller is told plainly.
///
/// Every expected amount is an INDEPENDENT LITERAL.

const kBase = 4500;
const k240 = 1500;
const kCola = 1000;
const kIce = 300;
// 2 x (4500 + 1500) = 12000; 1 x (1000 + 300) = 1300; active cart = 13300.
const kBurgerLine = 12000;
const kColaLine = 1300;
const kActiveSubtotal = 13300;

const _burger = DemoMenuItem(
  id: 'burger-meat',
  name: 'Burger',
  priceMinor: kBase,
  categoryId: 'food',
  categoryName: 'Food',
  categoryDisplayOrder: 1,
  itemDisplayOrder: 2,
);
const _cola = DemoMenuItem(
  id: 'cola',
  name: 'Cola',
  priceMinor: kCola,
  categoryId: 'drinks',
  categoryName: 'Drinks',
  categoryDisplayOrder: 3,
  itemDisplayOrder: 1,
);

const _meat240 = SelectedModifier(
  optionId: 'opt-240',
  modifierGroupId: 'grp-meat',
  groupName: 'Meat',
  optionName: '240g',
  priceDeltaMinor: k240,
  kitchenMeat: KitchenMeat(quantity: 1, unit: 'patty'),
);
const _extraIce = SelectedModifier(
  optionId: 'opt-ice',
  modifierGroupId: 'grp-ice',
  groupName: 'Ice',
  optionName: 'Extra ice',
  priceDeltaMinor: kIce,
);

ProviderContainer harness() {
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// The cashier's ACTIVE cart: a quantity-2 upgraded burger with a note and a
/// prep snapshot, plus a configured cola. 13300 in total.
void buildActiveCart(ProviderContainer c) {
  final cart = c.read(cartControllerProvider.notifier);
  cart.addItemWithModifiers(_burger, const [_meat240], note: 'no onion');
  final burgerLine = c.read(cartControllerProvider).lines.single.lineId;
  cart.increaseQuantity(burgerLine);
  cart.addItemWithModifiers(_cola, const [_extraIce]);

  final v = c.read(cartControllerProvider);
  expect(v.lines, hasLength(2));
  expect(v.lines[0].lineTotalMinor, kBurgerLine);
  expect(v.lines[1].lineTotalMinor, kColaLine);
  expect(v.subtotalMinor, kActiveSubtotal);
}

/// A complete, comparable fingerprint of the cart's money and identity.
List<String> fingerprint(ProviderContainer c) {
  final v = c.read(cartControllerProvider);
  return <String>[
    'subtotal=${v.subtotalMinor}',
    for (final l in v.lines)
      [
        l.lineId,
        l.menuItemId,
        'qty=${l.quantity}',
        'unit=${l.unitPriceMinor}',
        'total=${l.lineTotalMinor}',
        'note=${l.note}',
        'cat=${l.categoryDisplayOrder}',
        'item=${l.itemDisplayOrder}',
        for (final m in l.modifiers)
          '${m.modifierGroupId}|${m.optionId}|${m.priceDeltaMinor}|${m.quantity}',
      ].join(','),
  ];
}

CartDraftLine draftLine({
  required String lineId,
  String menuItemId = 'burger-meat',
  String name = 'Burger',
  int basePriceMinor = kBase,
  int quantity = 1,
  List<SelectedModifier> modifiers = const [_meat240],
}) => CartDraftLine(
  lineId: lineId,
  menuItemId: menuItemId,
  name: name,
  basePriceMinor: basePriceMinor,
  quantity: quantity,
  modifiers: modifiers,
);

CartDraftSnapshot draftWith(List<CartDraftLine> lines) =>
    CartDraftSnapshot(currencyCode: 'ILS', lines: lines);

void main() {
  group('[A] a draft that cannot be restored leaves the active cart alone', () {
    test('A1 DUPLICATE LINE IDS: the active cart survives byte-for-byte and '
        'the caller is told the restore did not apply', () {
      final c = harness();
      buildActiveCart(c);
      final before = fingerprint(c);

      // Five incoming lines whose THIRD repeats the first id.
      final result = c
          .read(cartControllerProvider.notifier)
          .restoreDraft(
            draftWith([
              draftLine(lineId: 'line-100'),
              draftLine(lineId: 'line-101'),
              draftLine(lineId: 'line-100'), // duplicate
              draftLine(lineId: 'line-102'),
              draftLine(lineId: 'line-103'),
            ]),
          );

      expect(
        result,
        isNot(CartMutationResult.applied),
        reason: 'the caller must be able to tell nothing was applied',
      );
      expect(
        fingerprint(c),
        before,
        reason:
            'the cashier still has the cart they had — 13300, both lines, '
            'the note, the prep ranks and every surcharge',
      );
      expect(c.read(cartControllerProvider).subtotalMinor, kActiveSubtotal);
    });

    test('A2 the duplicate may be FIRST, MIDDLE or LAST — all reject', () {
      for (final lines in <List<CartDraftLine>>[
        [
          draftLine(lineId: 'dup'),
          draftLine(lineId: 'dup'),
          draftLine(lineId: 'x'),
        ],
        [
          draftLine(lineId: 'x'),
          draftLine(lineId: 'dup'),
          draftLine(lineId: 'dup'),
        ],
        [
          draftLine(lineId: 'dup'),
          draftLine(lineId: 'x'),
          draftLine(lineId: 'dup'),
        ],
      ]) {
        final c = harness();
        buildActiveCart(c);
        final before = fingerprint(c);
        final result = c
            .read(cartControllerProvider.notifier)
            .restoreDraft(draftWith(lines));
        expect(result, isNot(CartMutationResult.applied));
        expect(fingerprint(c), before);
      }
    });

    test('A3 duplicate ids carrying DIFFERENT products still reject — the '
        'cart must not end up holding whichever one happened to win', () {
      final c = harness();
      buildActiveCart(c);
      final before = fingerprint(c);
      final result = c
          .read(cartControllerProvider.notifier)
          .restoreDraft(
            draftWith([
              draftLine(lineId: 'same'),
              draftLine(
                lineId: 'same',
                menuItemId: 'cola',
                name: 'Cola',
                basePriceMinor: kCola,
                modifiers: const [_extraIce],
              ),
            ]),
          );
      expect(result, isNot(CartMutationResult.applied));
      expect(fingerprint(c), before);
    });

    test(
      'A4 duplicate ids carrying DIFFERENT modifier prices still reject',
      () {
        const cheaper = SelectedModifier(
          optionId: 'opt-120',
          modifierGroupId: 'grp-meat',
          groupName: 'Meat',
          optionName: '120g',
          priceDeltaMinor: 0,
        );
        final c = harness();
        buildActiveCart(c);
        final before = fingerprint(c);
        final result = c
            .read(cartControllerProvider.notifier)
            .restoreDraft(
              draftWith([
                draftLine(lineId: 'same'),
                draftLine(lineId: 'same', modifiers: const [cheaper]),
              ]),
            );
        expect(
          result,
          isNot(CartMutationResult.applied),
          reason: 'a cheaper duplicate must never be the one that survives',
        );
        expect(fingerprint(c), before);
      },
    );

    test('A5 an EMPTY active cart is also left empty by a failed restore', () {
      final c = harness();
      expect(c.read(cartControllerProvider).lines, isEmpty);
      final result = c
          .read(cartControllerProvider.notifier)
          .restoreDraft(
            draftWith([draftLine(lineId: 'dup'), draftLine(lineId: 'dup')]),
          );
      expect(result, isNot(CartMutationResult.applied));
      expect(c.read(cartControllerProvider).lines, isEmpty);
      expect(c.read(cartControllerProvider).subtotalMinor, 0);
    });
  });

  // =========================================================================
  group('[A] a VALID restore still works exactly as before', () {
    test('A6 every line, modifier, note, prep, rank, quantity and total is '
        'restored, and the confirmation is dismissed', () {
      final c = harness();
      buildActiveCart(c);
      final cart = c.read(cartControllerProvider.notifier);

      // Capture the real draft from the real cart, then restore it back.
      final draft = cart.captureDraft();
      final before = fingerprint(c);

      final result = cart.restoreDraft(draft);
      expect(result, CartMutationResult.applied);
      expect(
        fingerprint(c),
        before,
        reason: 'a round trip through capture + restore changes nothing',
      );
      expect(c.read(cartControllerProvider).subtotalMinor, kActiveSubtotal);
      expect(c.read(cartControllerProvider).submittedOrder, isNull);
    });

    test(
      'A7 restoring a DIFFERENT valid draft replaces the cart wholesale',
      () {
        final c = harness();
        buildActiveCart(c);
        final result = c
            .read(cartControllerProvider.notifier)
            .restoreDraft(draftWith([draftLine(lineId: 'r-1', quantity: 3)]));
        expect(result, CartMutationResult.applied);
        final v = c.read(cartControllerProvider);
        expect(v.lines, hasLength(1));
        expect(v.lines.single.lineId, 'r-1');
        expect(v.lines.single.quantity, 3);
        // 3 x (4500 + 1500) = 18000, as an independent literal.
        expect(v.lines.single.lineTotalMinor, 18000);
        expect(v.subtotalMinor, 18000);
      },
    );

    test('A8 a valid restore emits exactly ONE state update', () {
      final c = harness();
      buildActiveCart(c);
      var emits = 0;
      final sub = c.listen(cartControllerProvider, (_, _) => emits++);
      addTearDown(sub.close);

      final result = c
          .read(cartControllerProvider.notifier)
          .restoreDraft(draftWith([draftLine(lineId: 'r-1')]));
      expect(result, CartMutationResult.applied);
      expect(
        emits,
        1,
        reason: 'a partially-applied restore would publish more than once',
      );
    });

    test('A9 a FAILED restore emits NOTHING at all', () {
      final c = harness();
      buildActiveCart(c);
      var emits = 0;
      final sub = c.listen(cartControllerProvider, (_, _) => emits++);
      addTearDown(sub.close);

      c
          .read(cartControllerProvider.notifier)
          .restoreDraft(
            draftWith([draftLine(lineId: 'dup'), draftLine(lineId: 'dup')]),
          );
      expect(
        emits,
        0,
        reason: 'no partially restored state may ever reach the UI',
      );
    });
  });

  // =========================================================================
  group('[A] the DECODER rejects duplicate line ids before restore begins', () {
    Map<String, Object?> lineJson(String lineId) => <String, Object?>{
      'line_id': lineId,
      'menu_item_id': 'burger-meat',
      'name': 'Burger',
      'base_price_minor': kBase,
      'quantity': 1,
    };

    test('A10 a persisted draft with duplicate line ids is corrupt', () {
      expect(
        () => CartDraftSnapshot.fromJson(<String, Object?>{
          'currency_code': 'ILS',
          'lines': <Object?>[
            lineJson('dup'),
            lineJson('other'),
            lineJson('dup'),
          ],
        }),
        throwsA(isA<FormatException>()),
        reason:
            'the quarantine seam must receive this like any other '
            'corruption — no first-wins, no last-wins, no regeneration',
      );
    });

    test('A11 distinct ids still decode, and an absent id is still legacy', () {
      final ok = CartDraftSnapshot.fromJson(<String, Object?>{
        'currency_code': 'ILS',
        'lines': <Object?>[lineJson('a'), lineJson('b')],
      });
      expect(ok.lines, hasLength(2));

      final legacy = CartDraftSnapshot.fromJson(<String, Object?>{
        'currency_code': 'ILS',
        'lines': <Object?>[
          lineJson('a')..remove('line_id'),
          lineJson('b')..remove('line_id'),
        ],
      });
      expect(legacy.lines, hasLength(2));
      expect(legacy.lines.every((l) => l.lineId == null), isTrue);
    });
  });
}
