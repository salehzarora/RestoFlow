import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/print/kds_ticket_document.dart';
import 'package:restoflow_kds/src/print/print_document.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// TABLET-UX-001 (E), KDS side: the kitchen ticket document is money-free and
/// never bakes in a printer-status ("not connected") message — the honest print
/// result stays UI-only on the card's status line.

Future<AppLocalizations> _l10n(String locale) =>
    AppLocalizations.delegate.load(Locale(locale));

KdsTicketView _ticket() => KdsTicketView(
  kitchenTicketId: 'kt-1',
  stationId: 'grill',
  status: KitchenTicketStatus.acknowledged,
  orderId: 'o1',
  orderNumber: '#ECEC63',
  items: const [
    KdsItemView(
      name: 'Burger',
      quantity: 2,
      modifiers: ['Double'],
      note: 'rare',
    ),
  ],
  kitchenCounts: const [KitchenCount(quantity: 19, label: 'patties')],
);

String _docText(PrintDocument doc) =>
    doc.lines.map((l) => '${l.left ?? ''} ${l.right ?? ''}').join('\n');

void main() {
  test('the KDS ticket document is money-free and carries no printer-status '
      'error text (en + ar)', () async {
    for (final locale in ['en', 'ar', 'he']) {
      final l10n = await _l10n(locale);
      final text = _docText(buildKdsTicketDocument(l10n, _ticket()));

      // Money-free (SECURITY T-003).
      expect(text.contains('₪'), isFalse, reason: locale);
      expect(text.contains(r'$'), isFalse, reason: locale);

      // No printer-status / "not connected" messaging inside the printed ticket.
      expect(
        text.contains(l10n.posReceiptNoPrinterNote),
        isFalse,
        reason: locale,
      );
      expect(
        text.contains(l10n.printStatusNotConfigured),
        isFalse,
        reason: locale,
      );
      expect(
        text.contains(l10n.printStatusBridgeUnavailable),
        isFalse,
        reason: locale,
      );

      // The real kitchen content IS present (order code + kitchen count).
      expect(text.contains('#ECEC63'), isTrue, reason: locale);
      expect(text.contains('19'), isTrue, reason: locale);
    }
  });
}
