import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show BranchTax;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/order_edit_diff.dart';
import 'package:restoflow_pos/src/data/order_edit_journal_store.dart';
import 'package:restoflow_pos/src/data/order_edit_read_model.dart';
import 'package:restoflow_pos/src/data/order_edit_response.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosPersistenceException;
import 'package:restoflow_pos/src/state/local_storage_health_provider.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/failing_prefs.dart';
import 'support/order_edit_fixtures.dart';

/// ORDER-EDIT-001E — the durable sent-order-edit journal (plan step 5, test
/// 9), held to the Add-items journal's contract: strict decode with VERBATIM
/// quarantine, a refused write is a typed failure, one envelope per device,
/// every phase round-trips, and the frozen payload comes back byte-identical.

const _key = 'restoflow.pos.order_edit_journal.v1.dev-1';

/// A real frozen payload, built by the engine (the design's worked example
/// with a reason, a bill instant and nested modifier maps).
Map<String, Object?> _payload() {
  final b = baselineOf(
    detail(
      items: [
        detailItem(
          'oi-burger',
          quantity: 2,
          unit: 4000,
          modifiers: [
            detailMod('opt-tomato', 'Tomato'),
            detailMod('opt-cheese', 'Cheese', price: 300),
          ],
        ),
        detailItem('oi-fries', unit: 1500),
      ],
    ),
  );
  final burger = b.lineFor('oi-burger')!;
  final plan = planOrderEdit(b, [
    sent(burger, quantity: 1),
    part(burger, 1, quantity: 1, modifiers: [mod('opt-cheese', 'Cheese')]),
    sent(b.lineFor('oi-fries')!, removed: true),
    added('line-1', 'mi-lemonade', name: 'Lemonade', unit: 900),
  ], tax: const BranchTax(enabled: true, rateBp: 1700));
  return buildOrderEditPayload(
    plan,
    reasonCode: 'other',
    reasonText: 'guest asked',
    billPresentedAt: DateTime.utc(2026, 10, 9, 11, 30),
  );
}

const _applied = OrderEditApplied(
  orderEditId: 'edit-9',
  editNumber: 2,
  revision: 7,
  kitchenChannel: PosKitchenChannel.paper,
  kitchenAckRequired: false,
  newRoundId: 'round-3',
  newRoundNumber: 3,
  remakeChangeCount: 1,
  kitchenDispatch: OrderEditKitchenDispatch(id: 'dispatch-1'),
  orderStatus: 'served',
);

/// ORDER-EDIT-001F: a paper envelope's changes (modify + add).
const _appliedWithChanges = OrderEditApplied(
  orderEditId: 'edit-9',
  editNumber: 2,
  revision: 7,
  kitchenChannel: PosKitchenChannel.paper,
  kitchenAckRequired: false,
  kitchenDispatch: OrderEditKitchenDispatch(id: 'dispatch-1'),
  changes: [
    OrderEditAppliedChange(
      kind: 'modify',
      orderItemId: 'oi-burger',
      newOrderItemIds: ['n-1', 'n-2'],
    ),
    OrderEditAppliedChange(kind: 'add', newOrderItemIds: ['n-3']),
  ],
);

/// ORDER-EDIT-001F (D2): the frozen "was" projections, as persisted.
const _slipWasJson = [
  {
    'order_item_id': 'oi-burger',
    'item': {
      'qty': 2,
      'name': 'Burger',
      'note': 'no salt',
      'prep': [
        {'name': 'Bun', 'quantity': 1, 'unit': 'pc'},
      ],
      'modifiers': [
        {'qty': 2, 'name': 'Tomato'},
        {'qty': 1, 'name': 'Cheese'},
      ],
    },
  },
  {
    'order_item_id': 'OI-FRIES',
    'item': {'qty': 1, 'name': 'Fries', 'modifiers': <Object?>[]},
  },
];

Map<String, Object?> _map(Object? raw) => (raw as Map).cast<String, Object?>();

OrderEditJournalRecord _record({
  String localOperationId = 'op-1',
  OrderEditJournalPhase phase = OrderEditJournalPhase.dispatching,
  OrderEditApplied? applied,
}) => OrderEditJournalRecord(
  localOperationId: localOperationId,
  orderId: 'order-1',
  orderCode: '#A1B2C3',
  clientCreatedAt: DateTime.utc(2026, 10, 9, 11, 31, 5, 123),
  generation: 4,
  payload: _payload(),
  summary: const OrderEditAttemptSummary(
    removedCount: 1,
    modifiedCount: 1,
    addedCount: 1,
    remakeDishCount: 1,
  ),
  phase: phase,
  attemptCount: 2,
  employeeProfileId: 'emp-7',
  lastErrorCode: 'transport',
  applied: applied,
);

Future<SharedPreferences> _prefs([Map<String, Object> seed = const {}]) {
  SharedPreferences.setMockInitialValues(seed);
  return SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('durability contract', () {
    test('an absent key is a valid EMPTY journal', () async {
      final store = SharedPrefsOrderEditJournalStore(await _prefs());
      expect(await store.load('dev-1'), isEmpty);
      expect(store.unreadableRecordCount('dev-1'), 0);
      expect(store.isDegraded, isFalse);
    });

    test('a refused write THROWS a typed failure and leaves the previous set '
        'on disk', () async {
      final prefs = FailingPrefs(await _prefs());
      final store = SharedPrefsOrderEditJournalStore(prefs);
      await store.persist('dev-1', {'op-1': _record()});
      final before = prefs.getString(_key);

      prefs.failWrites = true;
      await expectLater(
        store.persist('dev-1', {
          'op-1': _record(),
          'op-2': _record(localOperationId: 'op-2'),
        }),
        throwsA(isA<PosPersistenceException>()),
      );
      expect(store.isDegraded, isTrue);
      expect(prefs.getString(_key), before);
    });

    test('every phase round-trips exactly', () async {
      final prefs = await _prefs();
      for (final phase in OrderEditJournalPhase.values) {
        final record = _record(
          phase: phase,
          applied: phase == OrderEditJournalPhase.awaitingAuthoritativeRefresh
              ? _applied
              : null,
        );
        await SharedPrefsOrderEditJournalStore(
          prefs,
        ).persist('dev-1', {'op-1': record});
        final back = (await SharedPrefsOrderEditJournalStore(
          prefs,
        ).load('dev-1'))['op-1']!;
        expect(back.phase, phase);
        expect(back.localOperationId, 'op-1');
        expect(back.orderId, 'order-1');
        expect(back.orderCode, '#A1B2C3');
        expect(back.clientCreatedAt, DateTime.utc(2026, 10, 9, 11, 31, 5, 123));
        expect(back.clientCreatedAt.isUtc, isTrue);
        expect(back.generation, 4);
        expect(back.attemptCount, 2);
        expect(back.employeeProfileId, 'emp-7');
        expect(back.lastErrorCode, 'transport');
        expect(back.summary, record.summary);
        expect(back.isConflict, phase == OrderEditJournalPhase.conflict);
        expect(
          back.awaitingRefresh,
          phase == OrderEditJournalPhase.awaitingAuthoritativeRefresh,
        );
      }
    });

    test('the applied facts (and the paper dispatch) round-trip', () async {
      final prefs = await _prefs();
      await SharedPrefsOrderEditJournalStore(prefs).persist('dev-1', {
        'op-1': _record(
          phase: OrderEditJournalPhase.awaitingAuthoritativeRefresh,
          applied: const OrderEditApplied(
            orderEditId: 'edit-9',
            editNumber: 2,
            revision: 7,
            kitchenChannel: PosKitchenChannel.paper,
            kitchenAckRequired: false,
            remakeChangeCount: 0,
            kitchenDispatch: OrderEditKitchenDispatch(
              id: 'dispatch-1',
              claimExpiresAt: null,
            ),
            autoCompleted: true,
          ),
        ),
      });
      final a = (await SharedPrefsOrderEditJournalStore(
        prefs,
      ).load('dev-1'))['op-1']!.applied!;
      expect(a.orderEditId, 'edit-9');
      expect(a.editNumber, 2);
      expect(a.revision, 7);
      expect(a.kitchenChannel, PosKitchenChannel.paper);
      expect(a.kitchenAckRequired, isFalse);
      expect(a.newRoundId, isNull);
      expect(a.kitchenDispatch!.id, 'dispatch-1');
      expect(a.kitchenDispatch!.claimExpiresAt, isNull);
      expect(a.autoCompleted, isTrue);

      final withExpiry = _record(
        phase: OrderEditJournalPhase.awaitingAuthoritativeRefresh,
        applied: OrderEditApplied(
          orderEditId: 'edit-9',
          editNumber: 2,
          revision: 7,
          kitchenChannel: PosKitchenChannel.paper,
          kitchenAckRequired: false,
          kitchenDispatch: OrderEditKitchenDispatch(
            id: 'dispatch-1',
            claimExpiresAt: DateTime.utc(2026, 10, 9, 11, 41),
          ),
        ),
      );
      await SharedPrefsOrderEditJournalStore(
        prefs,
      ).persist('dev-1', {'op-1': withExpiry});
      expect(
        (await SharedPrefsOrderEditJournalStore(
          prefs,
        ).load('dev-1'))['op-1']!.applied!.kitchenDispatch!.claimExpiresAt,
        DateTime.utc(2026, 10, 9, 11, 41),
      );
    });

    test('ORDER-EDIT-001F (D2): the frozen slip "was" lines and the applied '
        'changes round-trip', () async {
      final prefs = await _prefs();
      final record = OrderEditJournalRecord.fromJson(
        _map(
          jsonDecode(
            jsonEncode(
              _record(
                phase: OrderEditJournalPhase.awaitingAuthoritativeRefresh,
                applied: _appliedWithChanges,
              ).toJson(),
            ),
          ),
        )..['slip_was'] = _slipWasJson,
      );
      await SharedPrefsOrderEditJournalStore(
        prefs,
      ).persist('dev-1', {'op-1': record});
      final back = (await SharedPrefsOrderEditJournalStore(
        prefs,
      ).load('dev-1'))['op-1']!;
      expect(back.slipWas!.keys, ['oi-burger', 'oi-fries']);
      final burger = back.slipWas!['oi-burger']!;
      expect(burger.qty, 2);
      expect(burger.note, 'no salt');
      expect(burger.prep.single.name, 'Bun');
      expect(burger.modifiers.map((m) => '${m.qty} ${m.name}'), [
        '2 Tomato',
        '1 Cheese',
      ]);
      expect(back.applied!.changes.map((c) => c.kind), ['modify', 'add']);
      expect(back.applied!.changes.first.newOrderItemIds, ['n-1', 'n-2']);
      expect(back.applied!.changes.last.orderItemId, isNull);
      // A phase transition keeps both.
      final moved = back.copyWith(attemptCount: 5);
      expect(moved.slipWas, same(back.slipWas));
      expect(
        jsonEncode(moved.toJson()['slip_was']),
        jsonEncode(back.toJson()['slip_was']),
      );
    });

    test('ORDER-EDIT-001F: a 001E-format record (no slip keys) still decodes, '
        'and a KDS record writes none', () async {
      final legacy = _record(
        phase: OrderEditJournalPhase.awaitingAuthoritativeRefresh,
        applied: _applied,
      ).toJson();
      expect(legacy.containsKey('slip_was'), isFalse);
      expect((legacy['applied']! as Map).containsKey('changes'), isFalse);
      final back = OrderEditJournalRecord.fromJson(legacy);
      expect(back.slipWas, isNull);
      expect(back.applied!.changes, isEmpty);
    });

    test('ORDER-EDIT-001F: unreadable slip evidence costs the SLIP, never the '
        'record (its identity may be live on the server)', () {
      final base = _record(
        phase: OrderEditJournalPhase.awaitingAuthoritativeRefresh,
        applied: _appliedWithChanges,
      ).toJson();
      for (final bad in <Object?>[
        'garbled',
        [
          {'order_item_id': 'oi-1'},
        ],
        [
          {
            'order_item_id': '',
            'item': {'qty': 1, 'name': 'Cola', 'modifiers': <Object?>[]},
          },
        ],
        [
          {
            'order_item_id': 'oi-1',
            'item': {
              'qty': 1,
              'name': 'Cola',
              'modifiers': <Object?>[],
              'price_minor': 800,
            },
          },
        ],
      ]) {
        final back = OrderEditJournalRecord.fromJson({
          ...base,
          'slip_was': bad,
        });
        expect(back.slipWas, isNull, reason: '$bad');
        expect(back.localOperationId, 'op-1');
      }
      final badChanges = _map(jsonDecode(jsonEncode(base)));
      (badChanges['applied']! as Map)['changes'] = [
        {'kind': 'remake', 'order_item_id': 'oi-1', 'new_order_item_ids': []},
      ];
      final back = OrderEditJournalRecord.fromJson(badChanges);
      expect(back.applied!.changes, isEmpty);
      expect(back.applied!.orderEditId, 'edit-9');
    });

    test('the frozen payload comes back byte-identical', () async {
      final prefs = await _prefs();
      final record = _record(phase: OrderEditJournalPhase.transportUncertain);
      await SharedPrefsOrderEditJournalStore(
        prefs,
      ).persist('dev-1', {'op-1': record});
      final back = (await SharedPrefsOrderEditJournalStore(
        prefs,
      ).load('dev-1'))['op-1']!;
      expect(jsonEncode(back.payload), jsonEncode(record.payload));
      // 2 × (4000 + 300) kept as modified, fries removed, lemonade 900 added:
      // 9500; 17% = 1615.
      expect(back.payload['expected'], {
        'subtotal_minor': 9500,
        'tax_total_minor': 1615,
        'grand_total_minor': 11115,
      });
      // A second persist of the RESTORED record is still the same bytes.
      await SharedPrefsOrderEditJournalStore(
        prefs,
      ).persist('dev-1', {'op-1': back.copyWith(attemptCount: 3)});
      final again = (await SharedPrefsOrderEditJournalStore(
        prefs,
      ).load('dev-1'))['op-1']!;
      expect(jsonEncode(again.payload), jsonEncode(record.payload));
      expect(again.attemptCount, 3);
    });

    test('one envelope per device: another device never sees it', () async {
      final prefs = await _prefs();
      final store = SharedPrefsOrderEditJournalStore(prefs);
      await store.persist('dev-1', {'op-1': _record()});
      await store.persist('dev-2', {'op-2': _record(localOperationId: 'op-2')});
      expect((await store.load('dev-1')).keys, ['op-1']);
      expect((await store.load('dev-2')).keys, ['op-2']);
      expect(prefs.getString(_key), isNotNull);
      expect(
        prefs.getString('restoflow.pos.order_edit_journal.v1.dev-2'),
        isNotNull,
      );
    });

    test('an unknown schema version is not mis-parsed', () async {
      final store = SharedPrefsOrderEditJournalStore(
        await _prefs({
          _key: jsonEncode({
            'version': 99,
            'records': {'op-1': _record().toJson()},
          }),
        }),
      );
      expect(await store.load('dev-1'), isEmpty);
    });

    test('a malformed ENVELOPE is preserved, never overwritten', () async {
      final prefs = await _prefs({_key: '{not json at all'});
      final store = SharedPrefsOrderEditJournalStore(prefs);
      expect(await store.load('dev-1'), isEmpty);
      await store.persist('dev-1', {'op-1': _record()});
      expect(prefs.getString('$_key.unreadable'), '{not json at all');
      expect(store.unreadableRecordCount('dev-1'), 1);
      expect((await store.load('dev-1')).keys, ['op-1']);
    });

    test('the in-memory store keeps a session-only copy', () async {
      final store = InMemoryOrderEditJournalStore();
      await store.persist('dev-1', {'op-1': _record()});
      expect((await store.load('dev-1')).keys, ['op-1']);
      expect(await store.load('dev-2'), isEmpty);
    });
  });

  group('strict decode: an unreadable record is quarantined VERBATIM', () {
    final corruptions = <String, void Function(Map<String, Object?>)>{
      'a summary count that is not an integer': (j) =>
          (j['summary']! as Map)['added_count'] = '1',
      'a payload for ANOTHER order': (j) =>
          (j['payload']! as Map)['order_id'] = 'order-2',
      'a payload without changes': (j) =>
          (j['payload']! as Map)['changes'] = <Object?>[],
      'a payload without expected totals': (j) =>
          (j['payload']! as Map).remove('expected'),
      'an unknown phase': (j) => j['phase'] = 'from_a_newer_build',
      'an applied record without its facts': (j) => j
        ..['phase'] = 'awaitingAuthoritativeRefresh'
        ..['applied'] = null,
      'an applied edit number that is not an integer': (j) => j
        ..['phase'] = 'awaitingAuthoritativeRefresh'
        ..['applied'] = {
          ...(_record(applied: _applied).toJson()['applied']! as Map),
          'edit_number': '2',
        },
      'a generation that is not an integer': (j) => j['generation'] = '4',
      'an operator id that is not a string': (j) =>
          j['employee_profile_id'] = 7,
      'a blank operation id': (j) => j['local_operation_id'] = ' ',
      'an unparseable timestamp': (j) => j['client_created_at'] = 'yesterday',
    };

    corruptions.forEach((label, corrupt) {
      test(label, () async {
        final bad =
            jsonDecode(jsonEncode(_record(localOperationId: 'op-bad').toJson()))
                as Map<String, Object?>;
        corrupt(bad);
        final prefs = await _prefs({
          _key: jsonEncode({
            'version': SharedPrefsOrderEditJournalStore.schemaVersion,
            'records': {
              'op-good': _record(localOperationId: 'op-good').toJson(),
              'op-bad': bad,
            },
          }),
        });
        final store = SharedPrefsOrderEditJournalStore(prefs);

        final loaded = await store.load('dev-1');
        expect(
          loaded.keys,
          ['op-good'],
          reason: 'an unreadable record is never handed out to be replayed',
        );
        expect(store.unreadableRecordCount('dev-1'), 1);

        await store.persist('dev-1', loaded);
        final stored =
            (jsonDecode(prefs.getString(_key)!) as Map)['records'] as Map;
        expect(
          jsonEncode(stored['op-bad']),
          jsonEncode(bad),
          reason:
              'a record naming a possibly-live server edit is not ours to '
              'delete just because this build cannot read it',
        );
      });
    });
  });

  group('local-storage health', () {
    const session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

    ProviderContainer container(
      OrderEditJournalStore store, {
      SyncSession? withSession = session,
    }) {
      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posSyncSessionProvider.overrideWithValue(withSession),
          orderEditJournalStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('a healthy journal reports healthy', () async {
      final store = SharedPrefsOrderEditJournalStore(await _prefs());
      await store.persist('dev-1', {'op-1': _record()});
      expect(
        container(store).read(posLocalStorageHealthProvider).isHealthy,
        isTrue,
      );
    });

    test('a refused journal write is reported', () async {
      final prefs = FailingPrefs(await _prefs());
      final store = SharedPrefsOrderEditJournalStore(prefs);
      prefs.failWrites = true;
      await store
          .persist('dev-1', {'op-1': _record()})
          .catchError((Object _) {});
      final health = container(store).read(posLocalStorageHealthProvider);
      expect(health.writeRefused, isTrue);
      expect(health.isHealthy, isFalse);
    });

    test('an unreadable journal record is counted for THIS device', () async {
      final prefs = await _prefs({
        _key: jsonEncode({
          'version': SharedPrefsOrderEditJournalStore.schemaVersion,
          'records': {
            'op-bad': {'local_operation_id': 'op-bad'},
          },
        }),
      });
      final store = SharedPrefsOrderEditJournalStore(prefs);
      expect(
        container(store).read(posLocalStorageHealthProvider).unreadableRecords,
        1,
      );
      expect(
        container(
          store,
          withSession: null,
        ).read(posLocalStorageHealthProvider).unreadableRecords,
        0,
        reason: 'without a session there is no device scope to count',
      );
    });
  });
}
