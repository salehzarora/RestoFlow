import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
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
    Future<void> pump(
      WidgetTester tester,
      AdminRepository repo, {
      AdminScope scope = AdminScope.demo,
      PairingPanelPresenter? pairingPanel,
    }) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...adminFeatureOverrides(scope: scope, repository: repo),
            if (pairingPanel != null)
              devicePairingPanelProvider.overrideWithValue(pairingPanel),
          ],
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

    testWidgets(
      'LIVE-UX-001: a revoked device is HIDDEN from the active list (collapsed '
      'under "Revoked devices") and offers NO issue-code / revoke',
      (tester) async {
        final t = _FakeTransport((fn, p) => listWith('revoked'));
        await pump(tester, _repo(t));

        // Not clutter in the active list: no revoked tile, no misleading actions.
        // (Issuing a code for a revoked/inactive device raises 42501, which the
        // client can only show as a bogus "you don't have permission" toast.)
        expect(find.text('Issue code'), findsNothing);
        expect(find.text('Revoke'), findsNothing);
        expect(find.text('Counter POS'), findsNothing);

        // It moved to the collapsed revoked section (the "show revoked" toggle).
        final section = find.byKey(const Key('revoked-devices-section'));
        expect(section, findsOneWidget);
        expect(find.byKey(const Key('device-counts')), findsOneWidget);

        // Expanding reveals the read-only tile — still NO issue-code / revoke.
        await tester.tap(section);
        await tester.pumpAndSettle();
        expect(find.text('Counter POS'), findsOneWidget);
        expect(find.text('Issue code'), findsNothing);
        expect(find.text('Revoke'), findsNothing);
      },
    );

    testWidgets(
      'LIVE-UX-001: revoking removes the device from the ACTIVE list (it lands '
      'in the collapsed revoked section)',
      (tester) async {
        var revoked = false;
        final t = _FakeTransport((fn, p) {
          if (p.containsKey('p_organization_id')) {
            return listWith(revoked ? 'revoked' : 'active');
          }
          revoked = true;
          return {'ok': true, 'device_id': 'dev-1'};
        });
        await pump(tester, _repo(t));
        // Active to start: the tile + its Revoke action are in the main list.
        expect(find.text('Counter POS'), findsOneWidget);
        expect(find.text('Revoke'), findsOneWidget);
        expect(find.byKey(const Key('revoked-devices-section')), findsNothing);

        await tester.tap(find.text('Revoke'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Revoke'));
        await tester.pumpAndSettle();

        // Refetched: gone from the active list, now under the revoked section.
        expect(revoked, isTrue);
        expect(find.text('Counter POS'), findsNothing); // collapsed away
        expect(
          find.byKey(const Key('revoked-devices-section')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'LIVE-UX-001: a below-manager role gets NO usable device manage action — '
      'Revoke/Issue-code are hidden and Create is DISABLED (so the "you don\'t '
      'have permission" toast can never fire from a visible/tappable action)',
      (tester) async {
        final t = _FakeTransport((fn, p) => listWith('active'));
        await pump(
          tester,
          _repo(t),
          scope: AdminScope.demo.copyWith(actingRole: MembershipRole.cashier),
        );
        // The device still lists (a cashier may READ), but the destructive
        // per-device actions the backend would deny are HIDDEN entirely.
        expect(find.text('Counter POS'), findsOneWidget);
        expect(find.text('Revoke'), findsNothing);
        expect(find.text('Issue code'), findsNothing);
        // The header create affordance uses the real "Add device" label and is
        // present but DISABLED (onPressed null) for a below-manager role, so it
        // is never tappable — asserting on onPressed catches a future regression
        // that re-enables it (which would resurrect the permission-denied toast).
        final create = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Add device'),
        );
        expect(create.onPressed, isNull);
      },
    );

    Map<String, dynamic> issueResult() => {
      'ok': true,
      'enrollment_code': 'CODE-XY',
      'device_id': 'dev-1',
      'device_pairing_id': 'pair-1',
    };

    testWidgets(
      'LIVE-OPS-001: issuing a code shows the host QR pairing panel (not the '
      'plain one-time dialog), passing the device type + code',
      (tester) async {
        PairingPanelRequest? captured;
        final t = _FakeTransport((fn, p) {
          if (fn == 'list_devices') return listWith('none');
          if (fn == 'issue_device_enrollment_code') return issueResult();
          return null;
        });
        await pump(
          tester,
          _repo(t),
          pairingPanel: (ctx, req) async => captured = req,
        );

        await tester.tap(find.text('Issue code'));
        await tester.pumpAndSettle();

        expect(captured, isNotNull);
        expect(captured!.code, 'CODE-XY');
        expect(captured!.deviceType, 'pos');
        expect(captured!.deviceLabel, 'Counter POS');
        // The host panel REPLACED the plain one-time-secret dialog.
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        expect(find.text(l10n.adminShownOnce), findsNothing);
      },
    );

    testWidgets(
      'LIVE-OPS-001: with NO host panel, issuing a code falls back to the '
      'one-time-secret dialog (no behaviour lost)',
      (tester) async {
        final t = _FakeTransport((fn, p) {
          if (fn == 'list_devices') return listWith('none');
          if (fn == 'issue_device_enrollment_code') return issueResult();
          return null;
        });
        await pump(tester, _repo(t)); // no pairing-panel override

        await tester.tap(find.text('Issue code'));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        expect(find.text(l10n.adminShownOnce), findsOneWidget);
      },
    );
  });
}
