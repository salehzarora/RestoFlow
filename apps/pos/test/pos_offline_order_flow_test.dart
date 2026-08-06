// POS-OFFLINE-OPERATIONS-002 — C9/C11 offline order taking.
//
// Covers OFFLINE-ARCH-SPEC tests 17, 18, 19, 20, 21, 22:
//   17 — the DURABLE SEQUENCE: an offline submit persists the order in the
//        durable outbox BEFORE the cart clears (proven at the persist call
//        itself), the confirmation shows the honest local presentation with
//        the offline saved-locally/awaiting-sync copy, and no server order
//        number is ever fabricated (the code shown IS the local display code);
//   18 — a REFUSED durable write keeps the cart intact and shows the honest
//        failure — the order is never silently lost and never dispatched;
//   19 — a container "restart" over the SAME prefs retains the queued order
//        verbatim (identity + payload bytes);
//   20 — a rapid double submit while the first is in flight enqueues exactly
//        ONE operation (the controller latch joins, POS-SUBMIT-GUARD-001);
//   21 — the reconnect flush resubmits the SAME (deviceId, localOperationId)
//        identity exactly once and settles it applied — and a further sweep
//        spends no extra transport attempt;
//   22 — an idempotent-replay stored result (the server already owned the
//        order) reconciles the entry to accepted without a duplicate and
//        without inventing a server receipt number.
//
// Harness: the REAL submit seam (`submitOrderFromCart`) over the REAL
// `RealOutboxRepository` + `SharedPrefsOutboxStore` (mocked prefs), a scripted
// sync transport that fails like a genuinely unreachable backend, and the
// real PIN sign-in — the kitchen_print_dual_001d_submission_test idiom.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show displayOrderCode;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/durable_outbox_store.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosPersistenceException;
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_offline_state.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart'
    show submitOrderFromCart;
import 'package:restoflow_pos/src/widgets/order_confirmation.dart';
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

final _menuSource = StateProvider<PosMenuData>(
  (_) => const PosMenuData(
    categories: [],
    currencyCode: 'ILS',
    items: [
      DemoMenuItem(
        id: 'm1',
        name: 'Burger',
        priceMinor: 4000,
        categoryId: 'cat',
        categoryName: 'Mains',
      ),
    ],
  ),
);

/// Scripted `sync_push` transport: consumes one step per push (the last step
/// repeats) and records every pushed operation identity. An optional [gate]
/// holds the FIRST push in flight so a concurrent second submit can be fired.
class _ScriptedSyncTransport implements SyncRpcTransport {
  _ScriptedSyncTransport(this.steps, {this.gate});

  final List<Object> steps;
  final Future<void>? gate;
  int pushes = 0;
  final List<String> pushedLocalOperationIds = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'start_pin_session') return 'pin-session-1';
    if (function != 'sync_push') return null;
    final op = (params['p_operations'] as List).first as Map;
    // The sign-in's best-effort `shift.open` rides the same pipeline; it is
    // not the seam under test — answer it blandly, count ONLY order pushes.
    if (op['operation_type'] != 'order.submit') {
      return <String, dynamic>{'ok': true, 'results': <dynamic>[]};
    }
    pushedLocalOperationIds.add(op['local_operation_id'] as String);
    final step = steps[pushes < steps.length ? pushes : steps.length - 1];
    final first = pushes == 0;
    pushes++;
    if (first && gate != null) await gate;
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

/// Wraps the REAL durable store and samples, AT THE PERSIST CALL ITSELF,
/// whether the live cart still holds its lines — the only honest way to prove
/// "the order is on disk BEFORE the cart clears".
class _SequencedStore implements DurableOutboxStore {
  _SequencedStore(this._inner, this._cartEmptyNow);

  final DurableOutboxStore _inner;
  final bool Function() _cartEmptyNow;
  final List<String> events = [];

  @override
  Future<List<OutboxEntry>> load(String scopeKey) => _inner.load(scopeKey);

  @override
  Future<void> persist(String scopeKey, List<OutboxEntry> entries) {
    events.add('persist(n=${entries.length}, cartEmpty=${_cartEmptyNow()})');
    return _inner.persist(scopeKey, entries);
  }
}

/// A durable store whose every write is refused — the 003B "storage said no"
/// device.
class _RefusingStore implements DurableOutboxStore {
  @override
  Future<List<OutboxEntry>> load(String scopeKey) async => const [];

  @override
  Future<void> persist(String scopeKey, List<OutboxEntry> entries) async {
    throw const PosPersistenceException('refused');
  }
}

class _Harness {
  _Harness({
    required this.container,
    required this.transport,
    required this.l10n,
    required this.ref,
    required this.context,
  });

  final ProviderContainer container;
  final _ScriptedSyncTransport transport;
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
}

Future<void> _settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.microtask(() {});
  }
}

/// Builds the real-mode submit world: signed-in session, verified KDS
/// readiness, real repository over [store] and [transport], one Burger in the
/// cart, and a pumped Scaffold whose context/ref drive the REAL Send handler.
Future<_Harness> _pump(
  WidgetTester tester, {
  required _ScriptedSyncTransport transport,
  required DurableOutboxStore store,
  bool offlineCached = true,
}) async {
  final repo = RealOutboxRepository(transport, _session, store: store);
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
  // The offline OPERATING PHASE: written only by real menu-fetch outcomes in
  // production; recorded directly here because these tests drive the submit
  // seam, not the menu fetch.
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
  container
      .read(cartControllerProvider.notifier)
      .addItem(
        const DemoMenuItem(
          id: 'm1',
          name: 'Burger',
          priceMinor: 4000,
          categoryId: 'cat',
          categoryName: 'Mains',
        ),
      );
  await tester.pump();
  return _Harness(
    container: container,
    transport: transport,
    l10n: l10n,
    ref: capturedRef,
    context: capturedContext,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('spec test 17 — the durable sequence: the order is persisted '
      'BEFORE the cart clears, and the offline presentation fabricates no '
      'server number', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer c;
    final store = _SequencedStore(
      SharedPrefsOutboxStore(prefs),
      () => c.read(cartControllerProvider).isEmpty,
    );
    final h = await _pump(
      tester,
      transport: _ScriptedSyncTransport(const [_offlineFailure]),
      store: store,
    );
    c = h.container;

    await h.submit();
    await tester.pumpAndSettle();

    // The FIRST persist (the enqueue) ran while the cart still held its line.
    expect(store.events, isNotEmpty);
    expect(
      store.events.first,
      'persist(n=1, cartEmpty=false)',
      reason: 'the durable outbox commit must precede the cart clear',
    );
    // Only after the submit settled did the cart clear into the confirmation.
    expect(c.read(cartControllerProvider).isEmpty, isTrue);
    final submitted = c.read(cartControllerProvider).submittedOrder;
    expect(submitted, isNotNull);

    // The queued order is durably on disk despite the unreachable backend.
    final entries = await SharedPrefsOutboxStore(prefs).load(_session.deviceId);
    expect(entries, hasLength(1));
    // An offline push records the transient transport failure; nothing about
    // the ORDER was decided, so it stays retryable and the sweep resubmits it.
    expect(entries.single.outcome, PosOrderOutcome.deliveryUnconfirmed);
    expect(entries.single.hasDefinitiveVerdict, isFalse);

    // NEVER a fabricated server receipt number (D-021): the code shown is the
    // LOCAL display code derived from the client-minted order id, byte-exact.
    expect(submitted!.orderNumber, displayOrderCode(entries.single.targetId));

    // The confirmation renders the honest offline copy under the real entry.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
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
    expect(
      find.byKey(const Key('confirmation-offline-pending')),
      findsOneWidget,
    );
    expect(find.text(h.l10n.posOfflineOrderSavedLocally), findsOneWidget);
    expect(find.text(h.l10n.posOfflineAwaitingSync), findsOneWidget);
    // A kds-dispatch queued order additionally says the KDS sees it on sync.
    expect(find.text(h.l10n.posOfflineKdsPending), findsOneWidget);
    // The rendered order number is the local code — nothing server-assigned.
    final numberText = tester.widget<Text>(
      find.byKey(const Key('order-number')),
    );
    expect(numberText.data, displayOrderCode(entries.single.targetId));
  });

  testWidgets('spec test 18 — a refused durable write keeps the cart intact '
      'and shows the honest failure (no silent loss, no dispatch)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    final transport = _ScriptedSyncTransport(const [_offlineFailure]);
    final h = await _pump(
      tester,
      transport: transport,
      store: _RefusingStore(),
    );

    await h.submit();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // snackbar entrance

    expect(find.text(h.l10n.posSubmitFailed), findsOneWidget);
    final cart = h.container.read(cartControllerProvider);
    expect(cart.isEmpty, isFalse, reason: 'the un-stored cart must survive');
    expect(cart.submittedOrder, isNull, reason: 'no confirmation for a loss');
    expect(
      transport.pushes,
      0,
      reason: 'an order that was never stored is never dispatched',
    );
  });

  testWidgets('spec test 19 — a container restart over the SAME prefs '
      'retains the queued order verbatim', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final h = await _pump(
      tester,
      transport: _ScriptedSyncTransport(const [_offlineFailure]),
      store: SharedPrefsOutboxStore(prefs),
    );
    await h.submit();
    await tester.pumpAndSettle();
    final before = await SharedPrefsOutboxStore(prefs).load(_session.deviceId);
    expect(before, hasLength(1));

    // "Restart": a NEW repository (fresh memory) over the SAME mocked prefs.
    final reloadedRepo = RealOutboxRepository(
      _ScriptedSyncTransport(const [_offlineFailure]),
      _session,
      store: SharedPrefsOutboxStore(prefs),
    );
    final after = await reloadedRepo.recentEntries();
    expect(after, hasLength(1));
    expect(after.single.localOperationId, before.single.localOperationId);
    expect(after.single.payloadJson, before.single.payloadJson);
    expect(after.single.deviceId, _session.deviceId);
  });

  testWidgets('spec test 20 — a rapid double submit while the first is in '
      'flight enqueues exactly ONE operation', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final gate = Completer<void>();
    final transport = _ScriptedSyncTransport(const [
      _offlineFailure,
    ], gate: gate.future);
    final h = await _pump(
      tester,
      transport: transport,
      store: SharedPrefsOutboxStore(prefs),
    );

    // First Send: enqueued, push held in flight on the gate.
    final first = h.submit();
    await tester.pump();
    // Second (impatient) Send while in flight: must JOIN the same submit.
    final second = h.submit();
    await tester.pump();
    gate.complete();
    await first;
    await second;
    await tester.pumpAndSettle();

    final entries = await SharedPrefsOutboxStore(prefs).load(_session.deviceId);
    expect(entries, hasLength(1), reason: 'one op, not two (D-022 identity)');
    expect(transport.pushes, 1, reason: 'one submit -> one push attempt');
    expect(transport.pushedLocalOperationIds.toSet(), hasLength(1));
  });

  testWidgets('spec test 21 — the reconnect flush resubmits the SAME identity '
      'exactly once and settles it applied', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final transport = _ScriptedSyncTransport([
      _offlineFailure,
      <String, Object?>{'ok': true, 'status': 'applied'},
    ]);
    final h = await _pump(
      tester,
      transport: transport,
      store: SharedPrefsOutboxStore(prefs),
    );
    await h.submit();
    await tester.pumpAndSettle();
    expect(transport.pushes, 1);

    // Reconnect: the flush re-queues + re-pushes the failed entry.
    // Pass B: the reconnect/startup flush resets the backoff schedule
    // (order_sync_controller does exactly this on pushFirst) — without the
    // reset the freshly-failed entry would honestly WAIT out its 2s×2^n
    // schedule instead of resubmitting inside this test.
    // (OLD: pushQueued() — there was no schedule to reset.)
    await h.container
        .read(outboxControllerProvider.notifier)
        .pushQueued(resetBackoff: true);
    await tester.pumpAndSettle();

    expect(transport.pushes, 2, reason: 'exactly one resubmission');
    expect(
      transport.pushedLocalOperationIds.toSet(),
      hasLength(1),
      reason: 'the SAME (deviceId, localOperationId) identity both times',
    );
    final entries = h.container.read(outboxControllerProvider);
    expect(entries, hasLength(1));
    expect(entries.single.syncState, OutboxSyncState.applied);
    expect(entries.single.outcome, PosOrderOutcome.accepted);

    // A further sweep spends NOTHING on the already-applied entry.
    await h.container.read(outboxControllerProvider.notifier).pushQueued();
    await tester.pumpAndSettle();
    expect(transport.pushes, 2);
  });

  testWidgets('spec test 22 — an idempotent-replay stored result reconciles '
      'to accepted without a duplicate and without inventing a number', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final transport = _ScriptedSyncTransport([
      _offlineFailure,
      // The server had ALREADY applied this identity before the answer was
      // lost: the replay returns its STORED result, not a fresh insert.
      <String, Object?>{'ok': true, 'status': 'applied', 'replayed': true},
    ]);
    final h = await _pump(
      tester,
      transport: transport,
      store: SharedPrefsOutboxStore(prefs),
    );
    await h.submit();
    await tester.pumpAndSettle();
    final submitted = h.container.read(cartControllerProvider).submittedOrder!;

    // Pass B: reconnect flush resets the backoff (see spec test 21's note).
    await h.container
        .read(outboxControllerProvider.notifier)
        .pushQueued(resetBackoff: true);
    await tester.pumpAndSettle();

    final entries = h.container.read(outboxControllerProvider);
    expect(entries, hasLength(1), reason: 'a replay never mints a duplicate');
    expect(entries.single.outcome, PosOrderOutcome.accepted);
    // The order's number is STILL the local display code of the same id —
    // reconciliation invents no server receipt sequence (D-021).
    expect(submitted.orderNumber, displayOrderCode(entries.single.targetId));
    expect(
      entries.single.summary.orderNumber,
      displayOrderCode(entries.single.targetId),
    );
  });
}
