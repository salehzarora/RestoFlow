/** Owner rollout gate. Changing this requires a separately approved rollout. */
export const LIVE_ORDERING_RELEASED = false;

/** Public origin only. Credentials and endpoint paths never cross this seam. */
export const ORDER_PROJECT_ORIGIN = 'https://oqmevrndtivqxgyvcmwy.supabase.co';

export function orderEndpointOrigin(value: string): string {
  const url = new URL(value);
  if (url.origin !== ORDER_PROJECT_ORIGIN || url.pathname !== '/' || url.search !== '' || url.hash !== '' || url.username !== '' || url.password !== '') {
    throw new Error('Unsupported web-order origin');
  }
  return url.origin;
}
