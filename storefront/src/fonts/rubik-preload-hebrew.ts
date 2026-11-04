import { rubikClass } from './rubik';

/** Preserve this route's preload set; all other glyphs remain available on demand. */
export function rubikPreloadHebrew() {
  return rubikClass('hebrew');
}
