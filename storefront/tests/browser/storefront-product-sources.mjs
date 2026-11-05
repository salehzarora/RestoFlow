// Browser evidence for the shipped carousel/CSS. Controlled dimension images
// prove resource selection, not photographic quality or a publication journey.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { isAbsolute, join } from 'node:path';
import { createServer } from 'node:http';
import { registerHooks } from 'node:module';
import { chromium } from '@playwright/test';
import ts from 'typescript';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

await import('../support/ts-resolver.mjs');

// Load actual TSX/CSS-module imports for server rendering in this test process.
// No application loader, build rule or runtime source is modified.
registerHooks({ load(url, context, next) {
  if (url.endsWith('.module.css')) {
    const css = readFileSync(new URL(url), 'utf8');
    const names = [...css.matchAll(/\.([a-zA-Z_][\w-]*)/g)].map(match => match[1]);
    return { format: 'module', shortCircuit: true, source: `export default ${JSON.stringify(Object.fromEntries(names.map(name => [name, name])))}` };
  }
  if (url.endsWith('.tsx')) return { format: 'module', shortCircuit: true, source: ts.transpileModule(readFileSync(new URL(url), 'utf8'), {
    compilerOptions: { jsx: ts.JsxEmit.ReactJSX, target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext }, fileName: new URL(url).pathname,
  }).outputText };
  return next(url, context);
} });
const { ProductCarousel } = await import('../../src/ui/storefront/home/ProductCarousel.tsx');
const { storefrontMessages } = await import('../../src/i18n/storefront.ts');
const homeCss = readFileSync(new URL('../../src/ui/storefront/home/home.module.css', import.meta.url), 'utf8');
const carouselCss = readFileSync(new URL('../../src/ui/storefront/home/carousel.module.css', import.meta.url), 'utf8');
const evidenceDir = process.env.SF_PRODUCT_EVIDENCE_DIR;
if (evidenceDir && !isAbsolute(evidenceDir)) throw new Error('Evidence directory must be absolute');
const evidence = evidenceDir ? JSON.parse(readFileSync(join(evidenceDir, 'manifest.json'), 'utf8')).records : [];
for (const row of evidence) if (!/^burger-(original|candidate)-w(480|960)\.webp$/.test(row.filename)) throw new Error('Unexpected evidence filename');
const server = createServer((req, res) => {
  const realImage = evidence.find(row => `/${row.filename}` === req.url);
  if (realImage) {
    res.writeHead(200, { 'content-type': 'image/webp', 'cache-control': 'no-store' });
    res.end(readFileSync(join(evidenceDir, realImage.filename))); return;
  }
  const match = /^\/(?:active|side)\/(\d+)x(\d+)\.svg$/.exec(req.url);
  if (!match) { res.writeHead(404).end(); return; }
  res.writeHead(200, { 'content-type': 'image/svg+xml', 'cache-control': 'no-store' });
  res.end(`<svg xmlns="http://www.w3.org/2000/svg" width="${match[1]}" height="${match[2]}"><rect width="100%" height="100%" fill="#f2ad79"/></svg>`);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({ executablePath: process.env.SF_BROWSER_EXECUTABLE || undefined, headless: true });
const rows = [];
const photoRows = [];
try {
  for (const viewport of [360, 390, 650, 651, 1440]) for (const dpr of [1, 2, 3]) for (const [shape, dimensions] of [
    ['portrait', [[320, 480], [640, 960]]], ['square', [[480, 480], [960, 960]]],
    ['landscape', [[480, 320], [960, 640]]], ['wide', [[480, 160], [960, 320]]],
  ]) {
    const context = await browser.newContext({ viewport: { width: viewport, height: 844 }, deviceScaleFactor: dpr, reducedMotion: 'reduce' });
    const page = await context.newPage();
    const sources = id => dimensions.map(([width, height]) => ({ url: `${origin}/${id}/${width}x${height}.svg`, width, height }));
    const items = ['active', 'side'].map(id => ({ id, name: id, image: sources(id)[0].url, imageVariants: sources(id), priceMinor: 1000, soldOut: false }));
    const html = renderToStaticMarkup(React.createElement(ProductCarousel, { items, m: storefrontMessages('en'), locale: 'en', label: 'Controlled source sizes' }));
    await page.setContent(`<style>body{margin:0}*{box-sizing:border-box}${homeCss}\n${carouselCss}</style><main class="page"><section class="inner menu"><div class="menuSections">${html}</div></section></main>`);
    await page.locator('.slide img').evaluateAll(images => Promise.all(images.map(img => img.decode())));
    for (const id of ['active', 'side']) {
      const variants = sources(id);
      const observation = await page.locator(`[data-sf-carousel-product="${id}"] img`).evaluate(img => {
        const rect = img.getBoundingClientRect(), css = getComputedStyle(img);
        const parent = getComputedStyle(img.parentElement);
        return { current: img.currentSrc, width: rect.width, height: rect.height, fit: css.objectFit, filter: css.filter, parentFilter: parent.filter };
      });
      const ratio = dimensions[0][0] / dimensions[0][1];
      const paintedWidth = Math.min(observation.width, observation.height * ratio);
      const required = paintedWidth * dpr;
      const chosen = variants.find(variant => observation.current === variant.url);
      assert.ok(chosen, 'The browser chose a declared variant');
      assert.equal(observation.fit, 'contain');
      assert.doesNotMatch(observation.filter + observation.parentFilter, /blur\(/);
      const expected = variants.find(variant => variant.width >= required - .1) ?? variants.at(-1);
      assert.equal(chosen.width, expected.width, `${viewport}px DPR${dpr} ${shape} ${id}: painted ${paintedWidth}px`);
      rows.push({ viewport, dpr, shape, slide: id, paintedWidth: Math.round(paintedWidth * 100) / 100, chosenWidth: chosen.width, capped: required > variants.at(-1).width });
    }
    await context.close();
  }
  for (const kind of [...new Set(evidence.map(row => row.kind))]) for (const viewport of [390, 1440]) for (const dpr of [1, 2, 3]) {
    const sources = evidence.filter(row => row.kind === kind).map(row => ({ url: `${origin}/${row.filename}`, width: row.width, height: row.height }));
    const context = await browser.newContext({ viewport: { width: viewport, height: 844 }, deviceScaleFactor: dpr, reducedMotion: 'reduce' });
    const page = await context.newPage();
    const item = { id: 'burger', name: 'Same source burger', image: sources[0].url, priceMinor: 1000, soldOut: false };
    const render = responsive => renderToStaticMarkup(React.createElement(ProductCarousel, {
      items: [{ ...item, ...(responsive ? { imageVariants: sources } : {}) }], m: storefrontMessages('en'), locale: 'en', label: 'Product quality comparison',
    }));
    await page.setContent(`<style>body{margin:0;background:#151515;color:#f7f2ea;font:16px sans-serif}*{box-sizing:border-box}${homeCss}\n${carouselCss}</style><main class="page">
      <p>LOCAL REAL SOURCE — ${kind === 'candidate' ? 'PROVISIONAL CUTOUT; plate loss remains' : 'ORIGINAL BASELINE'} — ${viewport}px DPR${dpr}</p>
      <section class="inner menu" data-comparison="before"><h2>Before: existing w480 source</h2>${render(false)}</section>
      <section class="inner menu" data-comparison="after"><h2>After: responsive c4 copies from the same source</h2>${render(true)}</section></main>`);
    await page.locator('.slide img').evaluateAll(images => Promise.all(images.map(img => img.decode())));
    const after = await page.locator('[data-comparison="after"] .slide img').evaluate(img => {
      const rect = img.getBoundingClientRect();
      return { src: img.currentSrc, width: Math.min(rect.width, rect.height), fit: getComputedStyle(img).objectFit };
    });
    const chosen = sources.find(source => source.url === after.src);
    const expected = sources.find(source => source.width >= after.width * dpr - .1) ?? sources.at(-1);
    assert.equal(chosen.width, expected.width);
    assert.equal(after.fit, 'contain');
    const filename = `burger-${kind}-${viewport}-dpr${dpr}.png`;
    await page.screenshot({ path: join(evidenceDir, filename), fullPage: true });
    photoRows.push({ kind, viewport, dpr, paintedWidth: after.width, chosenWidth: chosen.width, capped: after.width * dpr > sources.at(-1).width, screenshot: filename });
    await context.close();
  }
  console.log(JSON.stringify({ status: 'PASS', checks: rows.length, kind: 'controlled source-selection browser test', rows, photoRows }, null, 2));
} finally { await browser.close(); await new Promise(resolve => server.close(resolve)); }
