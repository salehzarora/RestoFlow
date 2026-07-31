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
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/discount_controller.dart'
    show discountRepositoryProvider;
import 'package:restoflow_pos/src/state/order_sync_controller.dart'
    show orderSnapshotRepositoryProvider, posSyncPollIntervalProvider;
import 'package:restoflow_pos/src/widgets/discount_sheet.dart';

/// MONEY-PRODUCTION-PATH-TESTS-002D — DEFECT REPRODUCTION.
///
/// Classification: **DEFECT REPRODUCTION — the corrected stack FAILS this.**
///
/// THE DEFECT. `CartController.applyOrderDiscount` takes no order identity and
/// writes onto whatever order the confirmation currently holds:
///
///   void applyOrderDiscount({required int discountTotalMinor}) {
///     final current = _submittedOrder;
///     if (current == null) return;
///     _submittedOrder = current.copyWith(discountTotalMinor: ...);
///   }
///
/// `DiscountSheet` knows exactly which order it discounted — it passes
/// `orderId: widget.orderId` to the RPC — and then DISCARDS that id when it
/// writes the result into the cart:
///
///   ref.read(cartControllerProvider.notifier)
///      .applyOrderDiscount(discountTotalMinor: result.discountTotalMinor);
///
/// The sheet is reachable for an order that is NOT the confirmation's:
/// `order_action_row.dart` opens it per recent order with
/// `orderId: order.orderId ?? ''`, and `canDiscount` needs only a non-terminal,
/// not-yet-charged order with an id.
///
/// CUSTOMER IMPACT. Order A is on the confirmation screen and its authoritative
/// snapshot has not arrived yet (offline, or the seconds right after submit).
/// The cashier discounts order B. The client writes B's discount onto A. A's
/// confirmation then shows a discount it never received, A's printed customer
/// bill/receipt is built from that contaminated view, and A's payment sheet
/// opens for the under-charged amount. In real mode the SERVER recomputes at
/// `record_payment`, so the cash drawer is protected — the PRINTED CUSTOMER
/// DOCUMENT and the demo-mode payment are not.
///
/// This test is the honest reproduction. It is expected to FAIL on the current
/// code, and it must NOT be weakened to make the suite green: the fix belongs
/// to a separate, bounded corrective phase, not to this tests-only one.

const kBase = 4500;
const k240 = 1500;
// 4500 + 1500 = 6000. Order A owes exactly this and has no discount.
const kOrderATotal = 6000;

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

/// Applies whatever the caller asked for — standing in for the server, which
/// really does discount the order the sheet named.
class _FakeDiscountRepo implements DiscountRepository {
  final List<String> discountedOrderIds = <String>[];

  @override
  Future<OrderDiscount> applyOrderDiscount({
    required String orderId,
    required DiscountType type,
    required int value,
    required String reason,
    required int subtotalMinor,
    required int taxTotalMinor,
    int? expectedRevision,
  }) async {
    discountedOrderIds.add(orderId);
    return const OrderDiscount(discountTotalMinor: 2000, grandTotalMinor: 3000);
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

void main() {
  testWidgets('DEFECT: discounting order B contaminates order A, which is the '
      'order currently on the confirmation screen', (tester) async {
    final discounts = _FakeDiscountRepo();
    final c = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: true),
        ),
        discountRepositoryProvider.overrideWithValue(discounts),
        orderSnapshotRepositoryProvider.overrideWithValue(_EmptySnapshotRepo()),
        posSyncPollIntervalProvider.overrideWithValue(null),
      ],
    );
    addTearDown(c.dispose);

    // ---- ORDER A is submitted and its confirmation is showing.
    final cart = c.read(cartControllerProvider.notifier);
    cart.addItemWithModifiers(_burger, const [_meat240]);
    cart.submitOrder(
      orderType: OrderType.takeaway,
      orderNumber: '#AAAAAA',
      orderId: 'order-A',
    );
    final submittedA = c.read(cartControllerProvider).submittedOrder;
    expect(submittedA, isNotNull, reason: 'A is on the confirmation screen');
    expect(submittedA!.orderId, 'order-A');
    expect(submittedA.subtotalMinor, kOrderATotal);
    expect(submittedA.discountTotalMinor, 0);
    expect(submittedA.grandTotalMinor, kOrderATotal);

    // ---- The cashier discounts a DIFFERENT order, B, from the orders sheet.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => DiscountSheet.show(
                  ctx,
                  // The production call site passes the ROW's order id.
                  orderId: 'order-B',
                  subtotalMinor: 5000,
                  taxTotalMinor: 0,
                  currencyCode: 'ILS',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Enter a fixed 20.00 discount with a reason and apply it.
    final fields = find.byType(TextField);
    expect(fields, findsWidgets, reason: 'the sheet is open');
    await tester.enterText(fields.first, '20');
    await tester.enterText(fields.last, 'manager comp');
    await tester.pump();

    final apply = find.byType(FilledButton);
    expect(apply, findsWidgets);
    await tester.tap(apply.last);
    await tester.pumpAndSettle();

    expect(
      discounts.discountedOrderIds,
      <String>['order-B'],
      reason: 'the SERVER was correctly told to discount B',
    );

    // ---- THE ASSERTION THAT MATTERS.
    final afterA = c.read(cartControllerProvider).submittedOrder!;
    expect(
      afterA.orderId,
      'order-A',
      reason: 'the confirmation is still order A',
    );
    expect(
      afterA.discountTotalMinor,
      0,
      reason:
          "order B's discount must never be written onto order A — "
          "A never received it, yet A's printed bill and payment sheet are "
          'built from this view',
    );
    expect(
      afterA.grandTotalMinor,
      kOrderATotal,
      reason: 'A still owes 60.00; a contaminated view under-charges it',
    );
  });
}
