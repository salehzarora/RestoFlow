import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/widgets/kds_ticket_card.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// KITCHEN-PREP-001: the KDS card shows a compact, money-free prep summary when
/// the ticket carries one, and hides the whole block otherwise.
Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

KdsTicketView _ticket({
  List<KitchenPrepComponent> prepSummary = const <KitchenPrepComponent>[],
}) => KdsTicketView(
  kitchenTicketId: 'o1:grill',
  stationId: 'grill',
  status: KitchenTicketStatus.inPreparation,
  orderId: 'o1',
  orderNumber: '#ABC123',
  items: [const KdsItemView(name: 'Burger', quantity: 2)],
  prepSummary: prepSummary,
);

Widget _harness(AppLocalizations l10n, KdsTicketView ticket) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: restoflowLocalizationsDelegates,
  supportedLocales: kSupportedLocales,
  theme: restoflowBaseTheme(brightness: Brightness.dark),
  home: Scaffold(
    body: SizedBox(
      width: 420,
      child: KdsTicketCard(
        ticket: ticket,
        l10n: l10n,
        now: DateTime(2026, 7, 8, 12),
        onAdvance: (_) {},
        onRecall: null,
      ),
    ),
  ),
);

void main() {
  testWidgets('shows the prep summary section + component pills when present', (
    tester,
  ) async {
    final l10n = await _en();
    await tester.pumpWidget(
      _harness(
        l10n,
        _ticket(
          prepSummary: const [
            KitchenPrepComponent(name: 'Beef patty', quantity: 8, unit: 'pcs'),
            KitchenPrepComponent(name: 'Bun', quantity: 4),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kds-prep-summary')), findsOneWidget);
    expect(find.text(l10n.kdsPrepSummaryLabel), findsOneWidget);
    expect(find.text('Beef patty ×8 pcs'), findsOneWidget);
    expect(find.text('Bun ×4'), findsOneWidget);
  });

  testWidgets('hides the prep block entirely when there is no prep', (
    tester,
  ) async {
    final l10n = await _en();
    await tester.pumpWidget(_harness(l10n, _ticket()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kds-prep-summary')), findsNothing);
    expect(find.text(l10n.kdsPrepSummaryLabel), findsNothing);
  });

  testWidgets('the prep summary is money-free (no ₪)', (tester) async {
    final l10n = await _en();
    await tester.pumpWidget(
      _harness(
        l10n,
        _ticket(
          prepSummary: const [
            KitchenPrepComponent(name: 'Beef patty', quantity: 8, unit: 'pcs'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('₪'), findsNothing);
  });
}
