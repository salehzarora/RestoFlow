import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// RF-020 / DECISION D-014: pumps a localized app using the SHARED
/// `packages/l10n` wiring and asserts the resolved [Directionality] per locale
/// (ar/he -> RTL, en -> LTR) plus that [AppLocalizations] resolves per locale.
/// Direction is data-driven by `GlobalWidgetsLocalizations` — no manual hacks.
void main() {
  Future<({TextDirection direction, AppLocalizations l10n})> pumpFor(
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
            return Text(l10n.appName);
          },
        ),
      ),
    );
    await tester.pump();
    return (direction: direction, l10n: l10n);
  }

  testWidgets('en resolves LTR and AppLocalizations resolves', (tester) async {
    final r = await pumpFor(tester, const Locale('en'));
    expect(r.direction, TextDirection.ltr);
    expect(r.l10n.appName, 'RestoFlow');
  });

  testWidgets('ar resolves RTL and AppLocalizations resolves', (tester) async {
    final r = await pumpFor(tester, const Locale('ar'));
    expect(r.direction, TextDirection.rtl);
    expect(r.l10n.appName, 'ريستوفلو');
    expect(r.l10n.appName, isNot('RestoFlow'));
  });

  testWidgets('he resolves RTL and AppLocalizations resolves', (tester) async {
    final r = await pumpFor(tester, const Locale('he'));
    expect(r.direction, TextDirection.rtl);
    expect(r.l10n.appName, 'רסטופלו');
    expect(r.l10n.appName, isNot('RestoFlow'));
  });
}
