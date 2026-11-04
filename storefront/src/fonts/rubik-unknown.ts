import { rubikClass } from './rubik';

/** Preserve this route's preload set; all other glyphs remain available on demand. */
export function rubikUnknown() {
  return rubikClass();
}
