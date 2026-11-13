import { createHash } from 'node:crypto';
import { localMediaTarget, logicalMediaUrl } from './live-transport.mjs';

// Only the six optional fields changed by this synthetic settings acceptance.
export const responsiveBannerKeys = Object.freeze(['menu_banner_layout', 'menu_banner_desktop_media_id',
  'menu_banner_mobile_height_px', 'menu_banner_desktop_height_px', 'menu_banner_desktop_focal_x', 'menu_banner_desktop_focal_y']);
export function responsiveBannerFixture(document) {
  const copy = structuredClone(document);
  if (!copy.appearance || typeof copy.appearance !== 'object' || Array.isArray(copy.appearance)) throw new Error('Banner fixture requires existing appearance');
  const materializedNullKeys = responsiveBannerKeys.filter(key => !Object.hasOwn(copy.appearance, key));
  for (const key of materializedNullKeys) copy.appearance[key] = null;
  return { document: copy, materializedNullKeys };
}
export function legacyBannerDocument(document) {
  const copy = structuredClone(document);
  for (const key of responsiveBannerKeys) delete copy.appearance?.[key];
  return copy;
}
export function legacyBannerMenu(envelope) {
  const copy = structuredClone(envelope);
  delete copy.menu_banner_desktop_images_v1;
  for (const key of ['menu_banner_layout', 'menu_banner_desktop_url', 'menu_banner_width', 'menu_banner_height',
    'menu_banner_desktop_width', 'menu_banner_desktop_height', 'menu_banner_mobile_height_px',
    'menu_banner_desktop_height_px', 'menu_banner_desktop_focal_x', 'menu_banner_desktop_focal_y']) delete copy.content_v1?.appearance?.[key];
  return copy;
}

// A same-resource response can still be an older ISR document after a height
// edit. All presentation fields must be current before a fresh-context proof.
export function responsiveBannerReady(expected, actual) {
  return Number.isFinite(expected?.height) && expected.height > 0 && Number.isFinite(actual?.height)
    && Math.abs(actual.height - expected.height) < .02 && actual.focus === expected.focus
    && actual.resourceMatch === true && actual.layoutResponsive === true && actual.hydrated === true;
}

// Observe an already-issued native Dashboard image request. The existing URL
// admission helpers stay authoritative; this helper makes no request or rewrite.
export function dashboardImageHash({ url, method, resourceType, headers }) {
  if (method !== 'GET' || !headers || typeof headers !== 'object' || Array.isArray(headers)) throw new Error('dashboard_media_evidence_denied');
  const h = new Headers(headers);
  if (resourceType !== 'image' || ['authorization', 'apikey', 'cookie'].some(key => h.has(key))
    || localMediaTarget(logicalMediaUrl(url), method) !== url) throw new Error('dashboard_media_evidence_denied');
  return new URL(url).pathname.split('/').at(-1).slice(0, -5);
}
export function dashboardImageBytesMatch(hash, status, bytes) {
  return typeof hash === 'string' && /^[0-9a-f]{64}$/.test(hash) && status === 200
    && bytes instanceof Uint8Array && bytes.byteLength > 0 && createHash('sha256').update(bytes).digest('hex') === hash;
}
export function dashboardMediaReady(requests, verified, checks) {
  return Number.isInteger(requests) && requests > 0 && verified === requests
    && Array.isArray(checks) && checks.length === requests && checks.every(value => value === true);
}
