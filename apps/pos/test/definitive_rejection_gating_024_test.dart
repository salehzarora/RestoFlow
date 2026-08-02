import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show
        DevicePrinterAssignments,
        DevicePrinterAssignmentsFailure,
        DevicePrinterAssignmentsReader;
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show
        SyncRpcTransport,
        SyncSession,
        SyncTransportErrorKind,
        SyncTransportException;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/durable_outbox_store.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:restoflow_pos/src/state/pos_printer_assignments.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/order_confirmation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// POS-DEFINITIVE-REJECTION-ACTION-GATING-FIX-024.
///
/// 023 classified outcomes correctly but left every ACTION surface gated on
/// `kPermanentRejectionCodes`. So an order the server definitively refused —
/// a typed `auth` failure, or a structured refusal whose code simply was not
/// allowlisted yet — still offered Pay, Discount, kitchen printing and Retry,
/// and the automatic sweep kept re-pushing it. A new canonical server refusal
/// code would silently reopen all of them until someone remembered to add it
/// to that set.
///
/// These drive the REAL chain: a typed transport error or a structured refusal
/// out of a real transport, through `RealOutboxRepository`, into the real
/// `OrderConfirmation`. Strings are asserted as English LITERALS so they fail
/// on behaviour against HEAD 90adfa1, not on a missing symbol.
const _successTitle = 'Order sent';
const _rejectedTitle = 'Order not submitted';
const _unconfirmedTitle = 'Delivery not confirmed';
const _pendingTitle = 'Order pending';

/// A structured refusal code deliberately ABSENT from kPermanentRejectionCodes —
/// standing in for a canonical code the server gains after this build ships.
const String _futureCode = 'future_canonical_refusal';

const SyncSession _session = SyncSession(
  pinSessionId: 'pin-1',
  deviceId: 'dev-1',
);

class _ScriptedTransport implements SyncRpcTransport {
  _ScriptedTransport(this._steps);
  final List<Object> _steps;
  int pushes = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function != 'sync_push') return <String, dynamic>{'ok': false};
    final step = _steps[pushes < _steps.length ? pushes : _steps.length - 1];
    pushes++;
    if (step is SyncTransportException) throw step;
    final op = (params['p_operations'] as List).first as Map;
    return <String, dynamic>{
      'ok': true,
      'results': <dynamic>[
        <String, dynamic>{
          'local_operation_id': op['local_operation_id'],
          'operation_type': 'order.submit',
          ...(step as Map).cast<String, Object?>(),
        },
      ],
      'server_ts': '2026-08-02T09:00:01Z',
    };
  }
}

Map<String, Object?> get _accepted => <String, Object?>{
  'ok': true,
  'status': 'applied',
};

Map<String, Object?> get _futureRefusal => <String, Object?>{
  'ok': false,
  'status': 'rejected',
  'error': _futureCode,
  'entity': 'order',
};

const _authFailure = SyncTransportException(
  SyncTransportErrorKind.auth,
  code: '42501',
);
const _transientFailure = SyncTransportException(
  SyncTransportErrorKind.transient,
);

class _MemoryStore implements DurableOutboxStore {
  final Map<String, List<Map<String, Object?>>> saved = {};
  @override
  Future<List<OutboxEntry>> load(String scopeKey) async => [
    for (final j in saved[scopeKey] ?? const <Map<String, Object?>>[])
      OutboxEntry.fromJson(j),
  ];
  @override
  Future<void> persist(String scopeKey, List<OutboxEntry> entries) async {
    saved[scopeKey] = [for (final e in entries) e.toJson()];
  }
}

class _EmptyAssignments implements DevicePrinterAssignmentsReader {
  @override
  Future<Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>>
  load() async => Success(
    DevicePrinterAssignments(
      fetchedAt: DateTime(2026, 8, 2, 12),
      printers: const [],
    ),
  );
}

const _order = SubmittedOrderView(
  orderNumber: '#3F7A2C',
  orderType: OrderType.takeaway,
  currencyCode: 'ILS',
  subtotalMinor: 4200,
  lines: [
    SubmittedLineView(
      name: 'Classic Burger',
      quantity: 1,
      lineTotalMinor: 4200,
      currencyCode: 'ILS',
    ),
  ],
  orderId: 'order-1',
  outboxEntryId: 'e1',
  localOperationId: 'op-1',
);

OutboxEntry _seed() => OutboxEntry(
  id: 'e1',
  deviceId: 'dev-1',
  localOperationId: 'op-1',
  operationType: 'order.submit',
  targetEntity: 'order',
  targetId: 'order-1',
  payloadJson: '{}',
  summary: const OrderSummary(
    orderNumber: '#3F7A2C',
    orderType: OrderType.takeaway,
    tableLabel: null,
    itemCount: 1,
    subtotalMinor: 4200,
    currencyCode: 'ILS',
  ),
  syncState: OutboxSyncState.pending,
  clientCreatedAt: DateTime.utc(2026, 8, 2),
);

Future<(OutboxEntry, _ScriptedTransport)> _pushOnce(List<Object> steps) async {
  final transport = _ScriptedTransport(steps);
  final repo = RealOutboxRepository(transport, _session, store: _MemoryStore());
  await repo.enqueue(_seed());
  return (await repo.push('e1'), transport);
}

class _FakeOutbox extends OutboxController {
  _FakeOutbox(this.entries);
  final List<OutboxEntry> entries;
  @override
  List<OutboxEntry> build() => entries;
}

Future<void> _pump(
  WidgetTester tester,
  OutboxEntry entry, {
  bool settle = true,
}) async {
  SharedPreferences.setMockInitialValues(const {});
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posPrinterAssignmentsReaderProvider.overrideWithValue(
        _EmptyAssignments(),
      ),
      paymentRepositoryProvider.overrideWithValue(DemoPaymentStore()),
      outboxControllerProvider.overrideWith(() => _FakeOutbox([entry])),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: OrderConfirmation(order: _order, onNewOrder: () {}),
        ),
      ),
    ),
  );
  // An IN-FLIGHT entry renders a live progress indicator, which never
  // settles — pump once for it instead of spinning until timeout.
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// Every action that asserts a server order exists.
const _serverOrderActionKeys = <String>[
  'pay-cash-button',
  'pay-later-button',
  'apply-discount-button',
  'print-kitchen-ticket-button',
  'receipt-print-status',
  'sync-retry-button',
];

void _expectNoServerOrderActions() {
  for (final k in _serverOrderActionKeys) {
    expect(
      find.byKey(Key(k)),
      findsNothing,
      reason: '$k acts on an order the server never created',
    );
  }
}

/// 024 — the FULL four-way invariant. Exactly one outcome header, exactly its
/// own title, and none of the other three. The 023 helper only compared success
/// against rejection, so an accepted page carrying an unconfirmed claim (or a
/// pending page carrying a success claim) passed it.
const _headerKeys = <PosOrderOutcome, String>{
  PosOrderOutcome.accepted: 'confirmation-success-header',
  PosOrderOutcome.rejected: 'confirmation-rejected-header',
  PosOrderOutcome.deliveryUnconfirmed: 'confirmation-unconfirmed-header',
  PosOrderOutcome.pending: 'confirmation-pending-header',
};
const _titles = <PosOrderOutcome, String>{
  PosOrderOutcome.accepted: _successTitle,
  PosOrderOutcome.rejected: _rejectedTitle,
  PosOrderOutcome.deliveryUnconfirmed: _unconfirmedTitle,
  PosOrderOutcome.pending: _pendingTitle,
};

void expectExactlyOneOutcome(PosOrderOutcome expected) {
  for (final entry in _headerKeys.entries) {
    final matcher = entry.key == expected ? findsOneWidget : findsNothing;
    expect(
      find.byKey(Key(entry.value)),
      matcher,
      reason: 'header ${entry.value} for expected $expected',
    );
  }
  for (final entry in _titles.entries) {
    final matcher = entry.key == expected ? findsOneWidget : findsNothing;
    expect(
      find.text(entry.value),
      matcher,
      reason: 'title "${entry.value}" for expected $expected',
    );
  }
}

void main() {
  group('A. one authoritative predicate', () {
    test('024-A1 a typed AUTH rejection is definitive', () async {
      final (entry, _) = await _pushOnce(const [_authFailure]);
      expect(entry.outcome, PosOrderOutcome.rejected);
      expect(entry.hasDefinitiveVerdict, isTrue);
      expect(entry.isDefinitiveNoServerOrder, isTrue);
    });

    test('024-A2 an UNKNOWN structured refusal is definitive', () async {
      final (entry, _) = await _pushOnce([_futureRefusal]);
      expect(
        kPermanentRejectionCodes.contains(_futureCode),
        isFalse,
        reason: 'the whole point: no allowlist entry exists for this code',
      );
      expect(entry.lastErrorKind, kServerVerdictErrorKind);
      expect(entry.isDefinitiveNoServerOrder, isTrue);
    });

    test('024-A3 the established business codes stay definitive', () async {
      for (final code in const [
        'modifier_prep_snapshot_stale',
        'item_unavailable',
        'modifier_option_not_in_scope',
      ]) {
        final (entry, _) = await _pushOnce([
          <String, Object?>{'ok': false, 'status': 'rejected', 'error': code},
        ]);
        expect(entry.isDefinitiveNoServerOrder, isTrue, reason: code);
      }
    });

    test('024-A4 nothing uncertain is ever definitive', () async {
      for (final step in const [
        _transientFailure,
        SyncTransportException(SyncTransportErrorKind.server, code: 'P0001'),
        SyncTransportException(SyncTransportErrorKind.unknown),
        <String, Object?>{},
      ]) {
        final (entry, _) = await _pushOnce([step]);
        expect(entry.isDefinitiveNoServerOrder, isFalse, reason: '$step');
        expect(entry.hasDefinitiveVerdict, isFalse);
      }
      final (accepted, _) = await _pushOnce([_accepted]);
      expect(accepted.isDefinitiveNoServerOrder, isFalse);
      expect(_seed().isDefinitiveNoServerOrder, isFalse, reason: 'pending');
      // A legacy failed row with no classification.
      expect(
        _seed()
            .copyWith(
              syncState: OutboxSyncState.rejected,
              lastErrorCode: 'some_old_code',
            )
            .isDefinitiveNoServerOrder,
        isFalse,
      );
    });
  });

  group('B. a typed AUTH rejection withdraws every order action', () {
    testWidgets('024-B1 no Pay / Discount / print / receipt / Retry', (
      tester,
    ) async {
      final (entry, _) = await _pushOnce(const [_authFailure]);
      await _pump(tester, entry);
      expectExactlyOneOutcome(PosOrderOutcome.rejected);
      _expectNoServerOrderActions();
    });

    test('024-B2 the automatic sweep never re-pushes it', () async {
      final transport = _ScriptedTransport(const [_authFailure]);
      final repo = RealOutboxRepository(
        transport,
        _session,
        store: _MemoryStore(),
      );
      final container = ProviderContainer(
        overrides: [outboxRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      await repo.enqueue(_seed());
      final controller = container.read(outboxControllerProvider.notifier);
      await controller.pushEntry('e1');
      final afterFirstPush = transport.pushes;

      await controller.retryAllFailed();
      expect(
        transport.pushes,
        afterFirstPush,
        reason: 'a definitive refusal must never be re-pushed by the sweep',
      );
    });

    test('024-B3 a MANUAL retry cannot re-push it either', () async {
      final transport = _ScriptedTransport(const [_authFailure]);
      final repo = RealOutboxRepository(
        transport,
        _session,
        store: _MemoryStore(),
      );
      final container = ProviderContainer(
        overrides: [outboxRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      await repo.enqueue(_seed());
      final controller = container.read(outboxControllerProvider.notifier);
      await controller.pushEntry('e1');
      final afterFirstPush = transport.pushes;

      await controller.retryEntry('e1');
      expect(
        transport.pushes,
        afterFirstPush,
        reason: 'the button is withdrawn, and the command fails closed too',
      );
    });
  });

  group('C. an UNKNOWN structured refusal is gated identically', () {
    testWidgets('024-C1 no actions, without touching the allowlist', (
      tester,
    ) async {
      final (entry, _) = await _pushOnce([_futureRefusal]);
      await _pump(tester, entry);
      expectExactlyOneOutcome(PosOrderOutcome.rejected);
      _expectNoServerOrderActions();
    });

    test('024-C2 neither sweep nor manual retry re-pushes it', () async {
      final transport = _ScriptedTransport([_futureRefusal]);
      final repo = RealOutboxRepository(
        transport,
        _session,
        store: _MemoryStore(),
      );
      final container = ProviderContainer(
        overrides: [outboxRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      await repo.enqueue(_seed());
      final controller = container.read(outboxControllerProvider.notifier);
      await controller.pushEntry('e1');
      final afterFirstPush = transport.pushes;
      await controller.retryAllFailed();
      await controller.retryEntry('e1');
      expect(transport.pushes, afterFirstPush);
    });
  });

  group('D. PENDING never claims success', () {
    testWidgets('024-D1 a queued order shows the pending header', (
      tester,
    ) async {
      await _pump(tester, _seed());
      expectExactlyOneOutcome(PosOrderOutcome.pending);
    });

    testWidgets('024-D2 an IN-FLIGHT order shows the pending header', (
      tester,
    ) async {
      await _pump(
        tester,
        _seed().copyWith(syncState: OutboxSyncState.inFlight),
        settle: false,
      );
      expectExactlyOneOutcome(PosOrderOutcome.pending);
    });
  });

  group('E. the other outcomes are unchanged', () {
    testWidgets('024-E1 ACCEPTED keeps its header and its actions', (
      tester,
    ) async {
      final (entry, _) = await _pushOnce([_accepted]);
      await _pump(tester, entry);
      expectExactlyOneOutcome(PosOrderOutcome.accepted);
      // Accepted is the one outcome that MAY act on a server order.
      expect(find.byKey(const Key('pay-cash-button')), findsOneWidget);
    });

    testWidgets('024-E2 DELIVERY-UNCONFIRMED keeps Retry and its actions', (
      tester,
    ) async {
      final (entry, _) = await _pushOnce(const [_transientFailure]);
      await _pump(tester, entry);
      expectExactlyOneOutcome(PosOrderOutcome.deliveryUnconfirmed);
      // The established offline contract: the order may well exist, so the
      // same-identity retry stays, and so do the offline actions.
      expect(find.byKey(const Key('sync-retry-button')), findsOneWidget);
      expect(find.byKey(const Key('pay-cash-button')), findsOneWidget);
    });

    test('024-E3 an unconfirmed entry is still re-pushable', () async {
      final transport = _ScriptedTransport(const [
        _transientFailure,
        _transientFailure,
      ]);
      final repo = RealOutboxRepository(
        transport,
        _session,
        store: _MemoryStore(),
      );
      final container = ProviderContainer(
        overrides: [outboxRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      await repo.enqueue(_seed());
      final controller = container.read(outboxControllerProvider.notifier);
      await controller.pushEntry('e1');
      await controller.retryAllFailed();
      expect(
        transport.pushes,
        greaterThan(1),
        reason: 'delivery is unknown — retrying the same identity is the fix',
      );
    });

    testWidgets('024-E4 a STALE business refusal is unchanged', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final (entry, _) = await _pushOnce([
        <String, Object?>{
          'ok': false,
          'status': 'rejected',
          'error': 'modifier_prep_snapshot_stale',
        },
      ]);
      await _pump(tester, entry);
      expectExactlyOneOutcome(PosOrderOutcome.rejected);
      expect(find.text(l10n.posPrepSnapshotStale), findsOneWidget);
      expect(find.byKey(const Key('recovery-actions')), findsOneWidget);
      _expectNoServerOrderActions();
    });
  });
}
