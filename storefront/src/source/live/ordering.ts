import type { WireService } from './decode';

/** General rollout remains disabled; the bounded Maps Burger pilot is separate. */
export const LIVE_ORDERING_RELEASED = false;

/** The server alone admits the owner-bound, expiring, single-request pilot. */
export const MANUAL_ORDER_PILOT_SLUG = 'mapsburger';

export function liveOrderingEnabled(slug: string, service: WireService): boolean {
  return (LIVE_ORDERING_RELEASED || slug === MANUAL_ORDER_PILOT_SLUG)
    && service.ordering_enabled
    && service.state === 'open'
    && service.pickup_enabled;
}

/** Public origin only. Credentials and endpoint paths never cross this seam. */
export const ORDER_PROJECT_ORIGIN = 'https://oqmevrndtivqxgyvcmwy.supabase.co';

export function orderEndpointOrigin(value: string): string {
  const url = new URL(value);
  if (url.origin !== ORDER_PROJECT_ORIGIN || url.pathname !== '/' || url.search !== '' || url.hash !== '' || url.username !== '' || url.password !== '') {
    throw new Error('Unsupported web-order origin');
  }
  return url.origin;
}
