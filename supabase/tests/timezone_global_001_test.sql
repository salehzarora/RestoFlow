-- ============================================================================
-- TIMEZONE-GLOBAL-001 — pgTAP: PER-EVENT branch-local audit timestamps + day
-- windows (DST-correct, no fixed offset), and the global IANA catalog RPC
-- app.list_timezones (authenticated-only). occurred_at stays absolute UTC in
-- storage; only the DISPLAY string is branch-local.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(29);

-- ===== app.list_timezones — the global IANA catalog ==========================
-- 1-3. Asia/Jerusalem present; Asia/Gaza + Asia/Hebron still available;
--      representative zones from every continent available (realistic global).
select ok(
  exists (select 1 from jsonb_array_elements(app.list_timezones() -> 'zones') z where z ->> 'id' = 'Asia/Jerusalem'),
  'list_timezones includes Asia/Jerusalem');
select ok(
  (select count(*) from jsonb_array_elements(app.list_timezones() -> 'zones') z where z ->> 'id' in ('Asia/Gaza','Asia/Hebron')) = 2,
  'list_timezones still includes Asia/Gaza and Asia/Hebron');
select ok(
  (select count(*) from jsonb_array_elements(app.list_timezones() -> 'zones') z
     where z ->> 'id' in ('Europe/London','Europe/Berlin','America/New_York','America/Los_Angeles','Asia/Tokyo','Australia/Sydney','Africa/Cairo')) = 7,
  'list_timezones includes representative zones from Europe/America/Asia/Africa/Australia');
-- 4. it excludes non-canonical aliases (Etc/, posix/, SystemV/) and bare legacy ids.
select ok(
  not exists (select 1 from jsonb_array_elements(app.list_timezones() -> 'zones') z
              where z ->> 'id' like 'Etc/%' or z ->> 'id' like 'posix/%' or z ->> 'id' not like '%/%'),
  'list_timezones is filtered to canonical Region/City ids');
-- 5. each entry carries an integer offset (for the picker''s "(UTC±HH:MM)" label).
select ok(
  (select bool_and(jsonb_typeof(z -> 'offset_minutes') = 'number') from jsonb_array_elements(app.list_timezones() -> 'zones') z),
  'every catalog entry has a numeric offset_minutes');

-- ===== DST-correct conversion (no fixed offset) ==============================
-- 6/7. Asia/Jerusalem is UTC+3 in summer (IDT) and UTC+2 in winter (IST) — the
--      SAME mechanism (AT TIME ZONE over the IANA db) the RPC uses. Proves NO
--      hardcoded offset: summer and winter differ.
select is(to_char(timestamptz '2026-07-01 12:00:00+00' at time zone 'Asia/Jerusalem', 'HH24:MI'), '15:00',
  'Asia/Jerusalem summer (IDT) = UTC+3');
select is(to_char(timestamptz '2026-01-01 12:00:00+00' at time zone 'Asia/Jerusalem', 'HH24:MI'), '14:00',
  'Asia/Jerusalem winter (IST) = UTC+2');
-- 8. the autumn DST transition is handled by the tz database (still +3 mid-Oct,
--    +2 in Nov) — a fixed-offset model could not produce both.
select ok(
  to_char(timestamptz '2026-10-20 12:00:00+00' at time zone 'Asia/Jerusalem', 'HH24:MI') = '15:00'
  and to_char(timestamptz '2026-11-10 12:00:00+00' at time zone 'Asia/Jerusalem', 'HH24:MI') = '14:00',
  'the Asia/Jerusalem autumn DST transition is applied (Oct=+3, Nov=+2)');

-- ===== fixtures: org with a Jerusalem + a Tokyo + a tz-less branch ===========
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000e0000', 'Org T', 'tz-t', 'ILS');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000e1000', '00000000-0000-0000-0000-0000000e0000', 'Rest T1', 'Asia/Jerusalem');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000e1a00', '00000000-0000-0000-0000-0000000e0000', '00000000-0000-0000-0000-0000000e1000', 'Jerusalem', 'Asia/Jerusalem'),
  ('00000000-0000-0000-0000-0000000e1b00', '00000000-0000-0000-0000-0000000e0000', '00000000-0000-0000-0000-0000000e1000', 'Tokyo', 'Asia/Tokyo'),
  ('00000000-0000-0000-0000-0000000e1c00', '00000000-0000-0000-0000-0000000e0000', '00000000-0000-0000-0000-0000000e1000', 'NoZone', null);
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000fe01', 'tz-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000e0a01', '00000000-0000-0000-0000-00000000fe01', '00000000-0000-0000-0000-0000000e0000', null, null, 'org_owner');

-- Two events at the SAME absolute instant (Jerusalem-today 10:00) on the
-- Jerusalem + Tokyo branches; one tz-less-branch event (falls back to the
-- restaurant zone); one just after Jerusalem local midnight (00:30) — which is
-- the PREVIOUS UTC day in summer, so a UTC window would wrongly drop it.
insert into audit_events
  (id, organization_id, restaurant_id, branch_id, actor_app_user_id, action, new_values, occurred_at) values
  ('00000000-0000-0000-0000-0000000eae01', '00000000-0000-0000-0000-0000000e0000', '00000000-0000-0000-0000-0000000e1000', '00000000-0000-0000-0000-0000000e1a00', '00000000-0000-0000-0000-00000000fe01', 'order.voided', '{"status":"voided"}'::jsonb,
   (((now() at time zone 'Asia/Jerusalem')::date + time '10:00') at time zone 'Asia/Jerusalem')),
  ('00000000-0000-0000-0000-0000000eae02', '00000000-0000-0000-0000-0000000e0000', '00000000-0000-0000-0000-0000000e1000', '00000000-0000-0000-0000-0000000e1b00', '00000000-0000-0000-0000-00000000fe01', 'order.voided', '{"status":"voided"}'::jsonb,
   (((now() at time zone 'Asia/Jerusalem')::date + time '10:00') at time zone 'Asia/Jerusalem')),
  ('00000000-0000-0000-0000-0000000eae03', '00000000-0000-0000-0000-0000000e0000', '00000000-0000-0000-0000-0000000e1000', null, '00000000-0000-0000-0000-00000000fe01', 'order.voided', '{"status":"voided"}'::jsonb,
   (((now() at time zone 'Asia/Jerusalem')::date + time '10:00') at time zone 'Asia/Jerusalem')),
  ('00000000-0000-0000-0000-0000000eae04', '00000000-0000-0000-0000-0000000e0000', '00000000-0000-0000-0000-0000000e1000', '00000000-0000-0000-0000-0000000e1a00', '00000000-0000-0000-0000-00000000fe01', 'order.voided', '{"status":"voided"}'::jsonb,
   (((now() at time zone 'Asia/Jerusalem')::date + time '00:30') at time zone 'Asia/Jerusalem'));

set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000fe01';
create temp table t_org30 as select app.owner_audit_events('00000000-0000-0000-0000-0000000e0000', null, null, 'last30', null, null, false, null, null, 100) as res;
create temp table t_jertoday as select app.owner_audit_events('00000000-0000-0000-0000-0000000e0000', '00000000-0000-0000-0000-0000000e1000', '00000000-0000-0000-0000-0000000e1a00', 'today') as res;
reset role;

-- ===== per-event branch-local DISPLAY (not one scope zone, not browser tz) ===
-- 9. the Jerusalem-branch event displays in Asia/Jerusalem local time + carries
--    its resolved IANA id.
select is(
  (select e ->> 'occurred_at' from t_org30, jsonb_array_elements(res -> 'events') e where e ->> 'event_id' = '00000000-0000-0000-0000-0000000eae01'),
  to_char((select occurred_at from audit_events where id = '00000000-0000-0000-0000-0000000eae01') at time zone 'Asia/Jerusalem', 'YYYY-MM-DD HH24:MI'),
  'Jerusalem-branch event displays in Asia/Jerusalem local time');
select is(
  (select e ->> 'timezone' from t_org30, jsonb_array_elements(res -> 'events') e where e ->> 'event_id' = '00000000-0000-0000-0000-0000000eae01'),
  'Asia/Jerusalem', 'the event returns its resolved IANA timezone id (Asia/Jerusalem)');
-- 10. the Tokyo-branch event (SAME UTC instant) displays in Asia/Tokyo — using
--     ITS branch zone, not the other branch''s and not the browser''s.
select is(
  (select e ->> 'occurred_at' from t_org30, jsonb_array_elements(res -> 'events') e where e ->> 'event_id' = '00000000-0000-0000-0000-0000000eae02'),
  to_char((select occurred_at from audit_events where id = '00000000-0000-0000-0000-0000000eae02') at time zone 'Asia/Tokyo', 'YYYY-MM-DD HH24:MI'),
  'Tokyo-branch event displays in Asia/Tokyo local time');
select is(
  (select e ->> 'timezone' from t_org30, jsonb_array_elements(res -> 'events') e where e ->> 'event_id' = '00000000-0000-0000-0000-0000000eae02'),
  'Asia/Tokyo', 'the Tokyo event returns Asia/Tokyo');
-- 11. same absolute instant, DIFFERENT local strings (per-branch, not one zone).
select isnt(
  (select e ->> 'occurred_at' from t_org30, jsonb_array_elements(res -> 'events') e where e ->> 'event_id' = '00000000-0000-0000-0000-0000000eae01'),
  (select e ->> 'occurred_at' from t_org30, jsonb_array_elements(res -> 'events') e where e ->> 'event_id' = '00000000-0000-0000-0000-0000000eae02'),
  'the same UTC instant shows different local times per branch (not one scope zone)');
-- 12. the underlying stored instant is IDENTICAL for both (only display differs).
select is(
  (select occurred_at from audit_events where id = '00000000-0000-0000-0000-0000000eae01'),
  (select occurred_at from audit_events where id = '00000000-0000-0000-0000-0000000eae02'),
  'the stored occurred_at is the SAME absolute UTC instant for both events');
-- 13. a tz-less BRANCH falls back to the RESTAURANT zone (documented fallback).
select is(
  (select e ->> 'timezone' from t_org30, jsonb_array_elements(res -> 'events') e where e ->> 'event_id' = '00000000-0000-0000-0000-0000000eae03'),
  'Asia/Jerusalem', 'a branch with no timezone falls back to the restaurant timezone');

-- ===== branch-local day WINDOW (Today = branch-local midnight, DST-safe) ======
-- 14. the 00:30 Jerusalem-local event is TODAY in Jerusalem even though it is the
--     PREVIOUS calendar day in UTC — so range=today (Jerusalem branch) includes it.
select ok(
  exists (select 1 from t_jertoday, jsonb_array_elements(res -> 'events') e where e ->> 'event_id' = '00000000-0000-0000-0000-0000000eae04'),
  'an event just after Jerusalem midnight (prev UTC day) is in range=today for the Jerusalem branch');
-- 15. and its displayed date is today''s Jerusalem calendar date.
select is(
  (select left(e ->> 'occurred_at', 10) from t_jertoday, jsonb_array_elements(res -> 'events') e where e ->> 'event_id' = '00000000-0000-0000-0000-0000000eae04'),
  to_char((now() at time zone 'Asia/Jerusalem')::date, 'YYYY-MM-DD'),
  'the near-midnight event shows today''s Jerusalem calendar date');
-- 16. sanity: the same instant, evaluated in UTC, is the PREVIOUS day (proving
--     the window is branch-local, not UTC).
select is(
  ((select occurred_at from audit_events where id = '00000000-0000-0000-0000-0000000eae04') at time zone 'UTC')::date,
  (now() at time zone 'Asia/Jerusalem')::date - 1,
  'that event''s UTC date is the previous day (a UTC window would have dropped it)');

-- ===== list_timezones ACL (authenticated-only; no anon; wrapper hygiene) =====
select ok(has_function_privilege('authenticated','public.list_timezones()','execute'),
  'authenticated may execute public.list_timezones');
select ok(not has_function_privilege('anon','public.list_timezones()','execute'),
  'anon may NOT execute public.list_timezones');
select ok(not has_function_privilege('anon','app.list_timezones()','execute'),
  'anon may NOT execute app.list_timezones');
select is((select prosecdef from pg_proc where proname='list_timezones' and pronamespace='public'::regnamespace),
  false, 'public.list_timezones is SECURITY INVOKER');
select is((select prosecdef from pg_proc where proname='list_timezones' and pronamespace='app'::regnamespace),
  true, 'app.list_timezones is SECURITY DEFINER');

-- ===== owner_audit_events still returns the timezone field on every event =====
select ok(
  (select bool_and(e ? 'timezone') from t_org30, jsonb_array_elements(res -> 'events') e),
  'every returned audit event carries a resolved timezone id');

-- ===== the backend already accepts the GLOBAL IANA catalog (no migration) =====
-- The save path validates against pg_timezone_names, so a non-Israel global zone
-- saves, and the existing Israel/Palestine zones remain valid. (Role / scope /
-- cross-tenant / invalid-zone denials are owned by rf112_settings_rpc_test.sql.)
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000fe01';  -- org_owner
select is(
  (public.update_branch_settings('00000000-0000-0000-0000-0000000ec001','00000000-0000-0000-0000-0000000e0000','00000000-0000-0000-0000-0000000e1000','00000000-0000-0000-0000-0000000e1a00', null, null, 'Europe/London', null, null) ->> 'ok'),
  'true', 'a GLOBAL zone (Europe/London) saves via update_branch_settings (backend catalog is global)');
select is(
  (public.update_branch_settings('00000000-0000-0000-0000-0000000ec002','00000000-0000-0000-0000-0000000e0000','00000000-0000-0000-0000-0000000e1000','00000000-0000-0000-0000-0000000e1a00', null, null, 'Asia/Gaza', null, null) ->> 'ok'),
  'true', 'the existing Asia/Gaza value remains valid on save');
select is(
  (public.update_branch_settings('00000000-0000-0000-0000-0000000ec003','00000000-0000-0000-0000-0000000e0000','00000000-0000-0000-0000-0000000e1000','00000000-0000-0000-0000-0000000e1a00', null, null, 'Asia/Hebron', null, null) ->> 'ok'),
  'true', 'the existing Asia/Hebron value remains valid on save');
reset role;
-- the canonical IANA id is what gets stored (last write above was Asia/Hebron).
select is((select timezone from branches where id = '00000000-0000-0000-0000-0000000e1a00'), 'Asia/Hebron',
  'update_branch_settings stores the exact canonical IANA id');
-- the settings save RPC is authenticated-only (no anon), unchanged.
select ok(
  has_function_privilege('authenticated','public.update_branch_settings(uuid,uuid,uuid,uuid,text,text,text,text,text)','execute')
  and not has_function_privilege('anon','public.update_branch_settings(uuid,uuid,uuid,uuid,text,text,text,text,text)','execute'),
  'update_branch_settings is authenticated-only (no anon execute)');

select * from finish();
rollback;
