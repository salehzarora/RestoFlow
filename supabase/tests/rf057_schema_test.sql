-- ============================================================================
-- RF-057 — pgTAP schema test
-- ============================================================================
-- app.sync_pull exists, is SECURITY DEFINER, executable by authenticated; the
-- internal app.sync_pull_changes helper exists but is NOT client-callable. RF-057
-- adds only functions (no new tables, no ALTERs) — the clean `supabase db reset`
-- replay of the prior migrations is the no-regression gate.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(6);

-- the two functions exist ---------------------------------------------------- 1-2
select has_function('app', 'sync_pull',         'app.sync_pull() exists');
select has_function('app', 'sync_pull_changes', 'app.sync_pull_changes() internal helper exists');

-- sync_pull is SECURITY DEFINER ---------------------------------------------- 3
select is(
  (select prosecdef from pg_proc where proname='sync_pull' and pronamespace='app'::regnamespace and pronargs=5),
  true, 'app.sync_pull is SECURITY DEFINER');

-- sync_pull is executable by authenticated ----------------------------------- 4
select ok(
  has_function_privilege('authenticated', 'app.sync_pull(uuid, uuid, text[], jsonb, integer)', 'execute'),
  'authenticated may EXECUTE app.sync_pull');

-- the internal helper is NOT client-callable --------------------------------- 5-6
select ok(
  not has_function_privilege('authenticated', 'app.sync_pull_changes(text, uuid, uuid, timestamptz, uuid, integer)', 'execute'),
  'authenticated may NOT execute the internal app.sync_pull_changes helper');
select ok(
  not has_function_privilege('public', 'app.sync_pull(uuid, uuid, text[], jsonb, integer)', 'execute'),
  'PUBLIC may NOT execute app.sync_pull (revoked)');

select * from finish();
rollback;
