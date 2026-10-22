/** v4 is a separate strict wire boundary. Server drift normalization is NOT
 * decoder repair. No network, environment, v3 endpoint retry or fixture path. */
import type { HeroFormat, ImageFit, CardLayout } from '../types';
import { contentTextValid, heroFormatValid } from '../../content/unicode';
import { EnvelopeError, type StorefrontMenuFailure } from './decode';
import { decodeStorefrontMenuV3, type StorefrontMenuV3Ok } from './decodeFeaturedItems';

export interface WireCategoryPresentation {
  readonly category_id: string; readonly heading: string|null; readonly blurb:string|null;
  readonly image_url:string|null; readonly image_fit:ImageFit|null; readonly card_layout:CardLayout|null;
}
export interface WireItemPresentation { readonly item_id:string; readonly image_fit:ImageFit|null; readonly card_layout:CardLayout|null; }
export interface WireContentV1 {
  readonly schema:1;
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
export function decodeStorefrontMenuV4(raw:unknown):StorefrontMenuV4Envelope{
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
  const o=record(content,['schema','hero','announcement_segments','promo','story','category_presentation','item_presentation'],'object');if(o.schema!==1)return reject('schema');
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
  return {...base,content_v1:{schema:1,hero,announcement_segments:segments,promo,story,category_presentation:cats,item_presentation:items}};
}
