// Render the shipped MenuBackdrop and stylesheet; an isolated local HTTP server
// supplies genuine photos. This exercises browser selection, not service publication.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { resolve, isAbsolute } from 'node:path';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { chromium, webkit } from '@playwright/test';
import { testStripBands } from './helpers/scene-strip-bands.mjs';
import { webpInfo } from '../../../supabase/functions/storefront-media-publish/lib/sniff.mjs';
await import('./helpers/ssr-components.mjs');
const { menuBackground } = await import('../../src/ui/storefront/home/menuBackground.ts');
const { MenuBackdrop } = await import('../../src/ui/storefront/home/MenuBackdrop.tsx');
const css = readFileSync(new URL('../../src/ui/storefront/home/home.module.css', import.meta.url), 'utf8');
const evidence = process.env.SF_BACKGROUND_EVIDENCE_DIR;
if (evidence && !isAbsolute(evidence)) throw new Error('Evidence directory must be absolute');
const files = new Map();
function photo(source, name) {
  const bytes = readFileSync(source);
  const { width, height } = webpInfo(bytes);
  files.set('/' + name, bytes);
  return { path: '/' + name, width, height };
}
const pairs = new Map();
if (evidence) {
  for (const orientation of ['landscape', 'portrait']) {
    pairs.set(orientation, [960, 2560].map(edge => {
      const name = `${orientation}-${edge}.webp`;
      return photo(resolve(evidence, name), name);
    }));
  }
} else {
  pairs.set('landscape', [480, 960].map(edge => {
    const name = `original-c4-w${edge}.webp`;
    return photo(new URL(`../../../docs/visual-references/PR380-quality-review/highres/${name}`, import.meta.url), name);
  }));
}
const photoRequests = new Map();
let markup = '';
const server = createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/') {
    return res.writeHead(200, { 'content-type':'text/html', 'cache-control':'no-store' }).end(markup);
  }
  const bytes = req.method === 'GET' && files.get(req.url);
  if (!bytes) return res.writeHead(404).end();
  photoRequests.set(req.url, (photoRequests.get(req.url) ?? 0) + 1);
  res.writeHead(200, { 'content-type':'image/webp', 'cache-control':'public, max-age=31536000, immutable',
    'content-length':bytes.length }).end(bytes);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const engine = process.argv.includes('--webkit') ? webkit : chromium;
const rows = [];
let browser;
try {
  browser = await engine.launch();
  for (const [shape, pair] of pairs) for (const [width, height] of [[390,844],[1440,900]]) {
    const variants = pair.map(p => ({ width:p.width, height:p.height, url:origin + p.path }));
    for (const dpr of [1,2,3]) for (const responsive of [false,true]) {
      const context = await browser.newContext({ viewport:{width,height}, deviceScaleFactor:dpr, isMobile:width===390, hasTouch:width===390 });
      try {
        const tenant = { heroImage:null, menuBackgroundImage:variants[0].url,
          ...(responsive ? { menuBackgroundVariants:variants } : {}) };
        const rendered = renderToStaticMarkup(React.createElement(MenuBackdrop,{
          background:menuBackground(tenant),sectionCount:5,itemCount:15
        }));
        assert.equal(rendered.includes('srcSet='), responsive);
        markup = '<!DOCTYPE html><meta name="viewport" content="width=device-width,initial-scale=1">' +
          '<style>html,body{margin:0}*{box-sizing:border-box}' + css + '</style>' +
          '<main class="page" data-sf-screen="home" style="height:400svh">' + rendered + '</main>';
        const page = await context.newPage();
        const seen = [];
        page.on('response', response => { if (new URL(response.url()).pathname.endsWith('.webp')) seen.push(response); });
        await page.goto(origin);
        const frame = await page.locator('[data-sf-menu-primary]').evaluate(async img => {
          await img.decode();
          const copies=[...document.querySelectorAll('[data-sf-scene-strip] > img')];
          await Promise.all(copies.map(copy=>copy.decode()));
          const bounds = [];
          for (const fraction of [0,.5,1]) {
            scrollTo(0, fraction * (document.documentElement.scrollHeight - innerHeight));
            await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
            const rect = img.getBoundingClientRect();
            bounds.push([scrollY, rect.x, rect.y, rect.width, rect.height]);
          }
          return { src:img.src, currentSrc:img.currentSrc, sizes:img.sizes, srcSet:img.srcset, strips:copies.length,
            stripsShareSource:copies.every(copy=>copy.currentSrc===img.currentSrc && copy.sizes===img.sizes && copy.srcset===img.srcset),
            stripBoxes:copies.map(copy=>{
              const box=copy.getBoundingClientRect();return [box.width,box.height];
            }),
            fit:getComputedStyle(img).objectFit, filter:getComputedStyle(img).filter, dpr:devicePixelRatio,
            overflow:document.documentElement.scrollWidth>innerWidth, bounds };
        });
        const paint = Math.max(width,height * variants[1].width / variants[1].height);
        const expected = responsive && paint*dpr > variants[0].width ? variants[1] : variants[0];
        assert.equal(frame.src, variants[0].url);
        assert.equal(frame.currentSrc, expected.url);
        assert.equal(frame.strips,16);assert.equal(frame.stripsShareSource,true);
        assert.equal(frame.fit, 'cover'); assert.equal(frame.filter, 'none'); assert.equal(frame.overflow,false);
        assert.equal(seen.length,1); assert.equal(seen[0].url(),frame.currentSrc);
        const received = await seen[0].body();
        const decoded = webpInfo(received);
        assert.deepEqual([decoded.width, decoded.height], [expected.width, expected.height]);
        assert.deepEqual(received, files.get(new URL(expected.url).pathname));
        const stripRequiredWidth=Math.max(...frame.stripBoxes.map(([w,h])=>Math.max(w,h*decoded.width/decoded.height)*dpr));
        if(responsive)assert.ok(decoded.width>=Math.min(stripRequiredWidth,variants[1].width),
          'Native source covers the physical strip demand up to the largest available candidate');
        for (const [scroll,x,y,w,h] of frame.bounds) {
          assert.equal(x,0); assert.ok(Math.abs(y+scroll)<1, 'Artwork stays at the document top'); assert.equal(w,width); assert.ok(Math.abs(h-height)<.25);
        }
        assert.ok(frame.bounds[2][0] > frame.bounds[1][0] && frame.bounds[1][0] > 0);
        const timing = await page.evaluate(url => performance.getEntriesByName(url).at(-1)?.toJSON(), frame.currentSrc);
        assert.equal(timing.encodedBodySize, received.length);
        const sceneChecks = [];
        if (responsive && dpr === 2) {
          for (const preset of ['brand','reference_dark']) for (const dim of [0,15,80]) {
            const check = await page.locator('.menuBackdrop').evaluate(async (layer, {preset,dim}) => {
              document.documentElement.dataset.sfScene = preset;
              layer.style.setProperty('--bg','#00ff00');
              layer.style.setProperty('--menu-image-dim',String(dim / 100));
              const photo = layer.querySelector('[data-sf-menu-primary]');
              const positions = [];
              for (const fraction of [0,.5,1]) {
                scrollTo(0, fraction * (document.documentElement.scrollHeight - innerHeight));
                await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
                positions.push({ scrollY, y:photo.getBoundingClientRect().y, currentSrc:photo.currentSrc });
              }
              const overlay = getComputedStyle(layer,'::after');
              return { preset,dim,color:overlay.backgroundColor,alpha:overlay.opacity,positions };
            }, {preset,dim});
            assert.equal(check.color, preset === 'brand' ? 'rgb(0, 255, 0)' : 'rgb(0, 0, 0)');
            assert.equal(check.alpha,String(dim/100));
            assert.ok(check.positions.every(p => Math.abs(p.y+p.scrollY)<1 && p.currentSrc === expected.url));
            assert.ok(check.positions.at(-1).y + frame.bounds[0][4] <= 0, 'Lead photograph leaves the footer viewport');
            sceneChecks.push(check);
          }
          assert.equal(seen.length,1);
        }
        const warm = {};
        if (responsive && dpr === 2) {
          // Same ordinary immutable response, new document in the existing browser context.
          const imagePath = new URL(frame.currentSrc).pathname;
          const requestsBefore = photoRequests.get(imagePath);
          const repeat = await context.newPage();
          await repeat.goto(origin);
          warm.currentSrc = await repeat.locator('[data-sf-menu-primary]').evaluate(async img => { await img.decode(); return img.currentSrc; });
          assert.equal(warm.currentSrc, frame.currentSrc);
          warm.serverImageRequests = photoRequests.get(imagePath) - requestsBefore;
          warm.resourceTiming = await repeat.evaluate(url => performance.getEntriesByName(url).at(-1)?.toJSON(), warm.currentSrc);
          await repeat.close();
        }
        rows.push({ engine:engine.name(), version:browser.version(), shape,viewport:[width,height],dpr,
          responsive, ...frame, stripRequiredWidth, physicalSource:[decoded.width,decoded.height], responseBodyBytes:received.length, transferBytes:timing.transferSize, sceneChecks, warm,
          sha256:createHash('sha256').update(received).digest('hex'), coverPaintedWidth:paint });
      } finally { await context.close(); }
    }
  }
  if (evidence) writeFileSync(resolve(evidence,`renderer-${engine.name()}.json`),JSON.stringify(rows,null,2));
  // This is the measured height of the real three-category, eight-strip menu.
  // Exercise the component's omitted-count default at that size separately.
  const shortPair=pairs.get('portrait')??pairs.get('landscape');
  const variants=shortPair.map(p=>({url:origin+p.path,width:p.width,height:p.height}));
  const shortMarkup=renderToStaticMarkup(React.createElement(MenuBackdrop,{background:menuBackground({
    menuBackgroundImage:variants[0].url,menuBackgroundVariants:variants,
  })}));
  markup='<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0}'+css+'</style><main class="page" data-sf-screen="home" style="height:2487.671875px">'+shortMarkup+'</main>';
  const short=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:1,isMobile:true,hasTouch:true});
  try {
    const responses=[];short.on('response',r=>{if(new URL(r.url()).pathname.endsWith('.webp'))responses.push(r)});
    await short.goto(origin);
    const measured=await short.locator('[data-sf-menu-primary]').evaluate(async lead=>{
      const copies=[...document.querySelectorAll('[data-sf-scene-strip] > img')];
      await Promise.all([lead,...copies].map(img=>img.decode()));scrollTo(0,document.documentElement.scrollHeight);
      return {count:copies.length,current:lead.currentSrc,same:copies.every(img=>img.currentSrc===lead.currentSrc),
        boxes:copies.map(img=>{const r=img.getBoundingClientRect();return [r.width,r.height]}),scrollY};
    });
    assert.equal(measured.count,8);assert.ok(measured.same&&measured.scrollY>0);assert.equal(responses.length,1);
    const leadWidth=Math.max(390,844*variants[1].width/variants[1].height);
    const expected=leadWidth<=variants[0].width?variants[0]:variants[1];
    assert.equal(measured.current,expected.url);assert.equal(responses[0].url(),expected.url);
    const bytes=await responses[0].body();assert.deepEqual(bytes,files.get(new URL(expected.url).pathname));
    const decoded=webpInfo(bytes),required=Math.max(...measured.boxes.map(([w,h])=>Math.max(w,h*decoded.width/decoded.height)));
    assert.ok(required<=decoded.width,'Short eight-strip menu fits the selected source');
    if(evidence)writeFileSync(resolve(evidence,`default-short-${engine.name()}.json`),JSON.stringify({
      stripCount:measured.count,viewport:[390,844],menuHeight:2487.671875,physicalWidth:required,
      selectedWidth:decoded.width,receivedBytes:bytes.length,backgroundRequests:responses.length
    },null,2));
  } finally {await short.close();}
  const bands=await testStripBands(browser,origin,src=>{
    const rendered=renderToStaticMarkup(React.createElement(MenuBackdrop,{
      background:menuBackground({menuBackgroundImage:src}),sectionCount:12,itemCount:24
    }));
    markup='<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;--menu-image-dim:0}*{box-sizing:border-box}'+css+'</style><main class="page" data-sf-screen="home" style="height:20001px">'+rendered+'</main>';
  });
  if(evidence)writeFileSync(resolve(evidence,`strip-bands-${engine.name()}.json`),JSON.stringify(bands,null,2));
  console.log('PASS wide/tall marked sources on a 20,001px menu, reflected joins and bounded rows at three depths');
  console.log(`PASS ${rows.length} ${engine.name()} SSR/currentSrc/received bytes/scroll cases`);
} finally {
  await browser?.close();
  await new Promise(resolve => server.close(resolve));
}
