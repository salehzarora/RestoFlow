-- ============================================================================
-- RF-150 — pgTAP E2E: two owners self-serve onboard (public.create_organization),
-- each configures a printer (public.upsert_printer_device), and NEITHER can see or
-- touch the OTHER tenant's printer. Composes the two RF-150 surfaces and proves
-- cross-tenant isolation end-to-end (Phase 10 item 8; RISK R-003, D-001/D-012).
-- ============================================================================
-- Onboarding runs on the JWT path (auth.uid()); printer configuration runs as the
-- freshly-created org_owner via the GUC test path (auth.uid() cleared => GUC
-- fallback), with the dynamically-generated org/app_user ids fed through set_config.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(9);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000e2a0001', 'rf150e2e-owner-a@example.test'),
  ('00000000-0000-0000-0000-00000e2b0001', 'rf150e2e-owner-b@example.test');

-- ===== owner A self-serve onboards =============================================
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000e2a0001';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000e2a0001","email":"rf150e2e-owner-a@example.test","aal":"aal2"}';
create temp table e2e_a as select public.create_organization(
  '1a1a1a1a-1a1a-1a1a-1a1a-1a1a1a1a1a1a'::uuid,
  'E2E Org A', 'rf150e2e-a', 'Rest A', 'Branch A', 'USD', 'Asia/Jerusalem', 'Grill') as res;
reset role;

-- ===== owner B self-serve onboards ============================================
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000e2b0001';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000e2b0001","email":"rf150e2e-owner-b@example.test","aal":"aal2"}';
create temp table e2e_b as select public.create_organization(
  '1b1b1b1b-1b1b-1b1b-1b1b-1b1b1b1b1b1b'::uuid,
  'E2E Org B', 'rf150e2e-b', 'Rest B', 'Branch B', 'EUR', 'Asia/Jerusalem', 'Grill') as res;
reset role;

create temp table e2e_ctx as
  select (a.res->>'organization_id')::uuid as org_a, (a.res->>'restaurant_id')::uuid as rest_a,
         (a.res->>'branch_id')::uuid as branch_a, (a.res->>'app_user_id')::uuid as usr_a,
         (b.res->>'organization_id')::uuid as org_b, (b.res->>'restaurant_id')::uuid as rest_b,
         (b.res->>'branch_id')::uuid as branch_b, (b.res->>'app_user_id')::uuid as usr_b
  from e2e_a a, e2e_b b;
-- the context temp table is built as the connection role; let `authenticated`
-- read it (the printer blocks below reference it while acting as an owner).
grant select on e2e_ctx to authenticated;

-- (1-2) both onboardings succeeded into DISTINCT organizations
select is((select (res->>'ok')::boolean from e2e_a) and (select (res->>'ok')::boolean from e2e_b), true,
          'both owners onboarded ok via public.create_organization');
select isnt((select org_a from e2e_ctx), (select org_b from e2e_ctx),
          'the two self-serve signups produced DISTINCT organizations');

-- helper: act as a freshly-onboarded owner via the GUC fallback (clear the JWT so
-- auth.uid() is null => app.current_app_user_id() uses the GUC).
-- ===== owner A configures a printer in org A ==================================
set local role authenticated;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{}';
select set_config('app.current_app_user_id',     (select usr_a::text from e2e_ctx), true);
select set_config('app.current_organization_id', (select org_a::text from e2e_ctx), true);
create temp table e2e_pa as select public.upsert_printer_device(
  (select org_a from e2e_ctx), (select rest_a from e2e_ctx), (select branch_a from e2e_ctx),
  null, 'A Kitchen', 'network', 'kitchen') as res;
reset role;
select is((select (res->>'ok')::boolean from e2e_pa), true, 'owner A configures a printer in org A (ok)');

-- ===== owner B configures a printer in org B ==================================
set local role authenticated;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{}';
select set_config('app.current_app_user_id',     (select usr_b::text from e2e_ctx), true);
select set_config('app.current_organization_id', (select org_b::text from e2e_ctx), true);
create temp table e2e_pb as select public.upsert_printer_device(
  (select org_b from e2e_ctx), (select rest_b from e2e_ctx), (select branch_b from e2e_ctx),
  null, 'B Kitchen', 'usb', 'receipt') as res;
reset role;
select is((select (res->>'ok')::boolean from e2e_pb), true, 'owner B configures a printer in org B (ok)');

-- (5-6) each org has exactly one printer, in its own org
select is((select count(*) from printer_devices where organization_id = (select org_a from e2e_ctx))::int, 1,
          'org A has exactly its own one printer');
select is((select count(*) from printer_devices where organization_id = (select org_b from e2e_ctx))::int, 1,
          'org B has exactly its own one printer');

-- (7) owner B (acting in org B) sees ONLY org B's printer via RLS, never org A's
set local role authenticated;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{}';
select set_config('app.current_app_user_id',     (select usr_b::text from e2e_ctx), true);
select set_config('app.current_organization_id', (select org_b::text from e2e_ctx), true);
select is((select count(*) from printer_devices)::int, 1,
          'owner B reads ONLY its own printer (RLS hides org A''s)');

-- (8) owner B CANNOT configure a printer into org A (cross-org structural 42501)
select throws_ok(
  format($f$ select public.upsert_printer_device(%L,%L,%L, null, 'Cross', 'network', 'kitchen') $f$,
         (select org_a from e2e_ctx), (select rest_a from e2e_ctx), (select branch_a from e2e_ctx)),
  '42501', NULL, 'owner B cannot configure a printer in org A (cross-org 42501)');
reset role;

-- (9) owner B cannot soft-delete org A's printer either
set local role authenticated;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{}';
select set_config('app.current_app_user_id',     (select usr_b::text from e2e_ctx), true);
select set_config('app.current_organization_id', (select org_b::text from e2e_ctx), true);
select throws_ok(
  format($f$ select public.soft_delete_printer_device(%L,%L,%L,%L) $f$,
         (select org_a from e2e_ctx), (select rest_a from e2e_ctx), (select branch_a from e2e_ctx),
         (select id from printer_devices where organization_id = (select org_a from e2e_ctx))),
  '42501', NULL, 'owner B cannot delete org A''s printer (cross-org 42501)');
reset role;

select * from finish();
rollback;
