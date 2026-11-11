import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
const {buildSiteTheme}=await import('../src/theme/buildSiteTheme.ts');
const {buildCinematicTheme}=await import('../src/theme/buildCinematicTheme.ts');
const {buildTheme}=await import('../src/theme/buildTheme.ts');
const {contrast}=await import('../src/theme/contrast.ts');
const brands=[{primary:'#292929',accent:'#ff8000',text:'#ffffff',buttonText:'#000000',fontFamily:'alexandria'},
 {primary:'#ffffff',accent:'#135f73',text:'#eeeeee',buttonText:'#135f73',fontFamily:'rubik'},
 {primary:'#292929',accent:'#777777',text:'#ffffff',buttonText:'#777777',fontFamily:'alexandria'},
 {primary:'#747474',accent:'#ffffff',text:'#888888',buttonText:'#ffffff',fontFamily:'system'}];
test('absent/null site theme preserves each legacy renderer token contract exactly',()=>{
 for(const brand of brands)for(const scenePreset of [null,'reference_dark']){
  const tenant={brand,scenePreset};assert.deepEqual(buildSiteTheme(tenant),buildCinematicTheme(brand,scenePreset));
  const legacy=buildTheme('light',{primary:'#123027',accent:'#C2410C'});
  assert.equal(buildSiteTheme({...tenant,siteTheme:null},legacy),legacy);
 }
});
test('explicit whole-site modes retain raw brands and contrast on actual copy/button/field surfaces',()=>{
 for(const brand of brands)for(const scenePreset of [null,'reference_dark'])for(const siteTheme of ['light','dark']){
  const tenant={brand,scenePreset,siteTheme},saved=structuredClone(tenant),t=buildSiteTheme(tenant);
  assert.deepEqual(tenant,saved);assert.equal(t.acc,brand.accent);
  if(siteTheme==='light')assert.equal(t.bg,'#ffffff');else assert.ok(contrast('#ffffff',t.bg)>=4.5);
  for(const ink of ['tx','tx2','tx3'])for(const surface of ['bg','sf','sf2','accs'])assert.ok(contrast(t[ink],t[surface])>=4.5,`${siteTheme}/${ink}/${surface}`);
  assert.ok(contrast(t.onacc,t.acc)>=4.5);assert.ok(contrast(t.tx,t.sf)>=4.5);
 }
});
test('private journey adapter explicitly bypasses payment and shared flow files remain unchanged',()=>{
 const adapter=readFileSync(new URL('../src/ui/storefront/checkout/JourneyAppearance.tsx',import.meta.url),'utf8');
 assert.match(adapter,/if \(payment\) return <ThemeScope tokens=\{legacyTokens\} className=\{shell.root\}/);
 const css=readFileSync(new URL('../src/ui/storefront/checkout/journey.module.css',import.meta.url),'utf8');
 assert.doesNotMatch(css.replace(/\/\*[\s\S]*?\*\//g,''),/payment|:root|body\s*\{/);assert.match(css,/\.journey\.journey :global\(\[data-sf-screen\]\)/);
});
