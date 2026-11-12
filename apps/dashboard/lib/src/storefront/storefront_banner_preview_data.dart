import '../format/money_format.dart';
import 'storefront_color_picker.dart';
import 'storefront_contrast.dart';
import 'storefront_content_unicode.dart' as unicode;
import 'storefront_models.dart';
import 'storefront_profile_repository.dart' show isStorefrontBannerPreviewMenu;

/// Draft-only data for the menu's upper scene. No IO, saved-value mutation,
/// ordering authority, or new image/publication operation lives here.
Map<String, Object?> storefrontBannerPreviewData({
  required StorefrontProfile profile,
  required Map<String, dynamic> document,
  required Map<String, dynamic>? publishedMenu,
  required Uri? logoUrl,
  required StorefrontColorSample colorSample,
  required String locale,
}) {
  final language = const {'ar', 'he', 'en'}.contains(locale)
      ? locale
      : profile.localeDefault.name;
  final m = _copy[language]!;
  final appearance = _object(document['appearance']);
  final siteTheme = const {'light', 'dark'}.contains(appearance['site_theme'])
      ? appearance['site_theme'] as String
      : null;
  final scene = appearance['scene_preset'] == 'reference_dark'
      ? 'reference_dark'
      : null;
  final font =
      const {
        'rubik',
        'alexandria',
        'system',
      }.contains(appearance['font_family'])
      ? appearance['font_family'] as String
      : 'rubik';
  final sample = StorefrontColorSample(
    background: colorSample.background,
    accent: colorSample.accent,
    text: appearance.containsKey('text_color')
        ? _text(appearance['text_color'])
        : colorSample.text,
    buttonText: appearance.containsKey('button_text_color')
        ? _text(appearance['button_text_color'])
        : colorSample.buttonText,
  );
  final available = isStorefrontBannerPreviewMenu(publishedMenu, profile.slug);
  final menu = available ? publishedMenu! : const <String, dynamic>{};
  final wireService = _object(menu['service']);
  final service = available
      ? <String, Object?>{
          'state': wireService['state'],
          'pickupEnabled': wireService['pickup_enabled'],
          'deliveryEnabled': wireService['delivery_enabled'],
          'orderingEnabled': wireService['ordering_enabled'],
        }
      : null;
  final state = service?['state'];
  final categories = _objects(menu['categories']);
  final items = _objects(menu['items']);
  final categoryIds = categories
      .map((c) => c['id'])
      .whereType<String>()
      .toSet();
  final heroDraft = _object(document['hero']);
  final heroItem = heroDraft['mode'] == 'item'
      ? items
            .where(
              (i) =>
                  i['id'] == heroDraft['item_id'] &&
                  categoryIds.contains(i['category_id']),
            )
            .firstOrNull
      : null;
  final heroTitle =
      _text(document['hero_headline']) ??
      profile.tagline ??
      profile.displayName;
  final notices = <Map<String, String>>[];
  if (state == 'closed') {
    final hours = _object(menu['hours']);
    final opens = _text(hours['opens']), closes = _text(hours['closes']);
    // Do not turn next_open into the operator computer's local timezone.
    // Without today's server window use the same complete no-hours sentence.
    final hasWindow = _clock(opens) && _clock(closes);
    notices.add({
      'title': m['closedTitle']!,
      'body': hasWindow
          ? _fill(m['closedBody']!, {'t': opens!})
          : m['closedBodyNoHours']!,
    });
  } else if (state == 'paused') {
    notices.add({
      'title': m['pausedTitle']!,
      'body': _fill(m['pausedBody']!, {'r': profile.displayName}),
    });
  } else if (state == 'open' && service?['orderingEnabled'] == false) {
    notices.add({
      'title': m['orderingOfflineTitle']!,
      'body': m['orderingOfflineBody']!,
    });
  }
  final showIntro = appearance['menu_intro_visible'] != false;
  final amount = heroItem?['base_price_minor'];
  final price =
      amount is int &&
          amount >= 0 &&
          _object(menu['restaurant'])['currency_code'] == 'ILS'
      ? MoneyFormatter.formatMinor(
          amount,
          'ILS',
        ).replaceFirst(RegExp(r'\.00$'), '')
      : null;
  final segments = state == 'open'
      ? _strings(document['announcement_segments'])
      : <String>[];
  final result = <String, Object?>{
    'enabled': appearance['menu_banner_enabled'] == true,
    'showIntro': showIntro,
    'displayName': profile.displayName,
    'city': profile.publicCity ?? '',
    'phoneAvailable': _phoneAvailable(profile.publicPhone),
    'logoUrl': logoUrl?.toString(),
    'locale': language,
    'fontFamily': font,
    'siteTheme': siteTheme,
    'scenePreset': scene,
    'empty': available && items.isEmpty,
    'colours': _colours(sample, siteTheme, scene),
    'publicStateAvailable': available,
    'service': service,
    'state': state,
    'pickupEnabled': service?['pickupEnabled'],
    'deliveryEnabled': service?['deliveryEnabled'],
    'orderingEnabled': service?['orderingEnabled'],
    'announcement': state == 'open'
        ? _text(document['announcement_text'])
        : null,
    'segments': segments,
    'menuHeading': m['menuHeading'],
    'eyebrow': m['menuEyebrow'],
    'menuCaption': m['menuCaption'],
    'searchText': m['searchPh'],
    'categoryNames': categories
        .map((c) => _text(c['name']))
        .whereType<String>()
        .toList(),
    'copy': <String, String>{
      for (final entry in _frameCopy.entries) entry.key: m[entry.value]!,
    },
    'notices': notices,
    if (heroItem != null)
      'hero': <String, Object?>{
        'title': heroTitle,
        'subline': _text(document['hero_subline']) ?? '',
        'eyebrow': _text(heroDraft['eyebrow']) ?? m['heroEyebrow'],
        'footnote': _text(heroDraft['footnote']),
        'format': _heroFormat(heroDraft['format'], heroTitle),
        'stamp': _text(heroDraft['stamp']),
        'imageFit': _heroImageFit(document, heroItem),
        'hasOptions': _heroHasOptions(menu, heroItem['id']),
        'soldOut': heroItem['availability'] == 'unavailable',
        'fromLabel': m['from'],
        // Canonical public path stays unguessed; the editor supplies its actual origin.
        'photo': _publicPhoto(heroItem['image_url']),
        'name': _text(heroItem['name']) ?? '',
        'price': price,
        'cta': heroItem['availability'] == 'available'
            ? m['orderNow']
            : m['soldOut'],
        'suggestionLabel': m['suggestItem'],
      },
  };
  return result;
}

Map<String, Object?>? _heroFormat(Object? value, String title) {
  if (value is! Map ||
      value.length != 3 ||
      !const ['text', 'highlight', 'break_before'].every(value.containsKey) ||
      value['text'] != title) {
    return null;
  }
  final highlight = value['highlight'];
  int? start, end;
  if (highlight != null) {
    if (highlight is! Map ||
        highlight.length != 2 ||
        highlight['start'] is! int ||
        highlight['end'] is! int) {
      return null;
    }
    start = highlight['start'] as int;
    end = highlight['end'] as int;
  }
  final lineBreak = value['break_before'];
  if ((lineBreak != null && lineBreak is! int) ||
      (start == null && lineBreak == null) ||
      !unicode.heroFormatValid(title, start, end, lineBreak as int?)) {
    return null;
  }
  return {
    'text': title,
    'highlight': start == null ? null : {'start': start, 'end': end},
    'break_before': lineBreak,
  };
}

String _heroImageFit(Map<String, dynamic> document, Map<String, dynamic> item) {
  String? fit(Object? value) =>
      const {'fill', 'whole-image'}.contains(value) ? value as String : null;
  // The real adapter constructs maps, so the last matching row owns its value.
  final own = _objects(
    document['item_presentation'],
  ).where((row) => row['item_id'] == item['id']).lastOrNull;
  final category = _objects(
    document['category_presentation'],
  ).where((row) => row['category_id'] == item['category_id']).lastOrNull;
  return fit(own?['image_fit']) ?? fit(category?['image_fit']) ?? 'fill';
}

bool _heroHasOptions(Map<String, dynamic> menu, Object? itemId) {
  final options = _objects(menu['modifier_options']);
  return _objects(menu['modifiers']).any((group) {
    if (group['item_id'] != itemId ||
        !const {'single', 'multiple'}.contains(group['selection_type']) ||
        group['is_required'] is! bool ||
        group['min_select'] is! int) {
      return false;
    }
    // Same admission as adapter.ts: optional empty multiple groups disappear;
    // a required/single group remains even when it has no valid options.
    return group['selection_type'] == 'single' ||
        group['is_required'] == true ||
        (group['min_select'] as int) > 0 ||
        options.any((option) => option['modifier_id'] == group['id']);
  });
}

Map<String, dynamic> _object(Object? value) => value is Map
    ? <String, dynamic>{
        for (final entry in value.entries)
          if (entry.key is String) entry.key as String: entry.value,
      }
    : <String, dynamic>{};
List<Map<String, dynamic>> _objects(Object? value) =>
    value is List ? value.whereType<Map>().map(_object).toList() : [];
List<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toList() : [];
String? _text(Object? value) => value is String ? value : null;
bool _clock(String? value) =>
    value != null && RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value);
String _fill(String template, Map<String, String> values) => template
    .replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) => values[m[1]] ?? m[0]!);
// Same published-phone grammar as storefront/src/source/publicPhone.ts.
// Return presence only; no phone number or callable contact is sent to the frame.
bool _phoneAvailable(String? value) =>
    value != null &&
    value.length <= 32 &&
    !RegExp(r'[^+0-9 -]').hasMatch(value) &&
    RegExp(
      r'^(?:\+[1-9][0-9]{6,14}|0[0-9]{1,2}[- ]?[0-9]{3}[- ]?[0-9]{4})$',
    ).hasMatch(value);
String? _publicPhoto(Object? value) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty ||
      (uri.hasScheme && uri.scheme != 'https' && uri.scheme != 'http') ||
      !RegExp(
        r'^/storage/v1/object/public/(storefront-media|restaurant-logos|menu-images)/',
      ).hasMatch(uri.path))
    return null;
  return value;
}

// Render-only port of buildCinematicTheme -> buildSiteTheme -> buildMenuBrand.
// Uses the existing contrast/RGB primitives; no stored colour is rewritten.
Map<String, String> _colours(
  StorefrontColorSample sample,
  String? theme,
  String? scene,
) {
  const aa = kStorefrontContrastAa;
  String? colour(String? v) => v != null && isStorefrontHex(v)
      ? storefrontRgbToHex(storefrontHexToRgb(v))
      : null;
  String? appearanceColour(String? v) =>
      v != null && v.length == 7 ? colour(v) : null;
  final primary = colour(sample.background),
      accent = colour(sample.accent) ?? '#e4ad83';
  final explicit = theme != null, light = theme == 'light';
  final darkBase =
      explicit && primary != null && storefrontContrast('#ffffff', primary) < aa
      ? '#151513'
      : primary;
  final bg = light
      ? '#ffffff'
      : scene == 'reference_dark'
      ? '#151515'
      : darkBase ?? '#151513';
  final automatic =
      storefrontContrast('#ffffff', bg) >= storefrontContrast('#000000', bg)
      ? '#ffffff'
      : '#000000';
  String surface(double fraction) {
    final candidate = _mix(
      bg,
      automatic == '#ffffff' ? '#ffffff' : '#000000',
      fraction,
    );
    return storefrontContrast(automatic, candidate) >= aa
        ? candidate
        : _mix(bg, automatic == '#ffffff' ? '#000000' : '#ffffff', fraction);
  }

  final sf = light ? '#ffffff' : surface(.03),
      sf2 = light ? '#f5f6f7' : surface(.07);
  final copySurfaces = [bg, sf, sf2];
  final explicitText = appearanceColour(sample.text),
      explicitButton = appearanceColour(sample.buttonText);
  final defaultInk = light ? '#202124' : '#ffffff';
  final selection = _mix(accent, sf, .91);
  final accs = explicit
      ? (storefrontContrast(defaultInk, selection) >= aa ? selection : sf)
      : _mix(accent, sf, .82);
  final surfaces = [...copySurfaces, if (explicit) accs];
  final tx = explicit
      ? (explicitText != null &&
                surfaces.every((c) => storefrontContrast(explicitText, c) >= aa)
            ? explicitText
            : defaultInk)
      : explicitText ??
            (copySurfaces.every((c) => storefrontContrast('#f7f2ea', c) >= aa)
                ? '#f7f2ea'
                : automatic);
  String muted(double fraction) {
    if (!explicit && explicitText != null) return explicitText;
    var ink = _mix(tx, bg, fraction);
    for (final c in surfaces) {
      ink = _walk(ink, c, aa, explicit ? defaultInk : automatic);
    }
    return ink;
  }

  final legacyButton = storefrontContrast('#FFFFFF', accent) >= aa
      ? '#FFFFFF'
      : '#0B1512';
  final autoButton = storefrontContrast(legacyButton, accent) >= aa
      ? legacyButton
      : storefrontContrast('#000000', accent) >=
            storefrontContrast('#ffffff', accent)
      ? '#000000'
      : '#ffffff';
  final onacc = explicit
      ? (explicitButton != null &&
                storefrontContrast(explicitButton, accent) >= aa
            ? explicitButton
            : autoButton)
      : explicitButton ?? legacyButton;
  final tx2 = muted(.2), tx3 = muted(.34);
  final toward = explicit ? defaultInk : automatic;
  final tokens = <String, String>{
    '--bg': bg,
    '--sf': sf,
    '--sf2': sf2,
    '--tx': tx,
    '--tx2': tx2,
    '--tx3': tx3,
    '--hair': _rgba(tx, .12),
    '--hair2': _rgba(tx, .24),
    '--hero': bg,
    '--onhero': explicit ? tx : explicitButton ?? tx,
    '--onhero2': tx2,
    '--acc': accent,
    '--onacc': onacc,
    '--acct': _walk(accent, sf, aa, toward),
    '--accLargeText': _walk(accent, bg, 3, toward),
    '--accs': accs,
    '--accA': explicit ? accs : _rgba(accent, .16),
    '--accOnSelection': _walk(
      accent,
      accs,
      aa,
      explicit
          ? defaultInk
          : storefrontContrast('#ffffff', accs) >=
                storefrontContrast('#000000', accs)
          ? '#ffffff'
          : '#000000',
    ),
    '--cta': accent,
    '--glass': _rgba(bg, explicit ? .96 : .9),
    '--glassDock': _rgba(bg, explicit ? .98 : .96),
    '--onDock2': tx2,
    '--glassLine': _rgba(tx, .14),
    if (explicit || scene == 'reference_dark') ...{
      '--sceneGlass': _rgba(bg, explicit ? .92 : .76),
      '--sceneGlassSoft': _rgba(
        explicit ? sf2 : '#252525',
        explicit ? .94 : .8,
      ),
      '--sceneLine': _rgba(tx, explicit ? .2 : .18),
    },
  };
  // The brand layer checks every gradient stop and its translucent photo bed.
  final secondary = primary ?? tx;
  final brandInk =
      storefrontContrast('#ffffff', sf) >= storefrontContrast('#000000', sf)
      ? '#ffffff'
      : '#000000';
  List<String> gradient(String from, String to, String copy, String fallback) =>
      List.generate(
        21,
        (i) => _mix(from, to, i / 20),
      ).every((c) => storefrontContrast(copy, c) >= aa + .02)
      ? [from, to]
      : [fallback, fallback];
  final chip = gradient(
    _mix(accent, sf, .93),
    _mix(secondary, sf, .95),
    tx,
    sf,
  );
  final stops = List.generate(21, (i) => _mix(chip[0], chip[1], i / 20));
  final chipAlpha =
      [.88, .96, 1.0]
          .where(
            (a) => stops.every(
              (s) => [
                '#000000',
                '#ffffff',
              ].every((b) => storefrontContrast(tx, _mix(b, s, a)) >= aa + .02),
            ),
          )
          .firstOrNull ??
      1.0;
  final dock = gradient(_mix(accent, sf, .76), sf, tx, sf);
  final darker = _mix(accent, '#000000', .1),
      lighter = _mix(accent, '#ffffff', .1);
  final active = gradient(
    storefrontContrast(onacc, darker) >= storefrontContrast(onacc, lighter)
        ? darker
        : lighter,
    accent,
    onacc,
    accent,
  );
  tokens.addAll({
    '--brandSecondary': _walk(secondary, sf, aa, brandInk),
    '--menuChipFrom': chip[0],
    '--menuChipTo': chip[1],
    '--menuChipPaintFrom': _rgba(chip[0], chipAlpha),
    '--menuChipPaintTo': _rgba(chip[1], chipAlpha),
    '--menuDockFrom': dock[0],
    '--menuDockTo': dock[1],
    '--menuActiveFrom': active[0],
    '--menuActiveTo': active[1],
  });
  return tokens;
}

String _mix(String a, String b, double fraction) {
  final first = storefrontHexToRgb(a), second = storefrontHexToRgb(b);
  return storefrontRgbToHex([
    for (var i = 0; i < 3; i++) first[i] + (second[i] - first[i]) * fraction,
  ]);
}

String _walk(String colour, String background, double floor, String toward) {
  for (var t = 0.0; t <= 1.0001; t += .05) {
    final value = _mix(colour, toward, t);
    if (storefrontContrast(value, background) >= floor) return value;
  }
  return toward;
}

String _rgba(String colour, double alpha) {
  final rgb = storefrontHexToRgb(colour);
  final a = alpha == alpha.truncateToDouble()
      ? alpha.toInt().toString()
      : alpha.toString();
  return 'rgba(${rgb[0]},${rgb[1]},${rgb[2]},$a)';
}

const _frameCopy = <String, String>{
  'openNow': 'openNow',
  'closed': 'closed',
  'paused': 'paused',
  'pickup': 'pickup',
  'pickupOff': 'pickupOff',
  'delivery': 'delivery',
  'deliveryOff': 'deliveryOff',
  'menuLabel': 'menuLabel',
  'chefPicks': 'chefPicks',
  'findUs': 'findUs',
  'callRestaurant': 'callRestaurant',
  'cartLabel': 'cart',
  'language': 'langLabel',
  'suggestLabel': 'suggestItem',
  'stateUnavailable': 'unavailableNow',
  'serviceUnavailable': 'unavailableNow',
};

// Exact feature-local subset of storefront/messages/storefront.{ar,he,en}.json.
// No shared Dashboard localization or merchant value is changed.
const _copy = <String, Map<String, String>>{
  'ar': {
    'openNow': "مفتوح الآن",
    'closed': "مغلق",
    'paused': "الطلبات متوقفة مؤقتاً",
    'pickup': "استلام من المطعم",
    'pickupOff': "الاستلام غير متاح",
    'delivery': "توصيل",
    'deliveryOff': "التوصيل غير متاح",
    'menuLabel': "المنيو",
    'chefPicks': "اختيارات المطبخ",
    'findUs': "وين تلاقينا؟",
    'callRestaurant': "اتصال بالمطعم",
    'cart': "سلتك",
    'langLabel': "اللغة",
    'suggestItem': "محتار؟ اختارلي!",
    'unavailableNow': "غير متاح الآن",
    'menuHeading': "على أي مزاج اليوم؟",
    'menuEyebrow': "خريطة الطعم",
    'menuCaption': "القائمة",
    'searchPh': "دوّر على لقمتك المفضّلة…",
    'heroEyebrow': "وصلت للمكان الصح",
    'orderNow': "اطلب الآن",
    'from': "من",
    'soldOut': "غير متوفر",
    'closedTitle': "مغلق حالياً",
    'closedBody': "يفتح المطعم في {t}.",
    'closedBodyNoHours': "القائمة متاحة للتصفّح.",
    'pausedTitle': "الطلبات متوقفة مؤقتاً",
    'pausedBody': "القائمة متاحة للتصفّح.",
    'orderingOfflineTitle': "الطلب الإلكتروني غير متاح",
    'orderingOfflineBody': "القائمة للتصفّح فقط.",
  },
  'he': {
    'openNow': "פתוח עכשיו",
    'closed': "סגור",
    'paused': "ההזמנות מושהות",
    'pickup': "איסוף עצמי",
    'pickupOff': "איסוף לא זמין",
    'delivery': "משלוח",
    'deliveryOff': "משלוח לא זמין",
    'menuLabel': "התפריט",
    'chefPicks': "בחירת המטבח",
    'findUs': "איפה אנחנו?",
    'callRestaurant': "התקשרות למסעדה",
    'cart': "העגלה שלך",
    'langLabel': "שפה",
    'suggestItem': "מתלבטים? נבחר לכם!",
    'unavailableNow': "לא זמין כעת",
    'menuHeading': "מה מתחשק היום?",
    'menuEyebrow': "מפת הטעמים",
    'menuCaption': "כל המנות",
    'searchPh': "חפשו את הביס האהוב…",
    'heroEyebrow': "הגעתם למקום הנכון",
    'orderNow': "להזמנה",
    'from': "מ־",
    'soldOut': "נגמר",
    'closedTitle': "סגור כעת",
    'closedBody': "המסעדה נפתחת ב־{t}.",
    'closedBodyNoHours': "אפשר לעיין בתפריט.",
    'pausedTitle': "ההזמנות מושהות",
    'pausedBody': "אפשר לעיין בתפריט.",
    'orderingOfflineTitle': "הזמנה מקוונת אינה זמינה",
    'orderingOfflineBody': "התפריט זמין לעיון בלבד.",
  },
  'en': {
    'openNow': "Open now",
    'closed': "Closed",
    'paused': "Ordering paused",
    'pickup': "Pickup",
    'pickupOff': "Pickup unavailable",
    'delivery': "Delivery",
    'deliveryOff': "Delivery unavailable",
    'menuLabel': "The menu",
    'chefPicks': "Chosen by the kitchen",
    'findUs': "Find us",
    'callRestaurant': "Call restaurant",
    'cart': "Your cart",
    'langLabel': "Language",
    'suggestItem': "Can't decide? Pick for me!",
    'unavailableNow': "Unavailable now",
    'menuHeading': "What are you in the mood for?",
    'menuEyebrow': "A map of flavour",
    'menuCaption': "THE MENU",
    'searchPh': "Find your favourite bite…",
    'heroEyebrow': "You've found the right place",
    'orderNow': "Order now",
    'from': "from",
    'soldOut': "Sold out",
    'closedTitle': "Closed right now",
    'closedBody': "The restaurant opens at {t}.",
    'closedBodyNoHours': "The menu is available to browse.",
    'pausedTitle': "Ordering is paused",
    'pausedBody': "The menu is available to browse.",
    'orderingOfflineTitle': "Online ordering is unavailable",
    'orderingOfflineBody': "Menu browsing only.",
  },
};
