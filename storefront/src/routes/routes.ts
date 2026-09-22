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

/**
 * The menu screen. This build splits the handoff's single `/s/:slug` into two
 * static documents - the intro at `/s/:slug` and the menu at `/s/:slug/menu` -
 * so every builder that means "the menu" has to say so explicitly.
 */
export function menuPath(locale: Locale, slug: string): string {
  return `${storefrontPath(locale, slug)}/menu`;
}

/** SCREEN_MAP.json:113 `routeIntent: "/s/:slug/search"`. */
export function searchPath(locale: Locale, slug: string): string {
  return `${storefrontPath(locale, slug)}/search`;
}

/**
 * The Phase D flow. Four real segments, one per screen, because the checkout
 * draft has to survive moving between them and only a shared LAYOUT above real
 * routes does that; the layout lives at the `s/[slug]` segment.
 *
 * SCREEN_MAP.json:203 `/s/:slug/cart`, :237 `/s/:slug/checkout`,
 * :277 `/s/:slug/payment`, :306 `/s/:slug/review`.
 */
export function cartPath(locale: Locale, slug: string): string {
  return `${storefrontPath(locale, slug)}/cart`;
}

export function checkoutPath(locale: Locale, slug: string): string {
  return `${storefrontPath(locale, slug)}/checkout`;
}

export function paymentPath(locale: Locale, slug: string): string {
  return `${storefrontPath(locale, slug)}/payment`;
}

export function reviewPath(locale: Locale, slug: string): string {
  return `${storefrontPath(locale, slug)}/review`;
}

export function requestPath(locale: Locale, ref: string): string {
  return `${localePrefix(locale)}/r/${ref}`;
}

export function localeHomePath(locale: Locale): string {
  return locale === DEFAULT_LOCALE ? '/' : `/${locale}`;
}

export interface ParsedRoute {
  readonly locale: Locale;
  readonly kind:
    | 'storefront'
    | 'menu'
    | 'search'
    | 'cart'
    | 'checkout'
    | 'payment'
    | 'review'
    | 'request'
    | 'localeHome'
    | 'unknown';
  readonly slug?: string;
  readonly ref?: string;
}

/**
 * The only leaf segments `/s/:slug/...` has. Whitelisted rather than pattern
 * matched, so a third screen cannot start parsing by accident: adding one is an
 * edit here, a builder above and a case in `switchLocalePath` below.
 */
const STOREFRONT_LEAVES = {
  menu: 'menu',
  search: 'search',
  cart: 'cart',
  checkout: 'checkout',
  payment: 'payment',
  review: 'review',
} as const;

function isLeaf(segment: string | undefined): segment is keyof typeof STOREFRONT_LEAVES {
  return segment !== undefined && Object.hasOwn(STOREFRONT_LEAVES, segment);
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
  if (rest.length === 3 && rest[0] === 's' && isValidSlug(rest[1]) && isLeaf(rest[2])) {
    return { locale, kind: rest[2], slug: rest[1] };
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
    case 'menu':
      return parsed.slug ? menuPath(target, parsed.slug) : null;
    case 'search':
      return parsed.slug ? searchPath(target, parsed.slug) : null;
    case 'cart':
      return parsed.slug ? cartPath(target, parsed.slug) : null;
    case 'checkout':
      return parsed.slug ? checkoutPath(target, parsed.slug) : null;
    case 'payment':
      return parsed.slug ? paymentPath(target, parsed.slug) : null;
    case 'review':
      return parsed.slug ? reviewPath(target, parsed.slug) : null;
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
