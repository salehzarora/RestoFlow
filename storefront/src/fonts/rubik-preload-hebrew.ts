/**
 * The font set of the Hebrew root (`/he`): Latin and Hebrew (with the shekel
 * sign) PRELOADED (two files); Arabic - the tenant's content script -
 * declared and fetched on demand, with a metric-tuned fallback face so the
 * swap moves little (storefront.module.css, measured in G-FONTS). Preloading
 * Arabic instead of Latin here was tried and could not be kept at two
 * preloads on this toolchain (builds c8-c10 in the correction record).
 * See ./README.md; the module order is load-bearing (rubik-preload-arabic.ts).
 */
import { rubikArabicLazy } from './rubik-arabic-lazy';
import { rubikHebrew } from './rubik-hebrew';
import { rubikLatin } from './rubik-latin';

/** The class that sets the three `--sf-font-*` variables on a root element. */
export const rubikPreloadHebrew = {
  className: `${rubikLatin.variable} ${rubikHebrew.variable} ${rubikArabicLazy.variable}`,
};
