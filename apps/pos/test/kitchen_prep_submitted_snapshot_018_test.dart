import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport;
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenPrepComponent, OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/draft_recovery_store.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/order_snapshot_repository.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart'
    show kdsTicketViewFromSubmittedOrder;
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/draft_recovery_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart'
    show posSyncClockProvider, orderSnapshotRepositoryProvider;
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart'
    show submitOrderFromCart;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/verified_kitchen_mode_readiness.dart';

/// KITCHEN-PREP-MODIFIER-SPLIT-FINAL-CLOSURE-018 — Codex HIGH #1 and HIGH #2.
///
/// #1 The authoritative submitted prep map answered `null` for an item it had no
///    entry for, which the old `map?[id] ?? _linePrep[...]` expression could not
///    tell apart from "no map at all" — so an owner who DELETED every preparation
///    resource before submit had the deleted add-time prep resurrected on the
///    confirmation and every manual reprint.
///
/// #2 The PIN-handover path built the departed worker's retained order from the
///    captured DRAFT, whose lines carry their ADD-TIME prep. A handover mid-submit
///    therefore rewound the retained row (and its reprints) to a configuration the
///    server never accepted.
///
/// Both are driven through the REAL production entry point (`submitOrderFromCart`)
/// with a live, MUTABLE menu — never a hand-built SubmittedOrderView.

const _ctx = DeviceContext(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-A',
  deviceId: 'device-1',
  deviceType: 'pos',
  deviceSessionId: 'ds-A',
);

const _cheeseId = 'burger-opt-cheese';

/// The burger as it stood when the cashier rang it up: Bread 1 + Meat pieces 2,
/// no classifier. This is what `_linePrep` captures at add time.
const _burgerAtAddTime = DemoMenuItem(
  id: 'burger-240',
  name: 'Burger 240g',
  priceMinor: 4500,
  categoryId: 'meals',
  categoryName: 'Meals',
  categoryDisplayOrder: 1,
  itemDisplayOrder: 1,
  attributes: <String, dynamic>{
    'prep_components': [
      {'name': 'Bread', 'quantity': 1, 'unit': ''},
      {'name': 'Meat pieces', 'quantity': 2, 'unit': ''},
    ],
  },
);

/// The SAME product after the owner linked Cheese and changed the bread count.
const _burgerAtSubmitTime = DemoMenuItem(
  id: 'burger-240',
  name: 'Burger 240g',
  priceMinor: 4500,
  categoryId: 'meals',
  categoryName: 'Meals',
  categoryDisplayOrder: 1,
  itemDisplayOrder: 1,
  attributes: <String, dynamic>{
    'prep_components': [
      {'name': 'Bread', 'quantity': 3, 'unit': ''},
      {
        'name': 'Meat pieces',
        'quantity': 2,
        'unit': '',
        'classifier_option_id': _cheeseId,
        'classifier_option_name': 'Cheese',
      },
    ],
  },
);

/// The SAME product after the owner deleted EVERY preparation resource — the
/// authoritative map then carries no entry for it at all (Codex HIGH #1).
const _burgerWithNoPrep = DemoMenuItem(
  id: 'burger-240',
  name: 'Burger 240g',
  priceMinor: 4500,
  categoryId: 'meals',
  categoryName: 'Meals',
  categoryDisplayOrder: 1,
  itemDisplayOrder: 1,
);

const _cheeseGroup = PosModifierGroup(
  id: 'grp-extras',
  menuItemId: 'burger-240',
  name: 'Extras',
  options: [
    PosModifierOption(id: _cheeseId, name: 'Cheese', priceDeltaMinor: 300),
  ],
);

PosMenuData _menu(DemoMenuItem burger) => PosMenuData(
  categories: const [],
  items: [burger],
  currencyCode: 'ILS',
  modifierGroups: const [_cheeseGroup],
);

/// The MUTABLE live menu the POS reads at submit time.
final _menuSource = StateProvider<PosMenuData>(
  (ref) => _menu(_burgerAtAddTime),
);

final _t0 = DateTime.utc(2026, 8, 2, 9);

/// A transport that accepts every submit and can run a SYNCHRONOUS side effect
/// while the order is in flight — the same interception shape the existing
/// handover tests use, so the handover is deterministic with no timing sleeps.
class _Transport implements SyncRpcTransport {
  int pinSessions = 0;
  final List<Map<String, dynamic>> orderSubmitOps = <Map<String, dynamic>>[];
  bool interceptNextOrder = false;
  void Function()? onIntercept;

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
      if (type == 'order.submit') {
        orderSubmitOps.add(op);
        if (interceptNextOrder) {
          interceptNextOrder = false;
          onIntercept?.call(); // SYNC handover while this op is in flight
        }
        return <String, dynamic>{
          'ok': true,
          'results': <dynamic>[
            <String, dynamic>{
              'local_operation_id': op['local_operation_id'],
              'operation_type': 'order.submit',
              'status': 'applied',
              'ok': true,
            },
          ],
        };
      }
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppLocalizations> l10nEn() =>
      AppLocalizations.delegate.load(const Locale('en'));

  ProviderContainer makeContainer(
    SharedPreferences prefs,
    _Transport transport,
  ) => ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport),
      posRealSessionConfigProvider.overrideWithValue(null),
      posDraftRecoveryStoreProvider.overrideWithValue(
        SharedPrefsDraftRecoveryStore(prefs),
      ),
      orderSnapshotRepositoryProvider.overrideWithValue(_EmptySnapshotRepo()),
      posRecentOrdersStoreProvider.overrideWithValue(
        InMemoryRecentOrdersStore(),
      ),
      posSyncClockProvider.overrideWithValue(() => _t0),
      // The MUTABLE live menu — the whole point of these tests.
      posMenuProvider.overrideWith((ref) => ref.watch(_menuSource)),
      verifiedKdsReadinessOverride(),
    ],
  );

  Future<void> settle() async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.microtask(() {});
    }
  }

  Future<void> signIn(
    ProviderContainer c, {
    String employeeProfileId = 'emp-A',
  }) async {
    c.read(posDeviceContextProvider.notifier).set(_ctx);
    await settle();
    final err = await c
        .read(posSessionControllerProvider.notifier)
        .signInWithPin(
          device: _ctx,
          deviceId: _ctx.deviceId!,
          deviceSessionId: _ctx.deviceSessionId!,
          employeeProfileId: employeeProfileId,
          pin: '1234',
        );
    expect(err, isNull);
    await settle();
  }

  Future<(WidgetRef, BuildContext)> pumpApp(
    WidgetTester tester,
    ProviderContainer c,
  ) async {
    late WidgetRef ref;
    late BuildContext context;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Consumer(
            builder: (ctx, r, _) {
              ref = r;
              context = ctx;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      ),
    );
    await tester.pump();
    return (ref, context);
  }

  /// The prep snapshot the AUTHORITATIVE order payload carried to the server.
  List<Map<String, Object?>> wirePrep(_Transport t) {
    final item =
        ((t.orderSubmitOps.last['payload'] as Map)['order_items'] as List).first
            as Map;
    return [
      for (final p in (item['prep_snapshot'] as List? ?? const []))
        (p as Map).cast<String, Object?>(),
    ];
  }

  /// Adds the burger (with Cheese) to the cart, then swaps the live menu.
  Future<(WidgetRef, BuildContext)> addThenChangeMenu(
    WidgetTester tester,
    ProviderContainer c,
    DemoMenuItem atSubmit,
  ) async {
    await signIn(c);
    c.read(posDraftRecoveryProvider);
    final (ref, context) = await pumpApp(tester, c);
    final cart = c.read(cartControllerProvider.notifier);
    cart.addItemWithModifiers(_burgerAtAddTime, const [
      SelectedModifier(
        optionId: _cheeseId,
        groupName: 'Extras',
        optionName: 'Cheese',
        priceDeltaMinor: 300,
      ),
    ]);
    c
        .read(orderSetupControllerProvider.notifier)
        .setOrderType(OrderType.takeaway);
    await tester.pump();
    // The owner edits the product AFTER it entered the cart.
    c.read(_menuSource.notifier).state = _menu(atSubmit);
    await tester.pump();
    return (ref, context);
  }

  Future<void> submit(
    WidgetTester tester,
    ProviderContainer c,
    WidgetRef ref,
    BuildContext context,
    AppLocalizations l10n,
  ) async {
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
  }

  // =====================================================================
  // Codex HIGH #1 — authoritative map with NO key for the item
  // =====================================================================
  group('018-1. an authoritative map without an entry means NO prep', () {
    testWidgets('deleting every resource before submit does not resurrect the '
        'add-time prep', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final transport = _Transport();
      final c = makeContainer(prefs, transport);
      addTearDown(c.dispose);
      final l10n = await l10nEn();

      // Rung up WITH prep; the owner then deletes every resource.
      final (ref, context) = await addThenChangeMenu(
        tester,
        c,
        _burgerWithNoPrep,
      );
      await submit(tester, c, ref, context, l10n);

      // 4. The authoritative wire payload carries NO preparation resource.
      expect(wirePrep(transport), isEmpty);

      // 5. The confirmation view — and therefore the manual reprint — agree.
      final submitted = c.read(cartControllerProvider).submittedOrder!;
      expect(submitted.lines.single.prepComponents, isEmpty);
      expect(kdsTicketViewFromSubmittedOrder(submitted).kitchenCounts, isEmpty);

      // 6. The deleted add-time resources are nowhere.
      expect(
        submitted.lines.single.prepComponents.map((p) => p.name),
        isNot(contains('Bread')),
      );
    });

    testWidgets('a present entry still wins over the add-time capture', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      final transport = _Transport();
      final c = makeContainer(prefs, transport);
      addTearDown(c.dispose);
      final l10n = await l10nEn();

      final (ref, context) = await addThenChangeMenu(
        tester,
        c,
        _burgerAtSubmitTime,
      );
      await submit(tester, c, ref, context, l10n);

      final submitted = c.read(cartControllerProvider).submittedOrder!;
      final prep = submitted.lines.single.prepComponents;
      expect(prep.first.quantity, 3, reason: 'the SUBMITTED bread count');
      expect(prep[1].isClassified, isTrue);
      expect(prep[1].classifierSelected, isTrue);
      // The wire payload says exactly the same thing.
      expect(wirePrep(transport).first['quantity'], 3);
    });

    test('submittedPrepForItem distinguishes "no map" from "no entry"', () {
      // The unit contract behind the two cases above.
      expect(submittedPrepForItem(null, 'burger-240'), isNull);
      expect(
        submittedPrepForItem(
          const <String, List<KitchenPrepComponent>>{},
          'burger-240',
        ),
        isEmpty,
      );
      expect(
        submittedPrepForItem(const <String, List<KitchenPrepComponent>>{
          'other': [KitchenPrepComponent(name: 'X', quantity: 1)],
        }, 'burger-240'),
        isEmpty,
      );
      expect(
        submittedPrepForItem(const <String, List<KitchenPrepComponent>>{
          'burger-240': [KitchenPrepComponent(name: 'Bread', quantity: 1)],
        }, 'burger-240'),
        hasLength(1),
      );
    });
  });

  // =====================================================================
  // Codex HIGH #2 — PIN handover must retain the SUBMITTED snapshot
  // =====================================================================
  group('018-2. a PIN handover keeps the submitted prep snapshot', () {
    testWidgets('the departed worker\'s retained order uses the submitted '
        'snapshot, not the draft', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final transport = _Transport();
      final c = makeContainer(prefs, transport);
      addTearDown(c.dispose);
      final l10n = await l10nEn();

      final (ref, context) = await addThenChangeMenu(
        tester,
        c,
        _burgerAtSubmitTime,
      );

      // Worker B takes the till WHILE the order is in flight (synchronous, no
      // sleeps) — so the result lands on the departed-session path.
      transport
        ..interceptNextOrder = true
        ..onIntercept = () =>
            c.read(posSignedInEmployeeProfileIdProvider.notifier).set('emp-B');
      await submit(tester, c, ref, context, l10n);

      expect(c.read(posSignedInEmployeeProfileIdProvider), 'emp-B');
      // The current session's cart was NOT applied to (Finding 1C stands).
      expect(c.read(cartControllerProvider).submittedOrder, isNull);

      // 5. Worker A's retained recent order carries the SUBMITTED snapshot.
      final retained = c.read(posRecentOrdersControllerProvider).single.order!;
      final line = retained.lines.single;
      expect(
        line.prepComponents.first.quantity,
        3,
        reason: 'the submitted bread count, not the add-time 1',
      );
      expect(line.prepComponents[1].isClassified, isTrue);
      expect(line.prepComponents[1].classifierOptionName, 'Cheese');
      expect(line.prepComponents[1].classifierSelected, isTrue);

      // 6. The outbox/wire payload said exactly the same thing.
      expect(wirePrep(transport).first['quantity'], 3);
      expect(wirePrep(transport)[1]['classifier_option_name'], 'Cheese');

      // 7. The old add-time configuration never reappears — and the manual
      //    reprint from the retained row agrees with the submitted operation.
      final counts = kdsTicketViewFromSubmittedOrder(retained).kitchenCounts;
      expect(
        [
          for (final c in counts)
            (c.quantity, c.label, c.classifier, c.classifierSelected),
        ],
        [(3, 'Bread', '', false), (2, 'Meat pieces', 'Cheese', true)],
      );
    });

    testWidgets('a handover after the resources were DELETED retains none', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      final transport = _Transport();
      final c = makeContainer(prefs, transport);
      addTearDown(c.dispose);
      final l10n = await l10nEn();

      final (ref, context) = await addThenChangeMenu(
        tester,
        c,
        _burgerWithNoPrep,
      );
      transport
        ..interceptNextOrder = true
        ..onIntercept = () =>
            c.read(posSignedInEmployeeProfileIdProvider.notifier).set('emp-B');
      await submit(tester, c, ref, context, l10n);

      final retained = c.read(posRecentOrdersControllerProvider).single.order!;
      expect(retained.lines.single.prepComponents, isEmpty);
      expect(wirePrep(transport), isEmpty);
    });

    testWidgets('a later menu change does not move the retained view', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      final transport = _Transport();
      final c = makeContainer(prefs, transport);
      addTearDown(c.dispose);
      final l10n = await l10nEn();

      final (ref, context) = await addThenChangeMenu(
        tester,
        c,
        _burgerAtSubmitTime,
      );
      transport
        ..interceptNextOrder = true
        ..onIntercept = () =>
            c.read(posSignedInEmployeeProfileIdProvider.notifier).set('emp-B');
      await submit(tester, c, ref, context, l10n);

      final before = kdsTicketViewFromSubmittedOrder(
        c.read(posRecentOrdersControllerProvider).single.order!,
      ).kitchenCounts;

      // The owner edits the product again, long after the order was accepted.
      c.read(_menuSource.notifier).state = _menu(_burgerWithNoPrep);
      await tester.pump();
      await settle();

      final after = kdsTicketViewFromSubmittedOrder(
        c.read(posRecentOrdersControllerProvider).single.order!,
      ).kitchenCounts;
      expect(after, before, reason: 'order-time snapshot (D-008)');
      expect(after, isNotEmpty);
    });

    testWidgets('money and cart/session state are otherwise untouched', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      final transport = _Transport();
      final c = makeContainer(prefs, transport);
      addTearDown(c.dispose);
      final l10n = await l10nEn();

      final (ref, context) = await addThenChangeMenu(
        tester,
        c,
        _burgerAtSubmitTime,
      );
      transport
        ..interceptNextOrder = true
        ..onIntercept = () =>
            c.read(posSignedInEmployeeProfileIdProvider.notifier).set('emp-B');
      await submit(tester, c, ref, context, l10n);

      final retained = c.read(posRecentOrdersControllerProvider).single.order!;
      // 4500 base + 300 cheese, one unit (MONEY-PRICING-FORMULA-002A).
      expect(retained.lines.single.lineTotalMinor, 4800);
      expect(retained.subtotalMinor, 4800);
      expect(retained.orderType, OrderType.takeaway);
      // Exactly one submit reached the wire.
      expect(transport.orderSubmitOps, hasLength(1));
    });
  });
}
