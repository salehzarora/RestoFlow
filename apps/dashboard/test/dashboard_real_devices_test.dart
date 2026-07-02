import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'package:restoflow_dashboard/src/admin/supabase_admin_device_repository.dart';
import 'package:restoflow_dashboard/src/dashboard_shell.dart';

/// A fake transport that answers `list_devices` with one real device row.
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Object? Function(String, Map<String, dynamic>) _handler;
  @override
  Future<Object?> invoke(String fn, Map<String, dynamic> p) async =>
      _handler(fn, p);
}

MembershipContext _managerMembership() => const MembershipContext(
  id: 'm',
  organizationId: 'org-1',
  organizationName: 'Org A',
  restaurantId: 'rest-1',
  restaurantName: 'Rest',
  branchId: 'branch-1',
  branchName: 'Main',
  role: MembershipRole.manager,
  status: 'active',
);

void main() {
  testWidgets('the Devices tab is backed by the REAL repo (no demo banner)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    final transport = _FakeTransport((fn, p) {
      if (fn == 'list_devices') {
        return {
          'ok': true,
          'devices': [
            {
              'device_id': 'd1',
              'label': 'Real Wired POS',
              'device_type': 'pos',
              'branch_id': 'branch-1',
              'branch_label': 'Main',
              'status': 'none',
              'device_pairing_id': null,
              'has_open_session': false,
            },
          ],
        };
      }
      return {'ok': false, 'error': 'unexpected'};
    });

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          theme: restoflowBaseTheme(),
          home: DashboardShell(
            membership: _managerMembership(),
            deviceRepositoryFor: (scope) => SupabaseAdminDeviceRepository(
              transport: transport,
              scope: scope,
              currentUserId: () => 'u',
              nonce: () => 1,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.dashboardNavDevices).first);
    await tester.pumpAndSettle();

    expect(find.byType(AdminDevicesScreen), findsOneWidget);
    // The list comes from the REAL repo (the fake transport), not the demo seed.
    expect(find.text('Real Wired POS'), findsOneWidget);
    expect(find.text('Front Counter POS'), findsNothing);
    // A real surface shows NO demo banner.
    expect(find.text(l10n.adminDemoBanner), findsNothing);
  });
}
