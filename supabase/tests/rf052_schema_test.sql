-- ============================================================================
-- RF-052 — pgTAP schema test
-- ============================================================================
-- Proves the order tables exist, are tenant/branch scoped, money is integer
-- bigint _minor ONLY (no numeric/float/double/money), idempotency + composite-FK
-- unique keys exist, RLS is enabled+forced, the RPC + helper exist, and the
-- submitted/pending status defaults are set.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(21);

-- tables exist ---------------------------------------------------------------- 1-3
select has_table('public', 'orders',               'orders table exists');
select has_table('public', 'order_items',          'order_items table exists');
select has_table('public', 'order_item_modifiers', 'order_item_modifiers table exists');

-- idempotency + composite-FK unique keys -------------------------------------- 4-6
select ok(exists(
  select 1 from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='orders' and con.contype='u'
    and con.conkey @> array[
      (select attnum from pg_attribute where attrelid=c.oid and attname='device_id'),
      (select attnum from pg_attribute where attrelid=c.oid and attname='local_operation_id')]::int2[]),
  'orders has UNIQUE(device_id, local_operation_id) (idempotency, D-022)');
select ok(exists(
  select 1 from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='orders' and con.contype='u'
    and con.conkey @> array[
      (select attnum from pg_attribute where attrelid=c.oid and attname='organization_id'),
      (select attnum from pg_attribute where attrelid=c.oid and attname='id')]::int2[]),
  'orders has UNIQUE(organization_id, id) (same-org composite-FK target)');
select ok(exists(
  select 1 from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='order_items' and con.contype='u'
    and con.conkey @> array[
      (select attnum from pg_attribute where attrelid=c.oid and attname='organization_id'),
      (select attnum from pg_attribute where attrelid=c.oid and attname='id')]::int2[]),
  'order_items has UNIQUE(organization_id, id)');

-- RLS enabled + forced on all three ------------------------------------------- 7-12
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='orders'),               'orders: RLS enabled');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='orders'),               'orders: RLS forced');
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='order_items'),          'order_items: RLS enabled');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='order_items'),          'order_items: RLS forced');
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='order_item_modifiers'), 'order_item_modifiers: RLS enabled');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='order_item_modifiers'), 'order_item_modifiers: RLS forced');

-- RPC + helper exist ---------------------------------------------------------- 13-14
select has_function('app', 'submit_order',     'app.submit_order() exists');
select has_function('app', 'order_parse_minor','app.order_parse_minor() exists');

-- money is integer bigint _minor ONLY ----------------------------------------- 15-17
select is(
  (select count(*) from information_schema.columns
    where table_schema='public' and table_name in ('orders','order_items','order_item_modifiers')
      and (column_name like '%\_minor' escape '\' or column_name like '%\_minor\_snapshot' escape '\')
      and data_type <> 'bigint')::int, 0,
  'every money column (_minor / _minor_snapshot) is bigint (D-007)');
select is(
  (select count(*) from information_schema.columns
    where table_schema='public' and table_name in ('orders','order_items','order_item_modifiers')
      and data_type in ('numeric','real','double precision','money'))::int, 0,
  'no numeric/real/double/money columns in the order tables (no float money)');
select cmp_ok(
  (select count(*) from information_schema.columns
    where table_schema='public' and table_name in ('orders','order_items','order_item_modifiers')
      and (column_name like '%\_minor' escape '\' or column_name like '%\_minor\_snapshot' escape '\'))::int,
  '>=', 8, 'the order tables actually carry money columns (non-vacuity)');

-- snapshot columns ------------------------------------------------------------ 18-19
select has_column('public', 'order_items',          'unit_price_minor_snapshot', 'order_items.unit_price_minor_snapshot exists (D-008)');
select has_column('public', 'order_item_modifiers', 'price_minor_snapshot',      'order_item_modifiers.price_minor_snapshot exists (D-008)');

-- initial status defaults ----------------------------------------------------- 20-21
select ok(
  (select column_default from information_schema.columns where table_schema='public' and table_name='orders' and column_name='status')::text like '%submitted%',
  'orders.status defaults to submitted');
select ok(
  (select column_default from information_schema.columns where table_schema='public' and table_name='order_items' and column_name='status')::text like '%pending%',
  'order_items.status defaults to pending');

select * from finish();
rollback;
