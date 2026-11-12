import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
const { buildMenuBrand } = await import('../src/theme/buildMenuBrand.ts');
const { buildSiteTheme } = await import('../src/theme/buildSiteTheme.ts');
const { contrast, mix, rgba } = await import('../src/theme/contrast.ts');

test('menu decoration retains all site/payment tokens and raw merchant values', () => {
  for (const siteTheme of [null, 'light', 'dark']) for (const primary of ['#075c91', '#292929', '#fffefe']) {
    const tenant = { siteTheme, brand: { primary, accent: '#e61473', text: '#ffffff', buttonText: '#ffffff' } };
    const original = structuredClone(tenant), base = buildSiteTheme(tenant), decorated = buildMenuBrand(tenant, base);
    const { brandSecondary, menuChipFrom, menuChipTo, menuChipPaintFrom, menuChipPaintTo, menuDockFrom, menuDockTo, menuActiveFrom, menuActiveTo, ...rest } = decorated;
    assert.deepEqual(rest, base); assert.deepEqual(tenant, original);
    assert.ok(contrast(brandSecondary, base.sf) >= 4.5);
    assert.equal(decorated.acc, original.brand.accent);
  }
});

test('translucent category washes keep AA over photographs without fading or changing merchant ink', () => {
  const alphas = new Set();
  for (const siteTheme of ['light', 'dark']) for (const text of ['#666666', '#6c6c6c', '#777777', '#ffffff', '#075c91']) {
    const tenant = { siteTheme, brand: { primary: '#075c91', accent: '#e61473', text, buttonText: '#ffffff' } };
    const saved = structuredClone(tenant), base = buildSiteTheme(tenant), paint = buildMenuBrand(tenant, base);
    const alpha = parseFloat(paint.menuChipPaintFrom.split(',').at(-1));
    alphas.add(alpha);
    assert.ok([.88, .96, 1].includes(alpha));
    assert.equal(paint.menuChipPaintFrom, rgba(paint.menuChipFrom, alpha));
    assert.equal(paint.menuChipPaintTo, rgba(paint.menuChipTo, alpha));
    for (let i = 0; i <= 20; i++) for (const bg of ['#000000', '#ffffff']) {
      const wash = mix(paint.menuChipFrom, paint.menuChipTo, i / 20);
      assert.ok(contrast(paint.tx, mix(bg, wash, alpha)) >= 4.5, `${siteTheme}/${text}/${alpha}/${bg}/${i}`);
    }
    assert.equal(paint.tx, base.tx); assert.deepEqual(tenant, saved);
  }
  assert.ok(alphas.has(.88), 'normal themes allow a translucent button surface');
  assert.ok(alphas.has(1), 'near-AA custom ink keeps the opaque button surface, not faded text');
});

test('tinted chips, active controls and dock preserve AA for the reviewed blue/pink/custom-text counterexamples', () => {
  for (const siteTheme of ['light', 'dark']) for (const accent of ['#4475bd', '#e61473', '#777777', '#ffffff']) for (const text of ['#666666', '#ffffff', '#075c91']) {
    const raw = { siteTheme, brand: {primary:'#075c91',accent,text,buttonText:'#ffffff'} };
    const original=structuredClone(raw), base=buildSiteTheme(raw), paint=buildMenuBrand(raw,base);
    for (const [a,b,copy] of [['menuChipFrom','menuChipTo','tx'],['menuDockFrom','menuDockTo','tx'],['menuActiveFrom','menuActiveTo','onacc']]) {
      for(let i=0;i<=20;i++) assert.ok(contrast(paint[copy],mix(paint[a],paint[b],i/20))>=4.5, `${siteTheme}/${accent}/${text}/${a}/${i}`);
    }
    assert.deepEqual(raw,original); assert.equal(paint.tx,base.tx); assert.equal(paint.onacc,base.onacc);
  }
});
