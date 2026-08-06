// POS-OFFLINE-OPERATIONS-002 — C9 direct-print offline spool identity.
//
// Covers OFFLINE-ARCH-SPEC tests 26, 27, 28, 29, 30, 31:
//   26 — the LOCAL dispatch identity has the exact documented format
//        `local:v1:<deviceId>:<local_operation_id>:kitchen`, and an offline
//        direct_print submit records it durably (`sent` after the transport
//        accepted the bytes) plus the order-scoped `<orderId>|initial` mirror;
//   27 — collision impossibility: the identity is injective over the D-022
//        pair and its namespace is disjoint from server dispatch UUIDs, the
//        plain orderId guard keys, the `orderId|round:` addition keys and the
//        `orderId|initial` keys;
//   28 — the pending print survives a restart: the durable claim (claimed /
//        failed) is what a fresh process reads, a crash-window `claimed`
//        suppresses the automatic re-print, and a `failed` releases exactly
//        one legitimate retry;
//   29 — reconciliation never re-prints: after the queued order syncs
//        (idempotent replay -> applied) the ticket count stays exactly one,
//        and both the local identity and the initial mirror read `sent`;
//   30 — a kds-dispatch branch prints NOTHING locally while offline: no
//        bytes, no claim envelope;
//   31 — direct-print is exactly-once per CONFIRMED send, a LAN-off failure
//        surfaces the failedRetryable claim + the posOfflinePrintPending copy
//        where the print status renders, and a deliberate retry runs again.
//
// Harness: the REAL submit seam over the REAL repository/durable stores with
// a scripted offline sync transport, a VERIFIED printer_only readiness, and a
// captured/throwing kitchen print transport (001d idiom).
import 'dart:convert' show jsonEncode;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/durable_outbox_store.dart';
import 'package:restoflow_pos/src/data/kitchen_mode_readiness.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/data/round_print_claim_store.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_offline_state.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart'
    show posNativePrintingAvailableProvider;
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart'
    show submitOrderFromCart;
import 'package:restoflow_pos/src/widgets/order_confirmation.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
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

const _claimEnvelopeKey = 'restoflow.pos.round_print_claims.v1.device-1';

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

/// The VERIFIED printer_only readiness for the ACTIVE device scope — the state
/// production reaches once the startup heartbeat resolved the branch as
/// printer_only, which is what makes the submit decision `direct_print`.
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

/// The LAN-off printer: every send throws (a network ESC/POS printer with no
/// network). Counts attempts so exactly-once/retry semantics are provable.
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

class _Harness {
  _Harness({
    required this.container,
    required this.prefs,
    required this.claims,
    required this.l10n,
    required this.ref,
    required this.context,
  });

  final ProviderContainer container;
  final SharedPreferences prefs;
  final SharedPrefsRoundPrintClaimStore claims;
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

Future<_Harness> _pump(
  WidgetTester tester, {
  required _ScriptedSyncTransport transport,
  required pp.PrintTransport printTransport,
  bool printerOnly = true,
}) async {
  SharedPreferences.setMockInitialValues({
    'restoflow.printer.selected.pos.kitchen_ticket.device-1': 'network',
    'restoflow.printer.network.pos.kitchen_ticket.device-1': jsonEncode({
      'host': '10.0.0.9',
      'port': 9100,
    }),
  });
  final prefs = await SharedPreferences.getInstance();
  final claims = SharedPrefsRoundPrintClaimStore(prefs)..scopeKey = 'device-1';
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
      if (printerOnly)
        posKitchenModeReadinessProvider.overrideWith(_PrinterOnlyReadiness.new)
      else
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
  container
      .read(posOfflineModeProvider.notifier)
      .recordOfflineCacheServed(snapshotFetchedAt: DateTime.utc(2026, 8, 6));

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
    prefs: prefs,
    claims: claims,
    l10n: l10n,
    ref: capturedRef,
    context: capturedContext,
  );
}

String _localKeyOf(OutboxEntry entry) => posLocalKitchenDispatchClaimKey(
  deviceId: entry.deviceId,
  localOperationId: entry.localOperationId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('spec test 26 — the local dispatch identity format, recorded '
      'durably by an offline direct-print submit', (tester) async {
    expect(
      posLocalKitchenDispatchClaimKey(
        deviceId: 'device-1',
        localOperationId: 'op-7',
      ),
      'local:v1:device-1:op-7:kitchen',
    );

    final capture = _CapturingPrintTransport();
    final h = await _pump(
      tester,
      transport: _ScriptedSyncTransport(const [_offlineFailure]),
      printTransport: capture,
    );
    await h.submit();
    await tester.pumpAndSettle();

    final entry = h.entry;
    expect(entry.isDirectPrintOrderSubmit, isTrue);
    expect(capture.sent, hasLength(1), reason: 'exactly one physical ticket');
    // The durable claim under the DOCUMENTED local identity is settled `sent`,
    // and the order-scoped initial mirror is recorded alongside it.
    expect(h.claims.claimOf(_localKeyOf(entry)), PosRoundPrintClaimState.sent);
    expect(
      h.claims.claimOf(posInitialKitchenPrintClaimKey(entry.targetId)),
      PosRoundPrintClaimState.sent,
    );
  });

  test('spec test 27 — cross-device collision impossibility: injective over '
      'the D-022 pair, namespace-disjoint from every other print identity', () {
    String local(String device, String op) =>
        posLocalKitchenDispatchClaimKey(deviceId: device, localOperationId: op);

    // Injective: any difference in EITHER component changes the key.
    expect(local('dev-A', 'op-1'), isNot(local('dev-B', 'op-1')));
    expect(local('dev-A', 'op-1'), isNot(local('dev-A', 'op-2')));
    expect(local('dev-A', 'op-1'), local('dev-A', 'op-1'));

    // Namespace disjointness. Server dispatch ids and client order ids are
    // UUIDs — no UUID starts with the reserved `local:v1:` prefix, so a local
    // key can never equal a server dispatch id, a plain orderId guard key, an
    // addition key (`<uuid>|round:<uuid>`) or an initial key (`<uuid>|initial`).
    const orderId = '4c7d2f10-1111-2222-3333-abcdefabc123';
    final key = local('device-1', orderId); // even built FROM uuids
    expect(key, startsWith('local:v1:'));
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
    );
    expect(uuid.hasMatch(key), isFalse);
    expect(key, isNot(orderId));
    expect(key, isNot(posInitialKitchenPrintClaimKey(orderId)));
    expect(
      key,
      isNot(
        posAdditionKitchenPrintGuardKey(orderId: orderId, roundId: orderId),
      ),
    );
    expect(posInitialKitchenPrintClaimKey(orderId), '$orderId|initial');
  });

  testWidgets('spec test 28 — the pending print survives a restart: a crash-'
      'window `claimed` suppresses the automatic re-print; a `failed` releases '
      'one legitimate retry', (tester) async {
    final printer = _ThrowingPrintTransport();
    final h = await _pump(
      tester,
      transport: _ScriptedSyncTransport(const [_offlineFailure]),
      printTransport: printer,
    );
    await h.submit();
    await tester.pumpAndSettle();

    final localKey = _localKeyOf(h.entry);
    expect(printer.attempts, 1);
    // The failure settled the durable claim to `failed` (released) — and it is
    // REALLY on disk, under the scope-partitioned envelope.
    expect(h.claims.claimOf(localKey), PosRoundPrintClaimState.failed);
    expect(h.prefs.getString(_claimEnvelopeKey), isNotNull);

    // "Restart": a FRESH store over the same prefs reads the same claim.
    final reloaded = SharedPrefsRoundPrintClaimStore(h.prefs)
      ..scopeKey = 'device-1';
    expect(reloaded.claimOf(localKey), PosRoundPrintClaimState.failed);

    // A released (`failed`) claim admits exactly one legitimate retry...
    var attempts = 0;
    final guard = PosAutoKitchenPrintGuard(claims: reloaded);
    final retried = await guard.runGuarded(localKey, () async {
      attempts++;
      return PosKitchenPrintOutcome.printed;
    });
    expect(retried, PosKitchenPrintOutcome.printed);
    expect(attempts, 1);
    expect(reloaded.claimOf(localKey), PosRoundPrintClaimState.sent);

    // ...while a crash-window `claimed` (committed, never settled) SUPPRESSES
    // the automatic send after restart — a ticket may already be at the
    // printer, and printing again to be sure is exactly the duplicate.
    const crashKey = 'local:v1:device-1:op-crashed:kitchen';
    await reloaded.record(crashKey, PosRoundPrintClaimState.claimed);
    final afterCrash = SharedPrefsRoundPrintClaimStore(h.prefs)
      ..scopeKey = 'device-1';
    var crashAttempts = 0;
    final suppressed = await PosAutoKitchenPrintGuard(claims: afterCrash)
        .runGuarded(crashKey, () async {
          crashAttempts++;
          return PosKitchenPrintOutcome.printed;
        });
    expect(suppressed, PosKitchenPrintOutcome.printed);
    expect(crashAttempts, 0, reason: 'claimed must suppress the re-print');
  });

  testWidgets('spec test 29 — reconciliation never re-prints: after the '
      'queued order syncs (idempotent replay) the count stays exactly one', (
    tester,
  ) async {
    final capture = _CapturingPrintTransport();
    final h = await _pump(
      tester,
      transport: _ScriptedSyncTransport([
        _offlineFailure,
        <String, Object?>{'ok': true, 'status': 'applied', 'replayed': true},
      ]),
      printTransport: capture,
    );
    await h.submit();
    await tester.pumpAndSettle();
    expect(capture.sent, hasLength(1));
    final localKey = _localKeyOf(h.entry);
    final initialKey = posInitialKitchenPrintClaimKey(h.entry.targetId);

    // Reconnect: the sweep resubmits the SAME identity; the server replays
    // its stored result and the entry settles applied.
    await h.container.read(outboxControllerProvider.notifier).pushQueued();
    await tester.pumpAndSettle();
    expect(h.entry.syncState, OutboxSyncState.applied);

    // NOTHING re-printed on reconciliation, and both claims read `sent`.
    expect(capture.sent, hasLength(1));
    expect(h.claims.claimOf(localKey), PosRoundPrintClaimState.sent);
    expect(h.claims.claimOf(initialKey), PosRoundPrintClaimState.sent);

    // Even a stray duplicate invocation of the offline print (same identity)
    // sends nothing further — in-memory AND durable dedupe agree.
    final again = await runOfflineDirectPrintKitchenTicket(
      container: h.container,
      orderId: h.entry.targetId,
      localDispatchClaimKey: localKey,
      ticket: kdsTicketViewFromCartLines(
        orderCode: h.entry.summary.orderNumber,
        orderType: OrderType.takeaway,
        lines: const [
          CartLineView(
            lineId: 'l1',
            menuItemId: 'm1',
            name: 'Burger',
            quantity: 1,
            unitPriceMinor: 4000,
            lineTotalMinor: 4000,
            currencyCode: 'ILS',
          ),
        ],
      ),
      labels: kitchenTicketPrintLabelsFromL10n(h.l10n),
    );
    expect(again, PosKitchenPrintOutcome.printed);
    expect(capture.sent, hasLength(1), reason: 'no duplicate ticket, ever');
  });

  testWidgets('spec test 30 — a kds-dispatch branch prints NOTHING locally '
      'while offline: no bytes, no claim envelope', (tester) async {
    final capture = _CapturingPrintTransport();
    final h = await _pump(
      tester,
      transport: _ScriptedSyncTransport(const [_offlineFailure]),
      printTransport: capture,
      printerOnly: false,
    );
    await h.submit();
    await tester.pumpAndSettle();

    expect(h.entry.isDirectPrintOrderSubmit, isFalse);
    expect(capture.sent, isEmpty, reason: 'the KDS owns the ticket');
    expect(
      h.prefs.getString(_claimEnvelopeKey),
      isNull,
      reason: 'no local dispatch claim exists for a kds order',
    );
  });

  testWidgets('spec test 31 — LAN-off: exactly one automatic attempt, the '
      'failedRetryable claim, the pending copy where the print status '
      'renders, and a deliberate retry that runs again', (tester) async {
    final printer = _ThrowingPrintTransport();
    final h = await _pump(
      tester,
      transport: _ScriptedSyncTransport(const [_offlineFailure]),
      printTransport: printer,
    );
    await h.submit();
    await tester.pumpAndSettle();

    final entry = h.entry;
    final localKey = _localKeyOf(entry);
    expect(printer.attempts, 1, reason: 'one automatic attempt, no loop');
    expect(h.claims.claimOf(localKey), PosRoundPrintClaimState.failed);
    // NEVER a fake success: no `sent`, no initial mirror.
    expect(
      h.claims.claimOf(posInitialKitchenPrintClaimKey(entry.targetId)),
      isNull,
    );

    // The confirmation surface — where the print status renders — carries the
    // pending-print copy (and NOT the kds-pending line: this order's frozen
    // payload is direct_print).
    final submitted = h.container.read(cartControllerProvider).submittedOrder!;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
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
      find.byKey(const Key('confirmation-offline-print-pending')),
      findsOneWidget,
    );
    expect(find.text(h.l10n.posOfflinePrintPending), findsOneWidget);
    expect(find.text(h.l10n.posOfflineKdsPending), findsNothing);
    expect(find.text(h.l10n.posOfflineOrderSavedLocally), findsOneWidget);

    // The failure RELEASED the round: a deliberate retry genuinely runs
    // (attempt 2) — a failed print never permanently suppresses the ticket.
    final retry = await runOfflineDirectPrintKitchenTicket(
      container: h.container,
      orderId: entry.targetId,
      localDispatchClaimKey: localKey,
      ticket: kdsTicketViewFromCartLines(
        orderCode: entry.summary.orderNumber,
        orderType: OrderType.takeaway,
        lines: const [
          CartLineView(
            lineId: 'l1',
            menuItemId: 'm1',
            name: 'Burger',
            quantity: 1,
            unitPriceMinor: 4000,
            lineTotalMinor: 4000,
            currencyCode: 'ILS',
          ),
        ],
      ),
      labels: kitchenTicketPrintLabelsFromL10n(h.l10n),
    );
    expect(retry, PosKitchenPrintOutcome.failed);
    expect(printer.attempts, 2);
    expect(h.claims.claimOf(localKey), PosRoundPrintClaimState.failed);
  });
}
