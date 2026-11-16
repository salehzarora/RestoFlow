-- BIZBOT-STOREFRONT-WELCOME-VIDEO-CONTRACT-001. LOCAL candidate only.
-- Requires responsive-banner v6/v11. New bounded video media is independent of
-- existing image catalogues, buckets, recipes and old reader response shapes.
-- MP4/H.264/AAC validation is performed by the caller-JWT Edge publisher before
-- registration/copy. SQL verifies authority, identity, bounds and actual Storage
-- metadata; it does not claim to decode media or authenticate bytes by filename.
set local lock_timeout='5s';
set local statement_timeout='60s';

create function app.storefront_welcome_video_appearance_v1(a jsonb)
returns boolean language plpgsql immutable set search_path='' as $$
begin
 if a is null then return true;end if;
 if jsonb_typeof(a) is distinct from 'object' then return false;end if;
 if a ? 'welcome_media_type' and a->'welcome_media_type'<>'null'::jsonb and
  (jsonb_typeof(a->'welcome_media_type') is distinct from 'string' or a->>'welcome_media_type' not in ('image','video')) then return false;end if;
 if a ? 'welcome_video_media_id' and a->'welcome_video_media_id'<>'null'::jsonb and
  not app.storefront_content_uuid_v1(a->'welcome_video_media_id') then return false;end if;
 return true;
end; $$;

alter table app.storefront_content_profiles
 drop constraint storefront_content_appearance_hex,
 add constraint storefront_content_appearance_hex check (
  app.storefront_welcome_video_appearance_v1(appearance) and
  appearance is null or case when jsonb_typeof(appearance)='object' then coalesce(
   app.storefront_content_keys_v1(appearance-array['font_family','menu_background_media_id','menu_background_dim','scene_preset','site_theme','menu_banner_media_id','menu_banner_enabled','menu_intro_visible','menu_banner_focal_x','menu_banner_focal_y','menu_banner_layout','menu_banner_desktop_media_id','menu_banner_mobile_height_px','menu_banner_desktop_height_px','menu_banner_desktop_focal_x','menu_banner_desktop_focal_y','welcome_media_type','welcome_video_media_id'],array['text_color','button_text_color'])
   and (appearance->'text_color'='null'::jsonb or (jsonb_typeof(appearance->'text_color')='string' and length(appearance->>'text_color')=7 and appearance->>'text_color' ~ '^#[0-9a-f]{6}$'))
   and (appearance->'button_text_color'='null'::jsonb or (jsonb_typeof(appearance->'button_text_color')='string' and length(appearance->>'button_text_color')=7 and appearance->>'button_text_color' ~ '^#[0-9a-f]{6}$'))
   and (not appearance ? 'font_family' or appearance->'font_family'='null'::jsonb or
     (jsonb_typeof(appearance->'font_family')='string' and appearance->>'font_family' in ('rubik','alexandria','system')))
   and (not appearance ? 'site_theme' or appearance->'site_theme'='null'::jsonb or
     (jsonb_typeof(appearance->'site_theme')='string' and appearance->>'site_theme' in ('light','dark')))
   and (not appearance ? 'scene_preset' or appearance->'scene_preset'='null'::jsonb or
     (jsonb_typeof(appearance->'scene_preset')='string' and appearance->>'scene_preset'='reference_dark'))
   and (not appearance ? 'menu_background_media_id' or appearance->'menu_background_media_id'='null'::jsonb
     or app.storefront_content_uuid_v1(appearance->'menu_background_media_id'))
   and (not appearance ? 'menu_background_dim' or appearance->'menu_background_dim'='null'::jsonb or
     case when jsonb_typeof(appearance->'menu_background_dim')='number' then
       (appearance->>'menu_background_dim')::numeric between 0 and 80
       and (appearance->>'menu_background_dim')::numeric=trunc((appearance->>'menu_background_dim')::numeric)
     else false end),
   false)
   and (not appearance ? 'menu_banner_media_id' or appearance->'menu_banner_media_id'='null'::jsonb or app.storefront_content_uuid_v1(appearance->'menu_banner_media_id'))
   and (not appearance ? 'menu_banner_enabled' or appearance->'menu_banner_enabled'='null'::jsonb or jsonb_typeof(appearance->'menu_banner_enabled')='boolean')
   and (not appearance ? 'menu_intro_visible' or appearance->'menu_intro_visible'='null'::jsonb or jsonb_typeof(appearance->'menu_intro_visible')='boolean')
   and (not appearance ? 'menu_banner_focal_x' or appearance->'menu_banner_focal_x'='null'::jsonb or case when jsonb_typeof(appearance->'menu_banner_focal_x')='number' then (appearance->>'menu_banner_focal_x')::numeric between 0 and 100 and (appearance->>'menu_banner_focal_x')::numeric=trunc((appearance->>'menu_banner_focal_x')::numeric) else false end)
   and (not appearance ? 'menu_banner_focal_y' or appearance->'menu_banner_focal_y'='null'::jsonb or case when jsonb_typeof(appearance->'menu_banner_focal_y')='number' then (appearance->>'menu_banner_focal_y')::numeric between 0 and 100 and (appearance->>'menu_banner_focal_y')::numeric=trunc((appearance->>'menu_banner_focal_y')::numeric) else false end)
   and (not appearance ? 'menu_banner_layout' or appearance->'menu_banner_layout'='null'::jsonb or
     (jsonb_typeof(appearance->'menu_banner_layout')='string' and appearance->>'menu_banner_layout'='responsive'))
   and (not appearance ? 'menu_banner_desktop_media_id' or appearance->'menu_banner_desktop_media_id'='null'::jsonb or app.storefront_content_uuid_v1(appearance->'menu_banner_desktop_media_id'))
   and (not appearance ? 'menu_banner_mobile_height_px' or appearance->'menu_banner_mobile_height_px'='null'::jsonb or case when jsonb_typeof(appearance->'menu_banner_mobile_height_px')='number' then (appearance->>'menu_banner_mobile_height_px')::numeric between 320 and 640 and (appearance->>'menu_banner_mobile_height_px')::numeric=trunc((appearance->>'menu_banner_mobile_height_px')::numeric) else false end)
   and (not appearance ? 'menu_banner_desktop_height_px' or appearance->'menu_banner_desktop_height_px'='null'::jsonb or case when jsonb_typeof(appearance->'menu_banner_desktop_height_px')='number' then (appearance->>'menu_banner_desktop_height_px')::numeric between 240 and 560 and (appearance->>'menu_banner_desktop_height_px')::numeric=trunc((appearance->>'menu_banner_desktop_height_px')::numeric) else false end)
   and (not appearance ? 'menu_banner_desktop_focal_x' or appearance->'menu_banner_desktop_focal_x'='null'::jsonb or case when jsonb_typeof(appearance->'menu_banner_desktop_focal_x')='number' then (appearance->>'menu_banner_desktop_focal_x')::numeric between 0 and 100 and (appearance->>'menu_banner_desktop_focal_x')::numeric=trunc((appearance->>'menu_banner_desktop_focal_x')::numeric) else false end)
   and (not appearance ? 'menu_banner_desktop_focal_y' or appearance->'menu_banner_desktop_focal_y'='null'::jsonb or case when jsonb_typeof(appearance->'menu_banner_desktop_focal_y')='number' then (appearance->>'menu_banner_desktop_focal_y')::numeric between 0 and 100 and (appearance->>'menu_banner_desktop_focal_y')::numeric=trunc((appearance->>'menu_banner_desktop_focal_y')::numeric) else false end)
 else false end
 );

-- Existing strict validator, OID and grants retained; only the optional video keys are added.
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
  if not app.storefront_welcome_video_appearance_v1(a) then
   return jsonb_build_object('error','presentation_invalid','field',case when a ? 'welcome_media_type' and a->'welcome_media_type'<>'null'::jsonb
    and (jsonb_typeof(a->'welcome_media_type') is distinct from 'string' or a->>'welcome_media_type' not in ('image','video'))
    then 'appearance.welcome_media_type' else 'appearance.welcome_video_media_id' end);
  end if;
  if jsonb_typeof(a) is distinct from 'object' then
   return jsonb_build_object('error','presentation_invalid','field','appearance');
  end if;
  if not app.storefront_content_keys_v1(a-array['font_family','menu_background_media_id','menu_background_dim','scene_preset','site_theme','menu_banner_media_id','menu_banner_enabled','menu_intro_visible','menu_banner_focal_x','menu_banner_focal_y','menu_banner_layout','menu_banner_desktop_media_id','menu_banner_mobile_height_px','menu_banner_desktop_height_px','menu_banner_desktop_focal_x','menu_banner_desktop_focal_y','welcome_media_type','welcome_video_media_id'],array['text_color','button_text_color']) then
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
  if a ? 'font_family' and a->'font_family'<>'null'::jsonb and
   (jsonb_typeof(a->'font_family') is distinct from 'string' or a->>'font_family' not in ('rubik','alexandria','system')) then
   return jsonb_build_object('error','presentation_invalid','field','appearance.font_family');
  end if;
  if a ? 'site_theme' and a->'site_theme'<>'null'::jsonb and
   (jsonb_typeof(a->'site_theme') is distinct from 'string' or a->>'site_theme' not in ('light','dark')) then
   return jsonb_build_object('error','presentation_invalid','field','appearance.site_theme');
  end if;
  if a ? 'scene_preset' and a->'scene_preset'<>'null'::jsonb and
   (jsonb_typeof(a->'scene_preset') is distinct from 'string' or a->>'scene_preset'<>'reference_dark') then
   return jsonb_build_object('error','presentation_invalid','field','appearance.scene_preset');
  end if;
  if a ? 'menu_background_media_id' and a->'menu_background_media_id'<>'null'::jsonb
   and not app.storefront_content_uuid_v1(a->'menu_background_media_id') then
   return jsonb_build_object('error','media_invalid','field','appearance.menu_background_media_id');
  end if;
  if a ? 'menu_background_dim' and a->'menu_background_dim'<>'null'::jsonb then
   if jsonb_typeof(a->'menu_background_dim') is distinct from 'number' then
    return jsonb_build_object('error','presentation_invalid','field','appearance.menu_background_dim');
   end if;
   if (a->>'menu_background_dim')::numeric not between 0 and 80
    or (a->>'menu_background_dim')::numeric<>trunc((a->>'menu_background_dim')::numeric) then
    return jsonb_build_object('error','presentation_invalid','field','appearance.menu_background_dim');
   end if;
   a:=jsonb_set(a,'{menu_background_dim}',to_jsonb((a->>'menu_background_dim')::numeric::integer));
  end if;

  if a ? 'menu_banner_media_id' and a->'menu_banner_media_id'<>'null'::jsonb and not app.storefront_content_uuid_v1(a->'menu_banner_media_id') then
   return jsonb_build_object('error','media_invalid','field','appearance.menu_banner_media_id');
  end if;
  foreach k in array array['menu_banner_enabled','menu_intro_visible'] loop
   if a ? k and a->k<>'null'::jsonb and jsonb_typeof(a->k) is distinct from 'boolean' then
    return jsonb_build_object('error','presentation_invalid','field','appearance.'||k);
   end if;
  end loop;
  foreach k in array array['menu_banner_focal_x','menu_banner_focal_y'] loop
   if a ? k and a->k<>'null'::jsonb then
    if jsonb_typeof(a->k) is distinct from 'number' then
     return jsonb_build_object('error','presentation_invalid','field','appearance.'||k);
    end if;
    if (a->>k)::numeric not between 0 and 100 or (a->>k)::numeric<>trunc((a->>k)::numeric) then
     return jsonb_build_object('error','presentation_invalid','field','appearance.'||k);
    end if;
    a:=jsonb_set(a,array[k],to_jsonb((a->>k)::numeric::integer));
   end if;
  end loop;
  -- Optional responsive presentation. Absence remains legacy, JSON null clears
  -- only that key; the existing writer merges each validated appearance key.
  if a ? 'menu_banner_layout' and a->'menu_banner_layout'<>'null'::jsonb and
   (jsonb_typeof(a->'menu_banner_layout') is distinct from 'string' or a->>'menu_banner_layout'<>'responsive') then
   return jsonb_build_object('error','presentation_invalid','field','appearance.menu_banner_layout');
  end if;
  if a ? 'menu_banner_desktop_media_id' and a->'menu_banner_desktop_media_id'<>'null'::jsonb then
   if not app.storefront_content_uuid_v1(a->'menu_banner_desktop_media_id') then
    return jsonb_build_object('error','media_invalid','field','appearance.menu_banner_desktop_media_id');
   end if;
   a:=jsonb_set(a,'{menu_banner_desktop_media_id}',to_jsonb((a->>'menu_banner_desktop_media_id')::uuid::text));
  end if;
  foreach k in array array['menu_banner_mobile_height_px','menu_banner_desktop_height_px','menu_banner_desktop_focal_x','menu_banner_desktop_focal_y'] loop
   if a ? k and a->k<>'null'::jsonb then
    if jsonb_typeof(a->k) is distinct from 'number' then
     return jsonb_build_object('error','presentation_invalid','field','appearance.'||k);
    end if;
    if (a->>k)::numeric<>trunc((a->>k)::numeric) or
     (a->>k)::numeric < (case k when 'menu_banner_mobile_height_px' then 320 when 'menu_banner_desktop_height_px' then 240 else 0 end) or
     (a->>k)::numeric > (case k when 'menu_banner_mobile_height_px' then 640 when 'menu_banner_desktop_height_px' then 560 else 100 end) then
     return jsonb_build_object('error','presentation_invalid','field','appearance.'||k);
    end if;
    a:=jsonb_set(a,array[k],to_jsonb((a->>k)::numeric::integer));
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

create table app.storefront_welcome_video_media (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete restrict,
 restaurant_id uuid not null,
 request_id uuid not null,
 created_by uuid not null,
 source_key text not null check(char_length(source_key)=114 and source_key ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.mp4$'),
 content_hash text not null check(char_length(content_hash)=64 and content_hash ~ '^[0-9a-f]{64}$'),
 object_key text not null,
 mime_type text not null default 'video/mp4' check(mime_type='video/mp4'),
 width integer not null check(width between 1 and 1920),
 height integer not null check(height between 1 and 1080),
 duration_ms integer not null check(duration_ms between 1 and 30000),
 bytes integer not null check(bytes between 1 and 20971520),
 created_at timestamptz not null default now(),
 published_at timestamptz,
 unique(organization_id,restaurant_id,request_id),
 foreign key(organization_id,restaurant_id) references public.restaurants(organization_id,id) on delete restrict,
 check(split_part(source_key,'/',1)=organization_id::text and split_part(source_key,'/',2)=restaurant_id::text),
 check(object_key=app.storefront_media_prefix(restaurant_id)||'/'||content_hash||'.mp4')
);
alter table app.storefront_welcome_video_media enable row level security;
alter table app.storefront_welcome_video_media force row level security;
revoke all on table app.storefront_welcome_video_media from public,anon,authenticated,service_role;

create function app.storefront_welcome_video_can_manage_v1(p_org uuid,p_restaurant uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select app.current_app_user_id() is not null and
 exists(select 1 from public.restaurants r where r.id=p_restaurant and r.organization_id=p_org and r.deleted_at is null)
 and app.actor_rank_in_scope(p_org,p_restaurant,null)>=2;
$$;
create function app.storefront_welcome_video_source_allowed_v1(p_name text)
returns boolean language plpgsql stable security definer set search_path='' as $$
begin
 if p_name is null or char_length(p_name)<>114 or
  p_name !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.mp4$' then return false;end if;
 return app.storefront_welcome_video_can_manage_v1(split_part(p_name,'/',1)::uuid,split_part(p_name,'/',2)::uuid);
end; $$;
create function app.storefront_welcome_video_public_write_v1(p_name text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from app.storefront_welcome_video_media m where m.object_key=p_name
  and app.storefront_welcome_video_can_manage_v1(m.organization_id,m.restaurant_id));
$$;

-- No UPDATE/DELETE on either new bucket. Each upload uses a fresh immutable key.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('storefront-welcome-video-originals','storefront-welcome-video-originals',false,20971520,array['video/mp4']),
 ('storefront-welcome-videos','storefront-welcome-videos',true,20971520,array['video/mp4']);
create policy storefront_welcome_video_original_select on storage.objects for select to authenticated
 using(bucket_id='storefront-welcome-video-originals' and app.storefront_welcome_video_source_allowed_v1(name));
create policy storefront_welcome_video_original_insert on storage.objects for insert to authenticated
 with check(bucket_id='storefront-welcome-video-originals' and app.storefront_welcome_video_source_allowed_v1(name));
create policy storefront_welcome_video_public_select on storage.objects for select to authenticated
 using(bucket_id='storefront-welcome-videos' and app.storefront_welcome_video_public_write_v1(name));
create policy storefront_welcome_video_public_insert on storage.objects for insert to authenticated
 with check(bucket_id='storefront-welcome-videos' and app.storefront_welcome_video_public_write_v1(name));

create function app.storefront_welcome_video_media_json_v1(m app.storefront_welcome_video_media)
returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('id',(m).id,'object_key',(m).object_key,'content_hash',(m).content_hash,'mime_type',(m).mime_type,
  'width',(m).width,'height',(m).height,'duration_ms',(m).duration_ms,'bytes',(m).bytes,
  'published',(m).published_at is not null and exists(select 1 from storage.objects o where o.bucket_id='storefront-welcome-videos'
    and o.name=(m).object_key and o.metadata->>'mimetype'='video/mp4' and o.metadata->>'size'=(m).bytes::text),
  'url',case when (m).published_at is not null and exists(select 1 from storage.objects o where o.bucket_id='storefront-welcome-videos'
    and o.name=(m).object_key and o.metadata->>'mimetype'='video/mp4' and o.metadata->>'size'=(m).bytes::text)
   then '/storage/v1/object/public/storefront-welcome-videos/'||(m).object_key else null end);
$$;
create function app.storefront_welcome_video_selected_v1(p_org uuid,p_restaurant uuid,p_media uuid)
returns jsonb language sql stable set search_path='' as $$
 select (app.storefront_welcome_video_media_json_v1(m)-array['id','object_key','content_hash','published'])
 from app.storefront_welcome_video_media m where m.id=p_media and m.organization_id=p_org and m.restaurant_id=p_restaurant
  and m.published_at is not null and (app.storefront_welcome_video_media_json_v1(m)->>'published')::boolean;
$$;

create function app.preflight_storefront_welcome_video_v1(p_organization_id uuid,p_restaurant_id uuid,p_source_key text,p_request_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare o storage.objects%rowtype;m app.storefront_welcome_video_media%rowtype;c_entity constant text:='storefront_welcome_video';
begin
 if not app.storefront_welcome_video_can_manage_v1(p_organization_id,p_restaurant_id) then return jsonb_build_object('ok',false,'error','permission_denied','entity',c_entity);end if;
 if p_request_id is null then return jsonb_build_object('ok',false,'error','invalid','field','request_id','entity',c_entity);end if;
 if not app.storefront_welcome_video_source_allowed_v1(p_source_key) or split_part(p_source_key,'/',1)<>p_organization_id::text or split_part(p_source_key,'/',2)<>p_restaurant_id::text then
  return jsonb_build_object('ok',false,'error','invalid','field','source_key','entity',c_entity);end if;
 select * into o from storage.objects where bucket_id='storefront-welcome-video-originals' and name=p_source_key;
 if not found or o.metadata->>'mimetype' is distinct from 'video/mp4' or coalesce(o.metadata->>'size','') !~ '^[0-9]{1,8}$' then
  return jsonb_build_object('ok',false,'error','source_unavailable','entity',c_entity);end if;
 if (o.metadata->>'size')::integer not between 1 and 20971520 then return jsonb_build_object('ok',false,'error','source_unavailable','entity',c_entity);end if;
 select * into m from app.storefront_welcome_video_media where organization_id=p_organization_id and restaurant_id=p_restaurant_id and request_id=p_request_id;
 if found and (m.source_key<>p_source_key or m.created_by<>app.current_app_user_id()) then return jsonb_build_object('ok',false,'error','request_mismatch','entity',c_entity);end if;
 return jsonb_build_object('ok',true,'entity',c_entity,'source',jsonb_build_object('bucket','storefront-welcome-video-originals','key',p_source_key,'bytes',(o.metadata->>'size')::integer,'mime_type','video/mp4'),
  'media',case when m.id is null then null else app.storefront_welcome_video_media_json_v1(m) end);
end; $$;
create function app.register_storefront_welcome_video_v1(p_organization_id uuid,p_restaurant_id uuid,p_source_key text,p_request_id uuid,p_content_hash text,p_width integer,p_height integer,p_duration_ms integer,p_bytes integer)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare pre jsonb;m app.storefront_welcome_video_media%rowtype;c_entity constant text:='storefront_welcome_video';
begin
 pre:=app.preflight_storefront_welcome_video_v1(p_organization_id,p_restaurant_id,p_source_key,p_request_id);
 if pre->>'ok' is distinct from 'true' then return pre;end if;
 if p_content_hash is null or char_length(p_content_hash)<>64 or p_content_hash !~ '^[0-9a-f]{64}$' then return jsonb_build_object('ok',false,'error','invalid','field','content_hash','entity',c_entity);end if;
 if p_width is null or p_width not between 1 and 1920 then return jsonb_build_object('ok',false,'error','invalid','field','width','entity',c_entity);end if;
 if p_height is null or p_height not between 1 and 1080 then return jsonb_build_object('ok',false,'error','invalid','field','height','entity',c_entity);end if;
 if p_duration_ms is null or p_duration_ms not between 1 and 30000 then return jsonb_build_object('ok',false,'error','invalid','field','duration_ms','entity',c_entity);end if;
 if p_bytes is null or p_bytes not between 1 and 20971520 or p_bytes<>(pre#>>'{source,bytes}')::integer then return jsonb_build_object('ok',false,'error','invalid','field','bytes','entity',c_entity);end if;
 -- Same restaurant lock order as the existing content/profile writers.
 perform 1 from public.restaurants r where r.id=p_restaurant_id and r.organization_id=p_organization_id and r.deleted_at is null for update;
 if not found or not app.storefront_welcome_video_can_manage_v1(p_organization_id,p_restaurant_id) then return jsonb_build_object('ok',false,'error','permission_denied','entity',c_entity);end if;
 insert into app.storefront_welcome_video_media(organization_id,restaurant_id,request_id,created_by,source_key,content_hash,object_key,width,height,duration_ms,bytes)
 values(p_organization_id,p_restaurant_id,p_request_id,app.current_app_user_id(),p_source_key,p_content_hash,app.storefront_media_prefix(p_restaurant_id)||'/'||p_content_hash||'.mp4',p_width,p_height,p_duration_ms,p_bytes)
 on conflict(organization_id,restaurant_id,request_id) do nothing returning * into m;
 if m.id is null then
  select * into m from app.storefront_welcome_video_media where organization_id=p_organization_id and restaurant_id=p_restaurant_id and request_id=p_request_id for update;
  if m.created_by<>app.current_app_user_id() or m.source_key<>p_source_key or m.content_hash<>p_content_hash or m.width<>p_width or m.height<>p_height or m.duration_ms<>p_duration_ms or m.bytes<>p_bytes then
   return jsonb_build_object('ok',false,'error','request_mismatch','entity',c_entity);end if;
 else
  perform app.management_audit(p_organization_id,p_restaurant_id,null,'settings.storefront.welcome_video.registered',null,app.storefront_welcome_video_media_json_v1(m));
 end if;
 return jsonb_build_object('ok',true,'entity',c_entity,'media',app.storefront_welcome_video_media_json_v1(m));
end; $$;
create function app.publish_storefront_welcome_video_v1(p_organization_id uuid,p_restaurant_id uuid,p_media_id uuid,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare m app.storefront_welcome_video_media%rowtype;c_entity constant text:='storefront_welcome_video';
begin
 if not app.storefront_welcome_video_can_manage_v1(p_organization_id,p_restaurant_id) then return jsonb_build_object('ok',false,'error','permission_denied','entity',c_entity);end if;
 perform 1 from public.restaurants r where r.id=p_restaurant_id and r.organization_id=p_organization_id and r.deleted_at is null for update;
 if not found or not app.storefront_welcome_video_can_manage_v1(p_organization_id,p_restaurant_id) then return jsonb_build_object('ok',false,'error','permission_denied','entity',c_entity);end if;
 select * into m from app.storefront_welcome_video_media where id=p_media_id and organization_id=p_organization_id and restaurant_id=p_restaurant_id for update;
 if not found then return jsonb_build_object('ok',false,'error','not_found','entity',c_entity);end if;
 if p_request_id is null or m.request_id<>p_request_id or m.created_by<>app.current_app_user_id() then return jsonb_build_object('ok',false,'error','request_mismatch','entity',c_entity);end if;
 if not exists(select 1 from storage.objects o where o.bucket_id='storefront-welcome-videos' and o.name=m.object_key and o.metadata->>'mimetype'='video/mp4' and o.metadata->>'size'=m.bytes::text) then
  return jsonb_build_object('ok',false,'error','object_unavailable','entity',c_entity);end if;
 if m.published_at is null then
  update app.storefront_welcome_video_media set published_at=now() where id=m.id returning * into m;
  perform app.management_audit(p_organization_id,p_restaurant_id,null,'settings.storefront.welcome_video.published',null,app.storefront_welcome_video_media_json_v1(m));
 end if;
 return jsonb_build_object('ok',true,'entity',c_entity,'media',app.storefront_welcome_video_media_json_v1(m));
end; $$;
create function app.list_storefront_welcome_videos_v1(p_organization_id uuid,p_restaurant_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;c_entity constant text:='storefront_welcome_video';
begin
 if not app.storefront_welcome_video_can_manage_v1(p_organization_id,p_restaurant_id) then return jsonb_build_object('ok',false,'error','permission_denied','entity',c_entity);end if;
 select coalesce(jsonb_agg(v order by published_at desc,id),'[]'::jsonb) into rows from (
  select app.storefront_welcome_video_media_json_v1(m) v,m.published_at,m.id from app.storefront_welcome_video_media m
   where m.organization_id=p_organization_id and m.restaurant_id=p_restaurant_id and m.published_at is not null
    and (app.storefront_welcome_video_media_json_v1(m)->>'published')::boolean order by m.published_at desc,m.id limit 200) x;
 return jsonb_build_object('ok',true,'entity',c_entity,'media',rows);
end; $$;

create function app.get_restaurant_storefront_content_v7(p_organization_id uuid,p_restaurant_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb;a jsonb;v uuid;selected_branch uuid;
begin
 m:=app.get_restaurant_storefront_content_v6(p_organization_id,p_restaurant_id);
 if m->>'ok' is distinct from 'true' then return m;end if;
 selected_branch:=(m->>'storefront_branch_id')::uuid;
 select c.appearance into a from app.storefront_content_profiles c where c.organization_id=p_organization_id and c.restaurant_id=p_restaurant_id
  and c.storefront_branch_id=selected_branch and c.deleted_at is null;
 m:=jsonb_set(m,'{document,appearance,welcome_media_type}',coalesce(a->'welcome_media_type','null'::jsonb));
 v:=(a->>'welcome_video_media_id')::uuid;
 if v is not null and app.storefront_welcome_video_selected_v1(p_organization_id,p_restaurant_id,v) is null then
  m:=jsonb_set(m,'{warnings}',(m->'warnings')||jsonb_build_array(jsonb_build_object('field','appearance.welcome_video_media_id','reason','media_unavailable')));v:=null;
 end if;
 return jsonb_set(m,'{document,appearance,welcome_video_media_id}',coalesce(to_jsonb(v),'null'::jsonb));
end; $$;
create function public.get_restaurant_storefront_content_v7(p_organization_id uuid,p_restaurant_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
 select app.get_restaurant_storefront_content_v7(p_organization_id,p_restaurant_id);
$$;

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
 if d#>>'{appearance,menu_background_media_id}' is not null and
  app.storefront_content_media_url_v1(p_organization_id,p_restaurant_id,p.storefront_branch_id,(d#>>'{appearance,menu_background_media_id}')::uuid) is null then
  return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','media_invalid','field','appearance.menu_background_media_id');
 end if;
 if d#>>'{appearance,menu_banner_media_id}' is not null and
  app.storefront_content_media_url_v1(p_organization_id,p_restaurant_id,p.storefront_branch_id,(d#>>'{appearance,menu_banner_media_id}')::uuid) is null then
  return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','media_invalid','field','appearance.menu_banner_media_id');
 end if;
 if d#>>'{appearance,menu_banner_desktop_media_id}' is not null and
  app.storefront_content_media_url_v1(p_organization_id,p_restaurant_id,p.storefront_branch_id,(d#>>'{appearance,menu_banner_desktop_media_id}')::uuid) is null then
  return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','media_invalid','field','appearance.menu_banner_desktop_media_id');
 end if;
 -- Optional video selection is scoped to this restaurant, not a foreign or staged row.
 if d#>>'{appearance,welcome_video_media_id}' is not null and
  app.storefront_welcome_video_selected_v1(p_organization_id,p_restaurant_id,(d#>>'{appearance,welcome_video_media_id}')::uuid) is null then
  return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','media_invalid','field','appearance.welcome_video_media_id');
 end if;
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
 old_doc:=app.get_restaurant_storefront_content_v7(p_organization_id,p_restaurant_id)->'document';
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
  -- Merge only validated keys: older writers omit optional fields, explicit
  -- JSON null overrides clear them. Tombstoned branch content is not revived.
  appearance=case when d ? 'appearance' then
    (case when app.storefront_content_profiles.deleted_at is null then coalesce(app.storefront_content_profiles.appearance,'{}'::jsonb) else '{}'::jsonb end)||excluded.appearance
    when app.storefront_content_profiles.deleted_at is null then app.storefront_content_profiles.appearance else null end,deleted_at=null;
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
 new_doc:=app.get_restaurant_storefront_content_v7(p_organization_id,p_restaurant_id)->'document';
 perform app.management_audit(p_organization_id,p_restaurant_id,p.storefront_branch_id,'settings.storefront.content.updated',old_doc,new_doc);
 return result;
end; $$;

create function public.storefront_menu_v12(p_slug text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb;p public.restaurant_storefront_profiles%rowtype;a jsonb;video jsonb;
begin
 m:=public.storefront_menu_v11(p_slug);
 if m->>'ok' is distinct from 'true' or m#>>'{restaurant,slug}' is distinct from p_slug then return m;end if;
 select * into p from public.restaurant_storefront_profiles where slug=p_slug and is_published and deleted_at is null;
 if found then
  select c.appearance into a from app.storefront_content_profiles c where c.organization_id=p.organization_id and c.restaurant_id=p.restaurant_id and c.storefront_branch_id=p.storefront_branch_id and c.deleted_at is null;
  if a->>'welcome_media_type'='video' then video:=app.storefront_welcome_video_selected_v1(p.organization_id,p.restaurant_id,(a->>'welcome_video_media_id')::uuid);end if;
 end if;
 m:=jsonb_set(m,'{restaurant,welcome_media_type}',coalesce(a->'welcome_media_type','null'::jsonb));
 return jsonb_set(m,'{restaurant,welcome_video}',coalesce(video,'null'::jsonb));
end; $$;


-- Public management boundaries remain INVOKER; only their scoped app bodies are DEFINER.
create function public.preflight_storefront_welcome_video_v1(p_organization_id uuid,p_restaurant_id uuid,p_source_key text,p_request_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
 select app.preflight_storefront_welcome_video_v1(p_organization_id,p_restaurant_id,p_source_key,p_request_id);
$$;
create function public.register_storefront_welcome_video_v1(p_organization_id uuid,p_restaurant_id uuid,p_source_key text,p_request_id uuid,p_content_hash text,p_width integer,p_height integer,p_duration_ms integer,p_bytes integer)
returns jsonb language sql volatile security invoker set search_path='' as $$
 select app.register_storefront_welcome_video_v1(p_organization_id,p_restaurant_id,p_source_key,p_request_id,p_content_hash,p_width,p_height,p_duration_ms,p_bytes);
$$;
create function public.publish_storefront_welcome_video_v1(p_organization_id uuid,p_restaurant_id uuid,p_media_id uuid,p_request_id uuid)
returns jsonb language sql volatile security invoker set search_path='' as $$
 select app.publish_storefront_welcome_video_v1(p_organization_id,p_restaurant_id,p_media_id,p_request_id);
$$;
create function public.list_storefront_welcome_videos_v1(p_organization_id uuid,p_restaurant_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
 select app.list_storefront_welcome_videos_v1(p_organization_id,p_restaurant_id);
$$;
revoke all on function app.preflight_storefront_welcome_video_v1(uuid,uuid,text,uuid) from public,anon,authenticated,service_role;
grant execute on function app.preflight_storefront_welcome_video_v1(uuid,uuid,text,uuid) to authenticated;
alter function app.preflight_storefront_welcome_video_v1(uuid,uuid,text,uuid) owner to postgres;
revoke all on function public.preflight_storefront_welcome_video_v1(uuid,uuid,text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.preflight_storefront_welcome_video_v1(uuid,uuid,text,uuid) to authenticated;
alter function public.preflight_storefront_welcome_video_v1(uuid,uuid,text,uuid) owner to postgres;
revoke all on function app.register_storefront_welcome_video_v1(uuid,uuid,text,uuid,text,integer,integer,integer,integer) from public,anon,authenticated,service_role;
grant execute on function app.register_storefront_welcome_video_v1(uuid,uuid,text,uuid,text,integer,integer,integer,integer) to authenticated;
alter function app.register_storefront_welcome_video_v1(uuid,uuid,text,uuid,text,integer,integer,integer,integer) owner to postgres;
revoke all on function public.register_storefront_welcome_video_v1(uuid,uuid,text,uuid,text,integer,integer,integer,integer) from public,anon,authenticated,service_role;
grant execute on function public.register_storefront_welcome_video_v1(uuid,uuid,text,uuid,text,integer,integer,integer,integer) to authenticated;
alter function public.register_storefront_welcome_video_v1(uuid,uuid,text,uuid,text,integer,integer,integer,integer) owner to postgres;
revoke all on function app.publish_storefront_welcome_video_v1(uuid,uuid,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function app.publish_storefront_welcome_video_v1(uuid,uuid,uuid,uuid) to authenticated;
alter function app.publish_storefront_welcome_video_v1(uuid,uuid,uuid,uuid) owner to postgres;
revoke all on function public.publish_storefront_welcome_video_v1(uuid,uuid,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.publish_storefront_welcome_video_v1(uuid,uuid,uuid,uuid) to authenticated;
alter function public.publish_storefront_welcome_video_v1(uuid,uuid,uuid,uuid) owner to postgres;
revoke all on function app.list_storefront_welcome_videos_v1(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function app.list_storefront_welcome_videos_v1(uuid,uuid) to authenticated;
alter function app.list_storefront_welcome_videos_v1(uuid,uuid) owner to postgres;
revoke all on function public.list_storefront_welcome_videos_v1(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.list_storefront_welcome_videos_v1(uuid,uuid) to authenticated;
alter function public.list_storefront_welcome_videos_v1(uuid,uuid) owner to postgres;
revoke all on function app.get_restaurant_storefront_content_v7(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function app.get_restaurant_storefront_content_v7(uuid,uuid) to authenticated;
alter function app.get_restaurant_storefront_content_v7(uuid,uuid) owner to postgres;
revoke all on function public.get_restaurant_storefront_content_v7(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.get_restaurant_storefront_content_v7(uuid,uuid) to authenticated;
alter function public.get_restaurant_storefront_content_v7(uuid,uuid) owner to postgres;
revoke all on function public.storefront_menu_v12(text) from public,anon,authenticated,service_role;
grant execute on function public.storefront_menu_v12(text) to anon,authenticated;
alter function public.storefront_menu_v12(text) owner to postgres;
revoke all on function app.storefront_welcome_video_appearance_v1(jsonb) from public,anon,authenticated,service_role;
alter function app.storefront_welcome_video_appearance_v1(jsonb) owner to postgres;
revoke all on function app.storefront_welcome_video_can_manage_v1(uuid,uuid) from public,anon,authenticated,service_role;
alter function app.storefront_welcome_video_can_manage_v1(uuid,uuid) owner to postgres;
revoke all on function app.storefront_welcome_video_source_allowed_v1(text) from public,anon,authenticated,service_role;
grant execute on function app.storefront_welcome_video_source_allowed_v1(text) to authenticated;
alter function app.storefront_welcome_video_source_allowed_v1(text) owner to postgres;
revoke all on function app.storefront_welcome_video_public_write_v1(text) from public,anon,authenticated,service_role;
grant execute on function app.storefront_welcome_video_public_write_v1(text) to authenticated;
alter function app.storefront_welcome_video_public_write_v1(text) owner to postgres;
revoke all on function app.storefront_welcome_video_media_json_v1(app.storefront_welcome_video_media) from public,anon,authenticated,service_role;
alter function app.storefront_welcome_video_media_json_v1(app.storefront_welcome_video_media) owner to postgres;
revoke all on function app.storefront_welcome_video_selected_v1(uuid,uuid,uuid) from public,anon,authenticated,service_role;
alter function app.storefront_welcome_video_selected_v1(uuid,uuid,uuid) owner to postgres;
alter table app.storefront_welcome_video_media owner to postgres;
create index storefront_welcome_video_object_key on app.storefront_welcome_video_media(object_key);
create index storefront_welcome_video_scope_published on app.storefront_welcome_video_media(organization_id,restaurant_id,published_at desc,id);
comment on table app.storefront_welcome_video_media is 'BIZBOT-STOREFRONT-WELCOME-VIDEO-CONTRACT-001: private immutable registry for explicit caller-JWT validated video publication; no direct client table grants. SQL does not decode MP4 bytes.';
comment on function public.storefront_menu_v12(text) is 'Welcome media opt-in and selected public bounded video only; v11 projection and all legacy shapes/ACLs remain unchanged. No private source key or management media id.';
comment on function public.get_restaurant_storefront_content_v7(uuid,uuid) is 'Explicit optional welcome-media capability. Existing CAS content save and independent profile save unchanged; omitted keys preserve values, explicit null clears.';
