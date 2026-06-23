-- ============================================================================
-- RF-090 — pgTAP: input validation + auth gating
-- ============================================================================
-- Unauthenticated callers and invalid inputs are rejected (errcode 42501),
-- before any tenant rows are created.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(8);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000a0004', 'owner4@example.test');

-- unauthenticated (no JWT principal) -> rejected
select throws_ok(
  $$ select app.create_organization('55555555-5555-5555-5555-555555555555'::uuid,'O','o','R','B','USD','UTC',null) $$,
  '42501', null, 'unauthenticated caller is rejected');

-- become an authenticated principal for the input-validation cases
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a0004';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0004","email":"owner4@example.test","aal":"aal2"}';

select throws_ok(
  $$ select app.create_organization(null::uuid,'O','o','R','B','USD','UTC',null) $$,
  '42501', null, 'null client_request_id rejected');
select throws_ok(
  $$ select app.create_organization('66666666-6666-6666-6666-666666666666'::uuid,'   ','o','R','B','USD','UTC',null) $$,
  '42501', null, 'blank organization name rejected');
select throws_ok(
  $$ select app.create_organization('66666666-6666-6666-6666-666666666666'::uuid,'O','o','   ','B','USD','UTC',null) $$,
  '42501', null, 'blank restaurant name rejected');
select throws_ok(
  $$ select app.create_organization('66666666-6666-6666-6666-666666666666'::uuid,'O','o','R','   ','USD','UTC',null) $$,
  '42501', null, 'blank branch name rejected');
select throws_ok(
  $$ select app.create_organization('66666666-6666-6666-6666-666666666666'::uuid,'O','o','R','B','US','UTC',null) $$,
  '42501', null, 'invalid currency code rejected');
select throws_ok(
  $$ select app.create_organization('66666666-6666-6666-6666-666666666666'::uuid,'O','o','R','B','USD','Nowhere/Land',null) $$,
  '42501', null, 'invalid timezone rejected');
select throws_ok(
  $$ select app.create_organization('66666666-6666-6666-6666-666666666666'::uuid,'O','Bad Slug','R','B','USD','UTC',null) $$,
  '42501', null, 'invalid slug (uppercase/space) rejected');

select * from finish();
rollback;
