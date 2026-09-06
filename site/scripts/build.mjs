#!/usr/bin/env node
// Static build for the BIZBOT marketing site.
//   node scripts/build.mjs            → writes ./dist
// Zero dependencies: reads src/locales/*.json + src/site.config.json, renders
// one HTML document per locale, copies public/ and the hashed CSS/JS bundle,
// and emits sitemap.xml / robots.txt / site.webmanifest.

import { createHash } from 'node:crypto';
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { renderPage } from '../src/render.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(here, '..');
const SRC = join(ROOT, 'src');
const PUBLIC = join(ROOT, 'public');
const DIST = process.env.SITE_DIST ? resolve(process.env.SITE_DIST) : join(ROOT, 'dist');

const readJson = (p) => JSON.parse(readFileSync(p, 'utf8'));
const hash = (buf) => createHash('sha256').update(buf).digest('hex').slice(0, 10);

export function build({ quiet = false } = {}) {
  const cfg = readJson(join(SRC, 'site.config.json'));
  const locales = ['ar', 'en', 'he'].map((c) => readJson(join(SRC, 'locales', `${c}.json`)));

  rmSync(DIST, { recursive: true, force: true });
  mkdirSync(join(DIST, 'assets'), { recursive: true });

  // Static files first (assets, favicon), then hashed bundles.
  if (existsSync(PUBLIC)) cpSync(PUBLIC, DIST, { recursive: true });
  const css = readFileSync(join(SRC, 'styles.css'));
  const js = readFileSync(join(SRC, 'main.js'));
  const assets = { css: `site.${hash(css)}.css`, js: `site.${hash(js)}.js` };
  writeFileSync(join(DIST, 'assets', assets.css), css);
  writeFileSync(join(DIST, 'assets', assets.js), js);
  cpSync(join(PUBLIC, 'assets', 'icons', 'favicon.ico'), join(DIST, 'favicon.ico'));

  const pages = [];
  for (const t of locales) {
    const html = renderPage(t, { cfg, locales, assets });
    const out = t.path === '/' ? join(DIST, 'index.html') : join(DIST, t.path.replace(/^\//, ''), 'index.html');
    mkdirSync(dirname(out), { recursive: true });
    writeFileSync(out, html);
    pages.push({ locale: t, out, bytes: Buffer.byteLength(html) });
  }

  // sitemap + robots + manifest
  const today = new Date().toISOString().slice(0, 10);
  const urlFor = (t) => cfg.siteUrl + (t.path === '/' ? '/' : t.path);
  const alt = locales
    .map((l) => `    <xhtml:link rel="alternate" hreflang="${l.htmlLang}" href="${urlFor(l)}"/>`)
    .join('\n');
  const sitemap = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
${locales
  .map(
    (l) => `  <url>
    <loc>${urlFor(l)}</loc>
    <lastmod>${today}</lastmod>
${alt}
    <xhtml:link rel="alternate" hreflang="x-default" href="${cfg.siteUrl}/"/>
  </url>`,
  )
  .join('\n')}
</urlset>
`;
  writeFileSync(join(DIST, 'sitemap.xml'), sitemap);
  writeFileSync(join(DIST, 'robots.txt'), `User-agent: *\nAllow: /\nDisallow: /api/\n\nSitemap: ${cfg.siteUrl}/sitemap.xml\n`);
  writeFileSync(
    join(DIST, 'site.webmanifest'),
    JSON.stringify(
      {
        name: 'BIZBOT | بِزبط',
        short_name: 'BIZBOT',
        start_url: '/',
        display: 'browser',
        background_color: '#F4F6F5',
        theme_color: '#1F2937',
        icons: [
          { src: '/assets/icons/icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: '/assets/icons/icon-512.png', sizes: '512x512', type: 'image/png' },
          { src: '/assets/icons/icon-maskable-192.png', sizes: '192x192', type: 'image/png', purpose: 'maskable' },
          { src: '/assets/icons/icon-maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      null,
      2,
    ),
  );

  if (!quiet) {
    for (const p of pages) console.log(`  ${p.locale.code}  ${p.out.replace(ROOT + '/', '')}  ${(p.bytes / 1024).toFixed(1)} KiB`);
    console.log(`  assets: ${assets.css}, ${assets.js}`);
    console.log(`built → ${DIST} (${readdirSync(DIST).length} top-level entries)`);
  }
  return { dist: DIST, pages, assets };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  build();
}
