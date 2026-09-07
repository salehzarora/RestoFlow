// HTML renderer for the BIZBOT marketing site. Pure function of (locale, ctx).
// No runtime dependencies — the build script feeds it the locale JSON, the
// site config and the hashed asset names, and writes the returned string.
//
// Visual V4 (on V3): the scroll-driven order journey, hero scroll life and a
// mobile presentation that never hides products behind a swipe. The Codex
// polish pass gives every real BIZBOT capture a more credible physical home:
// grounded POS hardware, a mounted KDS, a serviceable kiosk shell and a docked
// manager display. Real captures remain the only product UI. Presentation only
// — the lead form, its API contract and every product route are unchanged.

import { icon } from './icons.mjs';

const esc = (s) =>
  String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

// Locale copy may contain <em>…</em> for the highlighted word. Everything else
// is escaped so a stray angle bracket in a translation can never become markup.
const rich = (s) => esc(s).replace(/&lt;em&gt;/g, '<em>').replace(/&lt;\/em&gt;/g, '</em>');

const SHOT_WIDTHS = { land: [480, 800, 1200, 1600], port: [360, 600, 900] };
const SHOT_DIMS = { land: [1920, 1136], port: [1200, 1920] };

// Order-journey connectors in the stage's 1000×620 box (LTR; the SVG overlay is
// mirrored for RTL). styles.css repeats the same three paths as `offset-path`
// for the travelling tokens — visual.test.mjs asserts they stay identical.
export const JOURNEY_PATHS = [
  'M105 305 C 135 225 325 248 365 339', // kiosk top → reseated POS screen top
  'M222 489 C 155 414 410 132 510 132', // thermal-printer slot → KDS side
  'M780 132 C 875 132 820 270 820 367', // KDS (exits the other side) → tablet top
];
export const JOURNEY_PORTS = [
  [105, 305],
  [365, 339],
  [510, 132],
  [780, 132],
  [820, 367],
  [222, 489], // separate printer departure; screen arrival remains port 2
];

function kind(name) {
  return name.startsWith('kiosk') ? 'port' : 'land';
}

export function shot(name, alt, sizes, opts = {}) {
  const k = kind(name);
  const widths = SHOT_WIDTHS[k];
  const [w, h] = SHOT_DIMS[k];
  const src = `/assets/shots/${name}-${widths[widths.length - 2]}.webp`;
  const srcset = widths.map((x) => `/assets/shots/${name}-${x}.webp ${x}w`).join(', ');
  const eager = opts.eager ? ' loading="eager" fetchpriority="high" decoding="sync"' : ' loading="lazy" decoding="async"';
  const cls = opts.cls ? ` class="${opts.cls}"` : '';
  const extra = opts.attrs || '';
  return `<img${cls} src="${src}" srcset="${srcset}" sizes="${sizes}" width="${w}" height="${h}" alt="${esc(alt)}"${eager}${extra}>`;
}

/* ---------- environment plates (procedural, decorative) ---------- */

const ENV_WIDTHS = [960, 1600];
export function env(name, sizes = '(max-width: 960px) 100vw, 720px', opts = {}) {
  const srcset = ENV_WIDTHS.map((w) => `/assets/env/${name}-${w}.webp ${w}w`).join(', ');
  const eager = opts.eager ? ' loading="eager" fetchpriority="high"' : ' loading="lazy"';
  return `<img class="env" src="/assets/env/${name}-960.webp" srcset="${srcset}" sizes="${sizes}" width="1600" height="1067" alt="" aria-hidden="true" decoding="async"${eager}>`;
}

function businessImg(name) {
  return `<img class="bphoto" src="/assets/business/business-${name}-720.webp" width="720" height="480" alt="" aria-hidden="true" loading="lazy" decoding="async">`;
}

/* ---------- device frames ---------- */

function devPos(img, { printer = true, receiptTitle = 'Receipt', size = 'md', drawer = false, drawerAlt = '' } = {}) {
  const terminal = `<div class="dev dev-pos dev-pos-${size}">
    <div class="dev-screen"><span class="dev-cam" aria-hidden="true"></span>${img}<span class="glare" aria-hidden="true"></span></div>
    <span class="dev-pivot" aria-hidden="true"><i></i></span>
    <div class="dev-neck" aria-hidden="true"><i></i></div>
    <div class="dev-base" aria-hidden="true"><i></i></div>
  </div>`;
  if (!drawer) return `${terminal}${printer ? devPrinter(receiptTitle) : ''}`;
  return `<div class="counter-group">
    <span class="counter-mat" aria-hidden="true"></span>
    ${terminal}
    <div class="dev dev-drawer" role="img" aria-label="${esc(drawerAlt)}">
      <span class="drawer-top" aria-hidden="true"></span>
      <span class="drawer-front" aria-hidden="true"><i class="drawer-seam"></i><i class="drawer-grip"></i><i class="drawer-lock"></i><i class="drawer-slot"></i></span>
      <span class="drawer-foot drawer-foot-a" aria-hidden="true"></span><span class="drawer-foot drawer-foot-b" aria-hidden="true"></span>
    </div>
    ${printer ? devPrinter(receiptTitle) : ''}
    <span class="pos-cable" aria-hidden="true"></span>
    <span class="ground" aria-hidden="true"></span>
  </div>`;
}

function devPrinter(receiptTitle) {
  return `<div class="dev dev-printer" aria-hidden="true">
    <div class="paper"><span class="paper-brand">BIZBOT</span><span class="paper-title">${esc(receiptTitle)}</span><i></i><i></i><i class="short"></i><b></b><i></i><i class="short"></i><span class="paper-check">${icon('check')}</span></div>
    <div class="printer-body"><span class="printer-lid"><i></i></span><span class="slot"></span><span class="printer-seam"></span><span class="led"></span><span class="printer-control"></span><span class="printer-foot"></span></div>
  </div>`;
}

function devKds(img, { mounted = false } = {}) {
  return `<div class="dev dev-kds${mounted ? ' dev-kds-mounted' : ''}">
    ${mounted ? '<div class="kds-arm" aria-hidden="true"><span class="kds-rail"></span><i></i><b></b><em></em></div>' : '<div class="dev-mount" aria-hidden="true"></div>'}
    <div class="dev-screen">${img}<span class="glare" aria-hidden="true"></span><span class="kds-power" aria-hidden="true"></span></div>
    <div class="dev-bumpbar" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i></div>
  </div>`;
}

function devKiosk(inner, { standing = false } = {}) {
  return `<div class="dev dev-kiosk${standing ? ' dev-kiosk-standing' : ''}">
    <div class="kiosk-body">
      <div class="kiosk-cam" aria-hidden="true"></div>
      <span class="kiosk-speaker" aria-hidden="true"><i></i><i></i><i></i></span>
      <div class="dev-screen">${inner}<span class="glare" aria-hidden="true"></span></div>
      <div class="kiosk-reader" aria-hidden="true"><i></i></div>
      <span class="kiosk-receipt" aria-hidden="true"><i></i></span>
      <span class="kiosk-service" aria-hidden="true"><i></i></span>
    </div>
    ${standing ? '<div class="kiosk-stand" aria-hidden="true"><i></i><b></b></div><div class="kiosk-base" aria-hidden="true"><i></i></div><span class="ground ground-kiosk" aria-hidden="true"></span>' : '<div class="kiosk-foot" aria-hidden="true"></div>'}
  </div>`;
}

function devTablet(img) {
  return `<div class="dev dev-tablet">
    <span class="tablet-dock" aria-hidden="true"><i></i><b></b></span>
    <div class="dev-screen">${img}<span class="glare" aria-hidden="true"></span></div>
    <span class="tab-cam" aria-hidden="true"></span>
    <span class="tab-key" aria-hidden="true"></span>
    <span class="tablet-base" aria-hidden="true"><i></i></span>
    <span class="ground ground-tablet" aria-hidden="true"></span>
  </div>`;
}

function kioskVideo(t, posterOnly = false) {
  if (posterOnly) {
    return `<img class="kiosk-poster" src="/assets/video/kiosk-attract-poster.webp" width="540" height="864" alt="${esc(t.products.items[2].alt)}" loading="lazy" decoding="async">`;
  }
  return `<video class="kiosk-video" playsinline muted loop controls preload="none" poster="/assets/video/kiosk-attract-poster.webp" width="540" height="864" aria-label="${esc(t.showcase.tabs[2].shots[0].caption)}">
      <source src="/assets/video/kiosk-attract.mp4" type="video/mp4">
    </video>`;
}

function statusChip(text, ic = 'check', extra = '') {
  return `<span class="chip${extra ? ' ' + extra : ''}"><span class="chip-ic">${icon(ic)}</span><span>${esc(text)}</span></span>`;
}

/* ---------- brand lockup ---------- */

// Official brand bitmaps: WebP for browsers that take it, the PNG as the fallback
// (and the canonical asset reference). Same pixels, roughly a quarter of the bytes.
function brandImg(name, { cls = '', pic = '', w, h, alt = '', attrs = '' } = {}) {
  return `<picture class="pic${pic ? ' ' + pic : ''}"><source srcset="/assets/brand/${name}.webp" type="image/webp"><img class="${cls}" src="/assets/brand/${name}.png" width="${w}" height="${h}" alt="${esc(alt)}"${attrs}></picture>`;
}

function lockup(t, { reverse = false, size = 'md' } = {}) {
  const primaryAr = t.code !== 'en';
  const suf = reverse ? '-reverse' : '';
  const ar = brandImg(`bizbot-wordmark-ar${suf}`, { cls: 'wm wm-ar', pic: 'pic-ar', w: 456, h: 224, alt: 'بِزبط' });
  const en = brandImg(`bizbot-wordmark-en${suf}`, { cls: 'wm wm-en', pic: 'pic-en', w: 796, h: 152, alt: 'BIZBOT' });
  return `<span class="lockup lockup-${size}${reverse ? ' lockup-reverse' : ''}">
    ${brandImg('bizbot-symbol-256', { cls: 'symbol', w: 256, h: 256 })}
    <span class="lockup-words">${primaryAr ? ar + en : en + ar}</span>
  </span>`;
}

/* ---------- sections ---------- */

function header(t, cfg, locales) {
  const links = [
    ['#top', t.nav.home],
    ['#products', t.nav.products],
    ['#business', t.nav.business],
    ['#features', t.nav.features],
    ['#pricing', t.nav.pricing],
    ['#contact', t.nav.contact],
  ];
  const nav = links.map(([h, l]) => `<li><a href="${h}">${esc(l)}</a></li>`).join('');
  const langs = locales
    .map(
      (l) =>
        `<a href="${l.path}" lang="${l.htmlLang}" hreflang="${l.htmlLang}"${l.code === t.code ? ' aria-current="true"' : ''}>${esc(l.name)}</a>`,
    )
    .join('');
  return `<header class="site-header" id="header">
  <div class="container header-inner">
    <a class="brand" href="${t.path}" aria-label="${esc(t.code === 'en' ? 'BIZBOT — home' : 'بِزبط BIZBOT — ' + t.nav.home)}">${lockup(t, { reverse: true })}</a>
    <nav class="main-nav" aria-label="${esc(t.nav.menu)}"><ul>${nav}</ul></nav>
    <div class="header-actions">
      <div class="lang-switch" role="group" aria-label="${esc(t.nav.langLabel)}">${langs}</div>
      <a class="link-login" href="${cfg.appUrl}" rel="noopener" aria-label="${esc(t.nav.login)}">${icon('login')}<span>${esc(t.nav.login)}</span></a>
      <a class="btn btn-primary btn-sm" href="#contact">${esc(t.nav.cta)}</a>
      <button class="nav-toggle" type="button" aria-expanded="false" aria-controls="mobile-menu" aria-label="${esc(t.nav.menu)}">${icon('menu', 'ic-menu')}${icon('close', 'ic-close')}</button>
    </div>
  </div>
  <div class="mobile-menu" id="mobile-menu" hidden>
    <div class="container">
      <ul class="mobile-links">${nav}</ul>
      <div class="mobile-cta">
        <a class="btn btn-primary" href="#contact">${esc(t.nav.cta)}</a>
        <a class="btn btn-ghost" href="${cfg.appUrl}" rel="noopener">${esc(t.nav.login)}</a>
      </div>
      <div class="lang-switch lang-switch-mobile" role="group" aria-label="${esc(t.nav.langLabel)}">${langs}</div>
    </div>
  </div>
</header>`;
}

function hero(t) {
  const checks = t.hero.checks.map((c) => `<li>${icon('check')}<span>${esc(c)}</span></li>`).join('');
  const trust = t.hero.trust.map((x) => `<li>${icon(x.icon)}<span>${esc(x.text)}</span></li>`).join('');
  const states = t.hero.orderStates;
  const cards = t.hero.cards
    .map((c, i) =>
      i === 0
        ? `<li class="scard scard-1 scard-state" data-d="2">${icon('check')}<span class="st-stack"><span class="st-a">${esc(states[0])}</span><span class="st-b">${esc(states[1])}</span></span></li>`
        : `<li class="scard scard-${i + 1}" data-d="${i + 2}">${icon(c.icon)}<span>${esc(c.text)}</span></li>`,
    )
    .join('');
  const values = t.hero.cards
    .map((c) => `<li><span class="hvalue-icon">${icon(c.icon)}</span><span>${esc(c.text)}</span></li>`)
    .join('');
  const posImg = shot('pos-1', t.hero.deviceAlt, '(max-width: 720px) 88vw, (max-width: 1100px) 60vw, 560px', { eager: true });
  return `<section class="hero" id="top" data-scroll="hero">
  <div class="hero-bg" aria-hidden="true"><span class="glow glow-a"></span><span class="glow glow-b"></span><span class="grid"></span><span class="spot"></span></div>
  <div class="container hero-inner">
    <div class="hero-copy">
      <p class="eyebrow eyebrow-light reveal">${icon('spark')}<span>${esc(t.hero.eyebrow)}</span></p>
      <h1 class="reveal" data-d="1">${rich(t.hero.title)}</h1>
      <p class="lead reveal" data-d="2">${esc(t.hero.subtitle)}</p>
      <ul class="checks reveal" data-d="3">${checks}</ul>
      <div class="hero-cta reveal" data-d="4">
        <a class="btn btn-primary btn-lg btn-glow" href="#contact">${esc(t.hero.ctaPrimary)}${icon('arrow')}</a>
        <a class="btn btn-outline-light btn-lg" href="#showcase">${icon('play')}${esc(t.hero.ctaSecondary)}</a>
      </div>
      <ul class="trust reveal" data-d="5">${trust}</ul>
    </div>
    <div class="hero-visual reveal" data-d="2">
      <div class="scene scene-hero" data-tilt role="img" aria-label="${esc(t.hero.sceneAlt)}">
        ${env('env-counter-dark', '(max-width: 960px) 100vw, 760px', { eager: true })}
        <span class="scene-haze" aria-hidden="true"></span>
        <div class="layer layer-back" data-depth="0.35" aria-hidden="true">
          <div class="obj obj-kiosk">${devKiosk(`<img src="/assets/video/kiosk-attract-poster.webp" width="540" height="864" alt="" loading="lazy" decoding="async">`, { standing: true })}</div>
          <div class="obj obj-kds">${devKds(shot('kds-1', '', '(max-width: 960px) 34vw, 260px'), { mounted: true })}</div>
          <div class="obj obj-tablet">${devTablet(shot('dash-1', '', '(max-width: 960px) 40vw, 300px'))}</div>
        </div>
        <div class="layer layer-front" data-depth="1" aria-hidden="true">
          ${devPos(posImg, { printer: true, receiptTitle: t.hero.receiptTitle, size: 'lg', drawer: true, drawerAlt: t.hero.drawerAlt })}
        </div>
        <span class="scene-rim" aria-hidden="true"></span>
      </div>
      <ul class="scards" aria-hidden="true">${cards}</ul>
    </div>
  </div>
  <div class="container"><ul class="hero-value-strip reveal" data-d="5">${values}</ul></div>
  <span class="hero-link" aria-hidden="true"><i></i></span>
</section>`;
}

function sectionHead(s, light = false) {
  return `<div class="section-head reveal${light ? ' section-head-light' : ''}">
    <p class="eyebrow${light ? ' eyebrow-light' : ''}">${icon('spark')}<span>${esc(s.eyebrow)}</span></p>
    <h2>${rich(s.title)}</h2>
    <p class="sub">${esc(s.subtitle)}</p>
  </div>`;
}

// A short emerald thread at the top of a section: the page reads as one connected story.
function flowLink(dark = false) {
  return `<span class="flow-link${dark ? ' flow-link-dark' : ''} reveal" aria-hidden="true"><i></i><b></b></span>`;
}

function journey(t) {
  const j = t.journey;
  // KDS focus frame: an overlay that rides the real capture's ticket columns (new → preparing → ready)
  const kdsFocus = '<span class="jkds-focus" aria-hidden="true"><i></i></span>';
  const receipt = `<div class="jreceipt-wrap" aria-hidden="true"><div class="jreceipt">
          <span class="jr-head"><b>BIZBOT</b><span>${esc(t.hero.receiptTitle)}</span></span>
          <i class="jr-cut"></i>
          <span class="jr-row"><i class="jr-name"></i><i class="jr-amt"></i></span>
          <span class="jr-row"><i class="jr-name jr-w2"></i><i class="jr-amt"></i></span>
          <span class="jr-row"><i class="jr-name jr-w3"></i><i class="jr-amt"></i></span>
          <i class="jr-cut"></i>
          <span class="jr-row jr-total"><span>${esc(j.total)}</span><i class="jr-amt jr-amt-strong"></i></span>
          <span class="jr-paid">${icon('check')}<span>${esc(j.paid)}</span></span>
        </div></div>`;
  const pickup = `<div class="jpickup" aria-hidden="true"><span class="jp-ic">${icon('check')}</span><span class="jp-text"><b>${esc(j.pickup)}</b><small>${esc(j.pickupSub)}</small></span></div>`;
  const impact = `<ul class="jimpact" aria-hidden="true">
          <li class="jimpact-line"><svg class="jgrowth" viewBox="0 0 64 26" focusable="false"><path class="jgrowth-track" d="M2 22 C 12 20 16 12 24 14 S 38 8 46 9 S 56 4 62 3"/><path class="jgrowth-lit" pathLength="1" d="M2 22 C 12 20 16 12 24 14 S 38 8 46 9 S 56 4 62 3"/></svg></li>
          ${j.impact.map((x, i) => `<li class="jimpact-chip" data-i="${i + 1}">${icon('check')}<span>${esc(x)}</span></li>`).join('')}
        </ul>`;
  const mini = {
    kiosk: () => devKiosk(`<img src="/assets/video/kiosk-attract-poster.webp" width="540" height="864" alt="" loading="lazy" decoding="async">`, { standing: true }),
    pos: () => devPos(shot('pos-1', '', '(max-width: 1024px) 60vw, 1px'), { printer: true, receiptTitle: t.hero.receiptTitle, size: 'sm', drawer: true, drawerAlt: t.hero.drawerAlt }),
    kds: () => devKds(shot('kds-1', '', '(max-width: 1024px) 60vw, 1px') + kdsFocus, { mounted: true }),
    ready: () => pickup,
    dashboard: () => devTablet(shot('dash-1', '', '(max-width: 1024px) 60vw, 1px')) + impact,
  };
  const steps = j.steps
    .map(
      (st, i) => `<li class="jstep jstep-${st.id} reveal" data-step="${i + 1}" data-d="${(i % 3) + 1}">
        <span class="jmark" aria-hidden="true"><i class="jnum">${i + 1}</i><span class="jdot"></span></span>
        <figure class="jmini jmini-${st.id}" aria-hidden="true">${mini[st.id]()}</figure>
        <div class="jtext">
          <h3>${esc(st.title)}</h3>
          <p>${esc(st.desc)}</p>
          <span class="jstate">${icon(st.icon)}<span>${esc(st.state)}</span></span>
        </div>
      </li>`,
    )
    .join('');
  const kds = j.kdsStates.map((k, i) => `<li data-k="${i + 1}">${esc(k)}</li>`).join('');
  // Connector geometry in a 1000×620 box (LTR); the whole overlay is mirrored for RTL.
  // Ports sit on the device bezels: kiosk top → POS screen top → KDS side in/out → tablet top.
  const [P1, P2, P3] = JOURNEY_PATHS;
  // glow = a wide translucent stroke under the lit line (cheaper than a drop-shadow filter that re-rasterises every frame)
  const seg = (d, n) => `<path class="jtrack" d="${d}"/><path class="jglow jlit-${n}" pathLength="1" d="${d}"/><path class="jlit jlit-${n}" pathLength="1" d="${d}"/>`;
  const token = (d, n) => `<g class="jtoken jtoken-${n}"><circle class="jtoken-halo" r="18"/><circle class="jtoken-core" r="7"/></g>`;
  // the POS → kitchen token is the printed kitchen ticket itself (no text, so the RTL mirror is harmless)
  const ticket = `<g class="jtoken jtoken-2 jticket"><circle class="jtoken-halo" r="20"/><rect class="jticket-bg" x="-17" y="-12" width="34" height="24" rx="3.5"/><rect class="jticket-bar" x="-12" y="-7" width="24" height="3.5" rx="1.75"/><rect class="jticket-line" x="-12" y="0" width="17" height="2.4" rx="1.2"/><rect class="jticket-line" x="-12" y="5" width="12" height="2.4" rx="1.2"/></g>`;
  return `<section class="journey" id="journey" data-scroll="journey" aria-labelledby="journey-title">
  ${flowLink(true)}
  <div class="journey-sticky">
    <div class="container journey-grid">
      <div class="journey-copy">
        <p class="eyebrow eyebrow-light reveal">${icon('spark')}<span>${esc(j.eyebrow)}</span></p>
        <h2 id="journey-title" class="reveal" data-d="1">${rich(j.title)}</h2>
        <p class="sub reveal" data-d="2">${esc(j.subtitle)}</p>
        <ol class="jsteps">${steps}</ol>
        <p class="jhint" aria-hidden="true">${icon('arrow')}<span>${esc(j.hint)}</span></p>
      </div>
      <div class="journey-stage" aria-hidden="true">
        ${env('env-counter-dark', '(max-width: 1024px) 1px, 780px')}
        <span class="scene-haze"></span>
        <div class="jo jo-kiosk">${devKiosk(`<img src="/assets/video/kiosk-attract-poster.webp" width="540" height="864" alt="" loading="lazy" decoding="async">`, { standing: true })}</div>
        <div class="jo jo-pos">${devPos(shot('pos-1', '', '(max-width: 1024px) 1px, 240px'), { printer: true, receiptTitle: t.hero.receiptTitle, size: 'sm', drawer: true, drawerAlt: t.hero.drawerAlt })}</div>
        <div class="jo jo-kds">${devKds(shot('kds-1', '', '(max-width: 1024px) 1px, 230px') + kdsFocus, { mounted: true })}<ul class="jkds">${kds}</ul></div>
        <div class="jo jo-dash">${devTablet(shot('dash-1', '', '(max-width: 1024px) 1px, 210px'))}</div>
        ${receipt}
        <svg class="jlines" viewBox="0 0 1000 620" preserveAspectRatio="none" focusable="false">
          ${seg(P1, 1)}${seg(P2, 2)}${seg(P3, 3)}
          ${JOURNEY_PORTS.map(([x, y], i) => `<circle class="jport jport-${i + 1}" cx="${x}" cy="${y}" r="6"/>`).join('')}
          ${token(P1, 1)}${ticket}${token(P3, 3)}
        </svg>
        ${pickup}
        ${impact}
        <span class="jbadge jbadge-final">${icon('check')}<span>${esc(j.final)}</span></span>
        <span class="jveil"></span>
      </div>
    </div>
  </div>
</section>`;
}

function products(t) {
  const tabsById = Object.fromEntries(t.showcase.tabs.map((tab) => [tab.id, tab]));
  const scene = {
    pos: (it) => `<div class="scene scene-pos">
        ${env('env-counter-dark')}
        <span class="scene-haze" aria-hidden="true"></span>
        <div class="layer layer-front" data-depth="1">
          ${devPos(shot('pos-1', it.alt, '(max-width: 960px) 80vw, 440px'), { printer: true, receiptTitle: t.hero.receiptTitle, size: 'md', drawer: true, drawerAlt: t.hero.drawerAlt })}
        </div>
        ${statusChip(it.chip, 'check', 'chip-float chip-a')}
      </div>`,
    kds: (it) => `<div class="scene scene-kds">
        ${env('env-kitchen')}
        <div class="layer layer-front" data-depth="1">${devKds(shot('kds-1', it.alt, '(max-width: 960px) 86vw, 520px'), { mounted: true })}<span class="kds-ping" aria-hidden="true"></span></div>
        ${statusChip(it.chip, 'chef', 'chip-float chip-b chip-dark')}
      </div>`,
    kiosk: (it) => `<div class="scene scene-kiosk">
        ${env('env-showroom')}
        <div class="layer layer-front" data-depth="1">${devKiosk(kioskVideo(t, true) + '<span class="kiosk-wake" aria-hidden="true"></span>', { standing: true })}</div>
        ${statusChip(it.chip, 'touch', 'chip-float chip-c')}
      </div>`,
    dashboard: (it) => `<div class="scene scene-dashboard">
        ${env('env-office')}
        <div class="layer layer-front" data-depth="1">${devTablet(shot('dash-1', it.alt, '(max-width: 960px) 86vw, 520px') + '<span class="dash-scan" aria-hidden="true"></span>')}</div>
        ${statusChip(it.chip, 'chart', 'chip-float chip-d')}
      </div>`,
  };
  const rows = t.products.items
    .map((it, i) => {
      const tab = tabsById[it.id];
      const points = (tab ? tab.points : []).slice(0, 2).map((p) => `<li>${icon('check')}<span>${esc(p)}</span></li>`).join('');
      return `<article class="product-card product-card-${it.id} reveal" id="product-${it.id}" data-d="${(i % 2) + 1}">
      <div class="product-media">${scene[it.id](it)}</div>
      <div class="product-copy">
        <span class="tag">${esc(it.tag)}</span>
        <h3>${esc(it.title)}</h3>
        <p class="product-desc">${esc(it.desc)}</p>
        <ul class="points">${points}</ul>
        <a class="more" href="#showcase" data-tab="${it.id}">${esc(t.products.more)}${icon('arrow')}</a>
      </div>
    </article>`;
    })
    .join('');
  return `<section class="section products" id="products">
  <div class="container">
    ${sectionHead(t.products)}
    <div class="product-grid">${rows}</div>
  </div>
</section>`;
}

function story(t) {
  const problems = t.story.items
    .map((s) => `<li><span class="story-bullet story-bullet-muted">${icon(s.icon)}</span><span>${esc(s.problem)}</span></li>`)
    .join('');
  const solutions = t.story.items
    .map((s) => `<li><span class="story-bullet">${icon('check')}</span><span><strong>${esc(s.solution)}</strong><small>${esc(s.tag)}</small></span></li>`)
    .join('');
  return `<section class="section story" id="story">
  ${flowLink(true)}
  <div class="container">
    ${sectionHead(t.story)}
    <div class="story-shift reveal" data-d="1">
      <div class="story-side story-before">
        <span class="story-label">${esc(t.story.problemLabel)}</span>
        <ul>${problems}</ul>
      </div>
      <div class="story-transition" aria-hidden="true"><span>${icon('arrow')}</span><i></i></div>
      <div class="story-side story-after">
        <span class="story-label">${esc(t.story.solutionLabel)}</span>
        <ul>${solutions}</ul>
      </div>
    </div>
  </div>
</section>`;
}

function features(t) {
  const selected = [t.features.items[4], t.features.items[7], t.why.items[0], t.why.items[1], t.why.items[3], t.why.items[5]];
  const tiles = selected
    .map(
      (f, i) => `<li class="benefit-card reveal" data-d="${(i % 3) + 1}">
      <span class="benefit-icon">${icon(f.icon)}</span>
      <div><h3>${esc(f.title)}</h3><p>${esc(f.desc)}</p></div>
    </li>`,
    )
    .join('');
  const promises = t.statement.lines.map((line) => `<span>${esc(line)}</span>`).join('');
  return `<section class="section benefits" id="features">
  ${flowLink(true)}
  <div class="benefits-bg" aria-hidden="true"><span class="glow glow-a"></span><span class="grid"></span></div>
  <div class="container benefits-layout">
    <div class="benefits-copy reveal">
      <img src="/assets/brand/bizbot-symbol-512.webp" width="512" height="512" alt="" aria-hidden="true" loading="lazy" decoding="async">
      <p class="eyebrow eyebrow-light">${icon('spark')}<span>${esc(t.features.eyebrow)}</span></p>
      <h2>${esc(t.statement.brandLine)}</h2>
      <p>${esc(t.features.subtitle)}</p>
      <div class="promise-line">${promises}</div>
    </div>
    <ul class="benefit-grid">${tiles}</ul>
  </div>
</section>`;
}

function statement(t) {
  const lines = t.statement.lines.map((l, i) => `<span class="st-line" data-d="${i + 1}">${esc(l)}</span>`).join('');
  return `<section class="statement" aria-label="${esc(t.statement.brandLine)}">
  <div class="container statement-inner">
    <div class="st-brand reveal">
      <img class="st-symbol" src="/assets/brand/bizbot-symbol-512.webp" width="512" height="512" alt="${esc(t.statement.symbolAlt)}" loading="lazy" decoding="async">
      <div class="st-words">
        ${brandImg('bizbot-wordmark-ar', { cls: 'st-wm st-wm-ar', w: 456, h: 224, alt: 'بِزبط', attrs: ' loading="lazy"' })}
        ${brandImg('bizbot-wordmark-en', { cls: 'st-wm st-wm-en', w: 796, h: 152, alt: 'BIZBOT', attrs: ' loading="lazy"' })}
        <p>${esc(t.statement.brandLine)}</p>
      </div>
    </div>
    <p class="st-lines reveal" data-d="2">${lines}<span class="st-underline" aria-hidden="true"></span></p>
  </div>
</section>`;
}

function business(t) {
  const photoName = { restaurant: 'restaurant', cafe: 'cafe', sweets: 'sweets', fastfood: 'fastfood', cloud: 'cloud', more: 'more' };
  const cards = t.business.items
    .map(
      (b, i) => `<li class="bcard bcard-${b.icon} reveal" data-d="${(i % 3) + 1}">
      <div class="bscene">${businessImg(photoName[b.icon] || 'more')}<i aria-hidden="true"></i></div>
      <div class="bcopy"><span class="bicon">${icon(b.icon)}</span><div><h3>${esc(b.title)}</h3><p>${esc(b.desc)}</p></div></div>
    </li>`,
    )
    .join('');
  return `<section class="section business" id="business">
  ${flowLink(false)}
  <div class="container">
    ${sectionHead(t.business)}
    <ul class="bgrid">${cards}</ul>
    <p class="bnote reveal">${esc(t.business.note)}</p>
  </div>
</section>`;
}

function showcase(t) {
  const tabs = t.showcase.tabs
    .map(
      (tab, i) =>
        `<button class="tab" role="tab" id="tab-${tab.id}" aria-controls="panel-${tab.id}" aria-selected="${i === 0}" tabindex="${i === 0 ? 0 : -1}" data-tab="${tab.id}">${esc(tab.label)}</button>`,
    )
    .join('');

  const stageFor = (tab) => {
    const first = tab.shots[0];
    const sizes = '(max-width: 900px) 92vw, 680px';
    if (tab.id === 'pos') return `${env('env-counter-dark')}<div class="layer layer-front">${devPos(shot(first.src, `${tab.label} — ${first.caption}`, sizes, { attrs: ' data-stage-img' }), { printer: true, receiptTitle: t.hero.receiptTitle, size: 'lg', drawer: true, drawerAlt: t.hero.drawerAlt })}</div>`;
    if (tab.id === 'kds') return `${env('env-kitchen')}<div class="layer layer-front">${devKds(shot(first.src, `${tab.label} — ${first.caption}`, sizes, { attrs: ' data-stage-img' }), { mounted: true })}</div>`;
    if (tab.id === 'dashboard') return `${env('env-office')}<div class="layer layer-front">${devTablet(shot(first.src, `${tab.label} — ${first.caption}`, sizes, { attrs: ' data-stage-img' }))}</div>`;
    // kiosk: video first, images swap in
    return `${env('env-showroom')}<div class="layer layer-front">${devKiosk(
      `${kioskVideo(t)}${shot('kiosk-3', `${tab.label} — ${tab.shots[1].caption}`, '(max-width: 900px) 60vw, 300px', { attrs: ' data-stage-img hidden' })}`,
      { standing: true },
    )}</div>`;
  };

  const panels = t.showcase.tabs
    .map((tab, i) => {
      const points = tab.points.map((p) => `<li>${icon('check')}<span>${esc(p)}</span></li>`).join('');
      const thumbs = tab.shots
        .map((s, j) => {
          const isVideo = s.src === 'video';
          const inner = isVideo
            ? `<img src="/assets/video/kiosk-attract-poster.webp" width="540" height="864" alt="" loading="lazy"><span class="thumb-play">${icon('play')}</span>`
            : shot(s.src, '', '120px', { attrs: ' aria-hidden="true"' });
          return `<button class="thumb${j === 0 ? ' is-active' : ''}" type="button" data-shot="${s.src}" aria-label="${esc(s.caption)}" aria-pressed="${j === 0}">${inner}</button>`;
        })
        .join('');
      return `<div class="panel" role="tabpanel" id="panel-${tab.id}" aria-labelledby="tab-${tab.id}"${i === 0 ? '' : ' hidden'} data-kind="${tab.id}">
      <div class="show-grid">
        <div class="stage scene scene-stage scene-${tab.id} stage-${tab.id}">${stageFor(tab)}</div>
        <div class="show-copy">
          <h3>${esc(tab.title)}</h3>
          <ul class="points points-light">${points}</ul>
          <p class="caption" data-caption>${esc(tab.shots[0].caption)}</p>
          <div class="thumbs" role="group">${thumbs}</div>
        </div>
      </div>
    </div>`;
    })
    .join('');

  return `<section class="section showcase" id="showcase">
  ${flowLink(true)}
  <div class="showcase-bg" aria-hidden="true"><span class="glow glow-a"></span><span class="grid"></span></div>
  <div class="container">
    ${sectionHead(t.showcase, true)}
    <div class="tabs reveal" role="tablist" aria-label="${esc(t.showcase.eyebrow)}">${tabs}</div>
    <div class="panels reveal" data-d="1">${panels}</div>
  </div>
</section>`;
}

function why(t) {
  const items = t.why.items
    .map(
      (w, i) => `<li class="wcard reveal" data-d="${(i % 3) + 1}">
      <span class="wicon">${icon(w.icon)}</span>
      <div><h3>${esc(w.title)}</h3><p>${esc(w.desc)}</p></div>
    </li>`,
    )
    .join('');
  return `<section class="section why" id="why">
  <div class="container">
    ${sectionHead(t.why)}
    <ul class="wgrid">${items}</ul>
  </div>
</section>`;
}

function pricing(t) {
  const inc = t.pricing.includes.map((x) => `<li>${icon('check')}<span>${esc(x)}</span></li>`).join('');
  return `<section class="section pricing" id="pricing">
  ${flowLink(false)}
  <div class="container">
    <div class="price-card reveal">
      <div class="price-copy">
        <p class="eyebrow">${icon('spark')}<span>${esc(t.pricing.eyebrow)}</span></p>
        <h2>${esc(t.pricing.title)}</h2>
        <p class="sub">${esc(t.pricing.subtitle)}</p>
        <a class="btn btn-primary btn-lg btn-glow" href="#contact">${esc(t.pricing.cta)}${icon('arrow')}</a>
        <p class="note">${esc(t.pricing.note)}</p>
      </div>
      <ul class="price-includes">${inc}</ul>
    </div>
  </div>
</section>`;
}

function select(name, label, options, placeholder, required = true) {
  const opts = options.map((o) => `<option value="${esc(o.value)}">${esc(o.label)}</option>`).join('');
  return `<div class="field">
    <label for="f-${name}">${esc(label)}</label>
    <select id="f-${name}" name="${name}"${required ? ' required' : ''}><option value="" selected disabled>${esc(placeholder)}</option>${opts}</select>
  </div>`;
}

function contact(t, cfg) {
  const f = t.contact.form;
  const phoneRow = cfg.contact.phone
    ? `<li>${icon('phone')}<span><small>${esc(t.contact.phoneLabel)}</small><a href="tel:${esc(cfg.contact.phone.replace(/[^+\d]/g, ''))}" dir="ltr">${esc(cfg.contact.phone)}</a></span></li>`
    : '';
  const waRow = cfg.contact.whatsapp
    ? `<li>${icon('whatsapp')}<span><small>${esc(t.contact.whatsappLabel)}</small><a href="https://wa.me/${esc(cfg.contact.whatsapp.replace(/\D/g, ''))}" rel="noopener" dir="ltr">${esc(cfg.contact.whatsapp)}</a></span></li>`
    : '';
  const perks = t.contact.perks.map((p) => `<li>${icon('check')}<span>${esc(p)}</span></li>`).join('');
  return `<section class="section contact" id="contact">
  ${flowLink(true)}
  <div class="contact-bg" aria-hidden="true"><span class="glow glow-a"></span><span class="glow glow-b"></span></div>
  <div class="container contact-grid">
    <div class="contact-copy reveal">
      <p class="eyebrow eyebrow-light">${icon('spark')}<span>${esc(t.contact.eyebrow)}</span></p>
      <h2>${rich(t.contact.title)}</h2>
      <p class="sub">${esc(t.contact.subtitle)}</p>
      <ul class="perks">${perks}</ul>
      <ul class="contact-list">
        <li>${icon('mail')}<span><small>${esc(t.contact.emailLabel)}</small><a href="mailto:${esc(cfg.contact.sales)}" dir="ltr">${esc(cfg.contact.sales)}</a></span></li>
        <li>${icon('shield')}<span><small>${esc(t.contact.supportLabel)}</small><a href="mailto:${esc(cfg.contact.support)}" dir="ltr">${esc(cfg.contact.support)}</a></span></li>
        ${phoneRow}${waRow}
        <li>${icon('login')}<span><small>${esc(t.contact.appLabel)}</small><a href="${cfg.appUrl}" rel="noopener">${esc(t.contact.appLink)}</a></span></li>
      </ul>
      <div class="contact-visual" aria-hidden="true">${devTablet(shot('dash-1', '', '(max-width: 960px) 70vw, 380px'))}</div>
    </div>
    <form class="lead-form reveal" id="lead-form" method="post" action="/api/lead" novalidate data-d="1" data-sales="${esc(cfg.contact.sales)}">
      <div class="form-grid">
        <div class="field"><label for="f-name">${esc(f.name)}</label><input id="f-name" name="name" type="text" autocomplete="name" required minlength="2" maxlength="80" placeholder="${esc(f.namePh)}"></div>
        <div class="field"><label for="f-business">${esc(f.business)}</label><input id="f-business" name="business" type="text" autocomplete="organization" required minlength="2" maxlength="120" placeholder="${esc(f.businessPh)}"></div>
        <div class="field"><label for="f-phone">${esc(f.phone)}</label><input id="f-phone" name="phone" type="tel" autocomplete="tel" inputmode="tel" required minlength="6" maxlength="25" placeholder="${esc(f.phonePh)}" dir="ltr"></div>
        <div class="field"><label for="f-email">${esc(f.email)}</label><input id="f-email" name="email" type="email" autocomplete="email" inputmode="email" required maxlength="120" placeholder="${esc(f.emailPh)}" dir="ltr"></div>
        ${select('type', f.type, f.typeOptions, f.select)}
        ${select('branches', f.branches, f.branchesOptions, f.select)}
        <div class="field field-full"><label for="f-notes">${esc(f.notes)}</label><textarea id="f-notes" name="notes" rows="3" maxlength="1500" placeholder="${esc(f.notesPh)}"></textarea></div>
      </div>
      <div class="hp" aria-hidden="true"><label for="f-website">Website</label><input id="f-website" name="website" type="text" tabindex="-1" autocomplete="off"></div>
      <input type="hidden" name="locale" value="${t.code}">
      <input type="hidden" name="t0" value="">
      <div class="form-foot">
        <button class="btn btn-primary btn-lg" type="submit" data-label="${esc(f.submit)}" data-sending="${esc(f.sending)}">${esc(f.submit)}${icon('arrow')}</button>
        <p class="privacy">${esc(f.privacy)}</p>
      </div>
      <p class="form-status" role="status" aria-live="polite" data-success="${esc(f.success)}" data-error="${esc(f.errorGeneric)}" data-invalid="${esc(f.errorInvalid)}"></p>
    </form>
  </div>
</section>`;
}

function footer(t, cfg, locales) {
  const prod = t.footer.productLinks
    .map((l, i) => `<li><a href="#showcase" data-tab="${['pos', 'kds', 'kiosk', 'dashboard'][i]}">${esc(l)}</a></li>`)
    .join('');
  const links = [
    ['#top', t.nav.home],
    ['#business', t.nav.business],
    ['#features', t.nav.features],
    ['#pricing', t.nav.pricing],
    ['#contact', t.nav.contact],
  ]
    .map(([h, l]) => `<li><a href="${h}">${esc(l)}</a></li>`)
    .join('');
  const SOCIAL_LABEL = { instagram: 'Instagram', facebook: 'Facebook', linkedin: 'LinkedIn', tiktok: 'TikTok', youtube: 'YouTube', x: 'X' };
  const socials = Object.entries(cfg.social)
    .filter(([, url]) => typeof url === 'string' && /^https:\/\//.test(url))
    .map(([k, url]) => `<a href="${esc(url)}" rel="noopener" target="_blank">${k === 'instagram' ? icon('instagram') : ''}<span>${esc(SOCIAL_LABEL[k] || k)}</span></a>`)
    .join('');
  const langs = locales
    .map((l) => `<li><a href="${l.path}" lang="${l.htmlLang}" hreflang="${l.htmlLang}">${esc(l.name)}</a></li>`)
    .join('');
  return `<footer class="site-footer">
  <div class="container">
    <div class="foot-grid">
      <div class="foot-brand">
        ${lockup(t, { reverse: true, size: 'lg' })}
        <p>${esc(t.footer.tagline)}</p>
        ${socials ? `<div class="socials">${socials}</div>` : ''}
      </div>
      <div class="foot-col"><h3>${esc(t.footer.products)}</h3><ul>${prod}</ul></div>
      <div class="foot-col"><h3>${esc(t.footer.links)}</h3><ul>${links}</ul></div>
      <div class="foot-col">
        <h3>${esc(t.footer.contact)}</h3>
        <ul>
          <li><a href="mailto:${esc(cfg.contact.sales)}" dir="ltr">${esc(cfg.contact.sales)}</a></li>
          <li><a href="mailto:${esc(cfg.contact.support)}" dir="ltr">${esc(cfg.contact.support)}</a></li>
          <li><a href="${cfg.appUrl}" rel="noopener">${esc(t.footer.login)}</a></li>
        </ul>
        <h3 class="mt">${esc(t.footer.languages)}</h3>
        <ul class="foot-langs">${langs}</ul>
      </div>
    </div>
    <div class="foot-bottom">
      <p>© ${cfg.copyrightYear} BIZBOT · بِزبط — ${esc(t.footer.rights)}</p>
      <p class="foot-domain" dir="ltr">bizbot.systems</p>
    </div>
  </div>
</footer>`;
}

/* ---------- document ---------- */

function jsonLd(t, cfg, locales) {
  const url = cfg.siteUrl + (t.path === '/' ? '/' : t.path);
  const sameAs = Object.values(cfg.social).filter(Boolean);
  const data = [
    {
      '@context': 'https://schema.org',
      '@type': 'Organization',
      name: 'BIZBOT',
      alternateName: 'بِزبط',
      url: cfg.siteUrl + '/',
      logo: cfg.siteUrl + '/assets/brand/bizbot-symbol-512.png',
      email: cfg.contact.sales,
      ...(sameAs.length ? { sameAs } : {}),
    },
    {
      '@context': 'https://schema.org',
      '@type': 'SoftwareApplication',
      name: 'BIZBOT',
      alternateName: 'بِزبط',
      applicationCategory: 'BusinessApplication',
      operatingSystem: 'Android, Web',
      url,
      description: t.meta.description,
      inLanguage: locales.map((l) => l.htmlLang),
      offers: { '@type': 'Offer', priceCurrency: 'ILS', price: '0', description: 'Custom quote' },
    },
  ];
  return `<script type="application/ld+json">${JSON.stringify(data).replace(/</g, '\\u003c')}</script>`;
}

export function renderPage(t, ctx) {
  const { cfg, locales, assets } = ctx;
  const url = cfg.siteUrl + (t.path === '/' ? '/' : t.path);
  const alternates = locales
    .map((l) => `<link rel="alternate" hreflang="${l.htmlLang}" href="${cfg.siteUrl}${l.path === '/' ? '/' : l.path}">`)
    .join('\n  ');
  const fontPreloads =
    t.code === 'ar'
      ? ['rubik-arabic', 'alexandria-arabic']
      : t.code === 'he'
        ? ['rubik-hebrew', 'rubik-latin']
        : ['rubik-latin', 'inter-latin'];
  const preload = fontPreloads
    .map((f) => `<link rel="preload" href="/assets/fonts/${f}.woff2" as="font" type="font/woff2" crossorigin>`)
    .join('\n  ');
  return `<!doctype html>
<html lang="${t.htmlLang}" dir="${t.dir}" data-locale="${t.code}" class="no-js">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>${esc(t.meta.title)}</title>
  <meta name="description" content="${esc(t.meta.description)}">
  <link rel="canonical" href="${url}">
  ${alternates}
  <link rel="alternate" hreflang="x-default" href="${cfg.siteUrl}/">
  <meta name="theme-color" content="#1F2937">
  <meta name="color-scheme" content="light">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="BIZBOT | بِزبط">
  <meta property="og:title" content="${esc(t.meta.title)}">
  <meta property="og:description" content="${esc(t.meta.description)}">
  <meta property="og:url" content="${url}">
  <meta property="og:image" content="${cfg.siteUrl}/assets/og/og-${t.code}.png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:locale" content="${t.ogLocale}">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${esc(t.meta.title)}">
  <meta name="twitter:description" content="${esc(t.meta.description)}">
  <meta name="twitter:image" content="${cfg.siteUrl}/assets/og/og-${t.code}.png">
  <link rel="icon" href="/favicon.ico" sizes="32x32">
  <link rel="icon" href="/assets/icons/favicon-48.png" type="image/png" sizes="48x48">
  <link rel="apple-touch-icon" href="/assets/icons/apple-touch-icon.png">
  <link rel="manifest" href="/site.webmanifest">
  ${preload}
  <link rel="preload" as="image" href="/assets/shots/pos-1-1200.webp" imagesrcset="/assets/shots/pos-1-800.webp 800w, /assets/shots/pos-1-1200.webp 1200w, /assets/shots/pos-1-1600.webp 1600w" imagesizes="(max-width: 720px) 88vw, (max-width: 1100px) 60vw, 560px">
  <link rel="preload" as="image" href="/assets/env/env-counter-dark-960.webp" imagesrcset="/assets/env/env-counter-dark-960.webp 960w, /assets/env/env-counter-dark-1600.webp 1600w" imagesizes="(max-width: 960px) 100vw, 760px">
  <link rel="stylesheet" href="/assets/${assets.css}">
  ${jsonLd(t, cfg, locales)}
</head>
<body>
  <a class="skip" href="#main">${esc(t.skip)}</a>
  ${header(t, cfg, locales)}
  <main id="main">
    ${hero(t)}
    ${products(t)}
    ${journey(t)}
    ${story(t)}
    ${business(t)}
    ${features(t)}
    ${showcase(t)}
    ${pricing(t)}
    ${contact(t, cfg)}
  </main>
  ${footer(t, cfg, locales)}
  <script src="/assets/${assets.js}" defer></script>
</body>
</html>
`;
}
