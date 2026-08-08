import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/data/order_history_repository.dart';
import 'package:restoflow_dashboard/src/orders/order_history_screen.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/state/order_history_providers.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-E2) — the Orders history scope is
/// legible.
///
/// The request now follows the Overview selection, which is the fix. But a list
/// that silently filters to one branch is exactly the defect CLIENT-E1 removed
/// from the Overview, so the scope has to be readable here too — with no raw
/// ids and no second selector to disagree with the first.

class _EmptyRepository implements OrderHistoryRepository {
  const _EmptyRepository();

  @override
  Future<OrderHistoryPage> loadHistory(
    OrderHistoryQuery query, {
    String? cursor,
  }) async => const OrderHistoryPage(rows: [], hasMore: false);

  @override
  Future<OrderDetail> loadDetail(String orderId) async =>
      throw UnimplementedError();
}

MembershipContext _membership(MembershipRole role) => MembershipContext(
  id: 'm-1',
  organizationId: 'org-1',
  organizationName: 'Org',
  restaurantId: 'rest-1',
  restaurantName: 'Rest One',
  branchId: 'branch-1',
  branchName: 'Main',
  role: role,
  status: 'active',
);

const _harbor = AuditBranchOption(
  organizationId: 'org-1',
  branchId: 'branch-2',
  restaurantId: 'rest-1',
  label: 'Rest One · Harbor',
);

Widget _wrap({
  required MembershipRole role,
  AuditBranchOption? selected,
  Locale locale = const Locale('en'),
}) => ProviderScope(
  overrides: [
    dashboardMembershipProvider.overrideWithValue(_membership(role)),
    orderHistoryRepositoryProvider.overrideWithValue(const _EmptyRepository()),
    selectedAnalyticsBranchProvider.overrideWith((ref) => selected),
  ],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    theme: restoflowBaseTheme(),
    home: const Scaffold(body: OrderHistoryScreen()),
  ),
);

void _size(WidgetTester tester, [Size size = const Size(1100, 2200)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

String _indicator(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('orders-scope-indicator'))).data!;

void main() {
  testWidgets('a broad scope reads "All permitted branches"', (tester) async {
    _size(tester);
    await tester.pumpWidget(_wrap(role: MembershipRole.orgOwner));
    await tester.pumpAndSettle();

    expect(_indicator(tester), 'Branch: All permitted branches');
  });

  testWidgets('a restaurant-wide scope also reads "All permitted branches" — '
      'every branch INSIDE what that owner may see', (tester) async {
    _size(tester);
    await tester.pumpWidget(_wrap(role: MembershipRole.restaurantOwner));
    await tester.pumpAndSettle();

    expect(_indicator(tester), 'Branch: All permitted branches');
  });

  testWidgets('a selected branch is named, with no raw id', (tester) async {
    _size(tester);
    await tester.pumpWidget(
      _wrap(role: MembershipRole.orgOwner, selected: _harbor),
    );
    await tester.pumpAndSettle();

    expect(_indicator(tester), 'Branch: Rest One · Harbor');
    expect(find.text('branch-2'), findsNothing);
    expect(find.text('rest-1'), findsNothing);
  });

  testWidgets('a branch-scoped membership names its own branch, and a foreign '
      'selection cannot rename it', (tester) async {
    _size(tester);
    await tester.pumpWidget(
      _wrap(role: MembershipRole.manager, selected: _harbor),
    );
    await tester.pumpAndSettle();

    expect(_indicator(tester), 'Branch: Main');
  });

  testWidgets('demo mode (no membership) shows no indicator, exactly as '
      'before', (tester) async {
    _size(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderHistoryRepositoryProvider.overrideWithValue(
            const _EmptyRepository(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          theme: restoflowBaseTheme(),
          home: const Scaffold(body: OrderHistoryScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('orders-scope-indicator')), findsNothing);
  });

  testWidgets('there is exactly ONE scope control on the surface — the '
      'indicator, never a second selector to disagree with Overview', (
    tester,
  ) async {
    _size(tester);
    await tester.pumpWidget(
      _wrap(role: MembershipRole.orgOwner, selected: _harbor),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('orders-scope-indicator')), findsOneWidget);
    expect(
      find.byType(DropdownButtonFormField<String?>),
      findsNothing,
      reason: 'no branch dropdown was added to Orders history',
    );
  });

  group('layout', () {
    testWidgets('renders at phone width without overflow', (tester) async {
      _size(tester, const Size(390, 2600));
      await tester.pumpWidget(
        _wrap(role: MembershipRole.orgOwner, selected: _harbor),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('orders-scope-indicator')), findsOneWidget);
    });

    testWidgets('survives a 2x text scale at phone width', (tester) async {
      _size(tester, const Size(390, 3600));
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        _wrap(role: MembershipRole.orgOwner, selected: _harbor),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    for (final locale in const [Locale('ar'), Locale('he')]) {
      testWidgets('renders RTL (${locale.languageCode})', (tester) async {
        _size(tester, const Size(390, 2600));
        await tester.pumpWidget(
          _wrap(
            role: MembershipRole.orgOwner,
            selected: _harbor,
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          Directionality.of(
            tester.element(find.byKey(const Key('orders-scope-indicator'))),
          ),
          TextDirection.rtl,
        );
        // The branch NAME is data and stays as the server sent it.
        expect(_indicator(tester), contains('Rest One · Harbor'));
      });
    }
  });
}
