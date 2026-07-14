import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:restoflow_pos/src/data/order_identity.dart';
import 'package:restoflow_pos/src/widgets/cash_payment_sheet.dart';

/// DESIGN-001 POS polish contracts:
///  * a failed payment push is VISIBLE and actionable (pinned danger banner,
///    sheet stays open, Confirm doubles as retry) — previously fully silent;
///  * new input clears the failure banner;
///  * the cart line shows '× qty · unit price' as its own Text under the
///    (still exact-match) item name.
class _FailingPaymentRepository extends DemoPaymentStore {
  int attempts = 0;

  @override
  Future<CashPayment> recordCashPayment({
    required String orderId,
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
    PaymentMethod method = PaymentMethod.cash,
    int? expectedRevision,
  }) async {
    attempts++;
    throw const PaymentException('payment failed: transient');
  }
}

Widget _sheetHarness(_FailingPaymentRepository repo, {Locale? locale}) =>
    ProviderScope(
      overrides: [paymentRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        locale: locale ?? const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: CashPaymentSheet(
            identity: PosOrderIdentity.legacyDisplayCode('DEMO-0001'),
            orderNumber: 'DEMO-0001',
            amountMinor: 4200,
            currencyCode: 'ILS',
          ),
        ),
      ),
    );

void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  testWidgets('a failed cash payment shows the pinned danger banner and '
      'keeps the sheet open with Confirm as the retry', (tester) async {
    _useTallSurface(tester);
    final repo = _FailingPaymentRepository();
    final l10n = await _en();

    await tester.pumpWidget(_sheetHarness(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('payment-failed-banner')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('cash-received-field')),
      '42.00',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-payment-button')));
    await tester.pumpAndSettle();

    // Visible, honest failure — no silent dead-end.
    expect(find.byKey(const Key('payment-failed-banner')), findsOneWidget);
    expect(find.text(l10n.posPaymentFailedTitle), findsOneWidget);
    expect(find.text(l10n.posPaymentFailedBody), findsOneWidget);
    // Sheet still open; the client-validation errors are NOT reused.
    expect(find.text(l10n.posPaymentTitle), findsOneWidget);
    expect(find.text(l10n.posCashInvalid), findsNothing);
    expect(find.text(l10n.posCashInsufficient), findsNothing);
    expect(repo.attempts, 1);

    // Confirm stays enabled as the retry — a second attempt re-pushes.
    await tester.tap(find.byKey(const Key('confirm-payment-button')));
    await tester.pumpAndSettle();
    expect(repo.attempts, 2);
    expect(find.byKey(const Key('payment-failed-banner')), findsOneWidget);
  });

  testWidgets('new input clears the failure banner', (tester) async {
    _useTallSurface(tester);
    final repo = _FailingPaymentRepository();

    await tester.pumpWidget(_sheetHarness(repo));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('cash-received-field')),
      '42.00',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-payment-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment-failed-banner')), findsOneWidget);

    // Typing again (a corrected amount) dismisses the stale failure notice.
    await tester.tap(find.byKey(const Key('quick-cash-exact')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment-failed-banner')), findsNothing);
  });

  testWidgets('hardware-keyboard typing also clears the failure banner', (
    tester,
  ) async {
    _useTallSurface(tester);
    final repo = _FailingPaymentRepository();

    await tester.pumpWidget(_sheetHarness(repo));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('cash-received-field')),
      '42.00',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-payment-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment-failed-banner')), findsOneWidget);

    // enterText fires TextField.onChanged — the physical-keyboard path
    // (review fix: it previously left the stale banner pinned).
    await tester.enterText(
      find.byKey(const Key('cash-received-field')),
      '50.00',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment-failed-banner')), findsNothing);
  });

  testWidgets('the failure state fits a short POS display without clipping '
      'the retry (scrollable sheet)', (tester) async {
    // 1366×768 is a canonical POS terminal resolution; the failure state is
    // the sheet's TALLEST configuration (review fix: it used to overflow and
    // clip the Confirm/retry button exactly when it was needed).
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = _FailingPaymentRepository();

    await tester.pumpWidget(_sheetHarness(repo));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('cash-received-field')),
      '42.00',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-payment-button')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('payment-failed-banner')), findsOneWidget);

    // The retry stays reachable: scroll it into view and use it.
    await tester.ensureVisible(find.byKey(const Key('confirm-payment-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-payment-button')));
    await tester.pumpAndSettle();
    expect(repo.attempts, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed NON-CASH tender shows the same banner', (tester) async {
    _useTallSurface(tester);
    final repo = _FailingPaymentRepository();

    await tester.pumpWidget(_sheetHarness(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tender-card')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-payment-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('payment-failed-banner')), findsOneWidget);
    expect(repo.attempts, 1);
  });

  testWidgets('the failure banner renders under Arabic RTL without errors', (
    tester,
  ) async {
    _useTallSurface(tester);
    final repo = _FailingPaymentRepository();

    await tester.pumpWidget(_sheetHarness(repo, locale: const Locale('ar')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('cash-received-field')),
      '42.00',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-payment-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('payment-failed-banner')), findsOneWidget);
    expect(
      Directionality.of(
        tester.element(find.byKey(const Key('payment-failed-banner'))),
      ),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets("the cart line shows '× qty · unit' under the exact-match name", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final l10n = await _en();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: const PosMenuScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // First card is Classic Burger (₪42.00); add it twice.
    await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    // The name stays a standalone exact-match Text (frozen contract) and the
    // qty × unit composite is its OWN localized Text.
    expect(find.text('Classic Burger'), findsNWidgets(2));
    expect(find.text(l10n.posCartQtyUnit(2, '₪42.00')), findsOneWidget);
  });
}
