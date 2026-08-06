// [POS-OFFLINE-OPERATIONS-002] Pass C — owed-kitchen-ticket recovery.
//
// Pins the four hardening fixes on top of the C9 offline direct-print seam:
//   B1 — a REFUSED durable claim write no longer withholds the physical
//        attempt: the cart still clears, the order stays committed, the print
//        runs under the in-memory guard, and the pending/failed outcome is
//        visible on the confirmation through the session-only claim overlay;
//   B2 — an owed ticket (claim claimed/failed) is recoverable from the
//        RECENT-ORDERS surface, after a full process restart (new container
//        over the same durable stores), printing exactly once and settling
//        the local + initial-mirror claims to `sent`;
//   B3 — the confirmation's pending-print notice is CLAIM-driven: a failed
//        print stays visible even when the offline phase flips back to
//        `online`;
//   C2 — `runPreclaimed` consults the durable claim: `sent` suppresses any
//        second send (idempotent), `claimed`/`failed` still proceed (fresh
//        submit / deliberate crash-recovery re-attempt).
//
// Harness: the REAL submit seam over the REAL repository/durable stores with
// a scripted offline sync transport, a VERIFIED printer_only readiness, and a
// captured/throwing kitchen print transport (the pos_offline_print_test
// idiom), plus the REAL RecentOrdersSheet over a durable recent-orders store.
import 'dart:convert' show jsonEncode;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/durable_outbox_store.dart';
import 'package:restoflow_pos/src/data/kitchen_mode_readiness.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/round_print_claim_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosPersistenceException;
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_offline_state.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart'
    show posNativePrintingAvailableProvider;
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart'
    show submitOrderFromCart;
import 'package:restoflow_pos/src/widgets/order_confirmation.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

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

const _claimEnvelopeKey = 'restoflow.pos.round_print_claims.v1.device-1';

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

final class _PrinterOnlyReadiness extends PosKitchenModeReadinessController {
  @override
  PosKitchenModeReadiness build() => KitchenModeReadinessResolved(
    KitchenModePrinterOnlyWithRevision(
      revision: 4,
      verifiedAt: DateTime.utc(2026, 8, 1, 9),
    ),
    PosKitchenModeScopeKey.fromContext(ref.watch(posDeviceContextProvider)),
  );
}

class _ScriptedSyncTransport implements SyncRpcTransport {
  _ScriptedSyncTransport(this.steps);

  final List<Object> steps;
  int pushes = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'start_pin_session') return 'pin-session-1';
    if (function != 'sync_push') return null;
    final op = (params['p_operations'] as List).first as Map;
    if (op['operation_type'] != 'order.submit') {
      return <String, dynamic>{'ok': true, 'results': <dynamic>[]};
    }
    final step = steps[pushes < steps.length ? pushes : steps.length - 1];
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

class _CapturingPrintTransport implements pp.PrintTransport {
  final List<Uint8List> sent = [];

  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    sent.add(bytes);
    return const pp.PrintResult.success();
  }

  @override
  Future<void> dispose() async {}
}

class _ThrowingPrintTransport implements pp.PrintTransport {
  int attempts = 0;

  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    attempts++;
    throw Exception('LAN unreachable');
  }

  @override
  Future<void> dispose() async {}
}

/// B1: a claim store whose READS work but whose WRITES are refused — the
/// storage-unhealthy till (setString returning false / preserve failure).
final class _RefusingClaimStore implements PosRoundPrintClaimStore {
  int refusals = 0;

  @override
  PosRoundPrintClaimState? claimOf(String key) => null;

  @override
  Future<void> record(String key, PosRoundPrintClaimState state) async {
    refusals++;
    throw const PosPersistenceException('refused (test)');
  }
}

class _Harness {
  _Harness({
    required this.container,
    required this.prefs,
    required this.l10n,
    required this.ref,
    required this.context,
  });

  final ProviderContainer container;
  final SharedPreferences prefs;
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
}

Future<void> _settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.microtask(() {});
  }
}

/// A fresh durable claim store over [prefs], bound to this device's scope —
/// the restart idiom (a new process reads the same envelope).
SharedPrefsRoundPrintClaimStore _sharedPrefsClaims(SharedPreferences prefs) =>
    SharedPrefsRoundPrintClaimStore(prefs)..scopeKey = 'device-1';

Future<ProviderContainer> _bootContainer({
  required _ScriptedSyncTransport transport,
  required PosRoundPrintClaimStore claims,
  required pp.PrintTransport printTransport,
  required SharedPreferences prefs,
}) async {
  final repo = RealOutboxRepository(
    transport,
    _session,
    store: SharedPrefsOutboxStore(prefs),
  );
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport),
      posRealSessionConfigProvider.overrideWithValue(null),
      outboxRepositoryProvider.overrideWithValue(repo),
      posMenuProvider.overrideWith((ref) => ref.watch(_menuSource)),
      posNativePrintingAvailableProvider.overrideWithValue(true),
      posRoundPrintClaimStoreProvider.overrideWithValue(claims),
      kitchenPrintTransportOverrideProvider.overrideWithValue(
        (_) => printTransport,
      ),
      posKitchenModeReadinessProvider.overrideWith(_PrinterOnlyReadiness.new),
      // Durable recent orders + a quiet sync loop, so the recovery surface is
      // exercisable across a container restart without a polling timer.
      posRecentOrdersStoreProvider.overrideWithValue(
        SharedPrefsRecentOrdersStore(prefs),
      ),
      orderSnapshotRepositoryProvider.overrideWithValue(
        DemoOrderSnapshotRepository(),
      ),
      posSyncPollIntervalProvider.overrideWithValue(null),
    ],
  );
  addTearDown(() {
    // A test may "restart" by simply abandoning this container; teardown
    // disposes whichever containers are still live (idempotent via flag).
    if (!_disposedContainers.contains(container)) {
      _disposedContainers.add(container);
      container.dispose();
    }
  });
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
  container
      .read(posOfflineModeProvider.notifier)
      .recordOfflineCacheServed(snapshotFetchedAt: DateTime.utc(2026, 8, 6));
  return container;
}

final _disposedContainers = <ProviderContainer>{};

/// Pumps the submit host (a plain Consumer scaffold) for [container] and
/// returns the captured ref/context the real submit seam needs.
Future<(WidgetRef, BuildContext)> _pumpHost(
  WidgetTester tester,
  ProviderContainer container,
) async {
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
  return (capturedRef, capturedContext);
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required _ScriptedSyncTransport transport,
  required pp.PrintTransport printTransport,
  PosRoundPrintClaimStore Function(SharedPreferences prefs)? claimsFactory,
}) async {
  SharedPreferences.setMockInitialValues({
    'restoflow.printer.selected.pos.kitchen_ticket.device-1': 'network',
    'restoflow.printer.network.pos.kitchen_ticket.device-1': jsonEncode({
      'host': '10.0.0.9',
      'port': 9100,
    }),
  });
  final prefs = await SharedPreferences.getInstance();
  final container = await _bootContainer(
    transport: transport,
    claims: (claimsFactory ?? _sharedPrefsClaims)(prefs),
    printTransport: printTransport,
    prefs: prefs,
  );
  final l10n = await AppLocalizations.delegate.load(const Locale('en'));
  final (ref, context) = await _pumpHost(tester, container);
  container.read(cartControllerProvider.notifier).addItem(_burger);
  await tester.pump();
  return _Harness(
    container: container,
    prefs: prefs,
    l10n: l10n,
    ref: ref,
    context: context,
  );
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

Future<void> _pumpRecentOrdersSheet(
  WidgetTester tester,
  ProviderContainer container,
) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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

String _localKeyOf(OutboxEntry entry) => posLocalKitchenDispatchClaimKey(
  deviceId: entry.deviceId,
  localOperationId: entry.localOperationId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_disposedContainers.clear);

  testWidgets('B1 — a refused claim write no longer withholds the print: the '
      'cart clears, the order is committed, the attempt runs in-memory '
      'guarded, a second submit is unaffected, and the FAILED outcome '
      'renders the pending notice', (tester) async {
    final refusing = _RefusingClaimStore();
    final printer = _ThrowingPrintTransport();
    final h = await _pump(
      tester,
      transport: _ScriptedSyncTransport(const [_offlineFailure]),
      printTransport: printer,
      claimsFactory: (_) => refusing,
    );
    await h.submit();
    await tester.pumpAndSettle();

    // Order committed + cart cleared, exactly like a healthy-store submit.
    final entry = h.entry;
    expect(entry.isDirectPrintOrderSubmit, isTrue);
    expect(h.container.read(cartControllerProvider).isEmpty, isTrue);
    expect(h.container.read(cartControllerProvider).submittedOrder, isNotNull);
    // The durable commit WAS refused — and the print was still attempted.
    expect(refusing.refusals, greaterThan(0));
    expect(printer.attempts, 1, reason: 'the kitchen must still be attempted');
    // Nothing durable exists (the store refused every write).
    expect(h.prefs.getString(_claimEnvelopeKey), isNull);

    // A second submit is unaffected: its own fresh identity prints again.
    h.container.read(cartControllerProvider.notifier).addItem(_burger);
    await tester.pump();
    await h.submit();
    await tester.pumpAndSettle();
    expect(printer.attempts, 2);
    expect(h.container.read(cartControllerProvider).isEmpty, isTrue);
    expect(h.container.read(outboxControllerProvider), hasLength(2));

    // The FAILED outcome is VISIBLE: the session-only overlay drives the
    // confirmation's pending-print notice even though the store held nothing.
    await _pumpConfirmation(tester, h.container);
    expect(
      find.byKey(const Key('confirmation-offline-print-pending')),
      findsOneWidget,
    );
    expect(find.text(h.l10n.posOfflinePrintPending), findsOneWidget);
  });

  testWidgets('B1 — refused claim write with a WORKING printer: exactly one '
      'physical send, and NO pending notice (the overlay settled `sent`)', (
    tester,
  ) async {
    final refusing = _RefusingClaimStore();
    final capture = _CapturingPrintTransport();
    final h = await _pump(
      tester,
      transport: _ScriptedSyncTransport(const [_offlineFailure]),
      printTransport: capture,
      claimsFactory: (_) => refusing,
    );
    await h.submit();
    await tester.pumpAndSettle();

    expect(capture.sent, hasLength(1));
    await _pumpConfirmation(tester, h.container);
    expect(
      find.byKey(const Key('confirmation-offline-print-pending')),
      findsNothing,
      reason: 'a confirmed in-session send owes the kitchen nothing',
    );
  });

  testWidgets('B3 — a failed print stays visible when the phase is ONLINE: '
      'the pending notice is claim-driven, not phase-driven', (tester) async {
    final printer = _ThrowingPrintTransport();
    final h = await _pump(
      tester,
      transport: _ScriptedSyncTransport(const [_offlineFailure]),
      printTransport: printer,
    );
    await h.submit();
    await tester.pumpAndSettle();
    expect(printer.attempts, 1);
    expect(
      _sharedPrefsClaims(h.prefs).claimOf(_localKeyOf(h.entry)),
      PosRoundPrintClaimState.failed,
    );

    // The phase flips back to online (a later fetch succeeded) — the ticket
    // is still owed and the notice must keep saying so.
    h.container.read(posOfflineModeProvider.notifier).recordOnlineFetch();
    await tester.pumpAndSettle();

    await _pumpConfirmation(tester, h.container);
    expect(
      find.byKey(const Key('confirmation-offline-print-pending')),
      findsOneWidget,
      reason: 'the owed print must not vanish behind an online phase',
    );
    expect(find.text(h.l10n.posOfflinePrintPending), findsOneWidget);
    // The phase-gated offline SYNC lines are correctly gone — only the
    // claim-driven print line survived the phase flip.
    expect(find.byKey(const Key('confirmation-offline-saved')), findsNothing);
  });

  testWidgets('B2 — recent-orders recovery after a RESTART: the owed ticket '
      'shows the print action, prints exactly once, settles both claims and '
      'the action disappears', (tester) async {
    final printer = _ThrowingPrintTransport();
    final h = await _pump(
      tester,
      transport: _ScriptedSyncTransport(const [_offlineFailure]),
      printTransport: printer,
    );
    final prefs = h.prefs;
    await h.submit();
    await tester.pumpAndSettle();
    final entry = h.entry;
    final localKey = _localKeyOf(entry);
    final orderNumber = entry.summary.orderNumber;
    // The transport-failing printer left the DURABLE claim `failed` (owed).
    expect(
      _sharedPrefsClaims(prefs).claimOf(localKey),
      PosRoundPrintClaimState.failed,
    );
    expect(printer.attempts, 1);

    // "RESTART": a NEW container over the SAME durable stores — fresh
    // in-memory everything; the outbox entry, claim, and recent order are
    // read back from disk. The old container is simply abandoned.
    final capture = _CapturingPrintTransport();
    final restarted = await _bootContainer(
      transport: _ScriptedSyncTransport(const [_offlineFailure]),
      claims: _sharedPrefsClaims(prefs),
      printTransport: capture,
      prefs: prefs,
    );
    // A restart alone prints NOTHING automatically (auto print fires only on
    // a fresh submit; the durable claim suppresses replays).
    await tester.pump();
    expect(capture.sent, isEmpty);

    await _pumpRecentOrdersSheet(tester, restarted);
    final action = find.byKey(Key('recent-print-kitchen-$orderNumber'));
    expect(action, findsOneWidget, reason: 'the owed ticket offers recovery');

    await tester.tap(action);
    await tester.pumpAndSettle();

    // Exactly one physical send; both durable claims settled `sent`.
    expect(capture.sent, hasLength(1));
    final claims = _sharedPrefsClaims(prefs);
    expect(claims.claimOf(localKey), PosRoundPrintClaimState.sent);
    expect(
      claims.claimOf(posInitialKitchenPrintClaimKey(entry.targetId)),
      PosRoundPrintClaimState.sent,
    );
    // The debt is paid — the action is gone.
    expect(action, findsNothing);
  });

  testWidgets('B2 — crash-mid-print (`claimed` left behind) after a restart: '
      'the recent-orders action is visible and prints exactly once', (
    tester,
  ) async {
    final printer = _ThrowingPrintTransport();
    final h = await _pump(
      tester,
      transport: _ScriptedSyncTransport(const [_offlineFailure]),
      printTransport: printer,
    );
    final prefs = h.prefs;
    await h.submit();
    await tester.pumpAndSettle();
    final entry = h.entry;
    final localKey = _localKeyOf(entry);
    // Synthesize the crash window: a prior run committed `claimed` and died
    // before settling (overwrite the settled `failed` from the live attempt).
    await _sharedPrefsClaims(
      prefs,
    ).record(localKey, PosRoundPrintClaimState.claimed);

    final capture = _CapturingPrintTransport();
    final restarted = await _bootContainer(
      transport: _ScriptedSyncTransport(const [_offlineFailure]),
      claims: _sharedPrefsClaims(prefs),
      printTransport: capture,
      prefs: prefs,
    );
    await tester.pump();
    expect(capture.sent, isEmpty, reason: 'claimed suppresses every replay');

    await _pumpRecentOrdersSheet(tester, restarted);
    final action = find.byKey(
      Key('recent-print-kitchen-${entry.summary.orderNumber}'),
    );
    expect(action, findsOneWidget);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(capture.sent, hasLength(1), reason: 'exactly one deliberate send');
    expect(
      _sharedPrefsClaims(prefs).claimOf(localKey),
      PosRoundPrintClaimState.sent,
    );
  });

  test('C2 — runPreclaimed consults the durable claim: `sent` suppresses the '
      'second send; `claimed` (crash re-attempt) and `failed` (released) '
      'still proceed', () async {
    final claims = InMemoryRoundPrintClaimStore();
    final guard = PosAutoKitchenPrintGuard(claims: claims);
    var attempts = 0;
    Future<PosKitchenPrintOutcome> attempt() async {
      attempts++;
      return PosKitchenPrintOutcome.printed;
    }

    // `sent` => idempotent printed, ZERO sends — even with a FRESH guard
    // whose in-memory state knows nothing.
    await claims.record('k-sent', PosRoundPrintClaimState.sent);
    expect(
      await guard.runPreclaimed('k-sent', attempt),
      PosKitchenPrintOutcome.printed,
    );
    expect(attempts, 0);

    // `claimed` (a PRIOR run's crash window, re-entered via a deliberate
    // manual surface) proceeds — that re-attempt is the recovery contract.
    await claims.record('k-claimed', PosRoundPrintClaimState.claimed);
    expect(
      await guard.runPreclaimed('k-claimed', attempt),
      PosKitchenPrintOutcome.printed,
    );
    expect(attempts, 1);

    // `failed` was released — a retry proceeds.
    await claims.record('k-failed', PosRoundPrintClaimState.failed);
    expect(
      await guard.runPreclaimed('k-failed', attempt),
      PosKitchenPrintOutcome.printed,
    );
    expect(attempts, 2);
  });
}
