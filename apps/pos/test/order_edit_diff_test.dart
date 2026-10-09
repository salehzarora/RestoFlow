import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show BranchTax;
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenMeat, KitchenPrepComponent;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_edit_baseline.dart';
import 'package:restoflow_pos/src/data/order_edit_diff.dart';
import 'package:restoflow_pos/src/data/order_edit_read_model.dart';
import 'package:restoflow_pos/src/data/staff_capabilities.dart';
import 'package:restoflow_pos/src/state/addition_controller.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';

import 'support/order_edit_fixtures.dart';

/// ORDER-EDIT-001E — the DIFF ENGINE (plan step 4b, test 7).
///
/// Every expected amount is an INDEPENDENT LITERAL, worked out by hand from the
/// server rule (`app.edit_order`, MONEY_AND_TAX_SPEC §9.2 M1–M13), never
/// recomputed with the engine's own helpers. The final group is a property
/// test against a Dart port of `edit_order`'s plan rules (design §10, "applying
/// diff(baseline, cart) reproduces the cart; totals equal the server rule").

// The design's worked example (ORDER_EDIT_DESIGN.md §9.1): Burger 4000 with
// two free options, Fries 1500, Cola 800 — subtotal 6300.
PosOrderDetail _example({
  String burgerStatus = 'preparing',
  int burgerQty = 1,
  int discount = 0,
  int? tax,
  PosKitchenChannel channel = PosKitchenChannel.kds,
  PosBranchFeatures features = kFeaturesOn,
}) => detail(
  channel: channel,
  features: features,
  discount: discount,
  tax: tax,
  items: [
    detailItem(
      'oi-burger',
      menuItemId: 'mi-burger',
      name: 'Burger',
      quantity: burgerQty,
      unit: 4000,
      unitStatus: burgerStatus,
      modifiers: [
        detailMod('opt-tomato', 'Tomato'),
        detailMod('opt-cucumber', 'Cucumber'),
      ],
    ),
    detailItem('oi-fries', menuItemId: 'mi-fries', name: 'Fries', unit: 1500),
    detailItem('oi-cola', menuItemId: 'mi-cola', name: 'Cola', unit: 800),
  ],
);

OrderEditSourceLine _line(OrderEditBaseline b, String id) => b.lineFor(id)!;

OrderEditPlan _plan(
  OrderEditBaseline b,
  List<OrderEditCartLine> cart, {
  BranchTax tax = BranchTax.disabled,
  PosStaffCapabilities? caps,
  Map<String, List<KitchenPrepComponent>> prep =
      const <String, List<KitchenPrepComponent>>{},
}) => planOrderEdit(b, cart, tax: tax, capabilities: caps, prepByItemId: prep);

/// [untouched] with the line for [id] replaced by [replacement] (or dropped).
List<OrderEditCartLine> _with(
  OrderEditBaseline b,
  String id,
  List<OrderEditCartLine> replacement,
) => [
  for (final s in b.lines)
    if (s.orderItemId == id) ...replacement else sent(s),
];

PosStaffCapabilities _caps({
  bool fullComp = false,
  bool? voidOrder = true,
  String role = 'cashier',
}) => PosStaffCapabilities(
  applyDiscount: true,
  applyFullComp: fullComp,
  voidOrder: voidOrder,
  role: role,
);

const _tomato = SelectedModifier(
  optionId: 'opt-tomato',
  groupName: 'Toppings',
  optionName: 'Tomato',
  priceDeltaMinor: 0,
);
const _cucumber = SelectedModifier(
  optionId: 'opt-cucumber',
  groupName: 'Toppings',
  optionName: 'Cucumber',
  priceDeltaMinor: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('no change', () {
    test('the untouched cart plans nothing', () {
      final b = baselineOf(_example());
      final p = _plan(b, untouched(b));
      expect(p.changes, isEmpty);
      expect(p.noChanges, isTrue);
      expect(p.subtotalMinor, 6300);
      expect(p.grandMinor, 6300);
      expect(p.deltaMinor, 0);
      expect(p.hasRemoving, isFalse);
      expect(orderEditSendBlock(p, online: true), OrderEditSendBlock.noChanges);
    });

    test('+1 then −1 (and the options re-listed in another order) is no '
        'change', () {
      final b = baselineOf(_example());
      final burger = _line(b, 'oi-burger');
      final p = _plan(
        b,
        _with(b, 'oi-burger', [
          sent(burger, quantity: 1, modifiers: const [_cucumber, _tomato]),
        ]),
      );
      expect(p.changes, isEmpty);
    });

    test('a spaces-only note on a note-less line is no change (btrim)', () {
      final b = baselineOf(_example());
      final p = _plan(
        b,
        _with(b, 'oi-cola', [sent(_line(b, 'oi-cola'), note: '   ')]),
      );
      expect(p.changes, isEmpty);
    });
  });

  group('remove / set_quantity', () {
    test('remove: the exact wire change, the line total subtracted', () {
      final b = baselineOf(_example());
      for (final cart in [
        _with(b, 'oi-fries', [sent(_line(b, 'oi-fries'), removed: true)]),
        _with(b, 'oi-fries', const []),
      ]) {
        final p = _plan(b, cart);
        expect(p.changes, [
          {'op': 'remove', 'order_item_id': 'oi-fries'},
        ]);
        expect(p.subtotalMinor, 4800);
        expect(p.grandMinor, 4800);
        expect(p.deltaMinor, -1500);
        expect(p.hasRemoving, isTrue);
        expect(p.plannedChanges.single.kind, OrderEditChangeKind.remove);
        expect(p.plannedChanges.single.totalAfterMinor, 0);
        expect(
          orderEditSendBlock(p, online: true),
          OrderEditSendBlock.reasonRequired,
        );
      }
    });

    test('increase: set_quantity, stored total + the added units, no '
        'reason', () {
      final b = baselineOf(_example());
      final p = _plan(
        b,
        _with(b, 'oi-cola', [sent(_line(b, 'oi-cola'), quantity: 3)]),
      );
      expect(p.changes, [
        {'op': 'set_quantity', 'order_item_id': 'oi-cola', 'quantity': 3},
      ]);
      expect(p.plannedChanges.single.kind, OrderEditChangeKind.increase);
      expect(p.plannedChanges.single.totalAfterMinor, 2400);
      expect(p.subtotalMinor, 7900);
      expect(p.hasRemoving, isFalse);
      expect(orderEditSendBlock(p, online: true), isNull);
      expect(buildOrderEditPayload(p).containsKey('reason_code'), isFalse);
    });

    test('reduce: set_quantity, the remainder at the configured unit', () {
      final b = baselineOf(
        detail(
          items: [
            detailItem(
              'oi-wings',
              quantity: 3,
              unit: 1000,
              modifiers: [detailMod('opt-dip', 'Dip', price: 200)],
            ),
          ],
        ),
      );
      final p = _plan(b, [sent(_line(b, 'oi-wings'), quantity: 1)]);
      expect(p.changes, [
        {'op': 'set_quantity', 'order_item_id': 'oi-wings', 'quantity': 1},
      ]);
      expect(p.plannedChanges.single.kind, OrderEditChangeKind.reduce);
      expect(p.subtotalMinor, 1200);
      expect(p.hasRemoving, isTrue);
    });
  });

  group('modify', () {
    test('all N: one replacement; a kept option is id + quantity only, a new '
        'option carries its full snapshot; no item prep_snapshot', () {
      final b = baselineOf(_example(burgerQty: 2));
      final burger = _line(b, 'oi-burger');
      const cheese = SelectedModifier(
        optionId: 'opt-cheese',
        groupName: 'Extras',
        optionName: 'Cheese',
        priceDeltaMinor: 300,
        kitchenMeat: KitchenMeat(
          quantity: 1,
          unit: 'pc',
          classifierOptionId: 'opt-cucumber',
          classifierOptionName: 'Cucumber',
        ),
      );
      final p = _plan(
        b,
        _with(b, 'oi-burger', [
          sent(burger, modifiers: const [_cucumber, cheese]),
        ]),
      );
      expect(p.changes, [
        {
          'op': 'modify',
          'order_item_id': 'oi-burger',
          'replacements': [
            {
              'quantity': 2,
              'notes': null,
              'modifiers': [
                {'modifier_option_id': 'opt-cucumber', 'quantity': 1},
                {
                  'modifier_option_id': 'opt-cheese',
                  'option_name_snapshot': 'Cheese',
                  'modifier_name_snapshot': 'Extras',
                  'price_minor_snapshot': 300,
                  'quantity': 1,
                  'meat_snapshot': {
                    'quantity': 1,
                    'unit': 'pc',
                    'classifier_option_id': 'opt-cucumber',
                    'classifier_option_name': 'Cucumber',
                    'classifier_selected': true,
                  },
                },
              ],
            },
          ],
        },
      ]);
      expect(p.subtotalMinor, 10900); // 2 × 4300 + 1500 + 800
      expect(p.hasRemoving, isTrue);
    });

    test('"just 1 of 3" is [{2, original}, {1, new}], whatever the row '
        'order', () {
      final b = baselineOf(_example(burgerQty: 3));
      final burger = _line(b, 'oi-burger');
      final primary = sent(burger, quantity: 2);
      final one = part(burger, 1, quantity: 1, modifiers: const [_cucumber]);
      for (final rows in [
        [primary, one],
        [one, primary],
      ]) {
        final p = _plan(b, _with(b, 'oi-burger', rows));
        expect(p.changes.single, {
          'op': 'modify',
          'order_item_id': 'oi-burger',
          'replacements': [
            {
              'quantity': 2,
              'notes': null,
              'modifiers': [
                {'modifier_option_id': 'opt-tomato', 'quantity': 1},
                {'modifier_option_id': 'opt-cucumber', 'quantity': 1},
              ],
            },
            {
              'quantity': 1,
              'notes': null,
              'modifiers': [
                {'modifier_option_id': 'opt-cucumber', 'quantity': 1},
              ],
            },
          ],
        });
        expect(p.subtotalMinor, 14300); // 3 × 4000 + 1500 + 800
        expect(p.plannedChanges.single.quantityAfter, 3);
      }
    });

    test('a split edited back to the original coalesces to no change', () {
      final b = baselineOf(_example(burgerQty: 3));
      final burger = _line(b, 'oi-burger');
      final p = _plan(
        b,
        _with(b, 'oi-burger', [
          sent(burger, quantity: 2),
          part(burger, 1, quantity: 1, modifiers: const [_cucumber, _tomato]),
        ]),
      );
      expect(p.changes, isEmpty);
    });

    test('a note-only change is a modify with the trimmed note', () {
      final b = baselineOf(_example());
      final p = _plan(
        b,
        _with(b, 'oi-burger', [
          sent(_line(b, 'oi-burger'), note: '  no salt  '),
        ]),
      );
      expect(p.changes.single, {
        'op': 'modify',
        'order_item_id': 'oi-burger',
        'replacements': [
          {
            'quantity': 1,
            'notes': 'no salt',
            'modifiers': [
              {'modifier_option_id': 'opt-tomato', 'quantity': 1},
              {'modifier_option_id': 'opt-cucumber', 'quantity': 1},
            ],
          },
        ],
      });
      expect(p.subtotalMinor, 6300);
    });

    test('dishes beyond the old quantity are excess; only the old dishes a '
        'changed replacement takes are remade', () {
      final b = baselineOf(_example(burgerQty: 2, burgerStatus: 'ready'));
      final burger = _line(b, 'oi-burger');
      final p = _plan(
        b,
        _with(b, 'oi-burger', [
          sent(burger, quantity: 1),
          part(burger, 1, quantity: 3, modifiers: const [_cucumber]),
        ]),
      );
      final change = p.plannedChanges.single;
      expect(change.kind, OrderEditChangeKind.modify);
      expect(change.quantityBefore, 2);
      expect(change.quantityAfter, 4);
      // Continuation takes 1 old dish; the changed replacement takes the one
      // left (REMAKE) and its other 2 dishes are new.
      expect(change.remakeDishes, 1);
      expect(p.remakeCount, 1);
      expect(change.totalAfterMinor, 16000);
      expect(p.subtotalMinor, 18300);
      expect(p.needsFinishedFoodConfirm, isTrue);
    });

    test('kept options are charged their STORED price, never the live one', () {
      final b = baselineOf(
        detail(
          items: [
            detailItem(
              'oi-burger',
              menuItemId: 'mi-burger',
              quantity: 2,
              unit: 4000,
              modifiers: [
                detailMod('opt-cheese', 'Cheese', price: 300),
                detailMod('opt-bacon', 'Bacon', price: 700),
              ],
            ),
          ],
        ),
      );
      final burger = _line(b, 'oi-burger');
      // The sheet re-priced the touched Cheese at today's 450.
      final p = _plan(b, [
        sent(burger, modifiers: [mod('opt-cheese', 'Cheese', price: 450)]),
      ]);
      expect(p.subtotalMinor, 8600); // 2 × (4000 + 300), not 2 × 4450
      expect((p.changes.single['replacements'] as List).single, {
        'quantity': 2,
        'notes': null,
        'modifiers': [
          {'modifier_option_id': 'opt-cheese', 'quantity': 1},
        ],
      });
      expect(
        orderEditLineTotalMinor(
          source: burger,
          quantity: 2,
          modifiers: [mod('opt-cheese', 'Cheese', price: 450)],
          unitPriceMinor: 4000,
          note: null,
        ),
        8600,
      );
    });
  });

  group('add', () {
    test('identical to the REAL Add-items serializer '
        '(AdditionController._serializeLines)', () async {
      const lemonade = <String, dynamic>{
        'prep_components': [
          {'name': 'Glass', 'quantity': 1, 'unit': ''},
          {
            'name': 'Mint',
            'quantity': 2,
            'unit': 'g',
            'classifier_option_id': 'opt-mint',
            'classifier_option_name': 'Mint',
          },
        ],
      };
      final item = menuItem(
        'mi-lemonade',
        name: 'Lemonade',
        price: 900,
      ).copyWith(attributes: lemonade);
      const mint = SelectedModifier(
        optionId: 'opt-mint',
        groupName: 'Extras',
        optionName: 'Mint',
        priceDeltaMinor: 150,
        quantity: 2,
        kitchenMeat: KitchenMeat(quantity: 1, unit: 'leaf'),
      );
      final transport = _CapturingTransport();
      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posAuthTransportProvider.overrideWithValue(transport),
          posSyncSessionProvider.overrideWithValue(
            const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
          ),
          orderDetailRepositoryProvider.overrideWithValue(_DetailRepo()),
          orderSnapshotRepositoryProvider.overrideWithValue(
            DemoOrderSnapshotRepository(),
          ),
          posSyncPollIntervalProvider.overrideWithValue(null),
          posMenuProvider.overrideWith((ref) async => menuOf([item])),
        ],
      );
      addTearDown(c.dispose);
      await c.read(posMenuProvider.future);
      expect(
        await c.read(additionControllerProvider.notifier).enterForOrder('o-1'),
        AdditionEntryResult.entered,
      );
      c
          .read(cartControllerProvider.notifier)
          .addItemWithModifiers(
            item,
            const [mint],
            note: 'no sugar',
            quantity: 2,
          );
      final cartLine = c.read(cartControllerProvider).lines.single;
      await c.read(additionControllerProvider.notifier).submit();
      final wire = transport.itemsAdd.single;

      final b = baselineOf(_example());
      final p = _plan(
        b,
        [...untouched(b), OrderEditCartLine(line: cartLine)],
        prep: {item.id: item.prepComponents},
      );
      expect(p.changes.single['op'], 'add');
      expect(
        jsonEncode(p.changes.single['item']),
        jsonEncode(wire),
        reason: 'an added line is exactly the order.items_add item',
      );
      final added = p.changes.single['item']! as Map<String, Object?>;
      expect(added.containsKey('line_discount_minor'), isFalse);
      expect(added['line_total_minor'], 2400); // 2 × (900 + 150 × 2)
      expect(p.subtotalMinor, 8700);
    });

    test('no-merge: the same item as a sent line is a separate add', () {
      final b = baselineOf(_example());
      final p = _plan(b, [
        ...untouched(b),
        added('line-9', 'mi-cola', name: 'Cola', unit: 800),
      ]);
      expect(p.changes, hasLength(1));
      expect(p.changes.single['op'], 'add');
      expect(p.subtotalMinor, 7100);
    });
  });

  group('the design worked example (§9.1)', () {
    test('6300 → 5700: burger without tomato, fries removed, a lemonade', () {
      final b = baselineOf(_example());
      final p = _plan(b, [
        sent(_line(b, 'oi-burger'), modifiers: const [_cucumber]),
        sent(_line(b, 'oi-fries'), removed: true),
        sent(_line(b, 'oi-cola')),
        added('line-1', 'mi-lemonade', name: 'Lemonade', unit: 900),
      ]);
      expect(p.beforeGrandMinor, 6300);
      expect(p.subtotalMinor, 5700);
      expect(p.grandMinor, 5700);
      expect(p.deltaMinor, -600);
      expect(p.changes.map((c) => c['op']), ['modify', 'remove', 'add']);
      final summary = p.summary;
      expect(summary.modifiedCount, 1);
      expect(summary.removedCount, 1);
      expect(summary.addedCount, 1);
      expect(summary.quantityChangedCount, 0);
    });
  });

  group('tax, discount and the zero-out guard (M6–M8)', () {
    const tax17 = BranchTax(enabled: true, rateBp: 1700);

    test('tax on (subtotal − discount), half away from zero', () {
      final b = baselineOf(_example(discount: 300, tax: 1020));
      // 5700 − 300 = 5400; × 17% = 918.
      final p = _plan(b, [
        sent(_line(b, 'oi-burger'), modifiers: const [_cucumber]),
        sent(_line(b, 'oi-fries'), removed: true),
        sent(_line(b, 'oi-cola')),
        added('line-1', 'mi-lemonade', unit: 900),
      ], tax: tax17);
      expect(p.subtotalMinor, 5700);
      expect(p.discountMinor, 300);
      expect(p.taxMinor, 918);
      expect(p.grandMinor, 6318);
      expect(buildOrderEditPayload(p)['expected'], {
        'subtotal_minor': 5700,
        'tax_total_minor': 918,
        'grand_total_minor': 6318,
      });
    });

    test('a half cent rounds away from zero', () {
      // 25 at 2% = 0.5 → 1.
      final b = baselineOf(detail(items: [detailItem('oi-a', unit: 20)]));
      final p = _plan(b, [
        ...untouched(b),
        added('line-1', 'mi-x', unit: 5),
      ], tax: const BranchTax(enabled: true, rateBp: 200));
      expect(p.subtotalMinor, 25);
      expect(p.taxMinor, 1);
      expect(p.grandMinor, 26);
    });

    test('9999 at 17% is 1700 (1699.83)', () {
      final b = baselineOf(detail(items: [detailItem('oi-a', unit: 9000)]));
      final p = _plan(b, [
        ...untouched(b),
        added('line-1', 'mi-x', unit: 999),
      ], tax: tax17);
      expect(p.taxMinor, 1700);
    });

    test('R-008: an earlier untaxed round is taxed on the whole base', () {
      // Stored tax 0 although the branch now taxes; the edit re-taxes it all.
      final b = baselineOf(_example(tax: 0));
      final p = _plan(b, [
        ...untouched(b),
        added('line-1', 'mi-lemonade', unit: 900),
      ], tax: tax17);
      expect(p.subtotalMinor, 7200);
      expect(p.taxMinor, 1224);
      expect(p.grandMinor, 8424);
    });

    test('tax off adds nothing', () {
      final b = baselineOf(_example());
      final p = _plan(b, [
        ...untouched(b),
        added('line-1', 'mi-x', unit: 900),
      ], tax: const BranchTax(enabled: true, rateBp: 0));
      expect(p.taxMinor, 0);
      expect(p.grandMinor, 7200);
    });

    test('a kept discount above the new subtotal is never clamped', () {
      final b = baselineOf(_example(discount: 5000));
      final p = _plan(b, _with(b, 'oi-burger', const []));
      expect(p.subtotalMinor, 2300);
      expect(p.discountExceeds, isTrue);
      expect(p.grandMinor, -2700);
      expect(
        orderEditSendBlock(p, online: true, reasonCode: 'entry_mistake'),
        OrderEditSendBlock.discountExceeds,
      );
    });

    test('zero-out needs the full-comp right — when it is KNOWN to be '
        'missing', () {
      final b = baselineOf(
        detail(
          items: [
            detailItem('oi-water', unit: 0),
            detailItem('oi-burger', unit: 4000),
          ],
        ),
      );
      final cart = _with(b, 'oi-burger', const []);
      final denied = _plan(b, cart, caps: _caps());
      expect(denied.grandMinor, 0);
      expect(denied.zeroOut, isTrue);
      expect(
        orderEditSendBlock(denied, online: true, reasonCode: 'entry_mistake'),
        OrderEditSendBlock.fullCompDenied,
      );
      expect(_plan(b, cart, caps: _caps(fullComp: true)).zeroOut, isFalse);
      expect(
        _plan(b, cart).zeroOut,
        isFalse,
        reason: 'unknown capabilities never block — the server decides',
      );
    });

    test('a discount equal to the new subtotal also zeroes the total', () {
      final b = baselineOf(_example(discount: 1500));
      final p = _plan(b, [
        sent(_line(b, 'oi-burger'), removed: true),
        sent(_line(b, 'oi-fries')),
        sent(_line(b, 'oi-cola'), removed: true),
      ], caps: _caps());
      expect(p.subtotalMinor, 1500);
      expect(p.grandMinor, 0);
      expect(p.zeroOut, isTrue);
    });
  });

  group('empty, limits and invalid lines', () {
    test('every line removed is a cancellation, not an edit', () {
      final b = baselineOf(_example());
      final p = _plan(b, [for (final s in b.lines) sent(s, removed: true)]);
      expect(p.wouldEmpty, isTrue);
      expect(
        orderEditSendBlock(p, online: true),
        OrderEditSendBlock.wouldEmpty,
      );
    });

    test('every line removed plus an add is an edit', () {
      final b = baselineOf(_example());
      final p = _plan(b, [
        for (final s in b.lines) sent(s, removed: true),
        added('line-1', 'mi-lemonade', unit: 900),
      ]);
      expect(p.wouldEmpty, isFalse);
      expect(p.subtotalMinor, 900);
      expect(p.changes, hasLength(4));
    });

    test('removing a legacy or discounted line subtracts its STORED total', () {
      final b = baselineOf(
        detail(
          items: [
            detailItem(
              'oi-legacy',
              unit: 1000,
              quantity: 2,
              lineTotal: 1700,
              legacy: true,
            ),
            detailItem('oi-disc', unit: 1000, lineDiscount: 250),
            detailItem('oi-keep', unit: 500),
          ],
        ),
      );
      expect(b.liveSubtotalMinor, 2950); // 1700 + 750 + 500
      final kept = _plan(b, untouched(b));
      expect(kept.subtotalMinor, 2950);
      final p = _plan(b, [
        sent(_line(b, 'oi-legacy'), removed: true),
        sent(_line(b, 'oi-disc'), removed: true),
        sent(_line(b, 'oi-keep')),
      ]);
      expect(p.subtotalMinor, 500);
      expect(p.invalidLineChange, isFalse);
    });

    test('changing a remove-only line is never planned as sendable', () {
      final b = baselineOf(
        detail(items: [detailItem('oi-disc', unit: 1000, lineDiscount: 250)]),
      );
      final p = _plan(b, [sent(_line(b, 'oi-disc'), quantity: 2)]);
      expect(p.invalidLineChange, isTrue);
      expect(
        orderEditSendBlock(p, online: true),
        OrderEditSendBlock.invalidLineChange,
      );
    });

    test('a line bound to an unknown sent line is invalid', () {
      final b = baselineOf(_example());
      final other = baselineOf(
        detail(items: [detailItem('oi-elsewhere')]),
      ).lines.single;
      final p = _plan(b, [...untouched(b), sent(other)]);
      expect(p.invalidLineChange, isTrue);
    });

    test('more than 100 changes is too many', () {
      final b = baselineOf(_example());
      final p = _plan(b, [
        ...untouched(b),
        for (var i = 0; i < 101; i++) added('line-$i', 'mi-x', unit: 100),
      ]);
      expect(p.changes, hasLength(101));
      expect(p.tooMany, isTrue);
      expect(
        orderEditSendBlock(p, online: true),
        OrderEditSendBlock.tooManyChanges,
      );
    });

    test('more than 20 replacements is too many', () {
      final b = baselineOf(_example(burgerQty: 21));
      final burger = _line(b, 'oi-burger');
      final p = _plan(
        b,
        _with(b, 'oi-burger', [
          for (var i = 0; i < 21; i++)
            part(burger, i, quantity: 1, note: 'variant $i'),
        ]),
      );
      expect((p.changes.single['replacements'] as List), hasLength(21));
      expect(p.tooMany, isTrue);
    });

    test('a quantity above 999 is too many', () {
      final b = baselineOf(_example());
      final p = _plan(
        b,
        _with(b, 'oi-cola', [sent(_line(b, 'oi-cola'), quantity: 1000)]),
      );
      expect(p.tooMany, isTrue);
    });
  });

  group('determinism', () {
    test('a shuffled cart gives byte-identical payload JSON', () {
      final b = baselineOf(_example(burgerQty: 3));
      final burger = _line(b, 'oi-burger');
      final rows = <OrderEditCartLine>[
        sent(burger, quantity: 2),
        part(burger, 1, quantity: 1, modifiers: const [_cucumber]),
        sent(_line(b, 'oi-fries'), removed: true),
        sent(_line(b, 'oi-cola'), quantity: 2),
      ];
      final adds = [
        added('line-1', 'mi-lemonade', unit: 900),
        added('line-2', 'mi-water', unit: 300),
      ];
      final reference = jsonEncode(
        buildOrderEditPayload(
          _plan(b, [...rows, ...adds]),
          reasonCode: 'entry_mistake',
        ),
      );
      final random = Random(7);
      for (var i = 0; i < 20; i++) {
        // The sent lines in any order; the added lines anywhere, but in their
        // own relative order (that order is content, not position).
        final mixed = <OrderEditCartLine>[...rows]..shuffle(random);
        final i = random.nextInt(mixed.length + 1);
        mixed.insert(i, adds[0]);
        mixed.insert(i + 1 + random.nextInt(mixed.length - i), adds[1]);
        expect(
          jsonEncode(
            buildOrderEditPayload(_plan(b, mixed), reasonCode: 'entry_mistake'),
          ),
          reference,
        );
      }
    });
  });

  group('reason: requirement and preselect (design §7.1 point 5)', () {
    test('every removing change on a Waiting KDS ticket preselects', () {
      final b = baselineOf(_example(burgerStatus: 'submitted'));
      final burger = _line(b, 'oi-burger');
      expect(burger.isWaitingOnKds, isTrue);
      final p = _plan(b, _with(b, 'oi-burger', const []));
      expect(p.preselectCustomerChangedMind, isTrue);
      expect(p.preselectedReasonCode, 'customer_changed_mind');
    });

    test('one removing change past Waiting means the cashier chooses', () {
      final b = baselineOf(
        detail(
          items: [
            detailItem('oi-a', unitStatus: 'submitted'),
            detailItem('oi-b', unitStatus: 'preparing'),
          ],
        ),
      );
      final p = _plan(b, const []);
      expect(p.hasRemoving, isTrue);
      expect(p.preselectCustomerChangedMind, isFalse);
      expect(p.preselectedReasonCode, isNull);
    });

    test('paper never preselects', () {
      final b = baselineOf(
        _example(burgerStatus: 'submitted', channel: PosKitchenChannel.paper),
      );
      expect(
        _plan(b, _with(b, 'oi-burger', const [])).preselectCustomerChangedMind,
        isFalse,
      );
    });

    test('adds and increases ask for no reason', () {
      final b = baselineOf(_example(burgerStatus: 'submitted'));
      final p = _plan(b, [
        ...untouched(b).where((l) => l.sourceOrderItemId != 'oi-cola'),
        sent(_line(b, 'oi-cola'), quantity: 2),
        added('line-1', 'mi-x', unit: 100),
      ]);
      expect(p.hasRemoving, isFalse);
      expect(p.preselectCustomerChangedMind, isFalse);
      expect(orderEditSendBlock(p, online: true), isNull);
    });

    test('Other needs text; an unknown code is no reason', () {
      final b = baselineOf(_example());
      final p = _plan(b, _with(b, 'oi-fries', const []));
      expect(
        orderEditSendBlock(p, online: true, reasonCode: 'other'),
        OrderEditSendBlock.reasonOtherRequired,
      );
      expect(
        orderEditSendBlock(
          p,
          online: true,
          reasonCode: 'other',
          reasonText: '   ',
        ),
        OrderEditSendBlock.reasonOtherRequired,
      );
      expect(
        orderEditSendBlock(
          p,
          online: true,
          reasonCode: 'other',
          reasonText: 'spilled',
        ),
        isNull,
      );
      expect(
        orderEditSendBlock(p, online: true, reasonCode: 'made_up'),
        OrderEditSendBlock.reasonRequired,
      );
      expect(
        orderEditSendBlock(p, online: true, reasonCode: 'kitchen_issue'),
        isNull,
      );
    });
  });

  group('finished food (design §7.1 point 6)', () {
    OrderEditBaseline ready(PosKitchenChannel channel) => baselineOf(
      detail(
        channel: channel,
        items: [
          detailItem('oi-a', quantity: 2, unitStatus: 'ready'),
          detailItem('oi-b', quantity: 2, unitStatus: 'served'),
          detailItem('oi-c', quantity: 2, unitStatus: 'preparing'),
        ],
      ),
    );

    test('a Ready / Served KDS line removed or reduced is listed', () {
      final b = ready(PosKitchenChannel.kds);
      final p = _plan(b, [
        sent(_line(b, 'oi-b'), quantity: 1),
        sent(_line(b, 'oi-c'), removed: true),
      ]);
      expect(p.finishedFoodChanges.map((c) => c.source!.orderItemId), [
        'oi-a',
        'oi-b',
      ]);
      expect(p.needsFinishedFoodConfirm, isTrue);
    });

    test('a modify listed only when it remakes', () {
      final b = ready(PosKitchenChannel.kds);
      final a = _line(b, 'oi-a');
      final remake = _plan(b, [
        sent(a, quantity: 1),
        part(a, 1, quantity: 1, note: 'well done'),
        sent(_line(b, 'oi-b')),
        sent(_line(b, 'oi-c')),
      ]);
      expect(remake.finishedFoodChanges.single.remakeDishes, 1);
      final excessOnly = _plan(b, [
        sent(a),
        part(a, 1, quantity: 1, note: 'well done'),
        sent(_line(b, 'oi-b')),
        sent(_line(b, 'oi-c')),
      ]);
      expect(excessOnly.plannedChanges.single.kind, OrderEditChangeKind.modify);
      expect(excessOnly.plannedChanges.single.remakeDishes, 0);
      expect(excessOnly.needsFinishedFoodConfirm, isFalse);
    });

    test('paper is never finished food', () {
      final b = ready(PosKitchenChannel.paper);
      final p = _plan(b, const []);
      expect(p.needsFinishedFoodConfirm, isFalse);
      expect(p.remakeCount, 0);
    });
  });

  group('authority (known-denied only)', () {
    test('void_order denied blocks removing changes, not additions', () {
      final b = baselineOf(_example());
      final removing = _plan(
        b,
        _with(b, 'oi-fries', const []),
        caps: _caps(voidOrder: false),
      );
      expect(removing.removalNotPermitted, isTrue);
      expect(
        orderEditSendBlock(removing, online: true, reasonCode: 'entry_mistake'),
        OrderEditSendBlock.removalNotPermitted,
      );
      final adding = _plan(b, [
        ...untouched(b),
        added('line-1', 'mi-x', unit: 100),
      ], caps: _caps(voidOrder: false));
      expect(adding.removalNotPermitted, isFalse);
      expect(
        _plan(
          b,
          _with(b, 'oi-fries', const []),
          caps: _caps(voidOrder: null),
        ).removalNotPermitted,
        isFalse,
        reason: 'unknown is not denied (D14)',
      );
    });

    test('finished food with the switch ON needs a manager', () {
      final b = baselineOf(
        _example(
          burgerStatus: 'ready',
          features: const PosBranchFeatures(
            orderEditEnabled: true,
            finishedFoodManagerOnly: true,
          ),
        ),
      );
      final p = _plan(b, _with(b, 'oi-burger', const []), caps: _caps());
      expect(p.finishedFoodNeedsManager, isTrue);
      expect(
        orderEditSendBlock(p, online: true, reasonCode: 'kitchen_issue'),
        OrderEditSendBlock.finishedFoodNeedsManager,
      );
      expect(
        _plan(
          b,
          _with(b, 'oi-burger', const []),
          caps: _caps(role: 'manager'),
        ).finishedFoodNeedsManager,
        isFalse,
      );
    });
  });

  group('send-block order', () {
    test('offline comes after the plan reasons and before the reason', () {
      final b = baselineOf(_example());
      final p = _plan(b, _with(b, 'oi-fries', const []));
      expect(orderEditSendBlock(p, online: false), OrderEditSendBlock.offline);
      expect(
        orderEditSendBlock(p, online: true),
        OrderEditSendBlock.reasonRequired,
      );
    });

    test('the first applicable reason wins', () {
      final b = baselineOf(_example(discount: 9000));
      final p = _plan(b, [for (final s in b.lines) sent(s, removed: true)]);
      expect(p.wouldEmpty, isTrue);
      expect(p.discountExceeds, isTrue);
      expect(
        orderEditSendBlock(p, online: false),
        OrderEditSendBlock.wouldEmpty,
      );
    });
  });

  group('payload (API §4.45.1)', () {
    test('the envelope, with the reason only for a removing change', () {
      final b = baselineOf(_example());
      final p = _plan(b, _with(b, 'oi-fries', const []));
      expect(
        buildOrderEditPayload(
          p,
          reasonCode: 'item_unavailable',
          reasonText: 'ignored without other',
          billPresentedAt: DateTime.utc(2026, 10, 9, 11, 30),
        ),
        {
          'order_id': 'order-1',
          'reason_code': 'item_unavailable',
          'bill_presented_at': '2026-10-09T11:30:00.000Z',
          'expected': {
            'subtotal_minor': 4800,
            'tax_total_minor': 0,
            'grand_total_minor': 4800,
          },
          'changes': [
            {'op': 'remove', 'order_item_id': 'oi-fries'},
          ],
        },
      );
    });

    test('bill_presented_at is always a UTC instant with Z', () {
      final b = baselineOf(_example());
      final p = _plan(b, _with(b, 'oi-fries', const []));
      final local = DateTime(2026, 10, 9, 14, 30);
      final wire =
          buildOrderEditPayload(p, billPresentedAt: local)['bill_presented_at']!
              as String;
      expect(wire.endsWith('Z'), isTrue);
      expect(DateTime.parse(wire), local.toUtc());
    });

    test('Other text is trimmed and capped at 200 characters', () {
      final b = baselineOf(_example());
      final p = _plan(b, _with(b, 'oi-fries', const []));
      final payload = buildOrderEditPayload(
        p,
        reasonCode: 'other',
        reasonText: '  ${'ש' * 205}  ',
      );
      expect(payload['reason_code'], 'other');
      expect((payload['reason_text']! as String).runes.length, 200);
    });

    test('no reason, no text and no stale chip for an add-only edit', () {
      final b = baselineOf(_example());
      final p = _plan(b, [...untouched(b), added('line-1', 'mi-x', unit: 1)]);
      final payload = buildOrderEditPayload(
        p,
        reasonCode: 'other',
        reasonText: 'left over',
      );
      expect(payload.containsKey('reason_code'), isFalse);
      expect(payload.containsKey('reason_text'), isFalse);
    });
  });

  group('the cart view shares the plan formula', () {
    test('orderEditSubtotalMinor equals the plan subtotal', () {
      final b = baselineOf(_example(burgerQty: 3));
      final burger = _line(b, 'oi-burger');
      final cart = [
        sent(burger, quantity: 2),
        part(burger, 1, quantity: 2, modifiers: const [_cucumber]),
        sent(_line(b, 'oi-fries'), removed: true),
        sent(_line(b, 'oi-cola')),
        added('line-1', 'mi-x', unit: 650),
      ];
      final p = _plan(b, cart);
      expect(orderEditSubtotalMinor(b, cart), p.subtotalMinor);
      var viewSum = 0;
      for (final l in cart) {
        if (!l.removed) viewSum += l.line.lineTotalMinor;
      }
      expect(viewSum, p.subtotalMinor);
      expect(p.subtotalMinor, 17450); // 4 × 4000 + 800 + 650
    });
  });

  group('server-simulator property test (design §10)', () {
    test('applying the plan reproduces the cart; totals match the server '
        'rule', () {
      final random = Random(20261009);
      final kinds = <OrderEditChangeKind, int>{};
      var remade = 0;
      var multiReplacement = 0;
      for (var round = 0; round < 400; round++) {
        final scenario = _randomScenario(random, round);
        final b = scenario.baseline;
        final p = _plan(b, scenario.cart, tax: scenario.tax);
        final sim = _simulate(b, p.changes);
        for (final c in p.plannedChanges) {
          kinds[c.kind] = (kinds[c.kind] ?? 0) + 1;
        }
        if (p.remakeCount > 0) remade++;
        if (p.changes.any(
          (c) => c['op'] == 'modify' && (c['replacements']! as List).length > 1,
        )) {
          multiReplacement++;
        }

        expect(
          sim.multiset,
          _cartMultiset(b, scenario.cart),
          reason: 'round $round: the server result is not the cart',
        );
        expect(sim.subtotal, p.subtotalMinor, reason: 'round $round');
        final base = sim.subtotal - b.discountMinor;
        expect(
          p.taxMinor,
          _serverTax(base, scenario.tax),
          reason: 'round $round',
        );
        expect(p.grandMinor, base + p.taxMinor, reason: 'round $round');
        expect(p.remakeCount, sim.remakeDishes, reason: 'round $round');
        expect(
          orderEditSubtotalMinor(b, scenario.cart),
          p.subtotalMinor,
          reason: 'round $round',
        );
        var viewSum = 0;
        for (final l in scenario.cart) {
          if (!l.removed) viewSum += l.line.lineTotalMinor;
        }
        expect(viewSum, p.subtotalMinor, reason: 'round $round: cart view');
      }
      // Not vacuous: every change kind, multi-replacement modifies and
      // remakes were actually exercised.
      for (final kind in OrderEditChangeKind.values) {
        expect(kinds[kind] ?? 0, greaterThan(20), reason: '$kind');
      }
      expect(multiReplacement, greaterThan(20));
      expect(remade, greaterThan(10));
    });
  });
}

// ---------------------------------------------------------------------------
// The Add-items parity harness
// ---------------------------------------------------------------------------

class _CapturingTransport implements SyncRpcTransport {
  final List<Map<String, dynamic>> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function != 'sync_push') return {'ok': false};
    calls.add(params);
    return {'ok': true, 'results': <Object?>[]};
  }

  List<Object?> get itemsAdd => [
    for (final c in calls)
      for (final op in (c['p_operations'] as List).cast<Map>())
        if (op['operation_type'] == 'order.items_add')
          ...((op['payload'] as Map)['order_items'] as List),
  ];
}

class _DetailRepo implements OrderDetailRepository {
  @override
  Future<PosOrderDetail> fetch(String orderId) async => PosOrderDetail(
    orderId: orderId,
    orderCode: '#O00001',
    orderType: 'dine_in',
    status: 'preparing',
    revision: 2,
    currencyCode: 'ILS',
    subtotalMinor: 0,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: 0,
    items: const [],
    rounds: const [],
  );
}

// ---------------------------------------------------------------------------
// A Dart port of app.edit_order's plan rules (steps 6–11), for the property
// test. Written from the SQL, not from the engine.
// ---------------------------------------------------------------------------

class _Row {
  _Row(this.menuItemId, this.pairs, this.notes, this.qty, this.total);
  final String menuItemId;
  final List<String> pairs;
  final String? notes;
  final int qty;
  final int total;
}

String? _btrim(Object? s) {
  if (s is! String) return null;
  var a = 0;
  var z = s.length;
  while (a < z && s[a] == ' ') {
    a++;
  }
  while (z > a && s[z - 1] == ' ') {
    z--;
  }
  return a == z ? null : s.substring(a, z);
}

List<String> _sortedPairs(Iterable<(String, int)> mods) =>
    [for (final m in mods) '${m.$1.toLowerCase()}#${m.$2}']..sort();

({Map<String, int> multiset, int subtotal, int remakeDishes}) _simulate(
  OrderEditBaseline b,
  List<Map<String, Object?>> changes,
) {
  final retired = <String>{};
  final rows = <_Row>[];
  final referenced = <String>{};
  var remakes = 0;
  for (final c in changes) {
    final op = c['op'];
    if (op == 'add') {
      final item = c['item']! as Map<String, Object?>;
      final mods = (item['modifiers'] as List?)?.cast<Map>() ?? const [];
      var modSum = 0;
      for (final m in mods) {
        modSum +=
            (m['price_minor_snapshot']! as int) *
            ((m['quantity'] as int?) ?? 1);
      }
      final qty = item['quantity']! as int;
      rows.add(
        _Row(
          item['menu_item_id']! as String,
          _sortedPairs([
            for (final m in mods)
              (
                m['modifier_option_id']! as String,
                (m['quantity'] as int?) ?? 1,
              ),
          ]),
          _btrim(item['notes']),
          qty,
          qty * ((item['unit_price_minor_snapshot']! as int) + modSum),
        ),
      );
      continue;
    }
    final id = c['order_item_id']! as String;
    expect(referenced.add(id), isTrue, reason: 'duplicate_line_reference');
    final s = b.lineFor(id)!;
    final oldPairs = _sortedPairs([
      for (final m in s.modifiers) (m.optionId, m.quantity),
    ]);
    var cu = s.unitPriceMinor;
    for (final m in s.modifiers) {
      cu += m.priceMinor * m.quantity;
    }
    if (op == 'remove') {
      retired.add(id);
    } else if (op == 'set_quantity') {
      final q = c['quantity']! as int;
      expect(q, isNot(s.quantity), reason: 'an equal set_quantity is refused');
      expect(q, inInclusiveRange(1, 999));
      if (q > s.quantity) {
        rows.add(
          _Row(
            s.menuItemId,
            oldPairs,
            _btrim(s.notes),
            q - s.quantity,
            (q - s.quantity) * cu,
          ),
        );
      } else {
        retired.add(id);
        rows.add(_Row(s.menuItemId, oldPairs, _btrim(s.notes), q, q * cu));
      }
    } else if (op == 'modify') {
      retired.add(id);
      final reps = (c['replacements']! as List).cast<Map>();
      expect(reps.length, inInclusiveRange(1, 20));
      final composed =
          <
            ({int qty, bool cont, int unit, List<String> pairs, String? notes})
          >[];
      var changedQty = 0;
      for (final r in reps) {
        final mods = (r['modifiers'] as List?)?.cast<Map>() ?? const [];
        var unit = s.unitPriceMinor;
        final pairs = <(String, int)>[];
        for (final m in mods) {
          final optionId = (m['modifier_option_id']! as String).toLowerCase();
          final kept = s.modifiers
              .where((k) => k.optionId.toLowerCase() == optionId)
              .firstOrNull;
          final q = (m['quantity'] as int?) ?? kept?.quantity ?? 1;
          if (kept != null) {
            unit += kept.priceMinor * q; // the OLD row's price
          } else {
            expect(m['option_name_snapshot'], isA<String>());
            unit += (m['price_minor_snapshot']! as int) * q;
          }
          pairs.add((optionId, q));
        }
        final sorted = _sortedPairs(pairs);
        final cont =
            listEquals(sorted, oldPairs) &&
            _btrim(r['notes']) == _btrim(s.notes);
        final qty = r['quantity']! as int;
        expect(qty, inInclusiveRange(1, 999));
        if (!cont) changedQty += qty;
        composed.add((
          qty: qty,
          cont: cont,
          unit: unit,
          pairs: sorted,
          notes: _btrim(r['notes']),
        ));
      }
      expect(changedQty, greaterThan(0), reason: 'an all-unchanged modify');
      var budget = s.quantity;
      var takeChanged = 0;
      for (final pass in [1, 2]) {
        for (final r in composed) {
          if ((pass == 1) != r.cont) continue;
          final take = r.qty < budget ? r.qty : budget;
          budget -= take;
          if (pass == 2) takeChanged += take;
          // Continuation rows keep the old note; the rest carry their own.
          final note = r.cont ? _btrim(s.notes) : r.notes;
          rows.add(_Row(s.menuItemId, r.pairs, note, r.qty, r.qty * r.unit));
        }
      }
      if (s.channel == PosKitchenChannel.kds &&
          (s.unitStatus == 'ready' || s.unitStatus == 'served')) {
        remakes += takeChanged;
      }
    } else {
      fail('unknown op $op');
    }
  }
  final multiset = <String, int>{};
  var subtotal = 0;
  void count(String menuItemId, List<String> pairs, String? notes, int qty) {
    final key = jsonEncode([menuItemId, pairs, notes]);
    multiset[key] = (multiset[key] ?? 0) + qty;
  }

  for (final s in b.lines) {
    if (retired.contains(s.orderItemId)) continue;
    subtotal += s.lineTotalMinor;
    count(
      s.menuItemId,
      _sortedPairs([for (final m in s.modifiers) (m.optionId, m.quantity)]),
      _btrim(s.notes),
      s.quantity,
    );
  }
  for (final r in rows) {
    subtotal += r.total;
    count(r.menuItemId, r.pairs, r.notes, r.qty);
  }
  return (multiset: multiset, subtotal: subtotal, remakeDishes: remakes);
}

Map<String, int> _cartMultiset(
  OrderEditBaseline b,
  List<OrderEditCartLine> cart,
) {
  final out = <String, int>{};
  for (final c in cart) {
    if (c.removed) continue;
    final source = c.sourceOrderItemId == null
        ? null
        : b.lineFor(c.sourceOrderItemId!);
    final key = jsonEncode([
      source?.menuItemId ?? c.line.menuItemId,
      _sortedPairs([
        for (final m in c.line.modifiers) (m.optionId, m.quantity),
      ]),
      _btrim(c.line.note),
    ]);
    out[key] = (out[key] ?? 0) + c.line.quantity;
  }
  return out;
}

int _serverTax(int base, BranchTax tax) {
  // app.edit_tax_minor: disabled or 0 bp → 0; exclusive → round(base × bp /
  // 10000) on a numeric, which PostgreSQL rounds half away from zero.
  if (!tax.enabled || tax.rateBp <= 0) return 0;
  final scaled = base * tax.rateBp;
  final whole = scaled ~/ 10000;
  final rest = scaled - whole * 10000;
  return rest * 2 >= 10000 ? whole + 1 : whole;
}

const _pool = <(String, int)>[
  ('opt-a', 0),
  ('opt-b', 100),
  ('opt-c', 250),
  ('opt-d', 300),
  ('opt-e', 500),
];

const _statuses = ['submitted', 'accepted', 'preparing', 'ready', 'served'];

({OrderEditBaseline baseline, List<OrderEditCartLine> cart, BranchTax tax})
_randomScenario(Random r, int round) {
  T pick<T>(List<T> xs) => xs[r.nextInt(xs.length)];
  List<(String, int, int)> randomMods() {
    final chosen = [..._pool]..shuffle(r);
    return [
      for (final o in chosen.take(r.nextInt(3))) (o.$1, o.$2, 1 + r.nextInt(2)),
    ];
  }

  final items = <PosOrderDetailItem>[];
  for (var i = 0; i < 1 + r.nextInt(4); i++) {
    items.add(
      detailItem(
        'oi-$i',
        menuItemId: pick(['mi-1', 'mi-2', 'mi-3']),
        quantity: 1 + r.nextInt(4),
        unit: pick([800, 1200, 4000]),
        notes: pick<String?>([null, 'no salt']),
        unitStatus: pick(_statuses),
        modifiers: [
          for (final m in randomMods())
            detailMod(m.$1, m.$1, price: m.$2, quantity: m.$3),
        ],
      ),
    );
  }
  final b = baselineOf(
    detail(
      items: items,
      channel: pick([PosKitchenChannel.kds, PosKitchenChannel.paper]),
    ),
  );

  // A cart option: a kept option may arrive with a DRIFTED (live) price; the
  // plan must still charge the stored one.
  List<SelectedModifier> cartMods(OrderEditSourceLine s) {
    if (r.nextBool()) {
      return [
        for (final m in s.modifiers)
          mod(
            m.optionId,
            m.optionName,
            price: m.priceMinor + r.nextInt(3) * 50,
            quantity: m.quantity,
          ),
      ];
    }
    return [
      for (final m in randomMods())
        mod(m.$1, m.$1, price: m.$2, quantity: m.$3),
    ];
  }

  final cart = <OrderEditCartLine>[];
  for (final s in b.lines) {
    switch (r.nextInt(5)) {
      case 0:
        cart.add(sent(s));
      case 1:
        cart.add(sent(s, removed: true));
      case 2:
        cart.add(sent(s, quantity: 1 + r.nextInt(5)));
      default:
        final parts = 1 + r.nextInt(3);
        for (var p = 0; p < parts; p++) {
          final note = pick<String?>([s.notes, null, 'extra hot', ' no salt ']);
          final line = p == 0
              ? sent(
                  s,
                  quantity: 1 + r.nextInt(3),
                  modifiers: cartMods(s),
                  note: note,
                )
              : part(
                  s,
                  p,
                  quantity: 1 + r.nextInt(3),
                  modifiers: cartMods(s),
                  note: note,
                );
          cart.add(line);
        }
    }
  }
  for (var i = 0; i < r.nextInt(3); i++) {
    cart.add(
      added(
        'line-$round-$i',
        pick(['mi-1', 'mi-4']),
        quantity: 1 + r.nextInt(3),
        unit: pick([500, 900]),
        modifiers: [
          for (final m in randomMods())
            mod(m.$1, m.$1, price: m.$2, quantity: m.$3),
        ],
        note: pick<String?>([null, 'to go']),
      ),
    );
  }
  cart.shuffle(r);
  return (
    baseline: b,
    cart: cart,
    tax: pick(const [
      BranchTax.disabled,
      BranchTax(enabled: true, rateBp: 1700),
      BranchTax(enabled: true, rateBp: 1750),
    ]),
  );
}
