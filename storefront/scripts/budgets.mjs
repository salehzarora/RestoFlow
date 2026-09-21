// Single source of truth for the output budgets, shared by the audit script and
// the post-build test so the two can never disagree.
// Byte ceilings. `totalOutBytes` uses the BINARY convention (2 MiB = 2*1024*1024
// = 2,097,152 bytes); the two JS ceilings are exact DECIMAL byte counts as
// approved. The convention is spelled out here so a later reader cannot mistake
// one for the other.
export const BUDGETS = {
  // STOREFRONT-UI-001 approved ceiling (packet item 16): 4 MiB =
  // 4,194,304 bytes for the whole out/ tree. This task may NOT raise it;
  // Phase F may LOWER it once the real module set is measured.
  totalOutBytes: 4 * 1024 * 1024,   // 4 MiB = 4,194,304 bytes, whole out/ tree
  singleFileBytes: 256 * 1024,      // 262,144 bytes; mirrors the engine's public/ rule
  // STOREFRONT-INFRA-001B approved dual axis. Both must pass: compression does
  // not remove parse/compile cost, so the uncompressed guard stays.
  firstLoadJsBytes: 690000,         // exact decimal bytes, minified but uncompressed
  firstLoadJsBrotliBytes: 200000,   // exact decimal bytes, each response compressed separately
  sourceMaps: 0,
  referenceMedia: 0,
  serverFunctions: 0,
};

// Every direct-load route whose first-load cost is measured independently.
export const ROUTES = [
  { route: '/', file: 'index.html' },
  { route: '/ar', file: 'ar.html' },
  { route: '/en', file: 'en.html' },
  { route: '/he', file: 'he.html' },
  { route: '/s/maps-burger', file: 's/maps-burger.html' },
  { route: '/ar/s/maps-burger', file: 'ar/s/maps-burger.html' },
  { route: '/en/s/maps-burger', file: 'en/s/maps-burger.html' },
  { route: '/he/s/maps-burger', file: 'he/s/maps-burger.html' },
  // STOREFRONT-UI-001 Phase B: the home surface, measured in every locale root.
  { route: '/s/maps-burger/menu', file: 's/maps-burger/menu.html' },
  { route: '/ar/s/maps-burger/menu', file: 'ar/s/maps-burger/menu.html' },
  { route: '/en/s/maps-burger/menu', file: 'en/s/maps-burger/menu.html' },
  { route: '/he/s/maps-burger/menu', file: 'he/s/maps-burger/menu.html' },
  // STOREFRONT-UI-001 Phase C: the search surface, measured in every locale
  // root. Adding routes WIDENS coverage; no ceiling above is changed.
  { route: '/s/maps-burger/search', file: 's/maps-burger/search.html' },
  { route: '/ar/s/maps-burger/search', file: 'ar/s/maps-burger/search.html' },
  { route: '/en/s/maps-burger/search', file: 'en/s/maps-burger/search.html' },
  { route: '/he/s/maps-burger/search', file: 'he/s/maps-burger/search.html' },
];

export const MEDIA_EXTENSIONS = ['.jpg', '.jpeg', '.gif', '.mp4', '.webm', '.mov'];

export const REQUIRED_HTML = [
  'index.html', 'ar.html', 'en.html', 'he.html', '404.html',
  // STOREFRONT-UI-001 Phase A: the fixture storefront, in every locale root.
  's/maps-burger.html', 'ar/s/maps-burger.html', 'en/s/maps-burger.html', 'he/s/maps-burger.html',
  's/maps-burger/menu.html', 'ar/s/maps-burger/menu.html',
  'en/s/maps-burger/menu.html', 'he/s/maps-burger/menu.html',
  // STOREFRONT-UI-001 Phase C: the search surface must be emitted too.
  's/maps-burger/search.html', 'ar/s/maps-burger/search.html',
  'en/s/maps-burger/search.html', 'he/s/maps-burger/search.html',
];

// No favicon: gate K2 (owner approval for a BIZBOT symbol derivative) is NOT
// GRANTED, so the fallback is plain BIZBOT text and no custom icon. Authoring
// one would be inventing brand artwork.
export const REQUIRED_STATIC = ['robots.txt', 'healthz.json'];

/** Expected <html lang>/<html dir> for each emitted locale document. */
export const EXPECTED_DOCUMENT = {
  'index.html': { lang: 'ar', dir: 'rtl' },
  'ar.html': { lang: 'ar', dir: 'rtl' },
  'en.html': { lang: 'en', dir: 'ltr' },
  'he.html': { lang: 'he', dir: 'rtl' },
  's/maps-burger.html': { lang: 'ar', dir: 'rtl' },
  'ar/s/maps-burger.html': { lang: 'ar', dir: 'rtl' },
  'en/s/maps-burger.html': { lang: 'en', dir: 'ltr' },
  'he/s/maps-burger.html': { lang: 'he', dir: 'rtl' },
  's/maps-burger/menu.html': { lang: 'ar', dir: 'rtl' },
  'ar/s/maps-burger/menu.html': { lang: 'ar', dir: 'rtl' },
  'en/s/maps-burger/menu.html': { lang: 'en', dir: 'ltr' },
  'he/s/maps-burger/menu.html': { lang: 'he', dir: 'rtl' },
};
