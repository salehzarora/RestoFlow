@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_dashboard/src/admin/supabase_admin_device_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase/supabase.dart';

/// KIOSK-001-DEVICE-088 — LOCAL-ONLY end-to-end kiosk provisioning through
/// the SAME repository path the Dashboard uses. NEVER runs in CI/production:
/// skipped unless the LOCAL stack coordinates are passed explicitly:
///
///   flutter test test/integration \
///     --dart-define=RESTOFLOW_DASH_IT_URL=http://127.0.0.1:55321 \
///     --dart-define=RESTOFLOW_DASH_IT_ANON=sb_publishable_...
///
/// Prerequisites (driver-seeded): the kiosk IT org
/// (00000000-…-00713d0000a0) with branch …b1, and the owner login
/// kiosk-it-owner@local.test / local-owner-pass-088 holding an active
/// org_owner membership (LOCAL throwaway credentials, never production).
const _url = String.fromEnvironment('RESTOFLOW_DASH_IT_URL');
const _anon = String.fromEnvironment('RESTOFLOW_DASH_IT_ANON');
final String? _skip = _url.isEmpty || _anon.isEmpty
    ? 'local Supabase coordinates not provided (RESTOFLOW_DASH_IT_URL/_ANON)'
    : null;

const _scope = AdminScope(
  organizationId: '00000000-0000-0000-0000-00713d0000a0',
  organizationName: 'Kiosk IT Org',
  restaurantId: '00000000-0000-0000-0000-00713d0000a1',
  restaurantName: 'Kiosk IT Rest',
  branchId: '00000000-0000-0000-0000-00713d0000b1',
  branchName: 'Kiosk IT Branch',
  currencyCode: 'ILS',
  actingRole: MembershipRole.orgOwner,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SupabaseClient owner;
  late SupabaseAdminDeviceRepository repo;

  setUpAll(() async {
    if (_skip != null) return;
    HttpOverrides.global = null; // real local HTTP
    owner = SupabaseClient(_url, _anon);
    final auth = await owner.auth.signInWithPassword(
      email: 'kiosk-it-owner@local.test',
      password: 'local-owner-pass-088',
    );
    expect(auth.user, isNotNull);
    repo = SupabaseAdminDeviceRepository(
      transport: SupabaseSyncRpcTransport(owner),
      scope: _scope,
      currentUserId: () => owner.auth.currentUser?.id,
    );
  });

  test(
    'owner creates a KIOSK device through the Dashboard repository; the '
    'server persists device_type kiosk; the code redeems ONLY as kiosk',
    () async {
      // 1. Create — the exact generic path the Add-Device dialog calls.
      final created = await repo.createDevice(
        label: 'IT Lobby Kiosk 088',
        deviceType: 'kiosk',
      );
      final device = switch (created) {
        Success<AdminDevice, AdminFailure>(:final value) => value,
        Failure<AdminDevice, AdminFailure>(:final failure) => fail(
          'createDevice failed: $failure',
        ),
      };
      expect(device.deviceType, 'kiosk');

      // 2. The server round-trip agrees (loadDevices reads the stored row).
      final listed =
          (await repo.loadDevices())
              as Success<List<AdminDevice>, AdminFailure>;
      final stored = listed.value.firstWhere((d) => d.id == device.id);
      expect(
        stored.deviceType,
        'kiosk',
        reason: 'stored devices.device_type must be kiosk, never pos/kds',
      );

      // 3. Issue an enrollment code (the Issue-code panel path).
      final issued =
          (await repo.issueEnrollmentCode(device.id))
              as Success<EnrollmentCodeIssued, AdminFailure>;
      final code = issued.value.code;
      expect(code, isNotEmpty);

      // 4. A POS-declared redeem of the KIOSK code is REFUSED (exact-type
      //    match server-side) and does not consume the code...
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      Future<SupabaseDevicePairingRepository> anonPairing(String prefix) async {
        final t = await SupabaseAuthBootstrap(
          config: SupabaseBootstrapConfig.fromValues(url: _url, anonKey: _anon),
        ).createAnonymousDeviceTransport();
        return SupabaseDevicePairingRepository(
          transport: t,
          secretStore: SharedPreferencesDeviceSessionSecretStore(
            prefs,
            keyPrefix: prefix,
          ),
        );
      }

      final posAttempt = await (await anonPairing(
        kPosDeviceSessionPrefix,
      )).pairWithCode(code: code, deviceType: 'pos');
      expect(
        posAttempt,
        isA<Failure<DeviceContext, PairingFailure>>(),
        reason: 'a kiosk code must never redeem as POS',
      );

      // 5. ...while the KIOSK-declared redeem succeeds and the canonical
      //    restore path then recognizes the session.
      final kioskPairing = await anonPairing(kKioskDeviceSessionPrefix);
      final redeemed = await kioskPairing.pairWithCode(
        code: code,
        deviceType: 'kiosk',
      );
      final context = switch (redeemed) {
        Success<DeviceContext, PairingFailure>(:final value) => value,
        Failure<DeviceContext, PairingFailure>(:final failure) => fail(
          'kiosk redeem failed: ${failure.kind}',
        ),
      };
      expect(context.deviceType, 'kiosk');
      expect(context.deviceId, device.id);
      expect(
        await kioskPairing.restoreOutcome(expectedDeviceType: 'kiosk'),
        isA<DeviceSessionRestored>(),
      );
    },
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
