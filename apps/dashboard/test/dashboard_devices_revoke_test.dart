import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/admin/supabase_admin_device_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Object? Function(String fn, Map<String, dynamic> params) _handler;
  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return _handler(function, params);
  }
}

SupabaseAdminDeviceRepository _repo(_FakeTransport t) =>
    SupabaseAdminDeviceRepository(
      transport: t,
      scope: AdminScope.demo,
      currentUserId: () => 'u',
      nonce: () => 1,
    );

void main() {
  group('SupabaseAdminDeviceRepository.revokeDevice', () {
    test(
      'calls revoke_device_management and returns the revoked state',
      () async {
        final t = _FakeTransport(
          (fn, p) => {
            'ok': true,
            'entity': 'device',
            'device_id': 'dev-1',
            'pairings_revoked': 1,
            'sessions_revoked': 1,
          },
        );
        final result = await _repo(t).revokeDevice('dev-1');
        final device = result.fold((d) => d, (f) => fail('expected success'));
        expect(device.status, DeviceLifecycleStatus.revoked);
        final call = t.calls.single;
        expect(call.$1, 'revoke_device_management');
        expect(call.$2['p_device_id'], 'dev-1');
      },
    );

    test('permission_denied maps to a typed failure', () async {
      final t = _FakeTransport(
        (fn, p) => {'ok': false, 'error': 'permission_denied'},
      );
      final result = await _repo(t).revokeDevice('dev-1');
      result.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<AdminPermissionDenied>()),
      );
    });

    test('the REAL repo disables the manual lifecycle simulation', () {
      final t = _FakeTransport((fn, p) => null);
      expect(_repo(t).supportsManualLifecycle, isFalse);
      // The demo store keeps it (the simulated RF-112 walkthrough).
      expect(
        DemoAdminStore(scope: AdminScope.demo).supportsManualLifecycle,
        isTrue,
      );
    });
  });

  group('AdminDevicesScreen with a REAL repo', () {
    Future<void> pump(WidgetTester tester, AdminRepository repo) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: adminFeatureOverrides(
            scope: AdminScope.demo,
            repository: repo,
          ),
          child: MaterialApp(
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const Scaffold(body: AdminDevicesScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Map<String, dynamic> listWith(String status) => {
      'ok': true,
      'devices': [
        {
          'device_id': 'dev-1',
          'label': 'Counter POS',
          'device_type': 'pos',
          'branch_label': 'Main',
          'status': status,
          'device_pairing_id': status == 'none' ? null : 'pair-1',
        },
      ],
    };

    testWidgets(
      'a code_issued device shows the pair-on-device hint, no manual Redeem',
      (tester) async {
        final t = _FakeTransport((fn, p) => listWith('code_issued'));
        await pump(tester, _repo(t));
        expect(find.text('Counter POS'), findsOneWidget);
        // Device-originated pairing (RF-161): the manager never "redeems".
        expect(find.text('Redeem'), findsNothing);
        expect(
          find.textContaining("pairing screen to pair it"),
          findsOneWidget,
        );
        // A revocable pairing exists -> Revoke is offered.
        expect(find.text('Revoke'), findsOneWidget);
      },
    );

    testWidgets('an active device offers Revoke (confirmed) and revokes', (
      tester,
    ) async {
      var revoked = false;
      final t = _FakeTransport((fn, p) {
        if (p.containsKey('p_organization_id')) {
          return listWith(revoked ? 'revoked' : 'active');
        }
        revoked = true;
        return {'ok': true, 'device_id': 'dev-1'};
      });
      await pump(tester, _repo(t));
      expect(find.text('Revoke'), findsOneWidget);

      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();
      // Confirm dialog -> the destructive confirm button.
      await tester.tap(find.widgetWithText(FilledButton, 'Revoke'));
      await tester.pumpAndSettle();

      expect(revoked, isTrue);
      expect(find.textContaining('Revoked'), findsWidgets);
    });

    testWidgets('a revoked device offers a fresh Issue code action', (
      tester,
    ) async {
      final t = _FakeTransport((fn, p) => listWith('revoked'));
      await pump(tester, _repo(t));
      expect(find.text('Issue code'), findsOneWidget);
      expect(find.text('Revoke'), findsNothing);
    });
  });
}
