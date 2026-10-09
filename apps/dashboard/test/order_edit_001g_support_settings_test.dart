/// ORDER-EDIT-001G — the "Editing sent orders" Settings card in ADMIN-126B
/// platform support mode, through the REAL DashboardShell.
///
/// A support session resolves a concrete branch and Settings is a
/// support-readable destination, but `get_branch_order_edit_settings` uses the
/// MEMBER rank and refuses a support session (`not_found`, pgTAP 126b D7). The
/// shell therefore withholds the card, as it withholds the Overview "Order
/// edits" block: never a false "This branch is not available for your account"
/// warning, and the refused read is never sent. The tenant's own Dashboard is
/// unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/dashboard_shell.dart';
import 'package:restoflow_dashboard/src/data/currency_breakdown_repository.dart';
import 'package:restoflow_dashboard/src/data/order_history_repository.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/data/owner_top_items_repository.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/state/order_history_providers.dart';
import 'package:restoflow_dashboard/src/support/support_mode_scope.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

const _reader = 'get_branch_order_edit_settings';

/// Records every RPC. The order-edit settings reader answers like the server
/// does for each caller (a support session is refused, 126b D7), the kitchen
/// workflow read answers for both (126b V11), and every other read answers
/// an honest refusal, which the surfaces already render as "unavailable".
class _RecordingTransport implements SyncRpcTransport {
  _RecordingTransport({required this.support});

  final bool support;
  final List<String> calls = <String>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> p) async {
    calls.add(function);
    if (function == _reader) {
      return support
          ? const {'ok': false, 'error': 'not_found', 'entity': 'branch'}
          : const {
              'ok': true,
              'order_edit_enabled': true,
              'order_edit_finished_food_manager_only': false,
              'kitchen_workflow_mode': 'kds',
            };
    }
    if (function == 'get_branch_kitchen_workflow_mode') {
      return const {'ok': true, 'kitchen_workflow_mode': 'kds'};
    }
    return const {'ok': false, 'error': 'not_found'};
  }
}

/// The support session's synthesized membership with the concrete branch the
/// tenant-context resolver fills in from `list_org_structure`.
const _member = MembershipContext(
  id: 'support-member',
  organizationId: 'org-1',
  organizationName: 'Maps Group',
  restaurantId: 'rest-1',
  restaurantName: 'Maps Burger',
  branchId: 'branch-1',
  branchName: 'Kafr Manda',
  role: MembershipRole.orgOwner,
  status: 'active',
);

Future<void> _pumpSettings(
  WidgetTester tester,
  _RecordingTransport transport, {
  required bool supportMode,
}) async {
  tester.view.physicalSize = const Size(1400, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        dashboardCurrencyGuardProvider.overrideWith(
          (ref) async => const ReportCurrencyGuard.single('ILS'),
        ),
        ownerReportsRepositoryProvider.overrideWithValue(
          DemoOwnerReportsRepository(),
        ),
        ownerTopItemsRepositoryProvider.overrideWithValue(
          const DemoOwnerTopItemsRepository(),
        ),
        orderHistoryRepositoryProvider.overrideWithValue(
          DemoOrderHistoryRepository(),
        ),
      ],
      child: SupportModeScope(
        active: supportMode,
        child: MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: DashboardShell(
            membership: _member,
            currencyCode: 'ILS',
            reportsTransport: transport,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('dashboard-nav-9')).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('support mode: Settings omits the order-editing card and never '
      'sends its refused read', (tester) async {
    final transport = _RecordingTransport(support: true);
    await _pumpSettings(tester, transport, supportMode: true);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Settings itself rendered, with its support-readable kitchen card.
    expect(
      find.text(l10n.dashboardKitchenWorkflowSectionTitle),
      findsOneWidget,
    );
    expect(transport.calls, contains('get_branch_kitchen_workflow_mode'));

    expect(find.byKey(const Key('order-edit-settings-section')), findsNothing);
    expect(transport.calls, isNot(contains(_reader)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tenant Dashboard still shows and reads the card', (
    tester,
  ) async {
    final transport = _RecordingTransport(support: false);
    await _pumpSettings(tester, transport, supportMode: false);
    expect(
      find.byKey(const Key('order-edit-settings-section')),
      findsOneWidget,
    );
    expect(transport.calls, contains(_reader));
    expect(tester.takeException(), isNull);
  });
}
