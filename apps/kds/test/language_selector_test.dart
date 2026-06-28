import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kds/main.dart';
import 'package:restoflow_kds/src/kitchen_orders_home.dart';
import 'package:restoflow_kds/src/widgets/language_selector.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

Future<AppLocalizations> _load(String code) =>
    AppLocalizations.delegate.load(Locale(code));

/// Pumps the FULL [KdsApp] (demo board) so MaterialApp.locale reacts to the
/// language selector. [KdsApp] supplies its own ProviderScope.
Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const KdsApp(demoMode: true));
  await tester.pumpAndSettle();
}

TextDirection _dir(WidgetTester tester) =>
    Directionality.of(tester.element(find.byType(KitchenOrdersHome)));

Future<void> _select(WidgetTester tester, String endonym) async {
  await tester.tap(find.byKey(const Key('language-selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(endonym).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the KDS app bar shows a language selector (LTR by default)', (
    tester,
  ) async {
    final en = await _load('en');
    await _pump(tester);

    expect(find.byType(LanguageSelector), findsOneWidget);
    expect(find.byKey(const Key('language-selector')), findsOneWidget);
    expect(_dir(tester), TextDirection.ltr);

    await tester.tap(find.byKey(const Key('language-selector')));
    await tester.pumpAndSettle();
    expect(find.text(en.languageEnglish), findsOneWidget);
    expect(find.text(en.languageArabic), findsOneWidget);
    expect(find.text(en.languageHebrew), findsOneWidget);
  });

  testWidgets('selecting Arabic switches the whole app to RTL', (tester) async {
    final ar = await _load('ar');
    await _pump(tester);

    await _select(tester, ar.languageArabic);

    expect(_dir(tester), TextDirection.rtl);
    expect(find.text(ar.kdsAppTitle), findsOneWidget); // app re-localized
  });

  testWidgets('selecting Hebrew switches the whole app to RTL', (tester) async {
    final he = await _load('he');
    await _pump(tester);

    await _select(tester, he.languageHebrew);

    expect(_dir(tester), TextDirection.rtl);
    expect(find.text(he.kdsAppTitle), findsOneWidget);
  });

  testWidgets('switching back to English restores LTR', (tester) async {
    final en = await _load('en');
    await _pump(tester);

    await _select(tester, en.languageArabic); // go RTL first
    expect(_dir(tester), TextDirection.rtl);

    await _select(tester, en.languageEnglish);
    expect(_dir(tester), TextDirection.ltr);
    expect(find.text(en.kdsAppTitle), findsOneWidget);
  });
}
