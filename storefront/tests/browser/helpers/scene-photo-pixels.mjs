// Compare the unmodified viewport with the same scene after hiding only its photograph.
export async function scenePhotoPixels(page, output) {
  const options = { animations: 'disabled', caret: 'hide' };
  const normal = await page.screenshot({ ...options, path:output });
  const hidden = await page.screenshot({ ...options, style:'main[data-sf-screen="home"] > div[aria-hidden="true"]:first-child img{visibility:hidden!important}' });
  const restored = await page.screenshot(options);
  return page.evaluate(async sources => {
    async function pixels(source) {
      const bytes = Uint8Array.from(atob(source), c => c.charCodeAt(0));
      const image = await createImageBitmap(new Blob([bytes], {type:'image/png'}));
      const canvas = document.createElement('canvas');
      canvas.width=image.width; canvas.height=image.height;
      const ctx=canvas.getContext('2d',{willReadFrequently:true});
      ctx.drawImage(image,0,0);image.close();
      return ctx.getImageData(0,0,canvas.width,canvas.height);
    }
    const [normal,hidden,restored]=await Promise.all(sources.map(pixels));
    const {width,height}=normal;
    const cells=Array(12).fill(0);
    let samples=0, changed=0, texturePairs=0;
    // Eight-bit RGB contribution, sampled every four pixels. Ignore anything that
    // also changed after restoring the photograph, such as a moving scrollbar.
    for(let y=2;y<height;y+=4) {
      let previous=null;
      for(let x=2;x<width;x+=4) {
        const p=4*(y*width+x);
        const value=[0,1,2].map(c=>normal.data[p+c]-hidden.data[p+c]);
        const stable=[0,1,2].every(c=>Math.abs(normal.data[p+c]-restored.data[p+c])<=1);
        samples++;
        if(!stable||value.every(v=>Math.abs(v)<4)){previous=null;continue;}
        changed++;
        cells[Math.floor(3*y/height)*4+Math.floor(4*x/width)]++;
        if(previous&&value.some((v,c)=>Math.abs(v-previous[c])>=2))texturePairs++;
        previous=value;
      }
    }
    return {width,height,samples,changed,texturePairs,populatedCells:cells.filter(n=>n>=8).length};
  },[normal,hidden,restored].map(bytes=>bytes.toString('base64')));
}
