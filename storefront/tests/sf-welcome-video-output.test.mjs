import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { auditOutput, allowedWelcomeVideoResource } from '../scripts/audit-output.mjs';
const url=`https://oqmevrndtivqxgyvcmwy.supabase.co/storage/v1/object/public/storefront-welcome-videos/${'a'.repeat(32)}/${'b'.repeat(64)}.mp4`;
test('published MP4 resource exception is limited to welcome video src with a canonical identity',()=>{
 for(const route of ['s/synthetic.html','ar/s/synthetic.html','en/s/synthetic.html','he/s/synthetic.html'])assert.equal(allowedWelcomeVideoResource('video','src',url,route),true);
 for(const route of ['s/synthetic/menu.html','s/synthetic/checkout.html','s/synthetic/review.html','s/synthetic/request/1.html','fr/s/synthetic.html'])assert.equal(allowedWelcomeVideoResource('video','src',url,route),false);
 for(const uri of [url+'?token=private',url.replace('storefront-welcome-videos','storefront-welcome-video-originals'),url.replace('.mp4','.webm'),url.replace('oqmevrndtivqxgyvcmwy.supabase.co','other.invalid')])assert.equal(allowedWelcomeVideoResource('video','src',uri,'s/synthetic.html'),false);
 for(const [tag,attr]of[['script','src'],['iframe','src'],['link','href'],['video','poster'],['form','action']])assert.equal(allowedWelcomeVideoResource(tag,attr,url,'s/synthetic.html'),false);
 const poster=url.replace('storefront-welcome-videos','storefront-media').replace('.mp4','.webp');
 assert.equal(allowedWelcomeVideoResource('video','poster',poster,'s/synthetic.html'),true);
 assert.equal(allowedWelcomeVideoResource('video','poster',poster+'?secret=token','s/synthetic.html'),false);
});
test('actual output scanner does not exempt another tag merely because a video uses the same URL',()=>{
 const dir=mkdtempSync(path.join(tmpdir(),'BIZBOT-welcome-audit-'));
 try{
  mkdirSync(path.join(dir,'s'),{recursive:true});
  const file=path.join(dir,'s/synthetic.html');
  // Resource-only fixtures: other missing-output diagnostics remain intact;
  // these synthetic snippets do not claim a complete build acceptance.
  writeFileSync(file,`<html lang="ar" dir="rtl"><video src="${url}" controls></video></html>`);
  assert.equal(auditOutput(dir).problems.some(p=>p.includes('loads off-origin resource')),false);
  writeFileSync(file,`<html lang="ar" dir="rtl"><video src="${url}" controls></video><script src="${url}"></script></html>`);
  assert.equal(auditOutput(dir).problems.filter(p=>p.includes('loads off-origin resource')).length,1);
 }finally{
  assert.ok(path.resolve(dir).startsWith(path.resolve(tmpdir())+path.sep));
  assert.ok(path.basename(dir).startsWith('BIZBOT-welcome-audit-'));
  rmSync(dir,{recursive:true,force:true});
 }
});
