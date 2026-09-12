// PAYMENT-ATTEMPT-RECOVERY-001 (BCA-MONEY-001) — the CASHIER-FACING sheet.
//
// Recovery mode, the three bounded actions (Check status / Resume same
// attempt / Close and resume later), the honest wording in AR/HE/EN, the
// at-most-once AUTOMATIC receipt/drawer triggers across the effect crash
// windows (R14), the order-row chip (R16), and the "no second tender" rule.
//
// The sheet is opened through `CashPaymentSheet.show` (the ONE production
// entry point) over the REAL controller/repository/store, a contract-faithful
// stateful server fake, a RECORDING drawer service (counts kicks, sends
// nothing) and a COUNTING order-detail repository (counts how many times the
// automatic receipt was attempted; never prints). Physical paper and drawer
// movement are NOT observed here — by design.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_identity.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_attempt_store.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/print/pos_cash_drawer_service.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:restoflow_pos/src/state/pos_session.dart'
    show
        posAuthTransportProvider,
        posSignedInEmployeeProfileIdProvider,
        posSyncSessionProvider;
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/cash_payment_sheet.dart';
import 'package:restoflow_pos/src/widgets/order_action_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/failing_prefs.dart';
import 'support/payment_attempt_server_fake.dart';

class _CountingIds implements ClientIdGenerator {
  _CountingIds(this._prefix);
  final String _prefix;
  int calls = 0;

  @override
  String newId() => '$_prefix-id-${++calls}';
}

/// Records every AUTOMATIC drawer trigger; sends nothing to hardware.
class _RecordingDrawerService extends PosCashDrawerService {
  _RecordingDrawerService(super.ref);
  final List<CashPayment> kicks = <CashPayment>[];

  @override
  Future<PosCashDrawerOutcome> kickForPayment(CashPayment payment) async {
    kicks.add(payment);
    return PosCashDrawerOutcome.sent;
  }
}

/// Counts how many times the AUTOMATIC receipt path went looking for the
/// authoritative receipt source (the first thing it does); never prints.
class _CountingDetailRepo implements OrderDetailRepository {
  int fetches = 0;

  @override
  Future<PosOrderDetail> fetch(String orderId) async {
    fetches++;
    throw const PosOrderDetailException(PosOrderDetailFailure.transport);
  }
}

/// Fails writes AFTER N successful ones (the acceptance-save crash window).
class _FailAfterPrefs implements SharedPreferences {
  _FailAfterPrefs(this._inner, this.failAfter);
  final SharedPreferences _inner;
  final int failAfter;
  int writes = 0;

  @override
  Future<bool> setString(String key, String value) async {
    writes++;
    if (writes > failAfter) return false;
    return _inner.setString(key, value);
  }

  @override
  String? getString(String key) => _inner.getString(key);

  @override
  Future<bool> remove(String key) => _inner.remove(key);

  @override
  bool containsKey(String key) => _inner.containsKey(key);

  @override
  Set<String> getKeys() => _inner.getKeys();

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused: ${invocation.memberName}');
}

const _scopeA = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-A',
  deviceId: 'device-A',
);
const _scopeB = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-A',
  deviceId: 'device-B',
);

final _pinnedNow = DateTime.utc(2026, 9, 8, 12);

PosOrderSnapshot _snapshot({PosSettlement settlement = PosSettlement.unpaid}) =>
    PosOrderSnapshot(
      orderId: 'order-1',
      orderCode: '#A1',
      revision: 3,
      status: 'submitted',
      settlement: settlement,
      subtotalMinor: 4000,
      discountTotalMinor: 0,
      taxTotalMinor: 0,
      grandTotalMinor: 4000,
      createdAt: _pinnedNow.subtract(const Duration(hours: 1)),
      updatedAt: _pinnedNow.subtract(const Duration(minutes: 50)),
      syncAt: _pinnedNow.subtract(const Duration(minutes: 50)),
      orderType: 'takeaway',
      currencyCode: 'ILS',
    );

class _World {
  _World({
    required this.container,
    required this.server,
    required this.drawer,
    required this.detail,
    required this.snapshots,
    required this.ids,
  });
  final ProviderContainer container;
  final PaymentAttemptServerFake server;
  final _RecordingDrawerService drawer;
  final _CountingDetailRepo detail;
  final DemoOrderSnapshotRepository snapshots;
  final _CountingIds ids;

  /// The result the LAST `CashPaymentSheet.show` resolved with, or null while
  /// it is still open.
  bool? lastResult;
}

_World _world({
  required PaymentAttemptServerFake server,
  required SharedPreferences prefs,
  PosSyncScope scope = _scopeA,
  String employee = 'emp-1',
  String pinSession = 'pin-A',
  DemoOrderSnapshotRepository? snapshots,
}) {
  final ids = _CountingIds(scope.deviceId);
  final detail = _CountingDetailRepo();
  final snaps = snapshots ?? DemoOrderSnapshotRepository(seed: [_snapshot()]);
  late _RecordingDrawerService drawer;
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(server),
      posSyncSessionProvider.overrideWithValue(
        SyncSession(pinSessionId: pinSession, deviceId: scope.deviceId),
      ),
      posSyncScopeProvider.overrideWithValue(scope),
      clientIdGeneratorProvider.overrideWithValue(ids),
      paymentAttemptStoreProvider.overrideWithValue(
        SharedPrefsPaymentAttemptStore(prefs),
      ),
      posRecentOrdersStoreProvider.overrideWithValue(
        InMemoryRecentOrdersStore(),
      ),
      orderSnapshotRepositoryProvider.overrideWithValue(snaps),
      orderDetailRepositoryProvider.overrideWithValue(detail),
      posCashDrawerServiceProvider.overrideWith((ref) {
        drawer = _RecordingDrawerService(ref);
        return drawer;
      }),
      posSyncPollIntervalProvider.overrideWithValue(null),
      posSyncClockProvider.overrideWithValue(() => _pinnedNow),
    ],
  );
  addTearDown(container.dispose);
  container.read(posSignedInEmployeeProfileIdProvider.notifier).set(employee);
  // Materialise the drawer recorder now.
  container.read(posCashDrawerServiceProvider);
  return _World(
    container: container,
    server: server,
    drawer: drawer,
    detail: detail,
    snapshots: snaps,
    ids: ids,
  );
}

PaymentAttemptServerFake _server({
  Iterable<String> shifts = const {'device-A'},
}) => PaymentAttemptServerFake(
  orders: [
    FakeServerOrder(orderId: 'order-1', grandTotalMinor: 4000, revision: 3),
  ],
  devicesWithOpenShift: shifts,
);

Future<SharedPreferences> _freshPrefs() async {
  SharedPreferences.setMockInitialValues(const {});
  return SharedPreferences.getInstance();
}

void _size(WidgetTester tester, {Size size = const Size(1200, 2200)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// A host with the ONE production entry point behind a button.
Future<void> _pumpHost(
  WidgetTester tester,
  _World w, {
  String locale = 'en',
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: w.container,
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                key: const Key('open-pay'),
                onPressed: () async {
                  w.lastResult = null;
                  w.lastResult = await CashPaymentSheet.show(
                    context,
                    identity: PosOrderIdentity.server('order-1'),
                    orderNumber: '#A1',
                    amountMinor: 4000,
                    currencyCode: 'ILS',
                    orderId: 'order-1',
                    expectedRevision: 3,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open-pay')));
  await tester.pumpAndSettle();
  expect(find.byType(CashPaymentSheet), findsOneWidget);
}

Future<void> _confirmCash(
  WidgetTester tester, [
  String amount = '50.00',
]) async {
  await tester.enterText(find.byKey(const Key('cash-received-field')), amount);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('confirm-payment-button')));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void _expectRecoveryMode(WidgetTester tester, {bool resumable = true}) {
  expect(find.byKey(const Key('confirm-payment-button')), findsNothing);
  expect(find.byKey(const Key('cash-received-field')), findsNothing);
  expect(find.byKey(const Key('tender-card')), findsNothing);
  expect(find.byKey(const Key('payment-previous-attempt')), findsOneWidget);
  expect(find.byKey(const Key('payment-check-status-button')), findsOneWidget);
  expect(
    find.byKey(const Key('payment-resume-attempt-button')),
    resumable ? findsOneWidget : findsNothing,
  );
  expect(
    find.byKey(const Key('payment-close-resume-later-button')),
    findsOneWidget,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // S1-R3 / F001: the physical-key trust boundary is deliberately isolate-wide
  // and impossible to clear at runtime, so each test starts from a clean one.
  setUp(resetPaymentAttemptKeyGuardsForTest);

  testWidgets('S1 a lost reply puts the sheet in RECOVERY MODE: honest '
      'wording, frozen attempt, three actions, no Confirm', (tester) async {
    _size(tester);
    final prefs = await _freshPrefs();
    final w = _world(server: _server(), prefs: prefs);
    await _pumpHost(tester, w);
    await _open(tester);
    w.server.faultNext(ServerFault.dropResponseAfterCommit);
    await _confirmCash(tester);

    expect(find.byKey(const Key('payment-unconfirmed-banner')), findsOneWidget);
    expect(find.byKey(const Key('payment-failed-banner')), findsNothing);
    _expectRecoveryMode(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.posPaymentUnconfirmedTitle), findsOneWidget);
    expect(find.text(l10n.posPaymentUnconfirmedBody), findsOneWidget);
    expect(find.text(l10n.posPaymentResumeAttempt), findsOneWidget);
    expect(find.textContaining('50.00'), findsWidgets);
    expect(w.drawer.kicks, isEmpty, reason: 'no effect for an unknown result');
    expect(w.detail.fetches, 0);
    expect(w.server.completedPaymentsFor('order-1'), 1);
  });

  testWidgets('S1b the recovery layout holds on a compact phone width', (
    tester,
  ) async {
    _size(tester, size: const Size(390, 844));
    final prefs = await _freshPrefs();
    final w = _world(server: _server(), prefs: prefs);
    await _pumpHost(tester, w);
    await _open(tester);
    w.server.faultNext(ServerFault.dropResponseAfterCommit);
    await _confirmCash(tester);
    _expectRecoveryMode(tester);
    expect(tester.takeException(), isNull, reason: 'no overflow');
  });

  testWidgets('S2 close and reopen: recovery mode again; Resume recovers the '
      'SAME attempt; Done resolves the entry point with TRUE', (tester) async {
    _size(tester);
    final prefs = await _freshPrefs();
    final w = _world(server: _server(), prefs: prefs);
    await _pumpHost(tester, w);
    await _open(tester);
    w.server.faultNext(ServerFault.dropResponseAfterCommit);
    await _confirmCash(tester);
    await _tap(tester, 'payment-close-resume-later-button');
    expect(find.byType(CashPaymentSheet), findsNothing);
    expect(w.lastResult, isFalse, reason: 'a dismissed sheet is not success');

    await _open(tester);
    _expectRecoveryMode(tester);
    await _tap(tester, 'payment-resume-attempt-button');
    expect(find.byKey(const Key('payment-recovered-banner')), findsOneWidget);
    expect(
      find.byKey(const Key('payment-receipt-unknown')),
      findsNothing,
      reason: 'first durable reservation: the automatic receipt ran',
    );
    await _tap(tester, 'payment-done-button');
    expect(find.byType(CashPaymentSheet), findsNothing);
    expect(w.lastResult, isTrue);
    expect(w.server.paymentOpIdsFrom('device-A'), hasLength(1));
    expect(w.ids.calls, 2);
    expect(w.drawer.kicks, hasLength(1));
    expect(w.detail.fetches, 1);
    expect(w.server.completedPaymentsFor('order-1'), 1);
  });

  testWidgets('S3 (R14) a resolved attempt never re-fires the automatic '
      'receipt/drawer: a second pass shows "recovered" with the receipt '
      'outcome honestly unknown', (tester) async {
    _size(tester);
    final prefs = await _freshPrefs();
    final w = _world(server: _server(), prefs: prefs);
    await _pumpHost(tester, w);
    await _open(tester);
    await _confirmCash(tester); // plain success: pops true, effects once
    expect(w.lastResult, isTrue);
    expect(w.drawer.kicks, hasLength(1));
    expect(w.detail.fetches, 1);

    // The order is paid; a stale surface reopens the sheet and confirms
    // again. No second tender, no second effects.
    await _open(tester);
    await _confirmCash(tester);
    expect(find.byKey(const Key('payment-recovered-banner')), findsOneWidget);
    expect(find.byKey(const Key('payment-receipt-unknown')), findsOneWidget);
    expect(w.drawer.kicks, hasLength(1));
    expect(w.detail.fetches, 1);
    expect(w.server.paymentOpsSeen, hasLength(1));
    expect(w.ids.calls, 2);
  });

  testWidgets('S4 (R14/R9) accepted but the local save fails: effects are NOT '
      'fired; after a restart the resume arms them exactly once', (
    tester,
  ) async {
    _size(tester);
    final prefs = await _freshPrefs();
    final failAfter = _FailAfterPrefs(prefs, 1);
    final server = _server();
    final w1 = _world(server: server, prefs: failAfter);
    await _pumpHost(tester, w1);
    await _open(tester);
    await _confirmCash(tester);
    expect(w1.lastResult, isTrue, reason: 'the payment stands');
    expect(w1.drawer.kicks, isEmpty, reason: 'no durable reservation, no I/O');
    expect(w1.detail.fetches, 0);
    expect(server.completedPaymentsFor('order-1'), 1);

    // Restart over the same preferences.
    //
    // CHANGED IN S1-R3: a restart is a NEW ISOLATE, and that is the only thing
    // that legitimately clears the physical-key trust boundary the failed
    // acceptance installed. Disposing a container or building a new store is
    // deliberately NOT enough any more — that was the F001 defect.
    w1.container.dispose();
    resetPaymentAttemptKeyGuardsForTest();
    final w2 = _world(server: server, prefs: prefs);
    await _pumpHost(tester, w2);
    await _open(tester);
    _expectRecoveryMode(tester);
    await _tap(tester, 'payment-resume-attempt-button');
    expect(find.byKey(const Key('payment-recovered-banner')), findsOneWidget);
    expect(w2.drawer.kicks, hasLength(1));
    expect(w2.detail.fetches, 1);
    expect(server.executions, 1);
    expect(server.replays, 1);
  });

  testWidgets('S5/PDR-006 another till settled the order: the resume is '
      'REFUSED, fires nothing, and never claims to be our payment', (
    tester,
  ) async {
    // CHANGED IN S1. This asserted a "settled by another attempt/device"
    // banner, which the client inferred from "the order is paid". The reads
    // available to a POS expose no payment `device_id` and no
    // `local_operation_id`, so a paid order can never name the operation that
    // paid it. The sheet now reports what the server actually said about THIS
    // attempt — a refusal — and still fires nothing.
    _size(tester);
    final prefs = await _freshPrefs();
    final server = _server(shifts: const {'device-A', 'device-B'});
    final w = _world(server: server, prefs: prefs);
    await _pumpHost(tester, w);
    await _open(tester);
    server.faultNext(ServerFault.failBeforeExecute);
    await _confirmCash(tester);
    _expectRecoveryMode(tester);
    // Till B settles the order meanwhile.
    final b = _world(
      server: server,
      prefs: await _freshPrefs(),
      scope: _scopeB,
      pinSession: 'pin-B',
    );
    expect(
      await b.container
          .read(paymentControllerProvider.notifier)
          .submitAttempt(
            identity: PosOrderIdentity.server('order-1'),
            orderId: 'order-1',
            orderNumber: '#A1',
            amountMinor: 4000,
            tenderedMinor: 4000,
            currencyCode: 'ILS',
            expectedRevision: 3,
          ),
      isA<PaymentAttemptAccepted>(),
    );
    w.snapshots.upsert(_snapshot(settlement: PosSettlement.paid));

    await _tap(tester, 'payment-resume-attempt-button');
    expect(find.byKey(const Key('payment-failed-banner')), findsOneWidget);
    expect(find.byKey(const Key('payment-recovered-banner')), findsNothing);
    expect(
      find.byKey(const Key('payment-settled-elsewhere-banner')),
      findsNothing,
      reason: 'no attribution the client cannot prove',
    );
    expect(w.drawer.kicks, isEmpty);
    expect(w.detail.fetches, 0);
    expect(w.lastResult, isNull, reason: 'the sheet is still open');
    expect(server.completedPaymentsFor('order-1'), 1);
    expect(server.orders['order-1']!.paidByDevice, 'device-B');
  });

  testWidgets('S6/S1-F001 a refused durable write: honest banner, nothing '
      'sent, and the poisoned adapter cannot be talked into sending', (
    tester,
  ) async {
    // CHANGED IN S1-R2. This used to end by flipping the double healthy and
    // asserting the next Confirm paid. Codex S1-F001 showed the adapter still
    // holds an optimistic record that never reached storage, so a later
    // Confirm could transmit an attempt with no durable identity. The cashier
    // still gets an honest banner and the till still refuses to send.
    _size(tester);
    final prefs = await _freshPrefs();
    final failing = FailingPrefs(prefs)..failWrites = true;
    final w = _world(server: _server(), prefs: failing);
    await _pumpHost(tester, w);
    await _open(tester);
    await _confirmCash(tester);
    expect(
      find.byKey(const Key('payment-save-blocked-banner')),
      findsOneWidget,
    );
    expect(w.server.attemptedPushes, isEmpty);
    failing.failWrites = false;
    await _tap(tester, 'confirm-payment-button');
    expect(w.lastResult, isNull, reason: 'no payment was taken');
    expect(w.server.attemptedPushes, isEmpty);
    expect(w.drawer.kicks, isEmpty);
    expect(w.detail.fetches, 0);
  });

  testWidgets('S7 (R13) a stored attempt this build cannot read: quarantine '
      'banner, no Confirm, nothing sent', (tester) async {
    _size(tester);
    final prefs = await _freshPrefs();
    await prefs.setString(
      paymentAttemptsStorageKey(_scopeA.key),
      jsonEncode({
        'version': 1,
        'attempts': [
          {'order_id': 'order-1', 'local_operation_id': 'op-old', 'phase': 42},
        ],
      }),
    );
    final w = _world(server: _server(), prefs: prefs);
    await _pumpHost(tester, w);
    await _open(tester);
    expect(find.byKey(const Key('payment-quarantined-banner')), findsOneWidget);
    expect(find.byKey(const Key('confirm-payment-button')), findsNothing);
    await _tap(tester, 'payment-quarantined-close-button');
    expect(w.lastResult, isFalse);
    expect(w.server.attemptedPushes, isEmpty);
  });

  testWidgets('S8 (R10) another cashier sees the attempt but cannot resume '
      'it; the status check is read-only', (tester) async {
    _size(tester);
    final prefs = await _freshPrefs();
    final server = _server();
    final w1 = _world(server: server, prefs: prefs);
    await _pumpHost(tester, w1);
    await _open(tester);
    server.faultNext(ServerFault.dropResponseAfterCommit);
    await _confirmCash(tester);
    await _tap(tester, 'payment-close-resume-later-button');
    w1.container.dispose();

    final w2 = _world(
      server: server,
      prefs: prefs,
      employee: 'emp-2',
      pinSession: 'pin-A2',
    );
    await _pumpHost(tester, w2);
    await _open(tester);
    expect(find.byKey(const Key('payment-other-actor-banner')), findsOneWidget);
    _expectRecoveryMode(tester, resumable: false);
    await _tap(tester, 'payment-check-status-button');
    // The ledger holds the applied result: resolved from the read alone.
    expect(find.byKey(const Key('payment-recovered-banner')), findsOneWidget);
    expect(server.paymentOpsSeen, hasLength(1), reason: 'nothing re-sent');
    // S1-R2 (reviewer probe): a PASSIVE resolution is read-only for the
    // cashier's hardware too, and stays read-only across a full host rebuild
    // and sheet recreation over the same container — the window in which a
    // downstream listener could otherwise see a fresh null -> payment edge.
    expect(
      w2.drawer.kicks,
      isEmpty,
      reason: 'a passive status read cannot invoke the drawer',
    );
    expect(
      w2.detail.fetches,
      0,
      reason: 'a passive status read cannot enter automatic receipt printing',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await _pumpHost(tester, w2);
    await _open(tester);
    expect(w2.drawer.kicks, isEmpty, reason: 'still zero after host rebuild');
    expect(w2.detail.fetches, 0, reason: 'still zero after sheet recreation');
  });

  testWidgets('S9 (R11) Check status with no ledger row and an unpaid order '
      'says STILL PENDING and sends nothing', (tester) async {
    _size(tester);
    final prefs = await _freshPrefs();
    final w = _world(server: _server(), prefs: prefs);
    await _pumpHost(tester, w);
    await _open(tester);
    w.server.faultNext(ServerFault.failBeforeExecute);
    await _confirmCash(tester);
    _expectRecoveryMode(tester);
    final before = w.server.attemptedPushes.length;
    await _tap(tester, 'payment-check-status-button');
    expect(
      find.byKey(const Key('payment-status-still-pending')),
      findsOneWidget,
    );
    expect(w.server.attemptedPushes, hasLength(before));
    _expectRecoveryMode(tester);
  });

  testWidgets('S10 a PROVEN not-applied request keeps its own words and the '
      'same attempt resumes', (tester) async {
    _size(tester);
    final prefs = await _freshPrefs();
    final w = _world(server: _server(), prefs: prefs);
    await _pumpHost(tester, w);
    await _open(tester);
    w.server.faultNext(ServerFault.raiseBatch42501);
    await _confirmCash(tester);
    expect(find.byKey(const Key('payment-not-applied-banner')), findsOneWidget);
    _expectRecoveryMode(tester);
    await _tap(tester, 'payment-resume-attempt-button');
    expect(find.byKey(const Key('payment-recovered-banner')), findsOneWidget);
    expect(w.server.paymentOpIdsFrom('device-A'), hasLength(1));
    expect(w.ids.calls, 2);
  });

  testWidgets('S11 (R10) a session refusal keeps the attempt and asks for a '
      'sign-in, not for the customer\'s money', (tester) async {
    _size(tester);
    final prefs = await _freshPrefs();
    final w = _world(
      server: _server()..invalidPinSessions.add('pin-A'),
      prefs: prefs,
    );
    await _pumpHost(tester, w);
    await _open(tester);
    await _confirmCash(tester);
    expect(
      find.byKey(const Key('payment-auth-required-banner')),
      findsOneWidget,
    );
    _expectRecoveryMode(tester);
    expect(w.server.pushes, isEmpty);
  });

  testWidgets('S12 the recovery wording renders in Arabic and Hebrew under '
      'RTL, and in English under LTR', (tester) async {
    for (final locale in const ['ar', 'he', 'en']) {
      _size(tester);
      final prefs = await _freshPrefs();
      final w = _world(server: _server(), prefs: prefs);
      await _pumpHost(tester, w, locale: locale);
      await _open(tester);
      w.server.faultNext(ServerFault.dropResponseAfterCommit);
      await _confirmCash(tester);
      final l10n = await AppLocalizations.delegate.load(Locale(locale));
      expect(
        find.text(l10n.posPaymentUnconfirmedTitle),
        findsOneWidget,
        reason: locale,
      );
      expect(
        find.text(l10n.posPaymentUnconfirmedBody),
        findsOneWidget,
        reason: locale,
      );
      expect(find.text(l10n.posPaymentCheckStatus), findsOneWidget);
      expect(find.text(l10n.posPaymentResumeAttempt), findsOneWidget);
      expect(find.text(l10n.posPaymentCloseResumeLater), findsOneWidget);
      final dir = Directionality.of(
        tester.element(find.byKey(const Key('payment-unconfirmed-banner'))),
      );
      expect(
        dir,
        locale == 'en' ? TextDirection.ltr : TextDirection.rtl,
        reason: locale,
      );
      await _tap(tester, 'payment-resume-attempt-button');
      expect(find.text(l10n.posPaymentRecoveredTitle), findsOneWidget);
      expect(find.text(l10n.posPaymentRecoveredBody), findsOneWidget);
      expect(find.text(l10n.posPaymentDone), findsOneWidget);
      await _tap(tester, 'payment-done-button');
      w.container.dispose();
    }
  });

  testWidgets('S13 (R16) the order row shows the unconfirmed chip and still '
      'offers the ONE pay entry point', (tester) async {
    _size(tester);
    final prefs = await _freshPrefs();
    final w = _world(server: _server(), prefs: prefs);
    final payments = w.container.read(paymentControllerProvider.notifier);
    w.server.faultNext(ServerFault.dropResponseAfterCommit);
    expect(
      await payments.submitAttempt(
        identity: PosOrderIdentity.server('order-1'),
        orderId: 'order-1',
        orderNumber: '#A1',
        amountMinor: 4000,
        tenderedMinor: 5000,
        currencyCode: 'ILS',
        expectedRevision: 3,
      ),
      isA<PaymentAttemptUnconfirmed>(),
    );
    final order = PosRecentOrder(
      order: const SubmittedOrderView(
        orderNumber: '#A1',
        orderType: OrderType.takeaway,
        currencyCode: 'ILS',
        subtotalMinor: 4000,
        orderId: 'order-1',
        lines: [
          SubmittedLineView(
            name: 'Burger',
            quantity: 1,
            lineTotalMinor: 4000,
            currencyCode: 'ILS',
          ),
        ],
      ),
      submittedAt: _pinnedNow,
      snapshot: _snapshot(),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: w.container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: OrderActionRow(
              order: order,
              l10n: l10n,
              actions: const PosOrderActions(
                canPay: true,
                canDiscount: false,
                canFullComp: false,
                canVoid: false,
                canMoveTable: false,
                canOpenReceipt: false,
                pendingKind: null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('recent-payment-unconfirmed-#A1')),
      findsOneWidget,
    );
    expect(find.text(l10n.posPaymentUnconfirmedChip), findsOneWidget);
    expect(find.byKey(const Key('recent-pay-#A1')), findsOneWidget);
  });

  testWidgets('S9/S1-R3-F004 a refusal this device could not record shows BOTH '
      'truths: the exact refusal AND the blocked local save', (tester) async {
    // Codex S1-F004: the R2 build caught and discarded the store failure and
    // returned a plain refusal, so the cashier saw a settled-looking outcome
    // backed by nothing on disk. Relabelling the refusal as unconfirmed would
    // be the opposite error. Both facts are now rendered together.
    _size(tester);
    final prefs = await _freshPrefs();
    // The claim lands; the write that records the refusal does not.
    final failAfter = _FailAfterPrefs(prefs, 1);
    // No open shift: the server MEMOIZES an exact refusal, and nothing moved.
    final server = _server(shifts: const <String>{});
    final w = _world(server: server, prefs: failAfter);
    await _pumpHost(tester, w);
    await _open(tester);
    await _confirmCash(tester);

    expect(
      find.byKey(const Key('payment-no-shift-banner')),
      findsOneWidget,
      reason: 'the exact refusal keeps its own words',
    );
    expect(
      find.byKey(const Key('payment-refusal-save-blocked-banner')),
      findsOneWidget,
      reason: 'and the cashier is told this device could not record it',
    );
    expect(server.completedPaymentsFor('order-1'), 0);
    expect(w.drawer.kicks, isEmpty);
    expect(w.detail.fetches, 0);

    // A keystroke clears ordinary retryable errors; it must NOT quietly clear
    // a disclosure about money.
    await tester.enterText(find.byKey(const Key('cash-received-field')), '50');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('payment-refusal-save-blocked-banner')),
      findsOneWidget,
    );
  });

  testWidgets('S9b/S1-R3-F004 CONTROL: a refusal that DOES persist shows the '
      'refusal alone', (tester) async {
    _size(tester);
    final prefs = await _freshPrefs();
    final server = _server(shifts: const <String>{});
    final w = _world(server: server, prefs: prefs);
    await _pumpHost(tester, w);
    await _open(tester);
    await _confirmCash(tester);

    expect(find.byKey(const Key('payment-no-shift-banner')), findsOneWidget);
    expect(
      find.byKey(const Key('payment-refusal-save-blocked-banner')),
      findsNothing,
      reason: 'nothing to disclose when the record really was written',
    );
    expect(server.completedPaymentsFor('order-1'), 0);
  });
}
