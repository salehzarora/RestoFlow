import 'dart:convert' show json, utf8;
import 'dart:typed_data';

import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:test/test.dart';

Map<String, Object?> _dispatchJson() => {
  'v': 1,
  'kind': 'initial_order',
  'order_code': '#AB12CD',
  'order_type': 'dine_in',
  'table_label': 'T4',
  'customer_display_name': 'Layla',
  'order_note': 'no onions please',
  'created_at': '2026-07-20T10:00:00Z',
  'items': [
    {
      'qty': 2,
      'name': 'Falafel',
      'note': 'extra crispy',
      'prep': [
        {'name': 'Tahini', 'quantity': 1, 'unit': 'tbsp'},
      ],
      'modifiers': [
        {'qty': 1, 'name': 'Extra pickles'},
      ],
    },
  ],
};

Map<String, Object?> _payloadJson({
  Map<String, Object?>? dispatch,
  Map<String, Object?>? destination,
}) => {
  'v': 1,
  'purpose': 'kitchen_ticket',
  'dispatch': dispatch ?? _dispatchJson(),
  'destination':
      destination ?? {'kind': 'network', 'host': '10.0.0.5', 'port': 9100},
  'paper_width': '80mm',
  'document_version': 1,
  'raster_version': 1,
};

void main() {
  group('KitchenSpoolLocalPayload (KITCHEN-MODE-001C2A §9)', () {
    test('network destination round trip', () {
      final payload = KitchenSpoolLocalPayload.fromJson(_payloadJson());
      final dest = payload.destination;
      expect(dest, isA<NetworkKitchenDestination>());
      expect((dest as NetworkKitchenDestination).host, '10.0.0.5');
      expect(dest.port, 9100);
      final round = KitchenSpoolLocalPayload.fromBytes(payload.toBytes());
      expect(round.toJson(), payload.toJson());
      expect(round.dispatch.orderCode, '#AB12CD');
      expect(
        round.dispatch.items.single.modifiers.single.name,
        'Extra pickles',
      );
    });

    test('bluetooth destination round trip', () {
      final payload = KitchenSpoolLocalPayload.fromJson(
        _payloadJson(
          destination: {'kind': 'bluetooth', 'address': '00:11:22:33:44:55'},
        ),
      );
      expect(payload.destination, isA<BluetoothKitchenDestination>());
      final round = KitchenSpoolLocalPayload.fromBytes(payload.toBytes());
      expect(
        (round.destination as BluetoothKitchenDestination).address,
        '00:11:22:33:44:55',
      );
    });

    test('missing-destination (blocked configuration) variant round trips', () {
      final raw = _payloadJson(destination: {'kind': 'none'});
      raw.remove('paper_width');
      final payload = KitchenSpoolLocalPayload.fromJson(raw);
      expect(payload.destination, isA<MissingKitchenDestination>());
      expect(payload.paperWidth, isNull);
      // The authoritative dispatch document is still fully present and
      // serializable (encryptable) even with no runnable destination.
      final round = KitchenSpoolLocalPayload.fromBytes(payload.toBytes());
      expect(round.dispatch.items, hasLength(1));
      expect(round.destination, isA<MissingKitchenDestination>());
    });

    test('void and service_round dispatch kinds decode', () {
      final voidDoc = KitchenDispatchDocument.fromJson({
        'v': 1,
        'kind': 'void',
        'order_code': '#AB12CD',
        'order_type': 'dine_in',
        'reason': 'changed mind',
        'void': true,
        'voided_at': '2026-07-20T10:05:00Z',
        'affected_item_count': 2,
      });
      expect(voidDoc.kind, KitchenSpoolDispatchType.voidNotice);
      expect(voidDoc.voidMarker, isTrue);
      final round = KitchenDispatchDocument.fromJson({
        'v': 1,
        'kind': 'service_round',
        'order_code': '#AB12CD',
        'order_type': 'dine_in',
        'round_id': 'r1000000-0000-0000-0000-000000000001',
        'round_number': 2,
        'items': [
          {'qty': 1, 'name': 'Falafel', 'modifiers': <Object?>[]},
        ],
      });
      expect(round.kind, KitchenSpoolDispatchType.serviceRound);
      expect(round.roundNumber, 2);
    });

    test('unknown fields are rejected at EVERY level (closed decoding)', () {
      // Root level.
      final root = _payloadJson()..['surprise'] = 1;
      expect(
        () => KitchenSpoolLocalPayload.fromJson(root),
        throwsA(isA<KitchenSpoolPayloadFormatException>()),
      );
      // Dispatch level.
      final dispatch = _dispatchJson()..['future_field'] = 'x';
      expect(
        () =>
            KitchenSpoolLocalPayload.fromJson(_payloadJson(dispatch: dispatch)),
        throwsA(isA<KitchenSpoolPayloadFormatException>()),
      );
      // Item level.
      final itemDispatch = _dispatchJson();
      ((itemDispatch['items']! as List).first as Map<String, Object?>)['x'] = 1;
      expect(
        () => KitchenSpoolLocalPayload.fromJson(
          _payloadJson(dispatch: itemDispatch),
        ),
        throwsA(isA<KitchenSpoolPayloadFormatException>()),
      );
      // Destination level.
      expect(
        () => KitchenSpoolLocalPayload.fromJson(
          _payloadJson(
            destination: {
              'kind': 'network',
              'host': 'h',
              'port': 9100,
              'extra': true,
            },
          ),
        ),
        throwsA(isA<KitchenSpoolPayloadFormatException>()),
      );
    });

    test('money-shaped fields are rejected (defence in depth)', () {
      for (final hostile in [
        {'unit_price_minor': 500},
        {'totalValue': 12},
        {'taxAmount': 3},
        {'currency': 'ILS'},
        {'payment': 'cash'},
      ]) {
        final dispatch = _dispatchJson()..addAll(hostile);
        expect(
          () => KitchenSpoolLocalPayload.fromJson(
            _payloadJson(dispatch: dispatch),
          ),
          throwsA(isA<KitchenSpoolPayloadFormatException>()),
          reason: 'must reject $hostile',
        );
      }
    });

    test('phone/address are rejected inside the dispatch subtree', () {
      for (final hostile in [
        {'customerPhone': '05x'},
        {'delivery_address': 'street'},
      ]) {
        final dispatch = _dispatchJson()..addAll(hostile);
        expect(
          () => KitchenSpoolLocalPayload.fromJson(
            _payloadJson(dispatch: dispatch),
          ),
          throwsA(isA<KitchenSpoolPayloadFormatException>()),
        );
      }
    });

    test('valid customer display name and notes are accepted', () {
      final payload = KitchenSpoolLocalPayload.fromJson(_payloadJson());
      expect(payload.dispatch.customerDisplayName, 'Layla');
      expect(payload.dispatch.orderNote, 'no onions please');
      expect(payload.dispatch.items.single.note, 'extra crispy');
    });

    test(
      'unknown destination kind and unknown payload/dispatch versions are rejected',
      () {
        expect(
          () => KitchenSpoolLocalPayload.fromJson(
            _payloadJson(destination: {'kind': 'carrier-pigeon'}),
          ),
          throwsA(isA<KitchenSpoolPayloadFormatException>()),
        );
        final wrongVersion = _payloadJson()..['v'] = 9;
        expect(
          () => KitchenSpoolLocalPayload.fromJson(wrongVersion),
          throwsA(isA<KitchenSpoolPayloadFormatException>()),
        );
        final wrongPurpose = _payloadJson()..['purpose'] = 'receipt';
        expect(
          () => KitchenSpoolLocalPayload.fromJson(wrongPurpose),
          throwsA(isA<KitchenSpoolPayloadFormatException>()),
        );
      },
    );

    test('network port range is validated', () {
      expect(
        () => KitchenSpoolLocalPayload.fromJson(
          _payloadJson(
            destination: {'kind': 'network', 'host': 'h', 'port': 0},
          ),
        ),
        throwsA(isA<KitchenSpoolPayloadFormatException>()),
      );
    });

    test('malformed bytes are a typed error', () {
      expect(
        () => KitchenSpoolLocalPayload.fromBytes(
          Uint8List.fromList(utf8.encode('not-json')),
        ),
        throwsA(isA<KitchenSpoolPayloadFormatException>()),
      );
      expect(
        () => KitchenSpoolLocalPayload.fromBytes(
          Uint8List.fromList(utf8.encode(json.encode([1, 2]))),
        ),
        throwsA(isA<KitchenSpoolPayloadFormatException>()),
      );
    });

    test('endpoint data exists ONLY inside the encrypted serialization '
        '(the destination model), never anywhere plaintext-bound', () {
      // Structural statement: the only types carrying host/port/address are
      // the destination variants, which serialize exclusively inside
      // KitchenSpoolLocalPayload (the blob plaintext). The table contract
      // test (kitchen_spool_store_test) proves no plaintext column carries
      // them end-to-end.
      final net = const NetworkKitchenDestination(host: 'h', port: 9100);
      expect(net.toJson().keys, containsAll(['kind', 'host', 'port']));
      final bt = const BluetoothKitchenDestination(address: 'aa:bb');
      expect(bt.toJson()['kind'], 'bluetooth');
    });

    test(
      'sanitizeDestinationDisplayLabel normalizes endpoint-looking labels',
      () {
        expect(sanitizeDestinationDisplayLabel(null), isNull);
        expect(sanitizeDestinationDisplayLabel('  '), isNull);
        expect(
          sanitizeDestinationDisplayLabel('Kitchen Printer'),
          'Kitchen Printer',
        );
        expect(
          sanitizeDestinationDisplayLabel('EPSON 10.0.0.5'),
          'kitchen-printer',
        );
        expect(
          sanitizeDestinationDisplayLabel('printer 10.0.0.5:9100'),
          'kitchen-printer',
        );
        expect(
          sanitizeDestinationDisplayLabel('BT 00:11:22:33:44:55'),
          'kitchen-printer',
        );
        expect(
          sanitizeDestinationDisplayLabel('http://printer.local'),
          'kitchen-printer',
        );
      },
    );
  });
}
