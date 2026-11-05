/** v4, v5 and v6 are separate strict wire boundaries. Server drift normalization is NOT
 * decoder repair. No network, environment, v3 endpoint retry or fixture path. */
import type { HeroFormat, ImageFit, CardLayout, FontFamily, ImageVariant } from '../types';
import { contentTextValid, heroFormatValid } from '../../content/unicode';
import { EnvelopeError, type StorefrontMenuFailure } from './decode';
import { decodeStorefrontMenuV3, type StorefrontMenuV3Ok } from './decodeFeaturedItems';

export interface WireCategoryPresentation {
  readonly category_id: string; readonly heading: string|null; readonly blurb:string|null;
  readonly image_url:string|null; readonly image_fit:ImageFit|null; readonly card_layout:CardLayout|null;
}
export interface WireItemPresentation { readonly item_id:string; readonly image_fit:ImageFit|null; readonly card_layout:CardLayout|null; }
export interface WireAppearance {
  readonly text_color:string|null; readonly button_text_color:string|null;
  readonly font_family?:FontFamily|null;
  readonly menu_background_url?:string|null;
  readonly menu_background_dim?:number|null;
  readonly scene_preset?:'reference_dark'|null;
}
export interface WireContentV1 {
  readonly schema:1;
  /** Menu v5 exposes appearance; only v6 permits scene_preset. */
  readonly appearance?:WireAppearance;
  readonly hero:{ readonly mode:'editorial'|'item';readonly item_id:string|null;readonly format:HeroFormat|null;readonly eyebrow:string|null;readonly stamp:string|null;readonly footnote:string|null; };
  readonly announcement_segments:readonly string[]|null;
  readonly promo:null|{readonly kind:'category';readonly category_id:string;readonly kicker:string;readonly title:string;readonly body:string;readonly image_url:string}|{readonly kind:'item';readonly item_id:string;readonly kicker:string;readonly title:string;readonly body:string};
  readonly story:null|{readonly kicker:string;readonly title:string;readonly body:string;readonly image_url:string;readonly facts:readonly string[]};
  readonly category_presentation:readonly WireCategoryPresentation[];
  readonly item_presentation:readonly WireItemPresentation[];
}
export interface StorefrontMenuV4Ok extends StorefrontMenuV3Ok { readonly content_v1:WireContentV1; }
export type StorefrontMenuV4Envelope=StorefrontMenuV4Ok|StorefrontMenuFailure;
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const MEDIA=/^\/storage\/v1\/object\/public\/storefront-media\/[0-9a-f]{32}\/[0-9a-f]{64}\.webp$(?![\s\S])/;
const reject=(field:string):never=>{throw new EnvelopeError(`content_v1: invalid ${field}`);};
function record(v:unknown,keys:readonly string[],field:string):Record<string,unknown>{
  if(typeof v!=='object'||v===null||Array.isArray(v))return reject(field);
  const own=Object.keys(v).sort(),expected=[...keys].sort();if(own.length!==expected.length||own.some((x,i)=>x!==expected[i]))return reject(field);return v as Record<string,unknown>;
}
function text(v:unknown,max:number,field:string,nullable=false):string|null{
  if(v===null&&nullable)return null;
  if(typeof v!=='string'||v.length>max*2||!contentTextValid(v,max))return reject(field);return v;
}
function id(v:unknown,field:string):string{if(typeof v!=='string'||v.length!==36||!UUID.test(v))return reject(field);return v;}
function choice<T extends string>(v:unknown,values:readonly T[],field:string):T{if(typeof v!=='string'||!values.includes(v as T))return reject(field);return v as T;}
function fit(v:unknown,field:string):ImageFit|null{return v===null?null:choice<ImageFit>(v,['fill','whole-image'],field);}
function layout(v:unknown,field:string):CardLayout|null{return v===null?null:choice<CardLayout>(v,['standard','cutout'],field);}
function image(v:unknown,field:string,nullable=false):string|null{if(v===null&&nullable)return null;if(typeof v!=='string'||!MEDIA.test(v))return reject(field);return v;}
function integer(v:unknown,field:string):number{if(typeof v!=='number'||!Number.isSafeInteger(v))return reject(field);return v;}
function colour(v:unknown,field:string):string|null{
  if(v===null)return null;
  if(typeof v!=='string'||v.length!==7||!/^#[0-9a-fA-F]{6}$/.test(v))return reject(field);
  return v.toLowerCase();
}
function dim(v:unknown,field:string):number|null{
  if(v===null)return null;
  const value=integer(v,field);
  if(value<0||value>80)return reject(field);
  return value;
}
function array(v:unknown,max:number,field:string):unknown[]{if(!Array.isArray(v)||v.length>max)return reject(field);return v;}
function format(v:unknown,headline:string|null):HeroFormat|null{
  if(v===null)return null;const o=record(v,['text','highlight','break_before'],'hero.format');
  if(typeof o.text!=='string'||o.text!==headline||!contentTextValid(o.text,120,true))return reject('hero.format');
  let highlight:null|{start:number;end:number}=null;
  if(o.highlight!==null){const h=record(o.highlight,['start','end'],'hero.format.highlight');highlight={start:integer(h.start,'hero.format.highlight'),end:integer(h.end,'hero.format.highlight')};}
  const b=o.break_before===null?null:integer(o.break_before,'hero.format.break_before');
  if((highlight===null&&b===null)||!heroFormatValid(o.text,highlight?.start??null,highlight?.end??null,b))return reject('hero.format');
  return {text:o.text,highlight,break_before:b};
}
export type StorefrontMenuV5Ok = StorefrontMenuV4Ok;
export type StorefrontMenuV5Envelope = StorefrontMenuV5Ok|StorefrontMenuFailure;
export function decodeStorefrontMenuV4(raw:unknown):StorefrontMenuV4Envelope{
  return decodeContent(raw,false);
}
export function decodeStorefrontMenuV5(raw:unknown):StorefrontMenuV5Envelope{
  return decodeContent(raw,true);
}
export interface WireProductImages {
  readonly item_id:string; readonly w480_url:string; readonly w960_url:string;
  readonly width480:number; readonly height480:number; readonly width960:number; readonly height960:number;
}
export interface StorefrontMenuV6Ok extends StorefrontMenuV5Ok { readonly product_images_v1?:readonly WireProductImages[]; }
export type StorefrontMenuV6Envelope=StorefrontMenuV6Ok|StorefrontMenuFailure;
export function decodeStorefrontMenuV6(raw:unknown):StorefrontMenuV6Envelope{
  if(typeof raw!=='object'||raw===null||Array.isArray(raw))return reject('envelope');
  const e=raw as Record<string,unknown>;
  const {product_images_v1:variants,...rest}=e;
  const decoded=decodeContent(rest,true,true);
  if(!Object.hasOwn(e,'product_images_v1'))return decoded;
  if(!decoded.ok)return reject('product_images_v1');
  const items=new Map(decoded.items.map(item=>[item.id,item]));
  const seen=new Set<string>();
  const rows=array(variants,500,'product_images_v1').map(value=>{
    const row=record(value,['item_id','w480_url','w960_url','width480','height480','width960','height960'],'product_images_v1');
    const item_id=id(row.item_id,'product_images_v1.item_id');
    if(seen.has(item_id)||!items.has(item_id))return reject('product_images_v1.item_id');
    seen.add(item_id);
    const w480_url=image(row.w480_url,'product_images_v1.w480_url')!;
    const w960_url=image(row.w960_url,'product_images_v1.w960_url')!;
    if(w480_url!==items.get(item_id)!.image_url)return reject('product_images_v1.w480_url');
    const width480=integer(row.width480,'product_images_v1.width480'),height480=integer(row.height480,'product_images_v1.height480');
    const width960=integer(row.width960,'product_images_v1.width960'),height960=integer(row.height960,'product_images_v1.height960');
    if(width480<1||height480<1||width480>480||height480>480||width960<width480||height960<height480||width960>960||height960>960)return reject('product_images_v1.dimensions');
    return {item_id,w480_url,w960_url,width480,height480,width960,height960};
  });
  return {...decoded,product_images_v1:rows};
}
export interface WireMenuBackgroundImages {
  readonly base_url: string;
  readonly variants: readonly ImageVariant[];
}

export interface StorefrontMenuV7Ok extends StorefrontMenuV6Ok {
  readonly menu_background_images_v1?: WireMenuBackgroundImages;
}
export type StorefrontMenuV7Envelope = StorefrontMenuV7Ok | StorefrontMenuFailure;

/** v7 adds only an optional manifest for the selected editorial background. */
export function decodeStorefrontMenuV7(raw: unknown): StorefrontMenuV7Envelope {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) return reject('envelope');
  const field = 'menu_background_images_v1';
  if (!Object.hasOwn(raw, field)) return decodeStorefrontMenuV6(raw);
  const { menu_background_images_v1, ...rest } = raw as Record<string, unknown>;
  const decoded = decodeStorefrontMenuV6(rest);
  if (!decoded.ok) return reject(field);
  const manifest = record(menu_background_images_v1, ['base_url', 'variants'], field);
  const baseUrl = image(manifest.base_url, field)!;
  if (baseUrl !== decoded.content_v1.appearance?.menu_background_url) return reject(field);
  const variants = array(manifest.variants, 2, field).map((value, index) => {
    const row = record(value, ['url', 'width', 'height'], field);
    const width = integer(row.width, field), height = integer(row.height, field);
    const limit = index === 0 ? 960 : 2560;
    if (width < 1 || height < 1 || width > limit || height > limit) return reject(field);
    return { url: image(row.url, field)!, width, height };
  });
  const [base, high] = variants;
  if (!base || base.url !== baseUrl) return reject(field);
  if (high) {
    // Both copies fit the same source. Allow integer rounding of the shorter edge.
    const aspectError = Math.abs(high.width * base.height - high.height * base.width);
    if (high.url === baseUrl || high.width <= base.width || high.height < base.height ||
        aspectError > Math.max(high.width, high.height)) return reject(field);
  }
  return { ...decoded, menu_background_images_v1: { base_url: baseUrl, variants } };
}

function decodeContent(raw:unknown,allowAppearance:boolean,allowScene=false):StorefrontMenuV5Envelope{
  if(typeof raw!=='object'||raw===null||Array.isArray(raw))return reject('envelope');
  const e=raw as Record<string,unknown>;
  if(e.ok===false)return decodeStorefrontMenuV3(e) as StorefrontMenuFailure;
  if(!Object.hasOwn(e,'content_v1'))return reject('missing');
  const {content_v1:content,...rest}=e;const base=decodeStorefrontMenuV3(rest);if(!base.ok)return reject('base');
  // v3 itself remains unchanged. v4 never lets an invalid derivative be
  // silently repaired to null by the legacy adapter's mediaUrl defence.
  image(base.restaurant.logo_url,'restaurant.logo',true);image(base.restaurant.hero_url,'restaurant.hero',true);
  for(const item of base.items)image(item.image_url,'item.image',true);
  const itemMap=new Map(base.items.map(i=>[i.id,i]));const categoryMap=new Map(base.categories.map(c=>[c.id,c]));
  if(itemMap.size!==base.items.length||categoryMap.size!==base.categories.length)return reject('base identities');
  const servedItems=new Set(base.items.filter(i=>categoryMap.has(i.category_id)).map(i=>i.id));
  const populated=new Set(base.items.filter(i=>servedItems.has(i.id)).map(i=>i.category_id));
  const contentKeys=['schema','hero','announcement_segments','promo','story','category_presentation','item_presentation'];
  if(allowAppearance&&typeof content==='object'&&content!==null&&Object.hasOwn(content,'appearance'))contentKeys.push('appearance');
  const o=record(content,contentKeys,'object');if(o.schema!==1)return reject('schema');
  let appearance:WireAppearance|undefined;
  if(Object.hasOwn(o,'appearance')){
    const keys=['text_color','button_text_color'];
    for(const key of ['font_family','menu_background_url','menu_background_dim']){
      if(typeof o.appearance==='object'&&o.appearance!==null&&Object.hasOwn(o.appearance,key))keys.push(key);
    }
    if(allowScene&&typeof o.appearance==='object'&&o.appearance!==null&&Object.hasOwn(o.appearance,'scene_preset'))keys.push('scene_preset');
    const a=record(o.appearance,keys,'appearance');
    appearance={text_color:colour(a.text_color,'appearance.text_color'),button_text_color:colour(a.button_text_color,'appearance.button_text_color'),
      ...(Object.hasOwn(a,'font_family')?{font_family:a.font_family===null?null:choice<FontFamily>(a.font_family,['rubik','alexandria','system'],'appearance.font_family')}:{}),
      ...(Object.hasOwn(a,'menu_background_url')?{menu_background_url:image(a.menu_background_url,'appearance.menu_background_url',true)}:{}),
      ...(Object.hasOwn(a,'menu_background_dim')?{menu_background_dim:dim(a.menu_background_dim,'appearance.menu_background_dim')}:{}),
      ...(Object.hasOwn(a,'scene_preset')?{scene_preset:a.scene_preset===null?null:choice<'reference_dark'>(a.scene_preset,['reference_dark'],'appearance.scene_preset')}:{})};
  }
  const h=record(o.hero,['mode','item_id','format','eyebrow','stamp','footnote'],'hero');
  const mode=choice(h.mode,['editorial','item'],'hero.mode');const itemId=h.item_id===null?null:id(h.item_id,'hero.item_id');
  if(mode==='editorial'?itemId!==null:itemId===null||!servedItems.has(itemId))return reject('hero.item_id');
  const hero={mode,item_id:itemId,format:format(h.format,base.home_content.hero_headline),eyebrow:text(h.eyebrow,60,'hero.eyebrow',true),stamp:text(h.stamp,80,'hero.stamp',true),footnote:text(h.footnote,120,'hero.footnote',true)};
  let segments:readonly string[]|null=null;
  if(o.announcement_segments!==null){const list=array(o.announcement_segments,6,'segments');if(list.length===0)return reject('segments');segments=list.map(s=>text(s,40,'segments')!);if(segments.reduce((n,s)=>n+[...s].length,0)>240)return reject('segments');}
  const ordered=<T>(rows:unknown,max:number,field:string,ids:readonly string[],decode:(r:unknown)=>T,identity:(v:T)=>string):readonly T[]=>{
    let previous=-1;const result=array(rows,max,field).map(decode);for(const row of result){const at=ids.indexOf(identity(row));if(at<=previous)return reject(field);previous=at;}return result;
  };
  const cats=ordered(o.category_presentation,100,'category_presentation',base.categories.filter(c=>populated.has(c.id)).map(c=>c.id),(r)=>{
    const c=record(r,['category_id','heading','blurb','image_url','image_fit','card_layout'],'category_presentation');
    const row={category_id:id(c.category_id,'category_presentation'),heading:text(c.heading,80,'category.heading',true),blurb:text(c.blurb,120,'category.blurb',true),image_url:image(c.image_url,'category.image',true),image_fit:fit(c.image_fit,'category.fit'),card_layout:layout(c.card_layout,'category.layout')};
    if(row.heading===null&&row.blurb===null&&row.image_url===null&&row.image_fit===null&&row.card_layout===null)return reject('empty category_presentation');return row;
  },c=>c.category_id);
  const items=ordered(o.item_presentation,500,'item_presentation',base.items.filter(i=>servedItems.has(i.id)).map(i=>i.id),(r)=>{
    const i=record(r,['item_id','image_fit','card_layout'],'item_presentation');const row={item_id:id(i.item_id,'item_presentation'),image_fit:fit(i.image_fit,'item.fit'),card_layout:layout(i.card_layout,'item.layout')};if(row.image_fit===null&&row.card_layout===null)return reject('empty item_presentation');return row;
  },i=>i.item_id);
  let promo:WireContentV1['promo']=null;
  if(o.promo!==null){
    if(typeof o.promo!=='object'||Array.isArray(o.promo))return reject('promo');const kind=(o.promo as Record<string,unknown>).kind;
    const p=record(o.promo,kind==='category'?['kind','category_id','kicker','title','body','image_url']:['kind','item_id','kicker','title','body'],'promo');
    const copy={kicker:text(p.kicker,60,'promo.kicker')!,title:text(p.title,120,'promo.title')!,body:text(p.body,600,'promo.body')!};
    if(kind==='category'){const category_id=id(p.category_id,'promo.category');if(!populated.has(category_id))return reject('promo.category');promo={kind,category_id,...copy,image_url:image(p.image_url,'promo.image')!};}
    else if(kind==='item'){const item_id=id(p.item_id,'promo.item'),i=itemMap.get(item_id);if(!servedItems.has(item_id)||!i||i.availability!=='available'||!i.image_url||!MEDIA.test(i.image_url))return reject('promo.item');promo={kind,item_id,...copy};}
    else return reject('promo.kind');
  }
  let story:WireContentV1['story']=null;
  if(o.story!==null){const s=record(o.story,['kicker','title','body','image_url','facts'],'story');story={kicker:text(s.kicker,60,'story.kicker')!,title:text(s.title,120,'story.title')!,body:text(s.body,600,'story.body')!,image_url:image(s.image_url,'story.image')!,facts:array(s.facts,3,'story.facts').map(f=>text(f,80,'story.facts')!)};}
  return {...base,content_v1:{schema:1,hero,announcement_segments:segments,promo,story,category_presentation:cats,item_presentation:items,...(appearance===undefined?{}:{appearance})}};
}
