// Visual V3 structure + truth guards, extended for Visual V4.
//
// V3 adds restaurant-context photography, a compact product bento and one
// connected problem → solution story; V4 adds the scroll-driven order journey,
// hero scroll life and a mobile layout with no carousel-only sections. The
// guards below keep all imagery local, preserve real BIZBOT screens, prevent
// fabricated social proof or metrics, and pin the V4 scroll/motion rules.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { build } from '../scripts/build.mjs';
import { JOURNEY_PATHS } from '../src/render.mjs';

process.env.SITE_DIST = join(process.cwd(), '.test-dist-visual');
const { dist } = build({ quiet: true });

const PAGES = { ar: 'index.html', en: 'en/index.html', he: 'he/index.html' };
const html = Object.fromEntries(Object.entries(PAGES).map(([code, file]) => [code, readFileSync(join(dist, file), 'utf8')]));
const LOCALES = Object.keys(PAGES);
const locale = (code) => JSON.parse(readFileSync(join(process.cwd(), 'src', 'locales', `${code}.json`), 'utf8'));

function strings(node, path = '', out = []) {
  if (typeof node === 'string') out.push({ path, value: node });
  else if (Array.isArray(node)) node.forEach((value, index) => strings(value, `${path}[${index}]`, out));
  else if (node && typeof node === 'object') {
    for (const [key, value] of Object.entries(node)) strings(value, path ? `${path}.${key}` : key, out);
  }
  return out;
}

test('V4 hero, bento, order journey, compact story and showcase render for every locale', () => {
  for (const [code, doc] of Object.entries(html)) {
    assert.ok(doc.includes('class="scene scene-hero"'), `${code} hero scene`);
    assert.equal((doc.match(/class="hero-value-strip\b/g) || []).length, 1, `${code} qualitative value strip`);
    assert.ok(doc.includes('id="journey"'), `${code} order journey`);
    assert.equal((doc.match(/class="jstep jstep-/g) || []).length, 5, `${code} five journey steps`);
    assert.equal((doc.match(/class="story-side story-/g) || []).length, 2, `${code} compact before/after story`);
    assert.ok(!doc.includes('class="v3-flow'), `${code} the V3 flow band is folded into the journey (no duplicate story)`);
    assert.equal((doc.match(/class="benefit-card reveal"/g) || []).length, 6, `${code} combined benefit cards`);
    for (const id of ['pos', 'kds', 'kiosk', 'dashboard']) {
      assert.ok(doc.includes(`class="product-card product-card-${id} reveal"`), `${code} bento ${id}`);
      assert.ok(doc.includes(`class="scene scene-${id}"`), `${code} scene ${id}`);
      assert.ok(doc.includes(`scene-stage scene-${id} stage-${id}`), `${code} showcase ${id}`);
    }
    assert.ok((doc.match(/class="counter-group"/g) || []).length >= 3, `${code} POS hardware groups`);
    assert.ok(doc.includes('class="dev dev-drawer"'), `${code} cash drawer`);
    assert.ok(doc.includes('class="dev dev-printer"'), `${code} receipt printer`);
    assert.ok(doc.includes('dev-kiosk-standing'), `${code} floor-standing kiosk`);
    assert.ok(doc.includes('dev-kds-mounted'), `${code} mounted KDS`);
  }
});

test('every product scene contains a real BIZBOT screen or kiosk video', () => {
  for (const [code, doc] of Object.entries(html)) {
    const scenes = doc.match(/<div class="(?:stage )?scene[^\"]*"[\s\S]*?<\/div>\s*<\/div>/g) || [];
    assert.ok(scenes.length >= 9, `${code} scenes found (${scenes.length})`);
    for (const scene of scenes) {
      const real = /\/assets\/shots\/(pos|kds|kiosk|dash)-\d-\d+\.webp/.test(scene) || /\/assets\/video\/kiosk-attract/.test(scene);
      assert.ok(real, `${code}: scene lacks real product media: ${scene.slice(0, 120)}…`);
    }
  }
});

test('generated environment and industry plates stay local, decorative and compact', () => {
  for (const [code, doc] of Object.entries(html)) {
    for (const name of ['counter-dark', 'kitchen', 'showroom', 'office']) {
      assert.ok(doc.includes(`/assets/env/env-${name}-`), `${code} environment ${name}`);
    }
    for (const name of ['restaurant', 'cafe', 'fastfood', 'sweets', 'cloud', 'more']) {
      const asset = `/assets/business/business-${name}-720.webp`;
      assert.ok(doc.includes(asset), `${code} business plate ${name}`);
      assert.ok(statSync(join(dist, asset)).size <= 60_000, `${asset} under 60 KB`);
    }
    for (const match of doc.matchAll(/<img class="(?:env|bphoto)"[^>]*>/g)) {
      assert.ok(match[0].includes('alt=""') && match[0].includes('aria-hidden="true"'), `${code} decorative plate semantics`);
    }
    assert.doesNotMatch(doc, /<(?:img|source|video)\b[^>]*(?:src|srcset|poster)="https?:\/\//i, `${code} hotlinked media`);
  }
});

test('showcase kiosk video remains silent, inline, lazy and user-controllable', () => {
  for (const [code, doc] of Object.entries(html)) {
    const videos = doc.match(/<video[^>]*>/g) || [];
    assert.equal(videos.length, 1, `${code} one user-invoked showcase video`);
    for (const video of videos) {
      for (const attr of ['playsinline', 'muted', 'loop', 'controls', 'preload="none"', 'poster="/assets/video/kiosk-attract-poster.webp"']) {
        assert.ok(video.includes(attr), `${code} video ${attr}`);
      }
    }
  }
});

const FAKE_METRIC = [
  ['percentage figure', /\d+\s*%|%\s*\d+|٪/],
  ['plus-count figure', /\+\s*\d|\d\s*\+/],
  ['fake SLA', /99[.,]9|uptime|زمن التشغيل|זמינות של/i],
  ['customer count', /\d+\s*(customers|clients|restaurants|businesses|عميل|عملاء|مطعم|مطاعم|לקוחות|מסעדות|עסקים)/i],
  ['growth claim', /\d+\s*(x|×)|sales up|increase(d)? sales|زيادة المبيعات بنسبة|עלייה של/i],
];

test('no invented business metrics exist in any locale', () => {
  for (const code of LOCALES) {
    const hits = [];
    for (const { path, value } of strings(locale(code))) {
      if (/^contact\.form\.(phonePh|branchesOptions)/.test(path)) continue;
      for (const [label, expression] of FAKE_METRIC) {
        if (expression.test(value)) hits.push(`${label} @ ${path}: "${value}"`);
      }
    }
    assert.deepEqual(hits, [], code);
  }
  for (const [code, doc] of Object.entries(html)) assert.ok(!/100%/.test(doc), `${code} renders a fake completion metric`);
});

test('no testimonials, ratings or customer-logo proof is introduced', () => {
  const socialProof = [/<blockquote/i, /testimonial/i, /\bratings?\b|aggregateRating|reviewRating/i, /★|⭐/, /trusted by/i, /يثق بنا|قال عنّا|آراء العملاء|شعارات العملاء/, /סומכים עלינו|לקוחותינו אומרים|ביקורות/, /class="logo-wall|class="logos/i];
  for (const [code, doc] of Object.entries(html)) {
    for (const expression of socialProof) assert.doesNotMatch(doc, expression, `${code} ${expression}`);
    assert.ok(doc.includes('class="bnote reveal"'), `${code} industry-example disclaimer`);
  }
});

test('motion respects user preference and depth effects require a desktop fine pointer', () => {
  const cssName = html.ar.match(/\/assets\/(site\.[a-f0-9]{10}\.css)/)[1];
  const jsName = html.ar.match(/\/assets\/(site\.[a-f0-9]{10}\.js)/)[1];
  const css = readFileSync(join(dist, 'assets', cssName), 'utf8');
  const js = readFileSync(join(dist, 'assets', jsName), 'utf8');
  assert.match(css, /@media \(prefers-reduced-motion: reduce\)/, 'reduced motion CSS');
  assert.ok(css.includes('animation-play-state: paused'), 'ambient loops start paused');
  assert.doesNotMatch(css, /animation[^;{}]*\binfinite\b/i, 'no continuously looping decorative animation');
  assert.ok(js.includes("matchMedia('(prefers-reduced-motion: reduce)')"), 'reduced motion JS');
  assert.ok(js.includes("matchMedia('(pointer: fine)')"), 'fine pointer check');
  assert.ok(js.includes('finePointer && window.innerWidth > 1024'), 'desktop depth gate');
  assert.ok(!js.includes('if(en.isIntersecting)playVideo(en.target)'), 'viewport entry does not autoplay long video');
  for (const [code, doc] of Object.entries(html)) {
    assert.ok(doc.includes('data-tilt'), `${code} explicit tilt opt-in`);
    assert.doesNotMatch(doc, / style="/, `${code} inline style (CSP)`);
  }
});

test('responsive hero and mobile navigation accessibility regressions stay fixed', () => {
  const cssName = html.ar.match(/\/assets\/(site\.[a-f0-9]{10}\.css)/)[1];
  const jsName = html.ar.match(/\/assets\/(site\.[a-f0-9]{10}\.js)/)[1];
  const css = readFileSync(join(dist, 'assets', cssName), 'utf8');
  const js = readFileSync(join(dist, 'assets', jsName), 'utf8');

  const hiddenKiosk = css.lastIndexOf('.scene-hero .obj-kiosk { display: none; }');
  const visibleKiosk = css.lastIndexOf('.scene-hero .obj-kiosk { display: block; }');
  assert.ok(hiddenKiosk >= 0 && visibleKiosk > hiddenKiosk, 'V3 cascade restores the hero kiosk below 1280px');
  assert.ok(js.includes('if (first) first.focus()'), 'opening the mobile menu moves focus inside');
  assert.ok(js.includes('else if (focusWasInside)'), 'closing the mobile menu returns focus');
  assert.ok(js.includes("if (e.key === 'Tab')"), 'mobile menu traps keyboard focus while open');

  for (const [code, doc] of Object.entries(html)) {
    const login = doc.match(/<a class="link-login"[^>]*>/)?.[0] || '';
    const footer = doc.slice(doc.indexOf('<footer'));
    assert.ok(login.includes('aria-label='), `${code} login has an accessible name`);
    assert.ok(doc.includes('<li class="bcard bcard-'), `${code} business cards use semantic list-item markup`);
    assert.ok(doc.includes('<div class="bcopy">'), `${code} business card content uses valid block markup`);
    assert.ok(footer.indexOf('href="#business"') < footer.indexOf('href="#features"'), `${code} footer follows page order`);
  }
});

test('lead form contract is unchanged by visual V3', () => {
  for (const [code, doc] of Object.entries(html)) {
    const form = doc.match(/<form class="lead-form[\s\S]*?<\/form>/)[0];
    for (const name of ['name', 'business', 'phone', 'email', 'type', 'branches', 'notes', 'website', 'locale', 't0']) {
      assert.ok(form.includes(`name="${name}"`), `${code} field ${name}`);
    }
    assert.ok(form.includes('action="/api/lead"') && form.includes('method="post"'), `${code} form action/method`);
    assert.ok(form.includes('class="form-status" role="status" aria-live="polite"'), `${code} live status`);
  }
});

/* ---------- Visual V4 guards: scroll story + mobile clarity ---------- */

const css4 = () => readFileSync(join(dist, 'assets', html.ar.match(/\/assets\/(site\.[a-f0-9]{10}\.css)/)[1]), 'utf8');
const js4 = () => readFileSync(join(dist, 'assets', html.ar.match(/\/assets\/(site\.[a-f0-9]{10}\.js)/)[1]), 'utf8');

test('V4 order journey: five steps, KDS states, real captures and a final connected state in every locale', () => {
  for (const code of LOCALES) {
    const doc = html[code];
    const t = locale(code);
    const section = doc.match(/<section class="journey"[\s\S]*?<\/section>/)[0];
    assert.equal(t.journey.steps.length, 5, `${code} five journey steps in copy`);
    assert.deepEqual(t.journey.steps.map((s) => s.id), ['kiosk', 'pos', 'kds', 'ready', 'dashboard'], `${code} journey order`);
    for (const st of t.journey.steps) assert.ok(section.includes(`>${st.title}<`), `${code} step title rendered: ${st.title}`);
    assert.equal(t.journey.kdsStates.length, 3, `${code} three KDS states`);
    for (const k of t.journey.kdsStates) assert.ok(section.includes(`>${k}</li>`), `${code} KDS state ${k}`);
    assert.ok(section.includes(t.journey.final), `${code} final connected badge`);
    // the stage shows the real product screens, never fabricated UI
    for (const shot of ['pos-1', 'kds-1', 'dash-1']) assert.ok(new RegExp(`/assets/shots/${shot}-\\d+\\.webp`).test(section), `${code} journey uses real ${shot}`);
    assert.ok(section.includes('/assets/video/kiosk-attract-poster.webp'), `${code} journey kiosk uses the real attract poster`);
    assert.equal((section.match(/class="jlit jlit-/g) || []).length, 3, `${code} three connector segments`);
    assert.equal((section.match(/class="jtoken jtoken-/g) || []).length, 3, `${code} order token per segment`);
    assert.ok(section.includes('data-scroll="journey"') && doc.includes('data-scroll="hero"'), `${code} scroll drivers opt in via data-scroll`);
    // hero order-state chip: received → sent to kitchen
    assert.ok(doc.includes(`class="st-a">${t.hero.orderStates[0]}<`) && doc.includes(`class="st-b">${t.hero.orderStates[1]}<`), `${code} hero order state chip`);
  }
});

test('V4 mobile: products and industries are vertical/grid — no carousel-only structure, no swipe to discover', () => {
  const css = css4();
  const mobile = css.slice(css.indexOf('Visual V4'));
  assert.match(mobile, /@media \(max-width: 768px\)[\s\S]*\.product-grid \{ display: grid; grid-template-columns: 1fr;[^}]*scroll-snap-type: none;/, 'products stack vertically at ≤768');
  assert.match(mobile, /@media \(max-width: 768px\)[\s\S]*\.bgrid \{ display: grid; grid-template-columns: repeat\(2, minmax\(0, 1fr\)\);[^}]*scroll-snap-type: none;/, 'industries become a 2-column grid at ≤768');
  // the V3 horizontal carousels must be neutralised: every scroll-snap declaration on these grids is overridden by the V4 block
  const v3Snap = (css.slice(0, css.indexOf('Visual V4')).match(/\.(product-grid|bgrid)[^{]*\{[^}]*scroll-snap-type: x mandatory/g) || []).length;
  const v4Reset = (mobile.match(/\.(product-grid|bgrid) \{[^}]*scroll-snap-type: none/g) || []).length;
  assert.ok(v4Reset >= v3Snap && v4Reset >= 2, 'V4 resets every mobile carousel rule');
  for (const [code, doc] of Object.entries(html)) {
    assert.equal((doc.match(/class="product-card product-card-/g) || []).length, 4, `${code} four products in the DOM`);
    assert.equal((doc.match(/class="bcard bcard-/g) || []).length, 6, `${code} six industries in the DOM`);
  }
});

test('V4 scroll: normal document scrolling only — no wheel/touch interception, one rAF driver, reduced-motion final state', () => {
  const js = js4();
  const css = css4();
  assert.doesNotMatch(js, /addEventListener\(\s*['"](wheel|mousewheel|touchmove|touchstart)['"]/, 'no wheel/touch listeners');
  assert.doesNotMatch(js, /preventDefault\(\)[^\n]*scroll|scroll[^\n]*preventDefault\(\)/i, 'scroll is never prevented');
  assert.doesNotMatch(js, /overflow\s*=\s*['"]hidden['"][^\n]*scroll/, 'no scroll locking for the story');
  assert.ok(js.includes("addEventListener('scroll', requestFrame, { passive: true })"), 'passive scroll listener feeding a single rAF');
  assert.ok(js.includes("if (kind === 'journey' && !storyDesktop) return;"), 'the pinned story is desktop-only');
  assert.match(css, /prefers-reduced-motion: reduce\)\s*\{[\s\S]*\.journey \{ --p: 1; \}/, 'reduced motion resolves the journey to its final state');
  assert.match(css, /prefers-reduced-motion: reduce\)\s*\{[\s\S]*:root \{ --hp: 1; \}/, 'reduced motion resolves the hero to its settled state');
  assert.ok(css.includes('.no-js .journey { --p: 1; }') && css.includes('.no-js { --hp: 1; }'), 'no-JS shows the connected state');
  // the token offset-paths must trace the very same connectors the SVG draws
  JOURNEY_PATHS.forEach((d, i) => assert.ok(css.includes(`.jtoken-${i + 1} { offset-path: path('${d}');`), `token ${i + 1} rides connector ${i + 1}`));
  for (const code of LOCALES) JOURNEY_PATHS.forEach((d) => assert.ok(html[code].includes(`d="${d}"`), `${code} connector drawn: ${d.slice(0, 12)}…`));
  assert.doesNotMatch(css, /animation[^;{}]*\binfinite\b/i, 'no infinite loops added by V4');
});
