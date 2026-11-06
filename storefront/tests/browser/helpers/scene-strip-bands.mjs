import assert from 'node:assert/strict';

// Wide and tall PNGs deliberately have a red upper half and a black bottom edge.
// A long actual MenuBackdrop must continue only the intervening blue/green band.
export async function testStripBands(browser,origin,setMenu) {
  const results=[];
  for (const [shape,sw,sh,width] of [['wide',2400,400,390],['tall',400,2400,1440]]) {
    const page=await browser.newPage({viewport:{width,height:844},deviceScaleFactor:1});
    try {
      const src=await page.evaluate(({sw,sh})=>{
        const c=document.createElement('canvas');c.width=sw;c.height=sh;
        const ctx=c.getContext('2d');
        ctx.fillStyle='rgb(230,20,10)';ctx.fillRect(0,0,sw,sh/2);
        // One source pixel of guard colour prevents bilinear interpolation at
        // exactly 50% from mixing the deliberately saturated red into the test.
        for(let y=sh/2-1;y<sh;y++){
          ctx.fillStyle='rgb(10,'+(80+y%100)+',195)';ctx.fillRect(0,y,sw,1);
        }
        ctx.fillStyle='black';ctx.fillRect(0,sh-2,sw,2);
        return c.toDataURL('image/png');
      },{sw,sh});
      setMenu(src);
      await page.goto(origin);
      await page.locator('[data-sf-menu-primary]').evaluate(img=>img.decode());
      const count=await page.locator('[data-sf-scene-strip]').count();
      assert.equal(count,64,'Long fixture exercises 64 strips');
      for (const depth of ['top','middle','footer']) {
        const geometry=await page.evaluate(depth=>{
          scrollTo(0,depth==='top'?0:depth==='middle'?10010:document.documentElement.scrollHeight);
          const layer=document.querySelector('[data-sf-menu-continuation]');
          const bounds=Array.from(layer.children,e=>e.getBoundingClientRect());
          const edges=bounds.slice(1).map(b=>b.top).filter(y=>y>2&&y<innerHeight-2);
          const normal=layer.firstElementChild,copy=normal.firstElementChild,box=copy.getBoundingClientRect();
          const drawnHeight=Math.max(box.height,box.width*copy.naturalHeight/copy.naturalWidth);
          const sourceStart=1-(box.bottom-bounds[0].top)/drawnHeight;
          const sourceEnd=1-(box.bottom-bounds[0].bottom)/drawnHeight;
          return {scrollY,edges,sourceStart,sourceEnd,layerBottom:layer.getBoundingClientRect().bottom,last:bounds.at(-1).bottom,
            maxGap:Math.max(0,...bounds.slice(1).map((b,i)=>b.top-bounds[i].bottom))};
        },depth);
        assert.ok(geometry.last>=geometry.layerBottom && geometry.maxGap<=.1,'Strips reach the full 20,001px document without a gap');
        assert.ok(geometry.sourceStart>=.5-1e-6 && geometry.sourceEnd<1,'Cover crop starts in the lower half and trims the original bottom edge');
        const frame=(await page.screenshot()).toString('base64');
        const pixels=await page.evaluate(async ({frame,edges})=>{
          const raw=Uint8Array.from(atob(frame),v=>v.charCodeAt(0));
          const bmp=await createImageBitmap(new Blob([raw],{type:'image/png'}));
          const c=document.createElement('canvas');c.width=bmp.width;c.height=bmp.height;
          const ctx=c.getContext('2d');ctx.drawImage(bmp,0,0);bmp.close();
          const {data,width,height}=ctx.getImageData(0,0,c.width,c.height);
          let red=0,lower=0,total=0;
          for(let y=2;y<height;y+=4)for(let x=2;x<width;x+=4){
            const n=4*(y*width+x);
            if(data[n]>150 && data[n+2]<60)red++;
            if(data[n]<30 && data[n+1]>60 && data[n+2]>150)lower++;
            total++;
          }
          const seams=edges.map(edge=>{
            const y=Math.round(edge);let maxJump=0;
            for(let x=0;x<width;x++){
              const i=4*(y*width+x);
              for(let k=0;k<3;k++)maxJump=Math.max(maxJump,Math.abs(data[i+k]-data[i-4*width+k]));
            }
            return {y,maxJump};
          });
          return {total,red,lower,seams};
        },{frame,edges:geometry.edges});
        if(depth==='top')assert.ok(pixels.red>100,'Upper-half positive control is visibly red in the lead photograph');
        else {
          assert.equal(pixels.red,0,'Continuation never resamples the upper half');
          assert.equal(pixels.lower,pixels.total,'Every sampled lower pixel is photographic and the black source edge is cropped');
          assert.ok(pixels.seams.length>0 && pixels.seams.every(s=>s.maxJump<=4),'Reflected row joins preserve adjacent pixel colours');
        }
        results.push({shape,depth,width,source:[sw,sh],count,...geometry,...pixels});
      }
    } finally {await page.close();}
  }
  return results;
}
