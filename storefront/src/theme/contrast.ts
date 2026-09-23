/**
 * Colour maths ported verbatim in BEHAVIOUR from the approved design handoff
 * (`prototype/storefront-data.js`). The handoff is explicit that the hex codes
 * in TOKENS.json are the Maps Burger *output* of these rules — so this module
 * implements the derivation and no resolved tenant colour is hard-coded.
 *
 * WCAG relative luminance and contrast ratio, per the same definitions the
 * design used.
 */

export type Hex = string;

const HEX6 = /^#[0-9a-fA-F]{6}$/;
const HEX3 = /^#[0-9a-fA-F]{3}$/;

/** True for `#rgb` or `#rrggbb`. Nothing else is accepted anywhere. */
export function isHex(value: string): boolean {
  return HEX6.test(value) || HEX3.test(value);
}

export function hexToRgb(hex: Hex): [number, number, number] {
  let h = hex.replace('#', '');
  if (h.length === 3) {
    h = h
      .split('')
      .map((c) => c + c)
      .join('');
  }
  const n = Number.parseInt(h, 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

export function rgbToHex(rgb: readonly number[]): Hex {
  return (
    '#' +
    rgb
      .map((v) => Math.round(Math.max(0, Math.min(255, v))).toString(16).padStart(2, '0'))
      .join('')
  );
}

/** WCAG 2.x relative luminance. */
export function luminance(hex: Hex): number {
  const [r, g, b] = hexToRgb(hex).map((v) => {
    const c = v / 255;
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** WCAG contrast ratio, always >= 1. Order of arguments does not matter. */
export function contrast(a: Hex, b: Hex): number {
  const la = luminance(a);
  const lb = luminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

/** Linear RGB mix. `t` 0 keeps `a`, 1 becomes `b`. */
export function mix(a: Hex, b: Hex, t: number): Hex {
  const A = hexToRgb(a);
  const B = hexToRgb(b);
  return rgbToHex(A.map((v, i) => v + (B[i] - v) * t));
}

/**
 * Walk `colour` toward `toward` in 5% steps until it clears `floor` against
 * `bg`. Returns `toward` if even that cannot reach the floor — the caller is
 * responsible for not offering a background where that happens.
 */
export function walk(colour: Hex, bg: Hex, floor: number, toward: Hex): Hex {
  for (let t = 0; t <= 1.0001; t += 0.05) {
    const x = mix(colour, toward, t);
    if (contrast(x, bg) >= floor) return x;
  }
  return toward;
}

/** White if it reaches AA on `bg`, otherwise the design's near-black ink. */
export function inkOn(bg: Hex): Hex {
  return contrast('#FFFFFF', bg) >= 4.5 ? '#FFFFFF' : '#0B1512';
}

export function toHsl(hex: Hex): [number, number, number] {
  const [r, g, b] = hexToRgb(hex).map((v) => v / 255);
  const mx = Math.max(r, g, b);
  const mn = Math.min(r, g, b);
  let h = 0;
  let s = 0;
  const l = (mx + mn) / 2;
  if (mx !== mn) {
    const d = mx - mn;
    s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
    h = mx === r ? (g - b) / d + (g < b ? 6 : 0) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
    h /= 6;
  }
  return [h, s, l];
}

export function fromHsl(h: number, s: number, l: number): Hex {
  const f = (p: number, q: number, t: number): number => {
    let x = t;
    if (x < 0) x += 1;
    if (x > 1) x -= 1;
    if (x < 1 / 6) return p + (q - p) * 6 * x;
    if (x < 0.5) return q;
    if (x < 2 / 3) return p + (q - p) * (2 / 3 - x) * 6;
    return p;
  };
  if (s === 0) return rgbToHex([l * 255, l * 255, l * 255]);
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  return rgbToHex([f(p, q, h + 1 / 3) * 255, f(p, q, h) * 255, f(p, q, h - 1 / 3) * 255]);
}

/**
 * Hue transplant: take the seed's hue, damp its saturation, and force a fixed
 * lightness for the role. This is what keeps a tenant's canvas recognisably
 * "their" colour without letting a saturated brand hue wreck the surfaces.
 */
export function tone(seed: Hex, lightness: number, satCap = 0.32): Hex {
  const [h, s] = toHsl(seed);
  return fromHsl(h, Math.min(s, satCap), lightness);
}

export function rgba(hex: Hex, alpha: number): string {
  const [r, g, b] = hexToRgb(hex);
  return `rgba(${r},${g},${b},${alpha})`;
}
