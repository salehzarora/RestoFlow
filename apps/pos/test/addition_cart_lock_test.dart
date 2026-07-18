import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart' show DemoMenuItem;
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/addition_controller.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/widgets/menu_item_card.dart';

/// PSC-001C final cart-safety micro-fix — the OWNER-TOKEN cart mutation lock.
///
/// A frozen addition attempt owns the cart from the atomic freeze+lock at
/// first submit until the verified reconciliation or an explicit cancel:
///  A. every CartController mutation refuses while SENDING;
///  B. every mutation refuses while APPLIED-AWAITING-REFRESH;
///  C. a retryable failure keeps the lock; retry is byte-identical; explicit
///     cancel releases WITHOUT clearing; a new attempt gets a new op id;
///  D. successful reconciliation clears + unlocks with the matching token,
///     exactly once, and normal editing resumes;
///  E. a stale attempt-A callback cannot clear/unlock/alter attempt B;
///  F. direct privileged calls with a WRONG token fail closed;
///  G. the UI: controls disabled while locked, banner cancel disabled while
///     sending, enabled on a retryable failure, everything restored after.

const _item = DemoMenuItem(
  id: 'm-lock',
  name: 'Lock Burger',
  priceMinor: 700,
  categoryId: 'c1',
  categoryName: 'Food',
);

const _intruder = DemoMenuItem(
  id: 'm-intruder',
  name: 'Intruder',
  priceMinor: 100,
  categoryId: 'c1',
  categoryName: 'Food',
);

PosOrderDetail _detail({
  String orderId = 'o-1',
  List<PosOrderDetailRound> rounds = const [
    PosOrderDetailRound(roundId: 'r-new', roundNumber: 2, status: 'submitted'),
  ],
}) => PosOrderDetail(
  orderId: orderId,
  orderCode: '#O00001',
  orderType: 'dine_in',
  status: 'preparing',
  revision: 2,
  currencyCode: 'ILS',
  subtotalMinor: 2500,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 2500,
  tableLabel: 'T1',
  items: const [],
  rounds: rounds,
);

Object? _applied(Map<String, dynamic> params) {
  final ops = params['p_operations'] as List;
  final localOp = (ops.single as Map)['local_operation_id'] as String;
  return {
    'ok': true,
    'results': [
      {
        'local_operation_id': localOp,
        'status': 'applied',
        'ok': true,
        'round_id': 'r-new',
        'round_number': 2,
      },
    ],
  };
}

Object? _rejected(Map<String, dynamic> params) {
  final ops = params['p_operations'] as List;
  final localOp = (ops.single as Map)['local_operation_id'] as String;
  return {
    'ok': true,
    'results': [
      {
        'local_operation_id': localOp,
        'status': 'rejected',
        'ok': false,
        'error': 'rejected',
      },
    ],
  };
}

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._responses);
  final List<Object? Function(Map<String, dynamic>)> _responses;
  final List<Map<String, dynamic>> calls = [];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function != 'sync_push') return {'ok': false};
    calls.add(params);
    final handler = _responses.length >= calls.length
        ? _responses[calls.length - 1]
        : _responses.last;
    return handler(params);
  }
}

/// Per-call gated transport — the test decides when each response lands.
class _GatedTransport implements SyncRpcTransport {
  final List<Map<String, dynamic>> calls = [];
  final List<Completer<Object?>> gates = [];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) {
    if (function != 'sync_push') return Future.value({'ok': false});
    calls.add(params);
    final gate = Completer<Object?>();
    gates.add(gate);
    return gate.future;
  }
}

/// Per-call gated detail repository — drives entry/refresh races.
class _GatedDetailRepo implements OrderDetailRepository {
  final List<String> requested = [];
  final List<Completer<PosOrderDetail>> gates = [];
  @override
  Future<PosOrderDetail> fetch(String orderId) {
    requested.add(orderId);
    final gate = Completer<PosOrderDetail>();
    gates.add(gate);
    return gate.future;
  }
}

class _FakeDetailRepo implements OrderDetailRepository {
  int fetches = 0;
  @override
  Future<PosOrderDetail> fetch(String orderId) async {
    fetches++;
    return _detail(orderId: orderId);
  }
}

(ProviderContainer, SyncRpcTransport) _container(
  SyncRpcTransport transport, {
  OrderDetailRepository? detailRepo,
}) {
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport),
      posSyncSessionProvider.overrideWithValue(
        const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
      ),
      orderDetailRepositoryProvider.overrideWithValue(
        detailRepo ?? _FakeDetailRepo(),
      ),
      orderSnapshotRepositoryProvider.overrideWithValue(
        DemoOrderSnapshotRepository(),
      ),
      posSyncPollIntervalProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  return (container, transport);
}

/// Asserts EVERY normal cart mutation entry point refuses while locked and
/// that the cart's single frozen line is untouched afterwards.
void expectAllMutationsRefused(ProviderContainer container) {
  final cart = container.read(cartControllerProvider.notifier);
  final before = container.read(cartControllerProvider);
  final lineId = before.lines.single.lineId;
  const locked = CartMutationResult.lockedByAddition;
  expect(cart.addItem(_intruder), locked);
  expect(cart.addItemWithModifiers(_intruder, const []), locked);
  expect(
    cart.addItemWithModifiers(_intruder, const [
      SelectedModifier(
        optionId: 'op1',
        groupName: 'G',
        optionName: 'O',
        priceDeltaMinor: 100,
      ),
    ]),
    locked,
  );
  expect(
    cart.updateLineModifiers(lineId, const [
      SelectedModifier(
        optionId: 'op1',
        groupName: 'G',
        optionName: 'O',
        priceDeltaMinor: 100,
      ),
    ]),
    locked,
  );
  expect(cart.increaseQuantity(lineId), locked);
  expect(cart.decreaseQuantity(lineId), locked);
  expect(cart.removeLine(lineId), locked);
  expect(cart.clear(), locked);
  expect(
    cart.restoreDraft(const CartDraftSnapshot(currencyCode: 'ILS', lines: [])),
    locked,
  );
  expect(cart.submitOrder(), locked);
  expect(cart.startNewOrder(), locked);
  final after = container.read(cartControllerProvider);
  expect(after.lines, hasLength(1));
  expect(after.lines.single.lineId, lineId);
  expect(after.lines.single.menuItemId, _item.id);
  expect(after.lines.single.quantity, before.lines.single.quantity);
  expect(after.lockedByAddition, isTrue);
}

void main() {
  group('A. mutation during SENDING', () {
    test('every mutation entry point refuses; the frozen payload stays X; '
        'the transport payload is exactly X', () async {
      final transport = _GatedTransport();
      final (container, _) = _container(transport);
      final notifier = container.read(additionControllerProvider.notifier);
      final cart = container.read(cartControllerProvider.notifier);
      await notifier.enterForOrder('o-1');
      expect(cart.addItem(_item), CartMutationResult.applied);
      final submitted = notifier.submit();
      // The atomic freeze+lock happened synchronously with the dispatch.
      expect(container.read(cartControllerProvider).lockedByAddition, isTrue);
      expect(container.read(additionControllerProvider).sending, isTrue);
      expectAllMutationsRefused(container);
      // The wire payload is the frozen X — the intruder never entered it.
      final op = (transport.calls.single['p_operations'] as List).single as Map;
      final items = (op['payload'] as Map)['order_items'] as List;
      expect(items, hasLength(1));
      expect((items.single as Map)['menu_item_id'], _item.id);
      transport.gates.single.complete(_applied(transport.calls.single));
      await submitted;
    });
  });

  group('B. mutation during APPLIED-AWAITING-REFRESH', () {
    test('every mutation refuses; no unrelated line can be introduced only '
        'to be lost on reconciliation', () async {
      final repo = _GatedDetailRepo();
      final transport = _FakeTransport([(p) => _applied(p)]);
      final (container, _) = _container(transport, detailRepo: repo);
      final notifier = container.read(additionControllerProvider.notifier);
      final cart = container.read(cartControllerProvider.notifier);
      final entry = notifier.enterForOrder('o-1');
      repo.gates[0].complete(_detail());
      expect(await entry, AdditionEntryResult.entered);
      expect(cart.addItem(_item), CartMutationResult.applied);
      // The applied response returns; the refresh (gate 1) is DELAYED.
      final submitted = notifier.submit();
      await pumpEventQueue(times: 5);
      expect(
        container.read(additionControllerProvider).awaitingRefresh,
        isTrue,
      );
      expectAllMutationsRefused(container);
      // The delayed reconciliation then completes normally — the ONLY thing
      // cleared is the frozen attempt's own submitted line.
      repo.gates[1].complete(_detail());
      final result = await submitted;
      expect(result.applied, isTrue);
      expect(container.read(cartControllerProvider).isEmpty, isTrue);
      expect(container.read(cartControllerProvider).lockedByAddition, isFalse);
    });
  });

  group('C. retryable failure lifecycle', () {
    test(
      'the lock survives the failure; retry is byte-identical; explicit '
      'cancel unlocks WITHOUT clearing; editing and a NEW op id follow',
      () async {
        final transport = _FakeTransport([
          (p) => _rejected(p),
          (p) => _rejected(p),
          (p) => _applied(p),
        ]);
        final (container, _) = _container(transport);
        final notifier = container.read(additionControllerProvider.notifier);
        final cart = container.read(cartControllerProvider.notifier);
        await notifier.enterForOrder('o-1');
        expect(cart.addItem(_item), CartMutationResult.applied);
        final first = await notifier.submit();
        expect(first.applied, isFalse);
        // Still locked through the retryable failure.
        expect(container.read(cartControllerProvider).lockedByAddition, isTrue);
        expectAllMutationsRefused(container);
        // The retry reuses the exact frozen payload + op id.
        final retry = await notifier.submit();
        expect(retry.applied, isFalse);
        final op1 = (transport.calls[0]['p_operations'] as List).single as Map;
        final op2 = (transport.calls[1]['p_operations'] as List).single as Map;
        expect(op2['local_operation_id'], op1['local_operation_id']);
        expect(op2['payload'], op1['payload']);
        // EXPLICIT cancel: unlock, lines INTACT, attempt gone.
        expect(notifier.exit(), isTrue);
        final unlockedCart = container.read(cartControllerProvider);
        expect(unlockedCart.lockedByAddition, isFalse);
        expect(unlockedCart.lines, hasLength(1)); // never cleared by cancel
        expect(
          container.read(additionControllerProvider).hasOpenAttempt,
          isFalse,
        );
        // Editing works again; a fresh attempt gets a NEW operation id.
        expect(
          cart.increaseQuantity(unlockedCart.lines.single.lineId),
          CartMutationResult.applied,
        );
        expect(cart.clear(), CartMutationResult.applied);
        await notifier.enterForOrder('o-1');
        expect(cart.addItem(_item), CartMutationResult.applied);
        final fresh = await notifier.submit();
        expect(fresh.applied, isTrue);
        final op3 = (transport.calls[2]['p_operations'] as List).single as Map;
        expect(op3['local_operation_id'], isNot(op1['local_operation_id']));
      },
    );

    test('a foreign lock refuses the freeze: no dispatch, no attempt, the '
        'cart untouched', () async {
      final transport = _FakeTransport([(p) => _applied(p)]);
      final (container, _) = _container(transport);
      final notifier = container.read(additionControllerProvider.notifier);
      final cart = container.read(cartControllerProvider.notifier);
      await notifier.enterForOrder('o-1');
      expect(cart.addItem(_item), CartMutationResult.applied);
      // Someone else's token owns the cart (the cannot-happen defense path).
      const foreign = CartLockOwner(
        generation: 99,
        orderId: 'o-x',
        localOperationId: 'op-x',
      );
      expect(cart.lockForAddition(foreign), isTrue);
      final refused = await notifier.submit();
      expect(refused.applied, isFalse);
      expect(refused.error, 'cart_locked');
      expect(transport.calls, isEmpty); // nothing dispatched
      expect(
        container.read(additionControllerProvider).hasOpenAttempt,
        isFalse, // no unsafe operation identity was allocated
      );
      expect(container.read(cartControllerProvider).lines, hasLength(1));
    });
  });

  group('D. successful authoritative reconciliation', () {
    test('verified detail → owner-token clear succeeds exactly once, the '
        'lock releases, the attempt clears, normal editing resumes', () async {
      final transport = _FakeTransport([(p) => _applied(p)]);
      final repo = _FakeDetailRepo();
      final (container, _) = _container(transport, detailRepo: repo);
      final notifier = container.read(additionControllerProvider.notifier);
      final cart = container.read(cartControllerProvider.notifier);
      await notifier.enterForOrder('o-1');
      expect(cart.addItem(_item), CartMutationResult.applied);
      final result = await notifier.submit();
      expect(result.applied, isTrue);
      expect(result.refreshRequired, isFalse);
      expect(repo.fetches, 2); // the entry load + the VERIFYING refresh
      final cartState = container.read(cartControllerProvider);
      expect(cartState.isEmpty, isTrue); // the submitted lines cleared
      expect(cartState.lockedByAddition, isFalse); // the lock released
      final addition = container.read(additionControllerProvider);
      expect(addition.hasOpenAttempt, isFalse);
      expect(addition.phase, AdditionPhase.idle);
      // Later NORMAL cart mutation works.
      expect(cart.addItem(_intruder), CartMutationResult.applied);
      expect(container.read(cartControllerProvider).lines, hasLength(1));
    });
  });

  group('E. stale attempt-A callback vs a LIVE attempt B', () {
    test('token A cannot clear, unlock, or alter the cart/attempt/phase '
        'owned by attempt B', () async {
      final repo = _GatedDetailRepo();
      final transport = _GatedTransport();
      final (container, _) = _container(transport, detailRepo: repo);
      final notifier = container.read(additionControllerProvider.notifier);
      final cart = container.read(cartControllerProvider.notifier);
      // Attempt A applies; its refresh (gate 1) HANGS.
      final entryA = notifier.enterForOrder('o-a');
      repo.gates[0].complete(_detail(orderId: 'o-a'));
      expect(await entryA, AdditionEntryResult.entered);
      expect(cart.addItem(_item), CartMutationResult.applied);
      final submittedA = notifier.submit();
      transport.gates[0].complete(_applied(transport.calls[0]));
      await pumpEventQueue(times: 5);
      expect(
        container.read(additionControllerProvider).awaitingRefresh,
        isTrue,
      );
      // A manual refresh retry (gate 2) completes A's cleanup exactly once.
      final retried = notifier.retryRefresh();
      await pumpEventQueue(times: 5);
      repo.gates[2].complete(_detail(orderId: 'o-a'));
      expect(await retried, isTrue);
      expect(container.read(cartControllerProvider).isEmpty, isTrue);
      // Attempt B begins and OWNS the cart (sending, lock held by token B).
      final entryB = notifier.enterForOrder('o-b');
      repo.gates[3].complete(_detail(orderId: 'o-b'));
      expect(await entryB, AdditionEntryResult.entered);
      expect(cart.addItem(_intruder), CartMutationResult.applied);
      final submittedB = notifier.submit();
      expect(container.read(cartControllerProvider).lockedByAddition, isTrue);
      // NOW attempt A's STALE refresh callback (gate 1) finally lands.
      repo.gates[1].complete(_detail(orderId: 'o-a'));
      final resultA = await submittedA;
      expect(resultA.applied, isTrue);
      // ZERO side effects on B: its cart line, lock, attempt, phase all live.
      final bCart = container.read(cartControllerProvider);
      expect(bCart.lockedByAddition, isTrue);
      expect(bCart.lines.single.menuItemId, _intruder.id);
      final bState = container.read(additionControllerProvider);
      expect(bState.target?.orderId, 'o-b');
      expect(bState.sending, isTrue);
      expect(bState.hasOpenAttempt, isTrue);
      // B then completes normally (its reconcile fetch registers only after
      // the transport response is consumed).
      transport.gates[1].complete(_applied(transport.calls[1]));
      await pumpEventQueue(times: 5);
      repo.gates[4].complete(_detail(orderId: 'o-b'));
      final resultB = await submittedB;
      expect(resultB.applied, isTrue);
      expect(container.read(cartControllerProvider).isEmpty, isTrue);
      expect(container.read(cartControllerProvider).lockedByAddition, isFalse);
    });
  });

  group('F. wrong-token direct privileged calls', () {
    test('clear/unlock with a mismatched owner fail closed — the cart stays '
        'locked and unchanged; the TRUE owner still works', () async {
      final transport = _GatedTransport();
      final (container, _) = _container(transport);
      final notifier = container.read(additionControllerProvider.notifier);
      final cart = container.read(cartControllerProvider.notifier);
      await notifier.enterForOrder('o-1');
      expect(cart.addItem(_item), CartMutationResult.applied);
      final submitted = notifier.submit();
      final attempt = container.read(additionControllerProvider).attempt!;
      final generation = container.read(additionControllerProvider).generation;
      const wrong = CartLockOwner(
        generation: 999,
        orderId: 'o-x',
        localOperationId: 'op-x',
      );
      expect(cart.clearForAddition(wrong), isFalse);
      expect(cart.unlockForAddition(wrong), isFalse);
      final held = container.read(cartControllerProvider);
      expect(held.lockedByAddition, isTrue);
      expect(held.lines, hasLength(1));
      // A partially-matching token (right ids, wrong generation) also fails.
      final wrongGen = CartLockOwner(
        generation: generation + 7,
        orderId: attempt.orderId,
        localOperationId: attempt.localOperationId,
      );
      expect(cart.clearForAddition(wrongGen), isFalse);
      expect(cart.unlockForAddition(wrongGen), isFalse);
      // The MATCHING token is the one the controller itself uses — the flow
      // completes and the privileged clear succeeds exactly through it.
      transport.gates.single.complete(_applied(transport.calls.single));
      final result = await submitted;
      expect(result.applied, isTrue);
      expect(container.read(cartControllerProvider).isEmpty, isTrue);
      expect(container.read(cartControllerProvider).lockedByAddition, isFalse);
    });
  });

  group('G. UI enforcement', () {
    Future<AppLocalizations> en() =>
        AppLocalizations.delegate.load(const Locale('en'));

    testWidgets('DEMO menu+cart: add/quantity/edit/remove/clear controls are '
        'disabled while the cart is locked and restore after unlock', (
      tester,
    ) async {
      final l10n = await en();
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const PosMenuScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Add one demo item through the REAL card tap.
      await tester.tap(
        find
            .descendant(
              of: find.byType(MenuItemCard).first,
              matching: find.byIcon(Icons.add_shopping_cart),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final lineId = container.read(cartControllerProvider).lines.single.lineId;
      final cardItemId = tester
          .widget<MenuItemCard>(find.byType(MenuItemCard).first)
          .item
          .id;

      InkWell cardTap() =>
          tester.widget<InkWell>(find.byKey(Key('menu-item-$cardItemId')));
      IconButton lineButton(String prefix) =>
          tester.widget<IconButton>(find.byKey(Key('$prefix-$lineId')));

      // ENABLED before the lock.
      expect(cardTap().onTap, isNotNull);
      expect(lineButton('cart-edit').onPressed, isNotNull);
      expect(lineButton('cart-remove').onPressed, isNotNull);
      expect(find.text(l10n.posClearCart), findsOneWidget);

      // LOCKED: every mutation control disables; Clear withdraws.
      const owner = CartLockOwner(
        generation: 1,
        orderId: 'o-1',
        localOperationId: 'op-1',
      );
      expect(
        container.read(cartControllerProvider.notifier).lockForAddition(owner),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(cardTap().onTap, isNull);
      expect(lineButton('cart-edit').onPressed, isNull);
      expect(lineButton('cart-remove').onPressed, isNull);
      expect(find.text(l10n.posClearCart), findsNothing);

      // UNLOCKED (matching token): everything restores.
      expect(
        container
            .read(cartControllerProvider.notifier)
            .unlockForAddition(owner),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(cardTap().onTap, isNotNull);
      expect(lineButton('cart-edit').onPressed, isNotNull);
      expect(lineButton('cart-remove').onPressed, isNotNull);
      expect(find.text(l10n.posClearCart), findsOneWidget);
    });

    testWidgets('the addition banner: Cancel DISABLED while sending, ENABLED '
        'on a retryable failure, and cancel restores the controls', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final transport = _GatedTransport();
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posAuthTransportProvider.overrideWithValue(transport),
          posSyncSessionProvider.overrideWithValue(
            const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
          ),
          orderDetailRepositoryProvider.overrideWithValue(_FakeDetailRepo()),
          orderSnapshotRepositoryProvider.overrideWithValue(
            DemoOrderSnapshotRepository(),
          ),
          posSyncPollIntervalProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const PosMenuScreen(),
          ),
        ),
      );
      await tester.pump();
      final notifier = container.read(additionControllerProvider.notifier);
      await notifier.enterForOrder('o-1');
      container.read(cartControllerProvider.notifier).addItem(_item);
      await tester.pump();
      final submitted = notifier.submit();
      await tester.pump();

      TextButton cancelButton() => tester.widget<TextButton>(
        find.byKey(const Key('pos-addition-cancel')),
      );
      // SENDING: cancel is disabled (the controller refuses it regardless).
      expect(cancelButton().onPressed, isNull);
      // Retryable failure: cancel ENABLES.
      transport.gates.single.complete(_rejected(transport.calls.single));
      await submitted;
      await tester.pump();
      expect(cancelButton().onPressed, isNotNull);
      // Tapping it exits addition mode and restores the editable cart.
      await tester.tap(find.byKey(const Key('pos-addition-cancel')));
      await tester.pump();
      expect(find.byKey(const Key('pos-addition-banner')), findsNothing);
      expect(container.read(cartControllerProvider).lockedByAddition, isFalse);
      expect(container.read(cartControllerProvider).lines, hasLength(1));
    });
  });
}
