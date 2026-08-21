@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show displayOrderCode;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_kiosk/src/data/kiosk_fixtures.dart';
import 'package:restoflow_kiosk/src/data/kiosk_live_data.dart';
import 'package:restoflow_kiosk/src/data/kiosk_menu_data.dart';
import 'package:restoflow_kiosk/src/data/kiosk_order_submit.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// KIOSK-001-REAL-SUBMIT-092 — LOCAL-ONLY end-to-end real submits against a
/// local Supabase stack (never CI/production). Skipped unless the LOCAL
/// coordinates are passed explicitly:
///
///   flutter test test/integration \
///     --dart-define=RESTOFLOW_KIOSK_IT_URL=http://127.0.0.1:55321 \
///     --dart-define=RESTOFLOW_KIOSK_IT_ANON=sb_publishable_...
///
/// Driver prerequisites: the kiosk IT org + live menu/tables, and the
/// dedicated submit kiosk (device …005) with code KIOSK-IT-CODE-2. The
/// driver verifies the persisted rows via psql after this run.
const _url = String.fromEnvironment('RESTOFLOW_KIOSK_IT_URL');
const _anon = String.fromEnvironment('RESTOFLOW_KIOSK_IT_ANON');
final String? _skip = _url.isEmpty || _anon.isEmpty
    ? 'local Supabase coordinates not provided (RESTOFLOW_KIOSK_IT_URL/_ANON)'
    : null;

const _submitDeviceId = '00000000-0000-0000-0000-00713d000005';
const _tableIT1 = '00000000-0000-0000-0000-00713d00f101';
const _burger = '00000000-0000-0000-0000-00713d00a001';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SupabaseDevicePairingRepository pairing;
  late KioskLiveReads reads;
  late KioskOrderSubmitter submitter;
  late KioskBranchTaxReader taxReader;
  late KioskMenuData menu;
  late KioskBranchTax tax;

  KioskCartLine burgerLine({int qty = 1}) {
    final item = menu.itemById(_burger);
    final group = menu.group(item.groupIds.first)!;
    final option = group.options.firstWhere((o) => o.priceDeltaMinor > 0);
    return KioskCartLine(
      lineId: 1,
      itemId: item.id,
      quantity: qty,
      selected: {
        group.id: [option.id],
      },
      note: 'IT no salt',
      capturedUnitMinor: item.basePriceMinor + option.priceDeltaMinor,
    );
  }

  KioskSubmitAttempt attemptFor({
    required KioskServiceType service,
    String? tableId,
    int qty = 1,
  }) => buildKioskSubmitAttempt(
    menu: menu,
    cart: [burgerLine(qty: qty)],
    service: service,
    tableId: tableId,
    tax: tax,
    customerName: 'IT Guest',
    customerPhone: '050-000-0092',
    clientCreatedAt: DateTime.now(),
  );

  setUpAll(() async {
    if (_skip != null) return;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = SharedPreferencesDeviceSessionSecretStore(
      prefs,
      keyPrefix: kKioskDeviceSessionPrefix,
    );
    final session = await SupabaseAuthBootstrap(
      config: SupabaseBootstrapConfig.fromValues(url: _url, anonKey: _anon),
    ).createAnonymousDeviceSession();
    pairing = SupabaseDevicePairingRepository(
      transport: session.transport,
      secretStore: store,
    );
    reads = KioskLiveReads(transport: session.transport, secretStore: store);
    submitter = KioskOrderSubmitter(
      transport: session.transport,
      secretStore: store,
    );
    taxReader = KioskBranchTaxReader(
      transport: session.transport,
      secretStore: store,
    );
  });

  test('pairs the dedicated submit kiosk and loads live menu + tax', () async {
    final paired = await pairing.pairWithCode(
      code: 'KIOSK-IT-CODE-2',
      deviceType: 'kiosk',
    );
    expect(paired, isA<Success<DeviceContext, PairingFailure>>());
    expect(
      (paired as Success<DeviceContext, PairingFailure>).value.deviceId,
      _submitDeviceId,
    );
    menu = ((await reads.fetchMenu()) as KioskReadOk<KioskMenuData>).value;
    final t = await taxReader.load();
    expect(t, isNotNull, reason: 'the tax read must never silently fail');
    tax = t!;
  }, skip: _skip);

  late String takeawayOrderId;
  late KioskSubmitAttempt takeawayAttempt;

  test(
    'A. TAKEAWAY real submit is accepted (frozen snapshots, no discount)',
    () async {
      takeawayAttempt = attemptFor(service: KioskServiceType.takeaway, qty: 2);
      final r = await submitter.submit(takeawayAttempt);
      expect(r, isA<KioskSubmitAccepted>(), reason: '$r');
      final a = r as KioskSubmitAccepted;
      takeawayOrderId = a.orderId;
      expect(a.orderId, takeawayAttempt.orderId);
      expect(a.idempotencyReplay, isFalse);
      expect(a.orderStatus, 'submitted');
      // The kiosk confirmation code IS the shared cross-surface code.
      expect(displayOrderCode(a.orderId), startsWith('#'));
    },
    skip: _skip,
  );

  test('D. lost-response replay: the SAME attempt returns the SAME order '
      'exactly once', () async {
    final replay = await submitter.submit(takeawayAttempt);
    expect(replay, isA<KioskSubmitAccepted>());
    final a = replay as KioskSubmitAccepted;
    expect(a.orderId, takeawayOrderId, reason: 'same identity, same order');
    expect(
      a.idempotencyReplay,
      isTrue,
      reason: 'D-022 replays, not re-creates',
    );
  }, skip: _skip);

  test(
    'B. DINE-IN with the AUTHORITATIVE table UUID occupies the table',
    () async {
      final r = await submitter.submit(
        attemptFor(service: KioskServiceType.dineIn, tableId: _tableIT1),
      );
      expect(r, isA<KioskSubmitAccepted>(), reason: '$r');
      // Fresh floor truth: IT1 is no longer available to the next customer.
      final zones =
          ((await reads.fetchTables()) as KioskReadOk<List<KioskFixtureZone>>)
              .value;
      final it1 = zones
          .expand((z) => z.tables)
          .firstWhere((t) => t.id == _tableIT1);
      expect(it1.state, isNot(KioskTableState.available));
    },
    skip: _skip,
  );

  test('B2. the TABLE RACE is a stable, non-success refusal', () async {
    final r = await submitter.submit(
      attemptFor(service: KioskServiceType.dineIn, tableId: _tableIT1),
    );
    expect(r, isA<KioskSubmitRejected>(), reason: '$r');
    expect(
      (r as KioskSubmitRejected).code,
      anyOf('table_no_longer_available', 'table_not_available'),
    );
  }, skip: _skip);

  test(
    'C. DINE-IN WITHOUT a table (picker off) is accepted with NULL table',
    () async {
      final r = await submitter.submit(
        attemptFor(service: KioskServiceType.dineIn, tableId: null),
      );
      expect(r, isA<KioskSubmitAccepted>(), reason: '$r');
    },
    skip: _skip,
  );

  test('E. a forged price is the stable menu_price_changed refusal', () async {
    final item = menu.itemById(_burger);
    final group = menu.group(item.groupIds.first)!;
    final option = group.options.firstWhere((o) => o.priceDeltaMinor > 0);
    final forged = KioskSubmitAttempt(
      orderId: generateKioskUuidV4(),
      localOperationId: 'kiosk-${generateKioskUuidV4()}',
      params: {
        ...attemptFor(service: KioskServiceType.takeaway).params,
        'p_order_items': [
          {
            'menu_item_id': item.id,
            'menu_item_name_snapshot': item.name.of('en'),
            'quantity': 1,
            'unit_price_minor_snapshot': item.basePriceMinor - 100, // forged
            'line_total_minor': item.basePriceMinor - 100,
            'modifiers': [
              {
                'modifier_option_id': option.id,
                'option_name_snapshot': option.name.of('en'),
                'price_minor_snapshot': option.priceDeltaMinor,
                'quantity': 1,
                if (option.kitchenMeat != null)
                  'meat_snapshot': option.kitchenMeat,
              },
            ],
          },
        ],
        'p_client_subtotal_minor':
            item.basePriceMinor - 100 + option.priceDeltaMinor,
        'p_client_grand_total_minor':
            item.basePriceMinor - 100 + option.priceDeltaMinor,
        'p_client_tax_total_minor': 0,
      },
    );
    // Fix the frozen identity keys to the new ones.
    forged.params['p_order_id'] = forged.orderId;
    forged.params['p_local_operation_id'] = forged.localOperationId;
    final r = await submitter.submit(forged);
    expect(r, isA<KioskSubmitRejected>(), reason: '$r');
    expect((r as KioskSubmitRejected).code, 'menu_price_changed');
  }, skip: _skip);

  test('F. a dead/foreign option id is a stable modifier refusal', () async {
    final item = menu.itemById(_burger);
    final base = attemptFor(service: KioskServiceType.takeaway);
    final bad = KioskSubmitAttempt(
      orderId: generateKioskUuidV4(),
      localOperationId: 'kiosk-${generateKioskUuidV4()}',
      params: {
        ...base.params,
        'p_order_id': null, // set below
        'p_order_items': [
          {
            'menu_item_id': item.id,
            'menu_item_name_snapshot': item.name.of('en'),
            'quantity': 1,
            'unit_price_minor_snapshot': item.basePriceMinor,
            'line_total_minor': item.basePriceMinor,
            'modifiers': [
              {
                'modifier_option_id': generateKioskUuidV4(), // nonexistent
                'option_name_snapshot': 'Ghost',
                'price_minor_snapshot': 0,
                'quantity': 1,
              },
            ],
          },
        ],
        'p_client_subtotal_minor': item.basePriceMinor,
        'p_client_grand_total_minor': item.basePriceMinor,
        'p_client_tax_total_minor': 0,
      },
    );
    bad.params['p_order_id'] = bad.orderId;
    bad.params['p_local_operation_id'] = bad.localOperationId;
    final r = await submitter.submit(bad);
    expect(r, isA<KioskSubmitRejected>(), reason: '$r');
    expect(
      (r as KioskSubmitRejected).code,
      anyOf('modifier_option_not_in_scope', 'modifier_selection_invalid'),
    );
  }, skip: _skip);

  test('H. a dead credential is an INVALID SESSION, never an order', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final deadStore = SharedPreferencesDeviceSessionSecretStore(
      prefs,
      keyPrefix: kKioskDeviceSessionPrefix,
    );
    await deadStore.write(
      const DeviceSessionCredential(
        deviceId: _submitDeviceId,
        sessionToken: 'definitely-dead-token',
      ),
    );
    final transport = await SupabaseAuthBootstrap(
      config: SupabaseBootstrapConfig.fromValues(url: _url, anonKey: _anon),
    ).createAnonymousDeviceTransport();
    final deadSubmitter = KioskOrderSubmitter(
      transport: transport,
      secretStore: deadStore,
    );
    final r = await deadSubmitter.submit(
      attemptFor(service: KioskServiceType.takeaway),
    );
    expect(r, isA<KioskSubmitInvalidSession>(), reason: '$r');
  }, skip: _skip);
}
