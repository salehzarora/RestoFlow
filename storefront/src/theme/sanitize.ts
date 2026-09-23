/**
 * Tenant input sanitation.
 *
 * UI-001 supports a DELIBERATELY NARROW tenant colour domain (approved decision
 * 7): only primaries dark enough that white ink reaches AA on the hero and on
 * the hero-tinted glass survive. Anything else is rejected and replaced with the
 * BIZBOT-neutral default rather than silently rendered at a failing ratio.
 * Broadening this domain is design work, not an implementation decision.
 */
import { contrast, isHex, rgbToHex, hexToRgb, type Hex } from './contrast';
import { AA } from './buildTheme';

/**
 * BIZBOT-neutral defaults. These are PLATFORM colours, not a tenant's, and are
 * what an unsupported or missing tenant value falls back to.
 */
export const NEUTRAL_PRIMARY: Hex = '#13322a';
export const NEUTRAL_ACCENT_DARK: Hex = '#e07b2c';
export const NEUTRAL_ACCENT_LIGHT: Hex = '#b8460f';

/** `--glass` composites the primary at 74% over the hero photo. */
const GLASS_ALPHA = 0.74;

/** Worst-case glass composite: primary at 74% over WHITE (the lightest photo). */
export function glassOverWhite(primary: Hex): Hex {
  const [r, g, b] = hexToRgb(primary);
  return rgbToHex([
    r * GLASS_ALPHA + 255 * (1 - GLASS_ALPHA),
    g * GLASS_ALPHA + 255 * (1 - GLASS_ALPHA),
    b * GLASS_ALPHA + 255 * (1 - GLASS_ALPHA),
  ]);
}

export interface PrimaryVerdict {
  readonly supported: boolean;
  readonly heroRatio: number;
  readonly glassRatio: number;
  readonly reason?: string;
}

/**
 * A primary is supported only when WHITE reaches AA on BOTH the flat hero and
 * the worst-case glass composite. Both are required because the design paints
 * white ink on each.
 */
export function inspectPrimary(primary: string): PrimaryVerdict {
  if (!isHex(primary)) {
    return { supported: false, heroRatio: 0, glassRatio: 0, reason: 'not a hex colour' };
  }
  const heroRatio = contrast('#FFFFFF', primary);
  const glassRatio = contrast('#FFFFFF', glassOverWhite(primary));
  if (heroRatio < AA) {
    return { supported: false, heroRatio, glassRatio, reason: 'white ink below AA on the hero' };
  }
  if (glassRatio < AA) {
    return { supported: false, heroRatio, glassRatio, reason: 'white ink below AA on hero glass' };
  }
  return { supported: true, heroRatio, glassRatio };
}

export function isSupportedPrimary(primary: string): boolean {
  return inspectPrimary(primary).supported;
}

/** Returns the primary if supported, otherwise the BIZBOT-neutral default. */
export function sanitizePrimary(primary: string | null | undefined): Hex {
  if (typeof primary !== 'string') return NEUTRAL_PRIMARY;
  return inspectPrimary(primary).supported ? normaliseHex(primary) : NEUTRAL_PRIMARY;
}

/**
 * An accent only has to BE a colour: every place it is used as ink is walked to
 * AA by the theme derivation, so no accent can produce a failing pair.
 */
export function sanitizeAccent(accent: string | null | undefined, preset: 'dark' | 'light'): Hex {
  const fallback = preset === 'dark' ? NEUTRAL_ACCENT_DARK : NEUTRAL_ACCENT_LIGHT;
  if (typeof accent !== 'string' || !isHex(accent)) return fallback;
  return normaliseHex(accent);
}

/** Expand `#abc` to `#aabbcc` and lower-case, so equality is meaningful. */
export function normaliseHex(hex: string): Hex {
  return rgbToHex(hexToRgb(hex)).toLowerCase();
}

/**
 * Storefront slugs are the public URL identity of a tenant. Keep them to a
 * conservative shape so a slug can never introduce a path segment, a scheme, or
 * a case-folding collision.
 */
const SLUG = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;

/**
 * The `typeof` check is NOT redundant with the type annotation.
 *
 * `RegExp.prototype.test` COERCES its argument, so `SLUG.test(null)` tests the
 * string "null" - which matches this pattern - and the function returned true
 * for null, undefined, 7 and true. Types are erased at runtime, and both
 * callers of this are trust boundaries that build a STORAGE KEY from the
 * result, so the check has to exist in the code, not only in the annotation.
 * Returning a type predicate makes that guarantee usable by callers.
 */
export function isValidSlug(value: unknown): value is string {
  return typeof value === 'string' && SLUG.test(value);
}

/** Request references are short, upper-case and dash-separated, e.g. MB-2487. */
const REF = /^[A-Z0-9]{1,8}-[A-Z0-9]{1,12}$/;

/** Same coercion hazard as isValidSlug; guarded the same way. */
export function isValidRef(value: unknown): value is string {
  return typeof value === 'string' && REF.test(value);
}

/**
 * Characters removed from tenant free text, as code point RANGES.
 *
 * React escapes on render and the storefront never uses
 * dangerouslySetInnerHTML, so sanitizeText is a LENGTH and control-character
 * guard, not an HTML sanitiser.
 *
 * Deliberately NOT a regex literal built from unicode escapes: such a literal
 * is one careless edit away from containing the actual control and
 * bidi-override characters it describes, which makes the file binary to git,
 * unreviewable in a diff, and - for the bidi ones - able to reorder how the
 * surrounding source itself reads. Ranges say the same thing in pure ASCII.
 */
const STRIPPED_RANGES: ReadonlyArray<readonly [number, number]> = [
  [0x00, 0x08], // C0 controls, keeping tab and the newlines a tagline may use
  [0x0b, 0x0c],
  [0x0e, 0x1f],
  [0x7f, 0x7f], // DEL
  [0x202a, 0x202e], // bidi embeddings and overrides
  [0x2066, 0x2069], // bidi isolates
];

function isStripped(codePoint: number): boolean {
  return STRIPPED_RANGES.some(([lo, hi]) => codePoint >= lo && codePoint <= hi);
}

export function sanitizeText(value: string | null | undefined, maxLength: number): string {
  if (typeof value !== 'string') return '';
  let kept = '';
  for (const character of value) {
    const codePoint = character.codePointAt(0);
    if (codePoint !== undefined && isStripped(codePoint)) continue;
    kept += character;
  }
  const cleaned = kept.trim();
  return cleaned.length > maxLength ? cleaned.slice(0, maxLength) : cleaned;
}
