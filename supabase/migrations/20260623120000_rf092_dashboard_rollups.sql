-- ============================================================================
-- RF-092 — Owner/manager dashboard rollups (multi-restaurant/branch)
-- ============================================================================
-- Two read-only aggregation views over the RF-075 per-branch report
-- (public.daily_branch_sales_report). They roll the per-branch integer _minor
-- buckets up to the restaurant and organization grain for the owner/manager
-- dashboard (D-002). NO new tables, NO money/tax recompute (pure integer SUM),
-- NO mutation, NO new RLS/role logic.
--
-- SCOPING: both views are `security_invoker = true` over a `security_invoker`
-- source, so RF-075's RF-059 SELECT gate (app.can_read_financials per branch)
-- applies AS THE CALLER through the whole chain. Therefore an org_owner /
-- restaurant_owner (org-wide membership) aggregates ALL their branches; a
-- branch-scoped manager aggregates ONLY their branch; kitchen_staff / KDS /
-- cross-tenant callers get ZERO rows — with no role logic duplicated here. The
-- rollups reconcile to daily_branch_sales_report by construction (same columns,
-- summed). The platform plane (RF-091) is untouched and separate.
-- ----------------------------------------------------------------------------

-- 1. Organization-level daily rollup: one row per (org, business_day, currency).
create view public.dashboard_org_daily_sales
  with (security_invoker = true) as
select b.organization_id,
       b.business_day,
       b.currency_code,
       count(distinct b.restaurant_id)        as restaurant_count,
       count(distinct b.branch_id)            as branch_count,
       sum(b.order_count)                      as order_count,
       sum(b.gross_minor)                      as gross_minor,
       sum(b.discount_total_minor)             as discount_total_minor,
       sum(b.net_sales_minor)                  as net_sales_minor,
       sum(b.tax_total_minor)                  as tax_total_minor,
       sum(b.void_count)                       as void_count,
       sum(b.void_total_minor)                 as void_total_minor,
       sum(b.collected_total_minor)            as collected_total_minor,
       sum(b.collected_cash_minor)             as collected_cash_minor
from public.daily_branch_sales_report b
group by b.organization_id, b.business_day, b.currency_code;

comment on view public.dashboard_org_daily_sales is
  'RF-092: org-level daily dashboard rollup (one row per organization_id/business_day/currency_code) aggregating public.daily_branch_sales_report. security_invoker so RF-075/RF-059 scoping applies as the caller (org_owner sees all visible branches; branch-scoped manager sees only their branch; kitchen_staff/KDS/cross-tenant see nothing). Integer _minor sums; reconciles to RF-075 by construction. Read-only.';

-- 2. Restaurant-level daily rollup: one row per (org, restaurant, business_day, currency).
create view public.dashboard_restaurant_daily_sales
  with (security_invoker = true) as
select b.organization_id,
       b.restaurant_id,
       b.business_day,
       b.currency_code,
       count(distinct b.branch_id)            as branch_count,
       sum(b.order_count)                      as order_count,
       sum(b.gross_minor)                      as gross_minor,
       sum(b.discount_total_minor)             as discount_total_minor,
       sum(b.net_sales_minor)                  as net_sales_minor,
       sum(b.tax_total_minor)                  as tax_total_minor,
       sum(b.void_count)                       as void_count,
       sum(b.void_total_minor)                 as void_total_minor,
       sum(b.collected_total_minor)            as collected_total_minor,
       sum(b.collected_cash_minor)             as collected_cash_minor
from public.daily_branch_sales_report b
group by b.organization_id, b.restaurant_id, b.business_day, b.currency_code;

comment on view public.dashboard_restaurant_daily_sales is
  'RF-092: restaurant-level daily dashboard rollup (one row per organization_id/restaurant_id/business_day/currency_code) aggregating public.daily_branch_sales_report. security_invoker so RF-075/RF-059 scoping applies as the caller (a branch-scoped manager aggregates only their branch within the restaurant). Integer _minor sums; reconciles to RF-075. Read-only.';

-- Grants: authenticated only (RLS on the underlying RF-075 view still constrains
-- which rows aggregate). anon is not granted.
revoke all on public.dashboard_org_daily_sales        from public;
revoke all on public.dashboard_restaurant_daily_sales from public;
grant select on public.dashboard_org_daily_sales        to authenticated;
grant select on public.dashboard_restaurant_daily_sales to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop view if exists public.dashboard_restaurant_daily_sales;
--   drop view if exists public.dashboard_org_daily_sales;
-- ============================================================================
