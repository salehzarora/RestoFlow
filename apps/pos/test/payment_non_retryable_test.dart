import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:restoflow_pos/src/widgets/cash_payment_sheet.dart';

/// POS-OPERATIONS-SYNC-001 — the DEFERRED defect from MONEY-SETTLEMENT-CONSISTENCY-001.
///
/// After the server's typed `order_not_chargeable` refusal the sheet showed the
/// right banner — and then left Confirm ENABLED. Worse, `_clearErrors()` ran on
/// every keystroke and wiped the flag, so the banner vanished as soon as the
/// cashier touched the field. The result: an endless supply of rejected sync
/// operations, one per attempt, while the cashier believed they were retrying
/// something that could work.
///
/// It cannot work. A zero-total order owes NOTHING; no tender, amount or method
/// will ever change that. The refusal is TERMINAL for this sheet.
void main() {
  Widget wrap(Widget child, {PaymentRepository? repo}) => ProviderScope(
    overrides: [
      if (repo != null) paymentRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(body: child),
    ),
  );

  Future<void> refuse(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, '0.00');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-payment-button')));
    await tester.pumpAndSettle();
  }

  testWidgets('1 order_not_chargeable DISABLES Confirm', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _CountingNotChargeableRepo();
    await tester.pumpWidget(
      wrap(
        const CashPaymentSheet(
          orderNumber: '#Z0',
          amountMinor: 0,
          currencyCode: 'ILS',
          orderId: 'oid-Z0',
        ),
        repo: repo,
      ),
    );
    await tester.pumpAndSettle();
    await refuse(tester);

    expect(
      find.byKey(const Key('payment-not-chargeable-banner')),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('confirm-payment-button')),
    );
    expect(
      button.onPressed,
      isNull,
      reason: 'a refusal that can never succeed must not offer a retry',
    );
  });

  testWidgets('2 a SECOND identical request cannot be sent', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _CountingNotChargeableRepo();
    await tester.pumpWidget(
      wrap(
        const CashPaymentSheet(
          orderNumber: '#Z0',
          amountMinor: 0,
          currencyCode: 'ILS',
          orderId: 'oid-Z0',
        ),
        repo: repo,
      ),
    );
    await tester.pumpAndSettle();
    await refuse(tester);
    expect(repo.attempts, 1);

    // Try hard to fire a second one: tap again, and retype the amount (which used
    // to clear the flag and re-arm the button).
    await tester.tap(
      find.byKey(const Key('confirm-payment-button')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '0.00');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('confirm-payment-button')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(
      repo.attempts,
      1,
      reason: 'every extra attempt is a doomed, rejected sync operation',
    );
  });

  testWidgets('3 typing does NOT clear the non-chargeable state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(
        const CashPaymentSheet(
          orderNumber: '#Z0',
          amountMinor: 0,
          currencyCode: 'ILS',
          orderId: 'oid-Z0',
        ),
        repo: _CountingNotChargeableRepo(),
      ),
    );
    await tester.pumpAndSettle();
    await refuse(tester);

    await tester.enterText(find.byType(TextField).first, '5.00');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('payment-not-chargeable-banner')),
      findsOneWidget,
      reason:
          'the explanation must survive a keystroke — the order still owes 0',
    );
  });

  testWidgets('4 a RETRYABLE failure still offers a retry', (tester) async {
    // The counterpart: a transport failure is NOT terminal and Confirm stays live.
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(
        const CashPaymentSheet(
          orderNumber: '#A1',
          amountMinor: 1000,
          currencyCode: 'ILS',
          orderId: 'oid-A1',
        ),
        repo: const _TransportFailRepo(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '10.00');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-payment-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('payment-failed-banner')), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('confirm-payment-button')),
    );
    expect(
      button.onPressed,
      isNotNull,
      reason: 'a transport blip IS retryable — do not strand the cashier',
    );
  });
}

/// Refuses with the server's exact typed code, and COUNTS how many times the POS
/// actually tried. The count is the whole point: each attempt was a real rejected
/// sync operation in production.
class _CountingNotChargeableRepo implements PaymentRepository {
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
    throw const PaymentException('order_not_chargeable', notChargeable: true);
  }

  @override
  ShiftContext shiftContext() => const ShiftContext(
    shiftOpen: false,
    drawerOpen: false,
    openingFloatMinor: 0,
    cashInDrawerMinor: 0,
    lastPaymentMinor: 0,
    currencyCode: 'ILS',
  );

  @override
  CashPayment? paymentFor(String orderNumber) => null;
}

class _TransportFailRepo implements PaymentRepository {
  const _TransportFailRepo();

  @override
  Future<CashPayment> recordCashPayment({
    required String orderId,
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
    PaymentMethod method = PaymentMethod.cash,
    int? expectedRevision,
  }) async => throw const PaymentException('network');

  @override
  ShiftContext shiftContext() => const ShiftContext(
    shiftOpen: false,
    drawerOpen: false,
    openingFloatMinor: 0,
    cashInDrawerMinor: 0,
    lastPaymentMinor: 0,
    currencyCode: 'ILS',
  );

  @override
  CashPayment? paymentFor(String orderNumber) => null;
}
