import type { WireService } from './decode';

/** The current server envelope decides admission for every published tenant. */
export function liveOrderingEnabled(service: WireService): boolean {
  return service.ordering_enabled
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
