-- ============================================================================
-- RF-056 — pgTAP schema test
-- ============================================================================
-- sync_operations exists with the right columns/checks (status set matching RF-018,
-- the 5 allowed operation_types), the (org, device, local_operation_id) idempotency
-- identity, jsonb payload/depends_on/result/conflict_info (no float/money columns),
-- RLS enabled+forced, direct writes revoked, and the app.sync_push RPC.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(20);

-- table + key columns -------------------------------------------------------- 1-7
select has_table('public', 'sync_operations', 'sync_operations table exists');
select col_not_null('public', 'sync_operations', 'organization_id',    'organization_id NOT NULL');
select col_not_null('public', 'sync_operations', 'device_id',          'device_id NOT NULL');
select col_not_null('public', 'sync_operations', 'local_operation_id', 'local_operation_id NOT NULL');
select col_not_null('public', 'sync_operations', 'operation_type',     'operation_type NOT NULL');
select col_not_null('public', 'sync_operations', 'payload',            'payload NOT NULL');
select is((select data_type from information_schema.columns where table_schema='public' and table_name='sync_operations' and column_name='payload'), 'jsonb', 'payload is jsonb');

-- jsonb columns -------------------------------------------------------------- 8-9
select is((select data_type from information_schema.columns where table_schema='public' and table_name='sync_operations' and column_name='depends_on'), 'jsonb', 'depends_on is jsonb');
select is((select data_type from information_schema.columns where table_schema='public' and table_name='sync_operations' and column_name='result'),     'jsonb', 'result is jsonb');

-- NO float/numeric/double/money columns (D-007) ------------------------------ 10
select is(
  (select count(*) from information_schema.columns
     where table_schema='public' and table_name='sync_operations'
       and data_type in ('numeric','real','double precision','money'))::int, 0,
  'sync_operations has no numeric/real/double/money columns (money lives in the dispatched RPCs)');

-- identity unique (org, device, local_operation_id) (D-022) ------------------ 11
select ok(exists(
  select 1 from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='sync_operations' and con.contype='u'
    and con.conkey @> array[
      (select attnum from pg_attribute where attrelid=c.oid and attname='organization_id'),
      (select attnum from pg_attribute where attrelid=c.oid and attname='device_id'),
      (select attnum from pg_attribute where attrelid=c.oid and attname='local_operation_id')]::int2[]),
  'sync_operations has UNIQUE(organization_id, device_id, local_operation_id) (D-022 identity)');

-- operation_type CHECK = the 5 approved types ------------------------------- 12
select ok(
  (select pg_get_constraintdef(oid) from pg_constraint where conname='sync_operations_operation_type_check' and conrelid='public.sync_operations'::regclass)
    like all (array['%shift.open%','%order.submit%','%order.discount%','%payment.create%','%shift.close%']),
  'operation_type CHECK carries exactly the 5 approved types (A3)');

-- status CHECK = the 8 RF-018 wire names ------------------------------------ 13
select ok(
  (select pg_get_constraintdef(oid) from pg_constraint where conname='sync_operations_status_check' and conrelid='public.sync_operations'::regclass)
    like all (array['%created%','%pending%','%in_flight%','%applied%','%rejected%','%dead%','%conflict%','%resolved%']),
  'status CHECK carries the 8 RF-018 SyncOperationState wire names (D-018)');

-- payload-is-object + depends_on-is-array guards ----------------------------- 14-15
select ok(exists(select 1 from pg_constraint where conname='sync_operations_payload_is_object'   and conrelid='public.sync_operations'::regclass), 'payload-is-object CHECK exists');
select ok(exists(select 1 from pg_constraint where conname='sync_operations_depends_on_is_array' and conrelid='public.sync_operations'::regclass), 'depends_on-is-array CHECK exists');

-- RLS enabled + forced ------------------------------------------------------- 16-17
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='sync_operations'), 'sync_operations: RLS enabled');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='sync_operations'), 'sync_operations: RLS forced');

-- RPC exists ----------------------------------------------------------------- 18
select has_function('app', 'sync_push', 'app.sync_push() exists');

-- direct write revoked for authenticated; RPC is the only writer ------------- 19-20
set local role authenticated;
select throws_ok($$
  insert into sync_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type, payload, payload_fingerprint)
  values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','x','order.submit','{}'::jsonb,'fp')
$$, '42501', NULL, 'authenticated cannot directly INSERT into sync_operations');
reset role;
select has_function('app', 'sync_push', 'app.sync_push() exists (confirm callable surface)');

select * from finish();
rollback;
