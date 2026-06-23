-- ============================================================================
-- RF-093 — Subscription/billing (basic): internal per-organization plan state
-- ============================================================================
-- Billing attaches to the ORGANIZATION (the tenant, D-003). RF-093 ships INTERNAL
-- plan/subscription state + a tenant-isolated entitlement surface only. There is
-- NO real payment provider, NO Stripe/external ids, NO checkout, NO webhooks, NO
-- invoices, NO tax/legal accounting, NO secrets (Q-016 billing model still
-- deferred). Money is integer _minor (D-007); placeholder prices are 0 (no real
-- pricing before Q-016). Plan assignment is MANUAL by a platform admin (audited,
-- separate plane, D-026); org_owner reads only; managers/cashiers/kitchen/KDS get
-- no billing access. Active call-site limit enforcement is DEFERRED — RF-093 ships
-- the entitlement/limit PRIMITIVE only.
-- ----------------------------------------------------------------------------

-- 1. plans — shared plan catalog (NOT tenant-scoped reference data).
create table public.plans (
  code           text        primary key check (length(btrim(code)) > 0),
  display_name   text        not null check (length(btrim(display_name)) > 0),
  price_minor    bigint      not null check (price_minor >= 0),               -- integer minor units (D-007); placeholder 0
  currency_code  char(3)     not null check (currency_code ~ '^[A-Z]{3}$'),
  max_branches   integer              check (max_branches is null or max_branches >= 0), -- null => unlimited
  is_active      boolean     not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

comment on table public.plans is
  'RF-093: shared (non-tenant) subscription plan catalog. price_minor is integer minor units (D-007); placeholder pricing 0 until the billing model (Q-016) is frozen. max_branches null => unlimited. Reference data: readable by authenticated, no tenant writes.';

create trigger plans_set_updated_at
  before update on public.plans for each row execute function app.set_updated_at();

-- Approved Q-016 placeholder catalog (internal, not real pricing).
insert into public.plans (code, display_name, price_minor, currency_code, max_branches, is_active) values
  ('free',  'Free',  0, 'ILS', 1,    true),
  ('basic', 'Basic', 0, 'ILS', null, true);

-- 2. organization_subscriptions — one row per organization (the billing unit).
create table public.organization_subscriptions (
  organization_id      uuid        primary key references public.organizations (id) on delete cascade,
  plan_code            text        not null references public.plans (code) on delete restrict,
  status               text        not null check (status in ('trialing', 'active', 'past_due', 'canceled')),
  current_period_start timestamptz,
  current_period_end   timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint organization_subscriptions_period_order
    check (current_period_start is null or current_period_end is null or current_period_end >= current_period_start)
);

comment on table public.organization_subscriptions is
  'RF-093: one subscription row per organization (billing attaches to the Organization, D-003). Mutated ONLY by app.set_organization_plan (platform-admin, audited); tenant direct writes are denied. Readable by org_owner/accountant within their org via RLS.';

create trigger organization_subscriptions_set_updated_at
  before update on public.organization_subscriptions for each row execute function app.set_updated_at();

-- ----------------------------------------------------------------------------
-- RLS + grants
-- ----------------------------------------------------------------------------
-- plans: reference data — authenticated may READ; no authenticated writes.
alter table public.plans enable row level security;
create policy plans_sel     on public.plans for select to authenticated using (true);
create policy plans_ins_deny on public.plans for insert to authenticated with check (false);
create policy plans_upd_deny on public.plans for update to authenticated using (false) with check (false);
create policy plans_del_deny on public.plans for delete to authenticated using (false);
grant select on public.plans to authenticated;

-- organization_subscriptions: org-scoped; SELECT only to org_owner/accountant in
-- the active org; all direct writes denied (only the DEFINER RPC, as owner, writes).
alter table public.organization_subscriptions enable row level security;
alter table public.organization_subscriptions force  row level security;
create policy organization_subscriptions_sel on public.organization_subscriptions for select to authenticated
  using (
    organization_id = app.current_org_id()
    and app.has_role_in_scope(organization_id, null, null, 'org_owner', 'accountant')
  );
create policy organization_subscriptions_ins_deny on public.organization_subscriptions for insert to authenticated with check (false);
create policy organization_subscriptions_upd_deny on public.organization_subscriptions for update to authenticated using (false) with check (false);
create policy organization_subscriptions_del_deny on public.organization_subscriptions for delete to authenticated using (false);
grant select on public.organization_subscriptions to authenticated;

-- 3. organization_entitlements — tenant-scoped read surface (plan + status + limits).
create view public.organization_entitlements
  with (security_invoker = true) as
select s.organization_id,
       s.plan_code,
       p.display_name              as plan_display_name,
       s.status                    as subscription_status,
       p.price_minor,
       p.currency_code,
       p.max_branches,
       s.current_period_start,
       s.current_period_end
from public.organization_subscriptions s
join public.plans p on p.code = s.plan_code;

comment on view public.organization_entitlements is
  'RF-093: tenant read surface for an organization''s plan/status/limits. security_invoker so the organization_subscriptions RLS applies (org_owner/accountant see their own org; managers/cashiers/kitchen/KDS and cross-tenant see nothing). Read-only.';

revoke all on public.organization_entitlements from public;
grant select on public.organization_entitlements to authenticated;

-- 4. app.org_plan_limit — entitlement/limit PRIMITIVE (future enforcement).
--    SECURITY INVOKER (default): reads organization_subscriptions under the
--    caller's RLS, so a caller not authorized for the org sees no row and gets
--    NULL — it cannot leak another org's limit. RF-093 does NOT wire call-site
--    blocking. Unknown p_key returns NULL.
create or replace function app.org_plan_limit(p_organization_id uuid, p_key text)
  returns integer
  language sql
  stable
  set search_path = ''
as $$
  select case
           when p_key = 'max_branches' then (
             select p.max_branches
             from public.organization_subscriptions s
             join public.plans p on p.code = s.plan_code
             where s.organization_id = p_organization_id
           )
           else null
         end
$$;

comment on function app.org_plan_limit(uuid, text) is
  'RF-093: entitlement/limit primitive (currently supports key "max_branches"). SECURITY INVOKER — reads organization_subscriptions under the caller''s RLS, so it returns the org''s own limit (or NULL when the caller is not authorized for that org, or for an unknown/unset key). Cannot leak another org''s limits. Read-only; RF-093 does not enforce at call sites.';

revoke all on function app.org_plan_limit(uuid, text) from public;
grant execute on function app.org_plan_limit(uuid, text) to authenticated;

-- 5. app.set_organization_plan — platform-admin manual assignment (audited).
create or replace function app.set_organization_plan(
  p_organization_id      uuid,
  p_plan_code            text,
  p_status               text,
  p_reason               text,
  p_current_period_start timestamptz default null,
  p_current_period_end   timestamptz default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor uuid;
  v_old   public.organization_subscriptions%rowtype;
begin
  -- reuse the RF-091 platform gate: active platform_admin grant + MFA aal2 +
  -- non-empty reason; returns the platform-admin actor (D-026, separate plane).
  v_actor := app.platform_admin_guard(p_reason);

  -- validation (read-only checks)
  if not exists (select 1 from public.organizations o where o.id = p_organization_id and o.deleted_at is null) then
    raise exception 'set_organization_plan: organization % not found', p_organization_id using errcode = '42501';
  end if;
  if not exists (select 1 from public.plans p where p.code = p_plan_code and p.is_active) then
    raise exception 'set_organization_plan: plan "%" is not an active plan', p_plan_code using errcode = '42501';
  end if;
  if p_status not in ('trialing', 'active', 'past_due', 'canceled') then
    raise exception 'set_organization_plan: invalid status "%"', p_status using errcode = '42501';
  end if;
  if p_current_period_start is not null and p_current_period_end is not null
     and p_current_period_end < p_current_period_start then
    raise exception 'set_organization_plan: current_period_end is before current_period_start' using errcode = '42501';
  end if;

  -- capture prior state (for audit), then upsert.
  select * into v_old from public.organization_subscriptions where organization_id = p_organization_id;

  insert into public.organization_subscriptions
    (organization_id, plan_code, status, current_period_start, current_period_end)
  values
    (p_organization_id, p_plan_code, p_status, p_current_period_start, p_current_period_end)
  on conflict (organization_id) do update set
    plan_code            = excluded.plan_code,
    status               = excluded.status,
    current_period_start = excluded.current_period_start,
    current_period_end   = excluded.current_period_end,
    updated_at           = now();

  -- audit on the separate platform plane (D-013); no secrets.
  insert into public.platform_admin_audit_events
    (actor_app_user_id, target_organization_id, action, reason, details)
  values
    (v_actor, p_organization_id, 'platform.org.plan_set', btrim(p_reason),
     jsonb_build_object(
       'old', case when v_old.organization_id is null then null
                   else jsonb_build_object('plan_code', v_old.plan_code, 'status', v_old.status) end,
       'new', jsonb_build_object('plan_code', p_plan_code, 'status', p_status,
                                 'current_period_start', p_current_period_start,
                                 'current_period_end', p_current_period_end)));

  return jsonb_build_object(
    'ok', true,
    'organization_id', p_organization_id,
    'plan_code', p_plan_code,
    'status', p_status,
    'server_ts', now());
end;
$$;

comment on function app.set_organization_plan(uuid, text, text, text, timestamptz, timestamptz) is
  'RF-093: platform-admin manual plan assignment for an organization. SECURITY DEFINER, search_path locked. Gated via app.platform_admin_guard (active platform grant + MFA aal2 + non-empty reason — D-026, never a tenant role). Validates org/plan/status/period, upserts organization_subscriptions, and writes a platform_admin_audit_events row (platform.org.plan_set, old/new). No payment provider, no secrets.';

revoke all on function app.set_organization_plan(uuid, text, text, text, timestamptz, timestamptz) from public;
grant execute on function app.set_organization_plan(uuid, text, text, text, timestamptz, timestamptz) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists app.set_organization_plan(uuid, text, text, text, timestamptz, timestamptz);
--   drop function if exists app.org_plan_limit(uuid, text);
--   drop view if exists public.organization_entitlements;
--   drop table if exists public.organization_subscriptions;
--   drop table if exists public.plans;
-- ============================================================================
