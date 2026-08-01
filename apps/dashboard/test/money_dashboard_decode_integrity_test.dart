import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/data/order_history_repository.dart';
import 'package:restoflow_dashboard/src/data/real_order_history_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// MONEY-CODEX-FINAL-CORRECTIONS-004 (F5) — the OWNER-FACING money decoder
/// fails closed.
///
/// THE DEFECT. `RealOrderHistoryRepository._int` was
///
///   static int _int(Object? value, {int fallback = 0}) =>
///       value is int ? value : int.tryParse('$value') ?? fallback;
///
/// and it was called for TWELVE money fields: the list row's grand total, the
/// detail's subtotal / discount / tax / grand total, every line's unit price,
/// line discount and line total, every modifier's price, and every payment's
/// amount, tendered and change.
///
/// A value this build could not read therefore became **0**, and 0 is not an
/// error on a money screen — it is a NUMBER. The owner saw a real order with a
/// real code, a real customer and a real timestamp, priced at 0.00. Nothing
/// anywhere said the figure was invented. That is the worst failure mode a
/// reporting surface has: it is indistinguishable from a genuinely free order,
/// it sums into whatever the operator adds up by eye, and it is the basis for
/// decisions about staff, pricing and takings.
///
/// THE RULE. Money is read exactly or the read FAILS. This repository already
/// promises exactly that in its own library docstring — "never fabricated
/// data, never a silent demo fallback" — and `OrderHistoryException` is the
/// signal it already uses. A screen that says "could not load" is honest; a
/// screen showing 0.00 is not.
///
/// ATOMIC, deliberately. One unreadable field rejects the whole response
/// rather than dropping the row: an owner silently missing an order from a
/// history list has no way to know a number is absent, and the remaining rows
/// still look like the complete picture.
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._payload);
  final Object? _payload;
  @override
  Future<Object?> invoke(String f, Map<String, dynamic> p) async => _payload;
}

MembershipContext _scope() => const MembershipContext(
  id: 'm1',
  organizationId: 'org-1',
  organizationName: 'Org 1',
  restaurantId: 'rest-1',
  restaurantName: 'Rest 1',
  branchId: 'branch-1',
  branchName: 'Branch 1',
  role: MembershipRole.orgOwner,
  status: 'active',
);

RealOrderHistoryRepository _repo(Object? payload) => RealOrderHistoryRepository(
  null,
  scope: _scope(),
  transport: _FakeTransport(payload),
);

/// Base 4500 + one paid modifier 1500, quantity 2 => 12000 (002A formula B).
const kBase = 4500;
const kDelta = 1500;
const kLineTotal = 12000;

Map<String, dynamic> _row([Map<String, dynamic> o = const {}]) =>
    <String, dynamic>{
      'order_id': 'o1',
      'order_code': '#01D001',
      'status': 'completed',
      'order_type': 'dine_in',
      'created_at': '2026-08-05 10:00',
      'item_count': 2,
      'grand_total_minor': kLineTotal,
      'payment_status': 'paid',
      'payment_method': 'cash',
      'paid_amount_minor': kLineTotal,
      ...o,
    };

Map<String, dynamic> _history({List<Map<String, dynamic>>? rows}) =>
    <String, dynamic>{
      'ok': true,
      'entity': 'owner_order_history',
      'currency_code': 'ILS',
      'orders': rows ?? <Map<String, dynamic>>[_row()],
      'has_more': false,
      'next_cursor': null,
    };

Map<String, dynamic> _payment([Map<String, dynamic> o = const {}]) =>
    <String, dynamic>{
      'method': 'cash',
      'status': 'completed',
      'amount_minor': kLineTotal,
      'tendered_minor': kLineTotal,
      'change_minor': 0,
      'receipt_number': 'R-100',
      'created_at': '2026-08-05 10:01',
      ...o,
    };

Map<String, dynamic> _modifier([Map<String, dynamic> o = const {}]) =>
    <String, dynamic>{
      'option_name': '240g',
      'modifier_name': 'Meat',
      'quantity': 1,
      'price_minor': kDelta,
      ...o,
    };

Map<String, dynamic> _item([Map<String, dynamic> o = const {}]) =>
    <String, dynamic>{
      'order_item_id': 'i1',
      'name': 'Burger',
      'quantity': 2,
      'unit_price_minor': kBase,
      'line_discount_minor': 0,
      'line_total_minor': kLineTotal,
      'modifiers': <Map<String, dynamic>>[_modifier()],
      ...o,
    };

Map<String, dynamic> _detail({
  Map<String, dynamic> order = const {},
  List<Map<String, dynamic>>? items,
  List<Map<String, dynamic>>? payments,
}) => <String, dynamic>{
  'ok': true,
  'entity': 'owner_order_detail',
  'currency_code': 'ILS',
  'order': <String, dynamic>{
    'order_id': 'o1',
    'order_code': '#01D001',
    'status': 'completed',
    'order_type': 'dine_in',
    'created_at': '2026-08-05 10:00',
    'currency_code': 'ILS',
    'subtotal_minor': kLineTotal,
    'discount_total_minor': 0,
    'tax_total_minor': 0,
    'grand_total_minor': kLineTotal,
    'items': items ?? <Map<String, dynamic>>[_item()],
    'payments': payments ?? <Map<String, dynamic>>[_payment()],
    ...order,
  },
};

/// Everything a bigint money field must never silently become 0.
const _badMoney = <Object?>[
  null,
  'oops',
  '',
  true,
  12000.5,
  // F5: a numeric STRING is corruption too — see A4.
  '12000',
  '0',
  <Object?>[12000],
  <String, Object?>{'v': 12000},
];

void main() {
  group('A. the LIST row total', () {
    test('A0 a valid row decodes exactly', () async {
      final page = await _repo(
        _history(),
      ).loadHistory(const OrderHistoryQuery());
      expect(page.rows.single.grandTotalMinor, kLineTotal);
      expect(page.rows.single.paidAmountMinor, kLineTotal);
    });

    for (final bad in _badMoney) {
      test('A1 grand_total_minor ${bad.runtimeType} is a FAILED READ, never '
          '0.00', () async {
        expect(
          () => _repo(
            _history(
              rows: [
                _row({'grand_total_minor': bad}),
              ],
            ),
          ).loadHistory(const OrderHistoryQuery()),
          throwsA(isA<OrderHistoryException>()),
          reason:
              'the owner saw a real order, with a real code and customer, '
              'priced at zero — and nothing told them the number was invented',
        );
      });
    }

    for (final bad in <Object?>[
      'oops',
      true,
      12000.5,
      <Object?>[1],
    ]) {
      test('A2 an optional paid_amount_minor of ${bad.runtimeType} is a '
          'FAILED READ (absent stays absent)', () async {
        expect(
          () => _repo(
            _history(
              rows: [
                _row({'paid_amount_minor': bad}),
              ],
            ),
          ).loadHistory(const OrderHistoryQuery()),
          throwsA(isA<OrderHistoryException>()),
        );
      });
    }

    test('A3 a genuinely absent paid_amount_minor is legitimate — an unpaid '
        'order has no payment to sum', () async {
      final page = await _repo(
        _history(
          rows: [
            _row({'paid_amount_minor': null}),
          ],
        ),
      ).loadHistory(const OrderHistoryQuery());
      expect(page.rows.single.paidAmountMinor, isNull);
    });

    // MONEY-CODEX-FINAL-CLOSURE-005 (F5) — THIS EXPECTATION WAS CORRECTED.
    //
    // A4 used to assert that a numeric STRING decodes to its integer, on the
    // theory that "PostgREST can render a bigint as a JSON string". That is not
    // true of THIS path. `owner_order_history` / `owner_order_detail` are RPCs
    // returning ONE jsonb document; the money keys are built with
    // `jsonb_build_object(... , 'grand_total_minor', o.grand_total_minor, ...)`
    // from bigint columns, so they arrive as JSON numbers and Dart decodes them
    // as `int`. A String in a money field is therefore not a wire form — it is
    // evidence that something between the column and here reshaped the value,
    // and a reshaped money value is exactly what must not be trusted.
    //
    // Accepting it also re-opened the coercion door the strict decoder closed:
    // `int.tryParse` silently accepts '0012000', ' 12000', '+12000' and
    // '-12000', so a padded or sign-flipped figure would have read as a clean
    // total. Money is an exact `int` or the read fails.
    for (final numericString in <Object?>[
      '12000',
      '0',
      '0012000',
      ' 12000',
      '+12000',
    ]) {
      test('A4 a numeric STRING ("$numericString") is a FAILED READ, not a '
          'total', () async {
        expect(
          () => _repo(
            _history(
              rows: [
                _row({'grand_total_minor': numericString}),
              ],
            ),
          ).loadHistory(const OrderHistoryQuery()),
          throwsA(isA<OrderHistoryException>()),
        );
      });
    }

    test('A5 an exact ZERO is a real total, not a failure', () async {
      final page = await _repo(
        _history(
          rows: [
            _row({'grand_total_minor': 0}),
          ],
        ),
      ).loadHistory(const OrderHistoryQuery());
      expect(
        page.rows.single.grandTotalMinor,
        0,
        reason:
            'a fully comped order really is 0 — the fix must distinguish that '
            'from a number we could not read',
      );
    });

    test('A6 ONE corrupt row rejects the WHOLE page — valid siblings are not '
        'shown around a fabricated one', () async {
      expect(
        () => _repo(
          _history(
            rows: [
              _row({'order_id': 'o1'}),
              _row({'order_id': 'o2', 'grand_total_minor': 'oops'}),
              _row({'order_id': 'o3'}),
            ],
          ),
        ).loadHistory(const OrderHistoryQuery()),
        throwsA(isA<OrderHistoryException>()),
        reason:
            'dropping the bad row silently would leave the owner reading a '
            'history that LOOKS complete while an order is missing from it',
      );
    });
  });

  group('B. the DETAIL header money', () {
    test('B0 a valid detail decodes exactly', () async {
      final d = await _repo(_detail()).loadDetail('o1');
      expect(d.subtotalMinor, kLineTotal);
      expect(d.grandTotalMinor, kLineTotal);
      expect(d.items.single.lineTotalMinor, kLineTotal);
      expect(d.items.single.unitPriceMinor, kBase);
      expect(d.items.single.modifiers.single.priceMinor, kDelta);
      expect(d.payments.single.amountMinor, kLineTotal);
    });

    for (final field in <String>[
      'subtotal_minor',
      'discount_total_minor',
      'tax_total_minor',
      'grand_total_minor',
    ]) {
      test('B1 $field that cannot be read is a FAILED READ, never 0', () async {
        expect(
          () => _repo(_detail(order: {field: 'oops'})).loadDetail('o1'),
          throwsA(isA<OrderHistoryException>()),
        );
      });
    }
  });

  group('C. the DETAIL line money', () {
    for (final field in <String>[
      'unit_price_minor',
      'line_discount_minor',
      'line_total_minor',
    ]) {
      for (final bad in <Object?>[null, 'oops', true, 4500.5]) {
        test('C1 line $field ${bad.runtimeType} is a FAILED READ', () async {
          expect(
            () => _repo(
              _detail(
                items: [
                  _item({field: bad}),
                ],
              ),
            ).loadDetail('o1'),
            throwsA(isA<OrderHistoryException>()),
          );
        });
      }
    }

    test('C2 a corrupt MODIFIER price is a failed read — it is the surcharge '
        'the customer was charged', () async {
      expect(
        () => _repo(
          _detail(
            items: [
              _item({
                'modifiers': [
                  _modifier({'price_minor': 'oops'}),
                ],
              }),
            ],
          ),
        ).loadDetail('o1'),
        throwsA(isA<OrderHistoryException>()),
      );
    });

    test('C3 a corrupt QUANTITY is a failed read — it multiplies the line '
        '(002A: line = qty x (unit + mods))', () async {
      expect(
        () => _repo(
          _detail(
            items: [
              _item({'quantity': 'oops'}),
            ],
          ),
        ).loadDetail('o1'),
        throwsA(isA<OrderHistoryException>()),
      );
    });

    test(
      'C4 an ABSENT modifier quantity keeps its documented default of 1',
      () async {
        final mod = _modifier()..remove('quantity');
        final d = await _repo(
          _detail(
            items: [
              _item({
                'modifiers': [mod],
              }),
            ],
          ),
        ).loadDetail('o1');
        expect(d.items.single.modifiers.single.quantity, 1);
      },
    );

    test('C5 ONE corrupt line rejects the whole order — no partly-priced '
        'detail is ever shown', () async {
      expect(
        () => _repo(
          _detail(
            items: [
              _item({'order_item_id': 'i1'}),
              _item({'order_item_id': 'i2', 'line_total_minor': 'oops'}),
            ],
          ),
        ).loadDetail('o1'),
        throwsA(isA<OrderHistoryException>()),
      );
    });
  });

  // MONEY-CODEX-FINAL-CLOSURE-005 (F5): the numeric-string form of EVERY money
  // field this repository decodes, in one place, so none is left tolerant.
  group('E. no money field anywhere accepts a numeric String', () {
    test('E1 detail header fields', () async {
      for (final field in <String>[
        'subtotal_minor',
        'discount_total_minor',
        'tax_total_minor',
        'grand_total_minor',
      ]) {
        expect(
          () => _repo(_detail(order: {field: '12000'})).loadDetail('o1'),
          throwsA(isA<OrderHistoryException>()),
          reason: 'detail $field',
        );
      }
    });

    test('E2 line fields', () async {
      for (final entry in <String, String>{
        'unit_price_minor': '4500',
        'line_discount_minor': '0',
        'line_total_minor': '12000',
        'quantity': '2',
      }.entries) {
        expect(
          () => _repo(
            _detail(
              items: [
                _item({entry.key: entry.value}),
              ],
            ),
          ).loadDetail('o1'),
          throwsA(isA<OrderHistoryException>()),
          reason: 'line ${entry.key}',
        );
      }
    });

    test('E3 modifier price', () async {
      expect(
        () => _repo(
          _detail(
            items: [
              _item({
                'modifiers': [
                  _modifier({'price_minor': '1500'}),
                ],
              }),
            ],
          ),
        ).loadDetail('o1'),
        throwsA(isA<OrderHistoryException>()),
      );
    });

    test('E4 payment fields', () async {
      for (final entry in <String, String>{
        'amount_minor': '12000',
        'tendered_minor': '15000',
        'change_minor': '3000',
      }.entries) {
        expect(
          () => _repo(
            _detail(
              payments: [
                _payment({entry.key: entry.value}),
              ],
            ),
          ).loadDetail('o1'),
          throwsA(isA<OrderHistoryException>()),
          reason: 'payment ${entry.key}',
        );
      }
    });

    test('E5 the optional paid_amount_minor', () async {
      expect(
        () => _repo(
          _history(
            rows: [
              _row({'paid_amount_minor': '12000'}),
            ],
          ),
        ).loadHistory(const OrderHistoryQuery()),
        throwsA(isA<OrderHistoryException>()),
      );
    });

    test(
      'E6 and a real integer still decodes exactly — including zero',
      () async {
        final d = await _repo(
          _detail(
            order: {'discount_total_minor': 0},
            payments: [
              _payment({'change_minor': 0}),
            ],
          ),
        ).loadDetail('o1');
        expect(d.discountTotalMinor, 0);
        expect(d.grandTotalMinor, kLineTotal);
        expect(d.payments.single.changeMinor, 0);
        expect(d.items.single.lineTotalMinor, kLineTotal);
      },
    );
  });

  group('D. the DETAIL payment money', () {
    for (final field in <String>[
      'amount_minor',
      'tendered_minor',
      'change_minor',
    ]) {
      for (final bad in <Object?>[null, 'oops', true, 12000.5]) {
        test('D1 payment $field ${bad.runtimeType} is a FAILED READ', () async {
          expect(
            () => _repo(
              _detail(
                payments: [
                  _payment({field: bad}),
                ],
              ),
            ).loadDetail('o1'),
            throwsA(isA<OrderHistoryException>()),
            reason:
                'a payment reading 0.00 says the customer paid nothing for an '
                'order the server settled',
          );
        });
      }
    }

    test('D2 a valid zero change decodes as zero', () async {
      final d = await _repo(
        _detail(
          payments: [
            _payment({'change_minor': 0}),
          ],
        ),
      ).loadDetail('o1');
      expect(d.payments.single.changeMinor, 0);
    });

    test('D3 an order with NO payments is legitimate', () async {
      final d = await _repo(_detail(payments: [])).loadDetail('o1');
      expect(d.payments, isEmpty);
      expect(d.grandTotalMinor, kLineTotal);
    });
  });
}
