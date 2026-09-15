/**
 * Theme seam for the placeholder shell. Values are emitted as CSS custom
 * properties by app/globals.css; this module is the typed source of truth so a
 * later design pass has one place to change. No colour is hard-coded in a
 * component.
 */
export const TOKENS = {
  colorBackground: '#0f1115',
  colorSurface: '#171a21',
  colorText: '#f4f5f7',
  colorMuted: '#a6adbb',
  colorAccent: '#c9a227',
  colorFocus: '#7cc4ff',
  radius: '12px',
  maxWidth: '40rem',
} as const;

export type ThemeToken = keyof typeof TOKENS;
