/**
 * Tenant theme derivation.
 *
 * Behaviour is ported from the approved handoff's `buildTheme(preset, primary,
 * accent)`. The handoff states the rule, not the result: "Implement the
 * derivation, not the hex codes." No Maps Burger colour appears here — the demo
 * tenant's values live in the fixture source and only ever arrive as arguments.
 *
 * Five owner-approved contrast corrections (PX-3 / PX-4) are applied. Each is
 * marked `PX-3` or `PX-4` and each is the minimum rule-level change that fixes
 * the ratio while preserving the approved visual intent. They are asserted as
 * golden vectors in tests/sf-theme.test.mjs.
 */
import { contrast, inkOn, mix, rgba, tone, walk, type Hex } from './contrast';

export type Preset = 'dark' | 'light';

export interface TenantColours {
  readonly primary: Hex;
  readonly accent: Hex;
}

/** Every CSS custom property the storefront paints with, without the `--`. */
export type ThemeTokens = Readonly<Record<string, string>>;

/** Semantic colours are FIXED per preset and never derive from the brand. */
const SEMANTIC = {
  dark: {
    tx: '#FFF4E6',
    tx2: '#D8CEC2',
    tx3: '#A79C90',
    hair: 'rgba(255,244,230,.10)',
    hair2: 'rgba(255,244,230,.20)',
    scrim: 'rgba(6,8,7,.66)',
    ok: '#43E3AC',
    okbg: '#0E3A2C',
    warn: '#FBBF24',
    warnbg: '#78350F',
    bad: '#F87171',
    badbg: '#7F1D1D',
    info: '#93C5FD',
    infobg: '#1E3A8A',
    promoWarm: '#F3E6D2',
    promoWarm2: '#E7D3B7',
  },
  light: {
    tx: '#1F2937',
    tx2: '#4B5563',
    tx3: '#626D79',
    hair: '#E3E8E5',
    hair2: '#C9D3CE',
    scrim: 'rgba(17,24,39,.55)',
    ok: '#15803D',
    okbg: '#DCFCE7',
    warn: '#B45309',
    warnbg: '#FEF3C7',
    bad: '#B91C1C',
    badbg: '#FEE2E2',
    info: '#1D4ED8',
    infobg: '#DBEAFE',
    promoWarm: '#FBF3E6',
    promoWarm2: '#F0E2CC',
  },
} as const;

export const AA = 4.5;
export const AA_LARGE = 3;

export function buildTheme(preset: Preset, { primary, accent }: TenantColours): ThemeTokens {
  const dark = preset === 'dark';
  const s = SEMANTIC[preset];
  const toWhite = dark ? '#FFFFFF' : '#000000';

  const bg: Hex = dark ? mix(tone(primary, 0.09), '#101413', 0.62) : '#F4F6F5';
  const sf: Hex = dark ? mix(tone(primary, 0.14), '#161A19', 0.58) : '#FFFFFF';
  const sf2: Hex = dark ? mix(tone(primary, 0.19), '#1D2220', 0.55) : '#EEF2F0';

  const onhero = inkOn(primary);
  const onacc = inkOn(accent);

  // Accent as TEXT must reach AA on the card surface.
  const acct = walk(accent, sf, AA, toWhite);

  // PX-4 — focus ring: the handoff walks `ring` against the canvas only, but the
  // ring also lands on cards and on the accent selection bed. Walk against the
  // WORST of the surfaces it is actually drawn on, so 3:1 holds everywhere.
  const accsRaw: Hex = dark ? mix(accent, sf, 0.82) : mix(accent, '#FFFFFF', 0.88);
  const ringCandidates: Hex[] = [bg, sf, sf2, accsRaw];
  let ring = accent;
  for (let t = 0; t <= 1.0001; t += 0.05) {
    const x = mix(accent, toWhite, t);
    if (ringCandidates.every((surface) => contrast(x, surface) >= AA_LARGE)) {
      ring = x;
      break;
    }
    if (t > 1) ring = toWhite;
  }
  if (!ringCandidates.every((surface) => contrast(ring, surface) >= AA_LARGE)) {
    // Could not satisfy every surface; fall back to the ink that certainly can.
    ring = dark ? '#FFFFFF' : '#0B1512';
  }

  // PX-3 — light accent-on-selection-bed: accent text sitting on `accs` is a
  // tint-on-tint pair the base rule never checked. Walk it to AA on that bed.
  const accOnSelection = walk(accent, accsRaw, AA, toWhite);

  // PX-3 — dark danger text on the danger bed: #F87171 on #7F1D1D is below AA.
  const badText = walk(s.bad, s.badbg, AA, toWhite);

  // PX-3 — danger-button ink: derive from the fill rather than assuming white.
  const onBad = inkOn(s.bad);

  // PX-4 — light CTA gradient stop: white ink is validated against the mid
  // accent, but the 0% stop is the LIGHTEST part of the gradient. Cap how far
  // that stop may lighten so `onacc` keeps AA across the whole sweep.
  let ctaLightStop = mix(accent, '#FFFFFF', 0.16);
  if (contrast(onacc, ctaLightStop) < AA) {
    for (let t = 0.16; t >= 0; t -= 0.02) {
      const candidate = mix(accent, '#FFFFFF', t);
      if (contrast(onacc, candidate) >= AA) {
        ctaLightStop = candidate;
        break;
      }
      ctaLightStop = accent;
    }
  }
  const ctaDarkStop = mix(accent, '#000000', 0.18);

  const dockBase: Hex = dark ? mix(primary, bg, 0.55) : '#FFFFFF';
  const onDock2 = walk(dark ? '#C0CBC6' : '#4B5563', dockBase, AA, toWhite);
  const heroInkIsWhite = onhero === '#FFFFFF';

  return {
    bg,
    sf,
    sf2,
    hair: s.hair,
    hair2: s.hair2,
    tx: s.tx,
    tx2: s.tx2,
    tx3: s.tx3,
    scrim: s.scrim,
    ok: s.ok,
    okbg: s.okbg,
    warn: s.warn,
    warnbg: s.warnbg,
    bad: s.bad,
    badbg: s.badbg,
    badText,
    onBad,
    info: s.info,
    infobg: s.infobg,
    promoWarm: s.promoWarm,
    promoWarm2: s.promoWarm2,
    promoBg: dark ? mix(accent, '#101413', 0.84) : mix(accent, '#FFFFFF', 0.88),
    hero: primary,
    onhero,
    onhero2: heroInkIsWhite ? 'rgba(255,255,255,.78)' : 'rgba(11,21,18,.72)',
    acc: accent,
    onacc,
    acct,
    accOnSelection,
    ring,
    accs: accsRaw,
    cta: `linear-gradient(135deg, ${ctaLightStop} 0%, ${accent} 52%, ${ctaDarkStop} 100%)`,
    ctaSh: `0 12px 28px -8px ${rgba(accent, dark ? 0.6 : 0.42)}, 0 2px 6px rgba(0,0,0,${
      dark ? 0.35 : 0.1
    }), inset 0 1px 0 rgba(255,255,255,.28)`,
    glow: dark ? `0 0 14px ${rgba(accent, 0.55)}` : `0 0 10px ${rgba(accent, 0.28)}`,
    accA: rgba(accent, dark ? 0.16 : 0.12),
    accB: rgba(accent, dark ? 0.45 : 0.38),
    heroGlow: `radial-gradient(90% 70% at 50% 108%, ${rgba(accent, dark ? 0.4 : 0.3)}, transparent 72%)`,
    glass: rgba(primary, 0.74),
    glassDock: dark ? rgba(dockBase, 0.92) : 'rgba(255,255,255,.94)',
    onDock2,
    glassLine: heroInkIsWhite ? 'rgba(255,255,255,.14)' : 'rgba(0,0,0,.14)',
  };
}

/** `--name: value` pairs, for CSSOM application. Never an inline style string. */
export function themeEntries(tokens: ThemeTokens): [string, string][] {
  return Object.entries(tokens).map(([k, v]) => [`--${k}`, v]);
}
