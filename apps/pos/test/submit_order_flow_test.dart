import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';

/// POS-SUBMIT-GUARD-001 harness: an outbox repo whose [enqueue] blocks on [_gate]
/// so a submit can be held "in flight" while the test fires a second Send tap.
/// It counts every enqueue CALL (a duplicate submit would mint a fresh
/// local_operation_id, so this counter — not idempotency — is what proves the
/// guard). Everything else delegates to a plain in-memory demo store.
class _GatedOutboxStore implements OutboxRepository {
  _GatedOutboxStore(this._gate);

  final Future<void> _gate;
  final DemoOutboxStore _inner = DemoOutboxStore(delay: (_) async {});
  int enqueueCount = 0;

  @override
  Future<OutboxEntry> enqueue(OutboxEntry entry) async {
    enqueueCount++;
    await _gate;
    return _inner.enqueue(entry);
  }

  @override
  Future<List<OutboxEntry>> recentEntries() => _inner.recentEntries();

  @override
  Future<OutboxEntry> push(String entryId) => _inner.push(entryId);

  @override
  Future<OutboxEntry> retry(String entryId) => _inner.retry(entryId);
}

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(WidgetTester tester, {OutboxRepository? repo}) async {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (repo != null) outboxRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const PosMenuScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _addItem(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('takeaway Send Order enqueues to the outbox and shows a pending '
      'sync confirmation with an outbox ref', (tester) async {
    final l10n = await _en();
    await _pump(tester, repo: DemoOutboxStore(delay: (_) async {}));

    await _addItem(tester);
    await tester.tap(find.text(l10n.posSendOrder));
    await tester.pumpAndSettle();

    // Confirmation replaces the cart.
    expect(find.text(l10n.posOrderSubmittedTitle), findsOneWidget);
    expect(find.text(l10n.posSendOrder), findsNothing);
    // The order is visibly queued for sync, honestly labelled, with a ref.
    expect(find.byKey(const Key('sync-status-card')), findsOneWidget);
    expect(find.text(l10n.posSyncStatePending), findsOneWidget);
    expect(find.text(l10n.posSyncStoredLocally), findsOneWidget);
    expect(find.textContaining('demo-op-0001'), findsOneWidget);
    expect(find.byKey(const Key('sync-now-button')), findsOneWidget);
  });

  testWidgets('RF-141B: the confirmation uses the shared design-system '
      'components (status pills + notice banner)', (tester) async {
    final l10n = await _en();
    await _pump(tester, repo: DemoOutboxStore(delay: (_) async {}));

    await _addItem(tester);
    await tester.tap(find.text(l10n.posSendOrder));
    await tester.pumpAndSettle();

    // Submitted status, order type, and sync state are all shared pills now;
    // the demo-order notice is the shared notice banner.
    expect(find.byType(RestoflowStatusPill), findsWidgets);
    expect(find.byType(RestoflowNoticeBanner), findsOneWidget);
    // Behaviour preserved: the existing labels still render verbatim.
    expect(find.text(l10n.posOrderStatusSubmitted), findsOneWidget);
    expect(find.text(l10n.posSyncStatePending), findsOneWidget);
  });

  testWidgets('Sync now (demo) moves the order to Synced', (tester) async {
    final l10n = await _en();
    await _pump(tester, repo: DemoOutboxStore(delay: (_) async {}));

    await _addItem(tester);
    await tester.tap(find.text(l10n.posSendOrder));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sync-now-button')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.posSyncStateSynced), findsOneWidget);
    expect(find.byKey(const Key('sync-now-button')), findsNothing);
  });

  testWidgets('a failed enqueue keeps the cart and shows a message', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(tester, repo: DemoOutboxStore(enqueueFails: true));

    await _addItem(tester);
    await tester.tap(find.text(l10n.posSendOrder));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // snackbar entrance

    // No confirmation; the cart is intact and can still be submitted.
    expect(find.text(l10n.posOrderSubmittedTitle), findsNothing);
    expect(find.text(l10n.posSubmitFailed), findsOneWidget);
    expect(find.text(l10n.posSendOrder), findsOneWidget);
    expect(find.text('Classic Burger'), findsNWidgets(2)); // menu card + cart
  });

  testWidgets('a dine-in order carries its table into the queued submission', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(tester, repo: DemoOutboxStore(delay: (_) async {}));

    await _addItem(tester);
    await tester.tap(find.text(l10n.posOrderTypeDineIn));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assign-table-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('T1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.posSendOrder));
    await tester.pumpAndSettle();

    expect(find.text(l10n.posOrderSubmittedTitle), findsOneWidget);
    expect(find.text(l10n.posOrderTypeDineIn), findsOneWidget); // type chip
    expect(find.text('${l10n.posTableLabel} T1'), findsOneWidget); // table chip
    expect(find.byKey(const Key('sync-status-card')), findsOneWidget);
  });

  testWidgets('a failed push surfaces Retry, and retry reaches Synced', (
    tester,
  ) async {
    final l10n = await _en();
    final store = DemoOutboxStore(delay: (_) async {});
    await _pump(tester, repo: store);

    await _addItem(tester);
    await tester.tap(find.text(l10n.posSendOrder));
    await tester.pumpAndSettle();

    // Force the next (demo) push to fail.
    store.nextPushFails = true;
    await tester.tap(find.byKey(const Key('sync-now-button')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.posSyncStateFailed), findsOneWidget);
    expect(find.byKey(const Key('sync-retry-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sync-retry-button')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.posSyncStateSynced), findsOneWidget);
  });

  testWidgets('POS-SUBMIT-GUARD-001: a double-tap on Send while the submit is '
      'in flight enqueues exactly one order', (tester) async {
    final l10n = await _en();
    final gate = Completer<void>();
    final repo = _GatedOutboxStore(gate.future);
    await _pump(tester, repo: repo);

    await _addItem(tester);

    // First tap: the enqueue starts and blocks on the gate, so the submit is
    // held in flight — Send shows a spinner and is disabled.
    await tester.tap(find.text(l10n.posSendOrder));
    await tester.pump(); // apply setState(_submitting = true)
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(repo.enqueueCount, 1);

    // Second (impatient) tap while still in flight must NOT enqueue a second
    // order — the button is disabled and the re-entry guard also short-circuits.
    await tester.tap(find.text(l10n.posSendOrder), warnIfMissed: false);
    await tester.pump();
    expect(repo.enqueueCount, 1);

    // Releasing the gate lets the single order settle into a confirmation.
    gate.complete();
    await tester.pumpAndSettle();
    expect(repo.enqueueCount, 1);
    expect(find.text(l10n.posOrderSubmittedTitle), findsOneWidget);
    expect(find.text(l10n.posSendOrder), findsNothing);
  });

  testWidgets('starting a new order returns to an empty cart after submit', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(tester, repo: DemoOutboxStore(delay: (_) async {}));

    await _addItem(tester);
    await tester.tap(find.text(l10n.posSendOrder));
    await tester.pumpAndSettle();
    expect(find.text(l10n.posOrderSubmittedTitle), findsOneWidget);

    // POS-ORDERS-AND-PAYMENT-001: the unpaid confirmation's reset action is
    // "Pay later" (order stays unpaid, findable in Recent orders).
    await tester.tap(find.text(l10n.posPayLaterAction));
    await tester.pumpAndSettle();

    expect(find.text(l10n.posOrderSubmittedTitle), findsNothing);
    expect(find.text(l10n.posCartEmpty), findsOneWidget);
    expect(find.text(l10n.posSendOrder), findsOneWidget);
  });
}
