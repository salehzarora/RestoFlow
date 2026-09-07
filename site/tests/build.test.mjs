import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
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

test('the nine V4 sections render once, in order, with the production lead form', () => {
  const ids = ['top', 'products', 'journey', 'story', 'business', 'features', 'showcase', 'pricing', 'contact'];
  for (const exp of Object.values(expectPage)) {
    const html = readFileSync(join(dist, exp.file), 'utf8');
    const positions = ids.map((id) => {
      const marker = `id="${id}"`;
      assert.equal((html.match(new RegExp(marker, 'g')) || []).length, 1, `${exp.file} has one #${id}`);
      return html.indexOf(marker);
    });
    for (let i = 1; i < positions.length; i++) {
      assert.ok(positions[i] > positions[i - 1], `${exp.file}: #${ids[i]} follows #${ids[i - 1]}`);
    }
    assert.equal((html.match(/id="lead-form"/g) || []).length, 1, `${exp.file} has one #lead-form`);
    assert.ok(html.includes('name="website"'), exp.file + ' honeypot');
    assert.ok(html.includes('action="/api/lead"'), exp.file + ' form action');
  }
});

test('official brand assets only — no legacy identity anywhere in the output', () => {
  for (const exp of Object.values(expectPage)) {
    const html = readFileSync(join(dist, exp.file), 'utf8');
    assert.ok(!/veyro/i.test(html), exp.file + ' mentions VEYRO');
    assert.ok(html.includes('/assets/brand/bizbot-symbol-256.png'), exp.file + ' symbol');
    assert.ok(html.includes('/assets/brand/bizbot-wordmark-ar-reverse.png'), exp.file + ' Arabic wordmark');
    assert.ok(html.includes('/assets/brand/bizbot-wordmark-en-reverse.png'), exp.file + ' English wordmark');
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

test('CSS and markup use shipped local assets only, with no media hotlinks or inline styles (CSP)', () => {
  const html = readFileSync(join(dist, 'index.html'), 'utf8');
  assert.ok(!/ style="/.test(html), 'inline style attribute found');
  const cssName = html.match(/\/assets\/(site\.[a-f0-9]{10}\.css)/)[1];
  const css = readFileSync(join(dist, 'assets', cssName), 'utf8');
  assert.doesNotMatch(css, /url\(\s*['"]?https?:\/\//i, 'remote CSS asset');
  for (const m of css.matchAll(/url\(\s*(['"]?)([^)'"\s]+)\1\s*\)/g)) {
    const asset = m[2];
    if (asset.startsWith('data:')) continue;
    assert.ok(asset.startsWith('/assets/'), `unexpected CSS URL: ${asset}`);
    assert.ok(existsSync(join(dist, asset)), `missing CSS asset: ${asset}`);
  }
  for (const exp of Object.values(expectPage)) {
    const doc = readFileSync(join(dist, exp.file), 'utf8');
    assert.doesNotMatch(doc, /<(?:img|source|video)\b[^>]*(?:src|srcset|poster)="https?:\/\//i, `${exp.file} hotlinked media`);
  }
});

test('V3 output stays inside practical static-site budgets', () => {
  const pageBudget = 140 * 1024;
  for (const exp of Object.values(expectPage)) {
    assert.ok(statSync(join(dist, exp.file)).size <= pageBudget, `${exp.file} exceeds ${pageBudget} bytes`);
  }

  const ar = readFileSync(join(dist, 'index.html'), 'utf8');
  const cssName = ar.match(/\/assets\/(site\.[a-f0-9]{10}\.css)/)[1];
  const jsName = ar.match(/\/assets\/(site\.[a-f0-9]{10}\.js)/)[1];
  assert.ok(statSync(join(dist, 'assets', cssName)).size <= 100 * 1024, 'CSS exceeds 100 KiB');
  assert.ok(statSync(join(dist, 'assets', jsName)).size <= 32 * 1024, 'JS exceeds 32 KiB');

  const visualDirs = ['env', 'business'];
  for (const dir of visualDirs) {
    for (const file of readdirSync(join(dist, 'assets', dir))) {
      assert.ok(statSync(join(dist, 'assets', dir, file)).size <= 180 * 1024, `${dir}/${file} exceeds 180 KiB`);
    }
  }

  const bytes = (dir) => readdirSync(dir, { withFileTypes: true }).reduce(
    (sum, entry) => sum + (entry.isDirectory() ? bytes(join(dir, entry.name)) : statSync(join(dir, entry.name)).size),
    0,
  );
  assert.ok(bytes(dist) <= 7 * 1024 * 1024, 'complete static output exceeds 7 MiB');
});

test('sitemap, robots and manifest are emitted', () => {
  assert.ok(existsSync(join(dist, 'sitemap.xml')));
  assert.ok(existsSync(join(dist, 'robots.txt')));
  assert.ok(existsSync(join(dist, 'site.webmanifest')));
  assert.ok(existsSync(join(dist, 'favicon.ico')));
  const sm = readFileSync(join(dist, 'sitemap.xml'), 'utf8');
  assert.equal((sm.match(/<loc>/g) || []).length, 3);
});

test('contact / social: only confirmed values are rendered, never empty placeholders', () => {
  const cfg = JSON.parse(readFileSync(join(process.cwd(), 'src', 'site.config.json'), 'utf8'));
  for (const exp of Object.values(expectPage)) {
    const html = readFileSync(join(dist, exp.file), 'utf8');
    assert.ok(!/href="mailto:"/.test(html), exp.file + ' empty mailto');
    assert.ok(!/href="(tel:|https:\/\/wa\.me\/)"/.test(html), exp.file + ' empty tel/whatsapp');
    assert.ok(!/href=""/.test(html), exp.file + ' empty href');
    assert.equal(/href="tel:/.test(html), Boolean(cfg.contact.phone), exp.file + ' phone rendered iff configured');
    assert.equal(/wa\.me\//.test(html), Boolean(cfg.contact.whatsapp), exp.file + ' whatsapp rendered iff configured');
    for (const [name, url] of Object.entries(cfg.social)) {
      const rendered = new RegExp(`class="socials">[\\s\\S]*?${name === 'x' ? '>X<' : name}`, 'i').test(html);
      if (url) assert.ok(html.includes(`href="${url}"`), `${exp.file} ${name} link missing`);
      else assert.ok(!rendered, `${exp.file} ${name} rendered without a confirmed URL`);
    }
    assert.ok(html.includes('mailto:' + cfg.contact.sales), exp.file + ' sales mailbox');
    assert.ok(html.includes('mailto:' + cfg.contact.support), exp.file + ' support mailbox');
  }
  // The confirmed Instagram account is the only social link today.
  assert.equal(cfg.social.instagram, 'https://www.instagram.com/bizbot.systems/');
});
