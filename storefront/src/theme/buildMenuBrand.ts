/** Home-only decoration; raw profile primary/background and accent retain their contracts. */
import type { Tenant } from '../source/types';
import type { ThemeTokens } from './buildTheme';
import { AA } from './buildTheme';
import { contrast, isHex, mix, walk, type Hex } from './contrast';

export function buildMenuBrand(tenant: Tenant, tokens: ThemeTokens): ThemeTokens {
  const raw = tenant.brand.primary;
  const secondary = isHex(raw) ? raw.toLowerCase() as Hex : tokens.tx as Hex;
  const surface = tokens.sf as Hex;
  const ink = contrast('#ffffff', surface) >= contrast('#000000', surface) ? '#ffffff' : '#000000';
  const accent = tokens.acc as Hex, text = tokens.tx as Hex, button = tokens.onacc as Hex;
  // Washes never reduce the contrast already established by the site theme.
  // Flatten only the painted surface when a custom text colour needs it.
  const gradient = (from: Hex, to: Hex, copy: Hex, fallback: Hex): [Hex, Hex] =>
    Array.from({ length: 21 }, (_, i) => mix(from, to, i / 20)).every(s => contrast(copy, s) >= AA + .02)
      ? [from, to] : [fallback, fallback];
  const [menuChipFrom, menuChipTo] = gradient(mix(accent, surface, .93), mix(secondary, surface, .95), text, surface);
  const [menuDockFrom, menuDockTo] = gradient(mix(accent, surface, .76), surface, text, surface);
  const darker = mix(accent, '#000000', .1), lighter = mix(accent, '#ffffff', .1);
  const [menuActiveFrom, menuActiveTo] = gradient(contrast(button, darker) >= contrast(button, lighter) ? darker : lighter, accent, button, accent);
  return { ...tokens, brandSecondary: walk(secondary, surface, AA, ink),
    menuChipFrom, menuChipTo, menuDockFrom, menuDockTo, menuActiveFrom, menuActiveTo };
}
