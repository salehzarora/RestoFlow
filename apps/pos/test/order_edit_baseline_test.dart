import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_edit_baseline.dart';
import 'package:restoflow_pos/src/data/order_edit_read_model.dart';
import 'package:restoflow_pos/src/data/staff_capabilities.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';

import 'support/order_edit_fixtures.dart';

/// ORDER-EDIT-001E — the edit BASELINE (plan step 4a, test 6): the eligibility
/// verdict mirrors `app.edit_order` step 5 and fails closed; every live line
/// keeps its stored money, its stage and its remove-only / keep-or-remove-only
/// / "+" flags.

PosOrderDetail _detail({
  String orderType = 'dine_in',
  String status = 'preparing',
  PosKitchenChannel? channel = PosKitchenChannel.kds,
  PosBranchFeatures? features = kFeaturesOn,
  bool paid = false,
  List<PosOrderDetailItem>? items,
}) => detail(
  orderType: orderType,
  status: status,
  channel: channel,
  features: features,
  paid: paid,
  items: items ?? [detailItem('oi-1')],
);

OrderEditIneligibility? _verdict(PosOrderDetail d, {PosMenuData? menu}) =>
    OrderEditBaseline.fromDetail(d, menu: menu).ineligibility;

void main() {
  group('eligibility verdict (edit_order step 5)', () {
    for (final type in ['dine_in', 'takeaway']) {
      for (final status in kOrderEditableStatuses) {
        test('$type / $status is editable', () {
          final v = OrderEditBaseline.fromDetail(
            _detail(orderType: type, status: status),
          );
          expect(v.isEligible, isTrue);
          expect(v.ineligibility, isNull);
          expect(v.baseline!.lines, hasLength(1));
        });
      }
    }

    test('the switch OFF, or UNKNOWN, is feature_disabled', () {
      expect(
        _verdict(
          _detail(
            features: const PosBranchFeatures(
              orderEditEnabled: false,
              finishedFoodManagerOnly: false,
            ),
          ),
        ),
        OrderEditIneligibility.featureDisabled,
      );
      expect(
        _verdict(_detail(features: null)),
        OrderEditIneligibility.featureDisabled,
        reason: 'an unknown rollout gate hides the entry (§4.30b)',
      );
    });

    test('a type outside dine-in / takeaway is not editable', () {
      expect(
        _verdict(_detail(orderType: 'delivery')),
        OrderEditIneligibility.notEditable,
      );
    });

    for (final status in ['pending', 'completed', 'voided', 'cancelled', '']) {
      test('status "$status" is not editable', () {
        expect(
          _verdict(_detail(status: status)),
          OrderEditIneligibility.notEditable,
        );
      });
    }

    test('a live completed payment is order_already_settled', () {
      expect(_verdict(_detail(paid: true)), OrderEditIneligibility.alreadyPaid);
    });

    test('an unresolvable kitchen channel is kitchen_mode_changed', () {
      expect(
        _verdict(_detail(channel: null)),
        OrderEditIneligibility.kitchenModeChanged,
      );
    });

    test('a line or an option without a server identity fails closed', () {
      expect(
        _verdict(_detail(items: [detailItem('oi-1', identified: false)])),
        OrderEditIneligibility.unidentifiedLine,
      );
      expect(
        _verdict(
          _detail(
            items: [
              detailItem(
                'oi-1',
                modifiers: [
                  const PosOrderDetailModifier(
                    optionName: 'Cheese',
                    priceMinor: 300,
                    quantity: 1,
                  ),
                ],
              ),
            ],
          ),
        ),
        OrderEditIneligibility.unidentifiedLine,
        reason: 'modifier_option_id is NOT NULL server-side',
      );
    });

    test('the checks run in step-5 order', () {
      expect(
        _verdict(
          _detail(
            features: null,
            status: 'completed',
            paid: true,
            channel: null,
          ),
        ),
        OrderEditIneligibility.featureDisabled,
      );
      expect(
        _verdict(_detail(status: 'completed', paid: true, channel: null)),
        OrderEditIneligibility.notEditable,
      );
      expect(
        _verdict(_detail(paid: true, channel: null)),
        OrderEditIneligibility.alreadyPaid,
      );
    });
  });

  group('source lines', () {
    final menu = menuOf(
      [menuItem('mi-burger'), menuItem('mi-cola', unavailable: true)],
      groups: [
        menuGroup('grp-top', 'mi-burger', const [
          PosModifierOption(
            id: 'opt-tomato',
            name: 'Tomato',
            priceDeltaMinor: 0,
          ),
          PosModifierOption(
            id: 'opt-cheese',
            name: 'Cheese',
            priceDeltaMinor: 500,
          ),
        ]),
      ],
    );

    test('keep the server order, ids and stored money', () {
      final b = baselineOf(
        _detail(
          items: [
            detailItem(
              'oi-b',
              menuItemId: 'mi-burger',
              quantity: 2,
              unit: 4000,
              modifiers: [detailMod('OPT-CHEESE', 'Cheese', price: 300)],
              notes: 'no salt',
            ),
            detailItem('oi-c', menuItemId: 'mi-cola', unit: 800),
          ],
        ),
        menu: menu,
      );
      expect(b.lines.map((l) => l.orderItemId), ['oi-b', 'oi-c']);
      final burger = b.lines.first;
      expect(burger.unitPriceMinor, 4000);
      expect(
        burger.configuredUnitMinor,
        4300,
        reason: 'the STORED option price (300), never the live 500',
      );
      expect(burger.lineTotalMinor, 8600);
      expect(burger.storedPriceOf('opt-cheese'), 300);
      expect(burger.storedPriceOf('opt-tomato'), isNull);
      expect(burger.notes, 'no salt');
      expect(b.liveSubtotalMinor, 9400);
      expect(b.orderCode, '#A1B2C3');
    });

    test('the live subtotal is the sum of live lines, not the header', () {
      final b = baselineOf(
        detail(
          items: [
            detailItem('oi-1', unit: 1200),
            detailItem('oi-2', unit: 300),
          ],
          subtotal: 99999,
        ),
      );
      expect(b.liveSubtotalMinor, 1500);
    });

    test('the option is attributed to its UNIQUE live group by id', () {
      final b = baselineOf(
        _detail(
          items: [
            detailItem(
              'oi-b',
              menuItemId: 'mi-burger',
              modifiers: [detailMod('OPT-TOMATO', 'Tomato')],
            ),
          ],
        ),
        menu: menu,
      );
      final m = b.lines.single.modifiers.single;
      expect(m.groupId, 'grp-top');
      final selected = m.toSelectedModifier();
      expect(selected.modifierGroupId, 'grp-top');
      expect(selected.priceDeltaMinor, 0);
      expect(selected.groupName, 'Toppings');
      expect(b.lines.single.keepOrRemoveOnly, isFalse);
    });

    test('an option offered by two groups cannot be attributed', () {
      final ambiguous = menuOf(
        [menuItem('mi-burger')],
        groups: [
          menuGroup('g1', 'mi-burger', const [
            PosModifierOption(id: 'opt-x', name: 'X', priceDeltaMinor: 0),
          ]),
          menuGroup('g2', 'mi-burger', const [
            PosModifierOption(id: 'opt-x', name: 'X', priceDeltaMinor: 0),
          ]),
        ],
      );
      final line = baselineOf(
        _detail(
          items: [
            detailItem(
              'oi-b',
              menuItemId: 'mi-burger',
              modifiers: [detailMod('opt-x', 'X')],
            ),
          ],
        ),
        menu: ambiguous,
      ).lines.single;
      expect(line.modifiers.single.groupId, isNull);
      expect(line.keepOrRemoveOnly, isTrue);
    });
  });

  group('line flags', () {
    OrderEditSourceLine line(
      PosOrderDetailItem item, {
      PosMenuData? menu,
      PosKitchenChannel channel = PosKitchenChannel.kds,
    }) => baselineOf(
      _detail(items: [item], channel: channel),
      menu: menu,
    ).lines.single;

    final menu = menuOf(
      [menuItem('mi-1'), menuItem('mi-sold-out', unavailable: true)],
      groups: [
        menuGroup('g', 'mi-1', const [
          PosModifierOption(id: 'opt-a', name: 'A', priceDeltaMinor: 100),
        ]),
      ],
    );

    test('legacy null counts as legacy: remove only', () {
      final l = line(
        detailItem('oi', menuItemId: 'mi-1', legacy: null),
        menu: menu,
      );
      expect(l.isLegacy, isTrue);
      expect(l.removeOnly, isTrue);
    });

    test('legacy true: remove only', () {
      expect(
        line(
          detailItem('oi', menuItemId: 'mi-1', legacy: true),
          menu: menu,
        ).removeOnly,
        isTrue,
      );
    });

    test('a line discount: remove only', () {
      final l = line(
        detailItem('oi', menuItemId: 'mi-1', unit: 1000, lineDiscount: 200),
        menu: menu,
      );
      expect(l.hasLineDiscount, isTrue);
      expect(l.removeOnly, isTrue);
      expect(l.lineTotalMinor, 800);
    });

    test('a current, undiscounted line is fully editable', () {
      final l = line(
        detailItem(
          'oi',
          menuItemId: 'mi-1',
          modifiers: [detailMod('opt-a', 'A', price: 100)],
        ),
        menu: menu,
      );
      expect(l.removeOnly, isFalse);
      expect(l.keepOrRemoveOnly, isFalse);
      expect(l.increaseBlocked, isFalse);
    });

    test('the item left the menu: keep or remove only, no "+"', () {
      final l = line(detailItem('oi', menuItemId: 'mi-gone'), menu: menu);
      expect(l.keepOrRemoveOnly, isTrue);
      expect(l.increaseBlocked, isTrue);
    });

    test('an option left the menu: keep or remove only', () {
      final l = line(
        detailItem(
          'oi',
          menuItemId: 'mi-1',
          modifiers: [detailMod('opt-gone', 'Gone')],
        ),
        menu: menu,
      );
      expect(l.keepOrRemoveOnly, isTrue);
    });

    test('no menu proves nothing: every line is keep or remove only', () {
      final l = line(detailItem('oi', menuItemId: 'mi-1'));
      expect(l.keepOrRemoveOnly, isTrue);
    });

    test('an unavailable item withholds "+" only', () {
      final l = line(detailItem('oi', menuItemId: 'mi-sold-out'), menu: menu);
      expect(l.increaseBlocked, isTrue);
      expect(l.keepOrRemoveOnly, isFalse);
      expect(l.removeOnly, isFalse);
    });

    const stages = <String, PosLineStage?>{
      'submitted': PosLineStage.waiting,
      'accepted': PosLineStage.inKitchen,
      'preparing': PosLineStage.inKitchen,
      'ready': PosLineStage.ready,
      'served': PosLineStage.served,
      'mystery': null,
    };
    stages.forEach((status, stage) {
      test('KDS unit "$status" shows $stage', () {
        expect(line(detailItem('oi', unitStatus: status)).stage, stage);
      });
      test('paper unit "$status" shows Printed', () {
        expect(
          line(
            detailItem('oi', unitStatus: status),
            channel: PosKitchenChannel.paper,
          ).stage,
          PosLineStage.printed,
        );
      });
    });

    test('waiting and finished are KDS-only notions', () {
      final waiting = line(detailItem('oi', unitStatus: 'submitted'));
      expect(waiting.isWaitingOnKds, isTrue);
      expect(waiting.isFinishedOnKds, isFalse);
      for (final s in ['ready', 'served']) {
        expect(line(detailItem('oi', unitStatus: s)).isFinishedOnKds, isTrue);
        final paper = line(
          detailItem('oi', unitStatus: s),
          channel: PosKitchenChannel.paper,
        );
        expect(paper.isFinishedOnKds, isFalse);
        expect(paper.isWaitingOnKds, isFalse);
      }
    });
  });

  group('manager needed (step 7)', () {
    OrderEditBaseline b({
      bool switchOn = true,
      PosKitchenChannel channel = PosKitchenChannel.kds,
      String unitStatus = 'ready',
    }) => baselineOf(
      detail(
        channel: channel,
        features: PosBranchFeatures(
          orderEditEnabled: true,
          finishedFoodManagerOnly: switchOn,
        ),
        items: [detailItem('oi', unitStatus: unitStatus)],
      ),
    );

    PosStaffCapabilities role(String? r) => PosStaffCapabilities(
      applyDiscount: true,
      applyFullComp: false,
      role: r,
    );

    test('a cashier on a Ready / Served KDS line with the switch ON', () {
      for (final s in ['ready', 'served']) {
        final base = b(unitStatus: s);
        expect(
          base.needsManagerFor(base.lines.single, role('cashier')),
          isTrue,
        );
      }
    });

    test('never for a manager, an unknown role, the switch OFF, earlier '
        'stages or paper', () {
      final base = b();
      final l = base.lines.single;
      expect(base.needsManagerFor(l, role('manager')), isFalse);
      expect(base.needsManagerFor(l, role(null)), isFalse);
      expect(base.needsManagerFor(l, null), isFalse);
      final off = b(switchOn: false);
      expect(off.needsManagerFor(off.lines.single, role('cashier')), isFalse);
      final early = b(unitStatus: 'preparing');
      expect(
        early.needsManagerFor(early.lines.single, role('cashier')),
        isFalse,
      );
      final paper = b(channel: PosKitchenChannel.paper);
      expect(
        paper.needsManagerFor(paper.lines.single, role('cashier')),
        isFalse,
      );
    });
  });
}
