import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';

/// MONEY-VOID-001: the app-bar unpaid-orders badge ([RecentOrdersButton]) counts
/// only orders that are still awaiting payment. A cancelled (voided) order — like
/// a paid one — is no longer active work and must drop off the badge the instant
/// it is cancelled, with NO app restart. When nothing is unpaid the badge is
/// hidden entirely (the previous UX).
SubmittedOrderView _view(String number) => SubmittedOrderView(
  orderNumber: number,
  orderType: OrderType.takeaway,
  currencyCode: 'ILS',
  subtotalMinor: 4200,
  orderId: 'oid-$number',
  lines: [
    SubmittedLineView(
      name: 'Burger',
      quantity: 1,
      lineTotalMinor: 4200,
      currencyCode: 'ILS',
    ),
  ],
);

CashPayment _payment(String number) => CashPayment(
  paymentId: 'pay-$number',
  orderNumber: number,
  deviceId: 'd1',
  localOperationId: 'op-$number',
  method: PaymentMethod.cash,
  status: PaymentStatus.completed,
  amountMinor: 4200,
  tenderedMinor: 4200,
  changeMinor: 0,
  currencyCode: 'ILS',
  receiptNumber: 'R-1',
  paidAt: DateTime.now(),
);

Widget _wrap(InMemoryRecentOrdersStore store) => ProviderScope(
  overrides: [posRecentOrdersStoreProvider.overrideWithValue(store)],
  child: MaterialApp(
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: const Scaffold(
      appBar: null,
      body: Center(child: RecentOrdersButton()),
    ),
  ),
);

/// The badge text (e.g. "2"), or null when no [Badge] is shown.
String? _badgeText(WidgetTester tester) {
  final badge = tester.widgetList<Badge>(find.byType(Badge));
  if (badge.isEmpty) return null;
  final label = badge.first.label;
  if (label is Text) return label.data;
  return null;
}

void main() {
  testWidgets('the badge counts unpaid orders and hides at zero', (
    tester,
  ) async {
    final store = InMemoryRecentOrdersStore();
    await tester.pumpWidget(_wrap(store));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RecentOrdersButton)),
    );
    final notifier = container.read(posRecentOrdersControllerProvider.notifier);

    // No orders -> no badge at all.
    await tester.pumpAndSettle();
    expect(find.byType(Badge), findsNothing);

    // Two unpaid (pay-later) orders -> badge shows 2.
    notifier
      ..recordSubmitted(_view('#U1'))
      ..recordSubmitted(_view('#U2'));
    await tester.pump();
    expect(_badgeText(tester), '2');

    // Cancel one -> badge decrements to 1 immediately (no restart).
    notifier.markVoided('#U1', 'wrong order');
    await tester.pump();
    expect(_badgeText(tester), '1');

    // Cancel the last -> badge disappears (count 0 hides it).
    notifier.markVoided('#U2', 'also wrong');
    await tester.pump();
    expect(find.byType(Badge), findsNothing);
  });

  testWidgets('a paid order does not count toward the badge', (tester) async {
    final store = InMemoryRecentOrdersStore();
    await tester.pumpWidget(_wrap(store));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RecentOrdersButton)),
    );
    final notifier = container.read(posRecentOrdersControllerProvider.notifier);

    notifier
      ..recordSubmitted(_view('#U1'))
      ..recordSubmitted(_view('#P1'));
    await tester.pump();
    expect(_badgeText(tester), '2');

    // Paying one drops it off the badge (paid is not "awaiting payment").
    notifier.recordPayment('#P1', _payment('#P1'));
    await tester.pump();
    expect(_badgeText(tester), '1');
  });

  testWidgets(
    'a cancelled order is excluded even while its submit is unsynced',
    (tester) async {
      // Pre-seed a voided order (payment == null): !isPaid is true, so only the
      // voided check keeps it off the badge. Sync state is irrelevant here.
      final store = InMemoryRecentOrdersStore();
      await store.persist(kDemoSyncScope.key, [
        PosRecentOrder(
          order: _view('#V1'),
          submittedAt: DateTime.now(),
          voidedAt: DateTime.now(),
          voidReason: 'cancelled',
        ),
        PosRecentOrder(order: _view('#U1'), submittedAt: DateTime.now()),
      ]);
      await tester.pumpWidget(_wrap(store));
      await tester.pumpAndSettle();

      // Only the one genuinely-unpaid order is counted.
      expect(_badgeText(tester), '1');
    },
  );
}
