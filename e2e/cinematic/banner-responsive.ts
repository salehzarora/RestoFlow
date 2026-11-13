import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { isDeepStrictEqual } from 'node:util';
import type { Locator, Page } from '@playwright/test';

// Exactly the optional appearance keys this synthetic responsive scenario edits.
// The existing writer preserves omitted keys; JSON null restores legacy meaning.
const responsiveFixtureKeys = ['site_theme', 'menu_intro_visible', 'menu_banner_enabled',
  'menu_banner_focal_x', 'menu_banner_focal_y'] as const;
export function completeResponsiveFixture<T extends { appearance: Record<string, unknown> }>(original: T) {
  const document = structuredClone(original);
  const materializedNullKeys = responsiveFixtureKeys.filter(key => !Object.hasOwn(document.appearance, key));
  for (const key of materializedNullKeys) document.appearance[key] = null;
  return { document, materializedNullKeys };
}

/** A failed fixture write may expose only these five public appearance values. */
export function responsiveFixtureMismatch(expected: Record<string, any>, actual: Record<string, any>) {
  const safeValue = (value: unknown) => value === null || typeof value === 'boolean'
    || (typeof value === 'number' && Number.isFinite(value)) || value === 'light' || value === 'dark'
    ? value : '[unexpected value omitted]';
  const knownAppearance = Object.fromEntries(responsiveFixtureKeys.map(key => [key,
    { expected: { present: Object.hasOwn(expected.appearance, key),
      ...(Object.hasOwn(expected.appearance, key) ? { value: safeValue(expected.appearance[key]) } : {}) },
      actual: { present: Object.hasOwn(actual.appearance, key),
        ...(Object.hasOwn(actual.appearance, key) ? { value: safeValue(actual.appearance[key]) } : {}) } }]));
  const others = (document: Record<string, any>) => {
    const copy = structuredClone(document);
    for (const key of responsiveFixtureKeys) delete copy.appearance[key];
    return copy;
  };
  return { knownAppearance, allOtherDocumentFieldsEqual: isDeepStrictEqual(others(expected), others(actual)) };
}

/** Isolated CI evidence helpers only. No session, transport or application code. */
export async function bannerGeometry(root: Locator): Promise<Record<string, any>> {
  await root.evaluate(async el => {
    await el.ownerDocument.fonts.ready;
    await el.ownerDocument.querySelector<HTMLImageElement>('[data-sf-menu-banner] img')!.decode();
  });
  // The existing render-only iframe forbids scripts. Its own rAF cannot run.
  await root.page().evaluate(async () => {
    await new Promise<void>(done => requestAnimationFrame(() => requestAnimationFrame(() => done())));
  });
  return root.evaluate(el => {
    const doc = el.ownerDocument, image = doc.querySelector<HTMLImageElement>('[data-sf-menu-banner] img')!;
    const box = image.getBoundingClientRect(), style = getComputedStyle(image);
    const fit = style.objectFit, ratios = [box.width / image.naturalWidth, box.height / image.naturalHeight];
    const scale = fit === 'contain' ? Math.min(...ratios) : Math.max(...ratios);
    const points = style.objectPosition.split(' ').map(p => Number.parseFloat(p) / 100);
    const photo = { width: image.naturalWidth * scale, height: image.naturalHeight * scale,
      x: box.x + (box.width - image.naturalWidth * scale) * points[0],
      y: box.y + (box.height - image.naturalHeight * scale) * points[1] };
    const scene = el.getBoundingClientRect(), banner = image.parentElement!.getBoundingClientRect();
    const controls = Array.from(el.children).filter(node => node !== image.parentElement && node.getAttribute('aria-hidden') !== 'true')
      .map(node => { const r = node.getBoundingClientRect(); return { width: r.width, height: r.height, x: r.x, y: r.y }; });
    const overlap = controls.map(r => Math.max(0, Math.min(photo.x + photo.width, r.x + r.width) - Math.max(photo.x, r.x))
      * Math.max(0, Math.min(photo.y + photo.height, r.y + r.height) - Math.max(photo.y, r.y)));
    const bannerStyle = getComputedStyle(image.parentElement!);
    return { viewportWidth: doc.documentElement.clientWidth, width: box.width, height: box.height,
      naturalWidth: image.naturalWidth, naturalHeight: image.naturalHeight, fit,
      publicPath: new URL(image.currentSrc).pathname, position: style.objectPosition,
      clippedX: Math.max(0, image.naturalWidth - box.width / scale), clippedY: Math.max(0, image.naturalHeight - box.height / scale),
      photo, sceneWidth: scene.width, sceneHeight: scene.height, bannerWidth: banner.width,
      maxControlOverlapArea: Math.max(0, ...overlap), imageCount: doc.querySelectorAll('[data-sf-menu-banner] img').length,
      borderWidth: bannerStyle.borderTopWidth, borderRadius: bannerStyle.borderTopLeftRadius, shadow: bannerStyle.boxShadow,
      sceneBackground: getComputedStyle(el).backgroundImage, imageFilter: style.filter,
      themeBackground: getComputedStyle(doc.querySelector('[data-sf-root],[data-banner-preview-root]')!).getPropertyValue('--bg').trim().toLowerCase(),
      state: doc.querySelector('[data-sf-order-status] [data-state]')!.getAttribute('data-state'),
      announcement: doc.querySelector('[data-sf-module="announce"]')?.textContent?.replace(/\s+/g, ' ').trim() ?? null,
      searchY: doc.querySelector('[role="search"]')!.getBoundingClientRect().y,
      categoriesY: doc.querySelector('[data-sf-module="categories"]')!.getBoundingClientRect().y };
  });
}

export function baselineBannerEvidence(repoRoot: string) {
  const commit = '1e2ec4102d8d69b9f33d867e8b73a9cff97f3431';
  const file = 'storefront/src/ui/storefront/home/home.module.css';
  const bytes = execFileSync('git', ['-C', repoRoot, 'show', `${commit}:${file}`]);
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  assert.equal(sha256, 'f1577b7819c9c8ed6907a25ce05e6485c094d4367c804958c9d43beb74003c62');
  const css = bytes.toString('utf8');
  for (const fragment of [
    '.menuBanner{position:absolute;inset:0;z-index:-1;overflow:hidden;pointer-events:none;mask-image:linear-gradient(#000 60%,transparent)}',
    '.menuBanner img{display:block;width:100%;height:100%;object-fit:cover}',
    '.sceneWindow{height:clamp(181px,16vw,190px)}',
    '.topScene{position:relative;z-index:21;isolation:isolate;padding-block-end:14px}',
    '.sceneWindow[data-sf-hero]{height:56px}',
    '.topControls{margin-block:0;padding-block:12px 0}',
  ]) assert.ok(css.includes(fragment), 'Reject an unknown baseline instead of silently replaying another design');
  assert.ok(!css.includes('object-fit:contain}\n .sceneWindow{display:none}'));
  return { commit, file, bytes: bytes.length, sha256,
    kind: 'BASELINE_CSS_REPLAY_ON_CURRENT_RENDERER_NOT_A_MAIN_BUILD',
    limit: 'Only the banner presentation rules are replayed; no claim that this is a separately built main deployment.' };
}

/** Replay pinned prior banner/top-scene declarations at EVERY width, including phones.
 * CSSOM is used for both mutation and restoration; style-src and sandbox remain intact.
 */
export async function replayBaselineBanner(root: Locator): Promise<() => Promise<void>> {
  const saved = await root.evaluate(el => {
    const image = el.ownerDocument.querySelector<HTMLElement>('[data-sf-menu-banner] img')!;
    const banner = image.parentElement!, window = el.querySelector<HTMLElement>('[data-sf-scene-window]')!;
    const search = el.querySelector('[role="search"]')!;
    const controls = Array.from(el.children).find(child => child.contains(search))! as HTMLElement;
    const nodes = [el, banner, image, window, controls] as HTMLElement[];
    // These are the literal rules validated against the pinned old source above.
    // Explicitly apply them on phones too: this is never a mobile no-op replay.
    const declarations: Record<string, string>[] = [
      { position: 'relative', 'z-index': '21', isolation: 'isolate', 'padding-block-end': '14px', background: 'none' },
      { position: 'absolute', inset: '0', 'z-index': '-1', overflow: 'hidden', 'pointer-events': 'none',
        'mask-image': 'linear-gradient(#000 60%,transparent)', height: 'auto' },
      { display: 'block', width: '100%', height: '100%', 'object-fit': 'cover', 'max-width': 'none', margin: '0' },
      { height: window.hasAttribute('data-sf-hero') ? '56px' : 'clamp(181px,16vw,190px)', display: 'block' },
      { 'margin-block': '0', 'padding-block': '12px 0' },
    ];
    const saved = nodes.map((node, index) => Object.fromEntries(Object.keys(declarations[index]).map(property =>
      [property, { value: node.style.getPropertyValue(property), priority: node.style.getPropertyPriority(property) }])));
    nodes.forEach((node, index) => Object.entries(declarations[index]).forEach(([property, value]) => node.style.setProperty(property, value)));
    // object-position is intentionally untouched: both images use the actual saved focal values.
    return saved;
  });
  return async () => root.evaluate((el, saved) => {
    const image = el.ownerDocument.querySelector<HTMLElement>('[data-sf-menu-banner] img')!;
    const search = el.querySelector('[role="search"]')!;
    const controls = Array.from(el.children).find(child => child.contains(search))! as HTMLElement;
    const nodes = [el, image.parentElement!, image, el.querySelector<HTMLElement>('[data-sf-scene-window]')!, controls] as HTMLElement[];
    nodes.forEach((node, index) => Object.entries(saved[index]).forEach(([property, original]) => {
      if (original.value) node.style.setProperty(property, original.value, original.priority);
      else node.style.removeProperty(property);
    }));
  }, saved);
}

export async function bannerViewportScreenshot(page: Page, path: string, label: string): Promise<void> {
  await page.evaluate(text => {
    window.scrollTo(0, 0);
    const node = document.createElement('div'); node.dataset.bannerCiLabel = '';
    node.textContent = 'ISOLATED CI / SYNTHETIC — ' + text;
    Object.assign(node.style, { position: 'fixed', bottom: '0', left: '0', zIndex: '2147483647', background: '#fff', color: '#111', padding: '6px', font: '12px sans-serif' });
    document.body.appendChild(node);
  }, label);
  await page.screenshot({ path, fullPage: false });
  await page.locator('[data-banner-ci-label]').evaluateAll(nodes => nodes.forEach(node => node.remove()));
}
