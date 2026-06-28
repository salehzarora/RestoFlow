import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_kds/src/data/kitchen_order.dart';
import 'package:restoflow_kds/src/data/kitchen_orders_repository.dart';
import 'package:restoflow_kds/src/state/kitchen_orders_controller.dart';

void main() {
  late DemoKitchenOrdersStore store;
  late ProviderContainer container;

  setUp(() {
    store = DemoKitchenOrdersStore(clock: () => DateTime(2026, 6, 28, 12, 0));
    container = ProviderContainer(
      overrides: [kitchenOrdersRepositoryProvider.overrideWithValue(store)],
    );
  });
  tearDown(() => container.dispose());

  KitchenOrdersController controller() =>
      container.read(kitchenOrdersControllerProvider.notifier);
  KitchenOrderTicket ticket(String id) => container
      .read(kitchenOrdersControllerProvider)
      .value!
      .firstWhere((t) => t.ticketId == id);

  test('loads a demo feed mirroring the submitted-order shape', () async {
    final orders = await container.read(kitchenOrdersControllerProvider.future);
    expect(orders, isNotEmpty);

    final k1001 = orders.firstWhere((o) => o.ticketId == 'K-1001');
    expect(k1001.orderNumber, 'K-1001');
    expect(k1001.orderType, OrderType.dineIn);
    expect(k1001.tableLabel, 'T3');
    expect(k1001.status, KitchenTicketStatus.newTicket);
    expect(k1001.itemCount, 3); // 2 burgers + 1 cola
    expect(k1001.items.first.modifiers, contains('No pickles'));
  });

  test('Start advances a new order to in_preparation', () async {
    await container.read(kitchenOrdersControllerProvider.future);
    controller().start('K-1001'); // newTicket
    expect(ticket('K-1001').status, KitchenTicketStatus.inPreparation);

    controller().start('K-1004'); // acknowledged
    expect(ticket('K-1004').status, KitchenTicketStatus.inPreparation);
  });

  test('Mark ready advances in_preparation to ready', () async {
    await container.read(kitchenOrdersControllerProvider.future);
    expect(ticket('K-1003').status, KitchenTicketStatus.inPreparation);
    controller().markReady('K-1003');
    expect(ticket('K-1003').status, KitchenTicketStatus.ready);
  });

  test('Complete bumps a ready order; Recall brings it back', () async {
    await container.read(kitchenOrdersControllerProvider.future);
    expect(ticket('K-1005').status, KitchenTicketStatus.ready);

    controller().complete('K-1005');
    expect(ticket('K-1005').status, KitchenTicketStatus.bumped);

    controller().recall('K-1005');
    expect(ticket('K-1005').status, KitchenTicketStatus.inPreparation);
  });

  test('an invalid action is a no-op (no impossible transition)', () async {
    await container.read(kitchenOrdersControllerProvider.future);
    // K-1005 is already ready — Start does not apply.
    controller().start('K-1005');
    expect(ticket('K-1005').status, KitchenTicketStatus.ready);
    // Recall only applies to a bumped ticket.
    controller().recall('K-1005');
    expect(ticket('K-1005').status, KitchenTicketStatus.ready);
  });

  test('an empty seed yields no orders', () async {
    final empty = ProviderContainer(
      overrides: [
        kitchenOrdersRepositoryProvider.overrideWithValue(
          DemoKitchenOrdersStore(seed: const []),
        ),
      ],
    );
    addTearDown(empty.dispose);
    final orders = await empty.read(kitchenOrdersControllerProvider.future);
    expect(orders, isEmpty);
  });
}
