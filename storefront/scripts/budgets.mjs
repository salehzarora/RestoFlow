// Single source of truth for the output budgets, shared by the audit script and
// the post-build test so the two can never disagree.
// Byte ceilings. `totalOutBytes` uses the BINARY convention (2 MiB = 2*1024*1024
// = 2,097,152 bytes); the two JS ceilings are exact DECIMAL byte counts as
// approved. The convention is spelled out here so a later reader cannot mistake
// one for the other.
export const BUDGETS = {
  totalOutBytes: 2 * 1024 * 1024,   // 2 MiB = 2,097,152 bytes, whole out/ tree
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
];

export const MEDIA_EXTENSIONS = ['.jpg', '.jpeg', '.gif', '.mp4', '.webm', '.mov'];

export const REQUIRED_HTML = ['index.html', 'ar.html', 'en.html', 'he.html', '404.html'];

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
};
