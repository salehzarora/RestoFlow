import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/print/kds_print_bridge.dart'
    show kitchenTicketToEscPosDocument;
import 'package:restoflow_kds/src/print/kds_ticket_document.dart';
import 'package:restoflow_kds/src/print/print_document.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// PRINT-LAYOUT-001: the kitchen-ticket layout — big order number, grouped
/// centered order type / table / customer, bold items with a prominent quantity,
/// modifiers underneath, and notes flagged with a "»" marker. NO money anywhere
/// (T-003); the Arabic raster path still carries the content into the bitmap.

Future<AppLocalizations> _l10n(String locale) =>
    AppLocalizations.delegate.load(Locale(locale));

KdsTicketView _ticket({
  String? customerName,
  String? note,
  String? item,
  List<KitchenCount> kitchenCounts = const <KitchenCount>[],
}) => KdsTicketView(
  kitchenTicketId: 'o1:grill',
  stationId: 'grill',
  status: KitchenTicketStatus.acknowledged,
  orderId: 'o1',
  orderNumber: '#ABC123',
  orderType: 'dine_in',
  tableLabel: 'T3',
  customerName: customerName,
  items: [
    KdsItemView(
      name: item ?? 'Burger',
      quantity: 2,
      modifiers: const ['extra cheese'],
      note: note,
    ),
  ],
  kitchenCounts: kitchenCounts,
);

void main() {
  group('kitchen ticket layout', () {
    test('the order number is a big title heading', () async {
      final l10n = await _l10n('en');
      final doc = buildKdsTicketDocument(l10n, _ticket());
      expect(
        doc.lines.first.kind == PrintLineKind.title &&
            doc.lines.first.left == '#ABC123',
        isTrue,
      );
    });

    test('order type / table / customer are grouped centered lines', () async {
      final l10n = await _l10n('en');
      final doc = buildKdsTicketDocument(l10n, _ticket(customerName: 'Dana'));
      final centered = doc.lines
          .where((l) => l.kind == PrintLineKind.center)
          .map((l) => l.left)
          .toList();
      expect(centered, contains(l10n.posOrderTypeDineIn));
      expect(centered, contains('${l10n.posTableLabel} T3'));
      expect(centered, contains('${l10n.customerNameKitchenLabel}: Dana'));
    });

    test('the item is emphasised with a prominent quantity', () async {
      final l10n = await _l10n('en');
      final doc = buildKdsTicketDocument(l10n, _ticket());
      final item = doc.lines.firstWhere((l) => l.kind == PrintLineKind.item);
      expect(item.left, 'Burger');
      expect(item.right, '2×');
      expect(item.emphasised, isTrue);
    });

    test(
      'a note is flagged with a "»" marker so a chef never misses it',
      () async {
        final l10n = await _l10n('en');
        final doc = buildKdsTicketDocument(l10n, _ticket(note: 'no onion'));
        expect(
          doc.lines.any(
            (l) =>
                l.kind == PrintLineKind.sub &&
                (l.left ?? '').startsWith('» ') &&
                (l.left ?? '').contains('no onion'),
          ),
          isTrue,
        );
      },
    );

    test('the ticket is MONEY-FREE (T-003)', () async {
      final l10n = await _l10n('en');
      final doc = buildKdsTicketDocument(l10n, _ticket(customerName: 'Dana'));
      final html = documentToHtml(doc);
      expect(html.contains('₪'), isFalse);
      expect(html.toLowerCase().contains('minor'), isFalse);
    });
  });

  group('raster Arabic kitchen ticket', () {
    test('carries the Arabic content into the bitmap with NO money', () async {
      final l10n = await _l10n('ar');
      final doc = buildKdsTicketDocument(
        l10n,
        _ticket(customerName: 'محمد', item: 'برجر', note: 'بدون بصل'),
      );
      final escpos = kitchenTicketToEscPosDocument(doc);
      final fake = pp.FakeReceiptRasterizer();
      final raster = await pp.maybeRasterizeForRtl(escpos, rasterizer: fake);

      expect(raster.lines.whereType<pp.PrintRasterImageLine>(), isNotEmpty);
      final lines = fake.requests.single.lines.join('\n');
      expect(lines.contains('محمد'), isTrue); // customer
      expect(lines.contains('برجر'), isTrue); // item
      expect(lines.contains('بدون بصل'), isTrue); // note
      // Money-free: no shekel sign anywhere in the kitchen raster (T-003).
      expect(lines.contains('₪'), isFalse);
    });
  });
}
