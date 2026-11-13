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
