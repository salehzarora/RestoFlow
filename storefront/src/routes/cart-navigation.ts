import { parseRoute } from './routes';

/** Keep the live RAM cart under its existing root layout on direct cart/menu
 * links. Canonical Arabic builders remain unprefixed; an already-open `/ar`
 * storefront must not cross to that separate root while carrying a cart. */
export function cartNavigationHref(href: string, pathname: string | null): string {
  if (!pathname?.startsWith('/ar/s/')) return href;
  const current = parseRoute(pathname);
  const target = parseRoute(href);
  if (current.locale !== 'ar' || !current.slug || (current.kind !== 'menu' && current.kind !== 'cart') || target.locale !== 'ar' ||
      target.slug !== current.slug || (target.kind !== 'cart' && target.kind !== 'menu') ||
      href !== `/s/${current.slug}/${target.kind}` ||
      pathname !== `/ar/s/${current.slug}/${current.kind}`) return href;
  return `/ar${href}`;
}
