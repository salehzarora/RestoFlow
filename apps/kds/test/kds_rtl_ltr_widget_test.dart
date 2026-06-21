import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kds/src/kds_screen.dart';
import 'package:restoflow_kds/src/kds_ticket_view.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// RF-034 AC#3 (DECISION D-014): the KDS screen renders correctly in LTR (en)
/// and RTL (ar/he), using the SHARED `packages/l10n` wiring (direction is
/// data-driven by GlobalWidgetsLocalizations — no manual hacks).
List<KdsTicketView> _tickets() => [
  KdsTicketView(
    kitchenTicketId: 'order-1:grill',
    stationId: 'grill',
    items: const [KdsItemView(name: 'Burger', quantity: 2)],
  ),
];

Future<({TextDirection direction, AppLocalizations l10n})> _pump(
  WidgetTester tester,
  Locale locale,
) async {
  late TextDirection direction;
  late AppLocalizations l10n;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Builder(
        builder: (context) {
          direction = Directionality.of(context);
          l10n = AppLocalizations.of(context);
          return KdsScreen(tickets: _tickets());
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (direction: direction, l10n: l10n);
}

void main() {
  testWidgets('en renders LTR with localized chrome + ticket content', (
    tester,
  ) async {
    final r = await _pump(tester, const Locale('en'));
    expect(r.direction, TextDirection.ltr);
    // Localized chrome renders (bump action on a ready ticket).
    expect(find.text(r.l10n.kdsBumpAction), findsOneWidget);
    // Ticket data content renders.
    expect(find.textContaining('grill'), findsWidgets);
    expect(find.textContaining('Burger'), findsOneWidget);
  });

  testWidgets('ar renders RTL with localized chrome', (tester) async {
    final r = await _pump(tester, const Locale('ar'));
    expect(r.direction, TextDirection.rtl);
    expect(r.l10n.kdsBumpAction, isNot('Bump'));
    expect(find.text(r.l10n.kdsBumpAction), findsOneWidget);
    expect(find.textContaining('Burger'), findsOneWidget);
  });

  testWidgets('he renders RTL with localized chrome', (tester) async {
    final r = await _pump(tester, const Locale('he'));
    expect(r.direction, TextDirection.rtl);
    expect(r.l10n.kdsBumpAction, isNot('Bump'));
    expect(find.text(r.l10n.kdsBumpAction), findsOneWidget);
  });

  testWidgets('empty ticket list renders the localized empty state', (
    tester,
  ) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return const KdsScreen(tickets: []);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.kdsEmptyState), findsOneWidget);
  });
}
