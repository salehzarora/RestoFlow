'use client';

/**
 * Applies the derived tenant theme as CSS custom properties.
 *
 * WHY CSSOM AND NOT A STYLE PROP: the committed CSP is `style-src 'self'` with
 * no `'unsafe-inline'`, so both inline `<style>` elements and `style=`
 * attributes are blocked — PG-1/U-0 demonstrated the block and proved the
 * detector is non-vacuous. PG-1/U-8 proved `setProperty` is unaffected, because
 * CSSOM mutation is not an inline-style source. So the theme is applied here,
 * and the emitted HTML contains no style attribute of our authorship.
 *
 * The module's neutral platform fallbacks paint the first frame; this swaps in
 * the tenant's derived values on mount.
 */
import { useLayoutEffect, useRef, type ReactNode } from 'react';
import { themeEntries, type ThemeTokens } from '@/theme/buildTheme';

export function ThemeScope({
  tokens,
  className,
  children,
  dir,
  menuImageDim,
  scenePreset,
}: {
  tokens: ThemeTokens;
  className: string;
  children: ReactNode;
  dir: 'rtl' | 'ltr';
  /** Only Home supplies this presentation value; other screens stay unchanged. */
  menuImageDim?: number | null;
  /** Explicit opt-in, independent of the merchant's stored colour palette. */
  scenePreset?: 'reference_dark' | null;
}) {
  const host = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    const el = host.current;
    if (!el) return;
    for (const [name, value] of themeEntries(tokens)) {
      el.style.setProperty(name, value);
    }
    if (typeof menuImageDim === 'number' && Number.isInteger(menuImageDim) && menuImageDim >= 0 && menuImageDim <= 80) {
      el.style.setProperty('--menu-image-dim', String(menuImageDim / 100));
    } else el.style.removeProperty('--menu-image-dim');
  }, [tokens, menuImageDim]);

  return (
    <div ref={host} className={className} dir={dir} data-sf-root="" data-sf-scene={scenePreset === 'reference_dark' ? scenePreset : undefined}>
      {children}
    </div>
  );
}
