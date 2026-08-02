@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport, SyncSession;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/demo_menu.dart' show DemoMenuItem;
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/state/addition_controller.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';

/// KITCHEN-MODIFIER-PREP-CLASSIFIER-REJECTION-UX-AUDIT-FIX-022 — Codex MEDIUM.
///
/// The stale refusal tells the cashier to "refresh the menu and select the item
/// options again", but only `item_unavailable` actually invalidated the menu.
/// So the instruction was unactionable: the cashier re-picked the SAME stale
/// 240g option from the SAME cached menu and got refused again, forever.
///
/// These drive the REAL `posMenuProvider`, whose real-mode body calls
/// `pos_menu` on the injected transport. The second read is a genuine refetch
/// returning a genuinely different configuration — no menu object is mutated or
/// reused to fake a refresh.
const String _staleCode = 'modifier_prep_snapshot_stale';
const String _burgerId = 'm-022';
const String _sizeOptionId = 'opt-240';

const DemoMenuItem _burger = DemoMenuItem(
  id: _burgerId,
  name: 'Burger',
  priceMinor: 4500,
  categoryId: 'food',
  categoryName: 'Food',
);

/// A `pos_menu` envelope whose 240g size option contributes [pieces] pieces.
Map<String, Object?> _menuEnvelope(int pieces) => <String, Object?>{
  'ok': true,
  'currency_code': 'ILS',
  'categories': <Object?>[
    <String, Object?>{'id': 'food', 'name': 'Food', 'display_order': 1},
  ],
  'items': <Object?>[
    <String, Object?>{
      'id': _burgerId,
      'name': 'Burger',
      'base_price_minor': 4500,
      'menu_category_id': 'food',
    },
  ],
  'modifiers': <Object?>[
    <String, Object?>{
      'id': 'grp-size',
      'menu_item_id': _burgerId,
      'name': 'Size',
      'selection_type': 'single',
    },
  ],
  'modifier_options': <Object?>[
    <String, Object?>{
      'id': _sizeOptionId,
      'modifier_id': 'grp-size',
      'name': '240g',
      'price_delta_minor': 0,
      'kitchen_meat': <String, Object?>{
        'quantity': pieces,
        'unit': 'Meat pieces',
      },
    },
  ],
};

/// Serves a DIFFERENT menu on each successive `pos_menu` call and answers every
/// `sync_push` with the server's stale refusal.
class _StaleThenFreshTransport implements SyncRpcTransport {
  _StaleThenFreshTransport(this.operationType, {this.refusalCode = _staleCode});

  final String operationType;

  /// The typed refusal the server returns for every push.
  final String refusalCode;
  int menuCalls = 0;
  int pushCalls = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'pos_menu') {
      menuCalls++;
      // The owner edited 240g from 2 pieces to 3 between the two loads.
      return _menuEnvelope(menuCalls == 1 ? 2 : 3);
    }
    if (function != 'sync_push') return <String, dynamic>{'ok': false};
    pushCalls++;
    final op = (params['p_operations'] as List).first as Map;
    return <String, dynamic>{
      'ok': true,
      'results': <dynamic>[
        <String, dynamic>{
          'local_operation_id': op['local_operation_id'],
          'operation_type': operationType,
          'ok': false,
          'status': 'rejected',
          'error': refusalCode,
          'entity': 'order',
          'order_id': op['target_id'],
        },
      ],
      'server_ts': '2026-08-02T09:00:01Z',
    };
  }
}

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

const SyncSession _session = SyncSession(
  pinSessionId: 'pin-1',
  deviceId: 'dev-1',
);

ProviderContainer _container(SyncRpcTransport transport) {
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport),
      posSyncSessionProvider.overrideWithValue(_session),
      // The REAL outbox over the REAL transport, so `_applyPushResult` parses
      // the true envelope rather than a stub verdict.
      outboxRepositoryProvider.overrideWithValue(
        RealOutboxRepository(transport, _session),
      ),
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

/// The 240g option's configured contribution in the CURRENT menu snapshot.
num? _pieces(PosMenuData menu) {
  for (final group in menu.modifierGroups) {
    for (final option in group.options) {
      if (option.id == _sizeOptionId) return option.kitchenMeat?.quantity;
    }
  }
  return null;
}

void main() {
  group('A. the central policy', () {
    test('022-P1 a stale preparation refusal refreshes the menu', () {
      expect(shouldRefreshMenuForSubmissionError(_staleCode), isTrue);
    });

    test('022-P2 the established item_unavailable behaviour is preserved', () {
      expect(shouldRefreshMenuForSubmissionError('item_unavailable'), isTrue);
    });

    test('022-P3 nothing else refreshes the menu', () {
      for (final code in const [
        null,
        'table_required',
        'table_not_allowed',
        'table_not_available',
        'dispatch_mode_not_allowed',
        'modifier_option_not_in_scope',
        'rejected',
        'transport',
        'timeout',
        'conflict',
        'invalid_device_type',
        'permission_denied',
        'order_already_settled',
        'malformed_response',
      ]) {
        expect(
          shouldRefreshMenuForSubmissionError(code),
          isFalse,
          reason: '$code must not trigger a menu reload',
        );
      }
    });
  });

  group('B. the INITIAL submit really reloads the menu', () {
    test('022-M1 a stale refusal refetches a genuinely different menu', () async {
      final transport = _StaleThenFreshTransport('order.submit');
      final container = _container(transport);

      final before = await container.read(posMenuProvider.future);
      expect(_pieces(before), 2, reason: 'the frozen configuration');
      expect(transport.menuCalls, 1);

      await container
          .read(outboxControllerProvider.notifier)
          .submit(
            lines: const [
              CartLineView(
                lineId: 'l1',
                menuItemId: _burgerId,
                name: 'Burger',
                quantity: 1,
                unitPriceMinor: 4500,
                lineTotalMinor: 4500,
                currencyCode: 'ILS',
              ),
            ],
            subtotalMinor: 4500,
            currencyCode: 'ILS',
            orderType: OrderType.takeaway,
          );

      // The push happened exactly once and was refused.
      expect(transport.pushCalls, 1);
      final entry = container.read(outboxControllerProvider).single;
      expect(entry.lastErrorCode, _staleCode);
      expect(entry.isPermanentBusinessRejection, isTrue);

      // THE FIX: the next menu read is a real second fetch of a real new menu.
      final after = await container.read(posMenuProvider.future);
      expect(transport.menuCalls, 2, reason: 'the provider was invalidated');
      expect(_pieces(after), 3, reason: 'the refreshed configuration');
      expect(
        identical(before, after),
        isFalse,
        reason: 'a refreshed menu must be a new snapshot, not the same object',
      );

      // ...and the refused operation was NOT resent behind the cashier's back.
      expect(
        transport.pushCalls,
        1,
        reason: 'the old frozen operation is never automatically rebuilt',
      );
    });

    test(
      '022-M2 an UNRELATED permanent refusal does NOT reload the menu',
      () async {
        // 003D ownership is an equally PERMANENT business rejection, but it says
        // nothing about our menu being stale — spending a round trip and resetting
        // the grid on it would be a regression the policy must prevent.
        final transport = _StaleThenFreshTransport(
          'order.submit',
          refusalCode: 'modifier_option_not_in_scope',
        );
        final container = _container(transport);
        final before = await container.read(posMenuProvider.future);
        expect(transport.menuCalls, 1);

        await container
            .read(outboxControllerProvider.notifier)
            .submit(
              lines: const [
                CartLineView(
                  lineId: 'l1',
                  menuItemId: _burgerId,
                  name: 'Burger',
                  quantity: 1,
                  unitPriceMinor: 4500,
                  lineTotalMinor: 4500,
                  currencyCode: 'ILS',
                ),
              ],
              subtotalMinor: 4500,
              currencyCode: 'ILS',
              orderType: OrderType.takeaway,
            );

        final entry = container.read(outboxControllerProvider).single;
        expect(entry.lastErrorCode, 'modifier_option_not_in_scope');
        expect(entry.isPermanentBusinessRejection, isTrue);

        final after = await container.read(posMenuProvider.future);
        expect(transport.menuCalls, 1, reason: 'no menu reload for this code');
        expect(identical(before, after), isTrue);
      },
    );
  });

  group('C. ADD-ITEMS really reloads the menu', () {
    test(
      '022-M3 a stale round refusal refetches and keeps the draft',
      () async {
        final transport = _StaleThenFreshTransport('order.items_add');
        final container = _container(transport);

        final before = await container.read(posMenuProvider.future);
        expect(_pieces(before), 2);
        expect(transport.menuCalls, 1);

        final notifier = container.read(additionControllerProvider.notifier);
        final cart = container.read(cartControllerProvider.notifier);
        await notifier.enterForOrder('o-1');
        expect(cart.addItem(_burger), CartMutationResult.applied);

        final result = await notifier.submit();
        expect(result.applied, isFalse);
        expect(result.error, _staleCode);
        expect(result.printPayload, isNull, reason: 'nothing may be printed');

        // The draft survives and the identity is released.
        expect(container.read(cartControllerProvider).lines, hasLength(1));
        final state = container.read(additionControllerProvider);
        expect(state.phase, AdditionPhase.failed);
        expect(state.dispatched, isFalse);
        expect(state.canCancel, isTrue);

        // THE FIX: the same central provider was invalidated.
        final after = await container.read(posMenuProvider.future);
        expect(transport.menuCalls, 2, reason: 'the provider was invalidated');
        expect(_pieces(after), 3);
        expect(identical(before, after), isFalse);

        // The rejected round is never resent automatically.
        expect(transport.pushCalls, 1);
      },
    );

    test('022-M4 the refresh happens ONCE per handled refusal', () async {
      final transport = _StaleThenFreshTransport('order.items_add');
      final container = _container(transport);
      await container.read(posMenuProvider.future);

      final notifier = container.read(additionControllerProvider.notifier);
      final cart = container.read(cartControllerProvider.notifier);
      await notifier.enterForOrder('o-1');
      expect(cart.addItem(_burger), CartMutationResult.applied);
      await notifier.submit();

      // Reading twice must not keep refetching — invalidation is not a loop.
      await container.read(posMenuProvider.future);
      await container.read(posMenuProvider.future);
      expect(transport.menuCalls, 2);
    });
  });
}
