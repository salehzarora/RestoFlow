import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { SYNTH_IDS as ID, SYNTH_MEDIA_PATH as IMG, NOT_FOUND_ENVELOPE } from './support/envelope.mjs';
import { defaultContentV1, syntheticV4Envelope } from './support/content-envelope.mjs';
const {decodeStorefrontMenuV4}=await import('../src/source/live/decodeContentV1.ts');
const {decodeStorefrontMenuV3}=await import('../src/source/live/decodeFeaturedItems.ts');
const {EnvelopeError}=await import('../src/source/live/decode.ts');
const {adaptStorefront,liveStorefrontSource}=await import('../src/source/live/adapter.ts');
// Public identity required by the existing order-origin guard. Every source
// request below is intercepted by an in-process fetch mock; never contacted.
const ORIGIN='https://oqmevrndtivqxgyvcmwy.supabase.co';
function menu(content={},over={}){return syntheticV4Envelope({...over,content_v1:{...defaultContentV1(),...content}});}
const row=(over={})=>({category_id:ID.catFood,heading:null,blurb:null,image_url:null,image_fit:null,card_layout:'cutout',...over});
test('v4 is strictly separate; v3 remains exact and failures have no content extension',()=>{
  const m=menu(),{content_v1,...v3}=m;
  assert.equal(decodeStorefrontMenuV4(m).ok,true);assert.equal(decodeStorefrontMenuV3(v3).ok,true);
  assert.throws(()=>decodeStorefrontMenuV3(m),EnvelopeError);assert.throws(()=>decodeStorefrontMenuV4(v3),EnvelopeError);
  assert.deepEqual(decodeStorefrontMenuV4(NOT_FOUND_ENVELOPE),NOT_FOUND_ENVELOPE);
  assert.throws(()=>decodeStorefrontMenuV4({...NOT_FOUND_ENVELOPE,content_v1}),EnvelopeError);
  for(const raw of [null,[],false,{},menu({schema:2}),{...m,private_id:'not-public'},menu({unknown:null})])assert.throws(()=>decodeStorefrontMenuV4(raw),EnvelopeError);
});
test('Hero exact scalar-bound format; invalid tuples are rejected rather than normalized',()=>{
  const headline='🍔 طَعْم رائع';
  const h={...defaultContentV1().hero,format:{text:headline,highlight:{start:2,end:7},break_before:8}};
  const m=menu({hero:h},{home_content:{hero_headline:headline,hero_subline:null,announcement_text:null}});
  assert.equal(decodeStorefrontMenuV4(m).content_v1.hero.format.text,headline);
  for(const format of [{...h.format,text:'🍔 طعم رائع'},{text:headline,highlight:null,break_before:null},{text:headline,highlight:{start:3,end:7},break_before:null},{text:headline,highlight:{start:2,end:7},break_before:4},{...h.format,extra:1}])assert.throws(()=>decodeStorefrontMenuV4(menu({hero:{...h,format}},{home_content:m.home_content})),EnvelopeError);
  for(const id of [ID.orphan,ID.catFood,'00000000-0000-0000-0000-000000000099',null])assert.throws(()=>decodeStorefrontMenuV4(menu({hero:{...h,mode:'item',item_id:id,format:null}})),EnvelopeError);
  assert.equal(decodeStorefrontMenuV4(menu({hero:{...h,mode:'item',item_id:ID.soldOut,format:null}})).content_v1.hero.item_id,ID.soldOut,'soldout/no-photo Hero is truthful, not a guessed replacement');
  assert.throws(()=>decodeStorefrontMenuV4(menu({hero:{...h,item_id:ID.burger,format:null}})),EnvelopeError);
});
test('all new copy uses exact bounded plain-text domains and complete optional modules',()=>{
  for(const copy of ['مرحبا','ברוכים הבאים','<b>plain text</b>','🍔'.repeat(40)])assert.equal(decodeStorefrontMenuV4(menu({announcement_segments:[copy]})).content_v1.announcement_segments[0],copy);
  for(const value of [[],[''],[' hi'],['hello\n'],['A\u2028B'],['\ud800'],Array(7).fill('ok'),['🍔'.repeat(41)],{},false])assert.throws(()=>decodeStorefrontMenuV4(menu({announcement_segments:value})),EnvelopeError);
  const story={kicker:'Own story',title:'Restaurant title',body:'Merchant content',image_url:IMG,facts:['Own claim']};
  assert.equal(decodeStorefrontMenuV4(menu({story})).content_v1.story.body,story.body);
  for(const s of [{...story,body:null},{...story,facts:['']},{...story,facts:Array(4).fill('x')},{...story,private_source:'x'},{}])assert.throws(()=>decodeStorefrontMenuV4(menu({story:s})),EnvelopeError);
});
test('wire media and relationships reject malformed data instead of silent null repair',()=>{
  for(const path of ['https://synthetic.invalid'+IMG,'http://evil.invalid/image','/private/x','javascript:x',IMG+'?v=1',IMG+'\n',IMG+'\r\n']){
    assert.throws(()=>decodeStorefrontMenuV4(menu({category_presentation:[row({image_url:path})]})),EnvelopeError);
    const m=menu();m.items[0].image_url=path;assert.throws(()=>decodeStorefrontMenuV4(m),EnvelopeError);
  }
  for(const rows of [[row(),row()],[row({category_id:ID.catEmpty})],[row({category_id:ID.burger})],[row({card_layout:'guess'})],[row({card_layout:null})]])assert.throws(()=>decodeStorefrontMenuV4(menu({category_presentation:rows})),EnvelopeError);
  assert.throws(()=>decodeStorefrontMenuV4(menu({category_presentation:[row({category_id:ID.catFood+'\n'})]})),EnvelopeError);
  for(const rows of [[{item_id:ID.orphan,image_fit:'whole-image',card_layout:null}],[{item_id:ID.burger,image_fit:null,card_layout:null}],[{item_id:ID.cola,image_fit:null,card_layout:'cutout'},{item_id:ID.burger,image_fit:null,card_layout:'cutout'}]])assert.throws(()=>decodeStorefrontMenuV4(menu({item_presentation:rows})),EnvelopeError);
});
test('closed category/item promos use real current-menu targets and never new prices',()=>{
  const copy={kicker:'Menu',title:'Try it',body:'Our text'};
  const category={kind:'category',category_id:ID.catFood,...copy,image_url:IMG};
  const item={kind:'item',item_id:ID.burger,...copy};
  assert.equal(decodeStorefrontMenuV4(menu({promo:category})).content_v1.promo.kind,'category');
  assert.equal(decodeStorefrontMenuV4(menu({promo:item})).content_v1.promo.kind,'item');
  for(const promo of [{...category,category_id:ID.catEmpty},{...category,item_id:ID.burger},{...item,item_id:ID.soldOut},{...item,item_id:ID.cola},{...item,item_id:ID.orphan},{...item,price_minor:1},{...item,image_url:IMG},{...item,kind:'unknown'}])assert.throws(()=>decodeStorefrontMenuV4(menu({promo})),EnvelopeError);
});
test('adapter resolves presentation without mutating canonical identity, order or money',()=>{
  const old=menu(),{content_v1,...v3}=old,previous=adaptStorefront(decodeStorefrontMenuV3(v3),ORIGIN);
  const m=menu({hero:{...defaultContentV1().hero,mode:'item',item_id:ID.burger,eyebrow:'Owned'},announcement_segments:['A','B'],category_presentation:[row({heading:'Editorial heading',blurb:'Own blurb',image_url:IMG,image_fit:'whole-image'})],item_presentation:[{item_id:ID.cola,image_fit:'fill',card_layout:'standard'}],promo:{kind:'item',item_id:ID.burger,kicker:'K',title:'T',body:'B'},story:{kicker:'K',title:'T',body:'B',image_url:IMG,facts:[]}});
  const result=adaptStorefront(decodeStorefrontMenuV4(m),ORIGIN);
  assert.deepEqual(result.groups,previous.groups);assert.equal(result.menuVersion,previous.menuVersion);assert.deepEqual(result.view.tenant,previous.view.tenant);assert.deepEqual(result.view.cart,previous.view.cart);
  assert.deepEqual(result.view.items.map(({imageFit,cardLayout,...item})=>item),previous.view.items);
  assert.equal(result.view.items[0].imageFit,'whole-image');assert.equal(result.view.items[0].cardLayout,'cutout');assert.equal(result.view.items[1].imageFit,'fill');assert.equal(result.view.items[1].cardLayout,'standard');
  assert.equal(result.view.categories[0].name,previous.view.categories[0].name);assert.equal(result.view.categories[0].heading,'Editorial heading');assert.equal(result.view.categories[0].cardLayout,'cutout','item override never changes section setting');
  assert.deepEqual(result.view.modules.announcement,{text:'',segments:['A','B']});
  assert.equal(result.view.modules.promo.priceMinor,previous.view.items[0].priceMinor);assert.equal(result.view.modules.promo.image,previous.view.items[0].image);assert.equal(result.view.modules.promo.hasOptions,previous.view.items[0].hasOptions);
  const b=adaptStorefront(decodeStorefrontMenuV4(menu()),ORIGIN);assert.equal(b.view.categories[0].heading,null);assert.equal(b.view.items[0].imageFit,'fill');assert.equal(b.view.modules.story,null);
});
test('live composition requests v4 exactly once and never downgrades on old/malformed/error responses',async()=>{
  const old=globalThis.fetch,calls=[];const source=liveStorefrontSource({url:ORIGIN,anonKey:'SYNTHETIC_PUBLIC_KEY_NOT_A_REAL_SECRET'});
  try {
    globalThis.fetch=async(url,init)=>{calls.push(url);assert.equal(url,ORIGIN+'/rest/v1/rpc/storefront_menu_v4');assert.equal(init.body,JSON.stringify({p_slug:'sf-synth-a'}));return {ok:true,json:async()=>menu()};};
    assert.equal((await source.getStorefront('sf-synth-a')).view.tenant.slug,'sf-synth-a');assert.equal(calls.length,1);
    const {content_v1,...legacy}=menu();
    for(const body of [legacy,menu({schema:99}),{ok:false,error:'temporary',entity:'storefront_menu'}]){globalThis.fetch=async()=>{calls.push('only');return {ok:true,json:async()=>body};};await assert.rejects(()=>source.getStorefront('sf-synth-a'));}
    assert.equal(calls.length,4);
    globalThis.fetch=async()=>{calls.push('http');return {ok:false,status:404};};await assert.rejects(()=>source.getStorefront('sf-synth-a'),/HTTP 404/);assert.equal(calls.length,5);
  }finally{globalThis.fetch=old;}
});
