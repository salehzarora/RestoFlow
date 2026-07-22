import 'dart:convert' show jsonEncode, utf8;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:restoflow_pos/src/state/pos_printer_assignments.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart'
    show posNativePrintingAvailableProvider;
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/order_confirmation.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

/// KITCHEN-PRINT-DUAL-001 — the manual "Print kitchen ticket" action is
/// available ONLY once a real server order id exists (never on a bare submit
/// with no id, never on a rejected draft).

class _EmptyAssignments implements DevicePrinterAssignmentsReader {
  @override
  Future<Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>>
  load() async => Success(
    DevicePrinterAssignments(
      fetchedAt: DateTime(2026, 7, 22, 12),
      printers: const [],
    ),
  );
}

const _lines = [
  SubmittedLineView(
    name: 'Classic Burger',
    quantity: 1,
    lineTotalMinor: 5400,
    currencyCode: 'ILS',
  ),
];

const _orderNoId = SubmittedOrderView(
  orderNumber: '#3F7A2C',
  orderType: OrderType.dineIn,
  currencyCode: 'ILS',
  subtotalMinor: 5400,
  lines: _lines,
);

const _orderWithId = SubmittedOrderView(
  orderNumber: '#3F7A2C',
  orderType: OrderType.dineIn,
  currencyCode: 'ILS',
  subtotalMinor: 5400,
  orderId: 'order-1',
  lines: _lines,
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  SubmittedOrderView order, {
  Map<String, Object> prefs = const {},
  List<Override> extraOverrides = const [],
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      // A REAL (non-demo) order — otherwise the shared eligibility rule
      // correctly hides the kitchen button for demo orders.
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posPrinterAssignmentsReaderProvider.overrideWithValue(
        _EmptyAssignments(),
      ),
      paymentRepositoryProvider.overrideWithValue(DemoPaymentStore()),
      ...extraOverrides,
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: OrderConfirmation(order: order, onNewOrder: () {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('ABSENT until a real order id exists', (tester) async {
    await _pump(tester, _orderNoId);
    expect(find.byKey(const Key('print-kitchen-ticket-button')), findsNothing);
  });

  testWidgets('present for a real created order (localized label)', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _pump(tester, _orderWithId);
    expect(
      find.byKey(const Key('print-kitchen-ticket-button')),
      findsOneWidget,
    );
    expect(find.text(l10n.posPrintKitchenTicketAction), findsOneWidget);
  });

  testWidgets('F5 manual real path: the REAL button routes money-free kitchen '
      'bytes to the KITCHEN endpoint; order/payment/KDS unchanged', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final captured = _CapturingTransport();
    String? routedKey;
    final c = await _pump(
      tester,
      _orderWithId,
      prefs: {
        'restoflow.printer.selected.pos.kitchen_ticket.local': 'network',
        'restoflow.printer.network.pos.kitchen_ticket.local': jsonEncode({
          'host': '10.0.0.9',
          'port': 9100,
        }),
      },
      extraOverrides: [
        posNativePrintingAvailableProvider.overrideWithValue(true),
        kitchenPrintTransportOverrideProvider.overrideWithValue((target) {
          routedKey = target.destinationKey;
          return captured;
        }),
      ],
    );

    await tester.tap(find.byKey(const Key('print-kitchen-ticket-button')));
    await tester.pumpAndSettle();

    // One send, routed to the KITCHEN endpoint (purpose = kitchen_ticket).
    expect(captured.sent, hasLength(1));
    expect(
      routedKey,
      pp.PrinterDestinationSendGate.networkKey('10.0.0.9', 9100),
    );
    // The REAL kitchen renderer output — item present, no money.
    final text = utf8
        .decode(captured.sent.single, allowMalformed: true)
        .toLowerCase();
    expect(text.contains('classic burger'), isTrue);
    for (final t in ['total', 'subtotal', 'tax', 'payment', '5400', '₪']) {
      expect(text.contains(t.toLowerCase()), isFalse, reason: 'no money "$t"');
    }
    // Honest confirmation feedback is shown.
    expect(find.text(l10n.posKitchenTicketPrintedSnack), findsOneWidget);
    // Order/payment/KDS state UNCHANGED: no payment recorded for this order.
    expect(
      c.read(paymentControllerProvider).paymentFor(_orderWithId.identity),
      isNull,
    );
  });
}

/// Records the bytes + the resolved destination key it was routed to.
class _CapturingTransport implements pp.PrintTransport {
  final List<Uint8List> sent = [];
  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    sent.add(bytes);
    return const pp.PrintResult.success();
  }

  @override
  Future<void> dispose() async {}
}
