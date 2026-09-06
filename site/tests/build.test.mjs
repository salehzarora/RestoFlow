import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { build } from '../scripts/build.mjs';

process.env.SITE_DIST = join(process.cwd(), '.test-dist');
const { dist, pages } = build({ quiet: true });

const expectPage = {
  ar: { file: 'index.html', dir: 'rtl', lang: 'ar' },
  en: { file: 'en/index.html', dir: 'ltr', lang: 'en' },
  he: { file: 'he/index.html', dir: 'rtl', lang: 'he' },
};

test('renders one document per locale with the right direction', () => {
  assert.equal(pages.length, 3);
  for (const [code, exp] of Object.entries(expectPage)) {
    const html = readFileSync(join(dist, exp.file), 'utf8');
    assert.match(html, new RegExp(`<html lang="${exp.lang}" dir="${exp.dir}"`), code);
    assert.ok(html.includes('<title>'), code + ' title');
    assert.ok(!/\{\{|undefined|\[object Object\]/.test(html), code + ' has no unrendered placeholders');
  }
});

test('every page carries hreflang alternates, canonical and OG tags', () => {
  for (const exp of Object.values(expectPage)) {
    const html = readFileSync(join(dist, exp.file), 'utf8');
    for (const l of ['ar', 'en', 'he', 'x-default']) assert.ok(html.includes(`hreflang="${l}"`), `${exp.file} hreflang ${l}`);
    assert.ok(html.includes('<link rel="canonical" href="https://bizbot.systems/'), exp.file + ' canonical');
    assert.ok(html.includes('property="og:image"'), exp.file + ' og:image');
    assert.ok(html.includes('application/ld+json'), exp.file + ' json-ld');
  }
});

test('all nine sections and the lead form are present on every page', () => {
  const ids = ['top', 'products', 'features', 'business', 'showcase', 'why', 'pricing', 'contact', 'lead-form'];
  for (const exp of Object.values(expectPage)) {
    const html = readFileSync(join(dist, exp.file), 'utf8');
    for (const id of ids) assert.ok(html.includes(`id="${id}"`), `${exp.file} #${id}`);
    assert.ok(html.includes('name="website"'), exp.file + ' honeypot');
    assert.ok(html.includes('action="/api/lead"'), exp.file + ' form action');
  }
});

test('official brand assets only — no legacy identity anywhere in the output', () => {
  for (const exp of Object.values(expectPage)) {
    const html = readFileSync(join(dist, exp.file), 'utf8');
    assert.ok(!/veyro/i.test(html), exp.file + ' mentions VEYRO');
    assert.ok(html.includes('/assets/brand/bizbot-symbol-256.png'), exp.file + ' symbol');
    assert.ok(html.includes('/assets/brand/bizbot-wordmark-ar.png'), exp.file + ' Arabic wordmark');
    assert.ok(html.includes('/assets/brand/bizbot-wordmark-en.png'), exp.file + ' English wordmark');
  }
});

test('every referenced local asset exists in dist', () => {
  const missing = new Set();
  for (const exp of Object.values(expectPage)) {
    const html = readFileSync(join(dist, exp.file), 'utf8');
    const refs = new Set();
    for (const m of html.matchAll(/(?:src|href|poster)="(\/[^"?#]+)"/g)) refs.add(m[1]);
    for (const m of html.matchAll(/srcset="([^"]+)"/g)) for (const part of m[1].split(',')) refs.add(part.trim().split(' ')[0]);
    for (const m of html.matchAll(/imagesrcset="([^"]+)"/g)) for (const part of m[1].split(',')) refs.add(part.trim().split(' ')[0]);
    for (const r of refs) {
      if (r.startsWith('/api/') || r === '/' || r === '/en' || r === '/he') continue;
      if (!existsSync(join(dist, r))) missing.add(r);
    }
  }
  assert.deepEqual([...missing], []);
});

test('CSS references only shipped fonts and no inline style attributes leak into markup (CSP)', () => {
  const html = readFileSync(join(dist, 'index.html'), 'utf8');
  assert.ok(!/ style="/.test(html), 'inline style attribute found');
  const cssName = html.match(/\/assets\/(site\.[a-f0-9]{10}\.css)/)[1];
  const css = readFileSync(join(dist, 'assets', cssName), 'utf8');
  for (const m of css.matchAll(/url\('(\/assets\/fonts\/[^']+)'\)/g)) assert.ok(existsSync(join(dist, m[1])), m[1]);
});

test('sitemap, robots and manifest are emitted', () => {
  assert.ok(existsSync(join(dist, 'sitemap.xml')));
  assert.ok(existsSync(join(dist, 'robots.txt')));
  assert.ok(existsSync(join(dist, 'site.webmanifest')));
  assert.ok(existsSync(join(dist, 'favicon.ico')));
  const sm = readFileSync(join(dist, 'sitemap.xml'), 'utf8');
  assert.equal((sm.match(/<loc>/g) || []).length, 3);
});
