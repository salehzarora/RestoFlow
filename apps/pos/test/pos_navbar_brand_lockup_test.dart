import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
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

void main() {
  group('bar height ladder', () {
    test('metrics: one modest step over the 68 / 62 / 56 ladder', () {
      const previous = {1280.0: 68.0, 900.0: 62.0, 600.0: 56.0, 430.0: 56.0};
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
        wordmark: true,
      ));
      expect(posTopBarMetricsFor(900), (
        height: 70.0,
        markSize: 40.0,
        wordmark: true,
      ));
      expect(posTopBarMetricsFor(600), (
        height: 62.0,
        markSize: 34.0,
        wordmark: true,
      ));
      expect(posTopBarMetricsFor(430), (
        height: 62.0,
        markSize: 34.0,
        wordmark: false,
      ));
      // The wordmark yields at the same width the typed title used to.
      expect(kPosCompactAppBarWidth, 480);
      expect(posTopBarMetricsFor(480).wordmark, isTrue);
      expect(posTopBarMetricsFor(479).wordmark, isFalse);
    });

    testWidgets('the rendered bar is 76 / 70 / 62 and the lockup fits inside '
        'it', (tester) async {
      for (final entry in {1280.0: 76.0, 900.0: 70.0, 430.0: 62.0}.entries) {
        await _pump(tester, width: entry.key);
        final appBar = tester.widget<AppBar>(_appBar());
        expect(appBar.toolbarHeight, entry.value, reason: '${entry.key}px');
        expect(tester.getSize(_appBar()).height, entry.value);
        final plate = tester.getRect(find.byKey(_plate));
        final bar = tester.getRect(_appBar());
        expect(plate.top, greaterThanOrEqualTo(bar.top + 6));
        expect(plate.bottom, lessThanOrEqualTo(bar.bottom - 6));
      }
    });
  });

  group('official lockup', () {
    testWidgets('the OFFICIAL symbol asset renders at every width; the '
        'OFFICIAL English wordmark artwork renders from 480px up', (
      tester,
    ) async {
      for (final width in const [320.0, 430.0, 480.0, 900.0, 1280.0]) {
        await _pump(tester, width: width);
        expect(
          _asset(RestoflowBrandMark.symbolAsset),
          findsOneWidget,
          reason: 'symbol at ${width}px',
        );
        expect(RestoflowBrandMark.symbolAsset, 'assets/brand/bizbot/bizbot_symbol.png');
        expect(
          _asset(RestoflowBrandMark.wordmarkLatinAsset),
          width >= kPosCompactAppBarWidth ? findsOneWidget : findsNothing,
          reason: 'wordmark at ${width}px',
        );
        // The symbol is drawn at the ladder's mark size, aspect preserved.
        final symbol = tester.widget<Image>(
          _asset(RestoflowBrandMark.symbolAsset),
        );
        final m = posTopBarMetricsFor(width);
        expect(symbol.width, m.markSize);
        expect(symbol.height, m.markSize);
        expect(symbol.fit, BoxFit.contain);
        // No retired art, no temporary monogram, no VEYRO anywhere in the bar.
        expect(find.descendant(of: _appBar(), matching: find.byIcon(Icons.point_of_sale)), findsNothing);
        expect(find.descendant(of: _appBar(), matching: find.text('B')), findsNothing);
        expect(find.descendant(of: _appBar(), matching: find.textContaining('VEYRO')), findsNothing);
      }
    });

    testWidgets('the plate is Light Neutral with no white halo box around '
        'the artwork', (tester) async {
      await _pump(tester, width: 1280);
      final plate = tester.widget<Container>(find.byKey(_plate));
      final deco = plate.decoration! as BoxDecoration;
      expect(deco.color, kBizbotSurface);
      expect(deco.borderRadius, BorderRadius.circular(RestoflowRadii.md));
    });

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
        await tester.pumpWidget(_app(locale: const Locale('en'), bundle: bundle));
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
          find.descendant(of: find.byKey(_plate), matching: find.byType(Transform)),
        )) {
          expect(t.transform.storage[0], greaterThanOrEqualTo(0));
        }
        final symbolX = tester.getCenter(_asset(RestoflowBrandMark.symbolAsset)).dx;
        final wordX = tester.getCenter(_asset(RestoflowBrandMark.wordmarkLatinAsset)).dx;
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
