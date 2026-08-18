import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/print/native_print_bridges.dart'
    show posReceiptReadinessResolverProvider;
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/print/print_bridge.dart'
    show PosPrintBridge, posPrintBridgeProvider;
import 'package:restoflow_pos/src/print/print_document.dart' show PrintDocument;
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';
import 'package:restoflow_pos/src/state/receipt_print_controller.dart'
    show ReceiptReadiness, receiptPrintControllerProvider;
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/order_action_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// OPEN-ORDER-PRINT-CHOOSER-040 — the gap v35 exposed on real hardware.
///
/// A CLOSED paid order got the two-document chooser in PR #226, but an OPEN
/// unpaid order still only offered «طباعة الحساب» — the customer bill and
/// nothing else. Once the cart moved to the next order there was no way to put
/// a kitchen ticket back on the pass for an order still being served.
///
/// The open row now opens the same chooser with context-appropriate wording:
/// customer BILL (not "receipt" — it may never have been printed, and it is
/// not a paid final document) or kitchen ticket.
///
/// THE BLOCKING RULE is unchanged and is what most of this file exists for:
/// each document reaches ONLY its own configured printer, and neither ever
/// falls back to the other. The receipt bridge and the kitchen seam are
/// observed separately and asserted against each other in every case.

// ---------------------------------------------------------------------------
// Observers — one per printer purpose
// ---------------------------------------------------------------------------

class _RecordingBridge implements PosPrintBridge {
  final List<PrintDocument> documents = [];

  @override
  Future<pp.BridgeSubmitResult> submit(PrintDocument document) async {
    documents.add(document);
    return const pp.BridgeSubmitResult.sentToPrinter();
  }

  @override
  Future<pp.BridgeHealth> health() async => pp.BridgeHealth.connected;
}

class _RecordingKitchen {
  final List<SubmittedOrderView> orders = [];
  PosKitchenPrintOutcome outcome = PosKitchenPrintOutcome.printed;

  PosKitchenReprint get seam =>
      ({required container, required order, required labels}) async {
        orders.add(order);
        return outcome;
      };
}

// ---------------------------------------------------------------------------
// Fixtures — an OPEN, unpaid, already-submitted dine-in order
// ---------------------------------------------------------------------------

const _code = '#OPEN01';
const _orderId = 'order-open-01';

/// Anchored to `now`: the orders surface shows a today+yesterday window, so a
/// hard-coded date would silently rot past a calendar boundary.
DateTime get _at => DateTime.now().toUtc().subtract(const Duration(hours: 1));

SubmittedOrderView _openView() => SubmittedOrderView(
  orderNumber: _code,
  orderType: OrderType.dineIn,
  currencyCode: 'ILS',
  subtotalMinor: 5400,
  orderId: _orderId,
  customerName: 'Rami',
  tableLabel: 'T5',
  lines: [
    SubmittedLineView(
      name: 'Shawarma Plate',
      quantity: 3,
      lineTotalMinor: 5400,
      currencyCode: 'ILS',
      modifiers: const ['Spicy', 'No pickles'],
      note: 'table in a hurry',
    ),
  ],
);

PosOrderSnapshot _openSnapshot({
  String orderId = _orderId,
  String orderCode = _code,
}) => PosOrderSnapshot(
  orderId: orderId,
  orderCode: orderCode,
  revision: 2,
  status: 'served',
  settlement: PosSettlement.unpaid,
  subtotalMinor: 5400,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 5400,
  createdAt: _at,
  updatedAt: _at,
  syncAt: _at,
  orderType: 'dine_in',
  tableLabel: 'T5',
  currencyCode: 'ILS',
);

PosRecentOrder _openOrder({SubmittedOrderView? view}) => PosRecentOrder(
  order: view ?? _openView(),
  snapshot: _openSnapshot(),
  submittedAt: _at,
);

Future<(ProviderContainer, _RecordingBridge, _RecordingKitchen)> _pumpRow(
  WidgetTester tester, {
  PosRecentOrder? row,
  Locale locale = const Locale('en'),
  Size size = const Size(1024, 600),
}) async {
  SharedPreferences.setMockInitialValues(const {});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final bridge = _RecordingBridge();
  final kitchen = _RecordingKitchen();
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
      posNativePrintingAvailableProvider.overrideWithValue(false),
      posPrintBridgeProvider.overrideWithValue(bridge),
      posKitchenReprintProvider.overrideWithValue(kitchen.seam),
      // A CONFIGURED customer printer. Without this the demo harness reports
      // "no printer" and the bill never dispatches — which would let the
      // never-cross-print assertions below pass vacuously.
      posReceiptReadinessResolverProvider.overrideWithValue(
        () async => ReceiptReadiness.configured,
      ),
    ],
  );
  addTearDown(container.dispose);
  final order = row ?? _openOrder();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: OrderActionRow(
              order: order,
              l10n: AppLocalizations.of(ctx),
              actions: resolveOrderActions(order),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container, bridge, kitchen);
}

Finder _printButtonFor(String code) =>
    find.byKey(Key('recent-print-bill-$code'));

Finder get _printButton => _printButtonFor(_code);

Future<void> _openChooser(WidgetTester tester, {String code = _code}) async {
  await tester.tap(_printButtonFor(code));
  await tester.pumpAndSettle();
}

void main() {
  group('A. the OPEN-order chooser', () {
    testWidgets('A1. the open row now opens a chooser with exactly the bill, '
        'the kitchen ticket and cancel — it no longer prints on the spot', (
      tester,
    ) async {
      final (_, bridge, kitchen) = await _pumpRow(tester);
      expect(_printButton, findsOneWidget);
      await _openChooser(tester);

      expect(find.byKey(const Key('print-chooser')), findsOneWidget);
      expect(find.byKey(const Key('print-choice-bill')), findsOneWidget);
      expect(find.byKey(const Key('print-choice-kitchen')), findsOneWidget);
      expect(find.byKey(const Key('print-choice-cancel')), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(2));
      expect(bridge.documents, isEmpty);
      expect(kitchen.orders, isEmpty);
    });

    testWidgets('A2. the button says PRINT, not "reprint" — an unpaid '
        'pre-bill has not necessarily been printed before', (tester) async {
      await _pumpRow(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        find.descendant(
          of: _printButton,
          matching: find.text(l10n.posPrintAction),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _printButton,
          matching: find.text(l10n.posReprintChooserTitle),
        ),
        findsNothing,
      );
    });

    testWidgets('A3. CANCEL prints nothing at all', (tester) async {
      final (_, bridge, kitchen) = await _pumpRow(tester);
      await _openChooser(tester);
      await tester.tap(find.byKey(const Key('print-choice-cancel')));
      await tester.pumpAndSettle();

      expect(bridge.documents, isEmpty);
      expect(kitchen.orders, isEmpty);
    });

    testWidgets('A4. dismissing by BARRIER prints nothing at all', (
      tester,
    ) async {
      final (_, bridge, kitchen) = await _pumpRow(tester);
      await _openChooser(tester);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('print-chooser')), findsNothing);
      expect(bridge.documents, isEmpty);
      expect(kitchen.orders, isEmpty);
    });
  });

  group('B. routing — each purpose reaches ONLY its own printer', () {
    testWidgets('B1. CUSTOMER BILL runs the existing pre-bill path exactly '
        'once and calls the kitchen seam zero times', (tester) async {
      final (container, bridge, kitchen) = await _pumpRow(tester);
      await _openChooser(tester);
      await tester.tap(find.byKey(const Key('print-choice-bill')));
      await tester.pumpAndSettle();

      expect(bridge.documents, hasLength(1));
      // The unchanged pre-bill contract: its own repeatable job key, distinct
      // from the paid receipt's.
      expect(container.read(receiptPrintControllerProvider).keys, [
        'bill:srv:$_orderId',
      ]);
      expect(
        kitchen.orders,
        isEmpty,
        reason: 'a customer bill must never touch the kitchen printer',
      );
    });

    testWidgets('B2. KITCHEN TICKET runs the kitchen seam exactly once and '
        'the receipt bridge zero times', (tester) async {
      final (_, bridge, kitchen) = await _pumpRow(tester);
      await _openChooser(tester);
      await tester.tap(find.byKey(const Key('print-choice-kitchen')));
      await tester.pumpAndSettle();

      expect(kitchen.orders, hasLength(1));
      expect(
        bridge.documents,
        isEmpty,
        reason: 'a kitchen ticket must never reach the receipt printer',
      );
    });

    testWidgets('B3. one kitchen choice is ONE print attempt — no second '
        'document, no bill printed alongside it', (tester) async {
      final (_, bridge, kitchen) = await _pumpRow(tester);
      await _openChooser(tester);
      await tester.tap(find.byKey(const Key('print-choice-kitchen')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));

      expect(kitchen.orders, hasLength(1));
      expect(bridge.documents, isEmpty);
    });
  });

  group('C. the SELECTED OPEN order is what prints', () {
    testWidgets('C1. the kitchen seam receives THIS open order snapshot — its '
        'items, modifiers, note, type and table', (tester) async {
      final (_, _, kitchen) = await _pumpRow(tester);
      await _openChooser(tester);
      await tester.tap(find.byKey(const Key('print-choice-kitchen')));
      await tester.pumpAndSettle();

      final printed = kitchen.orders.single;
      expect(printed.orderNumber, _code);
      expect(printed.orderId, _orderId);
      expect(printed.orderType, OrderType.dineIn);
      expect(printed.tableLabel, 'T5');
      final line = printed.lines.single;
      expect(line.name, 'Shawarma Plate');
      expect(line.quantity, 3);
      expect(line.modifiers, ['Spicy', 'No pickles']);
      expect(line.note, 'table in a hurry');
    });

    testWidgets('C2. THE CART-MOVED-ON CASE: the row prints the order it was '
        'built from, so a DIFFERENT open order on screen prints its own '
        'ticket', (tester) async {
      // Order B is a different open order — the one the row is built from.
      final otherView = SubmittedOrderView(
        orderNumber: '#OPEN02',
        orderType: OrderType.takeaway,
        currencyCode: 'ILS',
        subtotalMinor: 5400,
        orderId: 'order-open-02',
        lines: [
          SubmittedLineView(
            name: 'Falafel Wrap',
            quantity: 1,
            lineTotalMinor: 5400,
            currencyCode: 'ILS',
          ),
        ],
      );
      final (_, _, kitchen) = await _pumpRow(
        tester,
        row: PosRecentOrder(
          order: otherView,
          snapshot: _openSnapshot(
            orderId: 'order-open-02',
            orderCode: '#OPEN02',
          ),
          submittedAt: _at,
        ),
      );
      await _openChooser(tester, code: '#OPEN02');
      await tester.tap(find.byKey(const Key('print-choice-kitchen')));
      await tester.pumpAndSettle();

      final printed = kitchen.orders.single;
      expect(
        printed.orderNumber,
        '#OPEN02',
        reason: 'the ticket must come from the SELECTED row, never a cart',
      );
      expect(printed.lines.single.name, 'Falafel Wrap');
    });
  });

  group('D. failure is purpose-scoped — never a cross-printer fallback', () {
    for (final outcome in const [
      PosKitchenPrintOutcome.noPrinterConfigured,
      PosKitchenPrintOutcome.unavailable,
      PosKitchenPrintOutcome.failed,
    ]) {
      testWidgets('D1. kitchen ${outcome.name} on an OPEN order: the receipt '
          'printer is NEVER used as a fallback', (tester) async {
        final (_, bridge, kitchen) = await _pumpRow(tester);
        kitchen.outcome = outcome;
        await _openChooser(tester);
        await tester.tap(find.byKey(const Key('print-choice-kitchen')));
        await tester.pumpAndSettle();

        expect(kitchen.orders, hasLength(1));
        expect(
          bridge.documents,
          isEmpty,
          reason: 'a failed kitchen print must not silently print the bill',
        );
      });
    }

    testWidgets('D2. an open order with NO printable kitchen snapshot refuses '
        'in KITCHEN terms and prints nothing anywhere', (tester) async {
      // Branch-discovered: this device never saw the lines.
      final (_, bridge, kitchen) = await _pumpRow(
        tester,
        row: PosRecentOrder.discovered(_openSnapshot()),
      );
      await _openChooser(tester);
      await tester.tap(find.byKey(const Key('print-choice-kitchen')));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.posReprintKitchenUnavailable), findsOneWidget);
      expect(kitchen.orders, isEmpty);
      expect(
        bridge.documents,
        isEmpty,
        reason: 'no kitchen ticket must never mean "print the bill instead"',
      );
    });
  });

  group('E. the order stays exactly as it was', () {
    testWidgets('E1. after a kitchen reprint the row is still UNPAID and open '
        '— printing settles nothing', (tester) async {
      final row = _openOrder();
      final before = resolveOrderActions(row);
      final (_, _, kitchen) = await _pumpRow(tester, row: row);
      await _openChooser(tester);
      await tester.tap(find.byKey(const Key('print-choice-kitchen')));
      await tester.pumpAndSettle();

      expect(kitchen.orders, hasLength(1));
      // The row object is immutable and the policy still reads the same:
      // still payable, still bill-printable, no payment appeared.
      final after = resolveOrderActions(row);
      expect(row.payment, isNull);
      expect(after.canPay, before.canPay);
      expect(after.canPrintBill, before.canPrintBill);
      expect(after.canOpenReceipt, before.canOpenReceipt);
      expect(row.snapshot!.settlement, PosSettlement.unpaid);
    });
  });

  group('F. the CLOSED-order chooser from PR #226 is untouched', () {
    testWidgets('F1. a paid order still shows the REPRINT chooser with its '
        'own keys and wording', (tester) async {
      final paid = PosRecentOrder(
        order: _openView(),
        snapshot: PosOrderSnapshot(
          orderId: _orderId,
          orderCode: _code,
          revision: 3,
          status: 'served',
          settlement: PosSettlement.paid,
          subtotalMinor: 5400,
          discountTotalMinor: 0,
          taxTotalMinor: 0,
          grandTotalMinor: 5400,
          createdAt: _at,
          updatedAt: _at,
          syncAt: _at,
          orderType: 'dine_in',
          tableLabel: 'T5',
          currencyCode: 'ILS',
        ),
        submittedAt: _at,
      );
      final (_, bridge, kitchen) = await _pumpRow(tester, row: paid);

      // The OPEN print control is gone; the paid reprint control is there.
      expect(_printButton, findsNothing);
      await tester.tap(find.byKey(const Key('recent-reprint-$_code')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reprint-chooser')), findsOneWidget);
      expect(find.byKey(const Key('reprint-choice-customer')), findsOneWidget);
      expect(find.byKey(const Key('reprint-choice-kitchen')), findsOneWidget);
      expect(bridge.documents, isEmpty);
      expect(kitchen.orders, isEmpty);
    });
  });

  group('G. locales and layout', () {
    for (final (locale, title, bill) in const [
      (Locale('ar'), 'خيارات الطباعة', 'حساب الزبون'),
      (Locale('he'), 'אפשרויות הדפסה', 'חשבון לקוח'),
      (Locale('en'), 'Print options', 'Customer bill'),
    ]) {
      testWidgets('G1. ${locale.languageCode}: the open chooser renders its '
          'localized title and both options without overflow', (tester) async {
        final overflows = <String>[];
        final prior = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.exceptionAsString().contains('overflowed')) {
            overflows.add(details.toString());
          } else {
            prior?.call(details);
          }
        };
        await _pumpRow(tester, locale: locale);
        await _openChooser(tester);
        final l10n = await AppLocalizations.delegate.load(locale);
        FlutterError.onError = prior;

        expect(find.text(title), findsOneWidget);
        expect(find.text(bill), findsOneWidget);
        expect(find.text(l10n.posReprintKitchenTicket), findsOneWidget);
        expect(
          overflows.where((o) => o.contains('order_action_row.dart')),
          isEmpty,
        );
      });
    }

    testWidgets('G2. the open chooser fits a NARROW tablet', (tester) async {
      final overflows = <String>[];
      final prior = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) {
          overflows.add(details.toString());
        } else {
          prior?.call(details);
        }
      };
      await _pumpRow(
        tester,
        locale: const Locale('ar'),
        size: const Size(600, 960),
      );
      await _openChooser(tester);
      FlutterError.onError = prior;

      expect(find.byKey(const Key('print-chooser')), findsOneWidget);
      expect(
        overflows.where((o) => o.contains('order_action_row.dart')),
        isEmpty,
      );
    });
  });
}
