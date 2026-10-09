import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession;
import 'package:restoflow_domain/restoflow_domain.dart'
    show DiningTable, OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_tables.dart';
import 'package:restoflow_pos/src/data/kitchen_mode_readiness.dart'
    show posVerifiedKitchenModeProvider;
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_actions_assembly.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/order_snapshot_repository.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/staff_capabilities.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart';
import 'package:restoflow_pos/src/state/discount_controller.dart'
    show staffCapabilitiesProvider;
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_offline_state.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/order_action_row.dart';
import 'package:restoflow_pos/src/widgets/order_detail_preview.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';
import 'package:restoflow_pos/src/widgets/table_order_recovery_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ORDER-EDIT-001E — the "Edit order" ENTRY in the shared [OrderActionRow]
/// (ORDER_EDIT_DESIGN §7.1 step 1).
///
/// The button sits right after Add items and reaches every host of the row
/// through the shared assembly — the Orders sheet (`recent-`), the detail
/// preview (`preview-`) and the table recovery sheet (`table-recovery-`). It
/// is drawn only when the central policy says `canEditOrder`, and editing is
/// online-only: offline, a tap says so in the edit's own words.

const _code = '#ED0001';
const _orderId = 'oid-ED0001';

final DateTime _at = DateTime.now().toUtc().subtract(const Duration(hours: 1));

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

PosOrderSnapshot _snap({String status = 'preparing'}) => PosOrderSnapshot(
  orderId: _orderId,
  orderCode: _code,
  revision: 2,
  status: status,
  settlement: PosSettlement.unpaid,
  subtotalMinor: 4200,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 4200,
  createdAt: _at,
  updatedAt: _at,
  syncAt: _at,
  orderType: 'dine_in',
  tableLabel: 'T1',
  currencyCode: 'ILS',
);

PosRecentOrder _discovered() => PosRecentOrder.discovered(_snap());

const _enabled = {
  'order_edit_enabled': true,
  'order_edit_finished_food_manager_only': false,
};

PosStaffCapabilities _caps({
  String role = 'cashier',
  Object? features = _enabled,
}) => PosStaffCapabilities.fromJson(
  const {'apply_discount': true, 'void_order': true},
  role: role,
  branchFeatures: features,
);

class _EmptyRepo implements OrderSnapshotRepository {
  _EmptyRepo([this.byId]);
  final PosOrderSnapshot? byId;

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
        orders: [if (byId case final s? when orderIds.contains(s.orderId)) s],
        hasMore: false,
      );
}

class _NoDetail implements OrderDetailRepository {
  @override
  Future<PosOrderDetail> fetch(String orderId) async =>
      throw const PosOrderDetailException(PosOrderDetailFailure.transport);
}

class _FakeOutbox extends OutboxController {
  _FakeOutbox(this.entries);
  final List<OutboxEntry> entries;
  @override
  List<OutboxEntry> build() => entries;
}

class _OfflineCached extends PosOfflineController {
  @override
  PosOfflineState build() => PosOfflineState(
    phase: PosOfflinePhase.offlineCached,
    snapshotFetchedAt: DateTime.utc(2026, 10, 8, 9),
    menuFromCache: true,
  );
}

/// The real-mode scope every host needs (no network: every read is faked).
List<Override> _realMode({
  PosStaffCapabilities? caps,
  bool demo = false,
  InMemoryRecentOrdersStore? store,
  PosOrderSnapshot? byId,
}) => [
  runtimeConfigProvider.overrideWithValue(RuntimeConfig.test(isDemoMode: demo)),
  posSyncSessionProvider.overrideWithValue(
    const SyncSession(pinSessionId: 'pin1', deviceId: 'dev1'),
  ),
  posSyncScopeProvider.overrideWithValue(kDemoSyncScope),
  posRecentOrdersStoreProvider.overrideWithValue(
    store ?? InMemoryRecentOrdersStore(),
  ),
  posSyncCursorStoreProvider.overrideWithValue(InMemorySyncCursorStore()),
  posSyncPollIntervalProvider.overrideWithValue(null),
  orderSnapshotRepositoryProvider.overrideWithValue(_EmptyRepo(byId)),
  orderDetailRepositoryProvider.overrideWithValue(_NoDetail()),
  posVerifiedKitchenModeProvider.overrideWithValue(null),
  staffCapabilitiesProvider.overrideWith((ref) async => caps),
];

void _size(WidgetTester tester, [Size size = const Size(1400, 2400)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(List<Override> overrides, Widget body) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: Scaffold(body: body),
  ),
);

/// Resolves the SHARED assembly for one order in the surrounding scope and
/// renders the shared row with it — exactly what every host does.
class _RowHost extends ConsumerWidget {
  const _RowHost(this.order, {required this.captured});
  final PosRecentOrder order;
  final List<PosOrderActions> captured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final actions = PosOrderActionsAssembly.watch(ref, [
      order,
    ]).resolveFor(order);
    captured
      ..clear()
      ..add(actions);
    return OrderActionRow(order: order, l10n: l10n, actions: actions);
  }
}

/// Captures the assembly's verdict for every loaded order, in the SAME scope
/// as the Orders sheet under test (the parity-test idiom, in real mode).
class _AssemblyProbe extends ConsumerWidget {
  const _AssemblyProbe({required this.captured});
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

Finder _edit([String prefix = 'recent']) =>
    find.byKey(Key('$prefix-edit-order-$_code'));

int _indexInRow(WidgetTester tester, Finder button) {
  final wrap = tester.widget<Wrap>(
    find.ancestor(of: button, matching: find.byType(Wrap)).first,
  );
  final key = tester.widget(button).key;
  return wrap.children.indexWhere(
    (w) => w is OrderActionButton && w.child.key == key,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  group('visibility through the shared assembly', () {
    testWidgets('eligible: Edit order sits right after Add items', (
      tester,
    ) async {
      _size(tester);
      final l10n = await _en();
      final captured = <PosOrderActions>[];
      await tester.pumpWidget(
        _app(
          _realMode(caps: _caps()),
          _RowHost(_discovered(), captured: captured),
        ),
      );
      await tester.pumpAndSettle();

      expect(captured.single.canEditOrder, isTrue);
      final edit = _edit();
      expect(edit, findsOneWidget);
      expect(
        find.descendant(
          of: edit,
          matching: find.text(l10n.posRecoveryEditOrder),
        ),
        findsOneWidget,
      );
      final add = find.byKey(const Key('recent-add-items-$_code'));
      expect(add, findsOneWidget);
      expect(_indexInRow(tester, edit), _indexInRow(tester, add) + 1);
    });

    final hidden = <String, List<Override> Function()>{
      'the switch is OFF': () => _realMode(
        caps: _caps(
          features: const {
            'order_edit_enabled': false,
            'order_edit_finished_food_manager_only': false,
          },
        ),
      ),
      'the switch is unknown': () => _realMode(caps: _caps(features: null)),
      'capabilities are unknown': () => _realMode(caps: null),
      'demo mode': () => _realMode(caps: _caps(), demo: true),
      'a kitchen_staff session': () =>
          _realMode(caps: _caps(role: 'kitchen_staff')),
    };
    for (final entry in hidden.entries) {
      testWidgets('hidden when ${entry.key}; Add items is untouched', (
        tester,
      ) async {
        _size(tester);
        final captured = <PosOrderActions>[];
        await tester.pumpWidget(
          _app(entry.value(), _RowHost(_discovered(), captured: captured)),
        );
        await tester.pumpAndSettle();
        expect(captured.single.canEditOrder, isFalse);
        expect(_edit(), findsNothing);
        expect(
          find.byKey(const Key('recent-add-items-$_code')),
          findsOneWidget,
        );
      });
    }

    testWidgets('hidden while the server has not acknowledged the submit', (
      tester,
    ) async {
      _size(tester);
      // A device-owned order whose `order.submit` is IN FLIGHT: no longer
      // `pending` (so Add items stays), yet the server may never have taken
      // it — exactly the case `!submitUnacknowledged` exists for.
      final order = PosRecentOrder(
        order: SubmittedOrderView(
          orderNumber: _code,
          orderType: OrderType.dineIn,
          currencyCode: 'ILS',
          subtotalMinor: 4200,
          orderId: _orderId,
          tableLabel: 'T1',
          lines: const [],
        ),
        submittedAt: _at,
        status: 'preparing',
      );
      final entry = OutboxEntry(
        id: 'e1',
        deviceId: 'dev1',
        localOperationId: 'op-1',
        operationType: 'order.submit',
        targetEntity: 'order',
        targetId: _orderId,
        payloadJson: '{}',
        summary: const OrderSummary(
          orderNumber: _code,
          orderType: OrderType.dineIn,
          tableLabel: 'T1',
          itemCount: 1,
          subtotalMinor: 4200,
          currencyCode: 'ILS',
        ),
        syncState: OutboxSyncState.inFlight,
        clientCreatedAt: _at,
      );
      final captured = <PosOrderActions>[];
      await tester.pumpWidget(
        _app([
          ..._realMode(caps: _caps()),
          outboxControllerProvider.overrideWith(() => _FakeOutbox([entry])),
        ], _RowHost(order, captured: captured)),
      );
      await tester.pump();
      expect(captured.single.submitUnacknowledged, isTrue);
      expect(captured.single.canAddItems, isTrue);
      expect(captured.single.canEditOrder, isFalse);
      expect(_edit(), findsNothing);
    });
  });

  group('every host renders it', () {
    testWidgets('the Orders sheet (recent-), in parity with the assembly', (
      tester,
    ) async {
      _size(tester);
      final store = InMemoryRecentOrdersStore();
      await store.persist(kDemoSyncScope.key, [_discovered()]);
      final captured = <String, PosOrderActions>{};
      await tester.pumpWidget(
        _app(
          _realMode(caps: _caps(), store: store),
          Column(
            children: [
              _AssemblyProbe(captured: captured),
              const Expanded(child: RecentOrdersSheet()),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recent-order-$_code')), findsOneWidget);
      expect(captured[_code]?.canEditOrder, isTrue);
      expect(_edit(), findsOneWidget);
    });

    testWidgets('the detail preview (preview-)', (tester) async {
      _size(tester);
      final captured = <PosOrderActions>[];
      // Resolve through the shared assembly first, then hand the verdict to
      // the preview exactly as the strip and the Orders sheet do.
      await tester.pumpWidget(
        _app(
          _realMode(caps: _caps()),
          _RowHost(_discovered(), captured: captured),
        ),
      );
      await tester.pumpAndSettle();
      final actions = captured.single;
      expect(actions.canEditOrder, isTrue);
      await tester.pumpWidget(
        _app(
          _realMode(caps: _caps()),
          OrderDetailPreview(order: _discovered(), actions: actions),
        ),
      );
      await tester.pumpAndSettle();
      expect(_edit('preview'), findsOneWidget);
    });

    testWidgets('the table recovery sheet (table-recovery-)', (tester) async {
      _size(tester, const Size(1000, 1800));
      final entry = PosTableActiveOrder(
        orderId: _orderId,
        orderCode: _code,
        status: 'preparing',
        createdAt: _at,
        orderType: 'dine_in',
        revision: 2,
      );
      await tester.pumpWidget(
        _app(
          _realMode(caps: _caps(), byId: _snap()),
          TableOrderRecoverySheet(
            table: DemoTable(
              table: DiningTable(
                tableId: 't1',
                label: 'T1',
                organizationId: 'o',
                restaurantId: 'r',
                branchId: 'b',
              ),
              status: TableStatusKind.occupied,
              activeOrderCount: 1,
              activeOrders: [entry],
            ),
            entry: entry,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_edit('table-recovery'), findsOneWidget);
    });
  });

  testWidgets('offline: the tap says why, in the edit\'s own words', (
    tester,
  ) async {
    _size(tester);
    final l10n = await _en();
    await tester.pumpWidget(
      _app([
        ..._realMode(caps: _caps()),
        posOfflineModeProvider.overrideWith(_OfflineCached.new),
      ], _RowHost(_discovered(), captured: [])),
    );
    await tester.pumpAndSettle();
    await tester.tap(_edit());
    await tester.pump();
    expect(find.text(l10n.posOrderEditNeedsConnection), findsOneWidget);
    expect(find.text(l10n.posOfflineActionUnavailable), findsNothing);
  });

  testWidgets('a pending edit reads "Sending changes…"', (tester) async {
    _size(tester);
    final l10n = await _en();
    await tester.pumpWidget(
      _app(
        _realMode(caps: _caps()),
        OrderDetailPreview(
          order: _discovered(),
          actions: const PosOrderActions(
            canPay: false,
            canDiscount: false,
            canFullComp: false,
            canVoid: false,
            canMoveTable: false,
            canOpenReceipt: false,
            pendingKind: PosPendingKind.orderEdit,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('preview-pending-$_code')),
        matching: find.text(l10n.posOrderEditSending),
      ),
      findsOneWidget,
    );
  });
}
