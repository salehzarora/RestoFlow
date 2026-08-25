import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kiosk/src/data/kiosk_fixtures.dart';
import 'package:restoflow_kiosk/src/design/kiosk_theme.dart';
import 'package:restoflow_kiosk/src/widgets/category_wheel.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// KIOSK-CATEGORY-LOOP-116 — the circular / wrapping category rail.
///
/// Owner-approved contract:
/// * N >= [KioskWheel.wrapMinCount] (= 4, OWNER DECISION) loops: after the
///   last category the next swipe lands on the first, and backward from the
///   first lands on the last — no hard stop, no tail, no end bounce;
/// * N = 1..3 keep the finite Model B behavior byte-for-byte;
/// * wrapping renders a 17-slot modulo window keyed by VIRTUAL slot
///   ('wrap-slot-$j') — real category ids may legitimately appear in more
///   than one slot at once;
/// * one gesture advances at most [KioskWheel.wheelMaxRowsPerSwipe] rows;
/// * the lazy window recenter is pixel-invisible;
/// * the active focus stays at disc-center 320 for EVERY index (the finite
///   420 tail state does not exist in wrapping mode).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpWheel(
    WidgetTester tester, {
    required List<KioskFixtureCategory> categories,
    int initial = 0,
    List<int>? selections,
    String locale = 'ar',
  }) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var active = initial;
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        debugShowCheckedModeBanner: false,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          backgroundColor: const Color(0xFF0A1526),
          body: StatefulBuilder(
            builder: (context, setHarness) => Row(
              children: [
                KioskCategoryWheel(
                  categories: categories,
                  activeIndex: active,
                  onSelect: (i) {
                    selections?.add(i);
                    setHarness(() => active = i);
                  },
                ),
                const Expanded(child: SizedBox.expand()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(KioskWheel.snapDuration);
  }

  Finder rail() => find.byType(KioskCategoryWheel);

  /// The unique ACTIVE disc: only distance 0 carries the 5px ring.
  Finder activeDisc() => find.descendant(
    of: rail(),
    matching: find.byWidgetPredicate(
      (w) =>
          w is AnimatedContainer &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).border?.top.width == 5,
    ),
  );

  Finder wrapSlots() => find.descendant(
    of: rail(),
    matching: find.byWidgetPredicate(
      (w) => (w.key is ValueKey<String>)
          ? (w.key! as ValueKey<String>).value.startsWith('wrap-slot-')
          : false,
    ),
  );

  /// True when a Text with [text] renders with its center within [tol] px
  /// of [y] (position-matched content lookup — wrap duplicates make plain
  /// find.text ambiguous by design). Labels hang ~70–130px below their
  /// row's disc center; rows are 200px apart, so 150 stays unambiguous.
  bool textAtY(WidgetTester tester, String text, double y, {double tol = 150}) {
    for (final e in find.text(text).evaluate()) {
      final box = e.renderObject;
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final center = box.localToGlobal(box.size.center(Offset.zero));
      if ((center.dy - y).abs() <= tol) return true;
    }
    return false;
  }

  Future<void> railDrag(WidgetTester tester, double dy) async {
    final gesture = await tester.startGesture(tester.getCenter(rail()));
    await gesture.moveBy(Offset(0, dy.isNegative ? -19 : 19));
    await tester.pump();
    await gesture.moveBy(Offset(0, dy));
    await tester.pump();
    await gesture.up();
    await tester.pump(KioskWheel.snapDuration);
    await tester.pump(KioskWheel.snapDuration);
    await tester.pump(KioskWheel.snapDuration);
  }

  final four = kioskFixtureMenu.take(4).toList();

  group('A. wrap logic + constants (OWNER DECISION: threshold 4)', () {
    test('binding constants: wrapMinCount 4, window radius 8, swipe cap 3', () {
      expect(KioskWheel.wrapMinCount, 4);
      expect(KioskWheel.wheelWindowRadius, 8);
      expect(KioskWheel.wheelMaxRowsPerSwipe, 3);
    });

    testWidgets('N=4 forward from the LAST lands on the FIRST (no clamp)', (
      tester,
    ) async {
      final sel = <int>[];
      await pumpWheel(tester, categories: four, initial: 3, selections: sel);
      await railDrag(tester, -KioskWheel.rowExtent);
      expect(sel, [0]);
    });

    testWidgets('N=4 backward from the FIRST lands on the LAST', (
      tester,
    ) async {
      final sel = <int>[];
      await pumpWheel(tester, categories: four, selections: sel);
      await railDrag(tester, KioskWheel.rowExtent);
      expect(sel, [3]);
    });

    testWidgets('a huge fling advances exactly wheelMaxRowsPerSwipe rows', (
      tester,
    ) async {
      final sel = <int>[];
      await pumpWheel(tester, categories: four, selections: sel);
      await railDrag(tester, -KioskWheel.rowExtent * 20);
      expect(sel, [3]); // +3 capped, not +20, and NOT clamped at the end
    });

    testWidgets('reported indices stay real (0..N-1) across a triple loop', (
      tester,
    ) async {
      final sel = <int>[];
      await pumpWheel(tester, categories: four, selections: sel);
      for (var i = 0; i < 12; i++) {
        await railDrag(tester, -KioskWheel.rowExtent);
      }
      expect(sel, [1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3, 0]);
    });
  });

  group('B. four-category owner walkthrough', () {
    testWidgets('forward 1->2->3->4->1 and backward 1->4', (tester) async {
      final sel = <int>[];
      await pumpWheel(tester, categories: four, selections: sel);
      for (var i = 0; i < 4; i++) {
        await railDrag(tester, -KioskWheel.rowExtent);
      }
      expect(sel, [1, 2, 3, 0], reason: 'forward loop must wrap 4 -> 1');
      sel.clear();
      await railDrag(tester, KioskWheel.rowExtent);
      expect(sel, [3], reason: 'backward from 1 must land on 4');
    });
  });

  group('C. visible modulo window', () {
    testWidgets('exactly 17 uniquely-keyed virtual slots; the slot above the '
        'first category resolves to the LAST; no dead tail below', (
      tester,
    ) async {
      await pumpWheel(tester, categories: four);
      expect(wrapSlots(), findsNWidgets(17));
      final keys = wrapSlots()
          .evaluate()
          .map((e) => (e.widget.key! as ValueKey<String>).value)
          .toSet();
      expect(keys.length, 17, reason: 'virtual slot keys must be unique');

      final focusY = tester.getCenter(activeDisc()).dy;
      // Wrapped neighbor ABOVE active 0 is the LAST category.
      expect(
        textAtY(tester, four[3].name.of('ar'), focusY - KioskWheel.rowExtent),
        isTrue,
        reason: 'slot above the first category must show the last one',
      );
      // Rows stay populated well below the focus (no dead tail).
      for (var k = 1; k <= 3; k++) {
        expect(
          textAtY(
            tester,
            four[k % 4].name.of('ar'),
            focusY + k * KioskWheel.rowExtent,
          ),
          isTrue,
          reason: 'row +$k below the focus must be populated',
        );
      }
    });

    testWidgets('after selecting the LAST category the rail below is '
        'populated by wrapped categories — no empty end-state', (tester) async {
      await pumpWheel(tester, categories: four);
      for (var i = 0; i < 3; i++) {
        await railDrag(tester, -KioskWheel.rowExtent);
      }
      final focusY = tester.getCenter(activeDisc()).dy;
      expect(textAtY(tester, four[3].name.of('ar'), focusY), isTrue);
      expect(
        textAtY(tester, four[0].name.of('ar'), focusY + KioskWheel.rowExtent),
        isTrue,
      );
      expect(
        textAtY(
          tester,
          four[1].name.of('ar'),
          focusY + 2 * KioskWheel.rowExtent,
        ),
        isTrue,
      );
    });
  });

  group('D. wrapped tap', () {
    testWidgets('tapping the wrapped occurrence ABOVE the first category '
        'selects the LAST and rotates toward it', (tester) async {
      final sel = <int>[];
      await pumpWheel(tester, categories: four, selections: sel);
      final focus = tester.getCenter(activeDisc());
      await tester.tapAt(Offset(focus.dx, focus.dy - KioskWheel.rowExtent));
      await tester.pump(KioskWheel.snapDuration);
      await tester.pump(KioskWheel.snapDuration);
      await tester.pump(KioskWheel.snapDuration);
      expect(sel, [3]);
      // The tapped category now sits at the focus.
      expect(
        textAtY(
          tester,
          four[3].name.of('ar'),
          tester.getCenter(activeDisc()).dy,
        ),
        isTrue,
      );
    });
  });

  group('E. wrap drag feel', () {
    testWidgets('the 4 -> 1 wrap slide has NO spring-back: the incoming '
        'category is in the focus under the finger and stays there', (
      tester,
    ) async {
      await pumpWheel(tester, categories: four);
      for (var i = 0; i < 3; i++) {
        await railDrag(tester, -KioskWheel.rowExtent); // walk to active 3
      }
      final focusBefore = tester.getCenter(activeDisc());
      final gesture = await tester.startGesture(tester.getCenter(rail()));
      await gesture.moveBy(const Offset(0, -19));
      await tester.pump();
      await gesture.moveBy(Offset(0, -KioskWheel.rowExtent));
      await tester.pump();
      // Mid-drag: the FIRST category (wrapping in) sits at the focus y.
      expect(
        textAtY(tester, four[0].name.of('ar'), focusBefore.dy),
        isTrue,
        reason: 'the wrapping-in category must ride into the focus',
      );
      await gesture.up();
      await tester.pump(KioskWheel.snapDuration);
      await tester.pump(KioskWheel.snapDuration);
      // Post-settle: still at the focus — no spring-back over the boundary.
      expect(textAtY(tester, four[0].name.of('ar'), focusBefore.dy), isTrue);
      expect(
        tester.getCenter(activeDisc()).dy,
        closeTo(focusBefore.dy, 2),
        reason: 'the focus never moves — including across the wrap',
      );
    });
  });

  group('F. marker / spine under wrapping', () {
    double markerApex(WidgetTester tester) {
      final paint = tester.widget<CustomPaint>(
        find.byWidgetPredicate(
          (w) =>
              w is CustomPaint &&
              w.painter.runtimeType.toString() == '_WheelRailPainter',
        ),
      );
      return (paint.foregroundPainter as dynamic).apexY as double;
    }

    testWidgets('marker rests at 320 for EVERY wrapped selection (the 420 '
        'finite tail never occurs); the static spine stays', (tester) async {
      await pumpWheel(tester, categories: four);
      for (var i = 0; i < 6; i++) {
        await railDrag(tester, -KioskWheel.rowExtent);
        expect(
          markerApex(tester),
          closeTo(KioskWheel.focusTop + KioskWheel.rowExtent / 2, 2),
          reason: 'marker must rest at the focus after every wrap step',
        );
      }
    });
  });

  group('G. lazy recenter is pixel-invisible', () {
    testWidgets('overlapping slot rects are identical before and after the '
        'window recenters', (tester) async {
      await pumpWheel(tester, categories: four);
      final gesture = await tester.startGesture(tester.getCenter(rail()));
      await gesture.moveBy(const Offset(0, -19));
      await tester.pump();
      await gesture.moveBy(Offset(0, -KioskWheel.rowExtent));
      await tester.pump();
      await gesture.up();
      await tester.pump(KioskWheel.snapDuration); // settle completes
      Map<String, Rect> snapshot() => {
        for (final e in wrapSlots().evaluate())
          (e.widget.key! as ValueKey<String>).value: (() {
            final box = e.renderObject! as RenderBox;
            final o = box.localToGlobal(Offset.zero);
            return o & box.size;
          })(),
      };
      final before = snapshot(); // post-settle, pre-recenter frame
      await tester.pump(); // the recenter build
      final after = snapshot();
      final overlap = before.keys.toSet().intersection(after.keys.toSet());
      expect(overlap, isNotEmpty);
      for (final key in overlap) {
        expect(
          (before[key]!.top - after[key]!.top).abs(),
          lessThan(.5),
          reason: 'recenter moved $key — must be pixel-identical',
        );
      }
    });
  });

  group('H. small counts (OWNER DECISION: 1..3 stay finite)', () {
    testWidgets('N=1: stable, no wrap slots, drags select nothing', (
      tester,
    ) async {
      final sel = <int>[];
      await pumpWheel(
        tester,
        categories: kioskFixtureMenu.take(1).toList(),
        selections: sel,
      );
      expect(wrapSlots(), findsNothing);
      await railDrag(tester, -KioskWheel.rowExtent);
      await railDrag(tester, KioskWheel.rowExtent);
      expect(sel, isEmpty);
      expect(activeDisc(), findsOneWidget);
    });

    testWidgets('N=2 stays FINITE: backward from the first clamps (no wrap)', (
      tester,
    ) async {
      final sel = <int>[];
      await pumpWheel(
        tester,
        categories: kioskFixtureMenu.take(2).toList(),
        selections: sel,
      );
      expect(wrapSlots(), findsNothing);
      await railDrag(tester, KioskWheel.rowExtent); // backward at the start
      expect(sel, isEmpty, reason: 'N=2 must NOT wrap');
      await railDrag(tester, -KioskWheel.rowExtent);
      expect(sel, [1]);
    });

    testWidgets('N=3 stays FINITE: forward from the last clamps (no wrap)', (
      tester,
    ) async {
      final sel = <int>[];
      await pumpWheel(
        tester,
        categories: kioskFixtureMenu.take(3).toList(),
        initial: 2,
        selections: sel,
      );
      expect(wrapSlots(), findsNothing);
      await railDrag(tester, -KioskWheel.rowExtent);
      expect(sel, isEmpty, reason: 'N=3 must NOT wrap (owner decision)');
      await railDrag(tester, KioskWheel.rowExtent);
      expect(sel, [1]);
    });
  });
}
