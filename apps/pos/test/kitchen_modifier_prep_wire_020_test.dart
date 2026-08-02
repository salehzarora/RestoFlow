@TestOn('vm')
library;

import 'dart:convert' show json;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport;
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenMeat, OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart' show DemoMenuItem;
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/order_snapshot_repository.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart'
    show posSyncClockProvider, orderSnapshotRepositoryProvider;
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart'
    show submitOrderFromCart;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/verified_kitchen_mode_readiness.dart';

/// KITCHEN-MODIFIER-PREP-CLASSIFIER-CODEX-FIX-020 — Codex BLOCKER #1.
///
/// The initial submit sent `m.kitchenMeat` — raw MENU CONFIGURATION — so the
/// authoritative wire operation carried the classifier's id and name but **no
/// `classifier_selected`**. The server and the KDS therefore received an
/// unresolved contribution; only the local direct print looked right.
///
/// These tests read the ACTUAL serialized `order.submit` operation off a fake
/// transport, not a helper's return value.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const ctx = DeviceContext(
    organizationId: 'org-1',
    restaurantId: 'rest-1',
    branchId: 'branch-A',
    deviceId: 'device-1',
    deviceType: 'pos',
    deviceSessionId: 'ds-A',
  );

  const size240 = 'opt-size-240';
  const cheeseId = 'opt-cheese';

  const burger = DemoMenuItem(
    id: 'burger',
    name: 'Burger',
    priceMinor: 4500,
    categoryId: 'meals',
    categoryName: 'Meals',
  );

  /// The 240g size option: 2 Meat pieces per unit, split by Cheese.
  const sizeGroup = PosModifierGroup(
    id: 'grp-size',
    menuItemId: 'burger',
    name: 'Size',
    options: [
      PosModifierOption(
        id: size240,
        name: '240g',
        priceDeltaMinor: 0,
        kitchenMeat: KitchenMeat(
          quantity: 2,
          unit: 'Meat pieces',
          classifierOptionId: cheeseId,
          classifierOptionName: 'Cheese',
        ),
      ),
    ],
  );
  const extrasGroup = PosModifierGroup(
    id: 'grp-extras',
    menuItemId: 'burger',
    name: 'Extras',
    options: [
      PosModifierOption(id: cheeseId, name: 'Cheese', priceDeltaMinor: 300),
    ],
  );

  final menuSource = StateProvider<PosMenuData>(
    (ref) => PosMenuData.withTrustedPrepClassifiers(
      const PosMenuData(
        categories: [],
        items: [burger],
        currencyCode: 'ILS',
        modifierGroups: [sizeGroup, extrasGroup],
      ),
    ),
  );

  SelectedModifier size({int quantity = 1}) =>
      const PosModifierOption(
        id: size240,
        name: '240g',
        priceDeltaMinor: 0,
      ).let(
        (o) => SelectedModifier(
          optionId: o.id,
          groupName: 'Size',
          optionName: o.name,
          priceDeltaMinor: 0,
          quantity: quantity,
          kitchenMeat: const KitchenMeat(
            quantity: 2,
            unit: 'Meat pieces',
            classifierOptionId: cheeseId,
            classifierOptionName: 'Cheese',
          ),
        ),
      );

  SelectedModifier cheese({int quantity = 1}) => SelectedModifier(
    optionId: cheeseId,
    groupName: 'Extras',
    optionName: 'Cheese',
    priceDeltaMinor: 300,
    quantity: quantity,
  );

  /// A transport that records every submitted operation verbatim.
  late _Transport transport;

  ProviderContainer makeContainer(SharedPreferences prefs) => ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport),
      posRealSessionConfigProvider.overrideWithValue(null),
      orderSnapshotRepositoryProvider.overrideWithValue(_EmptySnapshotRepo()),
      posRecentOrdersStoreProvider.overrideWithValue(
        InMemoryRecentOrdersStore(),
      ),
      posSyncClockProvider.overrideWithValue(() => DateTime.utc(2026, 8, 2)),
      posMenuProvider.overrideWith((ref) => ref.watch(menuSource)),
      verifiedKdsReadinessOverride(),
    ],
  );

  Future<void> settle() async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.microtask(() {});
    }
  }

  /// Submits ONE burger line through the REAL production entry point and
  /// returns the `meat_snapshot` the wire actually carried for the size option.
  Future<Map<String, Object?>?> submitAndReadSnapshot(
    WidgetTester tester,
    List<SelectedModifier> modifiers,
  ) async {
    transport = _Transport();
    final prefs = await SharedPreferences.getInstance();
    final c = makeContainer(prefs);
    addTearDown(c.dispose);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    c.read(posDeviceContextProvider.notifier).set(ctx);
    await settle();
    expect(
      await c
          .read(posSessionControllerProvider.notifier)
          .signInWithPin(
            device: ctx,
            deviceId: ctx.deviceId!,
            deviceSessionId: ctx.deviceSessionId!,
            employeeProfileId: 'emp-A',
            pin: '1234',
          ),
      isNull,
    );
    await settle();

    late WidgetRef ref;
    late BuildContext context;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Consumer(
            builder: (ctx2, r, _) {
              ref = r;
              context = ctx2;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      ),
    );
    await tester.pump();

    c
        .read(cartControllerProvider.notifier)
        .addItemWithModifiers(burger, modifiers);
    c
        .read(orderSetupControllerProvider.notifier)
        .setOrderType(OrderType.takeaway);
    await tester.pump();
    await submitOrderFromCart(
      ref: ref,
      context: context,
      cart: c.read(cartControllerProvider),
      setup: c.read(orderSetupControllerProvider),
      cartController: c.read(cartControllerProvider.notifier),
      setupController: c.read(orderSetupControllerProvider.notifier),
      l10n: l10n,
    );
    await tester.pump();
    await settle();

    expect(
      transport.orderSubmits,
      isNotEmpty,
      reason: 'the submit reached the wire',
    );
    final op = transport.orderSubmits.last;
    final item = ((op['payload'] as Map)['order_items'] as List).first as Map;
    final mods = (item['modifiers'] as List).cast<Map<dynamic, dynamic>>();
    final sizeMod = mods.firstWhere((m) => m['modifier_option_id'] == size240);
    final snap = sizeMod['meat_snapshot'];
    return snap == null ? null : (snap as Map).cast<String, Object?>();
  }

  testWidgets('020-1. 240g + Cheese sends quantity 2 and selected=true', (
    tester,
  ) async {
    final snap = await submitAndReadSnapshot(tester, [size(), cheese()]);
    expect(snap, isNotNull);
    expect(snap!['quantity'], 2, reason: 'PER MODIFIER UNIT, not pre-scaled');
    expect(snap['unit'], 'Meat pieces');
    expect(snap['classifier_option_id'], cheeseId);
    expect(snap['classifier_option_name'], 'Cheese');
    expect(
      snap['classifier_selected'],
      isTrue,
      reason: 'the ORDER-TIME answer must be on the wire',
    );
  });

  testWidgets(
    '020-2. 240g without Cheese sends quantity 2 and selected=false',
    (tester) async {
      final snap = await submitAndReadSnapshot(tester, [size()]);
      expect(snap!['quantity'], 2);
      expect(
        snap['classifier_selected'],
        isFalse,
        reason: 'false is an ANSWER — absence is not',
      );
    },
  );

  testWidgets('020-3. Cheese x4 does not change the meat quantity', (
    tester,
  ) async {
    final snap = await submitAndReadSnapshot(tester, [
      size(),
      cheese(quantity: 4),
    ]);
    expect(snap!['quantity'], 2, reason: 'the classifier never multiplies');
    expect(snap['classifier_selected'], isTrue);
  });

  testWidgets('020-4. the size option\'s OWN units stay in its quantity field', (
    tester,
  ) async {
    // An option taken twice keeps its per-unit contribution on the wire; the
    // units live in the adjacent modifier `quantity`, applied downstream once.
    transport = _Transport();
    final snap = await submitAndReadSnapshot(tester, [
      size(quantity: 2),
      cheese(),
    ]);
    expect(snap!['quantity'], 2, reason: 'per-unit, NOT 2x2');
    final op = transport.orderSubmits.last;
    final item = ((op['payload'] as Map)['order_items'] as List).first as Map;
    final mods = (item['modifiers'] as List).cast<Map<dynamic, dynamic>>();
    expect(
      mods.firstWhere((m) => m['modifier_option_id'] == size240)['quantity'],
      2,
      reason: 'the modifier units are represented separately',
    );
  });

  testWidgets('020-5. an unconfigured option sends no snapshot at all', (
    tester,
  ) async {
    // Cheese contributes nothing of its own, so its wire modifier must carry
    // NO meat_snapshot key — byte-identical to a pre-feature payload.
    await submitAndReadSnapshot(tester, [size(), cheese()]);
    final op = transport.orderSubmits.last;
    final item = ((op['payload'] as Map)['order_items'] as List).first as Map;
    final mods = (item['modifiers'] as List).cast<Map<dynamic, dynamic>>();
    final cheeseMod = mods.firstWhere(
      (m) => m['modifier_option_id'] == cheeseId,
    );
    expect(cheeseMod.containsKey('meat_snapshot'), isFalse);
    expect(cheeseMod['quantity'], 1);
  });

  test(
    '020-6. the shared resolver never pre-scales and answers by presence',
    () {
      const config = KitchenMeat(
        quantity: 2,
        unit: 'Meat pieces',
        classifierOptionId: cheeseId,
        classifierOptionName: 'Cheese',
      );
      final withCheese = resolveOrderTimeMeatSnapshot(config, {
        size240,
        cheeseId,
      })!;
      expect(withCheese.quantity, 2);
      expect(withCheese.classifierSelected, isTrue);

      final without = resolveOrderTimeMeatSnapshot(config, {size240})!;
      expect(without.quantity, 2);
      expect(without.classifierSelected, isFalse);

      // Unconfigured / unclassified inputs pass straight through.
      expect(resolveOrderTimeMeatSnapshot(null, {size240}), isNull);
      const plain = KitchenMeat(quantity: 2, unit: 'Meat pieces');
      expect(resolveOrderTimeMeatSnapshot(plain, {size240}), plain);
    },
  );

  test('020-7. selectedOptionIdsOf ignores zero-unit selections', () {
    expect(selectedOptionIdsOf([size(), cheese(quantity: 0)]), {size240});
  });
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// Records every `order.submit` / `order.add_items` operation verbatim.
class _Transport implements SyncRpcTransport {
  int pinSessions = 0;
  final List<Map<String, dynamic>> orderSubmits = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> additions = <Map<String, dynamic>>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'start_pin_session') {
      pinSessions++;
      return 'pin-session-$pinSessions';
    }
    if (function == 'sync_push') {
      final ops = (params['p_operations'] as List)
          .cast<Map<dynamic, dynamic>>();
      final op = ops.first.cast<String, dynamic>();
      final type = op['operation_type'];
      if (type == 'shift.open') {
        return <String, dynamic>{
          'ok': true,
          'results': <dynamic>[
            <String, dynamic>{
              'operation_type': 'shift.open',
              'status': 'applied',
              'ok': true,
            },
          ],
        };
      }
      // Round-trip through JSON so the test inspects exactly what the wire
      // would carry — never a live Dart object.
      final wire = json.decode(json.encode(op)) as Map<String, dynamic>;
      if (type == 'order.submit') orderSubmits.add(wire);
      if (type == 'order.add_items') additions.add(wire);
      return <String, dynamic>{
        'ok': true,
        'results': <dynamic>[
          <String, dynamic>{
            'local_operation_id': op['local_operation_id'],
            'operation_type': type,
            'status': 'applied',
            'ok': true,
          },
        ],
      };
    }
    return null;
  }
}

class _EmptySnapshotRepo implements OrderSnapshotRepository {
  @override
  Future<PosSnapshotPage> fetchWindow({
    PosSyncCursor? before,
    int limit = 50,
    int windowDays = 2,
  }) async => PosSnapshotPage.empty;
  @override
  Future<PosSnapshotPage> fetchChanges({
    PosSyncCursor? cursor,
    int limit = 50,
    int windowDays = 2,
  }) async => PosSnapshotPage.empty;
  @override
  Future<PosSnapshotPage> fetchOrders(List<String> orderIds) async =>
      PosSnapshotPage.empty;
}
