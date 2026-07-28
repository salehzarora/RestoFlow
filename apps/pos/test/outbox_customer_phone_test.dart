// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 2): the DURABLE order.submit
// outbox is the authoritative phone source for the encrypted kitchen spool —
// available BEFORE the network push, so the phone survives even when the server
// dispatch is imported before the order reaches recent-orders. Synthetic numbers.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';

OutboxEntry _entry({
  required String orderId,
  String operationType = 'order.submit',
  String? phone,
  Object? phoneRaw = _unset,
  bool malformed = false,
}) {
  final body = <String, Object?>{
    'order_id': orderId,
    'order_items': <Object?>[],
    if (!identical(phoneRaw, _unset))
      'customer_phone': phoneRaw
    else if (phone != null)
      'customer_phone': phone,
  };
  return OutboxEntry(
    id: 'outbox-$orderId-$operationType',
    deviceId: 'dev-1',
    localOperationId: 'op-$orderId',
    operationType: operationType,
    targetEntity: 'order',
    targetId: orderId,
    payloadJson: malformed ? '{not json' : jsonEncode(body),
    summary: const OrderSummary(
      orderNumber: 'DEMO-1',
      orderType: OrderType.dineIn,
      tableLabel: null,
      itemCount: 1,
      subtotalMinor: 900,
      currencyCode: 'ILS',
    ),
    syncState: OutboxSyncState.pending,
    clientCreatedAt: DateTime.utc(2026, 7, 28),
  );
}

const _unset = Object();

void main() {
  group('customerPhoneFromOrderSubmitEntries', () {
    test('an order.submit op carrying the phone returns it', () {
      expect(
        customerPhoneFromOrderSubmitEntries([
          _entry(orderId: 'order-1', phone: '050-7654321'),
        ], 'order-1'),
        '050-7654321',
      );
    });

    test('a NON-order.submit op for the same order id is ignored', () {
      expect(
        customerPhoneFromOrderSubmitEntries([
          _entry(
            orderId: 'order-1',
            operationType: 'order.status',
            phone: '050-7654321',
          ),
        ], 'order-1'),
        isNull,
      );
    });

    test('a DIFFERENT order id is ignored (never a cross-order match)', () {
      expect(
        customerPhoneFromOrderSubmitEntries([
          _entry(orderId: 'order-2', phone: '050-7654321'),
        ], 'order-1'),
        isNull,
      );
    });

    test('a malformed payload body is skipped safely (no throw)', () {
      expect(
        customerPhoneFromOrderSubmitEntries([
          _entry(orderId: 'order-1', malformed: true),
          _entry(orderId: 'order-1', phone: '050-7654321'),
        ], 'order-1'),
        '050-7654321',
      );
    });

    test('a blank / non-string phone on the matched op yields null', () {
      expect(
        customerPhoneFromOrderSubmitEntries([
          _entry(orderId: 'order-1', phoneRaw: '   '),
        ], 'order-1'),
        isNull,
      );
      expect(
        customerPhoneFromOrderSubmitEntries([
          _entry(orderId: 'order-1', phoneRaw: 12345),
        ], 'order-1'),
        isNull,
      );
    });

    test('an op with no phone key yields null', () {
      expect(
        customerPhoneFromOrderSubmitEntries([
          _entry(orderId: 'order-1'),
        ], 'order-1'),
        isNull,
      );
    });

    test('the matching order.submit op is chosen among many', () {
      expect(
        customerPhoneFromOrderSubmitEntries([
          _entry(orderId: 'order-0', phone: '050-0000000'),
          _entry(orderId: 'order-1', phone: '054-1234567'),
          _entry(orderId: 'order-2', phone: '050-2222222'),
        ], 'order-1'),
        '054-1234567',
      );
    });
  });

  group('DemoOutboxStore.findOrderSubmitCustomerPhone', () {
    test('reads the phone from the enqueued durable order.submit op', () async {
      final store = DemoOutboxStore(delay: (_) async {});
      await store.enqueue(_entry(orderId: 'order-1', phone: '050-7654321'));
      expect(
        await store.findOrderSubmitCustomerPhone('order-1'),
        '050-7654321',
      );
      expect(await store.findOrderSubmitCustomerPhone('order-9'), isNull);
    });
  });

  // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 4): customer_phone is DATA ONLY —
  // excluded from the order.submit operation IDENTITY (mirrors the server's
  // `v_payload - 'customer_phone'`), while the transport payload still carries it.
  group('canonicalOperationIdentityPayload / operationIdentityKey', () {
    Map<String, dynamic> submit({
      String? phone,
      int subtotal = 900,
      String table = 't-1',
      String name = 'Layla',
    }) => <String, dynamic>{
      'order_id': 'order-1',
      'order_type': 'dine_in',
      'table_id': table,
      'customer_name': name,
      if (phone != null) 'customer_phone': phone,
      'order_items': <Object?>[
        <String, dynamic>{'menu_item_id': 'm1', 'quantity': 1},
      ],
      'subtotal_minor': subtotal,
      'grand_total_minor': subtotal,
    };

    test('the identity payload EXCLUDES customer_phone for order.submit; the '
        'transport payload still carries it', () {
      final p = submit(phone: '050-7654321');
      final id = canonicalOperationIdentityPayload('order.submit', p);
      expect(id.containsKey('customer_phone'), isFalse);
      expect(p['customer_phone'], '050-7654321', reason: 'transport unchanged');
    });

    test('changing ONLY the phone leaves the identity key equal', () {
      final a = operationIdentityKey(
        'order.submit',
        submit(phone: '050-7654321'),
      );
      final b = operationIdentityKey(
        'order.submit',
        submit(phone: '054-1234567'),
      );
      final none = operationIdentityKey('order.submit', submit());
      expect(a, b);
      expect(
        a,
        none,
        reason: 'phone-present and phone-less share the identity',
      );
    });

    test('changing any identity-bearing order field CHANGES the key', () {
      final base = operationIdentityKey(
        'order.submit',
        submit(phone: '050-7654321'),
      );
      expect(
        operationIdentityKey(
          'order.submit',
          submit(phone: '050-7654321', subtotal: 1000),
        ),
        isNot(base),
      );
      expect(
        operationIdentityKey(
          'order.submit',
          submit(phone: '050-7654321', table: 't-2'),
        ),
        isNot(base),
      );
      expect(
        operationIdentityKey(
          'order.submit',
          submit(phone: '050-7654321', name: 'Sam'),
        ),
        isNot(base),
      );
    });

    test('a NON-order.submit op keeps its FULL payload as identity', () {
      final p = <String, dynamic>{
        'order_id': 'order-1',
        'customer_phone': '050-7654321',
        'new_status': 'completed',
      };
      final id = canonicalOperationIdentityPayload('order.status', p);
      expect(id.containsKey('customer_phone'), isTrue);
      expect(identical(id, p), isTrue);
    });

    test('a phone-less order.submit payload is returned UNCHANGED', () {
      final p = submit();
      expect(
        identical(canonicalOperationIdentityPayload('order.submit', p), p),
        isTrue,
      );
    });
  });
}
