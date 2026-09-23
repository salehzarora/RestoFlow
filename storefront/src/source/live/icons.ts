/**
 * CATEGORY ICON REGISTRY - the storefront side of the Dashboard's 49-key
 * category icon library (packages/design_system/lib/src/menu_category_icons.dart).
 *
 * WHY A REGISTRY. `Category.iconPath` is injected into an SVG `d` attribute
 * unsanitised (HomeChrome.tsx CategoryIcon), so the path may NEVER come from
 * tenant data. The database stores an abstract KEY (`menu_categories.icon_key`,
 * shape-checked `^[a-z][a-z0-9_]{0,39}$`); this module maps a key to one of
 * its own 24-grid outlined paths and falls back to `menu` for NULL or any key
 * it does not know. Only registry paths are ever emitted.
 *
 * The keys are the Dashboard registry's, verbatim, so the owner's pick shows
 * the same pictogram family here. The glyphs are this build's outlines (2px
 * stroke, round caps - the storefront icon language), not Material glyphs.
 *
 * Server-only by use (the adapter resolves paths before render); it holds no
 * secret and no I/O, so it is safe wherever it lands.
 */

export const DEFAULT_ICON_KEY = 'menu';

const PATHS: Readonly<Record<string, string>> = {
  // --- mains
  meals: 'M3 12h18M5 12a7 7 0 0114 0M8 20h8M12 12v8',
  dinner: 'M4 14h16l-2 6H6zM4 14a8 8 0 0116 0M12 3v3',
  grill: 'M3 8h18M5 8a7 7 0 0014 0M8 15l-2 6M16 15l2 6M12 15v6',
  rice: 'M4 12h16a8 8 0 01-16 0zM6 12c0-3 3-6 6-6s6 3 6 6',
  noodles: 'M4 12h16a8 8 0 01-16 0zM7 4l1 8M12 3v9M17 4l-1 8',
  soup: 'M3 11h18a9 9 0 01-18 0zM8 5c0 2 2 2 2 4M14 5c0 2 2 2 2 4',
  set_meal: 'M3 6h18v12H3zM3 12h18M9 6v12',
  bento: 'M3 5h18v14H3zM12 5v14M3 12h9',
  skewers: 'M4 20L20 4M8 12l4 4M11 9l4 4M14 6l4 4',
  tapas: 'M4 8h6v6H4zM14 8h6v6h-6zM9 16h6v4H9z',
  // --- fast food + service styles
  burger: 'M4 10h16a8 8 0 00-16 0zM3 14h18M4 17h16v1a2 2 0 01-2 2H6a2 2 0 01-2-2z',
  fast_food: 'M5 10h14l-1 10H6zM5 10a7 7 0 0114 0M9 14h6',
  pizza: 'M12 3l9 16H3zM12 9h.01M9 14h.01M15 14h.01',
  takeaway: 'M5 8h14l-1 12H6zM9 8V6a3 3 0 016 0v2',
  delivery: 'M6.5 18.5a2.5 2.5 0 100-5 2.5 2.5 0 000 5zM18.5 18.5a2.5 2.5 0 100-5 2.5 2.5 0 000 5zM9 16h7M16 16l-2-9h-3M6.5 13.5V10h4',
  room_service: 'M3 17h18M5 17a7 7 0 0114 0M12 8v2M10 8h4',
  kids_meal: 'M12 3a6 6 0 016 6c0 3.3-2.7 6-6 6s-6-2.7-6-6a6 6 0 016-6zM12 15v4M9 21h6M10 8.5h.01M14 8.5h.01',
  // --- bakery + sweets
  bakery: 'M4 13c0-4 4-7 8-7s8 3 8 7v5H4zM8 13v5M12 13v5M16 13v5',
  breakfast: 'M4 12a8 8 0 1016 0 8 8 0 00-16 0zM12 8v4l3 2',
  brunch: 'M5 10h14v9H5zM5 10a7 7 0 0114 0M8 14h8',
  eggs: 'M12 3c4 0 7 6 7 11a7 7 0 01-14 0c0-5 3-11 7-11z',
  cake: 'M5 12h14l-1 8H6zM5 12a7 7 0 0114 0M9 20v-4M12 20v-5M15 20v-4',
  cookie: 'M12 3a9 9 0 109 9 4 4 0 01-4-4 4 4 0 01-5-5zM8 12h.01M12 16h.01M14 10h.01',
  donut: 'M12 3a9 9 0 100 18 9 9 0 000-18zM12 9a3 3 0 100 6 3 3 0 000-6z',
  ice_cream: 'M7 10a5 5 0 0110 0v1H7zM7 11l5 10 5-10',
  celebration: 'M5 21l4-12 8 8zM13 5l1 2M17 3l-1 3M19 8l-3 1',
  // --- cold drinks
  drinks: 'M6 5h12l-1.3 15H7.3zM6.6 10h10.8M14 5l2.5-3',
  bar: 'M4 4h16l-8 9zM12 13v7M8 20h8',
  wine: 'M8 3h8v6a4 4 0 01-8 0zM12 13v7M8 20h8',
  spirits: 'M9 3h6v4l2 3v11H7V10l2-3z',
  beer: 'M6 8h10v12H6zM16 11h3v6h-3M8 5c0-2 6-2 6 0',
  nightlife: 'M12 3a9 9 0 109 9 7 7 0 01-9-9z',
  water: 'M12 3s7 8 7 12a7 7 0 01-14 0c0-4 7-12 7-12z',
  cold: 'M12 3v18M4 7l16 10M4 17L20 7',
  // --- hot drinks
  coffee: 'M4 8h13v7a5 5 0 01-10 0V8zM17 10h2a2 2 0 010 4h-2M8 4c0 1 1 1 1 2M12 4c0 1 1 1 1 2',
  espresso: 'M6 10h10v4a5 5 0 01-10 0zM16 11h2a1.5 1.5 0 010 3h-2M5 20h12',
  tea: 'M4 9h13v5a5 5 0 01-10 0V9zM17 10h2a2 2 0 010 4h-2M9 3v4M13 5v2',
  hot_drinks: 'M5 10h12v5a5 5 0 01-10 0v-5zM17 11h2a2 2 0 010 4h-2M8 4c0 1.5 2 1.5 2 3M12 4c0 1.5 2 1.5 2 3',
  coffee_maker: 'M5 3h14v6H5zM7 9v11h10V9M9 13h6',
  // --- other
  salad: 'M4 12h16a8 8 0 01-16 0zM8 12c0-3 2-6 4-6s4 3 4 6M6 8l2-3M18 8l-2-3',
  produce: 'M12 21c-4 0-8-4-8-9V6l8-3 8 3v6c0 5-4 9-8 9zM12 7v10',
  herbs: 'M12 21V9M12 9c-4 0-7 3-7 7 4 0 7-3 7-7zM12 9c4 0 7 3 7 7-4 0-7-3-7-7z',
  sauces: 'M9 3h6v4l2 3v11H7V10l2-3zM9 15h6',
  spicy: 'M9 4c0 6-5 8-5 12a5 5 0 0010 0c0-4 2-6 2-6M9 4c3 0 5 2 5 5',
  kitchen: 'M5 3v18M5 9h4V3M15 3v18M15 3c3 0 4 3 4 6s-1 4-4 4',
  sides: 'M7 10l-1 11h12l-1-11M7 10V5l2 1.5L12 4l3 2.5L17 5v5M7 10h10M10 14v4M14 14v4',
  offers: 'M20.6 13.4l-7.2 7.2a2 2 0 01-2.8 0L3 13V4h9l8.6 8.6a.6.6 0 010 .8zM7.5 8.5h.01',
  general: 'M4 6h16M4 12h16M4 18h16',
  menu: 'M5 3h14v18H5zM8 8h8M8 12h8M8 16h5',
};

/** Every key the registry knows, in the Dashboard's picker order. */
export const CATEGORY_ICON_KEYS: readonly string[] = Object.keys(PATHS);

/** The 24-grid path for a key; the `menu` outline for NULL or an unknown key. */
export function iconPathFor(key: string | null | undefined): string {
  if (typeof key === 'string' && Object.hasOwn(PATHS, key)) return PATHS[key];
  return PATHS[DEFAULT_ICON_KEY];
}
