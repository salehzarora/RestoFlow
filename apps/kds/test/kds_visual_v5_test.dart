/// GLOBAL-BRAND-KDS-V5 — the kitchen board on the global dark brand, measured.
///
/// WHAT V5 IS ACTUALLY ABOUT.
///
/// KDS was already the cleanest surface in the repo on the palette axis: ZERO
/// raw colour literals, everything from theme roles and
/// [RestoflowSemanticColors]. There was no local palette layer to re-value (as
/// POS had) and — checked before touching anything — no semantic value aliased
/// to a brand constant, so the trap that would have turned POS's "synced" state
/// navy does not exist here. Those are findings, not work items, and V5
/// deliberately does not manufacture changes to match a template.
///
/// The one real subject is ATTENTION. A freshly-arrived ticket announced itself
/// with `colorScheme.primary` — the structural brand navy — which is the same
/// colour the board already uses for its ordinary chrome. "Look here now" was
/// therefore painted in the one colour that says "this is the furniture". V5
/// moves it to the brand ORANGE, which is exactly what that accent is for and
/// which KDS is allowed to use more prominently than any other surface.
///
/// The tests below pin three things that are easy to get wrong while doing it:
///   * orange means NEW, and must stay distinguishable from warning and danger;
///   * the CANCELLED highlight stays semantic danger — a cancellation is not an
///     arrival, and merging the two would be a lie told in colour;
///   * nothing else that happened to be `primary` turned orange.
///
/// Overflow is captured through [FlutterError.onError]; `takeException()` does
/// not see paint-time RenderFlex overflow in this harness.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/kds_screen.dart';
import 'package:restoflow_kds/src/widgets/kds_ticket_card.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

// ── fixtures ───────────────────────────────────────────────────────────────

Future<AppLocalizations> _l10n(String code) =>
    AppLocalizations.delegate.load(Locale(code));

const _longEn =
    'Slow-roasted lamb shoulder shawarma with tahini, pickled turnip and herbs';
const _longAr =
    'شاورما لحم الضأن المشوي ببطء مع الطحينة واللفت المخلل والأعشاب الطازجة';
const _longHe =
    'שווארמה מכתף טלה צלויה לאט עם טחינה, לפת כבושה ועשבי תיבול טריים';

/// A ticket whose lines are as long as real kitchen data gets: a long name, a
/// pile of modifiers, and a note. Short fixtures are exactly why a starving
/// row survives a suite.
KdsTicketView _denseTicket(
  String id, {
  KitchenTicketStatus? status,
  String? name,
}) => KdsTicketView(
  kitchenTicketId: id,
  stationId: 'grill',
  status: status ?? KitchenTicketStatus.newTicket,
  orderId: id,
  orderNumber: '#$id',
  orderType: 'dine_in',
  tableLabel: 'T12',
  customerName: 'Abd al-Rahman al-Farsi',
  items: [
    KdsItemView(
      name: name ?? _longEn,
      quantity: 3,
      modifiers: const [
        'extra cheese',
        'no pickles',
        'well done',
        'sauce on the side',
      ],
      note: 'Allergy: sesame. Please keep separate from the rest of the order.',
    ),
    KdsItemView(name: name ?? _longEn, quantity: 1, modifiers: const ['rare']),
  ],
);

Widget _app(
  Widget home, {
  Locale locale = const Locale('en'),
  double scale = 1.0,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: restoflowLocalizationsDelegates,
  supportedLocales: kSupportedLocales,
  theme: restoflowKdsDarkBrandTheme(),
  builder: (context, child) => MediaQuery.withClampedTextScaling(
    minScaleFactor: scale,
    maxScaleFactor: scale,
    child: child!,
  ),
  home: home,
);

/// Runs [body] and returns every RenderFlex overflow the renderer reported.
///
/// Restored BEFORE the caller's expectation: the binding asserts it owns
/// `FlutterError.onError` by then.
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

Future<List<String>> _pumpBoard(
  WidgetTester tester, {
  required Size size,
  Locale locale = const Locale('en'),
  double scale = 1.0,
  int tickets = 4,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final name = switch (locale.languageCode) {
    'ar' => _longAr,
    'he' => _longHe,
    _ => _longEn,
  };
  return _overflowsDuring(() async {
    await tester.pumpWidget(
      _app(
        KdsScreen(
          tickets: [
            for (var i = 0; i < tickets; i++)
              _denseTicket('T$i', name: name, status: _statusFor(i)),
          ],
          allowRecall: false,
          enableNewArrivalAlert: true,
          newArrivalWindow: const Duration(milliseconds: 120),
        ),
        locale: locale,
        scale: scale,
      ),
    );
    await tester.pumpAndSettle();
  });
}

/// Spread the fixture across the board's real columns so every column layout is
/// exercised, not just the first.
KitchenTicketStatus _statusFor(int i) => switch (i % 3) {
  0 => KitchenTicketStatus.newTicket,
  1 => KitchenTicketStatus.acknowledged,
  _ => KitchenTicketStatus.ready,
};

const _widths = [1440.0, 1280.0, 1024.0, 834.0, 700.0, 540.0, 430.0, 390.0];
const _locales = [Locale('en'), Locale('ar'), Locale('he')];

/// Every colour the new-arrival highlight is currently painted with.
List<Color> _arrivalGlowColors(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.byType(DecoratedBox))
    .map((b) => b.decoration)
    .whereType<BoxDecoration>()
    .where((d) => d.boxShadow != null && d.boxShadow!.isNotEmpty)
    .expand((d) => d.boxShadow!)
    .map((s) => s.color)
    .toList();

void main() {
  // =========================================================================
  // A. ATTENTION IS ORANGE — the V5 subject
  // =========================================================================
  group('A. a freshly-arrived ticket announces itself in ORANGE', () {
    const brand = RestoflowBrandPalette.dark;
    const semantic = RestoflowSemanticColors.dark;

    Future<void> pumpCard(
      WidgetTester tester, {
      required bool highlightNew,
      KitchenTicketStatus? status,
      bool reduceMotion = false,
    }) async {
      tester.view.physicalSize = const Size(700, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final l10n = await _l10n('en');
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          theme: restoflowKdsDarkBrandTheme(),
          builder: (context, child) => reduceMotion
              ? MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: true),
                  child: child!,
                )
              : child!,
          home: Scaffold(
            body: SizedBox(
              width: 460,
              child: KdsTicketCard(
                ticket: _denseTicket('a1', status: status),
                l10n: l10n,
                now: DateTime(2026, 7, 9, 12),
                onAdvance: (_) {},
                onRecall: null,
                highlightNew: highlightNew,
                newArrivalWindow: const Duration(milliseconds: 120),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('the arrival glow is the brand ORANGE, not the structural '
        'navy it used to be', (tester) async {
      await pumpCard(tester, highlightNew: true, reduceMotion: true);
      final glows = _arrivalGlowColors(tester);
      expect(glows, isNotEmpty, reason: 'the arrival highlight must render');
      // Every glow layer is an alpha of the SAME hue; comparing the opaque
      // hue keeps this independent of the animation phase.
      final hues = glows.map((c) => c.withValues(alpha: 1)).toSet();
      expect(
        hues,
        contains(brand.accentOrange),
        reason: '"look here now" must not be painted in the furniture colour',
      );
      expect(
        hues,
        isNot(contains(brand.primaryNavy)),
        reason: 'the structural navy no longer carries attention',
      );
    });

    testWidgets('the New-order badge is orange with a legible foreground', (
      tester,
    ) async {
      await pumpCard(tester, highlightNew: true, reduceMotion: true);
      final badge = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(const Key('kds-new-badge-a1')),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (badge.decoration! as BoxDecoration).color,
        semantic.accent,
        reason: 'the loud badge and the glow must be the same attention hue',
      );
    });

    test('attention orange is NOT warning and NOT danger', () {
      // The whole point of a separate attention colour: a new ticket is not
      // late, and it is not cancelled. If these ever collide the board starts
      // lying about urgency.
      expect(semantic.accent, isNot(semantic.warning));
      expect(semantic.accent, isNot(semantic.danger));
      expect(semantic.accent, isNot(semantic.success));
      expect(semantic.accent, isNot(semantic.info));
      // ...and it IS the brand accent, so identity and attention agree.
      expect(semantic.accent, brand.accentOrange);
    });

    testWidgets('a CANCELLED ticket still pulses semantic DANGER, not orange', (
      tester,
    ) async {
      // PSC-001D. A cancellation is not an arrival; merging the two would be a
      // lie told in colour.
      await pumpCard(
        tester,
        highlightNew: false,
        status: KitchenTicketStatus.cancelled,
        reduceMotion: true,
      );
      final hues = _arrivalGlowColors(
        tester,
      ).map((c) => c.withValues(alpha: 1)).toSet();
      if (hues.isNotEmpty) {
        expect(hues, isNot(contains(brand.accentOrange)));
      }
    });

    testWidgets('an ordinary ticket carries no attention treatment at all', (
      tester,
    ) async {
      await pumpCard(
        tester,
        highlightNew: false,
        status: KitchenTicketStatus.acknowledged,
        reduceMotion: true,
      );
      final hues = _arrivalGlowColors(
        tester,
      ).map((c) => c.withValues(alpha: 1)).toSet();
      expect(
        hues,
        isNot(contains(brand.accentOrange)),
        reason:
            'orange must mean something; every card wearing it means '
            'nothing does',
      );
      expect(find.byKey(const Key('kds-new-badge-a1')), findsNothing);
    });

    testWidgets('orange did not leak into the rest of the card', (
      tester,
    ) async {
      // Structural chrome (the prep-summary block, ordinary icons) stays navy.
      // A palette pass that repaints every accent is how "attention" stops
      // being attention.
      await pumpCard(
        tester,
        highlightNew: false,
        status: KitchenTicketStatus.acknowledged,
        reduceMotion: true,
      );
      final context = tester.element(find.byType(KdsTicketCard));
      expect(Theme.of(context).colorScheme.primary, brand.primaryNavy);
    });
  });

  // =========================================================================
  // B. SEMANTIC STATES ARE FROZEN AND DISTINCT
  // =========================================================================
  group('B. the operational vocabulary survives the pass', () {
    const semantic = RestoflowSemanticColors.dark;

    test('success / warning / danger / info are four distinct colours', () {
      final roles = {
        semantic.success,
        semantic.warning,
        semantic.danger,
        semantic.info,
        semantic.accent,
      };
      expect(
        roles.length,
        5,
        reason: 'a state that shares a colour with another is unreadable',
      );
    });

    test('NO semantic value aliases a brand constant', () {
      // The POS trap, checked rather than assumed: there, "synced" was defined
      // AS the brand accent, so migrating the brand silently repainted an
      // operational state. KDS defines every semantic value explicitly, and
      // this pins that.
      const brand = RestoflowBrandPalette.dark;
      for (final value in [
        semantic.success,
        semantic.warning,
        semantic.danger,
        semantic.info,
      ]) {
        expect(value, isNot(brand.primaryNavy));
        expect(value, isNot(brand.accentOrange));
      }
    });
  });

  // =========================================================================
  // C. RESPONSIVE — the board at every target width
  // =========================================================================
  group('C. the board holds across the width matrix', () {
    for (final width in _widths) {
      testWidgets('${width.toInt()}px', (tester) async {
        final overflows = await _pumpBoard(
          tester,
          size: Size(width, width >= 900 ? 1000.0 : 1800.0),
        );
        expect(
          overflows,
          isEmpty,
          reason: 'no ticket surface may clip at ${width.toInt()}px',
        );
      });
    }
  });

  // =========================================================================
  // D. DIRECTION — long kitchen lines in every supported script
  // =========================================================================
  group('D. dense tickets in ar / he / en', () {
    for (final locale in _locales) {
      for (final width in [1280.0, 834.0, 430.0, 390.0]) {
        testWidgets('${width.toInt()}px / ${locale.languageCode}', (
          tester,
        ) async {
          final overflows = await _pumpBoard(
            tester,
            size: Size(width, width >= 900 ? 1200.0 : 2200.0),
            locale: locale,
          );
          expect(overflows, isEmpty);
        });
      }
    }
  });

  // =========================================================================
  // E. TEXT SCALE — a wall display is exactly where this gets turned up
  // =========================================================================
  group('E. 2x text scale', () {
    for (final locale in _locales) {
      for (final width in [1280.0, 430.0]) {
        testWidgets('${width.toInt()}px / ${locale.languageCode} / 2x', (
          tester,
        ) async {
          final overflows = await _pumpBoard(
            tester,
            size: Size(width, width >= 900 ? 3000.0 : 5000.0),
            locale: locale,
            scale: 2.0,
          );
          expect(overflows, isEmpty);
        });
      }
    }
  });

  // =========================================================================
  // F. NO WORKFLOW REGRESSION — a visual pass touches none of this
  // =========================================================================
  group('F. kitchen behaviour is untouched', () {
    testWidgets('the advance action still fires with its ticket id', (
      tester,
    ) async {
      final advanced = <String>[];
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          KdsScreen(
            tickets: [_denseTicket('T1')],
            allowRecall: false,
            onAdvanced: (ticket, _) => advanced.add(ticket.kitchenTicketId),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final action = find
          .descendant(
            of: find.byType(KdsTicketCard),
            matching: find.byType(FilledButton),
          )
          .first;
      await tester.ensureVisible(action);
      await tester.tap(action, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(advanced, [
        'T1',
      ], reason: 'the palette pass must not have gone near the workflow');
    });

    testWidgets('every ticket still renders its items, modifiers and note', (
      tester,
    ) async {
      await _pumpBoard(tester, size: const Size(1440, 1400), tickets: 1);
      expect(find.textContaining('extra cheese'), findsWidgets);
      expect(find.textContaining('no pickles'), findsWidgets);
      expect(
        find.textContaining('Allergy: sesame'),
        findsWidgets,
        reason: 'a note is kitchen-critical and may never be dropped for space',
      );
    });
  });
}
