import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/pos_palette.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart';
import 'package:restoflow_pos/src/widgets/pos_bottom_bar.dart';

/// DEVICE-RUNTIME-LARGE-TABLET-PERF-110 — POS shell POSTURE is decided by
/// orientation first: PORTRAIT is ALWAYS single-pane (full-width menu +
/// bottom cart bar / sheet) however wide the logical viewport is; LANDSCAPE
/// keeps the frozen desktop/tablet/compact/phone contracts byte for byte.
/// A 16" 1920×1200 tablet turned portrait used to read as a WIDTH-band tablet
/// (1200 ≥ 1100 → two-pane with a 360dp side cart squeezed into portrait).
void main() {
  const portrait = <Size>[
    Size(1200, 1920),
    Size(1080, 1920),
    Size(960, 1536),
    Size(900, 1440),
    Size(800, 1280),
  ];
  group('A. posture matrix (pure functions)', () {
    for (final s in portrait) {
      test('${s.width.toInt()}x${s.height.toInt()} portrait → single pane, '
          'no side cart, 3 columns', () {
        expect(
          posShellPostureFor(width: s.width, height: s.height),
          PosShellPosture.singlePane,
        );
        expect(posShellCartWidthFor(width: s.width, height: s.height), 0);
        expect(posMenuColumnsForViewport(width: s.width, height: s.height), 3);
        expect(posCompactDensityFor(width: s.width, height: s.height), isFalse);
      });
    }

    test('phone portrait keeps 2 columns', () {
      expect(posMenuColumnsForViewport(width: 390, height: 844), 2);
      expect(
        posShellPostureFor(width: 390, height: 844),
        PosShellPosture.singlePane,
      );
      expect(posMenuColumnsForViewport(width: 600, height: 1000), 2);
      expect(posMenuColumnsForViewport(width: 759, height: 1200), 2);
      expect(posMenuColumnsForViewport(width: 760, height: 1200), 3);
    });

    test('desktop-class portrait (≥1360 wide: monitors / tall browser windows, '
        'never tablets) keeps the two-pane shell it has today', () {
      expect(
        posShellPostureFor(width: 1360, height: 1800),
        PosShellPosture.twoPane,
      );
      expect(posShellCartWidthFor(width: 1360, height: 1800), 400);
      expect(posMenuColumnsForViewport(width: 1360, height: 1800), 5);
      expect(
        posShellPostureFor(width: 1400, height: 2200),
        PosShellPosture.twoPane,
      );
      // ...and 1359 is the last tablet-class portrait width: single pane.
      expect(
        posShellPostureFor(width: 1359, height: 1800),
        PosShellPosture.singlePane,
      );
      expect(posShellCartWidthFor(width: 1359, height: 1800), 0);
      expect(posMenuColumnsForViewport(width: 1359, height: 1800), 3);
    });

    test('the square diagonal is portrait (single pane) — no 1dp flip into a '
        'side cart', () {
      expect(
        posShellPostureFor(width: 1000, height: 1000),
        PosShellPosture.singlePane,
      );
      expect(
        posShellPostureFor(width: 1001, height: 1000),
        PosShellPosture.twoPane,
      );
    });

    test('landscape matrix keeps the frozen two-pane contracts', () {
      expect(
        posShellPostureFor(width: 1920, height: 1200),
        PosShellPosture.twoPane,
      );
      expect(posShellCartWidthFor(width: 1920, height: 1200), 400);
      expect(posMenuColumnsForViewport(width: 1920, height: 1200), 5);

      expect(posShellCartWidthFor(width: 1536, height: 960), 400);
      expect(posMenuColumnsForViewport(width: 1536, height: 960), 5);

      expect(posShellCartWidthFor(width: 1280, height: 800), 360);
      expect(posMenuColumnsForViewport(width: 1280, height: 800), 4);
      expect(posCompactDensityFor(width: 1280, height: 800), isFalse);

      expect(posShellCartWidthFor(width: 1024, height: 600), 320);
      expect(posMenuColumnsForViewport(width: 1024, height: 600), 3);
      expect(posCompactDensityFor(width: 1024, height: 600), isTrue);
    });
  });

  group('B. LANDSCAPE byte-identity with the frozen PosLayoutMode tables', () {
    const sweep = <Size>[
      Size(1920, 1200),
      Size(1536, 960),
      Size(1440, 900),
      Size(1366, 1024),
      Size(1360, 800),
      Size(1359, 800),
      Size(1280, 800),
      Size(1100, 800),
      Size(1099, 800),
      Size(1024, 768),
      Size(1024, 641),
      Size(1024, 640),
      Size(1024, 600),
      Size(940, 720),
      Size(900, 600),
      Size(860, 600),
      Size(820, 600),
      Size(819, 600),
      Size(800, 600),
      Size(800, 480),
      Size(760, 600),
      Size(700, 400),
      Size(699, 400),
      Size(650, 400),
    ];
    for (final s in sweep) {
      test('${s.width.toInt()}x${s.height.toInt()}', () {
        final mode = posLayoutModeFor(width: s.width, height: s.height);
        expect(
          posShellPostureFor(width: s.width, height: s.height),
          mode == PosLayoutMode.phone
              ? PosShellPosture.singlePane
              : PosShellPosture.twoPane,
        );
        expect(
          posShellCartWidthFor(width: s.width, height: s.height),
          posCartWidthFor(mode),
        );
        expect(
          posMenuColumnsForViewport(width: s.width, height: s.height),
          posMenuColumnsFor(mode),
        );
        expect(
          posCompactDensityFor(width: s.width, height: s.height),
          mode == PosLayoutMode.compactLandscape,
        );
      });
    }
  });

  group('C. widget-level shell', () {
    Future<void> pumpMenu(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: PosMenuScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    SliverGridDelegateWithFixedCrossAxisCount gridDelegate(
      WidgetTester tester,
    ) {
      final keyed = find.byKey(const Key('pos-product-grid'));
      if (keyed.evaluate().isNotEmpty) {
        return tester.widget<SliverGrid>(keyed).gridDelegate
            as SliverGridDelegateWithFixedCrossAxisCount;
      }
      return tester.widget<GridView>(find.byType(GridView).last).gridDelegate
          as SliverGridDelegateWithFixedCrossAxisCount;
    }

    for (final s in portrait) {
      testWidgets(
        '${s.width.toInt()}x${s.height.toInt()} portrait: bottom cart bar, '
        'NO side cart panel, 3 columns, clean frame',
        (tester) async {
          await pumpMenu(tester, s);
          expect(tester.takeException(), isNull);
          expect(find.byType(PosBottomBar), findsOneWidget);
          expect(find.byKey(const Key('pos-bottom-cart-bar')), findsOneWidget);
          expect(find.byType(CartPanel), findsNothing);
          expect(gridDelegate(tester).crossAxisCount, 3);
          // The menu pane spans the FULL width.
          final scroll = tester.getSize(
            find.byKey(const Key('pos-menu-scroll')),
          );
          expect(scroll.width, s.width);
        },
      );
    }

    testWidgets('1280x800 (the 11" landscape reference) is untouched: '
        'side cart 360, 4 columns, no bottom bar', (tester) async {
      await pumpMenu(tester, const Size(1280, 800));
      expect(tester.takeException(), isNull);
      expect(find.byType(PosBottomBar), findsNothing);
      expect(find.byType(CartPanel), findsOneWidget);
      expect(tester.getSize(find.byType(CartPanel)).width, 360);
      expect(gridDelegate(tester).crossAxisCount, 4);
    });

    testWidgets('1920x1200 landscape (16" tablet flat) stays desktop: '
        'side cart 400, 5 columns', (tester) async {
      await pumpMenu(tester, const Size(1920, 1200));
      expect(tester.takeException(), isNull);
      expect(find.byType(CartPanel), findsOneWidget);
      expect(tester.getSize(find.byType(CartPanel)).width, 400);
      expect(gridDelegate(tester).crossAxisCount, 5);
    });

    testWidgets('1024x600 compact landscape keeps its 320 cart and 3 columns', (
      tester,
    ) async {
      await pumpMenu(tester, const Size(1024, 600));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(CartPanel)).width, 320);
      expect(gridDelegate(tester).crossAxisCount, 3);
    });

    testWidgets('rotating 1200x1920 → 1920x1200 → 1200x1920 swaps posture '
        'cleanly both ways', (tester) async {
      await pumpMenu(tester, const Size(1200, 1920));
      expect(find.byType(PosBottomBar), findsOneWidget);
      tester.view.physicalSize = const Size(1920, 1200);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(PosBottomBar), findsNothing);
      expect(tester.getSize(find.byType(CartPanel)).width, 400);
      tester.view.physicalSize = const Size(1200, 1920);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(PosBottomBar), findsOneWidget);
      expect(find.byType(CartPanel), findsNothing);
    });
  });
}
