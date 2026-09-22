/**
 * The font set of the Arabic-content roots (`/`, `/ar`, `/en`): Latin and
 * Arabic PRELOADED (two files), Hebrew - which also carries the shekel sign -
 * declared and fetched on demand. See ./README.md.
 *
 * THE MODULE LIST AND ITS ORDER ARE LOAD-BEARING. The toolchain merges CSS
 * chunks "loosely" and links the merged chunk into every document; which
 * set it absorbs depends on the sets' module names and order (proven by
 * builds c5-c10 in the correction record). This exact arrangement - each
 * root's own preload in its own module, the Latin module shared with the
 * 404 document, listed in this order - keeps every root at two preloads.
 */
import { rubikArabic } from './rubik-arabic';
import { rubikHebrewLazy } from './rubik-hebrew-lazy';
import { rubikLatin } from './rubik-latin';

/** The class that sets the three `--sf-font-*` variables on a root element. */
export const rubikPreloadArabic = {
  className: `${rubikLatin.variable} ${rubikArabic.variable} ${rubikHebrewLazy.variable}`,
};
