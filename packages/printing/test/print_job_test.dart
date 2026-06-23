import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// RF-58: the [PrintJobType] enum + its stable wire names. Adds `cashDrawer`
/// (`drawer_kick`) for RF-074 without disturbing the existing receipt/kitchen
/// values.
void main() {
  group('PrintJobType wire names', () {
    test('cashDrawer wire name is the stable "drawer_kick"', () {
      expect(PrintJobType.cashDrawer.wireName, 'drawer_kick');
      expect(PrintJobType.fromWire('drawer_kick'), PrintJobType.cashDrawer);
    });

    test('existing receipt + kitchen ticket wire names are unchanged', () {
      expect(PrintJobType.receipt.wireName, 'receipt');
      expect(PrintJobType.kitchenTicket.wireName, 'kitchen_ticket');
      expect(PrintJobType.fromWire('receipt'), PrintJobType.receipt);
      expect(
        PrintJobType.fromWire('kitchen_ticket'),
        PrintJobType.kitchenTicket,
      );
    });

    test('every value round-trips through its wire name', () {
      for (final t in PrintJobType.values) {
        expect(PrintJobType.fromWire(t.wireName), t);
      }
      // The full, stable wire set (guards against silent renames).
      expect(PrintJobType.values.map((t) => t.wireName).toSet(), {
        'receipt',
        'kitchen_ticket',
        'drawer_kick',
      });
    });

    test('an unknown wire string still throws (unchanged behavior)', () {
      expect(() => PrintJobType.fromWire('bogus'), throwsArgumentError);
    });
  });
}
