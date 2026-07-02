import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';

/// RF-063 (approved decision A4): minimal, MONEY-FREE mapping of `sync_pull`
/// rows to KDS tickets.
void main() {
  group('KdsTicketMapper.map', () {
    test(
      'groups active items by (order, station) and derives ticket status',
      () {
        final tickets = KdsTicketMapper.map(
          orders: [
            {'id': 'o1', 'status': 'preparing', 'deleted_at': null},
          ],
          orderItems: [
            {
              'id': 'i1',
              'order_id': 'o1',
              'station_id': 'grill',
              'status': 'preparing',
              'quantity': 2,
              'menu_item_name_snapshot': 'Burger',
            },
            {
              'id': 'i2',
              'order_id': 'o1',
              'station_id': 'grill',
              'status': 'queued',
              'quantity': 1,
              'menu_item_name_snapshot': 'Steak',
            },
            {
              'id': 'i3',
              'order_id': 'o1',
              'station_id': 'bar',
              'status': 'queued',
              'quantity': 3,
              'menu_item_name_snapshot': 'Beer',
            },
          ],
          modifiers: const [],
        );

        expect(tickets.map((t) => t.kitchenTicketId), ['o1:bar', 'o1:grill']);
        final grill = tickets.firstWhere((t) => t.stationId == 'grill');
        expect(grill.status, KitchenTicketStatus.inPreparation);
        expect(grill.items.map((i) => '${i.name}x${i.quantity}'), [
          'Burgerx2',
          'Steakx1',
        ]);
        final bar = tickets.firstWhere((t) => t.stationId == 'bar');
        expect(bar.items.single.name, 'Beer');
      },
    );

    test('carries modifier option names as STRUCTURED lines (demo-readiness '
        'sprint — no longer flattened into the item name)', () {
      final tickets = KdsTicketMapper.map(
        orders: [
          {'id': 'o1', 'status': 'preparing'},
        ],
        orderItems: [
          {
            'id': 'i1',
            'order_id': 'o1',
            'station_id': 'grill',
            'status': 'preparing',
            'quantity': 1,
            'menu_item_name_snapshot': 'Burger',
          },
        ],
        modifiers: [
          {
            'id': 'm1',
            'order_item_id': 'i1',
            'option_name_snapshot': 'no onion',
          },
          {
            'id': 'm2',
            'order_item_id': 'i1',
            'option_name_snapshot': 'extra cheese',
          },
        ],
      );
      final item = tickets.single.items.single;
      expect(item.name, 'Burger');
      expect(item.modifiers, ['no onion', 'extra cheese']);
    });

    test('plucks the display fields: SAME order number as the POS, order '
        'type, table label (via the tables entity), and notes', () {
      final tickets = KdsTicketMapper.map(
        orders: [
          {
            'id': '4c7d2f10-1111-2222-3333-abcdefabc123',
            'status': 'submitted',
            'order_type': 'dine_in',
            'table_id': 'tbl-1',
            'notes': 'rush order',
          },
        ],
        orderItems: [
          {
            'id': 'i1',
            'order_id': '4c7d2f10-1111-2222-3333-abcdefabc123',
            'station_id': 'grill',
            'status': 'pending',
            'quantity': 2,
            'menu_item_name_snapshot': 'Burger',
            'notes': 'well done',
          },
        ],
        modifiers: const [],
        tables: [
          {'id': 'tbl-1', 'label': 'T3'},
        ],
      );
      final ticket = tickets.single;
      // The shared display code — identical to the POS confirmation number.
      expect(
        ticket.orderNumber,
        displayOrderCode('4c7d2f10-1111-2222-3333-abcdefabc123'),
      );
      expect(ticket.orderNumber, '#ABC123');
      expect(ticket.orderType, 'dine_in');
      expect(ticket.tableLabel, 'T3');
      expect(ticket.notes, 'rush order');
      expect(ticket.items.single.note, 'well done');
    });

    test(
      'ignores tombstoned orders, items, and modifiers (deleted_at != null)',
      () {
        final tickets = KdsTicketMapper.map(
          orders: [
            {'id': 'o1', 'status': 'preparing', 'deleted_at': null},
            {
              'id': 'o2',
              'status': 'preparing',
              'deleted_at': '2026-06-22T11:00:00+00:00',
            },
          ],
          orderItems: [
            {
              'id': 'i1',
              'order_id': 'o1',
              'station_id': 'grill',
              'status': 'preparing',
              'quantity': 1,
              'menu_item_name_snapshot': 'Live',
            },
            {
              'id': 'iDead',
              'order_id': 'o1',
              'station_id': 'grill',
              'status': 'preparing',
              'quantity': 1,
              'menu_item_name_snapshot': 'Dead',
              'deleted_at': '2026-06-22T11:00:00+00:00',
            },
            {
              'id': 'i2',
              'order_id': 'o2',
              'station_id': 'grill',
              'status': 'preparing',
              'quantity': 1,
              'menu_item_name_snapshot': 'OrphanOfDeadOrder',
            },
          ],
          modifiers: [
            {
              'id': 'mDead',
              'order_item_id': 'i1',
              'option_name_snapshot': 'should-not-appear',
              'deleted_at': '2026-06-22T11:00:00+00:00',
            },
          ],
        );
        expect(tickets.length, 1);
        expect(tickets.single.items.map((i) => i.name), ['Live']);
      },
    );

    test(
      'excludes non-active orders (completed/cancelled/voided/draft) and excluded item statuses',
      () {
        final tickets = KdsTicketMapper.map(
          orders: [
            {'id': 'oDone', 'status': 'completed'},
            {'id': 'oVoid', 'status': 'voided'},
            {'id': 'oDraft', 'status': 'draft'},
            {'id': 'oActive', 'status': 'ready'},
          ],
          orderItems: [
            {
              'id': 'i1',
              'order_id': 'oDone',
              'station_id': 'grill',
              'status': 'served',
              'quantity': 1,
              'menu_item_name_snapshot': 'X',
            },
            {
              'id': 'i2',
              'order_id': 'oActive',
              'station_id': 'grill',
              'status': 'voided',
              'quantity': 1,
              'menu_item_name_snapshot': 'VoidedItem',
            },
            {
              'id': 'i3',
              'order_id': 'oActive',
              'station_id': 'grill',
              'status': 'ready',
              'quantity': 1,
              'menu_item_name_snapshot': 'GoodItem',
            },
          ],
          modifiers: const [],
        );
        expect(tickets.length, 1);
        expect(tickets.single.kitchenTicketId, 'oActive:grill');
        expect(tickets.single.status, KitchenTicketStatus.ready);
        expect(tickets.single.items.map((i) => i.name), ['GoodItem']);
      },
    );

    test('items with no station_id fall into the unassigned bucket', () {
      final tickets = KdsTicketMapper.map(
        orders: [
          {'id': 'o1', 'status': 'submitted'},
        ],
        orderItems: [
          {
            'id': 'i1',
            'order_id': 'o1',
            'station_id': null,
            'status': 'pending',
            'quantity': 1,
            'menu_item_name_snapshot': 'Mystery',
          },
        ],
        modifiers: const [],
      );
      expect(tickets.single.stationId, KdsTicketMapper.unassignedStation);
      expect(tickets.single.status, KitchenTicketStatus.newTicket);
    });

    test('NO money field is required or read (kitchen redaction, T-003)', () {
      // Rows carry NO *_minor / price / total keys at all — mapping must succeed.
      final withoutMoney = KdsTicketMapper.map(
        orders: [
          {'id': 'o1', 'status': 'preparing'},
        ],
        orderItems: [
          {
            'id': 'i1',
            'order_id': 'o1',
            'station_id': 'grill',
            'status': 'preparing',
            'quantity': 2,
            'menu_item_name_snapshot': 'Burger',
          },
        ],
        modifiers: [
          {'id': 'm1', 'order_item_id': 'i1', 'option_name_snapshot': 'rare'},
        ],
      );

      // The same rows WITH money keys present must produce identical output —
      // proving the mapper ignores every money field.
      final withMoney = KdsTicketMapper.map(
        orders: [
          {
            'id': 'o1',
            'status': 'preparing',
            'subtotal_minor': 9999,
            'grand_total_minor': 12345,
          },
        ],
        orderItems: [
          {
            'id': 'i1',
            'order_id': 'o1',
            'station_id': 'grill',
            'status': 'preparing',
            'quantity': 2,
            'menu_item_name_snapshot': 'Burger',
            'unit_price_minor_snapshot': 500,
            'line_total_minor': 1000,
            'line_discount_minor': 0,
          },
        ],
        modifiers: [
          {
            'id': 'm1',
            'order_item_id': 'i1',
            'option_name_snapshot': 'rare',
            'price_minor_snapshot': 50,
          },
        ],
      );

      String render(List<KdsTicketView> ts) => ts
          .map(
            (t) =>
                '${t.kitchenTicketId}|${t.status.canonicalName}|'
                '${t.items.map((i) => '${i.name}x${i.quantity}').join(',')}',
          )
          .join(';');

      expect(render(withoutMoney), render(withMoney));
      expect(withoutMoney.single.items.single, isA<KdsItemView>());
    });
  });
}
