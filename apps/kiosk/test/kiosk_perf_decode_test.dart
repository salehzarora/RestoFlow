import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kiosk/src/design/kiosk_theme.dart';
import 'package:restoflow_kiosk/src/media/kiosk_media_image.dart';
import 'package:restoflow_kiosk/src/widgets/kiosk_chrome.dart';

/// DEVICE-RUNTIME-LARGE-TABLET-PERF-110 — kiosk image DECODE budget: photos
/// decode near the physical pixel need of their destination (design px ×
/// stage scale × devicePixelRatio), never at the camera's native size, and
/// never upscaled.
void main() {
  group('kioskDecodeWidthFor (pure math)', () {
    test(
      'native 1080×1920 stage at dpr 1 decodes exactly the design width',
      () {
        expect(
          kioskDecodeWidthFor(
            designWidth: 343,
            stageScale: 1,
            devicePixelRatio: 1,
          ),
          343,
        );
      },
    );

    test('letterboxed stage × dpr resolves to the physical need', () {
      // A 411×731 logical phone panel at dpr 2.625 letterboxes the stage to
      // ≈0.3806 → 343 design px need ≈ 342.7 → 343 device px (ceil).
      expect(
        kioskDecodeWidthFor(
          designWidth: 343,
          stageScale: 0.3806,
          devicePixelRatio: 2.625,
        ),
        343,
      );
      expect(
        kioskDecodeWidthFor(
          designWidth: 150,
          stageScale: 0.5,
          devicePixelRatio: 2,
        ),
        150,
      );
      // Acer-class 1200×1920 logical panel → stage fits by height (1.0).
      expect(
        kioskDecodeWidthFor(
          designWidth: 1080 * 1.08,
          stageScale: 1,
          devicePixelRatio: 1.5,
        ),
        1750,
      );
    });

    test('unknown / unbounded / degenerate inputs mean NO cap (null)', () {
      expect(
        kioskDecodeWidthFor(
          designWidth: double.infinity,
          stageScale: 1,
          devicePixelRatio: 1,
        ),
        isNull,
      );
      expect(
        kioskDecodeWidthFor(designWidth: 0, stageScale: 1, devicePixelRatio: 1),
        isNull,
      );
      expect(
        kioskDecodeWidthFor(
          designWidth: 200,
          stageScale: 0,
          devicePixelRatio: 1,
        ),
        isNull,
      );
      expect(
        kioskDecodeWidthFor(
          designWidth: 200,
          stageScale: 1,
          devicePixelRatio: double.nan,
        ),
        isNull,
      );
    });
  });

  group('KioskStageScale.forBox mirrors FittedBox.contain', () {
    test('exact, width-limited, height-limited and degenerate boxes', () {
      expect(
        KioskStageScale.forBox(const Size(1080, 1920), kioskDesignSize),
        1,
      );
      expect(
        KioskStageScale.forBox(const Size(540, 1920), kioskDesignSize),
        0.5,
      );
      expect(
        KioskStageScale.forBox(const Size(1200, 1920), kioskDesignSize),
        1.0,
      ); // taller than wide: height wins
      expect(
        KioskStageScale.forBox(const Size(1200, 1800), kioskDesignSize),
        closeTo(0.9375, 1e-9),
      );
      expect(
        KioskStageScale.forBox(
          const Size(double.infinity, 100),
          kioskDesignSize,
        ),
        1,
      );
      expect(KioskStageScale.forBox(Size.zero, kioskDesignSize), 1);
    });
  });

  group('widget-level cap through the real stage', () {
    Future<void> pumpAt(
      WidgetTester tester, {
      required Size physical,
      required double dpr,
      required Widget child,
    }) async {
      tester.view.physicalSize = physical;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: KioskStage(child: child),
        ),
      );
      await tester.pump();
    }

    ResizeImage providerOf(WidgetTester tester) {
      final image = tester.widget<Image>(find.byType(Image));
      return image.image as ResizeImage;
    }

    testWidgets('native stage: a 343-wide menu well decodes at 343', (
      tester,
    ) async {
      await pumpAt(
        tester,
        physical: const Size(1080, 1920),
        dpr: 1,
        child: const Center(
          child: SizedBox(
            width: 343,
            height: 284,
            child: KioskMenuImage(
              url: 'https://cdn.example/photo.jpg',
              fallback: SizedBox.shrink(),
            ),
          ),
        ),
      );
      final p = providerOf(tester);
      expect(p.width, 343);
      expect(p.height, isNull); // width-only, like POS
      expect(p.allowUpscaling, isFalse);
      expect(
        (p.imageProvider as NetworkImage).url,
        'https://cdn.example/photo.jpg',
      );
    });

    testWidgets(
      'letterboxed stage (half size) at dpr 2 still decodes exactly 343 '
      'device px — stage scale × dpr is honored',
      (tester) async {
        await pumpAt(
          tester,
          physical: const Size(1080, 1920), // 540×960 logical at dpr 2
          dpr: 2,
          child: const Center(
            child: SizedBox(
              width: 343,
              height: 284,
              child: KioskMenuImage(
                url: 'https://cdn.example/photo.jpg',
                fallback: SizedBox.shrink(),
              ),
            ),
          ),
        );
        expect(providerOf(tester).width, 343);
      },
    );

    testWidgets('an explicit designWidth (wheel disc / hero) wins', (
      tester,
    ) async {
      await pumpAt(
        tester,
        physical: const Size(1080, 1920),
        dpr: 1,
        child: const Center(
          child: SizedBox(
            width: 600,
            height: 600,
            child: KioskMenuImage(
              url: 'https://cdn.example/photo.jpg',
              designWidth: 150,
              fallback: SizedBox.shrink(),
            ),
          ),
        ),
      );
      expect(providerOf(tester).width, 150);
    });
  });
}
