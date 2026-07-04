import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
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

  @override
  List<OutboxEntry> build() => _seed;

  @override
  Future<void> retryAllFailed() async => retryAllCalls++;
}

OutboxEntry _e(OutboxSyncState state, {String op = 'op'}) => OutboxEntry(
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
);

Future<_SeededOutbox> _pump(WidgetTester tester, List<OutboxEntry> seed) async {
  final controller = _SeededOutbox(seed);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [outboxControllerProvider.overrideWith(() => controller)],
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
}
