-- BIZBOT-POS-CUSTOMER-SUGGEST-001: directory capture, lookup and device/PIN isolation.
-- Synthetic fixtures only. Normal POS orders enter through the sync_push RPC used
-- by the outbox, including the separate name/phone stamps and idempotent replays.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;
select no_plan();

-- Deterministic scoped IDs keep the device, pairing, PIN and principal distinct.
create function pg_temp.fixture_id(label text) returns uuid
language sql immutable as $$ select md5('pos-contact-test:' || label)::uuid $$;

create temp table actors as
select station, tenant, location, kind, staff_role,
  pg_temp.fixture_id('org/' || tenant) as org,
  pg_temp.fixture_id('restaurant/' || tenant) as rest,
  pg_temp.fixture_id('branch/' || tenant || '/' || location) as branch,
  pg_temp.fixture_id('device/' || station) as device,
  pg_temp.fixture_id('pair/' || station) as pairing,
  pg_temp.fixture_id('device-session/' || station) as session,
  pg_temp.fixture_id('principal/' || station) as principal,
  pg_temp.fixture_id('user/' || station) as app_user,
  pg_temp.fixture_id('member/' || station) as member,
  pg_temp.fixture_id('employee/' || station) as employee,
  pg_temp.fixture_id('pin/' || station) as pin
from (values
  ('first',   'one', 'north', 'pos', 'cashier'),
  ('second',  'one', 'north', 'pos', 'cashier'),
  ('sibling', 'one', 'south', 'pos', 'cashier'),
  ('other',   'two', 'north', 'pos', 'cashier'),
  ('kitchen', 'one', 'north', 'pos', 'kitchen_staff'),
  ('display', 'one', 'north', 'kds', 'cashier')
) f(station, tenant, location, kind, staff_role);

insert into organizations (id, name, slug, default_currency)
  select distinct org, tenant, 'pos-contact-' || tenant, 'ILS' from actors;
insert into restaurants (id, organization_id, name)
  select distinct rest, org, tenant from actors;
insert into branches (id, organization_id, restaurant_id, name)
  select distinct branch, org, rest, location from actors;
insert into devices (id, organization_id, restaurant_id, branch_id, device_type)
  select device, org, rest, branch, kind from actors;
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status)
  select pairing, org, rest, branch, device, 'active' from actors;
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id,
                             device_pairing_id, auth_user_id, expires_at)
  select session, org, rest, branch, device, pairing, principal, now() + interval '4 hours' from actors;
insert into app_users (id, email)
  select app_user, station || '@pos-contact.example.test' from actors;
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role)
  select member, app_user, org, rest, branch, staff_role from actors;
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name)
  select employee, org, rest, branch, app_user, member, station from actors;
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id,
                          employee_profile_id, resolved_membership_id, expires_at)
  select pin, org, rest, branch, session, employee, member, now() + interval '2 hours' from actors;
insert into menu_categories (id, organization_id, restaurant_id, name, display_order)
  select distinct pg_temp.fixture_id('category/' || tenant), org, rest, 'Menu', 1 from actors;
insert into menu_items (id, organization_id, restaurant_id, menu_category_id, name, base_price_minor, currency_code, display_order)
  select distinct pg_temp.fixture_id('item/' || tenant), org, rest, pg_temp.fixture_id('category/' || tenant),
    'Sample', 500, 'ILS', 1 from actors;

grant select on actors to authenticated;
create function pg_temp.use_device(p_station text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', principal::text, true) from actors where station = p_station;
$$;
create function pg_temp.submit(p_station text, p_operation text, p_name text, p_phone text)
returns jsonb language sql as $$
  select public.sync_push(pin, device, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_operation, 'operation_type', 'order.submit', 'target_entity', 'order',
    'target_id', pg_temp.fixture_id('order/' || p_operation),
    'payload', jsonb_strip_nulls(jsonb_build_object(
      'order_id', pg_temp.fixture_id('order/' || p_operation), 'order_type', 'takeaway',
      'currency_code', 'ILS', 'dispatch_mode', 'kds', 'customer_name', p_name, 'customer_phone', p_phone,
      'subtotal_minor', 500, 'discount_total_minor', 0, 'tax_total_minor', 0, 'grand_total_minor', 500,
      'order_items', jsonb_build_array(jsonb_build_object('menu_item_id', pg_temp.fixture_id('item/' || tenant),
        'menu_item_name_snapshot', 'Sample', 'quantity', 1, 'unit_price_minor_snapshot', 500, 'modifiers', '[]'::jsonb))
    ))
  ))) #> '{results,0}'
  from actors where station = p_station;
$$;
create function pg_temp.search(p_station text, p_query text, p_phone boolean default false)
returns jsonb language sql as $$
  select public.pos_customer_suggestions(pg_temp.fixture_id('pin/' || p_station), p_query, p_phone);
$$;

select ok(not has_function_privilege('anon', 'public.pos_customer_suggestions(uuid,text,boolean)', 'EXECUTE'),
  'public/anon clients cannot request suggestions');
select ok(not has_table_privilege('authenticated', 'app.pos_customer_contacts', 'SELECT')
      and not has_table_privilege('authenticated', 'app.pos_customer_contacts', 'INSERT'),
  'cashiers cannot read or populate the directory table directly');

-- Device-only Kiosk orders have all human actor fields NULL. They can carry a
-- name/phone at insert; that contact must never appear at a cashier terminal.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type)
  select pg_temp.fixture_id('kiosk'), org, rest, branch, 'kiosk' from actors where station='first';
insert into orders (organization_id, restaurant_id, branch_id, device_id, order_type, status,
                    currency_code, subtotal_minor, grand_total_minor, local_operation_id, customer_name, customer_phone)
  select org, rest, branch, pg_temp.fixture_id('kiosk'), 'takeaway', 'submitted', 'ILS', 500, 500,
    'example-kiosk', 'Kiosk Sample', '0500-000900' from actors where station='first';

set local role authenticated;
select pg_temp.use_device('first');
select is(pg_temp.submit('first', 'example-1', 'نموذج ألف', '0500-000101')->>'status', 'applied',
  'cashier submits a contact through the normal queued-order API');
select is(pg_temp.search('first', 'نم'), '[{"name":"نموذج ألف","phone":"0500-000101"}]'::jsonb,
  'accepted POS order appears with exactly the two original display fields');
select is(pg_temp.search('first', '0500', true), pg_temp.search('first', 'نم'),
  'four-digit phone prefix finds the same customer');
select is(pg_temp.search('first', '٠٥٠٠', true), pg_temp.search('first', '0500', true),
  'Arabic-Indic digits can find the stored ASCII display number');
select is(pg_temp.search('first', 'ن'), '[]'::jsonb, 'one-letter search cannot enumerate contacts');
select is(pg_temp.search('first', '050', true), '[]'::jsonb, 'three digits cannot enumerate contacts');
select is(pg_temp.search('first', '%%'), '[]'::jsonb, 'LIKE wildcards cannot list contacts');
select is(pg_temp.search('first', '__'), '[]'::jsonb, 'underscores are not single-character wildcards');

select is(pg_temp.submit('first', 'example-1', 'نموذج ألف', '0500-999999')->>'idempotency_replay', 'true',
  'retry follows the normal order replay path');
select is(pg_temp.search('first', '050099', true), '[]'::jsonb, 'replay cannot replace the stored contact');
select is(pg_temp.submit('first', 'example-2', 'نموذج ألف', '0500 000101')->>'status', 'applied',
  'a second visit with a different phone display format is accepted');
select is(jsonb_array_length(pg_temp.search('first', 'نم')), 1, 'a repeat contact does not create a duplicate');
select is(pg_temp.submit('first', 'example-3', 'نموذج باء', '0500-000101')->>'status', 'applied',
  'different names may use a shared phone');
select is(pg_temp.submit('first', 'example-4', 'نموذج ألف', '0500-000102')->>'status', 'applied',
  'the same display name may use a different phone');
select is(jsonb_array_length(pg_temp.search('first', '0500000101', true)), 2,
  'two named contacts on a shared phone remain selectable');
select is(jsonb_array_length(pg_temp.search('first', 'نموذج ألف')), 2,
  'identical names with distinct numbers remain selectable');
select is(pg_temp.submit('first', 'example-blank', 'Missing Phone', null)->>'status', 'applied',
  'a valid order still submits without a contact number');
select is(pg_temp.search('first', 'Missing'), '[]'::jsonb, 'partial contacts do not enter the directory');
select is(pg_temp.submit('first', 'example-bad', 'Rejected Sample', 'bad')->>'error', 'invalid_payload',
  'order validation still rejects an invalid phone');
select is(pg_temp.search('first', 'Reject'), '[]'::jsonb, 'rejected submissions do not leave a suggestion');
select is(pg_temp.submit('first', 'web-accept:sample:decision', 'Web Sample', '0500-000901')->>'status', 'applied',
  'the storefront acceptance operation can persist its own order contact');
select is(pg_temp.search('first', 'Web'), '[]'::jsonb, 'accepting a web order at the till does not import the web contact');
select is(pg_temp.search('first', 'Kiosk'), '[]'::jsonb, 'a kiosk contact is not imported');
-- A directory-only write fault must not deny the sale or roll back its
-- historical order contact. This constraint exists only in this transaction.
reset role;
alter table app.pos_customer_contacts add constraint fixture_directory_fault
  check (display_name <> 'Directory unavailable');
set local role authenticated;
select is(pg_temp.submit('first', 'directory-fault', 'Directory unavailable', '0500000990')->>'status', 'applied',
  'a directory-only failure does not fail the order');
select is(pg_temp.search('first', 'Directory unavailable'), '[]'::jsonb,
  'a failed contact capture produces no suggestion');
reset role;
select is((select customer_phone from orders where id = pg_temp.fixture_id('order/directory-fault')),
  '0500000990', 'the accepted order retains its own phone through a directory failure');
alter table app.pos_customer_contacts drop constraint fixture_directory_fault;
set local role authenticated;
select ok((select bool_and(pg_temp.submit('first', 'list-' || n, 'Listed ' || n,
    '05000120' || n)->>'status' = 'applied') from generate_series(1, 8) n),
  'eight distinct matching orders are accepted');
select is(jsonb_array_length(pg_temp.search('first', 'list')), 5, 'the list is case-insensitive and capped at five');

select pg_temp.use_device('second');
select is(jsonb_array_length(pg_temp.search('second', 'نموذج ألف')), 2, 'another till in the same branch shares suggestions');
select throws_ok($$select pg_temp.search('first','نموذج')$$, '42501', null,
  'a different authenticated device cannot use the first till PIN, even within the branch');

select pg_temp.use_device('sibling');
select is(pg_temp.submit('sibling', 'sibling-order', 'Listed Sibling', '0500-888888')->>'status', 'applied',
  'the sibling branch records its own customer');
select is(pg_temp.search('sibling','list'), '[{"name":"Listed Sibling","phone":"0500-888888"}]'::jsonb,
  'a sibling branch sees only its own matching contact');
select is(pg_temp.search('sibling','0500000',true), '[]'::jsonb, 'phone search is isolated across branches');
select pg_temp.use_device('other');
select is(pg_temp.submit('other', 'other-order', 'Listed Other', '0500-777777')->>'status', 'applied',
  'another tenant records its own customer');
select is(pg_temp.search('other','list'), '[{"name":"Listed Other","phone":"0500-777777"}]'::jsonb,
  'another tenant sees only its own matching contact');
select throws_ok($$select pg_temp.search('first','نموذج')$$, '42501', null,
  'a foreign tenant principal cannot use a known valid PIN from the first branch');
select pg_temp.use_device('kitchen');
select throws_ok($$select pg_temp.search('kitchen','list')$$, '42501', null,
  'a kitchen employee on a POS cannot read customer suggestions');
select pg_temp.use_device('display');
select throws_ok($$select pg_temp.search('display','list')$$, '42501', null,
  'a cashier PIN on a KDS cannot read customer suggestions');

reset role;
update pin_sessions set expires_at = now() - interval '1 minute' where id=pg_temp.fixture_id('pin/second');
set local role authenticated;
select pg_temp.use_device('second');
select throws_ok($$select pg_temp.search('second','نموذج')$$, '42501', null, 'an expired PIN cannot search');

select * from finish();
rollback;
