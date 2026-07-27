import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport, SyncTransportException, SyncTransportErrorKind;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_feature_kitchen/kitchen_print.dart' as kit;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/draft_recovery_store.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/order_snapshot_repository.dart';
import 'package:restoflow_pos/src/data/payment.dart'
    show CashPayment, PaymentMethod, PaymentStatus;
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart'
    show kdsTicketViewFromCartLines, kitchenTicketPrintLabelsFromL10n;
import 'package:restoflow_pos/src/print/print_document.dart' show PrintLineKind;
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/draft_recovery_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart'
    show posSyncClockProvider, orderSnapshotRepositoryProvider;
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart'
    show submitOrderFromCart;
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart'
    show buildReceiptDocument;
import 'package:restoflow_pos/src/widgets/recovery_coordinator.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MENU-ORDER-001 (Codex 8th pass) — CORRECTION-RESULT SETTLEMENT ACROSS WORKER/SCOPE
/// HANDOVER. A corrected submit (source recovery e1 -> corrected op e2, durably linked
/// BEFORE dispatch) that settles AFTER the submitting worker/scope changed must NEVER
/// create a second standalone recovery keyed by e2. These drive the REAL public POS flow
/// (submitOrderFromCart) with a fake transport that performs the handover SYNCHRONOUSLY
/// while the corrected order is in flight — flipping the STABLE worker id
/// (posSignedInEmployeeProfileIdProvider), which is the recovery's durable ownership axis
/// (D-006), so at result time the binding differs from the submitting binding and the
/// departed-session settlement path runs. This models a PIN handover on the same till
/// without mid-flight session/outbox churn.

const _ctxA = DeviceContext(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-A',
  deviceId: 'device-1',
  deviceType: 'pos',
  deviceSessionId: 'ds-A',
);

/// A fake transport that can INTERCEPT the next order.submit (the corrected op): it runs
/// a synchronous handover side-effect just before producing the result, then returns
/// [correctedResult] or throws [correctedThrow]. Models the worker changing while the
/// corrected op is in flight.
class _HandoverTransport implements SyncRpcTransport {
  int pinSessions = 0;
  final List<Map<String, dynamic>> orderSubmitOps = <Map<String, dynamic>>[];
  final List<Map<String, dynamic> Function(String opId)> orderScript =
      <Map<String, dynamic> Function(String opId)>[];
  int _idx = 0;

  bool interceptNextOrder = false;
  void Function()? onIntercept;
  Map<String, dynamic> Function(String opId)? correctedResult;
  Object? correctedThrow;

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
        final opId = op['local_operation_id'] as String;
        if (interceptNextOrder) {
          interceptNextOrder = false;
          onIntercept?.call(); // SYNC handover while this op is in flight
          final err = correctedThrow;
          if (err != null) {
            correctedThrow = null;
            throw err;
          }
          return <String, dynamic>{
            'ok': true,
            'results': <dynamic>[correctedResult!(opId)],
          };
        }
        final builder = _idx < orderScript.length
            ? orderScript[_idx]
            : orderScript.last;
        _idx++;
        return <String, dynamic>{
          'ok': true,
          'results': <dynamic>[builder(opId)],
        };
      }
    }
    return null;
  }
}

Map<String, dynamic> _itemUnavailable(String opId) => <String, dynamic>{
  'local_operation_id': opId,
  'operation_type': 'order.submit',
  'status': 'rejected',
  'error': 'item_unavailable',
  'items': <dynamic>[
    <String, dynamic>{'name': 'Cola'},
  ],
};

Map<String, dynamic> _accepted(String opId) => <String, dynamic>{
  'local_operation_id': opId,
  'operation_type': 'order.submit',
  'status': 'applied',
  'ok': true,
};

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

/// A store whose writes fail while [failWrites] is set (reads delegate).
class _ToggleFailRecoveryStore implements PosDraftRecoveryStore {
  _ToggleFailRecoveryStore(this._inner);
  final PosDraftRecoveryStore _inner;
  bool failWrites = false;
  @override
  Future<Map<String, PosDraftRecovery>> load() => _inner.load();
  @override
  Future<void> persist(Map<String, PosDraftRecovery> recoveries) async {
    if (failWrites) throw StateError('durable write failed');
    return _inner.persist(recoveries);
  }
}

const _cola = DemoMenuItem(
  id: 'cola',
  name: 'Cola',
  priceMinor: 1000,
  categoryId: 'drinks',
  categoryName: 'Drinks',
  categoryDisplayOrder: 3,
  itemDisplayOrder: 1,
);
const _burgerA = DemoMenuItem(
  id: 'burger-a',
  name: 'Burger A',
  priceMinor: 2000,
  categoryId: 'meals',
  categoryName: 'Meals',
  categoryDisplayOrder: 1,
  itemDisplayOrder: 2,
);
const _burgerB = DemoMenuItem(
  id: 'burger-b',
  name: 'Burger B',
  priceMinor: 2000,
  categoryId: 'meals',
  categoryName: 'Meals',
  categoryDisplayOrder: 1,
  itemDisplayOrder: 1,
);
const _fries = DemoMenuItem(
  id: 'fries',
  name: 'Fries',
  priceMinor: 1000,
  categoryId: 'sides',
  categoryName: 'Sides',
  categoryDisplayOrder: 2,
  itemDisplayOrder: 1,
);

final _t0 = DateTime.utc(2026, 7, 27, 9);

void main() {
  Future<AppLocalizations> l10nEn() =>
      AppLocalizations.delegate.load(const Locale('en'));

  ProviderContainer makeContainer(
    SharedPreferences prefs,
    _HandoverTransport transport, {
    PosDraftRecoveryStore? recoveryStore,
  }) => ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport),
      posRealSessionConfigProvider.overrideWithValue(null),
      posDraftRecoveryStoreProvider.overrideWithValue(
        recoveryStore ?? SharedPrefsDraftRecoveryStore(prefs),
      ),
      orderSnapshotRepositoryProvider.overrideWithValue(_EmptySnapshotRepo()),
      posRecentOrdersStoreProvider.overrideWithValue(InMemoryRecentOrdersStore()),
      posSyncClockProvider.overrideWithValue(() => _t0),
    ],
  );

  Future<void> settle() async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.microtask(() {});
    }
  }

  Future<void> signIn(
    ProviderContainer c, {
    DeviceContext ctx = _ctxA,
    String employeeProfileId = 'emp-A',
  }) async {
    c.read(posDeviceContextProvider.notifier).set(ctx);
    await settle();
    final err = await c
        .read(posSessionControllerProvider.notifier)
        .signInWithPin(
          device: ctx,
          deviceId: ctx.deviceId!,
          deviceSessionId: ctx.deviceSessionId!,
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

  /// Signs A in, builds a [cola, burger-b] cart, submits once so the backend rejects it
  /// (item_unavailable) and production captures source recovery e1, then restores e1 and
  /// drops Cola. Returns (ref, context, e1 key). The transport must have _itemUnavailable
  /// scripted for the first submit.
  Future<(WidgetRef, BuildContext, String)> captureRestoreCorrect(
    WidgetTester tester,
    ProviderContainer c,
    _HandoverTransport transport,
    AppLocalizations l10n,
  ) async {
    await signIn(c);
    c.read(posDraftRecoveryProvider);
    final (ref, context) = await pumpApp(tester, c);
    final cart = c.read(cartControllerProvider.notifier);
    cart.addItem(_cola);
    cart.addItem(_burgerB);
    c.read(orderSetupControllerProvider.notifier).setOrderType(OrderType.takeaway);
    await tester.pump();
    await submitOrderFromCart(
      ref: ref,
      context: context,
      cart: c.read(cartControllerProvider),
      setup: c.read(orderSetupControllerProvider),
      cartController: cart,
      setupController: c.read(orderSetupControllerProvider.notifier),
      l10n: l10n,
    );
    await tester.pump();
    await settle();
    final e1 = c.read(posDraftRecoveryProvider).keys.single;
    final rec = c
        .read(posDraftRecoveryProvider.notifier)
        .recoverable(e1, c.read(posRecoveryBindingProvider))!;
    await PosRecoveryCoordinator(ref).restore(context, rec);
    await tester.pump();
    cart.removeLine(
      c
          .read(cartControllerProvider)
          .lines
          .firstWhere((l) => l.menuItemId == 'cola')
          .lineId,
    );
    c.read(orderSetupControllerProvider.notifier).setOrderType(OrderType.takeaway);
    await tester.pump();
    return (ref, context, e1);
  }

  int rejectedShellCount(ProviderContainer c) => c
      .read(posRecentOrdersControllerProvider)
      .where((o) => o.isNeverCreated)
      .length;

  // ---------------------------------------------------------------------------------
  // §8 — item_unavailable after Worker A -> Worker B handover.
  // ---------------------------------------------------------------------------------
  testWidgets(
    'A->B worker handover, corrected op item_unavailable: ONE logical recovery on e1, '
    'no standalone e2, one shell, B denied, A returns to exactly one',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final l10n = await l10nEn();
      final transport = _HandoverTransport()..orderScript.add(_itemUnavailable);
      final c = makeContainer(prefs, transport);
      addTearDown(c.dispose);
      final (ref, context, e1) = await captureRestoreCorrect(
        tester,
        c,
        transport,
        l10n,
      );
      final ownerA = c.read(posRecoveryBindingProvider); // scope-A + emp-A

      // Corrected submit: the transport hands the till to Worker B (flips the stable
      // worker id) WHILE the corrected op is in flight, then returns item_unavailable.
      transport
        ..interceptNextOrder = true
        ..correctedResult = _itemUnavailable
        ..onIntercept = () => c
            .read(posSignedInEmployeeProfileIdProvider.notifier)
            .set('emp-B');
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

      final e2 = c.read(posDraftRecoveryProvider)[e1]!.correctionOutboxEntryId!;
      // Exactly one logical recovery, on e1, owned by A, linked to e2, corrected draft.
      final map = c.read(posDraftRecoveryProvider);
      expect(map, hasLength(1), reason: 'exactly one logical recovery');
      expect(map.containsKey(e1), isTrue);
      expect(map.containsKey(e2), isFalse, reason: 'NO standalone recovery keyed by e2');
      expect(map[e1]!.binding.employeeProfileId, ownerA.employeeProfileId);
      expect(map[e1]!.binding.scopeKey, ownerA.scopeKey);
      expect(map[e1]!.correctionOutboxEntryId, e2);
      expect(map[e1]!.draft.lines.map((l) => l.menuItemId).toList(), ['burger-b']);
      expect(rejectedShellCount(c), 1, reason: 'exactly one rejected shell');

      // Worker B (current) cannot list / restore / discard it, and sees no draft.
      final bindingB = c.read(posRecoveryBindingProvider);
      expect(bindingB.employeeProfileId, 'emp-B');
      expect(
        c.read(posDraftRecoveryProvider.notifier).recoverable(e1, bindingB),
        isNull,
      );
      expect(
        await c.read(posDraftRecoveryProvider.notifier).discardOwned(e1, bindingB),
        isFalse,
      );
      expect(c.read(posDraftRecoveryProvider.notifier).hasRecoveryFor(e1), isTrue);

      // Worker A returns to a fresh till, and restores the ONE recovery: one copy of
      // each line (the departed corrected submit left the cart untouched, so clear it
      // first — restore then takes the empty-cart path, no overwrite dialog).
      c.read(posSignedInEmployeeProfileIdProvider.notifier).set('emp-A');
      c.read(cartControllerProvider.notifier).clear();
      final recA = c
          .read(posDraftRecoveryProvider.notifier)
          .recoverable(e1, c.read(posRecoveryBindingProvider));
      expect(recA, isNotNull);
      await PosRecoveryCoordinator(ref).restore(context, recA!);
      await tester.pump();
      final lines = c.read(cartControllerProvider).lines;
      expect(lines, hasLength(1));
      expect(lines.single.menuItemId, 'burger-b');
    },
  );

  // ---------------------------------------------------------------------------------
  // §9A — retryable after handover.
  // ---------------------------------------------------------------------------------
  testWidgets(
    'A->B handover, corrected op RETRYABLE (network): e1 retained + linked, no standalone '
    'e2, B unaffected',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final l10n = await l10nEn();
      final transport = _HandoverTransport()..orderScript.add(_itemUnavailable);
      final c = makeContainer(prefs, transport);
      addTearDown(c.dispose);
      final (ref, context, e1) = await captureRestoreCorrect(
        tester,
        c,
        transport,
        l10n,
      );
      final ownerA = c.read(posRecoveryBindingProvider);
      transport
        ..interceptNextOrder = true
        ..correctedThrow = const SyncTransportException(
          SyncTransportErrorKind.transient,
          code: '503',
          message: 'unavailable',
        )
        ..onIntercept = () => c
            .read(posSignedInEmployeeProfileIdProvider.notifier)
            .set('emp-B');
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

      final e2 = c.read(posDraftRecoveryProvider)[e1]!.correctionOutboxEntryId!;
      final map = c.read(posDraftRecoveryProvider);
      expect(map, hasLength(1));
      expect(map.containsKey(e1), isTrue);
      expect(map.containsKey(e2), isFalse, reason: 'no standalone e2 recovery');
      expect(map[e1]!.correctionOutboxEntryId, e2);
      expect(map[e1]!.binding.employeeProfileId, ownerA.employeeProfileId);
      expect(
        c
            .read(posDraftRecoveryProvider.notifier)
            .recoverable(e1, c.read(posRecoveryBindingProvider)),
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  // ---------------------------------------------------------------------------------
  // §9C — accepted response lost after handover, reconciled by snapshot.
  // ---------------------------------------------------------------------------------
  testWidgets(
    'A->B handover, corrected op accepted-but-response-lost then ACCEPTED snapshot for e2: '
    'e1 clears via its link, no standalone e2, no duplicate order',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final l10n = await l10nEn();
      final transport = _HandoverTransport()..orderScript.add(_itemUnavailable);
      final c = makeContainer(prefs, transport);
      addTearDown(c.dispose);
      final (ref, context, e1) = await captureRestoreCorrect(
        tester,
        c,
        transport,
        l10n,
      );
      transport
        ..interceptNextOrder = true
        ..correctedThrow = const SyncTransportException(
          SyncTransportErrorKind.transient,
          code: '503',
          message: 'lost after acceptance',
        )
        ..onIntercept = () => c
            .read(posSignedInEmployeeProfileIdProvider.notifier)
            .set('emp-B');
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
      final e2 = c.read(posDraftRecoveryProvider)[e1]!.correctionOutboxEntryId!;
      expect(c.read(posDraftRecoveryProvider), hasLength(1));

      // Authoritative window pull (under B) surfaces the ACCEPTED corrected order e2.
      final orders = c.read(posRecentOrdersControllerProvider.notifier);
      orders.recordSubmitted(
        SubmittedOrderView(
          orderNumber: '#ACC',
          orderType: OrderType.takeaway,
          currencyCode: 'ILS',
          subtotalMinor: 2000,
          orderId: 'o2',
          outboxEntryId: e2,
          lines: const [],
        ),
      );
      await settle();
      await orders.applySnapshots([
        PosOrderSnapshot(
          orderId: 'o2',
          orderCode: '#ACC',
          revision: 1,
          status: 'served',
          settlement: PosSettlement.unpaid,
          subtotalMinor: 2000,
          discountTotalMinor: 0,
          taxTotalMinor: 0,
          grandTotalMinor: 2000,
          createdAt: _t0,
          updatedAt: _t0,
          syncAt: _t0,
          currencyCode: 'ILS',
        ),
      ]);
      await settle();
      expect(c.read(posDraftRecoveryProvider.notifier).hasRecoveryFor(e1), isFalse);
      expect(c.read(posDraftRecoveryProvider), isEmpty);
    },
  );

  // ---------------------------------------------------------------------------------
  // §10 — cross-SCOPE isolation of the settled recovery.
  // ---------------------------------------------------------------------------------
  testWidgets(
    'after handover + item_unavailable, the settled recovery e1 stays owned by the '
    'ORIGINAL scope: a DIFFERENT scope (branch) cannot list/restore/discard it',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final l10n = await l10nEn();
      final transport = _HandoverTransport()..orderScript.add(_itemUnavailable);
      final c = makeContainer(prefs, transport);
      addTearDown(c.dispose);
      final (ref, context, e1) = await captureRestoreCorrect(
        tester,
        c,
        transport,
        l10n,
      );
      final ownerA = c.read(posRecoveryBindingProvider); // scope-A + emp-A
      transport
        ..interceptNextOrder = true
        ..correctedResult = _itemUnavailable
        ..onIntercept = () => c
            .read(posSignedInEmployeeProfileIdProvider.notifier)
            .set('emp-B');
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
      final e2 = c.read(posDraftRecoveryProvider)[e1]!.correctionOutboxEntryId!;

      // The settled recovery is owned by the ORIGINAL scope-A; a DIFFERENT branch scope
      // (same or any worker) cannot list/restore/discard it and creates no recovery.
      final map = c.read(posDraftRecoveryProvider);
      expect(map, hasLength(1));
      expect(map[e1]!.binding.scopeKey, ownerA.scopeKey);
      expect(map[e1]!.correctionOutboxEntryId, e2);
      const scopeZ = PosRecoveryBinding(
        scopeKey: 'org-1.rest-1.branch-Z.device-1',
        employeeProfileId: 'emp-A',
      );
      expect(
        c.read(posDraftRecoveryProvider.notifier).recoverable(e1, scopeZ),
        isNull,
      );
      expect(
        await c.read(posDraftRecoveryProvider.notifier).discardOwned(e1, scopeZ),
        isFalse,
      );
      // Returning to the ORIGINAL scope + worker reveals exactly one recovery.
      c.read(posSignedInEmployeeProfileIdProvider.notifier).set('emp-A');
      expect(
        c
            .read(posDraftRecoveryProvider.notifier)
            .recoverable(e1, c.read(posRecoveryBindingProvider)),
        isNotNull,
      );
    },
  );

  // ---------------------------------------------------------------------------------
  // §11 — ORDINARY (non-correction) departed-session result: unchanged behaviour.
  // ---------------------------------------------------------------------------------
  testWidgets(
    'ordinary new order (no source recovery) rejected after A->B handover: exactly ONE '
    'standalone recovery bound to A; B cannot see it',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final l10n = await l10nEn();
      final transport = _HandoverTransport();
      final c = makeContainer(prefs, transport);
      addTearDown(c.dispose);
      await signIn(c);
      c.read(posDraftRecoveryProvider);
      final (ref, context) = await pumpApp(tester, c);
      final ownerA = c.read(posRecoveryBindingProvider);
      c.read(cartControllerProvider.notifier).addItem(_burgerB);
      c.read(orderSetupControllerProvider.notifier).setOrderType(OrderType.takeaway);
      await tester.pump();
      // Intercept the FIRST (ordinary) submit; hand over; return item_unavailable.
      transport
        ..interceptNextOrder = true
        ..correctedResult = _itemUnavailable
        ..onIntercept = () => c
            .read(posSignedInEmployeeProfileIdProvider.notifier)
            .set('emp-B');
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
      // Exactly one standalone recovery, bound to A (the original submitter), not B.
      final map = c.read(posDraftRecoveryProvider);
      expect(map, hasLength(1));
      final rec = map.values.single;
      expect(rec.binding.employeeProfileId, ownerA.employeeProfileId);
      expect(rec.correctionOutboxEntryId, isNull, reason: 'ordinary: no correction link');
      expect(
        c
            .read(posDraftRecoveryProvider.notifier)
            .recoverable(map.keys.single, c.read(posRecoveryBindingProvider)),
        isNull,
      );
    },
  );

  // ---------------------------------------------------------------------------------
  // §12 — persistence failure during settlement after handover.
  // ---------------------------------------------------------------------------------
  testWidgets(
    'store WRITE FAILURE during settlement after handover: old e1 intact + linked, no '
    'standalone e2, no false success, no crash',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final l10n = await l10nEn();
      final transport = _HandoverTransport()..orderScript.add(_itemUnavailable);
      final toggle = _ToggleFailRecoveryStore(SharedPrefsDraftRecoveryStore(prefs));
      final c = makeContainer(prefs, transport, recoveryStore: toggle);
      addTearDown(c.dispose);
      final (ref, context, e1) = await captureRestoreCorrect(
        tester,
        c,
        transport,
        l10n,
      );
      final ownerA = c.read(posRecoveryBindingProvider);
      // The pre-dispatch supersede commits BEFORE the push (store still healthy). The
      // intercept then fails writes and hands over WHILE the corrected op is in flight;
      // the result-time settlement performs NO recovery-map write, so e1 stays intact and
      // no standalone e2 is published — no crash, no false success.
      transport
        ..interceptNextOrder = true
        ..correctedResult = _itemUnavailable
        ..onIntercept = () {
          toggle.failWrites = true;
          c.read(posSignedInEmployeeProfileIdProvider.notifier).set('emp-B');
        };
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
      toggle.failWrites = false;

      final map = c.read(posDraftRecoveryProvider);
      final e2 = map[e1]!.correctionOutboxEntryId;
      expect(e2, isNotNull, reason: 'the pre-dispatch link committed before the failure');
      expect(map, hasLength(1), reason: 'old e1 intact; no standalone e2 published');
      expect(map.containsKey(e1), isTrue);
      expect(map[e1]!.correctionOutboxEntryId, e2);
      expect(map[e1]!.binding.employeeProfileId, ownerA.employeeProfileId);
      expect(tester.takeException(), isNull);
    },
  );

  // ---------------------------------------------------------------------------------
  // §13 — duplicate / racing result delivery after handover.
  // ---------------------------------------------------------------------------------
  testWidgets(
    'after handover + item_unavailable, a later ACCEPTED snapshot clears the exact e1 '
    'once, and a duplicate snapshot delivery does not resurrect it',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final l10n = await l10nEn();
      final transport = _HandoverTransport()..orderScript.add(_itemUnavailable);
      final c = makeContainer(prefs, transport);
      addTearDown(c.dispose);
      final (ref, context, e1) = await captureRestoreCorrect(
        tester,
        c,
        transport,
        l10n,
      );
      transport
        ..interceptNextOrder = true
        ..correctedResult = _itemUnavailable
        ..onIntercept = () => c
            .read(posSignedInEmployeeProfileIdProvider.notifier)
            .set('emp-B');
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
      final e2 = c.read(posDraftRecoveryProvider)[e1]!.correctionOutboxEntryId!;
      expect(c.read(posDraftRecoveryProvider), hasLength(1));

      final orders = c.read(posRecentOrdersControllerProvider.notifier);
      PosOrderSnapshot snap(int revision) => PosOrderSnapshot(
        orderId: 'o2',
        orderCode: '#ACC',
        revision: revision,
        status: 'served',
        settlement: PosSettlement.unpaid,
        subtotalMinor: 2000,
        discountTotalMinor: 0,
        taxTotalMinor: 0,
        grandTotalMinor: 2000,
        createdAt: _t0,
        updatedAt: _t0,
        syncAt: _t0,
        currencyCode: 'ILS',
      );
      orders.recordSubmitted(
        SubmittedOrderView(
          orderNumber: '#ACC',
          orderType: OrderType.takeaway,
          currencyCode: 'ILS',
          subtotalMinor: 2000,
          orderId: 'o2',
          outboxEntryId: e2,
          lines: const [],
        ),
      );
      await settle();
      await orders.applySnapshots([snap(1)]);
      await settle();
      expect(c.read(posDraftRecoveryProvider.notifier).hasRecoveryFor(e1), isFalse);
      // A duplicate authoritative delivery cannot resurrect the cleared recovery.
      await orders.applySnapshots([snap(2)]);
      await settle();
      expect(c.read(posDraftRecoveryProvider), isEmpty);
    },
  );

  // ---------------------------------------------------------------------------------
  // §15 — real customer receipt + kitchen from the single returned recovery.
  // ---------------------------------------------------------------------------------
  testWidgets(
    'after A->B handover (item_unavailable) and A returns, the ONE recovery restores and '
    'builds a real receipt + kitchen ticket in Dashboard order; receipt has money, kitchen '
    'money-free',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final l10n = await l10nEn();
      final transport = _HandoverTransport()..orderScript.add(_itemUnavailable);
      final c = makeContainer(prefs, transport);
      addTearDown(c.dispose);
      await signIn(c);
      c.read(posDraftRecoveryProvider);
      final (ref, context) = await pumpApp(tester, c);
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItem(_cola);
      cart.addItemWithModifiers(_burgerA, const [
        SelectedModifier(
          optionId: 'no-onion',
          groupName: 'Extras',
          optionName: 'no onion',
          priceDeltaMinor: 0,
        ),
      ], note: 'well done');
      cart.addItem(_fries);
      cart.increaseQuantity(
        c.read(cartControllerProvider).lines.firstWhere((l) => l.name == 'Fries').lineId,
      );
      cart.addItem(_burgerB);
      c.read(orderSetupControllerProvider.notifier).setOrderType(OrderType.takeaway);
      await tester.pump();
      Future<void> submit() => submitOrderFromCart(
        ref: ref,
        context: context,
        cart: c.read(cartControllerProvider),
        setup: c.read(orderSetupControllerProvider),
        cartController: cart,
        setupController: c.read(orderSetupControllerProvider.notifier),
        l10n: l10n,
      );
      await submit(); // item_unavailable -> recovery e1
      await tester.pump();
      await settle();
      final e1 = c.read(posDraftRecoveryProvider).keys.single;
      final rec = c
          .read(posDraftRecoveryProvider.notifier)
          .recoverable(e1, c.read(posRecoveryBindingProvider))!;
      await PosRecoveryCoordinator(ref).restore(context, rec);
      await tester.pump();
      cart.removeLine(
        c.read(cartControllerProvider).lines.firstWhere((l) => l.menuItemId == 'cola').lineId,
      );
      c.read(orderSetupControllerProvider.notifier).setOrderType(OrderType.takeaway);
      await tester.pump();

      // Corrected submit with A->B handover, item_unavailable -> the ONE recovery is
      // superseded with the corrected cart (Cola gone) and retained under A.
      transport
        ..interceptNextOrder = true
        ..correctedResult = _itemUnavailable
        ..onIntercept = () => c
            .read(posSignedInEmployeeProfileIdProvider.notifier)
            .set('emp-B');
      await submit();
      await tester.pump();
      await settle();
      expect(c.read(posDraftRecoveryProvider), hasLength(1));

      // Worker A returns to a fresh till and restores the SINGLE recovery (clear first so
      // restore takes the empty-cart path — the departed submit left the cart untouched).
      c.read(posSignedInEmployeeProfileIdProvider.notifier).set('emp-A');
      cart.clear();
      final recA = c
          .read(posDraftRecoveryProvider.notifier)
          .recoverable(e1, c.read(posRecoveryBindingProvider))!;
      await PosRecoveryCoordinator(ref).restore(context, recA);
      await tester.pump();
      final restoredLines = c.read(cartControllerProvider).lines;

      final kitchen = kit.buildKdsTicketPrintDocument(
        ticket: kdsTicketViewFromCartLines(
          orderCode: '#R',
          orderType: OrderType.takeaway,
          lines: restoredLines,
        ),
        labels: kitchenTicketPrintLabelsFromL10n(l10n),
      );
      final kitchenItems = [
        for (final line in kitchen.lines)
          if (line.kind == kit.PrintLineKind.item) line.left ?? '',
      ];
      expect(kitchenItems, const ['1 × Burger B', '1 × Burger A', '2 × Fries']);

      // Real customer receipt: submit once more (accepted) and build from the confirmation.
      transport.orderScript.add(_accepted);
      await submit();
      await tester.pump();
      await settle();
      final submitted = c.read(cartControllerProvider).submittedOrder!;
      final payment = CashPayment(
        paymentId: 'pay-1',
        orderNumber: submitted.orderNumber,
        deviceId: 'device-1',
        localOperationId: 'pop-1',
        method: PaymentMethod.cash,
        status: PaymentStatus.completed,
        amountMinor: submitted.grandTotalMinor,
        tenderedMinor: submitted.grandTotalMinor,
        changeMinor: 0,
        currencyCode: submitted.currencyCode,
        receiptNumber: 'R-1',
        paidAt: _t0,
      );
      final receipt = buildReceiptDocument(l10n, submitted, payment, isDemo: false);
      final receiptItems = [
        for (final line in receipt.lines)
          if (line.kind == PrintLineKind.item) line.left,
      ];
      expect(receiptItems, const ['1 × Burger B', '1 × Burger A', '2 × Fries']);
      final receiptText = [for (final line in receipt.lines) line.left ?? ''];
      expect(receiptText.where((t) => t.contains('no onion')), hasLength(1));
      expect(receiptText.where((t) => t.contains('well done')), hasLength(1));
      expect(
        receipt.lines.any(
          (l) => l.kind == PrintLineKind.item && (l.right ?? '').isNotEmpty,
        ),
        isTrue,
      );
      expect(submitted.grandTotalMinor, isA<int>());
      final kitchenText = [
        for (final line in kitchen.lines) '${line.left ?? ''} ${line.right ?? ''}',
      ];
      expect(
        kitchenText.any((t) => t.contains('ILS') || t.contains('₪')),
        isFalse,
      );
    },
  );
}
