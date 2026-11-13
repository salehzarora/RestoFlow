// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F: the card flow inside the payment sheet —
// the tenders each server posture offers, the card view's states and actions,
// the one receipt edge, closing (automatic checks stop, the journal stays), the
// hand-recorded Card on a till whose posture was unknown, the quarantined
// journal, and AR/HE right-to-left at phone width (execution packet §7, §9,
// §10, §11).
//
// The sheet is opened through `CashPaymentSheet.show` over the REAL payment
// and card controllers. One fake till serves both worlds: the card Edge, the
// provider leg and the PIN-session probe go to [CardServerFake]; the ordinary
// tenders go to the contract-faithful [PaymentAttemptServerFake]. No network.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_identity.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_attempt_store.dart';
import 'package:restoflow_pos/src/data/provider_card_attempt.dart';
import 'package:restoflow_pos/src/data/provider_card_store.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/format/provider_card_presentation.dart';
import 'package:restoflow_pos/src/print/pos_cash_drawer_service.dart';
import 'package:restoflow_pos/src/state/discount_controller.dart'
    show staffCapabilitiesProvider;
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/provider_card_controller.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/widgets/cash_payment_sheet.dart';
import 'package:restoflow_pos/src/widgets/provider_card_payment_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/payment_attempt_server_fake.dart';
import 'support/provider_card_fakes.dart';

/// One till: the card surfaces to [card], everything else to [ordinary] —
/// except that, like the 001D guard, a hand-recorded Card pushed on a LIVE
/// terminal till (configured, enabled or draining) is refused
/// `card_terminal_required` and never reaches the ordinary ledger.
class _Till implements SyncRpcTransport, AuthenticatedCardChargeTransport {
  _Till(this.card, this.ordinary);
  final CardServerFake card;
  final PaymentAttemptServerFake ordinary;
  int terminalRequired = 0;

  @override
  Future<CardChargeTransportResult> sendCardCharge(
    Map<String, dynamic> body, {
    bool Function()? isCurrent,
  }) => card.sendCardCharge(body, isCurrent: isCurrent);

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) {
    if (function == 'pin_session_capabilities') {
      return card.invoke(function, params);
    }
    if (function == 'sync_push') {
      final ops = params['p_operations'];
      final leg =
          ops is List &&
          ops.length == 1 &&
          ops.single is Map &&
          card.attempts.containsKey((ops.single as Map)['local_operation_id']);
      if (leg) return card.invoke(function, params);
      if (ops is List && card.terminalMode == 'live') {
        final manual = <Map>[
          for (final op in ops)
            if (op is Map &&
                op['operation_type'] == 'payment.create' &&
                (op['payload'] as Map?)?['tender_type'] == 'card')
              op,
        ];
        if (manual.isNotEmpty) {
          terminalRequired++;
          return Future<Object?>.value(<String, Object?>{
            'ok': true,
            'results': <Map<String, Object?>>[
              for (final op in manual)
                <String, Object?>{
                  'local_operation_id': op['local_operation_id'],
                  'operation_type': 'payment.create',
                  'ok': false,
                  'error': 'card_terminal_required',
                  'order_id': (op['payload'] as Map)['order_id'],
                  'server_ts': '2026-10-30T12:00:00Z',
                  'status': 'rejected',
                  'idempotency_replay': false,
                },
            ],
            'server_ts': '2026-10-30T12:00:00Z',
          });
        }
      }
    }
    return ordinary.invoke(function, params);
  }
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

PosOrderSnapshot _snapshot() => PosOrderSnapshot(
  orderId: kCardOrder,
  orderCode: '#A1',
  revision: 7,
  status: 'submitted',
  settlement: PosSettlement.unpaid,
  subtotalMinor: 1200,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 1200,
  createdAt: kCardNow.subtract(const Duration(hours: 1)),
  updatedAt: kCardNow.subtract(const Duration(minutes: 50)),
  syncAt: kCardNow.subtract(const Duration(minutes: 50)),
  orderType: 'takeaway',
  currencyCode: 'ILS',
);

class _World {
  _World({
    required this.c,
    required this.card,
    required this.ordinary,
    required this.till,
    required this.store,
    required this.prefs,
    required this.ids,
    required this.detail,
    required this.drawer,
  });
  final ProviderContainer c;
  final CardServerFake card;
  final PaymentAttemptServerFake ordinary;
  final _Till till;
  final HookedCardStore store;
  final SharedPreferences prefs;
  final CountingCardIds ids;
  final _CountingDetailRepo detail;
  final _RecordingDrawerService drawer;

  /// What the LAST `CashPaymentSheet.show` resolved with (null while open).
  bool? lastResult;

  ProviderCardAttempt? get attempt => c
      .read(providerCardControllerProvider)
      .currentFor(PosOrderIdentity.server(kCardOrder), includeTest: true);

  Future<ProviderCardLoad> journal() =>
      SharedPrefsProviderCardStore(prefs: () async => prefs).load(kCardScope);

  bool get journalWritten =>
      prefs.containsKey(providerCardAttemptsStorageKey(kCardScope.key));
}

Future<_World> _world({
  CardServerFake? card,
  Map<String, Object> prefs = const <String, Object>{},
  ProviderCardPollPolicy? policy,
}) async {
  final server = card ?? CardServerFake();
  final ordinary = PaymentAttemptServerFake(
    orders: [
      FakeServerOrder(orderId: kCardOrder, grandTotalMinor: 1200, revision: 7),
    ],
    devicesWithOpenShift: const {kCardDevice},
  );
  final p = await freshCardPrefs(prefs);
  final ids = CountingCardIds();
  final detail = _CountingDetailRepo();
  final till = _Till(server, ordinary);
  final store = HookedCardStore(
    SharedPrefsProviderCardStore(prefs: () async => p),
  );
  late _RecordingDrawerService drawer;
  final c = cardContainer(
    server: server,
    prefs: p,
    transport: till,
    ids: ids,
    store: store,
    policy: policy,
    extra: <Override>[
      paymentAttemptStoreProvider.overrideWithValue(
        SharedPrefsPaymentAttemptStore(p),
      ),
      posRecentOrdersStoreProvider.overrideWithValue(
        InMemoryRecentOrdersStore(),
      ),
      orderSnapshotRepositoryProvider.overrideWithValue(
        DemoOrderSnapshotRepository(seed: [_snapshot()]),
      ),
      orderDetailRepositoryProvider.overrideWithValue(detail),
      posCashDrawerServiceProvider.overrideWith((ref) {
        drawer = _RecordingDrawerService(ref);
        return drawer;
      }),
      posSyncPollIntervalProvider.overrideWithValue(null),
    ],
  );
  c.read(posCashDrawerServiceProvider);
  return _World(
    c: c,
    card: server,
    ordinary: ordinary,
    till: till,
    store: store,
    prefs: p,
    ids: ids,
    detail: detail,
    drawer: drawer,
  );
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
      container: w.c,
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
                    identity: PosOrderIdentity.server(kCardOrder),
                    orderNumber: '#A1',
                    amountMinor: 1200,
                    currencyCode: 'ILS',
                    orderId: kCardOrder,
                    expectedRevision: 7,
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

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// Lets the first automatic check (3 s after the view attached) run.
Future<void> _autoCheck(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

/// The tender form's title and amount rows overflow a 390 px phone under the
/// square test glyphs in every language, with the feature OFF exactly as ON
/// (measured on the 001F base: AR 10 + 48 px, HE 70 px, EN 180 px). That
/// layout is the base sheet's, outside 001F; only an overflow is tolerated,
/// and only here. The card view is held to no overflow at all.
void _drainTenderFormOverflow(WidgetTester tester) {
  final e = tester.takeException();
  if (e == null) return;
  expect(e.toString(), contains('A RenderFlex overflowed by'));
}

void _expectKeys(Iterable<String> keys, Matcher matcher) {
  for (final k in keys) {
    expect(find.byKey(Key(k)), matcher, reason: k);
  }
}

Finder _state(ProviderCardPhase phase) =>
    find.byKey(Key('card-state-${phase.name}'));

/// The server learns of an attempt whose start answer was lost.
void _serverHas(CardServerFake card, String id) {
  card.attempts[id] = FakeCardAttempt(
    id: id,
    mode: 'live',
    amountMinor: 1200,
    currencyCode: 'ILS',
    orderId: kCardOrder,
    expectedRevision: 7,
  );
}

const List<String> _tenders = <String>[
  'tender-cash',
  'tender-card',
  'tender-bit',
  'tender-external',
];

const List<String> _cardNotes = <String>[
  'card-terminal-required',
  'card-posture-unknown',
  'card-terminal-unavailable',
  'card-terminal-lab-switch',
  'card-journal-quarantined',
  'card-start-issue',
];

final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

void main() {
  setUp(() {
    resetPaymentAttemptKeyGuardsForTest();
    resetProviderCardStoreChainsForTest();
    installNoNetworkGuard();
  });

  group('the tenders follow the server posture (packet §9.1)', () {
    testWidgets('no terminal binding: the RF-117 tenders and the hand-recorded '
        'Card are unchanged; nothing reaches the Edge or the card journal', (
      tester,
    ) async {
      _size(tester);
      final w = await _world(card: CardServerFake(terminalMode: null));
      await _pumpHost(tester, w);
      await _open(tester);
      _expectKeys(_tenders, findsOneWidget);
      _expectKeys(<String>[
        'tender-card-terminal',
        ..._cardNotes,
      ], findsNothing);

      await _tap(tester, 'tender-card');
      expect(find.text(_en.posNonCashNote), findsOneWidget);
      expect(find.text(_en.posConfirmPayment), findsOneWidget);
      await _tap(tester, 'confirm-payment-button');

      expect(w.lastResult, isTrue);
      final payload = w.ordinary.paymentOpsSeen.single['payload'] as Map;
      expect(payload['tender_type'], 'card');
      expect(payload['expected_revision'], 7, reason: 'PDR-003 stands');
      expect(w.card.edgeBodies, isEmpty);
      expect(w.card.pushCalls, isEmpty);
      expect(w.journalWritten, isFalse);
      expect(
        w.drawer.kicks,
        hasLength(1),
        reason:
            'unchanged: every payment is offered to the drawer service, '
            'which keeps the drawer shut for a card itself',
      );
    });

    testWidgets('LIVE and enabled: the integrated tender replaces the '
        'hand-recorded Card; Cash, Bit and External stay', (tester) async {
      _size(tester);
      final w = await _world();
      await _pumpHost(tester, w);
      await _open(tester);
      _expectKeys(<String>[
        'tender-cash',
        'tender-bit',
        'tender-external',
        'tender-card-terminal',
      ], findsOneWidget);
      _expectKeys(<String>['tender-card', ..._cardNotes], findsNothing);
      expect(find.text(_en.posCardTerminalTender), findsOneWidget);

      await _tap(tester, 'tender-card-terminal');
      expect(find.text(_en.posCardTerminalNote), findsOneWidget);
      expect(find.text(_en.posCardTerminalStart), findsOneWidget);
      expect(w.card.edgeBodies, isEmpty, reason: 'choosing sends nothing');
      expect(w.journalWritten, isFalse);
    });

    testWidgets('LIVE but not enabled (configured or draining): no Card of '
        'either kind and no start; an open attempt stays recoverable', (
      tester,
    ) async {
      _size(tester);
      final w = await _world();
      await _pumpHost(tester, w);
      await _open(tester);
      await _tap(tester, 'tender-card-terminal');
      await _tap(tester, 'confirm-payment-button');
      final id = w.attempt!.attemptId;
      await _tap(tester, 'card-close-button');
      expect(find.byType(CashPaymentSheet), findsNothing);

      w.card.terminalEnabled = false;
      w.c.invalidate(staffCapabilitiesProvider);
      await tester.pumpAndSettle();

      await _open(tester);
      expect(
        _state(ProviderCardPhase.waiting),
        findsOneWidget,
        reason: 'recovery stays possible while starts are stopped',
      );
      await _tap(tester, 'card-check-status-button');
      expect(w.card.edgeCount('status'), 1);
      expect(w.card.edgeBodies.last['source'], 'operator');

      w.card.decline(id);
      await _tap(tester, 'card-check-status-button');
      expect(_state(ProviderCardPhase.declined), findsOneWidget);
      await _tap(tester, 'card-other-method-button');

      _expectKeys(<String>[
        'tender-cash',
        'tender-bit',
        'tender-external',
        'card-terminal-unavailable',
      ], findsOneWidget);
      _expectKeys(<String>[
        'tender-card',
        'tender-card-terminal',
      ], findsNothing);
      expect(find.text(_en.posCardTerminalUnavailableNote), findsOneWidget);
      expect(w.card.edgeCount('start'), 1);
      expect(w.card.pushCalls, isEmpty);
    });

    testWidgets('TEST: only behind the lab switch (default OFF); an approval '
        'is never paid and nothing is recorded', (tester) async {
      _size(tester);
      final w = await _world(card: CardServerFake(terminalMode: 'test'));
      await _pumpHost(tester, w);
      await _open(tester);
      _expectKeys(_tenders, findsOneWidget);
      expect(find.byKey(const Key('tender-card-terminal')), findsNothing);
      final lab = tester.widget<SwitchListTile>(
        find.byKey(const Key('card-terminal-lab-switch')),
      );
      expect(lab.value, isFalse);

      await _tap(tester, 'card-terminal-lab-switch');
      expect(find.text(_en.posCardTerminalTestTender), findsOneWidget);
      await _tap(tester, 'tender-card-terminal');
      expect(find.text(_en.posCardTerminalTestNote), findsOneWidget);
      await _tap(tester, 'confirm-payment-button');

      final start = w.card.edgeBodies.single;
      expect(start['mode'], 'test');
      expect(start.containsKey('order_id'), isFalse);
      expect(start.containsKey('expected_revision'), isFalse);
      expect(find.byKey(const Key('card-test-badge')), findsOneWidget);
      expect(find.text(_en.posCardAttemptTestTitle), findsOneWidget);

      w.card.approve(w.attempt!.attemptId);
      await _autoCheck(tester);
      expect(_state(ProviderCardPhase.testApproved), findsOneWidget);
      expect(find.byKey(const Key('card-done-button')), findsNothing);
      expect(w.card.pushCalls, isEmpty);
      expect(w.ordinary.attemptedPushes, isEmpty);
      expect(w.detail.fetches, 0);

      await _tap(tester, 'card-back-to-payment-button');
      expect(find.byKey(const Key('card-attempt-view')), findsNothing);
      expect(find.byKey(const Key('tender-card-terminal')), findsOneWidget);
      expect(w.lastResult, isNull, reason: 'the sheet is still open');
    });
  });

  group('the card view (packet §7, §8, §10)', () {
    testWidgets('start → waiting (no other tender) → approved → recorded ONCE '
        'without expected_revision → Done resolves TRUE; one receipt', (
      tester,
    ) async {
      _size(tester);
      final w = await _world();
      await _pumpHost(tester, w);
      await _open(tester);
      await _tap(tester, 'tender-card-terminal');
      await _tap(tester, 'confirm-payment-button');

      final start = w.card.edgeBodies.single;
      expect(start['action'], 'start');
      expect(start['mode'], 'live');
      expect(start['order_id'], kCardOrder);
      expect(start['amount_minor'], 1200);
      expect(start['currency_code'], 'ILS');
      expect(start['expected_revision'], 7);
      expect(find.byKey(const Key('card-attempt-view')), findsOneWidget);
      expect(_state(ProviderCardPhase.waiting), findsOneWidget);
      _expectKeys(<String>[
        'card-check-status-button',
        'card-release-button',
        'card-close-button',
      ], findsOneWidget);
      _expectKeys(<String>[
        ..._tenders,
        'tender-card-terminal',
        'confirm-payment-button',
        'card-other-method-button',
        'card-done-button',
      ], findsNothing);

      w.card.approve(w.attempt!.attemptId);
      await _autoCheck(tester);

      expect(_state(ProviderCardPhase.recorded), findsOneWidget);
      expect(w.card.paymentsCreated, 1);
      final leg = w.card.pushedOps.single;
      expect(leg['operation_type'], 'payment.create');
      expect(leg['local_operation_id'], w.attempt!.attemptId);
      final legPayload = leg['payload'] as Map;
      expect(legPayload.keys.toSet(), <String>{
        'order_id',
        'tender_type',
        'amount_tendered_minor',
      });
      expect(legPayload['tender_type'], 'card');
      expect(w.card.providerCommits, 1, reason: 'recording never charges');
      expect(w.ordinary.attemptedPushes, isEmpty);
      expect(w.detail.fetches, 1, reason: 'the one automatic receipt');
      expect(find.byKey(const Key('card-receipt-unknown')), findsNothing);
      expect(w.drawer.kicks, isEmpty);

      await _tap(tester, 'card-done-button');
      expect(find.byType(CashPaymentSheet), findsNothing);
      expect(w.lastResult, isTrue);
      expect(w.detail.fetches, 1);
    });

    testWidgets('an approval is never "Paid": an unconfirmed recording offers '
        'only resend, check and later; the resend is the SAME leg', (
      tester,
    ) async {
      _size(tester);
      final w = await _world();
      await _pumpHost(tester, w);
      await _open(tester);
      await _tap(tester, 'tender-card-terminal');
      await _tap(tester, 'confirm-payment-button');
      w.card.approve(w.attempt!.attemptId);
      w.card.legFaults.add('lost');
      await _autoCheck(tester);

      expect(_state(ProviderCardPhase.recordingUnconfirmed), findsOneWidget);
      _expectKeys(<String>[
        'card-resend-recording-button',
        'card-check-status-button',
        'card-close-button',
      ], findsOneWidget);
      _expectKeys(<String>[
        'card-done-button',
        'card-other-method-button',
        'card-release-button',
      ], findsNothing);
      expect(find.text(_en.posPaymentDone), findsNothing);

      await _tap(tester, 'card-resend-recording-button');
      expect(_state(ProviderCardPhase.recorded), findsOneWidget);
      expect(w.card.pushedOps, hasLength(2));
      expect(
        w.card.pushedOps[0].toString(),
        w.card.pushedOps[1].toString(),
        reason: 'the same leg',
      );
      expect(w.card.paymentsCreated, 1);
      expect(w.card.edgeCount('start'), 1);
      await _tap(tester, 'card-done-button');
      expect(w.lastResult, isTrue);
    });

    testWidgets('an uncertain start offers ONLY Check status — never a new '
        'start, never another tender — and closing keeps that rule', (
      tester,
    ) async {
      _size(tester);
      final w = await _world();
      w.card.edgeScript.add(
        const CardChargeTransportFailure.uncertain(
          CardChargeFailureReason.transport,
        ),
      );
      await _pumpHost(tester, w);
      await _open(tester);
      await _tap(tester, 'tender-card-terminal');
      await _tap(tester, 'confirm-payment-button');

      void expectUncertain() {
        expect(_state(ProviderCardPhase.uncertain), findsOneWidget);
        _expectKeys(<String>[
          'card-check-status-button',
          'card-close-button',
        ], findsOneWidget);
        _expectKeys(<String>[
          ..._tenders,
          'tender-card-terminal',
          'confirm-payment-button',
          'card-send-again-button',
          'card-other-method-button',
          'card-release-button',
          // BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F-JOURNAL-RECOVERY-CORRECTIONS-
          // 001: no way back to the tender form either.
          'card-back-to-payment-button',
          'card-cancel-request-button',
        ], findsNothing);
      }

      expectUncertain();
      await _tap(tester, 'card-close-button');
      expect(w.lastResult, isFalse);
      await _open(tester);
      expectUncertain();

      // The start did reach the server after all; only a status check says so.
      _serverHas(w.card, w.attempt!.attemptId);
      await _tap(tester, 'card-check-status-button');
      expect(_state(ProviderCardPhase.waiting), findsOneWidget);
      expect(w.card.edgeCount('start'), 1);
      expect(w.ids.calls, 1);
    });

    testWidgets('an open LIVE attempt — waiting, or after a confirmed cancel '
        '— never offers a way back to the tender form, before or after the '
        'sheet is reopened', (tester) async {
      _size(tester);
      final w = await _world();
      await _pumpHost(tester, w);
      await _open(tester);
      await _tap(tester, 'tender-card-terminal');
      await _tap(tester, 'confirm-payment-button');
      final away = <String>[
        'card-back-to-payment-button',
        'card-other-method-button',
        'card-cancel-request-button',
        ..._tenders,
        'tender-card-terminal',
        'confirm-payment-button',
      ];
      expect(_state(ProviderCardPhase.waiting), findsOneWidget);
      _expectKeys(away, findsNothing);
      await _tap(tester, 'card-release-button');
      expect(_state(ProviderCardPhase.released), findsOneWidget);
      _expectKeys(away, findsNothing);
      await _tap(tester, 'card-close-button');
      await _open(tester);
      expect(_state(ProviderCardPhase.released), findsOneWidget);
      _expectKeys(away, findsNothing);
      expect(w.ordinary.attemptedPushes, isEmpty);
    });

    testWidgets('the dark server: card_payments_disabled is a refusal in '
        'words, never a payment; another tender stays possible', (
      tester,
    ) async {
      _size(tester);
      final w = await _world();
      w.card.startsDisabled = true;
      await _pumpHost(tester, w);
      await _open(tester);
      await _tap(tester, 'tender-card-terminal');
      await _tap(tester, 'confirm-payment-button');
      expect(_state(ProviderCardPhase.refused), findsOneWidget);
      expect(find.text(_en.posCardRefusedTitle), findsOneWidget);
      expect(find.byKey(const Key('card-done-button')), findsNothing);
      await _tap(tester, 'card-other-method-button');
      expect(find.byKey(const Key('tender-cash')), findsOneWidget);
      expect(w.card.pushCalls, isEmpty);
      expect(w.ordinary.attemptedPushes, isEmpty);
    });

    testWidgets('closing the sheet stops the automatic checks and keeps the '
        'attempt; reopening resumes them', (tester) async {
      _size(tester);
      final w = await _world();
      await _pumpHost(tester, w);
      await _open(tester);
      await _tap(tester, 'tender-card-terminal');
      await _tap(tester, 'confirm-payment-button');
      final id = w.attempt!.attemptId;

      await _autoCheck(tester);
      expect(w.card.edgeCount('status'), 1);
      expect(w.card.edgeBodies.last['source'], 'auto');

      await _tap(tester, 'card-close-button');
      expect(find.byType(CashPaymentSheet), findsNothing);
      await tester.pump(const Duration(seconds: 60));
      expect(w.card.edgeCount('status'), 1, reason: 'no hidden monitor');
      expect((await w.journal()).attempts.single.attemptId, id);

      await _open(tester);
      await _autoCheck(tester);
      expect(w.card.edgeCount('status'), 2);
      expect(w.card.edgeCount('start'), 1);
    });
  });

  group('fail-closed edges (packet §5.5, §9.1)', () {
    testWidgets('posture unknown: the hand-recorded Card stays on screen; '
        'choosing it reads the posture, and a LIVE till refuses it before '
        'anything is minted or sent', (tester) async {
      _size(tester);
      final w = await _world();
      w.card.capabilitiesThrow = true;
      await _pumpHost(tester, w);
      await _open(tester);
      _expectKeys(_tenders, findsOneWidget);
      expect(find.byKey(const Key('tender-card-terminal')), findsNothing);

      w.card.capabilitiesThrow = false;
      await _tap(tester, 'tender-card');

      _expectKeys(<String>[
        'card-terminal-required',
        'tender-card-terminal',
      ], findsOneWidget);
      expect(find.text(_en.posCardTerminalRequiredNote), findsOneWidget);
      _expectKeys(<String>[
        'tender-card',
        'card-posture-unknown',
      ], findsNothing);
      expect(w.ordinary.attemptedPushes, isEmpty);
      expect(w.till.terminalRequired, 0);
      expect(w.card.edgeBodies, isEmpty);
      expect(w.ids.calls, 0, reason: 'nothing minted');
      expect(w.lastResult, isNull, reason: 'the sheet stays open');
    });

    testWidgets('the send reads it again: a till found LIVE only at Confirm '
        'refuses the hand-recorded Card there', (tester) async {
      _size(tester);
      final w = await _world();
      w.card.capabilitiesThrow = true;
      await _pumpHost(tester, w);
      await _open(tester);
      await _tap(tester, 'tender-card');
      expect(find.byKey(const Key('card-posture-unknown')), findsOneWidget);
      w.card.capabilitiesThrow = false;
      await _tap(tester, 'confirm-payment-button');
      _expectKeys(<String>[
        'card-terminal-required',
        'tender-card-terminal',
      ], findsOneWidget);
      _expectKeys(<String>[
        'tender-card',
        'card-posture-unknown',
      ], findsNothing);
      expect(w.ordinary.attemptedPushes, isEmpty);
      expect(w.till.terminalRequired, 0);
      expect(w.ids.calls, 0);
      expect(w.lastResult, isNull);
    });

    testWidgets('posture still unknown after the re-read: the hand-recorded '
        'Card is held with a note — nothing is minted or sent — and goes '
        'through unchanged once the posture reads as unbound', (tester) async {
      _size(tester);
      final w = await _world();
      w.card.capabilitiesThrow = true;
      await _pumpHost(tester, w);
      await _open(tester);
      final probes = w.card.capabilitiesCalls;
      await _tap(tester, 'tender-card');
      expect(find.byKey(const Key('card-posture-unknown')), findsOneWidget);
      expect(find.text(_en.posCardPostureUnknownNote), findsOneWidget);
      await _tap(tester, 'confirm-payment-button');
      expect(
        w.card.capabilitiesCalls,
        probes + 2,
        reason: 'one read on choosing it, one on sending it',
      );
      expect(find.byKey(const Key('card-posture-unknown')), findsOneWidget);
      expect(find.byKey(const Key('tender-card')), findsOneWidget);
      expect(w.ordinary.attemptedPushes, isEmpty);
      expect(w.till.terminalRequired, 0);
      expect(w.ids.calls, 0, reason: 'nothing minted');
      expect(w.lastResult, isNull, reason: 'the sheet stays open');

      // The probe answers again: this till has no terminal binding.
      w.card.capabilitiesThrow = false;
      w.card.terminalMode = null;
      await _tap(tester, 'confirm-payment-button');
      expect(w.lastResult, isTrue);
      final payload = w.ordinary.paymentOpsSeen.single['payload'] as Map;
      expect(payload['tender_type'], 'card');
      expect(payload['expected_revision'], 7);
      expect(w.card.edgeBodies, isEmpty);
    });

    testWidgets('a binding configured mid-session: the send reads the posture '
        'fresh, and the newly LIVE till refuses the hand-recorded Card', (
      tester,
    ) async {
      _size(tester);
      final w = await _world(card: CardServerFake(terminalMode: null));
      await _pumpHost(tester, w);
      await _open(tester);
      final caps = w.c.read(staffCapabilitiesProvider).valueOrNull;
      await _tap(tester, 'tender-card');
      expect(find.byKey(const Key('card-posture-unknown')), findsNothing);
      // The operator binds this till to a LIVE terminal meanwhile.
      w.card.terminalMode = 'live';
      await _tap(tester, 'confirm-payment-button');
      expect(
        w.c.read(staffCapabilitiesProvider).valueOrNull,
        same(caps),
        reason: 'the read publishes only the card posture',
      );
      _expectKeys(<String>[
        'card-terminal-required',
        'tender-card-terminal',
      ], findsOneWidget);
      expect(find.byKey(const Key('tender-card')), findsNothing);
      expect(w.till.terminalRequired, 0);
      expect(w.ordinary.attemptedPushes, isEmpty);
      expect(w.ids.calls, 0);
      expect(w.lastResult, isNull);
    });

    testWidgets('a till proven unbound whose probe fails at the send holds '
        'the hand-recorded Card until the probe answers (packet §9.1)', (
      tester,
    ) async {
      _size(tester);
      final w = await _world(card: CardServerFake(terminalMode: null));
      await _pumpHost(tester, w);
      await _open(tester);
      await _tap(tester, 'tender-card');
      w.card.capabilitiesThrow = true;
      await _tap(tester, 'confirm-payment-button');
      expect(find.byKey(const Key('card-posture-unknown')), findsOneWidget);
      expect(w.ordinary.attemptedPushes, isEmpty);
      expect(w.lastResult, isNull);
      w.card.capabilitiesThrow = false;
      await _tap(tester, 'confirm-payment-button');
      expect(w.lastResult, isTrue);
      final payload = w.ordinary.paymentOpsSeen.single['payload'] as Map;
      expect(payload['tender_type'], 'card');
      expect(payload['expected_revision'], 7);
    });

    testWidgets('a send-time read that fails holds the hand-recorded Card and '
        'leaves the PIN session\'s capabilities as they were', (tester) async {
      _size(tester);
      final w = await _world(card: CardServerFake(terminalMode: null));
      await _pumpHost(tester, w);
      await _open(tester);
      final caps = w.c.read(staffCapabilitiesProvider).valueOrNull;
      expect(caps, isNotNull);
      await _tap(tester, 'tender-card');
      w.card.capabilitiesThrow = true;
      final probes = w.card.capabilitiesCalls;
      await _tap(tester, 'confirm-payment-button');
      expect(find.byKey(const Key('card-posture-unknown')), findsOneWidget);
      expect(w.card.capabilitiesCalls, probes + 1);
      expect(
        w.c.read(staffCapabilitiesProvider).valueOrNull,
        same(caps),
        reason: 'one failed card read changes nothing else on the till',
      );
      expect(w.ordinary.attemptedPushes, isEmpty);
      expect(w.lastResult, isNull);
    });

    testWidgets('a terminal choice whose option goes away falls back to Cash, '
        'never to the hand-recorded Card', (tester) async {
      _size(tester);
      final w = await _world();
      await _pumpHost(tester, w);
      await _open(tester);
      await _tap(tester, 'tender-card-terminal');
      w.card.capabilitiesThrow = true;
      w.c.invalidate(staffCapabilitiesProvider);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tender-card-terminal')), findsNothing);
      ChoiceChip chip(String key) =>
          tester.widget<ChoiceChip>(find.byKey(Key(key)));
      expect(chip('tender-cash').selected, isTrue);
      expect(chip('tender-card').selected, isFalse);
      expect(find.text(_en.posConfirmPayment), findsOneWidget);
      await _tap(tester, 'confirm-payment-button');
      expect(w.card.edgeBodies, isEmpty);
      expect(w.ordinary.attemptedPushes, isEmpty);
    });

    testWidgets('a quarantined journal is explained and blocks new starts; '
        'nothing is sent and nothing is rewritten', (tester) async {
      _size(tester);
      const unreadable = '{"version":2,"attempts":[]}';
      final key = providerCardAttemptsStorageKey(kCardScope.key);
      final w = await _world(prefs: <String, Object>{key: unreadable});
      await _pumpHost(tester, w);
      await _open(tester);
      expect(find.byKey(const Key('card-journal-quarantined')), findsOneWidget);
      expect(find.text(_en.posCardJournalQuarantinedTitle), findsOneWidget);
      await _tap(tester, 'tender-card-terminal');
      await _tap(tester, 'confirm-payment-button');
      expect(find.byKey(const Key('card-attempt-view')), findsNothing);
      expect(w.card.edgeBodies, isEmpty);
      expect(w.ids.calls, 0);
      expect(w.prefs.getString(key), unreadable);
    });
  });

  group('the view in flight, covered and rebuilt (packet §7, §10)', () {
    const actions = <String>[
      'card-send-again-button',
      'card-cancel-request-button',
      'card-other-method-button',
      'card-check-status-button',
      'card-release-button',
      'card-resend-recording-button',
      'card-resume-button',
      'card-manager-send-button',
      'card-done-button',
      'card-back-to-payment-button',
      'card-close-button',
    ];

    testWidgets('while this device starts the attempt the view says it is '
        'preparing, with no action; then it waits', (tester) async {
      _size(tester);
      final w = await _world();
      await _pumpHost(tester, w);
      await _open(tester);
      await _tap(tester, 'tender-card-terminal');
      final hold = Completer<void>();
      w.card.holdEdge = hold;
      await tester.tap(find.byKey(const Key('confirm-payment-button')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('card-state-preparing')), findsOneWidget);
      expect(find.text(_en.posCardPreparingTitle), findsOneWidget);
      expect(_state(ProviderCardPhase.notSent), findsNothing);
      expect(_state(ProviderCardPhase.uncertain), findsNothing);
      _expectKeys(actions, findsNothing);
      expect((await w.journal()).attempts.single.startInDoubt, isTrue);
      hold.complete();
      await tester.pumpAndSettle();
      expect(_state(ProviderCardPhase.waiting), findsOneWidget);
      expect(find.byKey(const Key('card-state-preparing')), findsNothing);
    });

    testWidgets('a route over the sheet pauses the automatic checks; '
        'uncovering it resumes them', (tester) async {
      _size(tester);
      final w = await _world();
      await _pumpHost(tester, w);
      await _open(tester);
      await _tap(tester, 'tender-card-terminal');
      await _tap(tester, 'confirm-payment-button');
      await _autoCheck(tester);
      expect(w.card.edgeCount('status'), 1);
      unawaited(
        showDialog<void>(
          context: tester.element(find.byKey(const Key('card-attempt-view'))),
          builder: (_) => const SizedBox(key: Key('cover')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 30));
      expect(w.card.edgeCount('status'), 1, reason: 'covered: no check');
      Navigator.of(tester.element(find.byKey(const Key('cover')))).pop();
      await tester.pumpAndSettle();
      await _autoCheck(tester);
      expect(w.card.edgeCount('status'), 2);
    });

    testWidgets('a set-aside the journal refuses keeps the card view; it is '
        'left only once it is stored', (tester) async {
      _size(tester);
      // A 401: no start can have had an effect, so taking payment another way
      // sets the attempt aside (correction packet §4: never an unresolved
      // TEST attempt, which is only left).
      final w = await _world();
      w.card.edgeScript.add((
        401,
        <String, Object?>{'ok': false, 'error': 'invalid_session'},
      ));
      await _pumpHost(tester, w);
      await _open(tester);
      await _tap(tester, 'tender-card-terminal');
      await _tap(tester, 'confirm-payment-button');
      expect(_state(ProviderCardPhase.authRequired), findsOneWidget);
      w.store.failUpdates = 1;
      await _tap(tester, 'card-other-method-button');
      expect(find.byKey(const Key('card-attempt-view')), findsOneWidget);
      expect(find.byKey(const Key('card-note-saveFailed')), findsOneWidget);
      await _tap(tester, 'card-other-method-button');
      expect(find.byKey(const Key('card-attempt-view')), findsNothing);
      expect(
        (await w.journal()).attempts.single.closed,
        ProviderCardClosure.setAside,
      );
    });

    testWidgets('another PIN session holds every tender while the card '
        'journal is read again', (tester) async {
      _size(tester);
      final w = await _world();
      await _pumpHost(tester, w);
      await _open(tester);
      await _tap(tester, 'tender-bit');
      FilledButton confirm() => tester.widget<FilledButton>(
        find.byKey(const Key('confirm-payment-button')),
      );
      expect(confirm().onPressed, isNotNull);
      final hold = Completer<void>();
      w.store.holdLoad = hold;
      w.c.read(cardSessionProvider.notifier).state = const SyncSession(
        pinSessionId: kCardPin2,
        deviceId: kCardDevice,
      );
      await tester.pump();
      expect(
        confirm().onPressed,
        isNull,
        reason: 'held while the journal is read again',
      );
      hold.complete();
      await tester.pumpAndSettle();
      expect(confirm().onPressed, isNotNull);
    });

    testWidgets('while a send reads the posture the lab switch is held, and a '
        'card attempt that covers the form meanwhile stops the hand-recorded '
        'Card', (tester) async {
      _size(tester);
      final w = await _world(card: CardServerFake(terminalMode: 'test'));
      await _pumpHost(tester, w);
      await _open(tester);
      expect(find.byKey(const Key('card-attempt-view')), findsNothing);
      await _tap(tester, 'tender-card');
      final hold = Completer<void>();
      w.card.capabilitiesHold = hold;
      await tester.tap(find.byKey(const Key('confirm-payment-button')));
      await tester.pump();
      final lab = tester.widget<SwitchListTile>(
        find.byKey(const Key('card-terminal-lab-switch')),
      );
      expect(lab.onChanged, isNull, reason: 'held while the posture is read');
      // A TEST attempt for this order starts another way meanwhile (an
      // unresolved TEST attempt covers the form whatever the lab).
      w.c.read(providerCardLabEnabledProvider.notifier).state = true;
      expect(
        await w.c
            .read(providerCardControllerProvider.notifier)
            .start(
              identity: PosOrderIdentity.server(kCardOrder),
              orderId: kCardOrder,
              orderNumber: '#A1',
              amountMinor: 1200,
              currencyCode: 'ILS',
              expectedRevision: 7,
              mode: ProviderCardMode.test,
            ),
        ProviderCardStartRequest.started,
      );
      await tester.pump();
      expect(find.byKey(const Key('card-attempt-view')), findsOneWidget);
      hold.complete();
      await tester.pumpAndSettle();
      expect(w.ordinary.attemptedPushes, isEmpty);
      expect(w.lastResult, isNull);
      expect(find.byKey(const Key('card-attempt-view')), findsOneWidget);
    });
  });

  group('the card view alone (packet §7.3)', () {
    /// Starts an attempt of [mode] through the controller and shows its view
    /// alone; returns its id and how often the view left for the form.
    Future<(String, int Function())> viewAlone(
      WidgetTester tester,
      _World w,
      ProviderCardMode mode,
    ) async {
      if (mode == ProviderCardMode.test) {
        w.c.read(providerCardLabEnabledProvider.notifier).state = true;
      }
      await w.c.read(staffCapabilitiesProvider.future);
      final ctrl = w.c.read(providerCardControllerProvider.notifier);
      await ctrl.ensureHydrated();
      expect(
        await ctrl.start(
          identity: PosOrderIdentity.server(kCardOrder),
          orderId: kCardOrder,
          orderNumber: '#A1',
          amountMinor: 1200,
          currencyCode: 'ILS',
          expectedRevision: 7,
          mode: mode,
        ),
        ProviderCardStartRequest.started,
      );
      final id = w.attempt!.attemptId;
      var left = 0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: w.c,
          child: MaterialApp(
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(
              body: ProviderCardPaymentView(
                attemptId: id,
                onTakeAnotherWay: () => left++,
                onRecorded: (_) {},
                onDone: () {},
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (id, () => left);
    }

    testWidgets('it leaves for the tender form only once a set-aside is '
        'stored', (tester) async {
      _size(tester);
      final w = await _world();
      w.card.edgeScript.add((
        401,
        <String, Object?>{'ok': false, 'error': 'invalid_session'},
      ));
      final (_, left) = await viewAlone(tester, w, ProviderCardMode.live);
      expect(_state(ProviderCardPhase.authRequired), findsOneWidget);
      w.store.failUpdates = 1;
      await _tap(tester, 'card-other-method-button');
      expect(left(), 0, reason: 'not stored: the attempt is still open');
      expect(find.byKey(const Key('card-note-saveFailed')), findsOneWidget);
      await _tap(tester, 'card-other-method-button');
      expect(left(), 1);
    });

    testWidgets('an unresolved TEST attempt offers no way back and no '
        'set-aside — waiting, or after a confirmed cancel — only Check status, '
        'Cancel on the terminal while it waits, and "Close and resume later" '
        '(correction packet §4)', (tester) async {
      _size(tester);
      final w = await _world(card: CardServerFake(terminalMode: 'test'));
      final (id, left) = await viewAlone(tester, w, ProviderCardMode.test);
      const leaving = <String>[
        'card-back-to-payment-button',
        'card-other-method-button',
        'card-cancel-request-button',
      ];
      expect(_state(ProviderCardPhase.testWaiting), findsOneWidget);
      _expectKeys(<String>[
        'card-check-status-button',
        'card-release-button',
        'card-close-button',
      ], findsOneWidget);
      _expectKeys(leaving, findsNothing);
      // The close button keeps the attempt (fix-delta review FR-6).
      expect(find.text(_en.posPaymentCloseResumeLater), findsOneWidget);
      expect(find.text(_en.posCardClose), findsNothing);
      await _tap(tester, 'card-release-button');
      expect(_state(ProviderCardPhase.testReleased), findsOneWidget);
      _expectKeys(<String>[
        'card-check-status-button',
        'card-close-button',
      ], findsOneWidget);
      _expectKeys(<String>[...leaving, 'card-release-button'], findsNothing);
      // The close button keeps the attempt (fix-delta review FR-6).
      expect(find.text(_en.posPaymentCloseResumeLater), findsOneWidget);
      expect(find.text(_en.posCardClose), findsNothing);
      expect(left(), 0);
      final stored = (await w.journal()).attempts.single;
      expect(stored.attemptId, id);
      expect(stored.closed, isNull);
      expect(stored.isOpen, isTrue);
    });
  });

  // BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F-JOURNAL-RECOVERY-CORRECTIONS-001.
  group('an unresolved TEST attempt stays recoverable '
      '(correction packet §4)', () {
    // No automatic check runs in these tests: every request is explicit.
    const quiet = ProviderCardPollPolicy(
      firstDelay: Duration(hours: 1),
      interval: Duration(hours: 1),
    );
    final key = providerCardAttemptsStorageKey(kCardScope.key);
    int operatorChecks(_World w) => w.card.edgeBodies
        .where((b) => b['action'] == 'status' && b['source'] == 'operator')
        .length;
    const leaving = <String>[
      'card-back-to-payment-button',
      'card-other-method-button',
      'card-cancel-request-button',
    ];

    /// Opens the sheet in the lab and starts a TEST attempt (test waiting).
    Future<String> startInLab(WidgetTester tester, _World w) async {
      await _pumpHost(tester, w);
      await _open(tester);
      await _tap(tester, 'card-terminal-lab-switch');
      await _tap(tester, 'tender-card-terminal');
      await _tap(tester, 'confirm-payment-button');
      expect(_state(ProviderCardPhase.testWaiting), findsOneWidget);
      return w.attempt!.attemptId;
    }

    testWidgets('with the lab off after a PIN switch it covers every tender of '
        'its order, with no way back; Check status asks about the same '
        'attempt and starts nothing; a reopened sheet shows it again', (
      tester,
    ) async {
      _size(tester);
      final w = await _world(
        card: CardServerFake(terminalMode: 'test'),
        policy: quiet,
      );
      final id = await startInLab(tester, w);
      await _tap(tester, 'card-close-button');
      expect(find.byType(CashPaymentSheet), findsNothing);

      // Another person signs in: the lab is off again.
      w.c.read(cardSessionProvider.notifier).state = const SyncSession(
        pinSessionId: kCardPin2,
        deviceId: kCardDevice,
      );
      await tester.pumpAndSettle();
      expect(w.c.read(providerCardLabEnabledProvider), isFalse);

      void expectRecoverySurface() {
        expect(_state(ProviderCardPhase.testWaiting), findsOneWidget);
        expect(find.byKey(const Key('card-test-badge')), findsOneWidget);
        _expectKeys(<String>[
          'card-check-status-button',
          'card-close-button',
        ], findsOneWidget);
        _expectKeys(<String>[
          ...leaving,
          ..._tenders,
          'tender-card-terminal',
          'confirm-payment-button',
        ], findsNothing);
      }

      await _open(tester);
      expectRecoverySurface();
      await _tap(tester, 'card-check-status-button');
      expect(operatorChecks(w), 1);
      expect(w.card.edgeBodies.last['attempt_id'], id);
      expectRecoverySurface();

      await _tap(tester, 'card-close-button');
      await _open(tester);
      expectRecoverySurface();
      await _tap(tester, 'card-check-status-button');
      expect(operatorChecks(w), 2);
      expect(w.card.edgeBodies.last['attempt_id'], id);
      expect(w.card.edgeCount('start'), 1, reason: 'never started again');
      expect(w.ids.calls, 1, reason: 'one identity');
      expect(w.card.pushCalls, isEmpty, reason: 'no payment.create');
      expect(w.ordinary.attemptedPushes, isEmpty, reason: 'no other tender');
      expect(w.detail.fetches, 0, reason: 'no receipt');
      expect(find.byKey(const Key('card-done-button')), findsNothing);
      expect(_state(ProviderCardPhase.recorded), findsNothing);
      final stored = (await w.journal()).attempts.single;
      expect(stored.attemptId, id);
      expect(stored.closed, isNull);
    });

    testWidgets('a TEST result not confirmed stays in sight after a restart '
        'with the lab off, covering every tender, never set aside; Check '
        'status asks about it and nothing starts again', (tester) async {
      _size(tester);
      final server = CardServerFake(terminalMode: 'test');
      final w = await _world(card: server, policy: quiet);
      server.edgeScript.add(
        const CardChargeTransportFailure.uncertain(
          CardChargeFailureReason.transport,
        ),
      );
      await _pumpHost(tester, w);
      await _open(tester);
      await _tap(tester, 'card-terminal-lab-switch');
      await _tap(tester, 'tender-card-terminal');
      await _tap(tester, 'confirm-payment-button');
      expect(_state(ProviderCardPhase.uncertain), findsOneWidget);
      final id = w.attempt!.attemptId;
      final stored = w.prefs.getString(key)!;
      await _tap(tester, 'card-close-button');
      await tester.pumpWidget(const SizedBox());

      // A restart: a new process over the same journal, the lab off.
      final restarted = await _world(
        card: server,
        prefs: <String, Object>{key: stored},
        policy: quiet,
      );
      await _pumpHost(tester, restarted);
      await _open(tester);
      expect(_state(ProviderCardPhase.uncertain), findsOneWidget);
      expect(restarted.attempt!.attemptId, id);
      _expectKeys(<String>[
        ...leaving,
        ..._tenders,
        'tender-card-terminal',
        'confirm-payment-button',
      ], findsNothing);
      await _tap(tester, 'card-check-status-button');
      expect(operatorChecks(restarted), 1);
      expect(restarted.card.edgeBodies.last['attempt_id'], id);
      expect(
        restarted.prefs.getString(key),
        stored,
        reason: 'an answer inside the settle window records nothing',
      );
      expect(server.edgeCount('start'), 1, reason: 'never started again');
      expect(restarted.ids.calls, 0);
      final again = (await restarted.journal()).attempts.single;
      expect(again.attemptId, id);
      expect(again.closed, isNull);
      expect(again.isOpen, isTrue);
    });

    testWidgets('a final TEST result is out of sight with the lab off', (
      tester,
    ) async {
      _size(tester);
      final w = await _world(
        card: CardServerFake(terminalMode: 'test'),
        policy: quiet,
      );
      await startInLab(tester, w);
      w.card.approve(w.attempt!.attemptId);
      await _tap(tester, 'card-check-status-button');
      expect(_state(ProviderCardPhase.testApproved), findsOneWidget);
      await _tap(tester, 'card-close-button');
      w.c.read(providerCardLabEnabledProvider.notifier).state = false;
      await tester.pumpAndSettle();
      await _open(tester);
      expect(find.byKey(const Key('card-attempt-view')), findsNothing);
      _expectKeys(_tenders, findsOneWidget);
    });

    testWidgets('a TEST attempt this sheet shows with the lab off stays in '
        'sight when it turns final, until the cashier leaves it', (
      tester,
    ) async {
      _size(tester);
      final w = await _world(
        card: CardServerFake(terminalMode: 'test'),
        policy: quiet,
      );
      final id = await startInLab(tester, w);
      await _tap(tester, 'card-close-button');
      w.c.read(providerCardLabEnabledProvider.notifier).state = false;
      await tester.pumpAndSettle();
      await _open(tester);
      expect(_state(ProviderCardPhase.testWaiting), findsOneWidget);
      w.card.approve(id);
      await _tap(tester, 'card-check-status-button');
      expect(
        _state(ProviderCardPhase.testApproved),
        findsOneWidget,
        reason: 'a result this sheet showed stays until it is left',
      );
      expect(find.byKey(const Key('card-done-button')), findsNothing);
      await _tap(tester, 'card-back-to-payment-button');
      expect(find.byKey(const Key('card-attempt-view')), findsNothing);
      _expectKeys(_tenders, findsOneWidget);
      expect(w.card.pushCalls, isEmpty);
    });

    testWidgets('after a confirmed cancel the TEST attempt still covers its '
        'order: no way back and no hand-recorded Card until it is final', (
      tester,
    ) async {
      _size(tester);
      final w = await _world(
        card: CardServerFake(terminalMode: 'test'),
        policy: quiet,
      );
      final id = await startInLab(tester, w);
      await _tap(tester, 'card-release-button');
      expect(_state(ProviderCardPhase.testReleased), findsOneWidget);
      _expectKeys(<String>[...leaving, ..._tenders], findsNothing);
      await _tap(tester, 'card-close-button');
      await _open(tester);
      expect(_state(ProviderCardPhase.testReleased), findsOneWidget);
      _expectKeys(<String>[...leaving, ..._tenders], findsNothing);
      // The provider's lookup finds the test declined: final, so it may go.
      w.card.nextLookupState[id] = 'declined';
      await _tap(tester, 'card-check-status-button');
      expect(_state(ProviderCardPhase.testDeclined), findsOneWidget);
      await _tap(tester, 'card-back-to-payment-button');
      _expectKeys(_tenders, findsOneWidget);
      expect(w.ordinary.attemptedPushes, isEmpty);
      expect(w.card.pushCalls, isEmpty);
    });

    testWidgets('a TEST attempt that turns to reconciliation keeps covering, '
        'with no way back', (tester) async {
      _size(tester);
      final w = await _world(
        card: CardServerFake(terminalMode: 'test'),
        policy: quiet,
      );
      final id = await startInLab(tester, w);
      // The server answers a LIVE envelope for this TEST identity: a stop.
      w.card.edgeScript.add((
        200,
        w.card.envelope(
          FakeCardAttempt(
            id: id,
            mode: 'live',
            amountMinor: 1200,
            currencyCode: 'ILS',
            orderId: kCardOrder,
            expectedRevision: 7,
          ),
        ),
      ));
      await _tap(tester, 'card-check-status-button');
      expect(_state(ProviderCardPhase.reconciliation), findsOneWidget);
      expect(w.attempt!.safetyStop, ProviderCardSafetyStop.modeMismatch);
      _expectKeys(<String>[...leaving, ..._tenders], findsNothing);
      w.c.read(providerCardLabEnabledProvider.notifier).state = false;
      await tester.pumpAndSettle();
      expect(_state(ProviderCardPhase.reconciliation), findsOneWidget);
      _expectKeys(<String>[...leaving, ..._tenders], findsNothing);
    });
  });

  // BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F-JOURNAL-RECOVERY-CORRECTIONS-001, the
  // fix-delta review (FR-1): once a card attempt lets the order go, the order
  // is PAID on this till — the tender form is not only shown, Confirm works.
  group('once a card attempt lets the order go it is paid on this till '
      '(correction packet §4.2)', () {
    // No automatic check runs in these tests: every request is explicit.
    const quiet = ProviderCardPollPolicy(
      firstDelay: Duration(hours: 1),
      interval: Duration(hours: 1),
    );
    final key = providerCardAttemptsStorageKey(kCardScope.key);

    /// From the tender form: exact cash, then Confirm; the ordinary payload.
    Future<Map> payCash(WidgetTester tester, _World w) async {
      expect(find.byKey(const Key('card-attempt-view')), findsNothing);
      await _tap(tester, 'tender-cash');
      await tester.enterText(
        find.byKey(const Key('cash-received-field')),
        '12.00',
      );
      await tester.pumpAndSettle();
      final confirm = tester.widget<FilledButton>(
        find.byKey(const Key('confirm-payment-button')),
      );
      expect(confirm.onPressed, isNotNull, reason: 'Confirm is live');
      await _tap(tester, 'confirm-payment-button');
      expect(w.lastResult, isTrue, reason: 'paid on this till');
      return w.ordinary.paymentOpsSeen.single['payload'] as Map;
    }

    testWidgets('a final TEST result shown with the lab off is left, then '
        'cash pays with expected_revision', (tester) async {
      _size(tester);
      final w = await _world(
        card: CardServerFake(terminalMode: 'test'),
        policy: quiet,
      );
      await _pumpHost(tester, w);
      await _open(tester);
      await _tap(tester, 'card-terminal-lab-switch');
      await _tap(tester, 'tender-card-terminal');
      await _tap(tester, 'confirm-payment-button');
      final id = w.attempt!.attemptId;
      await _tap(tester, 'card-close-button');
      w.c.read(providerCardLabEnabledProvider.notifier).state = false;
      await tester.pumpAndSettle();
      await _open(tester);
      expect(_state(ProviderCardPhase.testWaiting), findsOneWidget);
      w.card.approve(id);
      await _tap(tester, 'card-check-status-button');
      expect(_state(ProviderCardPhase.testApproved), findsOneWidget);
      await _tap(tester, 'card-back-to-payment-button');
      final payload = await payCash(tester, w);
      expect(payload['tender_type'], 'cash');
      expect(payload['expected_revision'], 7);
      expect(w.card.pushCalls, isEmpty, reason: 'no TEST recording leg');
    });

    testWidgets('a never-sent TEST attempt with the lab off: "Send the same '
        'request" sends nothing; Cancel this request, then cash pays', (
      tester,
    ) async {
      _size(tester);
      final a = cardStoredAttempt(
        5,
        order: kCardOrder,
        mode: ProviderCardMode.test,
      );
      expect(a.phase, ProviderCardPhase.notSent);
      final w = await _world(
        card: CardServerFake(terminalMode: 'test'),
        prefs: <String, Object>{
          key: cardJournalEnvelope([a]),
        },
        policy: quiet,
      );
      await _pumpHost(tester, w);
      await _open(tester);
      expect(w.c.read(providerCardLabEnabledProvider), isFalse);
      expect(_state(ProviderCardPhase.notSent), findsOneWidget);
      _expectKeys(<String>[
        ..._tenders,
        'card-terminal-lab-switch',
      ], findsNothing);
      await _tap(tester, 'card-send-again-button');
      expect(w.card.edgeBodies, isEmpty, reason: 'no TEST start, lab off');
      expect(
        find.byKey(const Key('card-note-terminalUnavailable')),
        findsOneWidget,
      );
      expect(_state(ProviderCardPhase.notSent), findsOneWidget);
      await _tap(tester, 'card-cancel-request-button');
      expect(
        (await w.journal()).attempts.single.closed,
        ProviderCardClosure.abandoned,
      );
      final payload = await payCash(tester, w);
      expect(payload['tender_type'], 'cash');
      expect(payload['expected_revision'], 7);
      expect(w.card.edgeBodies, isEmpty);
      expect(w.card.pushCalls, isEmpty);
    });

    testWidgets('a settled not-found TEST attempt with the lab off: Take '
        'payment another way, then cash pays', (tester) async {
      _size(tester);
      final at = kCardNow.toUtc().toIso8601String();
      final a = cardInDoubt(
        cardStoredAttempt(5, order: kCardOrder, mode: ProviderCardMode.test),
      ).copyWith(serverNotFoundAt: at, updatedAt: at);
      expect(a.phase, ProviderCardPhase.notFound);
      final w = await _world(
        card: CardServerFake(terminalMode: 'test'),
        prefs: <String, Object>{
          key: cardJournalEnvelope([a]),
        },
        policy: quiet,
      );
      await _pumpHost(tester, w);
      await _open(tester);
      expect(_state(ProviderCardPhase.notFound), findsOneWidget);
      _expectKeys(_tenders, findsNothing);
      await _tap(tester, 'card-other-method-button');
      expect(
        (await w.journal()).attempts.single.closed,
        ProviderCardClosure.setAside,
      );
      final payload = await payCash(tester, w);
      expect(payload['tender_type'], 'cash');
      expect(payload['expected_revision'], 7);
      expect(w.card.edgeBodies, isEmpty);
    });

    testWidgets('a never-sent LIVE attempt: Cancel this request, then cash '
        'pays', (tester) async {
      _size(tester);
      final a = cardStoredAttempt(5, order: kCardOrder);
      expect(a.phase, ProviderCardPhase.notSent);
      final w = await _world(
        prefs: <String, Object>{
          key: cardJournalEnvelope([a]),
        },
        policy: quiet,
      );
      await _pumpHost(tester, w);
      await _open(tester);
      expect(_state(ProviderCardPhase.notSent), findsOneWidget);
      _expectKeys(_tenders, findsNothing);
      await _tap(tester, 'card-cancel-request-button');
      final payload = await payCash(tester, w);
      expect(payload['tender_type'], 'cash');
      expect(payload['expected_revision'], 7);
      expect(w.card.edgeBodies, isEmpty);
    });

    testWidgets('a settled not-found LIVE attempt: Take payment another way, '
        'then cash pays', (tester) async {
      _size(tester);
      final at = kCardNow.toUtc().toIso8601String();
      final a = cardInDoubt(
        cardStoredAttempt(5, order: kCardOrder),
      ).copyWith(serverNotFoundAt: at, updatedAt: at);
      expect(a.phase, ProviderCardPhase.notFound);
      final w = await _world(
        prefs: <String, Object>{
          key: cardJournalEnvelope([a]),
        },
        policy: quiet,
      );
      await _pumpHost(tester, w);
      await _open(tester);
      expect(_state(ProviderCardPhase.notFound), findsOneWidget);
      await _tap(tester, 'card-other-method-button');
      final payload = await payCash(tester, w);
      expect(payload['tender_type'], 'cash');
      expect(payload['expected_revision'], 7);
    });

    testWidgets('a LIVE start answered "sign in again": Take payment another '
        'way, then cash pays', (tester) async {
      _size(tester);
      final w = await _world(policy: quiet);
      w.card.edgeScript.add((
        401,
        <String, Object?>{'ok': false, 'error': 'invalid_session'},
      ));
      await _pumpHost(tester, w);
      await _open(tester);
      await _tap(tester, 'tender-card-terminal');
      await _tap(tester, 'confirm-payment-button');
      expect(_state(ProviderCardPhase.authRequired), findsOneWidget);
      await _tap(tester, 'card-other-method-button');
      final payload = await payCash(tester, w);
      expect(payload['tender_type'], 'cash');
      expect(payload['expected_revision'], 7);
    });

    testWidgets('in the lab a final TEST result is left and the hand-recorded '
        'Card is recorded with expected_revision', (tester) async {
      _size(tester);
      final w = await _world(
        card: CardServerFake(terminalMode: 'test'),
        policy: quiet,
      );
      await _pumpHost(tester, w);
      await _open(tester);
      await _tap(tester, 'card-terminal-lab-switch');
      await _tap(tester, 'tender-card-terminal');
      await _tap(tester, 'confirm-payment-button');
      w.card.approve(w.attempt!.attemptId);
      await _tap(tester, 'card-check-status-button');
      expect(_state(ProviderCardPhase.testApproved), findsOneWidget);
      await _tap(tester, 'card-back-to-payment-button');
      expect(find.byKey(const Key('card-attempt-view')), findsNothing);
      await _tap(tester, 'tender-card');
      await _tap(tester, 'confirm-payment-button');
      expect(w.lastResult, isTrue, reason: 'the hand-recorded Card was sent');
      final payload = w.ordinary.paymentOpsSeen.single['payload'] as Map;
      expect(payload['tender_type'], 'card');
      expect(payload['expected_revision'], 7);
      expect(w.card.pushCalls, isEmpty, reason: 'no TEST recording leg');
    });
  });

  // BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F-JOURNAL-RECOVERY-CORRECTIONS-001, the
  // fix-delta review (FR-3): open TEST attempts now always compete for the
  // form, and an open LIVE attempt of the order still comes first.
  group('an open LIVE attempt covers the form before a newer open TEST one '
      '(correction packet §4.2)', () {
    for (final mode in <String>['live', 'test']) {
      for (final lab in <bool>[false, true]) {
        testWidgets('$mode till, lab ${lab ? 'on' : 'off'}: an open LIVE '
            'attempt and a newer open TEST attempt of the order — the LIVE one '
            'is shown and checked', (tester) async {
          _size(tester);
          final live = cardInDoubt(cardStoredAttempt(7, order: kCardOrder));
          final trial = cardInDoubt(
            cardStoredAttempt(
              8,
              order: kCardOrder,
              mode: ProviderCardMode.test,
            ),
          );
          final w = await _world(
            card: CardServerFake(terminalMode: mode),
            prefs: <String, Object>{
              providerCardAttemptsStorageKey(kCardScope.key):
                  cardJournalEnvelope([live, trial]),
            },
          );
          if (lab) {
            await w.c.read(staffCapabilitiesProvider.future);
            w.c.read(providerCardLabEnabledProvider.notifier).state = true;
          }
          await _pumpHost(tester, w);
          await _open(tester);
          expect(_state(ProviderCardPhase.uncertain), findsOneWidget);
          expect(find.byKey(const Key('card-test-badge')), findsNothing);
          expect(find.text(_en.posCardAttemptTitle), findsOneWidget);
          expect(find.text(_en.posCardAttemptTestTitle), findsNothing);
          _expectKeys(_tenders, findsNothing);
          // The LIVE view holds the lease: its first automatic check is
          // about the LIVE attempt.
          await _autoCheck(tester);
          expect(w.card.edgeCount('status'), 1);
          expect(w.card.edgeBodies.last['attempt_id'], cardV4(7));
        });
      }
    }

    testWidgets('a LIVE attempt kept in doubt beside a newer TEST attempt of '
        'the order covers the form again after a PIN switch', (tester) async {
      _size(tester);
      final w = await _world();
      await _pumpHost(tester, w);
      await _open(tester);
      // A LIVE start the server refuses, whose answer could not be saved: in
      // memory it is refused, in the journal it may have been sent.
      w.card.startsDisabled = true;
      w.card.onEdge = (body) {
        if (body['action'] == 'start') w.store.failUpdates = 1;
      };
      await _tap(tester, 'tender-card-terminal');
      await _tap(tester, 'confirm-payment-button');
      w.card
        ..onEdge = null
        ..startsDisabled = false;
      expect(_state(ProviderCardPhase.refused), findsOneWidget);
      expect(
        (await w.journal()).attempts.single.phase,
        ProviderCardPhase.uncertain,
      );
      await _tap(tester, 'card-other-method-button');
      // The till is read again as a TEST till; in the lab a TEST start for
      // the same order is admitted (another mode).
      w.card.terminalMode = 'test';
      w.c.invalidate(staffCapabilitiesProvider);
      await w.c.read(staffCapabilitiesProvider.future);
      await tester.pumpAndSettle();
      _drainTenderFormOverflow(tester);
      await _tap(tester, 'card-terminal-lab-switch');
      await _tap(tester, 'tender-card-terminal');
      await _tap(tester, 'confirm-payment-button');
      expect(find.byKey(const Key('card-test-badge')), findsOneWidget);
      expect(
        [
          for (final a in (await w.journal()).attempts)
            '${a.mode.wire}:${a.phase.name}',
        ],
        ['live:uncertain', 'test:testWaiting'],
      );
      // A PIN switch reads the journal again: the LIVE attempt covers.
      w.c.read(cardSessionProvider.notifier).state = const SyncSession(
        pinSessionId: kCardPin2,
        deviceId: kCardDevice,
      );
      await tester.pumpAndSettle();
      _drainTenderFormOverflow(tester);
      expect(_state(ProviderCardPhase.uncertain), findsOneWidget);
      expect(find.byKey(const Key('card-test-badge')), findsNothing);
      await _autoCheck(tester);
      expect(w.card.edgeBodies.last['action'], 'status');
      expect(w.card.edgeBodies.last['attempt_id'], cardV4(1));
    });
  });

  group('the journal bound and envelope uniqueness '
      '(correction packet §5, §6)', () {
    final key = providerCardAttemptsStorageKey(kCardScope.key);

    testWidgets('at the bound a card start is refused in words — not as an '
        'unreadable journal — and nothing is minted, written or sent', (
      tester,
    ) async {
      _size(tester);
      final stored = cardJournalEnvelope(<ProviderCardAttempt>[
        for (var i = 0; i < kProviderCardJournalCap; i++)
          cardInDoubt(cardStoredAttempt(100 + i, order: cardOrderN(i))),
      ]);
      final w = await _world(prefs: <String, Object>{key: stored});
      await _pumpHost(tester, w);
      await _open(tester);
      await _tap(tester, 'tender-card-terminal');
      await _tap(tester, 'confirm-payment-button');
      expect(find.byKey(const Key('card-start-issue')), findsOneWidget);
      expect(find.text(_en.posCardJournalFullNote), findsOneWidget);
      expect(find.byKey(const Key('card-journal-quarantined')), findsNothing);
      expect(find.byKey(const Key('card-attempt-view')), findsNothing);
      expect(w.card.edgeBodies, isEmpty);
      expect(w.ids.calls, 0);
      expect(w.prefs.getString(key), stored);
    });

    testWidgets('a journal holding one attempt twice is quarantined in words; '
        'nothing is shown, sent or rewritten', (tester) async {
      _size(tester);
      final a = cardInDoubt(cardStoredAttempt(5, order: kCardOrder));
      final raw = cardJournalEnvelope([a, a]);
      final w = await _world(prefs: <String, Object>{key: raw});
      await _pumpHost(tester, w);
      await _open(tester);
      expect(
        find.byKey(const Key('card-attempt-view')),
        findsNothing,
        reason: 'no copy is chosen',
      );
      expect(find.byKey(const Key('card-journal-quarantined')), findsOneWidget);
      await _tap(tester, 'tender-card-terminal');
      await _tap(tester, 'confirm-payment-button');
      expect(find.byKey(const Key('card-attempt-view')), findsNothing);
      expect(w.card.edgeBodies, isEmpty);
      expect(w.ids.calls, 0);
      expect(w.prefs.getString(key), raw);
    });

    for (final locale in const <String>['ar', 'he']) {
      testWidgets('$locale: the full-journal sentence and the TEST recovery '
          'surface with the lab off are localized and right to left', (
        tester,
      ) async {
        _size(tester);
        final l10n = lookupAppLocalizations(Locale(locale));
        final full = await _world(
          prefs: <String, Object>{
            key: cardJournalEnvelope(<ProviderCardAttempt>[
              for (var i = 0; i < kProviderCardJournalCap; i++)
                cardInDoubt(cardStoredAttempt(100 + i, order: cardOrderN(i))),
            ]),
          },
        );
        await _pumpHost(tester, full, locale: locale);
        await _open(tester);
        await _tap(tester, 'tender-card-terminal');
        await _tap(tester, 'confirm-payment-button');
        expect(find.text(l10n.posCardJournalFullNote), findsOneWidget);
        expect(
          Directionality.of(
            tester.element(find.byKey(const Key('card-start-issue'))),
          ),
          TextDirection.rtl,
        );
        await tester.pumpWidget(const SizedBox());

        final open = cardInDoubt(
          cardStoredAttempt(5, order: kCardOrder, mode: ProviderCardMode.test),
        );
        final lab = await _world(
          card: CardServerFake(terminalMode: 'test'),
          prefs: <String, Object>{
            key: cardJournalEnvelope([open]),
          },
          policy: const ProviderCardPollPolicy(
            firstDelay: Duration(hours: 1),
            interval: Duration(hours: 1),
          ),
        );
        await _pumpHost(tester, lab, locale: locale);
        await _open(tester);
        expect(lab.c.read(providerCardLabEnabledProvider), isFalse);
        expect(find.text(l10n.posCardAttemptTestTitle), findsOneWidget);
        expect(find.text(l10n.posCardUncertainTitle), findsOneWidget);
        expect(find.text(l10n.posPaymentCheckStatus), findsOneWidget);
        _expectKeys(_tenders, findsNothing);
        expect(
          Directionality.of(
            tester.element(find.byKey(const Key('card-attempt-view'))),
          ),
          TextDirection.rtl,
        );
      });
    }
  });

  group('AR / HE right to left at phone width (packet §7.1, §11)', () {
    for (final locale in <String>['ar', 'he']) {
      testWidgets('$locale: localized states with an icon in a live region, '
          'reachable actions, no overflow', (tester) async {
        _size(tester, size: const Size(390, 844));
        final l10n = lookupAppLocalizations(Locale(locale));
        final w = await _world();
        w.card.edgeScript.add(
          const CardChargeTransportFailure.uncertain(
            CardChargeFailureReason.transport,
          ),
        );
        await _pumpHost(tester, w, locale: locale);
        await _open(tester);
        _drainTenderFormOverflow(tester);
        expect(
          Directionality.of(tester.element(find.byType(CashPaymentSheet))),
          TextDirection.rtl,
        );
        expect(find.text(l10n.posCardTerminalTender), findsOneWidget);
        await _tap(tester, 'tender-card-terminal');
        _drainTenderFormOverflow(tester);
        expect(find.text(l10n.posCardTerminalStart), findsOneWidget);
        await _tap(tester, 'confirm-payment-button');

        void expectShown(ProviderCardPhase phase) {
          final a = w.attempt!;
          expect(a.phase, phase);
          final shown = presentProviderCardAttempt(l10n, a);
          final banner = _state(phase);
          expect(banner, findsOneWidget);
          expect(
            find.descendant(of: banner, matching: find.text(shown.title)),
            findsOneWidget,
          );
          expect(
            find.descendant(of: banner, matching: find.text(shown.body)),
            findsOneWidget,
          );
          expect(
            find.descendant(of: banner, matching: find.byIcon(shown.icon)),
            findsOneWidget,
            reason: 'never colour alone',
          );
          expect(
            find.ancestor(
              of: banner,
              matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.liveRegion == true,
              ),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull, reason: 'no overflow');
        }

        expectShown(ProviderCardPhase.uncertain);
        expect(find.text(l10n.posPaymentCheckStatus), findsOneWidget);
        final id = w.attempt!.attemptId;
        _serverHas(w.card, id);
        await _tap(tester, 'card-check-status-button');
        expectShown(ProviderCardPhase.waiting);
        expect(find.text(l10n.posCardRelease), findsOneWidget);

        w.card.approve(id);
        await _tap(tester, 'card-check-status-button');
        expectShown(ProviderCardPhase.recorded);
        expect(find.text(l10n.posPaymentDone), findsOneWidget);
        await _tap(tester, 'card-done-button');
        expect(w.lastResult, isTrue);
      });
    }
  });
}
