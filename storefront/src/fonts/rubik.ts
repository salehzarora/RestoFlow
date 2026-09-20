import localFont from 'next/font/local';

/**
 * Rubik, self-hosted. One VARIABLE woff2 per script subset covers the whole
 * 400-900 range the design uses, so six static weights cost three files.
 * `font-src 'self'` forbids gstatic, which is why these are vendored.
 */
export const rubik = localFont({
  src: [
    { path: './rubik-latin-var.woff2', weight: '400 900', style: 'normal' },
    { path: './rubik-arabic-var.woff2', weight: '400 900', style: 'normal' },
    { path: './rubik-hebrew-var.woff2', weight: '400 900', style: 'normal' },
  ],
  display: 'swap',
  variable: '--sf-font',
  fallback: ['Segoe UI', 'Tahoma', 'sans-serif'],
  preload: true,
});
