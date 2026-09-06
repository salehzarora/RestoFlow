import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/order_submission.dart' show OutboxEntry;
import 'package:restoflow_pos/src/design/pos_visual_tokens.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/pos_palette.dart' show kPosCompactAppBarWidth;
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/ready_notifications_controller.dart';
import 'package:restoflow_pos/src/widgets/device_settings_menu.dart';
import 'package:restoflow_pos/src/widgets/language_selector.dart';
import 'package:restoflow_pos/src/widgets/outbox_status_indicator.dart';
import 'package:restoflow_pos/src/widgets/pos_identity_title.dart';
import 'package:restoflow_pos/src/widgets/ready_notification_bell.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';

/// POS-NAVBAR-BRAND-LOCKUP (2026-09-06) — the POS top bar is one modest step
/// taller (+10–15 %) and its start-edge brand block is the OFFICIAL BIZBOT
/// lockup: the final symbol asset + the official English wordmark PNG on a
/// Light Neutral plate. No typed `BIZBOT` stands in for the artwork, the
/// artwork never mirrors in RTL, nothing overflows at any supported width,
/// and the five operational actions + the restaurant identity keep their
/// places. POS only — no other app's navbar is touched by this change (the
/// PR diff is the proof; the dashboard rail keeps its own pins in
/// rf132_visual_fidelity_test).

class _QuietReady extends PosReadyNotificationsController {
  @override
  PosReadyNotificationsState build() =>
      const PosReadyNotificationsState(initialized: true, records: []);
}

class _QuietOutbox extends OutboxController {
  @override
  List<OutboxEntry> build() => const [];
}

/// Serves the design-system package assets from the repository checkout so the
/// REAL artwork decodes inside `flutter test apps/pos` (an app's test asset
/// bundle does not carry package assets); everything else falls through to
/// the normal test bundle.
class _RepoAssetBundle extends CachingAssetBundle {
  _RepoAssetBundle(this.root);

  final Directory root;
  static const String _pkgPrefix = 'packages/restoflow_design_system/';

  @override
  Future<ByteData> load(String key) async {
    if (key.startsWith(_pkgPrefix)) {
      final file = File(
        '${root.path}/packages/design_system/'
        '${key.substring(_pkgPrefix.length)}',
      );
      final bytes = await file.readAsBytes();
      return ByteData.sublistView(bytes);
    }
    return rootBundle.load(key);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      rootBundle.loadString(key, cache: cache);
}

Directory _repoRoot() {
  var dir = Directory.current;
  while (!(File('${dir.path}/vercel.json').existsSync() &&
      File('${dir.path}/pubspec.yaml').existsSync())) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('repo root not found from ${Directory.current}');
    }
    dir = parent;
  }
  return dir;
}

Widget _app({required Locale locale, AssetBundle? bundle}) {
  Widget app = MaterialApp(
    locale: locale,
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: const PosMenuScreen(),
  );
  if (bundle != null) {
    app = DefaultAssetBundle(bundle: bundle, child: app);
  }
  return ProviderScope(
    overrides: [
      posReadyNotificationsControllerProvider.overrideWith(_QuietReady.new),
      outboxControllerProvider.overrideWith(_QuietOutbox.new),
    ],
    child: app,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  Locale locale = const Locale('en'),
  double height = 800,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_app(locale: locale));
  await tester.pumpAndSettle();
}

/// Pumps with the REAL artwork decoded (repo-backed bundle + precache), so the
/// measured geometry is production geometry, not the Image fallbacks'.
Future<void> _pumpReal(
  WidgetTester tester, {
  required double width,
  Locale locale = const Locale('en'),
}) async {
  final bundle = _RepoAssetBundle(_repoRoot());
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(() async {
    await tester.pumpWidget(_app(locale: locale, bundle: bundle));
    final context = tester.element(find.byType(PosMenuScreen));
    for (final asset in const [
      RestoflowBrandMark.symbolAsset,
      RestoflowBrandMark.wordmarkLatinAsset,
    ]) {
      await precacheImage(
        AssetImage(asset, package: RestoflowBrandMark.package),
        context,
      );
    }
  });
  await tester.pumpAndSettle();
}

/// Width / height from a PNG's IHDR chunk (offset 16 / 20, big-endian).
({int width, int height}) _pngSize(File file) {
  final data = ByteData.sublistView(file.readAsBytesSync());
  return (width: data.getUint32(16), height: data.getUint32(20));
}

Finder _appBar() => find.byType(AppBar);

Finder _asset(String asset) => find.descendant(
  of: _appBar(),
  matching: find.byWidgetPredicate(
    (w) =>
        w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName == asset &&
        (w.image as AssetImage).package == RestoflowBrandMark.package,
  ),
);

const Key _plate = Key('pos-brand-tile');

/// The title Row that carries the plate and the restaurant identity.
RenderFlex _titleRow(WidgetTester tester) => tester.renderObject<RenderFlex>(
  find.ancestor(of: find.byKey(_plate), matching: find.byType(Row)).first,
);

void main() {
  group('bar height ladder', () {
    test('metrics: one modest step over the 68 / 62 / 56 ladder', () {
      final previous = <double, double>{1280: 68, 900: 62, 600: 56, 430: 56};
      for (final entry in previous.entries) {
        final m = posTopBarMetricsFor(entry.key);
        final ratio = m.height / entry.value;
        expect(
          ratio,
          inInclusiveRange(1.10, 1.15),
          reason: '${entry.key}px: ${entry.value} → ${m.height}',
        );
      }
      expect(posTopBarMetricsFor(1280), (
        height: 76.0,
        markSize: 44.0,
        plateWidth: 170.0,
        wordmark: true,
      ));
      expect(posTopBarMetricsFor(900), (
        height: 70.0,
        markSize: 40.0,
        plateWidth: 158.0,
        wordmark: true,
      ));
      expect(posTopBarMetricsFor(600), (
        height: 62.0,
        markSize: 34.0,
        plateWidth: 140.0,
        wordmark: true,
      ));
      expect(posTopBarMetricsFor(430), (
        height: 62.0,
        markSize: 34.0,
        plateWidth: 140.0,
        wordmark: false,
      ));
      // The wordmark yields at the same width the typed title used to.
      expect(kPosCompactAppBarWidth, 480);
      expect(posTopBarMetricsFor(480).wordmark, isTrue);
      expect(posTopBarMetricsFor(479).wordmark, isFalse);
    });

    test('the fixed wordmark plates are the lockup\'s natural width at the '
        'REAL artwork\'s proportion — never a squeezed wordmark', () {
      final png = _pngSize(
        File(
          '${_repoRoot().path}/packages/design_system/'
          '${RestoflowBrandMark.wordmarkLatinAsset}',
        ),
      );
      final aspect = png.width / png.height;
      expect(aspect, closeTo(796 / 152, 0.01));
      for (final width in const [1280.0, 900.0, 600.0]) {
        final m = posTopBarMetricsFor(width);
        final natural =
            kPosNavbarBrandPlateInsets.horizontal +
            m.markSize +
            RestoflowSpacing.md +
            m.markSize * 0.40 * aspect;
        expect(
          m.plateWidth,
          inInclusiveRange(natural, natural + 4),
          reason: '${width}px: natural $natural → ${m.plateWidth}',
        );
        expect(m.plateWidth % 2, 0, reason: 'even px');
      }
    });

    test('the plate resolves against the title slot: wordmark plate within '
        'its share, symbol-only otherwise (symbol scaling down to the room), '
        'never wider than the slot', () {
      final wide = posTopBarMetricsFor(1280);
      expect(posNavbarBrandPlateFor(wide, 828), (
        width: 170.0,
        markSize: 44.0,
        wordmark: true,
      ));
      expect(posNavbarBrandPlateFor(wide, 340), (
        width: 170.0,
        markSize: 44.0,
        wordmark: true,
      ));
      expect(posNavbarBrandPlateFor(wide, 339), (
        width: 52.0,
        markSize: 44.0,
        wordmark: false,
      ));
      // A slot narrower than the symbol plate: the symbol scales down
      // (aspect kept — it is a square) and the plate stays inside the slot.
      expect(posNavbarBrandPlateFor(wide, 30), (
        width: 30.0,
        markSize: 22.0,
        wordmark: false,
      ));
      expect(posNavbarBrandPlateFor(wide, 24), (
        width: 24.0,
        markSize: 16.0,
        wordmark: false,
      ));
      // Below the smallest legible symbol the plate hides rather than dots.
      expect(posNavbarBrandPlateFor(wide, 23), (
        width: 0.0,
        markSize: 0.0,
        wordmark: false,
      ));
      final twoPane = posTopBarMetricsFor(900);
      expect(posNavbarBrandPlateFor(twoPane, 428), (
        width: 158.0,
        markSize: 40.0,
        wordmark: true,
      ));
      expect(posNavbarBrandPlateFor(twoPane, 300), (
        width: 48.0,
        markSize: 40.0,
        wordmark: false,
      ));
      final phone = posTopBarMetricsFor(430);
      expect(posNavbarBrandPlateFor(phone, 1000), (
        width: 42.0,
        markSize: 34.0,
        wordmark: false,
      ));
      expect(posNavbarSymbolPlateWidth(34), 42);
      expect(kPosNavbarBrandMarkMin, 16);
    });

    testWidgets('the rendered bar is 76 / 70 / 62 and the REAL lockup sits '
        'inside it with ≥ 6 px above and below', (tester) async {
      for (final entry in {1280.0: 76.0, 900.0: 70.0, 430.0: 62.0}.entries) {
        await _pumpReal(tester, width: entry.key);
        expect(tester.takeException(), isNull);
        final appBar = tester.widget<AppBar>(_appBar());
        expect(appBar.toolbarHeight, entry.value, reason: '${entry.key}px');
        expect(tester.getSize(_appBar()).height, entry.value);
        final m = posTopBarMetricsFor(entry.key);
        final plate = tester.getRect(find.byKey(_plate));
        final bar = tester.getRect(_appBar());
        // The plate is exactly the symbol + its insets tall: the wordmark
        // column (17.6 / 16 px image + tagline) never rises above the symbol.
        final insets = m.wordmark
            ? kPosNavbarBrandPlateInsets
            : kPosNavbarBrandPlateCompactInsets;
        expect(plate.height, m.markSize + insets.vertical);
        expect(plate.top, greaterThanOrEqualTo(bar.top + 6));
        expect(plate.bottom, lessThanOrEqualTo(bar.bottom - 6));
        // The symbol renders at the step's mark size, the wordmark at its
        // native proportion (contained, never squeezed or stretched).
        final symbol = tester.getSize(_asset(RestoflowBrandMark.symbolAsset));
        expect(symbol, Size(m.markSize, m.markSize));
        if (m.wordmark) {
          final word = tester.getSize(
            _asset(RestoflowBrandMark.wordmarkLatinAsset),
          );
          expect(word.height, closeTo(m.markSize * 0.40, 0.01));
          expect(word.width, closeTo(word.height * 796 / 152, 0.5));
          expect(plate.width, m.plateWidth);
        } else {
          expect(plate.width, posNavbarSymbolPlateWidth(m.markSize));
        }
      }
    });

    testWidgets('even with the Image fallbacks (no package bundle) the plate '
        'stays inside the bar', (tester) async {
      for (final width in const [1280.0, 900.0, 430.0]) {
        await _pump(tester, width: width);
        expect(tester.takeException(), isNull);
        final plate = tester.getRect(find.byKey(_plate));
        final bar = tester.getRect(_appBar());
        expect(plate.top, greaterThanOrEqualTo(bar.top));
        expect(plate.bottom, lessThanOrEqualTo(bar.bottom));
      }
    });
  });

  group('official lockup', () {
    testWidgets('the OFFICIAL symbol asset renders at every width; the '
        'OFFICIAL English wordmark artwork renders once the title slot can '
        'host it (tablet / desktop bars) and yields on phone bars', (
      tester,
    ) async {
      final wordmarkExpected = <double, bool>{
        320: false,
        430: false,
        480: false,
        900: true,
        1280: true,
      };
      for (final entry in wordmarkExpected.entries) {
        final width = entry.key;
        await _pump(tester, width: width);
        // Sequential pumps in ONE tree double as a live-resize check: the
        // bar must re-lay out cleanly when the window grows or shrinks.
        expect(tester.takeException(), isNull, reason: 'resize → ${width}px');
        expect(
          _asset(RestoflowBrandMark.symbolAsset),
          findsOneWidget,
          reason: 'symbol at ${width}px',
        );
        expect(
          RestoflowBrandMark.symbolAsset,
          'assets/brand/bizbot/bizbot_symbol.png',
        );
        expect(
          _asset(RestoflowBrandMark.wordmarkLatinAsset),
          entry.value ? findsOneWidget : findsNothing,
          reason: 'wordmark at ${width}px',
        );
        // The plate is the fixed box resolved from the REAL title slot (the
        // Row's own max width): the wordmark plate when the wordmark shows,
        // the symbol-only plate otherwise — the Image fallbacks in this
        // bundle cannot inflate it. (This test font is far wider than any
        // production face, so at 480 px the five actions and the full outbox
        // label leave a slot far narrower than a real bar's — the plate
        // still fits it, symbol scaled down, nothing overflowing.)
        final m = posTopBarMetricsFor(width);
        final slot = _titleRow(tester).constraints.maxWidth;
        final resolved = posNavbarBrandPlateFor(m, slot);
        expect(resolved.wordmark, entry.value, reason: 'slot $slot @ $width');
        expect(
          resolved.markSize,
          greaterThanOrEqualTo(kPosNavbarBrandMarkMin),
        );
        final plate = tester.getSize(find.byKey(_plate));
        expect(plate.width, resolved.width, reason: 'plate at ${width}px');
        expect(plate.width, lessThanOrEqualTo(slot));
        // The symbol is drawn at the resolved mark size, aspect preserved.
        final symbol = tester.widget<Image>(
          _asset(RestoflowBrandMark.symbolAsset),
        );
        expect(symbol.width, resolved.markSize);
        expect(symbol.height, resolved.markSize);
        expect(symbol.fit, BoxFit.contain);
        if (entry.value) expect(resolved.markSize, m.markSize);
        // No retired art, no temporary monogram, no VEYRO anywhere in the bar.
        expect(
          find.descendant(
            of: _appBar(),
            matching: find.byIcon(Icons.point_of_sale),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: _appBar(), matching: find.text('B')),
          findsNothing,
        );
        expect(
          find.descendant(
            of: _appBar(),
            matching: find.textContaining('VEYRO'),
          ),
          findsNothing,
        );
      }
    });

    testWidgets('the plate is Light Neutral with no white halo box around '
        'the artwork', (tester) async {
      await _pump(tester, width: 1280);
      final plate = tester.widget<Container>(find.byKey(_plate));
      final deco = plate.decoration! as BoxDecoration;
      expect(deco.color, kBizbotSurface);
      expect(deco.borderRadius, BorderRadius.circular(RestoflowRadii.md));
      expect(plate.alignment, AlignmentDirectional.centerStart);
    });

    for (final locale in const [Locale('en'), Locale('ar')]) {
      testWidgets('${locale.languageCode}: a LIVE resize (desktop window / '
          'tablet rotation) re-lays the bar out without overflow, and the '
          'title Row always sums to its slot', (tester) async {
        for (final width in const [
          900.0,
          1280.0,
          430.0,
          1920.0,
          600.0,
          320.0,
          1100.0,
        ]) {
          await _pump(tester, width: width, locale: locale);
          final exception = tester.takeException();
          if (exception != null) {
            // Leave the geometry in the log so a recurrence is diagnosable.
            final plateBox = tester.renderObject(find.byKey(_plate));
            RenderObject? flex = plateBox.parent;
            while (flex != null && flex is! RenderFlex) {
              flex = flex.parent;
            }
            debugPrint(flex?.toStringDeep());
          }
          expect(exception, isNull, reason: 'resize → ${width}px');
          final row = _titleRow(tester);
          var sum = 0.0;
          row.visitChildren((child) => sum += (child as RenderBox).size.width);
          expect(sum, closeTo(row.size.width, 0.01), reason: '${width}px');
          expect(row.size.width, lessThanOrEqualTo(row.constraints.maxWidth));
        }
      });
    }

    testWidgets('with the REAL artwork decoded, no typed BIZBOT stands in for '
        'the wordmark (the tagline stays a localized text line)', (
      tester,
    ) async {
      final bundle = _RepoAssetBundle(_repoRoot());
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          _app(locale: const Locale('en'), bundle: bundle),
        );
        final context = tester.element(find.byType(PosMenuScreen));
        await precacheImage(
          const AssetImage(
            RestoflowBrandMark.symbolAsset,
            package: RestoflowBrandMark.package,
          ),
          context,
        );
        await precacheImage(
          const AssetImage(
            RestoflowBrandMark.wordmarkLatinAsset,
            package: RestoflowBrandMark.package,
          ),
          context,
        );
      });
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        find.descendant(of: _appBar(), matching: find.text(l10n.posBrandName)),
        findsNothing,
        reason: 'the wordmark is artwork, never typed',
      );
      expect(
        find.descendant(
          of: _appBar(),
          matching: find.text(l10n.posBrandTagline),
        ),
        findsOneWidget,
      );
      expect(_asset(RestoflowBrandMark.wordmarkLatinAsset), findsOneWidget);
      expect(_asset(RestoflowBrandMark.symbolAsset), findsOneWidget);
      // The decoded mark sits directly on the plate — no extra tile/box and
      // no fallback glyph (the errorBuilder never ran).
      expect(
        find.descendant(
          of: find.byType(RestoflowBrandMark),
          matching: find.byType(Container),
        ),
        findsNothing,
      );
      expect(find.byIcon(Icons.receipt_long_rounded), findsNothing);
    });

    testWidgets('without the package bundle a typed BIZBOT can only be the '
        'Image fallback, never a sibling substitute', (tester) async {
      await _pump(tester, width: 1280);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final typed = find.descendant(
        of: _appBar(),
        matching: find.text(l10n.posBrandName),
      );
      for (final element in typed.evaluate()) {
        expect(
          element.findAncestorWidgetOfExactType<Image>(),
          isNotNull,
          reason: 'a typed brand name outside an Image errorBuilder',
        );
      }
    });
  });

  group('RTL / LTR', () {
    for (final locale in const [Locale('ar'), Locale('he'), Locale('en')]) {
      testWidgets('${locale.languageCode}: artwork never mirrors, the symbol '
          'leads at the START edge, nothing overflows', (tester) async {
        await _pump(tester, width: 1280, locale: locale);
        expect(tester.takeException(), isNull);
        final images = tester.widgetList<Image>(
          find.descendant(of: find.byKey(_plate), matching: find.byType(Image)),
        );
        expect(images.length, 2);
        for (final image in images) {
          expect(image.matchTextDirection, isFalse);
        }
        for (final t in tester.widgetList<Transform>(
          find.descendant(
            of: find.byKey(_plate),
            matching: find.byType(Transform),
          ),
        )) {
          expect(t.transform.storage[0], greaterThanOrEqualTo(0));
        }
        final symbolX = tester
            .getCenter(_asset(RestoflowBrandMark.symbolAsset))
            .dx;
        final wordX = tester
            .getCenter(_asset(RestoflowBrandMark.wordmarkLatinAsset))
            .dx;
        final direction = Directionality.of(tester.element(find.byKey(_plate)));
        if (direction == TextDirection.rtl) {
          expect(symbolX, greaterThan(wordX));
          expect(tester.getRect(find.byKey(_plate)).right, lessThan(1280 - 8));
        } else {
          expect(symbolX, lessThan(wordX));
          expect(tester.getRect(find.byKey(_plate)).left, greaterThan(8));
        }
      });
    }
  });

  group('responsive + existing bar contents', () {
    for (final locale in const [Locale('ar'), Locale('en')]) {
      for (final width in const [
        320.0,
        360.0,
        390.0,
        430.0,
        600.0,
        768.0,
        820.0,
        1024.0,
        1100.0,
        1280.0,
        1920.0,
      ]) {
        testWidgets('${locale.languageCode} @ ${width.toInt()}px: no overflow, '
            'five actions, plate never collides with the cluster', (
          tester,
        ) async {
          await _pump(tester, width: width, locale: locale);
          expect(tester.takeException(), isNull);
          expect(find.byType(ReadyNotificationBell), findsOneWidget);
          expect(find.byType(RecentOrdersButton), findsOneWidget);
          expect(find.byType(OutboxStatusIndicator), findsOneWidget);
          expect(find.byType(LanguageSelector), findsOneWidget);
          expect(find.byType(DeviceSettingsMenu), findsOneWidget);
          expect(find.byKey(_plate), findsOneWidget);
          expect(find.byType(PosIdentityTitle), findsOneWidget);
          final plate = tester.getRect(find.byKey(_plate));
          final bell = tester.getRect(find.byType(ReadyNotificationBell));
          expect(plate.overlaps(bell), isFalse);
          final bar = tester.getRect(_appBar());
          expect(plate.top, greaterThanOrEqualTo(bar.top));
          expect(plate.bottom, lessThanOrEqualTo(bar.bottom));
          for (final action in <Finder>[
            find.byType(ReadyNotificationBell),
            find.byType(RecentOrdersButton),
            find.byType(LanguageSelector),
            find.byType(DeviceSettingsMenu),
          ]) {
            expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
          }
        });
      }
    }
  });
}
