import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/print/kds_ticket_document.dart';
import 'package:restoflow_kds/src/print/print_document.dart';
import 'package:restoflow_kds/src/widgets/kds_ticket_card.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// ORDER-CUSTOMER-001: the OPTIONAL customer name appears on the KDS kitchen
/// ticket + the on-screen card when present, is omitted when absent, and the
/// kitchen surface stays MONEY-FREE (T-003).

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

KdsTicketView _ticket({String? customerName}) => KdsTicketView(
  kitchenTicketId: 'o1:grill',
  stationId: 'grill',
  status: KitchenTicketStatus.inPreparation,
  orderId: 'o1',
  orderNumber: '#ABC123',
  orderType: 'dine_in',
  tableLabel: 'T3',
  customerName: customerName,
  items: [
    const KdsItemView(
      name: 'Burger',
      quantity: 2,
      modifiers: ['extra cheese'],
      note: 'well done',
    ),
  ],
);

Widget _harness(AppLocalizations l10n, KdsTicketView ticket) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: restoflowLocalizationsDelegates,
  supportedLocales: kSupportedLocales,
  theme: restoflowBaseTheme(brightness: Brightness.dark),
  home: Scaffold(
    body: SizedBox(
      width: 480,
      child: KdsTicketCard(
        ticket: ticket,
        l10n: l10n,
        onAdvance: (_) {},
        onRecall: null,
      ),
    ),
  ),
);

void main() {
  group('kitchen ticket document', () {
    test('includes a customer row when present; money-free', () async {
      final l10n = await _en();
      final doc = buildKdsTicketDocument(l10n, _ticket(customerName: 'Dana'));
      final html = documentToHtml(doc);
      expect(html, contains(l10n.customerNameKitchenLabel));
      expect(html, contains('Dana'));
      // Money-free (T-003): the kitchen ticket never carries money.
      expect(html.contains('₪'), isFalse);
      expect(html.toLowerCase().contains('minor'), isFalse);
    });

    test('omits the customer row when absent', () async {
      final l10n = await _en();
      final doc = buildKdsTicketDocument(l10n, _ticket());
      final lines = doc.lines
          .map((l) => '${l.left ?? ''}|${l.right ?? ''}')
          .join('\n');
      expect(lines.contains('Dana'), isFalse);
      // The customer label only appears when a name is present.
      expect(lines.contains('${l10n.customerNameKitchenLabel}|'), isFalse);
    });
  });

  group('ticket card', () {
    testWidgets('shows a compact customer pill when present', (tester) async {
      final l10n = await _en();
      await tester.pumpWidget(_harness(l10n, _ticket(customerName: 'Dana')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('customer-o1:grill')), findsOneWidget);
      expect(
        find.text('${l10n.customerNameKitchenLabel}: Dana'),
        findsOneWidget,
      );
    });

    testWidgets('shows no customer pill when absent', (tester) async {
      final l10n = await _en();
      await tester.pumpWidget(_harness(l10n, _ticket()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('customer-o1:grill')), findsNothing);
    });

    testWidgets('the card shows no money anywhere (T-003)', (tester) async {
      final l10n = await _en();
      await tester.pumpWidget(_harness(l10n, _ticket(customerName: 'Dana')));
      await tester.pumpAndSettle();
      expect(find.textContaining('₪'), findsNothing);
      expect(find.textContaining('minor'), findsNothing);
    });
  });
}
