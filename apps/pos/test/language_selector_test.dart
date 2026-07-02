import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/main.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/locale_controller.dart';
import 'package:restoflow_pos/src/widgets/language_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppLocalizations> _load(String code) =>
    AppLocalizations.delegate.load(Locale(code));

/// Pumps the FULL [PosApp] (in demo mode) so the MaterialApp.locale reacts to
/// the language selector. A wide surface gives the menu+cart layout room.
Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const ProviderScope(child: PosApp(demoMode: true)));
  await tester.pumpAndSettle();
}

TextDirection _dir(WidgetTester tester) =>
    Directionality.of(tester.element(find.byType(PosMenuScreen)));

Future<void> _select(WidgetTester tester, String endonym) async {
  await tester.tap(find.byKey(const Key('language-selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(endonym).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the POS app bar shows a language selector (LTR by default)', (
    tester,
  ) async {
    final en = await _load('en');
    await _pump(tester);

    expect(find.byType(LanguageSelector), findsOneWidget);
    expect(find.byKey(const Key('language-selector')), findsOneWidget);
    expect(_dir(tester), TextDirection.ltr);

    // The menu offers all three languages by endonym.
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
    expect(find.text(ar.posMenuHeading), findsOneWidget); // app re-localized
  });

  testWidgets('selecting Hebrew switches the whole app to RTL', (tester) async {
    final he = await _load('he');
    await _pump(tester);

    await _select(tester, he.languageHebrew);

    expect(_dir(tester), TextDirection.rtl);
    expect(find.text(he.posMenuHeading), findsOneWidget);
  });

  testWidgets('switching back to English restores LTR', (tester) async {
    final en = await _load('en');
    await _pump(tester);

    await _select(tester, en.languageArabic); // go RTL first
    expect(_dir(tester), TextDirection.rtl);

    await _select(tester, en.languageEnglish);
    expect(_dir(tester), TextDirection.ltr);
    expect(find.text(en.posMenuHeading), findsOneWidget);
  });

  // Sprint (I): Arabic-by-default + per-device persistence.
  group('Arabic default + persistence', () {
    testWidgets('the production first-launch locale (main: persisted ?? ar) '
        'renders the whole app in Arabic, RTL', (tester) async {
      final ar = await _load('ar');
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // What main() passes on a first launch with nothing persisted.
            initialLocaleProvider.overrideWithValue(const Locale('ar')),
          ],
          child: const PosApp(demoMode: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(_dir(tester), TextDirection.rtl);
      expect(find.text(ar.posMenuHeading), findsOneWidget);
    });

    test(
      'readPersistedLocale restores a stored choice and rejects junk',
      () async {
        SharedPreferences.setMockInitialValues({kLocalePrefsKey: 'he'});
        expect(await readPersistedLocale(), const Locale('he'));
        SharedPreferences.setMockInitialValues({kLocalePrefsKey: 'xx'});
        expect(await readPersistedLocale(), isNull);
        SharedPreferences.setMockInitialValues({});
        expect(await readPersistedLocale(), isNull);
      },
    );

    testWidgets('selecting a language PERSISTS it for the next launch', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final en = await _load('en');
      await _pump(tester);
      await _select(tester, en.languageHebrew);
      // The controller wrote the choice; the next launch's
      // readPersistedLocale() restores it.
      await tester.pumpAndSettle();
      expect(await readPersistedLocale(), const Locale('he'));
    });
  });
}
