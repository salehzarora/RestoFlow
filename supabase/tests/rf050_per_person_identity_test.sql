-- ============================================================================
-- RF-050 — pgTAP: per-person identity / no shared auth principal (AC#2)
-- ============================================================================
-- AC#2: per-person identity, no shared accounts (DECISION D-004). Proves the
-- structural binding RF-050 adds:
--   * app_users.auth_user_id exists and is NULLABLE (PIN-only/local staff);
--   * a UNIQUE index enforces one Supabase auth principal -> at most one app_user;
--   * two app_users cannot share an auth principal (23505 unique_violation);
--   * app_users.email is still UNIQUE (no shared-email login);
--   * multiple PIN-only app_users (NULL auth_user_id) are allowed (not blocked);
--   * the resulting fixture contains NO shared auth principal.
-- Runs as the BYPASSRLS connection role so FORCE RLS never masks a raw
-- constraint error (constraints bind every role), mirroring rf015_constraints_test.
-- SQLSTATE: 23505 unique_violation.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(9);

-- ---- catalog: the binding column + its UNIQUE index exist ------------------
select has_column('public', 'app_users', 'auth_user_id', 'app_users.auth_user_id exists (RF-050 auth principal link)');     -- 1
select col_is_null('public', 'app_users', 'auth_user_id', 'app_users.auth_user_id is nullable (PIN-only/local staff)');      -- 2
select is(
  (select indisunique from pg_index where indexrelid = 'public.app_users_auth_user_id_key'::regclass),
  true,
  'app_users_auth_user_id_key is a UNIQUE index (one auth principal -> one app_user)');                                      -- 3

-- ---- fixtures: two auth principals; one linked app_user --------------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000a0001', 'person-one@example.test'),
  ('00000000-0000-0000-0000-0000000a0002', 'person-two@example.test');
insert into app_users (id, email, auth_user_id) values
  ('00000000-0000-0000-0000-00000000ee01', 'person-one@example.test', '00000000-0000-0000-0000-0000000a0001');

-- 4. two app_users CANNOT share one auth principal (no shared login; D-004) --
select throws_ok(
  $$ insert into app_users (email, auth_user_id)
     values ('alias@example.test', '00000000-0000-0000-0000-0000000a0001') $$,
  '23505', NULL,
  'a second app_user cannot reuse an auth principal (unique auth_user_id; D-004 no shared accounts)');                       -- 4

-- 5. email uniqueness still prevents a shared-email login --------------------
select throws_ok(
  $$ insert into app_users (email, auth_user_id)
     values ('person-one@example.test', '00000000-0000-0000-0000-0000000a0002') $$,
  '23505', NULL,
  'app_users.email remains UNIQUE (no shared-email login)');                                                                -- 5

-- 6. multiple PIN-only/local app_users (NULL auth_user_id) are allowed -------
select lives_ok(
  $$ insert into app_users (email, auth_user_id) values
       ('pin-only-a@example.test', null),
       ('pin-only-b@example.test', null) $$,
  'multiple app_users may have NULL auth_user_id (PIN-only staff not blocked by the partial-unique index)');                -- 6

-- 7. a distinct second principal links cleanly to a distinct app_user --------
select lives_ok(
  $$ insert into app_users (email, auth_user_id)
     values ('person-two@example.test', '00000000-0000-0000-0000-0000000a0002') $$,
  'a distinct auth principal links to a distinct app_user');                                                                -- 7

-- 8. no app_user shares an auth principal in the resulting fixture -----------
select is(
  (select count(distinct auth_user_id) from app_users where auth_user_id is not null)::int,
  (select count(*) from app_users where auth_user_id is not null)::int,
  'every non-null auth_user_id in app_users is distinct (no shared auth principal)');                                       -- 8

-- 9. no app_user shares an email in the resulting fixture --------------------
select is(
  (select count(distinct email) from app_users)::int,
  (select count(*) from app_users)::int,
  'every email in app_users is distinct (no shared-email login in the fixture)');                                          -- 9

select * from finish();
rollback;
