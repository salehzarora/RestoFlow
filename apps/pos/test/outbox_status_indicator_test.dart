import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/state/local_storage_health_provider.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/widgets/outbox_status_indicator.dart';

/// RF-114: the POS app-bar outbox indicator honestly shows pending / syncing /
/// failed / all-synced, and its FAILED state retries all failed orders. It never
/// shows "synced" for an order the backend has not confirmed.

/// A seeded controller: returns a fixed outbox and records retry-all, WITHOUT
/// touching the repo/recovery (the widget only reads `state`).
class _SeededOutbox extends OutboxController {
  _SeededOutbox(this._seed);
  final List<OutboxEntry> _seed;
  int retryAllCalls = 0;
  int dismissCalls = 0;

  @override
  List<OutboxEntry> build() => _seed;

  @override
  Future<void> retryAllFailed() async => retryAllCalls++;

  @override
  Future<int> dismissResolvedFailures() async {
    dismissCalls++;
    return _seed.where((e) => e.isDismissibleResolvedFailure).length;
  }
}

OutboxEntry _e(OutboxSyncState state, {String op = 'op', String? errorCode}) =>
    OutboxEntry(
      id: 'outbox-$op',
      deviceId: 'd',
      localOperationId: op,
      operationType: 'order.submit',
      targetEntity: 'order',
      targetId: 'order-$op',
      payloadJson: '{}',
      summary: const OrderSummary(
        orderNumber: 'DEMO-1',
        orderType: OrderType.dineIn,
        tableLabel: 'T1',
        itemCount: 1,
        subtotalMinor: 1000,
        currencyCode: 'ILS',
      ),
      syncState: state,
      clientCreatedAt: DateTime.utc(2026, 6, 29, 9),
      lastErrorCode: errorCode,
    );

Future<_SeededOutbox> _pump(
  WidgetTester tester,
  List<OutboxEntry> seed, {
  PosLocalStorageHealth storage = const PosLocalStorageHealth(),
}) async {
  final controller = _SeededOutbox(seed);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        outboxControllerProvider.overrideWith(() => controller),
        posLocalStorageHealthProvider.overrideWithValue(storage),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          appBar: null,
          body: Align(
            alignment: Alignment.topRight,
            child: OutboxStatusIndicator(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

void main() {
  testWidgets('empty outbox renders nothing (no clutter)', (tester) async {
    await _pump(tester, const []);
    expect(find.byKey(const Key('outbox-status-indicator')), findsNothing);
    expect(find.byKey(const Key('outbox-retry-all')), findsNothing);
    expect(find.byType(SizedBox), findsWidgets); // SizedBox.shrink
  });

  testWidgets('pending shows the queued count', (tester) async {
    await _pump(tester, [
      _e(OutboxSyncState.pending, op: 'a'),
      _e(OutboxSyncState.pending, op: 'b'),
    ]);
    expect(find.text('2 pending sync'), findsOneWidget);
    expect(find.byKey(const Key('outbox-status-indicator')), findsOneWidget);
  });

  testWidgets('syncing shows a spinner + the syncing label', (tester) async {
    await _pump(tester, [_e(OutboxSyncState.inFlight)]);
    expect(find.text('Syncing…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('failed shows a retry action that retries all failed', (
    tester,
  ) async {
    final controller = await _pump(tester, [
      _e(OutboxSyncState.rejected, op: 'a'),
      _e(OutboxSyncState.applied, op: 'b'),
    ]);
    expect(find.text('1 failed — retry'), findsOneWidget);
    expect(find.byKey(const Key('outbox-retry-all')), findsOneWidget);

    await tester.tap(find.byKey(const Key('outbox-retry-all')));
    await tester.pump();
    expect(controller.retryAllCalls, 1);
  });

  testWidgets('all-applied shows the honest all-synced state', (tester) async {
    await _pump(tester, [
      _e(OutboxSyncState.applied, op: 'a'),
      _e(OutboxSyncState.applied, op: 'b'),
    ]);
    expect(find.text('All orders synced'), findsOneWidget);
    // failed/pending take precedence — none here, so no retry affordance.
    expect(find.byKey(const Key('outbox-retry-all')), findsNothing);
  });

  // RF-114 Codex fix: conflict/resolved must NOT fall through to "All synced".
  testWidgets('conflict shows "attention needed", NOT all-synced', (
    tester,
  ) async {
    await _pump(tester, [
      _e(OutboxSyncState.conflict, op: 'a'),
      _e(OutboxSyncState.applied, op: 'b'),
    ]);
    expect(find.text('Sync attention needed'), findsOneWidget);
    expect(find.text('All orders synced'), findsNothing);
    // conflict is not auto-retryable, so no retry-all affordance.
    expect(find.byKey(const Key('outbox-retry-all')), findsNothing);
  });

  testWidgets('resolved is treated conservatively (attention, NOT synced)', (
    tester,
  ) async {
    await _pump(tester, [_e(OutboxSyncState.resolved)]);
    expect(find.text('Sync attention needed'), findsOneWidget);
    expect(find.text('All orders synced'), findsNothing);
  });

  testWidgets('mixed states pick the safest priority (failed > conflict)', (
    tester,
  ) async {
    await _pump(tester, [
      _e(OutboxSyncState.rejected, op: 'a'),
      _e(OutboxSyncState.conflict, op: 'b'),
      _e(OutboxSyncState.applied, op: 'c'),
    ]);
    // failed (retryable) outranks conflict; never "all synced".
    expect(find.text('1 failed — retry'), findsOneWidget);
    expect(find.text('All orders synced'), findsNothing);
    expect(find.byKey(const Key('outbox-retry-all')), findsOneWidget);
  });

  testWidgets(
    'created shows pending; a pending mixed with applied is NOT synced',
    (tester) async {
      await _pump(tester, [
        _e(OutboxSyncState.created, op: 'a'),
        _e(OutboxSyncState.applied, op: 'b'),
      ]);
      expect(find.text('1 pending sync'), findsOneWidget);
      expect(find.text('All orders synced'), findsNothing);
    },
  );

  // MONEY-DURABLE-STORES-003B: local storage that refused a write, or that is
  // holding records this build cannot read, outranks every queue state — and is
  // shown even when the queue is empty.
  group('local-storage health', () {
    testWidgets('a refused durable write is shown INSTEAD of "all synced"', (
      tester,
    ) async {
      await _pump(tester, [
        _e(OutboxSyncState.applied, op: 'a'),
      ], storage: const PosLocalStorageHealth(writeRefused: true));
      expect(find.text('This device could not save an order'), findsOneWidget);
      expect(
        find.text('All orders synced'),
        findsNothing,
        reason:
            'a till that could not store an order must never present the same '
            'confident face as a healthy one',
      );
    });

    testWidgets('unreadable records are reported with their count', (
      tester,
    ) async {
      await _pump(
        tester,
        const [],
        storage: const PosLocalStorageHealth(unreadableRecords: 3),
      );
      expect(find.text('3 local records cannot be read'), findsOneWidget);
      expect(
        find.byKey(const Key('outbox-status-indicator')),
        findsOneWidget,
        reason:
            'an EMPTY queue must still surface storage trouble — otherwise the '
            'only sign is silence',
      );
    });

    testWidgets('storage trouble outranks a failed queue entry', (
      tester,
    ) async {
      await _pump(tester, [
        _e(OutboxSyncState.rejected, op: 'a'),
      ], storage: const PosLocalStorageHealth(writeRefused: true));
      expect(find.text('This device could not save an order'), findsOneWidget);
      expect(find.text('1 failed — retry'), findsNothing);
      expect(
        find.byKey(const Key('outbox-retry-all')),
        findsNothing,
        reason: 'retrying does not fix storage that refuses writes',
      );
    });

    testWidgets('the spoken label explains what the icon cannot', (
      tester,
    ) async {
      await _pump(
        tester,
        const [],
        storage: const PosLocalStorageHealth(unreadableRecords: 1),
      );
      final labels = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((s) => s.properties.label)
          .whereType<String>();
      expect(
        labels,
        contains(
          '1 local records cannot be read. Local storage needs attention — '
          'records are being kept but cannot sync',
        ),
      );
    });

    testWidgets('a healthy till with an empty queue still renders nothing', (
      tester,
    ) async {
      await _pump(tester, const []);
      expect(find.byKey(const Key('outbox-status-indicator')), findsNothing);
    });
  });

  // SINGLE-DEVICE-ADDITION-CLOSE-AND-STALE-FAILURES-007 — the chip separates a
  // failure a Retry can move from one it never could.
  group('resolved (terminal, never-applied) failures', () {
    testWidgets('a permanently-rejected submit is NOT offered as retry — it is '
        'offered as CLEAR, and tapping dismisses it', (tester) async {
      final c = await _pump(tester, [
        for (var i = 1; i <= 6; i++)
          _e(OutboxSyncState.rejected, op: 'old-$i', errorCode: 'rejected'),
      ]);

      expect(
        find.byKey(const Key('outbox-retry-all')),
        findsNothing,
        reason:
            'THE DEFECT: they were shown as "N failed — retry" while retry '
            'deliberately skips them, so the count could never move',
      );
      final clear = find.byKey(const Key('outbox-clear-resolved'));
      expect(clear, findsOneWidget);

      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(c.dismissCalls, 1);
      expect(c.retryAllCalls, 0, reason: 'nothing is re-sent');
    });

    testWidgets('a RETRYABLE failure still shows the retry affordance and is '
        'never offered as clear', (tester) async {
      final c = await _pump(tester, [
        _e(OutboxSyncState.rejected, op: 'transient', errorCode: 'transport'),
      ]);
      expect(find.byKey(const Key('outbox-retry-all')), findsOneWidget);
      expect(find.byKey(const Key('outbox-clear-resolved')), findsNothing);
      await tester.tap(find.byKey(const Key('outbox-retry-all')));
      await tester.pumpAndSettle();
      expect(c.retryAllCalls, 1);
      expect(c.dismissCalls, 0);
    });

    testWidgets('with BOTH kinds present the RETRYABLE state is shown first — '
        'the safest-first order this chip already uses', (tester) async {
      await _pump(tester, [
        _e(OutboxSyncState.rejected, op: 'transient', errorCode: 'transport'),
        _e(OutboxSyncState.rejected, op: 'old-1', errorCode: 'rejected'),
      ]);
      expect(find.byKey(const Key('outbox-retry-all')), findsOneWidget);
      expect(
        find.byKey(const Key('outbox-clear-resolved')),
        findsNothing,
        reason:
            'documented limitation: the clear action becomes reachable once the '
            'retryable failures are dealt with',
      );
    });

    testWidgets('a conflict is neither retried nor cleared', (tester) async {
      await _pump(tester, [_e(OutboxSyncState.conflict, op: 'c1')]);
      expect(find.byKey(const Key('outbox-retry-all')), findsNothing);
      expect(find.byKey(const Key('outbox-clear-resolved')), findsNothing);
      expect(find.byKey(const Key('outbox-status-indicator')), findsOneWidget);
    });
  });
}
