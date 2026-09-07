// Visual V2 structure + truth guards.
//
// The V2 presentation adds realistic device scenes, a one-system flow band and a
// problem → solution story. These tests keep that structure present on every
// locale and make sure the redesign never smuggles in fabricated social proof:
// no invented metrics, no testimonials, no customer logos, no ratings.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { build } from '../scripts/build.mjs';

process.env.SITE_DIST = join(process.cwd(), '.test-dist-visual');
const { dist } = build({ quiet: true });

const PAGES = { ar: 'index.html', en: 'en/index.html', he: 'he/index.html' };
const html = Object.fromEntries(Object.entries(PAGES).map(([c, f]) => [c, readFileSync(join(dist, f), 'utf8')]));
const LOCALES = ['ar', 'en', 'he'];
const locale = (c) => JSON.parse(readFileSync(join(process.cwd(), 'src', 'locales', `${c}.json`), 'utf8'));

function strings(node, path = '', out = []) {
  if (typeof node === 'string') out.push({ path, value: node });
  else if (Array.isArray(node)) node.forEach((v, i) => strings(v, `${path}[${i}]`, out));
  else if (node && typeof node === 'object') for (const [k, v] of Object.entries(node)) strings(v, path ? `${path}.${k}` : k, out);
  return out;
}

test('V2 sections render on every locale: hero scene, flow band, four product rows, story, showcase stages', () => {
  for (const [code, doc] of Object.entries(html)) {
    assert.ok(doc.includes('class="scene scene-hero"'), `${code} hero scene`);
    assert.ok(doc.includes('id="flow"'), `${code} #flow`);
    assert.equal((doc.match(/class="fstep fstep-/g) || []).length, 5, `${code} five flow steps`);
    assert.ok(doc.includes('id="story"'), `${code} #story`);
    assert.equal((doc.match(/class="spair reveal"/g) || []).length, 4, `${code} four problem→solution pairs`);
    for (const id of ['pos', 'kds', 'kiosk', 'dashboard']) {
      assert.ok(doc.includes(`class="prow prow-${id} reveal"`), `${code} product row ${id}`);
      assert.ok(doc.includes(`class="scene scene-${id}"`), `${code} product scene ${id}`);
      assert.ok(doc.includes(`scene-stage scene-${id} stage-${id}`), `${code} showcase stage ${id}`);
    }
    // real cashier hardware in the POS scenes: terminal + cash drawer + printer
    assert.ok((doc.match(/class="counter-group"/g) || []).length >= 3, `${code} counter groups (hero, products, showcase)`);
    assert.ok(doc.includes('class="dev dev-drawer"'), `${code} cash drawer`);
    assert.ok(doc.includes('class="dev dev-printer"'), `${code} receipt printer`);
    assert.ok(doc.includes('dev-kiosk-standing'), `${code} floor-standing kiosk`);
    assert.ok(doc.includes('dev-kds-mounted'), `${code} mounted KDS`);
  }
});

test('every scene uses a real BIZBOT screenshot or the kiosk video — never a generic mock UI', () => {
  for (const [code, doc] of Object.entries(html)) {
    const scenes = doc.match(/<div class="(?:stage )?scene[^"]*"[\s\S]*?<\/div>\s*<\/div>/g) || [];
    assert.ok(scenes.length >= 9, `${code} scenes found (${scenes.length})`);
    for (const sc of scenes) {
      const real = /\/assets\/shots\/(pos|kds|kiosk|dash)-\d-\d+\.webp/.test(sc) || /\/assets\/video\/kiosk-attract/.test(sc);
      assert.ok(real, `${code}: a scene without a real product capture: ${sc.slice(0, 120)}…`);
    }
    // environment plates are decorative and hidden from assistive tech
    for (const m of doc.matchAll(/<img class="env"[^>]*>/g)) {
      assert.ok(m[0].includes('alt=""') && m[0].includes('aria-hidden="true"'), `${code} env plate must be decorative`);
    }
  }
});

test('kiosk video: muted, inline, lazy (preload=none) with a poster — in the product scene and the showcase', () => {
  for (const [code, doc] of Object.entries(html)) {
    const videos = doc.match(/<video[^>]*>/g) || [];
    assert.equal(videos.length, 2, `${code} two kiosk videos`);
    for (const v of videos) for (const attr of ['playsinline', 'muted', 'loop', 'preload="none"', 'poster="/assets/video/kiosk-attract-poster.webp"']) assert.ok(v.includes(attr), `${code} video ${attr}`);
  }
});

const FAKE_METRIC = [
  ['percentage figure', /\d+\s*%|%\s*\d+|٪/],
  ['plus-count figure', /\+\s*\d|\d\s*\+/],
  ['fake SLA', /99[.,]9|uptime|زمن التشغيل|זמינות של/i],
  ['customer count', /\d+\s*(customers|clients|restaurants|businesses|عميل|عملاء|مطعم|مطاعم|לקוחות|מסעדות|עסקים)/i],
  ['growth claim', /\d+\s*(x|×)|sales up|increase(d)? sales|زيادة المبيعات بنسبة|עלייה של/i],
];

test('no invented business metrics anywhere in the marketing copy', () => {
  for (const code of LOCALES) {
    const hits = [];
    for (const { path, value } of strings(locale(code))) {
      if (/^contact\.form\.(phonePh|branchesOptions)/.test(path)) continue; // "05x-xxx-xxxx", "2 – 3 branches" are form UI, not claims
      for (const [label, re] of FAKE_METRIC) if (re.test(value)) hits.push(`${label} @ ${path}: "${value}"`);
    }
    assert.deepEqual(hits, [], code);
  }
  // The former "100%" ready-ring is gone from the rendered pages.
  for (const [code, doc] of Object.entries(html)) assert.ok(!/100%/.test(doc.replace(/<style[\s\S]*?<\/style>/g, '')), `${code} renders a 100% figure`);
});

test('no testimonials, ratings or customer logos — industry examples only', () => {
  const social = [/<blockquote/i, /testimonial/i, /\bratings?\b|aggregateRating|reviewRating/i, /★|⭐/, /trusted by/i, /يثق بنا|قال عنّا|آراء العملاء|شعارات العملاء/, /סומכים עלינו|לקוחותינו אומרים|ביקורות/, /class="logo-wall|class="logos/i];
  for (const [code, doc] of Object.entries(html)) {
    for (const re of social) assert.ok(!re.test(doc), `${code} matches ${re}`);
    assert.ok(doc.includes('class="bnote reveal"'), `${code} carries the "industry examples, not customer logos" note`);
  }
});

test('motion is optional: reduced-motion rules, tilt opt-in attribute and no inline styles', () => {
  const cssName = html.ar.match(/\/assets\/(site\.[a-f0-9]{10}\.css)/)[1];
  const css = readFileSync(join(dist, 'assets', cssName), 'utf8');
  assert.ok(/@media \(prefers-reduced-motion: reduce\)/.test(css), 'reduced-motion media query');
  assert.ok(/prefers-reduced-motion: reduce\)\s*\{[\s\S]*\.layer \{ transform: none; \}/.test(css), 'parallax layers are static under reduced motion');
  const js = readFileSync(join(dist, 'assets', html.ar.match(/\/assets\/(site\.[a-f0-9]{10}\.js)/)[1]), 'utf8');
  assert.ok(js.includes("matchMedia('(prefers-reduced-motion: reduce)')"), 'JS honours reduced motion');
  assert.ok(js.includes("matchMedia('(pointer: fine)')"), 'tilt only for fine pointers');
  for (const [code, doc] of Object.entries(html)) {
    assert.ok(doc.includes('data-tilt'), `${code} hero tilt opt-in`);
    assert.ok(!/ style="/.test(doc), `${code} inline style attribute (CSP)`);
  }
});

test('the lead form markup is unchanged by the redesign (same fields, names, honeypot, action)', () => {
  for (const [code, doc] of Object.entries(html)) {
    const form = doc.match(/<form class="lead-form[\s\S]*?<\/form>/)[0];
    for (const name of ['name', 'business', 'phone', 'email', 'type', 'branches', 'notes', 'website', 'locale', 't0']) assert.ok(form.includes(`name="${name}"`), `${code} field ${name}`);
    assert.ok(form.includes('action="/api/lead"') && form.includes('method="post"'), `${code} form action/method`);
    assert.ok(form.includes('class="form-status" role="status" aria-live="polite"'), `${code} live status`);
  }
});
