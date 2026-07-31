import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenMeat, OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/demo_menu.dart' show DemoMenuItem;
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/data/parked_carts_store.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';

/// MONEY-PRICING-FORMULA-002A — a cart line is N identical FULLY CONFIGURED
/// items, so every modifier surcharge is charged once per item unit.
///
/// AUTHORITATIVE CONTRACT — docs/MONEY_AND_TAX_SPEC.md §9:157 and its worked
/// example §9.1:179 ("Line A per-unit = 4500 + 700 = 5200; × 2 = 10400"):
///
///   modifierUnitSum      = Σ(priceDeltaMinor × modifierQuantity)
///   configuredUnitAmount = basePriceMinor + modifierUnitSum
///   lineTotalMinor       = configuredUnitAmount × itemQuantity
///
/// The shipped code computed `base × itemQty + modifierUnitSum`, adding the
/// surcharge ONCE per LINE. The two agree at quantity 1 and diverge by
/// `modifierUnitSum × (itemQty − 1)` above it — which is why it survived, and
/// why the kitchen (which already multiplies meat and prep by item quantity)
/// cooks N upgraded meals while the till charged for one upgrade.
///
/// Every expectation here is an INDEPENDENT literal or an arithmetic expression
/// written out in the test. Nothing is produced by the helper under assertion.

const kBase = 4500;
const k120 = 0;
const k240 = 1500;
const k360 = 2500;
const k480 = 3500;

const burger = DemoMenuItem(
  id: 'burger-meat',
  name: 'Burger',
  priceMinor: kBase,
  categoryId: 'food',
  categoryName: 'Food',
);

const wrap = DemoMenuItem(
  id: 'wrap',
  name: 'Wrap',
  priceMinor: 3800,
  categoryId: 'food',
  categoryName: 'Food',
);

SelectedModifier mod(int delta, {int quantity = 1, String? id}) =>
    SelectedModifier(
      optionId: id ?? 'opt-$delta-$quantity',
      groupName: 'Meat',
      optionName: '${delta}g',
      priceDeltaMinor: delta,
      quantity: quantity,
      kitchenMeat: const KitchenMeat(quantity: 1, unit: 'patty'),
    );

class _Repo implements OutboxRepository {
  final List<OutboxEntry> enqueued = <OutboxEntry>[];
  @override
  Future<OutboxEntry> enqueue(OutboxEntry entry) async {
    enqueued.add(entry);
    return entry;
  }

  @override
  Future<List<OutboxEntry>> recentEntries() async => List.of(enqueued);
  @override
  Future<OutboxEntry> push(String id) async =>
      enqueued.firstWhere((e) => e.id == id);
  @override
  Future<OutboxEntry> retry(String id) async =>
      enqueued.firstWhere((e) => e.id == id);
  @override
  Future<String?> findOrderSubmitCustomerPhone(
    OrderSubmitPhoneLookupKey key,
  ) async => null;
}

ProviderContainer container({OutboxRepository? repo}) {
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
      if (repo != null) outboxRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

CartController cartOf(ProviderContainer c) =>
    c.read(cartControllerProvider.notifier);
CartViewState viewOf(ProviderContainer c) => c.read(cartControllerProvider);

String add(
  ProviderContainer c,
  DemoMenuItem item,
  List<SelectedModifier> mods, {
  int quantity = 1,
}) {
  cartOf(c).addItemWithModifiers(item, mods);
  final id = viewOf(c).lines.last.lineId;
  for (var i = 1; i < quantity; i++) {
    cartOf(c).increaseQuantity(id);
  }
  return id;
}

void main() {
  group('A. the configured-unit formula, item quantity 1..3', () {
    // (base, delta, modifierQty, itemQty, EXPECTED line total — literal)
    const cases = <List<int>>[
      [kBase, k120, 1, 1, 4500],
      [kBase, k240, 1, 1, 6000],
      [kBase, k240, 1, 2, 12000],
      [kBase, k240, 1, 3, 18000],
      [kBase, k360, 1, 2, 14000],
      [kBase, k480, 1, 3, 24000],
      [kBase, 500, 2, 3, 16500],
      [kBase, 500, 3, 2, 12000],
      [kBase, k120, 1, 3, 13500],
      [kBase, k240, 2, 2, 15000],
    ];

    for (final t in cases) {
      final base = t[0], delta = t[1], mq = t[2], iq = t[3], expected = t[4];
      test('A base=$base delta=$delta modQty=$mq itemQty=$iq -> $expected', () {
        final c = container();
        add(c, burger, [mod(delta, quantity: mq)], quantity: iq);
        final v = viewOf(c);
        final line = v.lines.single;

        expect(line.quantity, iq);
        expect(
          line.modifiers.single.totalDeltaMinor,
          delta * mq,
          reason: 'modifier subtotal per configured unit',
        );
        expect(line.lineTotalMinor, expected);
        expect(v.subtotalMinor, expected);
      });
    }
  });

  group('B. the physical-equivalent cases', () {
    test('B1 120g qty 1 -> 4500', () {
      final c = container();
      add(c, burger, [mod(k120)]);
      expect(viewOf(c).lines.single.lineTotalMinor, 4500);
    });

    test('B2 240g qty 1 -> 6000', () {
      final c = container();
      add(c, burger, [mod(k240)]);
      expect(viewOf(c).lines.single.lineTotalMinor, 6000);
    });

    test('B3 240g qty 2 -> 12000 (the reported under-charge)', () {
      final c = container();
      add(c, burger, [mod(k240)], quantity: 2);
      expect(viewOf(c).lines.single.lineTotalMinor, 12000);
      expect(viewOf(c).subtotalMinor, 12000);
    });

    test('B4 240g qty 3 -> 18000', () {
      final c = container();
      add(c, burger, [mod(k240)], quantity: 3);
      expect(viewOf(c).lines.single.lineTotalMinor, 18000);
    });

    test('B5 +500 modifier qty 2, item qty 3 -> 16500', () {
      final c = container();
      add(c, burger, [mod(500, quantity: 2)], quantity: 3);
      expect(viewOf(c).lines.single.lineTotalMinor, 16500);
    });

    test('B6 two separate upgraded lines charge independently', () {
      final c = container();
      add(c, burger, [mod(k240)], quantity: 2);
      add(c, burger, [mod(k480)]);
      final v = viewOf(c);
      expect(v.lines[0].lineTotalMinor, 12000);
      expect(v.lines[1].lineTotalMinor, 8000);
      expect(v.subtotalMinor, 20000);
    });

    test('B7 a free line and an upgraded line do not leak', () {
      final c = container();
      add(c, burger, [mod(k120)], quantity: 2);
      add(c, burger, [mod(k240)], quantity: 2);
      final v = viewOf(c);
      expect(v.lines[0].lineTotalMinor, 9000);
      expect(v.lines[1].lineTotalMinor, 12000);
      expect(v.subtotalMinor, 21000);
    });

    test('B8 removing the FIRST line leaves the second exact', () {
      final c = container();
      final a = add(c, burger, [mod(k240)], quantity: 2);
      add(c, burger, [mod(k480)], quantity: 3);
      cartOf(c).removeLine(a);
      expect(viewOf(c).lines.single.lineTotalMinor, 24000);
      expect(viewOf(c).subtotalMinor, 24000);
    });

    test('B9 removing the SECOND line leaves the first exact', () {
      final c = container();
      add(c, burger, [mod(k240)], quantity: 2);
      final b = add(c, burger, [mod(k480)], quantity: 3);
      cartOf(c).removeLine(b);
      expect(viewOf(c).lines.single.lineTotalMinor, 12000);
    });

    test('B10 the recovered-draft view uses the SAME formula', () {
      final c = container();
      add(c, burger, [mod(k240)], quantity: 2);
      add(c, burger, [mod(500, quantity: 2)], quantity: 3);
      final live = viewOf(c);
      expect(live.subtotalMinor, 12000 + 16500);

      final recovered = cartOf(
        c,
      ).viewFromDraft(draft: cartOf(c).captureDraft());
      expect(recovered.subtotalMinor, 12000 + 16500);
      expect(recovered.lines[0].lineTotalMinor, 12000);
      expect(recovered.lines[1].lineTotalMinor, 16500);
    });

    test('B11 quantity decrement and clear/re-add reprice exactly', () {
      final c = container();
      final id = add(c, burger, [mod(k240)], quantity: 3);
      expect(viewOf(c).lines.single.lineTotalMinor, 18000);
      cartOf(c).decreaseQuantity(id);
      expect(viewOf(c).lines.single.lineTotalMinor, 12000);
      cartOf(c).clear();
      expect(viewOf(c).subtotalMinor, 0);
      add(c, burger, [mod(k360)], quantity: 2);
      expect(viewOf(c).subtotalMinor, 14000);
    });

    test('B12 different products keep independent configured units', () {
      final c = container();
      add(c, burger, [mod(k240)], quantity: 2);
      add(c, wrap, [mod(k360)], quantity: 2);
      final v = viewOf(c);
      expect(v.lines[0].lineTotalMinor, 12000);
      expect(v.lines[1].lineTotalMinor, 2 * (3800 + 2500));
      expect(v.subtotalMinor, 12000 + 12600);
    });

    test('B13 several modifiers on one configured unit', () {
      final c = container();
      add(c, burger, [
        mod(k240, id: 'a'),
        mod(500, quantity: 2, id: 'b'),
        mod(0, id: 'c'),
      ], quantity: 2);
      // per unit = 4500 + 1500 + 1000 + 0 = 7000; × 2 = 14000
      expect(viewOf(c).lines.single.lineTotalMinor, 14000);
    });

    test('B14 subtotal always equals the sum of line totals', () {
      final c = container();
      add(c, burger, [mod(k240)], quantity: 2);
      add(c, burger, [mod(k480)], quantity: 3);
      add(c, wrap, [mod(0)]);
      final v = viewOf(c);
      expect(
        v.subtotalMinor,
        v.lines.fold<int>(0, (s, l) => s + l.lineTotalMinor),
      );
      expect(v.subtotalMinor, 12000 + 24000 + 3800);
    });
  });

  group('C. the parked-cart subtotal must equal the live cart subtotal', () {
    test(
      'C1 ParkedCart.subtotalMinor matches the cart it was captured from',
      () {
        final c = container();
        add(c, burger, [mod(k240)], quantity: 2);
        add(c, burger, [mod(500, quantity: 2)], quantity: 3);
        final live = viewOf(c).subtotalMinor;
        expect(live, 12000 + 16500);

        final parked = ParkedCart(
          id: 'park-1',
          createdAt: DateTime.utc(2026, 8, 5),
          updatedAt: DateTime.utc(2026, 8, 5),
          orderType: OrderType.takeaway,
          draft: cartOf(c).captureDraft(),
        );
        expect(
          parked.subtotalMinor,
          live,
          reason: 'the parked badge must never show a different amount',
        );
        expect(parked.subtotalMinor, 28500);
      },
    );

    test('C2 the subtotal survives a JSON round-trip unchanged', () {
      final c = container();
      add(c, burger, [mod(k240)], quantity: 2);
      final parked = ParkedCart(
        id: 'park-2',
        createdAt: DateTime.utc(2026, 8, 5),
        updatedAt: DateTime.utc(2026, 8, 5),
        orderType: OrderType.takeaway,
        draft: cartOf(c).captureDraft(),
      );
      final revived = ParkedCart.fromJson(
        jsonDecode(jsonEncode(parked.toJson())) as Map<String, Object?>,
      );
      expect(revived.subtotalMinor, 12000);
    });
  });

  group('D. the submitted payload carries the configured-unit total', () {
    test('D1 line_total_minor is itemQty × (unit + Σ), while the wire keeps '
        'the BARE unit price and the UNIT modifier delta', () async {
      final repo = _Repo();
      final c = container(repo: repo);
      add(c, burger, [mod(500, quantity: 2)], quantity: 3);
      final v = viewOf(c);
      expect(v.subtotalMinor, 16500);

      await c
          .read(outboxControllerProvider.notifier)
          .submit(
            lines: v.lines,
            subtotalMinor: v.subtotalMinor,
            currencyCode: v.currencyCode,
            orderType: OrderType.takeaway,
          );

      final payload =
          jsonDecode(repo.enqueued.single.payloadJson) as Map<String, Object?>;
      final item = (payload['order_items'] as List)
          .cast<Map<String, Object?>>()
          .single;

      expect(item['quantity'], 3);
      expect(
        item['unit_price_minor_snapshot'],
        4500,
        reason: 'the wire still carries the BARE base price',
      );
      expect(item['line_total_minor'], 16500);
      final m = (item['modifiers'] as List).cast<Map<String, Object?>>().single;
      expect(
        m['price_minor_snapshot'],
        500,
        reason: 'never the pre-multiplied 1000',
      );
      expect(m['quantity'], 2);
      expect(payload['subtotal_minor'], 16500);
      expect(payload['grand_total_minor'], 16500);
    });

    test(
      'D2 the SERVER formula recomputed from the payload reproduces it',
      () async {
        final repo = _Repo();
        final c = container(repo: repo);
        add(c, burger, [mod(k240)], quantity: 2);
        add(c, wrap, [mod(0)]);
        final v = viewOf(c);
        await c
            .read(outboxControllerProvider.notifier)
            .submit(
              lines: v.lines,
              subtotalMinor: v.subtotalMinor,
              currencyCode: v.currencyCode,
              orderType: OrderType.takeaway,
            );
        final payload =
            jsonDecode(repo.enqueued.single.payloadJson)
                as Map<String, Object?>;
        final items = (payload['order_items'] as List)
            .cast<Map<String, Object?>>();

        // qty × (unit + Σ(delta × mqty)) — the corrected server rule.
        var sum = 0;
        for (final item in items) {
          final qty = item['quantity']! as int;
          final unit = item['unit_price_minor_snapshot']! as int;
          final mods = (item['modifiers'] as List).cast<Map<String, Object?>>();
          final perUnit = mods.fold<int>(
            0,
            (s, m) =>
                s +
                (m['price_minor_snapshot']! as int) * (m['quantity']! as int),
          );
          expect(item['line_total_minor'], qty * (unit + perUnit));
          sum += qty * (unit + perUnit);
        }
        expect(payload['subtotal_minor'], sum);
        expect(sum, 12000 + 3800);
      },
    );
  });
}
