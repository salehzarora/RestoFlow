/// DASHBOARD-VISUAL-RANGE-REFRESH-F3 — Top Selling Items + Recent Orders.
///
/// The one claim this file exists to defend: BOTH CARDS FOLLOW THE COMMITTED
/// ANALYTICS WINDOW. Before F3 neither did — top items and recent orders were
/// projections of `DashboardReport`, so they were empty in real mode and, in
/// demo, described "today" no matter which range was selected.
///
/// The tests are written against the SEAMS THAT CARRY THE WINDOW, not against
/// pixels: the query keys that identify a request, the parameters the real
/// repositories put on the wire, and the states each card renders. A widget
/// test that merely finds a card would pass with a hard-coded list, which is
/// precisely the defect F3 removes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_range.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_window.dart';
import 'package:restoflow_dashboard/src/analytics/overview_recent_orders_query_key.dart';
import 'package:restoflow_dashboard/src/analytics/owner_top_items_query_key.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/data/owner_top_items.dart';
import 'package:restoflow_dashboard/src/data/owner_top_items_repository.dart';
import 'package:restoflow_dashboard/src/data/real_order_history_repository.dart';
import 'package:restoflow_dashboard/src/data/real_owner_top_items_repository.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/widgets/recent_order_tile.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// Records every call and answers whatever the test told it to.
class _RecordingTransport implements SyncRpcTransport {
  _RecordingTransport({this.answer, this.error});

  /// Keyed by function name. Missing => a benign empty-but-ok payload.
  final Map<String, Object?>? answer;

  /// Keyed by function name. Thrown instead of answering.
  final Map<String, SyncTransportException>? error;

  final List<String> functions = <String>[];
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

  Map<String, dynamic>? lastTo(String fn) {
    for (var i = functions.length - 1; i >= 0; i--) {
      if (functions[i] == fn) return params[i];
    }
    return null;
  }

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> args) async {
    functions.add(function);
    params.add(args);
    final failure = error?[function];
    if (failure != null) throw failure;
    final canned = answer?[function];
    if (canned != null) return canned;
    return switch (function) {
      'owner_top_items' => <String, dynamic>{
        'ok': true,
        'currency_code': 'ILS',
        'range': args['p_range'] ?? 'custom',
        'items': <dynamic>[],
      },
      'owner_order_history' => <String, dynamic>{
        'ok': true,
        'currency_code': 'ILS',
        'orders': <dynamic>[],
        'has_more': false,
      },
      _ => <String, dynamic>{'ok': true},
    };
  }
}

MembershipContext _membership({
  String organizationId = 'org-1',
  String? restaurantId = 'rest-1',
  String? branchId = 'branch-1',
}) => MembershipContext(
  id: 'm-1',
  organizationId: organizationId,
  organizationName: 'Org',
  restaurantId: restaurantId,
  restaurantName: 'Rest One',
  branchId: branchId,
  branchName: 'Main',
  role: MembershipRole.orgOwner,
  status: 'active',
);

OwnerTopItemsQueryKey _topKey({
  AnalyticsRange range = AnalyticsRange.today,
  CustomAnalyticsWindow? custom,
  String? branchId,
  int limit = kOverviewTopItemsLimit,
}) => OwnerTopItemsQueryKey(
  organizationId: 'org-1',
  restaurantId: null,
  branchId: branchId,
  range: range,
  customWindow: custom,
  limit: limit,
  isDemoMode: false,
);

CustomAnalyticsWindow _custom(String start, String end) =>
    AnalyticsWindow.custom(DateTime.parse(start), DateTime.parse(end))
        as CustomAnalyticsWindow;

Future<OwnerTopItems> _loadTop(
  _RecordingTransport t, {
  required AnalyticsRange range,
  CustomAnalyticsWindow? custom,
  String? branchId,
  int limit = kOverviewTopItemsLimit,
}) {
  final repo = RealOwnerTopItemsRepository(scope: _membership(), transport: t);
  final key = _topKey(
    range: range,
    custom: custom,
    branchId: branchId,
    limit: limit,
  );
  return repo.loadTopItems(
    range: key.range,
    analyticsScope: key.analyticsScope,
    customWindow: key.customWindow,
    limit: key.limit,
  );
}

Widget _demoOverview() => const ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: DashboardHomeScreen(),
  ),
);

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  // =========================================================================
  // A — a PRESET selection travels as a preset, and only as a preset
  // =========================================================================
  group('A. top items: preset windows', () {
    test('sends p_range and NEVER p_start/p_end', () async {
      for (final range in AnalyticsRange.values) {
        final t = _RecordingTransport();
        await _loadTop(t, range: range);
        final call = t.lastTo('owner_top_items')!;
        expect(call['p_range'], range.wire, reason: 'range ${range.wire}');
        expect(call.containsKey('p_start'), isFalse);
        expect(call.containsKey('p_end'), isFalse);
      }
    });

    test(
      '60 and 90 travel as real tokens, never as an approximation',
      () async {
        final t = _RecordingTransport();
        await _loadTop(t, range: AnalyticsRange.last60);
        expect(t.lastTo('owner_top_items')!['p_range'], 'last60');
        await _loadTop(t, range: AnalyticsRange.last90);
        expect(t.lastTo('owner_top_items')!['p_range'], 'last90');
      },
    );

    test('requests the Overview card limit', () async {
      final t = _RecordingTransport();
      await _loadTop(t, range: AnalyticsRange.today);
      expect(t.lastTo('owner_top_items')!['p_limit'], kOverviewTopItemsLimit);
    });
  });

  // =========================================================================
  // B — a CUSTOM selection travels as two fixed dates, and only as dates
  // =========================================================================
  group('B. top items: custom windows', () {
    test('sends p_start/p_end and NEVER p_range', () async {
      final t = _RecordingTransport();
      await _loadTop(
        t,
        range: AnalyticsRange.today,
        custom: _custom('2026-03-01', '2026-03-14'),
      );
      final call = t.lastTo('owner_top_items')!;
      expect(call['p_start'], '2026-03-01');
      expect(call['p_end'], '2026-03-14');
      expect(
        call.containsKey('p_range'),
        isFalse,
        reason: 'a custom window must not also claim a preset',
      );
    });

    test('the custom window WINS over the range field beside it', () async {
      // The key carries both — `range` is whatever the chips last held. The
      // committed custom window is the selection, so it must be what ships.
      final t = _RecordingTransport();
      await _loadTop(
        t,
        range: AnalyticsRange.last90,
        custom: _custom('2026-01-05', '2026-01-06'),
      );
      final call = t.lastTo('owner_top_items')!;
      expect(call['p_start'], '2026-01-05');
      expect(call.containsKey('p_range'), isFalse);
    });
  });

  // =========================================================================
  // C — the scope in the KEY is the scope on the WIRE
  // =========================================================================
  group('C. top items: analytics scope', () {
    test('ORG-WIDE is not narrowed to the membership pins', () async {
      final t = _RecordingTransport();
      await _loadTop(t, range: AnalyticsRange.today);
      final call = t.lastTo('owner_top_items')!;
      expect(call['p_organization_id'], 'org-1');
      expect(call['p_restaurant_id'], isNull);
      expect(call['p_branch_id'], isNull);
    });

    test('a branch selection reaches the wire', () async {
      final t = _RecordingTransport();
      await _loadTop(t, range: AnalyticsRange.today, branchId: 'branch-9');
      expect(t.lastTo('owner_top_items')!['p_branch_id'], 'branch-9');
    });

    test('a key claiming a FOREIGN organization fails closed', () async {
      final t = _RecordingTransport();
      final repo = RealOwnerTopItemsRepository(
        scope: _membership(),
        transport: t,
      );
      await expectLater(
        repo.loadTopItems(
          range: AnalyticsRange.today,
          analyticsScope: const OwnerTopItemsQueryKey(
            organizationId: 'org-OTHER',
            restaurantId: null,
            branchId: null,
            range: AnalyticsRange.today,
            isDemoMode: false,
          ).analyticsScope,
        ),
        throwsA(isA<OwnerTopItemsException>()),
      );
      expect(t.functions, isEmpty, reason: 'nothing may reach the wire');
    });

    test('no transport at all is a failure, never an empty list', () async {
      const repo = RealOwnerTopItemsRepository();
      await expectLater(
        repo.loadTopItems(range: AnalyticsRange.today),
        throwsA(isA<RealRepoNotWiredError>()),
      );
    });
  });

  // =========================================================================
  // D/E/F — NOT DEPLOYED vs DENIED vs GENUINELY EMPTY stay three answers
  // =========================================================================
  group('D-F. top items: honest failure classification', () {
    test('D. a missing RPC (PGRST202) degrades to unavailable', () async {
      final t = _RecordingTransport(
        error: {
          'owner_top_items': const SyncTransportException(
            SyncTransportErrorKind.server,
            code: 'PGRST202',
            message: 'Could not find the function public.owner_top_items',
          ),
        },
      );
      final result = await _loadTop(t, range: AnalyticsRange.last7);
      expect(result.supported, isFalse);
      expect(result.items, isEmpty);
      expect(result.rangeWire, 'last7');
    });

    test('E. a 42501 denial THROWS — never softened to unavailable', () async {
      final t = _RecordingTransport(
        error: {
          'owner_top_items': const SyncTransportException(
            SyncTransportErrorKind.auth,
            code: '42501',
            message: 'permission denied',
          ),
        },
      );
      await expectLater(
        _loadTop(t, range: AnalyticsRange.today),
        throwsA(isA<OwnerTopItemsException>()),
      );
    });

    test('E2. an argument rejection (22023) THROWS', () async {
      final t = _RecordingTransport(
        error: {
          'owner_top_items': const SyncTransportException(
            SyncTransportErrorKind.server,
            code: '22023',
            message: 'custom range exceeds 92 days',
          ),
        },
      );
      await expectLater(
        _loadTop(t, range: AnalyticsRange.today),
        throwsA(isA<OwnerTopItemsException>()),
      );
    });

    test(
      'F. a successful EMPTY list is data, not a capability problem',
      () async {
        final t = _RecordingTransport();
        final result = await _loadTop(t, range: AnalyticsRange.last30);
        expect(result.supported, isTrue, reason: 'the RPC answered');
        expect(result.items, isEmpty);
        expect(result.isEmpty, isTrue);
      },
    );

    test(
      'F2. rows without an identity or a name are skipped, not invented',
      () async {
        final t = _RecordingTransport(
          answer: {
            'owner_top_items': <String, dynamic>{
              'ok': true,
              'currency_code': 'ILS',
              'range': 'today',
              'items': <dynamic>[
                <String, dynamic>{
                  'menu_item_id': 'mi-1',
                  'name': 'Margherita',
                  'quantity': 4,
                  'revenue_minor': 12000,
                  'order_count': 3,
                },
                <String, dynamic>{'name': 'no id'},
                <String, dynamic>{'menu_item_id': 'mi-2'},
              ],
            },
          },
        );
        final result = await _loadTop(t, range: AnalyticsRange.today);
        expect(result.items.map((i) => i.name), ['Margherita']);
        expect(result.items.single.lineRevenueMinor, 12000);
        expect(result.items.single.lineRevenueMinor, isA<int>());
      },
    );
  });

  // =========================================================================
  // G/H — Recent Orders rides the SAME window, at the Overview's page size
  // =========================================================================
  group('G-H. recent orders: window + limit', () {
    Future<void> load(
      _RecordingTransport t,
      OverviewRecentOrdersQueryKey key,
    ) async {
      final repo = RealOrderHistoryRepository(
        null,
        scope: _membership(),
        transport: t,
        analyticsScope: key.analyticsScope,
      );
      await repo.loadHistory(key.query);
    }

    OverviewRecentOrdersQueryKey key({
      AnalyticsRange range = AnalyticsRange.today,
      CustomAnalyticsWindow? custom,
    }) => OverviewRecentOrdersQueryKey(
      organizationId: 'org-1',
      restaurantId: null,
      branchId: null,
      range: range,
      customWindow: custom,
      isDemoMode: false,
    );

    test(
      'G. asks for exactly the Overview page size, not the history page size',
      () async {
        expect(kOverviewRecentOrdersLimit, 8);
        expect(kOrderHistoryPageSize, isNot(kOverviewRecentOrdersLimit));
        final t = _RecordingTransport();
        await load(t, key());
        expect(
          t.lastTo('owner_order_history')!['p_limit'],
          kOverviewRecentOrdersLimit,
        );
      },
    );

    test('G2. a preset window travels as p_range', () async {
      final t = _RecordingTransport();
      await load(t, key(range: AnalyticsRange.last60));
      final call = t.lastTo('owner_order_history')!;
      expect(call['p_range'], 'last60');
      expect(call.containsKey('p_start'), isFalse);
    });

    test(
      'H. a custom window travels as p_start/p_end, never p_range',
      () async {
        final t = _RecordingTransport();
        await load(t, key(custom: _custom('2026-02-02', '2026-02-09')));
        final call = t.lastTo('owner_order_history')!;
        expect(call['p_start'], '2026-02-02');
        expect(call['p_end'], '2026-02-09');
        expect(call.containsKey('p_range'), isFalse);
      },
    );

    test('H2. the Overview query carries NO row filters', () {
      // The Overview shows the newest orders in the window — full stop. A
      // filter leaking in here would make the card disagree with the KPIs
      // above it while looking exactly as authoritative.
      final q = key(range: AnalyticsRange.last7).query;
      expect(q.limit, kOverviewRecentOrdersLimit);
      expect(q.range, OrderHistoryRange.last7);
      expect(q.status, OrderStatusFilter.all);
      expect(q.orderType, OrderTypeFilter.all);
      expect(q.payment, PaymentFilter.all);
      expect(q.search, isEmpty);
    });
  });

  // =========================================================================
  // I — request identity: two windows are two requests
  // =========================================================================
  group('I. query-key identity', () {
    test('a preset key can never equal a custom key', () {
      final preset = _topKey(range: AnalyticsRange.last30);
      final custom = _topKey(
        range: AnalyticsRange.last30,
        custom: _custom('2026-03-01', '2026-03-30'),
      );
      expect(preset == custom, isFalse);
      expect(preset.window, isA<PresetAnalyticsWindow>());
      expect(custom.window, isA<CustomAnalyticsWindow>());
    });

    test('two different custom windows are two different requests', () {
      final a = _topKey(custom: _custom('2026-03-01', '2026-03-14'));
      final b = _topKey(custom: _custom('2026-03-02', '2026-03-14'));
      expect(a == b, isFalse);
      expect(a.hashCode == b.hashCode, isFalse);
    });

    test(
      'identical inputs are the same entry (value equality, stable hash)',
      () {
        final a = _topKey(custom: _custom('2026-03-01', '2026-03-14'));
        final b = _topKey(custom: _custom('2026-03-01', '2026-03-14'));
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      },
    );

    test(
      'the limit is part of identity — 10 rows cannot answer a 50-row ask',
      () {
        expect(_topKey(limit: 10) == _topKey(limit: 50), isFalse);
      },
    );

    test('demo and real are different sources, so different entries', () {
      const demo = OwnerTopItemsQueryKey(
        organizationId: 'org-1',
        restaurantId: null,
        branchId: null,
        range: AnalyticsRange.today,
        isDemoMode: true,
      );
      const real = OwnerTopItemsQueryKey(
        organizationId: 'org-1',
        restaurantId: null,
        branchId: null,
        range: AnalyticsRange.today,
        isDemoMode: false,
      );
      expect(demo == real, isFalse);
    });

    test('recent-orders keys follow the same rule', () {
      OverviewRecentOrdersQueryKey k({CustomAnalyticsWindow? c}) =>
          OverviewRecentOrdersQueryKey(
            organizationId: 'org-1',
            restaurantId: null,
            branchId: null,
            range: AnalyticsRange.today,
            customWindow: c,
            isDemoMode: false,
          );
      expect(k() == k(c: _custom('2026-03-01', '2026-03-02')), isFalse);
      expect(
        k(c: _custom('2026-03-01', '2026-03-02')),
        k(c: _custom('2026-03-01', '2026-03-02')),
      );
    });
  });

  // =========================================================================
  // Demo: the window actually moves the numbers
  // =========================================================================
  group('demo repository follows the window', () {
    DemoOwnerTopItemsRepository repo() =>
        DemoOwnerTopItemsRepository(clock: () => DateTime.utc(2026, 3, 20));

    test('a longer preset sells more than a shorter one', () async {
      final today = await repo().loadTopItems(range: AnalyticsRange.today);
      final month = await repo().loadTopItems(range: AnalyticsRange.last30);
      expect(today.items, isNotEmpty);
      expect(month.items, isNotEmpty);
      expect(month.topRevenueMinor, greaterThan(today.topRevenueMinor));
    });

    test('every preset answers with its own wire token', () async {
      for (final range in AnalyticsRange.values) {
        final r = await repo().loadTopItems(range: range);
        expect(r.rangeWire, range.wire);
      }
    });

    test('a custom window answers `custom`, never a preset token', () async {
      final r = await repo().loadTopItems(
        range: AnalyticsRange.today,
        customWindow: _custom('2026-03-01', '2026-03-14'),
      );
      expect(r.rangeWire, kCustomRangeWire);
      expect(r.items, isNotEmpty);
    });

    test('ranking is revenue-desc and the card limit is honoured', () async {
      final r = await repo().loadTopItems(
        range: AnalyticsRange.last30,
        limit: 3,
      );
      expect(r.items.length, lessThanOrEqualTo(3));
      for (var i = 1; i < r.items.length; i++) {
        expect(
          r.items[i - 1].lineRevenueMinor,
          greaterThanOrEqualTo(r.items[i].lineRevenueMinor),
        );
      }
    });

    test('money stays integer minor units (D-007)', () async {
      final r = await repo().loadTopItems(range: AnalyticsRange.last7);
      for (final item in r.items) {
        expect(item.lineRevenueMinor, isA<int>());
        expect(item.quantity, isA<int>());
      }
    });

    test(
      'a failing demo repository surfaces the error, not an empty card',
      () async {
        await expectLater(
          const DemoOwnerTopItemsRepository(
            failureMessage: 'boom',
          ).loadTopItems(range: AnalyticsRange.today),
          throwsA(isA<OwnerTopItemsException>()),
        );
      },
    );
  });

  // =========================================================================
  // The cards themselves: every state is reachable and distinct
  // =========================================================================
  group('cards render honest states', () {
    testWidgets('demo Overview renders BOTH lists', (tester) async {
      _size(tester, const Size(1320, 3600));
      await tester.pumpWidget(_demoOverview());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('top-items-card')), findsOneWidget);
      expect(find.byKey(const Key('top-items-list')), findsOneWidget);
      expect(find.byType(RestoflowRankRow), findsWidgets);

      expect(find.byKey(const Key('recent-orders-card')), findsOneWidget);
      expect(find.byKey(const Key('recent-orders-list')), findsOneWidget);
      expect(find.byType(RecentOrderTile), findsWidgets);
    });

    testWidgets('an UNDEPLOYED RPC reads as unavailable, never as empty', (
      tester,
    ) async {
      _size(tester, const Size(1320, 3600));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ownerTopItemsRepositoryProvider.overrideWithValue(
              const _UnavailableTopItems(),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: DashboardHomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('top-items-unavailable')), findsOneWidget);
      expect(find.byKey(const Key('top-items-empty')), findsNothing);
      expect(find.byKey(const Key('top-items-list')), findsNothing);
    });

    testWidgets('a GENUINELY empty window reads as empty, not unavailable', (
      tester,
    ) async {
      _size(tester, const Size(1320, 3600));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ownerTopItemsRepositoryProvider.overrideWithValue(
              const _EmptyTopItems(),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: DashboardHomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('top-items-empty')), findsOneWidget);
      expect(find.byKey(const Key('top-items-unavailable')), findsNothing);
    });

    testWidgets('a failure reads as an error, not as "nothing sold"', (
      tester,
    ) async {
      _size(tester, const Size(1320, 3600));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ownerTopItemsRepositoryProvider.overrideWithValue(
              const DemoOwnerTopItemsRepository(failureMessage: 'boom'),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: DashboardHomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('top-items-error')), findsOneWidget);
      expect(find.byKey(const Key('top-items-empty')), findsNothing);
      expect(find.byKey(const Key('top-items-unavailable')), findsNothing);
    });
  });
}

/// Answers "the RPC is not deployed here".
class _UnavailableTopItems implements OwnerTopItemsRepository {
  const _UnavailableTopItems();

  @override
  Future<OwnerTopItems> loadTopItems({
    required AnalyticsRange range,
    Object? analyticsScope,
    CustomAnalyticsWindow? customWindow,
    int limit = kOverviewTopItemsLimit,
  }) async => OwnerTopItems.unavailable(range.wire);
}

/// Answers "this window genuinely sold nothing".
class _EmptyTopItems implements OwnerTopItemsRepository {
  const _EmptyTopItems();

  @override
  Future<OwnerTopItems> loadTopItems({
    required AnalyticsRange range,
    Object? analyticsScope,
    CustomAnalyticsWindow? customWindow,
    int limit = kOverviewTopItemsLimit,
  }) async => OwnerTopItems(
    currencyCode: 'ILS',
    rangeWire: range.wire,
    items: const [],
  );
}
