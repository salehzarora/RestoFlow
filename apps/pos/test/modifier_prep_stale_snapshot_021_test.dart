@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport, SyncSession;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart'
    show isOrderEligibleForKitchenPrint;
import 'package:restoflow_pos/src/state/addition_controller.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart'
    show submitOrderFromCart;

import 'support/verified_kitchen_mode_readiness.dart';

/// KITCHEN-MODIFIER-PREP-CLASSIFIER-STALE-SNAPSHOT-FIX-021 — the POS half.
///
/// `app.submit_order` / `app.add_order_items` now refuse an operation whose
/// FROZEN preparation snapshot no longer matches the menu, instead of silently
/// storing a different answer than the one the cashier confirmed and the POS
/// will print. The refusal is DETERMINISTIC and NON-TRANSIENT: re-sending the
/// same frozen operation can only be refused again, so the POS must
///
///   * never place it in a retry loop,
///   * never print a kitchen ticket for it,
///   * never present the order as accepted,
///   * keep the local draft so the cashier can refresh and re-pick the line,
///   * release the Add-items submission identity so a corrected re-send is a
///     NEW operation rather than a second round of the same food,
///
/// and say something the cashier can act on.
///
/// The exact English sentence is asserted as a LITERAL, so these fail on
/// behaviour against HEAD b081de5 rather than on a missing symbol.
const _staleMessage =
    'The menu preparation settings changed. '
    'Refresh the menu and select the item options again.';

const String _staleCode = 'modifier_prep_snapshot_stale';

const SyncSession _session = SyncSession(
  pinSessionId: 'pin-1',
  deviceId: 'dev-1',
);

/// The exact envelope `public.sync_push` returns for the server's
/// RETURN-refusal: a per-op `status:'rejected'` row carrying the typed code and
/// the modifier echo built from the CLIENT's own payload labels.
class _StaleTransport implements SyncRpcTransport {
  _StaleTransport(this.operationType);

  final String operationType;
  int pushes = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> p) async {
    pushes++;
    final op = (p['p_operations'] as List).first as Map<String, dynamic>;
    return <String, dynamic>{
      'ok': true,
      'results': <dynamic>[
        <String, dynamic>{
          'local_operation_id': op['local_operation_id'],
          'operation_type': operationType,
          'ok': false,
          'status': 'rejected',
          'error': _staleCode,
          'entity': 'order',
          'order_id': op['target_id'],
          'modifiers': <dynamic>[
            <String, dynamic>{
              'menu_item_id': 'burger-classic',
              'option_name_snapshot': '240g',
            },
          ],
        },
      ],
      'server_ts': '2026-08-02T09:00:01Z',
    };
  }
}

/// The Add-items transport: every push is answered with the server's stale
/// refusal, and every pushed operation is recorded so the identity behaviour is
/// observable.
class _AdditionTransport implements SyncRpcTransport {
  final List<Map<String, dynamic>> calls = <Map<String, dynamic>>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function != 'sync_push') return <String, dynamic>{'ok': false};
    calls.add(params);
    final op = (params['p_operations'] as List).single as Map;
    return <String, dynamic>{
      'ok': true,
      'results': <dynamic>[
        <String, dynamic>{
          'local_operation_id': op['local_operation_id'],
          'operation_type': 'order.items_add',
          'status': 'rejected',
          'ok': false,
          'error': _staleCode,
          'entity': 'order',
          'order_id': op['target_id'],
        },
      ],
    };
  }
}

/// A live parent order to extend — the same shape the Add-items tests use.
class _ParentDetailRepo implements OrderDetailRepository {
  @override
  Future<PosOrderDetail> fetch(String orderId) async => PosOrderDetail(
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
    rounds: const [],
  );
}

const DemoMenuItem _burger = DemoMenuItem(
  id: 'm-021',
  name: 'Stale Burger',
  priceMinor: 700,
  categoryId: 'c1',
  categoryName: 'Food',
);

ProviderContainer _additionContainer(SyncRpcTransport transport) {
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport),
      posSyncSessionProvider.overrideWithValue(_session),
      orderDetailRepositoryProvider.overrideWithValue(_ParentDetailRepo()),
      orderSnapshotRepositoryProvider.overrideWithValue(
        DemoOrderSnapshotRepository(),
      ),
      posSyncPollIntervalProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pumpReal(WidgetTester tester, SyncRpcTransport transport) async {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posSyncSessionProvider.overrideWithValue(_session),
        outboxRepositoryProvider.overrideWithValue(
          RealOutboxRepository(transport, _session),
        ),
        posMenuProvider.overrideWith(
          (ref) async => const PosMenuData(
            categories: kDemoCategories,
            items: kDemoMenu,
            currencyCode: 'ILS',
          ),
        ),
        verifiedKdsReadinessOverride(),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const PosMenuScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.posSendOrder));
  await tester.pumpAndSettle();
}

void main() {
  group('A. the refusal is classified as TERMINAL business, not transient', () {
    OutboxEntry entry(OutboxSyncState state, String? code) => OutboxEntry(
      id: 'e1',
      deviceId: 'dev',
      localOperationId: 'op-1',
      operationType: 'order.submit',
      targetEntity: 'order',
      targetId: 'o-1',
      payloadJson: '{}',
      summary: const OrderSummary(
        orderNumber: '#000001',
        orderType: OrderType.takeaway,
        tableLabel: null,
        itemCount: 1,
        subtotalMinor: 2500,
        currencyCode: 'ILS',
      ),
      syncState: state,
      clientCreatedAt: DateTime.utc(2026, 8, 2),
      lastErrorCode: code,
    );

    test(
      'A1 an order.submit stale refusal is a PERMANENT business rejection',
      () {
        expect(
          entry(
            OutboxSyncState.rejected,
            _staleCode,
          ).isPermanentBusinessRejection,
          isTrue,
          reason:
              'the server refused the frozen operation deterministically; '
              're-pushing the same identity can only be refused again',
        );
      },
    );

    test('A2 it is also a terminal Add-items refusal', () {
      expect(kAdditionTerminalRefusalCodes.contains(_staleCode), isTrue);
    });

    test('A3 a stale-refused order is NEVER eligible for a kitchen print', () {
      expect(
        isOrderEligibleForKitchenPrint(
          orderId: 'order-1',
          isDemoMode: false,
          rejectionCode: _staleCode,
        ),
        isFalse,
        reason: 'no server order exists, so there is nothing to cook',
      );
      // Control: the same order with no refusal still prints.
      expect(
        isOrderEligibleForKitchenPrint(
          orderId: 'order-1',
          isDemoMode: false,
          rejectionCode: null,
        ),
        isTrue,
      );
    });

    test(
      'A4 the classification needs the REJECTED state, not just the code',
      () {
        expect(
          entry(
            OutboxSyncState.applied,
            _staleCode,
          ).isPermanentBusinessRejection,
          isFalse,
        );
      },
    );
  });

  group('B. the initial submit surface', () {
    testWidgets('B1 a stale refusal shows the actionable note and NO Retry', (
      tester,
    ) async {
      final l10n = await _en();
      final transport = _StaleTransport('order.submit');
      await _pumpReal(tester, transport);
      await _submit(tester, l10n);

      expect(transport.pushes, 1);
      expect(find.text(l10n.posSyncStateFailed), findsOneWidget);
      // Not a transient failure: the same-identity Retry is withdrawn.
      expect(find.byKey(const Key('sync-retry-button')), findsNothing);
      // ...and the cashier is told what to actually do.
      expect(find.text(_staleMessage), findsOneWidget);
      // Never the generic "the backend rejected this order" line.
      expect(find.text(l10n.posSyncFailedReal), findsNothing);
    });

    testWidgets('B2 the automatic sweep never re-pushes it', (tester) async {
      final l10n = await _en();
      final transport = _StaleTransport('order.submit');
      await _pumpReal(tester, transport);
      await _submit(tester, l10n);
      expect(transport.pushes, 1);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(PosMenuScreen)),
        listen: false,
      );
      await container.read(outboxControllerProvider.notifier).retryAllFailed();
      await tester.pumpAndSettle();

      expect(
        transport.pushes,
        1,
        reason: 'a ledgered business verdict is never burned on a retry',
      );
    });
  });

  group('C. the Add-items surface', () {
    test('C1 the stale envelope classifies as a REFUSAL, not unknown', () {
      final outcome = AdditionController.classifyAdditionResponse(
        <String, dynamic>{
          'ok': true,
          'results': <dynamic>[
            <String, dynamic>{
              'local_operation_id': 'op-1',
              'operation_type': 'order.items_add',
              'ok': false,
              'status': 'rejected',
              'error': _staleCode,
              'order_id': 'o-1',
            },
          ],
        },
        localOperationId: 'op-1',
        orderId: 'o-1',
      );

      expect(outcome.kind, AdditionOutcomeKind.refused);
      expect(outcome.reason, _staleCode);
      expect(
        outcome.roundId,
        isNull,
        reason: 'no round exists — nothing may be printed or shown as applied',
      );
    });

    test(
      'C2 the REAL controller keeps the draft and releases the identity',
      () async {
        final transport = _AdditionTransport();
        final container = _additionContainer(transport);
        final notifier = container.read(additionControllerProvider.notifier);
        final cart = container.read(cartControllerProvider.notifier);
        await notifier.enterForOrder('o-1');
        expect(cart.addItem(_burger), CartMutationResult.applied);

        final result = await notifier.submit();

        expect(result.applied, isFalse);
        expect(result.error, _staleCode);
        // NO print: the round does not exist, so nothing may reach the kitchen.
        expect(result.printPayload, isNull);
        expect(result.roundNumber, isNull);
        expect(result.refreshRequired, isFalse);

        final state = container.read(additionControllerProvider);
        expect(state.phase, AdditionPhase.failed);
        expect(state.lastError, _staleCode);
        // THE lock release: `dispatched: false` re-opens cancel, so `exit()` can
        // free the cart and the identity. A refusal is a definitive verdict.
        expect(state.dispatched, isFalse);
        expect(state.canCancel, isTrue);

        // The cashier's pending line is still there to correct.
        expect(container.read(cartControllerProvider).lines, hasLength(1));
        expect(
          container.read(cartControllerProvider).lines.single.menuItemId,
          _burger.id,
        );
      },
    );

    test(
      'C3 the freed identity lets a corrected attempt be a NEW operation',
      () async {
        final transport = _AdditionTransport();
        final container = _additionContainer(transport);
        final notifier = container.read(additionControllerProvider.notifier);
        final cart = container.read(cartControllerProvider.notifier);
        await notifier.enterForOrder('o-1');
        expect(cart.addItem(_burger), CartMutationResult.applied);
        await notifier.submit();

        // The refusal is definitive, so leaving addition mode is permitted —
        // that is exactly what `dispatched: false` unlocks, and it is the ONLY
        // way the frozen identity is retired. Nothing here resubmits by itself.
        expect(
          notifier.exit(),
          isTrue,
          reason: 'an undecided operation would refuse to release its identity',
        );

        // The cashier refreshes, re-picks the line and confirms again.
        // The retained line is still in the cart — which is why re-entering
        // addition mode is refused until the cashier deals with it. That is the
        // point: the draft was NOT thrown away behind their back.
        expect(
          await notifier.enterForOrder('o-1'),
          AdditionEntryResult.cartNotEmpty,
        );
        expect(cart.clear(), CartMutationResult.applied);

        // Now they re-pick from the refreshed menu and confirm again.
        expect(
          await notifier.enterForOrder('o-1'),
          AdditionEntryResult.entered,
        );
        expect(cart.addItem(_burger), CartMutationResult.applied);
        await notifier.submit();

        String opOf(int i) =>
            ((transport.calls[i]['p_operations'] as List).single
                    as Map)['local_operation_id']
                as String;
        expect(transport.calls, hasLength(2));
        expect(
          opOf(0),
          isNot(opOf(1)),
          reason:
              'a rebuilt attempt must be a NEW operation, never a replay that '
              'could be mistaken for the refused one',
        );
      },
    );

    testWidgets('C4 the Add-items message is the actionable one, not "retry"', (
      tester,
    ) async {
      final l10n = await _en();
      final transport = _AdditionTransport();
      final container = _additionContainer(transport);
      final notifier = container.read(additionControllerProvider.notifier);
      final cart = container.read(cartControllerProvider.notifier);
      await notifier.enterForOrder('o-1');
      expect(cart.addItem(_burger), CartMutationResult.applied);

      late WidgetRef ref;
      late BuildContext ctx;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Consumer(
              builder: (c, r, _) {
                ref = r;
                ctx = c;
                return const Scaffold(body: SizedBox());
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await submitOrderFromCart(
        ref: ref,
        context: ctx,
        cart: container.read(cartControllerProvider),
        setup: container.read(orderSetupControllerProvider),
        cartController: cart,
        setupController: container.read(orderSetupControllerProvider.notifier),
        l10n: l10n,
      );
      await tester.pump();

      expect(find.text(_staleMessage), findsOneWidget);
      expect(find.text(l10n.posAdditionFailedRetry), findsNothing);
      expect(find.text(l10n.posAdditionApplied), findsNothing);
    });
  });
}
