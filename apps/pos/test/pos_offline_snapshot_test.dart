// POS-OFFLINE-OPERATIONS-002 — the durable OPERATIONAL SNAPSHOT and the
// offline menu fallback, at the REAL seams (the real store over mocked prefs,
// the real posMenuProvider fetch path over a scripted transport, the real
// menu screen).
//
// Covers spec tests:
//   1  snapshot round-trip preserves every field the POS renders/prices from
//   2  save is an ATOMIC full replace of one scope's single envelope
//   3  a refused write throws PosPersistenceException and keeps the old
//      snapshot (build+serialize first, verify setString)
//   4  an unreadable/corrupt/unknown-version envelope reads as the typed
//      unreadable result, is treated as absent, and is NEVER auto-deleted
//   7  a payload naming another scope reads as ABSENT (embedded-scope check),
//      and a cross-scope save is refused outright
//   8  first online launch persists the snapshot; a FRESH process (new
//      container, same prefs) with a dead transport cold-boots onto the
//      cached menu — and renders it with the offline banner
//   9  a dead transport with NO snapshot is the honest SETUP-REQUIRED state
//      (localized explanation + retry), never a silent empty menu
//  10  the resume seam's single posMenuProvider invalidation is SAFE offline:
//      the re-fetch failure serves the cache instead of the error screen
//  34  ONLINE REGRESSION: a successful fetch still parses/renders exactly as
//      before AND refreshes the stored envelope (phase stays online)
//
// Synthetic values only. No network, no printer, no orders, no prints.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show BranchTax;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show
        SyncRpcTransport,
        SyncSession,
        SyncTransportErrorKind,
        SyncTransportException;
import 'package:restoflow_domain/restoflow_domain.dart' show KitchenMeat;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart'
    show DemoCategory, DemoMenuItem;
import 'package:restoflow_pos/src/data/operational_snapshot_store.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart'
    show DemoOutboxStore;
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosPersistenceException, PosSyncScope;
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart'
    show outboxRepositoryProvider;
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_offline_state.dart';
import 'package:restoflow_pos/src/state/pos_session.dart'
    show posAuthTransportProvider, posSyncSessionProvider;
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart'
    show posSyncScopeProvider;
import 'package:shared_preferences/shared_preferences.dart';

const _scope = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  deviceId: 'dev-1',
);
const _otherScope = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-2',
  deviceId: 'dev-1',
);
const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

final _t1 = DateTime.utc(2026, 8, 6, 9);
final _t2 = DateTime.utc(2026, 8, 6, 11);

/// A transport whose `pos_menu` answer is scripted per test; every OTHER
/// function (capability probe, shift bootstrap, …) is offline throughout —
/// none of them may ever be load-bearing for the menu. `failAll` simulates
/// losing the network AFTER a successful launch.
final class _ScriptedTransport implements SyncRpcTransport {
  _ScriptedTransport({this.menuEnvelope});

  Map<String, dynamic> Function()? menuEnvelope;
  bool failAll = false;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    final build = menuEnvelope;
    if (function == 'pos_menu' && build != null && !failAll) {
      return build();
    }
    throw const SyncTransportException(SyncTransportErrorKind.transient);
  }
}

/// The REAL `pos_menu` wire shape (v2 envelope: categories + items +
/// modifiers + modifier_options + currency): 2 categories, 3 items — one with
/// a modifier group carrying free/paid option deltas + kitchen meat, one
/// sold-out, one plain — exactly the variants the offline menu must preserve.
Map<String, dynamic> _menuEnvelopeV1() => <String, dynamic>{
  'ok': true,
  'currency_code': 'ILS',
  'categories': <dynamic>[
    <String, dynamic>{
      'id': 'cat-burgers',
      'name': 'Burgers',
      'display_order': 1,
    },
    <String, dynamic>{'id': 'cat-drinks', 'name': 'Drinks', 'display_order': 2},
  ],
  'items': <dynamic>[
    <String, dynamic>{
      'id': 'item-burger',
      'name': 'Burger',
      'base_price_minor': 4200,
      'menu_category_id': 'cat-burgers',
      'display_order': 1,
      'item_type': 'food',
      'tags': <dynamic>['popular'],
      'prep_minutes': 12,
      'kitchen_note': 'Toast the bun.',
      'description': 'Flame-grilled.',
      'attributes': <String, dynamic>{
        'prep_components': <dynamic>[
          <String, dynamic>{'name': 'Patty', 'quantity': 1, 'unit': 'pcs'},
        ],
      },
      'availability': 'available',
    },
    <String, dynamic>{
      'id': 'item-salad',
      'name': 'Salad',
      'base_price_minor': 2400,
      'menu_category_id': 'cat-burgers',
      'display_order': 2,
      'availability': 'unavailable',
      'availability_reason': 'sold_out',
    },
    <String, dynamic>{
      'id': 'item-cola',
      'name': 'Cola',
      'base_price_minor': 900,
      'menu_category_id': 'cat-drinks',
      'display_order': 1,
    },
  ],
  'modifiers': <dynamic>[
    <String, dynamic>{
      'id': 'grp-extras',
      'menu_item_id': 'item-burger',
      'name': 'Extras',
      'selection_type': 'multi',
      'min_select': 0,
      'max_select': 2,
      'is_required': false,
      'allow_quantity': true,
      'max_quantity': 3,
    },
  ],
  'modifier_options': <dynamic>[
    <String, dynamic>{
      'id': 'opt-cheese',
      'modifier_id': 'grp-extras',
      'name': 'Cheese',
      'price_delta_minor': 300,
      'kitchen_meat': <String, dynamic>{'quantity': 1, 'unit': 'patty'},
    },
    <String, dynamic>{
      'id': 'opt-onion',
      'modifier_id': 'grp-extras',
      'name': 'Onion',
      'price_delta_minor': 0,
    },
  ],
};

/// The SAME shop after a Dashboard edit (rename + reprice) — the marker the
/// online-regression test uses to prove the stored envelope was REFRESHED.
Map<String, dynamic> _menuEnvelopeV2() {
  final envelope = _menuEnvelopeV1();
  final items = envelope['items'] as List<dynamic>;
  (items[0] as Map<String, dynamic>)
    ..['name'] = 'Burger Deluxe'
    ..['base_price_minor'] = 4600;
  return envelope;
}

/// A fully-populated menu for the STORE-level tests, built from the real
/// model constructors (categories carry the shared palette presentation the
/// decoder re-derives by position).
PosMenuData _richMenu({int burgerPriceMinor = 4200}) {
  final (icon0, color0) = kPosCategoryPalette[0];
  final (icon1, color1) = kPosCategoryPalette[1];
  return PosMenuData(
    currencyCode: 'ILS',
    categories: <DemoCategory>[
      DemoCategory(
        id: 'cat-burgers',
        name: 'Burgers',
        icon: icon0,
        color: color0,
      ),
      DemoCategory(
        id: 'cat-drinks',
        name: 'Drinks',
        icon: icon1,
        color: color1,
      ),
    ],
    items: <DemoMenuItem>[
      DemoMenuItem(
        id: 'item-burger',
        name: 'Burger',
        priceMinor: burgerPriceMinor,
        categoryId: 'cat-burgers',
        categoryName: 'Burgers',
        categoryDisplayOrder: 1,
        itemDisplayOrder: 1,
        imagePath: 'menu/burger.jpg',
        imageUrl: 'https://cdn.example/burger-signed.jpg',
        itemType: 'food',
        tags: const <String>['popular'],
        prepMinutes: 12,
        kitchenNote: 'Toast the bun.',
        description: 'Flame-grilled.',
        attributes: const <String, dynamic>{
          'prep_components': <dynamic>[
            <String, dynamic>{'name': 'Patty', 'quantity': 1, 'unit': 'pcs'},
          ],
        },
      ),
      const DemoMenuItem(
        id: 'item-salad',
        name: 'Salad',
        priceMinor: 2400,
        categoryId: 'cat-burgers',
        categoryName: 'Burgers',
        categoryDisplayOrder: 1,
        itemDisplayOrder: 2,
        availability: 'unavailable',
        availabilityReason: 'sold_out',
      ),
      const DemoMenuItem(
        id: 'item-cola',
        name: 'Cola',
        priceMinor: 900,
        categoryId: 'cat-drinks',
        categoryName: 'Drinks',
        categoryDisplayOrder: 2,
        itemDisplayOrder: 1,
      ),
    ],
    modifierGroups: const <PosModifierGroup>[
      PosModifierGroup(
        id: 'grp-extras',
        menuItemId: 'item-burger',
        name: 'Extras',
        maxSelect: 2,
        allowQuantity: true,
        maxQuantity: 3,
        options: <PosModifierOption>[
          PosModifierOption(
            id: 'opt-cheese',
            name: 'Cheese',
            priceDeltaMinor: 300,
            kitchenMeat: KitchenMeat(quantity: 1, unit: 'patty'),
          ),
          PosModifierOption(id: 'opt-onion', name: 'Onion', priceDeltaMinor: 0),
        ],
      ),
    ],
  );
}

PosOperationalSnapshot _snapshot({
  PosSyncScope scope = _scope,
  DateTime? fetchedAt,
  int burgerPriceMinor = 4200,
}) => PosOperationalSnapshot(
  organizationId: scope.organizationId,
  restaurantId: scope.restaurantId,
  branchId: scope.branchId,
  deviceId: scope.deviceId,
  menu: _richMenu(burgerPriceMinor: burgerPriceMinor),
  fetchedAt: fetchedAt ?? _t1,
  restaurantName: 'Shawarma HaCarmel',
  branchName: 'Downtown',
  stationName: 'Till 1',
  employeeProfileId: 'emp-1',
  employeeDisplayName: 'Amal',
  capabilities: const <String, Object?>{
    'apply_discount': true,
    'apply_full_comp': false,
    'manage_menu_availability': true,
    'manage_table_operations': false,
    'role': 'cashier',
  },
  tax: const BranchTax(enabled: true, rateBp: 1700),
  kitchenMode: PosSnapshotKitchenMode(
    mode: 'printer_only',
    revision: 4,
    verifiedAt: _t1,
  ),
  openShift: PosSnapshotShiftRef(id: 'shift-1', openedAt: _t1),
  printerPurposeMeta: const <Object?>[
    <String, Object?>{
      'id': 'printer-1',
      'role': 'receipt',
      'supported_purposes': <String>['customer_receipt'],
      'is_enabled': true,
    },
  ],
);

/// A SharedPreferences double whose `setString` can report FALSE without
/// throwing — a full disk, a browser refusing localStorage (the same double
/// the parked-carts suite uses).
class _FailingPrefs implements SharedPreferences {
  _FailingPrefs(this._inner);
  final SharedPreferences _inner;
  bool failWrites = false;

  @override
  Future<bool> setString(String key, String value) async {
    if (failWrites) return false;
    return _inner.setString(key, value);
  }

  @override
  String? getString(String key) => _inner.getString(key);

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used by the operational snapshot store');
}

/// A few event-loop turns: enough for the deferred offline-state microtask
/// and the fire-and-forget snapshot write over mocked prefs to land.
Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ProviderContainer _realModeContainer(SyncRpcTransport transport) {
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport),
      posSyncSessionProvider.overrideWithValue(_session),
      posSyncScopeProvider.overrideWithValue(_scope),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Some real-mode compositions construct secure stores; a null-returning
    // handler makes every secure read an honest MISS (the recovery-002 idiom).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  });

  group('1. snapshot round-trip', () {
    test(
      'every field the POS renders/prices from survives save+load',
      () async {
        final store = SharedPrefsOperationalSnapshotStore();
        await store.save(_scope, _snapshot());

        final result = await store.load(_scope);
        expect(result, isA<PosOperationalSnapshotLoaded>());
        final restored = (result as PosOperationalSnapshotLoaded).snapshot;

        // Scope + context captures.
        expect(restored.organizationId, 'org-1');
        expect(restored.restaurantId, 'rest-1');
        expect(restored.branchId, 'branch-1');
        expect(restored.deviceId, 'dev-1');
        expect(restored.restaurantName, 'Shawarma HaCarmel');
        expect(restored.branchName, 'Downtown');
        expect(restored.stationName, 'Till 1');
        expect(restored.employeeProfileId, 'emp-1');
        expect(restored.employeeDisplayName, 'Amal');
        expect(restored.capabilities?['apply_discount'], isTrue);
        expect(restored.capabilities?['apply_full_comp'], isFalse);
        expect(restored.capabilities?['role'], 'cashier');
        expect(restored.tax, const BranchTax(enabled: true, rateBp: 1700));
        expect(restored.kitchenMode?.mode, 'printer_only');
        expect(restored.kitchenMode?.revision, 4);
        expect(restored.kitchenMode?.verifiedAt, _t1);
        expect(restored.openShift?.id, 'shift-1');
        expect(restored.openShift?.openedAt, _t1);
        expect(restored.printerPurposeMeta, hasLength(1));
        expect(restored.fetchedAt, _t1);

        // The menu: currency, categories (ids/names + re-derived presentation),
        // items with prices/availability/attributes, groups with deltas + meat.
        final menu = restored.menu;
        expect(menu.currencyCode, 'ILS');
        expect(menu.categories.map((c) => c.id), ['cat-burgers', 'cat-drinks']);
        expect(menu.categories.first.name, 'Burgers');
        expect(menu.categories.first.icon, kPosCategoryPalette[0].$1);
        expect(menu.categories.first.color, kPosCategoryPalette[0].$2);
        final burger = menu.items.firstWhere((i) => i.id == 'item-burger');
        expect(burger.name, 'Burger');
        expect(burger.priceMinor, 4200);
        expect(burger.categoryId, 'cat-burgers');
        expect(burger.categoryName, 'Burgers');
        expect(burger.categoryDisplayOrder, 1);
        expect(burger.itemDisplayOrder, 1);
        expect(burger.imagePath, 'menu/burger.jpg');
        expect(burger.imageUrl, 'https://cdn.example/burger-signed.jpg');
        expect(burger.itemType, 'food');
        expect(burger.tags, ['popular']);
        expect(burger.prepMinutes, 12);
        expect(burger.kitchenNote, 'Toast the bun.');
        expect(burger.description, 'Flame-grilled.');
        expect(burger.prepComponents, hasLength(1));
        expect(burger.prepComponents.first.name, 'Patty');
        final salad = menu.items.firstWhere((i) => i.id == 'item-salad');
        expect(salad.availability, 'unavailable');
        expect(salad.availabilityReason, 'sold_out');
        final groups = menu.groupsForItem('item-burger');
        expect(groups, hasLength(1));
        final extras = groups.single;
        expect(extras.name, 'Extras');
        expect(extras.maxSelect, 2);
        expect(extras.allowQuantity, isTrue);
        expect(extras.maxQuantity, 3);
        expect(extras.options.map((o) => o.id), ['opt-cheese', 'opt-onion']);
        expect(extras.options.first.priceDeltaMinor, 300);
        expect(
          extras.options.first.kitchenMeat,
          const KitchenMeat(quantity: 1, unit: 'patty'),
        );
        expect(extras.options.last.priceDeltaMinor, 0);
      },
    );
  });

  group('2. atomic replace', () {
    test(
      'a second save fully replaces the ONE envelope of that scope',
      () async {
        final store = SharedPrefsOperationalSnapshotStore();
        await store.save(_scope, _snapshot(fetchedAt: _t1));
        await store.save(
          _scope,
          _snapshot(fetchedAt: _t2, burgerPriceMinor: 4600),
        );

        final result = await store.load(_scope);
        final restored = (result as PosOperationalSnapshotLoaded).snapshot;
        expect(restored.fetchedAt, _t2);
        expect(
          restored.menu.items
              .firstWhere((i) => i.id == 'item-burger')
              .priceMinor,
          4600,
        );
        // Exactly one stored envelope for the scope — replace, never append.
        final prefs = await SharedPreferences.getInstance();
        final snapshotKeys = prefs
            .getKeys()
            .where((k) => k.startsWith('restoflow.pos.operational_snapshot.'))
            .toList();
        expect(snapshotKeys, [operationalSnapshotStorageKey(_scope)]);
      },
    );
  });

  group('3. refused write', () {
    test('setString==false throws PosPersistenceException and the previous '
        'snapshot survives untouched', () async {
      final prefs = _FailingPrefs(await SharedPreferences.getInstance());
      final store = SharedPrefsOperationalSnapshotStore(
        prefs: () async => prefs,
      );
      await store.save(_scope, _snapshot(fetchedAt: _t1));

      prefs.failWrites = true;
      await expectLater(
        store.save(_scope, _snapshot(fetchedAt: _t2, burgerPriceMinor: 9900)),
        throwsA(isA<PosPersistenceException>()),
      );

      prefs.failWrites = false;
      final result = await store.load(_scope);
      final restored = (result as PosOperationalSnapshotLoaded).snapshot;
      expect(restored.fetchedAt, _t1, reason: 'the old snapshot must stand');
      expect(
        restored.menu.items.firstWhere((i) => i.id == 'item-burger').priceMinor,
        4200,
      );
    });
  });

  group('4. unreadable envelope', () {
    test(
      'corrupt JSON reads as unreadable and the bytes are NEVER deleted',
      () async {
        final key = operationalSnapshotStorageKey(_scope);
        SharedPreferences.setMockInitialValues(<String, Object>{
          key: '{not json at all',
        });
        final store = SharedPrefsOperationalSnapshotStore();
        expect(
          await store.load(_scope),
          isA<PosOperationalSnapshotUnreadable>(),
        );
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString(key),
          '{not json at all',
          reason: 'a record we cannot read is not a record we may destroy',
        );
      },
    );

    test('an unknown schema version is refused, not guessed at', () async {
      final key = operationalSnapshotStorageKey(_scope);
      final alien = jsonEncode(<String, Object?>{
        'version': 99,
        'snapshot': <String, Object?>{},
      });
      SharedPreferences.setMockInitialValues(<String, Object>{key: alien});
      final store = SharedPrefsOperationalSnapshotStore();
      expect(await store.load(_scope), isA<PosOperationalSnapshotUnreadable>());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(key), alien);
    });

    test('a menu record missing its integer price fails the WHOLE envelope '
        'closed (no half-menu is ever served)', () async {
      final store = SharedPrefsOperationalSnapshotStore();
      await store.save(_scope, _snapshot());
      final key = operationalSnapshotStorageKey(_scope);
      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
      final menu =
          (decoded['snapshot'] as Map<String, dynamic>)['menu']
              as Map<String, dynamic>;
      ((menu['items'] as List<dynamic>).first as Map<String, dynamic>).remove(
        'price_minor',
      );
      await prefs.setString(key, jsonEncode(decoded));

      expect(await store.load(_scope), isA<PosOperationalSnapshotUnreadable>());
    });
  });

  group('7. scope isolation', () {
    test(
      'a payload naming another scope reads as ABSENT and is preserved',
      () async {
        final store = SharedPrefsOperationalSnapshotStore();
        await store.save(_scope, _snapshot());
        // Simulate a copied/tampered envelope: scope A's bytes under B's key.
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(operationalSnapshotStorageKey(_scope))!;
        await prefs.setString(operationalSnapshotStorageKey(_otherScope), raw);

        expect(
          await store.load(_otherScope),
          isA<PosOperationalSnapshotAbsent>(),
          reason: 'branch B must never sell from branch A\'s menu',
        );
        expect(
          prefs.getString(operationalSnapshotStorageKey(_otherScope)),
          raw,
          reason: 'absent-by-mismatch must not destroy the evidence',
        );
      },
    );

    test('a save whose payload names another scope is refused outright', () {
      final store = SharedPrefsOperationalSnapshotStore();
      expect(() => store.save(_otherScope, _snapshot()), throwsArgumentError);
    });
  });

  group('8. cold-offline boot from the persisted snapshot', () {
    test('first online launch persists; a fresh container over the SAME prefs '
        'with a dead transport serves the cached menu', () async {
      // ---- first online launch --------------------------------------------
      final online = _ScriptedTransport(menuEnvelope: _menuEnvelopeV1);
      final c1 = _realModeContainer(online);
      final fetched = await c1.read(posMenuProvider.future);
      expect(fetched.items, hasLength(3));
      await _settle();
      expect(c1.read(posOfflineModeProvider).phase, PosOfflinePhase.online);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(operationalSnapshotStorageKey(_scope)),
        isNotNull,
        reason: 'a successful fetch must persist the operational snapshot',
      );

      // ---- cold offline boot: NEW container, SAME prefs, dead transport ---
      final c2 = _realModeContainer(_ScriptedTransport());
      final cached = await c2.read(posMenuProvider.future);
      expect(cached.currencyCode, 'ILS');
      expect(cached.items.map((i) => i.id), fetched.items.map((i) => i.id));
      final burger = cached.items.firstWhere((i) => i.id == 'item-burger');
      expect(burger.priceMinor, 4200);
      expect(burger.description, 'Flame-grilled.');
      final salad = cached.items.firstWhere((i) => i.id == 'item-salad');
      expect(salad.availability, 'unavailable');
      expect(salad.availabilityReason, 'sold_out');
      final extras = cached.groupsForItem('item-burger').single;
      expect(extras.options.map((o) => o.priceDeltaMinor), [300, 0]);
      expect(
        extras.options.first.kitchenMeat,
        const KitchenMeat(quantity: 1, unit: 'patty'),
      );

      await _settle();
      final offline = c2.read(posOfflineModeProvider);
      expect(offline.phase, PosOfflinePhase.offlineCached);
      expect(offline.menuFromCache, isTrue);
      expect(offline.snapshotFetchedAt, isNotNull);
    });

    testWidgets('the cached menu RENDERS with the offline banner (Arabic)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
      await SharedPrefsOperationalSnapshotStore().save(_scope, _snapshot());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: false),
            ),
            posAuthTransportProvider.overrideWithValue(_ScriptedTransport()),
            posSyncSessionProvider.overrideWithValue(_session),
            posSyncScopeProvider.overrideWithValue(_scope),
            outboxRepositoryProvider.overrideWithValue(
              DemoOutboxStore(delay: (_) async {}),
            ),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: PosMenuScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The ordinary grid (no full-screen error/spinner) + the slim banner.
      expect(find.text('Burger'), findsWidgets);
      expect(find.byKey(const Key('pos-offline-banner')), findsOneWidget);
      expect(find.text(l10n.posOfflineModeBanner), findsOneWidget);
      expect(find.text(l10n.posMenuLoadError), findsNothing);
    });
  });

  group('9. setup required (no snapshot, no network)', () {
    test('the fetch failure is PosMenuUnavailable and the phase records '
        'setupRequired — never a silent empty menu', () async {
      final c = _realModeContainer(_ScriptedTransport());
      await expectLater(
        c.read(posMenuProvider.future),
        throwsA(isA<PosMenuUnavailable>()),
      );
      await _settle();
      expect(
        c.read(posOfflineModeProvider).phase,
        PosOfflinePhase.setupRequired,
      );
    });

    testWidgets('the localized setup-required explanation renders with retry', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: false),
            ),
            posAuthTransportProvider.overrideWithValue(_ScriptedTransport()),
            posSyncSessionProvider.overrideWithValue(_session),
            posSyncScopeProvider.overrideWithValue(_scope),
            outboxRepositoryProvider.overrideWithValue(
              DemoOutboxStore(delay: (_) async {}),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: PosMenuScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.posOfflineSetupRequiredTitle), findsOneWidget);
      expect(find.text(l10n.posOfflineSetupRequiredBody), findsOneWidget);
      expect(find.byKey(const Key('pos-offline-banner')), findsNothing);

      // Retry re-runs the fetch (still offline) and lands back on the SAME
      // honest state — a live button, never a dead end.
      await tester.tap(find.text(l10n.authTryAgain));
      await tester.pumpAndSettle();
      expect(find.text(l10n.posOfflineSetupRequiredTitle), findsOneWidget);
    });
  });

  group('10. resume while offline', () {
    test('the resume seam\'s single invalidation lands on the cached menu, '
        'not the error screen', () async {
      final transport = _ScriptedTransport(menuEnvelope: _menuEnvelopeV1);
      final c = _realModeContainer(transport);
      await c.read(posMenuProvider.future);
      await _settle();
      expect(c.read(posOfflineModeProvider).phase, PosOfflinePhase.online);

      // The device sleeps; the network dies; the app resumes. The lifecycle
      // performs exactly ONE ref.invalidate(posMenuProvider) (C4) — replayed
      // here at the provider seam.
      transport.failAll = true;
      c.invalidate(posMenuProvider);
      final cached = await c.read(posMenuProvider.future);
      expect(cached.items, hasLength(3));
      expect(
        cached
            .groupsForItem('item-burger')
            .single
            .options
            .first
            .priceDeltaMinor,
        300,
      );
      await _settle();
      final offline = c.read(posOfflineModeProvider);
      expect(offline.phase, PosOfflinePhase.offlineCached);
      expect(offline.menuFromCache, isTrue);
    });
  });

  group('34. online regression', () {
    test('a successful fetch still parses exactly as before AND refreshes the '
        'stored envelope', () async {
      var version = 1;
      final transport = _ScriptedTransport(
        menuEnvelope: () =>
            version == 1 ? _menuEnvelopeV1() : _menuEnvelopeV2(),
      );
      final c = _realModeContainer(transport);

      final menu1 = await c.read(posMenuProvider.future);
      expect(menu1.items, hasLength(3));
      expect(
        menu1.items.firstWhere((i) => i.id == 'item-burger').priceMinor,
        4200,
      );
      expect(menu1.groupsForItem('item-burger'), hasLength(1));
      await _settle();
      final prefs = await SharedPreferences.getInstance();
      final key = operationalSnapshotStorageKey(_scope);
      final raw1 = prefs.getString(key);
      expect(raw1, isNotNull);

      // The Dashboard edits the product; the POS refreshes online.
      version = 2;
      c.invalidate(posMenuProvider);
      final menu2 = await c.read(posMenuProvider.future);
      final deluxe = menu2.items.firstWhere((i) => i.id == 'item-burger');
      expect(deluxe.name, 'Burger Deluxe');
      expect(deluxe.priceMinor, 4600);
      await _settle();

      final raw2 = prefs.getString(key);
      expect(raw2, isNot(raw1), reason: 'the envelope must be REFRESHED');
      expect(raw2, contains('Burger Deluxe'));
      expect(c.read(posOfflineModeProvider).phase, PosOfflinePhase.online);
      expect(c.read(posOfflineModeProvider).menuFromCache, isFalse);
    });
  });
}
