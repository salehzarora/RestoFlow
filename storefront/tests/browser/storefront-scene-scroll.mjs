// Reads the built Storefront through its real SSR and hydrated menu. Only synthetic menu RPCs
// and approved public/fixture photo bytes are supplied by the test. No backend service is used.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { createServer } from 'node:net';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { chromium, webkit } from '@playwright/test';
import { scenePhotoPixels } from './helpers/scene-photo-pixels.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const engine = process.argv.includes('--webkit') ? webkit : chromium;
const out = process.env.SF_SCENE_SCROLL_EVIDENCE;
if (out) { assert.ok(isAbsolute(out)); mkdirSync(out, {recursive:true}); }
const lamp = process.env.SF_SCENE_SCROLL_LAMP;
const background = readFileSync(lamp || join(root, 'public/cinematic-preview/menu-background.webp'));
if (lamp) {
  assert.ok(isAbsolute(lamp));
  assert.equal(background.length, 12520);
  assert.equal(createHash('sha256').update(background).digest('hex'), '00cce46ea0a702e0f72a3d63438e2afc1c1571f8f670a1adfe33637b48ab2cd2');
}
const images = new Map([
  ['a', readFileSync(join(root, 'public/cinematic-preview/originals/8a7b43d0-5011-4376-bd5a-8cb518db81e1.webp'))],
  ['b', background],
  ['c', readFileSync(join(root, 'public/cinematic-preview/cover.webp'))],
]);
const reserve = createServer();
await new Promise(ok => reserve.listen(0, '127.0.0.1', ok));
const port = reserve.address().port;
await new Promise(ok => reserve.close(ok));
const origin = 'http://127.0.0.1:' + port;
const child = spawn(process.execPath, [join(root,'node_modules/next/dist/bin/next'), 'start','-H','127.0.0.1','-p',String(port)], {
  cwd:root, stdio:['ignore','pipe','pipe'], env:{...process.env, NEXT_TELEMETRY_DISABLED:'1', STOREFRONT_SOURCE:'live',
    STOREFRONT_SUPABASE_URL:'https://oqmevrndtivqxgyvcmwy.supabase.co', STOREFRONT_SUPABASE_ANON_KEY:'sb_publishable_SYNTHETIC_scene_scroll_only',
    NODE_OPTIONS:'--import='+pathToFileURL(join(root,'tests/browser/helpers/scene-scroll-fixture.mjs')).href},
});
let startup=''; for(const stream of [child.stdout,child.stderr])stream.on('data',chunk=>{ startup=(startup+chunk).slice(-8192); });
const rows=[], failures=[];
const check=(ok, name, row)=>{if(!ok) failures.push({case:row.name,check:name});};
const near=(a,b,epsilon=1)=>Math.abs(a-b)<=epsilon;
const settle=page=>page.evaluate(()=>new Promise(ok=>requestAnimationFrame(()=>requestAnimationFrame(ok))));
let browser;
try {
  let ready=false;
  for(let i=0;i<100;i++){
    if(child.exitCode!==null)throw Error('Local Next server stopped: '+startup);
    try{if((await fetch(origin+'/healthz.json')).ok){ready=true;break;}}catch{}
    await new Promise(ok=>setTimeout(ok,100));
  }
  assert.ok(ready,'Built Storefront is ready');
  browser=await engine.launch({headless:true});
  for(const spec of [
    {locale:'ar',scene:'brand',source:'custom',width:390,height:844},
    {locale:'he',scene:'reference',source:'inherited',width:390,height:844},
    {locale:'en',scene:'reference',source:'shared',width:1440,height:900},
    {locale:'en',scene:'brand',source:'custom',width:320,height:740},
  ]){
    const {locale,scene,source,width,height}=spec;
    const name=[engine.name(),locale,scene,source,width].join('-'),row={name,...spec,frames:[],viewportTransitions:[],flags:{}};
    rows.push(row);
    const contextOptions={viewport:{width,height},isMobile:width<=390,hasTouch:width<=390,
      deviceScaleFactor:1,locale,reducedMotion:'reduce',serviceWorkers:'block'};
    const ctx=await browser.newContext(contextOptions);
    try {
      const violations=[], errors=[]; let photoRequests=0;
      const fixtureRoute=route=>{
        const req=route.request(), url=new URL(req.url());
        if(req.method()==='GET' && url.origin===origin)return route.continue();
        const match=/^\/storage\/v1\/object\/public\/storefront-media\/0{32}\/([abc])\1{63}\.webp$/.exec(url.pathname);
        if(req.method()==='GET'&&url.origin==='https://oqmevrndtivqxgyvcmwy.supabase.co' && match){
          if(match[1]==='b')photoRequests++;
          return route.fulfill({contentType:'image/webp',body:images.get(match[1])});
        }
        violations.push('unexpected-network-request');return route.abort();
      };
      await ctx.route('**/*',fixtureRoute);
      const page=await ctx.newPage();page.on('pageerror',e=>errors.push(e.name));
      const slug=suffix=>'scene-'+[locale,scene,source,suffix].join('-');
      const go=async(suffix,screen='menu')=>{
        const path='/'+locale+'/s/'+slug(suffix)+(screen==='menu'?'/menu':'');
        const response=await page.goto(origin+path,{waitUntil:'networkidle'});
        assert.equal(response.status(),200);
      };
      await go('panel-a');
      const main=page.locator('main[data-sf-screen="home"]');
      const layer=main.locator(':scope > div[aria-hidden="true"]').first();
      const photo=layer.locator(':scope > img');await photo.waitFor();
      const snapshot=async()=>{
        await settle(page);
        return photo.evaluate(async img=>{
          await img.decode();
          const layer=img.parentElement,home=layer.closest('main'),r=img.getBoundingClientRect(),m=home.getBoundingClientRect(),u=layer.getBoundingClientRect();
          const visual=window.visualViewport,css=getComputedStyle(img),under=getComputedStyle(layer);
          const vw=document.documentElement.clientWidth, vh=visual?.height??innerHeight;
          const corner=document.elementFromPoint(Math.max(1,vw-2),Math.max(1,Math.min(vh,innerHeight)-2));
          const scale=Math.max(r.width/img.naturalWidth,r.height/img.naturalHeight);
          const strips=[...layer.querySelectorAll('[data-sf-scene-strip]')];
          const bounds=strips.map(strip=>strip.getBoundingClientRect());
          const stripGeometry={ count:strips.length,first:bounds[0]?.top??null,last:bounds.at(-1)?.bottom??null,
            maxGap:Math.max(0,...bounds.slice(1).map((b,i)=>b.top-bounds[i].bottom)),
            sameSource:strips.every(strip=>strip.firstElementChild.currentSrc===img.currentSrc),
            proportionate:strips.every((strip,i)=>{
              const copy=strip.firstElementChild,box=copy.getBoundingClientRect(),style=getComputedStyle(copy);
              return style.objectFit==='cover' && style.objectPosition==='50% 100%' &&
                Math.abs(box.width-bounds[i].width)<1 && Math.abs(box.height-(2*bounds[i].height+128))<1;
            })};
          const sourceTop=css.objectPosition==='50% 0%'?0:(r.height-img.naturalHeight*scale)/2;
          return {scrollY,x:r.x,y:r.y,width:r.width,height:r.height,documentY:r.y+scrollY,
            viewportWidth:vw,viewportHeight:vh,natural:[img.naturalWidth,img.naturalHeight],scale,
            // Center of the small upper lamp bulb in the verified 419x744 public photo.
            landmark:img.naturalWidth===419 && img.naturalHeight===744?{x:r.x+(r.width-img.naturalWidth*scale)/2+67*scale,y:r.y+sourceTop+82*scale}:null,
            position:css.position,fit:css.objectFit,objectPosition:css.objectPosition,mask:css.maskImage||css.webkitMaskImage,
            currentPath:new URL(img.currentSrc).pathname, mainHeight:m.height, mainTop:m.y,mainBottom:m.bottom,
            underlayTop:u.y,underlayBottom:u.bottom,underlayImage:under.backgroundImage,underlayColor:under.backgroundColor,
            cornerInsideHome:home.contains(corner),horizontalOverflow:document.documentElement.scrollWidth>innerWidth,
            stripGeometry,dim:Number(getComputedStyle(layer,'::after').opacity)};
        });
      };
      const scroll=async fraction=>{
        await page.evaluate(f=>scrollTo({top:f*(document.documentElement.scrollHeight-innerHeight),behavior:'instant'}),fraction);
        return snapshot();
      };
      const coverage=(frame,label)=>{
        check(!frame.horizontalOverflow,label+' horizontal bounds',row);
        check(frame.mainTop<=1 && frame.mainBottom>=frame.viewportHeight-1,label+' full home coverage',row);
        check(frame.underlayTop<=1 && frame.underlayBottom>=frame.viewportHeight-1,label+' full underlay coverage',row);
        check(frame.cornerInsideHome,label+' viewport bottom belongs to home',row);
        check(frame.underlayImage!=='none'||!['rgba(0, 0, 0, 0)','transparent'].includes(frame.underlayColor),label+' painted underlay',row);
        const bands=frame.stripGeometry;
        check(bands.count>=8 && bands.count<=64 && bands.first<=frame.mainTop+1 && bands.last>=frame.mainBottom-1 &&
          bands.maxGap<=.1 && bands.sameSource && bands.proportionate,label+' proportional photo strips cover the entire menu',row);
      };
      for(const [label,fraction] of [['top',0],['middle',.5],['footer',1],['return',0]]){
        const frame=await scroll(fraction);coverage(frame,label);
        if(label!=='return'&&(locale==='ar'||width===1440)){
          frame.photoPixels=await scenePhotoPixels(page,out?join(out,name+'-'+label+'.png'):undefined);
          const {samples,changed,texturePairs,populatedCells}=frame.photoPixels;
          check(changed>samples*.01 && texturePairs>=20 && populatedCells>=3,label+' visible photograph contributes distributed texture',row);
        }
        row.frames.push({label,...frame});
      }
      const [top,middle,end,back]=row.frames;
      check(top.position==='absolute'&&top.objectPosition==='50% 0%'&&top.fit==='cover','document artwork geometry',row);
      check(top.height<=height+1 && top.height<top.mainHeight/2,'lead photograph preserves its viewport composition',row);
      check(top.mask!=='none' && top.underlayImage!=='none','lead photograph blends over the continuation',row);
      check(row.frames.every(f=>near(f.documentY,top.documentY)&&near(f.width,top.width)&&near(f.height,top.height)&&f.currentPath===top.currentPath),'same document position, size and source',row);
      check(middle.scrollY>top.scrollY&&end.scrollY>middle.scrollY&&end.y+end.height<=1,'lead photograph scrolls out of view',row);
      check(near(back.y,top.y)&&near(back.scrollY,0),'return restores composition',row);
      if(lamp&&source!=='inherited'){
        check(top.landmark?.y>0 && top.landmark.y<top.viewportHeight && top.landmark.x>0 && top.landmark.x<top.width &&
          middle.landmark.y<0 && end.landmark.y<0 && near(top.landmark.y,back.landmark.y),'same lamp moves through and out of viewport',row);
      }
      const footerPhoto=page.locator('[data-sf-module="footer"] > [aria-hidden="true"] img');
      check(await footerPhoto.count()===(source==='custom'?1:0),'duplicate footer art omitted, different footer Hero preserved',row);
      check(top.dim===.15,'configured dim retained',row);
      const requestsAtTop=photoRequests;
      check(requestsAtTop===1,'one background request from top through footer',row);
      for(const next of [height-96,height+64,height-64,height]){
        await page.setViewportSize({width,height:next});const footer=await scroll(1);coverage(footer,'height transition');
        row.viewportTransitions.push({width,height:next,rectHeight:footer.height,mainBottom:footer.mainBottom,viewport:footer.viewportHeight});
      }
      if(width<=390){
        await page.setViewportSize({width:height,height:width});coverage(await scroll(1),'rotated landscape footer');
        await page.setViewportSize({width,height});coverage(await scroll(0),'restored portrait');
      }
      check(photoRequests===requestsAtTop,'scroll/viewport changes do not request the same artwork again',row);
      const sections=page.locator('[data-sf-module="sections"]:visible');
      assert.equal(await sections.count(),5);
      const rail=page.locator('[data-sf-module="categories"]');
      await rail.locator('button').nth(2).click();await settle(page);
      const nav=await rail.evaluate(n=>({sticky:getComputedStyle(n.parentElement).position,header:getComputedStyle(document.querySelector('header')).position,
        active:n.querySelector('[aria-current="true"]')?.textContent,focused:document.activeElement?.id}));
      assert.equal(nav.sticky,'sticky');assert.equal(nav.header,'sticky');assert.match(nav.active,/Category 3/);assert.match(nav.focused,/^sf-cat-title-/);
      const carousel=sections.nth(2).locator('[data-sf-carousel]');const initial=await carousel.getAttribute('data-sf-selected');
      await carousel.locator('[data-sf-carousel-next]').click();assert.notEqual(await carousel.getAttribute('data-sf-selected'),initial);
      await carousel.locator('[data-position="active"][data-sf-item]').click();const sheet=page.getByRole('dialog');await sheet.waitFor();
      await page.keyboard.press('Escape');await sheet.waitFor({state:'hidden'});
      const cart=page.locator('[data-sf-cart-trigger]');await cart.scrollIntoViewIfNeeded();await settle(page);
      const beforeCart=await page.evaluate(()=>scrollY);await cart.click();await page.locator('dialog[open]').waitFor();
      assert.equal(await page.evaluate(()=>getComputedStyle(document.body).overflow),'hidden');
      await page.keyboard.press('Escape');await page.locator('dialog[open]').waitFor({state:'detached'});await settle(page);
      const afterCart=await page.evaluate(()=>scrollY);check(near(beforeCart,afterCart),'cart close restores scroll position',row);
      const search=page.getByRole('searchbox');await search.fill('no-matching-scene-item');await settle(page);
      assert.equal(await sections.count(),1);const filtered=await scroll(1);coverage(filtered,'filtered short menu');
      assert.ok(filtered.mainHeight<top.mainHeight);
      await search.fill('');assert.equal(await sections.count(),5);row.flags={sticky:true,category:true,slider:true,product:true,cart:true,filter:true};
      // The sticky header can cover an element that is technically in view after a cart or category scroll.
      // Return to the actual menu top before measuring or photographing the complete announcement.
      await scroll(0);
      const ann=page.locator('[data-sf-module="announce"]');
      const framing=await ann.evaluate(n=>{
        const r=n.getBoundingClientRect(),header=n.closest('main').querySelector('header').getBoundingClientRect();
        return {top:r.top,bottom:r.bottom,headerBottom:header.bottom,viewport:innerHeight};
      });
      assert.ok(framing.top>=framing.headerBottom-1 && framing.bottom<=framing.viewport+1,'Complete announcement is clear of sticky header');

      const panel=await ann.evaluate(n=>{
        const text=n.querySelector(':scope > span[dir]'),button=n.querySelector('button'),rect=n.getBoundingClientRect(),
          t=text.getBoundingClientRect(),b=button.getBoundingClientRect(), css=getComputedStyle(n);
        const range=document.createRange();range.selectNodeContents(text);
        const lines=new Set([...range.getClientRects()].filter(r=>r.width>0).map(r=>Math.round(r.top))).size;
        return {role:n.getAttribute('role'),closeName:button.getAttribute('aria-label'),stars:n.querySelectorAll(':scope > [aria-hidden="true"]').length,
          lines,left:rect.left,right:innerWidth-rect.right,textInside:t.left>=rect.left&&t.right<=rect.right,
          closeSeparate:t.right<=b.left+1||b.right<=t.left+1,overflow:n.scrollWidth>n.clientWidth,
          radius:parseFloat(css.borderRadius),border:parseFloat(css.borderTopWidth),background:css.backgroundColor,backgroundImage:css.backgroundImage,
          themeText:css.getPropertyValue('--tx').trim(),themeBackground:css.getPropertyValue('--bg').trim(),
          ink:getComputedStyle(text).color,samples:[[rect.left+8,rect.top+8],[rect.right-8,rect.top+8],[rect.left+8,rect.bottom-8]]};
      });
      check(panel.role==='status'&&Boolean(panel.closeName)&&panel.stars===2,'announcement content semantics',row);
      check(panel.radius>0&&panel.border>=1&&panel.left>=15&&panel.right>=15,'bounded panel with gutters',row);
      check(panel.backgroundImage!=='none'&&panel.background!=='rgba(0, 0, 0, 0)','dark panel surface',row);
      check(panel.textInside&&panel.closeSeparate&&!panel.overflow&&(width>390||panel.lines>=2),'long announcement wraps clear of close control',row);
      // Read actual pixels in the panel's empty padding on this photographed surface.
      const png=(await page.screenshot()).toString('base64');
      const contrasts=await page.evaluate(async({png,ink,samples})=>{
        const bytes=Uint8Array.from(atob(png),c=>c.charCodeAt(0));
        const bmp=await createImageBitmap(new Blob([bytes],{type:'image/png'}));
        const c=document.createElement('canvas');c.width=bmp.width;c.height=bmp.height;
        const ctx=c.getContext('2d',{willReadFrequently:true});ctx.drawImage(bmp,0,0);bmp.close();
        const pixels=samples.map(([x,y])=>[...ctx.getImageData(Math.floor(x*devicePixelRatio),Math.floor(y*devicePixelRatio),1,1).data].slice(0,3));
        ctx.fillStyle=ink;ctx.fillRect(0,0,1,1);const fg=[...ctx.getImageData(0,0,1,1).data].slice(0,3);
        const luminance=rgb=>rgb.map(n=>n/255).map(n=>n<=.04045?n/12.92:((n+.055)/1.055)**2.4)
          .reduce((sum,n,i)=>sum+n*[.2126,.7152,.0722][i],0);
        return pixels.map(rgb=>{const a=luminance(fg),b=luminance(rgb);return (Math.max(a,b)+.05)/(Math.min(a,b)+.05);});
      },{png,ink:panel.ink,samples:panel.samples});
      check(contrasts.every(ratio=>ratio>=4.5),'announcement text contrast on photographed surface',row);
      if(locale==='en' && scene==='brand'){
        assert.equal(panel.themeBackground.toLowerCase(),'#f8f4ef');
        assert.equal(panel.themeText.toLowerCase(),'#000000');
        check(panel.ink!=='rgb(0, 0, 0)','dark panel ink stays readable with explicit black menu text',row);
      }
      row.announcement={...panel,framing,contrastRatios:contrasts};
      if(out)await page.screenshot({path:join(out,name+'-announcement.png')});
      await ann.getByRole('button').click();await ann.waitFor({state:'detached'});
      await page.reload({waitUntil:'networkidle'});assert.equal(await ann.count(),0);
      await go('panel-b');await ann.waitFor();
      await go('none-b');assert.equal(await ann.count(),0);row.flags.scopedDismissalAndAbsence=true;
      if(locale==='ar'){
        await go('none-a','intro');
        const intro=page.locator('main[data-sf-screen="intro"]');
        assert.equal(await intro.count(),1);
        assert.equal(await intro.locator('[data-sf-menu-continuation]').count(),0);
        assert.equal(await intro.locator(':scope > div[aria-hidden="true"] > img').evaluate(i=>getComputedStyle(i).position),'fixed');
      }
      if(locale==='ar' && width===390){
        // With page scripts disabled, only the HTML theme and its linked CSS can paint the scene.
        const first=await browser.newContext({...contextOptions,javaScriptEnabled:false});
        try {
          await first.route('**/*',fixtureRoute);
          const initial=await first.newPage();
          const response=await initial.goto(origin+'/'+locale+'/s/'+slug('panel-a')+'/menu',{waitUntil:'networkidle'});
          assert.equal(response.status(),200);
          const panel=initial.locator('[data-sf-module="announce"]');await panel.waitFor();
          row.firstPaint=await panel.evaluate(el=>{
            const layer=el.closest('main').querySelector('[data-sf-menu-background]');
            const panelStyle=getComputedStyle(el),sceneStyle=getComputedStyle(layer);
            return {stripCount:layer.querySelectorAll('[data-sf-scene-strip] > img').length,
              panelColor:panelStyle.backgroundColor,panelGradient:panelStyle.backgroundImage,
              ink:getComputedStyle(el.querySelector(':scope > span[dir]')).color,
              sceneColor:sceneStyle.backgroundColor,sceneGradient:sceneStyle.backgroundImage};
          });
          const painted=s=>!['transparent','rgba(0, 0, 0, 0)'].includes(s);
          check(painted(row.firstPaint.panelColor) && row.firstPaint.panelGradient!=='none','SSR announcement paints before hydration',row);
          check(painted(row.firstPaint.sceneColor) && row.firstPaint.sceneGradient!=='none','SSR scene paints before hydration',row);
          check(row.firstPaint.stripCount===16,'SSR includes the complete photo continuation before hydration',row);
          check(row.firstPaint.ink===row.announcement.ink,'SSR announcement ink matches hydrated ink',row);
          if(out)await initial.screenshot({path:join(out,name+'-first-paint.png')});
        } finally {await first.close();}
      }
      assert.deepEqual(violations,[]);assert.deepEqual(errors,[]);
      console.log(name, 'geometry/visibility checks:', failures.filter(f=>f.case===name).length, 'failures');
    } finally {await ctx.close();}
  }
} finally {
  await browser?.close();
  if(child.exitCode===null){const stopped=new Promise(ok=>child.once('exit',ok));child.kill();await stopped;}
  if(out) writeFileSync(join(out,'scene-scroll-'+engine.name()+'.json'),JSON.stringify({engine:engine.name(),version:browser?.version(),
    scope:'Local production renderer, synthetic tenant, read-only fixtures. Desktop WebKit and controlled viewport resizing are not a physical iPhone.',
    physicalIPhone:'NOT_RUN',backgroundSha256:createHash('sha256').update(background).digest('hex'),buildId:readFileSync(join(root,'.next/BUILD_ID'),'utf8').trim(),rows,failures},null,2)+'\n');
}
assert.deepEqual(failures,[]);
