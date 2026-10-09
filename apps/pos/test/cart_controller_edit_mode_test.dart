import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show BranchTax;
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_edit_baseline.dart';
import 'package:restoflow_pos/src/data/order_edit_diff.dart';
import 'package:restoflow_pos/src/data/order_edit_read_model.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';

import 'support/order_edit_fixtures.dart';

/// ORDER-EDIT-001E — the cart's EDIT MODE (plan step 6, test 10): the edit
/// cart is loaded atomically from a baseline, its sent lines are bound and
/// priced from their stored snapshots, a menu tap never merges into a sent
/// line, trash strikes a sent line (with Undo), "just 1" splits a part, a
/// touched kept option keeps its stored price, the cart refuses every
/// draft-replacing call, the send freeze reuses the owner-token lock, and the
/// view's subtotal is the plan's.
///
/// Every amount is an independent literal (D-007).

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  CartViewState state() => container.read(cartControllerProvider);
  CartController cart() => container.read(cartControllerProvider.notifier);

  // Burger ×3 at 4000 with Cheese +300 (stored) → 4300 × 3 = 12900.
  // Fries ×1 at 1500, plain, note "no salt" → 1500.
  // Cola ×1 at 900, a legacy price → stored 800 (remove only).
  OrderEditBaseline baseline({String status = 'submitted'}) => baselineOf(
    detail(
      items: [
        detailItem(
          'oi-burger',
          menuItemId: 'mi-burger',
          name: 'Burger',
          quantity: 3,
          unit: 4000,
          modifiers: [detailMod('opt-cheese', 'Cheese', price: 300)],
          unitStatus: status,
        ),
        detailItem(
          'oi-fries',
          menuItemId: 'mi-fries',
          name: 'Fries',
          unit: 1500,
          notes: 'no salt',
          unitStatus: status,
        ),
        detailItem(
          'oi-cola',
          menuItemId: 'mi-cola',
          name: 'Cola',
          unit: 900,
          lineTotal: 800,
          legacy: true,
          unitStatus: status,
        ),
      ],
    ),
    menu: menuOf(
      [
        menuItem('mi-burger', name: 'Burger', price: 4200),
        menuItem('mi-fries', name: 'Fries', price: 1500),
        menuItem('mi-cola', name: 'Cola', price: 900),
      ],
      groups: [
        menuGroup('grp-top', 'mi-burger', const [
          PosModifierOptionFixture.cheese,
          PosModifierOptionFixture.bacon,
        ]),
      ],
    ),
  );

  const friesMenu = DemoMenuItem(
    id: 'mi-fries',
    name: 'Fries',
    priceMinor: 1500,
    categoryId: 'cat',
    categoryName: 'Cat',
  );
  const colaMenu = DemoMenuItem(
    id: 'mi-cola',
    name: 'Cola',
    priceMinor: 900,
    categoryId: 'cat',
    categoryName: 'Cat',
  );

  CartEditLoadResult load(OrderEditBaseline b, {int generation = 1}) =>
      cart().loadForEdit(CartEditContext(baseline: b, generation: generation));

  CartLineView line(String id) =>
      state().lines.singleWhere((l) => l.lineId == id);

  group('loadForEdit', () {
    test('loads every sent line bound, in print order, at stored prices', () {
      final b = baseline();
      expect(load(b), CartEditLoadResult.loaded);
      final s = state();
      expect(s.isEditing, isTrue);
      expect(s.editContext!.orderId, 'order-1');
      expect(s.editContext!.orderCode, '#A1B2C3');
      expect(s.editContext!.tableLabel, '4');
      expect(s.lines.map((l) => l.lineId), [
        'sent-oi-burger',
        'sent-oi-fries',
        'sent-oi-cola',
      ]);
      expect(s.lines.map((l) => l.editSourceOrderItemId), [
        'oi-burger',
        'oi-fries',
        'oi-cola',
      ]);
      expect(s.lines.every((l) => !l.editRemoved && !l.editAdded), isTrue);
      expect(line('sent-oi-burger').unitPriceMinor, 4000);
      expect(line('sent-oi-burger').lineTotalMinor, 12900);
      expect(line('sent-oi-burger').modifiers.single.priceDeltaMinor, 300);
      expect(
        line('sent-oi-burger').modifiers.single.modifierGroupId,
        'grp-top',
      );
      expect(line('sent-oi-fries').note, 'no salt');
      // The legacy line keeps its STORED total, not 900.
      expect(line('sent-oi-cola').lineTotalMinor, 800);
      expect(line('sent-oi-cola').editSource!.removeOnly, isTrue);
      // 12900 + 1500 + 800.
      expect(s.subtotalMinor, 15200);
      expect(s.itemCount, 5);
      expect(line('sent-oi-burger').editStage, PosLineStage.waiting);
      expect(s.lockedByAddition, isFalse);
    });

    test('paper lines show Printed', () {
      final b = baselineOf(
        detail(
          channel: PosKitchenChannel.paper,
          items: [detailItem('oi-1', unitStatus: 'submitted')],
        ),
      );
      expect(load(b), CartEditLoadResult.loaded);
      expect(state().lines.single.editStage, PosLineStage.printed);
    });

    test('refuses a cart holding an ordinary draft, untouched', () {
      cart().addItem(friesMenu);
      final before = state();
      expect(load(baseline()), CartEditLoadResult.cartNotEmpty);
      expect(identical(state(), before), isTrue);
      expect(state().isEditing, isFalse);
    });

    test('refuses a locked cart', () {
      const owner = CartLockOwner(
        generation: 1,
        orderId: 'other',
        localOperationId: 'op-x',
      );
      expect(cart().lockForAddition(owner), isTrue);
      expect(load(baseline()), CartEditLoadResult.locked);
      expect(state().isEditing, isFalse);
    });

    test('an invalid replay changes nothing and emits nothing', () {
      final b = baseline();
      load(b);
      final before = state();
      var emits = 0;
      final sub = container.listen(cartControllerProvider, (_, _) => emits++);
      addTearDown(sub.close);
      final burger = b.lineFor('oi-burger')!;
      // A duplicate line id.
      expect(
        cart().loadForEdit(
          CartEditContext(baseline: b, generation: 1),
          replay: [sent(burger), sent(burger)],
        ),
        CartEditLoadResult.invalid,
      );
      // Bound to a sent line the baseline does not have.
      expect(
        cart().loadForEdit(
          CartEditContext(baseline: b, generation: 1),
          replay: [
            OrderEditCartLine(
              sourceOrderItemId: 'oi-gone',
              line: sent(burger).line,
            ),
          ],
        ),
        CartEditLoadResult.invalid,
      );
      // A struck line that is not bound.
      expect(
        cart().loadForEdit(
          CartEditContext(baseline: b, generation: 1),
          replay: [
            OrderEditCartLine(
              removed: true,
              line: added('line-9', 'mi-x').line,
            ),
          ],
        ),
        CartEditLoadResult.invalid,
      );
      expect(identical(state(), before), isTrue);
      expect(emits, 0);
    });

    test('a rebase reload of the SAME order swaps; another order is '
        'refused', () {
      final b = baseline();
      load(b);
      final burger = b.lineFor('oi-burger')!;
      expect(
        cart().loadForEdit(
          CartEditContext(baseline: b, generation: 2),
          replay: [sent(burger, quantity: 1)],
        ),
        CartEditLoadResult.loaded,
      );
      expect(state().lines.single.quantity, 1);
      expect(state().editContext!.generation, 2);

      final other = baselineOf(
        PosOrderDetailFixture.withOrderId(
          detail(items: [detailItem('oi-z')]),
          'order-2',
        ),
      );
      expect(load(other), CartEditLoadResult.cartNotEmpty);
      expect(state().editContext!.orderId, 'order-1');
    });

    test('a replayed bound line is rebuilt from its SOURCE, never from the '
        'replay line', () {
      final b = baseline();
      final burger = b.lineFor('oi-burger')!;
      final forged = OrderEditCartLine(
        sourceOrderItemId: 'oi-burger',
        line: CartLineView(
          lineId: 'sent-oi-burger',
          menuItemId: 'mi-forged',
          name: 'Forged',
          quantity: 3,
          unitPriceMinor: 1,
          lineTotalMinor: 3,
          currencyCode: 'ILS',
          // The kept option at a forged price.
          modifiers: [mod('opt-cheese', 'Cheese', price: 1)],
        ),
      );
      expect(
        cart().loadForEdit(
          CartEditContext(baseline: b, generation: 1),
          replay: [forged, sent(b.lineFor('oi-fries')!)],
        ),
        CartEditLoadResult.loaded,
      );
      final l = line('sent-oi-burger');
      expect(l.menuItemId, burger.menuItemId);
      expect(l.name, 'Burger');
      expect(l.unitPriceMinor, 4000);
      expect(l.modifiers.single.priceDeltaMinor, 300);
      expect(l.lineTotalMinor, 12900);
    });
  });

  group('the no-merge rule', () {
    test('a menu tap never merges into a sent line', () {
      load(baseline());
      expect(cart().addItem(friesMenu), CartMutationResult.applied);
      expect(state().lines, hasLength(4));
      final added = state().lines.last;
      expect(added.lineId, isNot('sent-oi-fries'));
      expect(added.editAdded, isTrue);
      expect(added.editSource, isNull);
      expect(line('sent-oi-fries').quantity, 1);
      // A second tap grows the ADDED line, still never the sent one.
      cart().addItem(friesMenu);
      expect(state().lines, hasLength(4));
      expect(state().lines.last.quantity, 2);
      expect(line('sent-oi-fries').quantity, 1);
      // 15200 + 2 × 1500.
      expect(state().subtotalMinor, 18200);
    });

    test('normal mode still merges a plain line (byte-identical)', () {
      cart().addItem(friesMenu);
      cart().addItem(friesMenu);
      expect(state().lines.single.quantity, 2);
      expect(state().lines.single.editAdded, isFalse);
      expect(state().subtotalMinor, 3000);
    });
  });

  group('strike, undo and delete', () {
    test('decrease at 1 strikes a primary sent line; Undo restores it', () {
      load(baseline());
      cart().decreaseQuantity('sent-oi-fries');
      expect(line('sent-oi-fries').editRemoved, isTrue);
      expect(state().lines, hasLength(3));
      // 15200 − 1500.
      expect(state().subtotalMinor, 13700);
      expect(state().itemCount, 4);
      // A struck line does not move.
      cart().increaseQuantity('sent-oi-fries');
      cart().decreaseQuantity('sent-oi-fries');
      expect(line('sent-oi-fries').quantity, 1);
      expect(cart().undoRemove('sent-oi-fries'), CartMutationResult.applied);
      expect(line('sent-oi-fries').editRemoved, isFalse);
      expect(state().subtotalMinor, 15200);
    });

    test('trash strikes a primary sent line at any quantity', () {
      load(baseline());
      cart().removeLine('sent-oi-burger');
      expect(line('sent-oi-burger').editRemoved, isTrue);
      expect(line('sent-oi-burger').quantity, 3);
      // 15200 − 12900.
      expect(state().subtotalMinor, 2300);
    });

    test('an added line and a split part are deleted, not struck', () {
      load(baseline());
      cart().addItem(colaMenu);
      final addedId = state().lines.last.lineId;
      cart().removeLine(addedId);
      expect(state().lines.any((l) => l.lineId == addedId), isFalse);

      cart().splitForEdit('sent-oi-burger', [mod('opt-bacon', 'Bacon')]);
      expect(line('sent-oi-burger-p1').quantity, 1);
      cart().decreaseQuantity('sent-oi-burger-p1');
      expect(
        state().lines.any((l) => l.lineId == 'sent-oi-burger-p1'),
        isFalse,
      );
    });

    test('a struck line is not edited by the sheet', () {
      load(baseline());
      cart().removeLine('sent-oi-fries');
      cart().updateLineModifiers('sent-oi-fries', const [], note: 'extra');
      cart().updateLineNote('sent-oi-fries', 'extra');
      expect(line('sent-oi-fries').note, 'no salt');
    });
  });

  group('just 1 (splitForEdit)', () {
    test('splits one unit into a bound part right after its line', () {
      load(baseline());
      cart().addItem(colaMenu); // an added line at the end
      expect(
        cart().splitForEdit('sent-oi-burger', const [], note: 'no cheese'),
        CartMutationResult.applied,
      );
      final ids = state().lines.map((l) => l.lineId).toList();
      expect(ids.sublist(0, 2), ['sent-oi-burger', 'sent-oi-burger-p1']);
      expect(line('sent-oi-burger').quantity, 2);
      final part = line('sent-oi-burger-p1');
      expect(part.quantity, 1);
      expect(part.editSourceOrderItemId, 'oi-burger');
      expect(part.modifiers, isEmpty);
      expect(part.note, 'no cheese');
      expect(part.unitPriceMinor, 4000);
      // 2 × 4300 + 1 × 4000 = 12600; + 1500 + 800 + 900 (added Cola).
      expect(state().subtotalMinor, 15800);

      // A second split mints the next part id.
      cart().splitForEdit('sent-oi-burger', [mod('opt-bacon', 'Bacon')]);
      expect(line('sent-oi-burger-p2').quantity, 1);
      expect(line('sent-oi-burger').quantity, 1);
    });

    test('refused (nothing changes) unless a kept bound line has 2+', () {
      load(baseline());
      final before = state();
      expect(
        cart().splitForEdit('sent-oi-fries', const []),
        CartMutationResult.invalidDraft,
      );
      cart().addItem(colaMenu);
      cart().increaseQuantity(state().lines.last.lineId);
      final added = state().lines.last.lineId;
      expect(
        cart().splitForEdit(added, const []),
        CartMutationResult.invalidDraft,
      );
      cart().removeLine('sent-oi-burger');
      expect(
        cart().splitForEdit('sent-oi-burger', const []),
        CartMutationResult.invalidDraft,
      );
      expect(before.lines, hasLength(3));
    });

    test('the part normalizes a kept option to its stored price', () {
      load(baseline());
      cart().splitForEdit('sent-oi-burger', [
        mod('opt-cheese', 'Cheese (live)', price: 450, quantity: 2),
      ]);
      final m = line('sent-oi-burger-p1').modifiers.single;
      expect(m.priceDeltaMinor, 300);
      expect(m.optionName, 'Cheese');
      expect(m.quantity, 2);
      // 4000 + 300 × 2.
      expect(line('sent-oi-burger-p1').lineTotalMinor, 4600);
    });
  });

  group('updateLineModifiers on a bound line', () {
    test('a kept option keeps its STORED price; a new one its own; the '
        'quantity is ignored', () {
      load(baseline());
      cart().updateLineModifiers('sent-oi-burger', [
        mod('OPT-CHEESE', 'Cheese (live)', price: 450),
        mod('opt-bacon', 'Bacon', price: 500),
      ], quantity: 7);
      final l = line('sent-oi-burger');
      expect(l.quantity, 3);
      expect(l.modifiers.map((m) => m.optionId), ['opt-cheese', 'opt-bacon']);
      expect(l.modifiers.first.priceDeltaMinor, 300);
      expect(l.modifiers.first.optionName, 'Cheese');
      expect(l.modifiers.last.priceDeltaMinor, 500);
      // 3 × (4000 + 300 + 500).
      expect(l.lineTotalMinor, 14400);
    });

    test('re-saving the same note keeps the stored one verbatim (no '
        'change)', () {
      final b = baselineOf(
        detail(items: [detailItem('oi-1', notes: 'no salt  ', quantity: 2)]),
      );
      load(b);
      cart().updateLineModifiers('sent-oi-1', const [], note: ' no salt ');
      expect(line('sent-oi-1').note, 'no salt  ');
      cart().updateLineNote('sent-oi-1', 'no salt');
      expect(line('sent-oi-1').note, 'no salt  ');
      final plan = planOrderEdit(b, state().editLines, tax: BranchTax.disabled);
      expect(plan.noChanges, isTrue);
      cart().updateLineNote('sent-oi-1', '  extra salt ');
      expect(line('sent-oi-1').note, 'extra salt');
    });
  });

  group('the cart is not a free draft in edit mode', () {
    test('clear, restore, submit and new order refuse with lockedByEdit', () {
      load(baseline());
      final before = state();
      expect(cart().clear(), CartMutationResult.lockedByEdit);
      expect(
        cart().restoreDraft(
          const CartDraftSnapshot(currencyCode: 'ILS', lines: []),
        ),
        CartMutationResult.lockedByEdit,
      );
      expect(cart().submitOrder(), CartMutationResult.lockedByEdit);
      expect(cart().startNewOrder(), CartMutationResult.lockedByEdit);
      expect(identical(state(), before), isTrue);
    });

    test('quantity stops at 999 in edit mode only', () {
      load(baseline());
      final burger = baseline().lineFor('oi-burger')!;
      cart().loadForEdit(
        CartEditContext(baseline: baseline(), generation: 1),
        replay: [sent(burger, quantity: 998)],
      );
      cart().increaseQuantity('sent-oi-burger');
      cart().increaseQuantity('sent-oi-burger');
      expect(line('sent-oi-burger').quantity, 999);
    });
  });

  group('the send freeze and the end of edit mode', () {
    const owner = CartLockOwner(
      generation: 1,
      orderId: 'order-1',
      localOperationId: 'op-1',
    );

    test('the owner-token lock refuses every mutation and exit', () {
      load(baseline());
      expect(cart().lockForAddition(owner), isTrue);
      expect(state().lockedByAddition, isTrue);
      expect(cart().addItem(friesMenu), CartMutationResult.lockedByAddition);
      expect(
        cart().removeLine('sent-oi-fries'),
        CartMutationResult.lockedByAddition,
      );
      expect(
        cart().splitForEdit('sent-oi-burger', const []),
        CartMutationResult.lockedByAddition,
      );
      expect(
        cart().undoRemove('sent-oi-fries'),
        CartMutationResult.lockedByAddition,
      );
      expect(cart().exitEdit(), isFalse);
      expect(state().isEditing, isTrue);
    });

    test('finishEdit fails closed on a foreign token, clears on the owner', () {
      load(baseline());
      cart().lockForAddition(owner);
      const foreign = CartLockOwner(
        generation: 1,
        orderId: 'order-1',
        localOperationId: 'op-2',
      );
      expect(cart().finishEdit(foreign), isFalse);
      expect(state().isEditing, isTrue);
      expect(cart().finishEdit(owner), isTrue);
      expect(state().isEditing, isFalse);
      expect(state().isEmpty, isTrue);
      expect(state().lockedByAddition, isFalse);
      // Normal editing resumes, merging as before.
      cart().addItem(friesMenu);
      cart().addItem(friesMenu);
      expect(state().lines.single.quantity, 2);
    });

    test('finishEdit outside edit mode is refused', () {
      cart().lockForAddition(owner);
      expect(cart().finishEdit(owner), isFalse);
      expect(state().lockedByAddition, isTrue);
    });

    test('exitEdit (unsent) empties the cart and leaves edit mode', () {
      load(baseline());
      cart().addItem(friesMenu);
      expect(cart().exitEdit(), isTrue);
      expect(state().isEditing, isFalse);
      expect(state().isEmpty, isTrue);
      expect(cart().exitEdit(), isFalse);
    });
  });

  group('the view subtotal is the plan subtotal', () {
    test('across removes, splits, modifies, increases and adds', () {
      final b = baseline();
      load(b);
      void expectPlanned() {
        final plan = planOrderEdit(
          b,
          state().editLines,
          tax: BranchTax.disabled,
        );
        expect(state().subtotalMinor, plan.subtotalMinor);
        expect(
          state().subtotalMinor,
          orderEditSubtotalMinor(b, state().editLines),
        );
      }

      expectPlanned();
      cart().increaseQuantity('sent-oi-fries');
      expectPlanned();
      cart().splitForEdit('sent-oi-burger', [
        mod('opt-bacon', 'Bacon', price: 500),
      ]);
      expectPlanned();
      cart().removeLine('sent-oi-cola');
      expectPlanned();
      cart().addItem(colaMenu);
      expectPlanned();
      // 2 × 4300 + 4500 (part) + 2 × 1500 + 900 (added) = 17000.
      expect(state().subtotalMinor, 17000);
      final plan = planOrderEdit(
        b,
        cart().editLines(),
        tax: BranchTax.disabled,
      );
      expect(plan.changes.map((c) => c['op']), [
        'modify',
        'set_quantity',
        'remove',
        'add',
      ]);
    });
  });
}

/// Fixture menu options for the burger's topping group.
abstract final class PosModifierOptionFixture {
  static const cheese = PosModifierOption(
    id: 'opt-cheese',
    name: 'Cheese',
    priceDeltaMinor: 450,
  );
  static const bacon = PosModifierOption(
    id: 'opt-bacon',
    name: 'Bacon',
    priceDeltaMinor: 500,
  );
}

/// The fixture detail under another order id.
abstract final class PosOrderDetailFixture {
  static PosOrderDetail withOrderId(PosOrderDetail d, String orderId) =>
      PosOrderDetail(
        orderId: orderId,
        orderCode: d.orderCode,
        orderType: d.orderType,
        status: d.status,
        revision: d.revision,
        currencyCode: d.currencyCode,
        subtotalMinor: d.subtotalMinor,
        discountTotalMinor: d.discountTotalMinor,
        taxTotalMinor: d.taxTotalMinor,
        grandTotalMinor: d.grandTotalMinor,
        items: d.items,
        rounds: d.rounds,
        tableLabel: d.tableLabel,
        kitchenChannel: d.kitchenChannel,
        branchFeatures: d.branchFeatures,
      );
}
