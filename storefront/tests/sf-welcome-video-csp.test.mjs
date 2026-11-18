import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { headersFor } from '../scripts/serve-out.mjs';
const {pathToRegexp}=createRequire(import.meta.url)('next/dist/compiled/path-to-regexp');
const config=JSON.parse(readFileSync(new URL('../vercel.json',import.meta.url),'utf8'));
const legacy="default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self'; img-src 'self' data: https://oqmevrndtivqxgyvcmwy.supabase.co; font-src 'self'; connect-src 'self' https://oqmevrndtivqxgyvcmwy.supabase.co; media-src 'none'; object-src 'none'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; manifest-src 'self'; upgrade-insecure-requests";
function policies(path){return config.headers.filter(h=>pathToRegexp(h.source).test(path)).flatMap(h=>h.headers).filter(h=>h.key==='Content-Security-Policy').map(h=>h.value);}
test('only exact welcome paths admit the one published video bucket',()=>{
 for(const prefix of ['','/ar','/he','/en'])for(const suffix of ['','/']){
  const route=`${prefix}/s/synthetic${suffix}`, values=policies(route);assert.equal(values.length,1);
  assert.equal(headersFor(route)['Content-Security-Policy'],values[0]);
  assert.equal(values[0],legacy.replace("media-src 'none'",'media-src https://oqmevrndtivqxgyvcmwy.supabase.co/storage/v1/object/public/storefront-welcome-videos/'));
 }
});
test('menu, order, payment and every other route retain the exact former CSP',()=>{
 for(const prefix of ['','/ar','/he','/en'])for(const tail of ['/menu','/search','/cart','/checkout','/review','/payment','/request/123','/menu/item']){const route=`${prefix}/s/synthetic${tail}`;assert.deepEqual(policies(route),[legacy]);assert.equal(headersFor(route)['Content-Security-Policy'],legacy);}
 for(const path of ['/','/_next/static/asset.js','/api/order','/fr/s/synthetic','/s','/s/','/other'])assert.deepEqual(policies(path),[legacy]);
 const common=config.headers.find(h=>h.source==='/(.*)').headers;
 assert.equal(common.find(h=>h.key==='X-Robots-Tag').value,'noindex, nofollow');
 assert.equal(common.find(h=>h.key==='X-Frame-Options').value,'DENY');
 assert.equal(common.find(h=>h.key==='Permissions-Policy').value,'camera=(), microphone=(), geolocation=(), payment=()');
});
