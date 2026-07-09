import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/print/kds_print_bridge.dart'
    show kitchenTicketToEscPosDocument;
import 'package:restoflow_kds/src/print/kds_ticket_document.dart';
import 'package:restoflow_kds/src/print/print_document.dart';
import 'package:restoflow_kds/src/widgets/kds_ticket_card.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// KITCHEN-MEAT-001: the whole-order meat total is the primary top chef note on
/// the KDS card + printed ticket (above the generic prep summary), while normal
/// item details stay below. Money-free; Arabic raster preserved.
Future<AppLocalizations> _l10n(String locale) =>
    AppLocalizations.delegate.load(Locale(locale));

KdsTicketView _ticket({
  List<KitchenMeat> meatTotals = const <KitchenMeat>[],
  List<KitchenPrepComponent> prepSummary = const <KitchenPrepComponent>[],
  String item = 'Burger',
}) => KdsTicketView(
  kitchenTicketId: 'o1:grill',
  stationId: 'grill',
  status: KitchenTicketStatus.acknowledged,
  orderId: 'o1',
  orderNumber: '#ABC123',
  orderType: 'dine_in',
  items: [
    KdsItemView(name: item, quantity: 2, modifiers: const ['Double']),
  ],
  prepSummary: prepSummary,
  meatTotals: meatTotals,
);

Widget _harness(
  AppLocalizations l10n,
  KdsTicketView ticket, {
  String locale = 'en',
}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: restoflowLocalizationsDelegates,
  supportedLocales: kSupportedLocales,
  theme: restoflowBaseTheme(brightness: Brightness.dark),
  home: Scaffold(
    body: SizedBox(
      width: 460,
      child: KdsTicketCard(
        ticket: ticket,
        l10n: l10n,
        now: DateTime(2026, 7, 9, 12),
        onAdvance: (_) {},
        onRecall: null,
      ),
    ),
  ),
);

void main() {
  group('KDS card', () {
    testWidgets('shows the meat total at the top; item details stay below', (
      tester,
    ) async {
      final l10n = await _l10n('en');
      await tester.pumpWidget(
        _harness(
          l10n,
          _ticket(
            meatTotals: const [KitchenMeat(quantity: 9, unit: 'patties')],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('kds-meat-total')), findsOneWidget);
      expect(find.text(l10n.kdsMeatTotalLabel('9', 'patties')), findsOneWidget);
      // Normal item + modifier still rendered underneath.
      expect(find.textContaining('Burger'), findsWidgets);
      expect(find.text('+ Double'), findsOneWidget);
    });

    testWidgets('hides the meat block when there is no meat total', (
      tester,
    ) async {
      final l10n = await _l10n('en');
      await tester.pumpWidget(_harness(l10n, _ticket()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kds-meat-total')), findsNothing);
    });

    testWidgets('meat is primary: the generic prep summary is hidden from the '
        'top when a meat total exists', (tester) async {
      final l10n = await _l10n('en');
      await tester.pumpWidget(
        _harness(
          l10n,
          _ticket(
            meatTotals: const [KitchenMeat(quantity: 9, unit: 'patties')],
            prepSummary: const [KitchenPrepComponent(name: 'Bun', quantity: 5)],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kds-meat-total')), findsOneWidget);
      expect(find.byKey(const Key('kds-prep-summary')), findsNothing);
    });

    testWidgets('the meat total is money-free (no ₪)', (tester) async {
      final l10n = await _l10n('en');
      await tester.pumpWidget(
        _harness(
          l10n,
          _ticket(
            meatTotals: const [KitchenMeat(quantity: 9, unit: 'patties')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('₪'), findsNothing);
    });
  });

  group('printed kitchen ticket', () {
    test(
      'the meat total prints near the top, above the items; money-free',
      () async {
        final l10n = await _l10n('en');
        final doc = buildKdsTicketDocument(
          l10n,
          _ticket(
            meatTotals: const [KitchenMeat(quantity: 9, unit: 'patties')],
          ),
        );
        final meatIdx = doc.lines.indexWhere(
          (l) =>
              l.kind == PrintLineKind.title &&
              l.left == l10n.kdsMeatTotalLabel('9', 'patties'),
        );
        expect(meatIdx, greaterThanOrEqualTo(0));
        final firstItemIdx = doc.lines.indexWhere(
          (l) => l.kind == PrintLineKind.item,
        );
        expect(meatIdx, lessThan(firstItemIdx));
        final html = documentToHtml(doc);
        expect(html.contains('₪'), isFalse);
        expect(html.toLowerCase().contains('minor'), isFalse);
      },
    );

    test('a meat total hides the generic prep block on the ticket', () async {
      final l10n = await _l10n('en');
      final doc = buildKdsTicketDocument(
        l10n,
        _ticket(
          meatTotals: const [KitchenMeat(quantity: 9, unit: 'patties')],
          prepSummary: const [KitchenPrepComponent(name: 'Bun', quantity: 5)],
        ),
      );
      expect(
        doc.lines.any((l) => l.left == l10n.kdsTicketPrepHeading),
        isFalse,
      );
    });

    test(
      'an Arabic meat total reaches the raster bitmap, money-free',
      () async {
        final l10n = await _l10n('ar');
        final doc = buildKdsTicketDocument(
          l10n,
          _ticket(
            item: 'برجر',
            meatTotals: const [KitchenMeat(quantity: 9, unit: 'قطع')],
          ),
        );
        final escpos = kitchenTicketToEscPosDocument(doc);
        final fake = pp.FakeReceiptRasterizer();
        final raster = await pp.maybeRasterizeForRtl(escpos, rasterizer: fake);

        expect(raster.lines.whereType<pp.PrintRasterImageLine>(), isNotEmpty);
        final lines = fake.requests.single.lines.join('\n');
        expect(lines.contains(l10n.kdsMeatTotalLabel('9', 'قطع')), isTrue);
        expect(lines.contains('₪'), isFalse);
      },
    );
  });
}
