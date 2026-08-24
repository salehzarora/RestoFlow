import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kiosk/src/data/kiosk_appearance.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_shell.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:restoflow_kiosk/src/widgets/kiosk_chrome.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// KIOSK-UI-113 — the primary + highlighted wordmark renders COMPLETELY in
/// every script, with renderer-owned separation:
/// - both segments always fully visible (scale-down, never ellipsis);
/// - two word segments get ONE natural space (AR / HE / EN alike);
/// - an attached-punctuation accent (EMBER + '.') keeps today's exact join;
/// - the stored model stays clean/trimmed — no space smuggling, no
///   punctuation workaround, no migration.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  Future<void> pumpShell(WidgetTester tester, {bool real = true}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container = ProviderContainer(
      overrides: [if (real) kioskRealModeProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            locale: Locale(ref.watch(kioskFlowProvider.select((s) => s.lang))),
            debugShowCheckedModeBanner: false,
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const KioskShell(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> saveBrand(
    WidgetTester tester, {
    required String primary,
    required String accent,
  }) async {
    container.read(kioskAppearanceScopeProvider.notifier).state = (
      deviceId: 'dev-1',
      fallbackName: 'first',
    );
    await container
        .read(kioskAppearanceProvider.notifier)
        .save(
          KioskAppearanceSettings.defaults(
            fallbackName: 'first',
          ).copyWith(brandTitlePrimary: primary, brandTitleAccent: accent),
        );
    await tester.pump(const Duration(milliseconds: 200));
  }

  Finder wordmark() => find.byKey(const Key('kiosk-attract-wordmark'));

  group('A. renderer-owned separation (join rule)', () {
    test('pure rule: word accents get ONE space; punctuation attaches; '
        'single pieces pass through', () {
      expect(kioskWordmarkText('برجر', 'الخرائط'), 'برجر الخرائط');
      expect(kioskWordmarkText('خرائط', 'البرجر'), 'خرائط البرجر');
      expect(kioskWordmarkText('בורגר', 'הבית'), 'בורגר הבית');
      expect(kioskWordmarkText('Maps', 'Burger'), 'Maps Burger');
      expect(kioskWordmarkText('EMBER', '.'), 'EMBER.');
      expect(kioskWordmarkText('برجر', ''), 'برجر');
      expect(kioskWordmarkText('', 'البرجر'), 'البرجر');
      expect(kioskWordmarkText('', ''), '');
    });

    testWidgets('AR: خرائط + البرجر renders "خرائط البرجر" on the attract '
        'hero — no punctuation workaround', (tester) async {
      await pumpShell(tester);
      await saveBrand(tester, primary: 'خرائط', accent: 'البرجر');
      expect(find.text('خرائط البرجر', findRichText: true), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('HE: בורגר + הבית renders "בורגר הבית"', (tester) async {
      await pumpShell(tester);
      await saveBrand(tester, primary: 'בורגר', accent: 'הבית');
      expect(find.text('בורגר הבית', findRichText: true), findsWidgets);
    });

    testWidgets('EN: Maps + Burger renders "Maps Burger"', (tester) async {
      await pumpShell(tester);
      await saveBrand(tester, primary: 'Maps', accent: 'Burger');
      expect(find.text('Maps Burger', findRichText: true), findsWidgets);
    });

    testWidgets('attached punctuation is preserved: demo EMBER + "." still '
        'renders exactly "EMBER."', (tester) async {
      await pumpShell(tester, real: false); // demo fixture identity
      expect(find.text('EMBER.', findRichText: true), findsWidgets);
      expect(find.text('EMBER .', findRichText: true), findsNothing);
    });

    testWidgets('the stored model stays CLEAN: no space is persisted into '
        'either segment', (tester) async {
      await pumpShell(tester);
      await saveBrand(tester, primary: 'خرائط', accent: 'البرجر');
      final a = container.read(kioskAppearanceProvider);
      expect(a.brandTitlePrimary, 'خرائط');
      expect(a.brandTitleAccent, 'البرجر');
    });
  });

  group('B. full visibility (scale-down, never ellipsis)', () {
    testWidgets('AR: برجر + الخرائط renders the COMPLETE name inside the '
        'stage — no ellipsis, no overflow', (tester) async {
      await pumpShell(tester);
      await saveBrand(tester, primary: 'برجر', accent: 'الخرائط');
      expect(find.text('برجر الخرائط', findRichText: true), findsWidgets);
      final mark = wordmark();
      expect(mark, findsOneWidget);
      // Fits the attract content width (1080 − 2×56 padding) after the
      // uniform scale-down; nothing is clipped or ellipsized.
      expect(tester.getSize(mark).width, lessThanOrEqualTo(968));
      final rich = tester.widget<Text>(
        find.descendant(of: mark, matching: find.byType(Text)).first,
      );
      expect(rich.overflow, isNot(TextOverflow.ellipsis));
      expect(tester.takeException(), isNull);
    });

    testWidgets('near-limit long brand (28+28) still renders COMPLETELY '
        'via scaling — the intentional overflow strategy', (tester) async {
      await pumpShell(tester);
      final primary = 'م' * 28;
      final accent = 'ب' * 28;
      await saveBrand(tester, primary: primary, accent: accent);
      expect(find.text('$primary $accent', findRichText: true), findsWidgets);
      expect(tester.getSize(wordmark()).width, lessThanOrEqualTo(968));
      expect(tester.takeException(), isNull);
    });

    testWidgets('semantic order is preserved under RTL: primary precedes '
        'accent in the rendered text', (tester) async {
      await pumpShell(tester);
      await saveBrand(tester, primary: 'خرائط', accent: 'البرجر');
      final rich = tester.widget<Text>(
        find.descendant(of: wordmark(), matching: find.byType(Text)).first,
      );
      final plain = rich.textSpan!.toPlainText();
      expect(plain.indexOf('خرائط'), lessThan(plain.indexOf('البرجر')));
    });
  });

  group('C. settings preview mirrors the attract contract', () {
    testWidgets('the preview joins with the same rule and renders the full '
        'name', (tester) async {
      await pumpShell(tester);
      await saveBrand(tester, primary: 'خرائط', accent: 'البرجر');
      container.read(kioskFlowProvider.notifier).enterSettingsAfterStaffAuth();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(container.read(kioskFlowProvider).screen, KioskScreen.settings);
      // Attract is gone; the ONLY joined render now is the settings preview.
      expect(find.text('خرائط البرجر', findRichText: true), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
