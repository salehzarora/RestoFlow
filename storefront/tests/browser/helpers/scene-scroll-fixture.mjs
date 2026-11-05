// Synthetic v7 input for the real Next menu. Server fetches stay inside this test process.
import { syntheticV4Envelope } from '../../support/content-envelope.mjs';

const logical = 'https://oqmevrndtivqxgyvcmwy.supabase.co/rest/v1/rpc/storefront_menu_v7';
const prefix = '/storage/v1/object/public/storefront-media/' + '0'.repeat(32) + '/';
const image = letter => prefix + letter.repeat(64) + '.webp';
const id = n => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
const copy = {
  ar: 'تتغير وجبات الغداء الموسمية يومياً. اسأل فريق المطعم عن مكونات الطبق قبل الاختيار. ',
  he: 'מנות הצהריים העונתיות מתחלפות מדי יום. אפשר לשאול את צוות המסעדה על המרכיבים לפני הבחירה. ',
  en: 'Seasonal lunch specials change daily. Ask our team about ingredients and availability before choosing. ',
};
if (process.env.STOREFRONT_SOURCE !== 'live' || process.env.STOREFRONT_SUPABASE_ANON_KEY !== 'sb_publishable_SYNTHETIC_scene_scroll_only') {
  throw new Error('Scene scroll fixture is only for the local test process.');
}
const localFetch = globalThis.fetch;
globalThis.fetch = async (input, init) => {
  const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url);
  if (url.hostname === '127.0.0.1') return localFetch(input, init);
  if (url.href !== logical || init?.method !== 'POST') throw new Error('Unexpected non-fixture request');
  const slug = JSON.parse(init.body).p_slug;
  const match = /^scene-(ar|he|en)-(brand|reference)-(custom|shared|inherited)-(panel|none)-(a|b)$/.exec(slug);
  if (!match) return Response.json({ ok:false, error:'not_found', entity:'storefront_menu' });
  const [, locale, scene, source, announce] = match;
  const data = syntheticV4Envelope();
  Object.assign(data.restaurant, { slug, display_name:'Scene test', primary_color:'#33312c', accent_color:'#f3ad60',
    motion:'calm', hero_url:image(source === 'shared' || source === 'inherited' ? 'b' : 'c') });
  const word = {ar:'الموسم',he:'עונתי',en:'seasonal'}[locale].repeat(10);
  data.home_content.announcement_text = announce === 'panel' ? copy[locale].trim() + ' ' + word : null;
  data.content_v1.appearance = { text_color:null, button_text_color:null, scene_preset:scene === 'reference' ? 'reference_dark' : null,
    menu_background_url:source === 'inherited' ? null : image('b'), menu_background_dim:15 };
  data.categories = Array.from({length:5}, (_, i) => ({...data.categories[0], id:id(100+i), name:'Category '+(i+1), display_order:i}));
  data.items = data.categories.flatMap((cat,i)=>Array.from({length:3}, (_, n) => ({...data.items[0], id:id(1000+i*3+n),
    category_id:cat.id, display_order:n, name:'Meal '+(i+1)+'-'+(n+1), image_url:image('a')})));
  data.modifiers=[];data.modifier_options=[];data.product_images_v1=[];
  return Response.json(data);
};
