import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/print/print_bridge.dart'
    show PosPrintBridge, posPrintBridgeProvider;
import 'package:restoflow_pos/src/print/print_document.dart' show PrintDocument;
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/order_action_row.dart';

/// ORDER-REPRINT-CHOOSER-038 — reprinting a customer receipt OR a kitchen
/// ticket from an existing order.
///
/// THE BLOCKING RULE these tests exist for: each document goes to its OWN
/// configured printer and there is never a cross-purpose fallback. A kitchen
/// ticket must never reach the receipt printer, an unavailable kitchen printer
/// must never quietly produce a receipt instead, and vice versa. That is only
/// provable if each path is observed separately — hence the recording bridge
/// (receipt) and the recording kitchen seam (kitchen), asserted against each
/// other on every case.
///
/// The chooser is also PRINT-ONLY: it composes and sends. Nothing here creates
/// an order, resubmits one, or moves any order/payment/table/kitchen state.

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

/// Records every KITCHEN reprint request without touching any transport.
class _RecordingKitchen {
  final List<SubmittedOrderView> orders = [];
  PosKitchenPrintOutcome outcome = PosKitchenPrintOutcome.printed;

  PosKitchenReprint get seam =>
      ({required container, required order, required labels}) async {
        orders.add(order);
        return outcome;
      };
}

/// A FIXED instant — a reprint must show when the money was taken, and a
/// fixture dated "now" rots across a calendar boundary.
final _paidAt = DateTime.utc(2026, 8, 17, 12, 30);

// ---------------------------------------------------------------------------
// Fixtures — a PAID historical order, with modifiers, a note and a table
// ---------------------------------------------------------------------------

SubmittedOrderView _historicalOrder() => SubmittedOrderView(
  orderNumber: '#HIST1',
  orderType: OrderType.dineIn,
  currencyCode: 'ILS',
  subtotalMinor: 9400,
  orderId: 'order-hist-1',
  customerName: 'Dana',
  tableLabel: '7',
  lines: [
    SubmittedLineView(
      name: 'Classic Burger',
      quantity: 2,
      lineTotalMinor: 9400,
      currencyCode: 'ILS',
      modifiers: const ['Extra cheese', 'No onion'],
      note: 'well done',
    ),
  ],
);

PosRecentOrder _paidRow({SubmittedOrderView? view}) => PosRecentOrder(
  order: view ?? _historicalOrder(),
  status: 'served',
  payment: CashPayment(
    paymentId: 'pay-HIST1',
    orderNumber: '#HIST1',
    deviceId: 'dev-1',
    localOperationId: 'op-pay-hist-1',
    method: PaymentMethod.cash,
    status: PaymentStatus.completed,
    amountMinor: 9400,
    tenderedMinor: 10000,
    changeMinor: 600,
    currencyCode: 'ILS',
    receiptNumber: 'R-99',
    paidAt: _paidAt,
    orderId: 'order-hist-1',
  ),
);

Future<(ProviderContainer, _RecordingBridge, _RecordingKitchen)> _pumpRow(
  WidgetTester tester, {
  PosRecentOrder? row,
  Locale locale = const Locale('en'),
  Size size = const Size(1024, 600),
}) async {
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
    ],
  );
  addTearDown(container.dispose);
  final order = row ?? _paidRow();
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

Future<void> _openChooser(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('recent-reprint-#HIST1')));
  await tester.pumpAndSettle();
}

void main() {
  group('A. the chooser itself', () {
    testWidgets('A1. tapping reprint offers EXACTLY two documents plus '
        'cancel — it no longer prints on the spot', (tester) async {
      final (_, bridge, kitchen) = await _pumpRow(tester);
      await _openChooser(tester);

      expect(find.byKey(const Key('reprint-chooser')), findsOneWidget);
      expect(find.byKey(const Key('reprint-choice-customer')), findsOneWidget);
      expect(find.byKey(const Key('reprint-choice-kitchen')), findsOneWidget);
      expect(find.byKey(const Key('reprint-choice-cancel')), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(2));
      // Opening the chooser prints NOTHING.
      expect(bridge.documents, isEmpty);
      expect(kitchen.orders, isEmpty);
    });

    testWidgets('A2. CANCEL prints nothing at all', (tester) async {
      final (_, bridge, kitchen) = await _pumpRow(tester);
      await _openChooser(tester);
      await tester.tap(find.byKey(const Key('reprint-choice-cancel')));
      await tester.pumpAndSettle();

      expect(bridge.documents, isEmpty);
      expect(kitchen.orders, isEmpty);
    });

    testWidgets('A3. dismissing by BARRIER prints nothing at all', (
      tester,
    ) async {
      final (_, bridge, kitchen) = await _pumpRow(tester);
      await _openChooser(tester);
      // Tap well above the sheet — the modal barrier.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reprint-chooser')), findsNothing);
      expect(bridge.documents, isEmpty);
      expect(kitchen.orders, isEmpty);
    });
  });

  group('B. routing — each purpose reaches ONLY its own printer', () {
    testWidgets('B1. CUSTOMER uses the receipt path exactly once and the '
        'kitchen path zero times', (tester) async {
      final (_, bridge, kitchen) = await _pumpRow(tester);
      await _openChooser(tester);
      await tester.tap(find.byKey(const Key('reprint-choice-customer')));
      await tester.pumpAndSettle();

      expect(bridge.documents, hasLength(1));
      expect(
        kitchen.orders,
        isEmpty,
        reason: 'a customer receipt must never touch the kitchen printer',
      );
    });

    testWidgets('B2. KITCHEN uses the kitchen path exactly once and the '
        'receipt path zero times', (tester) async {
      final (_, bridge, kitchen) = await _pumpRow(tester);
      await _openChooser(tester);
      await tester.tap(find.byKey(const Key('reprint-choice-kitchen')));
      await tester.pumpAndSettle();

      expect(kitchen.orders, hasLength(1));
      expect(
        bridge.documents,
        isEmpty,
        reason: 'a kitchen ticket must never reach the receipt printer',
      );
    });

    testWidgets('B3. ONE kitchen selection is exactly ONE print attempt — no '
        'second document, no automatic receipt alongside it', (tester) async {
      final (_, bridge, kitchen) = await _pumpRow(tester);
      await _openChooser(tester);
      await tester.tap(find.byKey(const Key('reprint-choice-kitchen')));
      await tester.pumpAndSettle();
      // Settle again: nothing may fire a second time.
      await tester.pump(const Duration(seconds: 1));

      expect(kitchen.orders, hasLength(1));
      expect(bridge.documents, isEmpty);
    });
  });

  group('C. the SELECTED HISTORICAL order is what prints', () {
    testWidgets('C1. the kitchen seam receives the order-time snapshot — its '
        'items, modifiers, note, type and table — not the current cart', (
      tester,
    ) async {
      final (_, _, kitchen) = await _pumpRow(tester);
      await _openChooser(tester);
      await tester.tap(find.byKey(const Key('reprint-choice-kitchen')));
      await tester.pumpAndSettle();

      final printed = kitchen.orders.single;
      expect(printed.orderNumber, '#HIST1');
      expect(printed.orderId, 'order-hist-1');
      expect(printed.orderType, OrderType.dineIn);
      expect(printed.tableLabel, '7');
      final line = printed.lines.single;
      expect(line.name, 'Classic Burger');
      expect(line.quantity, 2);
      expect(line.modifiers, ['Extra cheese', 'No onion']);
      expect(line.note, 'well done');
    });
  });

  group('D. failure is purpose-scoped — never a cross-printer fallback', () {
    for (final outcome in const [
      PosKitchenPrintOutcome.noPrinterConfigured,
      PosKitchenPrintOutcome.unavailable,
      PosKitchenPrintOutcome.failed,
    ]) {
      testWidgets('D1. kitchen ${outcome.name}: the receipt printer is NEVER '
          'used as a fallback', (tester) async {
        final (_, bridge, kitchen) = await _pumpRow(tester);
        kitchen.outcome = outcome;
        await _openChooser(tester);
        await tester.tap(find.byKey(const Key('reprint-choice-kitchen')));
        await tester.pumpAndSettle();

        expect(kitchen.orders, hasLength(1));
        expect(
          bridge.documents,
          isEmpty,
          reason: 'a failed kitchen print must not silently print a receipt',
        );
      });
    }

    testWidgets('D2. an order with NO printable kitchen snapshot refuses in '
        'KITCHEN terms and prints nothing anywhere', (tester) async {
      // A discovered/server-only row carries no device-owned snapshot.
      // A BRANCH-DISCOVERED row: another till took this order, so this device
      // never saw its lines and has no kitchen snapshot to print. The domain
      // requires one source or the other, so this carries the server snapshot.
      final row = PosRecentOrder.discovered(
        PosOrderSnapshot(
          orderId: 'order-hist-1',
          orderCode: '#HIST1',
          revision: 3,
          status: 'served',
          settlement: PosSettlement.paid,
          subtotalMinor: 9400,
          discountTotalMinor: 0,
          taxTotalMinor: 0,
          grandTotalMinor: 9400,
          createdAt: _paidAt,
          updatedAt: _paidAt,
          syncAt: _paidAt,
          orderType: 'dine_in',
          tableLabel: '7',
          currencyCode: 'ILS',
        ),
      );
      final (_, bridge, kitchen) = await _pumpRow(tester, row: row);
      await _openChooser(tester);
      await tester.tap(find.byKey(const Key('reprint-choice-kitchen')));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.posReprintKitchenUnavailable), findsOneWidget);
      expect(kitchen.orders, isEmpty);
      expect(
        bridge.documents,
        isEmpty,
        reason: 'no kitchen ticket must never mean "print a receipt instead"',
      );
    });
  });

  group('E. eligibility is unchanged', () {
    testWidgets('E1. an UNPAID order still offers no reprint control at all, '
        'so no chooser exists to open', (tester) async {
      final unpaid = PosRecentOrder(order: _historicalOrder());
      final (_, bridge, kitchen) = await _pumpRow(tester, row: unpaid);

      expect(find.byKey(const Key('recent-reprint-#HIST1')), findsNothing);
      expect(bridge.documents, isEmpty);
      expect(kitchen.orders, isEmpty);
    });
  });

  group('F. locales and layout', () {
    for (final (locale, title) in const [
      (Locale('ar'), 'إعادة الطباعة'),
      (Locale('he'), 'הדפסה חוזרת'),
      (Locale('en'), 'Reprint'),
    ]) {
      testWidgets('F1. ${locale.languageCode}: the chooser renders its '
          'localized title and both options without overflow at 1024x600', (
        tester,
      ) async {
        final overflows = <String>[];
        final prior = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.exceptionAsString().contains('overflowed')) {
            overflows.add(details.toString());
          } else {
            prior?.call(details);
          }
        };
        final (_, _, _) = await _pumpRow(tester, locale: locale);
        await _openChooser(tester);
        final l10n = await AppLocalizations.delegate.load(locale);
        FlutterError.onError = prior;

        expect(find.text(title), findsOneWidget);
        expect(find.text(l10n.posReprintCustomerReceipt), findsOneWidget);
        expect(find.text(l10n.posReprintKitchenTicket), findsOneWidget);
        expect(
          overflows.where((o) => o.contains('order_action_row.dart')),
          isEmpty,
        );
      });
    }

    testWidgets('F2. the chooser fits a NARROW tablet without overflow', (
      tester,
    ) async {
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

      expect(find.byKey(const Key('reprint-chooser')), findsOneWidget);
      expect(
        overflows.where((o) => o.contains('order_action_row.dart')),
        isEmpty,
      );
    });
  });
}
