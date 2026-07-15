import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/widgets/kds_ticket_card.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// RESTAURANT-OPERATIONS-V1-001 — the KDS ready-stage action is TYPE-AWARE:
/// a dine-in plate is "Served" to the table, a takeaway bag is "Picked up" by
/// the customer. The UNDERLYING transition is identical either way (the card
/// advances the ticket to bumped, which the pusher maps to the canonical
/// `served` order status) — only the words change.
void main() {
  KitchenTicketStatus? advancedTo;

  KdsTicketView ticket({required String orderType, String? table}) =>
      KdsTicketView(
        kitchenTicketId: 't-1',
        orderId: 'o-1',
        orderNumber: '#000001',
        orderType: orderType,
        tableLabel: table,
        stationId: 'grill',
        submittedAt: DateTime.utc(2026, 7, 14, 12),
        items: const [KdsItemView(name: 'Burger', quantity: 1)],
      );

  Future<AppLocalizations> pump(WidgetTester tester, KdsTicketView t) async {
    advancedTo = null;
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return Scaffold(
              body: SingleChildScrollView(
                child: KdsTicketCard(
                  ticket: t,
                  l10n: l10n,
                  onAdvance: (to) => advancedTo = to,
                  onRecall: null,
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    return l10n;
  }

  testWidgets('a READY dine-in ticket offers "Served"', (tester) async {
    final l10n = await pump(tester, ticket(orderType: 'dine_in', table: 'T3'));
    expect(find.text(l10n.kdsServedAction), findsOneWidget);
    expect(find.text(l10n.kdsPickedUpAction), findsNothing);
  });

  testWidgets('a READY takeaway ticket offers "Picked up"', (tester) async {
    final l10n = await pump(tester, ticket(orderType: 'takeaway'));
    expect(find.text(l10n.kdsPickedUpAction), findsOneWidget);
    expect(find.text(l10n.kdsServedAction), findsNothing);
  });

  testWidgets('BOTH wordings drive the SAME canonical transition', (
    tester,
  ) async {
    var l10n = await pump(tester, ticket(orderType: 'takeaway'));
    await tester.tap(find.text(l10n.kdsPickedUpAction));
    expect(advancedTo, KitchenTicketStatus.bumped);

    l10n = await pump(tester, ticket(orderType: 'dine_in', table: 'T3'));
    await tester.tap(find.text(l10n.kdsServedAction));
    // The SAME bumped advance — the server transition (-> served) is shared;
    // no lifecycle fork was introduced for the wording.
    expect(advancedTo, KitchenTicketStatus.bumped);
  });
}
