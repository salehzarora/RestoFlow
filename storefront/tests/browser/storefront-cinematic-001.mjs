// Focused UI evidence for the cinematic carousel; no hosted service or order write.
// Run after a fixture build with SF_BROWSER_EXECUTABLE pointing to local Chromium.
import assert from 'node:assert/strict';
import { chromium } from '@playwright/test';
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const output = process.env.SF_SCREENSHOT_DIR || path.join(root, 'test-results/cinematic');
const port = 4488;
const origin = `http://127.0.0.1:${port}`;
const menu = '/s/sf-design-preview/menu';
mkdirSync(output, { recursive: true });
const server = spawn(process.execPath, ['node_modules/next/dist/bin/next', 'start', '-H', '127.0.0.1', '-p', String(port)], {
  cwd: root, env: { ...process.env, STOREFRONT_SOURCE: 'fixture', SF_DESIGN_PREVIEW: '1' }, stdio: 'ignore',
});
let browser;
const evidence = { checks: [], pageErrors: [], writes: [] };
try {
  let ready = false;
  for (let i = 0; i < 100; i++) {
    try { if ((await fetch(`${origin}${menu}`)).ok) { ready = true; break; } } catch {}
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  assert.ok(ready, 'preview server must serve its guarded menu');
  browser = await chromium.launch({ executablePath: process.env.SF_BROWSER_EXECUTABLE || undefined,
    args: ['--no-sandbox', '--disable-dev-shm-usage'], headless: true });
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const page = await context.newPage();
  page.on('pageerror', error => evidence.pageErrors.push(error.message));
  page.on('request', request => { if (request.method() !== 'GET' && request.method() !== 'HEAD') evidence.writes.push(request.url()); });
  await page.goto(`${origin}/s/sf-design-preview`, { waitUntil: 'networkidle' });
  await page.screenshot({ path: path.join(output, '01-mobile-welcome.png'), fullPage: true });
  await page.locator('a[href="/s/sf-design-preview/menu"]').first().click();
  await page.waitForURL(`**${menu}`);
  await page.waitForLoadState('networkidle');
  const carousels = page.locator('[data-sf-carousel]');
  assert.equal(await carousels.count(), 4);
  assert.deepEqual(await carousels.evaluateAll(nodes => nodes.map(node => Number(node.dataset.sfCount))), [6, 4, 3, 7]);
  assert.equal(await page.locator('[data-sf-carousel-product]').count(), 20);
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
  evidence.checks.push('Four real categories, twenty real products, no mobile overflow');
  const selected = () => carousels.evaluateAll(nodes => nodes.map(node => node.dataset.sfSelected));
  const initial = await selected();
  await carousels.nth(1).locator('[data-sf-carousel-next]').click();
  let after = await selected();
  assert.notEqual(after[1], initial[1]);
  for (const i of [0, 2, 3]) assert.equal(after[i], initial[i]);
  await carousels.nth(1).locator('[data-sf-carousel-prev]').click();
  assert.deepEqual(await selected(), initial);
  // Last -> first wraps with exactly one DOM node per actual product.
  await carousels.first().locator('[data-sf-carousel-prev]').click();
  await carousels.first().locator('[data-sf-carousel-next]').click();
  assert.deepEqual(await selected(), initial);
  evidence.checks.push('Independent category selection and circular navigation');
  await page.locator('[data-sf-module="categories"] button').nth(3).click();
  await page.waitForTimeout(700);
  assert.equal(await carousels.count(), 4);
  assert.ok(await carousels.nth(3).evaluate(node => node.getBoundingClientRect().top < innerHeight));
  await page.locator('[data-sf-module="categories"] button').first().click();
  await page.waitForTimeout(700);
  const stage = carousels.first().locator('[data-sf-carousel-stage]');
  const box = await stage.boundingBox();
  const cdp = await context.newCDPSession(page);
  const touch = async (x1, y1, x2, y2) => {
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: x1, y: y1 }] });
    for (let i = 1; i <= 8; i++) await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: x1 + (x2-x1)*i/8, y: y1 + (y2-y1)*i/8 }] });
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await page.waitForTimeout(700);
  };
  await touch(box.x + 80, box.y + box.height / 2, box.x + 235, box.y + box.height / 2 + 3);
  after = await selected();
  assert.notEqual(after[0], initial[0], 'RTL swipe changes the central product');
  assert.equal(await page.locator('[data-sf-sheet="product"]').count(), 0, 'swiping never opens a product accidentally');
  for (const i of [1, 2, 3]) assert.equal(after[i], initial[i]);
  const scrollBefore = await page.evaluate(() => scrollY);
  const verticalBox = await stage.boundingBox();
  await touch(verticalBox.x + 170, verticalBox.y + 190, verticalBox.x + 174, verticalBox.y + 55);
  assert.deepEqual(await selected(), after, 'vertical swipe does not select a product');
  assert.ok(await page.evaluate(() => scrollY) > scrollBefore, 'vertical document scrolling stays native');
  evidence.checks.push('Real touch swipe in RTL, native vertical scroll, no accidental product opener');
  await carousels.first().locator('[data-sf-carousel-prev]').click();
  for (const carousel of await carousels.all()) {
    await carousel.scrollIntoViewIfNeeded();
    await carousel.locator('[data-position="active"] img').evaluate(image => image.decode());
    await page.waitForTimeout(100);
  }
  await page.locator('#sf-menu').evaluate(node => node.scrollIntoView({ block: 'start', behavior: 'instant' }));
  await page.waitForTimeout(650);
  await page.screenshot({ path: path.join(output, '02-mobile-menu.png') });
  await page.evaluate(() => scrollTo({ top: 0, behavior: 'instant' }));
  await page.screenshot({ path: path.join(output, '05-mobile-full-menu.png'), fullPage: true });
  await page.locator('[data-sf-module="categories"] button').nth(2).click();
  await page.waitForTimeout(700);
  await page.screenshot({ path: path.join(output, '06-mobile-cups-drinks.png') });
  await page.locator('[data-sf-module="footer"]').scrollIntoViewIfNeeded();
  await page.screenshot({ path: path.join(output, '03-mobile-footer.png') });
  for (const locale of ['en', 'he']) {
    await page.goto(`${origin}/${locale}${menu}`, { waitUntil: 'networkidle' });
    assert.equal(await page.locator('[data-sf-carousel]').count(), 4);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
  }
  evidence.checks.push('English LTR and Hebrew RTL keep all four sections without overflow');
  const desktop = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  await desktop.goto(`${origin}${menu}`, { waitUntil: 'networkidle' });
  await desktop.screenshot({ path: path.join(output, '04-desktop-menu.png'), fullPage: true });
  assert.equal(await desktop.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
  // Existing enabled synthetic tenant exercises the unchanged cart/options flow.
  const fixture = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await fixture.goto(`${origin}/s/maps-burger/menu`, { waitUntil: 'networkidle' });
  await fixture.locator('[data-sf-carousel]').first().locator('button[data-sf-item]').last().click();
  const sheet = fixture.locator('[data-sf-sheet="product"]');
  await sheet.waitFor({ state: 'visible' });
  for (const group of await sheet.locator('[role="radiogroup"]').all()) await group.locator('[role="radio"]').first().click();
  await sheet.locator('[data-sf-cta="product"]').click();
  await sheet.waitFor({ state: 'hidden' });
  assert.equal((await fixture.locator('[data-sf-cart-trigger] b').textContent()).trim(), '1');
  evidence.checks.push('Existing required options -> add -> cart count, no order submitted');
  assert.deepEqual(evidence.pageErrors, []);
  assert.deepEqual(evidence.writes, []);
  writeFileSync(path.join(output, 'checks.json'), JSON.stringify(evidence, null, 2));
  console.log(JSON.stringify(evidence, null, 2));
} finally {
  await browser?.close();
  server.kill();
}
