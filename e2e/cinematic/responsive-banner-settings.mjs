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
    && actual.resourceMatch === true && actual.layoutResponsive === true && actual.hydrated === true
    && typeof expected.serviceState === 'string' && expected.serviceState.length > 0 && actual.serviceState === expected.serviceState;
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

// Diagnostic enums only. Never export an exception message or change a guard.
export function classifyMediaReadError(error) {
  const message = typeof error === 'string' ? error : error instanceof Error ? error.message : '';
  if (/No data found for resource|No resource with given identifier|Network\.getResponseBody/i.test(message)) return 'body-unavailable';
  if (/Target.*closed|page.*closed|context.*closed|browser.*closed/i.test(message)) return 'context-closed';
  if (/net::ERR_ABORTED|\babort(?:ed)?\b|cancel(?:led|ed)/i.test(message)) return 'aborted';
  return 'unclassified';
}

// Evidence for the synthetic banner case only. Never serialize a whole reply,
// private object key, session, arbitrary string or customer-entered value.
const appearanceEvidenceKeys = ['menu_banner_media_id', 'menu_banner_desktop_media_id', 'menu_banner_enabled',
  'menu_banner_layout', 'menu_banner_focal_x', 'menu_banner_focal_y', 'menu_banner_desktop_focal_x',
  'menu_banner_desktop_focal_y', 'menu_banner_mobile_height_px', 'menu_banner_desktop_height_px',
  'menu_intro_visible', 'menu_background_media_id', 'menu_background_dim', 'site_theme', 'scene_preset',
  'font_family', 'text_color', 'button_text_color'];
export function evidenceScalar(value, present = true) {
  const type = value === null ? 'null' : Array.isArray(value) ? 'array' : typeof value;
  const result = { present, type };
  if (value === null || typeof value === 'boolean' || (typeof value === 'number' && Number.isFinite(value))) result.value = value;
  else if (typeof value === 'number') result.specialNumber = String(value);
  else if (typeof value === 'string') {
    // Public presentation enums/colours are useful verbatim; identifiers and
    // private keys are comparable through their digest, not exported verbatim.
    if (['responsive', 'light', 'dark', 'legacy_brand', 'reference_dark', 'alexandria', 'rubik', 'system', 'default'].includes(value)
      || /^#[0-9a-f]{3,8}$/i.test(value)) result.value = value;
    else { result.sha256 = createHash('sha256').update(value).digest('hex'); result.length = value.length; }
  }
  return result;
}
export function bannerDocumentEvidence(document) {
  const appearance = document?.appearance;
  return { appearance: Object.fromEntries(appearanceEvidenceKeys.map(key => [key,
    evidenceScalar(appearance?.[key], !!appearance && Object.hasOwn(appearance, key))])),
    media: Object.fromEntries(['promo', 'story'].map(key => [key + '.editorial_media_id',
      evidenceScalar(document?.[key]?.editorial_media_id, !!document?.[key] && Object.hasOwn(document[key], 'editorial_media_id'))])) };
}
export function bannerComparisonEvidence(assertion, field, expected, actual) {
  return { assertion, field, expected: evidenceScalar(expected), actual: evidenceScalar(actual), equal: Object.is(expected, actual) };
}
export function bannerAssertionFailure(error) {
  const matcher = error?.matcherResult;
  const name = typeof matcher?.name === 'string' && /^to[A-Za-z]{1,40}$/.test(matcher.name) ? matcher.name : 'unclassified';
  const locations = typeof error?.stack === 'string' ? [...error.stack.matchAll(/(dashboard\.spec|responsive-banner-settings)\.ts:(\d+):(\d+)/g)].slice(0, 6)
    .map(match => ({ file: match[1] + '.ts', line: Number(match[2]), column: Number(match[3]) })) : [];
  return { matcher: name, ...(matcher && Object.hasOwn(matcher, 'expected') ? { expected: evidenceScalar(matcher.expected) } : {}),
    ...(matcher && Object.hasOwn(matcher, 'actual') ? { actual: evidenceScalar(matcher.actual) } : {}),
    sourceLine: locations[0]?.line ?? null, sourceColumn: locations[0]?.column ?? null, sourceFrames: locations };
}
export function mediaReadErrorDetail(error) {
  const message = typeof error === 'string' ? error : error instanceof Error ? error.message : '';
  if (/No data found for resource/i.test(message)) return 'no-data';
  if (/No resource with given identifier/i.test(message)) return 'no-resource';
  if (/Network\.getResponseBody/i.test(message)) return 'get-body-error';
  if (/Target.*closed|page.*closed|context.*closed|browser.*closed/i.test(message)) return 'context-closed';
  if (/net::ERR_ABORTED|\babort(?:ed)?\b|cancel(?:led|ed)/i.test(message)) return 'aborted';
  return 'unclassified';
}
const evidencePhases = new Set(['baseline', 'upload-save-first-banner', 'replace-save-banner', 'verify-retained-private-source',
  'public-banner-read-and-render', 'banner-focal-persistence', 'banner-responsive', 'restored-banner-public-read-and-render',
  'independent-responsive-settings-ui-save-readback', 'after-responsive-restoration', 'clear-banner-only', 'clear-interface',
  'clear-save-result', 'clear-authenticated-readback', 'clear-preservation', 'clear-public-read', 'clear-storefront',
  'final-byte-guard', 'complete']);
export function bannerEvidencePhase(value) {
  if (typeof value !== 'string') return 'unclassified';
  return evidencePhases.has(value) || /^responsive-(?:phone-height|desktop-height|phone-auto|desktop-uploaded|desktop-replaced|desktop-selected|desktop-cleared)-(?:390|1280)$/.test(value)
    ? value : 'unclassified';
}
