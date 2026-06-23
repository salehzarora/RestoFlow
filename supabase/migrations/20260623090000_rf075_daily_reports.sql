-- ============================================================================
-- RF-075 — Daily reports (sales, shift, voids/discounts) — per-branch summary
-- ============================================================================
-- Read-only reporting over the EXISTING authoritative tables (orders,
-- order_items, payments, shifts, cash_drawer_sessions, audit_events). No new
-- physical table, no stored report rows, no money recomputation.
--
-- Architecture (approved): three `security_invoker = true` VIEWS. Each scans the
-- base tables AS THE CALLER, so the RF-059 SELECT policies apply unchanged:
--   orders/order_items/payments/shifts/cash_drawer_sessions SELECT =
--     organization_id = app.current_org_id() AND
--     app.can_read_financials(org, restaurant, branch)
-- => a manager/restaurant_owner/org_owner/accountant/cashier sees only their own
--    org+branch rows; kitchen_staff and KDS/device-only principals (no active
--    financial membership) and cross-tenant callers get ZERO rows (AC2, T-003,
--    RISK R-003). audit_events SELECT uses has_scope (NOT financial), so the
--    void/discount-reason view adds an EXPLICIT app.can_read_financials() guard
--    (defence in depth) so kitchen_staff cannot read reasons either.
--
-- Money (D-007/D-008): integer *_minor only; SUM authoritative columns; never
-- recompute tax/money. Voided/cancelled orders are excluded from sales and
-- reported in a separate voids bucket (a voided order has no completed payment —
-- RF-062). Tax is a passthrough of stored tax_total_minor.
--
-- Business day: orders/payments/shifts/audit are bucketed by their OWN server
-- timestamp (orders.created_at, payments.created_at, shifts.opened_at,
-- audit_events.occurred_at) converted to the branch-local date using
-- COALESCE(branches.timezone, restaurants.timezone). Rows whose branch+restaurant
-- both lack a timezone are EXCLUDED (no silent UTC mis-bucketing) — configure a
-- timezone to include them.
--
-- AC1 reconciliation: every bucket is an integer SUM of persisted columns, so a
-- report row reconciles to the underlying orders/payments with exactly zero
-- drift. AC3: void/discount reasons + operator + type/value come from
-- audit_events (order.voided / order.discount_applied), per D-013.
-- ----------------------------------------------------------------------------

-- ============================================================================
-- View 1 — daily_branch_sales_report: one row per (org, restaurant, branch,
-- business_day, currency) with sales/discount/tax/void/collected buckets.
-- ============================================================================
create view public.daily_branch_sales_report
  with (security_invoker = true) as
with branch_tz as (
  select b.organization_id,
         b.restaurant_id,
         b.id                                   as branch_id,
         coalesce(b.timezone, r.timezone)       as zone
  from public.branches b
  join public.restaurants r
    on r.organization_id = b.organization_id
   and r.id              = b.restaurant_id
  where b.deleted_at is null
),
order_day as (
  select o.organization_id,
         o.restaurant_id,
         o.branch_id,
         (o.created_at at time zone t.zone)::date as business_day,
         o.currency_code,
         o.id            as order_id,
         o.status,
         o.subtotal_minor,
         o.discount_total_minor,
         o.tax_total_minor,
         o.grand_total_minor
  from public.orders o
  join branch_tz t
    on t.organization_id = o.organization_id
   and t.branch_id       = o.branch_id
  where o.deleted_at is null
    and t.zone is not null
),
item_rollup as (
  -- per-order pre-discount gross + item-level discount (integer sums)
  select oi.order_id,
         sum(oi.line_total_minor + oi.line_discount_minor) as gross_minor,
         sum(oi.line_discount_minor)                       as item_discount_minor
  from public.order_items oi
  where oi.deleted_at is null
  group by oi.order_id
),
sales as (
  -- real sales = orders that are not voided/cancelled/draft
  select od.organization_id,
         od.restaurant_id,
         od.branch_id,
         od.business_day,
         od.currency_code,
         count(*)                                                   as order_count,
         coalesce(sum(ir.gross_minor), 0)                           as gross_minor,
         coalesce(sum(ir.item_discount_minor), 0)
           + coalesce(sum(od.discount_total_minor), 0)              as discount_total_minor,
         coalesce(sum(od.subtotal_minor - od.discount_total_minor), 0) as net_sales_minor,
         coalesce(sum(od.tax_total_minor), 0)                       as tax_total_minor
  from order_day od
  left join item_rollup ir on ir.order_id = od.order_id
  where od.status not in ('voided', 'cancelled', 'draft')
  group by od.organization_id, od.restaurant_id, od.branch_id, od.business_day, od.currency_code
),
voids as (
  select od.organization_id,
         od.restaurant_id,
         od.branch_id,
         od.business_day,
         od.currency_code,
         count(*)                          as void_count,
         coalesce(sum(od.grand_total_minor), 0) as void_total_minor
  from order_day od
  where od.status = 'voided'
  group by od.organization_id, od.restaurant_id, od.branch_id, od.business_day, od.currency_code
),
collected as (
  -- only COMPLETED payments are money actually taken (cash only in MVP)
  select p.organization_id,
         p.restaurant_id,
         p.branch_id,
         (p.created_at at time zone t.zone)::date as business_day,
         p.currency_code,
         coalesce(sum(p.amount_minor), 0)                                          as collected_total_minor,
         coalesce(sum(p.amount_minor) filter (where p.method = 'cash'), 0)         as collected_cash_minor
  from public.payments p
  join branch_tz t
    on t.organization_id = p.organization_id
   and t.branch_id       = p.branch_id
  where p.deleted_at is null
    and p.status = 'completed'
    and t.zone is not null
  group by p.organization_id, p.restaurant_id, p.branch_id, (p.created_at at time zone t.zone)::date, p.currency_code
),
keys as (
  select organization_id, restaurant_id, branch_id, business_day, currency_code from sales
  union
  select organization_id, restaurant_id, branch_id, business_day, currency_code from voids
  union
  select organization_id, restaurant_id, branch_id, business_day, currency_code from collected
)
select k.organization_id,
       k.restaurant_id,
       k.branch_id,
       k.business_day,
       k.currency_code,
       coalesce(s.order_count, 0)            as order_count,
       coalesce(s.gross_minor, 0)            as gross_minor,
       coalesce(s.discount_total_minor, 0)   as discount_total_minor,
       coalesce(s.net_sales_minor, 0)        as net_sales_minor,
       coalesce(s.tax_total_minor, 0)        as tax_total_minor,
       coalesce(v.void_count, 0)             as void_count,
       coalesce(v.void_total_minor, 0)       as void_total_minor,
       coalesce(c.collected_total_minor, 0)  as collected_total_minor,
       coalesce(c.collected_cash_minor, 0)   as collected_cash_minor
from keys k
left join sales     s using (organization_id, restaurant_id, branch_id, business_day, currency_code)
left join voids     v using (organization_id, restaurant_id, branch_id, business_day, currency_code)
left join collected c using (organization_id, restaurant_id, branch_id, business_day, currency_code);

comment on view public.daily_branch_sales_report is
  'RF-075: per-branch-day sales/discount/tax/void/collected summary in integer _minor over orders/order_items/payments. security_invoker so RF-059 RLS (can_read_financials) scopes by org+branch and denies kitchen_staff/KDS/cross-tenant. Sales exclude voided/cancelled/draft; collected = completed payments. Buckets are integer SUMs (zero-drift reconciliation, AC1). Tax is passthrough (never recomputed).';

-- ============================================================================
-- View 2 — daily_branch_shift_lines: per-shift reconciliation lines for the
-- branch-day (bucketed by shift.opened_at). Authoritative expected/counted/
-- variance from RF-055; open shifts are provisional with null variance.
-- ============================================================================
create view public.daily_branch_shift_lines
  with (security_invoker = true) as
select s.organization_id,
       s.restaurant_id,
       s.branch_id,
       (s.opened_at at time zone coalesce(b.timezone, r.timezone))::date as business_day,
       s.id                              as shift_id,
       s.device_id,
       s.opened_by_employee_profile_id,
       s.status,
       s.opened_at,
       s.closed_at,
       s.reconciled_at,
       s.expected_total_minor,
       s.counted_total_minor,
       s.variance_minor,
       cds.opening_float_minor,
       (s.status not in ('closed', 'reconciled')) as is_provisional
from public.shifts s
join public.branches b
  on b.organization_id = s.organization_id
 and b.id              = s.branch_id
join public.restaurants r
  on r.organization_id = s.organization_id
 and r.id              = s.restaurant_id
left join public.cash_drawer_sessions cds
  on cds.organization_id = s.organization_id
 and cds.shift_id        = s.id
 and cds.deleted_at is null
where s.deleted_at is null
  and coalesce(b.timezone, r.timezone) is not null;

comment on view public.daily_branch_shift_lines is
  'RF-075: per-shift reconciliation lines (expected/counted/variance _minor from RF-055; drawer opening_float) for the branch-day, bucketed by shift.opened_at in branch timezone. security_invoker so RF-059 RLS gates financial access. Open shifts are is_provisional=true with null variance (never computed here).';

-- ============================================================================
-- View 3 — daily_branch_void_discount_reasons: AC3 reason/operator/type/value
-- sourced from audit_events. audit_events RLS uses has_scope (not financial), so
-- an EXPLICIT can_read_financials() guard keeps kitchen_staff out of this view.
-- ============================================================================
create view public.daily_branch_void_discount_reasons
  with (security_invoker = true) as
select ae.organization_id,
       ae.restaurant_id,
       ae.branch_id,
       (ae.occurred_at at time zone coalesce(b.timezone, r.timezone))::date as business_day,
       ae.occurred_at,
       ae.action,
       ae.reason,
       ae.actor_employee_profile_id                  as operator_employee_profile_id,
       ae.device_id,
       ae.new_values ->> 'scope'                     as discount_scope,
       ae.new_values ->> 'discount_type'             as discount_type,
       case when (ae.new_values ? 'value')
            then (ae.new_values ->> 'value')::bigint
            else null end                            as discount_value
from public.audit_events ae
join public.branches b
  on b.organization_id = ae.organization_id
 and b.id              = ae.branch_id
join public.restaurants r
  on r.organization_id = ae.organization_id
 and r.id              = ae.restaurant_id
where ae.action in ('order.voided', 'order.discount_applied')
  and ae.branch_id is not null
  and coalesce(b.timezone, r.timezone) is not null
  -- explicit financial gate (audit_events RLS is has_scope, not financial):
  and app.can_read_financials(ae.organization_id, ae.restaurant_id, ae.branch_id);

comment on view public.daily_branch_void_discount_reasons is
  'RF-075 (AC3, D-013): void/discount reason + operator + discount type/value per branch-day, sourced from audit_events (order.voided / order.discount_applied). security_invoker + an EXPLICIT app.can_read_financials() guard (audit_events RLS is has_scope-only) so kitchen_staff/KDS cannot read financial reasons.';

-- ----------------------------------------------------------------------------
-- Grants: authenticated only (RLS on the base tables still constrains rows).
-- anon is not granted; an anon/no-membership caller would also get zero rows
-- via can_read_financials, but least-privilege keeps the surface authenticated.
-- ----------------------------------------------------------------------------
revoke all on public.daily_branch_sales_report          from public;
revoke all on public.daily_branch_shift_lines           from public;
revoke all on public.daily_branch_void_discount_reasons from public;
grant select on public.daily_branch_sales_report          to authenticated;
grant select on public.daily_branch_shift_lines           to authenticated;
grant select on public.daily_branch_void_discount_reasons to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays from
-- empty). To reverse locally:
--   drop view if exists public.daily_branch_void_discount_reasons;
--   drop view if exists public.daily_branch_shift_lines;
--   drop view if exists public.daily_branch_sales_report;
-- ============================================================================
