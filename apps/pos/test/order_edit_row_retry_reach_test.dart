import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show BranchTax, DeviceBranchTaxReader;
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/kitchen_mode_readiness.dart'
    show posVerifiedKitchenModeProvider;
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_actions_assembly.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_edit_diff.dart'
    show OrderEditAttemptSummary;
import 'package:restoflow_pos/src/data/order_edit_journal_store.dart';
import 'package:restoflow_pos/src/data/order_edit_read_model.dart';
import 'package:restoflow_pos/src/data/order_edit_response.dart'
    show OrderEditApplied;
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/order_snapshot_repository.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/staff_capabilities.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/discount_controller.dart'
    show staffCapabilitiesProvider;
import 'package:restoflow_pos/src/state/order_edit_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_branch_tax.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/widgets/order_detail_preview.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/order_edit_fixtures.dart';

/// ORDER-EDIT-001E (review fixes) — an UNRESOLVED edit's Retry is reachable
/// through the REAL hosts, and its row says what the edit actually is.
///
/// An unresolved edit of an order withdraws every other action on it (pay,
/// bill, discount, cancel, add items, edit). On an unpaid TAKEAWAY order —
/// which has no table recovery sheet — the central policy then had nothing
/// left to offer, the Orders sheet and the detail preview skipped the whole
/// action row, and the Retry that lives in that row was never drawn: after a
/// restart the order stayed blocked on this till with no way to settle it.
///
/// Every case here goes through the real [RecentOrdersSheet] (or the detail
/// preview fed by the real [PosOrderActionsAssembly]) with a journal record
/// restored at start-up, exactly as after a restart:
///
///  * an outcome-unknown edit: the row carries "Changes not sent — tap to
///    retry", which replays the SAME identity and payload and releases the
///    order;
///  * an APPLIED edit whose start-up reconcile failed: the pill reads
///    "Change 1 saved" and the button "Refresh orders" — it only refreshes,
///    never sends again — and it resolves the record;
///  * this session's applied-but-unproven edit reads the same;
///  * a conflict reads the conflict wording, not "Sending changes…";
///  * the journal's start-up blanket reads the neutral "Checking for
///    unfinished changes", not "Sending changes…".

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');
const _code = '#A1B2C3';
const _orderId = 'order-1';

final DateTime _at = DateTime.now().toUtc().subtract(const Duration(hours: 1));

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

/// An unpaid TAKEAWAY order: Burger ×2 at 4000 + Fries 1500 = 9500.
PosOrderSnapshot _snap() => PosOrderSnapshot(
  orderId: _orderId,
  orderCode: _code,
  revision: 3,
  status: 'preparing',
  settlement: PosSettlement.unpaid,
  subtotalMinor: 9500,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 9500,
  createdAt: _at,
  updatedAt: _at,
  syncAt: _at,
  orderType: 'takeaway',
  currencyCode: 'ILS',
);

PosOrderDetail _order({int editCount = 0, List<PosOrderDetailEdit>? edits}) {
  final d = detail(
    items: [
      detailItem(
        'oi-burger',
        menuItemId: 'mi-burger',
        name: 'Burger',
        quantity: 2,
        unit: 4000,
      ),
      detailItem('oi-fries', menuItemId: 'mi-fries', name: 'Fries', unit: 1500),
    ],
    orderType: 'takeaway',
    tableLabel: null,
  );
  return PosOrderDetail(
    orderId: d.orderId,
    orderCode: d.orderCode,
    orderType: d.orderType,
    status: d.status,
    revision: d.revision + editCount,
    currencyCode: d.currencyCode,
    subtotalMinor: d.subtotalMinor,
    discountTotalMinor: d.discountTotalMinor,
    taxTotalMinor: d.taxTotalMinor,
    grandTotalMinor: d.grandTotalMinor,
    items: d.items,
    rounds: d.rounds,
    tableLabel: d.tableLabel,
    kitchenChannel: d.kitchenChannel,
    branchFeatures: d.branchFeatures,
    editCount: editCount,
    edits: edits ?? const [],
  );
}

/// The order after the server applied `edit-1` — what proves it.
PosOrderDetail _proven() => _order(
  editCount: 1,
  edits: const [PosOrderDetailEdit(orderEditId: 'edit-1', editNumber: 1)],
);

const _applied = OrderEditApplied(
  orderEditId: 'edit-1',
  editNumber: 1,
  revision: 4,
  kitchenChannel: PosKitchenChannel.kds,
  kitchenAckRequired: true,
);

OrderEditJournalRecord _record(
  OrderEditJournalPhase phase, {
  OrderEditApplied? applied,
}) => OrderEditJournalRecord(
  localOperationId: 'op-old',
  orderId: _orderId,
  orderCode: _code,
  clientCreatedAt: DateTime.utc(2026, 10, 9, 11),
  generation: 1,
  payload: const <String, Object?>{
    'order_id': _orderId,
    'expected': <String, Object?>{
      'subtotal_minor': 8000,
      'tax_total_minor': 0,
      'grand_total_minor': 8000,
    },
    'changes': <Object?>[
      <String, Object?>{'op': 'remove', 'order_item_id': 'oi-fries'},
    ],
  },
  summary: const OrderEditAttemptSummary(removedCount: 1),
  phase: phase,
  attemptCount: 1,
  applied: applied,
);

class _Transport implements SyncRpcTransport {
  _Transport(this.onApplied);
  final void Function() onApplied;
  final List<Map<String, dynamic>> ops = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function != 'sync_push') return {'ok': false};
    final op = ((params['p_operations'] as List).single as Map)
        .cast<String, dynamic>();
    ops.add(op);
    onApplied();
    return {
      'ok': true,
      'results': [
        {
          'local_operation_id': op['local_operation_id'],
          'operation_type': 'order.edit',
          'status': 'applied',
          'ok': true,
          'order_id': _orderId,
          'order_edit_id': 'edit-1',
          'edit_number': 1,
          'revision': 4,
          'kitchen_channel': 'kds',
          'kitchen_ack_required': true,
          'changes': const <Object?>[],
        },
      ],
    };
  }
}

class _Details implements OrderDetailRepository {
  PosOrderDetail? current;
  Object? error;

  @override
  Future<PosOrderDetail> fetch(String orderId) async {
    if (error case final e?) throw e;
    final d = current;
    if (d == null || d.orderId != orderId) {
      throw const PosOrderDetailException(
        PosOrderDetailFailure.notFound,
        'order_not_found',
      );
    }
    return d;
  }
}

class _Snapshots implements OrderSnapshotRepository {
  @override
  Future<PosSnapshotPage> fetchChanges({
    PosSyncCursor? cursor,
    int limit = 50,
    int windowDays = 2,
  }) async => PosSnapshotPage.empty;

  @override
  Future<PosSnapshotPage> fetchWindow({
    PosSyncCursor? before,
    int limit = 50,
    int windowDays = 2,
  }) async => PosSnapshotPage.empty;

  @override
  Future<PosSnapshotPage> fetchOrders(List<String> orderIds) async =>
      PosSnapshotPage(
        orders: [if (orderIds.contains(_orderId)) _snap()],
        hasMore: false,
      );
}

class _Tax implements DeviceBranchTaxReader {
  @override
  Future<BranchTax?> load() async => BranchTax.disabled;
}

/// A journal that is never read to the end — the start-up blanket stays up.
class _NeverReadJournal implements OrderEditJournalStore {
  @override
  Future<Map<String, OrderEditJournalRecord>> load(String scopeKey) =>
      Completer<Map<String, OrderEditJournalRecord>>().future;

  @override
  Future<void> persist(
    String scopeKey,
    Map<String, OrderEditJournalRecord> records,
  ) async {}
}

/// A journal that cannot be read — the blanket stays up for good.
class _UnreadableJournal implements OrderEditJournalStore {
  @override
  Future<Map<String, OrderEditJournalRecord>> load(String scopeKey) async =>
      throw StateError('unreadable');

  @override
  Future<void> persist(
    String scopeKey,
    Map<String, OrderEditJournalRecord> records,
  ) async {}
}

class _H {
  _H({required this.journal, bool proveOnApply = true}) {
    details.current = _order();
    transport = _Transport(() {
      if (proveOnApply) details.current = _proven();
    });
    c = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posAuthTransportProvider.overrideWithValue(transport),
        posSyncSessionProvider.overrideWithValue(_session),
        posSyncScopeProvider.overrideWithValue(kDemoSyncScope),
        posRecentOrdersStoreProvider.overrideWithValue(store),
        posSyncCursorStoreProvider.overrideWithValue(InMemorySyncCursorStore()),
        posSyncPollIntervalProvider.overrideWithValue(null),
        orderSnapshotRepositoryProvider.overrideWithValue(_Snapshots()),
        orderDetailRepositoryProvider.overrideWithValue(details),
        posVerifiedKitchenModeProvider.overrideWithValue(null),
        posBranchTaxReaderProvider.overrideWithValue(_Tax()),
        posMenuProvider.overrideWith(
          (ref) async => menuOf([
            menuItem('mi-burger', name: 'Burger', price: 4000),
            menuItem('mi-fries', name: 'Fries', price: 1500),
            menuItem('mi-cola', name: 'Cola', price: 800),
          ]),
        ),
        staffCapabilitiesProvider.overrideWith(
          (ref) async => PosStaffCapabilities.fromJson(
            const {'apply_discount': true, 'void_order': true},
            role: 'cashier',
            branchFeatures: const {
              'order_edit_enabled': true,
              'order_edit_finished_food_manager_only': false,
            },
          ),
        ),
        clientIdGeneratorProvider.overrideWithValue(
          FixedClientIdGenerator(const ['op-1', 'op-2']),
        ),
        orderEditJournalStoreProvider.overrideWithValue(journal),
      ],
    );
    addTearDown(c.dispose);
  }

  final OrderEditJournalStore journal;
  final InMemoryRecentOrdersStore store = InMemoryRecentOrdersStore();
  final _Details details = _Details();
  late final _Transport transport;
  late final ProviderContainer c;
  final Map<String, PosOrderActions> captured = {};
}

/// The assembly's verdict for every loaded order, in the SAME scope as the
/// host under test.
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
        orders.map((o) => MapEntry(o.orderNumber, assembly.resolveFor(o))),
      );
    return const SizedBox.shrink();
  }
}

Future<void> _pumpHost(WidgetTester tester, _H h, Widget host) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: h.c,
      child: MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              _Probe(h.captured),
              Expanded(child: host),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The real Orders sheet over [h], with the takeaway order loaded.
Future<void> _pumpSheet(WidgetTester tester, _H h) async {
  await h.store.persist(kDemoSyncScope.key, [
    PosRecentOrder.discovered(_snap()),
  ]);
  await _pumpHost(tester, h, const RecentOrdersSheet());
  expect(find.byKey(const Key('recent-order-$_code')), findsOneWidget);
}

Finder _retry([String prefix = 'recent']) =>
    find.byKey(Key('$prefix-edit-retry-$_code'));

Finder _pillText(String text, [String prefix = 'order']) => find.descendant(
  of: find.byKey(Key('$prefix-pending-$_code')),
  matching: find.text(text),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  group('the Retry is reachable through the real hosts', () {
    testWidgets('Orders sheet: a restored outcome-unknown edit on an unpaid '
        'takeaway order carries its Retry, which replays the SAME identity '
        'and payload and releases the order', (tester) async {
      final l10n = await _en();
      final journal = InMemoryOrderEditJournalStore();
      await journal.persist('dev-1', {
        'op-old': _record(OrderEditJournalPhase.transportUncertain),
      });
      final h = _H(journal: journal);
      await _pumpSheet(tester, h);

      // The edit withdrew every other action on the order...
      final actions = h.captured[_code]!;
      expect(actions.pendingKind, PosPendingKind.orderEdit);
      expect(actions.canPay, isFalse);
      expect(actions.canPrintBill, isFalse);
      expect(actions.canDiscount, isFalse);
      expect(actions.canVoid, isFalse);
      expect(actions.canAddItems, isFalse);
      expect(actions.canEditOrder, isFalse);
      expect(find.byKey(const Key('recent-pay-$_code')), findsNothing);
      // ...and yet its Retry is on the row.
      final retry = _retry();
      expect(retry, findsOneWidget);
      expect(
        find.descendant(of: retry, matching: find.text(l10n.posOrderEditRetry)),
        findsOneWidget,
      );

      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(h.transport.ops, hasLength(1));
      expect(h.transport.ops.single['local_operation_id'], 'op-old');
      expect(
        h.transport.ops.single['payload'],
        _record(OrderEditJournalPhase.transportUncertain).payload,
      );
      expect(await journal.load('dev-1'), isEmpty);
      // Settled: the Retry is gone and the order is payable again.
      expect(_retry(), findsNothing);
      expect(find.byKey(const Key('recent-pay-$_code')), findsOneWidget);
    });

    testWidgets('detail preview: the same order, resolved by the shared '
        'assembly, carries the Retry too', (tester) async {
      final l10n = await _en();
      final journal = InMemoryOrderEditJournalStore();
      await journal.persist('dev-1', {
        'op-old': _record(OrderEditJournalPhase.transportUncertain),
      });
      final h = _H(journal: journal);
      await _pumpSheet(tester, h);
      final actions = h.captured[_code]!;

      final order = PosRecentOrder.discovered(_snap());
      await _pumpHost(
        tester,
        h,
        OrderDetailPreview(order: order, actions: actions),
      );
      final retry = _retry('preview');
      expect(retry, findsOneWidget);
      expect(
        find.descendant(of: retry, matching: find.text(l10n.posOrderEditRetry)),
        findsOneWidget,
      );
    });

    testWidgets('an APPLIED edit whose start-up reconcile failed: "Change 1 '
        'saved", and "Refresh orders" resolves it without sending it '
        'again', (tester) async {
      final l10n = await _en();
      final journal = InMemoryOrderEditJournalStore();
      await journal.persist('dev-1', {
        'op-old': _record(
          OrderEditJournalPhase.awaitingAuthoritativeRefresh,
          applied: _applied,
        ),
      });
      final h = _H(journal: journal);
      // Offline at boot: the automatic reconcile cannot read the detail.
      h.details.error = const PosOrderDetailException(
        PosOrderDetailFailure.transport,
      );
      await _pumpSheet(tester, h);
      expect(await journal.load('dev-1'), hasLength(1));

      // The row never claims the change was not sent.
      expect(_pillText(l10n.posOrderEditResultSaved(1)), findsOneWidget);
      expect(find.text(l10n.posOrderEditSending), findsNothing);
      final retry = _retry();
      expect(retry, findsOneWidget);
      expect(
        find.descendant(of: retry, matching: find.text(l10n.posOrdersRefresh)),
        findsOneWidget,
      );
      expect(find.text(l10n.posOrderEditRetry), findsNothing);

      // Back online: the refresh proves the edit and closes the record.
      h.details
        ..error = null
        ..current = _proven();
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(h.transport.ops, isEmpty);
      expect(await journal.load('dev-1'), isEmpty);
      expect(_retry(), findsNothing);
      expect(find.byKey(const Key('recent-pay-$_code')), findsOneWidget);
    });
  });

  group('the row says what the edit actually is', () {
    testWidgets('this session\'s applied-but-unproven edit: "Change 1 saved" '
        'and "Refresh orders", never "Sending changes…" / "Changes not '
        'sent"', (tester) async {
      final l10n = await _en();
      final h = _H(
        journal: InMemoryOrderEditJournalStore(),
        proveOnApply: false,
      );
      await _pumpSheet(tester, h);

      final edit = h.c.read(orderEditControllerProvider.notifier);
      final entry = edit.enterForOrder(_orderId);
      await tester.pumpAndSettle();
      expect(await entry, OrderEditEntryResult.entered);
      h.c
          .read(cartControllerProvider.notifier)
          .addItem(menuItem('mi-cola', name: 'Cola', price: 800));
      final sent = edit.submit();
      await tester.pumpAndSettle();
      final result = await sent;
      expect(result.status, OrderEditSubmitStatus.applied);
      expect(result.refreshRequired, isTrue);
      expect(
        h.c.read(orderEditControllerProvider).phase,
        OrderEditPhase.appliedAwaitingRefresh,
      );

      expect(_pillText(l10n.posOrderEditResultSaved(1)), findsOneWidget);
      expect(find.text(l10n.posOrderEditSending), findsNothing);
      final retry = _retry();
      expect(retry, findsOneWidget);
      expect(
        find.descendant(of: retry, matching: find.text(l10n.posOrdersRefresh)),
        findsOneWidget,
      );
      expect(find.text(l10n.posOrderEditRetry), findsNothing);
    });

    testWidgets('a conflict reads the conflict wording', (tester) async {
      final l10n = await _en();
      final journal = InMemoryOrderEditJournalStore();
      await journal.persist('dev-1', {
        'op-old': _record(OrderEditJournalPhase.conflict),
      });
      final h = _H(journal: journal);
      await _pumpSheet(tester, h);
      expect(_pillText(l10n.posAdditionConflictBlocked), findsOneWidget);
      expect(find.text(l10n.posOrderEditSending), findsNothing);
      // A person must settle it: nothing to retry here.
      expect(_retry(), findsNothing);
    });

    testWidgets('while the edit journal is still being read: the neutral '
        '"Checking for unfinished changes"', (tester) async {
      final l10n = await _en();
      final h = _H(journal: _NeverReadJournal());
      await _pumpSheet(tester, h);
      expect(h.c.read(orderEditControllerProvider).isHydrating, isTrue);
      expect(_pillText(l10n.posAdditionLoadingPending), findsOneWidget);
      expect(find.text(l10n.posOrderEditSending), findsNothing);
    });

    testWidgets('an unreadable edit journal: the same neutral wording', (
      tester,
    ) async {
      final l10n = await _en();
      final h = _H(journal: _UnreadableJournal());
      await _pumpSheet(tester, h);
      expect(h.c.read(orderEditControllerProvider).hydrationFailed, isTrue);
      expect(_pillText(l10n.posAdditionLoadingPending), findsOneWidget);
      expect(find.text(l10n.posOrderEditSending), findsNothing);
    });
  });
}
