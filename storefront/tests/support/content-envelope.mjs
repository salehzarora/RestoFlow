import { syntheticEnvelope } from './envelope.mjs';
/** Complete synthetic defaults. Never read an environment, URL or hosted data. */
export function defaultContentV1() {
  return {schema:1,hero:{mode:'editorial',item_id:null,format:null,eyebrow:null,stamp:null,footnote:null},announcement_segments:null,promo:null,story:null,category_presentation:[],item_presentation:[]};
}
export function syntheticV4Envelope(over={}) {
  return {...syntheticEnvelope(),home_content:{hero_headline:null,hero_subline:null,announcement_text:null},featured_item_ids:[],content_v1:defaultContentV1(),...over};
}
