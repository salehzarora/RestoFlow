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

/// MONEY-DISCOUNT-TARGET-INTEGRITY-002E — what the identity guard must KEEP
/// working, and where it must decline.
///
/// The cross-order and race proofs live in
/// `money_cross_order_discount_defect_test.dart` (002D) and
/// `money_discount_target_integrity_test.dart`. This suite pins the other half:
/// a MATCHING order still updates immediately and exactly once, the declining
/// cases decline safely, full comp inherits the guard, and 002A configured
/// modifier money survives a discount untouched.
///
/// Every expected amount is an INDEPENDENT LITERAL.

const kBase = 4500;
const k240 = 1500;
// 2 x (4500 + 1500) = 12000. Never computed from a production helper.
const kOrderTotal = 12000;
const kDiscount = 2000;
const kDiscountedTotal = 10000; // 12000 - 2000

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

class _Repo implements DiscountRepository {
  _Repo({this.discount = kDiscount});
  final int discount;
  final List<String> requestedOrderIds = <String>[];

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
    requestedOrderIds.add(orderId);
    return OrderDiscount(
      discountTotalMinor: discount,
      grandTotalMinor: subtotalMinor - discount,
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

ProviderContainer harness(_Repo repo) {
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

/// Holds [orderId] on the confirmation at 2 x (4500 + 1500) = 12000.
void holdConfirmationFor(ProviderContainer c, String? orderId) {
  final cart = c.read(cartControllerProvider.notifier);
  cart.startNewOrder();
  cart.addItemWithModifiers(_burger, const [_meat240]);
  final lineId = c.read(cartControllerProvider).lines.single.lineId;
  cart.increaseQuantity(lineId);
  cart.submitOrder(
    orderType: OrderType.takeaway,
    orderNumber: '#CONF',
    orderId: orderId,
  );
  final held = c.read(cartControllerProvider).submittedOrder!;
  expect(held.subtotalMinor, kOrderTotal);
  expect(held.discountTotalMinor, 0);
}

String money(int minor) => MoneyFormatter.formatMinor(minor, 'ILS');

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

Future<void> pumpHostAndApply(
  WidgetTester tester,
  ProviderContainer c,
  String orderId,
) async {
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
                orderId: orderId,
                subtotalMinor: kOrderTotal,
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
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  final fields = find.byType(TextField);
  await tester.enterText(fields.first, '20');
  await tester.enterText(fields.last, 'manager comp');
  await tester.pump();
  await tester.tap(find.byType(FilledButton).last);
  await tester.pumpAndSettle();
}

void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  // =========================================================================
  group('[B] the MATCHING order still updates, immediately and once', () {
    testWidgets('B1 discounting the held order updates it through the REAL '
        'sheet, and the document and payment amount follow', (tester) async {
      final repo = _Repo();
      final c = harness(repo);
      holdConfirmationFor(c, 'order-B');
      expect(billAmountDue(l10n, c), money(kOrderTotal));

      await pumpHostAndApply(tester, c, 'order-B');

      expect(repo.requestedOrderIds, <String>['order-B']);
      final v = c.read(cartControllerProvider).submittedOrder!;
      expect(v.orderId, 'order-B');
      expect(v.discountTotalMinor, kDiscount);
      expect(
        v.subtotalMinor,
        kOrderTotal,
        reason: 'a discount never rewrites the subtotal',
      );
      expect(v.taxTotalMinor, 0);
      expect(
        v.grandTotalMinor,
        kDiscountedTotal,
        reason: '12000 - 2000, applied exactly once',
      );
      expect(billAmountDue(l10n, c), money(kDiscountedTotal));
    });

    test('B2 applying the SAME discount twice is idempotent in value — it '
        'never compounds', () {
      final c = harness(_Repo());
      holdConfirmationFor(c, 'order-B');
      final cart = c.read(cartControllerProvider.notifier);
      cart.applyOrderDiscount(
        orderId: 'order-B',
        discountTotalMinor: kDiscount,
      );
      cart.applyOrderDiscount(
        orderId: 'order-B',
        discountTotalMinor: kDiscount,
      );
      final v = c.read(cartControllerProvider).submittedOrder!;
      expect(v.discountTotalMinor, kDiscount);
      expect(v.grandTotalMinor, kDiscountedTotal);
    });
  });

  // =========================================================================
  group('[D/E] the guard declines safely', () {
    test('D1 with NO confirmation held, a successful response is a no-op and '
        'does not crash', () {
      final c = harness(_Repo());
      // Nothing submitted: there is no confirmation at all.
      expect(c.read(cartControllerProvider).submittedOrder, isNull);
      c
          .read(cartControllerProvider.notifier)
          .applyOrderDiscount(
            orderId: 'order-Z',
            discountTotalMinor: kDiscount,
          );
      expect(c.read(cartControllerProvider).submittedOrder, isNull);
    });

    test('E1 a MISMATCHED target leaves every money field untouched', () {
      final c = harness(_Repo());
      holdConfirmationFor(c, 'order-A');
      c
          .read(cartControllerProvider.notifier)
          .applyOrderDiscount(
            orderId: 'order-B',
            discountTotalMinor: kDiscount,
          );
      final v = c.read(cartControllerProvider).submittedOrder!;
      expect(v.orderId, 'order-A');
      expect(v.discountTotalMinor, 0);
      expect(v.subtotalMinor, kOrderTotal);
      expect(v.taxTotalMinor, 0);
      expect(v.grandTotalMinor, kOrderTotal);
      expect(v.lines.single.lineTotalMinor, kOrderTotal);
    });

    test('E2 a BLANK target is refused', () {
      final c = harness(_Repo());
      holdConfirmationFor(c, 'order-A');
      c
          .read(cartControllerProvider.notifier)
          .applyOrderDiscount(orderId: '', discountTotalMinor: kDiscount);
      expect(
        c.read(cartControllerProvider).submittedOrder!.discountTotalMinor,
        0,
      );
    });

    test('E3 a held order with NO server identity yet cannot be discounted — '
        'there is nothing to match against', () {
      final c = harness(_Repo());
      holdConfirmationFor(
        c,
        null,
      ); // submitted, but the server has not named it
      expect(c.read(cartControllerProvider).submittedOrder!.orderId, isNull);
      c
          .read(cartControllerProvider.notifier)
          .applyOrderDiscount(
            orderId: 'order-A',
            discountTotalMinor: kDiscount,
          );
      final v = c.read(cartControllerProvider).submittedOrder!;
      expect(v.discountTotalMinor, 0);
      expect(v.grandTotalMinor, kOrderTotal);
    });

    test('E4 matching is EXACT — whitespace and case are not tolerated, '
        'because order ids are not canonically normalised anywhere', () {
      for (final near in <String>[
        ' order-A',
        'order-A ',
        'ORDER-A',
        'order-a',
        'order-A\n',
      ]) {
        final c = harness(_Repo());
        holdConfirmationFor(c, 'order-A');
        c
            .read(cartControllerProvider.notifier)
            .applyOrderDiscount(orderId: near, discountTotalMinor: kDiscount);
        expect(
          c.read(cartControllerProvider).submittedOrder!.discountTotalMinor,
          0,
          reason: '"$near" is not order-A',
        );
      }
      // ...and the exact id still works.
      final c = harness(_Repo());
      holdConfirmationFor(c, 'order-A');
      c
          .read(cartControllerProvider.notifier)
          .applyOrderDiscount(
            orderId: 'order-A',
            discountTotalMinor: kDiscount,
          );
      expect(
        c.read(cartControllerProvider).submittedOrder!.discountTotalMinor,
        kDiscount,
      );
    });
  });

  // =========================================================================
  group('[G] full comp inherits the same guard', () {
    testWidgets('G1 a full comp on the HELD order zeroes it exactly once', (
      tester,
    ) async {
      // A full comp is an order discount whose accepted value equals the total.
      final repo = _Repo(discount: kOrderTotal);
      final c = harness(repo);
      holdConfirmationFor(c, 'order-B');

      await pumpHostAndApply(tester, c, 'order-B');

      final v = c.read(cartControllerProvider).submittedOrder!;
      expect(v.discountTotalMinor, kOrderTotal);
      expect(v.grandTotalMinor, 0, reason: 'comped to zero');
      expect(
        v.subtotalMinor,
        kOrderTotal,
        reason: 'the comp does not erase what was ordered',
      );
      expect(billAmountDue(l10n, c), money(0));
    });

    testWidgets('G2 a full comp on a DIFFERENT order does not zero the held '
        "confirmation — the worst case of the original defect", (tester) async {
      final repo = _Repo(discount: kOrderTotal);
      final c = harness(repo);
      holdConfirmationFor(c, 'order-A');

      await pumpHostAndApply(tester, c, 'order-B');

      expect(repo.requestedOrderIds, <String>['order-B']);
      final v = c.read(cartControllerProvider).submittedOrder!;
      expect(v.orderId, 'order-A');
      expect(
        v.grandTotalMinor,
        kOrderTotal,
        reason: 'comping B must never make A free',
      );
      expect(v.discountTotalMinor, 0);
      expect(billAmountDue(l10n, c), money(kOrderTotal));
    });
  });

  // =========================================================================
  group('[I] 002A configured modifier money survives a discount', () {
    testWidgets('I1 the pre-discount value is the configured 12000, the '
        'discount subtracts once, and no surcharge is lost', (tester) async {
      final repo = _Repo();
      final c = harness(repo);
      holdConfirmationFor(c, 'order-B');

      final before = c.read(cartControllerProvider).submittedOrder!;
      expect(
        before.lines.single.lineTotalMinor,
        kOrderTotal,
        reason: '2 x (4500 + 1500) — never the old 10500',
      );
      expect(before.subtotalMinor, kOrderTotal);

      await pumpHostAndApply(tester, c, 'order-B');

      final after = c.read(cartControllerProvider).submittedOrder!;
      expect(
        after.lines.single.lineTotalMinor,
        kOrderTotal,
        reason: 'historical line totals are not recalculated by a discount',
      );
      expect(after.subtotalMinor, kOrderTotal);
      expect(after.discountTotalMinor, kDiscount);
      expect(after.grandTotalMinor, kDiscountedTotal);
      // Independent arithmetic over the document's own figures.
      expect(
        after.subtotalMinor - after.discountTotalMinor + after.taxTotalMinor,
        kDiscountedTotal,
      );
    });

    testWidgets('I2 a MISMATCHED discount leaves the surcharge and the line '
        'total exactly where they were', (tester) async {
      final c = harness(_Repo());
      holdConfirmationFor(c, 'order-A');
      await pumpHostAndApply(tester, c, 'order-B');

      final v = c.read(cartControllerProvider).submittedOrder!;
      expect(v.lines.single.lineTotalMinor, kOrderTotal);
      expect(v.subtotalMinor, kOrderTotal);
      expect(v.grandTotalMinor, kOrderTotal);
    });
  });
}
