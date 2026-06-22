-- ============================================================================
-- RF-053 — pgTAP schema test
-- ============================================================================
-- void_reason columns added; the order_operations idempotency ledger (tenant
-- scoped, unique idempotency key, RLS enabled+forced); the two RPCs exist; money
-- columns remain integer bigint _minor.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(17);

-- void_reason columns -------------------------------------------------------- 1-2
select has_column('public', 'orders',      'void_reason', 'orders.void_reason exists (RF-053)');
select has_column('public', 'order_items', 'void_reason', 'order_items.void_reason exists (RF-053)');

-- order_operations ledger ----------------------------------------------------- 3-10
select has_table('public', 'order_operations', 'order_operations ledger table exists');
select col_not_null('public', 'order_operations', 'organization_id',    'order_operations.organization_id NOT NULL');
select col_not_null('public', 'order_operations', 'device_id',          'order_operations.device_id NOT NULL');
select col_not_null('public', 'order_operations', 'local_operation_id', 'order_operations.local_operation_id NOT NULL');
select col_not_null('public', 'order_operations', 'action',             'order_operations.action NOT NULL');
select col_not_null('public', 'order_operations', 'order_id',           'order_operations.order_id NOT NULL');
select col_not_null('public', 'order_operations', 'result',             'order_operations.result NOT NULL');
select ok(exists(
  select 1 from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='order_operations' and con.contype='u'
    and con.conkey @> array[
      (select attnum from pg_attribute where attrelid=c.oid and attname='organization_id'),
      (select attnum from pg_attribute where attrelid=c.oid and attname='device_id'),
      (select attnum from pg_attribute where attrelid=c.oid and attname='local_operation_id'),
      (select attnum from pg_attribute where attrelid=c.oid and attname='action')]::int2[]),
  'order_operations has UNIQUE(organization_id, device_id, local_operation_id, action) (D-022)');

-- RLS enabled + forced -------------------------------------------------------- 11-12
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='order_operations'), 'order_operations: RLS enabled');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='order_operations'), 'order_operations: RLS forced');

-- RPCs exist ------------------------------------------------------------------ 13-14
select has_function('app', 'void_order',     'app.void_order() exists');
select has_function('app', 'apply_discount', 'app.apply_discount() exists');

-- money stays integer bigint _minor (no float introduced) --------------------- 15-16
select is((select data_type from information_schema.columns where table_schema='public' and table_name='orders' and column_name='discount_total_minor'), 'bigint', 'orders.discount_total_minor is bigint');
select is(
  (select count(*) from information_schema.columns
    where table_schema='public' and table_name in ('orders','order_items','order_operations')
      and data_type in ('numeric','real','double precision','money'))::int, 0,
  'no numeric/real/double/money columns on the RF-052/RF-053 order tables');

-- direct writes to the ledger are denied for authenticated (RPC-only writer) -- 17
set local role authenticated;
select throws_ok($$
  insert into order_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, order_id, result)
  values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','x','void_order','00000000-0000-0000-0000-00000000a0d1','{}'::jsonb)
$$, '42501', NULL, 'authenticated cannot directly INSERT into order_operations (writes only via the SECURITY DEFINER RPCs)');
reset role;

select * from finish();
rollback;
