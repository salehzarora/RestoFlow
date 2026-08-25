import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kiosk/src/design/kiosk_theme.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_shell.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:restoflow_kiosk/src/widgets/category_wheel.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// KIOSK-CATEGORY-RAIL-115A — orange guide drag-feel refinement.
///
/// v11 defect (owner-reported): the painter's WHOLE geometry rode `apexY`,
/// so during a swipe the entire orange bow translated with the category
/// stack as one rigid body. 115A contract:
/// * the base rail is a STATIC spine, fixed in rail-local space — its
///   painter has NO apex/shift input at all;
/// * ONLY the marker layer (bright local segment + ring + dot + connector
///   dots) moves, traveling ALONG the fixed spine;
/// * the marker still tracks the finger during drag and settles at the
///   focus after release; sizes/x-bow/Model B/no-spring-back untouched.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  Future<void> pumpMenu(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container = ProviderContainer();
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
    container.read(kioskFlowProvider.notifier).startFromAttract();
    container
        .read(kioskFlowProvider.notifier)
        .pickService(KioskServiceType.takeaway);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 600));
  }

  Finder guidePaint() => find.descendant(
    of: find
        .descendant(
          of: find.byType(KioskCategoryWheel),
          matching: find.byType(ClipRect),
        )
        .first,
    matching: find.byWidgetPredicate(
      (w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_WheelRailPainter',
    ),
  );

  CustomPaint guide(WidgetTester tester) =>
      tester.widget<CustomPaint>(guidePaint());

  double markerApex(WidgetTester tester) =>
      (guide(tester).foregroundPainter as dynamic).apexY as double;

  Future<void> selectAndSettle(WidgetTester tester, int index) async {
    container.read(kioskFlowProvider.notifier).setCategoryIndex(index);
    await tester.pump(KioskWheel.snapDuration);
    await tester.pump(KioskWheel.snapDuration);
  }

  group('A. static spine vs moving marker', () {
    test('the spine curve is a pure function of y/height — anchored at '
        'innerX at both ends, bulging to ~97.5 at mid-height, monotone out '
        'and back', () {
      const h = 1220.0;
      expect(KioskWheel.railSpineX(0, h), closeTo(36, .5));
      expect(KioskWheel.railSpineX(h, h), closeTo(36, .5));
      expect(KioskWheel.railSpineX(h / 2, h), closeTo(97.5, 1));
      // Rising limb bulges outward monotonically.
      expect(
        KioskWheel.railSpineX(h * .25, h),
        greaterThan(KioskWheel.railSpineX(h * .1, h)),
      );
      expect(
        KioskWheel.railSpineX(h * .5, h),
        greaterThan(KioskWheel.railSpineX(h * .25, h)),
      );
      // Symmetric fall past the belly.
      expect(
        KioskWheel.railSpineX(h * .75, h),
        closeTo(KioskWheel.railSpineX(h * .25, h), 1.5),
      );
    });

    testWidgets('ONE guide CustomPaint behind the rows: a static base rail '
        'painter (NO apex input) + a marker foreground painter (the only '
        'apex-driven layer)', (tester) async {
      await pumpMenu(tester);
      expect(guidePaint(), findsOneWidget);
      final paint = guide(tester);
      // The base painter must expose NO apexY — it cannot ride the stack.
      expect(
        () => (paint.painter as dynamic).apexY,
        throwsNoSuchMethodError,
        reason: 'the base rail painter must have no apex/shift input',
      );
      expect(
        paint.foregroundPainter.runtimeType.toString(),
        '_WheelMarkerPainter',
      );
      expect(markerApex(tester), closeTo(320, 2));
      // Pointer-transparent, as before.
      expect(
        find.ancestor(of: guidePaint(), matching: find.byType(IgnorePointer)),
        findsWidgets,
      );
    });
  });

  group('B. drag feel', () {
    testWidgets('during a one-row drag the MARKER rides the finger while the '
        'base painter stays the static spine; on release it settles at the '
        'focus on the new category', (tester) async {
      await pumpMenu(tester);
      await selectAndSettle(tester, 1);
      expect(markerApex(tester), closeTo(320, 2));
      final baseBefore = guide(tester).painter;

      final wheel = find.byType(KioskCategoryWheel);
      final gesture = await tester.startGesture(tester.getCenter(wheel));
      await gesture.moveBy(const Offset(0, -19));
      await tester.pump();
      await gesture.moveBy(Offset(0, -KioskWheel.rowExtent));
      await tester.pump();

      // Marker moved a full row with the finger (320 → 120)…
      expect(markerApex(tester), closeTo(120, 2));
      // …while the base rail layer is still the SAME static-spine painter
      // (flip-only state: nothing about it can translate with the stack).
      final baseDuring = guide(tester).painter;
      expect(baseDuring.runtimeType.toString(), '_WheelRailPainter');
      expect(
        baseDuring!.shouldRepaint(baseBefore!),
        isFalse,
        reason: 'the drag must not dirty the base rail layer',
      );

      await gesture.up();
      await tester.pump(KioskWheel.snapDuration);
      await tester.pump(KioskWheel.snapDuration);
      expect(container.read(kioskFlowProvider).categoryIndex, 2);
      expect(markerApex(tester), closeTo(320, 2));
    });

    testWidgets('marker rest positions: 320 for EVERY index (116 wrapping '
        'mode has no finite tail — 420 never occurs)', (tester) async {
      await pumpMenu(tester);
      for (var a = 0; a <= 4; a++) {
        await selectAndSettle(tester, a);
        expect(
          markerApex(tester),
          closeTo(320, 2),
          reason: 'marker off focus at active $a',
        );
      }
    });
  });
}
