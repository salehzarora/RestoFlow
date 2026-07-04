import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/discount.dart';
import 'package:restoflow_pos/src/data/discount_repository.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/discount_controller.dart';

/// RF-117 (C): the order-level discount sheet validates client-side (reject a
/// discount over the subtotal / <=0 / no reason), applies via the
/// server-authoritative repository, and surfaces permission_denied HONESTLY
/// (never a fake local discount in real mode). Demo mode applies locally.
Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

/// A repository that always denies (simulates a cashier lacking the permission).
class _DenyingDiscountRepo implements DiscountRepository {
  @override
  Future<OrderDiscount> applyOrderDiscount({
    required String orderId,
    required DiscountType type,
    required int value,
    required String reason,
    required int subtotalMinor,
    required int taxTotalMinor,
    int? expectedRevision,
  }) async => throw const DiscountException(
    'permission_denied',
    permissionDenied: true,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: PosMenuScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _submitAndOpenDiscount(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.posSendOrder));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('apply-discount-button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a fixed discount larger than the subtotal is rejected '
      'client-side (no backend, no apply)', (tester) async {
    final l10n = await _en();
    await _pump(tester);
    await _submitAndOpenDiscount(tester, l10n);

    // ₪100.00 on a ₪42.00 order.
    await tester.enterText(
      find.byKey(const Key('discount-value-field')),
      '100',
    );
    await tester.enterText(
      find.byKey(const Key('discount-reason-field')),
      'manager comp',
    );
    await tester.tap(find.byKey(const Key('discount-apply-button')));
    await tester.pumpAndSettle();

    // The sheet stays open with the honest validation message; nothing applied.
    expect(find.text(l10n.posDiscountExceedsSubtotal), findsOneWidget);
    expect(find.byKey(const Key('confirmation-discount')), findsNothing);
  });

  testWidgets('a valid demo fixed discount updates the order total', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(tester);
    await _submitAndOpenDiscount(tester, l10n);

    await tester.enterText(find.byKey(const Key('discount-value-field')), '10');
    await tester.enterText(
      find.byKey(const Key('discount-reason-field')),
      'loyalty',
    );
    await tester.tap(find.byKey(const Key('discount-apply-button')));
    await tester.pumpAndSettle();

    // 4200 − 1000 = 3200. The confirmation shows the discount + grand total.
    expect(
      tester.widget<Text>(find.byKey(const Key('confirmation-discount'))).data,
      '−₪10.00',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('confirmation-grand-total')))
          .data,
      '₪32.00',
    );
    // The discount button is hidden once a discount is applied (no stacking).
    expect(find.byKey(const Key('apply-discount-button')), findsNothing);
  });

  testWidgets('permission_denied shows the honest "ask a manager" message and '
      'applies NO local discount', (tester) async {
    final l10n = await _en();
    await _pump(
      tester,
      overrides: [
        discountRepositoryProvider.overrideWithValue(_DenyingDiscountRepo()),
      ],
    );
    await _submitAndOpenDiscount(tester, l10n);

    await tester.enterText(find.byKey(const Key('discount-value-field')), '5');
    await tester.enterText(
      find.byKey(const Key('discount-reason-field')),
      'promo',
    );
    await tester.tap(find.byKey(const Key('discount-apply-button')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.posDiscountPermissionDenied), findsOneWidget);
    // No fake local discount was applied.
    expect(find.byKey(const Key('confirmation-discount')), findsNothing);
  });
}
