import type { WireService } from './decode';

/** Other restaurants remain disabled; Maps Burger has a server-controlled rollout. */
export const LIVE_ORDERING_RELEASED = false;

/** This allowlist is only a UI gate; the server authorizes the exact branch. */
export const LIVE_PICKUP_ROLLOUT_SLUG = 'mapsburger';

export function liveOrderingEnabled(slug: string, service: WireService): boolean {
  return (LIVE_ORDERING_RELEASED || slug === LIVE_PICKUP_ROLLOUT_SLUG)
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
