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
  // STOREFRONT-UI-001 written acceptance limits for the two asset classes the
  // plan named without a validator (finishing mandate 7; correction pass 4):
  // per DIRECT-LOAD ROUTE, unique stylesheets actually referenced by the
  // document, raw AND per-response Brotli; and the font files the document
  // PRELOADS (link rel=preload as=font, plus any Link-header preload the
  // committed header set carries), count AND bytes. These are the limits as
  // written; this file never raises them. A route over a limit FAILS the
  // measurement, the audit and the output test - it is reported, not waived.
  cssPerRouteBytes: 70000,          // exact decimal bytes, minified but uncompressed
  cssPerRouteBrotliBytes: 14000,    // exact decimal bytes, each stylesheet compressed separately
  fontPreloadsPerRoute: 2,          // files
  fontPreloadBytesPerRoute: 120000, // exact decimal bytes, the preloaded files summed
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
  // STOREFRONT-UI-001 Phase D: the four flow surfaces, measured in every
  // locale root. Adding routes WIDENS coverage; no ceiling above changes.
  { route: '/s/maps-burger/cart', file: 's/maps-burger/cart.html' },
  { route: '/ar/s/maps-burger/cart', file: 'ar/s/maps-burger/cart.html' },
  { route: '/en/s/maps-burger/cart', file: 'en/s/maps-burger/cart.html' },
  { route: '/he/s/maps-burger/cart', file: 'he/s/maps-burger/cart.html' },
  { route: '/s/maps-burger/checkout', file: 's/maps-burger/checkout.html' },
  { route: '/ar/s/maps-burger/checkout', file: 'ar/s/maps-burger/checkout.html' },
  { route: '/en/s/maps-burger/checkout', file: 'en/s/maps-burger/checkout.html' },
  { route: '/he/s/maps-burger/checkout', file: 'he/s/maps-burger/checkout.html' },
  { route: '/s/maps-burger/payment', file: 's/maps-burger/payment.html' },
  { route: '/ar/s/maps-burger/payment', file: 'ar/s/maps-burger/payment.html' },
  { route: '/en/s/maps-burger/payment', file: 'en/s/maps-burger/payment.html' },
  { route: '/he/s/maps-burger/payment', file: 'he/s/maps-burger/payment.html' },
  { route: '/s/maps-burger/review', file: 's/maps-burger/review.html' },
  { route: '/ar/s/maps-burger/review', file: 'ar/s/maps-burger/review.html' },
  { route: '/en/s/maps-burger/review', file: 'en/s/maps-burger/review.html' },
  { route: '/he/s/maps-burger/review', file: 'he/s/maps-burger/review.html' },
  // STOREFRONT-UI-001 Phase E: the request surface (received | status on ONE
  // document), the single canonical demo ref, measured in every locale root.
  // Adding routes WIDENS coverage; no ceiling above changes.
  { route: '/r/DEMO-7K4XM2D9P3', file: 'r/DEMO-7K4XM2D9P3.html' },
  { route: '/ar/r/DEMO-7K4XM2D9P3', file: 'ar/r/DEMO-7K4XM2D9P3.html' },
  { route: '/en/r/DEMO-7K4XM2D9P3', file: 'en/r/DEMO-7K4XM2D9P3.html' },
  { route: '/he/r/DEMO-7K4XM2D9P3', file: 'he/r/DEMO-7K4XM2D9P3.html' },
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
  // STOREFRONT-UI-001 Phase D: all sixteen flow documents must be emitted.
  's/maps-burger/cart.html', 'ar/s/maps-burger/cart.html', 'en/s/maps-burger/cart.html', 'he/s/maps-burger/cart.html',
  's/maps-burger/checkout.html', 'ar/s/maps-burger/checkout.html', 'en/s/maps-burger/checkout.html', 'he/s/maps-burger/checkout.html',
  's/maps-burger/payment.html', 'ar/s/maps-burger/payment.html', 'en/s/maps-burger/payment.html', 'he/s/maps-burger/payment.html',
  's/maps-burger/review.html', 'ar/s/maps-burger/review.html', 'en/s/maps-burger/review.html', 'he/s/maps-burger/review.html',
  'r/DEMO-7K4XM2D9P3.html', 'ar/r/DEMO-7K4XM2D9P3.html', 'en/r/DEMO-7K4XM2D9P3.html', 'he/r/DEMO-7K4XM2D9P3.html',
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
  // Phase D: every flow document declares its own language and direction.
  's/maps-burger/cart.html': { lang: 'ar', dir: 'rtl' },
  'ar/s/maps-burger/cart.html': { lang: 'ar', dir: 'rtl' },
  'en/s/maps-burger/cart.html': { lang: 'en', dir: 'ltr' },
  'he/s/maps-burger/cart.html': { lang: 'he', dir: 'rtl' },
  's/maps-burger/checkout.html': { lang: 'ar', dir: 'rtl' },
  'ar/s/maps-burger/checkout.html': { lang: 'ar', dir: 'rtl' },
  'en/s/maps-burger/checkout.html': { lang: 'en', dir: 'ltr' },
  'he/s/maps-burger/checkout.html': { lang: 'he', dir: 'rtl' },
  's/maps-burger/payment.html': { lang: 'ar', dir: 'rtl' },
  'ar/s/maps-burger/payment.html': { lang: 'ar', dir: 'rtl' },
  'en/s/maps-burger/payment.html': { lang: 'en', dir: 'ltr' },
  'he/s/maps-burger/payment.html': { lang: 'he', dir: 'rtl' },
  's/maps-burger/review.html': { lang: 'ar', dir: 'rtl' },
  'ar/s/maps-burger/review.html': { lang: 'ar', dir: 'rtl' },
  'en/s/maps-burger/review.html': { lang: 'en', dir: 'ltr' },
  'he/s/maps-burger/review.html': { lang: 'he', dir: 'rtl' },
  'r/DEMO-7K4XM2D9P3.html': { lang: 'ar', dir: 'rtl' },
  'ar/r/DEMO-7K4XM2D9P3.html': { lang: 'ar', dir: 'rtl' },
  'en/r/DEMO-7K4XM2D9P3.html': { lang: 'en', dir: 'ltr' },
  'he/r/DEMO-7K4XM2D9P3.html': { lang: 'he', dir: 'rtl' },
};
