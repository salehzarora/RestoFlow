// PAYMENT-ATTEMPT-RECOVERY-001 (BCA-MONEY-001) — the BASELINE-RED file.
//
// Every test here is written against seams that exist at the audited base
// (dc56065e): the REAL `RealPaymentRepository` -> `PaymentController` ->
// `CashPaymentSheet` chain over a contract-faithful stateful `sync_push` fake.
// Each asserts the INTENDED safe behaviour and FAILS on the baseline for the
// exact reason the audit confirmed from source: after an ambiguous response the
// retry mints a brand-new `local_operation_id` + `target_id` (a new business
// attempt), so the server's same-key idempotency replay can never help it.
//
// The follow-on matrix (payment_attempt_recovery_001_test.dart) covers the cases
// that need the new durable-attempt seam and therefore cannot compile on the
// baseline; this file is the part that can, so the RED evidence is semantic,
// not a compile error.
//
// Synthetic ids, amounts and sessions only. No network, no printer, no drawer.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/order_identity.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:restoflow_pos/src/state/pos_session.dart'
    show
        posAuthTransportProvider,
        posSignedInEmployeeProfileIdProvider,
        posSyncSessionProvider;
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/widgets/cash_payment_sheet.dart';
import 'package:restoflow_pos/src/data/payment_attempt_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/payment_attempt_server_fake.dart';

/// Counts every id the POS mints. ONE business attempt = exactly TWO ids (the
/// `local_operation_id` and the provisional `target_id`), however many times it
/// is sent.
class _CountingIds implements ClientIdGenerator {
  _CountingIds(this._prefix);
  final String _prefix;
  int calls = 0;

  @override
  String newId() => '$_prefix-id-${++calls}';
}

final _pinnedNow = DateTime.utc(2026, 9, 8, 12);

PosOrderSnapshot _snapshot({
  String orderId = 'order-1',
  String code = '#A1',
  int revision = 3,
  int total = 4000,
  PosSettlement settlement = PosSettlement.unpaid,
}) => PosOrderSnapshot(
  orderId: orderId,
  orderCode: code,
  revision: revision,
  status: 'submitted',
  settlement: settlement,
  subtotalMinor: total,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: total,
  createdAt: _pinnedNow.subtract(const Duration(hours: 1)),
  updatedAt: _pinnedNow.subtract(const Duration(minutes: 50)),
  syncAt: _pinnedNow.subtract(const Duration(minutes: 50)),
  orderType: 'takeaway',
  currencyCode: 'ILS',
);

/// A REAL-mode till: the real payment repository/controller over [server].
ProviderContainer _till({
  required PaymentAttemptServerFake server,
  required String device,
  required _CountingIds ids,
}) {
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(server),
      posSyncSessionProvider.overrideWithValue(
        SyncSession(pinSessionId: 'pin-$device', deviceId: device),
      ),
      posSyncScopeProvider.overrideWithValue(
        PosSyncScope(
          organizationId: 'org-1',
          restaurantId: 'rest-1',
          branchId: 'branch-A',
          deviceId: device,
        ),
      ),
      clientIdGeneratorProvider.overrideWithValue(ids),
      posRecentOrdersStoreProvider.overrideWithValue(
        InMemoryRecentOrdersStore(),
      ),
      orderSnapshotRepositoryProvider.overrideWithValue(
        DemoOrderSnapshotRepository(seed: [_snapshot()]),
      ),
      posSyncPollIntervalProvider.overrideWithValue(null),
      posSyncClockProvider.overrideWithValue(() => _pinnedNow),
    ],
  );
  addTearDown(container.dispose);
  // PDR-007 (S1): a real attempt is always taken by a signed-in cashier, and
  // may only be resumed by that same cashier. The fixture states it.
  container.read(posSignedInEmployeeProfileIdProvider.notifier).set('emp-1');
  return container;
}

PaymentAttemptServerFake _server({Iterable<String> shifts = const {}}) =>
    PaymentAttemptServerFake(
      orders: [
        FakeServerOrder(orderId: 'order-1', grandTotalMinor: 4000, revision: 3),
      ],
      devicesWithOpenShift: shifts,
    );

/// The one cash decision every test below makes: ₪40.00 due, ₪50.00 tendered.
Future<CashPayment> _pay(ProviderContainer c) => c
    .read(paymentControllerProvider.notifier)
    .payCash(
      identity: PosOrderIdentity.server('order-1'),
      orderId: 'order-1',
      orderNumber: '#A1',
      amountMinor: 4000,
      tenderedMinor: 5000,
      currencyCode: 'ILS',
      expectedRevision: 3,
    );

Future<({CashPayment? payment, Object? error})> _try(
  Future<CashPayment> f,
) async {
  try {
    return (payment: await f, error: null);
  } catch (e) {
    return (payment: null, error: e);
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.microtask(() {});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // S1-R3 / F001: the physical-key trust boundary is deliberately isolate-wide
  // and impossible to clear at runtime, so each test starts from a clean one.
  setUp(resetPaymentAttemptKeyGuardsForTest);

  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  group('RED — the retry after an ambiguous response is a NEW attempt', () {
    test(
      'R1 commit + lost response: the retry reuses the SAME operation id, '
      'target id, timestamp and payload, and mints NO replacement identity',
      () async {
        final server = _server(shifts: {'device-A'});
        final ids = _CountingIds('a');
        final till = _till(server: server, device: 'device-A', ids: ids);

        server.faultNext(ServerFault.dropResponseAfterCommit);
        final first = await _try(_pay(till));
        expect(
          server.completedPaymentsFor('order-1'),
          1,
          reason: 'the server COMMITTED; only the response was lost',
        );
        expect(
          first.payment,
          isNull,
          reason: 'the client cannot know the outcome yet',
        );

        // The cashier retries the SAME decision.
        final second = await _try(_pay(till));

        final seen = server.paymentOpsSeen;
        expect(seen, hasLength(2), reason: 'two sends of ONE attempt');
        expect(seen[1]['local_operation_id'], seen[0]['local_operation_id']);
        expect(seen[1]['target_id'], seen[0]['target_id']);
        expect(seen[1]['client_created_at'], seen[0]['client_created_at']);
        expect(jsonEncode(seen[1]['payload']), jsonEncode(seen[0]['payload']));
        expect(
          ids.calls,
          2,
          reason:
              'ONE business attempt = ONE local_operation_id + ONE target_id',
        );
        expect(server.executions, 1);
        expect(
          server.replays,
          1,
          reason: 'the second send is a same-key replay',
        );
        expect(server.completedPaymentsFor('order-1'), 1);
        expect(
          second.error,
          isNull,
          reason: 'a verified applied replay resolves THIS attempt',
        );
        expect(second.payment?.paymentId, 'srv-pay-1');
        expect(second.payment?.receiptNumber, 'R-1');
        expect(second.payment?.changeMinor, 1000);
      },
    );

    test(
      'R5 an applied replay is ONE logical settlement — and once resolved, a '
      'further confirm mints no third identity and sends nothing new',
      () async {
        final server = _server(shifts: {'device-A'});
        final ids = _CountingIds('a');
        final till = _till(server: server, device: 'device-A', ids: ids);

        server.faultNext(ServerFault.dropResponseAfterCommit);
        await _try(_pay(till));
        final recovered = await _try(_pay(till));
        expect(recovered.payment?.paymentId, 'srv-pay-1');

        // The attempt is resolved. Whatever the caller does now, no NEW
        // business attempt may be minted for this settled order.
        await _try(_pay(till));
        expect(server.paymentOpsSeen, hasLength(2));
        expect(ids.calls, 2);
        expect(server.completedPaymentsFor('order-1'), 1);
      },
    );

    test('R11 a second confirm while the first request is STILL IN FLIGHT does '
        'not mint a fresh key and sends nothing', () async {
      final server = _server(shifts: {'device-A'});
      final ids = _CountingIds('a');
      final till = _till(server: server, device: 'device-A', ids: ids);

      server.faultNext(ServerFault.holdResponseAfterCommit);
      final inFlight = _try(_pay(till));
      await _settle();
      expect(server.isHolding, isTrue, reason: 'the response is held');
      expect(server.completedPaymentsFor('order-1'), 1);

      // Meanwhile: a refresh would read "unpaid" (the snapshot seed is
      // unpaid) and the cashier presses again.
      final again = await _try(_pay(till));
      expect(again.payment, isNull);
      expect(
        server.paymentOpsSeen,
        hasLength(1),
        reason: 'the original request is still pending; no fresh key',
      );
      expect(ids.calls, 2);

      server.releaseHeld();
      final first = await inFlight;
      expect(first.payment?.paymentId, 'srv-pay-1');
      expect(server.completedPaymentsFor('order-1'), 1);
    });

    test(
      'R7 two tills: the till whose request never arrived must resume its OWN '
      'attempt — never mint a new one — and never claim the other till\'s '
      'payment as its own',
      () async {
        final server = _server(shifts: {'device-A', 'device-B'});
        final idsA = _CountingIds('a');
        final idsB = _CountingIds('b');
        final tillA = _till(server: server, device: 'device-A', ids: idsA);
        final tillB = _till(server: server, device: 'device-B', ids: idsB);

        server.faultNext(ServerFault.failBeforeExecute);
        final a1 = await _try(_pay(tillA));
        expect(a1.payment, isNull);
        expect(server.pushes, isEmpty, reason: 'A\'s request never arrived');

        final b = await _try(_pay(tillB));
        expect(b.payment?.paymentId, 'srv-pay-1');
        expect(server.orders['order-1']!.paidByDevice, 'device-B');

        final a2 = await _try(_pay(tillA));
        expect(
          idsA.calls,
          2,
          reason: 'A\'s retry is the SAME business attempt, not a new one',
        );
        expect(server.paymentOpIdsFrom('device-A'), hasLength(1));
        expect(
          a2.payment,
          isNull,
          reason: 'B\'s payment is not A\'s; A must not report success',
        );
        expect(server.completedPaymentsFor('order-1'), 1);
      },
    );
  });

  group('RED — sheet close/reopen', () {
    testWidgets(
      'R2 after a lost response the reopened sheet must resume the SAME '
      'attempt, not start a new one',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final server = _server(shifts: {'device-A'});
        final ids = _CountingIds('a');
        final till = _till(server: server, device: 'device-A', ids: ids);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: till,
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: restoflowLocalizationsDelegates,
              supportedLocales: kSupportedLocales,
              home: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: FilledButton(
                      key: const Key('open-pay'),
                      onPressed: () => CashPaymentSheet.show(
                        context,
                        identity: PosOrderIdentity.server('order-1'),
                        orderNumber: '#A1',
                        amountMinor: 4000,
                        currencyCode: 'ILS',
                        orderId: 'order-1',
                        expectedRevision: 3,
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Attempt 1: the server commits, the response is lost.
        await tester.tap(find.byKey(const Key('open-pay')));
        await tester.pumpAndSettle();
        server.faultNext(ServerFault.dropResponseAfterCommit);
        await tester.enterText(
          find.byKey(const Key('cash-received-field')),
          '50.00',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm-payment-button')));
        await tester.pumpAndSettle();
        expect(server.completedPaymentsFor('order-1'), 1);
        expect(find.byType(CashPaymentSheet), findsOneWidget);

        // The cashier closes the sheet (a dismissed sheet cancels NOTHING on
        // the server) and reopens it for the same order.
        Navigator.of(tester.element(find.byType(CashPaymentSheet))).pop();
        await tester.pumpAndSettle();
        expect(find.byType(CashPaymentSheet), findsNothing);
        await tester.tap(find.byKey(const Key('open-pay')));
        await tester.pumpAndSettle();
        expect(find.byType(CashPaymentSheet), findsOneWidget);

        // Whatever action the reopened sheet offers for the earlier attempt,
        // it must be THE SAME attempt. (Post-fix the sheet offers an explicit
        // "Resume same attempt"; the baseline only offers Confirm.)
        final resume = find.byKey(const Key('payment-resume-attempt-button'));
        if (resume.evaluate().isNotEmpty) {
          await tester.tap(resume);
        } else {
          await tester.enterText(
            find.byKey(const Key('cash-received-field')),
            '50.00',
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('confirm-payment-button')));
        }
        await tester.pumpAndSettle();

        expect(
          server.paymentOpIdsFrom('device-A'),
          hasLength(1),
          reason: 'close/reopen must not allocate a replacement identity',
        );
        expect(ids.calls, 2);
        expect(server.completedPaymentsFor('order-1'), 1);
        expect(server.replays, 1);
      },
    );
  });
}
