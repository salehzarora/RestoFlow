import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kiosk/src/data/kiosk_fixtures.dart';
import 'package:restoflow_kiosk/src/design/kiosk_theme.dart';
import 'package:restoflow_kiosk/src/widgets/category_wheel.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// KIOSK-001 Phase 1 — the category wheel's V2 interaction contract:
/// drag-follow, snap math (round(idx − dy/172), clamped), tap selection,
/// distance-based geometry/opacity and RTL/LTR rail mirroring.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpWheel(
    WidgetTester tester, {
    required int activeIndex,
    required ValueChanged<int> onSelect,
    String locale = 'ar',
  }) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          backgroundColor: const Color(0xFF0A1526),
          body: Row(
            // Mirrors the menu screen: the rail is the row's FIRST child under
            // the ambient Directionality (RTL → right, LTR → left).
            children: [
              KioskCategoryWheel(
                categories: kioskFixtureMenu,
                activeIndex: activeIndex,
                onSelect: onSelect,
              ),
              const Expanded(child: SizedBox.expand()),
            ],
          ),
        ),
      ),
    );
    await tester.pump(KioskWheel.snapDuration);
  }

  Finder rail() => find.byType(KioskCategoryWheel);

  /// Drags the rail so the wheel's accumulated drag delta is exactly [dy].
  /// The pointer event that wins the gesture arena has its delta consumed as
  /// touch slop, so a small sign-matched priming move precedes the real one.
  Future<void> railDrag(WidgetTester tester, double dy) async {
    final gesture = await tester.startGesture(tester.getCenter(rail()));
    await gesture.moveBy(Offset(0, dy.isNegative ? -19 : 19));
    await tester.pump();
    await gesture.moveBy(Offset(0, dy));
    await tester.pump();
    await gesture.up();
    await tester.pump(KioskWheel.snapDuration);
    await tester.pump(KioskWheel.snapDuration);
  }

  testWidgets('drag of one row snaps to the next category', (tester) async {
    int? selected;
    await pumpWheel(tester, activeIndex: 0, onSelect: (i) => selected = i);
    await railDrag(tester, -KioskWheel.rowExtent);
    expect(selected, 1);
  });

  testWidgets('a long fling advances by the per-swipe cap (wrapping mode)', (
    tester,
  ) async {
    // KIOSK-CATEGORY-LOOP-116: the fixture menu (N=5 >= wrapMinCount) now
    // WRAPS — there is no end clamp; one gesture is capped instead.
    int? selected;
    await pumpWheel(tester, activeIndex: 0, onSelect: (i) => selected = i);
    await railDrag(tester, -KioskWheel.rowExtent * 20);
    expect(selected, KioskWheel.wheelMaxRowsPerSwipe);
  });

  testWidgets('dragging down from the first category WRAPS backward', (
    tester,
  ) async {
    int? selected;
    await pumpWheel(tester, activeIndex: 0, onSelect: (i) => selected = i);
    await railDrag(tester, KioskWheel.rowExtent * 3);
    // 116: -3 rows from 0 resolves to (0-3) mod 5 = 2 — no clamp-at-0.
    expect(selected, 2);
  });

  testWidgets('partial-row drags round to the nearest index', (tester) async {
    int? selected;
    await pumpWheel(tester, activeIndex: 2, onSelect: (i) => selected = i);
    // 0.7 of a row downward → round(2 − 120/172) = round(1.30) = 1.
    await railDrag(tester, KioskWheel.rowExtent * .7);
    expect(selected, 1);
  });

  testWidgets('a sub-half-row drag snaps back with no selection change', (
    tester,
  ) async {
    int? selected;
    await pumpWheel(tester, activeIndex: 2, onSelect: (i) => selected = i);
    await railDrag(tester, KioskWheel.rowExtent * .3);
    expect(selected, isNull);
  });

  testWidgets('the wheel follows the finger live while dragging', (
    tester,
  ) async {
    await pumpWheel(tester, activeIndex: 0, onSelect: (_) {});
    // 116: wrap duplicates make plain find.text ambiguous — anchor on the
    // active virtual slot (initial virtual == activeIndex here).
    final label = find.descendant(
      of: find.byKey(const ValueKey('wrap-slot-0')),
      matching: find.text(kioskFixtureMenu[0].name.of('ar')),
    );
    final gesture = await tester.startGesture(tester.getCenter(rail()));
    await gesture.moveBy(const Offset(0, -19)); // arena acceptance (slop)
    await tester.pump();
    final before = tester.getCenter(label);
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();
    final during = tester.getCenter(label);
    expect(during.dy, closeTo(before.dy - 80, 1));
    await gesture.up();
    await tester.pump(KioskWheel.snapDuration);
    await tester.pump(KioskWheel.snapDuration);
  });

  testWidgets('tapping a neighboring disc selects it', (tester) async {
    int? selected;
    await pumpWheel(tester, activeIndex: 0, onSelect: (i) => selected = i);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('wrap-slot-1')),
        matching: find.text(kioskFixtureMenu[1].name.of('ar')),
      ),
    );
    expect(selected, 1);
  });

  testWidgets('active disc carries the V2 geometry falloff', (tester) async {
    await pumpWheel(tester, activeIndex: 1, onSelect: (_) {});
    final discSizes = <double>[
      for (var i = 0; i < kioskFixtureMenu.length; i++)
        tester
            .getSize(
              find.descendant(
                // 116: wrap-mode rows are keyed by VIRTUAL slot; with the
                // harness's fixed activeIndex the primary occurrences sit
                // at slot == real index.
                of: find.byKey(ValueKey('wrap-slot-$i')),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .width,
    ];
    expect(discSizes[1], KioskWheel.discByDistance[0]); // active 150
    expect(discSizes[0], KioskWheel.discByDistance[1]); // neighbor 98
    expect(discSizes[2], KioskWheel.discByDistance[1]);
    expect(discSizes[3], KioskWheel.discByDistance[2]); // second 78
    expect(discSizes[4], KioskWheel.discByDistance[3]); // farther 64
  });

  testWidgets('distance-based opacity falloff matches 1/.78/.5/.32', (
    tester,
  ) async {
    await pumpWheel(tester, activeIndex: 0, onSelect: (_) {});
    double opacityFor(int index) => tester
        .widget<AnimatedOpacity>(
          find
              .descendant(
                of: find.byKey(ValueKey('wrap-slot-$index')),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        )
        .opacity;
    expect(opacityFor(0), KioskWheel.opacityByDistance[0]);
    expect(opacityFor(1), KioskWheel.opacityByDistance[1]);
    expect(opacityFor(2), KioskWheel.opacityByDistance[2]);
    expect(opacityFor(3), KioskWheel.opacityByDistance[3]);
    expect(opacityFor(4), KioskWheel.opacityByDistance[3]);
  });

  testWidgets('AR (RTL) puts the rail on the right, EN mirrors it left', (
    tester,
  ) async {
    await pumpWheel(tester, activeIndex: 0, onSelect: (_) {});
    expect(
      tester.getCenter(find.byType(KioskCategoryWheel)).dx,
      greaterThan(1080 / 2),
    );
    await pumpWheel(tester, activeIndex: 0, onSelect: (_) {}, locale: 'en');
    expect(
      tester.getCenter(find.byType(KioskCategoryWheel)).dx,
      lessThan(1080 / 2),
    );
  });
}
