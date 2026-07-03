-- ============================================================================
-- MVP — pgTAP: app.get_device_printer_assignments (token-proven device printer
-- read). Failure modes (invalid/blank/wrong/revoked/foreign token), POS
-- receipt-only visibility, KDS kitchen-only visibility, sibling-branch /
-- cross-org / tombstone exclusion (RISK R-003, D-020), NO connection_config or
-- LAN target anywhere in the payload, routes pinned to VISIBLE printers,
-- stations pinned to the RETURNED routes, device display context, wrapper
-- delegation + the introspection/grants block (mvp_list_printers pattern).
-- Fixtures inserted as the BYPASSRLS connection role (rf112/rf161 harness);
-- device calls run as an ANONYMOUS authenticated principal (GUC '').
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(45);

-- ===== fixture: Org A (Rest A1: branches A1a device-branch, A1b sibling); Org B
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-000117000a00', 'Org A', 'mvpdpa-a', 'USD'),
  ('00000000-0000-0000-0000-000117000b00', 'Org B', 'mvpdpa-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-000117000a10', '00000000-0000-0000-0000-000117000a00', 'Rest A1'),
  ('00000000-0000-0000-0000-000117000b10', '00000000-0000-0000-0000-000117000b00', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-000117000a1a', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', 'Branch A1a'),
  ('00000000-0000-0000-0000-000117000a1b', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', 'Branch A1b'),
  ('00000000-0000-0000-0000-000117000b1a', '00000000-0000-0000-0000-000117000b00', '00000000-0000-0000-0000-000117000b10', 'Branch B1a');
-- stations @ A1a: Grill + Expo live+active (routed); Legacy live+active but UNROUTED.
insert into stations (id, organization_id, restaurant_id, branch_id, name, is_active) values
  ('00000000-0000-0000-0000-000117001001', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', '00000000-0000-0000-0000-000117000a1a', 'Grill',  true),
  ('00000000-0000-0000-0000-000117001002', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', '00000000-0000-0000-0000-000117000a1a', 'Expo',   true),
  ('00000000-0000-0000-0000-000117001003', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', '00000000-0000-0000-0000-000117000a1a', 'Legacy', true);
-- printers: @A1a receipt live (PR1) + receipt DISABLED (PR2) + kitchen live (PK1)
-- + kitchen DISABLED (PK2) + tombstoned receipt (PRX); receipt @ SIBLING branch
-- A1b (PSib); receipt @ ANOTHER ORG (PB). PR1/PK1 carry a LAN connection_config
-- that must NEVER surface in the device payload.
insert into printer_devices (id, organization_id, restaurant_id, branch_id, display_name, connection_type, role, is_enabled, connection_config, deleted_at) values
  ('00000000-0000-0000-0000-000117002001', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', '00000000-0000-0000-0000-000117000a1a', 'Front Receipt',   'network',   'receipt', true,  '{"host":"192.0.2.50","port":9100}'::jsonb, null),
  ('00000000-0000-0000-0000-000117002002', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', '00000000-0000-0000-0000-000117000a1a', 'Backup Receipt',  'usb',       'receipt', false, '{}'::jsonb,                                null),
  ('00000000-0000-0000-0000-000117002003', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', '00000000-0000-0000-0000-000117000a1a', 'Grill Kitchen',   'network',   'kitchen', true,  '{"host":"192.0.2.50","port":9100}'::jsonb, null),
  ('00000000-0000-0000-0000-000117002004', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', '00000000-0000-0000-0000-000117000a1a', 'Pass Kitchen',    'bluetooth', 'kitchen', false, '{}'::jsonb,                                null),
  ('00000000-0000-0000-0000-000117002005', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', '00000000-0000-0000-0000-000117000a1a', 'Dead Receipt',    'network',   'receipt', true,  '{}'::jsonb,                                now()),
  ('00000000-0000-0000-0000-000117002006', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', '00000000-0000-0000-0000-000117000a1b', 'Sibling Receipt', 'network',   'receipt', true,  '{}'::jsonb,                                null),
  ('00000000-0000-0000-0000-000117002007', '00000000-0000-0000-0000-000117000b00', '00000000-0000-0000-0000-000117000b10', '00000000-0000-0000-0000-000117000b1a', 'OrgB Receipt',    'network',   'receipt', true,  '{}'::jsonb,                                null);
-- routes @ A1a: Grill->PK1 (kitchen), Expo->PK2 (kitchen, disabled printer),
-- Grill->PR1 (receipt: the invisible-role route from the KDS view), and a
-- TOMBSTONED Expo->PK1.
insert into printer_routes (id, organization_id, restaurant_id, branch_id, station_id, printer_device_id, deleted_at) values
  ('00000000-0000-0000-0000-000117003001', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', '00000000-0000-0000-0000-000117000a1a', '00000000-0000-0000-0000-000117001001', '00000000-0000-0000-0000-000117002003', null),
  ('00000000-0000-0000-0000-000117003002', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', '00000000-0000-0000-0000-000117000a1a', '00000000-0000-0000-0000-000117001002', '00000000-0000-0000-0000-000117002004', null),
  ('00000000-0000-0000-0000-000117003003', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', '00000000-0000-0000-0000-000117000a1a', '00000000-0000-0000-0000-000117001001', '00000000-0000-0000-0000-000117002001', null),
  ('00000000-0000-0000-0000-000117003004', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', '00000000-0000-0000-0000-000117000a1a', '00000000-0000-0000-0000-000117001002', '00000000-0000-0000-0000-000117002003', now());
-- paired POS + KDS devices @ A1a with LIVE token-proven sessions (RF-161 shape)
-- + a REVOKED session on the POS pairing.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('00000000-0000-0000-0000-000117004001', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', '00000000-0000-0000-0000-000117000a1a', 'pos', 'Front POS'),
  ('00000000-0000-0000-0000-000117004002', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', '00000000-0000-0000-0000-000117000a1a', 'kds', 'Kitchen Screen');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-000117004011', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', '00000000-0000-0000-0000-000117000a1a', '00000000-0000-0000-0000-000117004001', 'active'),
  ('00000000-0000-0000-0000-000117004012', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', '00000000-0000-0000-0000-000117000a1a', '00000000-0000-0000-0000-000117004002', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, revoked_at) values
  ('00000000-0000-0000-0000-000117004051', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', '00000000-0000-0000-0000-000117000a1a', '00000000-0000-0000-0000-000117004001', '00000000-0000-0000-0000-000117004011', app.hash_provisioning_secret('tok-dpa-pos'),     true,  null),
  ('00000000-0000-0000-0000-000117004052', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', '00000000-0000-0000-0000-000117000a1a', '00000000-0000-0000-0000-000117004002', '00000000-0000-0000-0000-000117004012', app.hash_provisioning_secret('tok-dpa-kds'),     true,  null),
  ('00000000-0000-0000-0000-000117004053', '00000000-0000-0000-0000-000117000a00', '00000000-0000-0000-0000-000117000a10', '00000000-0000-0000-0000-000117000a1a', '00000000-0000-0000-0000-000117004001', '00000000-0000-0000-0000-000117004011', app.hash_provisioning_secret('tok-dpa-revoked'), false, now());

-- captured RPC results (readable/writable by the authenticated harness role)
create temp table _res (label text primary key, r jsonb);
grant select, insert on _res to authenticated;

-- ============================================================================
-- A. failure modes -- ALWAYS invalid_session, never a raise (1-6)
-- ============================================================================
set local role authenticated;
set local app.current_app_user_id = '';   -- anonymous authenticated device: NO app_user

select is((app.get_device_printer_assignments(null, 'tok-dpa-pos') ->> 'error'),
  'invalid_session', 'a NULL device_id fails closed (invalid_session)');                                        -- 1
select is((app.get_device_printer_assignments('00000000-0000-0000-0000-000117004001', '   ') ->> 'error'),
  'invalid_session', 'a blank token fails closed (invalid_session)');                                           -- 2
select is((app.get_device_printer_assignments('00000000-0000-0000-0000-000117004001', 'wrong-token') ->> 'error'),
  'invalid_session', 'a wrong token fails closed (invalid_session, no scope leak)');                            -- 3
select is((app.get_device_printer_assignments('00000000-0000-0000-0000-000117004001', 'tok-dpa-revoked') ->> 'error'),
  'invalid_session', 'a REVOKED session fails closed (invalid_session)');                                       -- 4
select is((app.get_device_printer_assignments('00000000-0000-0000-0000-000117004001', 'tok-dpa-kds') ->> 'error'),
  'invalid_session', 'ANOTHER device''s token does not open this device (invalid_session)');                    -- 5
select is((app.get_device_printer_assignments('00000000-0000-0000-0000-000117004001', 'wrong-token') ->> 'entity'),
  'device_printer_assignments', 'the failure envelope carries the entity tag');                                 -- 6

-- ============================================================================
-- B. POS device -- receipt-role visibility ONLY, own branch ONLY (7-24)
-- ============================================================================
insert into _res values ('pos',
  public.get_device_printer_assignments('00000000-0000-0000-0000-000117004001', 'tok-dpa-pos'));

select is((select r ->> 'ok' from _res where label = 'pos'), 'true',
  'the POS device opens its assignments with the valid token (public wrapper)');                                -- 7
select is((select r ->> 'entity' from _res where label = 'pos'), 'device_printer_assignments',
  'the success envelope carries the entity tag');                                                               -- 8
select is(jsonb_array_length((select r -> 'printers' from _res where label = 'pos')), 2,
  'POS printers = 2 (its branch''s receipt printers; kitchen/sibling/other-org/tombstoned excluded)');          -- 9
select ok((select bool_and(e ->> 'role' = 'receipt')
             from _res, jsonb_array_elements(r -> 'printers') e where label = 'pos'),
  'a POS device sees receipt-role printers ONLY (never kitchen)');                                              -- 10
select is((select e ->> 'is_enabled' from _res, jsonb_array_elements(r -> 'printers') e
            where label = 'pos' and e ->> 'id' = '00000000-0000-0000-0000-000117002002'), 'false',
  'the DISABLED receipt printer IS included, carrying is_enabled=false');                                       -- 11
select is((select count(*) from _res, jsonb_array_elements(r -> 'printers') e
            where label = 'pos' and e ->> 'id' = '00000000-0000-0000-0000-000117002006')::int, 0,
  'a SIBLING-branch receipt printer is NOT returned');                                                          -- 12
select is((select count(*) from _res, jsonb_array_elements(r -> 'printers') e
            where label = 'pos' and e ->> 'id' = '00000000-0000-0000-0000-000117002007')::int, 0,
  'an OTHER-ORG receipt printer is NOT returned (RISK R-003)');                                                 -- 13
select is((select count(*) from _res, jsonb_array_elements(r -> 'printers') e
            where label = 'pos' and e ->> 'id' = '00000000-0000-0000-0000-000117002005')::int, 0,
  'a TOMBSTONED printer is NOT returned (D-020)');                                                              -- 14
select is(
  (select array_agg(distinct k order by k)
     from _res, jsonb_array_elements(r -> 'printers') e, jsonb_object_keys(e) k
    where label = 'pos')::text,
  '{connection_type,display_name,id,is_enabled,paper_width,role}',
  'printer rows carry ONLY the whitelisted keys (never connection_config)');                                    -- 15
select ok(
  (select position('connection_config' in r::text) = 0
      and position('192.0.2.50' in r::text) = 0
     from _res where label = 'pos'),
  'the POS payload carries NO connection_config key and NO LAN target ANYWHERE');                               -- 16
select is(jsonb_array_length((select r -> 'routes' from _res where label = 'pos')), 1,
  'POS routes = 1 (only the route pointing at a VISIBLE receipt printer)');                                     -- 17
select is((select r -> 'routes' -> 0 ->> 'printer_device_id' from _res where label = 'pos'),
  '00000000-0000-0000-0000-000117002001',
  'the POS route references the RETURNED receipt printer (Grill -> Front Receipt)');                            -- 18
select is(
  (select array_agg(distinct k order by k)
     from _res, jsonb_array_elements(r -> 'routes') e, jsonb_object_keys(e) k
    where label = 'pos')::text,
  '{is_enabled,printer_device_id,station_id}',
  'route rows carry ONLY station_id + printer_device_id + is_enabled');                                         -- 19
select is(jsonb_array_length((select r -> 'stations' from _res where label = 'pos')), 1,
  'POS stations = 1 (only stations referenced by the RETURNED routes)');                                        -- 20
select is((select (r -> 'stations' -> 0 ->> 'id') || ':' || (r -> 'stations' -> 0 ->> 'name')
             from _res where label = 'pos'),
  '00000000-0000-0000-0000-000117001001:Grill',
  'the POS station is Grill (the receipt route''s source station)');                                            -- 21
select is((select (r -> 'device' ->> 'device_type') || ':' || (r -> 'device' ->> 'label')
             from _res where label = 'pos'), 'pos:Front POS',
  'device{} carries device_type + label');                                                                      -- 22
select is((select (r -> 'device' ->> 'branch_id') || ':' || (r -> 'device' ->> 'branch_name')
              || ':' || (r -> 'device' ->> 'restaurant_name') from _res where label = 'pos'),
  '00000000-0000-0000-0000-000117000a1a:Branch A1a:Rest A1',
  'device{} carries branch_id + branch_name + restaurant_name');                                                -- 23
select ok((select (r ->> 'server_ts') is not null from _res where label = 'pos'),
  'the payload carries server_ts');                                                                             -- 24

-- ============================================================================
-- C. KDS device -- kitchen-role visibility ONLY (25-33)
-- ============================================================================
insert into _res values ('kds',
  public.get_device_printer_assignments('00000000-0000-0000-0000-000117004002', 'tok-dpa-kds'));

select is((select r ->> 'ok' from _res where label = 'kds'), 'true',
  'the KDS device opens its assignments with the valid token');                                                 -- 25
select is(jsonb_array_length((select r -> 'printers' from _res where label = 'kds')), 2,
  'KDS printers = 2 (its branch''s kitchen printers only)');                                                    -- 26
select ok((select bool_and(e ->> 'role' = 'kitchen')
             from _res, jsonb_array_elements(r -> 'printers') e where label = 'kds'),
  'a KDS device sees kitchen-role printers ONLY (never receipt)');                                              -- 27
select is((select e ->> 'is_enabled' from _res, jsonb_array_elements(r -> 'printers') e
            where label = 'kds' and e ->> 'id' = '00000000-0000-0000-0000-000117002004'), 'false',
  'the DISABLED kitchen printer IS included, carrying is_enabled=false');                                       -- 28
select is(jsonb_array_length((select r -> 'routes' from _res where label = 'kds')), 2,
  'KDS routes = 2 (the receipt-role route AND the tombstoned route are excluded)');                             -- 29
select ok((select bool_and(e ->> 'printer_device_id' in
             ('00000000-0000-0000-0000-000117002003', '00000000-0000-0000-0000-000117002004'))
             from _res, jsonb_array_elements(r -> 'routes') e where label = 'kds'),
  'KDS routes reference the RETURNED kitchen printers ONLY (never the invisible receipt route)');               -- 30
select is((select array_agg(e ->> 'name' order by e ->> 'name')
             from _res, jsonb_array_elements(r -> 'stations') e where label = 'kds')::text,
  '{Expo,Grill}',
  'KDS stations = exactly the ROUTED live stations (unrouted Legacy excluded)');                                -- 31
select is(
  (select array_agg(distinct k order by k)
     from _res, jsonb_array_elements(r -> 'stations') e, jsonb_object_keys(e) k
    where label = 'kds')::text,
  '{id,name}', 'station rows carry ONLY id + name');                                                            -- 32
select ok(
  (select position('connection_config' in r::text) = 0
      and position('192.0.2.50' in r::text) = 0
     from _res where label = 'kds'),
  'the KDS payload carries NO connection_config key and NO LAN target ANYWHERE');                               -- 33

-- ============================================================================
-- D. wrapper delegation + introspection / grants (34-45)
-- ============================================================================
select is(
  public.get_device_printer_assignments('00000000-0000-0000-0000-000117004001', 'tok-dpa-pos'),
  app.get_device_printer_assignments('00000000-0000-0000-0000-000117004001', 'tok-dpa-pos'),
  'public.get_device_printer_assignments delegates verbatim to app.*');                                         -- 34
reset role;

select is((select count(*) from pg_proc
            where proname = 'get_device_printer_assignments' and pronamespace = 'app'::regnamespace)::int, 1,
  'exactly ONE overload exists in the app schema');                                                             -- 35
select is((select count(*) from pg_proc
            where proname = 'get_device_printer_assignments' and pronamespace = 'public'::regnamespace)::int, 1,
  'exactly ONE overload exists in the public schema');                                                          -- 36
select is(
  (select prosecdef from pg_proc
    where proname = 'get_device_printer_assignments' and pronamespace = 'app'::regnamespace),
  true, 'app.get_device_printer_assignments is SECURITY DEFINER');                                              -- 37
select ok(
  (select exists(
     select 1 from pg_proc p
     cross join lateral unnest(coalesce(p.proconfig, '{}'::text[])) as cfg
     where p.proname = 'get_device_printer_assignments' and p.pronamespace = 'app'::regnamespace
       and cfg like 'search_path=%')),
  'app.get_device_printer_assignments has a locked search_path');                                               -- 38
select is(
  (select prosecdef from pg_proc
    where proname = 'get_device_printer_assignments' and pronamespace = 'public'::regnamespace),
  false, 'public.get_device_printer_assignments is SECURITY INVOKER (not definer)');                            -- 39
select ok(
  (select exists(
     select 1 from pg_proc p
     cross join lateral unnest(coalesce(p.proconfig, '{}'::text[])) as cfg
     where p.proname = 'get_device_printer_assignments' and p.pronamespace = 'public'::regnamespace
       and cfg like 'search_path=%')),
  'public.get_device_printer_assignments has a locked search_path');                                            -- 40
select ok(
  not has_function_privilege('public', 'public.get_device_printer_assignments(uuid, text)', 'execute'),
  'PUBLIC may NOT execute public.get_device_printer_assignments (revoked)');                                    -- 41
select ok(
  not has_function_privilege('anon', 'public.get_device_printer_assignments(uuid, text)', 'execute'),
  'anon may NOT execute public.get_device_printer_assignments');                                                -- 42
select ok(
  has_function_privilege('authenticated', 'public.get_device_printer_assignments(uuid, text)', 'execute'),
  'authenticated MAY execute public.get_device_printer_assignments');                                           -- 43
select ok(
  has_function_privilege('authenticated', 'app.get_device_printer_assignments(uuid, text)', 'execute'),
  'authenticated MAY execute app.get_device_printer_assignments');                                              -- 44
select ok(
  not has_function_privilege('anon', 'app.get_device_printer_assignments(uuid, text)', 'execute'),
  'anon may NOT execute app.get_device_printer_assignments');                                                   -- 45

select * from finish();
rollback;
