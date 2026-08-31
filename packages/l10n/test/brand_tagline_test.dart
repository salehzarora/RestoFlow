import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// VEYRO-REBRAND — the brand tagline under the VEYRO mark (login/onboarding/
/// pairing) is the NEUTRAL master-brand positioning, not restaurant-specific:
/// the platform is POS & operations, broader than restaurants even while the
/// current workflows remain restaurant-specific.
Future<AppLocalizations> _l10n(WidgetTester tester, String locale) async {
  late AppLocalizations l10n;
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Builder(
        builder: (context) {
          l10n = AppLocalizations.of(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pump();
  return l10n;
}

void main() {
  testWidgets('authBrandTagline is the neutral VEYRO positioning per locale', (
    tester,
  ) async {
    expect((await _l10n(tester, 'en')).authBrandTagline, 'POS & Operations');
    expect(
      (await _l10n(tester, 'ar')).authBrandTagline,
      'نقاط البيع والعمليات',
    );
    expect((await _l10n(tester, 'he')).authBrandTagline, 'קופות ותפעול');
  });

  testWidgets('the tagline no longer positions VEYRO as restaurant-only', (
    tester,
  ) async {
    for (final loc in const ['en', 'ar', 'he']) {
      final t = (await _l10n(tester, loc)).authBrandTagline;
      expect(t.toLowerCase(), isNot(contains('restaurant')));
      expect(t, isNot(contains('مطاعم')));
      expect(t, isNot(contains('מסעדות')));
    }
  });
}
