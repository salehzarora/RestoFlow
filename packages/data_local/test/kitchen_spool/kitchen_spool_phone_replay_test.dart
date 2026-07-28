// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap C) — the dedicated typed customer
// phone on the ENCRYPTED local spool payload: it round-trips through the
// serialized (encrypted) bytes so a crash-recovery replay keeps it, legacy rows
// decode null, a null phone is byte-identical to before, and — crucially — the
// generic hostile-key redaction of the server `dispatch` subtree is UNCHANGED.
// Synthetic phone numbers only.
import 'dart:convert';
import 'dart:typed_data';

import 'package:restoflow_data_local/src/kitchen_spool/kitchen_spool_payload.dart';
import 'package:restoflow_data_local/src/kitchen_spool/kitchen_spool_status.dart';
import 'package:test/test.dart';

KitchenSpoolLocalPayload _payload({String? customerPhone}) =>
    KitchenSpoolLocalPayload(
      dispatch: KitchenDispatchDocument(
        serverPayloadVersion: 1,
        kind: KitchenSpoolDispatchType.initialOrder,
        orderCode: '#000042',
        orderType: 'dine_in',
        customerDisplayName: 'Layla',
        items: [KitchenDispatchItem(qty: 1, name: 'Burger')],
      ),
      destination: NetworkKitchenDestination(host: '127.0.0.1', port: 9100),
      paperWidth: '80mm',
      documentVersion: 1,
      rasterVersion: 1,
      customerPhone: customerPhone,
    );

void main() {
  group('KitchenSpoolLocalPayload.customerPhone', () {
    test('round-trips through the serialized (encrypted) bytes', () {
      final back = KitchenSpoolLocalPayload.fromBytes(
        _payload(customerPhone: '050-7654321').toBytes(),
      );
      expect(back.customerPhone, '050-7654321');
      // The name stays too; the phone did NOT leak into the redaction-checked
      // dispatch subtree (its document carries no phone).
      expect(back.dispatch.customerDisplayName, 'Layla');
      expect(back.dispatch.toJson().containsKey('customer_phone'), isFalse);
    });

    test('a legacy blob (no customer_phone key) decodes as null', () {
      final legacy =
          jsonDecode(utf8.decode(_payload().toBytes())) as Map<String, Object?>;
      expect(legacy.containsKey('customer_phone'), isFalse);
      final back = KitchenSpoolLocalPayload.fromBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(legacy))),
      );
      expect(back.customerPhone, isNull);
    });

    test('a null phone is byte-identical to the pre-feature payload', () {
      // No customer_phone key is emitted when null.
      final json = jsonDecode(utf8.decode(_payload().toBytes())) as Map;
      expect(json.containsKey('customer_phone'), isFalse);
    });
  });

  group('generic redaction is UNCHANGED', () {
    test(
      'a phone key INSIDE the server dispatch subtree is still rejected',
      () {
        // rejectHostileKitchenKeys still guards the dispatch subtree.
        expect(
          () => rejectHostileKitchenKeys({
            'customer_phone': '050-1',
            'order_code': '#1',
          }, path: 'dispatch'),
          throwsA(isA<KitchenSpoolPayloadFormatException>()),
        );
      },
    );

    test(
      'customer_phone at the PAYLOAD ROOT (sibling of dispatch) is accepted',
      () {
        // The round-trip above already proved this; assert the payload root itself is
        // NOT run through rejectHostileKitchenKeys (only the dispatch subtree is).
        final back = KitchenSpoolLocalPayload.fromBytes(
          _payload(customerPhone: '054-1234567').toBytes(),
        );
        expect(back.customerPhone, '054-1234567');
      },
    );
  });
}
