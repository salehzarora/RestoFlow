import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { syntheticV4Envelope } from './support/content-envelope.mjs';
const { decodeStorefrontMenuV11 } = await import('../src/source/live/decodeContentV1.ts');
const { decodeStorefrontMenuV12 } = await import('../src/source/live/decodeWelcomeVideo.ts');
const { fetchStorefrontMenu } = await import('../src/source/live/client.ts');
const { adaptStorefront } = await import('../src/source/live/adapter.ts');
const origin = 'https://oqmevrndtivqxgyvcmwy.supabase.co';
const media = {url:`/storage/v1/object/public/storefront-welcome-videos/${'a'.repeat(32)}/${'b'.repeat(64)}.mp4`,mime_type:'video/mp4',width:1280,height:720,duration_ms:12000,bytes:660459};
const legacy = () => {const raw=syntheticV4Envelope();raw.content_v1.appearance={text_color:null,button_text_color:null};return raw;};
const menu = (mode=null,video=null) => {const raw=legacy();raw.restaurant={...raw.restaurant,welcome_media_type:mode,welcome_video:video};return raw;};

test('welcome v12 is optional and cannot alter the old v11 projection or inputs',()=>{
 const raw=menu(),copy=structuredClone(raw),next=decodeStorefrontMenuV12(raw);
 const {welcome_media_type,welcome_video,...restaurant}=next.restaurant;
 assert.equal(welcome_media_type,null);assert.equal(welcome_video,null);
 assert.deepEqual({...next,restaurant},decodeStorefrontMenuV11(legacy()));assert.deepEqual(raw,copy);
 assert.throws(()=>decodeStorefrontMenuV11(raw));assert.throws(()=>decodeStorefrontMenuV12(legacy()));
 const failed={ok:false,entity:'storefront_menu',error:'not_found'};
 assert.deepEqual(decodeStorefrontMenuV12(failed),failed);assert.throws(()=>decodeStorefrontMenuV12({...failed,welcome_video:null}));
});
test('explicit image/video and missing video preserve catalog, prices and image identity',()=>{
 const old=adaptStorefront(decodeStorefrontMenuV11(legacy()),origin);
 for(const [mode,video] of [['image',null],['video',media],['video',null]]){
  const next=adaptStorefront(decodeStorefrontMenuV12(menu(mode,video)),origin);
  assert.deepEqual(next.view.items,old.view.items);assert.deepEqual(next.groups,old.groups);assert.equal(next.taxRateBp,old.taxRateBp);
  assert.equal(next.view.tenant.heroImage,old.view.tenant.heroImage);assert.equal(next.view.tenant.welcomeMediaType,mode);
  assert.equal(next.view.tenant.welcomeVideo?.url??null,video?origin+media.url:null);
 }
});
test('video accepts only the complete bounded published projection, never original/arbitrary URLs',()=>{
 const bad=[{},[],false,0,'video',{...media,source_key:'private'}, {...media,url:origin+media.url},
  {...media,url:media.url.replace('storefront-welcome-videos','storefront-welcome-video-originals')},
  {...media,url:media.url+'?token=private'},{...media,url:media.url.replace('.mp4','.webm')},
  {...media,mime_type:'text/html'}, {...media,width:1921},{...media,height:1081},{...media,duration_ms:30001},
  {...media,bytes:20971521},{...media,bytes:0},{...media,width:'1280'},{...media,duration_ms:2.5}];
 for(const value of bad)assert.throws(()=>decodeStorefrontMenuV12(menu('video',value)),JSON.stringify(value));
 for(const mode of ['Video','',false,1,{},undefined])assert.throws(()=>decodeStorefrontMenuV12(menu(mode,media)));
 assert.throws(()=>decodeStorefrontMenuV12(menu('image',media)));
});
test('only exact missing v12 negotiates v11 with the same deadline and public request',async()=>{
 const prior=globalThis.fetch,calls=[];
 try{
  globalThis.fetch=async(url,init)=>{calls.push({url,init});return calls.length===1?Response.json({code:'PGRST202',message:'Could not find the function public.storefront_menu_v12(p_slug) in the schema cache'},{status:404}):Response.json(legacy());};
  const result=await fetchStorefrontMenu('sf-synth-a',{url:origin,anonKey:'synthetic-publishable-key'});
  assert.equal(result.ok,true);assert.deepEqual(calls.map(c=>c.url),[origin+'/rest/v1/rpc/storefront_menu_v12',origin+'/rest/v1/rpc/storefront_menu_v11']);
  assert.equal(calls[0].init.signal,calls[1].init.signal);assert.equal(calls[0].init.body,calls[1].init.body);
  for(const reply of [Response.json({code:'PGRST202',message:'unrelated missing function'},{status:404}),Response.json({}, {status:503}),Response.json(menu('video',{...media,url:'https://private.invalid/raw.mp4'}))]){
   let count=0;globalThis.fetch=async()=>{count++;return reply;};await assert.rejects(()=>fetchStorefrontMenu('sf-synth-a',{url:origin,anonKey:'synthetic-publishable-key'}));assert.equal(count,1);
  }
 }finally{globalThis.fetch=prior;}
});
