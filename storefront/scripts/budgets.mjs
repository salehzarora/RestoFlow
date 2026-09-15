// Single source of truth for the output budgets, shared by the audit script and
// the post-build test so the two can never disagree.
export const BUDGETS = {
  totalOutBytes: 2 * 1024 * 1024,   // 2 MB, whole out/ tree
  singleFileBytes: 256 * 1024,      // mirrors the engine's public/ rule
  firstLoadJsBytes: 400 * 1024,     // sum of <script src> bytes on /, uncompressed
  sourceMaps: 0,
  referenceMedia: 0,
  serverFunctions: 0,
};

export const MEDIA_EXTENSIONS = ['.jpg', '.jpeg', '.gif', '.mp4', '.webm', '.mov'];

export const REQUIRED_HTML = ['index.html', 'ar.html', 'en.html', 'he.html', '404.html'];

export const REQUIRED_STATIC = ['robots.txt', 'healthz.json', 'favicon.svg'];

/** Expected <html lang>/<html dir> for each emitted locale document. */
export const EXPECTED_DOCUMENT = {
  'index.html': { lang: 'ar', dir: 'rtl' },
  'ar.html': { lang: 'ar', dir: 'rtl' },
  'en.html': { lang: 'en', dir: 'ltr' },
  'he.html': { lang: 'he', dir: 'rtl' },
};
