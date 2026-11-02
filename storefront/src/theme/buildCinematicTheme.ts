/** Cinematic presentation only; order, service and semantic state are unchanged. */
import type { TenantBrand } from '../source/types';
import { AA, AA_LARGE, buildTheme, type ThemeTokens } from './buildTheme';
import { contrast, inkOn, isHex, mix, rgba, walk, type Hex } from './contrast';
import { normaliseHex } from './sanitize';

/** Platform defaults, never a restaurant-specific palette. */
const BG: Hex = '#151513';
const SF: Hex = '#1c1c19';
const SF2: Hex = '#262621';
const TEXT: Hex = '#f7f2ea';
const ACCENT: Hex = '#e4ad83';

function brandColour(value: string | null | undefined, fallback: Hex): Hex {
  return typeof value === 'string' && isHex(value) ? normaliseHex(value) : fallback;
}

function appearanceColour(value: string | null | undefined): Hex | null {
  return typeof value === 'string' && value.length === 7 && /^#[0-9a-fA-F]{6}$/.test(value)
    ? value.toLowerCase() as Hex : null;
}

/**
 * The owner can select every valid HEX; explicit copy colours are not replaced
 * by a contrast policy. Automatic ink/focus colours keep the existing rules.
 * The original buildTheme/sanitizePrimary contract remains unchanged.
 */
export function buildCinematicTheme(
  brand: Pick<TenantBrand, 'primary' | 'accent' | 'text' | 'buttonText'>,
): ThemeTokens {
  const primary = brandColour(brand.primary, BG);
  const accent = brandColour(brand.accent, ACCENT);
  const base = buildTheme('dark', { primary, accent });
  const explicitText = appearanceColour(brand.text);
  const tx = explicitText ?? TEXT;
  const tx2 = explicitText ?? '#c8c3ba';
  const tx3 = explicitText ?? '#a5a198';
  const onacc = appearanceColour(brand.buttonText) ?? inkOn(accent);
  const accs = mix(accent, SF, 0.82);
  const surfaces = [BG, SF, SF2, accs];
  let ring: Hex = '#ffffff';
  for (let step = 0; step <= 20; step++) {
    const candidate = mix(accent, '#ffffff', step / 20);
    if (surfaces.every(surface => contrast(candidate, surface) >= AA_LARGE)) {
      ring = candidate;
      break;
    }
  }

  return {
    ...base,
    bg: BG, sf: SF, sf2: SF2,
    tx, tx2, tx3,
    hair: rgba(tx, 0.12), hair2: rgba(tx, 0.24),
    hero: primary, onhero: tx, onhero2: tx2,
    acc: accent, onacc,
    acct: walk(accent, SF, AA, '#ffffff'),
    accLargeText: walk(accent, BG, AA_LARGE, '#ffffff'),
    accs, accOnSelection: walk(accent, accs, AA, '#ffffff'), ring,
    cta: accent, ctaSh: 'none', glow: 'none', heroGlow: 'none',
    glass: rgba(BG, 0.9), glassDock: rgba(BG, 0.96), onDock2: tx2,
    glassLine: rgba(tx, 0.14),
  };
}
