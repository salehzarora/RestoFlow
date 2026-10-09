import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/kitchen_finish_repository.dart';
import 'package:restoflow_pos/src/data/kitchen_mode_readiness.dart'
    show posVerifiedKitchenModeProvider;
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_actions_assembly.dart';
import 'package:restoflow_pos/src/data/order_edit_diff.dart'
    show OrderEditAttemptSummary;
import 'package:restoflow_pos/src/data/order_edit_journal_store.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/staff_capabilities.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart'
    show posHasKitchenNativePrinterProvider;
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/discount_controller.dart';
import 'package:restoflow_pos/src/state/draft_recovery_controller.dart';
import 'package:restoflow_pos/src/state/kitchen_finish_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_auto_print_prefs.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';
import 'package:restoflow_pos/src/widgets/recovery_coordinator.dart';

import 'support/fixed_pos_clock.dart';
import 'support/order_edit_fixtures.dart';

/// ORDER-EDIT-001E — an edit this device froze withdraws its order's other
/// actions (design §7.1 point 7), through the SAME shared assembly every
/// surface reads:
///
///  * a row whose order carries an unresolved edit record is stamped
///    [PosPendingKind.orderEdit] — Pay, Discount, Cancel, Add items, Move and
///    Edit withdrawn — while every other row is untouched;
///  * while the edit journal is still being read, EVERY row is held;
///  * the kitchen "finish all" batch never advances an order with an
///    unresolved edit, and touches nothing while the journal is unread.

const _scope = PosSyncScope(
  organizationId: 'org1',
  restaurantId: 'r1',
  branchId: 'branch-A',
  deviceId: 'dev1',
);

PosRecentOrder _order(String orderId, {String status = 'preparing'}) =>
    PosRecentOrder.discovered(
      PosOrderSnapshot(
        orderId: orderId,
        orderCode: '#O0000$orderId',
        revision: 3,
        status: status,
        settlement: PosSettlement.unpaid,
        subtotalMinor: 12000,
        discountTotalMinor: 0,
        taxTotalMinor: 0,
        grandTotalMinor: 12000,
        createdAt: DateTime.utc(2026, 8, 1, 10),
        updatedAt: DateTime.utc(2026, 8, 1, 10),
        syncAt: DateTime.utc(2026, 8, 1, 10),
        orderType: 'dine_in',
        tableLabel: 'T1',
        currencyCode: 'ILS',
      ),
    );

/// An edit of [orderId] whose outcome is unknown (a dead transport).
OrderEditJournalRecord _uncertain(String orderId) => OrderEditJournalRecord(
  localOperationId: 'op-$orderId',
  orderId: orderId,
  orderCode: '#O0000$orderId',
  clientCreatedAt: DateTime.utc(2026, 8, 1, 11),
  generation: 1,
  payload: <String, Object?>{
    'order_id': orderId,
    'expected': <String, Object?>{
      'subtotal_minor': 8000,
      'tax_total_minor': 0,
      'grand_total_minor': 8000,
    },
    'changes': <Object?>[
      <String, Object?>{'op': 'remove', 'order_item_id': 'oi-1'},
    ],
  },
  summary: const OrderEditAttemptSummary(removedCount: 1),
  phase: OrderEditJournalPhase.transportUncertain,
);

/// A journal whose read can be held open (the startup window).
class _Journal implements OrderEditJournalStore {
  _Journal(this.records);
  final Map<String, OrderEditJournalRecord> records;
  Completer<void>? gate;

  @override
  Future<Map<String, OrderEditJournalRecord>> load(String scopeKey) async {
    if (gate case final g?) await g.future;
    return scopeKey == 'dev1'
        ? Map<String, OrderEditJournalRecord>.of(records)
        : <String, OrderEditJournalRecord>{};
  }

  @override
  Future<void> persist(
    String scopeKey,
    Map<String, OrderEditJournalRecord> records,
  ) async {}
}

class _StubAutoKitchen extends PosAutoPrintKitchenTicketController {
  @override
  Future<bool?> build() async => true;
}

class _RecordingRepo implements KitchenFinishRepository {
  final List<String> advanced = [];

  @override
  Future<KitchenFinishResult> advanceToServed({
    required String orderId,
    required String fromStatus,
    required String batchRunId,
    required Future<String?> Function(String orderId) refreshStatus,
  }) async {
    advanced.add(orderId);
    return KitchenFinishResult(orderId, KitchenFinishStatus.finished);
  }

  @override
  Future<KitchenFinishResult> completeServedOrder({
    required String orderId,
    required String localOperationId,
  }) async => KitchenFinishResult(orderId, KitchenFinishStatus.finished);
}

/// Captures the shared assembly's verdict per order, in the sheet's scope.
class _Probe extends ConsumerWidget {
  const _Probe(this.captured);
  final Map<String, PosOrderActions> captured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(posRecentOrdersControllerProvider);
    final assembly = PosOrderActionsAssembly.watch(ref, orders);
    captured
      ..clear()
      ..addEntries(
        orders.map((o) => MapEntry(o.orderId!, assembly.resolveFor(o))),
      );
    return const RecentOrdersSheet();
  }
}

class _Host extends ConsumerStatefulWidget {
  const _Host(this.captured);
  final Map<String, PosOrderActions> captured;
  @override
  ConsumerState<_Host> createState() => _HostState();
}

class _HostState extends ConsumerState<_Host> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(posDeviceContextProvider.notifier)
          .set(
            const DeviceContext(
              organizationId: 'org1',
              branchId: 'branch-A',
              restaurantId: 'r1',
              deviceId: 'dev1',
            ),
          );
    });
  }

  @override
  Widget build(BuildContext context) => _Probe(widget.captured);
}

final _printerOnly = KitchenModePrinterOnlyWithRevision(
  revision: 4,
  verifiedAt: DateTime.utc(2026, 8, 1, 9),
);

Future<void> _pump(
  WidgetTester tester, {
  required _Journal journal,
  required Map<String, PosOrderActions> captured,
  _RecordingRepo? repo,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = InMemoryRecentOrdersStore();
  await store.persist(_scope.key, [_order('o-edited'), _order('o-free')]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posSyncSessionProvider.overrideWithValue(
          const SyncSession(pinSessionId: 'pin1', deviceId: 'dev1'),
        ),
        posRecentOrdersStoreProvider.overrideWithValue(store),
        posSyncCursorStoreProvider.overrideWithValue(InMemorySyncCursorStore()),
        posSyncPollIntervalProvider.overrideWithValue(null),
        pinnedPosSyncClock(),
        orderSnapshotRepositoryProvider.overrideWithValue(
          DemoOrderSnapshotRepository(),
        ),
        posHasKitchenNativePrinterProvider.overrideWithValue(true),
        posAutoPrintKitchenTicketProvider.overrideWith(_StubAutoKitchen.new),
        staffCapabilitiesProvider.overrideWith(
          (ref) async => PosStaffCapabilities.fromJson(
            const {'apply_discount': true, 'void_order': true},
            role: 'manager',
            branchFeatures: const {
              'order_edit_enabled': true,
              'order_edit_finished_food_manager_only': false,
            },
          ),
        ),
        if (repo != null)
          kitchenFinishRepositoryProvider.overrideWithValue(repo),
        posVerifiedKitchenModeProvider.overrideWithValue(_printerOnly),
        orderEditJournalStoreProvider.overrideWithValue(journal),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(body: _Host(captured)),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Future<void> _finishAll(WidgetTester tester) async {
  final l10n = await AppLocalizations.delegate.load(const Locale('en'));
  await tester.tap(find.byKey(const Key('finish-all-kitchen-orders-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.posFinishAllConfirmAction));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an unresolved edit withdraws ONLY its order\'s actions', (
    tester,
  ) async {
    final captured = <String, PosOrderActions>{};
    await _pump(
      tester,
      journal: _Journal({'op-o-edited': _uncertain('o-edited')}),
      captured: captured,
    );

    final edited = captured['o-edited']!;
    expect(edited.pendingKind, PosPendingKind.orderEdit);
    expect(edited.canPay, isFalse);
    expect(edited.canDiscount, isFalse);
    expect(edited.canVoid, isFalse);
    expect(edited.canAddItems, isFalse);
    expect(edited.canMoveTable, isFalse);
    expect(edited.canEditOrder, isFalse);

    final free = captured['o-free']!;
    expect(free.pendingKind, isNull);
    expect(free.canPay, isTrue);
    expect(free.canAddItems, isTrue);
    expect(free.canEditOrder, isTrue);
  });

  testWidgets('while the edit journal is unread, every order is held', (
    tester,
  ) async {
    final captured = <String, PosOrderActions>{};
    final journal = _Journal(const {})..gate = Completer<void>();
    await _pump(tester, journal: journal, captured: captured, settle: false);
    await tester.pump();
    await tester.pump();
    for (final id in ['o-edited', 'o-free']) {
      expect(captured[id]!.pendingKind, PosPendingKind.orderEdit, reason: id);
      expect(captured[id]!.canPay, isFalse, reason: id);
      expect(captured[id]!.canEditOrder, isFalse, reason: id);
    }

    journal.gate!.complete();
    await tester.pumpAndSettle();
    for (final id in ['o-edited', 'o-free']) {
      expect(captured[id]!.pendingKind, isNull, reason: id);
      expect(captured[id]!.canPay, isTrue, reason: id);
    }
  });

  testWidgets('finish all never advances an order with an unresolved edit', (
    tester,
  ) async {
    final repo = _RecordingRepo();
    await _pump(
      tester,
      journal: _Journal({'op-o-edited': _uncertain('o-edited')}),
      captured: <String, PosOrderActions>{},
      repo: repo,
    );
    await _finishAll(tester);
    expect(repo.advanced, ['o-free']);
  });

  testWidgets('a draft recovery is refused up front while the cart edits a '
      'sent order', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    late WidgetRef widgetRef;
    late BuildContext widgetContext;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Consumer(
            builder: (c, r, _) {
              widgetRef = r;
              widgetContext = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pump();
    final b = baselineOf(detail(items: [detailItem('oi-1')]));
    expect(
      container
          .read(cartControllerProvider.notifier)
          .loadForEdit(CartEditContext(baseline: b, generation: 1)),
      CartEditLoadResult.loaded,
    );
    final recovery = PosDraftRecovery(
      draft: const CartDraftSnapshot(
        currencyCode: 'ILS',
        lines: [
          CartDraftLine(
            menuItemId: 'm-draft',
            name: 'Draft Burger',
            basePriceMinor: 500,
            quantity: 1,
          ),
        ],
      ),
      orderType: OrderType.dineIn,
      outboxEntryId: 'entry-R',
      binding: container.read(posRecoveryBindingProvider),
    );
    final outcome = await PosRecoveryCoordinator(
      widgetRef,
    ).restore(widgetContext, recovery);
    await tester.pump();
    expect(outcome, PosRecoveryOutcome.lockedByAddition);
    expect(find.byKey(const Key('recovery-replace-dialog')), findsNothing);
    final cart = container.read(cartControllerProvider);
    expect(cart.isEditing, isTrue);
    expect(cart.lines.single.lineId, 'sent-oi-1');
  });
}
