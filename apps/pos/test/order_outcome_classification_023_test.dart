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
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart' show DemoMenuItem;
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/state/addition_controller.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:restoflow_pos/src/state/pos_printer_assignments.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/order_confirmation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// POS-ORDER-OUTCOME-CLASSIFICATION-FIX-023 — Codex HIGH.
///
/// `RealOutboxRepository` collapsed EVERY `SyncTransportException` into the
/// outbox `rejected` state carrying `e.code ?? e.kind.name`, and the
/// confirmation had only two visual outcomes: a recognised permanent business
/// rejection, and "everything else gets the success header". So a dropped
/// connection, a timeout or a 500 produced ONE screen reading
///
///     Order sent                                          (green, check-circle)
///     The backend rejected this order — it was NOT sent to the kitchen.
///
/// simultaneously — a success claim and a refusal claim about the same order,
/// neither of which was actually known.
///
/// These drive the REAL chain: a typed [SyncTransportException] out of a real
/// [SyncRpcTransport], through [RealOutboxRepository], through the durable
/// store (persist + reload), into the real [OrderConfirmation] widget. The
/// user-facing strings are asserted as LITERALS so they fail on behaviour
/// against HEAD 1d6e1a1, not on a missing symbol.
const _successTitle = 'Order sent';
const _rejectedTitle = 'Order not submitted';
const _unconfirmedTitle = 'Delivery not confirmed';
const _rejectedNote =
    'The backend rejected this order — it was NOT sent to the kitchen.';

const String _staleCode = 'modifier_prep_snapshot_stale';

const SyncSession _session = SyncSession(
  pinSessionId: 'pin-1',
  deviceId: 'dev-1',
);

/// A transport that throws ONE typed error, or returns a scripted envelope.
class _ScriptedTransport implements SyncRpcTransport {
  _ScriptedTransport(this._steps);

  /// Each entry is either a [SyncTransportException] to throw or a Map to
  /// return. The last step repeats.
  final List<Object> _steps;
  int calls = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function != 'sync_push') return <String, dynamic>{'ok': false};
    final step = _steps[calls < _steps.length ? calls : _steps.length - 1];
    calls++;
    if (step is SyncTransportException) throw step;
    final op = (params['p_operations'] as List).first as Map;
    final scripted = (step as Map).cast<String, Object?>();
    if (scripted['operation_type'] != null) {
      return <String, dynamic>{
        'ok': true,
        'results': <dynamic>[
          <String, dynamic>{
            'local_operation_id': op['local_operation_id'],
            ...scripted,
          },
        ],
      };
    }
    return <String, dynamic>{
      'ok': true,
      'results': <dynamic>[
        <String, dynamic>{
          'local_operation_id': op['local_operation_id'],
          'operation_type': 'order.submit',
          ...scripted,
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

Map<String, Object?> get _staleRefusal => <String, Object?>{
  'ok': false,
  'status': 'rejected',
  'error': _staleCode,
  'entity': 'order',
};

/// An in-memory durable store, so persistence + reload is exercised for real.
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

/// Queues one order and pushes it through the REAL repository, returning the
/// resulting entry AND the store it was persisted into.
Future<(OutboxEntry, _MemoryStore)> _pushOnce(
  SyncRpcTransport transport, {
  _MemoryStore? into,
}) async {
  final store = into ?? _MemoryStore();
  final repo = RealOutboxRepository(transport, _session, store: store);
  await repo.enqueue(_seed());
  final entry = await repo.push('e1');
  return (entry, store);
}

class _FakeOutbox extends OutboxController {
  _FakeOutbox(this.entries);
  final List<OutboxEntry> entries;
  @override
  List<OutboxEntry> build() => entries;
}

Future<void> _pumpConfirmation(WidgetTester tester, OutboxEntry entry) async {
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
  await tester.pumpAndSettle();
}

/// THE INVARIANT: one screen may never assert both that the order was sent and
/// that it was refused.
void _expectNoContradiction() {
  final claimsSuccess = find.text(_successTitle).evaluate().isNotEmpty;
  final claimsRefused =
      find.text(_rejectedNote).evaluate().isNotEmpty ||
      find.text(_rejectedTitle).evaluate().isNotEmpty;
  expect(
    claimsSuccess && claimsRefused,
    isFalse,
    reason: 'the page asserts BOTH acceptance and refusal of the same order',
  );
}

void main() {
  _additionRegressionTests();

  group('A. the real transport -> repository chain', () {
    test('023-T1 a TRANSIENT failure is delivery-unconfirmed', () async {
      final (entry, _) = await _pushOnce(
        _ScriptedTransport(const [
          SyncTransportException(SyncTransportErrorKind.transient),
        ]),
      );
      expect(entry.outcome, PosOrderOutcome.deliveryUnconfirmed);
      expect(entry.isPermanentBusinessRejection, isFalse);
    });

    test('023-T2 an AUTH failure is a durable AUTH_HOLD (pending) '
        '[POS-OFFLINE-OPERATIONS-002]', () async {
      // UPDATED CONTRACT (was: auth => rejected). app.sync_push raises 42501
      // in its preamble, BEFORE the per-operation dispatch loop — so nothing
      // was accepted; but nothing about the OPERATION was refused either. The
      // entry is HELD verbatim until a fresh online sign-in releases it, and
      // the honest epistemic outcome is pending (never a success claim, never
      // a refusal claim).
      // Pass B fixture honesty: kind `auth` now travels with a session-class
      // message, as the real transport mints it. (OLD: bare code, no message.)
      final (entry, _) = await _pushOnce(
        _ScriptedTransport(const [
          SyncTransportException(
            SyncTransportErrorKind.auth,
            code: '42501',
            message: 'sync_push: PIN session not found',
          ),
        ]),
      );
      expect(entry.syncState, OutboxSyncState.authHold);
      expect(entry.outcome, PosOrderOutcome.pending);
    });

    test(
      '023-T3 a SERVER failure is delivery-unconfirmed, not rejected',
      () async {
        // Acceptance could have happened before the response failed, so the safe
        // direction is "unknown".
        final (entry, _) = await _pushOnce(
          _ScriptedTransport(const [
            SyncTransportException(
              SyncTransportErrorKind.server,
              code: 'P0001',
            ),
          ]),
        );
        expect(entry.outcome, PosOrderOutcome.deliveryUnconfirmed);
      },
    );

    test('023-T4 an UNKNOWN failure is delivery-unconfirmed', () async {
      final (entry, _) = await _pushOnce(
        _ScriptedTransport(const [
          SyncTransportException(SyncTransportErrorKind.unknown),
        ]),
      );
      expect(entry.outcome, PosOrderOutcome.deliveryUnconfirmed);
    });

    test('023-T5 a structured business refusal stays REJECTED', () async {
      final (entry, _) = await _pushOnce(_ScriptedTransport([_staleRefusal]));
      expect(entry.outcome, PosOrderOutcome.rejected);
      expect(entry.lastErrorCode, _staleCode);
    });

    test('023-T6 a structured success is ACCEPTED', () async {
      final (entry, _) = await _pushOnce(_ScriptedTransport([_accepted]));
      expect(entry.outcome, PosOrderOutcome.accepted);
    });

    test('023-T7 an unreadable response is delivery-unconfirmed', () async {
      // We got A response but could not understand it: acceptance is unknown.
      final (entry, _) = await _pushOnce(
        _ScriptedTransport(const [<String, Object?>{}]),
      );
      expect(entry.outcome, PosOrderOutcome.deliveryUnconfirmed);
    });
  });

  group('B. the classification survives persistence and reload', () {
    test('023-P1 the transport kind is persisted and reloaded', () async {
      final (_, store) = await _pushOnce(
        _ScriptedTransport(const [
          SyncTransportException(SyncTransportErrorKind.transient),
        ]),
      );
      // A FRESH repository over the SAME store — the reload path, not memory.
      final reloaded = RealOutboxRepository(
        _ScriptedTransport(const [<String, Object?>{}]),
        _session,
        store: store,
      );
      final entry = (await reloaded.recentEntries()).single;
      expect(entry.outcome, PosOrderOutcome.deliveryUnconfirmed);
    });

    test('023-P2 an AUTH_HOLD survives reload as the held, pending entry '
        '[POS-OFFLINE-OPERATIONS-002]', () async {
      // UPDATED CONTRACT (was: auth reloads as rejected): the hold is durable
      // and reloads exactly as it was written — never as a refusal, never as
      // a success, never silently re-queued.
      // Pass B fixture honesty: session-class message alongside the kind.
      final (_, store) = await _pushOnce(
        _ScriptedTransport(const [
          SyncTransportException(
            SyncTransportErrorKind.auth,
            code: '42501',
            message: 'sync_push: PIN session not found',
          ),
        ]),
      );
      final reloaded = RealOutboxRepository(
        _ScriptedTransport(const [<String, Object?>{}]),
        _session,
        store: store,
      );
      final entry = (await reloaded.recentEntries()).single;
      expect(entry.syncState, OutboxSyncState.authHold);
      expect(entry.outcome, PosOrderOutcome.pending);
    });

    test(
      '023-P3 a LEGACY row with no error kind falls back to unconfirmed',
      () async {
        // Written by a build that predates this correction: a failed state with a
        // bare code and no kind. It must never read as success.
        final legacy = _seed()
            .copyWith(
              syncState: OutboxSyncState.rejected,
              lastErrorCode: 'some_old_code',
            )
            .toJson();
        expect(legacy.containsKey('last_error_kind'), isFalse);
        final store = _MemoryStore()..saved['dev-1'] = [legacy];
        final repo = RealOutboxRepository(
          _ScriptedTransport(const [<String, Object?>{}]),
          _session,
          store: store,
        );
        final entry = (await repo.recentEntries()).single;
        expect(entry.lastErrorKind, isNull);
        expect(entry.outcome, PosOrderOutcome.deliveryUnconfirmed);
      },
    );
  });

  group('C. the confirmation presents each outcome coherently', () {
    testWidgets('023-C1 ACCEPTED shows the success header only', (
      tester,
    ) async {
      final (entry, _) = await _pushOnce(_ScriptedTransport([_accepted]));
      await _pumpConfirmation(tester, entry);
      expect(
        find.byKey(const Key('confirmation-success-header')),
        findsOneWidget,
      );
      expect(find.text(_successTitle), findsOneWidget);
      expect(find.text(_rejectedTitle), findsNothing);
      expect(find.text(_unconfirmedTitle), findsNothing);
      _expectNoContradiction();
    });

    testWidgets('023-C2 a business REFUSAL shows the rejection header only', (
      tester,
    ) async {
      final (entry, _) = await _pushOnce(_ScriptedTransport([_staleRefusal]));
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await _pumpConfirmation(tester, entry);
      expect(
        find.byKey(const Key('confirmation-rejected-header')),
        findsOneWidget,
      );
      expect(find.text(_rejectedTitle), findsOneWidget);
      expect(find.text(_successTitle), findsNothing);
      expect(find.text(_unconfirmedTitle), findsNothing);
      // The 022 recovery text is untouched.
      expect(find.text(l10n.posPrepSnapshotStale), findsOneWidget);
      _expectNoContradiction();
    });

    testWidgets('023-C3 an AUTH_HOLD presents as PENDING — no success claim, '
        'no refusal claim [POS-OFFLINE-OPERATIONS-002]', (tester) async {
      // UPDATED CONTRACT (was: rejected header). The server never read the
      // operation, so the page claims exactly what is known: the order is
      // stored locally and waiting — the same conservative presentation
      // every queued order gets.
      // Pass B fixture honesty: session-class message alongside the kind.
      final (entry, _) = await _pushOnce(
        _ScriptedTransport(const [
          SyncTransportException(
            SyncTransportErrorKind.auth,
            code: '42501',
            message: 'sync_push: PIN session not found',
          ),
        ]),
      );
      await _pumpConfirmation(tester, entry);
      expect(find.text(_successTitle), findsNothing);
      expect(
        find.byKey(const Key('confirmation-success-header')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('confirmation-rejected-header')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('confirmation-pending-header')),
        findsOneWidget,
      );
      expect(find.text(_unconfirmedTitle), findsNothing);
      _expectNoContradiction();
    });

    testWidgets('023-C4 a TRANSIENT failure shows the UNCONFIRMED header', (
      tester,
    ) async {
      final (entry, _) = await _pushOnce(
        _ScriptedTransport(const [
          SyncTransportException(SyncTransportErrorKind.transient),
        ]),
      );
      await _pumpConfirmation(tester, entry);
      expect(
        find.byKey(const Key('confirmation-unconfirmed-header')),
        findsOneWidget,
      );
      expect(find.text(_unconfirmedTitle), findsOneWidget);
      // Neither of the two things we do not know.
      expect(find.text(_successTitle), findsNothing);
      expect(
        find.byKey(const Key('confirmation-success-header')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('confirmation-rejected-header')),
        findsNothing,
      );
      expect(find.text(_rejectedTitle), findsNothing);
      expect(
        find.text(_rejectedNote),
        findsNothing,
        reason: 'the backend did not refuse it — we simply do not know',
      );
      _expectNoContradiction();
    });

    testWidgets('023-C5 a SERVER failure shows the UNCONFIRMED header', (
      tester,
    ) async {
      final (entry, _) = await _pushOnce(
        _ScriptedTransport(const [
          SyncTransportException(SyncTransportErrorKind.server, code: 'P0001'),
        ]),
      );
      await _pumpConfirmation(tester, entry);
      expect(
        find.byKey(const Key('confirmation-unconfirmed-header')),
        findsOneWidget,
      );
      expect(find.text(_successTitle), findsNothing);
      expect(find.text(_rejectedNote), findsNothing);
      _expectNoContradiction();
    });

    testWidgets('023-C6 a LEGACY failed row shows the UNCONFIRMED header', (
      tester,
    ) async {
      final entry = _seed().copyWith(
        syncState: OutboxSyncState.rejected,
        lastErrorCode: 'some_old_code',
      );
      await _pumpConfirmation(tester, entry);
      expect(
        find.byKey(const Key('confirmation-unconfirmed-header')),
        findsOneWidget,
      );
      expect(find.text(_successTitle), findsNothing);
      _expectNoContradiction();
    });

    testWidgets('023-C8 THE INVARIANT: never both sent AND rejected', (
      tester,
    ) async {
      // The finding itself, asserted on its own: against HEAD this page carried
      // the green "Order sent" header AND "The backend rejected this order — it
      // was NOT sent to the kitchen." about the same order, and neither claim
      // was known to be true.
      final (entry, _) = await _pushOnce(
        _ScriptedTransport(const [
          SyncTransportException(SyncTransportErrorKind.transient),
        ]),
      );
      await _pumpConfirmation(tester, entry);
      _expectNoContradiction();
    });

    testWidgets('023-C7 a PENDING order claims neither outcome', (
      tester,
    ) async {
      // 024: pending got its own header. It was sharing the ACCEPTED one, which
      // claimed a server answer that had not arrived.
      await _pumpConfirmation(tester, _seed());
      expect(
        find.byKey(const Key('confirmation-pending-header')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('confirmation-success-header')),
        findsNothing,
      );
      expect(find.text(_successTitle), findsNothing);
      expect(find.text(_unconfirmedTitle), findsNothing);
      _expectNoContradiction();
    });
  });

  group('D. reconciliation moves the outcome, without a new identity', () {
    test('023-R1 unconfirmed -> ACCEPTED on an idempotent replay', () async {
      final transport = _ScriptedTransport([
        const SyncTransportException(SyncTransportErrorKind.transient),
        _accepted,
      ]);
      final store = _MemoryStore();
      final repo = RealOutboxRepository(transport, _session, store: store);
      await repo.enqueue(_seed());
      final first = await repo.push('e1');
      expect(first.outcome, PosOrderOutcome.deliveryUnconfirmed);

      await repo.retry('e1');
      final second = await repo.push('e1');
      expect(second.outcome, PosOrderOutcome.accepted);
      // THE identity is unchanged, so the server saw a replay, not a new order.
      expect(second.localOperationId, first.localOperationId);
      expect(second.deviceId, first.deviceId);
      expect(transport.calls, 2);
    });

    test(
      '023-R2 unconfirmed -> REJECTED on a later business refusal',
      () async {
        final transport = _ScriptedTransport([
          const SyncTransportException(SyncTransportErrorKind.transient),
          _staleRefusal,
        ]);
        final store = _MemoryStore();
        final repo = RealOutboxRepository(transport, _session, store: store);
        await repo.enqueue(_seed());
        expect(
          (await repo.push('e1')).outcome,
          PosOrderOutcome.deliveryUnconfirmed,
        );
        await repo.retry('e1');
        final second = await repo.push('e1');
        expect(second.outcome, PosOrderOutcome.rejected);
        expect(second.localOperationId, 'op-1');
      },
    );

    testWidgets('023-R3 the header follows the transition to accepted', (
      tester,
    ) async {
      final transport = _ScriptedTransport([
        const SyncTransportException(SyncTransportErrorKind.transient),
        _accepted,
      ]);
      final store = _MemoryStore();
      final repo = RealOutboxRepository(transport, _session, store: store);
      await repo.enqueue(_seed());
      await repo.push('e1');
      await repo.retry('e1');
      final accepted = await repo.push('e1');

      await _pumpConfirmation(tester, accepted);
      expect(
        find.byKey(const Key('confirmation-success-header')),
        findsOneWidget,
      );
      expect(find.text(_unconfirmedTitle), findsNothing);
      _expectNoContradiction();
    });
  });
}

/// A live parent order to extend.
class _ParentDetailRepo implements OrderDetailRepository {
  @override
  Future<PosOrderDetail> fetch(String orderId) async => PosOrderDetail(
    orderId: orderId,
    orderCode: '#O00001',
    orderType: 'dine_in',
    status: 'preparing',
    revision: 2,
    currencyCode: 'ILS',
    subtotalMinor: 2500,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: 2500,
    tableLabel: 'T1',
    items: const [],
    rounds: const [],
  );
}

const DemoMenuItem _burger = DemoMenuItem(
  id: 'm-023',
  name: 'Burger',
  priceMinor: 700,
  categoryId: 'c1',
  categoryName: 'Food',
);

ProviderContainer _additionContainer(SyncRpcTransport transport) {
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport),
      posSyncSessionProvider.overrideWithValue(_session),
      orderDetailRepositoryProvider.overrideWithValue(_ParentDetailRepo()),
      orderSnapshotRepositoryProvider.overrideWithValue(
        DemoOrderSnapshotRepository(),
      ),
      posSyncPollIntervalProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// E. ADD-ITEMS — a REGRESSION guard, not a change.
///
/// `AdditionController` already carries an accurate typed outcome model
/// (`AdditionOutcomeKind.applied / refused / conflict / unknown`) and a
/// transport throw lands in `unknown`, which is exactly "delivery
/// unconfirmed": the identity and the frozen payload are RETAINED so the next
/// attempt replays the same operation instead of building a second round, and
/// nothing claims the round was applied. No production change was needed there;
/// these pin that it stays true.
void _additionRegressionTests() {
  group('E. Add-items already classifies outcomes accurately', () {
    test('023-E1 a transport failure is UNKNOWN, never applied', () async {
      final transport = _ScriptedTransport(const [
        SyncTransportException(SyncTransportErrorKind.transient),
      ]);
      final container = _additionContainer(transport);
      final notifier = container.read(additionControllerProvider.notifier);
      final cart = container.read(cartControllerProvider.notifier);
      await notifier.enterForOrder('o-1');
      expect(cart.addItem(_burger), CartMutationResult.applied);

      final result = await notifier.submit();
      expect(result.applied, isFalse, reason: 'no success is claimed');
      expect(result.error, 'transport');
      expect(result.printPayload, isNull, reason: 'nothing may be printed');

      final state = container.read(additionControllerProvider);
      expect(state.phase, AdditionPhase.failed);
      // THE identity is RETAINED — an unknown delivery must replay, never mint
      // a second round for food that may already be cooking.
      expect(state.dispatched, isTrue);
      expect(state.attempt?.localOperationId, isNotNull);
      expect(container.read(cartControllerProvider).lines, hasLength(1));
    });

    test(
      '023-E2 a structured refusal is REFUSED and frees the identity',
      () async {
        final transport = _ScriptedTransport([
          <String, Object?>{
            'operation_type': 'order.items_add',
            'ok': false,
            'status': 'rejected',
            'error': _staleCode,
            'order_id': 'o-1',
          },
        ]);
        final container = _additionContainer(transport);
        final notifier = container.read(additionControllerProvider.notifier);
        final cart = container.read(cartControllerProvider.notifier);
        await notifier.enterForOrder('o-1');
        expect(cart.addItem(_burger), CartMutationResult.applied);

        final result = await notifier.submit();
        expect(result.applied, isFalse);
        expect(result.error, _staleCode);
        expect(result.printPayload, isNull);
        final state = container.read(additionControllerProvider);
        expect(
          state.dispatched,
          isFalse,
          reason: 'a verdict frees the identity',
        );
        expect(container.read(cartControllerProvider).lines, hasLength(1));
      },
    );
  });
}
