import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport, SyncSession;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/draft_recovery_store.dart';
import 'package:restoflow_pos/src/data/durable_outbox_store.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/order_snapshot_repository.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/draft_recovery_controller.dart';
import 'package:restoflow_pos/src/state/local_storage_health_provider.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart'
    show posSyncClockProvider, orderSnapshotRepositoryProvider;
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart'
    show submitOrderFromCart;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/failing_prefs.dart';
import 'support/verified_kitchen_mode_readiness.dart';

/// MONEY-DURABLE-STORES-003B — failing-first proof for the two durable stores
/// that still lie about their writes.
///
/// THE INVARIANT UNDER TEST: a local operation must never be described as
/// durably persisted unless the underlying storage write was CONFIRMED.
/// `SharedPreferences.setString` returning **false** is a persistence failure;
/// "it did not throw" is not sufficient. Four sibling stores in this app already
/// enforce exactly that (`recent_orders_store.dart:185`,
/// `sync_cursor_store.dart:124`, `parked_carts_store.dart:444`,
/// `ready_notifications_store.dart:307`). The durable OUTBOX
/// (`durable_outbox_store.dart:87`) and the DRAFT-RECOVERY store
/// (`draft_recovery_store.dart:150`) are the two that do not.
///
/// The second invariant: a record this build cannot READ is not a record it is
/// entitled to DESTROY. The outbox has no quarantine at all — 002B added one to
/// the recent-orders and recovery stores but not here — so an entry it fails to
/// decode is erased by the very next write.
///
/// Every fixture below uses the REAL production stores over a REAL
/// (mock-initialised) SharedPreferences, with [FailingPrefs] injecting only the
/// one failure the real platform actually produces.

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'device-abc');
const _outboxKey = 'restoflow.pos.outbox.v1.device-abc';
const _recoveryKey = 'restoflow.pos.draft_recovery.v1';

OutboxEntry _entry({
  String localOperationId = 'op-1',
  String orderId = 'order-1',
  String deviceId = 'device-abc',
}) {
  final payload = OrderSubmissionPayload(
    orderId: orderId,
    localOperationId: localOperationId,
    deviceId: deviceId,
    organizationId: 'org-1',
    restaurantId: 'rest-1',
    branchId: 'branch-A',
    orderType: OrderType.takeaway,
    currencyCode: 'ILS',
    subtotalMinor: 4200,
    grandTotalMinor: 4200,
    items: const [
      OrderSubmissionItem(
        menuItemId: 'm1',
        nameSnapshot: 'Burger',
        quantity: 2,
        unitPriceMinorSnapshot: 2100,
        lineTotalMinor: 4200,
      ),
    ],
    clientCreatedAt: DateTime.utc(2026, 8, 6, 9),
  );
  return OutboxEntry(
    id: 'outbox-$localOperationId',
    deviceId: deviceId,
    organizationId: 'org-1',
    restaurantId: 'rest-1',
    branchId: 'branch-A',
    localOperationId: localOperationId,
    operationType: 'order.submit',
    targetEntity: 'order',
    targetId: orderId,
    payloadJson: jsonEncode(payload.toJson()),
    summary: const OrderSummary(
      orderNumber: 'A-1',
      orderType: OrderType.takeaway,
      tableLabel: null,
      itemCount: 2,
      subtotalMinor: 4200,
      currencyCode: 'ILS',
    ),
    syncState: OutboxSyncState.pending,
    clientCreatedAt: DateTime.utc(2026, 8, 6, 9),
  );
}

/// A transport that records every call, so "no dispatch happened" is an
/// assertion about the ONE network boundary rather than an inference.
class _RecordingTransport implements SyncRpcTransport {
  final List<Map<String, dynamic>> calls = <Map<String, dynamic>>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add(params);
    return <String, dynamic>{'ok': true, 'results': <dynamic>[]};
  }
}

Map<String, Object?> _envelope(String? raw) =>
    (jsonDecode(raw!) as Map).cast<String, Object?>();

List<Object?> _storedOutboxEntries(SharedPreferences prefs) =>
    (_envelope(prefs.getString(_outboxKey))['entries']! as List)
        .cast<Object?>();

Map<String, Object?> _storedRecoveries(SharedPreferences prefs) =>
    (_envelope(prefs.getString(_recoveryKey))['recoveries']! as Map)
        .cast<String, Object?>();

CartDraftSnapshot _draft() => const CartDraftSnapshot(
  currencyCode: 'ILS',
  lines: [
    CartDraftLine(
      menuItemId: 'burger-9',
      name: 'Burger',
      basePriceMinor: 4500,
      quantity: 1,
    ),
  ],
);

PosDraftRecovery _recovery(String entryId) => PosDraftRecovery(
  draft: _draft(),
  orderType: OrderType.takeaway,
  outboxEntryId: entryId,
  binding: const PosRecoveryBinding(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // A — THE DURABLE OUTBOX STORE MUST NOT CLAIM A WRITE THAT DID NOT STICK
  // =========================================================================
  group('A. durable outbox store — write truthfulness', () {
    test('A1 persist THROWS when setString refuses (returns false)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = FailingPrefs(await SharedPreferences.getInstance());
      final store = SharedPrefsOutboxStore(prefs);

      prefs.failWrites = true;
      await expectLater(
        store.persist(_session.deviceId, <OutboxEntry>[_entry()]),
        throwsA(isA<Exception>()),
        reason:
            'a refused localStorage write is a persistence FAILURE; the store '
            'must not complete normally and let the caller believe the order '
            'is queued (recent_orders_store.dart:185 is the house pattern)',
      );
    });

    test('A2 a refused write leaves the PREVIOUS durable set intact', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = FailingPrefs(await SharedPreferences.getInstance());
      final store = SharedPrefsOutboxStore(prefs);

      await store.persist(_session.deviceId, <OutboxEntry>[_entry()]);
      final before = prefs.getString(_outboxKey);
      expect(before, isNotNull);

      prefs.failWrites = true;
      await store
          .persist(_session.deviceId, <OutboxEntry>[
            _entry(),
            _entry(localOperationId: 'op-2', orderId: 'order-2'),
          ])
          .catchError((Object _) {});

      expect(
        prefs.getString(_outboxKey),
        before,
        reason: 'a refused write must not half-rewrite the durable set',
      );
      expect((await store.load(_session.deviceId)).length, 1);
    });
  });

  // =========================================================================
  // B — THE REPOSITORY MUST FAIL CLOSED AND BE REVERSIBLE
  // =========================================================================
  group(
    'B. RealOutboxRepository — fail closed, no dispatch, no memory leak',
    () {
      test('B1 enqueue throws, dispatches NOTHING, and does not retain the '
          'operation in memory or on disk', () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = FailingPrefs(await SharedPreferences.getInstance());
        final store = SharedPrefsOutboxStore(prefs);
        final transport = _RecordingTransport();
        final repo = RealOutboxRepository(transport, _session, store: store);

        // A previously queued, healthy order.
        await repo.enqueue(_entry());
        expect(_storedOutboxEntries(prefs).length, 1);

        prefs.failWrites = true;
        final second = _entry(localOperationId: 'op-2', orderId: 'order-2');
        await expectLater(
          repo.enqueue(second),
          throwsA(isA<OrderSubmissionException>()),
          reason:
              'the submit handler catches OrderSubmissionException '
              '(cart_panel.dart:881) and keeps the cart — that is the honest '
              'landing zone for a failed durable write',
        );

        expect(
          transport.calls,
          isEmpty,
          reason:
              'nothing may be dispatched for an order that was never stored',
        );

        prefs.failWrites = false;
        final inMemory = await repo.recentEntries();
        expect(
          inMemory.map((e) => e.localOperationId),
          isNot(contains('op-2')),
          reason:
              'the refused operation must not be retained in memory — otherwise '
              'a later successful write silently resurrects it as "queued"',
        );
        expect(
          _storedOutboxEntries(prefs).length,
          1,
          reason:
              'the first order is untouched; the refused one is not on disk',
        );
      });

      test('B2 the refused operation is absent after a restart', () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = FailingPrefs(await SharedPreferences.getInstance());
        final transport = _RecordingTransport();
        final repoA = RealOutboxRepository(
          transport,
          _session,
          store: SharedPrefsOutboxStore(prefs),
        );
        await repoA.enqueue(_entry());

        prefs.failWrites = true;
        await repoA
            .enqueue(_entry(localOperationId: 'op-2', orderId: 'order-2'))
            .catchError((Object _) => _entry());
        prefs.failWrites = false;

        // FULL RESTART over the same durable prefs.
        final repoB = RealOutboxRepository(
          _RecordingTransport(),
          _session,
          store: SharedPrefsOutboxStore(prefs),
        );
        final loaded = await repoB.recentEntries();
        expect(loaded.map((e) => e.localOperationId), <String>['op-1']);
      });
    },
  );

  // =========================================================================
  // C — AN UNREADABLE OUTBOX RECORD IS NOT A RECORD WE MAY DESTROY
  // =========================================================================
  group('C. durable outbox store — preservation of what it cannot read', () {
    /// A stored entry whose `sync_state` this build does not understand. It
    /// raises FormatException, so `load` drops it — and the next write erases
    /// it, because the outbox has no quarantine.
    Map<String, Object?> unreadableEntry() {
      final raw = _entry(localOperationId: 'op-x', orderId: 'order-x').toJson();
      raw['sync_state'] = 'a_state_from_a_newer_build';
      return raw;
    }

    Future<SharedPreferences> seeded(Map<String, Object?> extra) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _outboxKey: jsonEncode(<String, Object?>{
          'version': SharedPrefsOutboxStore.schemaVersion,
          'entries': <Object?>[_entry().toJson(), extra],
        }),
      });
      return SharedPreferences.getInstance();
    }

    test(
      'C1 an entry this build cannot decode SURVIVES the next write',
      () async {
        final prefs = await seeded(unreadableEntry());
        final store = SharedPrefsOutboxStore(prefs);

        final loaded = await store.load(_session.deviceId);
        expect(loaded.length, 1, reason: 'only the readable entry decodes');

        await store.persist(_session.deviceId, loaded);

        final stored = _storedOutboxEntries(prefs);
        expect(
          stored.length,
          2,
          reason:
              'the undecodable entry must be re-emitted VERBATIM — it may be a '
              'real queued order written by a newer build, and erasing it '
              'destroys a customer order that was never sent',
        );
        expect(
          stored.whereType<Map<Object?, Object?>>().any(
            (e) => e['local_operation_id'] == 'op-x',
          ),
          isTrue,
        );
      },
    );

    test('C2 a WRONGLY-TYPED field drops only its own entry, never the whole '
        'envelope', () async {
      // `attempt_count` as a String raises TypeError, not FormatException. The
      // per-entry guard only catches FormatException, so this escapes to the
      // envelope-level catch and empties the ENTIRE queue.
      final broken = _entry(
        localOperationId: 'op-y',
        orderId: 'order-y',
      ).toJson();
      broken['attempt_count'] = 'not-a-number';
      final prefs = await seeded(broken);
      final store = SharedPrefsOutboxStore(prefs);

      final loaded = await store.load(_session.deviceId);
      expect(
        loaded.map((e) => e.localOperationId),
        <String>['op-1'],
        reason:
            'one badly TYPED entry must not take every healthy queued order '
            'down with it',
      );
    });

    test('C3 a whole unreadable ENVELOPE is preserved, not silently '
        'overwritten', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _outboxKey: '{not valid json at all',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPrefsOutboxStore(prefs);

      expect(await store.load(_session.deviceId), isEmpty);
      await store.persist(_session.deviceId, <OutboxEntry>[_entry()]);

      final preserved = prefs
          .getKeys()
          .where((k) => k.startsWith(_outboxKey) && k != _outboxKey)
          .toList();
      expect(
        preserved,
        isNotEmpty,
        reason:
            'the original bytes are the only evidence of what was queued; '
            'they must be kept somewhere recoverable before being replaced',
      );
      expect(prefs.getString(preserved.single), '{not valid json at all');
    });

    test('C4 a REPAIRED entry replaces its quarantined shadow instead of '
        'doubling it', () async {
      final prefs = await seeded(unreadableEntry());
      final store = SharedPrefsOutboxStore(prefs);

      // The same operation identity, now readable.
      await store.persist(_session.deviceId, <OutboxEntry>[
        _entry(),
        _entry(localOperationId: 'op-x', orderId: 'order-x'),
      ]);

      final stored = _storedOutboxEntries(prefs)
          .whereType<Map<Object?, Object?>>()
          .where((e) => e['local_operation_id'] == 'op-x')
          .toList();
      expect(
        stored.length,
        1,
        reason: 'one logical operation must never end up stored twice',
      );
      expect(stored.single['sync_state'], OutboxSyncState.pending.wire);
    });
  });

  // =========================================================================
  // D — THE DRAFT-RECOVERY STORE MUST NOT CLAIM A WRITE THAT DID NOT STICK
  // =========================================================================
  group('D. draft-recovery store — write truthfulness', () {
    test('D1 persist THROWS when setString refuses', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = FailingPrefs(await SharedPreferences.getInstance());
      final store = SharedPrefsDraftRecoveryStore(prefs);

      prefs.failWrites = true;
      await expectLater(
        store.persist(<String, PosDraftRecovery>{'e1': _recovery('e1')}),
        throwsA(isA<Exception>()),
        reason:
            'this store is what the pre-dispatch correction gate awaits; if it '
            'completes normally on a refused write the gate opens and the '
            'order is sent with its correction link held only in memory',
      );
    });

    test(
      'D2 a whole unreadable ENVELOPE is preserved, not overwritten',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          _recoveryKey: '{half a record',
        });
        final prefs = await SharedPreferences.getInstance();
        final store = SharedPrefsDraftRecoveryStore(prefs);

        expect(await store.load(), isEmpty);
        await store.persist(<String, PosDraftRecovery>{'e1': _recovery('e1')});

        final preserved = prefs
            .getKeys()
            .where((k) => k.startsWith(_recoveryKey) && k != _recoveryKey)
            .toList();
        expect(preserved, isNotEmpty);
        expect(prefs.getString(preserved.single), '{half a record');
      },
    );

    test('D3 an unreadable RECORD still survives the next write (002B '
        'regression)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _recoveryKey: jsonEncode(<String, Object?>{
          'version': SharedPrefsDraftRecoveryStore.schemaVersion,
          'recoveries': <String, Object?>{
            'broken': <String, Object?>{'outbox_entry_id': 'broken'},
          },
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPrefsDraftRecoveryStore(prefs);

      await store.persist(<String, PosDraftRecovery>{'e1': _recovery('e1')});
      expect(
        _storedRecoveries(prefs).keys,
        containsAll(<String>['broken', 'e1']),
      );
    });
  });

  // =========================================================================
  // E — THE CONTROLLER MUST REPORT THE TRUTH TO ITS CALLERS
  // =========================================================================
  group('E. draft-recovery controller — truthful results', () {
    ProviderContainer container(SharedPreferences prefs) {
      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: true),
          ),
          posDraftRecoveryStoreProvider.overrideWithValue(
            SharedPrefsDraftRecoveryStore(prefs),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test(
      'E1 linkCorrectedSubmit returns FALSE when the write is refused',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = FailingPrefs(await SharedPreferences.getInstance());
        final c = container(prefs);
        final recovery = c.read(posDraftRecoveryProvider.notifier);

        recovery.capture(_recovery('source-1'));
        await Future<void>.delayed(Duration.zero);

        prefs.failWrites = true;
        final linked = await recovery.linkCorrectedSubmit(
          sourceOutboxEntryId: 'source-1',
          correctedOutboxEntryId: 'corrected-1',
          binding: const PosRecoveryBinding(),
          correctedDraft: _draft(),
          orderType: OrderType.takeaway,
        );

        expect(
          linked,
          isFalse,
          reason:
              'the pre-dispatch gate aborts the submit on false; returning true '
              'here sends an order whose correction link was never stored',
        );
        expect(
          c.read(posDraftRecoveryProvider)['source-1']!.correctionOutboxEntryId,
          isNull,
          reason: 'a refused write must not publish the in-memory replacement',
        );
      },
    );

    test('E2 discardOwned returns FALSE when the write is refused and the '
        'record REMAINS recoverable', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = FailingPrefs(await SharedPreferences.getInstance());
      final c = container(prefs);
      final recovery = c.read(posDraftRecoveryProvider.notifier);

      recovery.capture(_recovery('e1'));
      await Future<void>.delayed(Duration.zero);

      prefs.failWrites = true;
      final discarded = await recovery.discardOwned(
        'e1',
        const PosRecoveryBinding(),
      );

      expect(discarded, isFalse);
      expect(c.read(posDraftRecoveryProvider).containsKey('e1'), isTrue);
    });
  });

  // =========================================================================
  // G — THE OPERATOR SURFACE IS WIRED TO THE REAL STORES
  // =========================================================================
  group('G. local-storage health provider', () {
    ProviderContainer container(
      SharedPreferences prefs, {
      SyncSession? session = _session,
    }) {
      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posSyncSessionProvider.overrideWithValue(session),
          durableOutboxStoreProvider.overrideWithValue(
            SharedPrefsOutboxStore(prefs),
          ),
          posDraftRecoveryStoreProvider.overrideWithValue(
            SharedPrefsDraftRecoveryStore(prefs),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('G1 a healthy till reports healthy', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final health = container(prefs).read(posLocalStorageHealthProvider);
      expect(health.isHealthy, isTrue);
      expect(health.unreadableRecords, 0);
    });

    test('G2 a REAL refused write is reported', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = FailingPrefs(await SharedPreferences.getInstance());
      final c = container(prefs);
      final store = c.read(durableOutboxStoreProvider)!;

      prefs.failWrites = true;
      await store
          .persist(_session.deviceId, <OutboxEntry>[_entry()])
          .catchError((Object _) {});

      final health = c.read(posLocalStorageHealthProvider);
      expect(health.writeRefused, isTrue);
      expect(health.isHealthy, isFalse);
    });

    test(
      'G3 REAL undecodable records are counted across both stores',
      () async {
        final brokenEntry = _entry(localOperationId: 'op-x').toJson();
        brokenEntry['sync_state'] = 'from_a_newer_build';
        SharedPreferences.setMockInitialValues(<String, Object>{
          _outboxKey: jsonEncode(<String, Object?>{
            'version': SharedPrefsOutboxStore.schemaVersion,
            'entries': <Object?>[_entry().toJson(), brokenEntry],
          }),
          _recoveryKey: jsonEncode(<String, Object?>{
            'version': SharedPrefsDraftRecoveryStore.schemaVersion,
            'recoveries': <String, Object?>{
              'broken': <String, Object?>{'outbox_entry_id': 'broken'},
            },
          }),
        });
        final prefs = await SharedPreferences.getInstance();

        final health = container(prefs).read(posLocalStorageHealthProvider);
        expect(
          health.unreadableRecords,
          2,
          reason: 'one undecodable outbox entry plus one undecodable recovery',
        );
        expect(health.isHealthy, isFalse);
      },
    );

    test(
      'G4 with no session the per-device outbox is not guessed at',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          _outboxKey: '{corrupt',
        });
        final prefs = await SharedPreferences.getInstance();
        final health = container(
          prefs,
          session: null,
        ).read(posLocalStorageHealthProvider);
        expect(
          health.unreadableRecords,
          0,
          reason:
              'without a session there is no scope key, and counting another '
              "device's records would be a guess",
        );
      },
    );
  });

  // =========================================================================
  // F — THE PRODUCTION PATH: A REFUSED DURABLE WRITE MEANS NO DISPATCH
  // =========================================================================
  group('F. production submit path', () {
    const ctx = DeviceContext(
      organizationId: 'org-1',
      restaurantId: 'rest-1',
      branchId: 'branch-A',
      deviceId: 'device-abc',
      deviceType: 'pos',
      deviceSessionId: 'ds-A',
    );
    const burger = DemoMenuItem(
      id: 'burger-9',
      name: 'Burger',
      priceMinor: 4500,
      categoryId: 'mains',
      categoryName: 'Mains',
    );

    /// Answers PIN sign-in, and records every `sync_push` so "no order was
    /// dispatched" is measured at the real network boundary.
    var pinSessions = 0;
    final orderOps = <Map<String, dynamic>>[];

    testWidgets('F1 when the durable outbox refuses the write, the order is '
        'NOT sent and the cart is kept', (tester) async {
      pinSessions = 0;
      orderOps.clear();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = FailingPrefs(await SharedPreferences.getInstance());

      final transport = _ScriptedTransport(
        onPin: () => 'pin-session-${++pinSessions}',
        onOrderSubmit: orderOps.add,
      );

      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posAuthTransportProvider.overrideWithValue(transport),
          posRealSessionConfigProvider.overrideWithValue(null),
          durableOutboxStoreProvider.overrideWithValue(
            SharedPrefsOutboxStore(prefs),
          ),
          posDraftRecoveryStoreProvider.overrideWithValue(
            SharedPrefsDraftRecoveryStore(prefs),
          ),
          orderSnapshotRepositoryProvider.overrideWithValue(
            _EmptySnapshotRepo(),
          ),
          posRecentOrdersStoreProvider.overrideWithValue(
            SharedPrefsRecentOrdersStore(prefs),
          ),
          posSyncClockProvider.overrideWithValue(
            () => DateTime.utc(2026, 8, 6, 9),
          ),
          verifiedKdsReadinessOverride(),
        ],
      );
      addTearDown(c.dispose);

      Future<void> settle() async {
        for (var i = 0; i < 12; i++) {
          await Future<void>.microtask(() {});
        }
      }

      c.read(posDeviceContextProvider.notifier).set(ctx);
      await settle();
      expect(
        await c
            .read(posSessionControllerProvider.notifier)
            .signInWithPin(
              device: ctx,
              deviceId: ctx.deviceId!,
              deviceSessionId: ctx.deviceSessionId!,
              employeeProfileId: 'emp-A',
              pin: '1234',
            ),
        isNull,
      );
      await settle();

      final cart = c.read(cartControllerProvider.notifier);
      cart.addItem(burger);
      c
          .read(orderSetupControllerProvider.notifier)
          .setOrderType(OrderType.takeaway);
      await settle();

      late WidgetRef ref;
      late BuildContext context;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Consumer(
              builder: (ctx2, r, _) {
                ref = r;
                context = ctx2;
                return const Scaffold(body: SizedBox.shrink());
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // THE FAILURE: localStorage refuses from here on.
      prefs.failWrites = true;

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await submitOrderFromCart(
        ref: ref,
        context: context,
        cart: c.read(cartControllerProvider),
        setup: c.read(orderSetupControllerProvider),
        cartController: cart,
        setupController: c.read(orderSetupControllerProvider.notifier),
        l10n: l10n,
        taxTotalMinor: 0,
        taxRateBp: 0,
      );
      await tester.pump();
      await settle();
      await tester.pump();

      expect(
        orderOps,
        isEmpty,
        reason:
            'THE RELEASE BLOCKER: the order reached the server while its only '
            'local record failed to persist. On restart the till has no trace '
            'of an order the kitchen is already cooking.',
      );
      expect(
        c.read(cartControllerProvider).lines,
        isNotEmpty,
        reason: 'the cashier keeps the cart and can retry',
      );
    });
  });
}

class _ScriptedTransport implements SyncRpcTransport {
  _ScriptedTransport({required this.onPin, required this.onOrderSubmit});
  final String Function() onPin;
  final void Function(Map<String, dynamic>) onOrderSubmit;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'start_pin_session') return onPin();
    if (function == 'sync_push') {
      final op = ((params['p_operations'] as List).first as Map)
          .cast<String, dynamic>();
      if (op['operation_type'] == 'order.submit') onOrderSubmit(op);
      return <String, dynamic>{
        'ok': true,
        'results': <dynamic>[
          <String, dynamic>{
            'local_operation_id': op['local_operation_id'],
            'operation_type': op['operation_type'],
            'status': 'applied',
            'ok': true,
          },
        ],
      };
    }
    return null;
  }
}

class _EmptySnapshotRepo implements OrderSnapshotRepository {
  @override
  Future<PosSnapshotPage> fetchWindow({
    PosSyncCursor? before,
    int limit = 50,
    int windowDays = 2,
  }) async => PosSnapshotPage.empty;
  @override
  Future<PosSnapshotPage> fetchChanges({
    PosSyncCursor? cursor,
    int limit = 50,
    int windowDays = 2,
  }) async => PosSnapshotPage.empty;
  @override
  Future<PosSnapshotPage> fetchOrders(List<String> orderIds) async =>
      PosSnapshotPage.empty;
}
