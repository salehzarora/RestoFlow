import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';

/// POS-SUBMIT-GUARD-001 harness: an outbox repo whose [enqueue] blocks on [_gate]
/// so a submit can be held in flight while a second submit is issued, and which
/// counts enqueue CALLS (a duplicate order would mint a fresh local_operation_id,
/// so this counter — not idempotency — proves the controller-level lock).
class _GatedEnqueueStore implements OutboxRepository {
  _GatedEnqueueStore(this._gate);

  final Future<void> _gate;
  final DemoOutboxStore _inner = DemoOutboxStore(delay: (_) async {});
  int enqueueCount = 0;

  @override
  Future<OutboxEntry> enqueue(OutboxEntry entry) async {
    enqueueCount++;
    await _gate;
    return _inner.enqueue(entry);
  }

  @override
  Future<List<OutboxEntry>> recentEntries() => _inner.recentEntries();

  @override
  Future<OutboxEntry> push(String entryId) => _inner.push(entryId);

  @override
  Future<OutboxEntry> retry(String entryId) => _inner.retry(entryId);
}

CartLineView _line(String id, String name, int qty, int unit) => CartLineView(
  lineId: 'l-$id',
  menuItemId: id,
  name: name,
  quantity: qty,
  unitPriceMinor: unit,
  lineTotalMinor: unit * qty,
  currencyCode: 'ILS',
);

void main() {
  late DemoOutboxStore store;
  late ProviderContainer container;

  setUp(() {
    // No push delay so the lifecycle resolves synchronously in tests.
    store = DemoOutboxStore(delay: (_) async {});
    container = ProviderContainer(
      overrides: [outboxRepositoryProvider.overrideWithValue(store)],
    );
  });
  tearDown(() => container.dispose());

  OutboxController controller() =>
      container.read(outboxControllerProvider.notifier);
  List<OutboxEntry> entries() => container.read(outboxControllerProvider);

  group('OutboxController.submit', () {
    test(
      'enqueues a pending entry with order type, table, items, and totals',
      () async {
        final result = await controller().submit(
          lines: [
            _line('classic-burger', 'Classic Burger', 2, 4200),
            _line('cola', 'Cola', 1, 900),
          ],
          subtotalMinor: 9300,
          currencyCode: 'ILS',
          orderType: OrderType.dineIn,
          tableId: 't3',
          tableLabel: 'T3',
        );

        expect(result.orderNumber, 'DEMO-0001');
        final entry = result.entry;
        expect(entry.syncState, OutboxSyncState.pending);
        expect(entry.operationType, 'order.submit');
        expect(entry.targetEntity, 'order');
        expect(entry.deviceId, kDemoDeviceId);
        expect(entry.localOperationId, 'demo-op-0001');
        expect(entry.summary.orderType, OrderType.dineIn);
        expect(entry.summary.tableLabel, 'T3');
        expect(entry.summary.itemCount, 3);
        expect(entry.summary.subtotalMinor, 9300);

        // Controller state reflects the new entry.
        expect(entries().length, 1);
        expect(entries().first.id, entry.id);
      },
    );

    test(
      'builds a submit_order-shaped payload with integer minor money',
      () async {
        final result = await controller().submit(
          lines: [_line('classic-burger', 'Classic Burger', 2, 4200)],
          subtotalMinor: 8400,
          currencyCode: 'ILS',
          orderType: OrderType.dineIn,
          tableId: 't3',
          tableLabel: 'T3',
        );
        final json =
            jsonDecode(result.entry.payloadJson) as Map<String, dynamic>;

        expect(json['order_id'], 'demo-order-0001');
        expect(json['local_operation_id'], 'demo-op-0001');
        expect(json['device_id'], kDemoDeviceId);
        expect(json['order_type'], 'dine_in');
        expect(json['table_id'], 't3');
        expect(json['currency_code'], 'ILS');
        expect(json['subtotal_minor'], 8400);
        expect(json['grand_total_minor'], 8400);
        // Money fields are integers, never floats (DECISION D-007).
        expect(json['subtotal_minor'], isA<int>());
        expect(json['grand_total_minor'], isA<int>());

        final items = json['order_items'] as List<dynamic>;
        expect(items, hasLength(1));
        final item = items.first as Map<String, dynamic>;
        expect(item['menu_item_id'], 'classic-burger');
        expect(item['menu_item_name_snapshot'], 'Classic Burger');
        expect(item['quantity'], 2);
        expect(item['unit_price_minor_snapshot'], 4200);
        expect(item['line_total_minor'], 8400);
        expect(item['unit_price_minor_snapshot'], isA<int>());
      },
    );

    test('an empty cart cannot be submitted', () {
      expect(
        () => controller().submit(
          lines: const [],
          subtotalMinor: 0,
          currencyCode: 'ILS',
          orderType: OrderType.takeaway,
        ),
        throwsA(isA<OrderSubmissionException>()),
      );
    });

    test('a dine-in order without a table cannot be submitted', () {
      expect(
        () => controller().submit(
          lines: [_line('cola', 'Cola', 1, 900)],
          subtotalMinor: 900,
          currencyCode: 'ILS',
          orderType: OrderType.dineIn,
        ),
        throwsA(isA<OrderSubmissionException>()),
      );
    });

    test('a takeaway order submits without a table', () async {
      final result = await controller().submit(
        lines: [_line('cola', 'Cola', 1, 900)],
        subtotalMinor: 900,
        currencyCode: 'ILS',
        orderType: OrderType.takeaway,
      );
      expect(result.entry.summary.tableLabel, isNull);
      final json = jsonDecode(result.entry.payloadJson) as Map<String, dynamic>;
      expect(json['order_type'], 'takeaway');
      expect(json['table_id'], isNull);
    });

    test('POS-SUBMIT-GUARD-001: a concurrent submit joins the in-flight one — '
        'one order enqueued, not two', () async {
      final gate = Completer<void>();
      final gated = _GatedEnqueueStore(gate.future);
      final c = ProviderContainer(
        overrides: [outboxRepositoryProvider.overrideWithValue(gated)],
      );
      addTearDown(c.dispose);
      final ctrl = c.read(outboxControllerProvider.notifier);

      // First submit starts and blocks in enqueue (in flight). A second submit
      // issued before it settles must JOIN it — the same future, not a new order
      // (this is what survives a phone cart-sheet dismiss/reopen that drops the
      // widget-local guard).
      final f1 = ctrl.submit(
        lines: [_line('cola', 'Cola', 1, 900)],
        subtotalMinor: 900,
        currencyCode: 'ILS',
        orderType: OrderType.takeaway,
      );
      final f2 = ctrl.submit(
        lines: [_line('cola', 'Cola', 1, 900)],
        subtotalMinor: 900,
        currencyCode: 'ILS',
        orderType: OrderType.takeaway,
      );
      expect(identical(f1, f2), isTrue);

      gate.complete();
      final r1 = await f1;
      final r2 = await f2;
      expect(r1.entry.id, r2.entry.id);
      expect(gated.enqueueCount, 1);

      // Once it settles the lock releases, so a genuinely new order can submit.
      final r3 = await ctrl.submit(
        lines: [_line('cola', 'Cola', 1, 900)],
        subtotalMinor: 900,
        currencyCode: 'ILS',
        orderType: OrderType.takeaway,
      );
      expect(r3.entry.id, isNot(r1.entry.id));
      expect(gated.enqueueCount, 2);
    });
  });

  group('outbox sync lifecycle', () {
    Future<OutboxEntry> submitOne() async {
      final r = await controller().submit(
        lines: [_line('cola', 'Cola', 1, 900)],
        subtotalMinor: 900,
        currencyCode: 'ILS',
        orderType: OrderType.takeaway,
      );
      return r.entry;
    }

    test('pushing a pending entry reaches applied', () async {
      final entry = await submitOne();
      await controller().pushEntry(entry.id);
      expect(entries().first.syncState, OutboxSyncState.applied);
    });

    test(
      'a failed push is marked failed and can be retried to success',
      () async {
        final entry = await submitOne();
        store.nextPushFails = true;
        await controller().pushEntry(entry.id);
        expect(entries().first.syncState, OutboxSyncState.rejected);
        expect(entries().first.syncState.isFailed, isTrue);

        await controller().retryEntry(entry.id);
        expect(entries().first.syncState, OutboxSyncState.applied);
      },
    );

    test('pendingCount drops once an entry is delivered', () async {
      final entry = await submitOne();
      expect(controller().pendingCount, 1);
      await controller().pushEntry(entry.id);
      expect(controller().pendingCount, 0);
    });
  });

  group('DemoOutboxStore', () {
    OutboxEntry sample(String localOp) => OutboxEntry(
      id: 'outbox-$localOp',
      deviceId: 'demo-device',
      localOperationId: localOp,
      operationType: 'order.submit',
      targetEntity: 'order',
      targetId: 'order-$localOp',
      payloadJson: '{}',
      summary: const OrderSummary(
        orderNumber: 'DEMO-1',
        orderType: OrderType.takeaway,
        tableLabel: null,
        itemCount: 1,
        subtotalMinor: 900,
        currencyCode: 'ILS',
      ),
      syncState: OutboxSyncState.pending,
      clientCreatedAt: DateTime(2026, 6, 28),
    );

    test('enqueue is idempotent on (deviceId, localOperationId)', () async {
      final a = await store.enqueue(sample('op-1'));
      final b = await store.enqueue(sample('op-1'));
      expect(a.id, b.id);
      expect((await store.recentEntries()), hasLength(1));
    });

    test('an enqueue-failing store throws (cart is kept upstream)', () {
      final failing = DemoOutboxStore(enqueueFails: true);
      expect(
        () => failing.enqueue(sample('op-2')),
        throwsA(isA<OrderSubmissionException>()),
      );
    });
  });
}
