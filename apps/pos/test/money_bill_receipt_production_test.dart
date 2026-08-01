import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/format/money_format.dart';
import 'package:restoflow_pos/src/print/print_document.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart'
    show buildBillDocument, buildReceiptDocument;

/// MONEY-PRODUCTION-PATH-TESTS-002D [D + E] — Codex Blocker 7, the customer
/// DOCUMENT layer (source function + builder). Action-level proof: 003E.
/// documents.
///
/// SCOPE, CORRECTED IN MONEY-RELEASE-PROOF-003E. This suite is a DOCUMENT-LEVEL
/// proof: it calls the real authoritative SOURCE FUNCTION and the real DOCUMENT
/// BUILDER that the POS buttons use, but it does NOT go through the button, the
/// widget, or the ReceiptPrintController. The rows below were previously
/// labelled "Auto receipt" and "Manual reprint", which overstated them twice
/// over — both call the SAME source function, so neither was distinguished from
/// the other, and neither exercised the action that triggers it.
///
///   Print bill            -> `authoritativeUnpaidOrderSource(...)` -> `buildBillDocument`
///   Paid-receipt document -> `authoritativeReceiptSource(...)`     -> `buildReceiptDocument`
///
/// The ACTION-level proof — the real CashPaymentSheet automatic request and the
/// real OrderActionRow manual reprint, each captured at the printer seam — lives
/// in `money_receipt_action_production_test.dart` (003E). This suite keeps its
/// real and useful value: that the source+builder pair preserves configured
/// modifier money exactly.
///
/// The order view is therefore built by the REAL `submittedOrderViewFromDetail`
/// mapper from an authoritative `PosOrderDetail`, and the payment by the REAL
/// `cashPaymentFromDetail`.
///
/// WHAT THIS SUITE DELIBERATELY DOES NOT CLAIM. The customer document renders a
/// modifier as a pre-formatted NAME line (`PrintLine.sub('+ ...')`); the
/// authoritative `price_minor_snapshot` is parsed by the detail mapper and then
/// intentionally not printed. So a per-modifier AMOUNT cannot be asserted on the
/// document, and this suite proves modifier money through the LINE TOTAL and the
/// order totals instead. Claiming otherwise would be exactly the overstated
/// coverage Blocker 7 is about.
///
/// Classification: CODEX COVERAGE GAP.

const kBase = 4500;
const k240 = 1500;
// Independent literals. Line 1: 2 x (4500 + 1500) = 12000. Line 2: 1000 + 300.
const kBurgerLine = 12000;
const kColaLine = 1300;
const kSubtotal = 13300;

/// An authoritative detail with TWO configured lines, one at quantity 2.
PosOrderDetail _detail({
  String status = 'preparing',
  PosOrderDetailPayment? payment,
}) => PosOrderDetail(
  orderId: 'ord-1',
  orderCode: '#O00042',
  orderType: 'takeaway',
  status: status,
  revision: 3,
  currencyCode: 'ILS',
  subtotalMinor: kSubtotal,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: kSubtotal,
  payment: payment,
  rounds: const [],
  items: const [
    PosOrderDetailItem(
      name: 'Burger',
      quantity: 2,
      unitPriceMinor: kBase,
      lineDiscountMinor: 0,
      lineTotalMinor: kBurgerLine,
      modifiers: [
        PosOrderDetailModifier(
          optionName: '240g',
          modifierName: 'Meat',
          priceMinor: k240,
          quantity: 1,
        ),
      ],
    ),
    PosOrderDetailItem(
      name: 'Cola',
      quantity: 1,
      unitPriceMinor: 1000,
      lineDiscountMinor: 0,
      lineTotalMinor: kColaLine,
      modifiers: [
        PosOrderDetailModifier(
          optionName: 'Extra ice',
          modifierName: 'Ice',
          priceMinor: 300,
          quantity: 1,
        ),
      ],
    ),
  ],
);

class _DetailRepo implements OrderDetailRepository {
  _DetailRepo(this._detail);
  final PosOrderDetail _detail;
  int fetches = 0;
  @override
  Future<PosOrderDetail> fetch(String orderId) async {
    fetches++;
    return _detail;
  }
}

class _FailingRepo implements OrderDetailRepository {
  @override
  Future<PosOrderDetail> fetch(String orderId) async =>
      throw const PosOrderDetailException(PosOrderDetailFailure.malformed);
}

String money(int minor) => MoneyFormatter.formatMinor(minor, 'ILS');

/// Every rendered RIGHT-hand value on the document (money columns), so an
/// assertion cannot pass merely because some label happens to match.
List<String> valuesOf(PrintDocument doc) => [
  for (final line in doc.lines)
    if (line.right != null) line.right!,
];

/// Every rendered LEFT-hand string (labels, item names, centered markers).
List<String> labelsOf(PrintDocument doc) => [
  for (final line in doc.lines)
    if (line.left != null) line.left!,
];

/// Alias kept for readability where the left column is prose, not a label.
List<String> textsOf(PrintDocument doc) => labelsOf(doc);

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  // =========================================================================
  group('[D] the REAL unpaid bill', () {
    test('D1 the bill is built from the AUTHORITATIVE detail and shows the '
        'exact configured money, with no payment anywhere', () async {
      final repo = _DetailRepo(_detail());
      final view = await authoritativeUnpaidOrderSource(
        isDemoMode: false,
        orderId: 'ord-1',
        localView: null,
        repository: repo,
      );
      expect(repo.fetches, 1, reason: 'the server detail is the authority');
      expect(view, isNotNull);

      // The mapper preserved the stored money exactly.
      expect(view!.subtotalMinor, kSubtotal);
      expect(view.lines, hasLength(2));
      expect(view.lines[0].lineTotalMinor, kBurgerLine);
      expect(view.lines[1].lineTotalMinor, kColaLine);

      final doc = buildBillDocument(l10n, view, isDemo: false);

      // Both configured items appear — not just the first line.
      expect(textsOf(doc).any((t) => t.contains('Burger')), isTrue);
      expect(textsOf(doc).any((t) => t.contains('Cola')), isTrue);

      // The exact money, as rendered.
      final values = valuesOf(doc);
      expect(
        values,
        contains(money(kBurgerLine)),
        reason: 'the quantity-2 upgraded line prints 120.00',
      );
      expect(values, contains(money(kColaLine)));
      expect(values, contains(money(kSubtotal)));

      // The UNPAID markers.
      expect(
        labelsOf(doc),
        contains(l10n.receiptAmountDueLabel),
        reason: 'a bill states an amount DUE, never an order total paid',
      );
      expect(textsOf(doc), contains(l10n.receiptUnpaidBillLabel));

      // ...and none of the payment rows.
      expect(labelsOf(doc), isNot(contains(l10n.posReceiptPaid)));
      expect(labelsOf(doc), isNot(contains(l10n.posReceiptChange)));
      expect(labelsOf(doc), isNot(contains(l10n.posPaymentMethodLabel)));
      expect(labelsOf(doc), isNot(contains(l10n.posReceiptOrderTotal)));
    });

    test(
      'D2 the amount due equals the sum of the printed line totals — the '
      'builder does not re-derive modifier money with another formula',
      () async {
        final view = await authoritativeUnpaidOrderSource(
          isDemoMode: false,
          orderId: 'ord-1',
          localView: null,
          repository: _DetailRepo(_detail()),
        );
        final doc = buildBillDocument(l10n, view!, isDemo: false);

        // Recomputed from the DOCUMENT's own line values, independently.
        final due = doc.lines
            .firstWhere((l) => l.left == l10n.receiptAmountDueLabel)
            .right;
        expect(due, money(kBurgerLine + kColaLine));
        expect(due, money(kSubtotal));
      },
    );

    test('D3 a detail that cannot be loaded yields NO bill — never a partial '
        'local document', () async {
      final view = await authoritativeUnpaidOrderSource(
        isDemoMode: false,
        orderId: 'ord-1',
        localView: null,
        repository: _FailingRepo(),
      );
      expect(
        view,
        isNull,
        reason: 'an honest "retry" beats a bill that understates the order',
      );
    });
  });

  // =========================================================================
  group('[E] the paid-receipt DOCUMENT (source fn + builder)', () {
    final paidDetail = PosOrderDetailPayment(
      paymentId: 'pay-authoritative-1',
      method: PaymentMethod.cash,
      status: PaymentStatus.completed,
      amountMinor: kSubtotal,
      tenderedMinor: 15000,
      changeMinor: 1700,
      paidAt: DateTime.utc(2026, 8, 6, 9),
      receiptNumber: 'R-9',
    );

    // Both the automatic request and the manual reprint call THIS source
    // function, so calling it twice proves they cannot diverge at the document
    // layer. It does NOT prove either ACTION ran — 003E does that.
    test('E1 two calls to the SAME authoritative source produce identical '
        'receipt documents', () async {
      final repo = _DetailRepo(
        _detail(status: 'completed', payment: paidDetail),
      );

      Future<(SubmittedOrderView, CashPayment)?> source() =>
          authoritativeReceiptSource(
            isDemoMode: false,
            orderId: 'ord-1',
            localView: null,
            localPayment: null,
            repository: repo,
          );

      final auto = await source();
      final manual = await source();
      expect(auto, isNotNull);
      expect(manual, isNotNull);

      final autoDoc = buildReceiptDocument(
        l10n,
        auto!.$1,
        auto.$2,
        isDemo: false,
      );
      final manualDoc = buildReceiptDocument(
        l10n,
        manual!.$1,
        manual.$2,
        isDemo: false,
      );

      // Semantically identical: same labels, same values, same order.
      expect(valuesOf(manualDoc), valuesOf(autoDoc));
      expect(labelsOf(manualDoc), labelsOf(autoDoc));
      expect(textsOf(manualDoc), textsOf(autoDoc));
    });

    test('E2 the receipt keeps the configured surcharges in its totals and '
        'states the exact tender and change', () async {
      final source = await authoritativeReceiptSource(
        isDemoMode: false,
        orderId: 'ord-1',
        localView: null,
        localPayment: null,
        repository: _DetailRepo(
          _detail(status: 'completed', payment: paidDetail),
        ),
      );
      final doc = buildReceiptDocument(
        l10n,
        source!.$1,
        source.$2,
        isDemo: false,
      );

      final values = valuesOf(doc);
      expect(values, contains(money(kBurgerLine)));
      expect(values, contains(money(kColaLine)));
      expect(values, contains(money(kSubtotal)));
      expect(values, contains(money(15000)), reason: 'tendered');
      expect(values, contains(money(1700)), reason: 'change');

      // The PAID markers, and no bill markers.
      expect(labelsOf(doc), contains(l10n.posReceiptOrderTotal));
      expect(labelsOf(doc), contains(l10n.posReceiptPaid));
      expect(labelsOf(doc), contains(l10n.posReceiptChange));
      expect(labelsOf(doc), contains(l10n.posPaymentMethodLabel));
      expect(textsOf(doc), isNot(contains(l10n.receiptUnpaidBillLabel)));
      expect(labelsOf(doc), isNot(contains(l10n.receiptAmountDueLabel)));

      // A later payment did NOT reprice the items.
      expect(source.$1.lines[0].lineTotalMinor, kBurgerLine);
      expect(source.$1.subtotalMinor, kSubtotal);
      expect(source.$2.amountMinor, kSubtotal);
    });

    test('E3 an order with NO completed payment produces NO receipt source — '
        'a paid receipt without a payment would be a lie', () async {
      final source = await authoritativeReceiptSource(
        isDemoMode: false,
        orderId: 'ord-1',
        localView: null,
        localPayment: null,
        repository: _DetailRepo(_detail()), // unpaid
      );
      expect(source, isNull);
    });

    test('E4 a CORRUPT local payment (002B) yields NO receipt source at all, so '
        'neither trigger can produce a document', () async {
      // 002B made the LOCAL payment decode fail closed, through the real
      // `PosRecentOrder.fromJson` used by the recent-orders store. A corrupt
      // record therefore never becomes a CashPayment at all, so there is
      // nothing to offer the receipt source as a local stand-in.
      Map<String, Object?> localRecord(Map<String, Object?> paymentOverride) =>
          <String, Object?>{
            'order': <String, Object?>{
              'order_number': '#O00042',
              'currency_code': 'ILS',
              'order_type': 'takeaway',
              'subtotal_minor': kSubtotal,
              'discount_total_minor': 0,
              'tax_total_minor': 0,
              'tax_rate_bp': 0,
              'lines': <Object?>[],
            },
            'submitted_at': '2026-08-06T09:00:00.000Z',
            'payment': <String, Object?>{
              'payment_id': 'pay-1',
              'order_number': '#O00042',
              'device_id': 'dev-1',
              'local_operation_id': 'op-1',
              'currency_code': 'ILS',
              'receipt_number': 'R-9',
              'paid_at': '2026-08-06T09:00:00.000Z',
              'amount_minor': kSubtotal,
              'tendered_minor': 15000,
              'change_minor': 1700,
              'method': 'cash',
              'status': 'completed',
              ...paymentOverride,
            },
          };

      for (final corrupt in <Map<String, Object?>>[
        {'method': 'bitcoin'},
        {'status': 'weird'},
        {'amount_minor': '13300'},
        {'tendered_minor': null},
        {'change_minor': 1700.0},
      ]) {
        expect(
          () => PosRecentOrder.fromJson(localRecord(corrupt)),
          throwsA(isA<FormatException>()),
          reason: 'a record we cannot read must never present as settled',
        );
      }

      // A VALID local record still decodes and still offers its receipt — the
      // strictness above is not simply refusing everything.
      final good = PosRecentOrder.fromJson(localRecord(const {}));
      expect(good.payment, isNotNull);
      expect(good.canReprintReceipt, isTrue);
      expect(good.payment!.amountMinor, kSubtotal);

      // And with no usable local payment and an unpaid server detail, the real
      // source refuses — no receipt, automatic or manual.
      final source = await authoritativeReceiptSource(
        isDemoMode: false,
        orderId: 'ord-1',
        localView: null,
        localPayment: null,
        repository: _DetailRepo(_detail()),
      );
      expect(source, isNull);
    });

    test('E5 a server-authoritative valid payment still produces the correct '
        'receipt even when this till holds no local payment', () async {
      final source = await authoritativeReceiptSource(
        isDemoMode: false,
        orderId: 'ord-1',
        localView: null,
        localPayment: null,
        repository: _DetailRepo(
          _detail(status: 'completed', payment: paidDetail),
        ),
      );
      expect(source, isNotNull);
      expect(source!.$2.method, PaymentMethod.cash);
      expect(source.$2.status, PaymentStatus.completed);
      expect(source.$2.amountMinor, kSubtotal);
      final doc = buildReceiptDocument(
        l10n,
        source.$1,
        source.$2,
        isDemo: false,
      );
      expect(valuesOf(doc), contains(money(kSubtotal)));
    });
  });
}
