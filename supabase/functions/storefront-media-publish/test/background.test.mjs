import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { validateRequest } from '../lib/validate.mjs';
import { createHandler } from '../lib/handler.mjs';
import { backgroundObjectKey } from '../lib/background.mjs';
import { resizeBackgroundBilinear } from '../lib/background-bilinear.mjs';
import { deriver } from './engine.mjs';
import { fixture, withOrientation } from './fixtures.mjs';
import { ANON, TOKEN, URL_BASE, fakeSupabase } from './fake_supabase.mjs';

const [org, restaurant, branch, baseId, requestId, variantId] =
  Array.from({length:6}, (_, i) => '0b5e0000-0000-4000-8000-00000000000' + (i + 1));
const body = { request_id:requestId, organization_id:org, restaurant_id:restaurant, branch_id:branch,
  base_media_id:baseId, slot:'background', variant:'bg2560', base_rung:0, rung:0 };
const sourceKey = org + '/' + restaurant + '/logo/' + requestId + '.png';
const snapshot = { storage_object_id:baseId, storage_version:'1', storage_updated_at:'2026-11-05T12:00:00Z' };
const response = data => Response.json(data);
const get = 'get_storefront_background_source_v1', stage = 'stage_storefront_background_variant_v1';
const finalize = 'finalize_storefront_background_variant_v1';

test('only bounded background identifiers are accepted, and legacy slots cannot request bg2560', () => {
  assert.equal(validateRequest(body).ok,true);
  for (const field of Object.keys(body)) {
    const empty = {...body}; delete empty[field];
    assert.equal(validateRequest(empty).ok,false,field);
  }
  for (const bad of [{slot:'hero'},{variant:'w960'},{branch_id:branch+'\n'},{base_rung:5},{rung:-1},{rung:0.5},
    {source_key:sourceKey},{source_bucket:'restaurant-logos'},{source_snapshot:snapshot},{bytes:'x'},
    {base_media_id:'not-an-id'},{dimensions:[2560,1280]}]) assert.equal(validateRequest({...body,...bad}).ok,false);
});

async function setup(options={}) {
  const engine=await deriver();
  const input=await fixture(options.fixture ?? 'logo_alpha_2000x1000');
  const base=await engine.derive(input,{source:'restaurant-logos',variant:'w960',rung:0});
  const original={ok:true,base_media_id:baseId,source_bucket:'restaurant-logos',source_key:sourceKey,source_snapshot:snapshot,
    base_hash:base.sha256,base_width:base.width,base_height:base.height};
  const fake=fakeSupabase({canManage:options.canManage??true,privateObjects:new Map([['restaurant-logos/'+sourceKey,input]])});
  const calls=[], staged=[], finalized=[];
  let row;
  const handle=createHandler({supabaseUrl:URL_BASE,anonKey:ANON,engine:async()=>options.engine??engine,retireWorker(){},
    fetchImpl:async(url,init)=>{
      const path=new URL(url).pathname, op=path.split('/').at(-1);
      calls.push(op);
      assert.equal(init.headers.authorization,'Bearer '+TOKEN);
      if (op===get || op===stage || op===finalize) {
        const p=JSON.parse(init.body);
        assert.equal(p.p_organization_id,org);assert.equal(p.p_restaurant_id,restaurant);
        if(op===get) {
          assert.deepEqual(p,{p_organization_id:org,p_restaurant_id:restaurant,p_branch_id:branch,p_base_media_id:baseId});
          return response({...original,...options.source});
        }
        if(op===stage) {
          staged.push(p);
          assert.deepEqual(p.p_source_snapshot,snapshot);assert.equal(p.p_expected_base_hash,base.sha256);
          assert.equal(p.p_base_media_id,baseId);assert.equal(p.p_branch_id,branch);
          row={variant_id:variantId,base_media_id:baseId,recipe:'storefront-background-b1',variant:'bg2560',
            content_hash:p.p_content_hash,width:p.p_width,height:p.p_height,bytes:p.p_bytes,
            object_key:await backgroundObjectKey(restaurant,p.p_content_hash)};
          fake.media.set(variantId,{object_key:row.object_key});
          return response({ok:true,...row,state:fake.objects.has(row.object_key)?'published':'staged',...options.stage});
        }
        finalized.push(p);
        assert.equal(p.p_variant_id,variantId);
        assert.ok(fake.objects.has(row.object_key));
        return response({ok:true,...row,state:'published',...options.finalize});
      }
      return fake.fetchImpl(url,init);
    }});
  return {fake,calls,staged,finalized, async run(fields={}) {
    const res=await handle(new Request('http://function.test/publish',{method:'POST',
      headers:{authorization:'Bearer '+TOKEN,'content-type':'application/json'},body:JSON.stringify({...body,...fields})}));
    return {status:res.status,json:await res.json()};
  }};
}

test('real handler derives and registers one separate immutable variant, then replays without overwriting bytes',async()=>{
  const f=await setup();
  const result=await f.run();
  assert.equal(result.status,200);assert.deepEqual(Object.keys(result.json).sort(),['media','ok','recipe','rung','status']);
  const media=result.json.media;
  assert.deepEqual(media,{variant_id:variantId,base_media_id:baseId,object_key:await backgroundObjectKey(restaurant,media.content_hash),
    content_hash:'8d53f883103a5521d7f5940285f7cbe3d6afd1c79db51386fac4c52a8e39f4a2',width:2000,height:1000,bytes:30534,
    variant:'bg2560',recipe:'storefront-background-b1',state:'published'});
  assert.equal(f.fake.objects.get(media.object_key).upsert,'false');
  assert.equal(f.fake.objects.get(media.object_key).cacheControl,'max-age=31536000');
  assert.deepEqual((await f.run()).json,result.json);
  assert.equal(f.fake.uploads.created,1);assert.deepEqual(f.staged[0],f.staged[1]);
  assert.deepEqual(f.finalized[0],f.finalized[1]);
  assert.notEqual(f.staged[0].p_client_request_id,f.finalized[0].p_client_request_id);
  assert.ok(!f.calls.includes('stage_storefront_media')&&!f.calls.includes('finalize_storefront_media'));
});

test('mismatched base rung, invalid source association and unsupported native size have no public effects',async()=>{
  const f=await setup();assert.deepEqual((await f.run({base_rung:3})).json,{ok:false,status:'refused',code:'base_mismatch'});
  assert.equal(f.staged.length,0);assert.equal(f.fake.objects.size,0);
  const small=await setup({fixture:'logo_small_300x150'});
  assert.deepEqual((await small.run()).json,{ok:true,status:'not_needed'});assert.equal(small.staged.length,0);
  for(const source of [{base_media_id:variantId},{base_hash:'invalid'},{base_width:961},{source_snapshot:{}},
    {source_key:sourceKey.replace(org,branch)},{source_bucket:'menu-images',source_key:org+'/'+restaurant+'/'+requestId+'/menu_item/'+requestId+'/'+baseId+'.png'}]){
    const bad=await setup({source});assert.equal((await bad.run()).status,500);assert.equal(bad.fake.pulled,0);assert.equal(bad.staged.length,0);
    assert.ok(!bad.fake.calls.some(c=>c.path?.includes('/object/authenticated/')));
  }
  const denied=await setup({canManage:false});assert.equal((await denied.run()).status,403);assert.ok(!denied.calls.includes(get));
});

test('stage and finalize must match the actual base, content address, recipe, dimensions and state',async()=>{
  for(const changed of [{variant_id:'invalid'},{base_media_id:requestId},{content_hash:'c'.repeat(64)},
    {width:961},{height:960},{bytes:9},{variant:'w960'},{recipe:'storefront-media-c4'},{state:'retracted'},
    {object_key:'a'.repeat(32)+'/'+'f'.repeat(64)+'.webp'}]){
    const f=await setup({stage:changed});assert.equal((await f.run()).status,500);assert.equal(f.fake.objects.size,0);
    assert.equal(f.finalized.length,0);
  }
  const f=await setup({finalize:{variant_id:requestId}});assert.equal((await f.run()).status,500);
  const stale=await setup({stage:{ok:false,error:'source_stale'}});
  assert.deepEqual((await stale.run()).json,{ok:false,status:'refused',code:'source_stale'});assert.equal(stale.fake.objects.size,0);
});

test('background resize uses alpha-weighted color and never enlarges its source',()=>{
  const pixels=new Uint8Array([255,0,0,255, 0,0,255,0]);
  assert.deepEqual([...resizeBackgroundBilinear(pixels,2,1,1,1)],[255,0,0,128]);
  assert.throws(()=>resizeBackgroundBilinear(pixels,2,1,3,1),RangeError);
  assert.deepEqual([...resizeBackgroundBilinear(new Uint8Array([99,9,9,0, 6,5,9,0]),2,1,1,1)],[0,0,0,0]);
});

test('8 MiP input and EXIF portrait produce pinned high-resolution WebP goldens under the existing caps',async()=>{
  const engine=await deriver();
  const full=await engine.deriveBackground(await fixture('png_at_cap_4096x2048'),{source:'restaurant-logos',rung:0});
  assert.deepEqual([full.sha256,full.width,full.height,full.byteLength],['06b6687af1ac175ebe30e61da5f7e2061653653b4dcc278cdb71163711115dac',2560,1280,46796]);
  const jpeg=await readFile(new URL('./fixtures/prog_420_1600x1200.jpg',import.meta.url));
  const rotated=await engine.deriveBackground(withOrientation(jpeg,6),{source:'restaurant-logos',rung:0});
  assert.deepEqual([rotated.sha256,rotated.orientation,rotated.width,rotated.height,rotated.byteLength],
    ['80d39cb235b637464f4d8ca8d7cbc8d1fb834684da317deba8fe6aa772f66c51',6,1200,1600,36504]);
  await assert.rejects(engine.derive(jpeg,{variant:'bg2560',source:'restaurant-logos',rung:0}),{code:'unknown_variant'});
});


test('oversized high-resolution outputs advance one rung, refuse at the cap and never overwrite public bytes', async()=>{
  const engine=await deriver();
  const noisy=await fixture('band_none');
  const high=await engine.deriveBackground(noisy,{source:'menu-images',rung:0});
  assert.equal(high.status,'ladder_next');
  assert.equal(high.nextRung,1);
  await assert.rejects(engine.deriveBackground(noisy,{source:'menu-images',rung:4}),{code:'output_too_large'});
  const f=await setup({engine:{
    derive:engine.derive,
    deriveBackground:async()=>({status:'ladder_next',nextRung:1}),
  }});
  assert.deepEqual((await f.run()).json,{ok:false,status:'ladder_next',next_rung:1});
  assert.equal(f.staged.length,0);
  const conflict=await setup();
  const published=await conflict.run();assert.equal(published.status,200);
  const key=published.json.media.object_key;
  conflict.fake.objects.get(key).bytes=new Uint8Array([0,1,2]);
  assert.equal((await conflict.run()).status,409);
  assert.equal(conflict.fake.uploads.created,1);
  assert.deepEqual([...conflict.fake.objects.get(key).bytes],[0,1,2]);
});
