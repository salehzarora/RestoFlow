import { Unknown } from '@/ui/storefront/Unknown';
import { DEFAULT_LOCALE } from '@/i18n/locales';

/**
 * Replaces Next's BUILT-IN not-found page, which ships inline `style`
 * attributes and an inline <style> element that the committed
 * `style-src 'self'` CSP blocks — so the built-in renders unstyled. This is
 * also screen 11 of the design: an unknown or unpublished slug lands here and
 * learns nothing about any tenant.
 */
export default function NotFound() {
  return <Unknown locale={DEFAULT_LOCALE} />;
}
