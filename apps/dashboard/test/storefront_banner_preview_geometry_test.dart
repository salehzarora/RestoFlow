import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_banner_preview_document.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_banner_preview_geometry.dart';

void main() {
  test('editor-only header CSS stays identical to actual Storefront rules', () {
    String canonical(List<String> paths) => paths
        .map(File.new)
        .firstWhere((file) => file.existsSync())
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(
      canonical([
        'web/storefront-banner-preview/home.css',
        'apps/dashboard/web/storefront-banner-preview/home.css',
      ]),
      canonical([
        '../../storefront/src/ui/storefront/home/home.module.css',
        'storefront/src/ui/storefront/home/home.module.css',
      ]),
    );
  });

  final base = Uri.parse('http://127.0.0.1:8147/storefront-banner-preview/');
  final image =
      '/storage/v1/object/public/storefront-media/${'a' * 32}/${'b' * 64}.webp';
  Map<String, Object?> data() => {
    'imageUrl': image,
    'enabled': true,
    'showIntro': true,
    'locale': 'ar',
    'displayName': 'اسم طويل بالعربية Restaurant',
    'city': 'كفرمندا',
    'menuHeading': 'على أي مزاج اليوم؟',
    'eyebrow': 'خريطة الطعم',
    'searchText': 'ابحث عن وجبتك',
    'categoryNames': ['وجبات', 'مشروبات'],
    'service': {
      'state': 'open',
      'pickupEnabled': true,
      'deliveryEnabled': false,
    },
    'copy': {
      'openNow': 'OPEN-SIGNAL',
      'closed': 'CLOSED-SIGNAL',
      'paused': 'PAUSED-SIGNAL',
      'pickup': 'استلام من المطعم',
      'pickupOff': 'غير متاح',
      'delivery': 'توصيل',
      'deliveryOff': 'غير متاح',
    },
  };
  test(
    'responsive image height uses the selected ratio, independent custom bounds and finite fallback',
    () {
      double h(bool phone, num width, num iw, num ih, [int? custom]) =>
          storefrontResponsiveBannerHeight(
            phone: phone,
            viewportWidth: width,
            imageWidth: iw,
            imageHeight: ih,
            customHeight: custom,
          );
      expect(h(true, 390, 960, 536), 320);
      expect(h(true, 390, 600, 1000), 640);
      expect(h(false, 1280, 2560, 640), 320);
      expect(h(false, 1920, 960, 536), 480);
      expect(h(true, 390, 960, 536, 520), 520);
      expect(h(false, 1920, 960, 536, 560), 560);
      expect(h(true, double.nan, 0, 0), 320);
      expect(h(false, 1280, 0, 0), 240);
    },
  );
  test(
    'responsive preview has real UI before its selected image and no legacy spacer; slider ticks retain its document',
    () {
      final responsive = {
        ...data(),
        'layout': 'responsive',
        'device': 'phone',
        'imageWidth': 960,
        'imageHeight': 536,
        'heightPx': 520,
      };
      final html = storefrontBannerPreviewDocument(responsive, base);
      expect(html, contains('class="menuBanner responsiveBanner"'));
      expect(html, contains('data-sf-banner-device="phone"'));
      expect(
        html.indexOf('orderStatus'),
        lessThan(html.indexOf('id="banner-photo"')),
      );
      expect(
        html.indexOf('id="banner-photo"'),
        lessThan(html.indexOf('searchControls')),
      );
      expect(html, isNot(contains('class="sceneWindow"')));
      expect(html, contains('width="960" height="536"'));
      final signature = storefrontBannerPresentationSignature(responsive);
      expect(
        storefrontBannerPresentationSignature({
          ...responsive,
          'heightPx': 640,
          'focalX': 0,
        }),
        signature,
      );
      expect(
        storefrontBannerPresentationSignature({
          ...responsive,
          'device': 'desktop',
        }),
        isNot(signature),
      );
      expect(html, contains("script-src &#39;none&#39;"));
      expect(html, isNot(contains('<script')));
      expect(
        storefrontBannerPreviewDocument(data(), base),
        isNot(contains('responsiveBanner')),
      );
    },
  );
  test(
    'cover preserves original pixels and physical X endpoints in every direction',
    () {
      final left = StorefrontBannerCrop.cover(1000, 500, 400, 400, 0, 50);
      final chosen = StorefrontBannerCrop.cover(1000, 500, 400, 400, 72, 50);
      final right = StorefrontBannerCrop.cover(1000, 500, 400, 400, 100, 50);
      expect(chosen.scale, .8);
      expect(chosen.offsetX, closeTo(-288, .001));
      expect(chosen.sourceLeft, closeTo(360, .001));
      expect(chosen.clippedX, 500);
      expect(chosen.clippedY, 0);
      expect(left.offsetX, 0);
      expect(right.sourceLeft, 500);
      expect(chosen.imageLoaded, isTrue);
    },
  );
  test('vertical cover and unavailable image are distinct, finite results', () {
    final tall = StorefrontBannerCrop.cover(500, 1000, 400, 200, 50, 25);
    expect(tall.sourceTop, 187.5);
    expect(tall.clippedY, 750);
    expect(tall.clippedX, 0);
    final missing = StorefrontBannerCrop.cover(0, 0, 390, 450, 50, 50);
    expect(missing.imageLoaded, isFalse);
    expect(missing.scale, 0);
    expect(missing.offsetX.isFinite, isTrue);
    expect(missing.clippedX, 0);
  });
  test(
    'desktop contain keeps the whole photograph and physical focal axes',
    () {
      for (final width in [960, 1280, 1920]) {
        for (final x in [0, 38, 50, 100]) {
          final fitted = StorefrontBannerCrop.cover(
            960,
            536,
            width,
            300,
            x,
            9,
            contain: true,
          );
          expect(fitted.renderedHeight, closeTo(300, .001));
          expect(fitted.renderedWidth, closeTo(960 * 300 / 536, .001));
          expect(fitted.clippedX, 0);
          expect(fitted.clippedY, 0);
          expect(fitted.sourceLeft, 0);
          expect(fitted.sourceTop, 0);
          expect(
            fitted.offsetX,
            closeTo((width - fitted.renderedWidth) * x / 100, .001),
          );
        }
      }
      final tall = StorefrontBannerCrop.cover(
        360,
        480,
        960,
        300,
        50,
        100,
        contain: true,
      );
      expect(tall.renderedHeight, 300);
      expect(tall.clippedX + tall.clippedY, 0);
      final wide = StorefrontBannerCrop.cover(
        1600,
        300,
        960,
        300,
        50,
        100,
        contain: true,
      );
      expect(wide.renderedWidth, 960);
      expect(wide.offsetY, 120);
    },
  );
  test('focal ticks are excluded from the document signature', () {
    final before = data()..['focalX'] = 0;
    final after = data()..['focalX'] = 100;
    expect(
      storefrontBannerPresentationSignature(before),
      storefrontBannerPresentationSignature(after),
    );
    after['showIntro'] = false;
    expect(
      storefrontBannerPresentationSignature(before),
      isNot(storefrontBannerPresentationSignature(after)),
    );
  });
  test(
    'markup escapes all tenant text and has no executable/navigation surface',
    () {
      final value = data()
        ..['displayName'] = '</span><script>alert(1)</script>';
      final html = storefrontBannerPreviewDocument(value, base);
      expect(html, contains('&lt;script&gt;'));
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('<form')));
      expect(html, isNot(contains('onclick=')));
      expect(html, contains('script-src &#39;none&#39;'));
      expect(html, contains('class="inner headerInner flexRow"'));
      expect(html, contains('data-sf-menu-banner'));
      expect(html, contains('class="menuAccent"'));
      expect(html, isNot(contains('class="headerPhone gridCenter"')));
      value['phoneAvailable'] = true;
      expect(
        storefrontBannerPreviewDocument(value, base),
        contains('class="headerPhone gridCenter"'),
      );
    },
  );
  test(
    'only published media and explicitly permitted public legacy hero URLs pass',
    () {
      expect(storefrontBannerPublicImage(image, base), isNotNull);
      expect(storefrontBannerPublicImage('$image?token=secret', base), isNull);
      expect(
        storefrontBannerPublicImage('https://example.org$image', base),
        isNull,
      );
      expect(
        storefrontBannerPublicImage(
          '/storage/v1/object/sign/menu-images/private.jpg',
          base,
        ),
        isNull,
      );
      final trusted = Uri.parse('https://isolated-preview.example');
      expect(
        storefrontBannerPublicImage(
          'https://isolated-preview.example$image',
          base,
        ),
        isNull,
      );
      expect(
        storefrontBannerPublicImage(
          'https://isolated-preview.example$image',
          base,
          mediaOrigin: trusted,
        ),
        isNotNull,
      );
      expect(
        storefrontBannerPublicImage(
          'https://isolated-preview.example$image',
          base,
          mediaOrigin: Uri.parse(
            'https://isolated-preview.example/not-an-origin',
          ),
        ),
        isNull,
      );
      expect(
        storefrontBannerPublicImage('http://127.0.0.1:55431$image', base),
        isNull,
      );
      expect(
        storefrontBannerPublicImage(
          'http://127.0.0.1:55431$image',
          base,
          mediaOrigin: Uri.parse('http://127.0.0.1:55431'),
        ),
        isNotNull,
      );
      const legacy =
          '/storage/v1/object/public/menu-images/restaurant/product.jpg';
      expect(storefrontBannerPublicImage(legacy, base), isNull);
      expect(
        storefrontBannerPublicImage(legacy, base, legacyHero: true),
        isNotNull,
      );
    },
  );
  test(
    'unknown public state never fabricates open/pickup and new scene rule matches',
    () {
      final value = data()
        ..['publicStateAvailable'] = false
        ..['service'] = null;
      var html = storefrontBannerPreviewDocument(value, base);
      expect(html, contains('data-state="unknown"'));
      expect(html, isNot(contains('OPEN-SIGNAL')));
      expect(html, isNot(contains('استلام من المطعم')));
      expect(html, contains('data-sf-scene-window'));
      expect(html, isNot(contains('data-sf-hero=""')));
      value['hero'] = {'title': 'عنوان', 'cta': 'اختيار'};
      html = storefrontBannerPreviewDocument(value, base);
      expect(html, contains('data-sf-hero=""'));
      value['showIntro'] = false;
      html = storefrontBannerPreviewDocument(value, base);
      expect(html, contains('data-sf-scene-window'));
      expect(html, isNot(contains('data-sf-hero=""')));
    },
  );
  test('CSS data cannot inject URLs, fonts or metric overrides', () {
    final colours = storefrontBannerPreviewColours({
      'colours': {
        '--bg': '#ffffff',
        '--sf': 'rgba(0,0,0,.5)',
        '--font': 'system-ui',
        '--acc': 'url(https://example.org/x)',
        '--header-height': '0px',
      },
    });
    expect(colours, {'--bg': '#ffffff', '--sf': 'rgba(0,0,0,.5)'});
  });
  test(
    'hero uses exact scalar format breaks and highlight without changing saved text',
    () {
      final value = data()
        ..['hero'] = {
          'title': 'A😀 B!',
          'format': {
            'text': 'A😀 B!',
            'highlight': {'start': 1, 'end': 2},
            'break_before': 3,
          },
          'name': 'PRODUCT-NAME',
          'price': '₪40',
          'cta': 'اختيار',
        };
      final html = storefrontBannerPreviewDocument(value, base);
      expect(html, contains('<span class="heroWord">😀<svg'));
      expect(
        html,
        contains('<span> </span><br aria-hidden="true"><span>B!</span>'),
      );
      expect(html, contains('aria-label="A😀 B!"'));
      expect(
        html,
        contains(
          'class="heroGhost" aria-hidden="true"><span dir="auto">اسم طويل بالعربية Restaurant',
        ),
      );
      (value['hero'] as Map)['format'] = {
        'text': 'not bound',
        'highlight': null,
        'break_before': null,
      };
      expect(
        () => storefrontBannerPreviewDocument(value, base),
        throwsFormatException,
      );
      (value['hero'] as Map)['format'] = {
        'text': 'A😀 B!',
        'highlight': null,
        'break_before': 9,
      };
      expect(
        () => storefrontBannerPreviewDocument(value, base),
        throwsFormatException,
      );
    },
  );
  test(
    'hero stamp product caption and whole-image choice match the existing presentation',
    () {
      final hero = <String, Object?>{
        'title': 'عنوان',
        'photo': image,
        'name': 'PRODUCT-NAME',
        'price': '₪40',
        'cta': 'اختيار',
        'stamp': 'NEW-STAMP',
        'imageFit': 'whole-image',
        'hasOptions': true,
        'fromLabel': 'FROM-LABEL',
      };
      final value = data()..['hero'] = hero;
      var html = storefrontBannerPreviewDocument(value, base);
      expect(html, contains('class="heroMedia wholeFrame" data-sf-product=""'));
      expect(html, contains('class="heroImg imageCover wholeImage"'));
      expect(html, contains('class="badge"><span dir="auto">NEW-STAMP</span>'));
      expect(html, contains('class="cardMain flexRow heroProduct"'));
      expect(
        html,
        contains('class="cardName"><span dir="auto">PRODUCT-NAME</span>'),
      );
      expect(html, contains('class="priceFrom">FROM-LABEL</span>'));
      expect(html, contains('class="ltr" dir="ltr">₪40</span>'));
      hero['imageFit'] = 'fill';
      hero['hasOptions'] = false;
      hero['stamp'] = null;
      html = storefrontBannerPreviewDocument(value, base);
      expect(html, contains('class="heroImg imageCover"'));
      expect(html, isNot(contains('class="heroImg imageCover wholeImage"')));
      expect(html, isNot(contains('class="priceFrom"')));
      expect(html, isNot(contains('NEW-STAMP')));
      expect(html, contains('class="langControl gridCenter"><span>ع</span>'));
    },
  );
}
