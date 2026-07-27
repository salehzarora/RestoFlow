import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// PRINT-LAYOUT-001B — the centralized, profile-aware typography tokens. This is
/// the single source both the raster renderer and the pagination estimate read,
/// so pinning its hierarchy pins the printed hierarchy AND the page planning.

void main() {
  const standard = PrintTypography.standard;
  const compact = PrintTypography.compact;

  group('PrintTypography — standard hierarchy', () {
    double m(PrintLineStyle s) => standard.sizeMultiplier(s);

    test(
      'is ranked so the restaurant-name hero is the single largest element',
      () {
        expect(
          m(PrintLineStyle.headingLarge),
          greaterThan(m(PrintLineStyle.total)),
        );
        expect(
          m(PrintLineStyle.headingLarge),
          greaterThan(m(PrintLineStyle.subheading)),
        );
      },
    );

    test('makes the final TOTAL the strongest money line — larger than an item '
        'name and any body row', () {
      expect(m(PrintLineStyle.total), greaterThan(m(PrintLineStyle.item)));
      expect(m(PrintLineStyle.total), greaterThan(m(PrintLineStyle.normal)));
    });

    test('places the secondary identifier and item name above plain body/'
        'modifier text', () {
      expect(
        m(PrintLineStyle.subheading),
        greaterThan(m(PrintLineStyle.normal)),
      );
      expect(
        m(PrintLineStyle.item),
        greaterThanOrEqualTo(m(PrintLineStyle.sub)),
      );
      expect(m(PrintLineStyle.item), greaterThan(m(PrintLineStyle.normal)));
    });

    test('keeps the separator rule and the inter-item spacer the smallest', () {
      expect(m(PrintLineStyle.separator), lessThan(m(PrintLineStyle.normal)));
      expect(m(PrintLineStyle.spacer), lessThan(m(PrintLineStyle.separator)));
      expect(m(PrintLineStyle.spacer), greaterThan(0));
    });
  });

  group('PrintTypography — compact (50x50) hierarchy', () {
    double c(PrintLineStyle s) => compact.sizeMultiplier(s);
    double s(PrintLineStyle x) => standard.sizeMultiplier(x);

    test('keeps the SAME ordering as the standard hierarchy', () {
      expect(
        c(PrintLineStyle.headingLarge),
        greaterThan(c(PrintLineStyle.subheading)),
      );
      expect(
        c(PrintLineStyle.subheading),
        greaterThan(c(PrintLineStyle.normal)),
      );
      expect(c(PrintLineStyle.total), greaterThan(c(PrintLineStyle.item)));
      expect(c(PrintLineStyle.separator), lessThan(c(PrintLineStyle.normal)));
    });

    test('uses gentler steps — every heading is smaller than on standard so it '
        'fits the small 384-dot label', () {
      expect(
        c(PrintLineStyle.headingLarge),
        lessThan(s(PrintLineStyle.headingLarge)),
      );
      expect(c(PrintLineStyle.total), lessThan(s(PrintLineStyle.total)));
      expect(
        c(PrintLineStyle.subheading),
        lessThan(s(PrintLineStyle.subheading)),
      );
      expect(c(PrintLineStyle.item), lessThan(s(PrintLineStyle.item)));
    });
  });

  group('PrintTypography — profile selection', () {
    test('forProfile picks compact ONLY for the small 50x50 label', () {
      expect(
        PrintTypography.forProfile(MediaProfile.label50x50).density,
        PrintTypographyDensity.compact,
      );
      expect(
        PrintTypography.forProfile(MediaProfile.label80x80).density,
        PrintTypographyDensity.standard,
      );
      expect(
        PrintTypography.forProfile(MediaProfile.continuous80).density,
        PrintTypographyDensity.standard,
      );
    });
  });

  group('PrintTypography — weight + alignment', () {
    test('weights collapse to bold / regular only (PILOT-PRINT-FIDELITY-001 — '
        'no synthetic axes)', () {
      for (final role in const [
        PrintLineStyle.headingLarge,
        PrintLineStyle.subheading,
        PrintLineStyle.item,
        PrintLineStyle.note,
        PrintLineStyle.total,
      ]) {
        expect(standard.weightFor(role), PrintFontWeight.bold, reason: '$role');
      }
      for (final role in const [
        PrintLineStyle.centered,
        PrintLineStyle.normal,
        PrintLineStyle.sub,
        PrintLineStyle.separator,
        PrintLineStyle.spacer,
      ]) {
        expect(
          standard.weightFor(role),
          PrintFontWeight.regular,
          reason: '$role',
        );
      }
    });

    test('brand + heading lines centre; item / total / body / modifier run '
        'from the start edge', () {
      for (final role in const [
        PrintLineStyle.headingLarge,
        PrintLineStyle.subheading,
        PrintLineStyle.centered,
      ]) {
        expect(
          standard.alignFor(role),
          PrintTextAlignRole.center,
          reason: '$role',
        );
      }
      for (final role in const [
        PrintLineStyle.item,
        PrintLineStyle.total,
        PrintLineStyle.normal,
        PrintLineStyle.sub,
        PrintLineStyle.note,
        PrintLineStyle.spacer,
      ]) {
        expect(
          standard.alignFor(role),
          PrintTextAlignRole.start,
          reason: '$role',
        );
      }
    });

    test('exposes the documented base metrics', () {
      expect(standard.baseFontSize, kBaseReceiptFontSize);
      expect(standard.lineHeight, kBaseReceiptLineHeight);
    });
  });

  group('PrintTypography — kitchen roles (PRINT-LAYOUT-001C, test C)', () {
    double m(PrintLineStyle s) => standard.sizeMultiplier(s);
    double c(PrintLineStyle s) => compact.sizeMultiplier(s);

    test(
      'the kitchen item + modifier + note are LARGER than the shared receipt '
      'item / sub / note baseline (standard + compact)',
      () {
        expect(
          m(PrintLineStyle.kitchenItem),
          greaterThan(m(PrintLineStyle.item)),
        );
        expect(
          m(PrintLineStyle.kitchenModifier),
          greaterThan(m(PrintLineStyle.sub)),
        );
        expect(
          m(PrintLineStyle.kitchenNote),
          greaterThan(m(PrintLineStyle.note)),
        );
        expect(
          c(PrintLineStyle.kitchenItem),
          greaterThan(c(PrintLineStyle.item)),
        );
        expect(
          c(PrintLineStyle.kitchenModifier),
          greaterThan(c(PrintLineStyle.sub)),
        );
      },
    );

    test('the item name stays STRONGER (larger) than the modifier, and both '
        'stay below the order-reference hero (standard + compact)', () {
      expect(
        m(PrintLineStyle.kitchenItem),
        greaterThan(m(PrintLineStyle.kitchenModifier)),
      );
      expect(
        m(PrintLineStyle.kitchenItem),
        lessThan(m(PrintLineStyle.headingLarge)),
      );
      expect(
        c(PrintLineStyle.kitchenItem),
        greaterThan(c(PrintLineStyle.kitchenModifier)),
      );
      expect(
        c(PrintLineStyle.kitchenItem),
        lessThan(c(PrintLineStyle.headingLarge)),
      );
    });

    test('kitchen item + note are bold; the modifier is regular; all run from '
        'the start edge', () {
      expect(
        standard.weightFor(PrintLineStyle.kitchenItem),
        PrintFontWeight.bold,
      );
      expect(
        standard.weightFor(PrintLineStyle.kitchenNote),
        PrintFontWeight.bold,
      );
      expect(
        standard.weightFor(PrintLineStyle.kitchenModifier),
        PrintFontWeight.regular,
      );
      for (final role in const [
        PrintLineStyle.kitchenItem,
        PrintLineStyle.kitchenModifier,
        PrintLineStyle.kitchenNote,
      ]) {
        expect(standard.alignFor(role), PrintTextAlignRole.start);
      }
    });

    test('REGRESSION (test E): the shared RECEIPT item / sub / total sizes are '
        'UNCHANGED by the kitchen enlargement', () {
      // The receipt hierarchy the customer-receipt tests pin is untouched.
      expect(m(PrintLineStyle.item), 1.25);
      expect(m(PrintLineStyle.sub), 1.0);
      expect(m(PrintLineStyle.total), 1.45);
      expect(
        m(PrintLineStyle.total),
        greaterThan(m(PrintLineStyle.item)),
        reason: 'the receipt total>item ranking still holds',
      );
    });
  });
}
