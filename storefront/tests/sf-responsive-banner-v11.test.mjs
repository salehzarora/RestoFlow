import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {syntheticV4Envelope} from './support/content-envelope.mjs';
import {SYNTH_MEDIA_PATH} from './support/envelope.mjs';
const {decodeStorefrontMenuV10,decodeStorefrontMenuV11}=await import('../src/source/live/decodeContentV1.ts');
const {adaptStorefront}=await import('../src/source/live/adapter.ts');
const origin='https://oqmevrndtivqxgyvcmwy.supabase.co',desktop=SYNTH_MEDIA_PATH.replace(/([0-9a-f]{64})\.webp$/, 'b'.repeat(64)+'.webp');
const fields={menu_banner_layout:'responsive',menu_banner_desktop_url:desktop,menu_banner_mobile_height_px:520,menu_banner_desktop_height_px:400,menu_banner_desktop_focal_x:23,menu_banner_desktop_focal_y:74,menu_banner_width:720,menu_banner_height:960,menu_banner_desktop_width:960,menu_banner_desktop_height:320};
function menu(newFields={}){const raw=syntheticV4Envelope();raw.content_v1.appearance={text_color:null,button_text_color:null,menu_banner_url:SYNTH_MEDIA_PATH,menu_banner_enabled:true,menu_intro_visible:false,menu_banner_focal_x:38,menu_banner_focal_y:9,...newFields};return raw;}
test('absence retains exact v10 decode and tenant; explicit new mode is not inferred from old image',()=>{
 const raw=menu();assert.deepEqual(decodeStorefrontMenuV11(raw),decodeStorefrontMenuV10(raw));
 const a=adaptStorefront(decodeStorefrontMenuV11(raw),origin);assert.equal(a.view.tenant.menuBanner.layout,undefined);
});
test('independent settings reach presentation only; catalog and money are identical',()=>{
 const raw=menu(fields),copy=structuredClone(raw),old=adaptStorefront(decodeStorefrontMenuV10(menu()),origin),next=adaptStorefront(decodeStorefrontMenuV11(raw),origin);
 assert.deepEqual(raw,copy);assert.equal(next.view.tenant.menuBanner.image,origin+SYNTH_MEDIA_PATH);assert.equal(next.view.tenant.menuBanner.desktopImage,origin+desktop);assert.equal(next.view.tenant.menuBanner.focalX,38);assert.equal(next.view.tenant.menuBanner.desktopFocalX,23);assert.equal(next.view.tenant.menuBanner.mobileHeightPx,520);assert.equal(next.view.tenant.menuBanner.desktopHeightPx,400);
 assert.deepEqual(next.view.items,old.view.items);assert.equal(next.taxRateBp,old.taxRateBp);assert.deepEqual(next.groups,old.groups);assert.throws(()=>decodeStorefrontMenuV10(raw));
});
test('invalid types, ranges, unknown fields and unsafe media fail closed',()=>{
 const invalid={menu_banner_layout:['new',true,1],menu_banner_mobile_height_px:[319,641,.5,'520',false],menu_banner_desktop_height_px:[239,561,.5,'400',false],menu_banner_desktop_focal_x:[-1,101,'50',false],menu_banner_desktop_url:['https://private.invalid/raw.png','/private/raw.png',false],menu_banner_width:[0,2561,'960',false]};
 for(const[key,values]of Object.entries(invalid))for(const value of values)assert.throws(()=>decodeStorefrontMenuV11(menu({...fields,[key]:value})),key+' '+value);
 assert.throws(()=>decodeStorefrontMenuV11(menu({...fields,unknown_layout_option:true})));
});
test('explicit null is auto/fallback, never an inferred new mode; dimension pairs are exact',()=>{
 const auto={...fields,menu_banner_mobile_height_px:null,menu_banner_desktop_height_px:null,menu_banner_desktop_url:null,menu_banner_desktop_width:null,menu_banner_desktop_height:null};assert.equal(decodeStorefrontMenuV11(menu(auto)).content_v1.appearance.menu_banner_desktop_url,null);
 assert.throws(()=>decodeStorefrontMenuV11(menu({...fields,menu_banner_width:null})));
 assert.throws(()=>decodeStorefrontMenuV11(menu({...fields,menu_banner_desktop_url:null})));
 assert.equal(decodeStorefrontMenuV11(menu({...fields,menu_banner_layout:null})).content_v1.appearance.menu_banner_layout,null);
});
test('published desktop companion must match base URL, dimensions, aspect and monotonic size',()=>{
 const raw=menu(fields),high=desktop.replace('b'.repeat(64),'c'.repeat(64));raw.menu_banner_desktop_images_v1={base_url:desktop,variants:[{url:desktop,width:960,height:320},{url:high,width:2172,height:724}]};assert.equal(decodeStorefrontMenuV11(raw).menu_banner_desktop_images_v1.variants.length,2);
 for(const change of[m=>m.base_url=SYNTH_MEDIA_PATH,m=>m.variants[0].width=959,m=>m.variants[1].height=800,m=>m.variants[1].url=desktop,m=>m.variants=[]]){const bad=structuredClone(raw);change(bad.menu_banner_desktop_images_v1);assert.throws(()=>decodeStorefrontMenuV11(bad));}
 assert.throws(()=>decodeStorefrontMenuV10(raw));
});
