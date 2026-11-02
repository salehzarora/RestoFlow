/** Cinematic presentation only; order, service and semantic state are unchanged. */
import type { TenantBrand } from '../source/types';
import { AA, AA_LARGE, buildTheme, type ThemeTokens } from './buildTheme';
import { contrast, inkOn, isHex, mix, rgba, walk, type Hex } from './contrast';
import { normaliseHex } from './sanitize';

/** Platform defaults, never a restaurant-specific palette. */
const BG: Hex = '#151513';
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
  const automaticInk = contrast('#ffffff', primary) >= contrast('#000000', primary) ? '#ffffff' : '#000000';
  const dark = automaticInk === '#ffffff';
  const surface = (amount: number): Hex => {
    const candidate = mix(primary, dark ? '#ffffff' : '#000000', amount);
    // Around the light/dark threshold, shade away from the ink so the same
    // automatic copy remains readable across the page and raised surfaces.
    return contrast(automaticInk, candidate) >= AA ? candidate : mix(primary, dark ? '#000000' : '#ffffff', amount);
  };
  const sf = surface(0.03);
  const sf2 = surface(0.07);
  const copySurfaces = [primary, sf, sf2];
  const explicitText = appearanceColour(brand.text);
  const tx = explicitText ?? (copySurfaces.every(background => contrast(TEXT, background) >= AA) ? TEXT : automaticInk);
  const muted = (amount: number): Hex => copySurfaces.reduce((colour, background) => walk(colour, background, AA, automaticInk), mix(tx, primary, amount));
  const tx2 = explicitText ?? muted(0.2);
  const tx3 = explicitText ?? muted(0.34);
  const buttonText = appearanceColour(brand.buttonText);
  const onacc = buttonText ?? inkOn(accent);
  const accs = mix(accent, sf, 0.82);
  const surfaces = [...copySurfaces, accs];
  const focusInk = Math.min(...surfaces.map(background => contrast('#ffffff', background))) >= Math.min(...surfaces.map(background => contrast('#000000', background))) ? '#ffffff' : '#000000';
  let ring: Hex = focusInk;
  for (let step = 0; step <= 20; step++) {
    const candidate = mix(accent, focusInk, step / 20);
    if (surfaces.every(surface => contrast(candidate, surface) >= AA_LARGE)) {
      ring = candidate;
      break;
    }
  }

  return {
    ...base,
    bg: primary, sf, sf2,
    tx, tx2, tx3,
    hair: rgba(tx, 0.12), hair2: rgba(tx, 0.24),
    hero: primary, onhero: buttonText ?? tx, onhero2: tx2,
    acc: accent, onacc,
    acct: walk(accent, sf, AA, automaticInk),
    accLargeText: walk(accent, primary, AA_LARGE, automaticInk),
    accs, accOnSelection: walk(accent, accs, AA, contrast('#ffffff', accs) >= contrast('#000000', accs) ? '#ffffff' : '#000000'), ring,
    cta: accent, ctaSh: 'none', glow: 'none', heroGlow: 'none',
    glass: rgba(primary, 0.9), glassDock: rgba(primary, 0.96), onDock2: tx2,
    glassLine: rgba(tx, 0.14),
  };
}
