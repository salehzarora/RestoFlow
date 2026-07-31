import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_pos/src/data/parked_carts_store.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MONEY-LOCAL-DECODE-INTEGRITY-002B — the guarantees the two corrections buy,
/// pinned END TO END rather than at the decoder.
///
/// Strictness and preservation only mean something together. Strict alone
/// deletes the cashier's work; preservation alone keeps a record we would still
/// misprice. These tests hold both at once, through the REAL stores.

const _scope = PosSyncScope(
  organizationId: 'orgA',
  restaurantId: 'restA',
  branchId: 'branchA',
  deviceId: 'dev1',
);

const String _ordersKey = 'restoflow.pos.recent_orders.v1.till-1';

Map<String, Object?> _payment({
  Object? status = 'completed',
  Object? method = 'cash',
  Object? amount = 9000,
}) => <String, Object?>{
  'payment_id': 'pay-1',
  'order_number': 'A-1',
  'device_id': 'dev-1',
  'local_operation_id': 'op-1',
  'method': method,
  'status': status,
  'amount_minor': amount,
  'tendered_minor': 10000,
  'change_minor': 1000,
  'currency_code': 'ILS',
  'receipt_number': 'R-1',
  'paid_at': '2026-08-05T09:05:00.000Z',
};

Map<String, Object?> _order(String number, {Object? subtotal = 9000}) =>
    <String, Object?>{
      'order_number': number,
      'currency_code': 'ILS',
      'order_type': 'takeaway',
      'subtotal_minor': subtotal,
      'discount_total_minor': 0,
      'tax_total_minor': 0,
      'tax_rate_bp': 0,
      'lines': <Object?>[
        <String, Object?>{
          'name': 'Burger',
          'quantity': 2,
          'line_total_minor': 9000,
          'currency_code': 'ILS',
          'modifiers': <Object?>['240g'],
        },
      ],
    };

Map<String, Object?> _record(String number, {Map<String, Object?>? payment}) =>
    <String, Object?>{
      'order': _order(number),
      'submitted_at': '2026-08-05T09:00:00.000Z',
      if (payment != null) 'payment': payment,
    };

Future<SharedPreferences> _seedOrders(List<Object?> entries) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    _ordersKey: jsonEncode(<String, Object?>{
      'version': SharedPrefsRecentOrdersStore.schemaVersion,
      'orders': entries,
    }),
  });
  return SharedPreferences.getInstance();
}

List<Object?> _storedOrders(SharedPreferences prefs) =>
    ((jsonDecode(prefs.getString(_ordersKey)!) as Map)['orders']! as List)
        .cast<Object?>();

void main() {
  group('F. a receipt is only ever offered for a payment we can READ', () {
    test('F1 a real paid order keeps its receipt', () {
      final o = PosRecentOrder.fromJson(_record('A-1', payment: _payment()));
      expect(o.canReprintReceipt, isTrue);
      expect(o.payment!.amountMinor, 9000);
    });

    test('F2 an UNPAID order offers no receipt — unchanged, and the honest '
        'answer', () {
      final o = PosRecentOrder.fromJson(_record('A-1'));
      expect(o.payment, isNull);
      expect(o.canReprintReceipt, isFalse);
    });

    test('F3 a record whose payment cannot be read NEVER reaches the surface '
        'at all, so it can never offer a forged receipt', () async {
      for (final broken in <Map<String, Object?>>[
        _payment(status: 'weird'),
        _payment(method: 'bitcoin'),
        _payment(amount: '9000'),
      ]) {
        final prefs = await _seedOrders(<Object?>[
          _record('A-1', payment: broken),
        ]);
        final loaded = await SharedPrefsRecentOrdersStore(prefs).load('till-1');
        expect(loaded, isEmpty);
        expect(
          loaded.where((o) => o.canReprintReceipt),
          isEmpty,
          reason: 'a fabricated settlement must never print',
        );
      }
    });

    test('F4 one unreadable payment does not hide the readable orders beside '
        'it', () async {
      final prefs = await _seedOrders(<Object?>[
        _record('A-1', payment: _payment()),
        _record('A-2', payment: _payment(status: 'weird')),
        _record('A-3'),
      ]);
      final loaded = await SharedPrefsRecentOrdersStore(prefs).load('till-1');
      expect(loaded.map((o) => o.orderNumber), <String>['A-1', 'A-3']);
      expect(loaded.first.canReprintReceipt, isTrue);
      expect(loaded.last.canReprintReceipt, isFalse);
    });
  });

  group('G. strictness never invents a cheaper order', () {
    test('G0 a readable order reports its EXACT stored money', () {
      final o = PosRecentOrder.fromJson(_record('A-1'));
      expect(o.subtotalMinor, 9000);
      expect(o.order!.lines.single.lineTotalMinor, 9000);
      expect(o.order!.lines.single.modifiers, <String>['240g']);
    });

    test(
      'G1 there is no path by which a corrupt total surfaces as 0',
      () async {
        final prefs = await _seedOrders(<Object?>[
          _record('A-1'),
          <String, Object?>{
            'order': _order('A-2', subtotal: 'oops'),
            'submitted_at': '2026-08-05T09:00:00.000Z',
          },
        ]);
        final loaded = await SharedPrefsRecentOrdersStore(prefs).load('till-1');
        expect(loaded.map((o) => o.orderNumber), <String>['A-1']);
        expect(
          loaded.where((o) => o.subtotalMinor == 0),
          isEmpty,
          reason: 'the old decoder read a corrupt subtotal as a free order',
        );
      },
    );

    test('G2 and the order it refused is still on disk after an ordinary '
        'write — refused is not deleted', () async {
      final broken = <String, Object?>{
        'order': _order('A-2', subtotal: 'oops'),
        'submitted_at': '2026-08-05T09:00:00.000Z',
      };
      final prefs = await _seedOrders(<Object?>[_record('A-1'), broken]);
      final store = SharedPrefsRecentOrdersStore(prefs);

      // Three ordinary save cycles, as a shift would produce.
      for (var i = 0; i < 3; i++) {
        await store.persist('till-1', await store.load('till-1'));
      }

      expect(
        _storedOrders(prefs).map((e) => jsonEncode(e)),
        contains(jsonEncode(broken)),
        reason: 'repeated writes must not erode the quarantine',
      );
      expect(_storedOrders(prefs), hasLength(2), reason: 'nor duplicate it');
    });
  });

  group('H. the parked-cart store holds the same line under the new rules', () {
    test('H1 a parked cart whose MODIFIER MONEY is corrupt is quarantined, '
        'not silently discounted', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPrefsParkedCartsStore(prefs);

      await store.add(
        _scope,
        (id) => ParkedCart(
          id: id,
          createdAt: DateTime.utc(2026, 8, 5, 9),
          updatedAt: DateTime.utc(2026, 8, 5, 9),
          orderType: OrderType.takeaway,
          draft: const CartDraftSnapshot(
            currencyCode: 'ILS',
            lines: [
              CartDraftLine(
                menuItemId: 'burger-9',
                name: 'Burger',
                basePriceMinor: 4500,
                quantity: 2,
                modifiers: [
                  SelectedModifier(
                    optionId: 'opt-240',
                    groupName: 'Meat',
                    optionName: '240g',
                    priceDeltaMinor: 1500,
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      // Exactly the failure this phase is about: the surcharge arrives in a
      // shape we refuse to guess at. The OLD decoder read it as a free option.
      final key = parkedCartsStorageKey(_scope);
      final envelope = (jsonDecode(prefs.getString(key)!) as Map)
          .cast<String, Object?>();
      final carts = (envelope['carts']! as List).cast<Object?>();
      final line =
          (((carts.single as Map)['draft'] as Map)['lines'] as List).first
              as Map;
      (((line['modifiers'] as List).first) as Map)['price_delta_minor'] =
          '1500';
      final corrupted = jsonEncode(carts.single);
      envelope['carts'] = carts;
      await prefs.setString(key, jsonEncode(envelope));

      final snapshot = await store.load(_scope);
      expect(snapshot.carts, isEmpty, reason: 'it must not load underpriced');
      expect(snapshot.unreadable, hasLength(1));

      // A later, ordinary park must not destroy it.
      await store.add(
        _scope,
        (id) => ParkedCart(
          id: id,
          createdAt: DateTime.utc(2026, 8, 5, 10),
          updatedAt: DateTime.utc(2026, 8, 5, 10),
          orderType: OrderType.takeaway,
          draft: const CartDraftSnapshot(
            currencyCode: 'ILS',
            lines: [
              CartDraftLine(
                menuItemId: 'cola-1',
                name: 'Cola',
                basePriceMinor: 1000,
                quantity: 1,
              ),
            ],
          ),
        ),
      );

      final after = await store.load(_scope);
      expect(after.carts, hasLength(1));
      expect(after.carts.single.subtotalMinor, 1000);
      expect(after.unreadable, hasLength(1));
      expect(jsonEncode(after.unreadable.single), corrupted);
    });

    test('H2 a readable parked cart still prices its surcharge PER UNIT — the '
        '002A rule survives the stricter decode', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPrefsParkedCartsStore(prefs);
      await store.add(
        _scope,
        (id) => ParkedCart(
          id: id,
          createdAt: DateTime.utc(2026, 8, 5, 9),
          updatedAt: DateTime.utc(2026, 8, 5, 9),
          orderType: OrderType.takeaway,
          draft: const CartDraftSnapshot(
            currencyCode: 'ILS',
            lines: [
              CartDraftLine(
                menuItemId: 'burger-9',
                name: 'Burger',
                basePriceMinor: 4500,
                quantity: 2,
                modifiers: [
                  SelectedModifier(
                    optionId: 'opt-240',
                    groupName: 'Meat',
                    optionName: '240g',
                    priceDeltaMinor: 1500,
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final reloaded = await store.load(_scope);
      expect(reloaded.carts.single.subtotalMinor, 2 * (4500 + 1500));
    });
  });
}
