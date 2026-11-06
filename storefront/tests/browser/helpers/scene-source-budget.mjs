import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { deriver } from '../../../../supabase/functions/storefront-media-publish/test/engine.mjs';

export async function measureDenseMenu(browser,origin,routeFixture,images) {
  const source=await readFile(new URL('../../../../e2e/cinematic/fixtures/background-quality/background-2816.jpg',import.meta.url));
  const engine=await deriver();
  const base=await engine.derive(source,{variant:'w960',source:'restaurant-logos',rung:0});
  const high=await engine.deriveBackground(source,{source:'restaurant-logos',rung:0});
  assert.equal(base.sha256,'211a00daf75bb8f868cec1c95aaa1e4c5e7d1d9aba8b46e6867d2753a8ff2ed3');
  assert.equal(high.sha256,'c0120cc575b08c4227d3c060ac78af28ee4ec7085ec4fd85f510778933fcd85f');
  const fixtures=new Map([...images,['d',Buffer.from(base.bytes)],['e',Buffer.from(high.bytes)]]);
  const ctx=await browser.newContext({viewport:{width:844,height:390},deviceScaleFactor:1,isMobile:true,
    hasTouch:true,javaScriptEnabled:false,locale:'ar',serviceWorkers:'block'});
  try {
    const rejected=[],requested=[];
    await ctx.route('**/*',routeFixture(fixtures,rejected,key=>{if(key==='d'||key==='e')requested.push(key)}));
    const page=await ctx.newPage(),responses=[];
    page.on('response',response=>{if(/\/[de]{64}\.webp$/.test(new URL(response.url()).pathname))responses.push(response)});
    const response=await page.goto(origin+'/ar/s/scene-ar-brand-custom-dense-a/menu',{waitUntil:'networkidle'});
    assert.equal(response.status(),200);
    const geometry=await page.evaluate(async ()=>{
      const lead=document.querySelector('main[data-sf-screen="home"] > div[aria-hidden="true"] > img');
      const copies=Array.from(document.querySelectorAll('[data-sf-scene-strip] > img'));
      await Promise.all([lead,...copies].map(image=>image.decode()));
      const sectionCount=document.querySelectorAll('[data-sf-module="sections"]').length;
      const requiredWidth=image=>{
        const box=image.getBoundingClientRect();
        return Math.max(box.width,box.height*image.naturalWidth/image.naturalHeight)*devicePixelRatio;
      };
      const main=lead.closest('main'),last=copies.at(-1);
      scrollTo(0,document.documentElement.scrollHeight);
      return {viewport:[innerWidth,innerHeight],dpr:devicePixelRatio,sectionCount,stripCount:copies.length,
        mainHeight:main.getBoundingClientRect().height,leadRequiredWidth:requiredWidth(lead),
        maxStripRequiredWidth:Math.max(0,...copies.map(requiredWidth)),natural:[lead.naturalWidth,lead.naturalHeight],
        sameNativeSelection:copies.every(copy=>copy.currentSrc===lead.currentSrc && copy.srcset===lead.srcset && copy.sizes===lead.sizes),
        footerCovered:!!last && last.parentElement.getBoundingClientRect().bottom>=main.getBoundingClientRect().bottom,
        footerScrollY:scrollY};
    });
    assert.deepEqual(rejected,[]);assert.deepEqual(requested,['d']);
    assert.equal(responses.length,1,'One actual responsive background response even on the maximum catalogue');
    const received=await responses[0].body();
    assert.equal(createHash('sha256').update(received).digest('hex'),base.sha256);
    return {...geometry,sourceWidth:base.width,sourceHeight:base.height,receivedBytes:received.length,
      receivedSha256:base.sha256,backgroundRequests:responses.length,htmlBytes:(await response.body()).length};
  } finally {await ctx.close();}
}
