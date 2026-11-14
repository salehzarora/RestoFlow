// Passive, allowlisted evidence for the one isolated warm-menu clear journey.
// Never exports an envelope, header bag, session or raw server error.
export const BANNER_PUBLIC_FIELDS = ['menu_banner_url', 'menu_banner_desktop_url',
  'menu_banner_enabled', 'menu_banner_layout', 'menu_banner_width', 'menu_banner_height',
  'menu_banner_desktop_width', 'menu_banner_desktop_height', 'menu_banner_mobile_height_px',
  'menu_banner_desktop_height_px', 'menu_banner_focal_x', 'menu_banner_focal_y',
  'menu_banner_desktop_focal_x', 'menu_banner_desktop_focal_y'];
export function bannerPublicProjection(envelope) {
  const appearance = envelope?.content_v1?.appearance;
  return { ok: envelope?.ok === true, appearance: Object.fromEntries(BANNER_PUBLIC_FIELDS.map(key => {
    const present = !!appearance && Object.hasOwn(appearance, key), value = appearance?.[key];
    const permitted = key.endsWith('_url') ? value === null || typeof value === 'string' &&
      /^\/storage\/v1\/object\/public\/storefront-media\/[a-f0-9]{32}\/[a-f0-9]{64}\.webp$/.test(value)
      : value === null || typeof value === 'number' && Number.isFinite(value) || typeof value === 'boolean' || value === 'responsive';
    return [key, { present, type: value === null ? 'null' : typeof value, ...(present && permitted ? { value } : {}) }];
  })), desktopManifestPresent: !!envelope && Object.hasOwn(envelope, 'menu_banner_desktop_images_v1'),
    desktopManifestNull: envelope?.menu_banner_desktop_images_v1 === null };
}
export function bannerHtmlProjection(html, previousPaths) {
  // Next's script serializes props with escaped quotes. Read only the banner
  // scalar keys; no script, HTML, other tenant field or full props are exported.
  const normalized = html.replaceAll('\\"', '"');
  const props = [...normalized.matchAll(/"menuBanner":\{([^}]{0,6000})\}/g)].slice(0, 4).map(match => {
    const result = {};
    for (const key of ['image', 'desktopImage', 'enabled', 'layout', 'width', 'height', 'desktopWidth', 'desktopHeight']) {
      const scalar = match[1].match(new RegExp('"' + key + '":(null|true|false|[0-9]+|"[^"\\n]{0,240}")'));
      if (!scalar) continue;
      const value = JSON.parse(scalar[1]);
      if (key === 'image' || key === 'desktopImage') {
        if (value !== null && !/^https:\/\/oqmevrndtivqxgyvcmwy\.supabase\.co\/storage\/v1\/object\/public\/storefront-media\/[a-f0-9]{32}\/[a-f0-9]{64}\.webp$/.test(value)) continue;
      }
      result[key] = value;
    }
    return result;
  });
  return { bannerElements: (html.match(/data-sf-menu-banner="/g) || []).length,
    previousPaths: previousPaths.filter(Boolean).map(path => ({ path, present: html.includes(path) })), props };
}
export function safeRegenerationErrors(text) {
  return text.split(/\r?\n/).filter(line => /(?:Error:|DecodeError|revalidat.*(?:fail|error))/i.test(line))
    .slice(-12).map(line => ({ decoder: /decode|content_v1|menu_banner/i.test(line),
      regeneration: /revalidat/i.test(line), digest: /digest/.test(line),
      field: line.match(/(?:menu_banner[.\w]*|content_v1[.\w]*)/)?.[0] ?? null }));
}
