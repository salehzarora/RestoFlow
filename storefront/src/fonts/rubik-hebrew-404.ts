/**
 * RUBIK, SELF-HOSTED, ONE FILE PER SCRIPT SUBSET - see ./README.md for the
 * whole arrangement. Every value below is a literal because the pinned
 * next/font loader refuses anything else ("Font loader values must be
 * explicitly written literals"). The unicode-range is the subset's BLOCKS,
 * not the file's exact coverage: a character inside a block that the file
 * lacks falls through to the next family exactly as it always did, and the
 * blocks are disjoint so exactly one subset owns each character (the few
 * glyphs two files share - space, hyphen, "A", combining marks - go to Latin).
 */
import localFont from 'next/font/local';

/** Hebrew and the shekel sign, ON DEMAND, for the 404 document ONLY: a module of its own, so the not-found boundary (part of every route's tree) shares no chunk with a root's preloaded set. */
export const rubikHebrew404 = localFont({
  src: [{ path: './rubik-hebrew-var.woff2', weight: '400 900', style: 'normal' }],
  display: 'swap',
  variable: '--sf-font-hebrew',
  preload: false,
  // No metric-adjusted `local()` fallback face at all: one would sit before
  // the next script's family and catch its characters, and `local()` matching
  // costs ~150 ms of the first layout on the throttled lab (storefront.module.css).
  adjustFontFallback: false,
  declarations: [{ prop: 'unicode-range', value: 'U+0590-05FF, U+20AA, U+FB1D-FB4F' }],
});
