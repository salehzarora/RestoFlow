/**
 * Storefront URL shapes.
 *
 * Approved route strategy: statically pre-rendered fixture slugs under each
 * existing locale root, `/s/:slug` and `/r/:ref`, no rewrites and no change to
 * next.config.mjs. The UNPREFIXED path is the tenant's default locale; `/ar`,
 * `/he` and `/en` are the explicit ones.
 *
 * Every builder returns a root-relative path with no trailing slash, matching
 * `trailingSlash: false` + `cleanUrls: true` in the committed vercel.json.
 */
import { DEFAULT_LOCALE, LOCALES, isLocale, type Locale } from '@/i18n/locales';
import { isValidRef, isValidSlug } from '@/theme/sanitize';

/** `/ar` etc., or `''` for the default locale which owns the unprefixed root. */
export function localePrefix(locale: Locale): string {
  return locale === DEFAULT_LOCALE ? '' : `/${locale}`;
}

export function storefrontPath(locale: Locale, slug: string): string {
  return `${localePrefix(locale)}/s/${slug}`;
}

export function requestPath(locale: Locale, ref: string): string {
  return `${localePrefix(locale)}/r/${ref}`;
}

export function localeHomePath(locale: Locale): string {
  return locale === DEFAULT_LOCALE ? '/' : `/${locale}`;
}

export interface ParsedRoute {
  readonly locale: Locale;
  readonly kind: 'storefront' | 'request' | 'localeHome' | 'unknown';
  readonly slug?: string;
  readonly ref?: string;
}

/**
 * Parse a pathname back into its parts. Used by the language switcher to build
 * the SAME screen's URL in another locale without inventing a route.
 */
export function parseRoute(pathname: string): ParsedRoute {
  const segments = pathname.split('/').filter((s) => s.length > 0);

  let locale: Locale = DEFAULT_LOCALE;
  let rest = segments;
  if (segments.length > 0 && isLocale(segments[0])) {
    locale = segments[0];
    rest = segments.slice(1);
  }

  if (rest.length === 0) return { locale, kind: 'localeHome' };
  if (rest.length === 2 && rest[0] === 's' && isValidSlug(rest[1])) {
    return { locale, kind: 'storefront', slug: rest[1] };
  }
  if (rest.length === 2 && rest[0] === 'r' && isValidRef(rest[1])) {
    return { locale, kind: 'request', ref: rest[1] };
  }
  return { locale, kind: 'unknown' };
}

/**
 * The same screen in another language. Returns null when the current path is
 * not one this app owns, so the caller does a normal navigation instead of
 * rewriting to a URL that would not resolve.
 */
export function switchLocalePath(pathname: string, target: Locale): string | null {
  const parsed = parseRoute(pathname);
  switch (parsed.kind) {
    case 'storefront':
      return parsed.slug ? storefrontPath(target, parsed.slug) : null;
    case 'request':
      return parsed.ref ? requestPath(target, parsed.ref) : null;
    case 'localeHome':
      return localeHomePath(target);
    default:
      return null;
  }
}

/** Every locale's path for one storefront — used for hreflang alternates. */
export function storefrontAlternates(slug: string): Record<Locale, string> {
  const out = {} as Record<Locale, string>;
  for (const locale of LOCALES) out[locale] = storefrontPath(locale, slug);
  return out;
}
