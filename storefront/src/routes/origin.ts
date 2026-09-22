/**
 * The CONFIGURED public origin of the storefront.
 *
 * It exists for exactly one consumer: the pre-filled WhatsApp message, whose
 * last line is a status link the restaurant will tap. The prototype ended that
 * line with the literal `bizbot.app/s/MB-2487` (Storefront.dc.html:768) - a
 * domain BIZBOT does not control in this repository and a path that contradicts
 * the pack's own `/r/:code` route. PACKET PX-2, approved in PG-0, replaces it
 * with "configured public origin + `/r/<ref>`".
 *
 * The value is the storefront's approved future host (PACKET DEPLOY-001,
 * `menu.bizbot.systems`). Nothing here fetches it, resolves it or checks that
 * it is attached: the domain, DNS and project creation stay separate,
 * unapproved gates, and this constant does not make any of them exist.
 * Configuration, not fixture data - it does not disappear with the fixtures.
 */
export const PUBLIC_ORIGIN = 'https://menu.bizbot.systems';

/** An absolute URL for a root-relative storefront path. */
export function absoluteUrl(path: string): string {
  return `${PUBLIC_ORIGIN}${path}`;
}
