import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// KITCHEN-COUNT-001: the kitchen count summary labels are GENERIC (not meat-
/// specific) in ar/he/en. The l10n KEYS keep the internal *Meat* name for
/// backwards compatibility; only the user-facing VALUES are generalized.
void main() {
  Future<AppLocalizations> load(String locale) =>
      AppLocalizations.delegate.load(Locale(locale));

  test('English labels are a generic kitchen count', () async {
    final l = await load('en');
    expect(l.kdsMeatTotalLabel('9', 'patties'), 'Kitchen total: 9 patties');
    expect(l.menuKitchenMeatSection, 'Kitchen count summary');
    expect(l.menuKitchenMeatEnabledLabel, 'Count in kitchen total');
    expect(l.menuKitchenMeatQuantityLabel, 'Quantity');
    expect(l.menuKitchenMeatUnitLabel, 'Resource');
    // No user-facing "meat" wording survives.
    for (final s in [
      l.menuKitchenMeatSection,
      l.menuKitchenMeatEnabledLabel,
      l.menuKitchenMeatQuantityLabel,
      l.menuKitchenMeatUnitLabel,
      l.kdsMeatTotalLabel('9', 'x'),
    ]) {
      expect(s.toLowerCase().contains('meat'), isFalse, reason: s);
    }
  });

  test(
    'Arabic labels are generic (التجهيز), not meat-specific (اللحم)',
    () async {
      final l = await load('ar');
      // The owner writes any unit — a meat pieces / fish pieces example.
      expect(l.kdsMeatTotalLabel('9', 'قطع لحم'), 'إجمالي التجهيز: 9 قطع لحم');
      expect(
        l.kdsMeatTotalLabel('6', 'حبات سمك'),
        'إجمالي التجهيز: 6 حبات سمك',
      );
      expect(l.menuKitchenMeatSection, 'ملخص التجهيز للمطبخ');
      expect(l.menuKitchenMeatEnabledLabel, 'يُحسب في إجمالي التجهيز');
      expect(l.menuKitchenMeatQuantityLabel, 'الكمية');
      expect(l.menuKitchenMeatUnitLabel, 'المورد');
      // The LABELS (no data interpolated) carry no meat word.
      for (final s in [
        l.menuKitchenMeatSection,
        l.menuKitchenMeatEnabledLabel,
        l.menuKitchenMeatQuantityLabel,
        l.menuKitchenMeatUnitLabel,
        l.kdsMeatTotalLabel('9', 'x'),
      ]) {
        expect(s.contains('اللحم'), isFalse, reason: s);
      }
    },
  );

  test('Hebrew labels use general preparation wording', () async {
    final l = await load('he');
    expect(l.kdsMeatTotalLabel('9', 'x'), 'סיכום הכנה: 9 x');
    expect(l.menuKitchenMeatSection, 'סיכום הכנה למטבח');
    expect(l.menuKitchenMeatEnabledLabel, 'נכלל בסיכום ההכנה');
    expect(l.menuKitchenMeatQuantityLabel, 'כמות');
    expect(l.menuKitchenMeatUnitLabel, 'משאב');
    // No meat word (בשר) in the labels.
    for (final s in [
      l.menuKitchenMeatSection,
      l.menuKitchenMeatEnabledLabel,
      l.menuKitchenMeatQuantityLabel,
      l.menuKitchenMeatUnitLabel,
      l.kdsMeatTotalLabel('9', 'x'),
    ]) {
      expect(s.contains('בשר'), isFalse, reason: s);
    }
  });
}
