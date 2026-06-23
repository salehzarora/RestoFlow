import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_printing/restoflow_printing.dart';

/// RF-072 — the kitchen print dispatcher: route -> resolve destination -> build
/// -> enqueue. All tests run against in-memory fakes only (no DB, no hardware,
/// no transport; approved A5/A6).
void main() {
  // Fixed instant -> deterministic createdAt/timestamps.
  final at = DateTime.utc(2026, 6, 23, 12, 0, 0);
  const auth = OrderActionAuthorization(canVoid: true, actorId: 'mgr-1');

  group('routing + enqueue (AC1)', () {
    test(
      'an order spanning two stations enqueues one job per station',
      () async {
        final order = _order(
          items: [
            _Line('a', 'burger', 'Burger', qty: 2),
            _Line('b', 'beer', 'Beer'),
          ],
        );
        final h = _Harness(
          routing: _routing({
            'grill': _dest('p-grill', label: 'Grill'),
            'bar': _dest('p-bar', label: 'Bar'),
          }),
          clock: () => at,
        );

        final result = await h.dispatcher.dispatch(
          order,
          KitchenRoutingRules(itemStation: {'burger': 'grill', 'beer': 'bar'}),
        );

        expect(result.isFullyRouted, isTrue);
        expect(result.unroutableItems, isEmpty);
        expect(result.noDestinationStations, isEmpty);
        expect(result.enqueuedJobs, hasLength(2));

        final byStation = {for (final j in result.enqueuedJobs) j.stationId: j};
        for (final stationId in ['grill', 'bar']) {
          final job = byStation[stationId]!;
          expect(job.jobType, PrintJobType.kitchenTicket);
          expect(job.organizationId, 'org-1');
          expect(job.branchId, 'branch-1');
          expect(job.deviceId, 'dev-1');
          expect(job.localOperationId, 'kitchen:o1:$stationId');
          expect(job.createdAt, at);
          expect(job.document.lines, isNotEmpty);
        }

        // Persisted to the spool as runnable jobs.
        expect(await h.store.listRunnable(at), hasLength(2));
      },
    );
  });

  group('unroutable items are flagged, not dropped (AC1)', () {
    test(
      'an item with no rule and no default is flagged, others still print',
      () async {
        final order = _order(
          items: [
            _Line('a', 'burger', 'Burger'),
            _Line('b', 'mystery', 'Mystery Item'),
          ],
        );
        final h = _Harness(
          routing: _routing({'grill': _dest('p-grill')}),
          clock: () => at,
        );

        final result = await h.dispatcher.dispatch(
          order,
          // No default station -> 'mystery' cannot route.
          KitchenRoutingRules(itemStation: {'burger': 'grill'}),
        );

        expect(result.enqueuedJobs, hasLength(1));
        expect(result.enqueuedJobs.single.stationId, 'grill');
        expect(result.unroutableItems, hasLength(1));
        expect(result.unroutableItems.single.orderItemId, 'b');
        expect(result.unroutableItems.single.menuItemId, 'mystery');
        expect(result.isFullyRouted, isFalse);
      },
    );
  });

  group('stations with no destination are flagged, not enqueued (AC1/AC3)', () {
    test('a routed station without a printer destination is flagged', () async {
      final order = _order(
        items: [_Line('a', 'burger', 'Burger'), _Line('b', 'beer', 'Beer')],
      );
      // Only 'grill' has a destination in this branch; 'bar' does not.
      final h = _Harness(
        routing: _routing({'grill': _dest('p-grill')}),
        clock: () => at,
      );

      final result = await h.dispatcher.dispatch(
        order,
        KitchenRoutingRules(itemStation: {'burger': 'grill', 'beer': 'bar'}),
      );

      expect(result.enqueuedJobs, hasLength(1));
      expect(result.enqueuedJobs.single.stationId, 'grill');
      expect(result.noDestinationStations, ['bar']);
      expect(result.isFullyRouted, isFalse);
      expect(await h.store.listRunnable(at), hasLength(1));
    });
  });

  group('idempotency (D-022): kitchen:<orderId>:<stationId>', () {
    test('re-dispatching the same order does not duplicate jobs', () async {
      final order = _order(
        items: [_Line('a', 'burger', 'Burger'), _Line('b', 'beer', 'Beer')],
      );
      final h = _Harness(
        routing: _routing({'grill': _dest('p-grill'), 'bar': _dest('p-bar')}),
        clock: () => at,
      );
      final rules = KitchenRoutingRules(
        itemStation: {'burger': 'grill', 'beer': 'bar'},
      );

      final first = await h.dispatcher.dispatch(order, rules);
      final second = await h.dispatcher.dispatch(order, rules);

      // Same job identities; the spool collapsed the duplicates.
      expect(
        second.enqueuedJobs.map((j) => j.id).toSet(),
        first.enqueuedJobs.map((j) => j.id).toSet(),
      );
      expect(await h.store.listRunnable(at), hasLength(2));
    });
  });

  group('void/cancel safety (D-018): never print inactive items', () {
    test('cancelled and voided items are not enqueued or rendered', () async {
      final order = _order(
        items: [
          _Line('a', 'burger', 'Burger'),
          _Line('b', 'fries', 'Fries'),
          _Line('c', 'beer', 'Beer'),
        ],
      );
      order.items
          .firstWhere((i) => i.orderItemId == 'b')
          .cancel('out of stock');
      order.items
          .firstWhere((i) => i.orderItemId == 'c')
          .voidItem('comp', auth);

      final h = _Harness(
        routing: _routing({'kitchen': _dest('p-kitchen')}),
        clock: () => at,
      );

      final result = await h.dispatcher.dispatch(
        order,
        KitchenRoutingRules(defaultStationId: 'kitchen'),
      );

      expect(result.enqueuedJobs, hasLength(1));
      final text = result.enqueuedJobs.single.document.lines
          .whereType<PrintTextLine>()
          .map((l) => l.text)
          .join('\n');
      expect(text, contains('Burger'));
      expect(text, isNot(contains('Fries')));
      expect(text, isNot(contains('Beer')));
    });

    test('a fully-voided order yields no tickets and no jobs', () async {
      final order = _order(items: [_Line('a', 'burger', 'Burger')]);
      order.items.single.voidItem('comp', auth);

      final h = _Harness(
        routing: _routing({'kitchen': _dest('p-kitchen')}),
        clock: () => at,
      );
      final result = await h.dispatcher.dispatch(
        order,
        KitchenRoutingRules(defaultStationId: 'kitchen'),
      );

      expect(result.enqueuedJobs, isEmpty);
      expect(result.noDestinationStations, isEmpty);
      expect(await h.store.listRunnable(at), isEmpty);
    });
  });

  group('branch scope (AC3)', () {
    test('the branch id is carried onto every enqueued job', () async {
      final order = _order(
        branch: 'branch-77',
        items: [_Line('a', 'burger', 'Burger')],
      );
      final h = _Harness(
        routing: _routing({'kitchen': _dest('p-kitchen')}),
        clock: () => at,
      );
      final result = await h.dispatcher.dispatch(
        order,
        KitchenRoutingRules(defaultStationId: 'kitchen'),
      );
      expect(result.enqueuedJobs.single.branchId, 'branch-77');
    });

    test(
      'a branchless order is rejected (cannot scope to a branch printer)',
      () async {
        final order = _order(branch: null, items: [_Line('a', 'burger', 'B')]);
        final h = _Harness(
          routing: _routing({'kitchen': _dest('p-kitchen')}),
          clock: () => at,
        );
        expect(
          () => h.dispatcher.dispatch(
            order,
            KitchenRoutingRules(defaultStationId: 'kitchen'),
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('no hardware / no transport (A6)', () {
    test('dispatch never touches the printer (jobs only queue)', () async {
      final order = _order(items: [_Line('a', 'burger', 'Burger')]);
      final h = _Harness(
        routing: _routing({'kitchen': _dest('p-kitchen')}),
        clock: () => at,
      );
      await h.dispatcher.dispatch(
        order,
        KitchenRoutingRules(defaultStationId: 'kitchen'),
      );
      // The dispatcher enqueues only; nothing is printed until the spool drains.
      expect(h.printer.printed, isEmpty);
    });
  });
}

// ---------------------------------------------------------------------------
// Harness + fixtures.
// ---------------------------------------------------------------------------

class _Harness {
  _Harness({required StationPrinterRouting routing, DateTime Function()? clock})
    : store = InMemoryPrintSpoolStore() {
    final spool = PrintSpool(
      store: store,
      printer: printer,
      auditSink: InMemoryReprintAuditSink(),
    );
    dispatcher = KitchenPrintDispatcher(
      routing: routing,
      spool: spool,
      deviceId: 'dev-1',
      clock: clock,
    );
  }

  final InMemoryPrintSpoolStore store;
  final FakePrinter printer = FakePrinter();
  late final KitchenPrintDispatcher dispatcher;
}

InMemoryStationPrinterRouting _routing(
  Map<String, PrintDestination> byStation,
) => InMemoryStationPrinterRouting(byStation);

PrintDestination _dest(String id, {String? label}) => PrintDestination(
  destinationId: id,
  profile: PrinterProfile.escPos80mm,
  label: label,
);

class _Line {
  _Line(this.lineId, this.menuItemId, this.name, {this.qty = 1});

  final String lineId;
  final String menuItemId;
  final String name;
  final int qty;
}

LocalOrder _order({
  String orderId = 'o1',
  String? branch = 'branch-1',
  required List<_Line> items,
}) {
  final cart = Cart(
    orderId: orderId,
    organizationId: 'org-1',
    restaurantId: 'rest-1',
    branchId: branch,
    currencyCode: 'ILS',
  );
  for (final it in items) {
    cart.addLine(
      CartLine.snapshot(
        lineId: it.lineId,
        menuItemId: it.menuItemId,
        itemNameSnapshot: it.name,
        basePriceMinorSnapshot: 1000,
        currencyCodeSnapshot: 'ILS',
        quantity: it.qty,
      ),
    );
  }
  return LocalOrder.submitFromCart(cart, orderType: OrderType.dineIn);
}
