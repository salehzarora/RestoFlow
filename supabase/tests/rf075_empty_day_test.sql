-- ============================================================================
-- RF-075 — pgTAP: empty branch/day returns a stable empty result (not an error)
-- ============================================================================
-- A branch with a financial-role manager but NO orders/payments/shifts yields
-- zero report rows from every view, with no error.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(3);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf075e-a', 'USD');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1', 'UTC');
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee01', 'rf075e-mgr@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'manager');

set local role authenticated;
set local app.current_app_user_id     = '00000000-0000-0000-0000-00000000ee01';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';

select is((select count(*) from public.daily_branch_sales_report)::int,          0, 'empty day: sales report returns zero rows (no error)');
select is((select count(*) from public.daily_branch_shift_lines)::int,           0, 'empty day: shift lines returns zero rows (no error)');
select is((select count(*) from public.daily_branch_void_discount_reasons)::int, 0, 'empty day: void/discount reasons returns zero rows (no error)');

select * from finish();
rollback;
