import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/print/kds_ticket_document.dart';
import 'package:restoflow_kds/src/print/print_document.dart';
import 'package:restoflow_kds/src/state/kds_kitchen_print_controller.dart';
import 'package:restoflow_kds/src/widgets/kds_ticket_card.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Device settings sprint (Part D): the kitchen print pipeline over REAL
/// synced tickets — the payload carries modifier quantities + notes and NO
/// money (T-003); preparation is idempotent per order (no double print
/// across poll refreshes); the ticket card renders the honest status line.

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

KdsTicketView _ticket({String? orderId = 'o1'}) => KdsTicketView(
  kitchenTicketId: 'kt-1',
  stationId: 'grill',
  orderId: orderId,
  orderNumber: '#3F7A2C',
  orderType: 'dine_in',
  tableLabel: 'T2',
  notes: 'rush order',
  items: [
    KdsItemView(
      name: 'برجر كلاسيك',
      quantity: 1,
      modifiers: const ['وسط', 'جبنة إضافية ×2'],
      note: 'بدون بصل',
    ),
  ],
  status: KitchenTicketStatus.newTicket,
);

void main() {
  test('the kitchen document carries code/table/items/modifier quantities/'
      'notes — and NO money', () async {
    final l10n = await _en();

    final html = documentToHtml(buildKdsTicketDocument(l10n, _ticket()));

    expect(html, contains('#3F7A2C'));
    expect(html, contains('T2'));
    expect(html, contains('برجر كلاسيك'));
    expect(html, contains('1×'));
    expect(html, contains('جبنة إضافية ×2')); // modifier quantity
    expect(html, contains('بدون بصل')); // item note
    expect(html, contains('rush order')); // order-level note
    // Money-free (T-003): no shekel sign, no money-looking tokens.
    expect(html.contains('₪'), isFalse);
    expect(html.toLowerCase().contains('minor'), isFalse);
    expect(html.contains(r'$'), isFalse);
  });

  test(
    'preparation is IDEMPOTENT per order id across poll-rebuilt views',
    () async {
      final l10n = await _en();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(
        kdsKitchenPrintControllerProvider.notifier,
      );
      var builds = 0;

      // The board rebuilds KdsTicketView objects on every pull — same order id,
      // different instances. Only the FIRST prepare may build/print.
      for (var i = 0; i < 3; i++) {
        controller.prepareForTicket(
          _ticket(),
          hasEnabledPrinter: true,
          buildDocument: () {
            builds++;
            return buildKdsTicketDocument(l10n, _ticket());
          },
        );
      }

      expect(builds, 1);
      expect(controller.jobFor(_ticket())!.status, KdsPrintJobStatus.prepared);
      expect(
        controller.jobFor(_ticket())!.status,
        isNot(KdsPrintJobStatus.printed),
      );
    },
  );

  test('no enabled kitchen printer -> an honest notConfigured marker', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(
      kdsKitchenPrintControllerProvider.notifier,
    );

    controller.prepareForTicket(
      _ticket(),
      hasEnabledPrinter: false,
      buildDocument: () => throw StateError('never built'),
    );

    expect(
      controller.jobFor(_ticket())!.status,
      KdsPrintJobStatus.notConfigured,
    );
  });

  testWidgets('the ticket card renders the print-status line when given one '
      '(and nothing when null)', (tester) async {
    final l10n = await _en();
    Widget card({String? printStatus}) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 420,
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

    await tester.pumpWidget(card(printStatus: l10n.printStatusPrepared));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ticket-print-status')), findsOneWidget);
    expect(find.textContaining(l10n.printStatusPrepared), findsOneWidget);
    expect(find.textContaining('₪'), findsNothing);

    await tester.pumpWidget(card());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ticket-print-status')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
