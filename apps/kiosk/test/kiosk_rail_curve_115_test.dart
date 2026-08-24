import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kiosk/src/data/kiosk_fixtures.dart';
import 'package:restoflow_kiosk/src/design/kiosk_theme.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_shell.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:restoflow_kiosk/src/widgets/category_wheel.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// KIOSK-CATEGORY-RAIL-115 — the curved, emphasized category carousel.
///
/// Contract under test (owner-approved, Model B):
/// * the stack translates like the shipped wheel — on an ordinary one-row
///   swipe the newly selected category visibly travels INTO the focus and
///   the rows do NOT spring back (final shift == drag-end shift);
/// * resting shift = clamp(focusTop − a·rowExtent,
///   min(focusTop, focusBottom − (N−1)·rowExtent), focusTop) — active disc
///   center 320 clip-local for indices 0..3 (N=5) and 420 at the clamped
///   tail;
/// * the rail bows: per-row outward x-offsets [22,−4,−20,−34] by distance
///   (RTL outward = +x, LTR mirrored), hit-tests following the transform;
/// * the orange guide is painted BEHIND the rows, its apex tracking the
///   focus; no wrapping, no duplicates, no continuous animation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  Future<void> pumpMenu(
    WidgetTester tester, {
    Size physical = const Size(1080, 1920),
    double dpr = 1,
    String? locale,
  }) async {
    tester.view.physicalSize = physical;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            locale: Locale(
              locale ?? ref.watch(kioskFlowProvider.select((s) => s.lang)),
            ),
            debugShowCheckedModeBanner: false,
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const KioskShell(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    container.read(kioskFlowProvider.notifier).startFromAttract();
    container
        .read(kioskFlowProvider.notifier)
        .pickService(KioskServiceType.takeaway);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 600));
  }

  Finder wheel() => find.byType(KioskCategoryWheel);

  // Scoped to the wheel: the menu grid reuses ValueKey(category.id).
  Finder rowOf(int index) => find.descendant(
    of: wheel(),
    matching: find.byKey(ValueKey(kioskFixtureMenu[index].id)),
  );

  Finder discOf(int index) => find.descendant(
    of: rowOf(index),
    matching: find.byType(AnimatedContainer),
  );

  double stageScale(WidgetTester tester) =>
      tester.getRect(wheel()).height / tester.getSize(wheel()).height;

  /// The drag viewport's top (global px) — clip-local y0.
  double clipTop(WidgetTester tester) => tester
      .getRect(
        find.descendant(of: wheel(), matching: find.byType(ClipRect)).first,
      )
      .top;

  double clipLocalYOf(WidgetTester tester, Offset global) =>
      (global.dy - clipTop(tester)) / stageScale(tester);

  Future<void> selectAndSettle(WidgetTester tester, int index) async {
    container.read(kioskFlowProvider.notifier).setCategoryIndex(index);
    await tester.pump(KioskWheel.snapDuration);
    await tester.pump(KioskWheel.snapDuration);
  }

  /// One vertical drag with the arena slop primed away (effective delta =
  /// [dy]), left UNRELEASED so mid-drag geometry can be asserted.
  Future<TestGesture> startRailDrag(WidgetTester tester, double dy) async {
    final gesture = await tester.startGesture(tester.getCenter(wheel()));
    await gesture.moveBy(Offset(0, dy.isNegative ? -19 : 19));
    await tester.pump();
    await gesture.moveBy(Offset(0, dy));
    await tester.pump();
    return gesture;
  }

  group('A. geometry constants + curve', () {
    test('xOffsetByDistance is exactly [22,-4,-20,-34] outward units', () {
      expect(KioskWheel.xOffsetByDistance, const [22.0, -4.0, -20.0, -34.0]);
    });

    testWidgets('RTL: the active disc center sits farther OUTWARD (right) '
        'than every neighbor', (tester) async {
      await pumpMenu(tester); // ar default → rail on the right
      final activeX = tester.getCenter(discOf(0).first).dx;
      for (var i = 1; i < 4; i++) {
        expect(
          activeX,
          greaterThan(tester.getCenter(discOf(i).first).dx + 10),
          reason: 'active must bow outward past distance-$i',
        );
      }
      // Farther rows recess progressively inward.
      expect(
        tester.getCenter(discOf(2).first).dx,
        lessThan(tester.getCenter(discOf(1).first).dx),
      );
      expect(
        tester.getCenter(discOf(3).first).dx,
        lessThan(tester.getCenter(discOf(2).first).dx),
      );
    });

    testWidgets('LTR mirrors the bow (active farther LEFT)', (tester) async {
      await pumpMenu(tester, locale: 'en');
      final activeX = tester.getCenter(discOf(0).first).dx;
      expect(activeX, lessThan(tester.getCenter(discOf(1).first).dx - 10));
      expect(
        tester.getCenter(discOf(3).first).dx,
        greaterThan(tester.getCenter(discOf(2).first).dx),
      );
    });

    testWidgets('active emphasis: 5px ring, blur 56 / spread 12 glow, and '
        'the ring stays inside the rail bounds', (tester) async {
      await pumpMenu(tester);
      final deco =
          tester.widget<AnimatedContainer>(discOf(0).first).decoration!
              as BoxDecoration;
      expect(deco.border!.top.width, 5);
      final shadows = deco.boxShadow!;
      expect(shadows[0].blurRadius, 56);
      expect(shadows[0].color.a, closeTo(.55, .01));
      expect(shadows[1].spreadRadius, 12);
      expect(shadows[1].color.a, closeTo(.16, .01));
      // Inactive keeps the 2px glass border.
      final inactive =
          tester.widget<AnimatedContainer>(discOf(1).first).decoration!
              as BoxDecoration;
      expect(inactive.border!.top.width, 2);
      // Ring bounds inside the rail (ring drawn inside the disc rect).
      final rail = tester.getRect(wheel());
      final disc = tester.getRect(discOf(0).first);
      expect(disc.left, greaterThanOrEqualTo(rail.left - .5));
      expect(disc.right, lessThanOrEqualTo(rail.right + .5));
    });

    testWidgets('the orange guide is painted BEHIND the rows, inside the '
        'clip, pointer-transparent', (tester) async {
      await pumpMenu(tester);
      final painterFinder = find.descendant(
        of: find.descendant(of: wheel(), matching: find.byType(ClipRect)).first,
        matching: find.byWidgetPredicate(
          // 115A: static spine painter + apex-driven marker foreground.
          (w) =>
              w is CustomPaint &&
              w.painter.runtimeType.toString() == '_WheelRailPainter' &&
              w.foregroundPainter.runtimeType.toString() ==
                  '_WheelMarkerPainter',
        ),
      );
      expect(painterFinder, findsOneWidget);
      expect(
        find.ancestor(of: painterFinder, matching: find.byType(IgnorePointer)),
        findsWidgets,
      );
    });
  });

  group('B. focus contract (N=5)', () {
    testWidgets('indices 0..3 rest with the active disc center at 320 '
        'clip-local; index 4 clamps to 420', (tester) async {
      await pumpMenu(tester);
      for (var a = 0; a <= 4; a++) {
        await selectAndSettle(tester, a);
        final center = clipLocalYOf(tester, tester.getCenter(discOf(a).first));
        expect(
          center,
          closeTo(a == 4 ? 420 : 320, 2),
          reason: 'active $a disc center off focus: $center',
        );
      }
    });
  });

  group('C. one-swipe travel proof (a=1 -> a=2)', () {
    testWidgets('index 2 travels INTO the focus during drag and stays there '
        'after release — zero spring-back', (tester) async {
      await pumpMenu(tester);
      await selectAndSettle(tester, 1);
      final beforeTop = clipLocalYOf(
        tester,
        tester.getRect(rowOf(2)).topCenter,
      );
      expect(beforeTop, closeTo(420, 2)); // one row below the focus

      final gesture = await startRailDrag(tester, -KioskWheel.rowExtent);
      final duringTop = clipLocalYOf(
        tester,
        tester.getRect(rowOf(2)).topCenter,
      );
      expect(
        duringTop,
        closeTo(KioskWheel.focusTop, 2),
        reason: 'row 2 must be IN the focus slot under the finger',
      );

      await gesture.up();
      await tester.pump(KioskWheel.snapDuration);
      await tester.pump(KioskWheel.snapDuration);
      expect(container.read(kioskFlowProvider).categoryIndex, 2);
      final afterTop = clipLocalYOf(tester, tester.getRect(rowOf(2)).topCenter);
      expect(
        afterTop,
        closeTo(duringTop, 2),
        reason: 'final shift must equal the drag-end shift (no spring-back)',
      );
      expect(
        clipLocalYOf(tester, tester.getCenter(discOf(2).first)),
        closeTo(320, 2),
      );
    });
  });

  group('D. tail clamp (a=3 -> a=4)', () {
    testWidgets('the last transition settles with 100px net stack motion and '
        'the active center at 420', (tester) async {
      await pumpMenu(tester);
      await selectAndSettle(tester, 3);
      final row4Before = clipLocalYOf(
        tester,
        tester.getRect(rowOf(4)).topCenter,
      );
      expect(row4Before, closeTo(420, 2));

      final gesture = await startRailDrag(tester, -KioskWheel.rowExtent);
      await gesture.up();
      await tester.pump(KioskWheel.snapDuration);
      await tester.pump(KioskWheel.snapDuration);
      expect(container.read(kioskFlowProvider).categoryIndex, 4);
      final row4After = clipLocalYOf(
        tester,
        tester.getRect(rowOf(4)).topCenter,
      );
      expect(row4After, closeTo(320, 2)); // net -100, not -200
      expect(
        clipLocalYOf(tester, tester.getCenter(discOf(4).first)),
        closeTo(420, 2),
      );
    });
  });

  group('E. density / list ends', () {
    testWidgets('active 0: all five categories on stage, last one above the '
        'cart bar', (tester) async {
      await pumpMenu(tester);
      for (var i = 0; i < 5; i++) {
        expect(rowOf(i), findsOneWidget);
      }
      final tops = [
        for (var i = 0; i < 5; i++)
          clipLocalYOf(tester, tester.getRect(rowOf(i)).topCenter),
      ];
      expect(tops[0], closeTo(220, 2));
      expect(tops[4], closeTo(1020, 2));
      // The rail has ALWAYS run behind the floating cart bar (V2 layout);
      // with the focus stack filling the viewport at a=0, the FARTHEST
      // disc's center stays above the bar line (its lower edge may tuck
      // behind the floating pill — measured ~29px at canonical).
      final barTop = tester
          .getRect(find.byKey(const Key('kiosk-cart-pill')))
          .top;
      expect(
        tester.getCenter(discOf(4).first).dy,
        lessThan(barTop),
        reason: 'the last disc center must stay above the cart bar',
      );
    });

    testWidgets('active 2: real neighbors visible above AND below the focus', (
      tester,
    ) async {
      await pumpMenu(tester);
      await selectAndSettle(tester, 2);
      // Row 1 fully inside the clip above; row 3 below.
      expect(
        clipLocalYOf(tester, tester.getRect(rowOf(1)).topCenter),
        closeTo(20, 2),
      );
      expect(
        clipLocalYOf(tester, tester.getRect(rowOf(3)).topCenter),
        closeTo(420, 2),
      );
    });

    testWidgets('active 4: rows 2/3/4 in view, earlier rows clipped above, '
        'exactly ONE widget per category — no wrap, no duplicates', (
      tester,
    ) async {
      await pumpMenu(tester);
      await selectAndSettle(tester, 4);
      expect(
        clipLocalYOf(tester, tester.getRect(rowOf(2)).topCenter),
        closeTo(-80, 2),
      );
      expect(
        clipLocalYOf(tester, tester.getRect(rowOf(3)).topCenter),
        closeTo(120, 2),
      );
      expect(
        clipLocalYOf(tester, tester.getRect(rowOf(4)).topCenter),
        closeTo(320, 2),
      );
      // Row 0 scrolled fully out of the clip above.
      expect(
        clipLocalYOf(tester, tester.getRect(rowOf(0)).bottomCenter),
        lessThanOrEqualTo(0),
      );
      for (var i = 0; i < 5; i++) {
        expect(rowOf(i), findsOneWidget); // one widget per category, no wrap
      }
    });
  });

  group('F. base() tiny-N unit contract', () {
    test(
      'N=5 bases are [220,20,-180,-380,-480]; N=1/N=2 stay well-ordered',
      () {
        expect(KioskWheel.baseShiftFor(0, 5), 220);
        expect(KioskWheel.baseShiftFor(1, 5), 20);
        expect(KioskWheel.baseShiftFor(2, 5), -180);
        expect(KioskWheel.baseShiftFor(3, 5), -380);
        expect(KioskWheel.baseShiftFor(4, 5), -480);
        // Tiny lists: the lower bound may exceed focusTop — the guard keeps
        // the clamp valid and the single/second item near the focus.
        expect(KioskWheel.baseShiftFor(0, 1), 220);
        expect(KioskWheel.baseShiftFor(0, 2), 220);
        expect(KioskWheel.baseShiftFor(1, 2), 120);
      },
    );
  });

  group('G. hit testing follows the transform', () {
    testWidgets('taps on transformed active/neighbor disc centers land '
        '(default warnIfMissed)', (tester) async {
      await pumpMenu(tester);
      await tester.tap(discOf(1).first); // no warnIfMissed:false — must HIT
      await tester.pump(KioskWheel.snapDuration);
      await tester.pump(KioskWheel.snapDuration);
      expect(container.read(kioskFlowProvider).categoryIndex, 1);
      await tester.tap(discOf(2).first);
      await tester.pump(KioskWheel.snapDuration);
      await tester.pump(KioskWheel.snapDuration);
      expect(container.read(kioskFlowProvider).categoryIndex, 2);
    });

    testWidgets('a drag starting on EMPTY rail space still turns the wheel', (
      tester,
    ) async {
      await pumpMenu(tester);
      // At the list tail the rail's lower half is real empty space (rows
      // end at clip-local 520): start a downward one-row drag there.
      await selectAndSettle(tester, 4);
      final origin = Offset(
        tester.getCenter(wheel()).dx,
        clipTop(tester) + 800 * stageScale(tester),
      );
      final gesture = await tester.startGesture(origin);
      await gesture.moveBy(const Offset(0, 19));
      await tester.pump();
      await gesture.moveBy(Offset(0, KioskWheel.rowExtent));
      await tester.pump();
      await gesture.up();
      await tester.pump(KioskWheel.snapDuration);
      await tester.pump(KioskWheel.snapDuration);
      expect(container.read(kioskFlowProvider).categoryIndex, 3);
    });
  });

  group('H. curved guide follows the focus', () {
    double apexOf(WidgetTester tester) {
      final paint = tester.widget<CustomPaint>(
        find.byWidgetPredicate(
          (w) =>
              w is CustomPaint &&
              w.painter.runtimeType.toString() == '_WheelRailPainter',
        ),
      );
      // 115A: the apex lives ONLY on the marker foreground layer.
      return (paint.foregroundPainter as dynamic).apexY as double;
    }

    testWidgets('apex settles at the focus center after selection (320), '
        'and at 420 on the clamped tail', (tester) async {
      await pumpMenu(tester);
      await selectAndSettle(tester, 2);
      expect(apexOf(tester), closeTo(320, 2));
      await selectAndSettle(tester, 4);
      expect(apexOf(tester), closeTo(420, 2));
    });
  });

  group('I. responsive matrix', () {
    for (final view in const [
      ('canonical 1080x1920', Size(1080, 1920), 1.0),
      ('Acer 16" 1200x1920', Size(1200, 1920), 1.0),
      ('11" 800x1280', Size(800, 1280), 1.0),
      ('narrow 450x975 regression', Size(450, 975), 1.0),
    ]) {
      testWidgets('${view.$1}: renders clean, focus holds, disc inside rail', (
        tester,
      ) async {
        await pumpMenu(tester, physical: view.$2, dpr: view.$3);
        expect(tester.takeException(), isNull);
        expect(
          clipLocalYOf(tester, tester.getCenter(discOf(0).first)),
          closeTo(320, 2),
        );
        final rail = tester.getRect(wheel());
        final disc = tester.getRect(discOf(0).first);
        expect(disc.left, greaterThanOrEqualTo(rail.left - .5));
        expect(disc.right, lessThanOrEqualTo(rail.right + .5));
        await selectAndSettle(tester, 4);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
