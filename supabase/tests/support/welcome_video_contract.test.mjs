// BIZBOT-STOREFRONT-WELCOME-VIDEO-CONTRACT-001.
// Source/lexical preservation checks only. They do not replace executing pgTAP.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { statements } from './cinematic_001b_migration_contract.mjs';
const sql=readFileSync(new URL('../../migrations/20261116160533_bizbot_storefront_welcome_video_001.sql',import.meta.url),'utf8');
const base=readFileSync(new URL('../../migrations/20261113134741_bizbot_storefront_responsive_banner_001.sql',import.meta.url),'utf8').replaceAll('\r\n','\n');
const feature=sql.replaceAll('\r\n','\n');
function body(source,name){const re=new RegExp(`create(?: or replace)? function ${name.replaceAll('.','\\.')}\\(`);const m=re.exec(source);assert.ok(m,`missing ${name}`);return source.slice(m.index,source.indexOf('$$;',m.index)+3);}
const selectedBlock=` -- Optional video selection is scoped to this restaurant, not a foreign or staged row.
 if d#>>'{appearance,welcome_video_media_id}' is not null and
  app.storefront_welcome_video_selected_v1(p_organization_id,p_restaurant_id,(d#>>'{appearance,welcome_video_media_id}')::uuid) is null then
  return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','media_invalid','field','appearance.welcome_video_media_id');
 end if;
`;
const stripWriter=(s)=>body(s,'app.set_restaurant_storefront_content_v1').replace(selectedBlock,'').replaceAll('old_doc:=app.get_restaurant_storefront_content_v7','old_doc:=app.get_restaurant_storefront_content_v6').replaceAll('new_doc:=app.get_restaurant_storefront_content_v7','new_doc:=app.get_restaurant_storefront_content_v6');
const legacyWriter=body(base,'app.set_restaurant_storefront_content_v1');
test('new writer preserves every existing authority, lock, CAS, branch, raw fingerprint, replay and merge line',()=>assert.equal(stripWriter(feature),legacyWriter));
test('writer preservation rejects planted authority, branch, idempotence and overwrite drift',()=>{for(const [from,to] of [["rank_value<2","rank_value<1"],["p.storefront_branch_id<>p_expected_storefront_branch_id","false"],["'document',p_document","'document',d"],["||excluded.appearance","||'{}'::jsonb"]]){const mutant=feature.replace(from,to);assert.notEqual(mutant,feature);assert.notEqual(stripWriter(mutant),legacyWriter);}});
test('legacy document validator changes only two optional keys and their bounded validation',()=>{const current=body(feature,'app.storefront_content_document_shape_v1').replace("'menu_banner_desktop_focal_y','welcome_media_type','welcome_video_media_id'],array['text_color'","'menu_banner_desktop_focal_y'],array['text_color'").replace("\n  if not app.storefront_welcome_video_appearance_v1(a) then\n   return jsonb_build_object('error','presentation_invalid','field',case when a ? 'welcome_media_type' and a->'welcome_media_type'<>'null'::jsonb\n    and (jsonb_typeof(a->'welcome_media_type') is distinct from 'string' or a->>'welcome_media_type' not in ('image','video'))\n    then 'appearance.welcome_media_type' else 'appearance.welcome_video_media_id' end);\n  end if;",'');assert.equal(current,body(base,'app.storefront_content_document_shape_v1'));});
test('all top-level statements are lexical and no external transaction or broad repair exists',()=>{const rows=statements(sql);assert.ok(rows.length>50);for(const row of rows){assert.doesNotMatch(row.text,/^(?:begin|commit|rollback|vacuum|alter\s+system|truncate)\b/i);}assert.doesNotMatch(sql,/\b(?:repair|include-all|service_role_key)\b/);});
test('old v6 and v11 and their grants are neither replaced nor renamed',()=>{assert.doesNotMatch(sql,/create(?: or replace)? function (?:public|app)\.get_restaurant_storefront_content_v6\(/);assert.doesNotMatch(sql,/create(?: or replace)? function public\.storefront_menu_v11\(/);assert.doesNotMatch(sql,/alter function .* rename/);assert.doesNotMatch(sql,/(?:grant|revoke).*?(?:storefront_menu_v11|get_restaurant_storefront_content_v6)/);});
test('public v12 adds only explicit mode and selected six-field video; no selection identity/source',()=>{const pub=body(feature,'public.storefront_menu_v12');assert.equal((pub.match(/public\.storefront_menu_v11\(p_slug\)/g)||[]).length,1);assert.deepEqual([...pub.matchAll(/\{restaurant,([^}]+)\}/g)].map(m=>m[1]),['slug','welcome_media_type','welcome_video']);assert.doesNotMatch(pub,/source_key|request_id|created_by|content_hash/);const selected=body(feature,'app.storefront_welcome_video_selected_v1');assert.match(selected,/array\['id','object_key','content_hash','published'\]/);});
test('new media stays private except intentional published bounded MP4, never widens old image buckets',()=>{assert.match(sql,/create table app\.storefront_welcome_video_media/);assert.match(sql,/force row level security/);assert.match(sql,/revoke all on table app\.storefront_welcome_video_media from public,anon,authenticated,service_role/);assert.doesNotMatch(sql,/grant .* on table app\.storefront_welcome_video_media/);const policies=[...sql.matchAll(/create policy ([\w]+) on storage\.objects for ([\w]+) to ([\w]+)/g)];assert.equal(policies.length,4);assert.ok(policies.every(m=>['select','insert'].includes(m[2])&&m[3]==='authenticated'));assert.doesNotMatch(sql,/insert into storage\.buckets[^;]*(?:'menu-images'|'restaurant-logos'|'storefront-media')/s);assert.match(sql,/20971520,array\['video\/mp4'\]/);});
test('all new manager RPCs expose exact grants and no service-role execution grant',()=>{for(const name of ['preflight_storefront_welcome_video_v1','register_storefront_welcome_video_v1','publish_storefront_welcome_video_v1','list_storefront_welcome_videos_v1']){assert.match(body(sql,'public.'+name),/security invoker set search_path=''/);assert.match(body(sql,'app.'+name),/security definer set search_path=''/);assert.match(sql,new RegExp(`revoke all on function public\\.${name}\\([^)]*\\) from public,anon,authenticated,service_role;`));assert.match(sql,new RegExp(`grant execute on function public\\.${name}\\([^)]*\\) to authenticated;`));}assert.doesNotMatch(sql,/grant execute[^;]*to [^;]*service_role/);});
test('selection validation is same-scope published storage proof, and old omission merge remains exact',()=>{const selected=body(feature,'app.storefront_welcome_video_selected_v1');assert.match(selected,/m\.organization_id=p_org and m\.restaurant_id=p_restaurant/);assert.match(selected,/m\.published_at is not null/);assert.match(body(feature,'app.storefront_welcome_video_media_json_v1'),/o\.metadata->>'mimetype'='video\/mp4' and o\.metadata->>'size'=\(m\)\.bytes::text/);assert.match(body(feature,'app.set_restaurant_storefront_content_v1'),/coalesce\(app\.storefront_content_profiles\.appearance,'\{\}'::jsonb\).*\|\|excluded\.appearance/s);});
test('immutable upload identity and all video bounds remain server enforced',()=>{assert.match(sql,/unique\(organization_id,restaurant_id,request_id\)/);for(const bound of ['width between 1 and 1920','height between 1 and 1080','duration_ms between 1 and 30000','bytes between 1 and 20971520'])assert.ok(sql.includes(bound));assert.match(body(feature,'app.register_storefront_welcome_video_v1'),/m\.created_by<>app\.current_app_user_id\(\).*m\.source_key<>p_source_key.*m\.content_hash<>p_content_hash.*m\.width<>p_width.*m\.height<>p_height.*m\.duration_ms<>p_duration_ms.*m\.bytes<>p_bytes/s);});

function constraint(source) { return statements(source).find(row => row.text.startsWith('alter table app.storefront_content_profiles')).text; }
function constraintPreservesGroupedBase(source) {
 const current=constraint(source);
 if (!current.includes("app.storefront_welcome_video_appearance_v1(appearance) and\n  (appearance is null or case")) return false;
 return current.replace("  app.storefront_welcome_video_appearance_v1(appearance) and\n  (appearance is null or case","  appearance is null or case")
  .replace("'menu_banner_desktop_focal_y','welcome_media_type','welcome_video_media_id'],array['text_color'","'menu_banner_desktop_focal_y'],array['text_color'")
  .replace(' else false end)\n );',' else false end\n );')===constraint(base);
}
test('actual CHECK conjunct groups the complete old predicate; an ungrouped OR mutant fails',()=>{
 assert.ok(constraintPreservesGroupedBase(feature));
 const ungrouped=feature.replace('  (appearance is null or case','  appearance is null or case').replace(' else false end)\n );',' else false end\n );');
 assert.equal(constraintPreservesGroupedBase(ungrouped),false,'helper cannot be bypassed by the object CASE branch');
});
function preservesLegacyReadProjection(source) {
 return source.replace("'menu_banner_desktop_focal_y','welcome_media_type','welcome_video_media_id'];","'menu_banner_desktop_focal_y'];")===body(base,'app.storefront_content_read_v2');
}
test('shared legacy reader changes only the two-key projection strip and rejects a leaked-key mutant',()=>{
 const current=body(feature,'app.storefront_content_read_v2');
 assert.ok(preservesLegacyReadProjection(current));
 assert.equal(preservesLegacyReadProjection(current.replace(",'welcome_media_type'",'')),false);
 assert.equal(preservesLegacyReadProjection(current.replace(",'welcome_video_media_id'",'')),false);
});
function legacyTypeRejectionFirst(source) {
 const previous=source.indexOf("if jsonb_typeof(a) is distinct from 'object' then");
 const added=source.indexOf('if not app.storefront_welcome_video_appearance_v1(a) then');
 return previous>=0 && added>previous;
}
test('old null/array/scalar appearance rejection precedes optional feature validation',()=>{
 const current=body(feature,'app.storefront_content_document_shape_v1');assert.ok(legacyTypeRejectionFirst(current));
 const oldBlock="  if jsonb_typeof(a) is distinct from 'object' then\n   return jsonb_build_object('error','presentation_invalid','field','appearance');\n  end if;";
 const moved=current.replace(oldBlock,'').replace("  if not app.storefront_content_keys_v1(a-array",oldBlock+"\n  if not app.storefront_content_keys_v1(a-array");
 assert.equal(legacyTypeRejectionFirst(moved),false,'moving old rejection after optional validation is rejected');
});
test('v7 materializes only its response appearance before adding nullable capability keys',()=>{
 const current=body(feature,'app.get_restaurant_storefront_content_v7');
 assert.match(current,/jsonb_set\(m,'\{document,appearance\}',jsonb_build_object\('text_color',null,'button_text_color',null\)\|\|/);
 assert.ok(current.indexOf("jsonb_set(m,'{document,appearance}',")<current.indexOf("jsonb_set(m,'{document,appearance,welcome_media_type}',"));
 assert.match(current,/when jsonb_typeof\(m#>'\{document,appearance\}'\)='object' then m#>'\{document,appearance\}' else '\{\}'::jsonb end/);
 assert.doesNotMatch(current,/update |insert into |delete from /);
});
