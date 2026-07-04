import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/pos_branch_tax.dart';

/// RF-117 (B): tax is DISPLAYED only when the owner's per-branch setting is
/// enabled. Default OFF => the cart shows only the subtotal (unchanged flow).
/// Enabled @ 17% => a Tax line + grand total on the cart and on the confirmation,
/// and the payment sheet asks for the GRAND total. Integer minor units.
class _FakeTaxReader implements DeviceBranchTaxReader {
  _FakeTaxReader(this.tax);
  final BranchTax? tax;
  @override
  Future<BranchTax?> load() async => tax;
}

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(WidgetTester tester, {DeviceBranchTaxReader? reader}) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (reader != null)
          posBranchTaxReaderProvider.overrideWithValue(reader),
      ],
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

Future<void> _addBurger(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'tax OFF (default): only the subtotal shows, no tax/grand lines',
    (tester) async {
      await _pump(tester);
      await _addBurger(tester);
      expect(find.byKey(const Key('cart-subtotal')), findsOneWidget);
      expect(find.byKey(const Key('cart-tax')), findsNothing);
      expect(find.byKey(const Key('cart-grand-total')), findsNothing);
    },
  );

  testWidgets('tax ON @ 17%: the cart shows a Tax line + grand total', (
    tester,
  ) async {
    await _pump(
      tester,
      reader: _FakeTaxReader(const BranchTax(enabled: true, rateBp: 1700)),
    );
    await _addBurger(tester);

    // 4200 @ 17% = 714 (half-away). Grand = 4914.
    expect(
      tester.widget<Text>(find.byKey(const Key('cart-tax'))).data,
      '₪7.14',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('cart-grand-total'))).data,
      '₪49.14',
    );
  });

  testWidgets('tax ON: the confirmation + payment sheet use the GRAND total', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(
      tester,
      reader: _FakeTaxReader(const BranchTax(enabled: true, rateBp: 1700)),
    );
    await _addBurger(tester);
    await tester.tap(find.text(l10n.posSendOrder));
    await tester.pumpAndSettle();

    // Confirmation shows the tax + grand breakdown.
    expect(
      tester.widget<Text>(find.byKey(const Key('confirmation-tax'))).data,
      '₪7.14',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('confirmation-grand-total')))
          .data,
      '₪49.14',
    );

    // The payment sheet asks for the grand total, not the bare subtotal.
    await tester.tap(find.byKey(const Key('pay-cash-button')));
    await tester.pumpAndSettle();
    expect(find.text('₪49.14'), findsWidgets);
  });
}
