import type { FontFamily } from '../source/types';

/** Closed font choices. Published data never supplies CSS or a font URL. */
const RUBIK = "var(--sf-font-latin, sf-unset), var(--sf-font-arabic, sf-unset), var(--sf-font-hebrew, sf-unset), 'Segoe UI', Tahoma, sans-serif";
const ALEXANDRIA = `"SF Alexandria", ${RUBIK}`;
const SYSTEM = "system-ui, 'Segoe UI', Tahoma, sans-serif";

export function storefrontFont(family: FontFamily | null | undefined): string {
  if (family === 'alexandria') return ALEXANDRIA;
  if (family === 'system') return SYSTEM;
  return RUBIK;
}
