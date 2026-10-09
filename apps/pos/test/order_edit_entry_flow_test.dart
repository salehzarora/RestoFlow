import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show BranchTax, DeviceBranchTaxReader;
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/kitchen_mode_readiness.dart'
    show posVerifiedKitchenModeProvider;
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_edit_diff.dart'
    show OrderEditAttemptSummary;
import 'package:restoflow_pos/src/data/order_edit_journal_store.dart';
import 'package:restoflow_pos/src/data/order_edit_read_model.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/parked_carts_store.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/staff_capabilities.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/discount_controller.dart'
    show staffCapabilitiesProvider;
import 'package:restoflow_pos/src/state/order_edit_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_branch_tax.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_offline_state.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/widgets/order_action_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/order_edit_fixtures.dart';

/// ORDER-EDIT-001E — the "Edit order" ENTRY wired to the controller (plan
/// §8e; design §7.1 points 1-2), through the shared [OrderActionRow]:
///
///  * online with an empty cart, the tap opens the edit and closes the sheet
///    it came from;
///  * a cart holding other work is not a dead end — Cancel, Clear or Park,
///    and only then is the order reserved and loaded;
///  * a refused entry says why in the edit's own words (a not-found order is
///    "Waiting for the order to reach the server"; a switch that turned off
///    re-reads the session's capabilities);
///  * offline the controller is never called;
///  * an edit whose outcome is unknown carries its Retry on the row, and the
///    retry replays the SAME identity and payload.

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');
const _code = '#A1B2C3';

typedef _Handler = Object? Function(Map<String, dynamic> op);

class _Transport implements SyncRpcTransport {
  _Transport(this.handler);
  final _Handler handler;
  final List<Map<String, dynamic>> ops = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function != 'sync_push') return {'ok': false};
    final op = ((params['p_operations'] as List).single as Map)
        .cast<String, dynamic>();
    ops.add(op);
    return handler(op);
  }
}

class _Details implements OrderDetailRepository {
  final Map<String, PosOrderDetail> byId = {};
  int fetches = 0;

  @override
  Future<PosOrderDetail> fetch(String orderId) async {
    fetches++;
    final d = byId[orderId];
    if (d == null) {
      throw const PosOrderDetailException(
        PosOrderDetailFailure.notFound,
        'order_not_found',
      );
    }
    return d;
  }
}

class _Tax implements DeviceBranchTaxReader {
  @override
  Future<BranchTax?> load() async => BranchTax.disabled;
}

final DateTime _at = DateTime.now().toUtc().subtract(const Duration(hours: 1));

PosRecentOrder _row() => PosRecentOrder.discovered(
  PosOrderSnapshot(
    orderId: 'order-1',
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
    orderType: 'dine_in',
    tableLabel: '4',
    currencyCode: 'ILS',
  ),
);

const _actions = PosOrderActions(
  canPay: false,
  canDiscount: false,
  canFullComp: false,
  canVoid: false,
  canMoveTable: false,
  canOpenReceipt: false,
  canEditOrder: true,
  pendingKind: null,
);

/// Burger ×2 at 4000 + Fries 1500 = 9500.
PosOrderDetail _order({PosBranchFeatures? features = kFeaturesOn}) => detail(
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
  features: features,
);

PosOrderDetail _proven() {
  final d = _order();
  return PosOrderDetail(
    orderId: d.orderId,
    orderCode: d.orderCode,
    orderType: d.orderType,
    status: d.status,
    revision: d.revision + 1,
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
    editCount: 1,
    edits: const [PosOrderDetailEdit(orderEditId: 'edit-1', editNumber: 1)],
  );
}

/// An edit of `order-1` whose outcome is unknown (a dead transport).
OrderEditJournalRecord _uncertain() => OrderEditJournalRecord(
  localOperationId: 'op-old',
  orderId: 'order-1',
  orderCode: _code,
  clientCreatedAt: DateTime.utc(2026, 10, 9, 11),
  generation: 1,
  payload: const <String, Object?>{
    'order_id': 'order-1',
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
  phase: OrderEditJournalPhase.transportUncertain,
);

class _H {
  _H({
    PosOrderDetail? order,
    bool known = true,
    OrderEditJournalStore? journal,
  }) {
    if (known) details.byId['order-1'] = order ?? _order();
    transport = _Transport((op) {
      details.byId['order-1'] = _proven();
      return {
        'ok': true,
        'results': [
          {
            'local_operation_id': op['local_operation_id'],
            'operation_type': 'order.edit',
            'status': 'applied',
            'ok': true,
            'order_id': 'order-1',
            'order_edit_id': 'edit-1',
            'edit_number': 1,
            'revision': 4,
            'kitchen_channel': 'kds',
            'kitchen_ack_required': true,
            'changes': const <Object?>[],
          },
        ],
      };
    });
    c = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posAuthTransportProvider.overrideWithValue(transport),
        posSyncSessionProvider.overrideWithValue(_session),
        posSyncScopeProvider.overrideWithValue(kDemoSyncScope),
        parkedCartsStoreProvider.overrideWithValue(parked),
        orderDetailRepositoryProvider.overrideWithValue(details),
        orderSnapshotRepositoryProvider.overrideWithValue(
          DemoOrderSnapshotRepository(),
        ),
        posSyncPollIntervalProvider.overrideWithValue(null),
        posBranchTaxReaderProvider.overrideWithValue(_Tax()),
        posMenuProvider.overrideWith(
          (ref) async => menuOf([
            menuItem('mi-burger', name: 'Burger', price: 4000),
            menuItem('mi-fries', name: 'Fries', price: 1500),
            menuItem('mi-cola', name: 'Cola', price: 800),
          ]),
        ),
        staffCapabilitiesProvider.overrideWith((ref) async {
          capsLoads++;
          return PosStaffCapabilities.fromJson(
            const {'apply_discount': true, 'void_order': true},
            role: 'cashier',
            branchFeatures: const {
              'order_edit_enabled': true,
              'order_edit_finished_food_manager_only': false,
            },
          );
        }),
        clientIdGeneratorProvider.overrideWithValue(
          FixedClientIdGenerator(const ['op-1', 'op-2']),
        ),
        posVerifiedKitchenModeProvider.overrideWithValue(null),
        if (journal != null)
          orderEditJournalStoreProvider.overrideWithValue(journal),
      ],
    );
    addTearDown(c.dispose);
  }

  final _Details details = _Details();
  final InMemoryParkedCartsStore parked = InMemoryParkedCartsStore();
  late final _Transport transport;
  late final ProviderContainer c;
  int capsLoads = 0;

  CartViewState get cart => c.read(cartControllerProvider);
  OrderEditState get edit => c.read(orderEditControllerProvider);
}

/// The row inside a pushed route (the Orders sheet stand-in), opened.
Future<void> _pump(WidgetTester tester, _H h) async {
  tester.view.physicalSize = const Size(1200, 1800);
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
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('open-sheet'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: Builder(
                      builder: (inner) => OrderActionRow(
                        order: _row(),
                        l10n: AppLocalizations.of(inner),
                        actions: _actions,
                      ),
                    ),
                  ),
                ),
              ),
              child: const SizedBox(width: 10, height: 10),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-sheet')));
  await tester.pumpAndSettle();
  expect(find.byType(OrderActionRow), findsOneWidget);
}

Future<void> _tapEdit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('recent-edit-order-$_code')));
  await tester.pumpAndSettle();
}

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  testWidgets('online, empty cart: the edit opens and the sheet closes', (
    tester,
  ) async {
    final h = _H();
    await _pump(tester, h);
    await _tapEdit(tester);

    expect(find.byType(OrderActionRow), findsNothing);
    expect(h.edit.phase, OrderEditPhase.active);
    expect(h.cart.isEditing, isTrue);
    expect(h.cart.lines.map((l) => l.lineId), [
      'sent-oi-burger',
      'sent-oi-fries',
    ]);
  });

  group('a cart holding other work', () {
    testWidgets('Cancel: nothing is reserved, loaded or changed', (
      tester,
    ) async {
      final l10n = await _en();
      final h = _H();
      h.c
          .read(cartControllerProvider.notifier)
          .addItem(menuItem('mi-cola', name: 'Cola', price: 800));
      await _pump(tester, h);
      await _tapEdit(tester);

      expect(find.text(l10n.posParkedActiveCartTitle), findsOneWidget);
      expect(find.text(l10n.posOrderEditCartNotEmptyBody), findsOneWidget);
      await tester.tap(find.byKey(const Key('order-edit-cart-prompt-cancel')));
      await tester.pumpAndSettle();

      expect(h.details.fetches, 0);
      expect(h.edit.phase, OrderEditPhase.idle);
      expect(h.cart.isEditing, isFalse);
      expect(h.cart.lines.single.name, 'Cola');
      expect(find.byType(OrderActionRow), findsOneWidget);
    });

    testWidgets('Clear, then the edit opens', (tester) async {
      final h = _H();
      h.c
          .read(cartControllerProvider.notifier)
          .addItem(menuItem('mi-cola', name: 'Cola', price: 800));
      await _pump(tester, h);
      await _tapEdit(tester);
      await tester.tap(find.byKey(const Key('order-edit-cart-prompt-clear')));
      await tester.pumpAndSettle();

      expect(h.cart.isEditing, isTrue);
      expect(h.cart.lines.any((l) => l.name == 'Cola'), isFalse);
      expect(find.byType(OrderActionRow), findsNothing);
    });

    testWidgets('Park, then the edit opens', (tester) async {
      final h = _H();
      h.c
          .read(cartControllerProvider.notifier)
          .addItem(menuItem('mi-cola', name: 'Cola', price: 800));
      await _pump(tester, h);
      await _tapEdit(tester);
      await tester.tap(find.byKey(const Key('order-edit-cart-prompt-park')));
      await tester.pumpAndSettle();

      expect(h.cart.isEditing, isTrue);
      final stored = await h.parked.load(kDemoSyncScope);
      expect(stored.carts.single.draft.lines.single.menuItemId, 'mi-cola');
    });
  });

  testWidgets('a not-found order: "Waiting for the order to reach the '
      'server"', (tester) async {
    final l10n = await _en();
    final h = _H(known: false);
    await _pump(tester, h);
    await _tapEdit(tester);
    expect(find.text(l10n.posOrderEditBlockedUnacknowledged), findsOneWidget);
    expect(h.cart.isEditing, isFalse);
    expect(find.byType(OrderActionRow), findsOneWidget);
  });

  testWidgets('the switch turned off: says so and re-reads the capabilities', (
    tester,
  ) async {
    final l10n = await _en();
    final h = _H(
      order: _order(
        features: const PosBranchFeatures(
          orderEditEnabled: false,
          finishedFoodManagerOnly: false,
        ),
      ),
    );
    await _pump(tester, h);
    final before = h.capsLoads;
    await _tapEdit(tester);
    expect(find.text(l10n.posOrderEditErrorFeatureDisabled), findsOneWidget);
    expect(h.cart.isEditing, isFalse);
    h.c.read(staffCapabilitiesProvider);
    await tester.pumpAndSettle();
    expect(h.capsLoads, greaterThan(before));
  });

  testWidgets('offline: the controller is never called', (tester) async {
    final l10n = await _en();
    final h = _H();
    h.c
        .read(posOfflineModeProvider.notifier)
        .recordOfflineCacheServed(snapshotFetchedAt: DateTime.utc(2026, 10, 9));
    await _pump(tester, h);
    await _tapEdit(tester);
    expect(find.text(l10n.posOrderEditNeedsConnection), findsOneWidget);
    expect(h.details.fetches, 0);
    expect(h.edit.phase, OrderEditPhase.idle);
    expect(h.edit.generation, 0);
  });

  testWidgets('offline with a non-empty cart: the connection message, never '
      'the Park / Clear prompt', (tester) async {
    final l10n = await _en();
    final h = _H();
    h.c
        .read(cartControllerProvider.notifier)
        .addItem(menuItem('mi-cola', name: 'Cola', price: 800));
    h.c
        .read(posOfflineModeProvider.notifier)
        .recordOfflineCacheServed(snapshotFetchedAt: DateTime.utc(2026, 10, 9));
    await _pump(tester, h);
    await _tapEdit(tester);
    expect(find.text(l10n.posOrderEditNeedsConnection), findsOneWidget);
    expect(find.byKey(const Key('order-edit-cart-prompt')), findsNothing);
    expect(h.cart.lines.single.name, 'Cola');
  });

  group('the row\'s retry', () {
    testWidgets('absent without an unresolved edit', (tester) async {
      final h = _H();
      await _pump(tester, h);
      expect(find.byKey(const Key('recent-edit-retry-$_code')), findsNothing);
    });

    testWidgets('an unknown outcome: Retry replays the SAME identity and '
        'payload', (tester) async {
      final l10n = await _en();
      final journal = InMemoryOrderEditJournalStore();
      await journal.persist('dev-1', {'op-old': _uncertain()});
      final h = _H(journal: journal);
      await _pump(tester, h);

      final retry = find.byKey(const Key('recent-edit-retry-$_code'));
      expect(retry, findsOneWidget);
      expect(
        find.descendant(of: retry, matching: find.text(l10n.posOrderEditRetry)),
        findsOneWidget,
      );
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(h.transport.ops, hasLength(1));
      expect(h.transport.ops.single['local_operation_id'], 'op-old');
      expect(h.transport.ops.single['payload'], _uncertain().payload);
      expect(find.text('Change 1 sent: kitchen must confirm'), findsOneWidget);
      // Proven and closed: the row no longer offers it.
      expect(find.byKey(const Key('recent-edit-retry-$_code')), findsNothing);
      expect(await journal.load('dev-1'), isEmpty);
    });
  });
}
