/// ORDER-EDIT-001G — the order drawer's "Changes" timeline, its round-aware
/// status pill and the "Edited ×N" badge (`owner_order_detail`, API_CONTRACT
/// §4.47a).
///
/// The timeline is parsed ALL OR NOTHING: a partial history would say an order
/// was changed fewer times than it was, so any malformed element hides the
/// whole timeline instead.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/data/demo_order_store.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/data/order_history_repository.dart';
import 'package:restoflow_dashboard/src/data/real_order_history_repository.dart';
import 'package:restoflow_dashboard/src/orders/order_history_screen.dart';
import 'package:restoflow_dashboard/src/state/order_history_providers.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

Future<AppLocalizations> _l10n(String code) =>
    AppLocalizations.delegate.load(Locale(code));

Map<String, Object?> _edit(
  int n, {
  String? reason = 'customer_changed_mind',
  String? text,
  String channel = 'kds',
  bool required = true,
  String? ackAt,
  bool pending = false,
}) => <String, Object?>{
  'edit_number': n,
  'created_at': '2026-10-09 12:5$n',
  'reason_code': reason,
  'reason_text': text,
  'kitchen_channel': channel,
  'kitchen_ack_required': required,
  'kitchen_ack_at': ackAt,
  'kitchen_ack_pending': pending,
};

const _timeline = <OrderEditTimelineEntry>[
  OrderEditTimelineEntry(
    editNumber: 1,
    createdAtLabel: '2026-10-09 12:51',
    reasonCode: 'customer_changed_mind',
    kitchenChannel: 'kds',
    kitchenAckRequired: true,
    kitchenAckAtLabel: '2026-10-09 12:53',
    kitchenAckPending: false,
  ),
  OrderEditTimelineEntry(
    editNumber: 2,
    createdAtLabel: '2026-10-09 12:55',
    reasonCode: 'other',
    reasonText: 'Guest allergy',
    kitchenChannel: 'kds',
    kitchenAckRequired: true,
    kitchenAckPending: true,
  ),
  OrderEditTimelineEntry(
    editNumber: 3,
    createdAtLabel: '2026-10-09 12:58',
    kitchenChannel: 'paper',
    kitchenAckRequired: false,
    kitchenAckPending: false,
  ),
];

OrderDetail _detail({
  String status = 'served',
  int editCount = 3,
  bool? hasActiveRound = true,
  bool? activeRoundsReady = false,
  List<OrderEditTimelineEntry>? edits = _timeline,
}) => OrderDetail(
  orderId: 'o-1',
  orderCode: '#ABC123',
  status: status,
  orderType: 'dine_in',
  currencyCode: 'ILS',
  subtotalMinor: 5700,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 5700,
  createdAtLabel: '2026-10-09 12:40',
  items: const [
    OrderDetailItem(name: 'Burger', quantity: 1, lineTotalMinor: 5700),
  ],
  editCount: editCount,
  hasActiveRound: hasActiveRound,
  activeRoundsReady: activeRoundsReady,
  edits: edits,
);

Widget _wrap(OrderDetail detail, {String locale = 'en'}) => ProviderScope(
  overrides: [
    runtimeConfigProvider.overrideWithValue(
      RuntimeConfig.test(isDemoMode: true),
    ),
    orderHistoryRepositoryProvider.overrideWithValue(
      DemoOrderHistoryRepository(
        orders: [DemoOrder(daysAgo: 0, detail: detail)],
      ),
    ),
  ],
  child: MaterialApp(
    locale: Locale(locale),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: const Scaffold(body: OrderHistoryScreen()),
  ),
);

Future<void> _openDrawer(
  WidgetTester tester,
  OrderDetail detail, {
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_wrap(detail, locale: locale));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('order-card-o-1')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('order-detail-sheet')), findsOneWidget);
}

Finder _inSheet(Finder f) => find.descendant(
  of: find.byKey(const Key('order-detail-sheet')),
  matching: f,
);

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this.response);
  final Object? response;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> args) async =>
      response;
}

MembershipContext _owner() => const MembershipContext(
  id: 'm1',
  organizationId: 'org-1',
  organizationName: 'Org 1',
  restaurantId: 'rest-1',
  restaurantName: 'Rest 1',
  branchId: 'branch-1',
  branchName: 'Branch 1',
  role: MembershipRole.orgOwner,
  status: 'active',
);

Map<String, Object?> _wireOrder({bool withKeys = true, Object? edits}) =>
    <String, Object?>{
      'order_id': 'o-1',
      'order_code': '#ABC123',
      'status': 'served',
      'order_type': 'dine_in',
      'currency_code': 'ILS',
      'subtotal_minor': 5700,
      'discount_total_minor': 0,
      'tax_total_minor': 0,
      'grand_total_minor': 5700,
      'items': <Object?>[],
      'payments': <Object?>[],
      if (withKeys) 'edit_count': 2,
      if (withKeys) 'has_active_round': true,
      if (withKeys) 'active_rounds_ready': true,
      if (withKeys)
        'edits':
            edits ??
            <Object?>[
              _edit(1, ackAt: '2026-10-09 12:53'),
              _edit(2, reason: null, channel: 'paper', required: false),
            ],
    };

void main() {
  group('the edits[] parser is all or nothing', () {
    test('a well-formed list keeps every entry, oldest first', () {
      final parsed = RealOrderHistoryRepository.parseOrderEditTimeline([
        _edit(1, ackAt: '2026-10-09 12:53'),
        _edit(2, reason: 'other', text: 'Allergy', pending: true),
      ])!;
      expect(parsed.map((e) => e.editNumber), [1, 2]);
      expect(parsed.first.kitchenAckAtLabel, '2026-10-09 12:53');
      expect(parsed.last.reasonText, 'Allergy');
      expect(parsed.last.kitchenAckPending, isTrue);
    });

    test('an empty list is a known "no edits"', () {
      expect(RealOrderHistoryRepository.parseOrderEditTimeline([]), isEmpty);
    });

    test('absent or not a list is unknown (null)', () {
      expect(RealOrderHistoryRepository.parseOrderEditTimeline(null), isNull);
      expect(RealOrderHistoryRepository.parseOrderEditTimeline('x'), isNull);
    });

    test('ANY malformed element hides the whole timeline', () {
      final bad = <Map<String, Object?>>[
        {..._edit(2), 'edit_number': '2'},
        {..._edit(2), 'edit_number': 0},
        {..._edit(2), 'created_at': null},
        {..._edit(2), 'kitchen_channel': null},
        {..._edit(2), 'kitchen_ack_required': 'true'},
        {..._edit(2), 'kitchen_ack_pending': null},
      ];
      for (final b in bad) {
        expect(
          RealOrderHistoryRepository.parseOrderEditTimeline([_edit(1), b]),
          isNull,
          reason: '$b',
        );
      }
      expect(
        RealOrderHistoryRepository.parseOrderEditTimeline([_edit(1), 'x']),
        isNull,
      );
    });
  });

  group('owner_order_detail parse', () {
    test('the new keys are read', () async {
      final repo = RealOrderHistoryRepository(
        null,
        scope: _owner(),
        transport: _FakeTransport(<String, Object?>{
          'ok': true,
          'order': _wireOrder(),
        }),
      );
      final d = await repo.loadDetail('o-1');
      expect(d.editCount, 2);
      expect(d.hasActiveRound, isTrue);
      expect(d.activeRoundsReady, isTrue);
      expect(d.edits!.map((e) => e.editNumber), [1, 2]);
      expect(d.edits!.last.printedForKitchen, isTrue);
    });

    test('an older server reads as today: no badge, no timeline', () async {
      final repo = RealOrderHistoryRepository(
        null,
        scope: _owner(),
        transport: _FakeTransport(<String, Object?>{
          'ok': true,
          'order': _wireOrder(withKeys: false),
        }),
      );
      final d = await repo.loadDetail('o-1');
      expect(d.editCount, 0);
      expect(d.hasActiveRound, isNull);
      expect(d.activeRoundsReady, isNull);
      expect(d.edits, isNull);
    });

    test('a malformed edits[] keeps the rest of the order', () async {
      final repo = RealOrderHistoryRepository(
        null,
        scope: _owner(),
        transport: _FakeTransport(<String, Object?>{
          'ok': true,
          'order': _wireOrder(edits: <Object?>[_edit(1), 'broken']),
        }),
      );
      final d = await repo.loadDetail('o-1');
      expect(d.edits, isNull);
      expect(d.editCount, 2, reason: 'the badge still tells the truth');
      expect(d.grandTotalMinor, 5700);
    });
  });

  group('the drawer', () {
    testWidgets('timeline states: confirmed, pending, printed, other text', (
      tester,
    ) async {
      final l10n = await _l10n('en');
      await _openDrawer(tester, _detail());
      expect(
        _inSheet(find.byKey(const Key('order-detail-edits'))),
        findsOneWidget,
      );
      expect(_inSheet(find.text(l10n.ordersEditTimelineTitle)), findsOneWidget);
      for (final n in [1, 2, 3]) {
        expect(
          _inSheet(find.text(l10n.kitchenEditChangeNumber(n))),
          findsOneWidget,
        );
      }
      expect(
        _inSheet(
          find.text(l10n.ordersEditKitchenConfirmedAt('2026-10-09 12:53')),
        ),
        findsOneWidget,
      );
      expect(
        _inSheet(find.text(l10n.ordersEditKitchenPending)),
        findsOneWidget,
      );
      expect(
        _inSheet(find.text(l10n.ordersEditKitchenPrinted)),
        findsOneWidget,
      );
      expect(
        _inSheet(find.text(l10n.orderEditReasonCustomerChangedMind)),
        findsOneWidget,
      );
      expect(
        _inSheet(find.text('${l10n.orderEditReasonOther} · Guest allergy')),
        findsOneWidget,
      );
      // No raw wire tokens.
      for (final raw in ['customer_changed_mind', 'paper', 'kds']) {
        expect(_inSheet(find.textContaining(raw)), findsNothing, reason: raw);
      }
    });

    testWidgets('the pill reads In kitchen, or Ready when every active round '
        'is ready; the badge shows the count', (tester) async {
      final l10n = await _l10n('en');
      await _openDrawer(tester, _detail());
      final pill = find.byKey(const Key('order-detail-status-pill'));
      expect(
        find.descendant(
          of: pill,
          matching: find.text(l10n.ordersStatusInKitchen),
        ),
        findsOneWidget,
      );
      expect(_inSheet(find.text(l10n.ordersEditedBadge(3))), findsOneWidget);
      await tester.tap(find.byKey(const Key('order-detail-close')));
      await tester.pumpAndSettle();

      await _openDrawer(tester, _detail(activeRoundsReady: true));
      expect(
        find.descendant(
          of: find.byKey(const Key('order-detail-status-pill')),
          matching: find.text(l10n.ordersStatusReady),
        ),
        findsOneWidget,
      );
    });

    testWidgets('no badge and no timeline for an unedited order', (
      tester,
    ) async {
      final l10n = await _l10n('en');
      await _openDrawer(
        tester,
        _detail(
          editCount: 0,
          hasActiveRound: false,
          activeRoundsReady: false,
          edits: const [],
        ),
      );
      expect(
        _inSheet(find.byKey(const Key('order-detail-edits'))),
        findsNothing,
      );
      expect(
        _inSheet(find.byKey(const Key('order-edited-badge'))),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('order-detail-status-pill')),
          matching: find.text(l10n.ordersStatusServed),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an unknown timeline (null) is hidden, the badge stays', (
      tester,
    ) async {
      final l10n = await _l10n('en');
      await _openDrawer(tester, _detail(edits: null));
      expect(
        _inSheet(find.byKey(const Key('order-detail-edits'))),
        findsNothing,
      );
      expect(_inSheet(find.text(l10n.ordersEditedBadge(3))), findsOneWidget);
    });

    testWidgets('Arabic and Hebrew render the timeline', (tester) async {
      for (final code in ['ar', 'he']) {
        final l10n = await _l10n(code);
        await _openDrawer(tester, _detail(), locale: code);
        expect(
          _inSheet(find.text(l10n.ordersEditTimelineTitle)),
          findsOneWidget,
        );
        expect(
          _inSheet(find.text(l10n.ordersEditKitchenPending)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('order-detail-close')));
        await tester.pumpAndSettle();
      }
    });
  });

  group('the demo store carries the edit facts', () {
    test('through serve, payment and completion', () {
      final store = DemoOrderStore([
        DemoOrder(
          daysAgo: 0,
          detail: _detail(status: 'ready', hasActiveRound: false),
        ),
      ]);
      expect(store.markServed('o-1').applied, isTrue);
      var d = store.orders.single.detail;
      expect(d.status, 'served');
      expect(d.editCount, 3);
      expect(d.hasActiveRound, isFalse);
      expect(d.activeRoundsReady, isFalse);
      expect(identical(d.edits, _timeline), isTrue);

      store.recordPayment('o-1');
      d = store.orders.single.detail;
      expect(d.status, 'completed');
      expect(d.editCount, 3);
      expect(d.edits, hasLength(3));
    });
  });
}
