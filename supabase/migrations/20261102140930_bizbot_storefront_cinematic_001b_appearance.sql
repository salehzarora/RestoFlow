-- BIZBOT-STOREFRONT-CINEMATIC-001B: optional presentation colors only.
-- Reuses the existing versioned content RPCs and hero_media_id image slot.
-- No endpoint, authorization, grants, RLS, media, order or payment changes.
-- Deploy readers accepting optional appearance before enabling color saves.
-- Existing documents omit appearance; legacy saves preserve stored overrides.
begin;

alter table app.storefront_content_profiles
 add column appearance jsonb,
 add constraint storefront_content_appearance_hex check (
  appearance is null or coalesce(
   app.storefront_content_keys_v1(appearance,array['text_color','button_text_color'])
   and (appearance->'text_color'='null'::jsonb or (jsonb_typeof(appearance->'text_color')='string' and length(appearance->>'text_color')=7 and appearance->>'text_color' ~ '^#[0-9a-f]{6}$'))
   and (appearance->'button_text_color'='null'::jsonb or (jsonb_typeof(appearance->'button_text_color')='string' and length(appearance->>'button_text_color')=7 and appearance->>'button_text_color' ~ '^#[0-9a-f]{6}$')),
   false)
 );

create or replace function app.storefront_content_document_shape_v1(p_document jsonb)
returns jsonb language plpgsql immutable set search_path='' as $$
declare
 d jsonb:=p_document; h jsonb; f jsonb; x jsonb; row_value jsonb; a jsonb;
 k text; value_text text; expected text[]; ids text[]; array_key text;
 s integer; e integer; b integer; headline text; max_len integer;
 c_fields constant text[]:=array['hero_headline','hero_subline','announcement_text','hero','announcement_segments','promo','story','category_presentation','item_presentation'];
begin
 if jsonb_typeof(d) is distinct from 'object' then return jsonb_build_object('error','document_not_object','field','document'); end if;
 if octet_length(d::text)>262144 then return jsonb_build_object('error','document_too_large','field','document'); end if;
 if not app.storefront_content_keys_v1(d-'appearance',c_fields) then
   if not d ?& c_fields then return jsonb_build_object('error','missing_field','field','document'); end if;
   return jsonb_build_object('error','unknown_field','field','document');
 end if;
 -- Appearance is optional for older editors. Omission never clears saved colors.
 if d ? 'appearance' then
  a:=d->'appearance';
  if not app.storefront_content_keys_v1(a,array['text_color','button_text_color']) then
   return jsonb_build_object('error','presentation_invalid','field','appearance');
  end if;
  foreach k in array array['text_color','button_text_color'] loop
   if a->k<>'null'::jsonb then
    if jsonb_typeof(a->k) is distinct from 'string' or length(a->>k)<>7 or (a->>k) !~ '^#[0-9A-Fa-f]{6}$' then
     return jsonb_build_object('error','presentation_invalid','field','appearance.'||k);
    end if;
    a:=jsonb_set(a,array[k],to_jsonb(lower(a->>k)));
   end if;
  end loop;
  d:=jsonb_set(d,'{appearance}',a);
 end if;
 foreach k in array array['hero_headline','hero_subline','announcement_text'] loop
   max_len:=case k when 'hero_headline' then 120 when 'hero_subline' then 180 else 240 end;
   if not app.storefront_content_input_text_v1(d->k,max_len,true) then return jsonb_build_object('error','text_invalid','field',k); end if;
   d:=jsonb_set(d,array[k],coalesce(to_jsonb(app.storefront_content_trim_v1(d->k)),'null'::jsonb));
 end loop;
 headline:=d->>'hero_headline'; h:=d->'hero';
 if not app.storefront_content_keys_v1(h,array['mode','item_id','format','eyebrow','stamp','footnote'])
   or jsonb_typeof(h->'mode') is distinct from 'string' or h->>'mode' not in ('editorial','item') then
   return jsonb_build_object('error','presentation_invalid','field','hero');
 end if;
 if h->'item_id'<>'null'::jsonb and not app.storefront_content_uuid_v1(h->'item_id') then return jsonb_build_object('error','target_invalid','field','hero.item_id'); end if;
 if h->>'mode'='item' and h->'item_id'='null'::jsonb then return jsonb_build_object('error','target_invalid','field','hero.item_id'); end if;
 foreach k in array array['eyebrow','stamp','footnote'] loop
   max_len:=case k when 'eyebrow' then 60 when 'stamp' then 80 else 120 end;
   if not app.storefront_content_input_text_v1(h->k,max_len,false) then return jsonb_build_object('error','text_invalid','field','hero.'||k); end if;
   h:=jsonb_set(h,array[k],coalesce(to_jsonb(app.storefront_content_trim_v1(h->k)),'null'::jsonb));
 end loop;
 f:=h->'format'; s:=null;e:=null;b:=null;
 if f<>'null'::jsonb then
   if not app.storefront_content_keys_v1(f,array['text','highlight','break_before']) or jsonb_typeof(f->'text') is distinct from 'string'
     or convert_to(f->>'text','UTF8') is distinct from convert_to(headline,'UTF8') then return jsonb_build_object('error','headline_format_invalid','field','hero.format'); end if;
   if f->'highlight'<>'null'::jsonb then
     x:=f->'highlight';
     if not app.storefront_content_keys_v1(x,array['start','end']) or jsonb_typeof(x->'start') is distinct from 'number' or jsonb_typeof(x->'end') is distinct from 'number' then return jsonb_build_object('error','headline_format_invalid','field','hero.format'); end if;
     if (x->>'start')::numeric<>trunc((x->>'start')::numeric) or (x->>'end')::numeric<>trunc((x->>'end')::numeric) or (x->>'start')::numeric not between 0 and 120 or (x->>'end')::numeric not between 0 and 120 then return jsonb_build_object('error','headline_format_invalid','field','hero.format'); end if;
     s:=(x->>'start')::numeric::integer;e:=(x->>'end')::numeric::integer;
   end if;
   if f->'break_before'<>'null'::jsonb then
     if jsonb_typeof(f->'break_before') is distinct from 'number' then return jsonb_build_object('error','headline_format_invalid','field','hero.format'); end if;
     if (f->>'break_before')::numeric<>trunc((f->>'break_before')::numeric) or (f->>'break_before')::numeric not between 0 and 120 then return jsonb_build_object('error','headline_format_invalid','field','hero.format'); end if;
     b:=(f->>'break_before')::numeric::integer;
   end if;
   if not app.storefront_content_hero_format_valid_v1(headline,s,e,b) then return jsonb_build_object('error','headline_format_invalid','field','hero.format'); end if;
   -- JSON numbers may be integral decimal/exponent spellings. Only after the
   -- strict type, integral, bounds and Unicode checks above, emit integer JSON.
   f:=jsonb_build_object('text',f->>'text','highlight',case when s is null then 'null'::jsonb else jsonb_build_object('start',s,'end',e) end,'break_before',b);
   h:=jsonb_set(h,'{format}',case when s is null and b is null then 'null'::jsonb else f end);
 end if;
 d:=jsonb_set(d,'{hero}',h);
 if d->'announcement_segments'<>'null'::jsonb then
   if jsonb_typeof(d->'announcement_segments') is distinct from 'array' then return jsonb_build_object('error','segments_invalid','field','announcement_segments'); end if;
   a:='[]';
   for x in select value from jsonb_array_elements(d->'announcement_segments') loop
     if x='null'::jsonb or not app.storefront_content_input_text_v1(x,40,false) or app.storefront_content_trim_v1(x) is null then return jsonb_build_object('error','segments_invalid','field','announcement_segments'); end if;
     a:=a||jsonb_build_array(app.storefront_content_trim_v1(x));
   end loop;
   if jsonb_array_length(a)>6 or (select coalesce(sum(char_length(v)),0) from jsonb_array_elements_text(a) x(v))>240 then return jsonb_build_object('error','segments_invalid','field','announcement_segments'); end if;
   d:=jsonb_set(d,'{announcement_segments}',case when jsonb_array_length(a)=0 then 'null'::jsonb else a end);
 end if;
 foreach array_key in array array['promo','story'] loop
   x:=d->array_key;
   if x='null'::jsonb then continue; end if;
   if array_key='story' then expected:=array['kicker','title','body','editorial_media_id','facts'];
   elsif x#>>'{target,kind}'='category' then expected:=array['target','kicker','title','body','editorial_media_id'];
   else expected:=array['target','kicker','title','body']; end if;
   if not app.storefront_content_keys_v1(x,expected) then return jsonb_build_object('error','presentation_invalid','field',array_key); end if;
   foreach k in array array['kicker','title','body'] loop
     max_len:=case k when 'kicker' then 60 when 'title' then 120 else 600 end;
     if x->k='null'::jsonb or not app.storefront_content_input_text_v1(x->k,max_len,false) or app.storefront_content_trim_v1(x->k) is null then return jsonb_build_object('error','text_invalid','field',array_key); end if;
     x:=jsonb_set(x,array[k],to_jsonb(app.storefront_content_trim_v1(x->k)));
   end loop;
   if array_key='story' or x#>>'{target,kind}'='category' then
     if not app.storefront_content_uuid_v1(x->'editorial_media_id') then return jsonb_build_object('error','media_invalid','field',array_key||'.editorial_media_id'); end if;
   end if;
   if array_key='story' then
     if jsonb_typeof(x->'facts') is distinct from 'array' then return jsonb_build_object('error','presentation_invalid','field','story'); end if;
     if jsonb_array_length(x->'facts')>3 then return jsonb_build_object('error','presentation_invalid','field','story'); end if;
     a:='[]';for row_value in select value from jsonb_array_elements(x->'facts') loop
       if row_value='null'::jsonb or not app.storefront_content_input_text_v1(row_value,80,false) or app.storefront_content_trim_v1(row_value) is null then return jsonb_build_object('error','text_invalid','field','story'); end if;
       a:=a||jsonb_build_array(app.storefront_content_trim_v1(row_value));
     end loop;x:=jsonb_set(x,'{facts}',a);
   elsif x#>>'{target,kind}'='category' then
     if not app.storefront_content_keys_v1(x->'target',array['kind','category_id']) or not app.storefront_content_uuid_v1(x#>'{target,category_id}') then return jsonb_build_object('error','target_invalid','field','promo.target'); end if;
   elsif x#>>'{target,kind}'='item' then
     if not app.storefront_content_keys_v1(x->'target',array['kind','item_id']) or not app.storefront_content_uuid_v1(x#>'{target,item_id}') then return jsonb_build_object('error','target_invalid','field','promo.target'); end if;
   else return jsonb_build_object('error','target_invalid','field','promo.target'); end if;
   d:=jsonb_set(d,array[array_key],x);
 end loop;
 foreach array_key in array array['category_presentation','item_presentation'] loop
   if jsonb_typeof(d->array_key) is distinct from 'array' then return jsonb_build_object('error','presentation_invalid','field',array_key); end if;
    if jsonb_array_length(d->array_key)>(case array_key when 'category_presentation' then 100 else 500 end) then return jsonb_build_object('error','presentation_invalid','field',array_key); end if;
   ids:='{}';a:='[]';
   for x in select value from jsonb_array_elements(d->array_key) loop
     if array_key='category_presentation' then expected:=array['category_id','heading','blurb','editorial_media_id','image_fit','card_layout'];k:='category_id';
     else expected:=array['item_id','image_fit','card_layout'];k:='item_id';end if;
     if not app.storefront_content_keys_v1(x,expected) or not app.storefront_content_uuid_v1(x->k) then return jsonb_build_object('error','presentation_invalid','field',array_key); end if;
     if x->>k=any(ids) then return jsonb_build_object('error','duplicate_id','field',array_key); end if;ids:=array_append(ids,x->>k);
     if not (x->'image_fit'='null'::jsonb or (jsonb_typeof(x->'image_fit')='string' and x->>'image_fit' in ('fill','whole-image')))
       or not (x->'card_layout'='null'::jsonb or (jsonb_typeof(x->'card_layout')='string' and x->>'card_layout' in ('standard','cutout'))) then return jsonb_build_object('error','presentation_invalid','field',array_key); end if;
     if array_key='category_presentation' then
       if x->'editorial_media_id'<>'null'::jsonb and not app.storefront_content_uuid_v1(x->'editorial_media_id') then return jsonb_build_object('error','media_invalid','field','category_presentation'); end if;
       foreach k in array array['heading','blurb'] loop
         if not app.storefront_content_input_text_v1(x->k,case k when 'heading' then 80 else 120 end,false) then return jsonb_build_object('error','text_invalid','field','category_presentation'); end if;
         x:=jsonb_set(x,array[k],coalesce(to_jsonb(app.storefront_content_trim_v1(x->k)),'null'::jsonb));
       end loop;
     end if;
     a:=a||jsonb_build_array(x);
   end loop;d:=jsonb_set(d,array[array_key],a);
 end loop;
 return jsonb_build_object('document',d);
end; $$;

create or replace function app.storefront_content_read_v1(p_org uuid,p_restaurant uuid,p_branch uuid,p_headline text,p_subline text,p_announcement text,p_catalog jsonb)
returns jsonb language plpgsql stable set search_path='' as $$
declare r app.storefront_content_profiles%rowtype; cr app.storefront_category_presentation%rowtype;
 ir app.storefront_item_presentation%rowtype; h jsonb; f jsonb:='null';promo jsonb:='null';story jsonb:='null';cats jsonb:='[]';items jsonb:='[]';warnings jsonb:='[]';
 hero_id uuid;hero_mode text;url text;heading text;blurb text;fit text;layout text;media_id uuid;entry jsonb;v_doc jsonb;
begin
 select * into r from app.storefront_content_profiles c where c.organization_id=p_org and c.restaurant_id=p_restaurant and c.storefront_branch_id=p_branch and c.deleted_at is null;
 hero_mode:=case when r.hero_mode in ('editorial','item') then r.hero_mode else 'editorial' end;
 hero_id:=r.hero_item_id;
 if (hero_mode='item' and hero_id is null) or (hero_id is not null and not app.storefront_content_item_member_v1(p_catalog,hero_id)) then
  hero_id:=null;hero_mode:='editorial';warnings:=warnings||jsonb_build_array(jsonb_build_object('field','hero.item_id','reason','relation_unavailable'));
 end if;
 if r.headline_format_text is not null then
  if convert_to(r.headline_format_text,'UTF8') is not distinct from convert_to(p_headline,'UTF8')
   and app.storefront_content_hero_format_valid_v1(p_headline,r.headline_highlight_start,r.headline_highlight_end,r.headline_break_before) then
   f:=jsonb_build_object('text',p_headline,'highlight',case when r.headline_highlight_start is null then 'null'::jsonb else jsonb_build_object('start',r.headline_highlight_start,'end',r.headline_highlight_end) end,'break_before',r.headline_break_before);
  else warnings:=warnings||jsonb_build_array(jsonb_build_object('field','hero.format','reason','legacy_value_invalid'));end if;
 end if;
 h:=jsonb_build_object('mode',hero_mode,'item_id',hero_id,'format',f,
  'eyebrow',case when app.storefront_content_text_v1(r.hero_eyebrow,60,false) then r.hero_eyebrow end,
  'stamp',case when app.storefront_content_text_v1(r.hero_stamp,80,false) then r.hero_stamp end,
  'footnote',case when app.storefront_content_text_v1(r.hero_footnote,120,false) then r.hero_footnote end);
 if not app.storefront_content_text_v1(r.hero_eyebrow,60,false) then warnings:=warnings||jsonb_build_array(jsonb_build_object('field','hero.eyebrow','reason','legacy_value_invalid'));end if;
 if not app.storefront_content_text_v1(r.hero_stamp,80,false) then warnings:=warnings||jsonb_build_array(jsonb_build_object('field','hero.stamp','reason','legacy_value_invalid'));end if;
 if not app.storefront_content_text_v1(r.hero_footnote,120,false) then warnings:=warnings||jsonb_build_array(jsonb_build_object('field','hero.footnote','reason','legacy_value_invalid'));end if;
 if r.announcement_segments is not null and not app.storefront_content_text_array_v1(r.announcement_segments,1,6,40,240) then warnings:=warnings||jsonb_build_array(jsonb_build_object('field','announcement_segments','reason','legacy_value_invalid'));end if;
 if r.promo_kind is not null then
  if r.promo_kicker is not null and r.promo_title is not null and r.promo_body is not null
    and app.storefront_content_text_v1(r.promo_kicker,60,false) and app.storefront_content_text_v1(r.promo_title,120,false) and app.storefront_content_text_v1(r.promo_body,600,false) then
   if r.promo_kind='category' and app.storefront_content_category_member_v1(p_catalog,r.promo_category_id)
     and app.storefront_content_media_url_v1(p_org,p_restaurant,p_branch,r.promo_media_id) is not null then
    promo:=jsonb_build_object('target',jsonb_build_object('kind','category','category_id',r.promo_category_id),'kicker',r.promo_kicker,'title',r.promo_title,'body',r.promo_body,'editorial_media_id',r.promo_media_id);
   elsif r.promo_kind='item' and app.storefront_content_item_member_v1(p_catalog,r.promo_item_id,true) then
    promo:=jsonb_build_object('target',jsonb_build_object('kind','item','item_id',r.promo_item_id),'kicker',r.promo_kicker,'title',r.promo_title,'body',r.promo_body);
   end if;
  end if;
  if promo='null'::jsonb then warnings:=warnings||jsonb_build_array(jsonb_build_object('field','promo','reason','relation_unavailable'));end if;
 end if;
 if r.story_media_id is not null then
  if app.storefront_content_media_url_v1(p_org,p_restaurant,p_branch,r.story_media_id) is not null
    and r.story_kicker is not null and r.story_title is not null and r.story_body is not null
    and app.storefront_content_text_v1(r.story_kicker,60,false) and app.storefront_content_text_v1(r.story_title,120,false) and app.storefront_content_text_v1(r.story_body,600,false)
    and app.storefront_content_text_array_v1(r.story_facts,0,3,80,240) then
   story:=jsonb_build_object('kicker',r.story_kicker,'title',r.story_title,'body',r.story_body,'editorial_media_id',r.story_media_id,'facts',r.story_facts);
  else warnings:=warnings||jsonb_build_array(jsonb_build_object('field','story','reason','media_unavailable'));end if;
 end if;
 if exists(select 1 from app.storefront_category_presentation c where c.organization_id=p_org and c.restaurant_id=p_restaurant and c.storefront_branch_id=p_branch and c.deleted_at is null and not app.storefront_content_category_member_v1(p_catalog,c.category_id)) then warnings:=warnings||jsonb_build_array(jsonb_build_object('field','category_presentation','reason','relation_unavailable'));end if;
 if exists(select 1 from app.storefront_item_presentation i where i.organization_id=p_org and i.restaurant_id=p_restaurant and i.storefront_branch_id=p_branch and i.deleted_at is null and not app.storefront_content_item_member_v1(p_catalog,i.item_id)) then warnings:=warnings||jsonb_build_array(jsonb_build_object('field','item_presentation','reason','relation_unavailable'));end if;
 for cr in select c.* from app.storefront_category_presentation c join jsonb_array_elements(p_catalog->'categories') with ordinality x(v,n) on x.v->>'id'=c.category_id::text
  where c.organization_id=p_org and c.restaurant_id=p_restaurant and c.storefront_branch_id=p_branch and c.deleted_at is null order by x.n loop
  if not app.storefront_content_category_member_v1(p_catalog,cr.category_id) then continue;end if;
  heading:=case when app.storefront_content_text_v1(cr.heading,80,false) then cr.heading end;blurb:=case when app.storefront_content_text_v1(cr.blurb,120,false) then cr.blurb end;
  fit:=case when cr.image_fit in ('fill','whole-image') then cr.image_fit end;layout:=case when cr.card_layout in ('standard','cutout') then cr.card_layout end;
  media_id:=case when app.storefront_content_media_url_v1(p_org,p_restaurant,p_branch,cr.editorial_media_id) is not null then cr.editorial_media_id end;
  if cr.editorial_media_id is not null and media_id is null then warnings:=warnings||jsonb_build_array(jsonb_build_object('field','category_presentation','reason','media_unavailable'));end if;
  if heading is not null or blurb is not null or media_id is not null or fit is not null or layout is not null then
   cats:=cats||jsonb_build_array(jsonb_build_object('category_id',cr.category_id,'heading',heading,'blurb',blurb,'editorial_media_id',media_id,'image_fit',fit,'card_layout',layout));
  end if;
 end loop;
 for ir in select i.* from app.storefront_item_presentation i join jsonb_array_elements(p_catalog->'items') with ordinality x(v,n) on x.v->>'id'=i.item_id::text
  where i.organization_id=p_org and i.restaurant_id=p_restaurant and i.storefront_branch_id=p_branch and i.deleted_at is null order by x.n loop
  if not app.storefront_content_item_member_v1(p_catalog,ir.item_id) then continue;end if;
  fit:=case when ir.image_fit in ('fill','whole-image') then ir.image_fit end;layout:=case when ir.card_layout in ('standard','cutout') then ir.card_layout end;
  if fit is not null or layout is not null then items:=items||jsonb_build_array(jsonb_build_object('item_id',ir.item_id,'image_fit',fit,'card_layout',layout));end if;
 end loop;
 -- Warnings never echo IDs, indexes, keys, source paths or caller values.
 select coalesce(jsonb_agg(v order by v->>'field',v->>'reason'),'[]'::jsonb) into warnings from (select distinct v from jsonb_array_elements(warnings) x(v)) q;
 v_doc:=jsonb_build_object('hero_headline',p_headline,'hero_subline',p_subline,'announcement_text',p_announcement,'hero',h,
  'announcement_segments',case when app.storefront_content_text_array_v1(r.announcement_segments,1,6,40,240) then to_jsonb(r.announcement_segments) else 'null'::jsonb end,
  'promo',promo,'story',story,'category_presentation',cats,'item_presentation',items);
 if r.appearance is not null then v_doc:=v_doc||jsonb_build_object('appearance',r.appearance);end if;
 return jsonb_build_object('document',v_doc,'warnings',warnings);
end; $$;

create or replace function app.set_restaurant_storefront_content_v1(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_expected_version integer,p_expected_storefront_branch_id uuid,p_document jsonb)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=app.current_app_user_id();rank_value integer;p public.restaurant_storefront_profiles%rowtype;
 fp text;replay jsonb;result jsonb;parsed jsonb;d jsonb;h jsonb;f jsonb;v jsonb;catalog jsonb;old_doc jsonb;new_doc jsonb;
 c_entity constant text:='restaurant_storefront_content';c_operation constant text:='set_restaurant_storefront_content_v1';
begin
 if actor is null then raise exception 'storefront content authentication required' using errcode='42501';end if;
 if p_client_request_id is null or p_organization_id is null or p_restaurant_id is null or p_expected_version is null or p_expected_version<0 or p_expected_storefront_branch_id is null then raise exception 'storefront content required input denied' using errcode='42501';end if;
 -- Check ancestry BEFORE rank1's audit, so a covering org actor cannot place
 -- an audit event under a restaurant from a different organization.
 if not exists(select 1 from public.restaurants r where r.id=p_restaurant_id and r.organization_id=p_organization_id and r.deleted_at is null) then raise exception 'storefront content scope denied' using errcode='42501';end if;
 rank_value:=app.actor_rank_in_scope(p_organization_id,p_restaurant_id,null);
 if rank_value=0 then raise exception 'storefront content authority denied' using errcode='42501';end if;
 if rank_value<2 then
  perform app.management_audit(p_organization_id,p_restaurant_id,null,'settings.storefront.content.denied',null,jsonb_build_object('setting','storefront_content'));
  return jsonb_build_object('ok',false,'error','permission_denied','entity',c_entity);
 end if;
 perform 1 from public.restaurants r where r.id=p_restaurant_id and r.organization_id=p_organization_id and r.deleted_at is null for update;
 if not found then raise exception 'storefront content scope changed' using errcode='42501';end if;
 select * into p from public.restaurant_storefront_profiles where organization_id=p_organization_id and restaurant_id=p_restaurant_id and deleted_at is null for update;
 if not found then return jsonb_build_object('ok',false,'error','not_found','entity',c_entity);end if;
 perform 1 from app.storefront_content_profiles c where c.organization_id=p_organization_id and c.restaurant_id=p_restaurant_id order by c.storefront_branch_id for update;
 perform 1 from app.storefront_category_presentation c where c.organization_id=p_organization_id and c.restaurant_id=p_restaurant_id order by c.storefront_branch_id,c.category_id for update;
 perform 1 from app.storefront_item_presentation i where i.organization_id=p_organization_id and i.restaurant_id=p_restaurant_id order by i.storefront_branch_id,i.item_id for update;
 perform 1 from public.storefront_media m where m.organization_id=p_organization_id and m.restaurant_id=p_restaurant_id order by m.id for update;
 if app.actor_rank_in_scope(p_organization_id,p_restaurant_id,null)<2 then raise exception 'storefront content authority changed' using errcode='42501';end if;
 fp:=md5(jsonb_build_object('org',p_organization_id,'restaurant',p_restaurant_id,'expected_version',p_expected_version,'expected_branch',p_expected_storefront_branch_id,'document',p_document)::text);
 replay:=app.management_idem_check(actor,p_client_request_id,c_operation,fp);
 if replay is not null then return replay;end if;
 -- Exact replay precedes NEW-request branch/CAS validation. It never restores
 -- old branch settings after a later branch change or content save.
 if p.storefront_branch_id<>p_expected_storefront_branch_id then return jsonb_build_object('ok',false,'error','branch_conflict','entity',c_entity,'version',p.version);end if;
 if p.version<>p_expected_version then return jsonb_build_object('ok',false,'error','version_conflict','entity',c_entity,'restaurant_id',p_restaurant_id,'version',p.version,'slug',p.slug,'is_published',p.is_published);end if;
 parsed:=app.storefront_content_document_shape_v1(p_document);
 if parsed ? 'error' then return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason',parsed->>'error','field',parsed->>'field');end if;
 d:=parsed->'document';h:=d->'hero';f:=h->'format';
 if not exists(select 1 from public.branches b where b.id=p.storefront_branch_id and b.organization_id=p_organization_id and b.restaurant_id=p_restaurant_id and b.status='active' and b.deleted_at is null) then return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','target_invalid','field','document');end if;
 catalog:=app.storefront_content_catalog_v1(p_organization_id,p_restaurant_id,p.storefront_branch_id);
 if h->>'item_id' is not null and not app.storefront_content_item_member_v1(catalog,(h->>'item_id')::uuid) then return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','target_invalid','field','hero.item_id');end if;
 if d->'promo'<>'null'::jsonb then
  v:=d->'promo';
  if v#>>'{target,kind}'='category' then
   if not app.storefront_content_category_member_v1(catalog,(v#>>'{target,category_id}')::uuid) then return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','target_invalid','field','promo.target');end if;
   if app.storefront_content_media_url_v1(p_organization_id,p_restaurant_id,p.storefront_branch_id,(v->>'editorial_media_id')::uuid) is null then return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','media_invalid','field','promo.editorial_media_id');end if;
  elsif not app.storefront_content_item_member_v1(catalog,(v#>>'{target,item_id}')::uuid,true) then return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','target_invalid','field','promo.target');end if;
 end if;
 if d->'story'<>'null'::jsonb and app.storefront_content_media_url_v1(p_organization_id,p_restaurant_id,p.storefront_branch_id,(d#>>'{story,editorial_media_id}')::uuid) is null then return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','media_invalid','field','story.editorial_media_id');end if;
 for v in select value from jsonb_array_elements(d->'category_presentation') loop
  if not app.storefront_content_category_member_v1(catalog,(v->>'category_id')::uuid) then return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','target_invalid','field','category_presentation');end if;
  if v->>'editorial_media_id' is not null and app.storefront_content_media_url_v1(p_organization_id,p_restaurant_id,p.storefront_branch_id,(v->>'editorial_media_id')::uuid) is null then return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','media_invalid','field','category_presentation');end if;
 end loop;
 for v in select value from jsonb_array_elements(d->'item_presentation') loop
  if not app.storefront_content_item_member_v1(catalog,(v->>'item_id')::uuid) then return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','target_invalid','field','item_presentation');end if;
 end loop;
 result:=jsonb_build_object('ok',true,'idempotent_replay',false,'entity',c_entity,'restaurant_id',p_restaurant_id,'version',p.version+1,'slug',p.slug,'is_published',p.is_published);
 replay:=app.management_claim_request(actor,p_client_request_id,c_operation,fp,result);if replay is not null then return replay;end if;
 old_doc:=app.get_restaurant_storefront_content_v1(p_organization_id,p_restaurant_id)->'document';
 -- Existing writer compatibility trigger clears OLD formatting first. The new
 -- validated tuple is installed only afterward, in this same transaction.
 update public.restaurant_storefront_profiles set hero_headline=d->>'hero_headline',hero_subline=d->>'hero_subline',announcement_text=d->>'announcement_text',version=p.version+1
  where organization_id=p_organization_id and restaurant_id=p_restaurant_id;
 insert into app.storefront_content_profiles(organization_id,restaurant_id,storefront_branch_id,hero_mode,hero_item_id,headline_format_text,headline_highlight_start,headline_highlight_end,headline_break_before,hero_eyebrow,hero_stamp,hero_footnote,announcement_segments,
  promo_kind,promo_category_id,promo_item_id,promo_media_id,promo_kicker,promo_title,promo_body,story_media_id,story_kicker,story_title,story_body,story_facts,appearance)
 values(p_organization_id,p_restaurant_id,p.storefront_branch_id,h->>'mode',(h->>'item_id')::uuid,f->>'text',(f#>>'{highlight,start}')::numeric::integer,(f#>>'{highlight,end}')::numeric::integer,(f->>'break_before')::numeric::integer,h->>'eyebrow',h->>'stamp',h->>'footnote',
  case when d->'announcement_segments'='null'::jsonb then null else array(select jsonb_array_elements_text(d->'announcement_segments')) end,
  d#>>'{promo,target,kind}',(d#>>'{promo,target,category_id}')::uuid,(d#>>'{promo,target,item_id}')::uuid,(d#>>'{promo,editorial_media_id}')::uuid,d#>>'{promo,kicker}',d#>>'{promo,title}',d#>>'{promo,body}',
  (d#>>'{story,editorial_media_id}')::uuid,d#>>'{story,kicker}',d#>>'{story,title}',d#>>'{story,body}',case when d->'story'='null'::jsonb then '{}'::text[] else array(select jsonb_array_elements_text(d#>'{story,facts}')) end,d->'appearance')
 on conflict(organization_id,restaurant_id,storefront_branch_id) do update set hero_mode=excluded.hero_mode,hero_item_id=excluded.hero_item_id,
  headline_format_text=excluded.headline_format_text,headline_highlight_start=excluded.headline_highlight_start,headline_highlight_end=excluded.headline_highlight_end,headline_break_before=excluded.headline_break_before,
  hero_eyebrow=excluded.hero_eyebrow,hero_stamp=excluded.hero_stamp,hero_footnote=excluded.hero_footnote,announcement_segments=excluded.announcement_segments,
  promo_kind=excluded.promo_kind,promo_category_id=excluded.promo_category_id,promo_item_id=excluded.promo_item_id,promo_media_id=excluded.promo_media_id,promo_kicker=excluded.promo_kicker,promo_title=excluded.promo_title,promo_body=excluded.promo_body,
  story_media_id=excluded.story_media_id,story_kicker=excluded.story_kicker,story_title=excluded.story_title,story_body=excluded.story_body,story_facts=excluded.story_facts,
  appearance=case when d ? 'appearance' then excluded.appearance when app.storefront_content_profiles.deleted_at is null then app.storefront_content_profiles.appearance else null end,deleted_at=null;
 update app.storefront_category_presentation c set deleted_at=now() where c.organization_id=p_organization_id and c.restaurant_id=p_restaurant_id and c.storefront_branch_id=p.storefront_branch_id and c.deleted_at is null
  and not exists(select 1 from jsonb_array_elements(d->'category_presentation') x(v) where x.v->>'category_id'=c.category_id::text);
 for v in select value from jsonb_array_elements(d->'category_presentation') loop
  insert into app.storefront_category_presentation(organization_id,restaurant_id,storefront_branch_id,category_id,heading,blurb,editorial_media_id,image_fit,card_layout)
  values(p_organization_id,p_restaurant_id,p.storefront_branch_id,(v->>'category_id')::uuid,v->>'heading',v->>'blurb',(v->>'editorial_media_id')::uuid,v->>'image_fit',v->>'card_layout')
  on conflict(organization_id,restaurant_id,storefront_branch_id,category_id) do update set heading=excluded.heading,blurb=excluded.blurb,editorial_media_id=excluded.editorial_media_id,image_fit=excluded.image_fit,card_layout=excluded.card_layout,deleted_at=null;
 end loop;
 update app.storefront_item_presentation i set deleted_at=now() where i.organization_id=p_organization_id and i.restaurant_id=p_restaurant_id and i.storefront_branch_id=p.storefront_branch_id and i.deleted_at is null
  and not exists(select 1 from jsonb_array_elements(d->'item_presentation') x(v) where x.v->>'item_id'=i.item_id::text);
 for v in select value from jsonb_array_elements(d->'item_presentation') loop
  insert into app.storefront_item_presentation(organization_id,restaurant_id,storefront_branch_id,item_id,image_fit,card_layout)
  values(p_organization_id,p_restaurant_id,p.storefront_branch_id,(v->>'item_id')::uuid,v->>'image_fit',v->>'card_layout')
  on conflict(organization_id,restaurant_id,storefront_branch_id,item_id) do update set image_fit=excluded.image_fit,card_layout=excluded.card_layout,deleted_at=null;
 end loop;
 new_doc:=app.get_restaurant_storefront_content_v1(p_organization_id,p_restaurant_id)->'document';
 perform app.management_audit(p_organization_id,p_restaurant_id,p.storefront_branch_id,'settings.storefront.content.updated',old_doc,new_doc);
 return result;
end; $$;

create or replace function public.storefront_menu_v4(p_slug text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb;p public.restaurant_storefront_profiles%rowtype;v jsonb;d jsonb;content jsonb;promo jsonb;story jsonb;cats jsonb;h jsonb;
begin
 m:=public.storefront_menu_v3(p_slug);if m->>'ok' is distinct from 'true' then return m;end if;
 if m#>>'{restaurant,slug}' is distinct from p_slug then return jsonb_build_object('ok',false,'error','not_found','entity','storefront_menu');end if;
 select p0.* into p from public.restaurant_storefront_profiles p0
  join public.organizations o on o.id=p0.organization_id join public.restaurants r on r.id=p0.restaurant_id and r.organization_id=p0.organization_id
  join public.branches b on b.id=p0.storefront_branch_id and b.restaurant_id=p0.restaurant_id and b.organization_id=p0.organization_id
 where p0.slug=p_slug and p0.deleted_at is null and p0.is_published and o.status='active' and o.deleted_at is null and r.status='active' and r.deleted_at is null
  and b.status='active' and b.deleted_at is null and coalesce(b.timezone,r.timezone) is not null and coalesce(r.currency_override,o.default_currency)='ILS' and (not b.tax_enabled or b.tax_mode='exclusive');
 if not found then return jsonb_build_object('ok',false,'error','not_found','entity','storefront_menu');end if;
 v:=app.storefront_content_read_v1(p.organization_id,p.restaurant_id,p.storefront_branch_id,p.hero_headline,p.hero_subline,p.announcement_text,m);d:=v->'document';h:=d->'hero';
 if h->>'mode'='editorial' then h:=jsonb_set(h,'{item_id}','null');end if;
 promo:=d->'promo';if promo<>'null'::jsonb then
  if promo#>>'{target,kind}'='category' then promo:=(promo-'target'-'editorial_media_id')||jsonb_build_object('kind','category','category_id',promo#>'{target,category_id}','image_url',app.storefront_content_media_url_v1(p.organization_id,p.restaurant_id,p.storefront_branch_id,(promo->>'editorial_media_id')::uuid));
  else promo:=(promo-'target')||jsonb_build_object('kind','item','item_id',promo#>'{target,item_id}');end if;
 end if;
 story:=d->'story';if story<>'null'::jsonb then story:=(story-'editorial_media_id')||jsonb_build_object('image_url',app.storefront_content_media_url_v1(p.organization_id,p.restaurant_id,p.storefront_branch_id,(story->>'editorial_media_id')::uuid));end if;
 select coalesce(jsonb_agg((x.v-'editorial_media_id')||jsonb_build_object('image_url',app.storefront_content_media_url_v1(p.organization_id,p.restaurant_id,p.storefront_branch_id,(x.v->>'editorial_media_id')::uuid)) order by x.n),'[]') into cats from jsonb_array_elements(d->'category_presentation') with ordinality x(v,n);
 content:=jsonb_build_object('schema',1,'hero',h,'announcement_segments',d->'announcement_segments','promo',promo,'story',story,'category_presentation',cats,'item_presentation',d->'item_presentation');
 if d ? 'appearance' then content:=content||jsonb_build_object('appearance',d->'appearance');end if;
 return m||jsonb_build_object('content_v1',content);
end; $$;

commit;
