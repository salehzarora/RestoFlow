import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/widgets/kds_ticket_card.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// PRINT-STABILITY-001: the KDS ticket card shows a Reprint action for an
/// already-SENT ticket (a money-free extra copy) and a Retry for a failed one,
/// both wired to re-run the kitchen print job. No money is ever shown (T-003).

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

KdsTicketView _ticket() => KdsTicketView(
  kitchenTicketId: 'o1:grill',
  stationId: 'grill',
  status: KitchenTicketStatus.inPreparation,
  orderId: 'o1',
  orderNumber: '#ABC123',
  orderType: 'dine_in',
  tableLabel: 'T3',
  customerName: 'Dana',
  items: [const KdsItemView(name: 'Burger', quantity: 2)],
);

Widget _harness(
  AppLocalizations l10n, {
  required KdsTicketPrintStatus printStatus,
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: restoflowLocalizationsDelegates,
  supportedLocales: kSupportedLocales,
  theme: restoflowBaseTheme(brightness: Brightness.dark),
  home: Scaffold(
    body: SizedBox(
      width: 480,
      child: KdsTicketCard(
        ticket: _ticket(),
        l10n: l10n,
        onAdvance: (_) {},
        onRecall: null,
        printStatus: printStatus,
      ),
    ),
  ),
);

void main() {
  testWidgets('a SENT ticket shows a Reprint action that re-runs the job', (
    tester,
  ) async {
    final l10n = await _en();
    var reprints = 0;
    await tester.pumpWidget(
      _harness(
        l10n,
        printStatus: KdsTicketPrintStatus(
          label: l10n.printStatusSentToPrinter,
          onRetry: () => reprints++,
          actionLabel: l10n.printReprintAction,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The action reads "Reprint" (not "Retry") and fires the re-run.
    expect(find.text(l10n.printReprintAction), findsOneWidget);
    expect(find.text(l10n.printRetryAction), findsNothing);
    await tester.tap(find.byKey(const Key('ticket-print-retry')));
    await tester.pump();
    expect(reprints, 1);

    // Money-free (T-003).
    expect(find.textContaining('₪'), findsNothing);
  });

  testWidgets('a FAILED ticket keeps the Retry label (default)', (
    tester,
  ) async {
    final l10n = await _en();
    await tester.pumpWidget(
      _harness(
        l10n,
        printStatus: KdsTicketPrintStatus(
          label: l10n.printStatusFailed,
          onRetry: () {},
          isError: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.printRetryAction), findsOneWidget);
  });
}
