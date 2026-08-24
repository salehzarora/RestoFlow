import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kiosk/src/design/kiosk_theme.dart';
import 'package:restoflow_kiosk/src/media/kiosk_media_image.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_shell.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:restoflow_kiosk/src/widgets/kiosk_chrome.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// KIOSK-UI-113 — the stage surface is FULL-BLEED on wider portrait tablets.
///
/// The kiosk is authored on a 1080×1920 canvas; 16:10 portrait tablets
/// (both owner devices) are wider than 9:16, and the fixed design width used
/// to leave ~5% app-painted gutters per side. The stage now widens its
/// design width to the viewport aspect (clamped to
/// [kioskDesignSize.width, kioskStageMaxDesignWidth]) while the SCALE — and
/// with it pointer transforms and every decode cap — keeps its exact
/// canonical meaning, and the canonical 1080×1920 composition stays
/// byte-identical.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  Future<void> pumpShell(
    WidgetTester tester, {
    required Size physical,
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
  }

  /// The stage-owned painted canvas (the vertical canvasTop→canvasBottom
  /// gradient surface every screen sits on) — NOT an incidental child.
  Finder stageCanvas() => find
      .descendant(
        of: find.byType(KioskStage),
        matching: find.byWidgetPredicate((w) {
          if (w is! DecoratedBox) return false;
          final d = w.decoration;
          if (d is! BoxDecoration) return false;
          final g = d.gradient;
          return g is LinearGradient &&
              g.begin == Alignment.topCenter &&
              g.end == Alignment.bottomCenter &&
              g.colors.length == 2 &&
              g.colors.first == KioskColors.canvasTop;
        }),
      )
      .first;

  Future<void> toMenu(WidgetTester tester) async {
    container.read(kioskFlowProvider.notifier).startFromAttract();
    container
        .read(kioskFlowProvider.notifier)
        .pickService(KioskServiceType.takeaway);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('A. pure stage-size rule', () {
    test('16:10 portrait classes widen to 1200×1920; canonical and narrow '
        'stay 1080; 4:3 clamps at the documented 1280 cap', () {
      expect(
        KioskStageScale.stageSizeFor(const Size(1200, 1920)),
        const Size(1200, 1920),
      );
      expect(
        KioskStageScale.stageSizeFor(const Size(800, 1280)),
        const Size(1200, 1920),
      );
      expect(
        KioskStageScale.stageSizeFor(const Size(1080, 1920)),
        const Size(1080, 1920),
      );
      expect(
        KioskStageScale.stageSizeFor(const Size(450, 975)),
        const Size(1080, 1920),
      );
      // 4:3 (iPad-class web preview): capped, small side gutters remain.
      expect(
        KioskStageScale.stageSizeFor(const Size(1024, 1366)),
        Size(kioskStageMaxDesignWidth, 1920),
      );
      // Degenerate boxes fall back to the canonical canvas.
      expect(KioskStageScale.stageSizeFor(Size.zero), kioskDesignSize);
    });

    test('the widened stage never changes the SCALE meaning', () {
      for (final box in const [
        Size(1200, 1920),
        Size(800, 1280),
        Size(1080, 1920),
        Size(450, 975),
        Size(1024, 1366),
      ]) {
        final scale = KioskStageScale.forBox(box, kioskDesignSize);
        final stage = KioskStageScale.stageSizeFor(box);
        // FittedBox.contain of the ADAPTIVE stage resolves to the SAME scale
        // the canonical math publishes (pointer transforms + decode caps).
        final fitted = KioskStageScale.forBox(box, stage);
        expect(fitted, closeTo(scale, 1e-9), reason: '$box');
      }
    });
  });

  group('B. on-screen full bleed', () {
    testWidgets('16" Acer class (1200×1920 @ dpr 1): the stage canvas spans '
        'the FULL viewport width on attract AND menu', (tester) async {
      await pumpShell(tester, physical: const Size(1200, 1920));
      var rect = tester.getRect(stageCanvas());
      expect(rect.left, 0);
      expect(rect.right, 1200);
      expect(tester.takeException(), isNull);

      await toMenu(tester);
      rect = tester.getRect(stageCanvas());
      expect(rect.left, 0);
      expect(rect.right, 1200);
      expect(tester.takeException(), isNull);
    });

    testWidgets('11" class (800×1280 @ dpr 1): full width, no gutter', (
      tester,
    ) async {
      await pumpShell(tester, physical: const Size(800, 1280));
      final rect = tester.getRect(stageCanvas());
      expect(rect.left, 0);
      expect(rect.right, 800);
      expect(tester.takeException(), isNull);
      await toMenu(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('same panel at dpr 1.5 (physical 1200×1920 → logical '
        '800×1280): full width, no gutter', (tester) async {
      await pumpShell(tester, physical: const Size(1200, 1920), dpr: 1.5);
      final rect = tester.getRect(stageCanvas());
      expect(rect.left, 0);
      expect(rect.right, 800);
      expect(tester.takeException(), isNull);
    });

    testWidgets('canonical 1080×1920 is BYTE-IDENTICAL: design size stays '
        '1080×1920 and fills the viewport exactly', (tester) async {
      await pumpShell(tester, physical: const Size(1080, 1920));
      // Render-box size in its own coordinates = the design canvas.
      expect(tester.getSize(stageCanvas()), const Size(1080, 1920));
      final rect = tester.getRect(stageCanvas());
      expect(rect, const Rect.fromLTWH(0, 0, 1080, 1920));
      expect(tester.takeException(), isNull);
    });

    testWidgets('narrow/tall 450×975 keeps the 1080 minimum: full WIDTH, '
        'letterbox stays top/bottom (existing posture)', (tester) async {
      await pumpShell(tester, physical: const Size(450, 975));
      expect(tester.getSize(stageCanvas()).width, 1080);
      final rect = tester.getRect(stageCanvas());
      expect(rect.left, 0);
      expect(rect.right, 450);
      expect(rect.top, greaterThan(0)); // vertical letterbox preserved
      expect(rect.bottom, lessThan(975));
      expect(tester.takeException(), isNull);
    });
  });

  group('C. decode follow-through', () {
    testWidgets('a stage-filling live image decodes for the WIDENED stage '
        'width (LayoutBuilder caps track the real surface)', (tester) async {
      tester.view.physicalSize = const Size(1200, 1920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: KioskStage(
            child: Stack(
              fit: StackFit.expand,
              children: const [
                KioskMenuImage(
                  url: 'https://cdn.example/hero.jpg',
                  fallback: SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image as ResizeImage;
      // Stage width 1200 design px × scale 1.0 × dpr 1 → 1200, not 1080.
      expect(provider.width, 1200);
    });
  });
}
