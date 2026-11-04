import { chromium } from '@playwright/test';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
const [assets, destination] = process.argv.slice(2);
await mkdir(destination, { recursive: true });
const browser = await chromium.launch({ headless: true, channel: 'chrome' });
const page = await browser.newPage({ viewport: {width: 1240, height: 560}, deviceScaleFactor: 1 });
const measurements = [];
try {
  for (const [name, source] of [['burger','item-burger.png'], ['fries','item-fries.png'], ['platter','item-plate.png'], ['drink','item-drink.png']]) {
    const original = await readFile(join(assets, source));
    const cutout = await readFile(join(destination, `${name}-u2net.png`));
    const uri = bytes => `data:image/png;base64,${bytes.toString('base64')}`;
    await page.setContent(`<style>body{font:18px system-ui;margin:20px;color:#111;background:#eee}main{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}figure{margin:0}img{width:100%;height:430px;object-fit:contain}figcaption{padding:10px}h1{font-size:20px}</style><h1>${name} — actual local U²-Net worker output, no generated pixels</h1><main><figure><figcaption>Original</figcaption><img src="${uri(original)}"></figure><figure><figcaption>Processed · light</figcaption><img style="background:#fafafa" src="${uri(cutout)}"></figure><figure><figcaption>Processed · dark</figcaption><img style="background:#171717" src="${uri(cutout)}"></figure></main>`);
    await page.locator('img').evaluateAll(images => Promise.all(images.map(image => image.decode())));
    const alpha = await page.locator('img').nth(1).evaluate(image => {
      const canvas = document.createElement('canvas'); canvas.width = image.naturalWidth; canvas.height = image.naturalHeight;
      const ctx = canvas.getContext('2d');ctx.drawImage(image,0,0);const rgba = ctx.getImageData(0,0,canvas.width,canvas.height).data;
      let transparent = 0, partial = 0, opaque = 0; for(let i=3;i<rgba.length;i+=4){if(rgba[i]===0)transparent++;else if(rgba[i]===255)opaque++;else partial++;}
      return {width:canvas.width,height:canvas.height,transparent,partial,opaque};
    });
    await page.screenshot({path:join(destination,`${name}-light-dark.png`)});
    measurements.push({name,source,sourceBytes:original.length,sourceWidth:original.readUInt32BE(16),sourceHeight:original.readUInt32BE(20),sourceSha256:createHash('sha256').update(original).digest('hex'),outputBytes:cutout.length,outputSha256:createHash('sha256').update(cutout).digest('hex'),...alpha});
  }
  await writeFile(join(destination,'cutout-measurements.json'),JSON.stringify(measurements,null,2)+'\n');
  console.log(JSON.stringify(measurements));
} finally {await browser.close();}
