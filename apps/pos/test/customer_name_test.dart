import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_tables.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/order_setup_section.dart';
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart'
    show buildReceiptDocument;

/// ORDER-CUSTOMER-001: the OPTIONAL customer display name. It is trimmed +
/// empty->null + capped at 80, never gates submit, survives order-type/table
/// changes, clears on reset, rides the outbox payload (surviving offline), and
/// its "Optional" hint renders under ar/he. Money/tax is never touched.

DemoTable _table(String id) => DemoTable(
  table: DiningTable(
    tableId: id,
    label: id.toUpperCase(),
    organizationId: 'demo-org',
    restaurantId: 'demo-restaurant',
    branchId: 'demo-branch',
    seats: 4,
    isActive: true,
  ),
  status: TableStatusKind.available,
);

class _RecordingTransport implements SyncRpcTransport {
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> p) async {
    params.add(p);
    return <String, dynamic>{
      'ok': true,
      'results': <dynamic>[
        {
          'local_operation_id':
              (p['p_operations'] as List).first['local_operation_id'],
          'operation_type': 'order.submit',
          'ok': true,
          'status': 'applied',
          'idempotency_replay': false,
        },
      ],
      'server_ts': '2026-07-07T09:00:01Z',
    };
  }
}

void main() {
  group('normalizeCustomerName', () {
    test('trims and treats empty/whitespace as null', () {
      expect(normalizeCustomerName('  Sara Cohen  '), 'Sara Cohen');
      expect(normalizeCustomerName(''), isNull);
      expect(normalizeCustomerName('   '), isNull);
      expect(normalizeCustomerName(null), isNull);
    });

    test('caps at 80 chars', () {
      final long = 'a' * 100;
      expect(normalizeCustomerName(long)!.length, 80);
    });

    test('preserves Arabic/Hebrew display names', () {
      expect(normalizeCustomerName(' محمد '), 'محمد');
      expect(normalizeCustomerName('דנה'), 'דנה');
    });
  });

  group('OrderSetupController.setCustomerName', () {
    late ProviderContainer c;
    late OrderSetupController ctrl;
    setUp(() {
      c = ProviderContainer();
      addTearDown(c.dispose);
      ctrl = c.read(orderSetupControllerProvider.notifier);
    });

    test('normalizes (trim + empty->null) and stores', () {
      ctrl.setCustomerName('  Dana  ');
      expect(c.read(orderSetupControllerProvider).customerName, 'Dana');
      ctrl.setCustomerName('   ');
      expect(c.read(orderSetupControllerProvider).customerName, isNull);
    });

    test('SURVIVES an order-type switch (not silently dropped)', () {
      ctrl.setCustomerName('Dana');
      ctrl.setOrderType(OrderType.dineIn);
      expect(c.read(orderSetupControllerProvider).orderType, OrderType.dineIn);
      expect(c.read(orderSetupControllerProvider).customerName, 'Dana');
    });

    test('SURVIVES assigning and clearing a table', () {
      ctrl.setOrderType(OrderType.dineIn);
      ctrl.setCustomerName('Dana');
      ctrl.assignTable(_table('t1'));
      expect(c.read(orderSetupControllerProvider).customerName, 'Dana');
      ctrl.clearTable();
      expect(c.read(orderSetupControllerProvider).customerName, 'Dana');
    });

    test('is cleared by reset() (after submit / new order)', () {
      ctrl.setCustomerName('Dana');
      ctrl.reset();
      expect(c.read(orderSetupControllerProvider).customerName, isNull);
    });

    test('never affects submit-readiness', () {
      // Takeaway is always ready, with or without a name.
      expect(c.read(orderSetupControllerProvider).isReadyToSubmit, isTrue);
      ctrl.setCustomerName('Dana');
      expect(c.read(orderSetupControllerProvider).isReadyToSubmit, isTrue);
      // Dine-in without a table is NOT ready — a name does not change that.
      ctrl.setOrderType(OrderType.dineIn);
      final s = c.read(orderSetupControllerProvider);
      expect(s.isReadyToSubmit, isFalse);
      expect(s.needsTableWarning, isTrue);
    });
  });

  group('OrderSubmissionPayload.toJson', () {
    OrderSubmissionPayload payload({String? name}) => OrderSubmissionPayload(
      orderId: 'o1',
      localOperationId: 'op1',
      deviceId: 'd1',
      organizationId: 'org',
      restaurantId: 'rest',
      branchId: 'branch',
      orderType: OrderType.takeaway,
      currencyCode: 'ILS',
      subtotalMinor: 1000,
      grandTotalMinor: 1000,
      items: const [],
      clientCreatedAt: DateTime.utc(2026, 7, 7),
      customerName: name,
    );

    test('emits customer_name when present', () {
      expect(payload(name: 'Dana').toJson()['customer_name'], 'Dana');
    });
    test('emits customer_name: null when absent (backward compatible)', () {
      final json = payload().toJson();
      expect(json.containsKey('customer_name'), isTrue);
      expect(json['customer_name'], isNull);
      // money fields are untouched.
      expect(json['grand_total_minor'], 1000);
    });
  });

  group('outbox -> public.sync_push op payload', () {
    test(
      'forwards customer_name into the pushed op (survives offline queue)',
      () async {
        final payload = OrderSubmissionPayload(
          orderId: 'order-1',
          localOperationId: 'op-1',
          deviceId: 'device-abc',
          organizationId: 'org',
          restaurantId: 'rest',
          branchId: 'branch',
          orderType: OrderType.takeaway,
          currencyCode: 'ILS',
          subtotalMinor: 1000,
          grandTotalMinor: 1000,
          items: const [
            OrderSubmissionItem(
              menuItemId: 'm1',
              nameSnapshot: 'Item',
              quantity: 1,
              unitPriceMinorSnapshot: 1000,
              lineTotalMinor: 1000,
            ),
          ],
          clientCreatedAt: DateTime.utc(2026, 7, 7, 9),
          customerName: 'Sara Cohen',
        );
        final entry = OutboxEntry(
          id: 'outbox-op-1',
          deviceId: 'device-abc',
          localOperationId: 'op-1',
          operationType: 'order.submit',
          targetEntity: 'order',
          targetId: 'order-1',
          // The durable payloadJson carries the name — it survives a refresh/restart.
          payloadJson: jsonEncode(payload.toJson()),
          summary: const OrderSummary(
            orderNumber: 'DEMO-1',
            orderType: OrderType.takeaway,
            tableLabel: null,
            itemCount: 1,
            subtotalMinor: 1000,
            currencyCode: 'ILS',
            customerName: 'Sara Cohen',
          ),
          syncState: OutboxSyncState.pending,
          clientCreatedAt: DateTime.utc(2026, 7, 7, 9),
        );
        final transport = _RecordingTransport();
        final repo = RealOutboxRepository(
          transport,
          const SyncSession(pinSessionId: 'pin-1', deviceId: 'device-abc'),
        );
        await repo.enqueue(entry);
        await repo.push(entry.id);

        final op =
            (transport.params.single['p_operations'] as List).single
                as Map<String, dynamic>;
        final opPayload = op['payload'] as Map<String, dynamic>;
        expect(opPayload['customer_name'], 'Sara Cohen');
      },
    );

    test('a null-customer / pre-feature entry keeps the EXACT pre-feature wire '
        'shape (no customer_name key -> server fingerprint unchanged)', () async {
      // A pre-feature durable outbox entry: its payloadJson has NO customer_name
      // key at all. The wire op must not gain one, or the server idempotency
      // fingerprint (md5 over the payload) would change and break replay.
      final legacyPayloadJson = jsonEncode(<String, Object?>{
        'order_id': 'order-2',
        'order_type': 'takeaway',
        'table_id': null,
        'currency_code': 'ILS',
        'notes': null,
        'subtotal_minor': 1000,
        'discount_total_minor': 0,
        'tax_total_minor': 0,
        'grand_total_minor': 1000,
        'order_items': const <Object?>[],
      });
      final entry = OutboxEntry(
        id: 'outbox-op-2',
        deviceId: 'device-abc',
        localOperationId: 'op-2',
        operationType: 'order.submit',
        targetEntity: 'order',
        targetId: 'order-2',
        payloadJson: legacyPayloadJson,
        summary: const OrderSummary(
          orderNumber: 'DEMO-2',
          orderType: OrderType.takeaway,
          tableLabel: null,
          itemCount: 0,
          subtotalMinor: 1000,
          currencyCode: 'ILS',
        ),
        syncState: OutboxSyncState.pending,
        clientCreatedAt: DateTime.utc(2026, 7, 7, 9),
      );
      final transport = _RecordingTransport();
      final repo = RealOutboxRepository(
        transport,
        const SyncSession(pinSessionId: 'pin-1', deviceId: 'device-abc'),
      );
      await repo.enqueue(entry);
      await repo.push(entry.id);

      final op =
          (transport.params.single['p_operations'] as List).single
              as Map<String, dynamic>;
      final opPayload = op['payload'] as Map<String, dynamic>;
      expect(opPayload.containsKey('customer_name'), isFalse);
    });
  });

  group('OrderSetupSection customer-name field', () {
    Future<void> pump(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
    }) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const Scaffold(
              body: SingleChildScrollView(child: OrderSetupSection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders the optional field with the localized hint', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await pump(tester);
      expect(find.byKey(const Key('customer-name-field')), findsOneWidget);
      expect(find.text(l10n.customerNameLabel), findsWidgets);
      expect(find.text(l10n.customerNamePlaceholder), findsWidgets);
    });

    testWidgets('typing a name updates the order-setup state (trimmed)', (
      tester,
    ) async {
      await pump(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OrderSetupSection)),
      );
      await tester.enterText(
        find.byKey(const Key('customer-name-field')),
        '  Dana  ',
      );
      await tester.pump();
      expect(container.read(orderSetupControllerProvider).customerName, 'Dana');
    });

    testWidgets('an empty name never blocks submit (takeaway stays ready)', (
      tester,
    ) async {
      await pump(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OrderSetupSection)),
      );
      // Field left empty.
      final s = container.read(orderSetupControllerProvider);
      expect(s.customerName, isNull);
      expect(s.isReadyToSubmit, isTrue);
    });

    testWidgets('renders under Arabic RTL with the localized hint', (
      tester,
    ) async {
      final ar = await AppLocalizations.delegate.load(const Locale('ar'));
      await pump(tester, locale: const Locale('ar'));
      expect(find.byKey(const Key('customer-name-field')), findsOneWidget);
      expect(find.text(ar.customerNameLabel), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('live cashier receipt document (buildReceiptDocument)', () {
    CashPayment payment() => CashPayment(
      paymentId: 'pay-1',
      orderNumber: '#ABC',
      deviceId: 'd1',
      localOperationId: 'op1',
      method: PaymentMethod.cash,
      status: PaymentStatus.completed,
      amountMinor: 1000,
      tenderedMinor: 1000,
      changeMinor: 0,
      currencyCode: 'ILS',
      receiptNumber: 'R-1',
      paidAt: DateTime.utc(2026, 7, 7, 12),
    );
    SubmittedOrderView order({String? name}) => SubmittedOrderView(
      orderNumber: '#ABC',
      orderType: OrderType.takeaway,
      currencyCode: 'ILS',
      subtotalMinor: 1000,
      customerName: name,
      lines: const [
        SubmittedLineView(
          name: 'Item',
          quantity: 1,
          lineTotalMinor: 1000,
          currencyCode: 'ILS',
        ),
      ],
    );

    test(
      'prints a customer row when a name is present, money intact',
      () async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final doc = buildReceiptDocument(
          l10n,
          order(name: 'Sara Cohen'),
          payment(),
        );
        // PRINT-LAYOUT-001: the customer name prints as a grouped, centered
        // header line ("Customer: <name>").
        expect(
          doc.lines.any(
            (l) =>
                (l.left ?? '') ==
                '${l10n.customerNameReceiptLabel}: Sara Cohen',
          ),
          isTrue,
        );
        // The total is still rendered (money untouched).
        final kv = doc.lines
            .map((l) => '${l.left ?? ''}=${l.right ?? ''}')
            .toList();
        expect(kv.any((s) => s.contains('₪10.00')), isTrue);
      },
    );

    test(
      'prints NO customer row when absent (existing receipts unchanged)',
      () async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final doc = buildReceiptDocument(l10n, order(), payment());
        final hasCustomer = doc.lines.any(
          (l) => (l.left ?? '').startsWith('${l10n.customerNameReceiptLabel}:'),
        );
        expect(hasCustomer, isFalse);
      },
    );
  });
}
