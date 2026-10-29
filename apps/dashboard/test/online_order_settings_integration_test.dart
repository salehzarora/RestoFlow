import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/admin/real_admin_views.dart';
import 'package:restoflow_dashboard/src/online_orders/online_order_settings_repository.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

class _Repo implements OnlineOrderSettingsRepository {
  int reads = 0;
  @override
  Future<OnlineOrderResult> read() async {
    reads++;
    return const OnlineOrderResult(
      OnlineOrderOutcome.ok,
      settings: OnlineOrderSettings(
        revision: '12',
        values: OnlineOrderValues(
          ordering: true,
          alerts: false,
          printing: false,
        ),
      ),
    );
  }

  @override
  Future<OnlineOrderResult> save(OnlineOrderMutation intent) =>
      throw StateError('no writes in integration render');
  @override
  Future<OnlineOrderReconciliation> reconcile(OnlineOrderMutation intent) =>
      throw StateError('no receipt query in integration render');
}

Future<void> _pump(
  WidgetTester tester, {
  OnlineOrderSettingsRepository? repository,
  MembershipRole role = MembershipRole.manager,
  String? branch = 'synthetic-branch',
  String status = 'active',
}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: kSupportedLocales,
        localizationsDelegates: restoflowLocalizationsDelegates,
        home: Scaffold(
          body: RealSettingsView(
            membership: MembershipContext(
              id: 'synthetic-membership',
              organizationId: 'synthetic-org',
              organizationName: 'Synthetic org',
              restaurantId: 'synthetic-restaurant',
              restaurantName: 'Synthetic restaurant',
              branchId: branch,
              branchName: 'Selected QA branch',
              role: role,
              status: status,
            ),
            currencyCode: 'ILS',
            onlineOrderSettingsRepository: repository,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final role in [
    MembershipRole.orgOwner,
    MembershipRole.restaurantOwner,
    MembershipRole.manager,
  ]) {
    testWidgets(
      '${role.name} gets independent Online Orders card for selected branch',
      (tester) async {
        final repo = _Repo();
        await _pump(tester, repository: repo, role: role);
        expect(repo.reads, 1);
        expect(
          find.byKey(const Key('online-order-settings-section')),
          findsOneWidget,
        );
        final toggle = tester.widget<SwitchListTile>(
          find.byKey(const Key('online-order-ordering-toggle')),
        );
        expect(toggle.onChanged, isNotNull);
        expect(find.text('Selected QA branch'), findsWidgets);
      },
    );
  }
  for (final role in [
    MembershipRole.cashier,
    MembershipRole.kitchenStaff,
    MembershipRole.accountant,
  ]) {
    testWidgets(
      '${role.name} cannot edit even if injected repository returns state',
      (tester) async {
        await _pump(tester, repository: _Repo(), role: role);
        expect(
          tester
              .widget<SwitchListTile>(
                find.byKey(const Key('online-order-ordering-toggle')),
              )
              .onChanged,
          isNull,
        );
      },
    );
  }
  testWidgets('no versioned seam means no fake controls', (tester) async {
    await _pump(tester);
    expect(
      find.byKey(const Key('online-order-settings-section')),
      findsNothing,
    );
  });
  testWidgets('no concrete branch means no controls or read', (tester) async {
    final repo = _Repo();
    await _pump(tester, repository: repo, branch: null);
    expect(repo.reads, 0);
    expect(
      find.byKey(const Key('online-order-settings-section')),
      findsNothing,
    );
  });
  testWidgets('inactive membership cannot edit even if role is manager', (
    tester,
  ) async {
    await _pump(tester, repository: _Repo(), status: 'revoked');
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('online-order-ordering-toggle')),
          )
          .onChanged,
      isNull,
    );
  });
}
