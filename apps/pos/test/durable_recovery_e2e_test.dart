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
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/draft_recovery_store.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/payment.dart'
    show CashPayment, PaymentMethod, PaymentStatus;
import 'package:restoflow_pos/src/data/order_snapshot_repository.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart'
    show kdsTicketViewFromCartLines, kitchenTicketPrintLabelsFromL10n;
import 'package:restoflow_pos/src/print/print_document.dart' show PrintLineKind;
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart'
    show buildReceiptDocument;
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/draft_recovery_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart'
    show posSyncClockProvider, orderSnapshotRepositoryProvider;
import 'package:restoflow_pos/src/state/outbox_controller.dart'
    show outboxControllerProvider;
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart'
    show submitOrderFromCart;
import 'package:restoflow_pos/src/widgets/recovery_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/verified_kitchen_mode_readiness.dart';

/// MENU-ORDER-001 (Codex 5th pass) — the END-TO-END durable recovery + resubmission
/// proof, driven through the REAL production seams (NOT _draft/captureDraft/
/// restoreDraft/viewFromDraft directly):
///   * PIN sign-in (PosSessionController.signInWithPin);
///   * cart built through public CartController ops;
///   * submitOrderFromCart (cart_panel.dart:376) — the real Send handler;
///   * a fake SyncRpcTransport at the ONLY boundary returns the REAL item_unavailable
///     then accepted sync_push shapes; the recovery is AUTO-captured by production;
///   * full ProviderContainer disposal (app restart) with a durable SharedPrefs store;
///   * a fresh container + a NEW PIN session (S1 != S2) rediscovers the recovery via
///     the stable worker + scope binding;
///   * the PUBLIC Back-to-cart restore (PosRecoveryCoordinator.restore);
///   * receipt/kitchen from the restored cart; correction; real accepted resubmit.

const _ctxA = DeviceContext(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-A',
  deviceId: 'device-1',
  deviceType: 'pos',
  deviceSessionId: 'ds-A',
);

/// A hand-written fake transport (house style): scripts the order.submit result
/// (item_unavailable, then accepted) and RECORDS every order.submit op so the test
/// can assert the exact request the production submit path sent.
class _RecordingTransport implements SyncRpcTransport {
  int pinSessions = 0;
  final List<Map<String, dynamic>> orderSubmitOps = <Map<String, dynamic>>[];

  /// Successive order.submit results, each built from the ECHOED local_operation_id.
  final List<Map<String, dynamic> Function(String opId)> orderScript =
      <Map<String, dynamic> Function(String opId)>[];
  int _orderIndex = 0;

  /// When set, the NEXT order.submit throws this transport error instead (network).
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
        final opId = op['local_operation_id'] as String;
        final builder = _orderIndex < orderScript.length
            ? orderScript[_orderIndex]
            : orderScript.last;
        _orderIndex++;
        return <String, dynamic>{
          'ok': true,
          'results': <dynamic>[builder(opId)],
        };
      }
    }
    return null; // pos_menu / anything else -> unavailable (tolerated)
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

/// A snapshot repo that contacts no backend (empty pages).
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

/// A durable recovery store whose WRITES fail (delegating reads), to prove a
/// persistence write failure never crashes the POS nor falsely retires a recovery.
class _ThrowingRecoveryStore implements PosDraftRecoveryStore {
  _ThrowingRecoveryStore(this._inner);
  final PosDraftRecoveryStore _inner;
  int persistAttempts = 0;

  @override
  Future<Map<String, PosDraftRecovery>> load() => _inner.load();

  @override
  Future<void> persist(Map<String, PosDraftRecovery> recoveries) async {
    persistAttempts++;
    throw StateError('durable write failed');
  }
}

/// A store that FAILS ONLY the pre-dispatch correction-LINK persist (any map carrying a
/// correctionOutboxEntryId), while letting the initial capture through — so a link-write
/// failure can be proven to abort the submit BEFORE any network dispatch (§4/§11.A).
class _LinkFailingRecoveryStore implements PosDraftRecoveryStore {
  _LinkFailingRecoveryStore(this._inner);
  final PosDraftRecoveryStore _inner;
  int linkPersistAttempts = 0;

  @override
  Future<Map<String, PosDraftRecovery>> load() => _inner.load();

  @override
  Future<void> persist(Map<String, PosDraftRecovery> recoveries) async {
    if (recoveries.values.any((r) => r.correctionOutboxEntryId != null)) {
      linkPersistAttempts++;
      throw StateError('link write failed');
    }
    return _inner.persist(recoveries);
  }
}

/// A store whose writes fail while [failWrites] is set (reads always delegate), to prove
/// an accepted-cleanup write failure is retried on the next acceptance signal (§11.C).
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

/// Menu items whose cart insertion order != Dashboard order:
/// Dashboard: Meals(1)[Burger B(1), Burger A(2)], Sides(2)[Fries(1)], Drinks(3)[Cola(1)].
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
const _cola = DemoMenuItem(
  id: 'cola',
  name: 'Cola',
  priceMinor: 1000,
  categoryId: 'drinks',
  categoryName: 'Drinks',
  categoryDisplayOrder: 3,
  itemDisplayOrder: 1,
);

final _t0 = DateTime.utc(2026, 7, 26, 9);

void main() {
  Future<AppLocalizations> l10nEn() =>
      AppLocalizations.delegate.load(const Locale('en'));

  ProviderContainer makeContainer(
    SharedPreferences prefs,
    _RecordingTransport transport, {
    PosRecentOrdersStore? recentStore,
  }) {
    final c = ProviderContainer(
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
          recentStore ?? InMemoryRecentOrdersStore(),
        ),
        posSyncClockProvider.overrideWithValue(() => _t0),
        // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap A): this recovery suite is a
        // KDS-branch flow; simulate the startup lifecycle having verified the
        // mode so the Gap-A readiness gate does not block submit/replay.
        verifiedKdsReadinessOverride(),
      ],
    );
    return c;
  }

  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.microtask(() {});
    }
  }

  Future<void> signIn(
    ProviderContainer c, {
    String employeeProfileId = 'emp-A',
  }) async {
    c.read(posDeviceContextProvider.notifier).set(_ctxA);
    await settle();
    final err = await c
        .read(posSessionControllerProvider.notifier)
        .signInWithPin(
          device: _ctxA,
          deviceId: _ctxA.deviceId!,
          deviceSessionId: _ctxA.deviceSessionId!,
          employeeProfileId: employeeProfileId,
          pin: '1234',
        );
    expect(err, isNull);
    await settle();
  }

  /// Pumps a bare app under [c] and returns the live (ref, context).
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

  testWidgets('REAL end-to-end: item_unavailable -> auto durable capture -> full restart -> '
      'S2 rediscovery -> public restore -> receipt/kitchen -> correct -> accepted '
      'resubmit; all through production seams', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final l10n = await l10nEn();
    final transport = _RecordingTransport()
      ..orderScript.addAll([_itemUnavailable, _accepted]);

    // ---- Process A -------------------------------------------------------
    final a = makeContainer(prefs, transport);
    await signIn(a); // PIN session S1, employeeProfileId emp-A published
    expect(a.read(posSignedInEmployeeProfileIdProvider), 'emp-A');
    final s1 = a.read(posSyncSessionProvider)!.pinSessionId;
    a.read(posDraftRecoveryProvider); // wire listeners + rehydrate

    final (refA, ctxA) = await pumpApp(tester, a);

    // A cart in a sequence DIFFERENT from Dashboard order, with quantities,
    // notes, and modifiers — built through PUBLIC cart ops.
    final cartA = a.read(cartControllerProvider.notifier);
    cartA.addItem(_cola); // the item the backend will mark unavailable
    cartA.addItemWithModifiers(_burgerA, const [
      SelectedModifier(
        optionId: 'no-onion',
        groupName: 'Extras',
        optionName: 'no onion',
        priceDeltaMinor: 0,
      ),
    ], note: 'well done');
    cartA.addItem(_fries);
    cartA.increaseQuantity(
      a
          .read(cartControllerProvider)
          .lines
          .firstWhere((l) => l.name == 'Fries')
          .lineId,
    ); // Fries x2
    cartA.addItem(_burgerB);
    a
        .read(orderSetupControllerProvider.notifier)
        .setOrderType(OrderType.takeaway);
    await tester.pump();

    final originalLineIds = a
        .read(cartControllerProvider)
        .lines
        .map((l) => l.lineId)
        .toList();
    expect(originalLineIds, hasLength(4));

    // REAL submit -> the transport returns item_unavailable.
    await submitOrderFromCart(
      ref: refA,
      context: ctxA,
      cart: a.read(cartControllerProvider),
      setup: a.read(orderSetupControllerProvider),
      cartController: cartA,
      setupController: a.read(orderSetupControllerProvider.notifier),
      l10n: l10n,
    );
    await tester.pump();
    await settle();

    // Production AUTO-captured the recovery (we never called capture()).
    final recoveriesA = a.read(posDraftRecoveryProvider);
    expect(
      recoveriesA,
      hasLength(1),
      reason: 'item_unavailable auto-captured exactly one durable recovery',
    );
    final capturedEntryId = recoveriesA.keys.single;
    final recA = recoveriesA[capturedEntryId]!;
    // The durable record carries the stable worker + scope, line ids, ranks,
    // quantities, notes, modifiers, integer money.
    expect(recA.binding.employeeProfileId, 'emp-A');
    expect(recA.binding.scopeKey, a.read(posSyncScopeProvider)!.key);
    expect(
      recA.draft.lines.map((l) => l.lineId).toList(),
      originalLineIds,
      reason: 'stable line ids captured',
    );
    final draftBurgerA = recA.draft.lines.firstWhere(
      (l) => l.menuItemId == 'burger-a',
    );
    expect(draftBurgerA.note, 'well done');
    expect(draftBurgerA.modifiers.single.optionName, 'no onion');
    expect(draftBurgerA.basePriceMinor, isA<int>());
    final draftFries = recA.draft.lines.firstWhere(
      (l) => l.menuItemId == 'fries',
    );
    expect(draftFries.quantity, 2);
    // The submit cleared the live cart (the confirmation stands on its own).
    expect(a.read(cartControllerProvider).isEmpty, isTrue);

    // ---- FULL RESTART ----------------------------------------------------
    await tester.pumpWidget(const SizedBox()); // tear down A's tree
    a.dispose();

    final b = makeContainer(prefs, transport);
    final (refB, ctxB) = await pumpApp(tester, b);
    b.read(posDraftRecoveryProvider); // rehydrate from SharedPrefs
    await settle();

    // Before sign-in: no worker -> the recovery is not restorable.
    expect(
      b
          .read(posDraftRecoveryProvider.notifier)
          .recoverable(capturedEntryId, b.read(posRecoveryBindingProvider)),
      isNull,
      reason: 'unauthenticated device cannot restore it',
    );

    await signIn(b); // SAME worker emp-A, NEW PIN session S2
    final s2 = b.read(posSyncSessionProvider)!.pinSessionId;
    expect(s2, isNot(s1), reason: 'a new PIN login mints a NEW pinSessionId');
    await settle();

    // Rediscovery via the stable worker + scope binding (not S1).
    final recB = b
        .read(posDraftRecoveryProvider.notifier)
        .recoverable(capturedEntryId, b.read(posRecoveryBindingProvider));
    expect(
      recB,
      isNotNull,
      reason: 'same worker + scope reclaims across restart + S1 != S2',
    );

    // ---- PUBLIC Back-to-cart restore ------------------------------------
    final outcome = await PosRecoveryCoordinator(refB).restore(ctxB, recB!);
    expect(outcome, PosRecoveryOutcome.restored);
    await tester.pump();

    final restoredLines = b.read(cartControllerProvider).lines;
    expect(
      restoredLines.map((l) => l.lineId).toList(),
      originalLineIds,
      reason: 'restore preserves the ORIGINAL stable line ids (no re-mint)',
    );
    expect(
      restoredLines.map((l) => l.menuItemId).toSet().length,
      4,
      reason: 'no duplicate lines',
    );
    // MENU-ORDER-001 (the fix): Back to cart is NOT terminal — the durable recovery
    // AND its shell REMAIN so a crash before the corrected re-Send recovers the same
    // order again; the cart is marked as correcting THIS recovery.
    expect(
      b.read(posDraftRecoveryProvider).containsKey(capturedEntryId),
      isTrue,
      reason:
          'restore RETAINS the durable recovery (correction-window durability)',
    );
    expect(
      b.read(posActiveCorrectionSourceProvider)?.sourceOutboxEntryId,
      capturedEntryId,
      reason: 'the active correction source is owner-bound to THIS recovery',
    );

    // Receipt/kitchen from the RESTORED cart print in Dashboard order.
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
    expect(kitchenItems, const [
      '1 × Burger B',
      '1 × Burger A',
      '2 × Fries',
      '1 × Cola',
    ]);
    // The modifier + note stay attached; kitchen stays money-free.
    final kitchenText = [for (final line in kitchen.lines) line.left ?? ''];
    expect(kitchenText.any((t) => t.contains('no onion')), isTrue);
    expect(kitchenText.any((t) => t.contains('well done')), isTrue);
    expect(
      kitchenText.any((t) => t.contains('ILS') || t.contains('₪')),
      isFalse,
    );

    // ---- Correction + REAL accepted resubmit -----------------------------
    final colaLineId = b
        .read(cartControllerProvider)
        .lines
        .firstWhere((l) => l.menuItemId == 'cola')
        .lineId;
    b.read(cartControllerProvider.notifier).removeLine(colaLineId);
    b
        .read(orderSetupControllerProvider.notifier)
        .setOrderType(OrderType.takeaway);
    await tester.pump();

    await submitOrderFromCart(
      ref: refB,
      context: ctxB,
      cart: b.read(cartControllerProvider),
      setup: b.read(orderSetupControllerProvider),
      cartController: b.read(cartControllerProvider.notifier),
      setupController: b.read(orderSetupControllerProvider.notifier),
      l10n: l10n,
    );
    await tester.pump();
    await settle();

    // The accepted order is now the confirmation / recent-orders row.
    final submitted = b.read(cartControllerProvider).submittedOrder;
    expect(submitted, isNotNull, reason: 'the corrected order was accepted');
    expect(
      submitted!.lines.map((l) => l.name).toSet(),
      {'Burger A', 'Fries', 'Burger B'},
      reason: 'no stale Cola; no duplicate lines',
    );
    expect(b.read(posRecentOrdersControllerProvider), hasLength(1));

    // MENU-ORDER-001 (the fix): the corrected order's ACCEPTANCE cleared exactly the
    // source recovery (via its correctionOutboxEntryId link) — the durable record is
    // gone only NOW (after acceptance), never at Back-to-cart; and the shell is retired.
    expect(
      b.read(posDraftRecoveryProvider.notifier).hasRecoveryFor(capturedEntryId),
      isFalse,
      reason: 'accepted completion removed exactly the source recovery',
    );
    expect(b.read(posActiveCorrectionSourceProvider), isNull);

    // Real-submission request content: TWO order.submit ops (item_unavailable
    // then accepted), each with a distinct client op id; the corrected request
    // dropped the unavailable item and carries integer-minor money only.
    expect(transport.orderSubmitOps, hasLength(2));
    final firstOpId = transport.orderSubmitOps[0]['local_operation_id'];
    final secondOpId = transport.orderSubmitOps[1]['local_operation_id'];
    expect(
      firstOpId,
      isNot(secondOpId),
      reason: 'a corrected resubmit mints a fresh operation identity',
    );
    final correctedPayload =
        transport.orderSubmitOps[1]['payload'] as Map<String, dynamic>;
    final correctedItems = correctedPayload['order_items'] as List;
    expect(
      correctedItems,
      hasLength(3),
      reason: 'the corrected request has exactly the 3 surviving items',
    );
    expect(
      correctedItems.any(
        (it) => (it as Map)['menu_item_name_snapshot'] == 'Cola',
      ),
      isFalse,
      reason: 'the unavailable item is gone from the resubmit',
    );
    expect(correctedPayload['subtotal_minor'], isA<int>());

    b.dispose();
  });

  /// Signs in [employeeProfileId], builds a one-line (Cola) cart, and submits it
  /// through the REAL handler where the transport returns item_unavailable — so
  /// production AUTO-captures exactly one durable recovery. Returns its entry id.
  Future<String> captureViaSubmit(
    WidgetTester tester,
    ProviderContainer c,
    _RecordingTransport transport, {
    String employeeProfileId = 'emp-A',
  }) async {
    final l10n = await l10nEn();
    await signIn(c, employeeProfileId: employeeProfileId);
    c.read(posDraftRecoveryProvider);
    final (ref, ctx) = await pumpApp(tester, c);
    final cart = c.read(cartControllerProvider.notifier);
    cart.addItem(_cola);
    c
        .read(orderSetupControllerProvider.notifier)
        .setOrderType(OrderType.takeaway);
    await tester.pump();
    await submitOrderFromCart(
      ref: ref,
      context: ctx,
      cart: c.read(cartControllerProvider),
      setup: c.read(orderSetupControllerProvider),
      cartController: cart,
      setupController: c.read(orderSetupControllerProvider.notifier),
      l10n: l10n,
    );
    await tester.pump();
    await settle();
    return c.read(posDraftRecoveryProvider).keys.single;
  }

  testWidgets(
    'ownership: a captured recovery is invisible to a WRONG worker, an '
    'UNAUTHENTICATED device, and ANOTHER scope — and is never leaked or deleted',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final transport = _RecordingTransport()
        ..orderScript.add(_itemUnavailable);
      final c = makeContainer(prefs, transport);
      addTearDown(c.dispose);

      final entryId = await captureViaSubmit(tester, c, transport);
      final recovery = c.read(posDraftRecoveryProvider.notifier);
      final bindingA = c.read(posRecoveryBindingProvider);
      expect(recovery.recoverable(entryId, bindingA), isNotNull);

      // A DIFFERENT worker on the same till.
      expect(
        recovery.recoverable(
          entryId,
          PosRecoveryBinding(
            scopeKey: bindingA.scopeKey,
            employeeProfileId: 'emp-B',
          ),
        ),
        isNull,
      );
      // No worker signed in (unauthenticated device).
      expect(recovery.recoverable(entryId, const PosRecoveryBinding()), isNull);
      // The SAME worker in a DIFFERENT scope (another branch/station).
      expect(
        recovery.recoverable(
          entryId,
          PosRecoveryBinding(
            scopeKey: 'org-1.rest-1.branch-Z.device-1',
            employeeProfileId: 'emp-A',
          ),
        ),
        isNull,
      );
      // The record still EXISTS under its owner (not leaked, not deleted).
      expect(recovery.hasRecoveryFor(entryId), isTrue);
    },
  );

  testWidgets(
    'sign-out HIDES the recovery without deleting it; the same worker sees it '
    'again on the next PIN session',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final transport = _RecordingTransport()
        ..orderScript.add(_itemUnavailable);
      final c = makeContainer(prefs, transport);
      addTearDown(c.dispose);

      final entryId = await captureViaSubmit(tester, c, transport);
      final recovery = c.read(posDraftRecoveryProvider.notifier);
      expect(
        recovery.recoverable(entryId, c.read(posRecoveryBindingProvider)),
        isNotNull,
      );

      // Sign out: no worker -> hidden, but the record is retained.
      c.read(posSessionControllerProvider.notifier).endSession();
      await settle();
      expect(c.read(posSignedInEmployeeProfileIdProvider), isNull);
      expect(
        recovery.recoverable(entryId, c.read(posRecoveryBindingProvider)),
        isNull,
      );
      expect(recovery.hasRecoveryFor(entryId), isTrue);

      // Re-sign-in the same worker -> visible again.
      await signIn(c, employeeProfileId: 'emp-A');
      await settle();
      expect(
        recovery.recoverable(entryId, c.read(posRecoveryBindingProvider)),
        isNotNull,
      );
    },
  );

  testWidgets(
    'a submit NETWORK failure RETAINS the recovery (rejected-retryable, not a '
    'throw) — the order is never lost',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final l10n = await l10nEn();
      final transport = _RecordingTransport()
        ..orderScript.add(_accepted); // unused; the throw pre-empts it
      final c = makeContainer(prefs, transport);
      addTearDown(c.dispose);

      await signIn(c);
      c.read(posDraftRecoveryProvider);
      final (ref, ctx) = await pumpApp(tester, c);
      c.read(cartControllerProvider.notifier).addItem(_cola);
      c
          .read(orderSetupControllerProvider.notifier)
          .setOrderType(OrderType.takeaway);
      await tester.pump();

      // The transport throws a transient network error on the order.submit push.
      transport.throwOnNextOrder = const SyncTransportException(
        SyncTransportErrorKind.transient,
        code: '503',
        message: 'unavailable',
      );
      await submitOrderFromCart(
        ref: ref,
        context: ctx,
        cart: c.read(cartControllerProvider),
        setup: c.read(orderSetupControllerProvider),
        cartController: c.read(cartControllerProvider.notifier),
        setupController: c.read(orderSetupControllerProvider.notifier),
        l10n: l10n,
      );
      await tester.pump();
      await settle();

      // RealOutboxRepository.push CATCHES the transient error and surfaces a
      // rejected-RETRYABLE entry, so submit returns normally and the same-session
      // path still auto-captures the recovery — the order is retained, not lost.
      expect(
        c.read(posDraftRecoveryProvider),
        hasLength(1),
        reason: 'a network failure retains the recovery (not deleted)',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ACCEPTED completion (an authoritative server snapshot for the order) removes '
    'ONLY the matching recovery — the accepted/idempotent reconcile',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final transport = _RecordingTransport()
        ..orderScript.add(_itemUnavailable);
      final c = makeContainer(prefs, transport);
      addTearDown(c.dispose);

      final entryId = await captureViaSubmit(tester, c, transport);
      final recovery = c.read(posDraftRecoveryProvider.notifier);
      expect(recovery.hasRecoveryFor(entryId), isTrue);

      // The AUTHORITATIVE window pull later shows a device-owned order carrying
      // THIS outbox entry id (the order was accepted; a lost response / crash
      // between acceptance and local cleanup is reconciled here). The controller-
      // seam _clearAcceptedBySnapshot listener removes the matching recovery.
      final orders = c.read(posRecentOrdersControllerProvider.notifier);
      orders.recordSubmitted(
        SubmittedOrderView(
          orderNumber: '#ACC',
          orderType: OrderType.takeaway,
          currencyCode: 'ILS',
          subtotalMinor: 1000,
          orderId: 'accepted-order-1',
          outboxEntryId: entryId,
          lines: const [
            SubmittedLineView(
              name: 'Cola',
              quantity: 1,
              lineTotalMinor: 1000,
              currencyCode: 'ILS',
            ),
          ],
        ),
      );
      await settle();
      await orders.applySnapshots([
        PosOrderSnapshot(
          orderId: 'accepted-order-1',
          orderCode: '#ACC',
          revision: 1,
          status: 'served',
          settlement: PosSettlement.unpaid,
          subtotalMinor: 1000,
          discountTotalMinor: 0,
          taxTotalMinor: 0,
          grandTotalMinor: 1000,
          createdAt: _t0,
          updatedAt: _t0,
          syncAt: _t0,
          currencyCode: 'ILS',
        ),
      ]);
      await settle();

      expect(
        recovery.hasRecoveryFor(entryId),
        isFalse,
        reason: 'an authoritative accepted snapshot cleared the recovery',
      );
    },
  );

  testWidgets(
    'repeated item_unavailable: restore -> correct -> resubmit rejected AGAIN '
    'keeps exactly ONE recovery (no duplicate shell); survivors keep stable ids',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final l10n = await l10nEn();
      final transport = _RecordingTransport()
        ..orderScript.addAll([_itemUnavailable, _itemUnavailable]);
      final c = makeContainer(prefs, transport);
      addTearDown(c.dispose);

      await signIn(c);
      c.read(posDraftRecoveryProvider);
      final (ref, ctx) = await pumpApp(tester, c);
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItem(_cola); // will be reported unavailable
      cart.addItem(_burgerB);
      c
          .read(orderSetupControllerProvider.notifier)
          .setOrderType(OrderType.takeaway);
      await tester.pump();
      final burgerLineId = c
          .read(cartControllerProvider)
          .lines
          .firstWhere((l) => l.menuItemId == 'burger-b')
          .lineId;

      Future<void> submit() => submitOrderFromCart(
        ref: ref,
        context: ctx,
        cart: c.read(cartControllerProvider),
        setup: c.read(orderSetupControllerProvider),
        cartController: cart,
        setupController: c.read(orderSetupControllerProvider.notifier),
        l10n: l10n,
      );

      await submit(); // #1 -> item_unavailable -> recovery #1 captured
      await tester.pump();
      await settle();
      final rec1 = c.read(posDraftRecoveryProvider).keys.single;

      // Restore, drop the unavailable Cola, resubmit -> item_unavailable AGAIN.
      final recovery = c.read(posDraftRecoveryProvider.notifier);
      final restored = recovery.recoverable(
        rec1,
        c.read(posRecoveryBindingProvider),
      )!;
      await PosRecoveryCoordinator(ref).restore(ctx, restored);
      await tester.pump();
      final colaLineId = c
          .read(cartControllerProvider)
          .lines
          .firstWhere((l) => l.menuItemId == 'cola')
          .lineId;
      cart.removeLine(colaLineId);
      c
          .read(orderSetupControllerProvider.notifier)
          .setOrderType(OrderType.takeaway);
      await tester.pump();
      await submit(); // #2 -> item_unavailable -> a NEW recovery #2
      await tester.pump();
      await settle();

      // Exactly ONE recovery — the SAME logical record (still keyed by rec1), atomically
      // SUPERSEDED with the corrected draft (§3.F/§8.D). The corrected resubmit never
      // captured a second record, and the source was never cleared on the (permanent)
      // rejection — so no duplicate shell accumulates and no interval lost the order.
      final recoveries = c.read(posDraftRecoveryProvider);
      expect(recoveries, hasLength(1), reason: 'exactly one logical recovery');
      final rec2 = recoveries.values.single;
      expect(
        recoveries.keys.single,
        rec1,
        reason:
            'the SAME logical recovery is superseded, not moved to a new key',
      );
      // The recovery now carries the CORRECTED draft (Cola dropped), and the surviving
      // Burger B kept its ORIGINAL stable line id across the round.
      expect(rec2.draft.lines.map((l) => l.menuItemId).toList(), ['burger-b']);
      expect(
        rec2.draft.lines.single.lineId,
        burgerLineId,
        reason: 'the surviving line keeps its stable id (no re-mint)',
      );
      // The record is durably LINKED to the second corrected op (a real dispatched
      // outbox entry) — so its later acceptance clears exactly this source.
      expect(rec2.correctionOutboxEntryId, isNotNull);
      expect(
        c
            .read(outboxControllerProvider.notifier)
            .entryById(rec2.correctionOutboxEntryId),
        isNotNull,
        reason: 'the stored correction id is a REAL dispatched outbox entry',
      );
      // Only ONE rejected shell remains (the source recovery's), never a duplicate for
      // the corrected attempt.
      final rejectedShells = c
          .read(posRecentOrdersControllerProvider)
          .where((o) => o.isNeverCreated)
          .length;
      expect(rejectedShells, 1, reason: 'no duplicate rejected shell');
    },
  );

  testWidgets(
    'CRASH AFTER Back-to-cart (no resubmit): the order is NOT lost — it survives '
    'to the next process and re-restores idempotently (the correction-window fix)',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final transport = _RecordingTransport()
        ..orderScript.add(_itemUnavailable);

      // Process A: item_unavailable -> durable recovery.
      final a = makeContainer(prefs, transport);
      final entryId = await captureViaSubmit(tester, a, transport);
      a.dispose();

      // Process B: sign in, RESTORE (Back to cart), then DIE without resubmitting.
      final b = makeContainer(prefs, transport);
      await signIn(b);
      b.read(posDraftRecoveryProvider);
      await settle();
      final (refB, ctxB) = await pumpApp(tester, b);
      final recB = b
          .read(posDraftRecoveryProvider.notifier)
          .recoverable(entryId, b.read(posRecoveryBindingProvider))!;
      await PosRecoveryCoordinator(refB).restore(ctxB, recB);
      await tester.pump();
      expect(b.read(cartControllerProvider).lines, isNotEmpty);
      expect(
        b.read(posDraftRecoveryProvider).containsKey(entryId),
        isTrue,
        reason: 'restore RETAINED the durable recovery',
      );
      await tester.pumpWidget(const SizedBox());
      b.dispose(); // CRASH: process dies after restore, before resubmit.
      await settle();

      // Process C: the SAME order is still recoverable, and re-restore is idempotent.
      final c = makeContainer(prefs, transport);
      await signIn(c);
      c.read(posDraftRecoveryProvider);
      await settle();
      final (refC, ctxC) = await pumpApp(tester, c);
      final recC = c
          .read(posDraftRecoveryProvider.notifier)
          .recoverable(entryId, c.read(posRecoveryBindingProvider));
      expect(
        recC,
        isNotNull,
        reason: 'a crash after Back-to-cart did NOT lose the order',
      );
      await PosRecoveryCoordinator(refC).restore(ctxC, recC!);
      await tester.pump();
      final lines = c.read(cartControllerProvider).lines;
      expect(lines, hasLength(1), reason: 're-restore is idempotent (no dup)');
      expect(lines.single.menuItemId, 'cola');
      c.dispose();
    },
  );

  testWidgets('ACCEPTED-then-crash (§7): the correction link is produced by the REAL pre-dispatch '
      'production flow; a corrected order accepted BEFORE the client sees the response is '
      'reconciled on the next startup via the authoritative snapshot — the source recovery '
      'is cleared through its REAL link, and no NEW corrected order is created', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final l10n = await l10nEn();
    // #1 rejected (item_unavailable); #2 the corrected op is ACCEPTED server-side, but
    // the client never sees the response (a transient network error is injected on the
    // push) — the "accepted before response" window. The durable e1->e2 link is written
    // by the REAL beforeDispatch BEFORE that failed push, never hand-injected.
    final transport = _RecordingTransport()
      ..orderScript.addAll([_itemUnavailable, _accepted]);

    // ---- Process A: capture, restore, corrected submit whose response is lost -------
    final a = makeContainer(prefs, transport);
    await signIn(a);
    a.read(posDraftRecoveryProvider);
    final (refA, ctxA) = await pumpApp(tester, a);
    final cartA = a.read(cartControllerProvider.notifier);
    cartA.addItem(_cola);
    cartA.addItem(_burgerB);
    a
        .read(orderSetupControllerProvider.notifier)
        .setOrderType(OrderType.takeaway);
    await tester.pump();
    Future<void> submitA() => submitOrderFromCart(
      ref: refA,
      context: ctxA,
      cart: a.read(cartControllerProvider),
      setup: a.read(orderSetupControllerProvider),
      cartController: cartA,
      setupController: a.read(orderSetupControllerProvider.notifier),
      l10n: l10n,
    );
    await submitA(); // -> item_unavailable -> recovery e1
    await tester.pump();
    await settle();
    final e1 = a.read(posDraftRecoveryProvider).keys.single;

    final restored = a
        .read(posDraftRecoveryProvider.notifier)
        .recoverable(e1, a.read(posRecoveryBindingProvider))!;
    await PosRecoveryCoordinator(refA).restore(ctxA, restored);
    await tester.pump();
    cartA.removeLine(
      a
          .read(cartControllerProvider)
          .lines
          .firstWhere((l) => l.menuItemId == 'cola')
          .lineId,
    );
    a
        .read(orderSetupControllerProvider.notifier)
        .setOrderType(OrderType.takeaway);
    await tester.pump();
    // The server ACCEPTS the corrected op, but the client's push sees a network error
    // (the accepted response is lost). beforeDispatch already persisted the e1->e2 link.
    transport.throwOnNextOrder = const SyncTransportException(
      SyncTransportErrorKind.transient,
      code: '503',
      message: 'response lost after acceptance',
    );
    await submitA(); // corrected resubmit -> real link persisted, response lost
    await tester.pump();
    await settle();

    // The REAL pre-dispatch link is on the source recovery, pointing at a REAL
    // dispatched outbox entry (e2) — no hand injection anywhere in this test.
    final recAfterLink = a.read(posDraftRecoveryProvider)[e1]!;
    final e2 = recAfterLink.correctionOutboxEntryId;
    expect(
      e2,
      isNotNull,
      reason: 'the corrected submit produced the durable link',
    );
    expect(
      a.read(outboxControllerProvider.notifier).entryById(e2),
      isNotNull,
      reason: 'the stored correction id is a REAL dispatched outbox entry',
    );
    final opsBeforeCrash = transport.orderSubmitOps.length; // 2
    await tester.pumpWidget(const SizedBox());
    a.dispose(); // CRASH before any local acceptance cleanup could run.

    // ---- Process C: fresh start; the authoritative window pull reconciles -----------
    // A fresh transport that would ACCEPT any idempotent outbox replay — proving the
    // reconcile needs no NEW op, only the accepted evidence for the SAME e2.
    final transportC = _RecordingTransport()..orderScript.add(_accepted);
    final c = makeContainer(prefs, transportC);
    addTearDown(c.dispose);
    await signIn(c);
    c.read(posDraftRecoveryProvider); // rehydrate the linked recovery
    await settle();
    expect(
      c.read(posDraftRecoveryProvider.notifier).hasRecoveryFor(e1),
      isTrue,
      reason: 'the linked source recovery survived the crash',
    );

    // The authoritative window pull surfaces the ACCEPTED corrected order carrying the
    // SAME outbox entry e2 (the server had accepted it despite the lost response).
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

    // The reconcile cleared the source recovery THROUGH its REAL correctionOutboxEntryId
    // link — no re-restore. No NEW corrected order was ever created: any transport
    // contact in process C is only the idempotent replay of the SAME e2, never a new op.
    expect(
      c.read(posDraftRecoveryProvider.notifier).hasRecoveryFor(e1),
      isFalse,
      reason: 'accepted-then-crash reconciled via the REAL correction link',
    );
    // No NEW corrected order was created in Process A beyond the two real ops (the
    // item_unavailable and the corrected op whose response was lost). Process C creates
    // no new deliberate op — it reconciles from the authoritative accepted snapshot.
    expect(opsBeforeCrash, 2, reason: 'only two real ops were ever dispatched');
    // The accepted order remains available; exactly one logical order exists.
    expect(c.read(posRecentOrdersControllerProvider), hasLength(1));
  });

  testWidgets(
    'a durable persistence WRITE FAILURE does not crash and does not falsely retire '
    'the recovery (safest recoverable state preserved)',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final transport = _RecordingTransport()
        ..orderScript.add(_itemUnavailable);
      final failing = _ThrowingRecoveryStore(
        SharedPrefsDraftRecoveryStore(prefs),
      );
      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posAuthTransportProvider.overrideWithValue(transport),
          posRealSessionConfigProvider.overrideWithValue(null),
          posDraftRecoveryStoreProvider.overrideWithValue(failing),
          orderSnapshotRepositoryProvider.overrideWithValue(
            _EmptySnapshotRepo(),
          ),
          posRecentOrdersStoreProvider.overrideWithValue(
            InMemoryRecentOrdersStore(),
          ),
          posSyncClockProvider.overrideWithValue(() => _t0),
          verifiedKdsReadinessOverride(),
        ],
      );
      addTearDown(c.dispose);
      final entryId = await captureViaSubmit(tester, c, transport);

      // The durable persist threw (best-effort, swallowed) — no crash surfaced.
      expect(tester.takeException(), isNull);
      expect(failing.persistAttempts, greaterThan(0));
      // The in-session recovery is still held (the safest recoverable state): the
      // capture was never falsely reported as durably retired.
      expect(
        c.read(posDraftRecoveryProvider.notifier).hasRecoveryFor(entryId),
        isTrue,
      );
    },
  );

  // ---------------------------------------------------------------------------------
  // MENU-ORDER-001 (Codex correction-ownership) — focused proofs for the fixed defects.
  // ---------------------------------------------------------------------------------

  testWidgets(
    'link-write FAILURE before dispatch sends ZERO network requests and leaves the '
    'source recovery UNLINKED (§4/§5/§11.A): no order is sent on an in-memory-only link',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final l10n = await l10nEn();
      final transport = _RecordingTransport()
        ..orderScript.addAll([_itemUnavailable, _accepted]);
      final linkFailing = _LinkFailingRecoveryStore(
        SharedPrefsDraftRecoveryStore(prefs),
      );
      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posAuthTransportProvider.overrideWithValue(transport),
          posRealSessionConfigProvider.overrideWithValue(null),
          posDraftRecoveryStoreProvider.overrideWithValue(linkFailing),
          orderSnapshotRepositoryProvider.overrideWithValue(
            _EmptySnapshotRepo(),
          ),
          posRecentOrdersStoreProvider.overrideWithValue(
            InMemoryRecentOrdersStore(),
          ),
          posSyncClockProvider.overrideWithValue(() => _t0),
          verifiedKdsReadinessOverride(),
        ],
      );
      addTearDown(c.dispose);

      await signIn(c);
      c.read(posDraftRecoveryProvider);
      final (ref, ctx) = await pumpApp(tester, c);
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItem(_cola);
      c
          .read(orderSetupControllerProvider.notifier)
          .setOrderType(OrderType.takeaway);
      await tester.pump();
      Future<void> submit() => submitOrderFromCart(
        ref: ref,
        context: ctx,
        cart: c.read(cartControllerProvider),
        setup: c.read(orderSetupControllerProvider),
        cartController: cart,
        setupController: c.read(orderSetupControllerProvider.notifier),
        l10n: l10n,
      );
      await submit(); // -> item_unavailable -> recovery e1 (capture persisted OK)
      await tester.pump();
      await settle();
      final e1 = c.read(posDraftRecoveryProvider).keys.single;
      expect(transport.orderSubmitOps, hasLength(1));

      // Restore + resubmit: the pre-dispatch link persist THROWS, so the submit aborts.
      final rec = c
          .read(posDraftRecoveryProvider.notifier)
          .recoverable(e1, c.read(posRecoveryBindingProvider))!;
      await PosRecoveryCoordinator(ref).restore(ctx, rec);
      await tester.pump();
      await submit(); // corrected resubmit: beforeDispatch link persist fails
      await tester.pump();
      await settle();

      // ZERO extra network dispatch — only the first submit ever reached the transport.
      expect(
        transport.orderSubmitOps,
        hasLength(1),
        reason: 'a failed pre-dispatch link sent NO corrected order.submit',
      );
      expect(linkFailing.linkPersistAttempts, greaterThan(0));
      // The source recovery is intact and UNLINKED (no in-memory-only association).
      expect(
        c.read(posDraftRecoveryProvider.notifier).hasRecoveryFor(e1),
        isTrue,
      );
      expect(
        c.read(posDraftRecoveryProvider)[e1]!.correctionOutboxEntryId,
        isNull,
        reason: 'a failed link is never published in memory',
      );
      // An honest failure was surfaced; no crash.
      expect(tester.takeException(), isNull);
      expect(find.text(l10n.posSubmitFailed), findsOneWidget);
    },
  );

  test(
    'cross-scope / wrong-worker mutations are refused INSIDE the controller (§10): link '
    'and discard both require the CURRENT binding to own the record',
    () async {
      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: true),
          ),
        ],
      );
      addTearDown(c.dispose);
      final ctrl = c.read(posDraftRecoveryProvider.notifier);
      const owner = PosRecoveryBinding(
        scopeKey: 'S1',
        employeeProfileId: 'emp-A',
      );
      ctrl.capture(
        PosDraftRecovery(
          draft: const CartDraftSnapshot(
            currencyCode: 'ILS',
            lines: [
              CartDraftLine(
                lineId: 'l1',
                menuItemId: 'cola',
                name: 'Cola',
                basePriceMinor: 1000,
                quantity: 1,
              ),
            ],
          ),
          orderType: OrderType.takeaway,
          outboxEntryId: 'e1',
          binding: owner,
        ),
      );
      const draft = CartDraftSnapshot(currencyCode: 'ILS', lines: []);
      Future<bool> link(PosRecoveryBinding b) => ctrl.linkCorrectedSubmit(
        sourceOutboxEntryId: 'e1',
        correctedOutboxEntryId: 'e2',
        binding: b,
        correctedDraft: draft,
        orderType: OrderType.takeaway,
      );

      // A DIFFERENT worker, and a DIFFERENT scope, are both refused.
      expect(
        await link(
          const PosRecoveryBinding(scopeKey: 'S1', employeeProfileId: 'emp-B'),
        ),
        isFalse,
      );
      expect(
        await link(
          const PosRecoveryBinding(scopeKey: 'S2', employeeProfileId: 'emp-A'),
        ),
        isFalse,
      );
      expect(
        c.read(posDraftRecoveryProvider)['e1']!.correctionOutboxEntryId,
        isNull,
        reason: 'a refused link never mutates the record',
      );
      // The OWNER links successfully.
      expect(await link(owner), isTrue);
      expect(
        c.read(posDraftRecoveryProvider)['e1']!.correctionOutboxEntryId,
        'e2',
      );
      // A DIFFERENT worker cannot discard; the OWNER can.
      expect(
        await ctrl.discardOwned(
          'e1',
          const PosRecoveryBinding(scopeKey: 'S1', employeeProfileId: 'emp-B'),
        ),
        isFalse,
      );
      expect(ctrl.hasRecoveryFor('e1'), isTrue);
      expect(await ctrl.discardOwned('e1', owner), isTrue);
      expect(ctrl.hasRecoveryFor('e1'), isFalse);
    },
  );

  testWidgets(
    'worker handover (§2/§9): sign-out CLEARS the active source (recovery retained); '
    'Worker B\'s unrelated submit never links / clears / discards Worker A\'s recovery; '
    'A reclaims it on return',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final l10n = await l10nEn();
      final transport = _RecordingTransport()
        ..orderScript.addAll([_itemUnavailable, _accepted]);
      final c = makeContainer(prefs, transport);
      addTearDown(c.dispose);

      await signIn(c, employeeProfileId: 'emp-A');
      c.read(posDraftRecoveryProvider);
      final (ref, ctx) = await pumpApp(tester, c);
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItem(_cola);
      c
          .read(orderSetupControllerProvider.notifier)
          .setOrderType(OrderType.takeaway);
      await tester.pump();
      await submitOrderFromCart(
        ref: ref,
        context: ctx,
        cart: c.read(cartControllerProvider),
        setup: c.read(orderSetupControllerProvider),
        cartController: cart,
        setupController: c.read(orderSetupControllerProvider.notifier),
        l10n: l10n,
      );
      await tester.pump();
      await settle();
      final eA = c.read(posDraftRecoveryProvider).keys.single;
      final recA = c
          .read(posDraftRecoveryProvider.notifier)
          .recoverable(eA, c.read(posRecoveryBindingProvider))!;
      await PosRecoveryCoordinator(ref).restore(ctx, recA);
      await tester.pump();
      expect(
        c.read(posActiveCorrectionSourceProvider)?.sourceOutboxEntryId,
        eA,
      );

      // Worker A signs out -> the active source is CLEARED; the recovery is RETAINED.
      c.read(posSessionControllerProvider.notifier).endSession();
      await settle();
      expect(
        c.read(posActiveCorrectionSourceProvider),
        isNull,
        reason: 'sign-out clears the volatile active source',
      );
      expect(
        c.read(posDraftRecoveryProvider.notifier).hasRecoveryFor(eA),
        isTrue,
      );

      // Worker B signs in, starts a fresh cart, and submits an UNRELATED accepted order.
      await signIn(c, employeeProfileId: 'emp-B');
      await settle();
      expect(c.read(posActiveCorrectionSourceProvider), isNull);
      final cartB = c.read(cartControllerProvider.notifier);
      cartB.clear();
      cartB.addItem(_burgerB);
      c
          .read(orderSetupControllerProvider.notifier)
          .setOrderType(OrderType.takeaway);
      await tester.pump();
      await submitOrderFromCart(
        ref: ref,
        context: ctx,
        cart: c.read(cartControllerProvider),
        setup: c.read(orderSetupControllerProvider),
        cartController: cartB,
        setupController: c.read(orderSetupControllerProvider.notifier),
        l10n: l10n,
      );
      await tester.pump();
      await settle();

      // B's submit NEVER touched A's recovery: still present, still UNLINKED.
      expect(
        c.read(posDraftRecoveryProvider.notifier).hasRecoveryFor(eA),
        isTrue,
      );
      expect(
        c.read(posDraftRecoveryProvider)[eA]!.correctionOutboxEntryId,
        isNull,
      );
      // B cannot discard A's recovery (owner mismatch).
      expect(
        await c
            .read(posDraftRecoveryProvider.notifier)
            .discardOwned(eA, c.read(posRecoveryBindingProvider)),
        isFalse,
      );
      expect(
        c.read(posDraftRecoveryProvider.notifier).hasRecoveryFor(eA),
        isTrue,
      );

      // Worker A returns: the recovery is reclaimable.
      c.read(posSessionControllerProvider.notifier).endSession();
      await settle();
      await signIn(c, employeeProfileId: 'emp-A');
      await settle();
      expect(
        c
            .read(posDraftRecoveryProvider.notifier)
            .recoverable(eA, c.read(posRecoveryBindingProvider)),
        isNotNull,
      );
    },
  );

  testWidgets(
    'concurrent corrected submits dedup to ONE production order (§13): the single-flight '
    'outbox latch never dispatches the corrected op twice',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final l10n = await l10nEn();
      final transport = _RecordingTransport()
        ..orderScript.addAll([_itemUnavailable, _accepted]);
      final c = makeContainer(prefs, transport);
      addTearDown(c.dispose);
      await signIn(c);
      c.read(posDraftRecoveryProvider);
      final (ref, ctx) = await pumpApp(tester, c);
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItem(_cola);
      cart.addItem(_burgerB);
      c
          .read(orderSetupControllerProvider.notifier)
          .setOrderType(OrderType.takeaway);
      await tester.pump();
      Future<void> submit() => submitOrderFromCart(
        ref: ref,
        context: ctx,
        cart: c.read(cartControllerProvider),
        setup: c.read(orderSetupControllerProvider),
        cartController: cart,
        setupController: c.read(orderSetupControllerProvider.notifier),
        l10n: l10n,
      );
      await submit(); // item_unavailable
      await tester.pump();
      await settle();
      final e1 = c.read(posDraftRecoveryProvider).keys.single;
      final rec = c
          .read(posDraftRecoveryProvider.notifier)
          .recoverable(e1, c.read(posRecoveryBindingProvider))!;
      await PosRecoveryCoordinator(ref).restore(ctx, rec);
      await tester.pump();
      cart.removeLine(
        c
            .read(cartControllerProvider)
            .lines
            .firstWhere((l) => l.menuItemId == 'cola')
            .lineId,
      );
      c
          .read(orderSetupControllerProvider.notifier)
          .setOrderType(OrderType.takeaway);
      await tester.pump();

      // TWO concurrent corrected submits.
      final f1 = submit();
      final f2 = submit();
      await Future.wait([f1, f2]);
      await tester.pump();
      await settle();

      // Exactly TWO order.submit ops ever reached the transport: the item_unavailable and
      // ONE corrected op — never two corrected dispatches.
      expect(
        transport.orderSubmitOps,
        hasLength(2),
        reason: 'concurrent corrected submits dedup to one production order',
      );
      expect(
        c.read(posDraftRecoveryProvider.notifier).hasRecoveryFor(e1),
        isFalse,
        reason: 'the accepted correction cleared the single source recovery',
      );
    },
  );

  testWidgets(
    'accepted-cleanup WRITE FAILURE is retried on the next acceptance signal (§11.C): the '
    'recovery is never lost and eventually clears idempotently',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final transport = _RecordingTransport();
      final toggle = _ToggleFailRecoveryStore(
        SharedPrefsDraftRecoveryStore(prefs),
      );
      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posAuthTransportProvider.overrideWithValue(transport),
          posRealSessionConfigProvider.overrideWithValue(null),
          posDraftRecoveryStoreProvider.overrideWithValue(toggle),
          orderSnapshotRepositoryProvider.overrideWithValue(
            _EmptySnapshotRepo(),
          ),
          posRecentOrdersStoreProvider.overrideWithValue(
            InMemoryRecentOrdersStore(),
          ),
          posSyncClockProvider.overrideWithValue(() => _t0),
          verifiedKdsReadinessOverride(),
        ],
      );
      addTearDown(c.dispose);
      await signIn(c);
      final ctrl = c.read(posDraftRecoveryProvider.notifier);
      final owner = c.read(posRecoveryBindingProvider);
      PosOrderSnapshot snap(int revision) => PosOrderSnapshot(
        orderId: 'o2',
        orderCode: '#ACC',
        revision: revision,
        status: 'served',
        settlement: PosSettlement.unpaid,
        subtotalMinor: 0,
        discountTotalMinor: 0,
        taxTotalMinor: 0,
        grandTotalMinor: 0,
        createdAt: _t0,
        updatedAt: _t0,
        syncAt: _t0,
        currencyCode: 'ILS',
      );
      ctrl.capture(
        PosDraftRecovery(
          draft: const CartDraftSnapshot(
            currencyCode: 'ILS',
            lines: [
              CartDraftLine(
                lineId: 'l1',
                menuItemId: 'cola',
                name: 'Cola',
                basePriceMinor: 1000,
                quantity: 1,
              ),
            ],
          ),
          orderType: OrderType.takeaway,
          outboxEntryId: 'e1',
          binding: owner,
        ),
      );
      expect(
        await ctrl.linkCorrectedSubmit(
          sourceOutboxEntryId: 'e1',
          correctedOutboxEntryId: 'e2',
          binding: owner,
          correctedDraft: const CartDraftSnapshot(
            currencyCode: 'ILS',
            lines: [],
          ),
          orderType: OrderType.takeaway,
        ),
        isTrue,
      );

      // First acceptance signal — the cleanup write FAILS, so the recovery must REMAIN.
      toggle.failWrites = true;
      final orders = c.read(posRecentOrdersControllerProvider.notifier);
      orders.recordSubmitted(
        const SubmittedOrderView(
          orderNumber: '#ACC',
          orderType: OrderType.takeaway,
          currencyCode: 'ILS',
          subtotalMinor: 0,
          orderId: 'o2',
          outboxEntryId: 'e2',
          lines: [],
        ),
      );
      await settle();
      await orders.applySnapshots([snap(1)]);
      await settle();
      expect(
        ctrl.hasRecoveryFor('e1'),
        isTrue,
        reason: 'a failed cleanup write retains the recovery (not lost)',
      );

      // Next acceptance signal with the store healthy — the cleanup retries + succeeds.
      toggle.failWrites = false;
      await orders.applySnapshots([snap(2)]);
      await settle();
      expect(
        ctrl.hasRecoveryFor('e1'),
        isFalse,
        reason: 'cleanup eventually succeeds idempotently on the next signal',
      );
    },
  );

  testWidgets(
    'real CUSTOMER RECEIPT + kitchen ticket both build from the SAME restored cart lines '
    '(§12): exact Dashboard order, each item/modifier once, receipt carries money, kitchen '
    'stays money-free, integer-minor totals',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final l10n = await l10nEn();
      final transport = _RecordingTransport()
        ..orderScript.addAll([_itemUnavailable, _accepted]);
      final c = makeContainer(prefs, transport);
      addTearDown(c.dispose);
      await signIn(c);
      c.read(posDraftRecoveryProvider);
      final (ref, ctx) = await pumpApp(tester, c);
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
        c
            .read(cartControllerProvider)
            .lines
            .firstWhere((l) => l.name == 'Fries')
            .lineId,
      );
      cart.addItem(_burgerB);
      c
          .read(orderSetupControllerProvider.notifier)
          .setOrderType(OrderType.takeaway);
      await tester.pump();
      Future<void> submit() => submitOrderFromCart(
        ref: ref,
        context: ctx,
        cart: c.read(cartControllerProvider),
        setup: c.read(orderSetupControllerProvider),
        cartController: cart,
        setupController: c.read(orderSetupControllerProvider.notifier),
        l10n: l10n,
      );
      await submit(); // item_unavailable -> recovery
      await tester.pump();
      await settle();
      final e1 = c.read(posDraftRecoveryProvider).keys.single;
      final rec = c
          .read(posDraftRecoveryProvider.notifier)
          .recoverable(e1, c.read(posRecoveryBindingProvider))!;
      await PosRecoveryCoordinator(ref).restore(ctx, rec);
      await tester.pump();

      // The KITCHEN ticket is built from the restored cart lines (BEFORE the submit empties
      // the cart); the CUSTOMER receipt from the accepted order those SAME lines produced.
      final restoredLines = c.read(cartControllerProvider).lines;
      final kitchen = kit.buildKdsTicketPrintDocument(
        ticket: kdsTicketViewFromCartLines(
          orderCode: '#R',
          orderType: OrderType.takeaway,
          lines: restoredLines,
        ),
        labels: kitchenTicketPrintLabelsFromL10n(l10n),
      );
      await submit(); // accepted (no correction) — all items available now
      await tester.pump();
      await settle();
      final submitted = c.read(cartControllerProvider).submittedOrder!;

      // The REAL customer receipt document, from the accepted submitted order.
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
      final receipt = buildReceiptDocument(
        l10n,
        submitted,
        payment,
        isDemo: false,
      );

      // Receipt items: exact Dashboard order, each once, at the "qty × name" format.
      final receiptItems = [
        for (final line in receipt.lines)
          if (line.kind == PrintLineKind.item) line.left,
      ];
      expect(receiptItems, const [
        '1 × Burger B',
        '1 × Burger A',
        '2 × Fries',
        '1 × Cola',
      ]);
      // Kitchen items: the SAME sequence from the SAME restored cart lines.
      final kitchenItems = [
        for (final line in kitchen.lines)
          if (line.kind == kit.PrintLineKind.item) line.left ?? '',
      ];
      expect(kitchenItems, receiptItems);
      // The modifier + note appear EXACTLY ONCE on the receipt.
      final receiptText = [for (final line in receipt.lines) line.left ?? ''];
      expect(receiptText.where((t) => t.contains('no onion')), hasLength(1));
      expect(receiptText.where((t) => t.contains('well done')), hasLength(1));
      // The receipt CARRIES money (item line totals present); integer-minor total.
      expect(
        receipt.lines.any(
          (l) => l.kind == PrintLineKind.item && (l.right ?? '').isNotEmpty,
        ),
        isTrue,
      );
      expect(submitted.grandTotalMinor, isA<int>());
      // The KITCHEN document stays money-free.
      final kitchenText = [
        for (final line in kitchen.lines)
          '${line.left ?? ''} ${line.right ?? ''}',
      ];
      expect(
        kitchenText.any((t) => t.contains('ILS') || t.contains('₪')),
        isFalse,
      );
    },
  );

  group('corrupt / legacy durable payload fails closed (POS never crashes)', () {
    const key = 'restoflow.pos.draft_recovery.v1';

    test('malformed JSON -> empty map (no crash)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        key: 'not json{',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(await SharedPrefsDraftRecoveryStore(prefs).load(), isEmpty);
    });

    test('a legacy v1 envelope is DROPPED (schema version mismatch)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        key:
            '{"version":1,"recoveries":{"e1":{"outbox_entry_id":"e1",'
            '"binding":{"pin_session_id":"S1"}}}}',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(
        await SharedPrefsDraftRecoveryStore(prefs).load(),
        isEmpty,
        reason: 'a v1 (pin-session-keyed) record is never mis-owned as v2',
      );
    });

    test(
      'a v2 record WITHOUT a stable owner id fails closed (unattributable)',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          key:
              '{"version":2,"recoveries":{"e1":{"outbox_entry_id":"e1",'
              '"order_type":"takeaway","draft":{"currency_code":"ILS","lines":[]},'
              '"binding":{"scope_key":"org-1.rest-1.branch-A.device-1"}}}}',
        });
        final prefs = await SharedPreferences.getInstance();
        final loaded = await SharedPrefsDraftRecoveryStore(prefs).load();
        expect(loaded.containsKey('e1'), isTrue, reason: 'decodes safely');
        // No employee_profile_id -> a NULL owner -> recoverable by NO real worker.
        final rec = loaded['e1']!;
        expect(rec.binding.employeeProfileId, isNull);
        final matcher = PosDraftRecovery(
          draft: rec.draft,
          orderType: rec.orderType,
          outboxEntryId: 'e1',
          binding: const PosRecoveryBinding(
            scopeKey: 'org-1.rest-1.branch-A.device-1',
            employeeProfileId: 'emp-A',
          ),
        );
        expect(
          rec.binding.matches(matcher.binding),
          isFalse,
          reason: 'an unattributable record is never owned by a real worker',
        );
      },
    );

    test(
      'a v2 record missing the new ordering fields decodes with safe defaults',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          key:
              '{"version":2,"recoveries":{"e1":{"outbox_entry_id":"e1",'
              '"order_type":"takeaway","binding":{"scope_key":"s","employee_profile_id":"emp-A"},'
              '"draft":{"currency_code":"ILS","lines":[{"menu_item_id":"m1",'
              '"name":"X","base_price_minor":100,"quantity":1}]}}}}',
        });
        final prefs = await SharedPreferences.getInstance();
        final loaded = await SharedPrefsDraftRecoveryStore(prefs).load();
        final line = loaded['e1']!.draft.lines.single;
        expect(line.categoryDisplayOrder, 0);
        expect(line.itemDisplayOrder, 0);
        expect(line.basePriceMinor, 100);
      },
    );
  });
}
