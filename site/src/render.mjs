// HTML renderer for the BIZBOT marketing site. Pure function of (locale, ctx).
// No runtime dependencies — the build script feeds it the locale JSON, the
// site config and the hashed asset names, and writes the returned string.

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

function kind(name) {
  return name.startsWith('kiosk') ? 'port' : 'land';
}

export function shot(name, alt, sizes, opts = {}) {
  const k = kind(name);
  const widths = SHOT_WIDTHS[k];
  const [w, h] = SHOT_DIMS[k];
  const src = `/assets/shots/${name}-${widths[widths.length - 2]}.webp`;
  const srcset = widths.map((x) => `/assets/shots/${name}-${x}.webp ${x}w`).join(', ');
  const eager = opts.eager ? ' loading="eager" fetchpriority="high"' : ' loading="lazy"';
  const cls = opts.cls ? ` class="${opts.cls}"` : '';
  const extra = opts.attrs || '';
  return `<img${cls} src="${src}" srcset="${srcset}" sizes="${sizes}" width="${w}" height="${h}" alt="${esc(alt)}" decoding="async"${eager}${extra}>`;
}

/* ---------- device frames ---------- */

function devPos(img, { printer = true, receiptTitle = 'Receipt', size = 'md' } = {}) {
  return `<div class="dev dev-pos dev-pos-${size}">
    <div class="dev-screen">${img}</div>
    <div class="dev-neck" aria-hidden="true"></div>
    <div class="dev-base" aria-hidden="true"></div>
  </div>${printer ? devPrinter(receiptTitle) : ''}`;
}

function devPrinter(receiptTitle) {
  return `<div class="dev dev-printer" aria-hidden="true">
    <div class="paper"><span class="paper-brand">BIZBOT</span><span class="paper-title">${esc(receiptTitle)}</span><i></i><i></i><i class="short"></i><b></b><i></i><i class="short"></i><span class="paper-check">${icon('check')}</span></div>
    <div class="printer-body"><span class="slot"></span><span class="led"></span><span class="btn"></span></div>
  </div>`;
}

function devKds(img) {
  return `<div class="dev dev-kds">
    <div class="dev-mount" aria-hidden="true"></div>
    <div class="dev-screen">${img}</div>
    <div class="dev-bumpbar" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i></div>
  </div>`;
}

function devKiosk(inner) {
  return `<div class="dev dev-kiosk">
    <div class="kiosk-body">
      <div class="kiosk-cam" aria-hidden="true"></div>
      <div class="dev-screen">${inner}</div>
      <div class="kiosk-reader" aria-hidden="true"><i></i></div>
    </div>
    <div class="kiosk-foot" aria-hidden="true"></div>
  </div>`;
}

function devTablet(img) {
  return `<div class="dev dev-tablet">
    <div class="dev-screen">${img}</div>
    <span class="tab-cam" aria-hidden="true"></span>
  </div>`;
}

function kioskVideo(t, posterOnly = false) {
  if (posterOnly) {
    return `<img class="kiosk-poster" src="/assets/video/kiosk-attract-poster.webp" width="540" height="864" alt="${esc(t.products.items[2].alt)}" loading="lazy" decoding="async">`;
  }
  return `<video class="kiosk-video" playsinline muted loop preload="none" poster="/assets/video/kiosk-attract-poster.webp" width="540" height="864" aria-label="${esc(t.showcase.tabs[2].shots[0].caption)}">
      <source src="/assets/video/kiosk-attract.mp4" type="video/mp4">
    </video>`;
}

/* ---------- brand lockup ---------- */

function lockup(t, { reverse = false, size = 'md' } = {}) {
  const primaryAr = t.code !== 'en';
  const suf = reverse ? '-reverse' : '';
  const ar = `<img class="wm wm-ar" src="/assets/brand/bizbot-wordmark-ar${suf}.png" width="456" height="224" alt="بِزبط">`;
  const en = `<img class="wm wm-en" src="/assets/brand/bizbot-wordmark-en${suf}.png" width="796" height="152" alt="BIZBOT">`;
  return `<span class="lockup lockup-${size}${reverse ? ' lockup-reverse' : ''}">
    <img class="symbol" src="/assets/brand/bizbot-symbol-256.png" width="256" height="256" alt="">
    <span class="lockup-words">${primaryAr ? ar + en : en + ar}</span>
  </span>`;
}

/* ---------- sections ---------- */

function header(t, cfg, locales) {
  const links = [
    ['#top', t.nav.home],
    ['#products', t.nav.products],
    ['#features', t.nav.features],
    ['#business', t.nav.business],
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
    <a class="brand" href="${t.path}" aria-label="${esc(t.code === 'en' ? 'BIZBOT — home' : 'بِزبط BIZBOT — ' + t.nav.home)}">${lockup(t)}</a>
    <nav class="main-nav" aria-label="${esc(t.nav.menu)}"><ul>${nav}</ul></nav>
    <div class="header-actions">
      <div class="lang-switch" role="group" aria-label="${esc(t.nav.langLabel)}">${langs}</div>
      <a class="link-login" href="${cfg.appUrl}" rel="noopener">${icon('login')}<span>${esc(t.nav.login)}</span></a>
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
  const trust = t.hero.trust
    .map((x) => `<li>${icon(x.icon)}<span>${esc(x.text)}</span></li>`)
    .join('');
  return `<section class="hero" id="top">
  <div class="hero-bg" aria-hidden="true"><span class="glow glow-a"></span><span class="glow glow-b"></span><span class="grid"></span></div>
  <div class="container hero-inner">
    <div class="hero-copy">
      <p class="eyebrow eyebrow-light reveal">${icon('spark')}<span>${esc(t.hero.eyebrow)}</span></p>
      <h1 class="reveal" data-d="1">${rich(t.hero.title)}</h1>
      <p class="lead reveal" data-d="2">${esc(t.hero.subtitle)}</p>
      <ul class="checks reveal" data-d="3">${checks}</ul>
      <div class="hero-cta reveal" data-d="4">
        <a class="btn btn-primary btn-lg" href="#contact">${esc(t.hero.ctaPrimary)}${icon('arrow')}</a>
        <a class="btn btn-outline-light btn-lg" href="#showcase">${icon('play')}${esc(t.hero.ctaSecondary)}</a>
      </div>
      <ul class="trust reveal" data-d="5">${trust}</ul>
    </div>
    <div class="hero-visual reveal" data-d="2" aria-hidden="false">
      <div class="cluster">
        <div class="float float-kds">${devKds(shot('kds-1', t.hero.kdsAlt, '(max-width: 720px) 60vw, 360px'))}</div>
        <div class="float float-pos">${devPos(shot('pos-1', t.hero.deviceAlt, '(max-width: 720px) 92vw, 620px', { eager: true }), { printer: true, receiptTitle: t.hero.receiptTitle, size: 'lg' })}</div>
        <div class="chip chip-sent float float-chip-a"><span class="chip-ic">${icon('check')}</span><span>${esc(t.hero.floatSent)}</span></div>
        <div class="chip chip-ready float float-chip-b"><span class="chip-ring"><b>${esc(t.hero.floatReadyValue)}</b></span><span>${esc(t.hero.floatReady)}</span></div>
      </div>
    </div>
  </div>
</section>`;
}

function sectionHead(s, light = false) {
  return `<div class="section-head reveal${light ? ' section-head-light' : ''}">
    <p class="eyebrow${light ? ' eyebrow-light' : ''}">${icon('spark')}<span>${esc(s.eyebrow)}</span></p>
    <h2>${rich(s.title)}</h2>
    <p class="sub">${esc(s.subtitle)}</p>
  </div>`;
}

function products(t) {
  const visual = {
    pos: (it) =>
      devPos(shot('pos-1', it.alt, '(max-width: 720px) 80vw, 300px'), { printer: true, receiptTitle: t.hero.receiptTitle, size: 'sm' }),
    kds: (it) => devKds(shot('kds-1', it.alt, '(max-width: 720px) 80vw, 300px')),
    kiosk: () => devKiosk(kioskVideo(t, true)),
    dashboard: (it) => devTablet(shot('dash-1', it.alt, '(max-width: 720px) 80vw, 300px')),
  };
  const cards = t.products.items
    .map(
      (it, i) => `<article class="pcard pcard-${it.id} reveal" data-d="${i + 1}" id="product-${it.id}">
      <div class="pcard-visual">${visual[it.id](it)}</div>
      <div class="pcard-body">
        <span class="tag">${esc(it.tag)}</span>
        <h3>${esc(it.title)}</h3>
        <p>${esc(it.desc)}</p>
        <a class="more" href="#showcase" data-tab="${it.id}">${esc(t.products.more)}${icon('arrow')}</a>
      </div>
    </article>`,
    )
    .join('');
  return `<section class="section products" id="products">
  <div class="container">
    ${sectionHead(t.products)}
    <div class="pgrid">${cards}</div>
  </div>
</section>`;
}

function features(t) {
  const tiles = t.features.items
    .map(
      (f, i) => `<li class="ftile reveal" data-d="${(i % 4) + 1}">
      <span class="ficon">${icon(f.icon)}</span>
      <h3>${esc(f.title)}</h3>
      <p>${esc(f.desc)}</p>
    </li>`,
    )
    .join('');
  return `<section class="section features" id="features">
  <div class="container">
    ${sectionHead(t.features)}
    <ul class="fgrid">${tiles}</ul>
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
        <img src="/assets/brand/bizbot-wordmark-ar.png" width="456" height="224" alt="بِزبط" loading="lazy">
        <img src="/assets/brand/bizbot-wordmark-en.png" width="796" height="152" alt="BIZBOT" loading="lazy">
        <p>${esc(t.statement.brandLine)}</p>
      </div>
    </div>
    <p class="st-lines reveal" data-d="2">${lines}<span class="st-underline" aria-hidden="true"></span></p>
  </div>
</section>`;
}

function business(t) {
  const cards = t.business.items
    .map(
      (b, i) => `<li class="bcard reveal" data-d="${(i % 3) + 1}">
      <span class="bicon">${icon(b.icon)}</span>
      <h3>${esc(b.title)}</h3>
      <p>${esc(b.desc)}</p>
    </li>`,
    )
    .join('');
  return `<section class="section business" id="business">
  <div class="container">
    ${sectionHead(t.business)}
    <ul class="bgrid">${cards}</ul>
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
    const sizes = '(max-width: 900px) 92vw, 720px';
    if (tab.id === 'pos') return devPos(shot(first.src, `${tab.label} — ${first.caption}`, sizes, { attrs: ' data-stage-img' }), { printer: true, receiptTitle: t.hero.receiptTitle, size: 'lg' });
    if (tab.id === 'kds') return devKds(shot(first.src, `${tab.label} — ${first.caption}`, sizes, { attrs: ' data-stage-img' }));
    if (tab.id === 'dashboard') return devTablet(shot(first.src, `${tab.label} — ${first.caption}`, sizes, { attrs: ' data-stage-img' }));
    // kiosk: video first, images swap in
    return devKiosk(
      `${kioskVideo(t)}${shot('kiosk-3', `${tab.label} — ${tab.shots[1].caption}`, '(max-width: 900px) 60vw, 300px', { attrs: ' data-stage-img hidden' })}`,
    );
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
        <div class="stage stage-${tab.id}">${stageFor(tab)}</div>
        <div class="show-copy">
          <h3>${esc(tab.title)}</h3>
          <ul class="points">${points}</ul>
          <p class="caption" data-caption>${esc(tab.shots[0].caption)}</p>
          <div class="thumbs" role="group">${thumbs}</div>
        </div>
      </div>
    </div>`;
    })
    .join('');

  return `<section class="section showcase" id="showcase">
  <div class="container">
    ${sectionHead(t.showcase)}
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
    ${sectionHead(t.why, true)}
    <ul class="wgrid">${items}</ul>
  </div>
</section>`;
}

function pricing(t) {
  const inc = t.pricing.includes.map((x) => `<li>${icon('check')}<span>${esc(x)}</span></li>`).join('');
  return `<section class="section pricing" id="pricing">
  <div class="container">
    <div class="price-card reveal">
      <div class="price-copy">
        <p class="eyebrow">${icon('spark')}<span>${esc(t.pricing.eyebrow)}</span></p>
        <h2>${esc(t.pricing.title)}</h2>
        <p class="sub">${esc(t.pricing.subtitle)}</p>
        <a class="btn btn-primary btn-lg" href="#contact">${esc(t.pricing.cta)}${icon('arrow')}</a>
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
  return `<section class="section contact" id="contact">
  <div class="container contact-grid">
    <div class="contact-copy reveal">
      <p class="eyebrow eyebrow-light">${icon('spark')}<span>${esc(t.contact.eyebrow)}</span></p>
      <h2>${rich(t.contact.title)}</h2>
      <p class="sub">${esc(t.contact.subtitle)}</p>
      <ul class="contact-list">
        <li>${icon('mail')}<span><small>${esc(t.contact.emailLabel)}</small><a href="mailto:${esc(cfg.contact.sales)}" dir="ltr">${esc(cfg.contact.sales)}</a></span></li>
        <li>${icon('shield')}<span><small>${esc(t.contact.supportLabel)}</small><a href="mailto:${esc(cfg.contact.support)}" dir="ltr">${esc(cfg.contact.support)}</a></span></li>
        ${phoneRow}${waRow}
        <li>${icon('login')}<span><small>${esc(t.contact.appLabel)}</small><a href="${cfg.appUrl}" rel="noopener">${esc(t.contact.appLink)}</a></span></li>
      </ul>
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
    ['#features', t.nav.features],
    ['#business', t.nav.business],
    ['#pricing', t.nav.pricing],
    ['#contact', t.nav.contact],
  ]
    .map(([h, l]) => `<li><a href="${h}">${esc(l)}</a></li>`)
    .join('');
  const socials = Object.entries(cfg.social)
    .filter(([, url]) => url)
    .map(([k, url]) => `<a href="${esc(url)}" rel="noopener" aria-label="${esc(k)}">${esc(k)}</a>`)
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
  <link rel="preload" as="image" href="/assets/shots/pos-1-1200.webp" imagesrcset="/assets/shots/pos-1-800.webp 800w, /assets/shots/pos-1-1200.webp 1200w, /assets/shots/pos-1-1600.webp 1600w" imagesizes="(max-width: 720px) 92vw, 620px">
  <link rel="stylesheet" href="/assets/${assets.css}">
  ${jsonLd(t, cfg, locales)}
</head>
<body>
  <a class="skip" href="#main">${esc(t.skip)}</a>
  ${header(t, cfg, locales)}
  <main id="main">
    ${hero(t)}
    ${products(t)}
    ${features(t)}
    ${statement(t)}
    ${business(t)}
    ${showcase(t)}
    ${why(t)}
    ${pricing(t)}
    ${contact(t, cfg)}
  </main>
  ${footer(t, cfg, locales)}
  <script src="/assets/${assets.js}" defer></script>
</body>
</html>
`;
}
