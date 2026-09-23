/**
 * The font set of the platform 404 document (`app/not-found.tsx`). The
 * not-found boundary is part of EVERY route's client tree on the pinned
 * toolchain, so whatever it imports is linked into every document - and a
 * module it shares with a root's set drags that set's chunk (its preloads
 * included) into every document too. So: the Latin subset (preloaded on every
 * root anyway) and two on-demand calls that belong to this document alone.
 * The module order is load-bearing (rubik-preload-arabic.ts). See ./README.md.
 */
import { rubikArabic404 } from './rubik-arabic-404';
import { rubikHebrew404 } from './rubik-hebrew-404';
import { rubikLatin } from './rubik-latin';

/** The class that sets the three `--sf-font-*` variables on the 404 root. */
export const rubikUnknown = {
  className: `${rubikLatin.variable} ${rubikArabic404.variable} ${rubikHebrew404.variable}`,
};
