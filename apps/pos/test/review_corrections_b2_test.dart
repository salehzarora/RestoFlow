import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport, SyncSession;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart' show CartLineView;
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';

/// REVIEW B2 — a PERMANENT business rejection replays its stored verdict under
/// the same operation identity forever, so the POS must not offer a "Retry"
/// that reuses that identity. Retry stays for transport-ish failures where no
/// server verdict was recorded (an idempotent re-push is safe and meaningful).
///
/// The failure is driven through the REAL production seam: the outbox store's
/// push records exactly what `_applyPushResult` stores for a per-op
/// `status:'rejected'` + `error:'item_unavailable'` sync_push result (state
/// rejected + error code + safe item-name detail).
class _BusinessRejectStore implements OutboxRepository {
  _BusinessRejectStore();

  final DemoOutboxStore inner = DemoOutboxStore(delay: (_) async {});

  /// When set, the next push records THIS permanent business rejection.
  /// Null = delegate to the inner demo store.
  String? nextBusinessRejectCode;
  String? nextBusinessRejectDetail;

  /// Entries whose SERVER verdict this store holds (overlays the inner copy).
  final Map<String, OutboxEntry> _verdicts = <String, OutboxEntry>{};

  @override
  Future<OutboxEntry> enqueue(OutboxEntry entry) => inner.enqueue(entry);

  @override
  Future<List<OutboxEntry>> recentEntries() async => [
    for (final e in await inner.recentEntries()) _verdicts[e.id] ?? e,
  ];

  @override
  Future<OutboxEntry> push(String entryId) async {
    final code = nextBusinessRejectCode;
    if (code == null) return inner.push(entryId);
    nextBusinessRejectCode = null;
    final entries = await recentEntries();
    final current = entries.firstWhere((e) => e.id == entryId);
    final updated = current.copyWith(
      syncState: OutboxSyncState.rejected,
      attemptCount: current.attemptCount + 1,
      lastErrorCode: code,
      lastErrorDetail: nextBusinessRejectDetail,
    );
    _verdicts[entryId] = updated;
    return updated;
  }

  @override
  Future<OutboxEntry> retry(String entryId) => inner.retry(entryId);
}

/// A REAL paired-device + staff-PIN session for the real-mode surface.
const SyncSession _session = SyncSession(
  pinSessionId: 'pin-1',
  deviceId: 'dev-1',
);

/// Scripted REAL transport answering `sync_push` with the server's typed
/// `item_unavailable` verdict — the exact envelope `public.sync_push` returns
/// for a RETURN-refusal (per-op `status:'rejected'` + `error` + the echoed
/// blocked-item names). Drives the true `_applyPushResult` parse, not a stub.
class _ItemUnavailableTransport implements SyncRpcTransport {
  int pushes = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> p) async {
    pushes++;
    final op = (p['p_operations'] as List).first as Map<String, dynamic>;
    return <String, dynamic>{
      'ok': true,
      'results': <dynamic>[
        <String, dynamic>{
          'local_operation_id': op['local_operation_id'],
          'operation_type': 'order.submit',
          'ok': false,
          'status': 'rejected',
          'error': 'item_unavailable',
          'items': <dynamic>[
            <String, dynamic>{'name': 'Onion Rings', 'reason': 'sold_out'},
          ],
        },
      ],
      'server_ts': '2026-07-15T09:00:01Z',
    };
  }
}

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

/// The REAL post-PIN POS surface (mirrors `pos_real_flow_labels_test`): real
/// runtime config, a live SyncSession, the production [RealOutboxRepository]
/// over [transport], and a known menu.
Future<void> _pumpReal(WidgetTester tester, SyncRpcTransport transport) async {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posSyncSessionProvider.overrideWithValue(_session),
        outboxRepositoryProvider.overrideWithValue(
          RealOutboxRepository(transport, _session),
        ),
        posMenuProvider.overrideWith(
          (ref) async => const PosMenuData(
            categories: kDemoCategories,
            items: kDemoMenu,
            currencyCode: 'ILS',
          ),
        ),
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

Future<void> _pump(WidgetTester tester, OutboxRepository repo) async {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [outboxRepositoryProvider.overrideWithValue(repo)],
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

Future<void> _submit(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.posSendOrder));
  await tester.pumpAndSettle();
}

/// One takeaway line through the REAL controller submit path (the same
/// choke point the cart uses), for the non-widget sweep test.
Future<OrderSubmitResult> _submitViaController(OutboxController controller) =>
    controller.submit(
      lines: const [
        CartLineView(
          lineId: 'l1',
          menuItemId: 'burger-classic',
          name: 'Classic Burger',
          quantity: 1,
          unitPriceMinor: 4800,
          lineTotalMinor: 4800,
          currencyCode: 'ILS',
        ),
      ],
      subtotalMinor: 4800,
      currencyCode: 'ILS',
      orderType: OrderType.takeaway,
    );

void main() {
  group('A. classification (pure)', () {
    OutboxEntry entry(OutboxSyncState state, String? code) => OutboxEntry(
      id: 'e1',
      deviceId: 'dev',
      localOperationId: 'op-1',
      operationType: 'order.submit',
      targetEntity: 'order',
      targetId: 'o-1',
      payloadJson: '{}',
      summary: const OrderSummary(
        orderNumber: '#000001',
        orderType: OrderType.takeaway,
        tableLabel: null,
        itemCount: 1,
        subtotalMinor: 2500,
        currencyCode: 'ILS',
      ),
      syncState: state,
      clientCreatedAt: DateTime.utc(2026, 7, 15),
      lastErrorCode: code,
    );

    test('A1 every ledgered business verdict is PERMANENT', () {
      for (final code in [
        'item_unavailable',
        'table_required',
        'table_not_allowed',
        'table_not_available',
        'rejected',
      ]) {
        expect(
          entry(OutboxSyncState.rejected, code).isPermanentBusinessRejection,
          isTrue,
          reason: code,
        );
      }
    });

    test('A2 parse/transport-ish codes and dead entries stay RETRYABLE', () {
      for (final code in [
        'malformed_response',
        'missing_results',
        'no_matching_operation',
        'demo_transient',
        null,
      ]) {
        expect(
          entry(OutboxSyncState.rejected, code).isPermanentBusinessRejection,
          isFalse,
          reason: '$code',
        );
      }
      // dead = attempts exhausted on transport — a manual retry stays honest.
      expect(
        entry(
          OutboxSyncState.dead,
          'item_unavailable',
        ).isPermanentBusinessRejection,
        isFalse,
      );
    });

    test('A3 a non-rejected state is never classified permanent', () {
      expect(
        entry(
          OutboxSyncState.applied,
          'item_unavailable',
        ).isPermanentBusinessRejection,
        isFalse,
      );
    });
  });

  group('B. the confirmation surface', () {
    testWidgets('B1 a REAL item_unavailable rejection shows NO Retry — the '
        'recovery is the typed note directing a deliberate re-entry', (
      tester,
    ) async {
      final l10n = await _en();
      final transport = _ItemUnavailableTransport();
      await _pumpReal(tester, transport);
      await _submit(tester, l10n);

      // The verdict landed once, via the automatic real-mode push at submit.
      expect(transport.pushes, 1);
      expect(find.text(l10n.posSyncStateFailed), findsOneWidget);
      // THE fix: no same-identity Retry over a ledgered business verdict.
      expect(find.byKey(const Key('sync-retry-button')), findsNothing);
      // The recovery path stays on screen: the typed note naming the blocked
      // items and directing the cashier to re-enter the order without them.
      expect(
        find.text(l10n.posSyncItemUnavailable('Onion Rings')),
        findsOneWidget,
      );
    });

    testWidgets('B2 a transport-ish failure KEEPS Retry (regression: the fix '
        'removes nothing genuinely retryable)', (tester) async {
      final l10n = await _en();
      final store = _BusinessRejectStore();
      await _pump(tester, store);
      await _submit(tester, l10n);

      store.inner.nextPushFails = true; // demo transient failure
      await tester.tap(find.byKey(const Key('sync-now-button')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.posSyncStateFailed), findsOneWidget);
      expect(find.byKey(const Key('sync-retry-button')), findsOneWidget);

      // ...and the retry still completes the lifecycle honestly.
      await tester.tap(find.byKey(const Key('sync-retry-button')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.posSyncStateSynced), findsOneWidget);
    });
  });

  group('C. the sweep never burns attempts on a ledgered verdict', () {
    test(
      'C1 retryAllFailed skips permanent rejections, keeps retryable ones',
      () async {
        final store = _BusinessRejectStore();
        final container = ProviderContainer(
          overrides: [outboxRepositoryProvider.overrideWithValue(store)],
        );
        addTearDown(container.dispose);
        final controller = container.read(outboxControllerProvider.notifier);

        // Two orders through the REAL submit path: the first permanently
        // rejected by the server verdict, the second transiently failed.
        // (Demo submits auto-push nothing; push explicitly, as Sync now does.)
        final a = await _submitViaController(controller);
        store.nextBusinessRejectCode = 'item_unavailable';
        await controller.pushEntry(a.entry.id);
        final b = await _submitViaController(controller);
        store.inner.nextPushFails = true;
        await controller.pushEntry(b.entry.id);

        await controller.retryAllFailed();

        final entries = container.read(outboxControllerProvider);
        final ea = entries.firstWhere((e) => e.id == a.entry.id);
        final eb = entries.firstWhere((e) => e.id == b.entry.id);
        // The permanent rejection was NOT re-pushed (verdict stands untouched)…
        expect(ea.syncState, OutboxSyncState.rejected);
        expect(ea.lastErrorCode, 'item_unavailable');
        // …while the transient failure was retried to success.
        expect(eb.syncState, OutboxSyncState.applied);
      },
    );
  });
}
