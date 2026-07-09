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

/// KDS-ALERTS-AND-KITCHEN-COUNTS-002 (B): the unified whole-order kitchen count
/// summary — MULTIPLE resources at the top of the card + printed ticket, generic
/// "إجمالي التجهيز: {count} {label}" copy, item details below, money-free,
/// Arabic raster preserved.
Future<AppLocalizations> _l10n(String locale) =>
    AppLocalizations.delegate.load(Locale(locale));

KdsTicketView _ticket({
  List<KitchenCount> kitchenCounts = const <KitchenCount>[],
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
  kitchenCounts: kitchenCounts,
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
  group('KDS card kitchen counts', () {
    testWidgets('shows MULTIPLE resource totals at the top; items stay below', (
      tester,
    ) async {
      final l10n = await _l10n('en');
      await tester.pumpWidget(
        _harness(
          l10n,
          _ticket(
            kitchenCounts: const [
              KitchenCount(quantity: 19, label: 'patties'),
              KitchenCount(quantity: 7, label: 'buns'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('kds-kitchen-counts')), findsOneWidget);
      expect(
        find.text(l10n.kdsMeatTotalLabel('19', 'patties')),
        findsOneWidget,
      );
      expect(find.text(l10n.kdsMeatTotalLabel('7', 'buns')), findsOneWidget);
      // Normal item + modifier still rendered underneath.
      expect(find.textContaining('Burger'), findsWidgets);
      expect(find.text('+ Double'), findsOneWidget);
    });

    testWidgets('hides the summary when there is no configured count', (
      tester,
    ) async {
      final l10n = await _l10n('en');
      await tester.pumpWidget(_harness(l10n, _ticket()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kds-kitchen-counts')), findsNothing);
    });

    testWidgets('the kitchen count summary is money-free (no ₪)', (
      tester,
    ) async {
      final l10n = await _l10n('en');
      await tester.pumpWidget(
        _harness(
          l10n,
          _ticket(
            kitchenCounts: const [KitchenCount(quantity: 19, label: 'patties')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('₪'), findsNothing);
    });

    testWidgets('uses the generic إجمالي التجهيز copy with any resource', (
      tester,
    ) async {
      final l10n = await _l10n('ar');
      await tester.pumpWidget(
        _harness(
          l10n,
          _ticket(
            item: 'برجر',
            kitchenCounts: const [KitchenCount(quantity: 9, label: 'قطع لحم')],
          ),
          locale: 'ar',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('إجمالي التجهيز: 9 قطع لحم'), findsOneWidget);
      expect(find.textContaining('إجمالي اللحم'), findsNothing);
    });
  });

  group('printed kitchen ticket kitchen counts', () {
    test(
      'the counts print near the top, above the items; money-free',
      () async {
        final l10n = await _l10n('en');
        final doc = buildKdsTicketDocument(
          l10n,
          _ticket(
            kitchenCounts: const [
              KitchenCount(quantity: 19, label: 'patties'),
              KitchenCount(quantity: 7, label: 'buns'),
            ],
          ),
        );
        final pattiesIdx = doc.lines.indexWhere(
          (l) =>
              l.kind == PrintLineKind.title &&
              l.left == l10n.kdsMeatTotalLabel('19', 'patties'),
        );
        final bunsIdx = doc.lines.indexWhere(
          (l) =>
              l.kind == PrintLineKind.title &&
              l.left == l10n.kdsMeatTotalLabel('7', 'buns'),
        );
        expect(pattiesIdx, greaterThanOrEqualTo(0));
        expect(bunsIdx, greaterThanOrEqualTo(0));
        final firstItemIdx = doc.lines.indexWhere(
          (l) => l.kind == PrintLineKind.item,
        );
        expect(pattiesIdx, lessThan(firstItemIdx));
        expect(bunsIdx, lessThan(firstItemIdx));
        final html = documentToHtml(doc);
        expect(html.contains('₪'), isFalse);
        expect(html.toLowerCase().contains('minor'), isFalse);
      },
    );

    test('an Arabic count reaches the raster bitmap, money-free', () async {
      final l10n = await _l10n('ar');
      final doc = buildKdsTicketDocument(
        l10n,
        _ticket(
          item: 'برجر',
          kitchenCounts: const [KitchenCount(quantity: 9, label: 'قطع لحم')],
        ),
      );
      final escpos = kitchenTicketToEscPosDocument(doc);
      final fake = pp.FakeReceiptRasterizer();
      final raster = await pp.maybeRasterizeForRtl(escpos, rasterizer: fake);

      expect(raster.lines.whereType<pp.PrintRasterImageLine>(), isNotEmpty);
      final lines = fake.requests.single.lines.join('\n');
      expect(lines.contains(l10n.kdsMeatTotalLabel('9', 'قطع لحم')), isTrue);
      expect(lines.contains('₪'), isFalse);
    });
  });
}
