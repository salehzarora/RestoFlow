-- ============================================================================
-- RF-054 — pgTAP schema test
-- ============================================================================
-- payments + branch_receipt_counters exist; money columns are integer bigint
-- _minor (no float/numeric/double/money); the per-branch receipt unique index on
-- orders exists; the order_operations action CHECK now includes record_payment
-- (and still includes void_order/apply_discount); RLS is enabled+forced on the
-- new tables; direct writes are revoked from authenticated; the RPC exists.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(19);

-- tables exist -------------------------------------------------------------- 1-2
select has_table('public', 'payments',                'payments table exists');
select has_table('public', 'branch_receipt_counters', 'branch_receipt_counters table exists');

-- money columns are integer bigint _minor ----------------------------------- 3-6
select is((select data_type from information_schema.columns where table_schema='public' and table_name='payments' and column_name='amount_minor'),   'bigint', 'payments.amount_minor is bigint');
select is((select data_type from information_schema.columns where table_schema='public' and table_name='payments' and column_name='tendered_minor'), 'bigint', 'payments.tendered_minor is bigint');
select is((select data_type from information_schema.columns where table_schema='public' and table_name='payments' and column_name='change_minor'),   'bigint', 'payments.change_minor is bigint');
select is((select data_type from information_schema.columns where table_schema='public' and table_name='branch_receipt_counters' and column_name='last_issued_value'), 'bigint', 'branch_receipt_counters.last_issued_value is bigint');

-- NO float/numeric/double/money columns anywhere on the new tables (D-007) ---- 7
select is(
  (select count(*) from information_schema.columns
     where table_schema='public' and table_name in ('payments','branch_receipt_counters')
       and data_type in ('numeric','real','double precision','money'))::int, 0,
  'no numeric/real/double/money columns on payments/branch_receipt_counters (integer _minor only)');

-- per-branch receipt unique index on orders --------------------------------- 8
select ok(
  (select indexdef from pg_indexes where schemaname='public' and indexname='orders_branch_receipt_number_uidx') like '%UNIQUE%receipt_number%',
  'orders has the per-branch UNIQUE receipt_number index (orders_branch_receipt_number_uidx)');

-- order_operations action CHECK extended additively ------------------------- 9-10
select ok(
  (select pg_get_constraintdef(oid) from pg_constraint
     where conname='order_operations_action_check' and conrelid='public.order_operations'::regclass) like '%record_payment%',
  'order_operations action CHECK includes record_payment (A5)');
select ok(
  (select pg_get_constraintdef(oid) from pg_constraint
     where conname='order_operations_action_check' and conrelid='public.order_operations'::regclass)
       like '%void_order%'
  and
  (select pg_get_constraintdef(oid) from pg_constraint
     where conname='order_operations_action_check' and conrelid='public.order_operations'::regclass)
       like '%apply_discount%',
  'order_operations action CHECK still includes void_order + apply_discount (preserved)');

-- payments idempotency UNIQUE(device_id, local_operation_id) (D-022) -------- 11
select ok(exists(
  select 1 from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='payments' and con.contype='u'
    and con.conkey @> array[
      (select attnum from pg_attribute where attrelid=c.oid and attname='device_id'),
      (select attnum from pg_attribute where attrelid=c.oid and attname='local_operation_id')]::int2[]),
  'payments has UNIQUE(device_id, local_operation_id) (D-022 idempotency backstop)');

-- RLS enabled + forced on the new tables ------------------------------------ 12-15
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='payments'),                'payments: RLS enabled');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='payments'),                'payments: RLS forced');
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='branch_receipt_counters'), 'branch_receipt_counters: RLS enabled');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='branch_receipt_counters'), 'branch_receipt_counters: RLS forced');

-- the RPC exists ------------------------------------------------------------ 16
select has_function('app', 'record_payment', 'app.record_payment() exists');

-- direct writes to the new tables are denied for authenticated (RPC-only) --- 17-18
set local role authenticated;
select throws_ok($$
  insert into payments (organization_id, restaurant_id, branch_id, order_id, device_id,
    taken_by_employee_profile_id, resolved_membership_id, method, status,
    amount_minor, tendered_minor, change_minor, currency_code, local_operation_id)
  values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','cash','completed',1000,1000,0,'USD','x')
$$, '42501', NULL, 'authenticated cannot directly INSERT into payments (writes only via the SECURITY DEFINER RPC)');
select throws_ok($$
  insert into branch_receipt_counters (organization_id, restaurant_id, branch_id, last_issued_value)
  values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1',1)
$$, '42501', NULL, 'authenticated cannot directly INSERT into branch_receipt_counters');
reset role;

-- payments.method is cash-only in RF-054 ------------------------------------ 19
select ok(
  (select pg_get_constraintdef(con.oid) from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relname='payments' and con.contype='c' and pg_get_constraintdef(con.oid) like '%method%') like '%cash%',
  'payments.method CHECK allows cash (card/online deferred)');

select * from finish();
rollback;
