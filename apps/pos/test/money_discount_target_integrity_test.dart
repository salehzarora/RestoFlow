import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/discount.dart';
import 'package:restoflow_pos/src/data/discount_repository.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/order_snapshot_repository.dart';
import 'package:restoflow_pos/src/format/money_format.dart';
import 'package:restoflow_pos/src/print/print_document.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/discount_controller.dart'
    show discountRepositoryProvider;
import 'package:restoflow_pos/src/state/order_sync_controller.dart'
    show orderSnapshotRepositoryProvider, posSyncPollIntervalProvider;
import 'package:restoflow_pos/src/widgets/discount_sheet.dart';
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart'
    show buildBillDocument;

/// MONEY-DISCOUNT-TARGET-INTEGRITY-002E — the ASYNC RACE and DOCUMENT
/// ISOLATION half of the cross-order defect.
///
/// `money_cross_order_discount_defect_test.dart` (committed in 002D) is the
/// primary reproduction: discounting order B contaminates order A. This suite
/// adds the cases that a UI-level fix would still get wrong — a response that
/// arrives after the held confirmation has CHANGED, two responses resolving in
/// REVERSE order, and the customer document / payment amount built from a
/// contaminated view.
///
/// Every case drives the REAL `DiscountSheet` widget, the REAL
/// `discountRepositoryProvider` seam and the REAL `CartController`. The fake
/// stands only at the repository boundary, where it also RECORDS which order
/// the server was told to discount — so a test can never confuse "the server
/// was asked correctly" with "the right local order changed".
///
/// Every expected amount is an INDEPENDENT LITERAL.

const kBase = 4500;
const k240 = 1500;
// 4500 + 1500 = 6000 per unit; x 2 = 12000. Written out, never computed.
const kConfiguredUnit = 6000;
const kOrderTotal = 12000;
const kDiscount = 2000;
// 12000 - 2000 = 10000.
const kDiscountedTotal = 10000;

const _burger = DemoMenuItem(
  id: 'burger-meat',
  name: 'Burger',
  priceMinor: kBase,
  categoryId: 'food',
  categoryName: 'Food',
);

const _meat240 = SelectedModifier(
  optionId: 'opt-240',
  modifierGroupId: 'grp-meat',
  groupName: 'Meat',
  optionName: '240g',
  priceDeltaMinor: k240,
);

/// Records the order the SERVER was told to discount, and can hold each
/// response open so a test can resolve them in any order it likes.
class _GatedDiscountRepo implements DiscountRepository {
  final List<String> requestedOrderIds = <String>[];
  final Map<String, Completer<OrderDiscount>> gates =
      <String, Completer<OrderDiscount>>{};

  /// When false, a response resolves immediately with [immediateDiscount].
  bool gate = false;
  int immediateDiscount = kDiscount;

  @override
  Future<OrderDiscount> applyOrderDiscount({
    required String orderId,
    required DiscountType type,
    required int value,
    required String reason,
    required int subtotalMinor,
    required int taxTotalMinor,
    int? expectedRevision,
  }) {
    requestedOrderIds.add(orderId);
    if (!gate) {
      return Future.value(
        OrderDiscount(
          discountTotalMinor: immediateDiscount,
          grandTotalMinor: subtotalMinor - immediateDiscount,
        ),
      );
    }
    final completer = Completer<OrderDiscount>();
    gates[orderId] = completer;
    return completer.future;
  }

  void release(String orderId, {int discountTotalMinor = kDiscount}) {
    gates
        .remove(orderId)!
        .complete(
          OrderDiscount(
            discountTotalMinor: discountTotalMinor,
            grandTotalMinor: kOrderTotal - discountTotalMinor,
          ),
        );
  }
}

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

ProviderContainer harness(_GatedDiscountRepo repo) {
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
      discountRepositoryProvider.overrideWithValue(repo),
      orderSnapshotRepositoryProvider.overrideWithValue(_EmptySnapshotRepo()),
      posSyncPollIntervalProvider.overrideWithValue(null),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Puts [orderId] on the confirmation, priced 2 x (4500 + 1500) = 12000.
void holdConfirmationFor(ProviderContainer c, String orderId) {
  final cart = c.read(cartControllerProvider.notifier);
  cart.startNewOrder();
  cart.addItemWithModifiers(_burger, const [_meat240]);
  final lineId = c.read(cartControllerProvider).lines.single.lineId;
  cart.increaseQuantity(lineId);
  expect(
    c.read(cartControllerProvider).lines.single.lineTotalMinor,
    kOrderTotal,
  );
  cart.submitOrder(
    orderType: OrderType.takeaway,
    orderNumber: '#${orderId.toUpperCase()}',
    orderId: orderId,
  );
  final held = c.read(cartControllerProvider).submittedOrder!;
  expect(held.orderId, orderId);
  expect(held.subtotalMinor, kOrderTotal);
  expect(held.discountTotalMinor, 0);
}

SubmittedOrderViewSnapshot snapshotOf(ProviderContainer c) {
  final v = c.read(cartControllerProvider).submittedOrder!;
  return (
    orderId: v.orderId,
    subtotal: v.subtotalMinor,
    discount: v.discountTotalMinor,
    tax: v.taxTotalMinor,
    grand: v.grandTotalMinor,
  );
}

typedef SubmittedOrderViewSnapshot = ({
  String? orderId,
  int subtotal,
  int discount,
  int tax,
  int grand,
});

/// Pumps ONE host carrying a button per order — the shape of the Orders sheet,
/// where every recent-order row can open the discount sheet for its own order.
Future<void> pumpHost(
  WidgetTester tester,
  ProviderContainer c, {
  List<String> orderIds = const ['order-A', 'order-B'],
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Column(
              children: [
                for (final id in orderIds)
                  TextButton(
                    key: Key('open-$id'),
                    onPressed: () => DiscountSheet.show(
                      ctx,
                      // Exactly what order_action_row.dart passes per row.
                      orderId: id,
                      subtotalMinor: kOrderTotal,
                      taxTotalMinor: 0,
                      currencyCode: 'ILS',
                    ),
                    child: Text('open $id'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Opens [orderId]'s sheet and taps Apply with a fixed 20.00 discount.
Future<void> applyDiscount(WidgetTester tester, String orderId) async {
  await tester.tap(find.byKey(Key('open-$orderId')));
  await tester.pumpAndSettle();
  final fields = find.byType(TextField);
  expect(fields, findsWidgets, reason: 'the real sheet is open');
  await tester.enterText(fields.first, '20');
  await tester.enterText(fields.last, 'manager comp');
  await tester.pump();
  await tester.tap(find.byType(FilledButton).last);
  await tester.pump();
}

/// Dismisses a sheet that is still waiting on its gated response.
Future<void> dismissSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(20, 20));
  await tester.pump();
}

String money(int minor) => MoneyFormatter.formatMinor(minor, 'ILS');

/// The amount-due value the REAL bill document prints.
String billAmountDue(AppLocalizations l10n, ProviderContainer c) {
  final doc = buildBillDocument(
    l10n,
    c.read(cartControllerProvider).submittedOrder!,
    isDemo: true,
  );
  return doc.lines
      .firstWhere((PrintLine l) => l.left == l10n.receiptAmountDueLabel)
      .right!;
}

void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('C1 STALE RESPONSE: a discount started for A must not mutate B '
      'when the held confirmation changes before it resolves', (tester) async {
    final repo = _GatedDiscountRepo()..gate = true;
    final c = harness(repo);

    holdConfirmationFor(c, 'order-A');
    await pumpHost(tester, c);
    await applyDiscount(
      tester,
      'order-A',
    ); // A's request is now in flight, un-resolved
    expect(repo.requestedOrderIds, <String>['order-A']);

    // The cashier moves on: confirmation B is now held.
    holdConfirmationFor(c, 'order-B');
    final beforeB = snapshotOf(c);
    expect(beforeB.orderId, 'order-B');
    expect(beforeB.discount, 0);

    // A's late response finally arrives.
    repo.release('order-A');
    await tester.pumpAndSettle();

    final afterB = snapshotOf(c);
    expect(
      afterB.discount,
      0,
      reason: "A's late response must never land on B",
    );
    expect(afterB.subtotal, kOrderTotal);
    expect(afterB.grand, kOrderTotal);
    expect(afterB.orderId, 'order-B');
  });

  testWidgets('F1 REVERSE RESOLUTION: with A and B both in flight, only the '
      'response matching the held confirmation may mutate it', (tester) async {
    final repo = _GatedDiscountRepo()..gate = true;
    final c = harness(repo);

    // SCOPE NOTE, stated rather than faked. Two discount RPCs cannot actually
    // be in flight at once through the UI: the sheet stays open until its own
    // response arrives, and dismissing it mid-flight hits a PRE-EXISTING
    // disposal hazard (`_apply` reads `ref` after the await to refresh orders,
    // guarded by `if (!mounted)` only AFTERWARDS) that is not money and is out
    // of this phase's bounded scope — it is recorded as a residual risk.
    //
    // So the reverse-resolution contract is proven where it actually lives: at
    // the mutation boundary, by delivering the two responses to the controller
    // in reverse order with their true target ids. This is the same call the
    // sheet makes, and C1/H1/H2 above already prove the widget path.
    holdConfirmationFor(c, 'order-A');
    final cart = c.read(cartControllerProvider.notifier);

    // B becomes the held confirmation while A's request is still outstanding.
    holdConfirmationFor(c, 'order-B');

    // B's response lands first — B is held, so B legitimately updates.
    cart.applyOrderDiscount(orderId: 'order-B', discountTotalMinor: kDiscount);
    expect(
      snapshotOf(c).discount,
      kDiscount,
      reason: 'B is held, so B may update',
    );

    // Then A's stale response arrives with a DIFFERENT amount.
    cart.applyOrderDiscount(orderId: 'order-A', discountTotalMinor: 500);

    final finalB = snapshotOf(c);
    expect(
      finalB.discount,
      kDiscount,
      reason: "last-response-wins would have written A's 500 onto B",
    );
    expect(finalB.grand, kDiscountedTotal);
    expect(finalB.orderId, 'order-B');
    expect(finalB.subtotal, kOrderTotal);
  });

  testWidgets('H1 DOCUMENT ISOLATION: discounting B while A is held leaves '
      "A's printed bill amount untouched", (tester) async {
    final repo = _GatedDiscountRepo();
    final c = harness(repo);

    holdConfirmationFor(c, 'order-A');
    final dueBefore = billAmountDue(l10n, c);
    expect(dueBefore, money(kOrderTotal));

    await pumpHost(tester, c);
    await applyDiscount(tester, 'order-B');
    await tester.pumpAndSettle();

    expect(
      repo.requestedOrderIds,
      <String>['order-B'],
      reason: 'the SERVER was correctly told to discount B',
    );
    expect(
      billAmountDue(l10n, c),
      money(kOrderTotal),
      reason: "A's customer document must not print B's discount",
    );
    final a = snapshotOf(c);
    expect(a.orderId, 'order-A');
    expect(a.discount, 0);
    expect(
      a.grand,
      kOrderTotal,
      reason: 'the payment sheet opens on this exact amount',
    );
  });

  testWidgets('H2 PAYMENT ISOLATION: the amount A would be charged is '
      'unchanged by a discount applied to B', (tester) async {
    final repo = _GatedDiscountRepo();
    final c = harness(repo);

    holdConfirmationFor(c, 'order-A');
    await pumpHost(tester, c);
    await applyDiscount(tester, 'order-B');
    await tester.pumpAndSettle();

    // `order_confirmation.dart` hands grandTotalMinor to the payment sheet.
    expect(
      c.read(cartControllerProvider).submittedOrder!.grandTotalMinor,
      kOrderTotal,
      reason: 'A still owes 120.00 — an under-charge here is real money',
    );
  });

  testWidgets('H3 the surcharge is still inside the protected amount — this '
      'is not passing because the money was already lost', (tester) async {
    final repo = _GatedDiscountRepo();
    final c = harness(repo);

    holdConfirmationFor(c, 'order-A');
    final held = c.read(cartControllerProvider).submittedOrder!;
    expect(held.lines.single.lineTotalMinor, kOrderTotal);
    expect(
      held.subtotalMinor,
      kOrderTotal,
      reason: '2 x (4500 + 1500) — the 002A configured-unit rule',
    );

    await pumpHost(tester, c);
    await applyDiscount(tester, 'order-B');
    await tester.pumpAndSettle();

    final after = c.read(cartControllerProvider).submittedOrder!;
    expect(after.lines.single.lineTotalMinor, kOrderTotal);
    expect(after.subtotalMinor, kOrderTotal);
    expect(
      after.grandTotalMinor,
      kOrderTotal,
      reason: 'no surcharge lost, no discount gained',
    );
  });
}
