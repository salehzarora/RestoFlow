@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_kiosk/src/data/kiosk_fixtures.dart';
import 'package:restoflow_kiosk/src/data/kiosk_live_data.dart';
import 'package:restoflow_kiosk/src/data/kiosk_menu_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// KIOSK-001 Phase 3 — LOCAL-ONLY integration proof against a local Supabase
/// stack. NEVER runs in CI or against production: every test is skipped
/// unless the LOCAL stack coordinates are passed explicitly:
///
///   flutter test test/integration \
///     --dart-define=RESTOFLOW_KIOSK_IT_URL=http://127.0.0.1:55321 \
///     --dart-define=RESTOFLOW_KIOSK_IT_ANON=sb_publishable_...
///
/// Prerequisites (the driver seeds these; see the Phase-3 PR notes):
///   * a kiosk device with a CODE_ISSUED pairing for code KIOSK-IT-CODE-1
///   * an EXPIRED kiosk session with token kiosk-it-expired-token
///   * a live POS device session with token pos-it-token
///   * a small live menu (incl. a sold-out item + a required group) + tables
///     in all four states
const _url = String.fromEnvironment('RESTOFLOW_KIOSK_IT_URL');
const _anon = String.fromEnvironment('RESTOFLOW_KIOSK_IT_ANON');
final String? _skip = _url.isEmpty || _anon.isEmpty
    ? 'local Supabase coordinates not provided (RESTOFLOW_KIOSK_IT_URL/_ANON)'
    : null;

const _kioskDeviceId = '00000000-0000-0000-0000-00713d000001';
const _posDeviceId = '00000000-0000-0000-0000-00713d000002';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SupabaseDevicePairingRepository pairing;
  late SharedPreferencesDeviceSessionSecretStore store;
  late KioskLiveReads reads;

  setUpAll(() async {
    if (_skip != null) return;
    // flutter_test fakes every HttpClient with a 400 stub; this harness
    // talks to the REAL local stack, so restore real networking.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = SharedPreferencesDeviceSessionSecretStore(
      prefs,
      keyPrefix: kKioskDeviceSessionPrefix,
    );
    final transport = await SupabaseAuthBootstrap(
      config: SupabaseBootstrapConfig.fromValues(url: _url, anonKey: _anon),
    ).createAnonymousDeviceTransport();
    pairing = SupabaseDevicePairingRepository(
      transport: transport,
      secretStore: store,
    );
    reads = KioskLiveReads(transport: transport, secretStore: store);
  });

  test(
    'redeems the enrollment code as a KIOSK and persists the session',
    () async {
      final result = await pairing.pairWithCode(
        code: 'KIOSK-IT-CODE-1',
        deviceType: 'kiosk',
      );
      final context = switch (result) {
        Success<DeviceContext, PairingFailure>(:final value) => value,
        Failure<DeviceContext, PairingFailure>(:final failure) => fail(
          'redeem failed: ${failure.kind}',
        ),
      };
      expect(context.deviceType, 'kiosk');
      expect(context.deviceId, _kioskDeviceId);
      final cred = await store.read();
      expect(cred, isNotNull);
      expect(cred!.deviceId, _kioskDeviceId);
      expect(cred.sessionToken, isNotEmpty);
    },
    skip: _skip,
  );

  test('restores the persisted session through the canonical path', () async {
    final outcome = await pairing.restoreOutcome(expectedDeviceType: 'kiosk');
    expect(outcome, isA<DeviceSessionRestored>());
    expect((outcome as DeviceSessionRestored).context.deviceType, 'kiosk');
  }, skip: _skip);

  test('kiosk_menu returns the live tenant menu, correctly mapped', () async {
    final result = await reads.fetchMenu();
    final menu = switch (result) {
      KioskReadOk<KioskMenuData>(:final value) => value,
      KioskReadError<KioskMenuData>(:final kind) => fail('menu failed: $kind'),
    };
    expect(menu.live, isTrue);
    expect(menu.currencyCode, 'ILS');
    expect(menu.categories, isNotEmpty);
    final burger = menu.tryItem('00000000-0000-0000-0000-00713d00a001');
    expect(burger, isNotNull);
    expect(burger!.basePriceMinor, 4000);
    expect(burger.available, isTrue);
    expect(burger.groupIds, isNotEmpty);
    final soldOut = menu.tryItem('00000000-0000-0000-0000-00713d00a002');
    expect(soldOut!.available, isFalse);
    expect(soldOut.availabilityReason, 'sold_out');
    final group = menu.group(burger.groupIds.first)!;
    expect(group.isRequired, isTrue);
    expect(group.options.map((o) => o.priceDeltaMinor), contains(1500));
  }, skip: _skip);

  test('kiosk_tables returns the live floor with honest states', () async {
    final result = await reads.fetchTables();
    final zones = switch (result) {
      KioskReadOk<List<KioskFixtureZone>>(:final value) => value,
      KioskReadError<List<KioskFixtureZone>>(:final kind) => fail(
        'tables failed: $kind',
      ),
    };
    final states = {
      for (final z in zones)
        for (final t in z.tables) t.label: t.state,
    };
    expect(states['IT1'], KioskTableState.available);
    expect(states['IT2'], KioskTableState.occupied);
    expect(states['IT3'], KioskTableState.reserved);
    expect(states['IT4'], KioskTableState.outOfService);
  }, skip: _skip);

  test('a POS token is refused by the kiosk read family', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final posStore = SharedPreferencesDeviceSessionSecretStore(
      prefs,
      keyPrefix: kPosDeviceSessionPrefix,
    );
    await posStore.write(
      const DeviceSessionCredential(
        deviceId: _posDeviceId,
        sessionToken: 'pos-it-token',
      ),
    );
    final transport = await SupabaseAuthBootstrap(
      config: SupabaseBootstrapConfig.fromValues(url: _url, anonKey: _anon),
    ).createAnonymousDeviceTransport();
    final posReads = KioskLiveReads(
      transport: transport,
      secretStore: posStore,
    );
    final result = await posReads.fetchMenu();
    expect(
      (result as KioskReadError).kind,
      KioskReadFailureKind.invalidSession,
    );
  }, skip: _skip);

  test('an EXPIRED kiosk session is refused (RF-118)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final expiredStore = SharedPreferencesDeviceSessionSecretStore(
      prefs,
      keyPrefix: kKioskDeviceSessionPrefix,
    );
    await expiredStore.write(
      const DeviceSessionCredential(
        deviceId: _kioskDeviceId,
        sessionToken: 'kiosk-it-expired-token',
      ),
    );
    final transport = await SupabaseAuthBootstrap(
      config: SupabaseBootstrapConfig.fromValues(url: _url, anonKey: _anon),
    ).createAnonymousDeviceTransport();
    final expiredReads = KioskLiveReads(
      transport: transport,
      secretStore: expiredStore,
    );
    final result = await expiredReads.fetchMenu();
    expect(
      (result as KioskReadError).kind,
      KioskReadFailureKind.invalidSession,
    );
  }, skip: _skip);

  test(
    'a WRONG token is refused; a REVOKED session restore lands rejected',
    () async {
      // wrong token
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final wrongStore = SharedPreferencesDeviceSessionSecretStore(
        prefs,
        keyPrefix: kKioskDeviceSessionPrefix,
      );
      await wrongStore.write(
        const DeviceSessionCredential(
          deviceId: _kioskDeviceId,
          sessionToken: 'definitely-not-a-token',
        ),
      );
      final transport = await SupabaseAuthBootstrap(
        config: SupabaseBootstrapConfig.fromValues(url: _url, anonKey: _anon),
      ).createAnonymousDeviceTransport();
      final wrongReads = KioskLiveReads(
        transport: transport,
        secretStore: wrongStore,
      );
      expect(
        ((await wrongReads.fetchMenu()) as KioskReadError).kind,
        KioskReadFailureKind.invalidSession,
      );

      // revoked: unpair the REAL session (server revoke + local clear), then a
      // restore must land Rejected and the reads must refuse.
      await pairing.unpair();
      expect(
        await pairing.restoreOutcome(expectedDeviceType: 'kiosk'),
        isA<DeviceSessionRestoreRejected>(),
      );
      expect(
        ((await reads.fetchMenu()) as KioskReadError).kind,
        KioskReadFailureKind.invalidSession,
      );
    },
    skip: _skip,
  );
}
