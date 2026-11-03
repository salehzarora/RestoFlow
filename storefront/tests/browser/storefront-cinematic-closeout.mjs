// Focused local live-reader checks. Synthetic HTTP RPC only; no hosted writes.
// Optional SF_APPEARANCE_ENVELOPE points to a public envelope from the disposable
// SQL roundtrip. This does not substitute for running the Flutter editor.
import assert from 'node:assert/strict';
import { chromium } from '@playwright/test';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { syntheticV4Envelope } from '../support/content-envelope.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const output = process.env.SF_SCREENSHOT_DIR || path.join(root, 'test-results/cinematic-closeout');
mkdirSync(output, { recursive: true });
const apiOrigin = 'http://127.0.0.1:4495';
// Existing public origin allowlist stays intact. Only this test process replaces
// its read transport with localhost; every other server-side fetch is refused.
const publicOrigin = 'https://oqmevrndtivqxgyvcmwy.supabase.co';
const origin = 'http://127.0.0.1:4494';
const appearance = process.env.SF_APPEARANCE_ENVELOPE
  ? JSON.parse(readFileSync(process.env.SF_APPEARANCE_ENVELOPE, 'utf8')) : null;
const profiles = appearance === null ? [] : Array.isArray(appearance) ? appearance : [appearance];
const envelopes = new Map();
for (const state of ['open', 'closed', 'paused']) for (const enabled of [true, false]) {
  const slug = `sf-closeout-${state}-${enabled ? 'on' : 'off'}`;
  const envelope = syntheticV4Envelope();
  envelope.restaurant.slug = slug;
  envelope.restaurant.display_name = '** اسم تجريبي **';
  envelope.service.state = state;
  envelope.service.ordering_enabled = enabled;
  envelope.hours = { timezone: 'Asia/Jerusalem', opens: '13:00', closes: '23:00', open_now: state !== 'closed', next_open: null };
  envelopes.set(slug, envelope);
}
profiles.forEach((envelope, index) => {
  const slug = `sf-closeout-appearance-${index}`;
  envelopes.set(slug, { ...envelope, restaurant: { ...envelope.restaurant, slug } });
});
const api = createServer((req, res) => {
  if (req.method === 'GET' && req.url.startsWith('/storage/v1/object/public/storefront-media/')) {
    res.writeHead(200, { 'content-type': 'image/webp' });
    res.end(readFileSync(path.join(root, 'public/cinematic-preview/cover.webp')));
    return;
  }
  if (req.method !== 'POST' || req.url !== '/rest/v1/rpc/storefront_menu_v4') { res.writeHead(404); res.end(); return; }
  let body = '';
  req.on('data', chunk => { body += chunk; });
  req.on('end', () => {
    const envelope = envelopes.get(JSON.parse(body).p_slug);
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify(envelope ?? { ok: false, error: 'not_found', entity: 'storefront_menu' }));
  });
});
await new Promise(resolve => api.listen(4495, '127.0.0.1', resolve));
const preload = path.join(output, 'closeout-fetch.mjs');
writeFileSync(preload, `const realFetch = globalThis.fetch;\nglobalThis.fetch = (input, init) => {\n const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;\n if (url !== ${JSON.stringify(`${publicOrigin}/rest/v1/rpc/storefront_menu_v4`)}) throw new Error('unexpected_offline_fetch');\n return realFetch(${JSON.stringify(`${apiOrigin}/rest/v1/rpc/storefront_menu_v4`)}, init);\n};\n`);
const server = spawn(process.execPath, ['node_modules/next/dist/bin/next', 'start', '-H', '127.0.0.1', '-p', '4494'], {
  cwd: root, stdio: ['ignore', 'ignore', 'pipe'], env: { ...process.env, STOREFRONT_SOURCE: 'live',
    NODE_OPTIONS: `--import=${preload}`, STOREFRONT_SUPABASE_URL: publicOrigin,
    STOREFRONT_SUPABASE_ANON_KEY: 'sb_publishable_SYNTHETIC_local_only_key_000000' },
});
let serverErrors = '';
server.stderr.on('data', chunk => { serverErrors += chunk; });
let browser;
const evidence = { states: [], appearance: [], pageErrors: [], browserWrites: [] };
try {
  let ready = false;
  for (let i = 0; i < 100; i++) {
    try { if ((await fetch(`${origin}/healthz.json`)).ok) { ready = true; break; } } catch {}
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  assert.ok(ready, 'local live-mode server starts');
  browser = await chromium.launch({ executablePath: process.env.SF_BROWSER_EXECUTABLE || undefined, args: ['--no-sandbox', '--disable-dev-shm-usage'], headless: true });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, isMobile: true });
  await page.route(`${publicOrigin}/**`, route => {
    assert.ok(route.request().method() === 'GET' && route.request().url().startsWith(`${publicOrigin}/storage/v1/object/public/storefront-media/`));
    return route.fulfill({ status: 200, contentType: 'image/webp', body: readFileSync(path.join(root, 'public/cinematic-preview/cover.webp')) });
  });
  page.on('pageerror', error => evidence.pageErrors.push(error.message));
  page.on('request', request => { if (!['GET', 'HEAD'].includes(request.method())) evidence.browserWrites.push(request.url()); });
  for (const [slug, envelope] of envelopes) {
    const response = await page.goto(`${origin}/s/${slug}/menu`, { waitUntil: 'networkidle' });
    assert.equal(response.status(), 200, `${slug}: ${serverErrors}`);
    await page.evaluate(() => document.fonts.ready);
    const state = envelope.service.state;
    const enabled = envelope.service.ordering_enabled;
    for (const kind of ['closed', 'paused', 'ordering-off']) {
      assert.equal(await page.locator(`[data-sf-notice="${kind}"]`).count(), Number(kind === 'ordering-off' ? state === 'open' && !enabled : state === kind), `${slug}: source-accurate ${kind}`);
    }
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
    const names = await page.locator('[class*="brandName"]').allTextContents();
    assert.ok(names.length >= 2 && names.every(name => name === envelope.restaurant.display_name), 'header/footer preserve canonical stored name');
    if (!slug.includes('appearance')) {
      const text = await page.locator('[data-sf-module="notice"]').allTextContents();
      if (state === 'closed') {
        assert.match(text.join(' '), /يفتح المطعم في 13:00/);
        assert.doesNotMatch(text.join(' '), /سيتوفر|خارج ساعات العمل/);
      }
      const panel = page.locator('[data-sf-module="notice"]').first();
      if (await panel.count()) assert.ok(await panel.evaluate(node => node.parentElement.getBoundingClientRect().height) < 115, 'compact notice group on mobile');
      evidence.states.push({ state, enabled, notices: text });
      continue;
    }
    const css = await page.locator('[data-sf-root]').first().evaluate(node => {
      const style = getComputedStyle(node);
      return Object.fromEntries(['--bg', '--acc', '--tx', '--onacc', '--font'].map(key => [key, style.getPropertyValue(key).trim()]));
    });
    assert.equal(css['--bg'], envelope.restaurant.primary_color.toLowerCase());
    assert.equal(css['--acc'], envelope.restaurant.accent_color.toLowerCase());
    const settings = envelope.content_v1.appearance;
    if (settings.text_color) assert.equal(css['--tx'], settings.text_color.toLowerCase());
    if (settings.button_text_color) assert.equal(css['--onacc'], settings.button_text_color.toLowerCase());
    if (settings.font_family === 'alexandria') assert.match(css['--font'], /SF Alexandria/);
    if (settings.font_family === 'system') assert.match(css['--font'], /^system-ui/);
    const hero = envelope.restaurant.hero_url;
    if (hero) {
      const image = page.locator('[data-sf-screen="home"] > div[aria-hidden="true"] img').first();
      await image.evaluate(node => node.decode());
      assert.ok((await image.getAttribute('src')).endsWith(new URL(hero, apiOrigin).pathname));
    }
    evidence.appearance.push({ slug, css, hero });
  }
  assert.deepEqual(evidence.pageErrors, []);
  assert.deepEqual(evidence.browserWrites, []);
  writeFileSync(path.join(output, 'closeout-checks.json'), JSON.stringify(evidence, null, 2));
  console.log(JSON.stringify(evidence, null, 2));
} finally {
  await browser?.close();
  server.kill();
  await new Promise(resolve => api.close(resolve));
}
