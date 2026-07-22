import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:restoflow_pos/src/state/pos_printer_assignments.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/order_confirmation.dart';
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

Future<void> _pump(WidgetTester tester, SubmittedOrderView order) async {
  SharedPreferences.setMockInitialValues(const {});
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      posPrinterAssignmentsReaderProvider.overrideWithValue(
        _EmptyAssignments(),
      ),
      paymentRepositoryProvider.overrideWithValue(DemoPaymentStore()),
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
}
