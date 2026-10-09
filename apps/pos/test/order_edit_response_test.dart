import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/data/order_edit_read_model.dart';
import 'package:restoflow_pos/src/data/order_edit_response.dart';

/// ORDER-EDIT-001E — the `order.edit` response classifier (plan step 4c, test
/// 8). Only a complete applied envelope, an allowlisted typed refusal or a
/// ledgered RAISE are definitive; everything else keeps the identity.

const _op = 'op-edit-1';
const _order = 'order-1';

/// The complete applied row `sync_push` returns: `app.edit_order`'s envelope
/// (`20261008170100`, :1894-1922) merged with the ledger stamp.
Map<String, Object?> _appliedRow({String channel = 'kds'}) => {
  'ok': true,
  'order_id': _order,
  'order_code': '#A1B2C3',
  'order_edit_id': 'edit-9',
  'edit_number': 2,
  'revision': 7,
  'order_status': 'preparing',
  'auto_completed': false,
  'kitchen_channel': channel,
  'kitchen_ack_required': true,
  'new_round_id': 'round-3',
  'new_round_number': 3,
  'unit1_closed': false,
  'rounds_closed': <Object?>[],
  'before': {
    'subtotal_minor': 6300,
    'discount_total_minor': 0,
    'tax_total_minor': 0,
    'grand_total_minor': 6300,
  },
  'totals': {
    'subtotal_minor': 5700,
    'discount_total_minor': 0,
    'tax_total_minor': 0,
    'grand_total_minor': 5700,
  },
  'changes': [
    {'kind': 'modify', 'remake': true},
    {'kind': 'remove', 'remake': false},
    {'kind': 'add', 'remake': false},
  ],
  if (channel == 'paper')
    'kitchen_dispatch': {
      'id': 'dispatch-1',
      'claim_expires_at': '2026-10-09T12:10:00Z',
    },
  'server_ts': '2026-10-09T12:00:00Z',
  'local_operation_id': _op,
  'operation_type': 'order.edit',
  'status': 'applied',
  'idempotency_replay': false,
};

Map<String, Object?> _envelope(Object? row) => {
  'ok': true,
  'results': [row],
  'server_ts': '2026-10-09T12:00:00Z',
};

Map<String, Object?> _refusedRow(String error, [Map<String, Object?>? extra]) =>
    {
      'ok': false,
      'error': error,
      'order_id': _order,
      ...?extra,
      'server_ts': '2026-10-09T12:00:00Z',
      'local_operation_id': _op,
      'operation_type': 'order.edit',
      'status': 'rejected',
      'idempotency_replay': false,
    };

OrderEditOutcome _classify(Object? raw) =>
    classifyOrderEditResponse(raw, localOperationId: _op, orderId: _order);

void main() {
  group('applied', () {
    test('a complete envelope is applied, with every fact', () {
      final o = _classify(_envelope(_appliedRow()));
      expect(o.kind, OrderEditOutcomeKind.applied);
      expect(o.isDefinitiveNo, isFalse);
      final a = o.applied!;
      expect(a.orderEditId, 'edit-9');
      expect(a.editNumber, 2);
      expect(a.revision, 7);
      expect(a.kitchenChannel, PosKitchenChannel.kds);
      expect(a.kitchenAckRequired, isTrue);
      expect(a.newRoundId, 'round-3');
      expect(a.newRoundNumber, 3);
      expect(a.remakeChangeCount, 1);
      expect(a.kitchenDispatch, isNull);
      expect(a.orderStatus, 'preparing');
      expect(a.autoCompleted, isFalse);
    });

    test('paper carries the claimed dispatch for ORDER-EDIT-001F', () {
      final a = _classify(_envelope(_appliedRow(channel: 'paper'))).applied!;
      expect(a.kitchenChannel, PosKitchenChannel.paper);
      expect(a.kitchenDispatch!.id, 'dispatch-1');
      expect(
        a.kitchenDispatch!.claimExpiresAt,
        DateTime.utc(2026, 10, 9, 12, 10),
      );
    });

    test('ORDER-EDIT-001F: the changes are kept in request order for the '
        'hand-built change slip', () {
      final row = _appliedRow(channel: 'paper')
        ..['changes'] = [
          {
            'kind': 'modify',
            'order_item_id': 'oi-1',
            'new_order_item_ids': ['n-1', 'n-2'],
            'remake': false,
          },
          {
            'kind': 'remove',
            'order_item_id': 'oi-2',
            'new_order_item_ids': <Object?>[],
          },
          {
            'kind': 'set_quantity',
            'order_item_id': 'oi-3',
            'new_order_item_ids': ['n-3'],
          },
          {
            'kind': 'add',
            'order_item_id': null,
            'new_order_item_ids': ['n-4'],
          },
        ];
      final changes = _classify(_envelope(row)).applied!.changes;
      expect(changes.map((c) => c.kind), [
        'modify',
        'remove',
        'set_quantity',
        'add',
      ]);
      expect(changes.map((c) => c.orderItemId), ['oi-1', 'oi-2', 'oi-3', null]);
      expect(changes.first.newOrderItemIds, ['n-1', 'n-2']);
      expect(changes.last.newOrderItemIds, ['n-4']);
    });

    test('ORDER-EDIT-001F: the changes are ALL OR NOTHING — one unreadable '
        'entry empties the list but never doubts the edit', () {
      Map<String, Object?> good() => {
        'kind': 'remove',
        'order_item_id': 'oi-2',
        'new_order_item_ids': <Object?>[],
      };
      final bad = <Object?>[
        'remove',
        {...good(), 'kind': 'remake'},
        {...good(), 'order_item_id': null},
        {...good(), 'order_item_id': ''},
        {...good(), 'kind': 'add', 'order_item_id': 'oi-2'},
        {...good(), 'new_order_item_ids': 'n-1'},
        {
          ...good(),
          'new_order_item_ids': ['n-1', ''],
        },
        {...good()}..remove('new_order_item_ids'),
      ];
      for (final entry in bad) {
        final row = _appliedRow(channel: 'paper')
          ..['changes'] = [good(), entry];
        final o = _classify(_envelope(row));
        expect(o.kind, OrderEditOutcomeKind.applied, reason: '$entry');
        expect(o.applied!.changes, isEmpty, reason: '$entry');
      }
    });

    test('the optional facts are tolerant', () {
      final row = _appliedRow()
        ..['new_round_id'] = null
        ..['new_round_number'] = null
        ..['changes'] = 'garbled'
        ..['kitchen_dispatch'] = {'id': ''}
        ..remove('order_status');
      final a = _classify(_envelope(row)).applied!;
      expect(a.newRoundId, isNull);
      expect(a.newRoundNumber, isNull);
      expect(a.remakeChangeCount, 0);
      expect(a.kitchenDispatch, isNull);
      expect(a.orderStatus, isNull);
    });

    final required = <String, List<Object?>>{
      'ok': [null, false, 'true', 1],
      'order_id': [null, 'order-2', 7],
      'order_edit_id': [null, '', '   ', 9],
      'edit_number': [null, 0, -1, '2', 2.0],
      'revision': [null, '7', 7.0],
      'kitchen_channel': [null, 'KDS', 'screen', 1],
      'kitchen_ack_required': [null, 'true', 1],
    };
    required.forEach((key, bad) {
      for (final value in [...bad, _absent]) {
        test('$key = ${value == _absent ? 'absent' : value} is unknown', () {
          final row = _appliedRow();
          if (value == _absent) {
            row.remove(key);
          } else {
            row[key] = value;
          }
          final o = _classify(_envelope(row));
          expect(o.kind, OrderEditOutcomeKind.unknown);
          expect(o.applied, isNull);
        });
      }
    });

    test('an applied row of ANOTHER operation type proves nothing', () {
      final row = _appliedRow()..['operation_type'] = 'order.items_add';
      expect(_classify(_envelope(row)).reason, 'operation_type_mismatch');
    });
  });

  group('refused (allowlisted, nothing written)', () {
    for (final code in kOrderEditRefusalCodes) {
      test('$code is a definitive refusal', () {
        final o = _classify(_envelope(_refusedRow(code)));
        expect(o.kind, OrderEditOutcomeKind.refused);
        expect(o.isDefinitiveNo, isTrue);
        expect(o.reason, code);
        expect(o.refusal!.code, code);
      });
    }

    test('the allowlist is exactly the §4.45.6 set', () {
      expect(kOrderEditRefusalCodes, {
        'invalid_device_type',
        'permission_denied',
        'invalid_payload',
        'no_changes',
        'too_many_changes',
        'duplicate_line_reference',
        'expected_totals_required',
        'feature_disabled',
        'order_not_editable',
        'order_already_settled',
        'kitchen_mode_changed',
        'line_changed',
        'line_has_discount',
        'legacy_line_not_editable',
        'reason_required',
        'item_unavailable',
        'modifier_option_not_in_scope',
        'modifier_prep_snapshot_stale',
        'invalid_item_payload',
        'edit_would_empty_order',
        'invalid_discount',
        'tax_mode_unsupported',
        'totals_mismatch',
      });
    });

    test('the error/detail pairs keep their detail', () {
      for (final detail in [
        'removal_not_permitted',
        'finished_food_needs_manager',
        'full_comp_permission_required',
      ]) {
        final r = _classify(
          _envelope(_refusedRow('permission_denied', {'detail': detail})),
        ).refusal!;
        expect(r.detail, detail);
      }
      expect(
        _classify(
          _envelope(
            _refusedRow('invalid_discount', {
              'detail': 'discount_exceeds_order_total',
            }),
          ),
        ).refusal!.detail,
        'discount_exceeds_order_total',
      );
    });

    test('line_changed keeps its stale ids', () {
      final r = _classify(
        _envelope(
          _refusedRow('line_changed', {
            'stale_ids': ['oi-1', 'oi-2', 7, null],
          }),
        ),
      ).refusal!;
      expect(r.staleIds, ['oi-1', 'oi-2']);
    });

    test('totals_mismatch keeps the server figures', () {
      final r = _classify(
        _envelope(
          _refusedRow('totals_mismatch', {
            'totals': {
              'subtotal_minor': 5700,
              'discount_total_minor': 300,
              'tax_total_minor': 918,
              'grand_total_minor': 6318,
            },
          }),
        ),
      ).refusal!;
      expect(r.totals!.subtotalMinor, 5700);
      expect(r.totals!.discountMinor, 300);
      expect(r.totals!.taxMinor, 918);
      expect(r.totals!.grandMinor, 6318);
      expect(
        _classify(
          _envelope(
            _refusedRow('totals_mismatch', {
              'totals': {'subtotal_minor': '5700'},
            }),
          ),
        ).refusal!.totals,
        isNull,
        reason: 'figures that are not exact integers are not figures',
      );
    });

    test('item_unavailable keeps the items it names', () {
      final r = _classify(
        _envelope(
          _refusedRow('item_unavailable', {
            'entity': 'order',
            'items': [
              {'menu_item_id': 'mi-1', 'name': 'Fries', 'reason': 'sold_out'},
              {'menu_item_id': 'mi-2', 'name': 'Cola', 'reason': 'unavailable'},
              'junk',
            ],
          }),
        ),
      ).refusal!;
      expect(r.items.map((i) => i.name), ['Fries', 'Cola']);
      expect(r.items.first.reason, 'sold_out');
    });

    test('order_not_editable keeps the order status', () {
      expect(
        _classify(
          _envelope(
            _refusedRow('order_not_editable', {'order_status': 'completed'}),
          ),
        ).refusal!.orderStatus,
        'completed',
      );
    });

    test('sync_push identity hardening (invalid_payload, no ledger row) is '
        'a refusal', () {
      final o = _classify(
        _envelope({
          'local_operation_id': _op,
          'operation_type': 'order.edit',
          'ok': false,
          'error': 'invalid_payload',
          'detail':
              'order.edit requires matching uuid target_id and '
              'payload.order_id',
          'status': 'rejected',
          'idempotency_replay': false,
        }),
      );
      expect(o.kind, OrderEditOutcomeKind.refused);
    });
  });

  group('rejected (a RAISE, ledgered terminally)', () {
    Map<String, Object?> raised({Object? sqlstate, Object? detail}) => {
      'local_operation_id': _op,
      'operation_type': 'order.edit',
      'ok': false,
      'error': 'rejected',
      if (sqlstate != null) 'sqlstate': sqlstate,
      'detail': detail,
      'status': 'rejected',
      'idempotency_replay': false,
    };

    test('42501 is the anti-oracle: the order is not found', () {
      final o = _classify(_envelope(raised(sqlstate: '42501')));
      expect(o.kind, OrderEditOutcomeKind.rejected);
      expect(o.rejection, OrderEditRejection.orderNotFound);
      expect(o.isDefinitiveNo, isTrue);
    });

    test('a revoked employee or device is not allowed, whatever the '
        'sqlstate', () {
      for (final detail in ['revoked_employee', 'revoked_device']) {
        for (final sqlstate in ['42501', null]) {
          expect(
            _classify(
              _envelope(raised(sqlstate: sqlstate, detail: detail)),
            ).rejection,
            OrderEditRejection.notAllowed,
          );
        }
      }
    });

    test('23514 is a slip too large', () {
      expect(
        _classify(_envelope(raised(sqlstate: '23514'))).rejection,
        OrderEditRejection.slipTooLarge,
      );
    });

    test('any other raise is invalid', () {
      for (final sqlstate in ['22023', 'P0001', null]) {
        expect(
          _classify(_envelope(raised(sqlstate: sqlstate))).rejection,
          OrderEditRejection.invalid,
        );
      }
    });

    test('a replayed ledger row classifies the same', () {
      final row = raised(sqlstate: '42501')..['idempotency_replay'] = true;
      expect(
        _classify(_envelope(row)).rejection,
        OrderEditRejection.orderNotFound,
      );
    });
  });

  group('conflict', () {
    test('40001 (the identity used on another order)', () {
      final o = _classify(
        _envelope({
          'local_operation_id': _op,
          'operation_type': 'order.edit',
          'ok': false,
          'error': 'conflict',
          'sqlstate': '40001',
          'status': 'conflict',
          'idempotency_replay': false,
        }),
      );
      expect(o.kind, OrderEditOutcomeKind.conflict);
      expect(o.isDefinitiveNo, isFalse);
    });

    test('a fingerprint mismatch (the identity under another payload)', () {
      final o = _classify(
        _envelope({
          'local_operation_id': _op,
          'operation_type': 'order.edit',
          'ok': false,
          'error': 'conflict',
          'detail':
              'idempotency key already used for a different '
              'operation/payload',
          'status': 'conflict',
          'idempotency_replay': false,
        }),
      );
      expect(o.kind, OrderEditOutcomeKind.conflict);
    });
  });

  group('unknown (the identity is kept)', () {
    test('dead has no server verdict', () {
      final row = _refusedRow('rejected')..['status'] = 'dead';
      expect(_classify(_envelope(row)).reason, 'dead_no_server_verdict');
    });

    test('a code this build has never seen', () {
      final o = _classify(_envelope(_refusedRow('brand_new_rule')));
      expect(o.kind, OrderEditOutcomeKind.unknown);
      expect(o.reason, 'unknown_refusal_code');
    });

    test('a refusal without a code', () {
      for (final error in [null, '', '  ', 7]) {
        final row = _refusedRow('x')..['error'] = error;
        expect(_classify(_envelope(row)).reason, 'refusal_without_code');
      }
    });

    test('a pending or unknown status', () {
      final row = _refusedRow('dependency_not_ready')..['status'] = 'pending';
      expect(_classify(_envelope(row)).reason, 'unknown_status');
    });

    test('malformed envelopes', () {
      expect(_classify(null).reason, 'malformed_envelope');
      expect(_classify('ok').reason, 'malformed_envelope');
      expect(_classify({'ok': true}).reason, 'missing_results');
      expect(
        _classify({'ok': true, 'results': 'nope'}).reason,
        'missing_results',
      );
      expect(
        _classify({
          'ok': true,
          'results': [1, 'x', null],
        }).reason,
        'operation_absent',
      );
    });

    test('our operation absent from the results', () {
      final other = _appliedRow()..['local_operation_id'] = 'op-other';
      expect(_classify(_envelope(other)).reason, 'operation_absent');
      expect(
        _classify({'ok': true, 'results': <Object?>[]}).reason,
        'operation_absent',
      );
    });
  });
}

const Object _absent = Object();
