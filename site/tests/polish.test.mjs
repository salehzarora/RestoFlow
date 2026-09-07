// Presentation contracts for the small V4.1 polish pass. Runtime resizing and
// motion-preference transitions are exercised in main-motion-behavior.test.mjs.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { renderPage } from '../src/render.mjs';

const src = join(process.cwd(), 'src');
const css = readFileSync(join(src, 'styles.css'), 'utf8');
const cfg = JSON.parse(readFileSync(join(src, 'site.config.json'), 'utf8'));
const locales = ['ar', 'en', 'he'].map(code => JSON.parse(readFileSync(join(src, 'locales', `${code}.json`), 'utf8')));

test('polished hardware keeps decorative supports around real product captures in every locale', () => {
  for (const locale of locales) {
    const html = renderPage(locale, { cfg, locales, assets: { css: 'test.css', js: 'test.js' } });
    for (const part of ['dev-pivot', 'counter-mat', 'pos-cable', 'drawer-grip', 'printer-lid', 'kds-rail', 'kiosk-service', 'tablet-dock', 'tablet-base']) {
      assert.ok(html.includes(`class="${part}"`), `${locale.code}: ${part}`);
    }
    for (const capture of ['pos-1', 'kds-1', 'dash-1']) {
      assert.ok(html.includes(`/assets/shots/${capture}-`), `${locale.code}: real ${capture}`);
    }
    assert.ok(html.includes('/assets/video/kiosk-attract.mp4'));
  }
});

test('POS support height is intrinsic and printer controls cannot inherit CTA sizing', () => {
  assert.match(css, /\.dev-pos \.dev-neck\s*\{[^}]*aspect-ratio:/);
  assert.match(css, /\.dev-pos \.dev-pivot\s*\{[^}]*aspect-ratio:/);
  const printerButton = css.match(/\.printer-body \.btn\s*\{([^}]+)\}/)?.[1];
  assert.ok(printerButton, 'physical printer control has a scoped rule');
  assert.match(printerButton, /min-width:\s*0/);
  assert.match(printerButton, /min-height:\s*0/);
  assert.match(printerButton, /padding:\s*0/);
});

test('final frame retires receipt, pickup and intermediate kitchen chips', () => {
  assert.match(css, /\.journey\.is-final \.jreceipt-wrap\s*\{[^}]*opacity:\s*0/);
  assert.match(css, /\.journey\.is-final \.jpickup\s*\{[^}]*opacity:\s*0/);
  assert.match(css, /\.journey\.is-final \.jkds li:not\(\[data-k='3'\]\)\s*\{[^}]*visibility:\s*hidden/);
  assert.match(css, /\.no-js \.journey-stage > \.jimpact\s*\{[^}]*opacity:\s*1/);
  assert.match(css, /\.no-js \.jreceipt-wrap, \.no-js \.journey-stage > \.jpickup\s*\{[^}]*display:\s*none/);
});

test('mobile journey gives device scenes a complete row and bounds the KDS mount', () => {
  assert.match(css, /grid-template-areas:\s*'mark text' 'mini mini'/);
  assert.match(css, /\.jmini-kds \.dev-kds\s*\{[^}]*width:\s*min\(72%, 232px\)/);
  assert.match(css, /\.jmini \.jp-text b, \.jmini \.jp-text small\s*\{[^}]*white-space:\s*normal/);
});
