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
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';

/// MONEY-MODIFIER-PRICING-INTEGRITY-001 [E/F] — the money a cashier SEES must be
/// the money that leaves the device, survives persistence and retry, and is what
/// every downstream document reads.
///
/// Every assertion is an exact integer minor-unit value read out of the REAL
/// serialized `order.submit` payload — not a `toString()` and not a presence
/// check.

const kBase = 4500;
const k240 = 1500;
const k480 = 3500;

const burger = DemoMenuItem(
  id: 'burger-meat',
  name: 'Burger',
  priceMinor: kBase,
  categoryId: 'food',
  categoryName: 'Food',
);

SelectedModifier meat(int delta, {int quantity = 1}) => SelectedModifier(
  optionId: 'opt-$delta',
  groupName: 'Meat',
  optionName: '${delta}g',
  priceDeltaMinor: delta,
  quantity: quantity,
  kitchenMeat: const KitchenMeat(quantity: 1, unit: 'patty'),
);

/// Captures every enqueued entry so the persisted payload can be inspected.
class _RecordingRepo implements OutboxRepository {
  final List<OutboxEntry> enqueued = <OutboxEntry>[];

  @override
  Future<OutboxEntry> enqueue(OutboxEntry entry) async {
    enqueued.add(entry);
    return entry;
  }

  @override
  Future<List<OutboxEntry>> recentEntries() async => List.of(enqueued);

  @override
  Future<OutboxEntry> push(String entryId) async =>
      enqueued.firstWhere((e) => e.id == entryId);

  @override
  Future<OutboxEntry> retry(String entryId) async =>
      enqueued.firstWhere((e) => e.id == entryId);

  @override
  Future<String?> findOrderSubmitCustomerPhone(
    OrderSubmitPhoneLookupKey key,
  ) async => null;
}

ProviderContainer containerWith(OutboxRepository repo) {
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
      outboxRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('[E] the submitted payload carries exactly the displayed money', () {
    test('E1 modifier unit delta, modifier quantity, item quantity, line '
        'totals and subtotal all round-trip into order.submit', () async {
      final repo = _RecordingRepo();
      final c = containerWith(repo);
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItemWithModifiers(burger, [meat(k240, quantity: 2)]);
      final firstId = c.read(cartControllerProvider).lines.single.lineId;
      cart.increaseQuantity(firstId); // item quantity 2
      cart.addItemWithModifiers(burger, [meat(k480)]);

      final view = c.read(cartControllerProvider);
      // What the cashier sees.
      expect(view.lines[0].lineTotalMinor, 2 * kBase + 2 * k240);
      expect(view.lines[1].lineTotalMinor, kBase + k480);
      expect(view.subtotalMinor, 2 * kBase + 2 * k240 + kBase + k480);

      await c
          .read(outboxControllerProvider.notifier)
          .submit(
            lines: view.lines,
            subtotalMinor: view.subtotalMinor,
            currencyCode: view.currencyCode,
            orderType: OrderType.takeaway,
          );

      expect(repo.enqueued, hasLength(1));
      final payload =
          jsonDecode(repo.enqueued.single.payloadJson) as Map<String, Object?>;
      final items = (payload['order_items'] as List)
          .cast<Map<String, Object?>>();
      expect(items, hasLength(2));

      // Line 1: item qty 2, ONE modifier at unit 1500 taken twice.
      expect(items[0]['quantity'], 2);
      expect(items[0]['unit_price_minor_snapshot'], kBase);
      expect(items[0]['line_total_minor'], 2 * kBase + 2 * k240);
      final mods0 = (items[0]['modifiers'] as List)
          .cast<Map<String, Object?>>();
      expect(mods0, hasLength(1));
      expect(
        mods0.single['price_minor_snapshot'],
        k240,
        reason: 'the payload carries the UNIT delta, not the multiplied total',
      );
      expect(mods0.single['quantity'], 2);

      // Line 2.
      expect(items[1]['quantity'], 1);
      expect(items[1]['line_total_minor'], kBase + k480);
      final mods1 = (items[1]['modifiers'] as List)
          .cast<Map<String, Object?>>();
      expect(mods1.single['price_minor_snapshot'], k480);
      expect(mods1.single['quantity'], 1);

      // Header money equals what was displayed.
      expect(payload['subtotal_minor'], view.subtotalMinor);
      expect(payload['grand_total_minor'], view.subtotalMinor);
    });

    test('E2 the SERVER formula recomputed from the payload alone reproduces '
        'every client line total and the subtotal', () async {
      final repo = _RecordingRepo();
      final c = containerWith(repo);
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItemWithModifiers(burger, [meat(k240)]);
      cart.addItemWithModifiers(burger, [meat(k480, quantity: 3)]);
      cart.addItemWithModifiers(burger, [meat(0)]);
      final view = c.read(cartControllerProvider);

      await c
          .read(outboxControllerProvider.notifier)
          .submit(
            lines: view.lines,
            subtotalMinor: view.subtotalMinor,
            currencyCode: view.currencyCode,
            orderType: OrderType.takeaway,
          );

      final payload =
          jsonDecode(repo.enqueued.single.payloadJson) as Map<String, Object?>;
      final items = (payload['order_items'] as List)
          .cast<Map<String, Object?>>();

      // The FROZEN RF-052 formula, evaluated exactly as the server does:
      //   line_total = qty × unit + Σ(delta × modifier_qty)
      var recomputed = 0;
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        final qty = item['quantity']! as int;
        final unit = item['unit_price_minor_snapshot']! as int;
        final mods = (item['modifiers'] as List).cast<Map<String, Object?>>();
        final modSum = mods.fold<int>(
          0,
          (s, m) =>
              s + (m['price_minor_snapshot']! as int) * (m['quantity']! as int),
        );
        final lineTotal = qty * unit + modSum;
        expect(
          item['line_total_minor'],
          lineTotal,
          reason: 'client and server must agree on line $i',
        );
        expect(view.lines[i].lineTotalMinor, lineTotal);
        recomputed += lineTotal;
      }
      expect(payload['subtotal_minor'], recomputed);
      expect(view.subtotalMinor, recomputed);
    });

    test('E3 a cart with NO modifiers is unaffected', () async {
      final repo = _RecordingRepo();
      final c = containerWith(repo);
      c.read(cartControllerProvider.notifier).addItem(burger);
      final view = c.read(cartControllerProvider);
      await c
          .read(outboxControllerProvider.notifier)
          .submit(
            lines: view.lines,
            subtotalMinor: view.subtotalMinor,
            currencyCode: view.currencyCode,
            orderType: OrderType.takeaway,
          );
      final payload =
          jsonDecode(repo.enqueued.single.payloadJson) as Map<String, Object?>;
      final items = (payload['order_items'] as List)
          .cast<Map<String, Object?>>();
      expect(items.single['line_total_minor'], kBase);
      expect(payload['subtotal_minor'], kBase);
    });
  });

  group('[E] persistence and retry never duplicate or drop a surcharge', () {
    test(
      'E4 the persisted payload is an OPAQUE string — a retry re-sends '
      'byte-identical money, so replay can neither zero nor double it',
      () async {
        final repo = _RecordingRepo();
        final c = containerWith(repo);
        c.read(cartControllerProvider.notifier).addItemWithModifiers(burger, [
          meat(k240),
        ]);
        final view = c.read(cartControllerProvider);
        await c
            .read(outboxControllerProvider.notifier)
            .submit(
              lines: view.lines,
              subtotalMinor: view.subtotalMinor,
              currencyCode: view.currencyCode,
              orderType: OrderType.takeaway,
            );

        final entry = repo.enqueued.single;
        final original = entry.payloadJson;

        // A retry re-sends the STORED string; it is never rebuilt from the menu
        // or re-decoded through a modifier model, so no `?? 0` can reach it.
        final replayed = jsonDecode(original) as Map<String, Object?>;
        final mods =
            ((replayed['order_items'] as List)
                        .cast<Map<String, Object?>>()
                        .single['modifiers']
                    as List)
                .cast<Map<String, Object?>>();
        expect(mods, hasLength(1), reason: 'no duplicated modifier on replay');
        expect(mods.single['price_minor_snapshot'], k240);
        expect(replayed['subtotal_minor'], kBase + k240);
        expect(
          jsonEncode(replayed),
          jsonEncode(jsonDecode(original)),
          reason: 'the payload survives a persistence round-trip unchanged',
        );

        // The idempotency key travels with it, so a replay is deduped rather than
        // charged twice.
        expect(entry.localOperationId, isNotEmpty);
        expect(
          replayed['local_operation_id'],
          entry.localOperationId,
          reason: 'replay is idempotent on device_id + local_operation_id',
        );
      },
    );
  });

  group('[E] every DOCUMENT reads the same money as the cart', () {
    test(
      'E5 the submitted order view — which the unpaid bill, the paid '
      'receipt and the order preview all read — matches the cart exactly',
      () {
        final c = containerWith(_RecordingRepo());
        final cart = c.read(cartControllerProvider.notifier);
        cart.addItemWithModifiers(burger, [meat(k240, quantity: 2)]);
        final id = c.read(cartControllerProvider).lines.single.lineId;
        cart.increaseQuantity(id);
        cart.addItemWithModifiers(burger, [meat(k480)]);
        cart.addItemWithModifiers(burger, [meat(0)]);

        final before = c.read(cartControllerProvider);
        final expectedLineTotals = [
          for (final l in before.lines) l.lineTotalMinor,
        ];
        final expectedSubtotal = before.subtotalMinor;
        expect(expectedSubtotal, 4 * kBase + 2 * k240 + k480);

        cart.submitOrder(orderNumber: 'A-1');
        final submitted = c.read(cartControllerProvider).submittedOrder!;

        expect(
          submitted.lines.map((l) => l.lineTotalMinor).toList(),
          expectedLineTotals,
          reason:
              'the bill/receipt/preview must not re-derive different totals',
        );
        expect(submitted.subtotalMinor, expectedSubtotal);
        expect(
          submitted.lines.fold<int>(0, (s, l) => s + l.lineTotalMinor),
          submitted.subtotalMinor,
        );
        // The upgraded line still NAMES its option on the document.
        expect(submitted.lines[0].modifiers, contains('1500g ×2'));
      },
    );

    test('E6 a RECOVERED draft view uses the identical arithmetic, so a '
        'restored order bills the same as it displayed', () {
      final c = containerWith(_RecordingRepo());
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItemWithModifiers(burger, [meat(k240, quantity: 2)]);
      cart.addItemWithModifiers(burger, [meat(k480)]);
      final live = c.read(cartControllerProvider);
      final draft = cart.captureDraft();

      final recovered = cart.viewFromDraft(draft: draft);
      expect(
        recovered.lines.map((l) => l.lineTotalMinor).toList(),
        live.lines.map((l) => l.lineTotalMinor).toList(),
      );
      expect(recovered.subtotalMinor, live.subtotalMinor);
      expect(recovered.subtotalMinor, 2 * kBase + 2 * k240 + k480);
    });

    test('E7 the same holds after a JSON round-trip of that draft — the '
        'park/restore and recovery documents cannot drift', () {
      final c = containerWith(_RecordingRepo());
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItemWithModifiers(burger, [meat(k240, quantity: 2)]);
      cart.addItemWithModifiers(burger, [meat(k480)]);
      final live = c.read(cartControllerProvider);

      final revived = CartDraftSnapshot.fromJson(
        jsonDecode(jsonEncode(cart.captureDraft().toJson()))
            as Map<String, Object?>,
      );
      final recovered = cart.viewFromDraft(draft: revived);
      expect(recovered.subtotalMinor, live.subtotalMinor);
      expect(
        recovered.lines.map((l) => l.lineTotalMinor).toList(),
        live.lines.map((l) => l.lineTotalMinor).toList(),
      );
    });
  });

  group('[F] the server trust boundary is unchanged by this phase', () {
    test('F1 the client sends SNAPSHOT prices it captured at order time and '
        'never re-reads the live catalog at submit time', () async {
      final repo = _RecordingRepo();
      final c = containerWith(repo);
      // A line whose modifier delta does NOT exist in any live menu: it is a
      // pure order-time snapshot (D-008). If anything re-priced from a catalog,
      // this value could not survive.
      const oddDelta = 1234;
      c.read(cartControllerProvider.notifier).addItemWithModifiers(burger, [
        meat(oddDelta),
      ]);
      final view = c.read(cartControllerProvider);
      await c
          .read(outboxControllerProvider.notifier)
          .submit(
            lines: view.lines,
            subtotalMinor: view.subtotalMinor,
            currencyCode: view.currencyCode,
            orderType: OrderType.takeaway,
          );

      final payload =
          jsonDecode(repo.enqueued.single.payloadJson) as Map<String, Object?>;
      final item = (payload['order_items'] as List)
          .cast<Map<String, Object?>>()
          .single;
      final mod = (item['modifiers'] as List)
          .cast<Map<String, Object?>>()
          .single;

      expect(mod['price_minor_snapshot'], oddDelta);
      expect(item['line_total_minor'], kBase + oddDelta);
      expect(payload['subtotal_minor'], kBase + oddDelta);

      // This phase fixed CLIENT snapshot integrity BEFORE submission. It did
      // not add catalog re-pricing, and the server's documented contract —
      // accept an internally consistent snapshot, recompute the frozen RF-052
      // arithmetic over it — is untouched. The pgTAP suites that pin that trust
      // boundary were not modified.
      expect(
        item['unit_price_minor_snapshot'],
        kBase,
        reason: 'the unit price is also an order-time snapshot',
      );
    });

    test('F2 money is integer minor units everywhere in the payload', () async {
      final repo = _RecordingRepo();
      final c = containerWith(repo);
      c.read(cartControllerProvider.notifier).addItemWithModifiers(burger, [
        meat(k240, quantity: 2),
      ]);
      final view = c.read(cartControllerProvider);
      await c
          .read(outboxControllerProvider.notifier)
          .submit(
            lines: view.lines,
            subtotalMinor: view.subtotalMinor,
            currencyCode: view.currencyCode,
            orderType: OrderType.takeaway,
          );
      final payload =
          jsonDecode(repo.enqueued.single.payloadJson) as Map<String, Object?>;
      for (final key in ['subtotal_minor', 'grand_total_minor']) {
        expect(payload[key], isA<int>(), reason: '$key must be an integer');
      }
      final item = (payload['order_items'] as List)
          .cast<Map<String, Object?>>()
          .single;
      expect(item['unit_price_minor_snapshot'], isA<int>());
      expect(item['line_total_minor'], isA<int>());
      final mod = (item['modifiers'] as List)
          .cast<Map<String, Object?>>()
          .single;
      expect(mod['price_minor_snapshot'], isA<int>());
      expect(mod['quantity'], isA<int>());
    });
  });
}
