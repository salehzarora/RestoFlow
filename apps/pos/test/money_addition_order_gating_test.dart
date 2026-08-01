import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/addition_journal_store.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/state/addition_controller.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MONEY-CODEX-FINAL-CLOSURE-005 self-review — THE PRODUCTION SURFACE.
///
/// F1 and F4 were proven at controller level, but the thing that actually stops
/// a cashier taking a payment against a total the server is about to change is
/// `RecentOrdersSheet`'s pending-kind map. Before 005 it was built from
/// `addition.target` alone, so:
///
///  * DURING HYDRATION no order was marked at all — the journal had not been
///    read, `target` was null, and every money action was on offer;
///  * AFTER a restart with two pending amendments only the FIRST was installed
///    as the active attempt, so the second order's Pay / Void / Discount stayed
///    live against an order this device has an unresolved operation for.
///
/// These drive the real widget.
const _base = 4500;
const _delta = 1500;
const _lineTotal = 12000; // 2 x (4500 + 1500)

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

const _meat240 = SelectedModifier(
  optionId: 'opt-240',
  modifierGroupId: 'grp-meat',
  groupName: 'Meat',
  optionName: '240g',
  priceDeltaMinor: _delta,
);

SubmittedOrderView _view(String code, String orderId) => SubmittedOrderView(
  orderNumber: code,
  orderType: OrderType.dineIn,
  currencyCode: 'ILS',
  subtotalMinor: _lineTotal,
  orderId: orderId,
  lines: const [
    SubmittedLineView(
      name: 'Burger',
      quantity: 2,
      lineTotalMinor: _lineTotal,
      currencyCode: 'ILS',
    ),
  ],
);

/// Two unpaid, chargeable orders — both would normally offer Take payment.
Future<InMemoryRecentOrdersStore> _seeded() async {
  final store = InMemoryRecentOrdersStore();
  final now = DateTime.now();
  await store.persist(kDemoSyncScope.key, [
    PosRecentOrder(order: _view('#AAA111', 'o-1'), submittedAt: now),
    PosRecentOrder(
      order: _view('#BBB222', 'o-2'),
      submittedAt: now.subtract(const Duration(minutes: 2)),
    ),
  ]);
  return store;
}

PosAdditionJournalRecord _record({
  required String localOperationId,
  required String orderId,
  required DateTime createdAt,
  String lineId = 'l-1',
}) => PosAdditionJournalRecord(
  localOperationId: localOperationId,
  orderId: orderId,
  orderCode: '#O00001',
  orderTypeWire: 'dine_in',
  generation: 1,
  itemsJson: const [
    {'menu_item_id': 'burger-meat', 'quantity': 2},
  ],
  lines: [
    CartLineView(
      lineId: lineId,
      menuItemId: 'burger-meat',
      name: 'Burger',
      quantity: 2,
      unitPriceMinor: _base,
      lineTotalMinor: _lineTotal,
      currencyCode: 'ILS',
      modifiers: const [_meat240],
    ),
  ],
  prepByItemId: const {},
  expectedDeltaMinor: _lineTotal,
  currencyCode: 'ILS',
  clientCreatedAt: createdAt,
  phase: PosAdditionJournalPhase.transportUncertain,
);

const _prefsKey = 'restoflow.pos.addition_journal.v1.dev-1';

Future<SharedPreferences> _seedJournal(
  List<PosAdditionJournalRecord> records,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    _prefsKey: jsonEncode(<String, Object?>{
      'version': SharedPrefsAdditionJournalStore.schemaVersion,
      'records': <String, Object?>{
        for (final r in records) r.localOperationId: r.toJson(),
      },
    }),
  });
  return SharedPreferences.getInstance();
}

/// A journal whose load is held open, so the hydration window can be observed.
class _HeldJournalStore implements PosAdditionJournalStore {
  _HeldJournalStore(this._records);
  final Map<String, PosAdditionJournalRecord> _records;
  final Completer<void> gate = Completer<void>();

  @override
  Future<Map<String, PosAdditionJournalRecord>> load(String scopeKey) async {
    await gate.future;
    return Map<String, PosAdditionJournalRecord>.of(_records);
  }

  @override
  Future<void> persist(
    String scopeKey,
    Map<String, PosAdditionJournalRecord> records,
  ) async {
    _records
      ..clear()
      ..addAll(records);
  }
}

class _FakeDetailRepo implements OrderDetailRepository {
  @override
  Future<PosOrderDetail> fetch(String orderId) async => PosOrderDetail(
    orderId: orderId,
    orderCode: '#O00001',
    orderType: 'dine_in',
    status: 'preparing',
    revision: 2,
    currencyCode: 'ILS',
    subtotalMinor: _lineTotal,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: _lineTotal,
    rounds: const [],
    items: const [],
  );
}

Widget _wrap(
  InMemoryRecentOrdersStore store,
  PosAdditionJournalStore journal,
) => ProviderScope(
  overrides: [
    posRecentOrdersStoreProvider.overrideWithValue(store),
    additionJournalStoreProvider.overrideWithValue(journal),
    posSyncSessionProvider.overrideWithValue(_session),
    orderDetailRepositoryProvider.overrideWithValue(_FakeDetailRepo()),
    runtimeConfigProvider.overrideWithValue(
      RuntimeConfig.test(isDemoMode: true),
    ),
  ],
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: const Scaffold(body: RecentOrdersSheet()),
  ),
);

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('A while the journal is still being read, NO order offers a '
      'money action — the affected ones are not yet known', (tester) async {
    _wide(tester);
    final journal = _HeldJournalStore({
      'op-1': _record(
        localOperationId: 'op-1',
        orderId: 'o-1',
        createdAt: DateTime.utc(2026, 8, 6, 10),
      ),
    });

    await tester.pumpWidget(_wrap(await _seeded(), journal));
    await tester.pump(); // one frame, hydration still in flight

    expect(
      find.byKey(const Key('recent-order-#AAA111')),
      findsOneWidget,
      reason: 'the rows are VISIBLE — this is not a blanket UI disable',
    );
    expect(
      find.byKey(const Key('recent-pay-#AAA111')),
      findsNothing,
      reason:
          'THE DEFECT: with the journal unread, every money action was on '
          'offer — including on the very order that has an unresolved '
          'amendment whose delta the server is about to add',
    );
    expect(
      find.byKey(const Key('recent-pay-#BBB222')),
      findsNothing,
      reason:
          'and on every other order too, because which ones are affected is '
          'exactly what we do not know yet',
    );

    journal.gate.complete();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('recent-pay-#BBB222')),
      findsOneWidget,
      reason:
          'once hydration finishes the UNAFFECTED order is usable again — the '
          'gate is brief and global, not a permanent lockout',
    );
  });

  testWidgets('B after a restart with TWO pending amendments, BOTH orders '
      'withdraw their money actions — not just the active one', (tester) async {
    _wide(tester);
    final prefs = await _seedJournal([
      _record(
        localOperationId: 'op-old',
        orderId: 'o-1',
        createdAt: DateTime.utc(2026, 8, 6, 10),
      ),
      _record(
        localOperationId: 'op-new',
        orderId: 'o-2',
        createdAt: DateTime.utc(2026, 8, 6, 11),
        lineId: 'l-2',
      ),
    ]);

    await tester.pumpWidget(
      _wrap(await _seeded(), SharedPrefsAdditionJournalStore(prefs)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('recent-pay-#AAA111')),
      findsNothing,
      reason: 'the ACTIVE amendment blocks its order, as it always did',
    );
    expect(
      find.byKey(const Key('recent-pay-#BBB222')),
      findsNothing,
      reason:
          'THE DEFECT: the sheet read only `addition.target`, so the SECOND '
          'pending amendment left its order fully payable against a total the '
          'server is about to change',
    );
  });

  testWidgets('C an order with NO pending amendment keeps its money actions', (
    tester,
  ) async {
    _wide(tester);
    final prefs = await _seedJournal([
      _record(
        localOperationId: 'op-1',
        orderId: 'o-1',
        createdAt: DateTime.utc(2026, 8, 6, 10),
      ),
    ]);

    await tester.pumpWidget(
      _wrap(await _seeded(), SharedPrefsAdditionJournalStore(prefs)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recent-pay-#AAA111')), findsNothing);
    expect(
      find.byKey(const Key('recent-pay-#BBB222')),
      findsOneWidget,
      reason:
          'the control: blocking is targeted, so an unrelated order is not '
          'collateral damage',
    );
  });
}
