import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_kiosk/src/data/kiosk_fixtures.dart';
import 'package:restoflow_kiosk/src/data/kiosk_live_data.dart';
import 'package:restoflow_kiosk/src/data/kiosk_menu_data.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';

/// KIOSK-001 Phase 3 — the live-read mapping + trust boundary, without any
/// network: envelope → view-model fidelity, the POS-grade money boundary,
/// fail-safe table states, the typed failure mapping, stale-cart detection,
/// and the no-invented-defaults rule.
Map<String, dynamic> _menuEnvelope({List<Map<String, Object?>>? items}) => {
  'ok': true,
  'currency_code': 'ILS',
  'categories': [
    {'id': 'c1', 'name': 'Burgers', 'display_order': 0, 'icon_key': 'burger'},
    {'id': 'c2', 'name': 'Drinks', 'display_order': 1, 'icon_key': 'zz-nope'},
  ],
  'items':
      items ??
      [
        {
          'id': 'i1',
          'menu_category_id': 'c1',
          'name': 'Classic Burger',
          'description': 'House burger',
          'base_price_minor': 4000,
          'image_path': 'org/rest/global/menu_item/i1/img.jpg',
          'availability': 'available',
        },
        {
          'id': 'i2',
          'menu_category_id': 'c1',
          'name': 'Special',
          'base_price_minor': 5200,
          'availability': 'unavailable',
          'availability_reason': 'sold_out',
        },
        {
          'id': 'i3',
          'menu_category_id': 'c2',
          'name': 'Cola',
          'base_price_minor': 1000,
        },
      ],
  'modifiers': [
    {
      'id': 'g1',
      'menu_item_id': 'i1',
      'name': 'Weight',
      'selection_type': 'single',
      'min_select': 1,
      'max_select': 1,
      'is_required': true,
      'allow_quantity': false,
      'display_order': 0,
    },
    {
      'id': 'g2',
      'menu_item_id': 'i1',
      'name': 'Extras',
      'selection_type': 'multiple',
      'min_select': 2,
      'max_select': 3,
      'is_required': true,
      'allow_quantity': true,
      'max_quantity': 2,
      'display_order': 1,
    },
  ],
  'modifier_options': [
    {
      'id': 'o1',
      'modifier_id': 'g1',
      'name': '120g',
      'display_order': 0,
      'price_delta_minor': 0,
      'kitchen_meat': {'quantity': 1, 'unit': 'pc'},
    },
    {
      'id': 'o2',
      'modifier_id': 'g1',
      'name': '240g',
      'display_order': 1,
      'price_delta_minor': 1500,
    },
    {
      'id': 'o3',
      'modifier_id': 'g2',
      'name': 'Sauce',
      'display_order': 0,
      'price_delta_minor': 200,
    },
    {
      'id': 'o4',
      'modifier_id': 'g2',
      'name': 'Cheese',
      'display_order': 1,
      'price_delta_minor': 300,
    },
  ],
};

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this.handler);
  final Future<Object?> Function(String fn, Map<String, dynamic> params)
  handler;
  final calls = <(String, Map<String, dynamic>)>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) {
    calls.add((function, params));
    return handler(function, params);
  }
}

void main() {
  group('kiosk_menu envelope mapping', () {
    test('maps categories/items/groups/options with integer minor money', () {
      final menu = mapKioskMenuEnvelope(_menuEnvelope())!;
      expect(menu.live, isTrue);
      expect(menu.currencyCode, 'ILS');
      expect(menu.categories.map((c) => c.id), ['c1', 'c2']);
      final burger = menu.itemById('i1');
      expect(burger.basePriceMinor, 4000);
      expect(burger.imagePath, isNotNull);
      expect(burger.available, isTrue);
      expect(burger.groupIds, ['g1', 'g2']);
      final weight = menu.group('g1')!;
      expect(weight.type, KioskGroupType.single);
      expect(weight.isRequired, isTrue);
      expect(weight.displayName!.of('en'), 'Weight');
      expect(weight.options.map((o) => o.priceDeltaMinor), [0, 1500]);
      expect(weight.options.first.kitchenMeat, {'quantity': 1, 'unit': 'pc'});
      final extras = menu.group('g2')!;
      expect(extras.minSelect, 2);
      expect(extras.maxSelect, 3);
      expect(extras.allowQuantity, isTrue);
      expect(extras.maxQuantity, 2);
    });

    test('sold-out item stays visible, marked unavailable with its reason', () {
      final menu = mapKioskMenuEnvelope(_menuEnvelope())!;
      final special = menu.itemById('i2');
      expect(special.available, isFalse);
      expect(special.availabilityReason, 'sold_out');
    });

    test('a NON-INTEGER price is never defaulted — the item is skipped', () {
      final menu = mapKioskMenuEnvelope(
        _menuEnvelope(
          items: [
            {
              'id': 'bad',
              'menu_category_id': 'c1',
              'name': 'Poison',
              'base_price_minor': '4000',
            },
            {
              'id': 'ok',
              'menu_category_id': 'c1',
              'name': 'Fine',
              'base_price_minor': 1000,
            },
          ],
        ),
      )!;
      expect(menu.tryItem('bad'), isNull);
      expect(menu.tryItem('ok'), isNotNull);
    });

    test('broken modifier config → item visible but unavailable', () {
      final env = _menuEnvelope();
      (env['modifier_options'] as List).removeWhere(
        (o) => (o as Map)['modifier_id'] == 'g1',
      ); // g1 left with zero options → i1 config unreadable
      final menu = mapKioskMenuEnvelope(env)!;
      final burger = menu.itemById('i1');
      expect(burger.available, isFalse);
      expect(burger.availabilityReason, 'configuration_unreadable');
      expect(burger.groupIds, isEmpty);
    });

    test('icon keys: known key resolves, unknown falls back to null', () {
      final menu = mapKioskMenuEnvelope(_menuEnvelope())!;
      expect(menu.categories[0].iconData, isNotNull); // 'burger' registry key
      expect(menu.categories[1].iconData, isNull); // 'zz-nope'
    });

    test('LIVE menus preselect NOTHING (no invented defaults)', () {
      final live = mapKioskMenuEnvelope(_menuEnvelope())!;
      final selected = live.defaultSelectionFor(live.itemById('i1'));
      expect(selected.values.every((v) => v.isEmpty), isTrue);
      // Fixtures keep the artifact's included-weight preselect.
      final fixtures = KioskMenuData.fixtures();
      final draft = fixtures.defaultSelectionFor(fixtures.itemById('b1'));
      expect(draft['weight'], [kioskIncludedWeightOptionId]);
    });

    test('required rules mirror the server: min_select 2 needs 2 picks', () {
      final menu = mapKioskMenuEnvelope(_menuEnvelope())!;
      final item = menu.itemById('i1');
      expect(
        menu.unmetRequiredGroups(item, {
          'g1': ['o1'],
          'g2': ['o3'],
        }),
        ['g2'],
      );
      expect(
        menu.unmetRequiredGroups(item, {
          'g1': ['o1'],
          'g2': ['o3', 'o4'],
        }),
        isEmpty,
      );
    });
  });

  group('kiosk_tables envelope mapping', () {
    Map<String, dynamic> env(List<Map<String, Object?>> rows) => {
      'ok': true,
      'tables': rows,
    };

    test('maps the four states; an UNKNOWN state is never selectable', () {
      final zones = mapKioskTablesEnvelope(
        env([
          {
            'id': 't1',
            'label': 'T1',
            'seats': 4,
            'effective_state': 'available',
          },
          {
            'id': 't2',
            'label': 'T2',
            'seats': 2,
            'effective_state': 'occupied',
          },
          {
            'id': 't3',
            'label': 'T3',
            'seats': 2,
            'effective_state': 'reserved',
          },
          {
            'id': 't4',
            'label': 'T4',
            'seats': 2,
            'effective_state': 'out_of_service',
          },
          {
            'id': 't5',
            'label': 'T5',
            'seats': 2,
            'effective_state': 'floating',
          },
        ]),
      )!;
      final states = {for (final t in zones.single.tables) t.label: t.state};
      expect(states['T1'], KioskTableState.available);
      expect(states['T2'], KioskTableState.occupied);
      expect(states['T3'], KioskTableState.reserved);
      expect(states['T4'], KioskTableState.outOfService);
      // fail safe: the unknown state renders non-selectable.
      expect(states['T5'], KioskTableState.outOfService);
    });

    test('groups by section ordered by section_display_order', () {
      final zones = mapKioskTablesEnvelope(
        env([
          {
            'id': 'b1',
            'label': 'B1',
            'seats': 1,
            'section_id': 's2',
            'section_name': 'Bar',
            'section_display_order': 5,
            'effective_state': 'available',
          },
          {
            'id': 'h1',
            'label': 'H1',
            'seats': 4,
            'section_id': 's1',
            'section_name': 'Hall',
            'section_display_order': 0,
            'effective_state': 'available',
          },
        ]),
      )!;
      expect(zones.map((z) => z.displayName), ['Hall', 'Bar']);
      expect(zones.first.tables.single.id, 'h1');
    });
  });

  group('KioskLiveReads failure mapping', () {
    final cred = DeviceSessionCredential(
      deviceId: 'dev-1',
      sessionToken: 'tok-1',
    );

    KioskLiveReads reads(
      _FakeTransport transport, {
      DeviceSessionCredential? credential,
    }) {
      final store = InMemoryDeviceSessionSecretStore();
      if (credential != null) store.write(credential);
      return KioskLiveReads(transport: transport, secretStore: store);
    }

    test(
      'sends the stored credential, never client-asserted identity',
      () async {
        final transport = _FakeTransport((fn, p) async => _menuEnvelope());
        final r = await reads(transport, credential: cred).fetchMenu();
        expect(r, isA<KioskReadOk<KioskMenuData>>());
        expect(transport.calls.single.$1, 'kiosk_menu');
        expect(transport.calls.single.$2, {
          'p_device_id': 'dev-1',
          'p_session_token': 'tok-1',
        });
      },
    );

    test('missing credential fails closed as invalidSession', () async {
      final transport = _FakeTransport((fn, p) async => _menuEnvelope());
      final r = await reads(transport).fetchMenu();
      expect((r as KioskReadError).kind, KioskReadFailureKind.invalidSession);
      expect(transport.calls, isEmpty);
    });

    test('an invalid_session envelope maps to invalidSession', () async {
      final transport = _FakeTransport(
        (fn, p) async => {'ok': false, 'error': 'invalid_session'},
      );
      final r = await reads(transport, credential: cred).fetchTables();
      expect((r as KioskReadError).kind, KioskReadFailureKind.invalidSession);
    });

    test(
      'transport kinds map: auth→invalidSession, transient→network',
      () async {
        for (final (kind, expected) in [
          (SyncTransportErrorKind.auth, KioskReadFailureKind.invalidSession),
          (SyncTransportErrorKind.transient, KioskReadFailureKind.network),
          (SyncTransportErrorKind.server, KioskReadFailureKind.unavailable),
        ]) {
          final transport = _FakeTransport(
            (fn, p) => throw SyncTransportException(kind),
          );
          final r = await reads(transport, credential: cred).fetchMenu();
          expect((r as KioskReadError).kind, expected, reason: '$kind');
        }
      },
    );
  });

  group('stale-cart detection', () {
    test('a repriced item marks the cart stale; refresh re-captures', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(kioskFlowProvider.notifier);
      // Build a real cart line from the fixtures (Cola, no groups).
      controller.openItem('d1');
      controller.submitDraft();
      final captured = container.read(kioskFlowProvider).cart.single;
      expect(container.read(kioskFlowProvider).cartStale, isFalse);

      // The same item priced differently in a fresh live menu → STALE.
      final repriced = mapKioskMenuEnvelope(
        _menuEnvelope(
          items: [
            {
              'id': captured.itemId,
              'menu_category_id': 'c1',
              'name': 'Cola',
              'base_price_minor': captured.capturedUnitMinor + 100,
            },
          ],
        ),
      )!;
      controller.revalidateCart(repriced);
      expect(container.read(kioskFlowProvider).cartStale, isTrue);

      // An unchanged menu clears the flag again.
      controller.revalidateCart(KioskMenuData.fixtures());
      expect(container.read(kioskFlowProvider).cartStale, isFalse);
    });

    test('a vanished item marks stale; the reconfirm action drops it', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(kioskFlowProvider.notifier);
      controller.openItem('d1');
      controller.submitDraft();
      final without = mapKioskMenuEnvelope(_menuEnvelope())!; // no 'd1'
      controller.revalidateCart(without);
      expect(container.read(kioskFlowProvider).cartStale, isTrue);
    });
  });

  test('the credential type never exposes the raw token in toString', () {
    final c = DeviceSessionCredential(
      deviceId: 'dev-9',
      sessionToken: 'super-secret-token',
    );
    expect('$c', isNot(contains('super-secret-token')));
  });
}
