// Optional local visual regression driver. No runtime dependency is added.
// node review/refinement-browser-check.mjs <Playwright package.json> <Chrome exe> <evidence directory> [base URL]
// All delivery is intercepted in-browser. Never sends a real lead.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { gzipSync } from 'node:zlib';
import { execFileSync } from 'node:child_process';

const [packagePath, chrome, out, base = 'http://localhost:8796'] = process.argv.slice(2);
assert.ok(packagePath && chrome && out, 'Playwright package, browser executable and evidence directory required');
assert.ok(/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(base), 'local-only driver');
const { chromium } = createRequire(packagePath)('playwright');
const browser = await chromium.launch({ headless: true, executablePath: chrome });
await mkdir(out, { recursive: true });
const report = { head: execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim(), dirty: execFileSync('git', ['status', '--short'], { encoding: 'utf8' }).trim(), browser: browser.version(), matrix: [], fallback: [], interactions: [], loads: [], bundles: {} };
const pause = p => p.waitForTimeout(250);
async function settle(p) {
  // Hidden/lazy images do not necessarily fetch until requested. Decode only
  // complete requests here; the section walk below exercises lazy loading.
  await p.locator('img').evaluateAll(a => Promise.all(a.filter(i => i.complete && i.naturalWidth).map(i => i.decode().catch(() => {}))));
  await pause(p);
}
async function progress(p, n) {
  await p.evaluate(n => { const j = document.querySelector('.journey'); window.scrollTo({ top: j.offsetTop + n * (j.offsetHeight - innerHeight), behavior: 'instant' }); }, n);
  await p.waitForTimeout(n === 1 ? 700 : 350);
}
async function geometry(p) {
  return p.evaluate(() => {
    const rect = e => { const r = e.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height, right: r.right, bottom: r.bottom }; };
    const visible = e => e.getClientRects().length && getComputedStyle(e).visibility !== 'hidden';
    const essentials = [...document.querySelectorAll('.product-card,.bcard,.showcase [role="tab"],.lead-form,.hero-visual .scard')].filter(visible);
    const outside = essentials.filter(e => { const r = rect(e); return r.x < -1 || r.right > innerWidth + 1; }).map(e => e.className);
    const products = [...document.querySelectorAll('.product-card')].map(rect);
    const business = [...document.querySelectorAll('.bcard')].map(rect);
    const scene = rect(document.querySelector('.scene-hero'));
    const badges = [...document.querySelectorAll('.scard')].filter(visible).map(rect);
    const fullBusinessOverlays = [...document.querySelectorAll('.bscene i')].every(e => { const a = rect(e), b = rect(e.parentElement); return Math.abs(a.w - b.w) < 1 && Math.abs(a.h - b.h) < 1; });
    const hardware = [...document.querySelectorAll('.counter-group')].filter(e => rect(e).w > 0).map(e => {
      const foot = rect(e.querySelector('.dev-base')), top = rect(e.querySelector('.drawer-top')), control = rect(e.querySelector('.printer-control')), printer = rect(e.querySelector('.printer-body'));
      return { seated: foot.bottom >= top.y - 2 && foot.bottom <= top.bottom + 3, controlBounded: control.w < printer.w * .25 && control.h < printer.h * .3 };
    });
    return { width: innerWidth, height: document.documentElement.scrollHeight, overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth, outside, products, business, scene, badges, fullBusinessOverlays, hardware, broken: [...document.images].filter(i => !i.complete || !i.naturalWidth).map(i => i.getAttribute('src')) };
  });
}
async function shot(p, selector, name) {
  const loc = p.locator(selector); await loc.scrollIntoViewIfNeeded(); await settle(p);
  await loc.screenshot({ path: join(out, name + '.png'), animations: 'disabled' });
}
try {
  for (const viewport of [{ width: 1440, height: 900 }, { width: 390, height: 844 }]) {
    const c = await browser.newContext({ viewport });
    await c.addInitScript(() => { window.__cls = 0; new PerformanceObserver(l => { for (const e of l.getEntries()) if (!e.hadRecentInput) window.__cls += e.value; }).observe({ type: 'layout-shift', buffered: true }); });
    const p = await c.newPage(); await p.goto(base, { waitUntil: 'load' }); await p.waitForTimeout(2000);
    report.loads.push(await p.evaluate(() => {
      const entries = [...performance.getEntriesByType('resource'), ...performance.getEntriesByType('navigation')];
      return { viewport: [innerWidth, innerHeight], height: document.documentElement.scrollHeight, cls: window.__cls, transfer: entries.reduce((n, e) => n + e.transferSize, 0), encoded: entries.reduce((n, e) => n + e.encodedBodySize, 0), decoded: entries.reduce((n, e) => n + e.decodedBodySize, 0), resourceCountIncludingNavigation: entries.length };
    })); await c.close();
  }
  for (const file of await readdir('dist/assets')) if (/^site\..*\.(css|js)$/.test(file)) { const b = await readFile(join('dist/assets', file)); report.bundles[file.split('.').at(-1)] = { raw: b.length, gzip: gzipSync(b).length }; }
  const cases = [['ar', 1920, 1080], ['ar', 1440, 900], ['ar', 1200, 900], ['ar', 1024, 900], ['ar', 768, 1024], ['ar', 430, 932], ['ar', 390, 844], ['ar', 375, 812], ['ar', 1366, 768], ['ar', 1280, 720], ['en', 1440, 900], ['en', 375, 812], ['en', 390, 844], ['he', 1440, 900], ['he', 375, 812], ['he', 390, 844]];
  for (const [lang, width, height] of cases) {
    const c = await browser.newContext({ viewport: { width, height } }); const p = await c.newPage(); const errors = [];
    p.on('pageerror', e => errors.push(e.message)); p.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
    await p.goto(base + (lang === 'ar' ? '/' : '/' + lang)); await settle(p);
    await p.screenshot({ path: join(out, `after-${lang}-${width}-hero.png`), animations: 'disabled' });
    // Decode every static image, visit each semantic section to trigger reveals.
    // Traverse the document, not section centres: tall mobile product sections
    // contain multiple independent reveal targets above/below their midpoint.
    const docHeight = await p.evaluate(() => document.documentElement.scrollHeight);
    for (let y = 0; y < docHeight; y += height * .65) {
      await p.evaluate(y => scrollTo({ top: y, behavior: 'instant' }), y); await p.waitForTimeout(70);
    }
    await p.waitForTimeout(1000);
    // Load each lazy asset deliberately for visual QA, after cold-load metrics.
    await p.locator('img[loading="lazy"]').evaluateAll(a => a.forEach(i => i.loading = 'eager'));
    await p.waitForFunction(() => [...document.images].every(i => i.complete && i.naturalWidth));
    await settle(p); const g = await geometry(p);
    assert.ok(g.overflow <= 1 && g.outside.length === 0, `${lang}/${width}: essential overflow ${JSON.stringify(g.outside)}`);
    assert.deepEqual(g.broken, [], `${lang}/${width}: broken/undecoded media`); assert.deepEqual(errors, []);
    assert.ok(g.fullBusinessOverlays, 'photo contrast overlay covers its whole card');
    assert.ok(g.hardware.length >= 3 && g.hardware.every(x => x.seated && x.controlBounded), `seated hardware/control geometry ${JSON.stringify(g.hardware)}`);
    if (width <= 430) {
      assert.equal(g.products.length, 4); assert.ok(g.products.every((r, i) => !i || r.y >= g.products[i - 1].bottom - 1), 'all products vertical');
      assert.equal(g.business.length, 6); assert.equal(new Set(g.business.map(r => Math.round(r.x))).size, 2, 'complete two-column businesses');
      assert.ok(g.badges.every(r => r.y >= g.scene.bottom), 'hero captions cannot overlap product UI');
    }
    if (width > 1024) {
      await progress(p, 1);
      const ports = await p.evaluate(() => {
        const stage = document.querySelector('.journey-stage').getBoundingClientRect();
        const slot = document.querySelector('.jo-pos .slot').getBoundingClientRect();
        const port = document.querySelector('.jport-6').getBoundingClientRect();
        const pills = [...document.querySelectorAll('.jkds li')].map(e => e.getBoundingClientRect().x);
        return { dx: Math.abs(port.x + port.width / 2 - slot.x - slot.width / 2) / stage.width * 1000, dy: Math.abs(port.y + port.height / 2 - slot.y - slot.height / 2) / stage.height * 620, pills };
      });
      assert.ok(ports.dx < 8 && ports.dy < 8, `printer docking ${JSON.stringify(ports)}`);
      assert.ok(ports.pills[0] > ports.pills[1] && ports.pills[1] > ports.pills[2], 'fixed capture status order');
      g.ports = ports;
    }
    if (lang === 'ar' && width === 1440) {
      await p.evaluate(() => scrollTo({ top: 350, behavior: 'instant' })); await pause(p); await p.screenshot({ path: join(out, 'after-ar-1440-hero-transition.png') });
      for (const name of ['pos', 'kds', 'kiosk', 'dashboard']) await shot(p, '.product-media .scene-' + name, 'after-' + name);
      for (const n of [.35, .45, .55, .65, .80, .88, 1]) { await progress(p, n); await p.screenshot({ path: join(out, `after-journey-${Math.round(n * 100)}.png`) }); }
    }
    if (lang === 'ar' && width === 390) for (const [sel, name] of [['.hero-visual', 'hero-visual'], ['#products', 'products'], ['#business', 'business'], ['#showcase', 'showcase'], ['#contact', 'contact']]) await shot(p, sel, 'after-ar-390-' + name);
    report.matrix.push({ lang, width, height, documentHeight: g.height, overflow: g.overflow, broken: g.broken.length, errors, ports: g.ports });
    await c.close(); console.log(`PASS ${lang} ${width}x${height}`);
  }
  for (const mode of ['no-js', 'reduce']) for (const lang of ['ar', 'en', 'he']) for (const width of [1440, 375]) {
    const c = await browser.newContext({ viewport: { width, height: 900 }, javaScriptEnabled: mode !== 'no-js', reducedMotion: mode === 'reduce' ? 'reduce' : 'no-preference' });
    const p = await c.newPage(); await p.goto(base + (lang === 'ar' ? '/' : '/' + lang));
    await p.locator('img[loading="lazy"]').evaluateAll(a => a.forEach(i => i.loading = 'eager'));
    await p.waitForFunction(() => [...document.images].every(i => i.complete && i.naturalWidth));
    await settle(p); const g = await geometry(p);
    assert.ok(g.overflow <= 1 && !g.outside.length, `${mode} ${lang} ${width} overflow`);
    assert.deepEqual(g.broken, []); const jh = await p.locator('.journey').evaluate(e => e.getBoundingClientRect().height);
    assert.ok(jh < 3000, 'static story does not retain long empty pin');
    report.fallback.push({ mode, lang, width, height: g.height, journeyHeight: jh }); await c.close();
  }
  const c = await browser.newContext({ viewport: { width: 1440, height: 900 } }); const p = await c.newPage();
  let delivered = 0; await p.route('**/api/lead', route => { delivered++; return route.fulfill({ status: 200, contentType: 'application/json', body: '{"ok":true}' }); });
  await p.goto(base); await settle(p);
  for (const n of [.01, .35, .55, .57, .65, .73, .9, 1, .9, .73, .65, .57, .55, .35, .01, .95, .12]) {
    await progress(p, n); const state = await p.locator('.journey').evaluate(e => ({ step: e.dataset.step, kds: e.dataset.kds || '0' }));
    assert.equal(state.step, String(n < .26 ? 1 : n < .56 ? 2 : n < .72 ? 3 : n < .86 ? 4 : 5));
    assert.equal(state.kds, String(n < .56 ? 0 : n < .64 ? 1 : n < .72 ? 2 : 3));
  }
  await progress(p, .65); await p.reload(); await p.evaluate(() => document.fonts.ready); await pause(p);
  // Native restored scroll/anchoring may change the pixel position on reload;
  // the driver must match the actual restored geometry, not an assumed .65.
  const restored = await p.locator('.journey').evaluate(e => ({ actual: Math.max(0, Math.min(1, -e.getBoundingClientRect().top / (e.getBoundingClientRect().height - innerHeight))), driven: Number(e.style.getPropertyValue('--p')), kds: e.dataset.kds || '0' }));
  assert.ok(Math.abs(restored.actual - restored.driven) < .005, `restored timeline is stale ${JSON.stringify(restored)}`);
  assert.equal(restored.kds, String(restored.actual < .56 ? 0 : restored.actual < .64 ? 1 : restored.actual < .72 ? 2 : 3));
  report.interactions.push({ restored });
  await p.setViewportSize({ width: 390, height: 844 }); await pause(p); assert.equal(await p.locator('.journey').getAttribute('data-step'), null);
  await p.setViewportSize({ width: 1440, height: 900 }); await progress(p, .65);
  await p.emulateMedia({ reducedMotion: 'reduce' }); await pause(p); assert.equal(await p.locator('.journey').getAttribute('style'), '');
  await p.emulateMedia({ reducedMotion: 'no-preference' }); await progress(p, .65); assert.equal(await p.locator('.journey').getAttribute('data-kds'), '2');
  report.interactions.push('forward/reverse/fast, refresh at mid-journey, resize both ways, live reduced motion');
  await p.setViewportSize({ width: 390, height: 844 }); await p.evaluate(() => scrollTo({ top: 0, behavior: 'instant' }));
  const menu = p.locator('.nav-toggle'); await menu.focus(); await p.keyboard.press('Enter'); assert.equal(await menu.getAttribute('aria-expanded'), 'true');
  await p.keyboard.press('Escape'); assert.equal(await menu.getAttribute('aria-expanded'), 'false'); assert.ok(await menu.evaluate(e => e === document.activeElement));
  report.interactions.push('keyboard menu, Escape, focus return');
  const tabs = p.locator('#showcase [role="tab"]');
  for (const tab of await tabs.all()) { await tab.click(); assert.equal(await tab.getAttribute('aria-selected'), 'true'); }
  report.interactions.push(`showcase tabs: ${await tabs.count()}`);
  await p.locator('#tab-pos').click();
  for (const thumb of await p.locator('#panel-pos .thumb').all()) { await thumb.click(); assert.equal(await thumb.getAttribute('aria-pressed'), 'true'); }
  await p.locator('#tab-kiosk').click();
  const video = p.locator('#panel-kiosk video'); assert.ok(await video.evaluate(v => v.paused && !v.autoplay));
  // The explicit video thumbnail is the existing user-start action.
  await p.locator('#panel-kiosk .thumb[data-shot="video"]').click();
  await p.waitForFunction(() => { const v = document.querySelector('#panel-kiosk video'); return !v.paused && v.currentTime > 0; });
  await p.locator('#tab-pos').click(); assert.ok(await video.evaluate(v => v.paused));
  report.interactions.push('POS thumbnails; user-started kiosk video plays, pauses when panel hidden');
  // CSS zoom is an explicit layout stress test, not a claim of browser-UI zoom.
  await p.setViewportSize({ width: 768, height: 900 }); await p.evaluate(() => { document.documentElement.style.zoom = '2'; }); await pause(p);
  const zoom = await geometry(p); assert.ok(zoom.overflow <= 1 && !zoom.outside.length, `200% CSS zoom overflow ${zoom.outside}`);
  await shot(p, '#business', 'after-ar-200pct-zoom-business'); await p.evaluate(() => { document.documentElement.style.zoom = ''; });
  report.interactions.push('200% CSS zoom at 768px');
  await p.setViewportSize({ width: 390, height: 844 });
  await p.locator('.bcard h3').evaluateAll(es => es.forEach(e => e.style.fontSize = '27px'));
  const textFits = await p.locator('.bcopy').evaluateAll(es => es.every(e => { const a = e.getBoundingClientRect(), b = e.parentElement.getBoundingClientRect(); return a.top >= b.top && a.bottom <= b.bottom && e.scrollWidth <= e.clientWidth; }));
  assert.ok(textFits, 'doubled business labels remain fully inside growing cards');
  await shot(p, '#business', 'after-ar-text-inflation-business');
  await p.locator('.bcard h3').evaluateAll(es => es.forEach(e => e.style.fontSize = ''));
  report.interactions.push('200% business-label text inflation at 390px');
  await p.locator('#lead-form button[type="submit"]').click(); assert.equal(delivered, 0); assert.ok(await p.locator('#lead-form .field.is-invalid').count());
  await p.locator('#f-name').fill('Local Design Test'); await p.locator('#f-business').fill('Test Restaurant'); await p.locator('#f-phone').fill('0000000000'); await p.locator('#f-email').fill('design-test@example.invalid');
  for (const s of await p.locator('#lead-form select').all()) await s.selectOption({ index: 1 });
  const consent = p.locator('#lead-form input[type="checkbox"]'); if (await consent.count()) await consent.check();
  await p.locator('#lead-form button[type="submit"]').click(); await pause(p); assert.equal(delivered, 1); assert.ok(await p.locator('.form-status.is-success').count());
  report.interactions.push('invalid form stays client-side; valid form intercepted, success UI; no real delivery');
  await c.close();
  console.log('ALL BROWSER CHECKS PASSED');
} catch (error) { report.failure = error.stack; throw error; }
finally { await writeFile(join(out, 'browser-report.json'), JSON.stringify(report, null, 2)); await browser.close(); }
