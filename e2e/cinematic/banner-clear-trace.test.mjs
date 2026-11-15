import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import { bannerPublicProjection, bannerHtmlProjection, safeRegenerationErrors } from './banner-clear-trace.mjs';
import { syntheticV4Envelope } from '../../storefront/tests/support/content-envelope.mjs';
const path = `/storage/v1/object/public/storefront-media/${'a'.repeat(32)}/${'b'.repeat(64)}.webp`;
test('trace exports only allowed banner scalars and distinguishes absent/null/native dimensions', () => {
  const result = bannerPublicProjection({ ok: true, secret: 'do-not-export', content_v1: { appearance: {
    menu_banner_url: null, menu_banner_desktop_url: path, menu_banner_width: null,
    menu_banner_desktop_width: 1280, menu_banner_layout: 'responsive', other: 'do-not-export',
  } } });
  assert.deepEqual(result.appearance.menu_banner_url, { present: true, type: 'null', value: null });
  assert.deepEqual(result.appearance.menu_banner_height, { present: false, type: 'undefined' });
  assert.equal(result.appearance.menu_banner_desktop_url.value, path);
  assert.equal(result.appearance.menu_banner_desktop_width.value, 1280);
  assert.equal(result.appearance.menu_banner_layout.value, 'responsive');
  assert.equal(result.desktopManifestPresent, false);
  assert(!JSON.stringify(result).includes('do-not-export'));
  const bad = bannerPublicProjection({ content_v1: { appearance: { menu_banner_url: 'private-key' } } });
  assert(!JSON.stringify(bad).includes('private-key'));
});
test('actual document projection separates server banner presence and serialized image props without exporting HTML', () => {
  const image = 'https://oqmevrndtivqxgyvcmwy.supabase.co' + path;
  const props = JSON.stringify({ menuBanner: { image, desktopImage: null, enabled: true, layout: null, width: 960, height: 450 } });
  const html = `<div data-sf-menu-banner="legacy"><img src="${image}"/></div><script>${JSON.stringify(props)}</script><p>private test text</p>`;
  const value = bannerHtmlProjection(html, [path]);
  assert.equal(value.bannerElements, 1); assert.equal(value.previousPaths[0].present, true);
  assert.equal(value.props[0].image, image); assert.equal(value.props[0].desktopImage, null);
  assert.equal(value.props[0].enabled, true); assert.equal(value.props[0].width, 960);
  assert(!JSON.stringify(value).includes('private test text'));
});
test('server errors are classification only; no arbitrary exception message or token is copied', () => {
  const rows = safeRegenerationErrors('Error: content_v1: invalid menu_banner.dimensions secret-value\nFailed to revalidate: Error: private-text\nordinary log');
  assert.equal(rows.length, 2); assert.equal(rows[0].decoder, true); assert.equal(rows[1].regeneration, true);
  assert(!JSON.stringify(rows).includes('secret-value')); assert(!JSON.stringify(rows).includes('private-text'));
});
test('private diagnostic executes shipped decoder/adapter on clear and still rejects orphaned dimensions', () => {
  const raw = syntheticV4Envelope();
  raw.content_v1.appearance = { menu_banner_url: null, menu_banner_desktop_url: null,
    text_color: '#fff1da', button_text_color: '#20140c', font_family: 'system',
    site_theme: null, scene_preset: null, menu_background_url: null, menu_background_dim: 15,
    menu_intro_visible: null, menu_banner_focal_x: 38, menu_banner_focal_y: 9,
    menu_banner_desktop_focal_x: null, menu_banner_desktop_focal_y: null,
    menu_banner_mobile_height_px: null, menu_banner_desktop_height_px: null,
    menu_banner_enabled: true, menu_banner_layout: null, menu_banner_width: null, menu_banner_height: null,
    menu_banner_desktop_width: null, menu_banner_desktop_height: null };
  const run = () => JSON.parse(execFileSync(process.execPath, [fileURLToPath(new URL('./banner-clear-decode.mjs', import.meta.url))],
    { input: JSON.stringify(raw), encoding: 'utf8', timeout: 5000, maxBuffer: 65536, stdio: ['pipe', 'pipe', 'pipe'] }));
  const valid = run(); assert.equal(valid.decoder.accepted, true);
  assert.equal(valid.adapter.image, null); assert.equal(valid.adapter.desktopImage, null);
  raw.content_v1.appearance.menu_banner_width = 960;
  assert.equal(run().decoder.accepted, false);
});
function clearWaitUnit(clearsAt) {
  const source = readFileSync(new URL('./dashboard.spec.ts', import.meta.url), 'utf8');
  const block = source.slice(source.indexOf('async function waitForClearedMenu('), source.indexOf('function recordClearServerEvidence('));
  assert(block.startsWith('async function waitForClearedMenu('));
  const code = ts.transpileModule(block, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
  let now = 0, options; const calls = [], receipt = { samples: [] };
  const wait = runInNewContext(code + '\nwaitForClearedMenu', {
    Date: { now: () => now }, Math,
    expect: { poll: (callback, value) => { options = value; return { toBe: async expected => {
      const deadline = now + value.timeout;
      while (now < deadline) { const actual = await callback(); if (actual === expected) return; now += 1000; }
      throw new Error('original bounded poll failed');
    } }; } },
    traceRenderedBanner: async (_page, _url, _paths, sample) => {
      calls.push(now); const ready = now >= clearsAt; now += 50;
      sample.html = { bannerElements: ready ? 0 : 1 }; sample.dom = { topCount: 1, bannerCount: ready ? 0 : 1 };
      return ready;
    }, bannerComparisonEvidence: (_name, _field, expected, actual) => ({ expected, actual }),
  });
  return { run: () => wait({}, 'http://127.0.0.1:3000/ar/s/cinematic-fixture/menu', [path], receipt),
    calls, receipt, options: () => options, now: () => now };
}
test('UNIT_ONLY: actual clear waiter observes regenerated ordinary document without reload on every poll', async () => {
  const u = clearWaitUnit(60000); await u.run();
  assert.equal(u.options().timeout, 100000); assert.equal(u.receipt.lastRendered.dom.bannerCount, 0);
  assert(u.calls.length > 1 && u.calls.length < 20);
  assert(u.calls.slice(1).every((at, i) => at - u.calls[i] >= 5000));
  assert(u.now() < 100000); assert(u.receipt.samples.slice(0, -1).every(s => s.predicate.actual === false));
});
test('UNIT_ONLY: an unchanged old document still fails at the existing acceptance deadline', async () => {
  const u = clearWaitUnit(Infinity);
  await assert.rejects(u.run(), /original bounded poll failed/);
  assert.equal(u.options().timeout, 100000); assert(u.calls.every(at => at < 100000));
  assert(u.receipt.samples.every(s => s.predicate.actual === false));
});
