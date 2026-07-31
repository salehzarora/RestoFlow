import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';

/// MONEY-LOCAL-DECODE-INTEGRITY-002B — Codex Blockers 2 and 3.
///
/// Financial and identity data must NEVER fail open. A record we cannot read
/// exactly is a record we are not entitled to re-price, re-state or re-bill.
///
/// THE LEGACY ALLOWANCES ARE EVIDENCE-BASED, not invented. `CartDraftLine.toJson`
/// has, since the single commit that introduced it (ab43893, MENU-ORDER-001),
/// ALWAYS written `menu_item_id`, `name`, `base_price_minor` and `quantity`, and
/// conditionally omitted `line_id`, `modifiers`, `note`, the display orders and
/// `prep_components`. So exactly those omissions are legitimate; anything else
/// missing is corruption.
///
/// Every money value here is an exact integer minor unit (D-007).

// ---------------------------------------------------------------------------
// A valid, current draft — the shape every assertion mutates ONE field of.
// ---------------------------------------------------------------------------
Map<String, Object?> validModifier() => <String, Object?>{
  'option_id': 'opt-240',
  'group_name': 'Meat',
  'option_name': '240g',
  'price_delta_minor': 1500,
  'quantity': 1,
};

Map<String, Object?> validLine() => <String, Object?>{
  'line_id': 'line-1',
  'menu_item_id': 'burger',
  'name': 'Burger',
  'base_price_minor': 4500,
  'quantity': 2,
  'modifiers': [validModifier()],
};

Map<String, Object?> validDraft() => <String, Object?>{
  'currency_code': 'ILS',
  'lines': [validLine()],
};

/// A draft whose single line has [key] replaced by [value].
Map<String, Object?> draftWithLineField(String key, Object? value) {
  final line = validLine()..[key] = value;
  return <String, Object?>{
    'currency_code': 'ILS',
    'lines': [line],
  };
}

Map<String, Object?> draftWithoutLineField(String key) {
  final line = validLine()..remove(key);
  return <String, Object?>{
    'currency_code': 'ILS',
    'lines': [line],
  };
}

const malformed = <Object?>[
  '4500',
  'oops',
  null,
  4500.0,
  true,
  <String, Object?>{},
  <Object?>[],
];

void main() {
  // =========================================================================
  group('A. the cart draft decodes exactly, or not at all', () {
    test('A0 a valid current draft round-trips exactly', () {
      final d = CartDraftSnapshot.fromJson(
        jsonDecode(jsonEncode(validDraft())) as Map<String, Object?>,
      );
      expect(d.currencyCode, 'ILS');
      expect(d.lines, hasLength(1));
      final l = d.lines.single;
      expect(l.lineId, 'line-1');
      expect(l.menuItemId, 'burger');
      expect(l.basePriceMinor, 4500);
      expect(l.quantity, 2);
      expect(l.modifiers.single.priceDeltaMinor, 1500);
      expect(l.modifiers.single.quantity, 1);
    });

    for (final bad in malformed) {
      test('A1 base_price_minor ${bad.runtimeType} is corrupt, never 0', () {
        expect(
          () => CartDraftSnapshot.fromJson(
            draftWithLineField('base_price_minor', bad),
          ),
          throwsA(isA<FormatException>()),
        );
      });
    }

    test('A2 an ABSENT base_price_minor is corrupt (always serialized)', () {
      expect(
        () => CartDraftSnapshot.fromJson(
          draftWithoutLineField('base_price_minor'),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    for (final bad in <Object?>[
      '2',
      'x',
      null,
      2.0,
      true,
      <String, Object?>{},
    ]) {
      test('A3 item quantity ${bad.runtimeType} is corrupt', () {
        expect(
          () => CartDraftSnapshot.fromJson(draftWithLineField('quantity', bad)),
          throwsA(isA<FormatException>()),
        );
      });
    }

    test('A4 a non-positive item quantity is corrupt', () {
      for (final q in <int>[0, -1]) {
        expect(
          () => CartDraftSnapshot.fromJson(draftWithLineField('quantity', q)),
          throwsA(isA<FormatException>()),
          reason: 'quantity $q would silently zero the line',
        );
      }
    });

    test('A5 an ABSENT quantity is corrupt (always serialized)', () {
      expect(
        () => CartDraftSnapshot.fromJson(draftWithoutLineField('quantity')),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'A6 a modifiers value that is NOT a list is corrupt — never "empty"',
      () {
        for (final bad in <Object?>[
          null,
          'none',
          0,
          <String, Object?>{'a': 1},
          true,
        ]) {
          expect(
            () => CartDraftSnapshot.fromJson(
              draftWithLineField('modifiers', bad),
            ),
            throwsA(isA<FormatException>()),
            reason:
                'reinterpreting ${bad.runtimeType} as [] deletes surcharges',
          );
        }
      },
    );

    test('A7 an ABSENT modifiers key IS legitimate — a plain line', () {
      final d = CartDraftSnapshot.fromJson(draftWithoutLineField('modifiers'));
      expect(d.lines.single.modifiers, isEmpty);
      expect(d.lines.single.basePriceMinor, 4500);
    });

    test('A8 a non-Map modifier ELEMENT invalidates the whole draft', () {
      for (final bad in <Object?>['x', 7, null, <Object?>[]]) {
        expect(
          () => CartDraftSnapshot.fromJson(
            draftWithLineField('modifiers', [validModifier(), bad]),
          ),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('A9 a non-Map LINE element invalidates the whole draft', () {
      for (final bad in <Object?>['x', 7, null, <Object?>[]]) {
        expect(
          () => CartDraftSnapshot.fromJson(<String, Object?>{
            'currency_code': 'ILS',
            'lines': [validLine(), bad],
          }),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('A10 a lines value that is not a list is corrupt', () {
      for (final bad in <Object?>[null, 'x', 3, <String, Object?>{}]) {
        expect(
          () => CartDraftSnapshot.fromJson(<String, Object?>{
            'currency_code': 'ILS',
            'lines': bad,
          }),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('A11 identifiers must be exact non-blank Strings', () {
      for (final key in <String>['menu_item_id', 'line_id']) {
        for (final bad in <Object?>[
          7,
          true,
          <Object?>[],
          <String, Object?>{},
          '',
          '   ',
        ]) {
          expect(
            () => CartDraftSnapshot.fromJson(draftWithLineField(key, bad)),
            throwsA(isA<FormatException>()),
            reason: '$key = ${bad.runtimeType} must not be coerced',
          );
        }
      }
    });

    test('A12 an ABSENT line_id IS legitimate (a fresh id is minted)', () {
      final d = CartDraftSnapshot.fromJson(draftWithoutLineField('line_id'));
      expect(d.lines.single.lineId, isNull);
    });

    test('A13 a free modifier with an exact integer 0 delta is VALID', () {
      final m = validModifier()..['price_delta_minor'] = 0;
      final d = CartDraftSnapshot.fromJson(
        draftWithLineField('modifiers', [m]),
      );
      expect(d.lines.single.modifiers.single.priceDeltaMinor, 0);
    });

    test('A14 an ABSENT legacy modifier quantity still decodes as 1', () {
      final m = validModifier()..remove('quantity');
      final d = CartDraftSnapshot.fromJson(
        draftWithLineField('modifiers', [m]),
      );
      expect(d.lines.single.modifiers.single.quantity, 1);
    });

    test('A15 MIXED valid and corrupt lines reject the WHOLE draft — no '
        'partial cart, no cheaper order', () {
      final bad = validLine()..['base_price_minor'] = 'oops';
      expect(
        () => CartDraftSnapshot.fromJson(<String, Object?>{
          'currency_code': 'ILS',
          'lines': [validLine(), bad, validLine()],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'A16 a corrupt element in FIRST, MIDDLE or LAST position all reject',
      () {
        final bad = validLine()..['quantity'] = '2';
        for (final lines in <List<Object?>>[
          [bad, validLine(), validLine()],
          [validLine(), bad, validLine()],
          [validLine(), validLine(), bad],
        ]) {
          expect(
            () => CartDraftSnapshot.fromJson(<String, Object?>{
              'currency_code': 'ILS',
              'lines': lines,
            }),
            throwsA(isA<FormatException>()),
          );
        }
      },
    );
  });

  // =========================================================================
  // The LOCAL order view and the LOCAL payment are where the fail-open decode
  // lives (`recent_order.dart`: `int.tryParse('$v') ?? 0`). The SERVER
  // snapshot decoder is already strict (`order_snapshot.dart`: `v is int ? v :
  // null`, negatives refused), so it is not re-litigated here.
  // =========================================================================
  Map<String, Object?> validLocalOrder() => <String, Object?>{
    'order_number': 'A-1',
    'currency_code': 'ILS',
    'order_type': 'takeaway',
    'subtotal_minor': 6000,
    'discount_total_minor': 0,
    'tax_total_minor': 0,
    'tax_rate_bp': 0,
    'lines': <Object?>[],
  };

  Map<String, Object?> record({
    Map<String, Object?>? order,
    Map<String, Object?>? payment,
  }) => <String, Object?>{
    'order': order ?? validLocalOrder(),
    'submitted_at': '2026-08-05T09:00:00.000Z',
    if (payment != null) 'payment': payment,
  };

  group('B. the LOCAL order view decodes its money exactly, or not at all', () {
    test('B0 a valid local record decodes with exact money', () {
      final o = PosRecentOrder.fromJson(
        jsonDecode(jsonEncode(record())) as Map<String, Object?>,
      );
      expect(o.order, isNotNull);
      expect(o.subtotalMinor, 6000);
    });

    for (final field in <String>[
      'subtotal_minor',
      'discount_total_minor',
      'tax_total_minor',
    ]) {
      for (final bad in <Object?>['6000', 'oops', 6000.0, true, <Object?>[]]) {
        test('B1 local $field ${bad.runtimeType} is corrupt, never 0', () {
          final o = validLocalOrder()..[field] = bad;
          expect(
            () => PosRecentOrder.fromJson(record(order: o)),
            throwsA(isA<FormatException>()),
            reason: 'a malformed total must never silently become 0',
          );
        });
      }
    }

    test('B2 a lines value that is not a list is corrupt', () {
      for (final bad in <Object?>['x', 7, <String, Object?>{}]) {
        final o = validLocalOrder()..['lines'] = bad;
        expect(
          () => PosRecentOrder.fromJson(record(order: o)),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('B3 a non-Map line element invalidates the record', () {
      final o = validLocalOrder()..['lines'] = <Object?>['x'];
      expect(
        () => PosRecentOrder.fromJson(record(order: o)),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // =========================================================================
  group('C. a corrupt PAYMENT can never look paid', () {
    Map<String, Object?> validPayment() => <String, Object?>{
      'payment_id': 'pay-1',
      'order_number': 'A-1',
      'device_id': 'dev-1',
      'local_operation_id': 'op-1',
      'method': 'cash',
      'status': 'completed',
      'amount_minor': 6000,
      'tendered_minor': 10000,
      'change_minor': 4000,
      'currency_code': 'ILS',
      'receipt_number': 'R-1',
      'paid_at': '2026-08-05T09:05:00.000Z',
    };

    test('C0 a valid cash payment is unchanged and CAN reprint', () {
      final o = PosRecentOrder.fromJson(record(payment: validPayment()));
      expect(o.payment, isNotNull);
      expect(o.payment!.amountMinor, 6000);
      expect(o.payment!.tenderedMinor, 10000);
      expect(o.payment!.changeMinor, 4000);
      expect(o.canReprintReceipt, isTrue);
    });

    test('C1 an UNKNOWN payment method must never become cash', () {
      for (final bad in <Object?>['bitcoin', '', null, 7, <Object?>[]]) {
        final p = validPayment()..['method'] = bad;
        expect(
          () => PosRecentOrder.fromJson(record(payment: p)),
          throwsA(isA<FormatException>()),
          reason: 'method ${bad.runtimeType} silently became cash',
        );
      }
    });

    test('C2 an UNKNOWN payment status must never become completed', () {
      for (final bad in <Object?>['weird', '', null, 7, <Object?>[]]) {
        final p = validPayment()..['status'] = bad;
        expect(
          () => PosRecentOrder.fromJson(record(payment: p)),
          throwsA(isA<FormatException>()),
          reason: 'status ${bad.runtimeType} silently became completed',
        );
      }
    });

    for (final field in <String>[
      'amount_minor',
      'tendered_minor',
      'change_minor',
    ]) {
      for (final bad in <Object?>['6000', 'oops', 6000.0, true, null]) {
        test('C3 payment $field ${bad.runtimeType} is corrupt, never 0', () {
          final p = validPayment()..[field] = bad;
          expect(
            () => PosRecentOrder.fromJson(record(payment: p)),
            throwsA(isA<FormatException>()),
          );
        });
      }
    }

    test('C4 a corrupt payment yields NO reprintable receipt — the whole '
        'record is rejected rather than fabricating one', () {
      // canReprintReceipt is `order != null && payment != null`, so a
      // fabricated payment object alone would offer a receipt for an order
      // that was never paid.
      final p = validPayment()..['status'] = 'weird';
      expect(
        () => PosRecentOrder.fromJson(record(payment: p)),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
