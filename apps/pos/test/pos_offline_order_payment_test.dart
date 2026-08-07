// POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass B — PAYMENT AFTER A RECONNECT.
//
// THE DEFECT. Pass A ended the global offline LATCH, so the till stops claiming
// to be offline once a real menu fetch answers again. That left the ORDER-scoped
// half of the bug untouched: `resolveOrderActions` decided `canPay` without ever
// asking whether the server had ACCEPTED the order's submit, and
// `PosPendingKind.submit` did not withdraw it. So a cashier who took an order
// during the outage was offered Take payment for it the instant the banner
// cleared — while the submit was still sitting in the outbox.
//
// What that produced was not a harmless failure. `app.record_payment` raises
// `order not found` (SQLSTATE 42501) for an order the server has never seen;
// `app.sync_push` ledgers that as a PERMANENT rejection of the payment identity;
// `payment_repository` throws an untyped PaymentException; and the sheet renders
// the generic "Payment not recorded — check the connection and try again". Every
// word of that is a lie: the connection is fine, the order is fine, and there is
// nothing to retry. Worse, `payments_one_completed_per_order_uidx` permits
// exactly ONE completed payment per order, so a guess here is not cheap.
//
// THE FIX UNDER TEST is one additive input to the ONE policy function
// (`posSubmitUnacknowledged` -> `resolveOrderActions(submitUnacknowledged:)`),
// which FAILS OPEN — it denies only on positive evidence (real mode + no server
// snapshot + this device holds the `order.submit` entry + that entry is not
// accepted) — plus the order-scoped refusal beside the offline one at the ONE
// payment entry point, and the awaiting-sync notes decoupled from the global
// phase.
//
// Covers the mandated regression list 11-20:
//   11    a queued order is NOT payable and says why, on the row and the sheet
//   12    the refusal is SYNC-specific, never the connectivity copy
//   13/14 connectivity returns -> the SAME identity syncs exactly once
//   15    the SAME MOUNTED tree becomes payable — no restart, no remount
//   16    the normal online payment workflow then opens
//   17    the local projection reconciles to the authoritative server order
//   18    no duplicate server order, and no second payable path
//   19    the fail-open rules (demo; and a row with no entry at all)
//   20    the awaiting-sync note renders while the phase reads ONLINE
//
// Synthetic values only. No network, no printer, no real money.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show
        SyncRpcTransport,
        SyncSession,
        SyncTransportErrorKind,
        SyncTransportException;
import 'package:restoflow_domain/restoflow_domain.dart'
    show OrderType, displayOrderCode;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart' show DemoMenuItem;
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_identity.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_offline_state.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart'
    show posSyncScopeProvider;
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart'
    show submitOrderFromCart;
import 'package:restoflow_pos/src/widgets/cash_payment_sheet.dart';
import 'package:restoflow_pos/src/widgets/order_confirmation.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/verified_kitchen_mode_readiness.dart';

const _offlineFailure = SyncTransportException(
  SyncTransportErrorKind.transient,
  code: 'network',
);

const _ctx = DeviceContext(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-A',
  deviceId: 'device-1',
  deviceType: 'pos',
  deviceSessionId: 'ds-A',
);

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'device-1');

/// The fixed scope the hand-seeded fail-open cases run under (both modes), so
/// the demo/real pair differs in exactly one variable.
const _seededScope = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-A',
  deviceId: 'device-1',
);

const _burger = DemoMenuItem(
  id: 'm1',
  name: 'Burger',
  priceMinor: 4000,
  categoryId: 'cat',
  categoryName: 'Mains',
);

final _menuSource = StateProvider<PosMenuData>(
  (_) =>
      const PosMenuData(categories: [], currencyCode: 'ILS', items: [_burger]),
);

/// Scripted `sync_push` transport: one step per `order.submit` push (the last
/// step repeats), recording every pushed operation identity so "exactly once,
/// same identity" is an assertion rather than a hope. `serverUp` flips the
/// answer MID-TEST — the whole point is that nothing is rebuilt when the
/// network comes back.
class _ScriptedSyncTransport implements SyncRpcTransport {
  /// Whether the backend currently answers. Starts DOWN in every scenario here:
  /// the defect only exists for an order taken while it was.
  bool serverUp = false;
  int pushes = 0;
  final List<String> pushedLocalOperationIds = <String>[];
  final List<String> appliedOperationTypes = <String>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'start_pin_session') return 'pin-session-1';
    if (function != 'sync_push') return null;
    final op = (params['p_operations'] as List).first as Map;
    // The sign-in's best-effort `shift.open` rides the same pipeline; it is not
    // the seam under test — answer it blandly and count ONLY order pushes.
    if (op['operation_type'] != 'order.submit') {
      return <String, dynamic>{'ok': true, 'results': <dynamic>[]};
    }
    pushes++;
    pushedLocalOperationIds.add(op['local_operation_id'] as String);
    if (!serverUp) throw _offlineFailure;
    appliedOperationTypes.add(op['operation_type'] as String);
    return <String, dynamic>{
      'ok': true,
      'results': <dynamic>[
        <String, dynamic>{
          'local_operation_id': op['local_operation_id'],
          'operation_type': 'order.submit',
          'ok': true,
          'status': 'applied',
        },
      ],
      'server_ts': '2026-08-06T09:00:01Z',
    };
  }
}

/// An outbox whose contents are HANDED IN, so the fail-open rules can be stated
/// against an exact queue without driving a whole submit. Never pushes anything.
class _SeededOutbox implements OutboxRepository {
  _SeededOutbox(this.entries);

  final List<OutboxEntry> entries;

  @override
  Future<OutboxEntry> enqueue(OutboxEntry entry) async => entry;

  @override
  Future<List<OutboxEntry>> recentEntries() async => entries;

  @override
  Future<OutboxEntry> push(String entryId) async =>
      entries.firstWhere((e) => e.id == entryId);

  @override
  Future<OutboxEntry> retry(String entryId) async =>
      entries.firstWhere((e) => e.id == entryId);

  @override
  Future<String?> findOrderSubmitCustomerPhone(
    OrderSubmitPhoneLookupKey key,
  ) async => null;
}

/// A queued `order.submit` for [orderId] that the server has NOT answered.
OutboxEntry _pendingSubmit(String orderId, String orderNumber) => OutboxEntry(
  id: 'entry-$orderId',
  deviceId: _ctx.deviceId!,
  localOperationId: 'op-$orderId',
  operationType: 'order.submit',
  targetEntity: 'order',
  targetId: orderId,
  payloadJson: '{"order_id":"$orderId"}',
  summary: OrderSummary(
    orderNumber: orderNumber,
    orderType: OrderType.takeaway,
    tableLabel: null,
    itemCount: 1,
    subtotalMinor: 4000,
    currencyCode: 'ILS',
  ),
  syncState: OutboxSyncState.pending,
  clientCreatedAt: DateTime.utc(2026, 8, 6, 9),
);

SubmittedOrderView _view(String orderNumber, String orderId) =>
    SubmittedOrderView(
      orderNumber: orderNumber,
      orderType: OrderType.takeaway,
      currencyCode: 'ILS',
      subtotalMinor: 4000,
      orderId: orderId,
      lines: const [
        SubmittedLineView(
          name: 'Burger',
          quantity: 1,
          lineTotalMinor: 4000,
          currencyCode: 'ILS',
        ),
      ],
    );

PosOrderSnapshot _snapshot(
  String orderId,
  String orderCode, {
  int revision = 3,
  int grandTotalMinor = 4000,
}) => PosOrderSnapshot(
  orderId: orderId,
  orderCode: orderCode,
  revision: revision,
  status: 'submitted',
  settlement: PosSettlement.unpaid,
  subtotalMinor: grandTotalMinor,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: grandTotalMinor,
  createdAt: DateTime.utc(2026, 8, 6, 9),
  updatedAt: DateTime.utc(2026, 8, 6, 9, 1),
  syncAt: DateTime.utc(2026, 8, 6, 9, 1),
  orderType: 'takeaway',
  currencyCode: 'ILS',
);

Future<void> _settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.microtask(() {});
  }
}

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 1900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _Harness {
  _Harness({
    required this.container,
    required this.transport,
    required this.snapshots,
    required this.l10n,
    required this.ref,
    required this.context,
  });

  final ProviderContainer container;
  final _ScriptedSyncTransport transport;
  final DemoOrderSnapshotRepository snapshots;
  final AppLocalizations l10n;
  final WidgetRef ref;
  final BuildContext context;

  Future<void> submit() => submitOrderFromCart(
    ref: ref,
    context: context,
    cart: container.read(cartControllerProvider),
    setup: container.read(orderSetupControllerProvider),
    cartController: container.read(cartControllerProvider.notifier),
    setupController: container.read(orderSetupControllerProvider.notifier),
    l10n: l10n,
  );

  OutboxEntry get entry => container.read(outboxControllerProvider).single;

  PosRecentOrder get row =>
      container.read(posRecentOrdersControllerProvider).single;

  String get code => row.orderNumber;
}

/// The REAL submit world in REAL mode: signed-in PIN session, verified KDS
/// readiness, the real repository over a scripted transport, one Burger in the
/// cart, and a pumped host whose ref/context drive the REAL Send handler.
Future<_Harness> _pump(
  WidgetTester tester, {
  required _ScriptedSyncTransport transport,
  bool offlineCached = true,
}) async {
  SharedPreferences.setMockInitialValues(const {});
  final snapshots = DemoOrderSnapshotRepository();
  final repo = RealOutboxRepository(transport, _session);
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport),
      posRealSessionConfigProvider.overrideWithValue(null),
      outboxRepositoryProvider.overrideWithValue(repo),
      posMenuProvider.overrideWith((ref) => ref.watch(_menuSource)),
      verifiedKdsReadinessOverride(),
      posRecentOrdersStoreProvider.overrideWithValue(
        InMemoryRecentOrdersStore(),
      ),
      orderSnapshotRepositoryProvider.overrideWithValue(snapshots),
      // No polling timer: `pumpAndSettle` must terminate.
      posSyncPollIntervalProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  container.read(posDeviceContextProvider.notifier).set(_ctx);
  await _settle();
  final err = await container
      .read(posSessionControllerProvider.notifier)
      .signInWithPin(
        device: _ctx,
        deviceId: _ctx.deviceId!,
        deviceSessionId: _ctx.deviceSessionId!,
        employeeProfileId: 'emp-1',
        pin: '1234',
      );
  expect(err, isNull);
  await _settle();
  // The offline OPERATING PHASE is written only by real menu-fetch outcomes in
  // production; recorded directly here because these tests drive the submit and
  // payment seams, not the menu fetch (Pass A owns that path).
  if (offlineCached) {
    container
        .read(posOfflineModeProvider.notifier)
        .recordOfflineCacheServed(snapshotFetchedAt: DateTime.utc(2026, 8, 6));
  }

  final l10n = await AppLocalizations.delegate.load(const Locale('en'));
  late WidgetRef capturedRef;
  late BuildContext capturedContext;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Consumer(
          builder: (context, r, _) {
            capturedRef = r;
            capturedContext = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    ),
  );
  container.read(cartControllerProvider.notifier).addItem(_burger);
  await tester.pump();
  return _Harness(
    container: container,
    transport: transport,
    snapshots: snapshots,
    l10n: l10n,
    ref: capturedRef,
    context: capturedContext,
  );
}

Future<void> _pumpOrdersSheet(
  WidgetTester tester,
  ProviderContainer container,
) async {
  _wide(tester);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const Scaffold(body: RecentOrdersSheet()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpConfirmation(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final submitted = container.read(cartControllerProvider).submittedOrder!;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: OrderConfirmation(order: submitted, onNewOrder: () {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------
  group('11. the predicate itself — positive evidence only', () {
    // -----------------------------------------------------------------------
    final queued = _pendingSubmit('order-1', '#ORDER1');

    test('a real-mode row with a queued submit and NO snapshot is '
        'unacknowledged, and that alone withdraws payment', () {
      expect(
        posSubmitUnacknowledged(
          isDemo: false,
          hasServerSnapshot: false,
          submitEntry: queued,
        ),
        isTrue,
      );
      final order = PosRecentOrder(
        order: _view('#ORDER1', 'order-1'),
        submittedAt: DateTime.utc(2026, 8, 6, 9),
      );
      final withheld = resolveOrderActions(order, submitUnacknowledged: true);
      final offered = resolveOrderActions(order);
      expect(offered.canPay, isTrue, reason: 'the control: payable otherwise');
      expect(withheld.canPay, isFalse);
      expect(withheld.submitUnacknowledged, isTrue);
      // PAYMENT ONLY. Nothing else moves — a queued order can still be voided,
      // discounted, moved and extended; none of those is the operation that
      // fails with `order not found`.
      expect(withheld.canVoid, offered.canVoid);
      expect(withheld.canDiscount, offered.canDiscount);
      expect(withheld.canMoveTable, offered.canMoveTable);
      expect(withheld.canAddItems, offered.canAddItems);
      expect(withheld.canOpenReceipt, offered.canOpenReceipt);
    });

    test('FAIL OPEN: demo, an accepted submit, a server snapshot, and no entry '
        'at all all read acknowledged', () {
      // Demo never pushes its entries, so they stay pending forever.
      expect(
        posSubmitUnacknowledged(
          isDemo: true,
          hasServerSnapshot: false,
          submitEntry: queued,
        ),
        isFalse,
      );
      // A snapshot IS the server speaking about this order.
      expect(
        posSubmitUnacknowledged(
          isDemo: false,
          hasServerSnapshot: true,
          submitEntry: queued,
        ),
        isFalse,
      );
      // The server said yes.
      expect(
        posSubmitUnacknowledged(
          isDemo: false,
          hasServerSnapshot: false,
          submitEntry: queued.copyWith(syncState: OutboxSyncState.applied),
        ),
        isFalse,
      );
      // UNKNOWN IS NOT DENIED — the recent_orders_sheet_test `#U1` shape.
      expect(
        posSubmitUnacknowledged(
          isDemo: false,
          hasServerSnapshot: false,
          submitEntry: null,
        ),
        isFalse,
      );
    });

    test('a LATER operation for the same order never answers the question', () {
      final payment = OutboxEntry(
        id: 'entry-pay',
        deviceId: _ctx.deviceId!,
        localOperationId: 'op-pay',
        operationType: 'payment.create',
        targetEntity: 'order',
        targetId: 'order-1',
        payloadJson: '{}',
        summary: queued.summary,
        syncState: OutboxSyncState.pending,
        clientCreatedAt: DateTime.utc(2026, 8, 6, 9),
      );
      final identity = PosOrderIdentity.server('order-1');
      expect(posSubmitEntryFor([payment], identity), isNull);
      expect(posSubmitEntryFor([payment, queued], identity), same(queued));
    });
  });

  // -------------------------------------------------------------------------
  group('11/12/20. an order the server has never seen', () {
    // -----------------------------------------------------------------------
    testWidgets('a queued offline order is NOT payable in the orders centre, '
        'and the row says it is waiting to sync', (tester) async {
      final h = await _pump(tester, transport: _ScriptedSyncTransport());
      await h.submit();
      await tester.pumpAndSettle();

      // The exact shape RC-2 describes: a client-minted order id (so the row is
      // NOT a local draft), no server snapshot, and an unanswered submit.
      expect(h.entry.operationType, 'order.submit');
      expect(h.entry.outcome, PosOrderOutcome.deliveryUnconfirmed);
      expect(h.row.orderId, isNotNull);
      expect(h.row.snapshot, isNull);

      await _pumpOrdersSheet(tester, h.container);
      final code = h.code;
      expect(find.byKey(Key('recent-order-$code')), findsOneWidget);
      expect(
        find.byKey(Key('recent-pay-$code')),
        findsNothing,
        reason: 'record_payment could only answer `order not found`',
      );
      expect(
        find.byKey(Key('recent-offline-pending-$code')),
        findsOneWidget,
        reason: 'the missing button must be explained, not merely absent',
      );
      // The row renders both lines in ONE Text (the note idiom the sheet uses),
      // so this reads the rendered data rather than matching two widgets.
      final note = tester.widget<Text>(
        find.byKey(Key('recent-offline-pending-$code')),
      );
      expect(note.data, contains(h.l10n.posOfflineOrderSavedLocally));
      expect(note.data, contains(h.l10n.posOfflineAwaitingSync));
    });

    testWidgets('20 — the awaiting-sync note stays while the phase reads '
        'ONLINE, on the row AND on the confirmation', (tester) async {
      final h = await _pump(tester, transport: _ScriptedSyncTransport());
      await h.submit();
      await tester.pumpAndSettle();
      // Connectivity is back — but this order is still in the queue. The note
      // used to be ANDed with the global phase and vanished right here, exactly
      // when the cashier is most likely to reach for Take payment.
      h.container.read(posOfflineModeProvider.notifier).recordOnlineFetch();
      await tester.pump();
      expect(
        h.container.read(posOfflineModeProvider).phase,
        PosOfflinePhase.online,
      );
      // The entry is still unanswered (the transport is still down).
      expect(h.entry.outcome, PosOrderOutcome.deliveryUnconfirmed);

      await _pumpConfirmation(tester, h.container);
      expect(
        find.byKey(const Key('confirmation-offline-pending')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('confirmation-offline-awaiting')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('pay-cash-button')), findsNothing);

      await _pumpOrdersSheet(tester, h.container);
      expect(
        find.byKey(Key('recent-offline-pending-${h.code}')),
        findsOneWidget,
      );
      expect(find.byKey(Key('recent-pay-${h.code}')), findsNothing);
    });

    testWidgets('12 — attempting payment refuses with the SYNC message, never '
        'the connectivity copy', (tester) async {
      _wide(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // ONLINE on purpose: this refusal is about the ORDER, so the offline gate
      // beside it must be provably not the one firing.
      expect(
        container.read(posOfflineModeProvider).phase,
        PosOfflinePhase.online,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  key: const Key('open-pay'),
                  onPressed: () => CashPaymentSheet.show(
                    context,
                    identity: PosOrderIdentity.server('order-1'),
                    orderNumber: '#ORDER1',
                    amountMinor: 4000,
                    currencyCode: 'ILS',
                    orderId: 'order-1',
                    submitUnacknowledged: true,
                  ),
                  child: const Text('pay'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-pay')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(CashPaymentSheet), findsNothing);
      expect(find.text(l10n.posPaymentAwaitingOrderSync), findsOneWidget);
      expect(
        find.text(l10n.posOfflineActionUnavailable),
        findsNothing,
        reason: 'this is not a connectivity fault and must not read like one',
      );
      // And the message itself never sends the cashier to the network.
      expect(
        l10n.posPaymentAwaitingOrderSync.toLowerCase(),
        isNot(contains('connection')),
      );
    });

    testWidgets('the SAME entry point still opens normally once the order is '
        'acknowledged (the refusal never overblocks)', (tester) async {
      _wide(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  key: const Key('open-pay'),
                  onPressed: () => CashPaymentSheet.show(
                    context,
                    identity: PosOrderIdentity.server('order-1'),
                    orderNumber: '#ORDER1',
                    amountMinor: 4000,
                    currencyCode: 'ILS',
                    orderId: 'order-1',
                  ),
                  child: const Text('pay'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-pay')));
      await tester.pumpAndSettle();
      expect(find.byType(CashPaymentSheet), findsOneWidget);
      expect(find.text(l10n.posPaymentAwaitingOrderSync), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('13-18. the reconnect: one sync, same tree, money reopens', () {
    // -----------------------------------------------------------------------
    testWidgets('the SAME queued operation syncs EXACTLY ONCE and the SAME '
        'MOUNTED orders screen becomes payable — no restart, no remount', (
      tester,
    ) async {
      final transport = _ScriptedSyncTransport();
      final h = await _pump(tester, transport: transport);
      await h.submit();
      await tester.pumpAndSettle();
      expect(transport.pushes, 1, reason: 'the offline attempt happened');
      final code = h.code;
      final queuedIdentity = (
        deviceId: h.entry.deviceId,
        localOperationId: h.entry.localOperationId,
      );

      await _pumpOrdersSheet(tester, h.container);
      expect(find.byKey(Key('recent-pay-$code')), findsNothing);
      // The identity of the live State — proof that everything below happens on
      // the tree that is already on screen. Nothing here remounts, reopens or
      // restarts anything.
      final sheetState = tester.state(find.byType(RecentOrdersSheet));

      // THE WORLD OUTSIDE THE APP CHANGES, and nothing else. The backend answers
      // again and the phase flips (Pass A's job); the outbox's reconnect
      // listener flushes the queue on that edge.
      final attemptsWhileDown = transport.pushes;
      transport.serverUp = true;
      h.container.read(posOfflineModeProvider.notifier).recordOnlineFetch();
      await tester.pumpAndSettle();

      // 13/14 — exactly ONE resubmission once the backend answers, and every
      // attempt (successful or not) carried the SAME D-022 identity. The count
      // of attempts WHILE DOWN is deliberately not pinned: idempotent replay is
      // what makes them safe, and the assertion that matters is that exactly one
      // of them was ever APPLIED.
      expect(transport.pushes, attemptsWhileDown + 1);
      expect(
        transport.pushedLocalOperationIds.toSet(),
        hasLength(1),
        reason: 'the SAME (deviceId, localOperationId) on every push',
      );
      expect(
        transport.appliedOperationTypes,
        ['order.submit'],
        reason: 'exactly one applied server operation — one order, not two',
      );
      // 18 — one server order, never two.
      final entries = h.container.read(outboxControllerProvider);
      expect(entries, hasLength(1));
      expect(entries.single.deviceId, queuedIdentity.deviceId);
      expect(entries.single.localOperationId, queuedIdentity.localOperationId);
      expect(entries.single.syncState, OutboxSyncState.applied);
      expect(entries.single.outcome, PosOrderOutcome.accepted);

      // 15 — the very same mounted State is now payable.
      expect(
        identical(tester.state(find.byType(RecentOrdersSheet)), sheetState),
        isTrue,
        reason: 'the same mounted screen recovered — nothing was rebuilt',
      );
      expect(
        find.byKey(Key('recent-pay-$code')),
        findsOneWidget,
        reason: 'the server accepted the order, so money may be taken',
      );
      expect(
        find.byKey(Key('recent-offline-pending-$code')),
        findsNothing,
        reason: 'nothing is waiting to sync any more',
      );

      // 18 — a further sweep spends NOTHING on the applied entry, so no second
      // server order can exist for this identity.
      final attemptsAfterFlush = transport.pushes;
      await h.container.read(outboxControllerProvider.notifier).pushQueued();
      await tester.pumpAndSettle();
      expect(transport.pushes, attemptsAfterFlush);
      expect(transport.appliedOperationTypes, hasLength(1));
      expect(h.container.read(posRecentOrdersControllerProvider), hasLength(1));

      // 16 — and it is the NORMAL online payment workflow that opens, through
      // the ONE entry point: no second payable path exists on this row.
      await tester.tap(find.byKey(Key('recent-pay-$code')));
      await tester.pumpAndSettle();
      expect(find.byType(CashPaymentSheet), findsOneWidget);
      expect(find.text(h.l10n.posPaymentAwaitingOrderSync), findsNothing);
      expect(find.text(h.l10n.posOfflineActionUnavailable), findsNothing);
    });

    testWidgets('17 — the local projection reconciles to the AUTHORITATIVE '
        'server order and the orders screen updates without a restart', (
      tester,
    ) async {
      final transport = _ScriptedSyncTransport();
      final h = await _pump(tester, transport: transport);
      await h.submit();
      await tester.pumpAndSettle();
      final orderId = h.row.orderId!;
      final code = h.code;

      await _pumpOrdersSheet(tester, h.container);
      final sheetState = tester.state(find.byType(RecentOrdersSheet));
      expect(h.row.snapshot, isNull);
      expect(find.byKey(Key('recent-pay-$code')), findsNothing);

      // The order lands, and the SERVER's view of it arrives through the normal
      // snapshot feed — a different total from the submit-time one, so the merge
      // is provably the server's and not the local copy's.
      transport.serverUp = true;
      h.container.read(posOfflineModeProvider.notifier).recordOnlineFetch();
      await tester.pumpAndSettle();
      h.snapshots.upsert(
        _snapshot(orderId, displayOrderCode(orderId), grandTotalMinor: 4500),
      );
      await h.container
          .read(posOrderSyncControllerProvider.notifier)
          .refreshWindow();
      await tester.pumpAndSettle();

      final row = h.row;
      expect(row.snapshot, isNotNull, reason: 'the projection took the server');
      expect(row.revision, 3);
      expect(row.grandTotalMinor, 4500);
      expect(
        identical(tester.state(find.byType(RecentOrdersSheet)), sheetState),
        isTrue,
        reason: 'the reconciliation landed on the mounted screen',
      );
      expect(find.byKey(Key('recent-pay-$code')), findsOneWidget);
      expect(find.byKey(Key('recent-offline-pending-$code')), findsNothing);
      // Still exactly one order — a reconciliation is not a second submit.
      expect(h.container.read(posRecentOrdersControllerProvider), hasLength(1));
      expect(transport.appliedOperationTypes, ['order.submit']);
    });
  });

  // -------------------------------------------------------------------------
  group('19. the fail-open rules, on the real orders surface', () {
    // -----------------------------------------------------------------------
    Future<ProviderContainer> seeded(
      WidgetTester tester, {
      required bool isDemo,
      required List<OutboxEntry> entries,
      PosOrderSnapshot? snapshot,
    }) async {
      SharedPreferences.setMockInitialValues(const {});
      final store = InMemoryRecentOrdersStore();
      await store.persist(_seededScope.key, [
        PosRecentOrder(
          order: _view('#U1', 'order-1'),
          submittedAt: DateTime.now(),
          snapshot: snapshot,
        ),
      ]);
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: isDemo),
          ),
          // One fixed scope for BOTH modes, so the demo/real pair differs in
          // exactly one thing: which rule the predicate applies.
          posSyncScopeProvider.overrideWithValue(_seededScope),
          outboxRepositoryProvider.overrideWithValue(_SeededOutbox(entries)),
          posRecentOrdersStoreProvider.overrideWithValue(store),
          orderSnapshotRepositoryProvider.overrideWithValue(
            DemoOrderSnapshotRepository(),
          ),
          posSyncPollIntervalProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      await _pumpOrdersSheet(tester, container);
      return container;
    }

    testWidgets('a DEMO row whose entry is pending forever stays payable', (
      tester,
    ) async {
      await seeded(
        tester,
        isDemo: true,
        entries: [_pendingSubmit('order-1', '#U1')],
      );
      expect(
        find.byKey(const Key('recent-pay-#U1')),
        findsOneWidget,
        reason: 'a demo entry is never pushed; denying it would break demo',
      );
      expect(find.byKey(const Key('recent-offline-pending-#U1')), findsNothing);
    });

    testWidgets('a REAL row with NO entry and no snapshot stays payable '
        '(the recent_orders_sheet_test #U1 shape)', (tester) async {
      await seeded(tester, isDemo: false, entries: const []);
      expect(
        find.byKey(const Key('recent-pay-#U1')),
        findsOneWidget,
        reason: 'absence of evidence is not evidence of a missing order',
      );
      expect(find.byKey(const Key('recent-offline-pending-#U1')), findsNothing);
    });

    testWidgets('a REAL row whose entry is pending but which HOLDS a server '
        'snapshot stays payable', (tester) async {
      await seeded(
        tester,
        isDemo: false,
        entries: [_pendingSubmit('order-1', '#U1')],
        snapshot: _snapshot('order-1', '#U1'),
      );
      expect(
        find.byKey(const Key('recent-pay-#U1')),
        findsOneWidget,
        reason: 'the server has spoken about this order; it exists',
      );
      expect(find.byKey(const Key('recent-offline-pending-#U1')), findsNothing);
    });

    testWidgets('the SAME real row WITHOUT a snapshot is withheld — the '
        'control that proves the three rules above are not vacuous', (
      tester,
    ) async {
      await seeded(
        tester,
        isDemo: false,
        entries: [_pendingSubmit('order-1', '#U1')],
      );
      expect(find.byKey(const Key('recent-pay-#U1')), findsNothing);
      expect(
        find.byKey(const Key('recent-offline-pending-#U1')),
        findsOneWidget,
      );
    });
  });
}
