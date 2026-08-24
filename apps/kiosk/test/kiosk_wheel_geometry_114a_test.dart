import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kiosk/src/design/kiosk_theme.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_shell.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:restoflow_kiosk/src/widgets/category_wheel.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// KIOSK-UX-114A (geometry retuned by KIOSK-CATEGORY-RAIL-115) — the rail's
/// size hierarchy and anchor contract. 115 supersedes the 114A fixed
/// top-anchor with the Model B FOCUS BAND: the active row rests at
/// [KioskWheel.focusTop] (clip-local) for every index except the clamped
/// list tail, where it slides down to at most [KioskWheel.focusBottom].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  Future<void> pumpMenu(
    WidgetTester tester, {
    Size physical = const Size(1080, 1920),
    double dpr = 1,
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

  /// The disc of the row at [index] (the sized AnimatedContainer circle).
  /// 116: wrap-mode rows carry VIRTUAL slot keys; this suite never changes
  /// the selection before measuring, so slot == real index throughout.
  Finder discOf(int index) => find.descendant(
    of: find.byKey(ValueKey('wrap-slot-$index')),
    matching: find.byType(AnimatedContainer),
  );

  group('A. approved geometry constants', () {
    test(
      'discs grow to [210,132,100,78] with a strictly descending hierarchy',
      () {
        expect(KioskWheel.discByDistance, const [210.0, 132.0, 100.0, 78.0]);
        for (var i = 1; i < KioskWheel.discByDistance.length; i++) {
          expect(
            KioskWheel.discByDistance[i],
            lessThan(KioskWheel.discByDistance[i - 1]),
          );
        }
        // Modestly larger than the old [150, 98, 78, 64] baseline (>= +12%).
        const old = [150.0, 98.0, 78.0, 64.0];
        for (var i = 0; i < old.length; i++) {
          expect(
            KioskWheel.discByDistance[i],
            greaterThanOrEqualTo(old[i] * 1.12),
          );
        }
      },
    );

    test('row extent 200, rail width 272, focus band 220..320 (centerShift '
        'retired by 115)', () {
      expect(KioskWheel.rowExtent, 200);
      expect(KioskWheel.railWidth, 272);
      expect(KioskWheel.focusTop, 220);
      expect(KioskWheel.focusBottom, 320);
    });

    test('115 emphasis tables: labels [28,20,17], opacity [1,.75,.45,.28]', () {
      expect(KioskWheel.labelSizeByDistance, const [28.0, 20.0, 17.0]);
      expect(KioskWheel.opacityByDistance, const [1, .75, .45, .28]);
    });

    test('untouched: tap slop and snap duration', () {
      expect(KioskWheel.tapSlop, 8);
      expect(KioskWheel.snapDuration, const Duration(milliseconds: 450));
    });
  });

  group('B. on-stage placement + sizes', () {
    for (final view in const [
      ('canonical 1080x1920', Size(1080, 1920), 1.0),
      ('Acer 16" full-bleed 1200x1920', Size(1200, 1920), 1.0),
      ('11" 16:10 800x1280', Size(800, 1280), 1.0),
    ]) {
      testWidgets('${view.$1}: active disc renders at discByDistance[0], '
          'rests at the 115 focus, inside the body, no overflow', (
        tester,
      ) async {
        await pumpMenu(tester, physical: view.$2, dpr: view.$3);
        expect(tester.takeException(), isNull);

        final wheel = find.byType(KioskCategoryWheel);
        expect(wheel, findsOneWidget);
        final active = discOf(0).first;
        // Active disc renders at the approved 170 design px (getSize reads
        // the render box's OWN coordinates, i.e. design px on scaled stages).
        expect(tester.getSize(active).width, KioskWheel.discByDistance[0]);

        // 115 FOCUS CONTRACT: at activeIndex 0 the active disc's CENTER
        // rests at focusTop + rowExtent/2 = 320 clip-local design px (the
        // drag viewport below the top swipe hint), scale-normalized.
        final clip = tester.getRect(
          find.descendant(of: wheel, matching: find.byType(ClipRect)).first,
        );
        final scale =
            tester.getRect(wheel).height / // proportion-safe on
            tester.getSize(wheel).height; // scaled stages
        final centerClipLocal =
            (tester.getCenter(active).dy - clip.top) / scale;
        expect(
          centerClipLocal,
          closeTo(KioskWheel.focusTop + KioskWheel.rowExtent / 2, 2),
          reason:
              'active disc center must rest at the focus, '
              'got $centerClipLocal clip-local design px',
        );

        // Collision guard: the rail's clip region has ALWAYS run the full
        // body height behind the floating bottom bar (V2 layout) — what must
        // hold is that the top-anchored ACTIVE disc sits well clear of both
        // the header block above and the cart bar below.
        final barTop = tester
            .getRect(find.byKey(const Key('kiosk-cart-pill')))
            .top;
        expect(tester.getRect(active).bottom, lessThan(barTop));
        expect(
          tester.getRect(active).top,
          greaterThan(tester.getRect(wheel).top),
        );
      });
    }

    testWidgets('neighbor hierarchy on stage: distance 1/2/3 discs render at '
        '112/90/74', (tester) async {
      await pumpMenu(tester);
      Future<double> sizeAt(int index) async =>
          tester.getSize(discOf(index).first).width;
      expect(await sizeAt(1), KioskWheel.discByDistance[1]);
      expect(await sizeAt(2), KioskWheel.discByDistance[2]);
      expect(await sizeAt(3), KioskWheel.discByDistance[3]);
    });
  });

  group('C. gestures with the new geometry', () {
    testWidgets('a one-row drag (new rowExtent) selects the next category', (
      tester,
    ) async {
      await pumpMenu(tester);
      final wheel = find.byType(KioskCategoryWheel);
      final center = tester.getCenter(wheel);
      final gesture = await tester.startGesture(center);
      // The arena-winning move is consumed as touch slop — prime, then drag
      // exactly one (new) rowExtent, mirroring category_wheel_test's helper.
      await gesture.moveBy(const Offset(0, -19));
      await tester.pump();
      await gesture.moveBy(Offset(0, -KioskWheel.rowExtent));
      await tester.pump();
      await gesture.up();
      await tester.pump(KioskWheel.snapDuration);
      await tester.pump(KioskWheel.snapDuration);
      expect(container.read(kioskFlowProvider).categoryIndex, 1);
    });

    testWidgets('tapping a neighbor row still selects it (hit target intact)', (
      tester,
    ) async {
      await pumpMenu(tester);
      await tester.tap(discOf(1).first, warnIfMissed: false);
      await tester.pump(KioskWheel.snapDuration);
      await tester.pump(KioskWheel.snapDuration);
      expect(container.read(kioskFlowProvider).categoryIndex, 1);
    });
  });
}
