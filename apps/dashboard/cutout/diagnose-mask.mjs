// Evidence-only observer for BIZBOT-STOREFRONT-VISUAL-PARITY-001.
// Serves an instrumented COPY of the shipped worker; never changes its protocol
// or arithmetic on disk. No hosted requests, service writes, or inferred masks.
import assert from 'node:assert/strict';
import { chromium } from '@playwright/test';
import { createServer } from 'node:http';
import { readFile, writeFile, mkdir, copyFile } from 'node:fs/promises';
import { extname, join } from 'node:path';
import { createHash } from 'node:crypto';
import { deriver } from '../../../supabase/functions/storefront-media-publish/test/engine.mjs';
import { MODEL } from '../web/product-cutout/limits.mjs';

const [inputDir, destination, ciReceipt] = process.argv.slice(2);
assert.ok(inputDir && destination && ciReceipt, 'INPUT_DIRECTORY OUTPUT_DIRECTORY CI_PRODUCT_JSON');
await mkdir(destination, { recursive: true });
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const webRoot = new URL('../web/', import.meta.url);
const shippedWorker = await readFile(new URL('product-cutout/worker.mjs', webRoot), 'utf8');
function once(text, anchor, insert) {
  assert.equal(text.split(anchor).length, 2, 'Diagnostic anchor must be unique');
  return text.replace(anchor, anchor + '\n' + insert);
}
let observedWorker = once(shippedWorker, 'const output = result[session.outputNames[0]];', `
    const rawCopy = new Float32Array(output.data);
    postMessage({ diagnostic: 'raw', bytes: rawCopy.buffer, dims: [...output.dims] }, [rawCopy.buffer]);`);
observedWorker = once(observedWorker, 'matte.getContext(\'2d\').putImageData(new ImageData(alphaMatte(output.data), LIMITS.modelSide, LIMITS.modelSide), 0, 0);', `
    postMessage({ diagnostic: 'normalized', bytes: await (await matte.convertToBlob({type:'image/png'})).arrayBuffer() });`);
observedWorker = once(observedWorker, 'const mask = out.getImageData(0, 0, size.width, size.height).data;', `
    postMessage({ diagnostic: 'resized', bytes: await (await canvas.convertToBlob({type:'image/png'})).arrayBuffer() });`);
await writeFile(join(destination, 'observed-worker.mjs'), observedWorker);
const server = createServer(async (req, res) => {
  try {
    if (req.url === '/') { res.setHeader('content-type', 'text/html'); res.end('<title>Local mask diagnosis</title>'); return; }
    const path = new URL(`.${req.url}`, webRoot);
    if (!path.href.startsWith(webRoot.href)) { res.writeHead(403).end(); return; }
    const bytes = req.url === '/product-cutout/worker.mjs' ? Buffer.from(observedWorker) : await readFile(path);
    res.setHeader('content-type', ({'.mjs':'text/javascript','.wasm':'application/wasm'})[extname(path.pathname)] || 'application/octet-stream');
    res.setHeader('content-length', bytes.length); res.end(bytes);
  } catch { res.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browserChannel = process.argv[5] === 'bundled' ? 'bundled' : 'chrome';
const browser = await chromium.launch({ headless: true, ...(browserChannel === 'chrome' ? {channel:'chrome'} : {}) });
const page = await browser.newPage({ viewport: { width: 1320, height: 940 } });
const origin = `http://127.0.0.1:${server.address().port}`;
await page.route('**/*', route => new URL(route.request().url()).origin === origin ? route.continue() : route.abort());
await page.goto(origin);
const actualCI = JSON.parse(await readFile(ciReceipt, 'utf8'));
const engine = await deriver();
const samples = [
  ['burger', { plateLeft:[15,260,45,60], food:[140,240,85,100], background:[300,400,35,45] }],
  ['fries-cup', { cup:[225,360,75,90], plate:[110,410,65,45], food:[220,275,60,40], bottle:[380,100,60,150], background:[440,350,30,80] }],
  ['platter', { food:[100,270,120,120], bottle:[135,70,50,100], background:[300,400,30,45] }],
];
function quantiles(values) {
  const sorted = [...values].sort((a,b)=>a-b);
  return { count:sorted.length, min:sorted[0], p10:sorted[Math.floor(sorted.length*.1)], median:sorted[Math.floor(sorted.length*.5)], p90:sorted[Math.floor(sorted.length*.9)], max:sorted.at(-1) };
}
const report = { model:MODEL, shippedWorkerSha256:sha(shippedWorker), diagnosticWorkerSha256:sha(observedWorker), browserChannel, browser:browser.version(), cases:[] };
try {
  for (const [name, regions] of samples) {
    const source = await readFile(join(inputDir, `${name}.webp`));
    const ci = actualCI.cases.find(c=>c.sample===name);
    assert.equal(sha(source), ci.sourceSha256, 'Source must match real-service CI fixture');
    await copyFile(join(inputDir, `${name}.webp`), join(destination, `${name}-source.webp`));
    const result = await page.evaluate(async input => {
      const worker = new Worker('/product-cutout/worker.mjs', {type:'module'}), observations={};
      return new Promise((resolve,reject)=>{
        const timer=setTimeout(()=>{worker.terminate();reject(Error('Diagnostic worker exceeded shipped 120s bound'));},120000);
        worker.onerror=()=>{clearTimeout(timer);worker.terminate();reject(Error('Diagnostic worker error'));};
        worker.onmessage=({data})=>{
          if(data.error){clearTimeout(timer);worker.terminate();reject(Error(data.error));}
          if(data.diagnostic)observations[data.diagnostic]={bytes:[...new Uint8Array(data.bytes)],dims:data.dims};
          if(data.done){clearTimeout(timer);worker.terminate();resolve({observations,bytes:[...new Uint8Array(data.bytes)],width:data.width,height:data.height});}
        };
        const bytes=new Uint8Array(input);worker.postMessage({bytes:bytes.buffer,mimeType:'image/webp'},[bytes.buffer]);
      });
    }, [...source]);
    assert.deepEqual(Object.keys(result.observations), ['raw','normalized','resized']);
    const rawBuffer=Buffer.from(result.observations.raw.bytes), candidate=Buffer.from(result.bytes);
    const rawValues=new Float32Array(rawBuffer.buffer,rawBuffer.byteOffset,rawBuffer.length/4);
    const rawStats=quantiles(rawValues), rawRegions={};
    for(const [label,[x,y,w,h]] of Object.entries(regions)){
      const values=[];
      for(let j=Math.floor(y*320/result.height);j<Math.min(320,Math.ceil((y+h)*320/result.height));j++)
        for(let i=Math.floor(x*320/result.width);i<Math.min(320,Math.ceil((x+w)*320/result.width));i++)values.push(rawValues[j*320+i]);
      rawRegions[label]=quantiles(values);
    }
    await writeFile(join(destination,`${name}-raw-mask.float32le`),rawBuffer);
    await writeFile(join(destination,`${name}-normalized-mask.png`),Buffer.from(result.observations.normalized.bytes));
    await writeFile(join(destination,`${name}-resized-mask.png`),Buffer.from(result.observations.resized.bytes));
    await writeFile(join(destination,`${name}-candidate.png`),candidate);
    const publications=[];
    for(const variant of ['w480','w960']){
      let derived;
      for(let rung=0;rung<3;rung++){derived=await engine.derive(candidate,{variant,source:'menu-images',rung});if(derived.status==='derived')break;}
      assert.equal(derived.status,'derived');
      const bytes=Buffer.from(derived.bytes);
      await writeFile(join(destination,`${name}-published-${variant}.webp`),bytes);
      publications.push({variant,bytes,sha256:sha(bytes),width:derived.width,height:derived.height});
    }
    const decoded = await page.evaluate(async ({source,candidate,normalized,resized,published,raw,regions})=>{
      const decode=async bytes=>{const img=await createImageBitmap(new Blob([new Uint8Array(bytes)]));const c=new OffscreenCanvas(img.width,img.height);const ctx=c.getContext('2d');ctx.drawImage(img,0,0);img.close();return {c,ctx,rgba:ctx.getImageData(0,0,c.width,c.height).data};};
      const digest=async bytes=>[...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))].map(v=>v.toString(16).padStart(2,'0')).join('');
      const png=async c=>[...new Uint8Array(await (await c.convertToBlob({type:'image/png'})).arrayBuffer())];
      const stats=values=>{values.sort((a,b)=>a-b);return {count:values.length,min:values[0],p10:values[Math.floor(values.length*.1)],median:values[Math.floor(values.length*.5)],p90:values[Math.floor(values.length*.9)],max:values.at(-1)};};
      const s=await decode(source),n=await decode(normalized),m=await decode(resized),f=await decode(candidate),p=await decode(published);
      const plane=(rgba,channel)=>Uint8Array.from({length:rgba.length/4},(_,i)=>rgba[i*4+channel]);
      const planes={normalized:plane(n.rgba,0),resized:plane(m.rgba,0),final:plane(f.rgba,3),published:plane(p.rgba,3)};
      const metrics={};
      for(const [label,values]of Object.entries(planes)){
        const width=label==='normalized'?320:f.c.width,height=label==='normalized'?320:f.c.height,roi={};
        for(const[key,[x,y,w,h]]of Object.entries(regions)){
          const v=[];for(let j=Math.floor(y*height/f.c.height);j<Math.min(height,Math.ceil((y+h)*height/f.c.height));j++)for(let i=Math.floor(x*width/f.c.width);i<Math.min(width,Math.ceil((x+w)*width/f.c.width));i++)v.push(values[j*width+i]);roi[key]=stats(v);
        }
        metrics[label]={width,height,sha256:await digest(values),transparent:values.filter(v=>v===0).length,partial:values.filter(v=>v>0&&v<255).length,opaque:values.filter(v=>v===255).length,regions:roi};
      }
      let resizedFinalDifferences=0,finalPublishedDifferences=0;
      for(let i=0;i<planes.final.length;i++){if(planes.resized[i]!==planes.final[i])resizedFinalDifferences++;if(planes.final[i]!==planes.published[i])finalPublishedDifferences++;}
      const grayPng=async(values,width,height)=>{const c=new OffscreenCanvas(width,height),ctx=c.getContext('2d'),rgba=new Uint8ClampedArray(width*height*4);for(let i=0;i<values.length;i++)rgba.set([values[i],values[i],values[i],255],i*4);ctx.putImageData(new ImageData(rgba,width,height),0,0);return png(c);};
      const rawValues=new Float32Array(new Uint8Array(raw).buffer),rawGray=Uint8Array.from(rawValues,v=>Math.round(Math.max(0,Math.min(1,v))*255));
      s.ctx.lineWidth=2;s.ctx.font='13px sans-serif';
      for(const [label,[x,y,w,h]]of Object.entries(regions)){
        s.ctx.strokeStyle='#00ffff';s.ctx.strokeRect(x,y,w,h);
        s.ctx.fillStyle='#000';s.ctx.fillRect(x,Math.max(0,y-17),Math.min(w,120),17);
        s.ctx.fillStyle='#fff';s.ctx.fillText(label,x+2,Math.max(13,y-4));
      }
      const rawVsNormalized=[];for(let i=0;i<rawGray.length;i++)rawVsNormalized.push(Math.abs(rawGray[i]-planes.normalized[i]));
      return {metrics,resizedFinalDifferences,finalPublishedDifferences,rawUnitScaleVsNormalized:stats(rawVsNormalized),sourceWidth:s.c.width,sourceHeight:s.c.height,
        regionsPng:await png(s.c),rawPng:await grayPng(rawGray,320,320),finalAlphaPng:await grayPng(planes.final,f.c.width,f.c.height),publishedAlphaPng:await grayPng(planes.published,p.c.width,p.c.height)};
    },{source:[...source],candidate:[...candidate],normalized:result.observations.normalized.bytes,resized:result.observations.resized.bytes,published:[...publications[0].bytes],raw:[...rawBuffer],regions});
    for(const [key,suffix]of [['regionsPng','source-regions'],['rawPng','raw-mask-unit-scale'],['finalAlphaPng','final-alpha'],['publishedAlphaPng','published-alpha']]){await writeFile(join(destination,`${name}-${suffix}.png`),Buffer.from(decoded[key]));delete decoded[key];}
    const row={sample:name,sourceKind:ci.sourceKind,sourceBytes:source.length,sourceSha256:sha(source),candidateBytes:candidate.length,candidateSha256:sha(candidate),rawDimensions:result.observations.raw.dims,rawFloat32Sha256:sha(rawBuffer),rawStats,regionBoxes:regions,rawRegions,...decoded,
      publications:publications.map(({bytes,...p})=>({...p,bytes:bytes.length,actualCISha256:ci.publishedImages.find(i=>i.variant===p.variant).sha256,matchesActualCI:p.sha256===ci.publishedImages.find(i=>i.variant===p.variant).sha256})),
      finalAlphaMatchesActualCI:decoded.metrics.final.sha256===ci.publishedImages[0].alphaSha256};
    report.cases.push(row);
    const uri=async(file,mime='image/png')=>`data:${mime};base64,${(await readFile(join(destination,file))).toString('base64')}`;
    const tiles=[['Source (published copy)',await uri(`${name}-source.webp`,'image/webp')],['Raw model probability ×255 (320²)',await uri(`${name}-raw-mask-unit-scale.png`)],['Actual normalized matte (320²)',await uri(`${name}-normalized-mask.png`)],['Actual resized matte',await uri(`${name}-resized-mask.png`)],['PNG candidate decoded alpha',await uri(`${name}-final-alpha.png`)],['c4 WebP decoded alpha',await uri(`${name}-published-alpha.png`)],['Candidate · light',await uri(`${name}-candidate.png`) ],['Candidate · dark',await uri(`${name}-candidate.png`)]];
    await page.setContent(`<style>body{font:16px system-ui;background:#eee;margin:14px;color:#111}h1{font-size:20px}main{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}figure{margin:0}img{width:100%;height:390px;object-fit:contain;background:#fafafa}figure:last-child img{background:#171717}figcaption{height:25px}</style><h1>${name}: unchanged raw model → actual processed alpha → pinned c4 local replay</h1><main>${tiles.map(([label,url])=>`<figure><figcaption>${label}</figcaption><img src="${url}"></figure>`).join('')}</main>`);
    await page.locator('img').evaluateAll(images=>Promise.all(images.map(i=>i.decode())));
    await page.screenshot({path:join(destination,`${name}-diagnostic-board.png`)});
    console.log(JSON.stringify({sample:name,rawMin:rawStats.min,rawMax:rawStats.max,normalizationMaxDifference:decoded.rawUnitScaleVsNormalized.max,resizedFinalDifferences:decoded.resizedFinalDifferences,finalPublishedDifferences:decoded.finalPublishedDifferences,finalAlphaMatchesActualCI:row.finalAlphaMatchesActualCI,publicationsMatchActualCI:row.publications.every(p=>p.matchesActualCI)}));
    await page.goto(origin);
  }
  await writeFile(join(destination,'mask-diagnosis.json'),JSON.stringify(report,null,2)+'\n');
} finally {await browser.close();server.close();}
