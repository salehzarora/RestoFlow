// Focused stylesheet regression, using the shipped CSS in a browser. This is
// not the consolidated same-asset visual evidence or a live publication test.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { chromium } from '@playwright/test';

const css = readFileSync(new URL('../../src/ui/storefront/home/home.module.css', import.meta.url), 'utf8');
const carouselCss = readFileSync(new URL('../../src/ui/storefront/home/carousel.module.css', import.meta.url), 'utf8');
const photo = readFileSync(new URL('../../public/cinematic-preview/menu-background.webp', import.meta.url)).toString('base64');
const browser = await chromium.launch({ executablePath: process.env.SF_BROWSER_EXECUTABLE || undefined, headless: true });
let checks = 0;
try {
  for (const width of [390, 1440]) for (const preset of [null, 'reference_dark']) for (const dim of [0, 15, 80]) {
    const page = await browser.newPage({ viewport: { width, height: 844 } });
    await page.setContent(`<style>${css}\n${carouselCss}</style>
      <div id="root" ${preset ? 'data-sf-scene="reference_dark"' : ''}>
        <main class="page" data-sf-screen="home">
          <div class="menuBackdrop"><img alt="" src="data:image/webp;base64,${photo}"></div>
          <header class="header"><button id="click-target">Cart</button></header>
          <nav class="categoryWrap">Category</nav>
          <div class="sceneBackdrop"><img alt=""></div>
          <div class="stage"><button class="slide"><img alt=""></button></div>
          <footer class="footer"><div class="footerPhoto"><img alt=""></div><div class="servicePanel">Hours</div></footer>
        </main>
      </div>`);
    await page.evaluate(({ tokens, dim }) => {
      const root = document.getElementById('root');
      for (const [key, value] of Object.entries(tokens)) root.style.setProperty(`--${key}`, value);
      root.style.setProperty('--menu-image-dim', String(dim / 100));
      root.querySelector('main').style.height = '4000px';
    }, { tokens: { bg: preset ? '#151515' : '#00ff00', acc: '#ff00ff', tx: '#f7f2ea',
      sceneGlass: 'rgba(21,21,21,0.76)', sceneGlassSoft: 'rgba(37,37,37,0.8)' }, dim });
    const computed = await page.evaluate(() => {
      const read = (selector, pseudo) => {
        const style = getComputedStyle(document.querySelector(selector), pseudo);
        return Object.fromEntries(['backgroundColor', 'opacity', 'filter', 'backdropFilter', 'objectFit', 'position', 'height', 'pointerEvents'].map(key => [key, style[key]]));
      };
      return { header: read('.header'), category: read('.categoryWrap'), footer: read('.servicePanel'), footerImage: read('.footerPhoto img'),
        layer: read('.menuBackdrop'), image: read('.menuBackdrop img'), dim: read('.menuBackdrop', '::after'),
        inherited: read('.sceneBackdrop img'), inheritedDim: read('.sceneBackdrop', '::after'), product: read('.slide img') };
    });
    assert.equal(computed.dim.opacity, String(dim / 100));
    assert.equal(computed.layer.pointerEvents, 'none');
    assert.equal(computed.image.objectFit, 'cover');
    assert.equal(computed.image.position, 'fixed');
    assert.equal(computed.image.filter, 'none');
    assert.equal(computed.image.opacity, '1');
    const frames = await page.locator('.menuBackdrop img').evaluate(async image => {
      await image.decode();
      return [0, 1500, document.documentElement.scrollHeight].map(top => {
        scrollTo(0, top);
        const { x, y, width, height } = image.getBoundingClientRect();
        return { scrollY, x, y, width, height, objectPosition: getComputedStyle(image).objectPosition };
      });
    });
    assert.ok(frames[2].scrollY > frames[1].scrollY && frames[1].scrollY > 0);
    for (const { scrollY, ...frame } of frames) {
      assert.deepEqual(frame, { x: 0, y: 0, width, height: 844, objectPosition: '50% 50%' });
    }
    assert.equal(computed.product.objectFit, 'contain');
    assert.doesNotMatch(computed.product.filter, /(?:^|\s)blur\(/);
    if (preset) {
      assert.equal(computed.header.backgroundColor, 'rgba(21, 21, 21, 0.76)');
      assert.equal(computed.category.backgroundColor, computed.header.backgroundColor);
      assert.equal(computed.footer.backgroundColor, 'rgba(37, 37, 37, 0.8)');
      assert.equal(computed.header.backdropFilter, 'none');
      assert.equal(computed.category.backdropFilter, 'none');
      assert.equal(computed.inherited.objectFit, 'cover');
      assert.equal(computed.inherited.position, 'fixed');
      assert.equal(computed.inherited.height, '844px');
      assert.equal(computed.inherited.filter, 'none');
      assert.equal(computed.inherited.opacity, '1');
      assert.equal(computed.dim.backgroundColor, 'rgb(0, 0, 0)');
      assert.equal(computed.inheritedDim.backgroundColor, 'rgb(0, 0, 0)');
      assert.equal(computed.inheritedDim.opacity, String(dim / 100));
      assert.equal(computed.footerImage.filter, 'none');
    } else {
      assert.equal(computed.dim.backgroundColor, 'rgb(0, 255, 0)');
      assert.equal(computed.inherited.filter, 'blur(22px)');
      assert.equal(computed.inherited.opacity, '0.18');
      assert.equal(computed.header.backdropFilter, 'blur(18px)');
    }
    await page.locator('#click-target').click();
    await page.close();
    checks++;
  }
  console.log(`PASS: ${checks} mobile/desktop legacy/reference/dimming stylesheet combinations; product fit and pointer access preserved`);
} finally {
  await browser.close();
}
