import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport, SyncTransportException, SyncTransportErrorKind;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/draft_recovery_store.dart';
import 'package:restoflow_pos/src/data/durable_outbox_store.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/order_snapshot_repository.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/draft_recovery_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart'
    show posSyncClockProvider, orderSnapshotRepositoryProvider;
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart'
    show submitOrderFromCart;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/verified_kitchen_mode_readiness.dart';

/// MONEY-PRODUCTION-PATH-TESTS-002D [A] — Codex Blocker 7, the durable outbox.
///
/// WHY THIS SUITE EXISTS. `durable_outbox_test.dart` proves RF-114 queue
/// mechanics, but it hand-builds an `OutboxEntry` around a PLAIN item
/// (2100 x 2 = 4200) and drives `RealOutboxRepository` directly. It therefore
/// never shows that a PAID MODIFIER survives the real submit path, and it never
/// crosses the cart. Its claim is honest but narrow; this suite is the
/// production-path proof that was missing.
///
/// Everything below runs through the REAL seams:
///   * PIN sign-in via `PosSessionController.signInWithPin`;
///   * the cart built through public `CartController` operations;
///   * `submitOrderFromCart` — the actual Send handler behind the POS button;
///   * `RealOutboxRepository` over a REAL `SharedPrefsOutboxStore`;
///   * a fake `SyncRpcTransport` at the ONE network boundary;
///   * FULL `ProviderContainer` disposal and rebuild over the SAME
///     `SharedPreferences`, i.e. an app restart.
///
/// Every expected amount below is an INDEPENDENT LITERAL. Nothing is derived by
/// calling the helper under test.
///
/// Classification: CODEX COVERAGE GAP — the behaviour is expected correct on the
/// corrected stack; no test exercised it end to end before.

// The canonical 002D money fixture.
const kBase = 4500;
const k240 = 1500;
const kQty = 2;
// Independent literals: 4500 + 1500 = 6000 per unit; 6000 x 2 = 12000.
const kConfiguredUnit = 6000;
const kLineTotal = 12000;

const _ctx = DeviceContext(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-A',
  deviceId: 'device-1',
  deviceType: 'pos',
  deviceSessionId: 'ds-A',
);

/// The durable outbox key the production store writes for THIS device.
const _outboxPrefsKey = 'restoflow.pos.outbox.v1.device-1';

const _burger = DemoMenuItem(
  id: 'burger-meat',
  name: 'Burger',
  priceMinor: kBase,
  categoryId: 'meals',
  categoryName: 'Meals',
);

const _meat240 = SelectedModifier(
  optionId: 'opt-240',
  modifierGroupId: 'grp-meat',
  groupName: 'Meat',
  optionName: '240g',
  priceDeltaMinor: k240,
);

/// Records every `order.submit` op the production path actually sent, and can be
/// told to fail the next one at the real transport boundary.
class _RecordingTransport implements SyncRpcTransport {
  int pinSessions = 0;
  final List<Map<String, dynamic>> orderSubmitOps = <Map<String, dynamic>>[];
  SyncTransportException? throwOnNextOrder;

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
        final err = throwOnNextOrder;
        if (err != null) {
          throwOnNextOrder = null;
          throw err;
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

final _t0 = DateTime.utc(2026, 8, 6, 9);

void main() {
  ProviderContainer makeContainer(
    SharedPreferences prefs,
    _RecordingTransport transport,
  ) => ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport),
      posRealSessionConfigProvider.overrideWithValue(null),
      // THE POINT OF THIS SUITE: the REAL durable outbox store, not an
      // in-memory double. No test in the repository overrode this before.
      durableOutboxStoreProvider.overrideWithValue(
        SharedPrefsOutboxStore(prefs),
      ),
      posDraftRecoveryStoreProvider.overrideWithValue(
        SharedPrefsDraftRecoveryStore(prefs),
      ),
      orderSnapshotRepositoryProvider.overrideWithValue(_EmptySnapshotRepo()),
      posRecentOrdersStoreProvider.overrideWithValue(
        SharedPrefsRecentOrdersStore(prefs),
      ),
      posSyncClockProvider.overrideWithValue(() => _t0),
      verifiedKdsReadinessOverride(),
    ],
  );

  Future<void> settle() async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.microtask(() {});
    }
  }

  Future<void> signIn(ProviderContainer c) async {
    c.read(posDeviceContextProvider.notifier).set(_ctx);
    await settle();
    final err = await c
        .read(posSessionControllerProvider.notifier)
        .signInWithPin(
          device: _ctx,
          deviceId: _ctx.deviceId!,
          deviceSessionId: _ctx.deviceSessionId!,
          employeeProfileId: 'emp-A',
          pin: '1234',
        );
    expect(err, isNull, reason: 'the real PIN sign-in must succeed');
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
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      ),
    );
    await tester.pump();
    return (ref, context);
  }

  /// The raw durable envelope the production store wrote, decoded but NOT
  /// re-encoded — this is what actually sits in localStorage.
  List<Map<String, Object?>> storedEntries(SharedPreferences prefs) {
    final raw = prefs.getString(_outboxPrefsKey);
    expect(raw, isNotNull, reason: 'the durable outbox wrote nothing at all');
    final envelope = (jsonDecode(raw!) as Map).cast<String, Object?>();
    expect(envelope['version'], SharedPrefsOutboxStore.schemaVersion);
    return (envelope['entries']! as List)
        .cast<Map<dynamic, dynamic>>()
        .map((e) => e.cast<String, Object?>())
        .toList();
  }

  testWidgets('A1 a paid modifier at item quantity 2 reaches the REAL durable '
      'outbox with exact money, survives a process restart byte-identically, '
      'and retries under the SAME operation identity', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final transport = _RecordingTransport();

    // ---------------------------------------------------------------- session 1
    final c1 = makeContainer(prefs, transport);
    await signIn(c1);

    final cart = c1.read(cartControllerProvider.notifier);
    cart.addItemWithModifiers(_burger, const [_meat240]);
    final lineId = c1.read(cartControllerProvider).lines.single.lineId;
    cart.increaseQuantity(lineId); // item quantity 2

    // What the cashier sees, against independent literals.
    final view = c1.read(cartControllerProvider);
    expect(view.lines.single.quantity, kQty);
    expect(view.lines.single.unitPriceMinor, kBase);
    expect(view.lines.single.lineTotalMinor, kLineTotal);
    expect(view.subtotalMinor, kLineTotal);

    c1
        .read(orderSetupControllerProvider.notifier)
        .setOrderType(OrderType.takeaway);
    await settle();

    // The FIRST send fails at the real transport boundary (a network error).
    transport.throwOnNextOrder = const SyncTransportException(
      SyncTransportErrorKind.transient,
      code: 'offline',
    );

    final (ref1, ctx1) = await pumpApp(tester, c1);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await submitOrderFromCart(
      ref: ref1,
      context: ctx1,
      cart: c1.read(cartControllerProvider),
      setup: c1.read(orderSetupControllerProvider),
      cartController: cart,
      setupController: c1.read(orderSetupControllerProvider.notifier),
      l10n: l10n,
      taxTotalMinor: 0,
      taxRateBp: 0,
    );
    await tester.pump();
    await settle();
    await tester.pump();

    // ------------------------------------------------- the DURABLE record
    final entries1 = storedEntries(prefs);
    expect(
      entries1,
      hasLength(1),
      reason: 'exactly one business operation was created',
    );
    final stored = entries1.single;
    expect(stored['operation_type'], 'order.submit');
    final frozenPayloadJson = stored['payload_json']! as String;
    final localOperationId = stored['local_operation_id']! as String;
    expect(localOperationId, isNotEmpty);

    final payload = jsonDecode(frozenPayloadJson) as Map<String, Object?>;
    final items = (payload['order_items']! as List)
        .cast<Map<dynamic, dynamic>>()
        .map((e) => e.cast<String, Object?>())
        .toList();
    expect(items, hasLength(1));
    final item = items.single;

    // Exact money, every value an independent literal.
    expect(item['quantity'], kQty);
    expect(item['unit_price_minor_snapshot'], kBase);
    expect(
      item['line_total_minor'],
      kLineTotal,
      reason: 'qty x (base + modifiers) — the corrected 002A rule',
    );
    final mods = (item['modifiers']! as List)
        .cast<Map<dynamic, dynamic>>()
        .map((e) => e.cast<String, Object?>())
        .toList();
    expect(mods, hasLength(1));
    expect(mods.single['price_minor_snapshot'], k240);
    expect(
      mods.single['quantity'],
      1,
      reason: 'the MODIFIER quantity is 1; the ITEM quantity is 2',
    );
    expect(payload['subtotal_minor'], kLineTotal);
    expect(payload['grand_total_minor'], kLineTotal);
    expect(payload['local_operation_id'], localOperationId);

    // 002C wire isolation, proven on the DURABLE record this time.
    expect(
      frozenPayloadJson.contains('modifier_group_id'),
      isFalse,
      reason: 'the local-only group id must never be persisted onto the wire',
    );
    expect(frozenPayloadJson.contains('grp-meat'), isFalse);

    // The failed attempt did not fabricate success.
    expect(transport.orderSubmitOps, hasLength(1));

    // ------------------------------------------------- process restart
    c1.dispose();

    final c2 = makeContainer(prefs, transport);
    addTearDown(c2.dispose);
    await signIn(c2);
    // A genuinely new PIN session, as a restart produces.
    expect(transport.pinSessions, 2);

    // The production controller loads its queue from the durable store.
    // Pass B: startup delivery is the reset path (order_sync_controller's
    // pushFirst does exactly this), so the entry that failed before the
    // restart is due NOW rather than waiting out its persisted backoff.
    // (OLD: pushQueued() — there was no schedule to reset.)
    await c2
        .read(outboxControllerProvider.notifier)
        .pushQueued(resetBackoff: true);
    await settle();

    final entries2 = storedEntries(prefs);
    expect(entries2, hasLength(1), reason: 'the restart created no duplicate');
    expect(
      entries2.single['local_operation_id'],
      localOperationId,
      reason: 'D-022: the idempotency identity must survive a restart',
    );
    expect(
      entries2.single['payload_json'],
      frozenPayloadJson,
      reason: 'the payload is FROZEN — byte-identical across the restart',
    );

    // ------------------------------------------------- the retry itself
    expect(
      transport.orderSubmitOps.length,
      greaterThanOrEqualTo(2),
      reason: 'the queued order was re-delivered after the restart',
    );
    final sentIds = transport.orderSubmitOps
        .map((op) => op['local_operation_id'])
        .toSet();
    expect(
      sentIds,
      <String>{localOperationId},
      reason:
          'every attempt carried ONE operation identity — the server '
          'dedupes on it, so a retry can never become a second order',
    );

    // The surcharge is present exactly once in every attempt.
    for (final op in transport.orderSubmitOps) {
      final sentPayload = (op['payload'] as Map).cast<String, Object?>();
      final sentItems = (sentPayload['order_items']! as List)
          .cast<Map<dynamic, dynamic>>()
          .map((e) => e.cast<String, Object?>())
          .toList();
      expect(sentItems, hasLength(1));
      final sentMods = (sentItems.single['modifiers']! as List)
          .cast<Map<dynamic, dynamic>>()
          .map((e) => e.cast<String, Object?>())
          .toList();
      expect(
        sentMods,
        hasLength(1),
        reason: 'the retry neither dropped nor duplicated the surcharge',
      );
      expect(sentMods.single['price_minor_snapshot'], k240);
      expect(sentItems.single['line_total_minor'], kLineTotal);
      expect(sentPayload['subtotal_minor'], kLineTotal);
    }
  });

  testWidgets('A2 the modifier UNIT delta is never pre-multiplied by the item '
      'quantity anywhere on the durable record', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final transport = _RecordingTransport();
    final c = makeContainer(prefs, transport);
    addTearDown(c.dispose);
    await signIn(c);

    final cart = c.read(cartControllerProvider.notifier);
    cart.addItemWithModifiers(_burger, const [_meat240]);
    final lineId = c.read(cartControllerProvider).lines.single.lineId;
    cart.increaseQuantity(lineId);
    cart.increaseQuantity(lineId); // item quantity 3
    expect(c.read(cartControllerProvider).lines.single.lineTotalMinor, 18000);

    c
        .read(orderSetupControllerProvider.notifier)
        .setOrderType(OrderType.takeaway);
    await settle();

    final (ref, ctx) = await pumpApp(tester, c);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await submitOrderFromCart(
      ref: ref,
      context: ctx,
      cart: c.read(cartControllerProvider),
      setup: c.read(orderSetupControllerProvider),
      cartController: cart,
      setupController: c.read(orderSetupControllerProvider.notifier),
      l10n: l10n,
      taxTotalMinor: 0,
      taxRateBp: 0,
    );
    await tester.pump();
    await settle();

    final payload =
        jsonDecode(storedEntries(prefs).single['payload_json']! as String)
            as Map<String, Object?>;
    final item = ((payload['order_items']! as List).first as Map)
        .cast<String, Object?>();
    final mod = ((item['modifiers']! as List).first as Map)
        .cast<String, Object?>();

    expect(item['quantity'], 3);
    expect(item['unit_price_minor_snapshot'], kBase);
    expect(
      mod['price_minor_snapshot'],
      k240,
      reason: 'the UNIT delta — the server multiplies, the client must not',
    );
    expect(mod['quantity'], 1);
    // 3 x (4500 + 1500) = 18000, as an independent literal.
    expect(item['line_total_minor'], 18000);
    expect(payload['subtotal_minor'], 18000);
    // And the configured unit is recoverable from the wire alone.
    expect(
      (item['unit_price_minor_snapshot']! as int) +
          (mod['price_minor_snapshot']! as int) * (mod['quantity']! as int),
      kConfiguredUnit,
    );
  });
}
