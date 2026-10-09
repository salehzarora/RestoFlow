import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_local/kitchen_dispatch_document.dart'
    show rejectHostileKitchenKeys;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession;
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenPrepComponent;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_feature_kitchen/kitchen_print.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsItemView;
import 'package:restoflow_pos/src/data/order_edit_slip.dart';
import 'package:restoflow_pos/src/data/order_edit_slip_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosPersistenceException;
import 'package:restoflow_pos/src/state/local_storage_health_provider.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/failing_prefs.dart';

/// ORDER-EDIT-001F — the durable store of UNSENT paper change slips, held to
/// the 001E journal's contract: strict decode with VERBATIM quarantine, a
/// refused write is a typed failure, one envelope per device, every field
/// round-trips (the stored slip reprints the SAME document), and nothing in
/// it is money. Plus the bounded direct-print evidence (72 h, at most 200).

const _key = 'restoflow.pos.order_edit_slips.v1.dev-1';
const _evidenceKey = 'restoflow.pos.order_edit_slip_evidence.v1.dev-1';

final _now = DateTime.utc(2026, 10, 9, 12);

const _cola = KdsItemView(name: 'Cola', quantity: 3, modifiers: ['ice ×2']);

final _slip = OrderChangeSlipView(
  orderCode: '#A1B2C3',
  editNumber: 2,
  orderType: 'dine_in',
  tableLabel: 'T4',
  customerName: 'Noa',
  editedAt: DateTime.utc(2026, 10, 9, 11, 58, 1, 250).toLocal(),
  reasonCode: 'other',
  reasonText: 'guest asked',
  staffFirstName: 'Dana',
  changes: [
    const OrderChangeQuantity(was: _cola, nowQuantity: 1),
    const OrderChangeRemoved(KdsItemView(name: 'Fries', quantity: 1)),
  ],
  orderNow: const [
    KdsItemView(
      name: 'Cola',
      quantity: 1,
      modifiers: ['ice ×2'],
      note: 'no straw',
      prepComponents: [
        KitchenPrepComponent(name: 'Cup', quantity: 1, unit: 'pc'),
      ],
      linePosition: 1,
    ),
  ],
);

OrderEditSlipRecord _record({
  String orderEditId = 'edit-2',
  OrderChangeSlipView? slip,
  bool unbuilt = false,
  OrderEditSlipState state = OrderEditSlipState.pending,
}) => OrderEditSlipRecord(
  orderEditId: orderEditId,
  orderId: 'order-1',
  orderCode: '#A1B2C3',
  editNumber: 2,
  dispatchId: 'dispatch-7',
  editCreatedAt: DateTime.utc(2026, 10, 9, 11, 58, 1, 250),
  slip: unbuilt ? null : (slip ?? _slip),
  was: const {
    'oi-cola': OrderEditSlipItem(
      qty: 3,
      name: 'Cola',
      modifiers: [OrderEditSlipModifier(qty: 2, name: 'ice')],
    ),
  },
  lines: const [
    OrderEditSlipLine(
      op: OrderEditSlipOp.setQuantity,
      orderItemId: 'oi-cola',
      nowQty: 1,
    ),
    OrderEditSlipLine(op: OrderEditSlipOp.remove, orderItemId: 'oi-fries'),
  ],
  staffFirstName: 'Dana',
  state: state,
  attempts: 1,
  updatedAt: _now,
);

Future<SharedPreferences> _prefs([Map<String, Object> seed = const {}]) {
  SharedPreferences.setMockInitialValues(seed);
  return SharedPreferences.getInstance();
}

OrderEditSlipEvidence _evidence(String orderId, DateTime recordedAt) =>
    OrderEditSlipEvidence(
      orderId: orderId,
      dispatchId: 'd-$orderId',
      editCreatedAt: recordedAt.subtract(const Duration(seconds: 2)),
      recordedAt: recordedAt,
    );

Future<List<int>> _bytes(OrderChangeSlipView slip) =>
    renderOrderChangeSlipBytes(
      slip: slip,
      labels: kitchenTicketPrintLabelsForLanguageCode('en'),
      changeLabels: kitchenChangeSlipLabelsForLanguageCode('en'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('durability contract', () {
    test('an absent key is a valid EMPTY store', () async {
      final store = SharedPrefsOrderEditSlipStore(await _prefs());
      expect(await store.load('dev-1'), isEmpty);
      expect(await store.loadEvidence('dev-1', now: _now), isEmpty);
      expect(store.unreadableRecordCount('dev-1'), 0);
      expect(store.isDegraded, isFalse);
    });

    test('every field round-trips, and the stored slip reprints the SAME '
        'bytes', () async {
      final prefs = await _prefs();
      for (final state in OrderEditSlipState.values) {
        await SharedPrefsOrderEditSlipStore(
          prefs,
        ).persist('dev-1', {'edit-2': _record(state: state)});
        final back = (await SharedPrefsOrderEditSlipStore(
          prefs,
        ).load('dev-1'))['edit-2']!;
        expect(back.orderEditId, 'edit-2');
        expect(back.orderId, 'order-1');
        expect(back.orderCode, '#A1B2C3');
        expect(back.editNumber, 2);
        expect(back.dispatchId, 'dispatch-7');
        expect(back.editCreatedAt, DateTime.utc(2026, 10, 9, 11, 58, 1, 250));
        expect(back.state, state);
        expect(back.attempts, 1);
        expect(back.updatedAt, _now);
        expect(back.staffFirstName, 'Dana');
        expect(back.was['oi-cola']!.modifiers.single.qty, 2);
        expect(back.lines.map((l) => l.toJson()), [
          {
            'op': 'set_quantity',
            'order_item_id': 'oi-cola',
            'now_qty': 1,
            'new_order_item_ids': <Object?>[],
          },
          {
            'op': 'remove',
            'order_item_id': 'oi-fries',
            'new_order_item_ids': <Object?>[],
          },
        ]);
        expect(back.isBuilt, isTrue);
        expect(await _bytes(back.slip!), await _bytes(_slip));
        expect(
          jsonEncode(encodeOrderChangeSlipView(back.slip!)),
          jsonEncode(encodeOrderChangeSlipView(_slip)),
        );
      }
    });

    test('an UNBUILT record keeps its inputs and no slip', () async {
      final prefs = await _prefs();
      await SharedPrefsOrderEditSlipStore(
        prefs,
      ).persist('dev-1', {'edit-2': _record(unbuilt: true)});
      final back = (await SharedPrefsOrderEditSlipStore(
        prefs,
      ).load('dev-1'))['edit-2']!;
      expect(back.isBuilt, isFalse);
      expect(back.slip, isNull);
      expect(back.was.keys, ['oi-cola']);
      expect(back.lines, hasLength(2));
      expect(back.toJson().containsKey('slip'), isFalse);
    });

    test('a refused write THROWS a typed failure and leaves the previous set '
        'on disk', () async {
      final prefs = FailingPrefs(await _prefs());
      final store = SharedPrefsOrderEditSlipStore(prefs);
      await store.persist('dev-1', {'edit-2': _record()});
      final before = prefs.getString(_key);
      prefs.failWrites = true;
      await expectLater(
        store.persist('dev-1', {
          'edit-2': _record(),
          'edit-3': _record(orderEditId: 'edit-3'),
        }),
        throwsA(isA<PosPersistenceException>()),
      );
      await expectLater(
        store.appendEvidence('dev-1', _evidence('o-1', _now), now: _now),
        throwsA(isA<PosPersistenceException>()),
      );
      expect(store.isDegraded, isTrue);
      expect(prefs.getString(_key), before);
    });

    test('one envelope per device: another device never sees it', () async {
      final prefs = await _prefs();
      final store = SharedPrefsOrderEditSlipStore(prefs);
      await store.persist('dev-1', {'edit-2': _record()});
      await store.persist('dev-2', {'edit-3': _record(orderEditId: 'edit-3')});
      await store.appendEvidence('dev-2', _evidence('o-2', _now), now: _now);
      expect((await store.load('dev-1')).keys, ['edit-2']);
      expect((await store.load('dev-2')).keys, ['edit-3']);
      expect(await store.loadEvidence('dev-1', now: _now), isEmpty);
      expect(await store.loadEvidence('dev-2', now: _now), hasLength(1));
      expect(prefs.getString(_key), isNotNull);
    });

    test('an unknown schema version is not mis-parsed', () async {
      final store = SharedPrefsOrderEditSlipStore(
        await _prefs({
          _key: jsonEncode({
            'version': 99,
            'records': {'edit-2': _record().toJson()},
          }),
        }),
      );
      expect(await store.load('dev-1'), isEmpty);
    });

    test('a malformed ENVELOPE is preserved, never overwritten', () async {
      final prefs = await _prefs({_key: '{not json at all'});
      final store = SharedPrefsOrderEditSlipStore(prefs);
      expect(await store.load('dev-1'), isEmpty);
      await store.persist('dev-1', {'edit-2': _record()});
      expect(prefs.getString('$_key.unreadable'), '{not json at all');
      expect(store.unreadableRecordCount('dev-1'), 1);
      expect((await store.load('dev-1')).keys, ['edit-2']);
    });

    test('the in-memory store keeps a session-only copy', () async {
      final store = InMemoryOrderEditSlipStore();
      await store.persist('dev-1', {'edit-2': _record()});
      await store.appendEvidence('dev-1', _evidence('o-1', _now), now: _now);
      expect((await store.load('dev-1')).keys, ['edit-2']);
      expect(await store.load('dev-2'), isEmpty);
      expect(await store.loadEvidence('dev-1', now: _now), hasLength(1));
    });
  });

  group('strict decode: an unreadable record is quarantined VERBATIM', () {
    Map<String, Object?> good() =>
        (jsonDecode(jsonEncode(_record().toJson())) as Map)
            .cast<String, Object?>();
    final cases = <String, Map<String, Object?> Function()>{
      'an unknown key': () => good()..['price_minor'] = 800,
      'a blank order_edit_id': () => good()..['order_edit_id'] = ' ',
      'no order_id': () => good()..remove('order_id'),
      'edit_number 0': () => good()..['edit_number'] = 0,
      'a negative attempt count': () => good()..['attempts'] = -1,
      'an unknown state': () => good()..['state'] = 'sent',
      'an unparseable updated_at': () => good()..['updated_at'] = 'soon',
      'a slip of another order': () =>
          good()
            ..['slip'] = encodeOrderChangeSlipView(
              OrderChangeSlipView(
                orderCode: '#FFFFFF',
                editNumber: 2,
                orderNow: const [KdsItemView(name: 'Cola', quantity: 1)],
              ),
            ),
      'a slip of another edit number': () =>
          good()
            ..['slip'] = encodeOrderChangeSlipView(
              OrderChangeSlipView(
                orderCode: '#A1B2C3',
                editNumber: 3,
                orderNow: const [KdsItemView(name: 'Cola', quantity: 1)],
              ),
            ),
      'a slip with an unknown key': () =>
          good()..['slip'] = {...encodeOrderChangeSlipView(_slip), 'tax': 1},
      'a was item with a money key': () => good()
        ..['was'] = [
          {
            'order_item_id': 'oi-cola',
            'item': {
              'qty': 1,
              'name': 'Cola',
              'modifiers': <Object?>[],
              'line_total_minor': 800,
            },
          },
        ],
      'an edit line of an unknown op': () => good()
        ..['edit_lines'] = [
          {'op': 'remake', 'order_item_id': 'x', 'new_order_item_ids': []},
        ],
    };
    cases.forEach((label, build) {
      test(label, () async {
        final bad = build();
        final prefs = await _prefs({
          _key: jsonEncode({
            'version': 1,
            'records': {'edit-9': bad, 'edit-2': _record().toJson()},
          }),
        });
        final store = SharedPrefsOrderEditSlipStore(prefs);
        expect((await store.load('dev-1')).keys, ['edit-2']);
        expect(store.unreadableRecordCount('dev-1'), 1);
        // A later write keeps the unreadable record byte-for-byte.
        await store.persist('dev-1', {'edit-2': _record()});
        final records =
            (jsonDecode(prefs.getString(_key)!) as Map)['records'] as Map;
        expect(jsonEncode(records['edit-9']), jsonEncode(bad));
      });
    });

    test(
      'a record filed under ANOTHER edit id is not this build\'s write',
      () async {
        final prefs = await _prefs({
          _key: jsonEncode({
            'version': 1,
            'records': {'edit-x': _record().toJson()},
          }),
        });
        final store = SharedPrefsOrderEditSlipStore(prefs);
        expect(await store.load('dev-1'), isEmpty);
        expect(store.unreadableRecordCount('dev-1'), 1);
      },
    );
  });

  group('money-free', () {
    test(
      'no money or hostile kitchen key anywhere in a stored record',
      () async {
        final prefs = await _prefs();
        final store = SharedPrefsOrderEditSlipStore(prefs);
        await store.persist('dev-1', {'edit-2': _record()});
        await store.appendEvidence('dev-1', _evidence('o-1', _now), now: _now);
        for (final key in [_key, _evidenceKey]) {
          final stored = prefs.getString(key)!;
          expect(stored, isNot(contains('_minor')));
          expect(
            () => rejectHostileKitchenKeys(jsonDecode(stored), path: 'stored'),
            returnsNormally,
          );
        }
      },
    );
  });

  group('direct-print evidence: 72 h, at most 200, oldest first', () {
    test('expired entries are dropped on read and on write', () async {
      final prefs = await _prefs();
      final store = SharedPrefsOrderEditSlipStore(prefs);
      final old = _now.subtract(const Duration(hours: 73));
      await store.appendEvidence('dev-1', _evidence('o-old', old), now: old);
      await store.appendEvidence(
        'dev-1',
        _evidence('o-new', _now.subtract(const Duration(hours: 1))),
        now: _now,
      );
      final live = await store.loadEvidence('dev-1', now: _now);
      expect(live.map((e) => e.orderId), ['o-new']);
      final stored =
          (jsonDecode(prefs.getString(_evidenceKey)!) as Map)['evidence']
              as List;
      expect(stored, hasLength(1));
      // Read-side expiry too: the entry recorded 1 h before [_now] is gone
      // 72 h later, with no write in between.
      expect(
        await store.loadEvidence(
          'dev-1',
          now: _now.add(const Duration(hours: 72)),
        ),
        isEmpty,
      );
    });

    test('at most 200 entries: the OLDEST go first', () async {
      final prefs = await _prefs();
      final store = SharedPrefsOrderEditSlipStore(prefs);
      for (var i = 0; i < 205; i++) {
        final at = _now.subtract(Duration(minutes: 205 - i));
        await store.appendEvidence('dev-1', _evidence('o-$i', at), now: at);
      }
      final live = await store.loadEvidence('dev-1', now: _now);
      expect(live, hasLength(kOrderEditSlipEvidenceCap));
      expect(live.first.orderId, 'o-5');
      expect(live.last.orderId, 'o-204');
      expect(live.last.editCreatedAt, isNotNull);
    });

    test('an unreadable evidence entry is dropped, never fatal', () async {
      final prefs = await _prefs({
        _evidenceKey: jsonEncode({
          'version': 1,
          'evidence': [
            {'order_id': 'o-bad', 'recorded_at': 'never'},
            {..._evidence('o-ok', _now).toJson(), 'price_minor': 1},
            _evidence('o-ok', _now).toJson(),
          ],
        }),
      });
      final store = SharedPrefsOrderEditSlipStore(prefs);
      expect(
        (await store.loadEvidence('dev-1', now: _now)).map((e) => e.orderId),
        ['o-ok'],
      );
      final garbled = SharedPrefsOrderEditSlipStore(
        await _prefs({_evidenceKey: '{nope'}),
      );
      expect(await garbled.loadEvidence('dev-1', now: _now), isEmpty);
    });
  });

  group('local-storage health', () {
    ProviderContainer container(OrderEditSlipStore store) {
      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posSyncSessionProvider.overrideWithValue(
            const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
          ),
          orderEditSlipStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('a healthy slip store reports healthy', () async {
      final store = SharedPrefsOrderEditSlipStore(await _prefs());
      await store.persist('dev-1', {'edit-2': _record()});
      expect(
        container(store).read(posLocalStorageHealthProvider).isHealthy,
        isTrue,
      );
    });

    test('a refused slip write is reported', () async {
      final prefs = FailingPrefs(await _prefs())..failWrites = true;
      final store = SharedPrefsOrderEditSlipStore(prefs);
      await expectLater(
        store.persist('dev-1', {'edit-2': _record()}),
        throwsA(isA<PosPersistenceException>()),
      );
      expect(
        container(store).read(posLocalStorageHealthProvider).writeRefused,
        isTrue,
      );
    });

    test('an unreadable slip record is counted for THIS device', () async {
      final store = SharedPrefsOrderEditSlipStore(
        await _prefs({
          _key: jsonEncode({
            'version': 1,
            'records': {'edit-9': 'garbled'},
          }),
        }),
      );
      expect(
        container(store).read(posLocalStorageHealthProvider).unreadableRecords,
        1,
      );
    });
  });
}
