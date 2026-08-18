import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/admin/currency_change_guard.dart';
import 'package:restoflow_dashboard/src/admin/supabase_settings_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// OPS-043 Phase 1 — the WIRE contract.
///
/// D1 says the operating currency is a RESTAURANT setting. The whole point of
/// these tests is that the write lands on `restaurants.currency_override` for
/// ONE restaurant and never on `organizations.default_currency`, because the
/// latter would silently re-denominate every sibling restaurant in the org.
void main() {
  group('A. saveOperatingCurrency writes the restaurant override', () {
    test(
      'A1. it calls update_restaurant_settings with the code and NOTHING '
      'else — null name/timezone/status leave those fields untouched',
      () async {
        final t = _Transport((fn, params) => {'ok': true});
        final result = await _repo(
          t,
        ).saveOperatingCurrency(currencyCode: 'EUR');

        expect(result, SettingsWrite.ok);
        expect(t.calls, ['update_restaurant_settings']);
        final args = t.lastParams!;
        expect(args['p_currency_override'], 'EUR');
        expect(args['p_organization_id'], 'org-1');
        expect(args['p_restaurant_id'], 'rest-1');
        expect(args['p_name'], isNull);
        expect(args['p_timezone'], isNull);
        expect(args['p_status'], isNull);
      },
    );

    test('A2. THE MULTI-RESTAURANT RULE: it never touches the organization '
        'default, so sibling restaurants keep their own currency', () async {
      final t = _Transport((fn, params) => {'ok': true});
      await _repo(t).saveOperatingCurrency(currencyCode: 'EUR');

      expect(
        t.calls,
        isNot(contains('update_organization_settings')),
        reason: 'an org-wide write would re-denominate every sibling',
      );
      expect(t.lastParams!.containsKey('p_default_currency'), isFalse);
      // The write is addressed to exactly one restaurant id.
      expect(t.lastParams!['p_restaurant_id'], 'rest-1');
    });

    test('A3. the code is normalized to the uppercase 3-letter shape the '
        'server validates', () async {
      final t = _Transport((fn, params) => {'ok': true});
      await _repo(t).saveOperatingCurrency(currencyCode: ' eur ');
      expect(t.lastParams!['p_currency_override'], 'EUR');
    });

    test('A4. a malformed code fails closed CLIENT-side — the server would '
        'answer 42501, which surfaces as an opaque failure', () async {
      final t = _Transport((fn, params) => {'ok': true});
      for (final bad in ['', 'EU', 'EURO', '12', 'E U']) {
        final result = await _repo(t).saveOperatingCurrency(currencyCode: bad);
        expect(result, SettingsWrite.unavailable, reason: bad);
      }
      expect(t.calls, isEmpty, reason: 'nothing malformed reaches the server');
    });

    test('A5. the idempotency key includes the currency, so two different '
        'currency saves are two different requests', () async {
      final t = _Transport((fn, params) => {'ok': true});
      final repo = _repo(t);
      await repo.saveOperatingCurrency(currencyCode: 'EUR');
      final first = t.lastParams!['p_client_request_id'];
      await repo.saveOperatingCurrency(currencyCode: 'USD');
      expect(t.lastParams!['p_client_request_id'], isNot(first));
    });

    test('A6. the RPC envelope is mapped honestly', () async {
      expect(
        await _repo(
          _Transport((fn, p) => {'ok': false, 'error': 'permission_denied'}),
        ).saveOperatingCurrency(currencyCode: 'EUR'),
        SettingsWrite.denied,
      );
      expect(
        await _repo(
          _Transport((fn, p) => {'ok': false, 'error': 'something_else'}),
        ).saveOperatingCurrency(currencyCode: 'EUR'),
        SettingsWrite.unavailable,
      );
      expect(
        await _repo(
          _Transport((fn, p) => throw StateError('offline')),
        ).saveOperatingCurrency(currencyCode: 'EUR'),
        SettingsWrite.unavailable,
      );
    });

    test('A7. the NAME save still sends a null currency — it must never '
        're-denominate a restaurant as a side effect', () async {
      final t = _Transport((fn, params) => {'ok': true});
      await _repo(t).saveRestaurant(name: 'Olive North', status: 'active');
      expect(t.lastParams!['p_currency_override'], isNull);
    });
  });

  group('B. readPrefill reports override vs inherited', () {
    test('B1. a null override means INHERITED, and the effective currency is '
        'the organization default', () async {
      final prefill = await _repo(
        _Transport(_structure(override: null)),
      ).readPrefill();
      expect(prefill!.restaurantCurrencyOverride, isNull);
      expect(prefill.organizationDefaultCurrency, 'ILS');
      expect(prefill.currencyIsInherited, isTrue);
      expect(prefill.effectiveCurrency, 'ILS');
    });

    test('B2. an override wins over the organization default', () async {
      final prefill = await _repo(
        _Transport(_structure(override: 'EUR')),
      ).readPrefill();
      expect(prefill!.restaurantCurrencyOverride, 'EUR');
      expect(prefill.currencyIsInherited, isFalse);
      expect(prefill.effectiveCurrency, 'EUR');
    });

    test('B3. it reads THIS restaurant\'s row, not a sibling\'s', () async {
      final prefill = await _repo(
        _Transport(_structure(override: 'EUR', siblingOverride: 'USD')),
      ).readPrefill();
      expect(prefill!.effectiveCurrency, 'EUR');
    });
  });

  group('C. the D3 safety gate', () {
    test('C1. no open orders and no open shifts = clear', () async {
      final gate = await _guard(
        _Transport(_live(openOrders: 0, openShifts: 0)),
      ).check();
      expect(gate.status, CurrencyChangeGateStatus.clear);
      expect(gate.blocksChange, isFalse);
    });

    test('C2. it asks about the RESTAURANT, all branches — not one branch and '
        'not the whole organization', () async {
      final t = _Transport(_live(openOrders: 0, openShifts: 0));
      await _guard(t).check();
      final args = t.paramsFor('owner_active_orders')!;
      expect(args['p_organization_id'], 'org-1');
      expect(args['p_restaurant_id'], 'rest-1');
      expect(args['p_branch_id'], isNull);
    });

    test('C3. open orders block, and the count is the SCOPE-WIDE summary '
        'total, not the returned page', () async {
      final gate = await _guard(
        _Transport(_live(openOrders: 7, openShifts: 0, rows: 1)),
      ).check();
      expect(gate.status, CurrencyChangeGateStatus.blocked);
      expect(gate.openOrders, 7);
    });

    test('C4. an open cash shift blocks on its own', () async {
      final gate = await _guard(
        _Transport(_live(openOrders: 0, openShifts: 2)),
      ).check();
      expect(gate.status, CurrencyChangeGateStatus.blocked);
      expect(gate.openShifts, 2);
    });

    group('C5. FAILS CLOSED — every unknown is a block', () {
      test('a throwing transport', () async {
        final gate = await _guard(
          _Transport((fn, p) => throw StateError('offline')),
        ).check();
        expect(gate.status, CurrencyChangeGateStatus.unknown);
        expect(gate.blocksChange, isTrue);
      });

      test('a denied envelope', () async {
        final gate = await _guard(
          _Transport((fn, p) => {'ok': false, 'error': 'permission_denied'}),
        ).check();
        expect(gate.status, CurrencyChangeGateStatus.unknown);
      });

      test('a malformed envelope with no summary', () async {
        final gate = await _guard(_Transport((fn, p) => {'ok': true})).check();
        expect(gate.status, CurrencyChangeGateStatus.unknown);
      });

      test('orders answered but the shift count missing — "the payload did '
          'not say" is not "zero"', () async {
        final gate = await _guard(
          _Transport((fn, p) {
            if (fn == 'owner_active_orders') {
              return {
                'ok': true,
                'summary': {'total': 0},
              };
            }
            return {'ok': true}; // no shift_cash block at all
          }),
        ).check();
        expect(gate.status, CurrencyChangeGateStatus.unknown);
      });
    });

    test('C6. when owner_report_range is not deployed it falls back to '
        'owner_daily_report rather than assuming zero', () async {
      final t = _Transport((fn, p) {
        if (fn == 'owner_active_orders') {
          return {
            'ok': true,
            'summary': {'total': 0},
          };
        }
        if (fn == 'owner_report_range') throw StateError('PGRST202');
        return {
          'ok': true,
          'shift_cash': {'open_shift_count': 0},
        };
      });
      final gate = await _guard(t).check();
      expect(gate.status, CurrencyChangeGateStatus.clear);
      expect(t.calls, contains('owner_daily_report'));
    });
  });
}

// ---------------------------------------------------------------------------

SupabaseSettingsRepository _repo(_Transport t) => SupabaseSettingsRepository(
  transport: t,
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
);

SupabaseCurrencyChangeGuard _guard(_Transport t) => SupabaseCurrencyChangeGuard(
  transport: t,
  organizationId: 'org-1',
  restaurantId: 'rest-1',
);

/// A `list_org_structure` envelope shaped like the real one.
Object? Function(String, Map<String, dynamic>) _structure({
  String? override,
  String? siblingOverride,
}) =>
    (fn, params) => {
      'ok': true,
      'entity': 'org_structure',
      'organization': {
        'id': 'org-1',
        'name': 'Olive Group',
        'default_currency': 'ILS',
      },
      'restaurants': [
        {
          'id': 'rest-1',
          'name': 'Olive North',
          'currency_override': override,
          'status': 'active',
          'branches': [
            {
              'id': 'branch-1',
              'name': 'Main hall',
              'status': 'active',
              'timezone': 'Asia/Jerusalem',
            },
          ],
        },
        {
          'id': 'rest-2',
          'name': 'Olive South',
          'currency_override': siblingOverride,
          'status': 'active',
          'branches': const [],
        },
      ],
    };

/// The two live signals the gate reads.
Object? Function(String, Map<String, dynamic>) _live({
  required int openOrders,
  required int openShifts,
  int rows = 0,
}) => (fn, params) {
  if (fn == 'owner_active_orders') {
    return {
      'ok': true,
      'rows': List.generate(rows, (i) => {'id': 'o-$i'}),
      'summary': {'total': openOrders, 'unpaid': 0},
    };
  }
  return {
    'ok': true,
    'shift_cash': {'open_shift_count': openShifts, 'closed_shift_count': 4},
  };
};

class _Transport implements SyncRpcTransport {
  _Transport(this._handler);

  final Object? Function(String fn, Map<String, dynamic> params) _handler;
  final List<String> calls = [];
  final Map<String, Map<String, dynamic>> _byFn = {};
  Map<String, dynamic>? lastParams;

  Map<String, dynamic>? paramsFor(String fn) => _byFn[fn];

  @override
  Future<Object?> invoke(String fn, Map<String, dynamic> params) async {
    calls.add(fn);
    lastParams = params;
    _byFn[fn] = params;
    return _handler(fn, params);
  }
}
