import { parseRoute } from './routes';

/** Keep the live RAM cart and details under their existing pre-submit root.
 * Canonical Arabic builders remain unprefixed; an already-open `/ar`
 * storefront must not cross to that separate root while carrying a cart. */
export function cartNavigationHref(href: string, pathname: string | null): string {
  if (!pathname?.startsWith('/ar/s/')) return href;
  const current = parseRoute(pathname);
  const target = parseRoute(href);
  const journey = ['menu', 'cart', 'checkout', 'review'];
  const sourceAllowed = journey.includes(current.kind) ||
    (current.kind === 'payment' && ['cart', 'checkout', 'review'].includes(target.kind)) ||
    (current.kind === 'search' && target.kind === 'checkout');
  if (current.locale !== 'ar' || !current.slug || !sourceAllowed || target.locale !== 'ar' ||
      target.slug !== current.slug || !journey.includes(target.kind) ||
      href !== `/s/${current.slug}/${target.kind}` ||
      pathname !== `/ar/s/${current.slug}/${current.kind}`) return href;
  return `/ar${href}`;
}
