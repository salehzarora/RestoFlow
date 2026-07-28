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
  String org = 'org-A',
  String rest = 'rest-A',
  String branch = 'branch-A',
  String device = 'dev-X',
  String operationType = 'order.submit',
  String localOp = 'op-1',
  String? targetId, // defaults to orderId
  String? payloadOrderId, // defaults to orderId
  String? phone,
  Object? phoneRaw = _unset,
  bool malformed = false,
}) {
  final body = <String, Object?>{
    'order_id': payloadOrderId ?? orderId,
    'order_items': <Object?>[],
    if (!identical(phoneRaw, _unset))
      'customer_phone': phoneRaw
    else if (phone != null)
      'customer_phone': phone,
  };
  return OutboxEntry(
    id: 'outbox-$orderId-$operationType-$localOp',
    deviceId: device,
    localOperationId: localOp,
    operationType: operationType,
    targetEntity: 'order',
    targetId: targetId ?? orderId,
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
    organizationId: org,
    restaurantId: rest,
    branchId: branch,
  );
}

OrderSubmitPhoneLookupKey _key({
  required String orderId,
  String org = 'org-A',
  String rest = 'rest-A',
  String branch = 'branch-A',
  String device = 'dev-X',
  String? localOp,
}) => OrderSubmitPhoneLookupKey(
  organizationId: org,
  restaurantId: rest,
  branchId: branch,
  deviceId: device,
  orderId: orderId,
  localOperationId: localOp,
);

const _unset = Object();

void main() {
  // Codex HIGH: the durable lookup must be FULLY SCOPED (org/restaurant/branch/
  // device + order identity) AND validate the recovered phone through the shared
  // normalizer, so a cross-scope or malformed durable value can never seed the
  // encrypted spool / printed ticket.
  group('customerPhoneFromOrderSubmitEntries — scope', () {
    test('an exact-scope order.submit op returns the NORMALIZED phone', () {
      expect(
        customerPhoneFromOrderSubmitEntries([
          _entry(orderId: 'O', phone: '  054-1234567  '),
        ], _key(orderId: 'O')),
        '054-1234567',
      );
    });

    test('a DIFFERENT organization (same device+order) is ignored', () {
      expect(
        customerPhoneFromOrderSubmitEntries([
          _entry(orderId: 'O', org: 'org-B', phone: '050-2222222'),
        ], _key(orderId: 'O', org: 'org-A')),
        isNull,
      );
    });

    test('a DIFFERENT restaurant is ignored', () {
      expect(
        customerPhoneFromOrderSubmitEntries([
          _entry(orderId: 'O', rest: 'rest-B', phone: '050-2222222'),
        ], _key(orderId: 'O', rest: 'rest-A')),
        isNull,
      );
    });

    test('a DIFFERENT branch is ignored', () {
      expect(
        customerPhoneFromOrderSubmitEntries([
          _entry(orderId: 'O', branch: 'branch-B', phone: '050-2222222'),
        ], _key(orderId: 'O', branch: 'branch-A')),
        isNull,
      );
    });

    test('a DIFFERENT device is ignored', () {
      expect(
        customerPhoneFromOrderSubmitEntries([
          _entry(orderId: 'O', device: 'dev-Y', phone: '050-2222222'),
        ], _key(orderId: 'O', device: 'dev-X')),
        isNull,
      );
    });

    test('CONFLICTING scopes: same device + order id, different org — each '
        'scope reads ONLY its own phone (never the other)', () {
      final entries = [
        _entry(
          orderId: 'O',
          org: 'org-A',
          device: 'dev-X',
          phone: '054-1111111',
        ),
        _entry(
          orderId: 'O',
          org: 'org-B',
          device: 'dev-X',
          phone: '050-2222222',
        ),
      ];
      expect(
        customerPhoneFromOrderSubmitEntries(
          entries,
          _key(orderId: 'O', org: 'org-A'),
        ),
        '054-1111111',
      );
      expect(
        customerPhoneFromOrderSubmitEntries(
          entries,
          _key(orderId: 'O', org: 'org-B'),
        ),
        '050-2222222',
      );
    });

    test('a wrong operation type is ignored', () {
      expect(
        customerPhoneFromOrderSubmitEntries([
          _entry(
            orderId: 'O',
            operationType: 'order.status',
            phone: '050-2222222',
          ),
        ], _key(orderId: 'O')),
        isNull,
      );
    });

    test('a targetId mismatch is ignored', () {
      expect(
        customerPhoneFromOrderSubmitEntries([
          _entry(orderId: 'O', targetId: 'OTHER', phone: '050-2222222'),
        ], _key(orderId: 'O')),
        isNull,
      );
    });

    test('a payload order_id mismatch is ignored', () {
      expect(
        customerPhoneFromOrderSubmitEntries([
          _entry(orderId: 'O', payloadOrderId: 'OTHER', phone: '050-2222222'),
        ], _key(orderId: 'O')),
        isNull,
      );
    });

    test('AMBIGUITY (two exact matches for the same key) resolves to null', () {
      final entries = [
        _entry(orderId: 'O', localOp: 'op-1', phone: '054-1111111'),
        _entry(orderId: 'O', localOp: 'op-2', phone: '050-2222222'),
      ];
      expect(
        customerPhoneFromOrderSubmitEntries(entries, _key(orderId: 'O')),
        isNull,
      );
    });

    test('a local_operation_id on the key narrows to the exact op', () {
      final entries = [
        _entry(orderId: 'O', localOp: 'op-1', phone: '054-1111111'),
        _entry(orderId: 'O', localOp: 'op-2', phone: '050-2222222'),
      ];
      expect(
        customerPhoneFromOrderSubmitEntries(
          entries,
          _key(orderId: 'O', localOp: 'op-2'),
        ),
        '050-2222222',
      );
    });

    test('a malformed body is skipped safely (no throw)', () {
      expect(
        customerPhoneFromOrderSubmitEntries([
          _entry(orderId: 'O', localOp: 'op-1', malformed: true),
          _entry(orderId: 'O', localOp: 'op-2', phone: '054-1234567'),
        ], _key(orderId: 'O')),
        '054-1234567',
      );
    });
  });

  // Codex HIGH: every recovered phone flows through the ONE shared validator, so a
  // malformed durable value NEVER enters the encrypted spool / printed ticket.
  group('customerPhoneFromOrderSubmitEntries — validation', () {
    String? lookup(Object? phoneRaw) => customerPhoneFromOrderSubmitEntries([
      _entry(orderId: 'O', phoneRaw: phoneRaw),
    ], _key(orderId: 'O'));

    test('letters (050-ABC-1234) -> null', () {
      expect(lookup('050-ABC-1234'), isNull);
    });
    test('a newline -> null', () {
      expect(lookup('054\n12345'), isNull);
    });
    test('fewer than 5 digits -> null', () {
      expect(lookup('12 34'), isNull);
    });
    test('over 32 chars -> null', () {
      expect(lookup('+${'9' * 40}'), isNull);
    });
    test('blank / whitespace -> null', () => expect(lookup('   '), isNull));
    test('a non-string phone -> null', () => expect(lookup(12345), isNull));
    test('no phone key -> null', () {
      expect(
        customerPhoneFromOrderSubmitEntries([
          _entry(orderId: 'O'),
        ], _key(orderId: 'O')),
        isNull,
      );
    });
    test('a valid international phone is preserved (trimmed)', () {
      expect(lookup('  +972 54 987 6543  '), '+972 54 987 6543');
    });
  });

  group('DemoOutboxStore.findOrderSubmitCustomerPhone', () {
    test(
      'reads the phone for the EXACT scope; a wrong-branch key -> null',
      () async {
        final store = DemoOutboxStore(delay: (_) async {});
        await store.enqueue(_entry(orderId: 'O', phone: '054-1234567'));
        expect(
          await store.findOrderSubmitCustomerPhone(_key(orderId: 'O')),
          '054-1234567',
        );
        expect(
          await store.findOrderSubmitCustomerPhone(
            _key(orderId: 'O', branch: 'branch-B'),
          ),
          isNull,
        );
      },
    );
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
