/** Opt-in whole-site presentation. Never rewrites a merchant's stored colours. */
import type { Tenant } from '../source/types';
import { AA, buildTheme, type ThemeTokens } from './buildTheme';
import { buildCinematicTheme } from './buildCinematicTheme';
import { contrast, inkOn, isHex, mix, rgba, walk, type Hex } from './contrast';
import { normaliseHex } from './sanitize';

type Appearance = Pick<Tenant, 'brand' | 'scenePreset'> & { readonly siteTheme?: 'light' | 'dark' | null };
const colour = (value: string | null | undefined): Hex | null =>
  typeof value === 'string' && isHex(value) ? normaliseHex(value) : null;

export function buildSiteTheme(tenant: Appearance, legacy?: ThemeTokens): ThemeTokens {
  const { brand, scenePreset, siteTheme } = tenant;
  // Absence is not an inferred opt-in. Every renderer keeps its own old contract.
  if (siteTheme !== 'light' && siteTheme !== 'dark') return legacy ?? buildCinematicTheme(brand, scenePreset);
  const light = siteTheme === 'light';
  const primary = colour(brand.primary);
  const darkBase: Hex = primary && contrast('#ffffff', primary) >= AA ? primary : '#151513';
  const cinematic = buildCinematicTheme({ ...brand, primary: darkBase, text: null, buttonText: null }, scenePreset);
  const base = light ? buildTheme('light', { primary: '#ffffff', accent: colour(brand.accent) ?? '#e4ad83', fontFamily: brand.fontFamily }) : cinematic;
  const bg: Hex = light ? '#ffffff' : cinematic.bg as Hex;
  const sf: Hex = light ? '#ffffff' : cinematic.sf as Hex;
  const sf2: Hex = light ? '#f5f6f7' : cinematic.sf2 as Hex;
  const defaultInk: Hex = light ? '#202124' : '#ffffff';
  const accent: Hex = colour(brand.accent) ?? '#e4ad83';
  const selection = mix(accent, sf, .91);
  const accs = contrast(defaultInk, selection) >= AA ? selection : sf;
  const text = colour(brand.text), buttonText = colour(brand.buttonText);
  const surfaces = [bg, sf, sf2, accs];
  const tx = text && surfaces.every(s => contrast(text, s) >= AA) ? text : defaultInk;
  const muted = (amount: number): Hex => surfaces.reduce((ink, surface) => walk(ink, surface, AA, defaultInk), mix(tx, bg, amount));
  // Legacy inkOn's dark fallback is intentionally unchanged. Opt-in surfaces
  // verify that fallback too: mid-grey accents can need true black to pass AA.
  const legacyButtonInk = inkOn(accent);
  const automaticButtonInk = contrast(legacyButtonInk, accent) >= AA ? legacyButtonInk
    : contrast('#000000', accent) >= contrast('#ffffff', accent) ? '#000000' : '#ffffff';
  const onacc = buttonText && contrast(buttonText, accent) >= AA ? buttonText : automaticButtonInk;
  const acct = walk(accent, sf, AA, defaultInk);
  return {
    ...base, bg, sf, sf2, tx, tx2: muted(.2), tx3: muted(.34),
    hair: rgba(tx, .12), hair2: rgba(tx, .24),
    hero: bg, onhero: tx, onhero2: muted(.2),
    acc: accent, onacc, acct, accLargeText: walk(accent, bg, 3, defaultInk),
    accs, accA: accs, accOnSelection: walk(accent, accs, AA, defaultInk),
    cta: accent, ctaSh: 'none', glow: 'none', heroGlow: 'none',
    glass: rgba(bg, .96), glassDock: rgba(bg, .98), onDock2: muted(.2),
    sceneGlass: rgba(bg, .92), sceneGlassSoft: rgba(sf2, .94), sceneLine: rgba(tx, .2),
    glassLine: rgba(tx, .14),
  };
}

export function siteThemeClass(siteTheme?: 'light' | 'dark' | null): 'light' | 'dark' | 'legacy' {
  return siteTheme === 'light' || siteTheme === 'dark' ? siteTheme : 'legacy';
}
