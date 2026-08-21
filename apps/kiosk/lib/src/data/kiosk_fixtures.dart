import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show IconData;

/// KIOSK-001 Phase 1 fixture data + the shared kiosk MENU VIEW-MODEL types.
///
/// The fixture half mirrors the demo dataset embedded in the approved artifact
/// (`Kiosk Prototype v2.dc.html`): the EMBER Burger House brand, five
/// categories, the mandatory pricing fixture (burger base 40.00 ILS with a
/// required weight group: 120g included · 240g +15.00 · 360g +25.00), option
/// sets, and the busy-floor table zones. Item/option names are TENANT DATA in
/// production (a single stored string), so fixtures carry them as data maps —
/// they are deliberately NOT l10n keys, matching how the POS treats menu
/// content.
///
/// Phase 3: the SAME classes are also the UI contract for the LIVE
/// `kiosk_menu`/`kiosk_tables` reads — the live mapper populates them from the
/// server envelope ([KioskText3.same]: a live name is one tenant string in
/// every language). The approved V2 screens render one shape either way, so
/// fixture (demo) and live (real) mode can never drift visually.
///
/// All money is INTEGER MINOR UNITS (D-007). The fixture currency is ILS
/// (exponent 2, symbol ₪) to match the approved design's price rendering.
@immutable
class KioskText3 {
  const KioskText3({required this.en, required this.he, required this.ar});

  /// A LIVE tenant string: production menu content is a single stored string,
  /// shown verbatim in every UI language (exactly how the POS renders it).
  const KioskText3.same(String value) : en = value, he = value, ar = value;

  final String en;
  final String he;
  final String ar;

  String of(String lang) => switch (lang) {
    'he' => he,
    'ar' => ar,
    _ => en,
  };
}

@immutable
class KioskFixtureOption {
  const KioskFixtureOption({
    required this.id,
    required this.name,
    required this.priceDeltaMinor,
    this.kitchenMeat,
  });
  final String id;
  final KioskText3 name;

  /// Signed integer minor units added to the unit price when selected.
  final int priceDeltaMinor;

  /// LIVE only: the option's opaque preparation snapshot source served by
  /// `kiosk_menu` (the 021 frozen-prep contract). Carried untouched so the
  /// future submit phase can build the payload; nothing renders it.
  final Map<String, dynamic>? kitchenMeat;
}

enum KioskGroupType { single, multi }

@immutable
class KioskFixtureGroup {
  const KioskFixtureGroup({
    required this.id,
    required this.type,
    required this.isRequired,
    this.maxSelect,
    this.minSelect = 0,
    this.allowQuantity = false,
    this.maxQuantity,
    this.displayName,
    required this.options,
  });
  final String id;
  final KioskGroupType type;
  final bool isRequired;

  /// Only meaningful for [KioskGroupType.multi].
  final int? maxSelect;

  /// LIVE server rule (fixtures encode required-ness via [isRequired] only).
  final int minSelect;

  /// LIVE server rules, carried for the submit phase. The approved V2 item
  /// sheet has no per-option quantity steppers, so every selection is
  /// quantity 1 — always a legal configuration under these rules.
  final bool allowQuantity;
  final int? maxQuantity;

  /// LIVE only: the tenant group name. Fixtures keep the l10n heading keyed
  /// by [id]; live groups show this string verbatim.
  final KioskText3? displayName;
  final List<KioskFixtureOption> options;

  /// The POS effective-rule mirror (the server enforces the same at submit):
  /// single ⇒ exactly one pick; a required multiple with min 0 ⇒ at least one.
  int get effectiveMin => type == KioskGroupType.single
      ? 1
      : (isRequired && minSelect == 0 ? 1 : minSelect);
  int? get effectiveMax => type == KioskGroupType.single ? 1 : maxSelect;
}

@immutable
class KioskFixtureItem {
  const KioskFixtureItem({
    required this.id,
    required this.name,
    required this.description,
    required this.basePriceMinor,
    required this.groupIds,
    this.imageAsset,
    this.imagePath,
    this.available = true,
    this.availabilityReason,
  });
  final String id;
  final KioskText3 name;
  final KioskText3 description;
  final int basePriceMinor;
  final List<String> groupIds;

  /// Fixture image asset path, or null for the approved no-photo treatment.
  final String? imageAsset;

  /// LIVE only: the server storage object key. NOT renderable in Phase 3 —
  /// the menu-image read policy is deliberately POS-only until the kiosk
  /// media phase — so the approved no-photo treatment renders instead.
  final String? imagePath;

  /// LIVE availability: an unavailable item stays visible but cannot be
  /// added (server refuses it at submit anyway).
  final bool available;
  final String? availabilityReason;
}

@immutable
class KioskFixtureCategory {
  const KioskFixtureCategory({
    required this.id,
    required this.name,
    required this.items,
    this.thumbAsset,
    this.iconKind,
    this.iconData,
  });
  final String id;
  final KioskText3 name;
  final List<KioskFixtureItem> items;

  /// Wheel disc photo, or null → glyph disc ([iconKind]: 'drink'|'dessert').
  final String? thumbAsset;
  final String? iconKind;

  /// LIVE only: the owner-chosen glyph resolved from the category's
  /// `icon_key` through the shared registry; null/unknown keys fall back to
  /// the stable Phase-1 glyph treatment.
  final IconData? iconData;
}

enum KioskTableState { available, occupied, reserved, outOfService }

@immutable
class KioskFixtureTable {
  const KioskFixtureTable({
    required this.label,
    required this.seats,
    required this.state,
    this.id,
  });
  final String label;
  final int seats;
  final KioskTableState state;

  /// LIVE only: the server table id the future submit phase will send.
  final String? id;
}

@immutable
class KioskFixtureZone {
  const KioskFixtureZone({
    required this.id,
    required this.tables,
    this.displayName,
  });

  /// l10n key discriminator: 'hall' | 'patio' | 'bar' (fixtures), or an
  /// opaque live section id.
  final String id;
  final List<KioskFixtureTable> tables;

  /// LIVE only: the tenant section name, shown verbatim; fixtures keep the
  /// l10n zone labels keyed by [id].
  final String? displayName;
}

/// Brand block — the artifact's demo brand. Wordmark stays Latin in every
/// language (V2 rule); the tagline localizes via l10n.
abstract final class KioskBrand {
  static const wordmark = 'EMBER';
  static const wordmarkSuffix = '.';
  static const subtitle = 'BURGER HOUSE';
  static const deviceLabel = 'KIOSK-01';
}

const String _imgSmash = 'assets/fixtures/fixture_smash.png';
const String _imgDouble = 'assets/fixtures/fixture_double.png';
const String _imgGarden = 'assets/fixtures/fixture_garden.png';
const String _imgFries = 'assets/fixtures/fixture_fries.png';
const String _imgBombs = 'assets/fixtures/fixture_bombs.png';
const String _imgMeal = 'assets/fixtures/fixture_meal.png';

const List<String> kioskAttractAssets = [
  'assets/fixtures/fixture_attract_1.png',
  'assets/fixtures/fixture_attract_2.png',
];

/// Option sets, exactly the artifact's OPTSETS (ids, order, deltas).
const Map<String, KioskFixtureGroup> kioskFixtureGroups = {
  'weight': KioskFixtureGroup(
    id: 'weight',
    type: KioskGroupType.single,
    isRequired: true,
    options: [
      KioskFixtureOption(
        id: 'w120',
        name: KioskText3(
          en: '120g · Classic',
          he: '120 גרם · קלאסי',
          ar: '120غ · كلاسيك',
        ),
        priceDeltaMinor: 0,
      ),
      KioskFixtureOption(
        id: 'w240',
        name: KioskText3(
          en: '240g · Double',
          he: '240 גרם · כפול',
          ar: '240غ · دبل',
        ),
        priceDeltaMinor: 1500,
      ),
      KioskFixtureOption(
        id: 'w360',
        name: KioskText3(
          en: '360g · Beast',
          he: '360 גרם · ענק',
          ar: '360غ · وحش',
        ),
        priceDeltaMinor: 2500,
      ),
    ],
  ),
  'side': KioskFixtureGroup(
    id: 'side',
    type: KioskGroupType.single,
    isRequired: true,
    options: [
      KioskFixtureOption(
        id: 'sd1',
        name: KioskText3(en: 'Fries', he: 'צ׳יפס', ar: 'بطاطا'),
        priceDeltaMinor: 0,
      ),
      KioskFixtureOption(
        id: 'sd2',
        name: KioskText3(
          en: 'Potato Bombs',
          he: 'פצצות תפו״ד',
          ar: 'قنابل البطاطا',
        ),
        priceDeltaMinor: 600,
      ),
      KioskFixtureOption(
        id: 'sd3',
        name: KioskText3(en: 'Side Salad', he: 'סלט', ar: 'سلطة'),
        priceDeltaMinor: 0,
      ),
    ],
  ),
  'drink': KioskFixtureGroup(
    id: 'drink',
    type: KioskGroupType.single,
    isRequired: true,
    options: [
      KioskFixtureOption(
        id: 'dr1',
        name: KioskText3(en: 'Cola', he: 'קולה', ar: 'كولا'),
        priceDeltaMinor: 0,
      ),
      KioskFixtureOption(
        id: 'dr2',
        name: KioskText3(en: 'Cola Zero', he: 'קולה זירו', ar: 'كولا زيرو'),
        priceDeltaMinor: 0,
      ),
      KioskFixtureOption(
        id: 'dr3',
        name: KioskText3(en: 'Craft Lemonade', he: 'לימונדה', ar: 'ليمونادة'),
        priceDeltaMinor: 400,
      ),
    ],
  ),
  'sauce': KioskFixtureGroup(
    id: 'sauce',
    type: KioskGroupType.single,
    isRequired: true,
    options: [
      KioskFixtureOption(
        id: 'sc1',
        name: KioskText3(en: 'Ketchup', he: 'קטשופ', ar: 'كاتشب'),
        priceDeltaMinor: 0,
      ),
      KioskFixtureOption(
        id: 'sc2',
        name: KioskText3(
          en: 'Garlic Aioli',
          he: 'איולי שום',
          ar: 'أيولي الثوم',
        ),
        priceDeltaMinor: 0,
      ),
      KioskFixtureOption(
        id: 'sc3',
        name: KioskText3(en: 'Spicy Ember', he: 'אמבר חריף', ar: 'إمبر حار'),
        priceDeltaMinor: 0,
      ),
    ],
  ),
  'addons': KioskFixtureGroup(
    id: 'addons',
    type: KioskGroupType.multi,
    isRequired: false,
    maxSelect: 4,
    options: [
      KioskFixtureOption(
        id: 'a1',
        name: KioskText3(
          en: 'Extra patty',
          he: 'קציצה נוספת',
          ar: 'قرص لحم إضافي',
        ),
        priceDeltaMinor: 1200,
      ),
      KioskFixtureOption(
        id: 'a2',
        name: KioskText3(
          en: 'Smoked cheddar',
          he: 'צ׳דר מעושן',
          ar: 'شيدر مدخّن',
        ),
        priceDeltaMinor: 600,
      ),
      KioskFixtureOption(
        id: 'a3',
        name: KioskText3(
          en: 'Beef bacon',
          he: 'בייקון בקר',
          ar: 'لحم مقدد بقري',
        ),
        priceDeltaMinor: 800,
      ),
      KioskFixtureOption(
        id: 'a4',
        name: KioskText3(en: 'Fried egg', he: 'ביצת עין', ar: 'بيضة مقلية'),
        priceDeltaMinor: 600,
      ),
      KioskFixtureOption(
        id: 'a5',
        name: KioskText3(
          en: 'Truffle mayo',
          he: 'מיונז כמהין',
          ar: 'مايونيز الكمأة',
        ),
        priceDeltaMinor: 500,
      ),
    ],
  ),
  'remove': KioskFixtureGroup(
    id: 'remove',
    type: KioskGroupType.multi,
    isRequired: false,
    maxSelect: 3,
    options: [
      KioskFixtureOption(
        id: 'r1',
        name: KioskText3(en: 'No onion', he: 'בלי בצל', ar: 'بدون بصل'),
        priceDeltaMinor: 0,
      ),
      KioskFixtureOption(
        id: 'r2',
        name: KioskText3(en: 'No tomato', he: 'בלי עגבנייה', ar: 'بدون طماطم'),
        priceDeltaMinor: 0,
      ),
      KioskFixtureOption(
        id: 'r3',
        name: KioskText3(en: 'No pickles', he: 'בלי חמוצים', ar: 'بدون مخلل'),
        priceDeltaMinor: 0,
      ),
    ],
  ),
};

/// The included option preselected when a required weight group opens
/// (V2: "Defaults preselect only when the menu defines an included option").
const String kioskIncludedWeightOptionId = 'w120';

/// The menu — the artifact's five categories and items, prices verbatim.
/// The MANDATORY pricing fixture is `b1` (base 4000 + w240 1500 / w360 2500).
const List<KioskFixtureCategory> kioskFixtureMenu = [
  KioskFixtureCategory(
    id: 'burgers',
    name: KioskText3(en: 'Burgers', he: 'בורגרים', ar: 'برغر'),
    thumbAsset: _imgSmash,
    items: [
      KioskFixtureItem(
        id: 'b1',
        name: KioskText3(en: 'Ember Smash', he: 'אמבר סמאש', ar: 'إمبر سماش'),
        description: KioskText3(
          en: 'Aged beef, smoked cheddar, charred onion',
          he: 'בקר מיושן, צ׳דר מעושן, בצל צרוב',
          ar: 'لحم معتّق، شيدر مدخّن، بصل مشوي',
        ),
        basePriceMinor: 4000,
        imageAsset: _imgSmash,
        groupIds: ['weight', 'addons', 'remove'],
      ),
      KioskFixtureItem(
        id: 'b2',
        name: KioskText3(en: 'Double Char', he: 'דאבל צ׳אר', ar: 'دبل تشار'),
        description: KioskText3(
          en: 'Double smash, double cheese pull',
          he: 'סמאש כפול, גבינה נמתחת',
          ar: 'سماش مزدوج وجبنة ذائبة',
        ),
        basePriceMinor: 5200,
        imageAsset: _imgDouble,
        groupIds: ['weight', 'addons', 'remove'],
      ),
      KioskFixtureItem(
        id: 'b3',
        name: KioskText3(en: 'Garden Char', he: 'גרדן צ׳אר', ar: 'غاردن تشار'),
        description: KioskText3(
          en: 'Fire-grilled tomato, crispy onions',
          he: 'עגבנייה על האש, בצל פריך',
          ar: 'طماطم مشوية وبصل مقرمش',
        ),
        basePriceMinor: 4400,
        imageAsset: _imgGarden,
        groupIds: ['weight', 'addons', 'remove'],
      ),
      KioskFixtureItem(
        id: 'b4',
        name: KioskText3(
          en: 'Halloumi Stack',
          he: 'חלומי סטאק',
          ar: 'ستاك حلومي',
        ),
        description: KioskText3(
          en: 'Seared halloumi, harissa mayo',
          he: 'חלומי צרוב, מיונז חריסה',
          ar: 'حلومي مشوي ومايونيز الهريسة',
        ),
        basePriceMinor: 3800,
        groupIds: ['addons', 'remove'],
      ),
    ],
  ),
  KioskFixtureCategory(
    id: 'meals',
    name: KioskText3(en: 'Meals', he: 'ארוחות', ar: 'وجبات'),
    thumbAsset: _imgDouble,
    items: [
      KioskFixtureItem(
        id: 'm1',
        name: KioskText3(en: 'Ember Meal', he: 'ארוחת אמבר', ar: 'وجبة إمبر'),
        description: KioskText3(
          en: 'Smash burger + side + drink',
          he: 'סמאש בורגר + תוספת + שתייה',
          ar: 'برغر سماش + جانبي + مشروب',
        ),
        basePriceMinor: 5800,
        imageAsset: _imgMeal,
        groupIds: ['weight', 'side', 'drink', 'addons'],
      ),
      KioskFixtureItem(
        id: 'm2',
        name: KioskText3(
          en: 'Family Char Box',
          he: 'מארז משפחתי',
          ar: 'بوكس العائلة',
        ),
        description: KioskText3(
          en: '2 doubles, 2 sides, 4 potato bombs',
          he: '2 כפולים, 2 תוספות, 4 פצצות',
          ar: '2 دبل، 2 جانبي، 4 قنابل بطاطا',
        ),
        basePriceMinor: 14900,
        groupIds: ['side', 'drink'],
      ),
    ],
  ),
  KioskFixtureCategory(
    id: 'sides',
    name: KioskText3(en: 'Sides', he: 'תוספות', ar: 'أطباق جانبية'),
    thumbAsset: _imgFries,
    items: [
      KioskFixtureItem(
        id: 's1',
        name: KioskText3(
          en: 'Loaded Fries Cup',
          he: 'צ׳יפס עמוס',
          ar: 'بطاطا محمّلة',
        ),
        description: KioskText3(
          en: 'Torched sauce, house seasoning',
          he: 'רוטב צרוב, תיבול הבית',
          ar: 'صوص محروق وتتبيلة البيت',
        ),
        basePriceMinor: 1600,
        imageAsset: _imgFries,
        groupIds: ['sauce'],
      ),
      KioskFixtureItem(
        id: 's2',
        name: KioskText3(
          en: 'Potato Bombs',
          he: 'פצצות תפו״ד',
          ar: 'قنابل البطاطا',
        ),
        description: KioskText3(
          en: 'Filled, glazed, torched',
          he: 'ממולאות, מזוגגות, צרובות',
          ar: 'محشوّة ومزجّجة ومشوية',
        ),
        basePriceMinor: 2200,
        imageAsset: _imgBombs,
        groupIds: ['sauce'],
      ),
      KioskFixtureItem(
        id: 's3',
        name: KioskText3(en: 'Onion Rings', he: 'טבעות בצל', ar: 'حلقات البصل'),
        description: KioskText3(
          en: 'Beer batter, ember dust',
          he: 'בצק בירה, אבקת אמבר',
          ar: 'عجينة مقرمشة وبهار إمبر',
        ),
        basePriceMinor: 1400,
        groupIds: ['sauce'],
      ),
    ],
  ),
  KioskFixtureCategory(
    id: 'drinks',
    name: KioskText3(en: 'Drinks', he: 'שתייה', ar: 'مشروبات'),
    iconKind: 'drink',
    items: [
      KioskFixtureItem(
        id: 'd1',
        name: KioskText3(en: 'Cola', he: 'קולה', ar: 'كولا'),
        description: KioskText3(
          en: 'Ice cold, 330ml',
          he: 'קפואה, 330 מ״ל',
          ar: 'مثلّجة، 330 مل',
        ),
        basePriceMinor: 1000,
        groupIds: [],
      ),
      KioskFixtureItem(
        id: 'd2',
        name: KioskText3(en: 'Cola Zero', he: 'קולה זירו', ar: 'كولا زيرو'),
        description: KioskText3(
          en: 'Ice cold, 330ml',
          he: 'קפואה, 330 מ״ל',
          ar: 'مثلّجة، 330 مل',
        ),
        basePriceMinor: 1000,
        groupIds: [],
      ),
      KioskFixtureItem(
        id: 'd3',
        name: KioskText3(
          en: 'Craft Lemonade',
          he: 'לימונדה ביתית',
          ar: 'ليمونادة حرفية',
        ),
        description: KioskText3(
          en: 'Charred lemon, mint',
          he: 'לימון צרוב, נענע',
          ar: 'ليمون مشوي ونعناع',
        ),
        basePriceMinor: 1400,
        groupIds: [],
      ),
      KioskFixtureItem(
        id: 'd4',
        name: KioskText3(
          en: 'Sparkling Water',
          he: 'מים מוגזים',
          ar: 'مياه غازية',
        ),
        description: KioskText3(
          en: '750ml bottle',
          he: 'בקבוק 750 מ״ל',
          ar: 'قنينة 750 مل',
        ),
        basePriceMinor: 900,
        groupIds: [],
      ),
    ],
  ),
  KioskFixtureCategory(
    id: 'desserts',
    name: KioskText3(en: 'Desserts', he: 'קינוחים', ar: 'حلويات'),
    iconKind: 'dessert',
    items: [
      KioskFixtureItem(
        id: 't1',
        name: KioskText3(
          en: 'Chocolate Shake',
          he: 'שייק שוקולד',
          ar: 'ميلك شيك شوكولاتة',
        ),
        description: KioskText3(
          en: 'Dark chocolate, torched cream',
          he: 'שוקולד מריר, קצפת צרובה',
          ar: 'شوكولاتة داكنة وكريمة محروقة',
        ),
        basePriceMinor: 1800,
        groupIds: [],
      ),
      KioskFixtureItem(
        id: 't2',
        name: KioskText3(
          en: 'Basque Cheesecake',
          he: 'עוגת גבינה באסקית',
          ar: 'تشيز كيك باسكي',
        ),
        description: KioskText3(
          en: 'Burnt top, soft heart',
          he: 'חרוכה מלמעלה, רכה בפנים',
          ar: 'محروقة من الأعلى وطرية من الداخل',
        ),
        basePriceMinor: 2400,
        groupIds: [],
      ),
    ],
  ),
];

KioskFixtureItem kioskItemById(String id) {
  for (final c in kioskFixtureMenu) {
    for (final it in c.items) {
      if (it.id == id) return it;
    }
  }
  throw ArgumentError.value(id, 'id', 'unknown fixture item');
}

/// Fixture floor — the artifact's ZONES with `busyFloor` fused in. `busy`
/// flips the B-marked tables to occupied (the board's "busy floor" preset).
List<KioskFixtureZone> kioskFixtureZones({required bool busy}) {
  KioskFixtureTable t(String l, int s, String st) => KioskFixtureTable(
    label: l,
    seats: s,
    state: switch (st) {
      'occ' => KioskTableState.occupied,
      'res' => KioskTableState.reserved,
      'oos' => KioskTableState.outOfService,
      'B' => busy ? KioskTableState.occupied : KioskTableState.available,
      _ => KioskTableState.available,
    },
  );
  return [
    KioskFixtureZone(
      id: 'hall',
      tables: [
        t('T1', 4, 'B'),
        t('T2', 2, 'occ'),
        t('T3', 4, 'B'),
        t('T4', 4, 'ok'),
        t('T5', 6, 'occ'),
        t('T6', 2, 'ok'),
        t('T7', 4, 'ok'),
        t('T8', 6, 'res'),
      ],
    ),
    KioskFixtureZone(
      id: 'patio',
      tables: [
        t('P1', 4, 'occ'),
        t('P2', 4, 'ok'),
        t('P3', 2, 'B'),
        t('P4', 2, 'B'),
        t('P5', 6, 'ok'),
        t('P6', 4, 'oos'),
      ],
    ),
    KioskFixtureZone(
      id: 'bar',
      tables: [
        t('B1', 1, 'res'),
        t('B2', 1, 'occ'),
        t('B3', 2, 'B'),
        t('B4', 2, 'ok'),
      ],
    ),
  ];
}

/// Fixture printers for the settings shell (visual only).
@immutable
class KioskFixturePrinter {
  const KioskFixturePrinter({
    required this.id,
    required this.name,
    required this.detail,
    required this.online,
  });
  final String id;
  final String name;
  final String detail;
  final bool online;
}

const List<KioskFixturePrinter> kioskFixturePrinters = [
  KioskFixturePrinter(
    id: 'p1',
    name: 'Counter-01',
    detail: 'Epson TM-T20III · 192.168.1.31 · 80mm',
    online: true,
  ),
  KioskFixturePrinter(
    id: 'p2',
    name: 'Counter-02',
    detail: 'Epson TM-m30 · 192.168.1.32 · 80mm',
    online: true,
  ),
  KioskFixturePrinter(
    id: 'p3',
    name: 'Kitchen-01',
    detail: 'Star SP700 · 192.168.1.40',
    online: false,
  ),
];

/// The Phase-1 staff PIN is a VISUAL FIXTURE ONLY (the artifact's demo PIN).
/// It exercises the keypad/shake flow; it is NOT authentication and is
/// replaced by the real employee PIN session in a later phase.
const String kioskFixturePin = '2468';

// ---------------------------------------------------------------------------
// Pricing — pure integer-minor-unit math (mirrors MONEY_AND_TAX_SPEC §9:
// unit = base + Σ selected deltas; line = unit × qty). Fixture-scoped: the
// real engine arrives with real menu integration in a later phase.
// ---------------------------------------------------------------------------

/// unit price of [item] with [selected] option ids per group.
int kioskUnitPriceMinor(
  KioskFixtureItem item,
  Map<String, List<String>> selected,
) {
  var minor = item.basePriceMinor;
  for (final gid in item.groupIds) {
    final group = kioskFixtureGroups[gid]!;
    for (final oid in selected[gid] ?? const <String>[]) {
      for (final o in group.options) {
        if (o.id == oid) minor += o.priceDeltaMinor;
      }
    }
  }
  return minor;
}

/// Required groups of [item] with no selection yet (V2 blocks the CTA and
/// names these groups).
List<String> kioskUnmetRequiredGroups(
  KioskFixtureItem item,
  Map<String, List<String>> selected,
) => [
  for (final gid in item.groupIds)
    if (kioskFixtureGroups[gid]!.isRequired &&
        (selected[gid] ?? const []).isEmpty)
      gid,
];

/// Money rendering, exactly the artifact's `fmt`: whole amounts drop the
/// decimals; EN leads with the symbol, RTL trails it.
String kioskFormatMinor(int minor, String lang) {
  final sign = minor < 0 ? '-' : '';
  final abs = minor.abs();
  final v = abs % 100 == 0 ? '${abs ~/ 100}' : (abs / 100).toStringAsFixed(2);
  return lang == 'en' ? '$sign₪$v' : '$sign$v ₪';
}

/// Signed delta rendering (`+₪15` / `+15 ₪`).
String kioskFormatDeltaMinor(int minor, String lang) =>
    '+${kioskFormatMinor(minor, lang)}';
