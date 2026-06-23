-- ============================================================================
-- RF-093 — pgTAP: plan catalog (seed + integer money + read/write rules)
-- ============================================================================
-- free/basic are seeded with integer placeholder pricing (0) and the approved
-- max_branches shape; authenticated may READ the catalog but not write it.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(9);

set local role authenticated;

select is((select display_name from public.plans where code='free'), 'Free', 'free plan seeded');
select is((select price_minor from public.plans where code='free')::bigint, 0::bigint, 'free price_minor = 0 (integer minor units)');
select is((select max_branches from public.plans where code='free')::int, 1, 'free max_branches = 1');
select is((select price_minor from public.plans where code='basic')::bigint, 0::bigint, 'basic price_minor = 0');
select ok((select max_branches is null from public.plans where code='basic'), 'basic max_branches is null (unlimited)');
select cmp_ok((select count(*) from public.plans)::int, '>=', 2, 'authenticated can read the plan catalog');

-- authenticated cannot write the catalog (reference data; RLS deny)
select throws_ok($$ insert into public.plans (code, display_name, price_minor, currency_code) values ('hack','Hack',0,'ILS') $$, null, null, 'authenticated cannot INSERT plans');
select throws_ok($$ update public.plans set price_minor = 999 where code='free' $$, null, null, 'authenticated cannot UPDATE plans');
select throws_ok($$ delete from public.plans where code='free' $$, null, null, 'authenticated cannot DELETE plans');

select * from finish();
rollback;
