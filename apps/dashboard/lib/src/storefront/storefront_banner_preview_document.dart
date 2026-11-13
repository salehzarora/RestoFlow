import 'dart:convert';

// No application/session transport is embedded in this document. All values
// are display data already read by the caller; no supplied value becomes HTML.
String _escape(Object? value) =>
    const HtmlEscape().convert(value is String ? value : '');
Map _map(Object? value) => value is Map ? value : const {};
List _list(Object? value) => value is List ? value : const [];
String _string(Object? value) => value is String ? value : '';

/// A closed presentation signature deliberately excludes focal values. Slider
/// ticks must update the existing image's CSS, not replace its document/node.
String storefrontBannerPresentationSignature(Map<String, Object?> data) =>
    jsonEncode({
      for (final key in const [
        'imageUrl',
        'imageWidth',
        'imageHeight',
        'layout',
        'device',
        'mediaOrigin',
        'enabled',
        'showIntro',
        'displayName',
        'city',
        'logoUrl',
        'phoneAvailable',
        'locale',
        'fontFamily',
        'colours',
        'announcement',
        'segments',
        'menuHeading',
        'menuCaption',
        'eyebrow',
        'searchText',
        'categoryNames',
        'service',
        'copy',
        'hero',
        'notices',
        'empty',
        'scenePreset',
        'publicStateAvailable',
        'state',
        'pickupEnabled',
        'deliveryEnabled',
        'orderingEnabled',
      ])
        key: data[key],
    });

/// Published derivative URL only. No token/query/private Storage URL, external
/// image host, data URL or navigation target can enter the inert preview.
String? storefrontBannerPublicImage(
  Object? value,
  Uri assetBase, {
  bool legacyHero = false,
  Uri? mediaOrigin,
}) {
  if (value is! String || value.isEmpty) return null;
  final parsed = Uri.tryParse(value);
  if (parsed == null ||
      parsed.userInfo.isNotEmpty ||
      parsed.hasQuery ||
      parsed.hasFragment)
    return null;
  final uri = assetBase.resolveUri(parsed);
  if (!['http', 'https'].contains(uri.scheme)) return null;
  final derivative = RegExp(
    r'^/storage/v1/object/public/storefront-media/[0-9a-f]{32}/[0-9a-f]{64}\.webp$',
  ).hasMatch(uri.path);
  final legacy =
      legacyHero &&
      uri.path.startsWith('/storage/v1/object/public/menu-images/') &&
      uri.path.length > '/storage/v1/object/public/menu-images/'.length &&
      !uri.path.contains('..');
  if (!derivative && !legacy) return null;
  final trusted =
      mediaOrigin != null &&
      ['http', 'https'].contains(mediaOrigin.scheme) &&
      mediaOrigin.host.isNotEmpty &&
      mediaOrigin.userInfo.isEmpty &&
      !mediaOrigin.hasQuery &&
      !mediaOrigin.hasFragment &&
      (mediaOrigin.path.isEmpty || mediaOrigin.path == '/') &&
      uri.origin == mediaOrigin.origin;
  return uri.origin == assetBase.origin || trusted ? uri.toString() : null;
}

/// CSSOM-only colours; font and geometry cannot be overridden by a colour map.
Map<String, String> storefrontBannerPreviewColours(Map<String, Object?> data) {
  const names = {
    '--bg',
    '--sf',
    '--sf2',
    '--tx',
    '--tx2',
    '--tx3',
    '--hair',
    '--hair2',
    '--acc',
    '--onacc',
    '--acct',
    '--ok',
    '--warn',
    '--badText',
    '--ring',
    '--accLargeText',
    '--accs',
    '--accOnSelection',
    '--brandSecondary',
    '--hero',
    '--onhero',
    '--onhero2',
    '--badbg',
    '--sceneGlass',
    '--sceneGlassSoft',
    '--sceneLine',
    '--scrim',
    '--promoWarm',
    '--menuChipFrom',
    '--menuChipTo',
    '--menuChipPaintFrom',
    '--menuChipPaintTo',
    '--menuActiveFrom',
    '--menuActiveTo',
    '--menuDockFrom',
    '--menuDockTo',
  };
  final result = <String, String>{};
  for (final entry in _map(data['colours']).entries) {
    final value = _string(entry.value);
    if (names.contains(entry.key) &&
        (RegExp(r'^#[0-9a-fA-F]{3,8}$').hasMatch(value) ||
            RegExp(r'^rgba?\([0-9.,%\s]+\)$').hasMatch(value) ||
            value == 'transparent')) {
      result[entry.key as String] = value;
    }
  }
  return result;
}

String storefrontBannerPreviewFont(Object? family) => switch (family) {
  'system' => "system-ui, 'Segoe UI', Tahoma, sans-serif",
  'alexandria' => '"SF Alexandria", ${storefrontBannerPreviewFont('rubik')}',
  _ =>
    "'SF Rubik Latin', 'SF Rubik Arabic', 'SF Rubik Hebrew', 'Segoe UI', Tahoma, sans-serif",
};

String _svg(String path) =>
    '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="$path"/></svg>';
const _pickup =
    'M4 9.5L5.2 5h13.6L20 9.5M4 9.5h16M4 9.5v9a1.5 1.5 0 001.5 1.5h13a1.5 1.5 0 001.5-1.5v-9M9.5 20v-5h5v5';
const _delivery =
    'M6.5 18.5a2.5 2.5 0 100-5 2.5 2.5 0 000 5zM18.5 18.5a2.5 2.5 0 100-5 2.5 2.5 0 000 5zM9 16h7M16 16l-2-9h-3M6.5 13.5V10h4';
const _cart =
    'M6 6h15l-1.5 9h-12zM6 6L5 3H2M8 21a1 1 0 100-2 1 1 0 000 2zm10 0a1 1 0 100-2 1 1 0 000 2z';
const _phone =
    'm5 3 4 5-2.5 3a15 15 0 0 0 6.5 6.5l3-2.5 5 4c-2 7-20-7-18-13L5 3Z';
const _close = 'M6 6l12 12M18 6L6 18';
const _clock = 'M12 7v5l3 2M12 21a9 9 0 100-18 9 9 0 000 18z';
const _search =
    '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></svg>';
const _suggest =
    '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><rect x="3" y="3" width="18" height="18" rx="5"/><path d="M8 8h.01M16 8h.01M12 12h.01M8 16h.01M16 16h.01" stroke-width="3"/></svg>';
String _tenant(Object? text) => '<span dir="auto">${_escape(text)}</span>';

String _menuTitle(Object? value, String locale) {
  final text = _string(value);
  final word = locale == 'ar'
      ? 'مزاج'
      : locale == 'en'
      ? 'mood'
      : '';
  final at = word.isEmpty ? -1 : text.indexOf(word);
  return at < 0
      ? _escape(text)
      : '${_escape(text.substring(0, at))}<span class="menuAccent">${_escape(word)}</span>${_escape(text.substring(at + word.length))}';
}

// Same validated Unicode-scalar slicing as contentPresentation.headlineParts.
// No trimming/reformatting or UTF-16 indexing of the tenant's saved text.
String _headlineMarkup(String text, Object? rawFormat) {
  if (rawFormat == null) return '<span>${_escape(text)}</span>';
  if (rawFormat is! Map || rawFormat['text'] != text) {
    throw const FormatException('invalid Hero format binding');
  }
  final scalars = text.runes.toList();
  int? offset(Object? value) {
    if (value == null) return null;
    if (value is! num ||
        !value.isFinite ||
        value != value.truncateToDouble() ||
        value < 0 ||
        value > scalars.length) {
      throw const FormatException('invalid Hero scalar offset');
    }
    return value.toInt();
  }

  final highlight = rawFormat['highlight'];
  if (highlight != null && highlight is! Map) {
    throw const FormatException('invalid Hero highlight');
  }
  final start = highlight == null ? null : offset(highlight['start']);
  final end = highlight == null ? null : offset(highlight['end']);
  if (highlight != null && (start == null || end == null)) {
    throw const FormatException('invalid Hero highlight');
  }
  final lineBreak = offset(rawFormat['break_before']);
  final boundaries = <int>{0, scalars.length, ?start, ?end, ?lineBreak}.toList()
    ..sort();
  final result = StringBuffer();
  for (var i = 0; i + 1 < boundaries.length; i++) {
    final at = boundaries[i];
    final highlighted = highlight != null && at >= start! && at < end!;
    if (at == lineBreak) result.write('<br aria-hidden="true">');
    result.write('<span${highlighted ? ' class="heroWord"' : ''}>');
    result.write(
      _escape(String.fromCharCodes(scalars.sublist(at, boundaries[i + 1]))),
    );
    if (highlighted) {
      result.write(
        '<svg viewBox="0 0 320 22" preserveAspectRatio="none" aria-hidden="true" focusable="false"><path d="M3 12C95-3 188 0 312 7M70 20c95-10 155-9 218-7"/></svg>',
      );
    }
    result.write('</span>');
  }
  return result.toString();
}

String _hero(
  Map hero,
  Uri base,
  String suggestionLabel, {
  Uri? mediaOrigin,
  String ghostName = '',
}) {
  final photo = storefrontBannerPublicImage(
    hero['photo'],
    base,
    legacyHero: true,
    mediaOrigin: mediaOrigin,
  );
  final titleText = _string(hero['title']);
  final title = _headlineMarkup(titleText, hero['format']);
  final eyebrow = _string(hero['eyebrow']);
  final subline = _string(hero['subline']);
  final footnote = _string(hero['footnote']);
  final stamp = _string(hero['stamp']);
  final whole = hero['imageFit'] == 'whole-image';
  return '<section class="inner hero" data-sf-module="hero" data-sf-hero-mode="item" aria-labelledby="sf-hero-title">'
      '<div class="heroCopy">${eyebrow.isEmpty ? '' : '<p class="eyebrow flexRow"><span class="littlePin gridCenter" aria-hidden="true"><svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M12 21s-7-6.2-7-11a7 7 0 0114 0c0 4.8-7 11-7 11z"/><circle cx="12" cy="10" r="2.5"/></svg></span>${_tenant(eyebrow)}</p>'}'
      '<h1 class="heroTitle" id="sf-hero-title" aria-label="${_escape(titleText)}"><span dir="auto">$title</span></h1>'
      '${subline.isEmpty ? '' : '<p class="heroSub">${_tenant(subline)}</p>'}'
      '<div class="heroActions flexRow"><button class="promoCta" type="button"${hero['soldOut'] == true ? ' disabled' : ''}>${_escape(hero['cta'])}${_svg('M9 5l7 7-7 7')}</button><button class="suggest">$_suggest${_escape(hero['suggestionLabel'] ?? suggestionLabel)}</button></div>'
      '${footnote.isEmpty ? '' : '<p class="heroSub">${_tenant(footnote)}</p>'}</div>'
      '<div class="heroVisual"><div class="heroGhost" aria-hidden="true">${_tenant(ghostName)}</div>'
      '<svg class="heroMotif" viewBox="0 0 560 460" fill="none" aria-hidden="true"><path d="M465 40c110 80 45 165-9 167S380 110 471 111c106 0 65 216-15 251S254 428 164 426"/><circle cx="466" cy="40" r="5"/><path d="m167 413-14 16 24 1"/></svg>'
      '<div class="heroMedia${whole ? ' wholeFrame' : ''}" data-sf-product="">${photo == null ? '' : '<img class="heroImg imageCover${whole ? ' wholeImage' : ''}" src="${_escape(photo)}" alt="" width="720" height="960" decoding="async" fetchpriority="high">'}${stamp.isEmpty ? '' : '<span class="badge">${_tenant(stamp)}</span>'}</div>'
      '<div class="cardMain flexRow heroProduct"><p class="cardName">${_tenant(hero['name'])}</p><span class="price">${hero['hasOptions'] == true ? '<span class="priceFrom">${_escape(hero['fromLabel'])}</span>' : ''}<span class="ltr" dir="ltr">${_escape(hero['price'])}</span></span></div></div></section>';
}

/// Static, escaped Home header markup. Explicit composition classes reproduce
/// CSS Modules' flexRow/gridCenter because the copied CSS remains untransformed.
String storefrontBannerPreviewDocument(
  Map<String, Object?> data,
  Uri assetBase,
) {
  final locale = ['ar', 'he', 'en'].contains(data['locale'])
      ? data['locale'] as String
      : 'ar';
  final direction = locale == 'en' ? 'ltr' : 'rtl';
  final copy = _map(data['copy']);
  final service = data['service'] is Map ? _map(data['service']) : data;
  String c(String key) => _escape(copy[key]);
  String serviceCopy(Object? flag, String yes, String no) =>
      flag == null && data['publicStateAvailable'] == false
      ? (_string(copy['serviceUnavailable']).isEmpty
            ? '—'
            : c('serviceUnavailable'))
      : c(flag == true ? yes : no);
  final state =
      data['publicStateAvailable'] != false &&
          ['open', 'closed', 'paused'].contains(service['state'])
      ? service['state'] as String
      : 'unknown';
  final stateClass = {
    'open': 'stateOpen',
    'closed': 'stateClosed',
    'paused': 'statePaused',
    'unknown': 'stateUnknown',
  }[state];
  final mediaOrigin = Uri.tryParse(_string(data['mediaOrigin']));
  final banner = storefrontBannerPublicImage(
    data['imageUrl'],
    assetBase,
    mediaOrigin: mediaOrigin,
  );
  final logo = storefrontBannerPublicImage(
    data['logoUrl'],
    assetBase,
    mediaOrigin: mediaOrigin,
  );
  final enabled = data['enabled'] == true && banner != null;
  final showIntro = data['showIntro'] != false;
  final responsive = data['layout'] == 'responsive';
  final phone = data['device'] != 'desktop';
  int dimension(Object? value, int fallback) =>
      value is int && value > 0 && value <= 8192 ? value : fallback;
  final imageWidth = dimension(data['imageWidth'], 960);
  final imageHeight = dimension(data['imageHeight'], 420);
  final hero = _map(data['hero']);
  final hasHero = hero.isNotEmpty;
  final empty = data['empty'] == true;
  final segments = _list(data['segments']).whereType<String>().toList();
  final announcement = _string(data['announcement']);
  final notices = _list(data['notices']);
  final categories = _list(data['categoryNames']);
  final imageOrigins = <String>{
    assetBase.origin,
    for (final value in [
      banner,
      logo,
      storefrontBannerPublicImage(
        hero['photo'],
        assetBase,
        legacyHero: true,
        mediaOrigin: mediaOrigin,
      ),
    ])
      if (value != null) Uri.parse(value).origin,
  }.join(' ');
  final csp =
      "default-src 'none'; script-src 'none'; style-src 'self'; font-src 'self'; img-src $imageOrigins; connect-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'";
  final sheet = assetBase.resolve('home.css');
  final preview = assetBase.resolve('preview.css');
  final fonts = assetBase.resolve('fonts.css');
  return '<!doctype html><html lang="$locale" dir="$direction"><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<meta http-equiv="Content-Security-Policy" content="${_escape(csp)}">'
      '<title>Storefront banner preview</title>'
      '<link rel="stylesheet" href="${_escape(sheet.toString())}">'
      '<link rel="stylesheet" href="${_escape(fonts.toString())}">'
      '<link rel="stylesheet" href="${_escape(preview.toString())}"></head>'
      '<body inert><div class="root variables previewRoot" data-banner-preview-root="" ${data['scenePreset'] == 'reference_dark' ? 'data-sf-scene="reference_dark"' : ''}>'
      '<main class="page previewSurface" data-sf-screen="home"><div class="topScene" data-sf-menu-top="" ${enabled ? 'data-sf-has-banner=""' : ''}>'
      '<header class="header" data-sf-module="compact"><div class="inner headerInner flexRow">'
      '<a class="brandLink"><div class="lockup flexRow">${logo == null ? '' : '<img class="brandLogo" src="${_escape(logo)}" alt="" width="84" height="84" decoding="async">'}'
      '<span class="lockupText"><span class="brandName">${_tenant(data['displayName'])}</span><span class="brandCity">${_tenant(data['city'])}</span></span></div></a>'
      '<nav class="headerNav flexRow"><a>${c('menuLabel')}</a><button>${c('chefPicks')}</button><a>${c('findUs')}</a></nav>'
      '<div class="headerActions flexRow">${data['phoneAvailable'] == true ? '<a class="headerPhone gridCenter">${_svg(_phone)}</a>' : ''}'
      '<details class="langWrap"><summary class="langControl gridCenter"><span>${const {'ar': 'ع', 'he': 'עב', 'en': 'EN'}[locale]}</span></summary></details>'
      '<button class="cartTrigger"><span class="cartGlyph cartGlyph">${_svg(_cart)}<b>0</b></span><span class="headerTotal headerTotal" dir="ltr">₪0</span><span class="srOnly">${c('cartLabel')}</span></button>'
      '</div></div></header>'
      '<div class="orderStatus inner" data-sf-order-status=""><span data-state="$state" class="$stateClass"><i class="stateDot" aria-hidden="true"></i>${state == 'unknown' ? (_string(copy['stateUnavailable']).isEmpty ? '—' : c('stateUnavailable')) : c(state == 'open' ? 'openNow' : state)}</span>'
      '<span>${_svg(_pickup)}${serviceCopy(service['pickupEnabled'], 'pickup', 'pickupOff')}</span>'
      '<span>${_svg(_delivery)}${serviceCopy(service['deliveryEnabled'], 'delivery', 'deliveryOff')}</span></div>'
      '${showIntro && hasHero ? _hero(hero, assetBase, _string(copy['suggestLabel']), mediaOrigin: mediaOrigin, ghostName: _string(data['displayName'])) : ''}'
      '${announcement.isEmpty ? '' : '<div class="announce flexRow" data-sf-module="announce"><span aria-hidden="true">✦</span><span dir="auto">${segments.isEmpty ? _tenant(announcement) : segments.map(_tenant).join('<span aria-hidden="true"> ✦ </span>')}</span><span aria-hidden="true">✦</span><button class="announceClose gridCenter">${_svg(_close)}</button></div>'}'
      '${notices.isEmpty ? '' : '<div class="notices">${notices.map((n) {
              final notice = _map(n);
              return '<div class="notice"><span class="noticeIcon" aria-hidden="true">${_svg(_clock)}</span><span class="noticeCopy"><span class="noticeTitle">${_escape(notice['title'])}</span><span class="noticeBody">${_tenant(notice['body'])}</span></span></div>';
            }).join()}</div>'}'
      '${enabled ? '<div class="menuBanner${responsive ? ' responsiveBanner' : ''}" data-sf-menu-banner="" ${responsive ? 'data-sf-banner-device="${phone ? 'phone' : 'desktop'}"' : ''} aria-hidden="true"><img id="banner-photo" src="${_escape(banner)}" alt="" width="${responsive ? imageWidth : 960}" height="${responsive ? imageHeight : 420}" decoding="async" fetchpriority="high"></div>' : ''}'
      '${enabled && !responsive ? '<div class="sceneWindow" data-sf-scene-window="" ${showIntro && hasHero ? 'data-sf-hero=""' : ''} aria-hidden="true"></div>' : ''}'
      '${empty ? '' : '<div class="inner topControls menuHeading">${showIntro ? '<div class="menuIntro"><p class="eyebrow flexRow">${_escape(data['eyebrow'])}<span>${_escape(data['menuCaption'])}</span></p><h2>${_menuTitle(data['menuHeading'], locale)}</h2></div>' : ''}<div class="searchControls"><div class="searchBox flexRow" role="search">$_search<input type="search" placeholder="${_escape(data['searchText'])}" tabindex="-1"><kbd aria-hidden="true">/</kbd></div>${hasHero ? '' : '<div class="suggestionSlot"><button class="suggest">$_suggest${c('suggestLabel')}</button></div>'}</div></div>'}'
      '</div>${empty ? '' : '<section class="inner menu"><div class="categoryWrap" data-preview-categories=""><nav class="rail" data-sf-module="categories">${categories.indexed.map((entry) {
              final raw = entry.$2;
              final name = raw is Map ? raw['name'] : raw;
              return '<button class="chip ${entry.$1 == 0 ? 'chipActive' : ''}">${_svg(_pickup)}<span dir="auto">${_escape(name)}</span><small dir="ltr">00</small></button>';
            }).join()}</nav></div></section>'}'
      '</main></div></body></html>';
}
