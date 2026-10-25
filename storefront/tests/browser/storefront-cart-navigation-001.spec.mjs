// Standalone regression: pinned Node --import boundary.mjs <this-file>.
// The source is a fresh LIVE build; only synthetic loopback RPC reads exist.
import { settings, boundaryEvidence, childEnvironment } from './helpers/cart-navigation-boundary-001.mjs';
import { startFixture, guardBrowser, cartSnapshot, privacyState, appOrigin, SLUGS, ITEM, REQUIRED, EXTRA, NOTE, EXPECTED_PRICE, itemName, messages } from './helpers/cart-navigation-001.mjs';
import { createRequire } from 'node:module';
import { mkdirSync, existsSync, writeFileSync, readFileSync } from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';

if (settings.phase !== 'test' || existsSync(settings.outputDir)) throw new Error('fresh_test_output_namespace_required');
mkdirSync(settings.outputDir, { recursive: true });
const require = createRequire(path.join(settings.sourceDir, 'package.json'));
const { chromium, expect } = require('@playwright/test');
const cases = settings.mode === 'old-desktop' ? [{ locale: 'ar', width: 1440 }] : ['ar', 'he', 'en'].flatMap(locale => [390, 1440].map(width => ({ locale, width })));
const results = [];
let fixture, browser;
function save(name, value) { writeFileSync(path.join(settings.outputDir, name), JSON.stringify(value, null, 2) + '\n', { flag: 'wx' }); }
async function assertPrivacy(page) { const state = await privacyState(page); assert.deepEqual(state.cartKeys, []); assert.ok(state.values.every(row => row.value === null)); return state; }
async function settledCart(page) { await expect(page.locator('[data-sf-screen="cart"]:not([data-sf-pending])')).toBeVisible(); await expect(page.locator('[data-sf-pending]')).toHaveCount(0); }
async function addProduct(page, slug) {
  await page.locator(`#sf-menu [data-sf-item="${ITEM}"]`).click();
  const sheet = page.locator('[data-sf-sheet="product"]'); await expect(sheet).toBeVisible();
  await expect(sheet.locator('h2')).toHaveText(itemName(slug));
  const required = sheet.locator(`[data-sf-group] [role="radio"]`).filter({ hasText: 'Synth Classic' });
  await expect(required).toHaveCount(1); await required.click(); await expect(required).toHaveAttribute('aria-checked', 'true');
  const extra = sheet.locator('[role="checkbox"]').filter({ hasText: 'Synth Cheese' });
  await extra.click(); await expect(extra).toHaveAttribute('aria-checked', 'true');
  await sheet.locator('textarea').fill(NOTE); await sheet.locator('[data-sf-step="inc"]').click();
  await expect(sheet.locator('[data-sf-cta="product"]')).toHaveAttribute('aria-disabled', 'false');
  await sheet.locator('[data-sf-cta="product"]').click(); await expect(sheet).toHaveCount(0);
  await expect(page.locator('[data-sf-cart-trigger] b')).toHaveText('2');
}
async function runCase(locale, width) {
  const key = `${locale}-${width}`; const row = { key, locale, width, sourceSha: settings.sourceSha, status: 'FAIL', facts: {} };
  const context = await browser.newContext({ viewport: { width, height: 900 }, serviceWorkers: 'block', locale, reducedMotion: 'reduce' });
  const denied = await guardBrowser(context); const page = await context.newPage(); const errors = []; const navigations = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', req => { if (req.isNavigationRequest() && req.frame() === page.mainFrame()) navigations.push(new URL(req.url()).pathname); });
  try {
    // Explicit /ar is intentionally retained: crossing to canonical /s would
    // replace the root layout and erase the live in-memory cart.
    const prefix = `/${locale}`; const base = `${prefix}/s/${SLUGS[0]}`;
    await page.goto(`${appOrigin}${base}/menu`, { waitUntil: 'domcontentloaded' });
    row.facts.startPath = new URL(page.url()).pathname;
    await expect(page.locator('html')).toHaveAttribute('lang', locale); await expect(page.locator('html')).toHaveAttribute('dir', locale === 'en' ? 'ltr' : 'rtl');
    await addProduct(page, SLUGS[0]); await assertPrivacy(page);
    const token = `synthetic-${key}`;
    const beforeDocument = await page.evaluate(value => { window.__cartNavigationTestSentinel = value; return { token: value, timeOrigin: performance.timeOrigin }; }, token);
    const beforeNavCount = navigations.length;
    const search = page.getByRole('searchbox', { name: messages[locale].search });
    await search.fill('Alpha Burger');
    const resultsRegion = page.locator('[data-sf-module="sections"]'); await expect(resultsRegion).toHaveCount(1);
    await expect(resultsRegion.locator(`[data-sf-item="${ITEM}"]`)).toHaveCount(1);
    await search.fill('synthetic-no-match-901'); await expect(resultsRegion.locator('[data-sf-item]')).toHaveCount(0);
    await expect(resultsRegion.locator('bdi')).toHaveText('synthetic-no-match-901'); await expect(resultsRegion.locator('[role="status"] h3')).toHaveText(messages[locale].noResults.replace('{q}', 'synthetic-no-match-901')); await expect(page.locator('[data-sf-cart-trigger] b')).toHaveText('2'); await search.fill('');
    let beforeLines;
    if (width === 1440) {
      await page.locator('[data-sf-cart-trigger]').click();
      const dialog = page.locator('dialog[open]'); await expect(dialog).toBeVisible();
      beforeLines = await cartSnapshot(page, 'dialog[open] [data-sf-aside-line]');
      assert.equal(beforeLines.length, 1); assert.equal(beforeLines[0].itemId, ITEM); assert.equal(beforeLines[0].qty, '2');
      assert.ok(beforeLines[0].text.includes('Synth Classic') && beforeLines[0].text.includes('Synth Cheese') && beforeLines[0].text.includes(EXPECTED_PRICE));
      const edit = dialog.locator('a').filter({ hasText: messages[locale].edit }); await expect(edit).toHaveCount(1);
      row.facts.actualHref = await edit.getAttribute('href'); await edit.focus(); await edit.press('Enter');
    } else {
      const dock = page.locator('[data-sf-dock-cta="cart"]'); await expect(dock).toBeVisible();
      row.facts.actualHref = await dock.getAttribute('href'); await dock.click();
    }
    await settledCart(page);
    row.facts.documentAfter = await page.evaluate(() => ({ token: window.__cartNavigationTestSentinel ?? null, timeOrigin: performance.timeOrigin }));
    row.facts.documentBefore = beforeDocument; row.facts.documentNavigations = navigations.slice(beforeNavCount);
    row.facts.cartAfter = await cartSnapshot(page, '[data-sf-cart-line]'); row.facts.cartBefore = beforeLines ?? { itemId: ITEM, qty: '2', note: NOTE, required: REQUIRED, extra: EXTRA };
    assert.equal(row.facts.cartAfter.length, 1, 'native cart navigation must retain the live RAM cart');
    const line = page.locator('[data-sf-cart-line]'); await expect(line.locator('[data-sf-item]')).toHaveAttribute('data-sf-item', ITEM);
    await expect(line.locator('[data-sf-stepper] > span')).toHaveText('2'); await expect(line).toContainText(itemName()); await expect(line).toContainText('Synth Classic'); await expect(line).toContainText('Synth Cheese'); await expect(line).toContainText(NOTE); await expect(line).toContainText(EXPECTED_PRICE);
    if (beforeLines) assert.equal(row.facts.cartAfter[0].lineId, beforeLines[0].lineId);
    assert.deepEqual(row.facts.documentAfter, beforeDocument); assert.deepEqual(row.facts.documentNavigations, []);
    assert.equal(new URL(page.url()).pathname, `${base}/cart`); await expect(page.locator('dialog[open]')).toHaveCount(0);
    assert.notEqual(await page.locator('body').evaluate(node => getComputedStyle(node).overflow), 'hidden'); await assertPrivacy(page);
    await line.locator('[data-sf-item]').click(); const edited = page.locator('[data-sf-sheet="product"]'); await expect(edited).toBeVisible(); await expect(edited.locator('textarea')).toHaveValue(NOTE); await expect(edited.getByRole('radio').filter({ hasText: 'Synth Classic' })).toHaveAttribute('aria-checked', 'true'); await expect(edited.getByRole('checkbox').filter({ hasText: 'Synth Cheese' })).toHaveAttribute('aria-checked', 'true'); await page.keyboard.press('Escape'); await expect(edited).toHaveCount(0);
    await page.locator('[data-sf-back]').click(); await expect(page.locator('[data-sf-module="compact"]')).toBeVisible(); assert.equal(new URL(page.url()).pathname, `${base}/menu`); await expect(page.locator('[data-sf-cart-trigger] b')).toHaveText('2');
    assert.deepEqual(await page.evaluate(() => ({ token: window.__cartNavigationTestSentinel ?? null, timeOrigin: performance.timeOrigin })), beforeDocument); assert.deepEqual(navigations.slice(beforeNavCount), []); await assertPrivacy(page);
    // The unprefixed default-AR root is an independent control, never a forced
    // cross-root transition with an existing cart.
    if (locale === 'ar') { await page.goto(`${appOrigin}/s/${SLUGS[0]}/menu`); await addProduct(page, SLUGS[0]); const c = width === 390 ? page.locator('[data-sf-dock-cta="cart"]') : null; if (c) await c.click(); else { await page.locator('[data-sf-cart-trigger]').click(); await page.locator('dialog[open] a').filter({ hasText: messages.ar.edit }).press('Enter'); } await settledCart(page); await expect(page.locator('[data-sf-cart-line]')).toHaveCount(1); assert.equal(new URL(page.url()).pathname, `/s/${SLUGS[0]}/cart`); }
    await page.goto(`${appOrigin}/${locale}/s/${SLUGS[1]}/menu`); await expect(page.locator('[data-sf-cart-trigger] b')).toHaveText('0'); await expect(page.locator(`#sf-menu [data-sf-item="${ITEM}"]`)).toContainText('Bravo Burger'); await expect(page.locator('#sf-menu')).not.toContainText('Alpha Burger'); await assertPrivacy(page);
    assert.deepEqual(denied, []); assert.deepEqual(errors, []); row.status = 'PASS';
  } catch (error) { row.failure = String(error.message).slice(0, 3000); await page.screenshot({ path: path.join(settings.outputDir, `${key}-failure.png`), fullPage: false }).catch(() => undefined); }
  finally { row.denied = denied; row.pageErrors = errors; save(`${key}.json`, row); results.push(row); await context.close(); }
}
try {
  fixture = await startFixture();
  browser = await chromium.launch({ executablePath: settings.chromiumPath, headless: true, env: childEnvironment(), args: ['--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1', '--disable-background-networking', '--disable-component-update', '--no-first-run'] });
  const browserVersion = browser.version();
  for (const item of cases) await runCase(item.locale, item.width);
  save('RESULT.json', { status: results.every(row => row.status === 'PASS') ? 'PASS' : 'FAIL', mode: settings.mode, sourceSha: settings.sourceSha, sourceTree: settings.sourceTree, browserVersion, boundaryEvidence, specSha256: createHash('sha256').update(readFileSync(new URL(import.meta.url))).digest('hex'), cases: results, rpcCalls: fixture.calls, rejectedRpcCalls: fixture.rejected, mappingProof: fixture.mappingProof, productionSocketOrRequest: false, sourceMode: 'actual LIVE decoder with synthetic backend', browserWrites: 0, realDatabase: false });
  process.exitCode = results.every(row => row.status === 'PASS') ? 0 : 1;
} catch (error) { save('INFRASTRUCTURE-FAILURE.json', { status: 'FAIL', error: String(error.message).slice(0, 2000), fixtureEvidence: error.fixtureEvidence ?? null }); process.exitCode = 1;
} finally { if (browser) await browser.close(); if (fixture) { const output = fixture.output(); await fixture.stop(); save('OWNED-CLEANUP.json', { stopped: true, nextPid: fixture.processId, appPort: settings.appPort, rpcPort: settings.rpcPort, syntheticServerOutput: output }); } }
