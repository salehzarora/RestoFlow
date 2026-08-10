/// GLOBAL-BRAND-POS-V4 — the cashier surface on the global brand, measured.
///
/// WHAT V4 CHANGES, AND WHAT IT DELIBERATELY DOES NOT.
///
/// The POS carried a complete, contrast-verified WARM palette (DESIGN-004
/// Warm/Bento, then POS-VISUAL-REDESIGN-PHASE-1-007/008): cream surfaces, a
/// brand-green selection family, and a deep-green cart header with its own
/// on-dark ramp. It is good work — it is simply a different identity from the
/// navy/white/orange every other RestoFlow surface now speaks. V4 RE-VALUES
/// those constants in place rather than rewriting the widgets that use them,
/// which is why forty files change appearance and none change structure.
///
/// Three things are explicitly NOT migrated, and each has a test below:
///
///  * SEMANTIC sync states (pending amber, failed red, offline neutral). An
///    operational warning painted in brand navy is a warning nobody sees.
///  * SYNCED green. It reads "success", so it stays in the success family —
///    which means it had to be DECOUPLED from the on-dark accent it used to
///    alias, because that accent is now navy-cool.
///  * The categorical category palette, which is identity-per-category and
///    would become meaningless if collapsed to one brand hue.
///
/// Overflow is captured through [FlutterError.onError]; `takeException()` does
/// not see paint-time RenderFlex overflow in this harness, so a matrix built on
/// it is green whatever the layout does.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/pos_palette.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';

// ── fixtures ───────────────────────────────────────────────────────────────

/// A menu whose names are LONG in every supported script. Short fixture names
/// are why a starving cart row survives a suite: the row only fails when the
/// text actually wants more than the column can give.
DemoMenuItem _item({
  required String id,
  required String name,
  String categoryId = 'mains',
}) => DemoMenuItem(
  id: id,
  name: name,
  priceMinor: 12450,
  categoryId: categoryId,
  categoryName: 'Mains',
  description: 'Slow-roasted lamb shoulder with tahini, sumac onion and herbs.',
  availability: 'available',
);

const _longEn = 'Slow-roasted lamb shoulder shawarma with tahini and pickles';
const _longAr =
    'شاورما لحم الضأن المشوي ببطء مع الطحينة والبصل السماق والمخللات';
const _longHe = 'שווארמה מכתף טלה צלויה לאט עם טחינה ובצל סומק וחמוצים';

PosMenuData _menu() => PosMenuData(
  categories: const [
    DemoCategory(
      id: 'mains',
      name: 'Mains',
      icon: Icons.lunch_dining,
      color: Color(0xFFC2410C),
    ),
    DemoCategory(
      id: 'sides',
      name: 'Sides and sharing plates',
      icon: Icons.local_pizza,
      color: Color(0xFF1B7A52),
    ),
  ],
  items: [
    _item(id: 'i-en', name: _longEn),
    _item(id: 'i-ar', name: _longAr),
    _item(id: 'i-he', name: _longHe),
    for (var i = 0; i < 9; i++)
      _item(
        id: 'i-$i',
        name: 'Product $i',
        categoryId: i.isEven ? 'mains' : 'sides',
      ),
  ],
  modifierGroups: const [],
  currencyCode: 'ILS',
);

// ── harness ────────────────────────────────────────────────────────────────

/// Runs [body] and returns every RenderFlex overflow the renderer reported.
///
/// Restored BEFORE the caller's expectation: the binding asserts it owns
/// `FlutterError.onError` by then, and leaving the override installed turns
/// every later failure in the file into an opaque "did not complete".
Future<List<String>> _overflowsDuring(Future<void> Function() body) async {
  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed')) {
      overflows.add(text.split('\n').first.trim());
    } else {
      previous?.call(details);
    }
  };
  await body();
  FlutterError.onError = previous;
  return overflows;
}

Future<List<String>> _pumpPos(
  WidgetTester tester, {
  required Size size,
  Locale locale = const Locale('en'),
  double scale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  return _overflowsDuring(() async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [posMenuProvider.overrideWith((ref) async => _menu())],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: scale,
            maxScaleFactor: scale,
            child: child!,
          ),
          home: const PosMenuScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  });
}

/// The POS's real layout targets. Below 820 the app is a phone (bottom bar +
/// slide-up cart); at and above it there are two panes.
const _widths = [1440.0, 1280.0, 1024.0, 834.0, 700.0, 540.0, 430.0, 390.0];
const _locales = [Locale('en'), Locale('ar'), Locale('he')];

/// The relative luminance contrast between two opaque colours.
double _contrast(Color a, Color b) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : _pow((c + 0.055) / 1.055, 2.4);
  double lum(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final la = lum(a);
  final lb = lum(b);
  return (la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05));
}

double _pow(double x, double e) {
  var result = 1.0;
  // 2.4 == 12/5; integer-exponent loop + a fifth root, so the helper needs no
  // dart:math import and stays deterministic.
  final fifth = _root5(x);
  for (var i = 0; i < 12; i++) {
    result *= fifth;
  }
  return result;
}

double _root5(double x) {
  if (x <= 0) return 0;
  var guess = x;
  for (var i = 0; i < 60; i++) {
    guess =
        guess -
        (guess * guess * guess * guess * guess - x) /
            (5 * guess * guess * guess * guess);
  }
  return guess;
}

void main() {
  // =========================================================================
  // A. RESPONSIVE — the cashier screen at every real layout target
  // =========================================================================
  group('A. the POS holds across the width matrix', () {
    for (final width in _widths) {
      testWidgets('${width.toInt()}px', (tester) async {
        final overflows = await _pumpPos(
          tester,
          size: Size(width, width > 900 ? 900.0 : 1400.0),
        );
        expect(
          overflows,
          isEmpty,
          reason: 'no POS surface may clip at ${width.toInt()}px',
        );
      });
    }
  });

  // =========================================================================
  // B. DIRECTION — ar / he RTL and en LTR with LONG localized names
  // =========================================================================
  group('B. long names in every supported script', () {
    for (final locale in _locales) {
      for (final width in [1280.0, 834.0, 430.0, 390.0]) {
        testWidgets('${width.toInt()}px / ${locale.languageCode}', (
          tester,
        ) async {
          final overflows = await _pumpPos(
            tester,
            size: Size(width, width > 900 ? 900.0 : 1600.0),
            locale: locale,
          );
          expect(overflows, isEmpty);
        });
      }
    }
  });

  // =========================================================================
  // C. TEXT SCALE — representative 2x
  // =========================================================================
  group('C. 2x text scale', () {
    for (final locale in _locales) {
      for (final width in [1280.0, 430.0]) {
        testWidgets('${width.toInt()}px / ${locale.languageCode} / 2x', (
          tester,
        ) async {
          final overflows = await _pumpPos(
            tester,
            size: Size(width, width > 900 ? 1800.0 : 3600.0),
            locale: locale,
            scale: 2.0,
          );
          expect(overflows, isEmpty);
        });
      }
    }
  });

  // =========================================================================
  // D. PALETTE — the cashier surface speaks navy/white/orange
  // =========================================================================
  group('D. the POS palette is the global brand', () {
    const brand = RestoflowBrandPalette.light;

    test('structural surfaces are COOL, not warm cream', () {
      // A warm surface has more red than blue; a cool one does not. Asserted as
      // a RELATION rather than a hex so a future palette revision does not have
      // to edit this test to stay true.
      for (final entry in <(String, Color)>[
        ('inner surface', kPosInnerSurface),
        ('chip background', kPosChipBg),
        ('disabled background', kPosDisabledBg),
        ('input border', kPosInputBorder),
        ('count badge', kPosCountBadgeBg),
        ('setup edge', kPosSetupEdge),
        ('stepper track', kPosStepperTrack),
        ('stepper track edge', kPosStepperTrackEdge),
      ]) {
        expect(
          entry.$2.b,
          greaterThanOrEqualTo(entry.$2.r),
          reason: '${entry.$1} must not be a warm cream any more',
        );
      }
    });

    test('the selection family is NAVY, not brand green', () {
      // The selected tint is a navy wash: blue-dominant, and clearly not the
      // green it used to be.
      expect(kPosSelectedTint.b, greaterThan(kPosSelectedTint.g));
      expect(kPosSelectedTint.b, greaterThan(kPosSelectedTint.r));
      // The primary CTA glow is drawn from the brand navy rather than a
      // one-off green.
      expect(
        kPosPrimaryGlow.single.color.b,
        greaterThan(kPosPrimaryGlow.single.color.g),
      );
      expect(
        kPosChipSelectedShadow.single.color.b,
        greaterThan(kPosChipSelectedShadow.single.color.g),
      );
    });

    test('the cart operational plane is a deep NAVY block', () {
      expect(kPosCartHeaderInk.b, greaterThan(kPosCartHeaderInk.g));
      expect(kPosCartHeaderInk.b, greaterThan(kPosCartHeaderInk.r));
      // Still unmistakably the dark operational plane, not a mid tone.
      expect(kPosCartHeaderInk.computeLuminance(), lessThan(0.1));
    });

    test('the accent is the SHARED brand orange, not a POS-local one', () {
      expect(kPosTerracotta, brand.accentOrange);
      expect(kPosTerracottaContainer, brand.accentOrangeContainer);
    });

    test('elevation ink is the shared navy-black, not a green-black', () {
      for (final shadow in [...kPosCardShadow, ...kPosDeckShadow]) {
        expect(
          shadow.color.b,
          greaterThanOrEqualTo(shadow.color.g),
          reason: 'shadow ink must be the brand navy-black',
        );
      }
    });
  });

  // =========================================================================
  // E. SEMANTICS ARE FROZEN — the part a palette pass must not touch
  // =========================================================================
  group('E. operational semantics survive the palette migration', () {
    test('sync PENDING stays amber and FAILED stays red', () {
      // Warm-dominant, i.e. still an amber/red warning rather than a brand hue.
      expect(kPosSyncPendingFg.r, greaterThan(kPosSyncPendingFg.b));
      expect(kPosSyncPendingFg.g, greaterThan(kPosSyncPendingFg.b));
      expect(kPosSyncFailedFg.r, greaterThan(kPosSyncFailedFg.g));
      expect(kPosSyncFailedFg.r, greaterThan(kPosSyncFailedFg.b));
    });

    test(
      'sync SYNCED stays a success green, decoupled from the brand accent',
      () {
        expect(
          kPosSyncSyncedFg.g,
          greaterThan(kPosSyncSyncedFg.b),
          reason: '"synced" reads as success; it must not become navy',
        );
        expect(
          kPosSyncSyncedFg,
          isNot(kPosOnDarkAccent),
          reason:
              'the success state must no longer ALIAS the brand accent, or '
              'a brand revision silently repaints an operational state',
        );
      },
    );

    test('every on-dark foreground still clears 4.5:1 on the NEW header', () {
      // The 008 contrast contract, re-verified against the migrated surface.
      // This is the reason the migration is safe to make by re-valuation: the
      // guarantee is a relationship, and the relationship is tested.
      for (final entry in <(String, Color)>[
        ('primary', kPosOnDarkPrimary),
        ('muted', kPosOnDarkMuted),
        ('accent', kPosOnDarkAccent),
        ('ghost', Color.alphaBlend(kPosOnDarkGhost, kPosCartHeaderInk)),
        ('sync pending', kPosSyncPendingFg),
        ('sync failed', kPosSyncFailedFg),
        ('sync synced', kPosSyncSyncedFg),
        (
          'sync offline',
          Color.alphaBlend(kPosSyncOfflineFg, kPosCartHeaderInk),
        ),
      ]) {
        expect(
          _contrast(entry.$2, kPosCartHeaderInk),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.$1} must stay legible on the operational plane',
        );
      }
    });

    test('the category palette stays CATEGORICAL', () {
      // Per-category identity. Collapsing it to one brand hue would make the
      // categories indistinguishable, so it is deliberately not migrated.
      final hues = kPosCategoryPalette.map((e) => e.$2).toSet();
      expect(
        hues.length,
        greaterThan(3),
        reason: 'categories must stay visually distinguishable',
      );
    });
  });

  // =========================================================================
  // F. NO BEHAVIOUR REGRESSION — the palette pass is presentation only
  // =========================================================================
  group('F. layout contracts are untouched', () {
    test('layout modes, column counts and cart widths are unchanged', () {
      expect(posLayoutModeFor(width: 1440, height: 900), PosLayoutMode.desktop);
      expect(posLayoutModeFor(width: 1280, height: 800), PosLayoutMode.tablet);
      expect(
        posLayoutModeFor(width: 1024, height: 768),
        PosLayoutMode.smallTablet,
      );
      expect(
        posLayoutModeFor(width: 1024, height: 600),
        PosLayoutMode.compactLandscape,
      );
      expect(posLayoutModeFor(width: 390, height: 844), PosLayoutMode.phone);

      expect(posMenuColumnsFor(PosLayoutMode.desktop), 5);
      expect(posMenuColumnsFor(PosLayoutMode.tablet), 4);
      expect(posMenuColumnsFor(PosLayoutMode.phone), 2);

      expect(posCartWidthFor(PosLayoutMode.desktop), 400);
      expect(posCartWidthFor(PosLayoutMode.phone), 0);
    });

    test('money formatting helpers are untouched', () {
      // Integer minor units, and a split that reassembles EXACTLY — a palette
      // pass must not have gone near the money path.
      final (lead, core, trail) = posSplitFormattedMoney('₪124.50');
      expect(lead + core + trail, '₪124.50');
      expect(core, '124.50');
    });
  });
}
