-- ============================================================================
-- POS-OPERATIONS-SYNC-001 — CATALOG assertions for app/public.pos_order_snapshots
-- ============================================================================
-- The signature/ACL posture of the snapshot read was previously verified only by
-- hand against the live catalog. These assertions make it part of the clean
-- migration sequence's proof:
--
--   * exactly ONE executable function per schema, with the INTENDED 9-argument
--     signature — and, specifically, the superseded 7-argument DRAFT signature
--     (no p_before_at/p_before_id) does NOT exist. `create or replace` with a
--     different argument list OVERLOADS rather than replaces, and a surviving
--     draft overload would be a second executable SECURITY DEFINER entry point
--     with the OLD (ascending-window) paging contract.
--   * the app function is SECURITY DEFINER with search_path='' pinned; the public
--     wrapper is SECURITY INVOKER (it carries no authority of its own).
--   * PUBLIC and anon hold NO EXECUTE; authenticated holds it — on both.
--
-- Catalog-only: this file changes nothing and can never mutate data.
-- ============================================================================
begin;

select plan(14);

-- The one intended identity-argument list, verbatim.
create temp table expected_sig as
select 'p_pin_session_id uuid, p_device_id uuid, '
    || 'p_since_at timestamp with time zone DEFAULT NULL::timestamp with time zone, '
    || 'p_since_id uuid DEFAULT NULL::uuid, '
    || 'p_before_at timestamp with time zone DEFAULT NULL::timestamp with time zone, '
    || 'p_before_id uuid DEFAULT NULL::uuid, '
    || 'p_order_ids uuid[] DEFAULT NULL::uuid[], '
    || 'p_limit integer DEFAULT 50, p_window_days integer DEFAULT 2' as sig;

-- 1/2: exactly ONE function of the name in each schema — no overload of ANY
-- arity survives the clean migration sequence.
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'pos_order_snapshots'),
  1,
  'C1 exactly one app.pos_order_snapshots exists — no overload of any arity');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'pos_order_snapshots'),
  1,
  'C2 exactly one public.pos_order_snapshots exists — no overload of any arity');

-- 3/4: the surviving function carries EXACTLY the intended 9-arg signature.
select is(
  (select pg_get_function_identity_arguments(p.oid)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'pos_order_snapshots'),
  (select regexp_replace(sig, ' DEFAULT [^,]+', '', 'g') from expected_sig),
  'C3 app signature is the intended 9-argument one');
select is(
  (select pg_get_function_identity_arguments(p.oid)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'pos_order_snapshots'),
  (select regexp_replace(sig, ' DEFAULT [^,]+', '', 'g') from expected_sig),
  'C4 public wrapper signature matches the app signature');

-- 5/6: the superseded 7-argument DRAFT signature is GONE. to_regprocedure
-- resolves a specific signature or returns null — the strongest direct probe.
select is(
  to_regprocedure('app.pos_order_snapshots(uuid, uuid, timestamptz, uuid, uuid[], integer, integer)'),
  null::regprocedure,
  'C5 the superseded 7-arg app draft signature does not exist');
select is(
  to_regprocedure('public.pos_order_snapshots(uuid, uuid, timestamptz, uuid, uuid[], integer, integer)'),
  null::regprocedure,
  'C6 the superseded 7-arg public draft signature does not exist');

-- 7/8: security posture of the app function — DEFINER with a pinned empty
-- search_path (the standard hardening for every DEFINER function here).
select ok(
  (select p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'pos_order_snapshots'),
  'C7 app.pos_order_snapshots is SECURITY DEFINER');
select ok(
  (select p.proconfig @> array['search_path=""']
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'pos_order_snapshots'),
  'C8 app.pos_order_snapshots pins search_path to empty');

-- 9/10: the public wrapper is INVOKER (carries no authority) and pins its
-- search_path too.
select ok(
  (select not p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'pos_order_snapshots'),
  'C9 public.pos_order_snapshots is SECURITY INVOKER');
select ok(
  (select p.proconfig @> array['search_path=""']
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'pos_order_snapshots'),
  'C10 public.pos_order_snapshots pins search_path to empty');

-- 11-14: ACLs. PUBLIC and anon must hold NO EXECUTE on either function;
-- authenticated must hold it on both. has_function_privilege('anon', ...)
-- includes privileges anon would inherit from PUBLIC, so C11/C12 also prove the
-- PUBLIC revoke held.
select ok(
  not has_function_privilege('anon',
    (select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app' and p.proname = 'pos_order_snapshots'), 'execute'),
  'C11 anon (and therefore PUBLIC) cannot execute the app function');
select ok(
  not has_function_privilege('anon',
    (select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'pos_order_snapshots'), 'execute'),
  'C12 anon (and therefore PUBLIC) cannot execute the public wrapper');
select ok(
  has_function_privilege('authenticated',
    (select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app' and p.proname = 'pos_order_snapshots'), 'execute'),
  'C13 authenticated can execute the app function');
select ok(
  has_function_privilege('authenticated',
    (select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'pos_order_snapshots'), 'execute'),
  'C14 authenticated can execute the public wrapper');

select * from finish();
rollback;
