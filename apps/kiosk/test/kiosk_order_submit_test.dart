import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show displayOrderCode;
import 'package:restoflow_kiosk/src/data/kiosk_fixtures.dart';
import 'package:restoflow_kiosk/src/data/kiosk_live_data.dart';
import 'package:restoflow_kiosk/src/data/kiosk_menu_data.dart';
import 'package:restoflow_kiosk/src/data/kiosk_order_submit.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_shell.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:restoflow_kiosk/src/state/kiosk_live_runtime.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// KIOSK-001-REAL-SUBMIT-092 — the real submit layer, no network anywhere:
/// tax math parity, canonical payload separation (base price vs modifier
/// deltas), the typed submitter, and the controller's D-022 identity +
/// freshness + recovery orchestration through fakes.
const _tableId = '00000000-0000-0000-0000-000000000t01';

Map<String, dynamic> _menuEnvelope({
  int burgerBase = 4000,
  int delta = 1500,
  String burgerName = 'Classic Burger',
  String bigName = '240g',
}) => {
  'ok': true,
  'currency_code': 'ILS',
  'categories': [
    {'id': 'c1', 'name': 'Burgers', 'display_order': 0},
  ],
  'items': [
    {
      'id': 'i1',
      'menu_category_id': 'c1',
      'name': burgerName,
      'base_price_minor': burgerBase,
      'availability': 'available',
    },
    {
      'id': 'i2',
      'menu_category_id': 'c1',
      'name': 'Cola',
      'base_price_minor': 1000,
    },
  ],
  'modifiers': [
    {
      'id': 'g1',
      'menu_item_id': 'i1',
      'name': 'Weight',
      'selection_type': 'single',
      'min_select': 1,
      'max_select': 1,
      'is_required': true,
      'allow_quantity': false,
      'display_order': 0,
    },
  ],
  'modifier_options': [
    {
      'id': 'o1',
      'modifier_id': 'g1',
      'name': '120g',
      'price_delta_minor': 0,
      'display_order': 0,
      'kitchen_meat': {'quantity': 1, 'unit': 'pc'},
    },
    {
      'id': 'o2',
      'modifier_id': 'g1',
      'name': bigName,
      'price_delta_minor': delta,
      'display_order': 1,
      'kitchen_meat': {'quantity': 2, 'unit': 'pc'},
    },
  ],
};

Map<String, dynamic> _tablesEnvelope({String state = 'available'}) => {
  'ok': true,
  'sections': [
    {'id': 's1', 'name': 'Hall', 'display_order': 0},
  ],
  'tables': [
    {
      'id': _tableId,
      'label': 'T1',
      'seats': 4,
      'section_id': 's1',
      'effective_state': state,
    },
  ],
};

Map<String, dynamic> _taxEnvelope({
  bool enabled = false,
  int bp = 0,
  String mode = 'exclusive',
}) => {'ok': true, 'tax_enabled': enabled, 'tax_rate_bp': bp, 'tax_mode': mode};

class _Rpc {
  _Rpc(this.handlers);
  final Map<String, Object? Function(Map<String, dynamic> params)> handlers;
  final calls = <(String, Map<String, dynamic>)>[];
}

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this.rpc);
  final _Rpc rpc;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    rpc.calls.add((function, Map<String, dynamic>.from(params)));
    final h = rpc.handlers[function];
    if (h == null) throw StateError('unexpected RPC $function');
    var out = h(params);
    if (out is Future) out = await out; // held/controllable responses
    if (out is Exception) throw out;
    return out;
  }
}

InMemoryDeviceSessionSecretStore _credStore() =>
    InMemoryDeviceSessionSecretStore()
      ..write(DeviceSessionCredential(deviceId: 'dev-1', sessionToken: 't-1'));

const _acceptedEnvelope = {
  'ok': true,
  'order_id': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeffff',
  'revision': 1,
  'idempotency_replay': false,
  'auto_completed': false,
  'order_status': 'submitted',
};

/// Full real-mode harness: live reads + tax + submitter over ONE fake
/// transport, with the real-mode menu/tables mirroring.
({ProviderContainer container, _Rpc rpc}) _harness({
  Map<String, Object? Function(Map<String, dynamic>)>? overrides,
  bool tablePicker = false,
}) {
  final rpc = _Rpc({
    'kiosk_menu': (_) => _menuEnvelope(),
    'kiosk_tables': (_) => _tablesEnvelope(),
    'get_device_branch_tax': (_) => _taxEnvelope(),
    'kiosk_submit_order': (p) => {
      ..._acceptedEnvelope,
      'order_id': p['p_order_id'],
    },
    ...?overrides,
  });
  final transport = _FakeTransport(rpc);
  final store = _credStore();
  final container = ProviderContainer(
    overrides: [
      kioskLiveReadsProvider.overrideWithValue(
        KioskLiveReads(transport: transport, secretStore: store),
      ),
      kioskOrderSubmitterProvider.overrideWithValue(
        KioskOrderSubmitter(transport: transport, secretStore: store),
      ),
      kioskBranchTaxReaderProvider.overrideWithValue(
        KioskBranchTaxReader(transport: transport, secretStore: store),
      ),
      kioskMenuDataProvider.overrideWith((ref) {
        final live = ref.watch(kioskLiveProvider.select((s) => s.menu));
        return live ?? const KioskMenuData.empty();
      }),
      kioskTablesViewProvider.overrideWith((ref) {
        final s = ref.watch(kioskLiveProvider);
        return (
          zones: s.zones ?? const <KioskFixtureZone>[],
          status: KioskTablesStatus.ready,
          live: true,
        );
      }),
    ],
  );
  final flow = container.read(kioskFlowProvider.notifier);
  if (!tablePicker) {
    flow.updateSettings(
      container
          .read(kioskFlowProvider)
          .settings
          .copyWith(tablePickerEnabled: false),
    );
  }
  return (container: container, rpc: rpc);
}

/// Loads the live menu and builds a one-line cart (burger + 240g + note).
Future<void> _fillCart(ProviderContainer c, {String note = ''}) async {
  await c.read(kioskLiveProvider.notifier).loadMenu();
  final flow = c.read(kioskFlowProvider.notifier);
  flow.startFromAttract();
  flow.pickService(KioskServiceType.takeaway);
  flow.openItem('i1');
  flow.toggleOption('g1', 'o2');
  if (note.isNotEmpty) flow.setDraftNote(note);
  expect(flow.submitDraft(), isTrue);
}

void main() {
  group('tax math (server parity, integer only)', () {
    const excl = KioskBranchTax(enabled: true, rateBp: 1700, mode: 'exclusive');
    const incl = KioskBranchTax(enabled: true, rateBp: 1700, mode: 'inclusive');
    const off = KioskBranchTax(enabled: false, rateBp: 0, mode: 'exclusive');

    test('disabled/0bp is exactly zero and grand == subtotal', () {
      expect(kioskTaxMinor(9999, off), 0);
      expect(kioskGrandMinor(9999, off), 9999);
      expect(
        kioskTaxMinor(
          9999,
          const KioskBranchTax(enabled: true, rateBp: 0, mode: 'exclusive'),
        ),
        0,
      );
    });

    test('exclusive matches round(sub*bp/10000) half-away', () {
      expect(kioskTaxMinor(10000, excl), 1700);
      expect(kioskTaxMinor(9999, excl), 1700); // 1699.83 -> 1700
      // exact half: 5 * 5000 / 10000 = 2.5 -> 3 (away from zero)
      expect(
        kioskTaxMinor(
          5,
          const KioskBranchTax(enabled: true, rateBp: 5000, mode: 'exclusive'),
        ),
        3,
      );
      expect(kioskGrandMinor(10000, excl), 11700);
    });

    test('inclusive matches round(sub*bp/(10000+bp)); grand unchanged', () {
      expect(kioskTaxMinor(11700, incl), 1700);
      expect(kioskGrandMinor(11700, incl), 11700);
      // exact half: 3 * 10000 / 20000 = 1.5 -> 2
      expect(
        kioskTaxMinor(
          3,
          const KioskBranchTax(enabled: true, rateBp: 10000, mode: 'inclusive'),
        ),
        2,
      );
    });
  });

  group('branch tax reader (never guesses OFF)', () {
    test(
      'parses enabled/rate/mode; refuses malformed or failed reads',
      () async {
        final rpc = _Rpc({
          'get_device_branch_tax': (_) =>
              _taxEnvelope(enabled: true, bp: 1700, mode: 'inclusive'),
        });
        final reader = KioskBranchTaxReader(
          transport: _FakeTransport(rpc),
          secretStore: _credStore(),
        );
        expect(
          await reader.load(),
          const KioskBranchTax(enabled: true, rateBp: 1700, mode: 'inclusive'),
        );

        for (final bad in <Object?>[
          {'ok': false, 'error': 'invalid_session'},
          {'ok': true, 'tax_enabled': true, 'tax_rate_bp': 1700}, // no mode
          {
            'ok': true,
            'tax_enabled': true,
            'tax_rate_bp': 1700,
            'tax_mode': 'weird',
          },
          'nonsense',
        ]) {
          final r = KioskBranchTaxReader(
            transport: _FakeTransport(
              _Rpc({'get_device_branch_tax': (_) => bad}),
            ),
            secretStore: _credStore(),
          );
          expect(
            await r.load(),
            isNull,
            reason: '$bad must not become a policy',
          );
        }

        final noCred = KioskBranchTaxReader(
          transport: _FakeTransport(rpc),
          secretStore: InMemoryDeviceSessionSecretStore(),
        );
        expect(await noCred.load(), isNull);
      },
    );
  });

  group('payload construction (canonical separation)', () {
    KioskMenuData menu() => mapKioskMenuEnvelope(_menuEnvelope())!;
    const taxOff = KioskBranchTax(enabled: false, rateBp: 0, mode: 'exclusive');

    KioskCartLine line({int qty = 2, String note = 'no salt'}) => KioskCartLine(
      lineId: 1,
      itemId: 'i1',
      quantity: qty,
      selected: const {
        'g1': ['o2'],
      },
      note: note,
      capturedUnitMinor: 5500, // 4000 base + 1500 delta
    );

    test(
      'base price and modifier deltas ride separately, never pre-summed',
      () {
        final attempt = buildKioskSubmitAttempt(
          menu: menu(),
          cart: [line()],
          service: KioskServiceType.takeaway,
          tableId: null,
          tax: taxOff,
          customerName: '  Dana  ',
          customerPhone: ' 050-123 ',
          clientCreatedAt: DateTime.utc(2026, 8, 21, 12),
        );
        final items = attempt.params['p_order_items'] as List;
        final item = items.single as Map<String, dynamic>;
        expect(item['menu_item_id'], 'i1');
        expect(item['menu_item_name_snapshot'], 'Classic Burger');
        expect(item['quantity'], 2);
        expect(
          item['unit_price_minor_snapshot'],
          4000, // BASE, not 5500
          reason: 'captured unit must never be sent as the base price',
        );
        expect(item['line_total_minor'], 2 * (4000 + 1500));
        expect(item['notes'], 'no salt');
        final mod = (item['modifiers'] as List).single as Map<String, dynamic>;
        expect(mod['modifier_option_id'], 'o2');
        expect(mod['option_name_snapshot'], '240g');
        expect(mod['modifier_name_snapshot'], 'Weight');
        expect(mod['price_minor_snapshot'], 1500);
        expect(mod['quantity'], 1); // UI has no option quantity — never faked
        expect(mod['meat_snapshot'], {'quantity': 2, 'unit': 'pc'});
        // Totals: subtotal only, zero discount, tax off.
        expect(attempt.params['p_client_subtotal_minor'], 11000);
        expect(attempt.params['p_client_discount_total_minor'], 0);
        expect(attempt.params['p_client_tax_total_minor'], 0);
        expect(attempt.params['p_client_grand_total_minor'], 11000);
        expect(attempt.params['p_currency_code'], 'ILS');
        // Customer normalization: trimmed; never numeric.
        expect(attempt.params['p_customer_name'], 'Dana');
        expect(attempt.params['p_customer_phone'], '050-123');
        expect(attempt.params['p_order_type'], 'takeaway');
        expect(attempt.params['p_table_id'], isNull);
      },
    );

    test('empty customer fields become null; name capped at 80 chars', () {
      final attempt = buildKioskSubmitAttempt(
        menu: menu(),
        cart: [line(note: '')],
        service: KioskServiceType.dineIn,
        tableId: _tableId,
        tax: taxOff,
        customerName: 'x' * 100,
        customerPhone: '   ',
        clientCreatedAt: DateTime.utc(2026),
      );
      expect((attempt.params['p_customer_name'] as String).length, 80);
      expect(attempt.params['p_customer_phone'], isNull);
      expect(attempt.params['p_order_type'], 'dine_in');
      expect(attempt.params['p_table_id'], _tableId);
      final item =
          (attempt.params['p_order_items'] as List).single
              as Map<String, dynamic>;
      expect(item.containsKey('notes'), isFalse);
    });

    test('exclusive tax rides in the totals exactly as the server derives', () {
      const tax = KioskBranchTax(
        enabled: true,
        rateBp: 1700,
        mode: 'exclusive',
      );
      final attempt = buildKioskSubmitAttempt(
        menu: menu(),
        cart: [line()],
        service: KioskServiceType.takeaway,
        tableId: null,
        tax: tax,
        customerName: '',
        customerPhone: '',
        clientCreatedAt: DateTime.utc(2026),
      );
      expect(attempt.params['p_client_tax_total_minor'], 1870); // 11000@17%
      expect(attempt.params['p_client_grand_total_minor'], 12870);
    });

    test('inclusive tax extracts without changing the grand total', () {
      const tax = KioskBranchTax(
        enabled: true,
        rateBp: 1700,
        mode: 'inclusive',
      );
      final attempt = buildKioskSubmitAttempt(
        menu: menu(),
        cart: [line()],
        service: KioskServiceType.takeaway,
        tableId: null,
        tax: tax,
        customerName: '',
        customerPhone: '',
        clientCreatedAt: DateTime.utc(2026),
      );
      // round(11000*1700/11700) = round(1598.29) = 1598
      expect(attempt.params['p_client_tax_total_minor'], 1598);
      expect(attempt.params['p_client_grand_total_minor'], 11000);
    });

    test('a drifted captured price refuses to build (stale gate backstop)', () {
      expect(
        () => buildKioskSubmitAttempt(
          menu: mapKioskMenuEnvelope(_menuEnvelope(burgerBase: 4100))!,
          cart: [line()], // captured 5500 vs fresh 5600
          service: KioskServiceType.takeaway,
          tableId: null,
          tax: taxOff,
          customerName: '',
          customerPhone: '',
          clientCreatedAt: DateTime.utc(2026),
        ),
        throwsA(isA<KioskCartOutOfSyncError>()),
      );
    });
  });

  group('submitter (typed results, exact wire shape)', () {
    test(
      'sends the stored credential + frozen params to the exact RPC',
      () async {
        final rpc = _Rpc({'kiosk_submit_order': (_) => _acceptedEnvelope});
        final submitter = KioskOrderSubmitter(
          transport: _FakeTransport(rpc),
          secretStore: _credStore(),
        );
        const attempt = KioskSubmitAttempt(
          orderId: 'oid',
          localOperationId: 'lop',
          params: {'p_order_id': 'oid', 'p_local_operation_id': 'lop'},
        );
        final r = await submitter.submit(attempt);
        expect(r, isA<KioskSubmitAccepted>());
        final (fn, params) = rpc.calls.single;
        expect(fn, 'kiosk_submit_order');
        expect(params['p_device_id'], 'dev-1');
        expect(params['p_session_token'], 't-1');
        expect(params['p_order_id'], 'oid');
        expect(params['p_local_operation_id'], 'lop');
      },
    );

    test('missing credential is an invalid session (no call made)', () async {
      final rpc = _Rpc({'kiosk_submit_order': (_) => _acceptedEnvelope});
      final submitter = KioskOrderSubmitter(
        transport: _FakeTransport(rpc),
        secretStore: InMemoryDeviceSessionSecretStore(),
      );
      expect(
        await submitter.submit(
          const KioskSubmitAttempt(
            orderId: 'o',
            localOperationId: 'l',
            params: {},
          ),
        ),
        isA<KioskSubmitInvalidSession>(),
      );
      expect(rpc.calls, isEmpty);
    });

    test('envelopes map to typed results', () async {
      Future<KioskSubmitResult> run(Object? envelope) {
        final submitter = KioskOrderSubmitter(
          transport: _FakeTransport(
            _Rpc({'kiosk_submit_order': (_) => envelope}),
          ),
          secretStore: _credStore(),
        );
        return submitter.submit(
          const KioskSubmitAttempt(
            orderId: 'o',
            localOperationId: 'l',
            params: {},
          ),
        );
      }

      final accepted =
          await run({..._acceptedEnvelope, 'idempotency_replay': true})
              as KioskSubmitAccepted;
      expect(accepted.idempotencyReplay, isTrue);
      expect(accepted.orderId, _acceptedEnvelope['order_id']);

      final rejected = await run({'ok': false, 'error': 'menu_price_changed'});
      expect((rejected as KioskSubmitRejected).code, 'menu_price_changed');

      final phone = await run({
        'ok': false,
        'error': 'invalid_payload',
        'field': 'customer_phone',
      });
      expect((phone as KioskSubmitRejected).invalidField, 'customer_phone');

      expect(
        await run({'ok': false, 'error': 'invalid_session'}),
        isA<KioskSubmitInvalidSession>(),
      );
      expect(await run('garbage'), isA<KioskSubmitUnconfirmed>());
      expect(await run({'ok': true}), isA<KioskSubmitUnconfirmed>());
    });

    test('transport kinds: auth -> invalid session; transient/server -> '
        'unconfirmed', () async {
      for (final (kind, matcher) in [
        (SyncTransportErrorKind.auth, isA<KioskSubmitInvalidSession>()),
        (SyncTransportErrorKind.transient, isA<KioskSubmitUnconfirmed>()),
        (SyncTransportErrorKind.server, isA<KioskSubmitUnconfirmed>()),
      ]) {
        final submitter = KioskOrderSubmitter(
          transport: _FakeTransport(
            _Rpc({'kiosk_submit_order': (_) => SyncTransportException(kind)}),
          ),
          secretStore: _credStore(),
        );
        expect(
          await submitter.submit(
            const KioskSubmitAttempt(
              orderId: 'o',
              localOperationId: 'l',
              params: {},
            ),
          ),
          matcher,
          reason: '$kind',
        );
      }
    });
  });

  group('controller orchestration (identity, freshness, recovery)', () {
    test(
      'accepted: one submit, cart cleared, code from the ACCEPTED id',
      () async {
        final h = _harness();
        await _fillCart(h.container);
        final flow = h.container.read(kioskFlowProvider.notifier);
        flow.placeOrder();
        await h.container.settle();
        final state = h.container.read(kioskFlowProvider);
        expect(state.screen, KioskScreen.confirm);
        expect(state.cart, isEmpty);
        expect(state.customerName, isEmpty);
        expect(state.selectedTableId, isNull);
        final submittedId =
            h.rpc.calls
                    .firstWhere((c) => c.$1 == 'kiosk_submit_order')
                    .$2['p_order_id']
                as String;
        expect(
          state.lastOrder!.code,
          '#${submittedId.replaceAll('-', '').substring(26).toUpperCase()}',
          reason: 'the code derives from the ACCEPTED (frozen) order id',
        );
        expect(state.submitPhase, KioskSubmitPhase.idle);
        expect(flow.debugPendingAttempt, isNull);
        final submits = h.rpc.calls
            .where((c) => c.$1 == 'kiosk_submit_order')
            .toList();
        expect(submits, hasLength(1));
        // The pre-submit freshness gate refreshed the menu + read the tax.
        expect(h.rpc.calls.any((c) => c.$1 == 'get_device_branch_tax'), isTrue);
      },
    );

    test('double tap is single-flight: exactly one submit call', () async {
      final h = _harness();
      await _fillCart(h.container);
      final flow = h.container.read(kioskFlowProvider.notifier);
      flow.placeOrder();
      flow.placeOrder(); // second tap while in flight
      await h.container.settle();
      expect(
        h.rpc.calls.where((c) => c.$1 == 'kiosk_submit_order'),
        hasLength(1),
      );
    });

    test('unconfirmed keeps cart + attempt; retry reuses the SAME identity '
        'and a replayed acceptance confirms once', () async {
      var fail = true;
      final h = _harness(
        overrides: {
          'kiosk_submit_order': (p) => fail
              ? SyncTransportException(SyncTransportErrorKind.transient)
              : {
                  ..._acceptedEnvelope,
                  'order_id': p['p_order_id'],
                  'idempotency_replay': true,
                },
        },
      );
      await _fillCart(h.container);
      final flow = h.container.read(kioskFlowProvider.notifier);
      flow.placeOrder();
      await h.container.settle();
      var state = h.container.read(kioskFlowProvider);
      expect(state.submitPhase, KioskSubmitPhase.unconfirmed);
      expect(state.cart, isNotEmpty, reason: 'never clear on uncertainty');
      expect(state.screen, isNot(KioskScreen.confirm));
      final first = flow.debugPendingAttempt!;

      fail = false;
      await flow.retrySubmit();
      state = h.container.read(kioskFlowProvider);
      expect(state.screen, KioskScreen.confirm);
      final submits = h.rpc.calls
          .where((c) => c.$1 == 'kiosk_submit_order')
          .toList();
      expect(submits, hasLength(2));
      expect(
        submits[1].$2['p_order_id'],
        first.orderId,
        reason: 'retry must reuse the SAME order id',
      );
      expect(submits[1].$2['p_local_operation_id'], first.localOperationId);
    });

    test('definitive price rejection: no success, cart stale, identity spent; '
        'the next deliberate attempt mints a NEW identity', () async {
      var reject = true;
      var price = 4000;
      final h = _harness(
        overrides: {
          'kiosk_menu': (_) => _menuEnvelope(burgerBase: price),
          'kiosk_submit_order': (p) {
            if (reject) {
              price = 4100; // the drift behind the server's refusal
              return {'ok': false, 'error': 'menu_price_changed'};
            }
            return {..._acceptedEnvelope, 'order_id': p['p_order_id']};
          },
        },
      );
      await _fillCart(h.container);
      final flow = h.container.read(kioskFlowProvider.notifier);
      flow.placeOrder();
      await h.container.settle();
      await h.container.settle(); // the recovery menu reload revalidates
      var state = h.container.read(kioskFlowProvider);
      expect(state.screen, isNot(KioskScreen.confirm));
      expect(state.cartStale, isTrue, reason: 'drift demands reconfirmation');
      expect(flow.debugPendingAttempt, isNull, reason: 'identity is spent');
      final firstId = h.rpc.calls
          .where((c) => c.$1 == 'kiosk_submit_order')
          .single
          .$2['p_order_id'];

      // Customer visibly reconfirms, then orders again.
      reject = false;
      flow.refreshCartAgainstMenu();
      flow.placeOrder();
      await h.container.settle();
      state = h.container.read(kioskFlowProvider);
      expect(state.screen, KioskScreen.confirm);
      final submits = h.rpc.calls
          .where((c) => c.$1 == 'kiosk_submit_order')
          .toList();
      expect(submits, hasLength(2));
      expect(
        submits[1].$2['p_order_id'],
        isNot(firstId),
        reason: 'a terminal rejection spends the identity',
      );
    });

    test('dine-in with the picker OFF submits table_id null', () async {
      final h = _harness();
      await h.container.read(kioskLiveProvider.notifier).loadMenu();
      final flow = h.container.read(kioskFlowProvider.notifier);
      flow.startFromAttract();
      flow.pickService(KioskServiceType.dineIn); // picker disabled -> menu
      flow.openItem('i1');
      flow.toggleOption('g1', 'o1');
      flow.submitDraft();
      flow.placeOrder();
      await h.container.settle();
      final params = h.rpc.calls
          .where((c) => c.$1 == 'kiosk_submit_order')
          .single
          .$2;
      expect(params['p_order_type'], 'dine_in');
      expect(params['p_table_id'], isNull);
    });

    test(
      'dine-in with the picker ON sends the AUTHORITATIVE table UUID',
      () async {
        final h = _harness(tablePicker: true);
        await h.container.read(kioskLiveProvider.notifier).loadMenu();
        await h.container.read(kioskLiveProvider.notifier).refreshTables();
        final flow = h.container.read(kioskFlowProvider.notifier);
        flow.startFromAttract();
        flow.pickService(KioskServiceType.dineIn);
        flow.toggleTable('T1', id: _tableId);
        flow.confirmTable();
        flow.openItem('i1');
        flow.toggleOption('g1', 'o1');
        flow.submitDraft();
        flow.placeOrder();
        await h.container.settle();
        final params = h.rpc.calls
            .where((c) => c.$1 == 'kiosk_submit_order')
            .single
            .$2;
        expect(params['p_table_id'], _tableId, reason: 'UUID, never the label');
        expect(
          h.container.read(kioskFlowProvider).lastOrder!.table,
          'T1',
          reason: 'the confirmation shows the LABEL',
        );
      },
    );

    test('table race: server refusal returns the customer to the picker with '
        'cart intact and the dead identity cleared', () async {
      final h = _harness(
        tablePicker: true,
        overrides: {
          'kiosk_submit_order': (_) => {
            'ok': false,
            'error': 'table_no_longer_available',
          },
        },
      );
      await h.container.read(kioskLiveProvider.notifier).loadMenu();
      await h.container.read(kioskLiveProvider.notifier).refreshTables();
      final flow = h.container.read(kioskFlowProvider.notifier);
      flow.startFromAttract();
      flow.pickService(KioskServiceType.dineIn);
      flow.toggleTable('T1', id: _tableId);
      flow.confirmTable();
      flow.openItem('i1');
      flow.toggleOption('g1', 'o1');
      flow.submitDraft();
      flow.placeOrder();
      await h.container.settle();
      final state = h.container.read(kioskFlowProvider);
      expect(state.screen, KioskScreen.tables);
      expect(state.selectedTableId, isNull);
      expect(state.selectedTable, isNull);
      expect(state.cart, isNotEmpty, reason: 'cart survives the race');
      expect(state.toast, 'table-taken');
      expect(flow.debugPendingAttempt, isNull);
    });

    test('pre-flight availability gate catches a taken table WITHOUT '
        'spending a submit', () async {
      final h = _harness(
        tablePicker: true,
        overrides: {'kiosk_tables': (_) => _tablesEnvelope(state: 'occupied')},
      );
      await h.container.read(kioskLiveProvider.notifier).loadMenu();
      final flow = h.container.read(kioskFlowProvider.notifier);
      flow.startFromAttract();
      flow.pickService(KioskServiceType.dineIn);
      flow.toggleTable('T1', id: _tableId);
      flow.confirmTable();
      flow.openItem('i1');
      flow.toggleOption('g1', 'o1');
      flow.submitDraft();
      flow.placeOrder();
      await h.container.settle();
      expect(
        h.rpc.calls.where((c) => c.$1 == 'kiosk_submit_order'),
        isEmpty,
        reason: 'the fresh floor check blocks before any server submit',
      );
      expect(h.container.read(kioskFlowProvider).screen, KioskScreen.tables);
    });

    test('a failed tax read BLOCKS the submit (never guesses OFF)', () async {
      final h = _harness(
        overrides: {
          'get_device_branch_tax': (_) => {'ok': false, 'error': 'x'},
        },
      );
      await _fillCart(h.container);
      h.container.read(kioskFlowProvider.notifier).placeOrder();
      await h.container.settle();
      final state = h.container.read(kioskFlowProvider);
      expect(h.rpc.calls.where((c) => c.$1 == 'kiosk_submit_order'), isEmpty);
      expect(state.submitErrorKey, 'tax-unavailable');
      expect(state.cart, isNotEmpty);
    });

    test('invalid session on submit raises the pairing-gate signal', () async {
      final h = _harness(
        overrides: {
          'kiosk_submit_order': (_) => {
            'ok': false,
            'error': 'invalid_session',
          },
        },
      );
      await _fillCart(h.container);
      h.container.read(kioskFlowProvider.notifier).placeOrder();
      await h.container.settle();
      expect(h.container.read(kioskLiveProvider).sessionInvalid, isTrue);
    });

    test(
      'invalid phone maps to the field message and keeps the cart',
      () async {
        final h = _harness(
          overrides: {
            'kiosk_submit_order': (_) => {
              'ok': false,
              'error': 'invalid_payload',
              'field': 'customer_phone',
            },
          },
        );
        await _fillCart(h.container);
        final flow = h.container.read(kioskFlowProvider.notifier);
        flow.setCustomerPhone('bad');
        flow.placeOrder();
        await h.container.settle();
        final state = h.container.read(kioskFlowProvider);
        expect(state.submitErrorKey, 'phone-invalid');
        expect(state.cart, isNotEmpty);
        expect(state.customerPhone, 'bad', reason: 'field kept for correction');
      },
    );

    test('REAL staff settings unlock is disabled by the provider seam', () {
      final c = ProviderContainer(
        overrides: [kioskStaffSettingsEnabledProvider.overrideWithValue(false)],
      );
      addTearDown(c.dispose);
      final flow = c.read(kioskFlowProvider.notifier);
      flow.staffTap();
      flow.staffTap();
      flow.staffTap();
      expect(
        c.read(kioskFlowProvider).sheet,
        isNull,
        reason: 'the fixture PIN gate must never open in real mode',
      );
    });
  });

  group(
    '093 frozen-attempt hardening (in-flight/unconfirmed immutability)',
    () {
      test('A. while IN-FLIGHT every business mutation is blocked and the '
          'accepted confirmation is EXACTLY the frozen order', () async {
        final held = Completer<Object?>();
        final h = _harness(
          overrides: {
            'kiosk_submit_order': (p) => held.future.then(
              (_) => {..._acceptedEnvelope, 'order_id': p['p_order_id']},
            ),
          },
        );
        await _fillCart(h.container, note: 'frozen note');
        final flow = h.container.read(kioskFlowProvider.notifier);
        flow.openCart(); // Place Order lives in the cart sheet
        flow.setCustomerName('Frozen Dana');
        flow.placeOrder();
        await h.container.settle();
        expect(
          h.container.read(kioskFlowProvider).submitPhase,
          KioskSubmitPhase.inFlight,
        );

        // Mutation attempts while the response is held open:
        flow.incrementLine(1);
        flow.decrementLine(1);
        flow.removeLine(1);
        flow.editCartLine(1);
        flow.setCustomerName('EDITED');
        flow.setCustomerPhone('999');
        flow.changeService();
        flow.toggleTable('T9', id: 'other');
        flow.closeCart();
        flow.openItem('i2');
        flow.backToAttract();
        var s = h.container.read(kioskFlowProvider);
        expect(s.cart.single.quantity, 1, reason: 'qty locked');
        expect(s.cart, hasLength(1), reason: 'remove locked');
        expect(s.customerName, 'Frozen Dana', reason: 'name locked');
        expect(s.customerPhone, isEmpty, reason: 'phone locked');
        expect(s.service, KioskServiceType.takeaway, reason: 'service locked');
        expect(s.selectedTable, isNull, reason: 'table locked');
        expect(s.sheet, KioskSheet.cart, reason: 'close-cart locked');
        expect(s.draft, isNull, reason: 'item sheet locked');
        expect(s.screen, isNot(KioskScreen.attract), reason: 'reset locked');

        held.complete(null);
        await h.container.settle();
        s = h.container.read(kioskFlowProvider);
        expect(s.screen, KioskScreen.confirm);
        final order = s.lastOrder!;
        expect(order.lines.single.quantity, 1);
        expect(order.lines.single.note, 'frozen note');
        expect(order.customerName, 'Frozen Dana');
        expect(order.service, KioskServiceType.takeaway);
        expect(order.totalMinor, 5500);
      });

      test('B+C. UNCONFIRMED keeps the frozen view immutable, survives the '
          'idle engine, and Retry replays the same identity', () async {
        var fail = true;
        final h = _harness(
          overrides: {
            'kiosk_submit_order': (p) => fail
                ? SyncTransportException(SyncTransportErrorKind.transient)
                : {
                    ..._acceptedEnvelope,
                    'order_id': p['p_order_id'],
                    'idempotency_replay': true,
                  },
          },
        );
        await _fillCart(h.container);
        final flow = h.container.read(kioskFlowProvider.notifier);
        flow.placeOrder();
        await h.container.settle();
        expect(
          h.container.read(kioskFlowProvider).submitPhase,
          KioskSubmitPhase.unconfirmed,
        );
        final frozen = flow.debugPendingAttempt!;

        // Edits stay blocked while unconfirmed.
        flow.incrementLine(1);
        flow.setCustomerName('EDITED');
        flow.changeService();
        var s = h.container.read(kioskFlowProvider);
        expect(s.cart.single.quantity, 1);
        expect(s.customerName, isEmpty);
        expect(s.service, KioskServiceType.takeaway);

        // C: the kiosk idle engine must NOT discard the uncertain handle.
        for (var i = 0; i < 200; i++) {
          flow.tick();
        }
        s = h.container.read(kioskFlowProvider);
        expect(
          s.screen,
          isNot(KioskScreen.attract),
          reason: 'idle reset must not run with an unresolved attempt',
        );
        expect(flow.debugPendingAttempt, same(frozen));

        fail = false;
        await flow.retrySubmit();
        final submits = h.rpc.calls
            .where((c) => c.$1 == 'kiosk_submit_order')
            .toList();
        expect(submits, hasLength(2));
        expect(submits[1].$2['p_order_id'], frozen.orderId);
        expect(submits[1].$2['p_local_operation_id'], frozen.localOperationId);
        s = h.container.read(kioskFlowProvider);
        expect(s.screen, KioskScreen.confirm);
        expect(
          s.lastOrder!.totalMinor,
          5500,
          reason: 'confirmation == the frozen attempt',
        );
      });

      test('D. a definitive rejection unlocks the controls again', () async {
        final h = _harness(
          overrides: {
            'kiosk_submit_order': (_) => {
              'ok': false,
              'error': 'discount_not_allowed',
            },
          },
        );
        await _fillCart(h.container);
        final flow = h.container.read(kioskFlowProvider.notifier);
        flow.placeOrder();
        await h.container.settle();
        final s = h.container.read(kioskFlowProvider);
        expect(
          s.submitPhase,
          KioskSubmitPhase.idle,
          reason: 'terminal => idle',
        );
        expect(flow.debugPendingAttempt, isNull);
        // Unlocked: edits work again.
        flow.incrementLine(1);
        expect(h.container.read(kioskFlowProvider).cart.single.quantity, 2);
        flow.setCustomerName('After');
        expect(h.container.read(kioskFlowProvider).customerName, 'After');
      });

      test('E. an accepted envelope naming a DIFFERENT order id fails closed '
          'to UNCONFIRMED (no foreign confirmation)', () async {
        final h = _harness(
          overrides: {
            'kiosk_submit_order': (_) => {
              ..._acceptedEnvelope,
              'order_id': 'ffffffff-0000-4000-8000-000000000000',
            },
          },
        );
        await _fillCart(h.container);
        final flow = h.container.read(kioskFlowProvider.notifier);
        flow.placeOrder();
        await h.container.settle();
        final s = h.container.read(kioskFlowProvider);
        expect(
          s.submitPhase,
          KioskSubmitPhase.unconfirmed,
          reason: 'a foreign id is an unreadable response, never a success',
        );
        expect(s.screen, isNot(KioskScreen.confirm));
        expect(s.cart, isNotEmpty);
        expect(
          flow.debugPendingAttempt,
          isNotNull,
          reason: 'the retry handle is retained',
        );
      });

      test('deep-copy: mutating the ORIGINAL cart structures never leaks into '
          'the frozen view', () {
        final menu = mapKioskMenuEnvelope(_menuEnvelope())!;
        final selected = <String, List<String>>{
          'g1': ['o2'],
        };
        final cart = <KioskCartLine>[
          KioskCartLine(
            lineId: 1,
            itemId: 'i1',
            quantity: 1,
            selected: selected,
            note: 'n',
            capturedUnitMinor: 5500,
          ),
        ];
        final attempt = buildKioskSubmitAttempt(
          menu: menu,
          cart: cart,
          service: KioskServiceType.takeaway,
          tableId: null,
          tax: const KioskBranchTax(
            enabled: false,
            rateBp: 0,
            mode: 'exclusive',
          ),
          customerName: 'n',
          customerPhone: '',
          clientCreatedAt: DateTime.utc(2026),
        );
        selected['g1']!.add('o1'); // mutate the ORIGINAL map after freezing
        cart.clear();
        final view = attempt.view!;
        expect(
          view.lines.single.selected['g1'],
          ['o2'],
          reason: 'the frozen selection must not alias the live map',
        );
        expect(view.lines, hasLength(1));
        expect(
          () => view.lines.single.selected['g1']!.add('x'),
          throwsUnsupportedError,
          reason: 'frozen collections are unmodifiable',
        );
      });
    },
  );

  group('094 final snapshot parity (frozen display + immutable wire)', () {
    KioskMenuData menu() => mapKioskMenuEnvelope(_menuEnvelope())!;
    const taxOff = KioskBranchTax(enabled: false, rateBp: 0, mode: 'exclusive');

    KioskSubmitAttempt build({
      String name = 'Dana',
      Map<String, dynamic>? envelope,
    }) => buildKioskSubmitAttempt(
      menu: envelope == null ? menu() : mapKioskMenuEnvelope(envelope)!,
      cart: [
        const KioskCartLine(
          lineId: 1,
          itemId: 'i1',
          quantity: 2,
          selected: {
            'g1': ['o2'],
          },
          note: 'no salt',
          capturedUnitMinor: 5500,
        ),
      ],
      service: KioskServiceType.takeaway,
      tableId: null,
      tax: taxOff,
      customerName: name,
      customerPhone: '050',
      clientCreatedAt: DateTime.utc(2026, 8, 22, 12),
    );

    test('customer name normalizes ONCE — wire and frozen view carry the '
        'SAME canonical value at every boundary', () {
      String? wire(KioskSubmitAttempt a) =>
          a.params['p_customer_name'] as String?;
      final n79 = 'x' * 79, n80 = 'y' * 80, n81 = 'z' * 81;
      final a79 = build(name: n79);
      expect(wire(a79), n79);
      expect(a79.view!.customerName, n79);
      final a80 = build(name: n80);
      expect(wire(a80), n80);
      expect(a80.view!.customerName, n80);
      final a81 = build(name: n81);
      expect(wire(a81)!.length, 80);
      expect(wire(a81), n81.substring(0, 80));
      expect(
        a81.view!.customerName,
        wire(a81),
        reason: 'confirmation must print EXACTLY what the server stores',
      );
      final padded = build(name: '   ${'w' * 81}   ');
      expect(wire(padded), 'w' * 80, reason: 'trim BEFORE capping');
      expect(padded.view!.customerName, wire(padded));
      final empty = build(name: '   ');
      expect(wire(empty), isNull);
      expect(empty.view!.customerName, isEmpty);
    });

    test('the RPC parameter graph is RECURSIVELY immutable — every mutation '
        'attempt throws (D-022 frozen payload, structural)', () {
      final env = _menuEnvelope();
      ((env['modifier_options'] as List)[1] as Map)['kitchen_meat'] = {
        'quantity': 2,
        'unit': 'pc',
        'parts': ['patty'],
      };
      final a = build(envelope: env);
      final params = a.params;
      expect(() => params['p_notes'] = 'x', throwsUnsupportedError);
      expect(() => params.remove('p_order_id'), throwsUnsupportedError);
      final items = params['p_order_items'] as List;
      expect(() => items.add(<String, dynamic>{}), throwsUnsupportedError);
      expect(() => items.removeAt(0), throwsUnsupportedError);
      final item = items.single as Map;
      expect(() => item['quantity'] = 9, throwsUnsupportedError);
      final mods = item['modifiers'] as List;
      expect(mods, hasLength(1));
      expect(() => mods.clear(), throwsUnsupportedError);
      final mod = mods.single as Map;
      expect(() => mod['price_minor_snapshot'] = 0, throwsUnsupportedError);
      final meat = mod['meat_snapshot'] as Map;
      expect(() => meat['quantity'] = 9, throwsUnsupportedError);
      expect(
        () => (meat['parts'] as List).add('x'),
        throwsUnsupportedError,
        reason: 'nested prep-snapshot collections are frozen too',
      );
    });

    test('freezing is wire-equivalent — identical JSON to the unfrozen '
        'literal payload', () {
      final a = buildKioskSubmitAttempt(
        menu: menu(),
        cart: [
          const KioskCartLine(
            lineId: 1,
            itemId: 'i1',
            quantity: 2,
            selected: {
              'g1': ['o2'],
            },
            note: 'no salt',
            capturedUnitMinor: 5500,
          ),
        ],
        service: KioskServiceType.dineIn,
        tableId: _tableId,
        tableLabel: 'T1',
        tax: const KioskBranchTax(
          enabled: true,
          rateBp: 1700,
          mode: 'exclusive',
        ),
        customerName: ' Dana ',
        customerPhone: ' 050-123 ',
        clientCreatedAt: DateTime.utc(2026, 8, 22, 12),
        orderId: 'oid-fixed',
        localOperationId: 'kiosk-fixed',
      );
      final expected = <String, dynamic>{
        'p_order_id': 'oid-fixed',
        'p_local_operation_id': 'kiosk-fixed',
        'p_order_type': 'dine_in',
        'p_table_id': _tableId,
        'p_currency_code': 'ILS',
        'p_notes': null,
        'p_customer_name': 'Dana',
        'p_customer_phone': '050-123',
        'p_order_items': [
          {
            'menu_item_id': 'i1',
            'menu_item_name_snapshot': 'Classic Burger',
            'quantity': 2,
            'unit_price_minor_snapshot': 4000,
            'line_total_minor': 11000,
            'notes': 'no salt',
            'modifiers': [
              {
                'modifier_option_id': 'o2',
                'option_name_snapshot': '240g',
                'modifier_name_snapshot': 'Weight',
                'price_minor_snapshot': 1500,
                'quantity': 1,
                'meat_snapshot': {'quantity': 2, 'unit': 'pc'},
              },
            ],
          },
        ],
        'p_client_subtotal_minor': 11000,
        'p_client_discount_total_minor': 0,
        'p_client_tax_total_minor': 1870,
        'p_client_grand_total_minor': 12870,
        'p_client_created_at': '2026-08-22T12:00:00.000Z',
      };
      expect(jsonEncode(a.params), jsonEncode(expected));
    });

    test('line display strings freeze at submit time in slip order and are '
        'unmodifiable', () {
      final a = build();
      final d = a.view!.lineDisplays.single;
      expect(d.lineId, 1);
      expect(d.itemName.of('en'), 'Classic Burger');
      expect(d.modifierNames.map((n) => n.of('en')), ['240g']);
      expect(() => a.view!.lineDisplays.add(d), throwsUnsupportedError);
      expect(() => d.modifierNames.clear(), throwsUnsupportedError);
    });

    test('ACCEPTED SNAPSHOT: every business field of the confirmation comes '
        'from the frozen attempt (not live state, not live menu)', () async {
      final held = Completer<Object?>();
      final h = _harness(
        tablePicker: true,
        overrides: {
          'get_device_branch_tax': (_) => _taxEnvelope(enabled: true, bp: 1700),
          'kiosk_submit_order': (p) => held.future.then(
            (_) => {..._acceptedEnvelope, 'order_id': p['p_order_id']},
          ),
        },
      );
      final c = h.container;
      await c.read(kioskLiveProvider.notifier).loadMenu();
      await c.read(kioskLiveProvider.notifier).refreshTables();
      final flow = c.read(kioskFlowProvider.notifier);
      flow.startFromAttract();
      flow.pickService(KioskServiceType.dineIn);
      flow.toggleTable('T1', id: _tableId);
      flow.confirmTable();
      flow.openItem('i1');
      flow.toggleOption('g1', 'o2');
      flow.setDraftNote('no salt');
      expect(flow.submitDraft(), isTrue);
      flow.setCustomerName('  Dana  ');
      flow.placeOrder();
      await c.settle();
      final frozen = flow.debugPendingAttempt!;
      final view = frozen.view!;
      held.complete(null);
      await c.settle();
      final s = c.read(kioskFlowProvider);
      expect(s.screen, KioskScreen.confirm);
      final order = s.lastOrder!;
      expect(order.code, displayOrderCode(frozen.orderId));
      expect(identical(order.lines, view.lines), isTrue);
      expect(identical(order.lineDisplays, view.lineDisplays), isTrue);
      expect(order.lines.single.quantity, 1);
      expect(order.lines.single.note, 'no salt');
      expect(order.lineDisplays!.single.itemName.of('en'), 'Classic Burger');
      expect(order.lineDisplays!.single.modifierNames.single.of('en'), '240g');
      expect(order.service, KioskServiceType.dineIn);
      expect(order.table, 'T1');
      expect(order.customerName, 'Dana');
      expect(order.subtotalMinor, view.subtotalMinor);
      expect(order.taxMinor, view.taxMinor);
      expect(order.totalMinor, view.grandMinor);
      expect(order.subtotalMinor, 5500);
      expect(order.taxMinor, 935); // round(5500*1700/10000)
      expect(order.totalMinor, 6435);
      expect(order.taxInclusive, isFalse);
    });

    testWidgets('menu drift after freeze: the slip renders the ORDERED names '
        '(A), never the new menu (B), even if the item is removed', (
      tester,
    ) async {
      var version = 'A';
      var removed = false;
      final held = Completer<Object?>();
      final h = _harness(
        overrides: {
          'kiosk_menu': (_) {
            final env = _menuEnvelope(
              burgerName: 'Burger $version',
              bigName: '240g $version',
            );
            if (removed) {
              (env['items'] as List).removeWhere(
                (it) => (it as Map)['id'] == 'i1',
              );
            }
            return env;
          },
          'kiosk_submit_order': (p) => held.future.then(
            (_) => {..._acceptedEnvelope, 'order_id': p['p_order_id']},
          ),
        },
      );
      final c = h.container;
      // testWidgets runs under a fake clock: Future.delayed-based settling
      // hangs, so the submit chain (pure microtasks) is driven by pumps.
      Future<void> settleW() async {
        for (var i = 0; i < 30; i++) {
          await tester.pump(Duration.zero);
        }
      }

      await _fillCart(c, note: 'x');
      final flow = c.read(kioskFlowProvider.notifier);
      flow.placeOrder();
      await settleW();
      expect(c.read(kioskFlowProvider).submitPhase, KioskSubmitPhase.inFlight);
      // The tenant publishes a RENAMED menu while acceptance is in flight.
      version = 'B';
      await c.read(kioskLiveProvider.notifier).loadMenu();
      held.complete(null);
      await settleW();
      expect(c.read(kioskFlowProvider).screen, KioskScreen.confirm);

      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: Consumer(
            builder: (context, ref, _) => MaterialApp(
              locale: Locale(
                ref.watch(kioskFlowProvider.select((st) => st.lang)),
              ),
              debugShowCheckedModeBanner: false,
              localizationsDelegates: restoflowLocalizationsDelegates,
              supportedLocales: kSupportedLocales,
              home: const KioskShell(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Burger A'), findsOneWidget);
      expect(find.text('240g A'), findsOneWidget);
      expect(find.textContaining('Burger B'), findsNothing);
      expect(find.textContaining('240g B'), findsNothing);

      // Even REMOVING the item entirely cannot blank the accepted slip.
      removed = true;
      await c.read(kioskLiveProvider.notifier).loadMenu();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Burger A'), findsOneWidget);
      expect(find.text('240g A'), findsOneWidget);
    });

    test('unconfirmed + menu drift + same-identity replay: the confirmation '
        'still shows the ORDERED names', () async {
      var version = 'A';
      var fail = true;
      final h = _harness(
        overrides: {
          'kiosk_menu': (_) => _menuEnvelope(
            burgerName: 'Burger $version',
            bigName: '240g $version',
          ),
          'kiosk_submit_order': (p) => fail
              ? SyncTransportException(SyncTransportErrorKind.transient)
              : {
                  ..._acceptedEnvelope,
                  'order_id': p['p_order_id'],
                  'idempotency_replay': true,
                },
        },
      );
      final c = h.container;
      await _fillCart(c);
      final flow = c.read(kioskFlowProvider.notifier);
      flow.placeOrder();
      await c.settle();
      expect(
        c.read(kioskFlowProvider).submitPhase,
        KioskSubmitPhase.unconfirmed,
      );
      final frozen = flow.debugPendingAttempt!;
      version = 'B';
      await c.read(kioskLiveProvider.notifier).loadMenu();
      fail = false;
      await flow.retrySubmit();
      final s = c.read(kioskFlowProvider);
      expect(s.screen, KioskScreen.confirm);
      final submits = h.rpc.calls
          .where((call) => call.$1 == 'kiosk_submit_order')
          .toList();
      expect(submits, hasLength(2));
      expect(submits[1].$2['p_order_id'], frozen.orderId);
      expect(
        s.lastOrder!.lineDisplays!.single.itemName.of('en'),
        'Burger A',
        reason: 'replayed confirmation = frozen submit-time content',
      );
      expect(
        s.lastOrder!.lineDisplays!.single.modifierNames.single.of('en'),
        '240g A',
      );
      expect(s.lastOrder!.code, displayOrderCode(frozen.orderId));
    });
  });
}

extension on ProviderContainer {
  /// Lets the async submit chain settle (event-loop turns + real time so
  /// nested awaited hops across fakes always resolve).
  Future<void> settle() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}
