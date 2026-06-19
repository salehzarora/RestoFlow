-- ============================================================================
-- RF-017 — pgTAP audit RLS isolation test  (RISK R-003, CRITICAL)
-- ============================================================================
-- Under the non-privileged `authenticated` role with the RF-015 GUCs
-- (app.current_app_user_id + app.current_organization_id, reused UNCHANGED):
--   * no tenant context => zero audit rows (deny-by-default);
--   * Org A user sees only Org A audit; cross-org read (and IDOR-by-id) denied;
--   * restaurant-scoped user sees only its restaurant's audit (not a sibling restaurant);
--   * branch-scoped user sees only its branch's audit (not a sibling branch);
--   * org-level audit rows (restaurant_id/branch_id NULL) are visible to in-org members;
--   * an out-of-org user cannot see another org's org-level audit row.
-- Fixtures inserted as the BYPASSRLS connection role; assertions run as authenticated.
-- audit_events has no FKs (soft uuid refs); org/restaurant/branch + memberships
-- are seeded so the RF-015 resolver/scope helpers can resolve context.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(15);

-- ---- Fixtures (connection role / BYPASSRLS) --------------------------------
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'a17-org-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'a17-org-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Restaurant A1'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a0', 'Restaurant A2'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Restaurant B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1'),
  ('00000000-0000-0000-0000-00000000a1b2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1b'),
  ('00000000-0000-0000-0000-00000000a2b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a2', 'Branch A2'),
  ('00000000-0000-0000-0000-00000000b1b1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'a17-org@example.test'),
  ('00000000-0000-0000-0000-00000000ee02', 'a17-ra1@example.test'),
  ('00000000-0000-0000-0000-00000000ee03', 'a17-ba1@example.test'),
  ('00000000-0000-0000-0000-00000000ee04', 'a17-orgb@example.test');
insert into memberships (app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', null,                                   null,                                   'org_owner'),
  ('00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null,                                   'cashier'),
  ('00000000-0000-0000-0000-00000000ee03', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-0000000000b0', null,                                   null,                                   'org_owner');

-- audit rows (soft uuid refs; actor set to satisfy the actor CHECK)
insert into audit_events (id, organization_id, restaurant_id, branch_id, actor_app_user_id, action) values
  ('00000000-0000-0000-0000-00000000ae00', '00000000-0000-0000-0000-0000000000a0', null,                                   null,                                   '00000000-0000-0000-0000-00000000ee01', 'org.event'),     -- Org A org-level
  ('00000000-0000-0000-0000-00000000ae01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee02', 'branch.event'),  -- Org A / RA1 / BA1
  ('00000000-0000-0000-0000-00000000ae02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b2', '00000000-0000-0000-0000-00000000ee02', 'branch.event'),  -- Org A / RA1 / BA1b
  ('00000000-0000-0000-0000-00000000ae03', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-00000000a2b1', '00000000-0000-0000-0000-00000000ee01', 'branch.event'),  -- Org A / RA2 / BA2
  ('00000000-0000-0000-0000-00000000aeb0', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1b1', '00000000-0000-0000-0000-00000000ee04', 'branch.event');  -- Org B

set local role authenticated;

-- deny-by-default ------------------------------------------------------------ 1
select is((select count(*) from audit_events)::int, 0, 'no tenant context: zero audit rows');

-- Org A org-wide member ------------------------------------------------------ 2-5
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee01';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from audit_events)::int, 4, 'org_owner @ Org A: sees all 4 Org A audit rows');
select is((select count(*) from audit_events where id = '00000000-0000-0000-0000-00000000aeb0')::int, 0, 'org_owner @ Org A: cannot read the Org B audit row (cross-org / IDOR)');
select is((select count(*) from audit_events where id = '00000000-0000-0000-0000-00000000ae00')::int, 1, 'org_owner @ Org A: CAN see the org-level (null restaurant/branch) row');
select is((select count(*) from audit_events where id = '00000000-0000-0000-0000-00000000ae03')::int, 1, 'org_owner @ Org A: sees the RA2 audit row (org-wide breadth)');

-- Org A restaurant-A1 scoped member ------------------------------------------ 6-9
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee02';
select is((select count(*) from audit_events where id = '00000000-0000-0000-0000-00000000ae01')::int, 1, 'RA1 cashier: sees the RA1/BA1 audit row');
select is((select count(*) from audit_events where id = '00000000-0000-0000-0000-00000000ae02')::int, 1, 'RA1 cashier: sees the RA1/BA1b audit row (restaurant-scoped covers both branches)');
select is((select count(*) from audit_events where id = '00000000-0000-0000-0000-00000000ae03')::int, 0, 'RA1 cashier: CANNOT read the RA2 audit row');
select is((select count(*) from audit_events)::int, 3, 'RA1 cashier: sees only org-level + RA1 audit rows (3)');

-- Org A branch-BA1 scoped member --------------------------------------------- 10-13
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee03';
select is((select count(*) from audit_events where id = '00000000-0000-0000-0000-00000000ae01')::int, 1, 'BA1 cashier: sees its own branch (BA1) audit row');
select is((select count(*) from audit_events where id = '00000000-0000-0000-0000-00000000ae02')::int, 0, 'BA1 cashier: CANNOT read the sibling branch (BA1b) audit row');
select is((select count(*) from audit_events where id = '00000000-0000-0000-0000-00000000ae00')::int, 1, 'BA1 cashier: CAN see the org-level audit row');
select is((select count(*) from audit_events)::int, 2, 'BA1 cashier: sees only org-level + own-branch audit rows (2)');

-- Out-of-org member ---------------------------------------------------------- 14-15
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee04';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000b0';
select is((select count(*) from audit_events where id = '00000000-0000-0000-0000-00000000ae00')::int, 0, 'Org B member: CANNOT see the Org A org-level audit row');
select is((select count(*) from audit_events)::int, 1, 'Org B member: sees only the Org B audit row');

select * from finish();
rollback;
