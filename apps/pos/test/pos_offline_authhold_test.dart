// POS-OFFLINE-OPERATIONS-002 — C8 AUTH_HOLD.
//
// Covers OFFLINE-ARCH-SPEC tests 23, 24, 25, 32:
//   23 — a batch 42501 moves the entry to the DURABLE authHold state
//        (identity + payload verbatim, restart-proof) and closes every retry
//        surface: auto-sweep, retry-all, retry-one, direct push, dismissal;
//   24 — after re-auth, releaseAuthHold() returns the entries to pending and
//        the normal sweep resubmits the SAME (deviceId, localOperationId)
//        identity (the server replays idempotently);
//   25 — per-operation SERVER verdicts stay DEFINITIVE — the business
//        rejection path is untouched by AUTH_HOLD;
//   32 — the indicator can never claim "all synced" while a hold exists: the
//        conservative aggregation surfaces its own labelled state.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show
        SyncRpcTransport,
        SyncSession,
        SyncTransportErrorKind,
        SyncTransportException,
        classifyPostgrestCode;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/durable_outbox_store.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/state/local_storage_health_provider.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/widgets/outbox_status_indicator.dart';
import 'package:restoflow_pos/src/widgets/outbox_status_summary.dart';

const SyncSession _session = SyncSession(
  pinSessionId: 'pin-1',
  deviceId: 'dev-1',
);

// Pass B fixture honesty: the real transport now mints kind `auth` for a
// 42501 ONLY when its message is one of the session-class refusals, so the
// fake carries the same pairing a genuine batch failure would.
// (OLD: kind auth + bare code '42501', no message.)
const _authFailure = SyncTransportException(
  SyncTransportErrorKind.auth,
  code: '42501',
  message: 'sync_push: PIN session is not valid (inactive/ended/expired)',
);

/// Pass B: a batch-level 42501 whose KIND is derived by the REAL classifier —
/// exactly what `SupabaseSyncRpcTransport` throws for that server message —
/// so these tests exercise the true classification -> outbox chain, not a
/// hand-picked kind.
SyncTransportException _batch42501(String message) => SyncTransportException(
  classifyPostgrestCode('42501', message: message),
  code: '42501',
  message: message,
);

/// Scripted sync_push transport (the 024/025 idiom): throws or answers each
/// step and records every pushed operation's identity.
class _ScriptedTransport implements SyncRpcTransport {
  _ScriptedTransport(this._steps);
  final List<Object> _steps;
  int pushes = 0;
  final List<String> pushedLocalOperationIds = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function != 'sync_push') return <String, dynamic>{'ok': false};
    final op = (params['p_operations'] as List).first as Map;
    pushedLocalOperationIds.add(op['local_operation_id'] as String);
    final step = _steps[pushes < _steps.length ? pushes : _steps.length - 1];
    pushes++;
    if (step is SyncTransportException) throw step;
    return <String, dynamic>{
      'ok': true,
      'results': <dynamic>[
        <String, dynamic>{
          'local_operation_id': op['local_operation_id'],
          'operation_type': 'order.submit',
          ...(step as Map).cast<String, Object?>(),
        },
      ],
      'server_ts': '2026-08-06T09:00:01Z',
    };
  }
}

class _MemoryStore implements DurableOutboxStore {
  final Map<String, List<Map<String, Object?>>> saved = {};
  @override
  Future<List<OutboxEntry>> load(String scopeKey) async => [
    for (final j in saved[scopeKey] ?? const <Map<String, Object?>>[])
      OutboxEntry.fromJson(j),
  ];
  @override
  Future<void> persist(String scopeKey, List<OutboxEntry> entries) async {
    saved[scopeKey] = [for (final e in entries) e.toJson()];
  }
}

OutboxEntry _seed({String id = 'e1', String op = 'op-1'}) => OutboxEntry(
  id: id,
  deviceId: 'dev-1',
  localOperationId: op,
  operationType: 'order.submit',
  targetEntity: 'order',
  targetId: 'order-$op',
  payloadJson: '{"order_id":"order-$op","subtotal_minor":4200}',
  summary: const OrderSummary(
    orderNumber: '#3F7A2C',
    orderType: OrderType.takeaway,
    tableLabel: null,
    itemCount: 1,
    subtotalMinor: 4200,
    currencyCode: 'ILS',
  ),
  syncState: OutboxSyncState.pending,
  clientCreatedAt: DateTime.utc(2026, 8, 6),
);

OutboxEntry _held({String id = 'held-1', String op = 'held-op-1'}) =>
    _seed(id: id, op: op).copyWith(
      syncState: OutboxSyncState.authHold,
      lastErrorCode: '42501',
      lastErrorKind: 'auth',
    );

({
  OutboxController controller,
  _ScriptedTransport transport,
  _MemoryStore store,
})
_wire(List<Object> steps, {List<OutboxEntry> preload = const []}) {
  final transport = _ScriptedTransport(steps);
  final store = _MemoryStore();
  if (preload.isNotEmpty) {
    store.saved['dev-1'] = [for (final e in preload) e.toJson()];
  }
  final repo = RealOutboxRepository(transport, _session, store: store);
  final container = ProviderContainer(
    overrides: [outboxRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return (
    controller: container.read(outboxControllerProvider.notifier),
    transport: transport,
    store: store,
  );
}

void main() {
  group('spec test 23 — 42501 => durable AUTH_HOLD, closed to every retry '
      'surface', () {
    test(
      'the batch auth failure holds the entry verbatim and durably',
      () async {
        final transport = _ScriptedTransport(const [_authFailure]);
        final store = _MemoryStore();
        final original = _seed();
        final repo = RealOutboxRepository(transport, _session, store: store);
        await repo.enqueue(original);
        final pushed = await repo.push('e1');

        expect(pushed.syncState, OutboxSyncState.authHold);
        expect(pushed.lastErrorCode, '42501');
        expect(pushed.lastErrorKind, 'auth');
        // Epistemically PENDING — never a definitive order verdict.
        expect(pushed.outcome, PosOrderOutcome.pending);
        expect(pushed.hasDefinitiveVerdict, isFalse);
        expect(pushed.isDefinitiveNoServerOrder, isFalse);
        expect(pushed.isDismissibleResolvedFailure, isFalse);
        // Not pending (no sweep), not failed (no Retry), not terminal.
        expect(pushed.syncState.isPending, isFalse);
        expect(pushed.syncState.isFailed, isFalse);
        expect(pushed.syncState.isTerminal, isFalse);

        // DURABLE + VERBATIM: a fresh repository over the same store reloads
        // the hold with the identical identity and payload bytes.
        final reloaded = RealOutboxRepository(
          _ScriptedTransport(const []),
          _session,
          store: store,
        );
        final held = (await reloaded.recentEntries()).single;
        expect(held.syncState, OutboxSyncState.authHold);
        expect(held.localOperationId, original.localOperationId);
        expect(held.payloadJson, original.payloadJson);
      },
    );

    test('sweep, retry-all, retry-one, direct push and dismissal all leave '
        'the hold untouched', () async {
      final w = _wire(const [_authFailure], preload: [_held()]);
      // Materializing the controller runs recovery + sweep over the preloaded
      // hold — which must spend NO transport attempt.
      await pumpEventQueue();
      expect(w.transport.pushes, 0, reason: 'auto-sweep must skip authHold');

      await w.controller.pushQueued();
      await w.controller.retryAllFailed();
      await w.controller.retryEntry('held-1');
      await w.controller.pushEntry('held-1');
      expect(w.transport.pushes, 0);
      expect(
        w.controller.entryById('held-1')!.syncState,
        OutboxSyncState.authHold,
      );

      // NOT clearable: dismissal is scoped to provably-refused work.
      expect(await w.controller.dismissResolvedFailures(), 0);
      expect(w.controller.entryById('held-1'), isNotNull);
      expect(w.controller.authHoldCount, 1);
    });
  });

  group('Pass B — 42501 is AUTH_HOLD only for the session-class messages', () {
    // The review-mandated scenario matrix, at the OUTBOX level, driving the
    // REAL classifier (`_batch42501` derives the kind from the message):
    // holding is correct ONLY where a fresh ONLINE sign-in can change the
    // answer. Every other batch 42501 must land in the visible, retryable
    // failed bucket — a hold would be unreleasable (the re-auth replays the
    // identical refusal, or — for a PostgREST function ACL denial — cannot
    // even run, because PIN sign-in dies on the same dead transport).
    //
    // Per-op verdicts are deliberately NOT duplicated here: revoked employee /
    // insufficient capability / wrong tenant / business validation already
    // arrive as structured per-op refusals and are pinned as DEFINITIVE
    // rejections by spec test 25 below and definitive_rejection_gating_024.

    test('(i) a session-class batch 42501 still holds (existing behavior '
        'retained)', () async {
      final transport = _ScriptedTransport([
        _batch42501(
          'sync_push: PIN session is not valid (inactive/ended/expired)',
        ),
      ]);
      final repo = RealOutboxRepository(
        transport,
        _session,
        store: _MemoryStore(),
      );
      await repo.enqueue(_seed());
      final pushed = await repo.push('e1');
      expect(pushed.syncState, OutboxSyncState.authHold);
      expect(pushed.lastErrorKind, 'auth');
      expect(pushed.outcome, PosOrderOutcome.pending);
    });

    test('(ii) the batch-shape 42501 is REJECTED, not held — and stays '
        'visible + retryable', () async {
      final transport = _ScriptedTransport([
        _batch42501('sync_push: p_operations must be a JSON array'),
        <String, Object?>{'ok': true, 'status': 'applied'},
      ]);
      final store = _MemoryStore();
      final repo = RealOutboxRepository(transport, _session, store: store);
      final container = ProviderContainer(
        overrides: [outboxRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      // Let the controller's startup recovery settle over the EMPTY store
      // BEFORE enqueueing, so its sweep cannot race this test's explicit push
      // for the scripted steps.
      final controller = container.read(outboxControllerProvider.notifier);
      await pumpEventQueue();
      await repo.enqueue(_seed());
      await controller.pushEntry('e1');
      await pumpEventQueue();

      final entry = controller.entryById('e1')!;
      expect(entry.syncState, OutboxSyncState.rejected, reason: 'NOT held');
      expect(entry.syncState, isNot(OutboxSyncState.authHold));
      // Visible in the failed bucket, with NO definitive claim about the order.
      expect(entry.syncState.isFailed, isTrue);
      expect(entry.outcome, PosOrderOutcome.deliveryUnconfirmed);
      expect(entry.hasDefinitiveVerdict, isFalse);
      // And genuinely retryable: a manual retry spends a real attempt.
      await controller.retryEntry('e1');
      await pumpEventQueue();
      expect(transport.pushes, 2);
      expect(controller.entryById('e1')!.syncState, OutboxSyncState.applied);
    });

    test(
      "(iii) PostgREST 'permission denied for function sync_push' is "
      'REJECTED, not held (the one hold no sign-in could ever release)',
      () async {
        final transport = _ScriptedTransport([
          _batch42501('permission denied for function sync_push'),
        ]);
        final repo = RealOutboxRepository(
          transport,
          _session,
          store: _MemoryStore(),
        );
        await repo.enqueue(_seed());
        final pushed = await repo.push('e1');
        expect(pushed.syncState, OutboxSyncState.rejected);
        expect(pushed.syncState, isNot(OutboxSyncState.authHold));
        expect(pushed.outcome, PosOrderOutcome.deliveryUnconfirmed);
        expect(pushed.hasDefinitiveVerdict, isFalse);
      },
    );

    test('(iv) a latent RLS 42501 is REJECTED, not held', () async {
      final transport = _ScriptedTransport([
        _batch42501(
          'new row violates row-level security policy for table "orders"',
        ),
      ]);
      final repo = RealOutboxRepository(
        transport,
        _session,
        store: _MemoryStore(),
      );
      await repo.enqueue(_seed());
      final pushed = await repo.push('e1');
      expect(pushed.syncState, OutboxSyncState.rejected);
      expect(pushed.syncState, isNot(OutboxSyncState.authHold));
      expect(pushed.outcome, PosOrderOutcome.deliveryUnconfirmed);
      expect(pushed.hasDefinitiveVerdict, isFalse);
    });
  });

  group('spec test 24 — release resubmits the SAME identity', () {
    test('releaseAuthHold() -> pending -> normal sweep -> applied, with the '
        'ORIGINAL (deviceId, localOperationId)', () async {
      final w = _wire(
        [
          <String, Object?>{'ok': true, 'status': 'applied'},
        ],
        preload: [_held()],
      );
      await pumpEventQueue();
      expect(w.transport.pushes, 0);

      final released = await w.controller.releaseAuthHold();
      await pumpEventQueue();

      expect(released, 1);
      expect(w.transport.pushes, 1, reason: 'the release sweep resubmits');
      expect(
        w.transport.pushedLocalOperationIds.single,
        'held-op-1',
        reason: 'SAME identity — the server replay ledger reconciles it',
      );
      final entry = w.controller.entryById('held-1')!;
      expect(entry.syncState, OutboxSyncState.applied);
      expect(entry.outcome, PosOrderOutcome.accepted);
      // Durably released too (restart-proof).
      final reloaded = RealOutboxRepository(
        _ScriptedTransport(const []),
        _session,
        store: w.store,
      );
      expect(
        (await reloaded.recentEntries()).single.syncState,
        OutboxSyncState.applied,
      );
    });

    test('release with nothing held is an honest zero', () async {
      final w = _wire(const []);
      expect(await w.controller.releaseAuthHold(), 0);
      expect(w.transport.pushes, 0);
    });
  });

  group('spec test 25 — per-op SERVER verdicts stay definitive', () {
    test('a structured business refusal is REJECTED (not held) and never '
        're-pushed', () async {
      for (final code in const [
        'item_unavailable',
        'dispatch_mode_not_allowed',
      ]) {
        final transport = _ScriptedTransport([
          <String, Object?>{'ok': false, 'status': 'rejected', 'error': code},
        ]);
        final repo = RealOutboxRepository(
          transport,
          _session,
          store: _MemoryStore(),
        );
        final container = ProviderContainer(
          overrides: [outboxRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);
        await repo.enqueue(_seed());
        final controller = container.read(outboxControllerProvider.notifier);
        await controller.pushEntry('e1');
        await pumpEventQueue();

        final entry = controller.entryById('e1')!;
        expect(entry.syncState, OutboxSyncState.rejected, reason: code);
        expect(entry.lastErrorKind, kServerVerdictErrorKind);
        expect(entry.outcome, PosOrderOutcome.rejected);
        expect(entry.hasDefinitiveVerdict, isTrue);
        expect(entry.isDefinitiveNoServerOrder, isTrue);

        final afterVerdict = transport.pushes;
        await controller.retryAllFailed();
        await controller.retryEntry('e1');
        await controller.pushEntry('e1');
        expect(transport.pushes, afterVerdict, reason: code);
      }
    });

    test("'auth' is no longer in the definitive-refusal kinds; the server "
        'verdict kind still is', () {
      expect(kDefinitiveRefusalKinds.contains('auth'), isFalse);
      expect(kDefinitiveRefusalKinds.contains(kServerVerdictErrorKind), isTrue);
    });
  });

  group('spec test 32 — never "all synced" while a hold exists', () {
    PosOutboxStatusSummary summarize(List<OutboxEntry> entries) =>
        PosOutboxStatusSummary.from(
          entries: entries,
          storage: const PosLocalStorageHealth(),
        );

    test('the conservative aggregation: authHold is its own state, below '
        'failed and above resolved — and blocks isAllApplied', () {
      final held = summarize([
        _held(),
        _seed(id: 'a', op: 'op-a').copyWith(syncState: OutboxSyncState.applied),
      ]);
      expect(held.authHold, 1);
      expect(held.isAllApplied, isFalse, reason: 'non-applied is not synced');
      expect(held.icon, Icons.lock_clock);

      // failed outranks authHold (safest-first: a failure may need action NOW).
      final withFailed = summarize([
        _held(),
        _seed(id: 'f', op: 'op-f').copyWith(
          syncState: OutboxSyncState.rejected,
          lastErrorCode: 'transport',
        ),
      ]);
      expect(withFailed.icon, Icons.error_outline);

      // authHold outranks the resolved-failures housekeeping state.
      final withResolved = summarize([
        _held(),
        _seed(id: 'r', op: 'op-r').copyWith(
          syncState: OutboxSyncState.rejected,
          lastErrorCode: 'rejected',
          lastErrorKind: kServerVerdictErrorKind,
        ),
      ]);
      expect(withResolved.icon, Icons.lock_clock);
    });

    testWidgets('the indicator shows the labelled hold, never all-synced; '
        'the details sheet carries the row + explanation and offers NO '
        'retry', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            outboxControllerProvider.overrideWith(
              () => _SeededOutbox([
                _held(),
                _seed(
                  id: 'a',
                  op: 'op-a',
                ).copyWith(syncState: OutboxSyncState.applied),
              ]),
            ),
            posLocalStorageHealthProvider.overrideWithValue(
              const PosLocalStorageHealth(),
            ),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topRight,
                child: OutboxStatusIndicator(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(l10n.posOutboxAuthHold(1)), findsOneWidget);
      expect(find.text(l10n.posOutboxSynced), findsNothing);

      await tester.tap(find.byKey(const Key('outbox-status-indicator')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sync-count-auth-hold')), findsOneWidget);
      expect(find.text(l10n.posOfflineReauthNeeded), findsOneWidget);
      expect(find.text(l10n.posOutboxAuthHoldTooltip), findsOneWidget);
      // No retry-all (nothing failed) and no clear (nothing provably refused):
      // the release affordance is signing in, which lives on the PIN gate.
      expect(find.byKey(const Key('outbox-retry-all')), findsNothing);
      expect(find.byKey(const Key('outbox-clear-resolved')), findsNothing);
    });
  });
}

class _SeededOutbox extends OutboxController {
  _SeededOutbox(this._seedEntries);
  final List<OutboxEntry> _seedEntries;

  @override
  List<OutboxEntry> build() => _seedEntries;
}
