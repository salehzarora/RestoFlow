import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/format/money_format.dart';
import 'package:restoflow_pos/src/print/print_bridge.dart'
    show receiptToEscPosDocument;
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart'
    show buildReceiptDocument;

/// PILOT-PRINT-FIDELITY-001 — the PHYSICAL print payload (the CONVERTED
/// ESC/POS lines a printer actually receives, not the source strings) must be
/// content-complete: every item with its quantity, localized name, and
/// amount; every modifier; totals, paid, and change. Plus: PSC-001C combined
/// original+round items stay one flat customer receipt, reprint reuses the
/// same authoritative content, and the paid timestamp is the payment's own.
void main() {
  Future<AppLocalizations> l10n(String locale) =>
      AppLocalizations.delegate.load(Locale(locale));

  CashPayment payment({DateTime? paidAt}) => CashPayment(
    paymentId: 'pay-1',
    orderNumber: '#A1B2C3',
    deviceId: 'd1',
    localOperationId: 'op1',
    method: PaymentMethod.cash,
    status: PaymentStatus.completed,
    amountMinor: 9800,
    tenderedMinor: 10000,
    changeMinor: 200,
    currencyCode: 'ILS',
    receiptNumber: 'R-9',
    paidAt: paidAt ?? DateTime.utc(2026, 7, 19, 14, 30),
  );

  // Three items, one carrying PSC-001C round context (an added-round item is
  // just another flattened line on the customer receipt — no round section).
  SubmittedOrderView order() => SubmittedOrderView(
    orderNumber: '#A1B2C3',
    orderType: OrderType.dineIn,
    tableLabel: 'T3',
    customerName: 'محمد',
    currencyCode: 'ILS',
    subtotalMinor: 9800,
    lines: const [
      SubmittedLineView(
        name: 'كباب حلبي',
        quantity: 2,
        lineTotalMinor: 5000,
        currencyCode: 'ILS',
        modifiers: ['إضافة ثوم ×2', 'بدون بصل'],
        note: 'بدون فلفل',
      ),
      SubmittedLineView(
        name: 'حمص بالطحينة',
        quantity: 1,
        lineTotalMinor: 1800,
        currencyCode: 'ILS',
        modifiers: [],
      ),
      // The PSC-001C added-round item, flattened like any other line.
      SubmittedLineView(
        name: 'كنافة نابلسية',
        quantity: 3,
        lineTotalMinor: 3000,
        currencyCode: 'ILS',
        modifiers: ['جبنة إضافية'],
      ),
    ],
  );

  Future<List<pp.PrintTextLine>> physicalLines(
    AppLocalizations strings,
    SubmittedOrderView view, {
    CashPayment? pay,
  }) async {
    final doc = buildReceiptDocument(
      strings,
      view,
      pay ?? payment(),
      isDemo: false,
    );
    return receiptToEscPosDocument(
      doc,
    ).lines.whereType<pp.PrintTextLine>().toList();
  }

  test('EVERY item (quantity + localized name + amount) and EVERY modifier '
      'exists in the converted physical payload', () async {
    final lines = await physicalLines(await l10n('ar'), order());
    final itemLines = lines
        .where((l) => l.style == pp.PrintLineStyle.item)
        .toList();
    final subLines = lines
        .where((l) => l.style == pp.PrintLineStyle.sub)
        .toList();

    expect(itemLines, hasLength(3));
    for (final line in order().lines) {
      final match = itemLines.where(
        (l) =>
            l.text.contains('${line.quantity} ×') &&
            l.text.contains(line.name) &&
            l.text.contains(
              MoneyFormatter.formatMinor(line.lineTotalMinor, 'ILS'),
            ),
      );
      expect(
        match,
        hasLength(1),
        reason:
            'item "${line.name}" must appear exactly once with its '
            'quantity and amount',
      );
      for (final modifier in line.modifiers) {
        expect(
          subLines.where((l) => l.text.contains(modifier)),
          hasLength(1),
          reason: 'modifier "$modifier" must appear exactly once',
        );
      }
    }
    // 3 modifiers + 1 note ride as sub lines.
    expect(subLines, hasLength(4));
  });

  test(
    'totals, paid amount, and change are present with formatted money',
    () async {
      final lines = await physicalLines(await l10n('ar'), order());
      final texts = lines.map((l) => l.text).toList();
      expect(
        texts.where((t) => t.contains(MoneyFormatter.formatMinor(9800, 'ILS'))),
        isNotEmpty,
        reason: 'grand total',
      );
      expect(
        texts.where(
          (t) => t.contains(MoneyFormatter.formatMinor(10000, 'ILS')),
        ),
        isNotEmpty,
        reason: 'paid amount',
      );
      expect(
        texts.where((t) => t.contains(MoneyFormatter.formatMinor(200, 'ILS'))),
        isNotEmpty,
        reason: 'change',
      );
    },
  );

  test('PSC-001C combined receipt stays ONE flat customer receipt: all '
      'original + added-round items, NO round section labels', () async {
    final strings = await l10n('ar');
    final lines = await physicalLines(strings, order());
    expect(
      lines.where((l) => l.style == pp.PrintLineStyle.item),
      hasLength(3), // 2 original + 1 added-round, one list
    );
    // No customer-facing round sections exist on the receipt (no round
    // wording in any language the receipt could carry).
    expect(strings, isNotNull);
    for (final marker in const ['جولة', 'Round', 'סבב']) {
      expect(
        lines.where((l) => l.text.contains(marker)),
        isEmpty,
        reason: 'customer receipts never show service-round sections',
      );
    }
  });

  test('REPRINT builds byte-identical content from the same authoritative '
      'view', () async {
    final strings = await l10n('ar');
    final first = await physicalLines(strings, order());
    final again = await physicalLines(strings, order());
    expect(again.length, first.length);
    for (var i = 0; i < first.length; i++) {
      expect(again[i].text, first[i].text);
      expect(again[i].style, first[i].style);
    }
  });

  test('the printed time is the AUTHORITATIVE payment paidAt (not now, not '
      'order time)', () async {
    final strings = await l10n('en');
    final at = DateTime.utc(2026, 7, 19, 9, 5);
    final lines = await physicalLines(
      strings,
      order(),
      pay: payment(paidAt: at),
    );
    expect(
      lines.where((l) => l.text.contains('09:05')),
      isNotEmpty,
      reason: 'the receipt time line must come from payment.paidAt',
    );
  });
}
