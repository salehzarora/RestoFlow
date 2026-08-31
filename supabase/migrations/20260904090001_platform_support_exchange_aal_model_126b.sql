-- ============================================================================
-- ADMIN-126B2 — SUPPORT HANDOFF AAL MODEL: aal2 is anchored at START, not
-- re-demanded at the Dashboard-origin EXCHANGE. NOT YET APPLIED HOSTED.
--
-- THE DEFECT THIS FIXES. platform_support_exchange required the CALLER'S
-- session to be aal2. But the exchange runs at the DASHBOARD origin, the admin
-- console is deliberately deployed on its OWN origin (one browser storage
-- scope per origin), and the Dashboard has no MFA flow — so a real operator at
-- the dashboard origin is always aal1 and every production exchange failed
-- closed with 42501. The headline flow could never work as deployed.
--
-- THE MODEL (smallest secure architecture; aal2 is NOT silently removed):
--   * START (admin origin) requires authenticated + ACTIVE platform grant +
--     verified aal2 + a typed reason — unchanged (app.platform_admin_guard).
--   * The 32-byte CSPRNG one-time token IS the cryptographic continuation of
--     that aal2-proven intent across origins: minted only after aal2, single
--     use, 60-second exchange window, SHA-256 hash-only storage.
--   * EXCHANGE (dashboard origin) requires: the SAME operator authenticated
--     (identity binding — token knowledge alone is never sufficient), a STILL-
--     ACTIVE platform grant (revocation window closed), an unspent token
--     within its window, an unexpired session. What it no longer demands is an
--     independent dashboard-origin aal2, which cannot exist without building a
--     Dashboard MFA surface — a larger attack surface than this model.
--   * No tenant membership is created at any point; reads stay bound to the
--     live session per call; end/expiry semantics unchanged.
--
-- THREAT MATRIX (each pinned in platform_support_exchange_aal_126b_test.sql):
--   stolen token, different operator      -> 42501 (identity binding)
--   unauthenticated dashboard             -> 42501
--   replay after success                  -> 42501 (status <> pending)
--   exchange window passed                -> 42501
--   platform grant revoked after start    -> 42501 (re-checked at exchange)
--   start WITHOUT aal2                    -> 42501 (unchanged)
--   exchange at aal1 by the SAME operator -> OK (the fix)
--
-- The function below is the applied 20260903090001 text with ONLY the aal
-- predicate removed (generator-asserted single substitution).
-- ============================================================================

create or replace function app.platform_support_exchange(p_token text)
  returns jsonb
  language plpgsql
  volatile
  security definer
  set search_path = ''
as $$
declare
  v_actor uuid := app.current_app_user_id();
  v_row   public.platform_support_sessions%rowtype;
  v_org   public.organizations%rowtype;
  v_rest  public.restaurants%rowtype;
begin
  if v_actor is null then
    raise exception 'platform support: authentication required' using errcode = '42501';
  end if;
  if coalesce(btrim(p_token), '') = '' then
    raise exception 'platform support: this handoff is not valid' using errcode = '42501';
  end if;

  -- Matched by HASH, and locked so two concurrent exchanges of one token cannot
  -- both win.
  select * into v_row
    from public.platform_support_sessions
   where token_hash = encode(extensions.digest(btrim(p_token), 'sha256'), 'hex')
   for update;

  -- Every failure below raises the SAME error on purpose: an attacker must not
  -- be able to tell "wrong token" from "already used" from "expired".
  if not found
     or v_row.platform_admin_app_user_id <> v_actor
     or v_row.status <> 'pending'
     or v_row.token_consumed_at is not null
     or v_row.expires_at <= now()
     or v_row.created_at + (app.platform_support_exchange_seconds() || ' seconds')::interval < now()
     -- re-checked AT EXCHANGE TIME: a grant revoked between start and exchange
     -- must close the door. ADMIN-126B2: assurance-level is anchored at
     -- START only - see the model note above this function.
     or not app.is_platform_admin()
  then
    raise exception 'platform support: this handoff is not valid' using errcode = '42501';
  end if;

  update public.platform_support_sessions
     set status = 'active', token_consumed_at = now()
   where id = v_row.id;

  select * into v_org  from public.organizations where id = v_row.target_organization_id;
  if v_row.target_restaurant_id is not null then
    select * into v_rest from public.restaurants where id = v_row.target_restaurant_id;
  end if;

  insert into public.platform_admin_audit_events
    (actor_app_user_id, target_organization_id, action, reason, details)
  values
    (v_actor, v_row.target_organization_id, 'platform.support.exchange', v_row.reason,
     jsonb_build_object('support_session_id', v_row.id));

  return jsonb_build_object(
    'ok', true,
    'support_session_id', v_row.id,
    'reason', v_row.reason,
    'expires_at', v_row.expires_at,
    'read_only', true,
    'organization', jsonb_build_object('id', v_org.id, 'name', v_org.name),
    'restaurant', case when v_rest.id is null then 'null'::jsonb
                       else jsonb_build_object('id', v_rest.id, 'name', v_rest.name) end,
    'server_ts', now());
end;
$$;

revoke all on function app.platform_support_exchange(text) from public;
revoke all on function app.platform_support_exchange(text) from anon;
grant execute on function app.platform_support_exchange(text) to authenticated;

-- DOWN (manual, documented only — forward-only per D-016): restore
-- app.platform_support_exchange from 20260903090001.
