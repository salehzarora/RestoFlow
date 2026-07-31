import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';

/// MONEY-LOCAL-ATOMICITY-003A [B/C/D] — strict identities, completed-only
/// receipts, and presence-aware authoritative snapshots.
///
/// SCOPE FENCES observed here deliberately, because tightening past them would
/// reject data the SERVER accepts and quarantine a real cashier's history:
///
///  * `group_name` / `option_name` are DISPLAY snapshots, not identities. The
///    write path can legitimately produce an empty string
///    (`pos_menu_provider` builds an option name as `(row['name'] ?? '')`), so
///    they are tightened to TYPE only — a String, blank allowed.
///  * Ids are stored UNTRIMMED and compared byte-exactly everywhere. A padded
///    id is REJECTED, never silently trimmed: trimming would re-point a stored
///    selection at a live group and re-price it — the class of defect 002C fixed.
///  * No local `change == tendered - amount` invariant. The client stores the
///    SHEET's amount but the SERVER's change, so a legitimate server-accepted
///    payment can fail that identity when the order total moved between
///    sheet-open and confirm. Enforcing it locally would quarantine real orders.
///  * `receipt_number` may be blank (nullable column) and `amount_minor` may be
///    0 (the server constrains only >= 0).
///
/// Every expected amount is an INDEPENDENT LITERAL.

const kBase = 4500;
const k240 = 1500;

Map<String, Object?> modifierJson([Map<String, Object?> o = const {}]) =>
    <String, Object?>{
      'option_id': 'opt-240',
      'modifier_group_id': 'grp-meat',
      'group_name': 'Meat',
      'option_name': '240g',
      'price_delta_minor': k240,
      'quantity': 1,
      ...o,
    };

Map<String, Object?> draftWithModifier(Map<String, Object?> modifier) =>
    <String, Object?>{
      'currency_code': 'ILS',
      'lines': <Object?>[
        <String, Object?>{
          'line_id': 'line-1',
          'menu_item_id': 'burger-meat',
          'name': 'Burger',
          'base_price_minor': kBase,
          'quantity': 2,
          'modifiers': <Object?>[modifier],
        },
      ],
    };

Map<String, Object?> paymentJson([Map<String, Object?> o = const {}]) =>
    <String, Object?>{
      'payment_id': 'pay-1',
      'order_number': '#A0001',
      'device_id': 'dev-1',
      'local_operation_id': 'op-1',
      'currency_code': 'ILS',
      'receipt_number': 'R-1',
      'paid_at': '2026-08-07T09:00:00.000Z',
      'amount_minor': 12000,
      'tendered_minor': 15000,
      'change_minor': 3000,
      'method': 'cash',
      'status': 'completed',
      ...o,
    };

Map<String, Object?> orderJson([Map<String, Object?> o = const {}]) =>
    <String, Object?>{
      'order_number': '#A0001',
      'currency_code': 'ILS',
      'order_type': 'takeaway',
      'subtotal_minor': 12000,
      'discount_total_minor': 0,
      'tax_total_minor': 0,
      'tax_rate_bp': 0,
      'lines': <Object?>[],
      ...o,
    };

Map<String, Object?> recordJson({
  Map<String, Object?>? payment,
  Object? snapshot,
  bool includeSnapshotKey = false,
  Map<String, Object?>? orderOverride,
}) => <String, Object?>{
  'order': orderJson(orderOverride ?? const {}),
  'submitted_at': '2026-08-07T09:00:00.000Z',
  if (payment != null) 'payment': payment,
  if (includeSnapshotKey) 'snapshot': snapshot,
};

Map<String, Object?> validSnapshot([Map<String, Object?> o = const {}]) =>
    <String, Object?>{
      'order_id': 'ord-1',
      'order_code': '#A0001',
      'status': 'preparing',
      'revision': 4,
      'subtotal_minor': 9000,
      'discount_total_minor': 0,
      'tax_total_minor': 0,
      'grand_total_minor': 9000,
      'created_at': '2026-08-07T09:00:00.000Z',
      'updated_at': '2026-08-07T09:00:00.000Z',
      'sync_at': '2026-08-07T09:00:00.000Z',
      ...o,
    };

void main() {
  // =========================================================================
  group('[B] modifier option identity is EXACT', () {
    test('B1 a non-String option_id is corrupt — never coerced', () {
      for (final bad in <Object?>[
        7,
        true,
        3.5,
        <Object?>[],
        <String, Object?>{},
        null,
      ]) {
        expect(
          () => CartDraftSnapshot.fromJson(
            draftWithModifier(modifierJson({'option_id': bad})),
          ),
          throwsA(isA<FormatException>()),
          reason: 'option_id ${bad.runtimeType} became a String via toString()',
        );
      }
    });

    test('B2 a blank or whitespace-only option_id is corrupt', () {
      for (final bad in <String>['', '   ', '\t', '\n']) {
        expect(
          () => CartDraftSnapshot.fromJson(
            draftWithModifier(modifierJson({'option_id': bad})),
          ),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('B3 a PADDED option_id is REJECTED, never silently trimmed — trimming '
        'would re-point a stored selection at a live group', () {
      expect(
        () => CartDraftSnapshot.fromJson(
          draftWithModifier(modifierJson({'option_id': ' opt-240'})),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('B4 a valid option_id decodes UNTRIMMED and exactly', () {
      final d = CartDraftSnapshot.fromJson(draftWithModifier(modifierJson()));
      final m = d.lines.single.modifiers.single;
      expect(m.optionId, 'opt-240');
      expect(m.modifierGroupId, 'grp-meat');
      expect(m.priceDeltaMinor, k240);
    });

    test('B5 group_name / option_name are TYPE-strict but may be blank — they '
        'are display snapshots, and the write path can produce empty', () {
      for (final key in <String>['group_name', 'option_name']) {
        for (final bad in <Object?>[
          7,
          true,
          <Object?>[],
          <String, Object?>{},
        ]) {
          expect(
            () => CartDraftSnapshot.fromJson(
              draftWithModifier(modifierJson({key: bad})),
            ),
            throwsA(isA<FormatException>()),
            reason: '$key ${bad.runtimeType} must not be coerced',
          );
        }
        // ...but an empty display name is legitimate history.
        final ok = CartDraftSnapshot.fromJson(
          draftWithModifier(modifierJson({key: ''})),
        );
        expect(ok.lines.single.modifiers, hasLength(1));
      }
    });
  });

  // =========================================================================
  group('[C] only a COMPLETED, coherent payment enables a receipt', () {
    test('C1 every non-completed KNOWN status refuses the record', () {
      for (final status in PaymentStatus.values.where((s) => !s.isPaid)) {
        expect(
          () => PosRecentOrder.fromJson(
            recordJson(payment: paymentJson({'status': status.wire})),
          ),
          throwsA(isA<FormatException>()),
          reason: '${status.wire} is not a settlement',
        );
      }
    });

    test(
      'C2 the COMPLETED status still decodes and still offers a receipt',
      () {
        final o = PosRecentOrder.fromJson(recordJson(payment: paymentJson()));
        expect(o.payment, isNotNull);
        expect(o.payment!.status, PaymentStatus.completed);
        expect(o.payment!.amountMinor, 12000);
        expect(o.canReprintReceipt, isTrue);
      },
    );

    test('C3 an UNPAID order offers no receipt and stays payable', () {
      final o = PosRecentOrder.fromJson(recordJson());
      expect(o.payment, isNull);
      expect(o.canReprintReceipt, isFalse);
    });

    test('C4 paid_at must be an exact String — an INTEGER date must not slip '
        'through string interpolation', () {
      for (final bad in <Object?>[
        20260805,
        true,
        <Object?>[],
        <String, Object?>{},
        null,
      ]) {
        expect(
          () => PosRecentOrder.fromJson(
            recordJson(payment: paymentJson({'paid_at': bad})),
          ),
          throwsA(isA<FormatException>()),
          reason:
              'paid_at ${bad.runtimeType} reached DateTime.tryParse via '
              'interpolation',
        );
      }
    });

    test('C5 a malformed paid_at STRING is still corrupt', () {
      expect(
        () => PosRecentOrder.fromJson(
          recordJson(payment: paymentJson({'paid_at': 'not-a-date'})),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('C6 negative money is corrupt', () {
      for (final key in <String>[
        'amount_minor',
        'tendered_minor',
        'change_minor',
      ]) {
        expect(
          () => PosRecentOrder.fromJson(
            recordJson(payment: paymentJson({key: -1})),
          ),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('C7 a ZERO amount and a BLANK receipt number are both legitimate — '
        'the server constrains amount >= 0 and receipt_number is nullable', () {
      final o = PosRecentOrder.fromJson(
        recordJson(
          payment: paymentJson({
            'amount_minor': 0,
            'tendered_minor': 0,
            'change_minor': 0,
            'receipt_number': '',
          }),
        ),
      );
      expect(o.payment!.amountMinor, 0);
      expect(o.payment!.receiptNumber, '');
      expect(o.canReprintReceipt, isTrue);
    });

    test('C8 a payment whose local triple does not balance is still ACCEPTED — '
        'the client stores the sheet amount and the SERVER change, so a real '
        'server-accepted payment can legitimately differ', () {
      final o = PosRecentOrder.fromJson(
        recordJson(
          payment: paymentJson({
            'amount_minor': 12000,
            'tendered_minor': 15000,
            // The order total dropped after the sheet opened; the server
            // returned a LARGER change than tendered - sheetAmount.
            'change_minor': 5000,
          }),
        ),
      );
      expect(
        o.payment!.changeMinor,
        5000,
        reason: 'enforcing the identity locally would quarantine a real order',
      );
      expect(o.canReprintReceipt, isTrue);
    });
  });

  // =========================================================================
  group('[D] authoritative snapshot: absent, valid and MALFORMED differ', () {
    test('D1 an ABSENT snapshot key is legitimate history', () {
      final o = PosRecentOrder.fromJson(recordJson());
      expect(o.snapshot, isNull);
      expect(o.subtotalMinor, 12000, reason: 'the local view answers');
    });

    test('D2 a VALID snapshot wins', () {
      final o = PosRecentOrder.fromJson(
        recordJson(includeSnapshotKey: true, snapshot: validSnapshot()),
      );
      expect(o.snapshot, isNotNull);
      expect(
        o.subtotalMinor,
        9000,
        reason: 'the SERVER is authoritative for money',
      );
    });

    test('D3 a PRESENT but MALFORMED snapshot is CORRUPTION — it must never '
        'silently fall back to the stale local money', () {
      for (final bad in <Object?>[
        <String, Object?>{'order_id': 'ord-1'}, // missing required fields
        <String, Object?>{...validSnapshot(), 'subtotal_minor': 'oops'},
        <String, Object?>{...validSnapshot(), 'revision': -1},
        <String, Object?>{...validSnapshot(), 'created_at': 12345},
        'not-a-map',
        7,
        <Object?>[],
      ]) {
        expect(
          () => PosRecentOrder.fromJson(
            recordJson(includeSnapshotKey: true, snapshot: bad),
          ),
          throwsA(isA<FormatException>()),
          reason:
              'a malformed ${bad.runtimeType} snapshot fell back to the '
              'local order, showing stale money as if it were current',
        );
      }
    });

    test('D4 an explicit NULL snapshot value is corruption, not absence', () {
      expect(
        () => PosRecentOrder.fromJson(
          recordJson(includeSnapshotKey: true, snapshot: null),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('D5 a malformed snapshot cannot resurrect a never-created shell', () {
      expect(
        () => PosRecentOrder.fromJson(<String, Object?>{
          ...recordJson(includeSnapshotKey: true, snapshot: 'garbage'),
          'never_created': true,
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // =========================================================================
  group('[D] order type fails closed', () {
    test('D6 every KNOWN order type parses exactly', () {
      for (final t in OrderType.values) {
        final o = PosRecentOrder.fromJson(
          recordJson(orderOverride: <String, Object?>{'order_type': t.name}),
        );
        expect(o.order!.orderType, t);
      }
    });

    test('D7 an UNKNOWN order-type token is corruption — never takeaway', () {
      for (final bad in <Object?>[
        'dinein',
        'DELIVERY',
        '',
        '  ',
        7,
        true,
        <Object?>[],
        <String, Object?>{},
        null,
      ]) {
        expect(
          () => PosRecentOrder.fromJson(
            recordJson(orderOverride: <String, Object?>{'order_type': bad}),
          ),
          throwsA(isA<FormatException>()),
          reason: 'order_type ${bad.runtimeType} silently became takeaway',
        );
      }
    });

    test('D8 an ABSENT order_type keeps its documented legacy default', () {
      final json = orderJson()..remove('order_type');
      final o = PosRecentOrder.fromJson(<String, Object?>{
        'order': json,
        'submitted_at': '2026-08-07T09:00:00.000Z',
      });
      expect(
        o.order!.orderType,
        OrderType.takeaway,
        reason: 'absence is history; a present unknown token is not',
      );
    });
  });
}
