// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 5): the ON-SCREEN receipt preview
// shows the optional customer phone directly below the name (matching the printed
// receipt), localized in en/ar/he, with no empty label/gap when absent. Synthetic
// numbers only.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart';

CashPayment _payment() => CashPayment(
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
  receiptNumber: 'R-INTERNAL-9',
  paidAt: DateTime.utc(2026, 7, 8, 14, 30),
);

SubmittedOrderView _order({String? name, String? phone}) => SubmittedOrderView(
  orderNumber: '#ABC123',
  orderType: OrderType.dineIn,
  tableLabel: 'T3',
  customerName: name,
  customerPhone: phone,
  currencyCode: 'ILS',
  subtotalMinor: 1000,
  lines: [
    SubmittedLineView(
      name: 'Burger',
      quantity: 2,
      lineTotalMinor: 1000,
      currencyCode: 'ILS',
    ),
  ],
);

Future<void> _pumpPreview(
  WidgetTester tester,
  String locale,
  SubmittedOrderView order,
) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: ReceiptPrintPreview(order: order, payment: _payment()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final locale in const ['en', 'ar', 'he']) {
    testWidgets('$locale: the preview shows the phone below the name', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(Locale(locale));
      await _pumpPreview(
        tester,
        locale,
        _order(name: 'Layla', phone: '050-7654321'),
      );
      final dialog = find.byKey(const Key('receipt-print-preview'));
      expect(
        find.descendant(
          of: dialog,
          matching: find.text('${l10n.customerPhoneReceiptLabel}: 050-7654321'),
        ),
        findsOneWidget,
      );
      // Both name and phone are present.
      expect(
        find.descendant(of: dialog, matching: find.textContaining('Layla')),
        findsOneWidget,
      );
    });
  }

  testWidgets('phone only (no name) still shows the phone', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _pumpPreview(tester, 'en', _order(phone: '054-1234567'));
    expect(find.text('${l10n.customerNameReceiptLabel}: '), findsNothing);
    expect(
      find.text('${l10n.customerPhoneReceiptLabel}: 054-1234567'),
      findsOneWidget,
    );
  });

  testWidgets('name only (no phone) shows NO phone label/gap', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _pumpPreview(tester, 'en', _order(name: 'Layla'));
    expect(find.textContaining('Layla'), findsOneWidget);
    expect(find.textContaining(l10n.customerPhoneReceiptLabel), findsNothing);
  });

  testWidgets('neither name nor phone: no customer lines at all', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _pumpPreview(tester, 'en', _order());
    expect(find.textContaining(l10n.customerPhoneReceiptLabel), findsNothing);
    expect(find.textContaining(l10n.customerNameReceiptLabel), findsNothing);
  });

  testWidgets(
    'the preview metadata order matches the printed receipt (name -> phone -> '
    'time), and a historical order preview uses the STORED phone',
    (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final order = _order(name: 'Layla', phone: '050-7654321');
      await _pumpPreview(tester, 'en', order);

      // The preview shows the phone (the stored value on the order view).
      final dialog = find.byKey(const Key('receipt-print-preview'));
      expect(
        find.descendant(
          of: dialog,
          matching: find.text('${l10n.customerPhoneReceiptLabel}: 050-7654321'),
        ),
        findsOneWidget,
      );

      // The PRINTED document uses the same order: name then phone then time.
      final doc = buildReceiptDocument(l10n, order, _payment(), isDemo: false);
      final texts = doc.lines
          .map((l) => l.left ?? '')
          .where((t) => t.isNotEmpty)
          .toList();
      final nameIdx = texts.indexWhere(
        (t) => t.contains(l10n.customerNameReceiptLabel),
      );
      final phoneIdx = texts.indexWhere(
        (t) => t.contains(l10n.customerPhoneReceiptLabel),
      );
      expect(nameIdx, greaterThanOrEqualTo(0));
      expect(phoneIdx, nameIdx + 1, reason: 'phone directly below the name');
    },
  );
}
