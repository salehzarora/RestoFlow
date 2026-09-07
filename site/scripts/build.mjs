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

const readJson = (p) => JSON.parse(readFileSync(p, 'utf8'));
const hash = (buf) => createHash('sha256').update(buf).digest('hex').slice(0, 10);
const RULE_CONTAINERS = /^@(media|supports|container|layer|document|scope|keyframes|-webkit-keyframes)\b/i;

/**
 * Conservatively compact CSS without changing its token stream.
 *
 * This intentionally is not an optimiser: values are not rewritten, strings
 * and escapes are copied byte-for-byte, calc/operator spacing is retained,
 * descendant-selector whitespace stays intact, and custom-property values keep
 * their whitespace. Only comments and whitespace adjacent to unambiguous CSS
 * punctuation are removed.
 */
export function minifyCss(text) {
  const out = [];
  const stack = [{ type: 'rules', prelude: '', property: '', inValue: false, custom: false, customBlockDepth: 0, lastDeclarationCustom: false }];
  let pendingSpaces = 0;
  let pendingAfterHexEscape = false;
  let commentGap = false;
  let afterHexEscape = false;
  let parenDepth = 0;
  let squareDepth = 0;

  const frame = () => stack[stack.length - 1];
  const last = () => out[out.length - 1] || '';
  const emit = (value) => {
    out.push(value);
    const current = frame();
    if (current.type === 'rules') current.prelude += value;
    else if (!current.inValue) current.property += value;
  };
  const keepSpace = (next) => {
    const prev = last();
    const current = frame();
    if (current.type === 'declarations' && current.inValue && current.custom) return Boolean(prev);
    if (!prev || '{};'.includes(prev) || '{};'.includes(next) || next === '{' || prev === '}') return false;

    if (current.type === 'rules') {
      if (',>+~'.includes(prev) || ',>+~'.includes(next) || prev === '(' || next === ')') return false;
      return true; // A space between selector tokens may be a descendant combinator.
    }

    if (!current.inValue) return next !== ':';
    if (prev === ':' || prev === ',' || next === ',' || prev === '(' || next === ')' || next === '!') return false;
    return true; // In particular, preserve spaces around calc() + and - operators.
  };
  const isName = (char) => Boolean(char) && /[\w\u0080-\uFFFF-]/u.test(char);
  const needsCommentSeparator = (next) => {
    const prev = last();
    if (!prev || !next) return false;
    if (afterHexEscape && /[\da-f]/i.test(next)) return true;
    if ((isName(prev) || prev === '\\') && (isName(next) || next === '\\')) return true;
    if (/\d/.test(prev) && (next === '.' || next === '%')) return true;
    if (prev === '.' && /\d/.test(next)) return true;
    if ((prev === '#' || prev === '@') && (isName(next) || next === '\\')) return true;
    if ((prev === '+' || prev === '-') && (next === '.' || /\d/.test(next))) return true;
    if ('~|^$*'.includes(prev) && next === '=') return true;
    return (prev === '/' && next === '*') || (prev === '<' && next === '!') || (prev === '-' && next === '-');
  };

  for (let i = 0; i < text.length; i += 1) {
    const char = text[i];

    if (char === '/' && text[i + 1] === '*') {
      commentGap = true;
      i += 2;
      while (i < text.length && !(text[i] === '*' && text[i + 1] === '/')) i += 1;
      if (i < text.length) i += 1;
      continue;
    }

    if (/\s/.test(char)) {
      if (pendingSpaces === 0) pendingAfterHexEscape = afterHexEscape;
      pendingSpaces += 1;
      continue;
    }

    if (pendingSpaces > 0) {
      if (pendingAfterHexEscape) {
        emit(' '); // terminates the hexadecimal escape
        if (pendingSpaces > 1 && keepSpace(char)) emit(' '); // preserves a separate whitespace token
      } else if (keepSpace(char)) emit(' ');
      pendingSpaces = 0;
      pendingAfterHexEscape = false;
      commentGap = false;
    } else if (commentGap) {
      if (needsCommentSeparator(char)) emit(' ');
      commentGap = false;
    }
    afterHexEscape = false;

    if (char === '"' || char === "'") {
      emit(char);
      const quote = char;
      while (++i < text.length) {
        emit(text[i]);
        if (text[i] === '\\' && i + 1 < text.length) emit(text[++i]);
        else if (text[i] === quote) break;
      }
      continue;
    }

    if (char === '\\' && i + 1 < text.length) {
      emit(char);
      if (/[\da-f]/i.test(text[i + 1])) {
        let digits = 0;
        while (i + 1 < text.length && digits < 6 && /[\da-f]/i.test(text[i + 1])) {
          emit(text[++i]);
          digits += 1;
        }
        afterHexEscape = true;
      } else {
        emit(text[++i]);
      }
      continue;
    }

    if (text.slice(i, i + 4).toLowerCase() === 'url(' && !isName(text[i - 1])) {
      let depth = 0;
      let quote = '';
      for (; i < text.length; i += 1) {
        const part = text[i];
        emit(part);
        if (quote) {
          if (part === '\\' && i + 1 < text.length) emit(text[++i]);
          else if (part === quote) quote = '';
        } else if (part === '"' || part === "'") quote = part;
        else if (part === '\\' && i + 1 < text.length) emit(text[++i]);
        else if (part === '(') depth += 1;
        else if (part === ')' && --depth === 0) break;
      }
      continue;
    }

    const currentBeforeBlock = frame();
    if (char === '{' && currentBeforeBlock.type === 'declarations' && currentBeforeBlock.inValue && currentBeforeBlock.custom) {
      currentBeforeBlock.customBlockDepth += 1;
      emit(char);
      continue;
    }

    if (char === '{' && parenDepth === 0 && squareDepth === 0) {
      const parent = frame();
      const prelude = (parent.type === 'rules' ? parent.prelude : parent.property).trim();
      if (last() === ' ') out.pop();
      out.push('{');
      parent.prelude = '';
      parent.property = '';
      stack.push({
        type: RULE_CONTAINERS.test(prelude) ? 'rules' : 'declarations',
        prelude: '',
        property: '',
        inValue: false,
        custom: false,
        customBlockDepth: 0,
        lastDeclarationCustom: false,
      });
      parenDepth = 0;
      squareDepth = 0;
      continue;
    }

    const currentBeforeClose = frame();
    if (char === '}' && currentBeforeClose.type === 'declarations' && currentBeforeClose.inValue && currentBeforeClose.customBlockDepth > 0) {
      currentBeforeClose.customBlockDepth -= 1;
      emit(char);
      continue;
    }

    if (char === '}' && parenDepth === 0 && squareDepth === 0) {
      const closing = frame();
      if (last() === ';' && !closing.lastDeclarationCustom) out.pop();
      if (last() === ' ' && !(closing.inValue && closing.custom)) out.pop();
      out.push('}');
      if (stack.length > 1) stack.pop();
      frame().prelude = '';
      frame().property = '';
      frame().inValue = false;
      frame().custom = false;
      parenDepth = 0;
      squareDepth = 0;
      continue;
    }

    const current = frame();
    if (char === ':' && current.type === 'declarations' && !current.inValue && parenDepth === 0 && squareDepth === 0) {
      if (last() === ' ') out.pop();
      out.push(':');
      current.custom = current.property.trim().startsWith('--');
      current.inValue = true;
      continue;
    }

    if (char === ';' && current.type === 'declarations' && parenDepth === 0 && squareDepth === 0 && current.customBlockDepth === 0) {
      if (last() === ' ' && !current.custom) out.pop();
      out.push(';');
      current.lastDeclarationCustom = current.custom;
      current.property = '';
      current.inValue = false;
      current.custom = false;
      continue;
    }

    if (char === '(') parenDepth += 1;
    else if (char === ')' && parenDepth > 0) parenDepth -= 1;
    else if (char === '[') squareDepth += 1;
    else if (char === ']' && squareDepth > 0) squareDepth -= 1;
    emit(char);
  }

  return out.join('').trim() + '\n';
}

export function build({ quiet = false } = {}) {
  // Resolved per call (not at import time) so a test file can point its own build
  // at a private directory before calling build() — two test files never race on dist/.
  const DIST = process.env.SITE_DIST ? resolve(process.env.SITE_DIST) : join(ROOT, 'dist');
  const cfg = readJson(join(SRC, 'site.config.json'));
  const locales = ['ar', 'en', 'he'].map((c) => readJson(join(SRC, 'locales', `${c}.json`)));

  rmSync(DIST, { recursive: true, force: true });
  mkdirSync(join(DIST, 'assets'), { recursive: true });

  // Static files first (assets, favicon), then hashed bundles.
  if (existsSync(PUBLIC)) cpSync(PUBLIC, DIST, { recursive: true });
  // Shipped CSS is conservatively compacted. Values and selectors keep their
  // token meaning; structural tests use whitespace-tolerant assertions.
  const css = Buffer.from(minifyCss(readFileSync(join(SRC, 'styles.css'), 'utf8')));
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
