-- ============================================================================
-- KITCHEN-MODE-001C1 — DORMANT kitchen print dispatch ledger + readiness
-- foundation for the printer-only kitchen workflow. ADDITIVE ONLY.
--
-- DEPLOY-AHEAD SAFE BY CONSTRUCTION:
--   * every dispatch-creating path is gated on branches.kitchen_workflow_mode
--     = 'printer_only' — a mode that NO production branch has, that NO setter
--     can produce (none exists; 001C3 ships the owner setter), and that no
--     app role can write directly (001A write-protection unchanged);
--   * the claim/pull RPC additionally requires a FRESH device readiness
--     report carrying capability 'kitchen_printer_only_v1' — which NO
--     deployed client reports — so production claims are impossible even if
--     a branch were privileged-flipped;
--   * kds-mode behavior of submit_order / add_order_items / void_order is
--     byte-identical (faithful re-creations; the dispatch tails are
--     mode-gated no-ops).
--
-- THE GUARANTEE THIS FOUNDATION EXISTS FOR: server acceptance and POS-local
-- durable persistence cannot share one transaction, so every accepted
-- printer-only kitchen event (initial order / service-round delta / void)
-- writes ONE durable, idempotent, MONEY-FREE dispatch row IN THE SAME
-- TRANSACTION as the acceptance itself. The POS later pulls-and-claims
-- atomically, imports into its (001C2) encrypted local spool, prints, and
-- acknowledges. A POS crash at any point recovers by re-pulling; local data
-- loss recovers from this ledger. Claimed/completed/client-status semantics
-- only — there is deliberately NO 'printed' boolean: transport acceptance is
-- never a physical-paper claim.
--
-- AUDIT NOTE (D-013): audit_events REQUIRES a human actor
-- (audit_events_actor_present). Dispatch creation runs inside PIN-session
-- RPCs and is audited (kitchen.dispatch_created / kitchen.dispatch_void_
-- created). The device-token RPCs (readiness / pull / ack) have NO human
-- actor and therefore CANNOT write audit rows — their observability lives in
-- the tables themselves (reported_at, claimed_at/claimed_by, completed_at,
-- last_client_status), surfaced by the inspection RPC.
--
-- Contents:
--   1.  branches.kitchen_workflow_mode_revision (consumed by the 001C3
--       setter; NOT bumped here — no setter exists).
--   2.  kitchen_printer_readiness_reports (one current report per device;
--       10-minute validity; fingerprint digest only — never an endpoint).
--   3.  app.kitchen_payload_offending_key — recursive money-free/PII guard.
--   4.  kitchen_print_dispatches + guard trigger + indexes + forced RLS.
--   5.  INTERNAL payload builders (initial / round-delta / void) — server
--       snapshots from authoritative rows, money-free by construction.
--   6.  INTERNAL app.create_kitchen_dispatch (idempotent; audits; supersedes
--       unclaimed priors on void).
--   7.  app.submit_order — faithful re-creation of 20260723090000:375-850
--       with the dormant initial-dispatch tail.
--   8.  app.add_order_items — faithful re-creation of 20260722090000:243-692
--       with the dormant round-dispatch tail.
--   9.  app.void_order — faithful re-creation of 20260722090000:1373-1642
--       (the NEWEST body: PSC-001D provenance + the PSC-001C round sweep)
--       with the dormant void-dispatch tail.
--   10. app.report_kitchen_printer_readiness (+wrapper) — device-token RPC.
--   11. app.pull_kitchen_print_dispatches (+wrapper) — atomic claim-and-pull.
--   12. app.acknowledge_kitchen_print_dispatch (+wrapper).
--   13. app.get_kitchen_workflow_transition_readiness (+wrapper) — read-only
--       member inspection of every mode-switch blocker.
--   14. Audit trio faithful re-creations (kitchen.% family).
--   15. app.sync_push — faithful re-creation of 20260722090000:1672-2370 with
--       ONE correction delta (order.submit only): after the ORDER-CUSTOMER-001
--       customer_name stamp, the initial kitchen dispatch payload is rebuilt
--       through the trusted internal builder in the SAME transaction, so the
--       REAL push path carries customer_display_name (CORRECTION-001).
--
-- KITCHEN-MODE-001C1-CORRECTION-001 (review REQUEST CHANGES, all folded into
-- this still-unshipped migration): real-path customer_display_name (via §15);
-- order_note in the initial payload; STICKY possibly_printed hold
-- (ambiguous_print_hold); one stable (created_at, type_rank, id) tuple for
-- both ORDER BY and the keyset cursor + truthful has_more/limit; token-
-- boundary key normalization (CamelCase/kebab/compact variants) + strict
-- prep_snapshot allowlist projection; VOID supersedes ALL unresolved priors
-- (claimed/failed/possibly_printed included — no resurrection); structural
-- composite FKs (order/branch, service round, claimed device, supersession +
-- self/cycle/void-target guard); unresolved rows never age out of read
-- surfaces; explicit anon revokes; QUALIFYING readiness selection (live POS
-- device, never shadowed by a newer non-qualifying report) + pull-side
-- mode-revision recheck; fail-closed branch-mode reads in the dispatch tails.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Branch mode revision (001C3 setter consumes it; nothing bumps it yet).
-- ----------------------------------------------------------------------------
alter table public.branches
  add column kitchen_workflow_mode_revision integer not null default 1
    constraint branches_kitchen_workflow_mode_revision_check
    check (kitchen_workflow_mode_revision > 0);

comment on column public.branches.kitchen_workflow_mode_revision is
  'KITCHEN-MODE-001C1: monotonic revision of kitchen_workflow_mode, bumped ONLY by the future owner setter (001C3) so stale mode-change requests and stale client caches can be rejected. No setter exists yet; direct app-role writes stay blocked by the 001A branches write-protection.';

-- CORRECTION-001 (structural integrity target): the authoritative composite
-- identity of an order INCLUDING its branch, so the dispatch ledger can tie
-- (organization_id, restaurant_id, branch_id, order_id) to ONE real order —
-- a cross-branch / cross-restaurant / cross-tenant order_id becomes
-- structurally impossible, not merely RPC-checked. Additive (id is already
-- the primary key, so the composite is trivially unique).
alter table public.orders
  add constraint orders_org_rest_branch_id_key
  unique (organization_id, restaurant_id, branch_id, id);

-- ----------------------------------------------------------------------------
-- 2. Device readiness reports (ONE current row per device, upserted; a report
--    is authoritative only while unexpired — reported_at + 10 minutes).
-- ----------------------------------------------------------------------------
create table public.kitchen_printer_readiness_reports (
  id                     uuid        not null default gen_random_uuid(),
  organization_id        uuid        not null references public.organizations (id) on delete restrict,
  restaurant_id          uuid        not null,
  branch_id              uuid        not null,
  device_id              uuid        not null,
  capability             text        not null check (capability = 'kitchen_printer_only_v1'),
  app_build              text        not null check (length(btrim(app_build)) between 1 and 64),
  printer_purpose        text        not null check (printer_purpose = 'kitchen_ticket'),
  transport_kind         text        not null check (transport_kind in ('network', 'bluetooth')),
  paper_width            text        not null check (paper_width in ('58mm', '80mm')),
  -- a NON-SECRET digest of the locally-selected endpoint identity: never a
  -- host, port, Bluetooth address, connection_config or credential.
  printer_fingerprint    text        not null check (printer_fingerprint ~ '^[0-9a-f]{16,128}$'),
  secure_spool_available boolean     not null,
  unresolved_local_jobs  integer     not null check (unresolved_local_jobs >= 0),
  mode_revision          integer     not null check (mode_revision > 0),
  reported_at            timestamptz not null default now(),
  expires_at             timestamptz not null,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  primary key (id),
  unique (organization_id, device_id),
  foreign key (organization_id, restaurant_id, branch_id)
    references public.branches (organization_id, restaurant_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id, device_id)
    references public.devices (organization_id, restaurant_id, branch_id, id) on delete restrict
);

comment on table public.kitchen_printer_readiness_reports is
  'KITCHEN-MODE-001C1: the POS''s device-session-proven kitchen-printing readiness report (capability kitchen_printer_only_v1, purpose kitchen_ticket, transport/paper facts, a NON-SECRET endpoint digest, local secure-spool availability and unresolved-job count). ONE current row per device (upsert); authoritative ONLY while unexpired (reported_at + 10 min — the RF-118 read-side-expiry house style). Readiness means "the transport accepted test bytes and the device reported its local state" — NEVER a physical-paper claim. Written only by app.report_kitchen_printer_readiness; no direct app-role access.';

alter table public.kitchen_printer_readiness_reports enable row level security;
alter table public.kitchen_printer_readiness_reports force row level security;
revoke all on table public.kitchen_printer_readiness_reports from public;
revoke all on table public.kitchen_printer_readiness_reports from anon;
revoke all on table public.kitchen_printer_readiness_reports from authenticated;
-- Explicit default-DENY policies (the sync_operations house pattern): access
-- is RPC-only; the grant revoke above already blocks direct reads (42501),
-- and these keep >=1 explicit policy per verb on the table (the RF-019
-- detector + RF-059 AC1 no-FOR-ALL-gap contract) and document the intent.
create policy kitchen_printer_readiness_reports_sel_deny on public.kitchen_printer_readiness_reports for select to authenticated using (false);
create policy kitchen_printer_readiness_reports_ins_deny on public.kitchen_printer_readiness_reports for insert to authenticated with check (false);
create policy kitchen_printer_readiness_reports_upd_deny on public.kitchen_printer_readiness_reports for update to authenticated using (false) with check (false);
create policy kitchen_printer_readiness_reports_del_deny on public.kitchen_printer_readiness_reports for delete to authenticated using (false);

-- ----------------------------------------------------------------------------
-- 3. Recursive MONEY-FREE / PII guard. Returns the FIRST offending key (a key
--    name is never sensitive) or NULL when the payload is clean. Values are
--    never inspected or returned; only keys are judged, so ordinary numeric
--    quantities always pass.
--
--    CORRECTION-001: keys are NORMALIZED to snake_case token form before
--    classification, so every key that carries a WORD BOUNDARY collapses to
--    the same tokens — unitPrice, Unit.Price, unit-price and unit_price all
--    become {unit, price} and are ONE key. Classification is TOKEN-BOUNDARY
--    matching — never broad substrings — so `tenderness`, `chicken_tenders`
--    and `tenderloin_name` stay legal while `taxAmount`, `serviceFee`,
--    `customerPhone`, `bluetoothAddress`, `apiKey` and `accessToken` are
--    hostile.
--
--    CORRECTION-001 (review cleanup): a COMPACT all-lowercase spelling that
--    carries NO boundary at all (unitprice / amountdue / apikey /
--    connectionconfig) does NOT split into the hostile single-word tokens, so
--    normalization alone would let it pass. Those compact compounds are
--    therefore enumerated EXPLICITLY as their own tokens in the deny array
--    below (exact whole-token spellings only — never substrings — so
--    `tenderness` and `chicken_tenders` are never affected).
-- ----------------------------------------------------------------------------
create or replace function app.kitchen_payload_normalize_key(p_key text)
  returns text
  language sql
  immutable
  set search_path = ''
as $$
  select btrim(
           regexp_replace(
             lower(
               regexp_replace(
                 regexp_replace(
                   regexp_replace(coalesce(p_key, ''), '([A-Z]+)([A-Z][a-z])', '\1_\2', 'g'),
                   '([a-z0-9])([A-Z])', '\1_\2', 'g'),
                 '[^A-Za-z0-9]+', '_', 'g')),
             '_{2,}', '_', 'g'),
           '_');
$$;

comment on function app.kitchen_payload_normalize_key(text) is
  'KITCHEN-MODE-001C1-CORRECTION-001 INTERNAL: canonical snake_case token form of a JSON key — token boundaries inserted at lower/digit->UPPER and ACRONYM->Word transitions, every non-alphanumeric run becomes one underscore, lowercased, collapsed, trimmed. unitPrice / unit-price / Unit.Price / unit_price all normalize identically to {unit, price}, so the payload guard cannot be bypassed by casing or separator games. NOTE: a COMPACT all-lowercase spelling with no boundary (unitprice) stays a single token and is caught by the explicit compact-compound deny list in app.kitchen_payload_offending_key, not here.';

revoke all on function app.kitchen_payload_normalize_key(text) from public;
revoke all on function app.kitchen_payload_normalize_key(text) from anon;
revoke all on function app.kitchen_payload_normalize_key(text) from authenticated;

create or replace function app.kitchen_payload_offending_key(p_value jsonb)
  returns text
  language plpgsql
  immutable
  set search_path = ''
as $$
declare
  v_key      text;
  v_norm     text;
  v_child    jsonb;
  v_found    text;
begin
  if p_value is null then
    return null;
  end if;
  if jsonb_typeof(p_value) = 'object' then
    for v_key, v_child in select * from jsonb_each(p_value) loop
      v_norm := app.kitchen_payload_normalize_key(v_key);
      -- (1) financial / privacy / endpoint / credential TOKENS at any token
      --     boundary of the normalized key ('minor' as a token also covers
      --     every *_minor spelling after normalization);
      -- (2) COMPACT all-lowercase compounds that carry no boundary to split on
      --     (unitprice / amountdue / apikey / connectionconfig / ...) — matched
      --     as WHOLE tokens (exact spellings, never substrings), so
      --     `tenderness` and `chicken_tenders` stay legal;
      -- (3) the api_key / connection_config compounds whose individual tokens
      --     are innocuous.
      if string_to_array(v_norm, '_') && array[
           'price', 'prices', 'subtotal', 'subtotals', 'total', 'totals',
           'paid', 'amount', 'amounts', 'change', 'currency', 'currencies',
           'payment', 'payments', 'tender', 'tendered', 'tax', 'taxes',
           'discount', 'discounts', 'tip', 'tips', 'fee', 'fees',
           'phone', 'phones', 'address', 'addresses', 'email', 'emails',
           'host', 'hosts', 'port', 'ports', 'token', 'tokens',
           'credential', 'credentials', 'secret', 'secrets',
           'password', 'passwords', 'minor',
           -- compact all-lowercase compounds (no case/separator boundary):
           'unitprice', 'priceminor', 'totalvalue', 'amountdue', 'paymentinfo',
           'taxamount', 'servicefee', 'tipamount', 'customerphone',
           'deliveryaddress', 'bluetoothaddress', 'connectionconfig',
           'apikey', 'accesstoken', 'currencycode', 'paymentmethod']
         or v_norm ~ '(^|_)api_keys?(_|$)'
         or v_norm ~ '(^|_)connection_configs?(_|$)'
      then
        return v_key;
      end if;
      v_found := app.kitchen_payload_offending_key(v_child);
      if v_found is not null then
        return v_found;
      end if;
    end loop;
    return null;
  elsif jsonb_typeof(p_value) = 'array' then
    for v_child in select * from jsonb_array_elements(p_value) loop
      v_found := app.kitchen_payload_offending_key(v_child);
      if v_found is not null then
        return v_found;
      end if;
    end loop;
    return null;
  end if;
  return null;
end;
$$;

comment on function app.kitchen_payload_offending_key(jsonb) is
  'KITCHEN-MODE-001C1: recursive KEY-ONLY inspection of a kitchen dispatch payload at every nesting level (objects and arrays). CORRECTION-001: each key is first normalized (app.kitchen_payload_normalize_key — CamelCase/PascalCase/kebab/dotted/spaced all collapse to snake_case tokens) and then judged by TOKEN-BOUNDARY matching against the closed money/financial/PII/endpoint/credential vocabulary, plus an EXPLICIT deny list of compact all-lowercase compounds (unitprice/amountdue/apikey/... — matched as whole tokens, never substrings, so tenderness/chicken_tenders stay legal) and the api_key / connection_config regex compounds and the minor token. Returns the first hostile ORIGINAL key or NULL when clean. Values are never judged, so numeric quantities always pass and harmless text values can never false-positive. INTERNAL — enforced by the kitchen_print_dispatches trigger on INSERT AND UPDATE.';

revoke all on function app.kitchen_payload_offending_key(jsonb) from public;
revoke all on function app.kitchen_payload_offending_key(jsonb) from anon;
revoke all on function app.kitchen_payload_offending_key(jsonb) from authenticated;

-- CORRECTION-001: STRICT ALLOWLIST projection of an order item's prep
-- snapshot. The supported prep component schema is {name, quantity, unit}
-- (KITCHEN-PREP-001); client-controlled JSON is NEVER embedded verbatim in a
-- dispatch — unknown/non-operational fields are ignored here (the tolerant
-- house convention; order validation itself is unchanged), text is trimmed
-- and bounded, and quantity survives only as a real JSON number.
-- CORRECTION-001 (review cleanup): name/unit survive ONLY when the value is a
-- real JSON STRING — an object/array/boolean/null value for name or unit is
-- DROPPED, never serialized to JSON text (so a prep element like
-- {"name": {"amountdue": 5}} can never smuggle a structured value in as text).
create or replace function app.kitchen_prep_projection(p_prep jsonb)
  returns jsonb
  language sql
  immutable
  set search_path = ''
as $$
  select case
    when p_prep is null or jsonb_typeof(p_prep) <> 'array' then null
    else (
      select nullif(coalesce(jsonb_agg(proj order by ord), '[]'::jsonb), '[]'::jsonb)
      from (
        select ord,
               jsonb_strip_nulls(jsonb_build_object(
                 'name',     case when jsonb_typeof(e.elem -> 'name') = 'string'
                                  then nullif(left(btrim(e.elem ->> 'name'), 120), '') end,
                 'quantity', case when jsonb_typeof(e.elem -> 'quantity') = 'number'
                                  then e.elem -> 'quantity' end,
                 'unit',     case when jsonb_typeof(e.elem -> 'unit') = 'string'
                                  then nullif(left(btrim(e.elem ->> 'unit'), 40), '') end)) as proj
        from jsonb_array_elements(p_prep) with ordinality as e(elem, ord)
        where jsonb_typeof(e.elem) = 'object'
      ) s
      where s.proj <> '{}'::jsonb
    )
  end;
$$;

comment on function app.kitchen_prep_projection(jsonb) is
  'KITCHEN-MODE-001C1-CORRECTION-001 INTERNAL: allowlisted kitchen projection of order_items.prep_snapshot — ONLY the supported {name, quantity, unit} operational fields survive (name<=120 / unit<=40 trimmed text, quantity only as a JSON number); unknown client keys are dropped and can never reach a dispatch payload; empty results collapse to NULL so the payload omits the prep key entirely.';

revoke all on function app.kitchen_prep_projection(jsonb) from public;
revoke all on function app.kitchen_prep_projection(jsonb) from anon;
revoke all on function app.kitchen_prep_projection(jsonb) from authenticated;

-- ----------------------------------------------------------------------------
-- 4. The dispatch ledger.
-- ----------------------------------------------------------------------------
create table public.kitchen_print_dispatches (
  id                        uuid        not null default gen_random_uuid(),
  organization_id           uuid        not null references public.organizations (id) on delete restrict,
  restaurant_id             uuid        not null,
  branch_id                 uuid        not null,
  order_id                  uuid        not null,
  service_round_id          uuid,
  dispatch_type             text        not null check (dispatch_type in ('initial_order', 'service_round', 'void')),
  payload_version           integer     not null default 1 check (payload_version > 0),
  money_free_payload        jsonb       not null check (jsonb_typeof(money_free_payload) = 'object'),
  target_purpose            text        not null default 'kitchen_ticket' check (target_purpose = 'kitchen_ticket'),
  idempotency_key           text        not null,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  claimed_at                timestamptz,
  claimed_by_device_id      uuid,
  claim_expires_at          timestamptz,
  completed_at              timestamptz,
  last_client_status        text        check (last_client_status is null or last_client_status in
                                               ('imported', 'transport_accepted', 'possibly_printed',
                                                'failed_retryable', 'blocked_configuration')),
  last_error_code           text        check (last_error_code is null or last_error_code ~ '^[a-z0-9_.\-]{1,64}$'),
  superseded_by_dispatch_id uuid,
  primary key (id),
  unique (organization_id, idempotency_key),
  -- CORRECTION-001: the supersession FK target (same org AND same order).
  unique (organization_id, order_id, id),
  constraint kitchen_print_dispatches_round_type check (
    (dispatch_type = 'service_round') = (service_round_id is not null)),
  constraint kitchen_print_dispatches_claim_shape check (
    (claimed_at is null) = (claimed_by_device_id is null)),
  constraint kitchen_print_dispatches_no_self_supersede check (
    superseded_by_dispatch_id is null or superseded_by_dispatch_id <> id),
  foreign key (organization_id, restaurant_id, branch_id)
    references public.branches (organization_id, restaurant_id, id) on delete restrict,
  -- CORRECTION-001 structural integrity: the order must be THE order of this
  -- exact org/restaurant/branch (cross-branch, cross-restaurant and
  -- cross-tenant order references are structurally impossible);
  foreign key (organization_id, restaurant_id, branch_id, order_id)
    references public.orders (organization_id, restaurant_id, branch_id, id) on delete restrict,
  -- ... a service-round dispatch must reference a round OF THAT ORDER
  -- (MATCH SIMPLE: null service_round_id — non-round dispatches — is exempt;
  -- the round_type CHECK above makes it mandatory for service_round rows);
  foreign key (organization_id, order_id, service_round_id)
    references public.order_service_rounds (organization_id, order_id, id) on delete restrict,
  -- ... a claim must belong to a REAL device of the same org/rest/branch
  -- (the RPC additionally enforces POS type + full liveness; RESTRICT keeps
  -- the operational ledger's history undeletable behind a claim);
  foreign key (organization_id, restaurant_id, branch_id, claimed_by_device_id)
    references public.devices (organization_id, restaurant_id, branch_id, id) on delete restrict,
  -- ... and supersession must point at a REAL dispatch of the SAME org and
  -- SAME order (self-reference blocked by the CHECK above; void-target and
  -- chain-length rules are enforced by the guard trigger).
  foreign key (organization_id, order_id, superseded_by_dispatch_id)
    references public.kitchen_print_dispatches (organization_id, order_id, id) on delete restrict
);

comment on table public.kitchen_print_dispatches is
  'KITCHEN-MODE-001C1: the durable server ledger guaranteeing every ACCEPTED printer-only kitchen event (initial order / service-round delta / void) has an idempotent MONEY-FREE dispatch created IN THE SAME TRANSACTION as the acceptance. The POS pulls-and-claims atomically (10-min claim expiry; stale claims reclaimable), imports into its encrypted local spool (001C2), prints, and acknowledges. claimed/completed/last_client_status semantics ONLY — deliberately NO printed boolean (transport acceptance is never a paper claim). Dispatch state is INDEPENDENT of order state. CORRECTION-001 retention contract: an UNRESOLVED row NEVER ages out of any read surface (it stays pullable and stays a transition blocker regardless of age); completed rows are permanent history in this phase (any pruning/archival of COMPLETED rows is a later, separate decision — never of unresolved ones). Structural FKs tie order/branch, service round, claimed device and supersession to authoritative rows. DORMANT: rows can only exist for printer_only branches (none exist; no setter until 001C3).';

create index kitchen_print_dispatches_pull_idx
  on public.kitchen_print_dispatches (organization_id, branch_id, created_at, id)
  where completed_at is null and superseded_by_dispatch_id is null;
create index kitchen_print_dispatches_order_idx
  on public.kitchen_print_dispatches (organization_id, order_id);

alter table public.kitchen_print_dispatches enable row level security;
alter table public.kitchen_print_dispatches force row level security;
revoke all on table public.kitchen_print_dispatches from public;
revoke all on table public.kitchen_print_dispatches from anon;
revoke all on table public.kitchen_print_dispatches from authenticated;
-- Explicit default-DENY policies (the sync_operations house pattern): access
-- is RPC-only; the grant revoke above already blocks direct reads (42501),
-- and these keep >=1 explicit policy per verb on the table (the RF-019
-- detector + RF-059 AC1 no-FOR-ALL-gap contract) and document the intent.
create policy kitchen_print_dispatches_sel_deny on public.kitchen_print_dispatches for select to authenticated using (false);
create policy kitchen_print_dispatches_ins_deny on public.kitchen_print_dispatches for insert to authenticated with check (false);
create policy kitchen_print_dispatches_upd_deny on public.kitchen_print_dispatches for update to authenticated using (false) with check (false);
create policy kitchen_print_dispatches_del_deny on public.kitchen_print_dispatches for delete to authenticated using (false);

create or replace function app.kitchen_print_dispatches_guard()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
declare
  v_bad          text;
  v_target_type  text;
  v_target_super uuid;
begin
  v_bad := app.kitchen_payload_offending_key(new.money_free_payload);
  if v_bad is not null then
    raise exception 'kitchen_print_dispatches: hostile payload key % rejected (money/PII/endpoint vocabulary is forbidden at every nesting level)', v_bad
      using errcode = '23514';
  end if;
  if pg_column_size(new.money_free_payload) > 32768 then
    raise exception 'kitchen_print_dispatches: payload exceeds the 32KB limit'
      using errcode = '23514';
  end if;
  -- CORRECTION-001 supersession shape: the target must be a VOID dispatch
  -- that is itself UNSUPERSEDED. Together with the composite FK (same org +
  -- same order) and the no-self CHECK, every supersession chain has length
  -- exactly 1 (row -> its order''s void), so cycles are structurally
  -- impossible — no walk can ever be needed.
  if new.superseded_by_dispatch_id is not null then
    select d.dispatch_type, d.superseded_by_dispatch_id
      into v_target_type, v_target_super
      from public.kitchen_print_dispatches d
      where d.id = new.superseded_by_dispatch_id
        and d.organization_id = new.organization_id;
    if v_target_type is not null and v_target_type <> 'void' then
      raise exception 'kitchen_print_dispatches: supersession target must be a VOID dispatch'
        using errcode = '23514';
    end if;
    if v_target_super is not null then
      raise exception 'kitchen_print_dispatches: supersession chains are forbidden (the target is itself superseded)'
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

comment on function app.kitchen_print_dispatches_guard() is
  'KITCHEN-MODE-001C1: BEFORE INSERT/UPDATE guard — recursive money-free/PII key enforcement (token-boundary matching on normalized keys) + ~32KB payload size cap + CORRECTION-001 supersession shape (target must be an unsuperseded VOID of the same org+order; with the composite FK and no-self CHECK every chain has length exactly 1, so cycles are structurally impossible). Fail-closed: a hostile payload aborts the surrounding mutation (an accepted printer-only event must be dispatchable or must not be accepted).';

revoke all on function app.kitchen_print_dispatches_guard() from public;
revoke all on function app.kitchen_print_dispatches_guard() from anon;
revoke all on function app.kitchen_print_dispatches_guard() from authenticated;

create trigger kitchen_print_dispatches_guard_trg
  before insert or update on public.kitchen_print_dispatches
  for each row execute function app.kitchen_print_dispatches_guard();

-- ----------------------------------------------------------------------------
-- 5. INTERNAL payload builders — server snapshots from AUTHORITATIVE rows in
--    the same transaction. Money-free BY CONSTRUCTION (no money column is
--    ever read); the trigger then re-proves it structurally.
--
--    CORRECTION-001 NOTE CAP: order_note (orders.notes) and each item note
--    (order_items.notes) are trimmed, omitted when empty, and bounded to 500
--    characters HERE — in the IMMUTABLE kitchen dispatch payload COPY ONLY.
--    The authoritative stored orders.notes / order_items.notes rows are NEVER
--    modified by these builders (they are pure read-side snapshots), so the
--    500-char cap is a physical-ticket display bound on the printed slip, not
--    a mutation of the order. A stored note longer than 500 chars keeps its
--    full length in the order; only its dispatch copy is capped.
-- ----------------------------------------------------------------------------
create or replace function app.kitchen_dispatch_payload_initial(
  p_organization_id uuid,
  p_order_id        uuid
)
  returns jsonb
  language sql
  stable
  set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'v', 1,
    'kind', 'initial_order',
    'order_code', '#' || upper(right(replace(o.id::text, '-', ''), 6)),
    'order_type', o.order_type,
    'table_label', tbl.label,
    'customer_display_name', nullif(left(btrim(coalesce(o.customer_name, '')), 80), ''),
    -- CORRECTION-001: the authoritative ORDER-LEVEL kitchen instruction (the
    -- same orders.notes the KDS workflow shows), trimmed, omitted when empty,
    -- bounded to a physical-ticket display cap. Initial slip only — a round
    -- delta ticket repeats items, not the standing order note.
    'order_note', nullif(left(btrim(coalesce(o.notes, '')), 500), ''),
    'created_at', o.created_at,
    'items', (
      select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
               'qty', oi.quantity,
               'name', oi.menu_item_name_snapshot,
               'note', nullif(left(btrim(coalesce(oi.notes, '')), 500), ''),
               'prep', app.kitchen_prep_projection(oi.prep_snapshot),
               'modifiers', (
                 select coalesce(jsonb_agg(jsonb_build_object(
                          'qty', om.quantity,
                          'name', om.option_name_snapshot)
                        order by om.created_at, om.id), '[]'::jsonb)
                 from public.order_item_modifiers om
                 where om.organization_id = oi.organization_id
                   and om.order_item_id = oi.id
                   and om.deleted_at is null)))
             order by oi.created_at, oi.id), '[]'::jsonb)
      from public.order_items oi
      where oi.organization_id = o.organization_id
        and oi.order_id = o.id
        and oi.service_round_id is null
        and oi.deleted_at is null)))
  from public.orders o
  left join public.tables tbl
    on tbl.organization_id = o.organization_id and tbl.id = o.table_id
  where o.organization_id = p_organization_id and o.id = p_order_id;
$$;

create or replace function app.kitchen_dispatch_payload_round(
  p_organization_id uuid,
  p_order_id        uuid,
  p_round_id        uuid
)
  returns jsonb
  language sql
  stable
  set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'v', 1,
    'kind', 'service_round',
    'order_code', '#' || upper(right(replace(o.id::text, '-', ''), 6)),
    'order_type', o.order_type,
    'table_label', tbl.label,
    'round_id', r.id,
    'round_number', r.round_number,
    'created_at', r.created_at,
    'items', (
      select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
               'qty', oi.quantity,
               'name', oi.menu_item_name_snapshot,
               'note', nullif(left(btrim(coalesce(oi.notes, '')), 500), ''),
               'prep', app.kitchen_prep_projection(oi.prep_snapshot),
               'modifiers', (
                 select coalesce(jsonb_agg(jsonb_build_object(
                          'qty', om.quantity,
                          'name', om.option_name_snapshot)
                        order by om.created_at, om.id), '[]'::jsonb)
                 from public.order_item_modifiers om
                 where om.organization_id = oi.organization_id
                   and om.order_item_id = oi.id
                   and om.deleted_at is null)))
             order by oi.created_at, oi.id), '[]'::jsonb)
      from public.order_items oi
      where oi.organization_id = o.organization_id
        and oi.order_id = o.id
        and oi.service_round_id = r.id
        and oi.deleted_at is null)))
  from public.orders o
  join public.order_service_rounds r
    on r.organization_id = o.organization_id and r.id = p_round_id and r.order_id = o.id
  left join public.tables tbl
    on tbl.organization_id = o.organization_id and tbl.id = o.table_id
  where o.organization_id = p_organization_id and o.id = p_order_id;
$$;

create or replace function app.kitchen_dispatch_payload_void(
  p_organization_id uuid,
  p_order_id        uuid,
  p_reason          text
)
  returns jsonb
  language sql
  stable
  set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'v', 1,
    'kind', 'void',
    'void', true,
    'order_code', '#' || upper(right(replace(o.id::text, '-', ''), 6)),
    'order_type', o.order_type,
    'table_label', tbl.label,
    'reason', nullif(left(btrim(coalesce(p_reason, '')), 200), ''),
    'voided_at', now(),
    'affected_item_count', (
      select count(*)::int from public.order_items oi
      where oi.organization_id = o.organization_id
        and oi.order_id = o.id and oi.deleted_at is null)))
  from public.orders o
  left join public.tables tbl
    on tbl.organization_id = o.organization_id and tbl.id = o.table_id
  where o.organization_id = p_organization_id and o.id = p_order_id;
$$;

comment on function app.kitchen_dispatch_payload_initial(uuid, uuid) is
  'KITCHEN-MODE-001C1 INTERNAL: the money-free initial-order kitchen snapshot (initial items only — service_round_id IS NULL). No money column is read; customer_display_name is optional, trimmed to 80 chars; CORRECTION-001 adds order_note (the authoritative orders.notes the KDS workflow shows — trimmed, <=500, omitted when empty; initial slip only) and routes prep through the strict allowlist projection; item notes are bounded the same way. Phone/address/payment data never exist here.';
comment on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) is
  'KITCHEN-MODE-001C1 INTERNAL: the money-free service-round DELTA snapshot (only that round''s items; the standing order_note stays on the initial slip and is deliberately NOT repeated). CORRECTION-001: bounded item notes + allowlisted prep projection.';
comment on function app.kitchen_dispatch_payload_void(uuid, uuid, text) is
  'KITCHEN-MODE-001C1 INTERNAL: the money-free VOID slip snapshot (marker + safe reason + counts; no items priced, no payment data).';

revoke all on function app.kitchen_dispatch_payload_initial(uuid, uuid) from public;
revoke all on function app.kitchen_dispatch_payload_initial(uuid, uuid) from anon;
revoke all on function app.kitchen_dispatch_payload_initial(uuid, uuid) from authenticated;
revoke all on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) from public;
revoke all on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) from anon;
revoke all on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) from authenticated;
revoke all on function app.kitchen_dispatch_payload_void(uuid, uuid, text) from public;
revoke all on function app.kitchen_dispatch_payload_void(uuid, uuid, text) from anon;
revoke all on function app.kitchen_dispatch_payload_void(uuid, uuid, text) from authenticated;

-- ----------------------------------------------------------------------------
-- 6. INTERNAL creator — idempotent (ON CONFLICT DO NOTHING on the logical
--    key), audits with the PIN-session actor (D-013), and on VOID supersedes
--    the order's unresolved prior dispatches (CORRECTION-001: ALL of them —
--    claimed / failed / possibly_printed included; no resurrection).
-- ----------------------------------------------------------------------------
create or replace function app.create_kitchen_dispatch(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid,
  p_order_id        uuid,
  p_round_id        uuid,
  p_dispatch_type   text,
  p_payload         jsonb,
  p_actor_employee_profile_id uuid,
  p_actor_membership_id       uuid,
  p_device_id       uuid
)
  returns uuid
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_key   text;
  v_id    uuid;
  v_code  text;
begin
  v_key := case p_dispatch_type
             when 'initial_order' then 'initial:' || p_order_id::text
             when 'service_round' then 'round:' || p_round_id::text
             else 'void:' || p_order_id::text
           end;

  insert into public.kitchen_print_dispatches
    (organization_id, restaurant_id, branch_id, order_id, service_round_id,
     dispatch_type, money_free_payload, idempotency_key)
  values
    (p_organization_id, p_restaurant_id, p_branch_id, p_order_id, p_round_id,
     p_dispatch_type, p_payload, v_key)
  on conflict (organization_id, idempotency_key) do nothing
  returning id into v_id;

  -- Idempotent retry: the logical dispatch already exists — reuse it, never
  -- duplicate, never audit twice.
  if v_id is null then
    select d.id into v_id from public.kitchen_print_dispatches d
      where d.organization_id = p_organization_id and d.idempotency_key = v_key;
    return v_id;
  end if;

  if p_dispatch_type = 'void' then
    -- CORRECTION-001: once a VOID exists, NO earlier dispatch for this order
    -- may ever become newly claimable or reclaimable — the void supersedes
    -- EVERY unresolved prior (unclaimed, actively claimed, failed_retryable,
    -- blocked_configuration, possibly_printed alike), preserving each row''s
    -- status/claim/observability untouched. A claim holder may still finish
    -- acknowledging what it already imported; the pull feed and stale-claim
    -- recovery skip superseded rows permanently. COMPLETED dispatches stay
    -- unlinked history: their paper may exist, and the VOID slip corrects it.
    update public.kitchen_print_dispatches d
      set superseded_by_dispatch_id = v_id, updated_at = now()
      where d.organization_id = p_organization_id
        and d.order_id = p_order_id
        and d.id <> v_id
        and d.completed_at is null
        and d.superseded_by_dispatch_id is null;
  end if;

  v_code := '#' || upper(right(replace(p_order_id::text, '-', ''), 6));
  insert into public.audit_events
    (organization_id, restaurant_id, branch_id, actor_app_user_id,
     actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values
    (p_organization_id, p_restaurant_id, p_branch_id, null,
     p_actor_employee_profile_id, p_device_id,
     case when p_dispatch_type = 'void'
          then 'kitchen.dispatch_void_created' else 'kitchen.dispatch_created' end,
     null, null,
     jsonb_build_object(
       'order_code', v_code,
       'dispatch_type', p_dispatch_type,
       'resolved_membership_id', p_actor_membership_id));

  return v_id;
end;
$$;

comment on function app.create_kitchen_dispatch(uuid, uuid, uuid, uuid, uuid, text, jsonb, uuid, uuid, uuid) is
  'KITCHEN-MODE-001C1 INTERNAL: creates ONE logical kitchen dispatch per authoritative event (idempotency key initial:<order>/round:<round>/void:<order>; ON CONFLICT DO NOTHING => retries reuse the same row and never re-audit). On void, supersedes EVERY unresolved prior dispatch of the order (CORRECTION-001 — unclaimed, claimed, failed_retryable, blocked_configuration and possibly_printed alike; statuses/claims/observability preserved; completed history stays unlinked), so no original can ever print after its void. Audits kitchen.dispatch_created/_void_created with the PIN-session actor (D-013). Runs INSIDE the caller''s transaction — a failure aborts the mutation (fail closed); a rollback leaves nothing. NEVER granted to client roles.';

revoke all on function app.create_kitchen_dispatch(uuid, uuid, uuid, uuid, uuid, text, jsonb, uuid, uuid, uuid) from public;
revoke all on function app.create_kitchen_dispatch(uuid, uuid, uuid, uuid, uuid, text, jsonb, uuid, uuid, uuid) from anon;
revoke all on function app.create_kitchen_dispatch(uuid, uuid, uuid, uuid, uuid, text, jsonb, uuid, uuid, uuid) from authenticated;

-- ----------------------------------------------------------------------------
-- 7. app.submit_order — faithful re-creation of 20260723090000 lines 375-850
--    with the dormant initial-dispatch tail (see header). Signature UNCHANGED.
-- ----------------------------------------------------------------------------

create or replace function app.submit_order(
  p_pin_session_id              uuid,
  p_order_id                    uuid,
  p_device_id                   uuid,
  p_local_operation_id          text,
  p_order_type                  text,
  p_table_id                    uuid,
  p_shift_id                    uuid,
  p_currency_code               text,
  p_notes                       text,
  p_order_items                 jsonb,
  p_client_subtotal_minor       bigint,
  p_client_discount_total_minor bigint,
  p_client_tax_total_minor      bigint,
  p_client_grand_total_minor    bigint,
  p_client_created_at           timestamptz default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org           uuid;
  v_rest          uuid;
  v_branch        uuid;
  v_dsid          uuid;
  v_emp           uuid;
  v_membership    uuid;
  v_ds_device     uuid;
  v_ds_active     boolean;
  v_ds_revoked    timestamptz;
  v_pairing_stat  text;
  v_role          text;
  v_m_status      text;
  v_m_deleted     timestamptz;
  v_m_rest        uuid;
  v_m_branch      uuid;
  v_existing_id   uuid;
  v_existing_rev  integer;
  v_item          jsonb;
  v_modifier      jsonb;
  v_item_id       uuid;
  v_qty           bigint;
  v_unit          bigint;
  v_line_disc     bigint;
  v_mod_qty       bigint;
  v_mod_price     bigint;
  v_mod_sum       bigint;
  v_line_total    bigint;
  v_subtotal      bigint := 0;
  v_grand         bigint;
  v_item_count    integer := 0;
  v_mod_count     integer := 0;
  v_unavailable   jsonb;
  v_item_ids      uuid[];
  -- KITCHEN-MODE-001A (all three used ONLY by the additive tail/replay below):
  v_kitchen_mode  text;
  v_auto          jsonb;
  v_existing_status text;
begin
  -- (1-5) PIN session: exists, valid (active/not-ended/not-expired), backing
  -- device session active + not revoked, pairing active. Scope + actor derived here.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps
    where ps.id = p_pin_session_id;
  if not found then
    raise exception 'submit_order: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'submit_order: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;

  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing_stat
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing_stat = 'active') then
    raise exception 'submit_order: backing device session/pairing is not active' using errcode = '42501';
  end if;

  -- (6) the caller's claimed device must be the device behind the PIN session
  if v_ds_device <> p_device_id then
    raise exception 'submit_order: device_id does not match the PIN session device' using errcode = '42501';
  end if;

  -- (9-14) membership: active, role permitted, scope covers the derived branch
  select m.role, m.status, m.deleted_at, m.restaurant_id, m.branch_id
    into v_role, v_m_status, v_m_deleted, v_m_rest, v_m_branch
    from public.memberships m
    where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'submit_order: resolved membership is not active' using errcode = '42501';
  end if;
  if v_role not in ('cashier', 'manager', 'restaurant_owner', 'org_owner') then
    raise exception 'submit_order: role % may not submit orders', v_role using errcode = '42501';
  end if;
  if not (v_m_rest is null or v_m_rest = v_rest) or not (v_m_branch is null or v_m_branch = v_branch) then
    raise exception 'submit_order: membership scope does not cover the order branch' using errcode = '42501';
  end if;
  -- NOTE: org/restaurant/branch are taken from the PIN session (v_org/v_rest/v_branch),
  -- NEVER from client input, so a cross-tenant submit is structurally impossible.

  -- (payload) basic shape + currency + order_type
  if p_order_items is null or jsonb_typeof(p_order_items) <> 'array' or jsonb_array_length(p_order_items) < 1 then
    raise exception 'submit_order: order_items must be a non-empty jsonb array' using errcode = '42501';
  end if;
  if p_order_type not in ('dine_in', 'takeaway') then
    raise exception 'submit_order: invalid order_type %', p_order_type using errcode = '42501';
  end if;
  if p_currency_code is null or p_currency_code !~ '^[A-Z]{3}$' then
    raise exception 'submit_order: currency_code must be a 3-letter ISO code' using errcode = '42501';
  end if;
  if p_client_discount_total_minor < 0 or p_client_tax_total_minor < 0
     or p_client_subtotal_minor < 0 or p_client_grand_total_minor < 0 then
    raise exception 'submit_order: order totals must be non-negative integers (minor units)' using errcode = '42501';
  end if;

  -- (payload+) RESTAURANT-OPERATIONS-V1-001 order-type table SHAPE rules —
  -- payload-stable, so they sit with the shape checks (before the replay
  -- lookup). RETURN-refusals, not raises: sync_push merges them VERBATIM so
  -- the POS can name the rule that fired (§4.35 error contract).
  if p_order_type = 'takeaway' and p_table_id is not null then
    -- takeaway never carries a table; a contradictory payload is refused, not
    -- silently "fixed" (the client's draft state is wrong and must say so).
    return jsonb_build_object('ok', false, 'error', 'table_not_allowed', 'entity', 'order');
  end if;
  if p_order_type = 'dine_in' and p_table_id is null then
    -- NEW dine-in orders require a table. Historical tableless dine-in rows
    -- remain valid (this rule binds acceptance, not stored data).
    return jsonb_build_object('ok', false, 'error', 'table_required', 'entity', 'order');
  end if;

  -- (money recompute) from the SUBMITTED SNAPSHOTS ONLY (never the live menu).
  -- Validate the per-line and order totals; reject any client/snapshot mismatch.
  for v_item in select * from jsonb_array_elements(p_order_items)
  loop
    v_qty       := app.order_parse_minor(v_item -> 'quantity', 'order_items[].quantity');
    -- bound to the integer column range so an absurd quantity yields a clean 42501
    -- rather than a raw 22003 on the ::int insert (and limits qty*price overflow risk).
    if v_qty <= 0 or v_qty > 2147483647 then
      raise exception 'submit_order: order_items[].quantity must be between 1 and 2147483647' using errcode = '42501';
    end if;
    v_unit      := app.order_parse_minor(v_item -> 'unit_price_minor_snapshot', 'order_items[].unit_price_minor_snapshot');
    v_line_disc := case when (v_item ? 'line_discount_minor') and jsonb_typeof(v_item -> 'line_discount_minor') <> 'null'
                        then app.order_parse_minor(v_item -> 'line_discount_minor', 'order_items[].line_discount_minor')
                        else 0 end;
    if (v_item ->> 'menu_item_id') is null then
      raise exception 'submit_order: order_items[].menu_item_id is required' using errcode = '42501';
    end if;
    if (v_item ->> 'menu_item_name_snapshot') is null then
      raise exception 'submit_order: order_items[].menu_item_name_snapshot is required' using errcode = '42501';
    end if;

    v_mod_sum := 0;
    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        if v_mod_qty <= 0 or v_mod_qty > 2147483647 then
          raise exception 'submit_order: modifiers[].quantity must be between 1 and 2147483647' using errcode = '42501';
        end if;
        v_mod_sum := v_mod_sum + v_mod_price * v_mod_qty;
      end loop;
    end if;

    v_line_total := v_qty * v_unit + v_mod_sum - v_line_disc;
    if v_line_total < 0 then
      raise exception 'submit_order: computed line_total_minor is negative' using errcode = '42501';
    end if;
    v_subtotal := v_subtotal + v_line_total;
  end loop;

  if p_client_subtotal_minor <> v_subtotal then
    raise exception 'submit_order: client subtotal_minor (%) does not match snapshot recompute (%)',
      p_client_subtotal_minor, v_subtotal using errcode = '42501';
  end if;
  v_grand := v_subtotal - p_client_discount_total_minor + p_client_tax_total_minor;
  if v_grand < 0 then
    raise exception 'submit_order: computed grand_total_minor is negative' using errcode = '42501';
  end if;
  if p_client_grand_total_minor <> v_grand then
    raise exception 'submit_order: client grand_total_minor (%) does not match snapshot recompute (%)',
      p_client_grand_total_minor, v_grand using errcode = '42501';
  end if;

  -- (idempotency) ONLY AFTER full validation: replay scoped to the validated
  -- (org, device, local_operation_id). Returns the same order; never re-inserts;
  -- never bypasses validation; never crosses tenants (org is session-derived).
  select o.id, o.revision, o.status into v_existing_id, v_existing_rev, v_existing_status
    from public.orders o
    where o.organization_id = v_org
      and o.device_id = p_device_id
      and o.local_operation_id = p_local_operation_id
    limit 1;
  if found then
    -- KITCHEN-MODE-001A (ADDITIVE keys only; existing keys byte-identical): the
    -- replay reports the CURRENT authoritative status, so a replayed zero-total
    -- printer-only submit consistently reads back `completed`. `auto_completed`
    -- on the replay path means "this order is completed NOW" — clients that
    -- predate the key ignore it.
    return jsonb_build_object(
      'ok', true, 'order_id', v_existing_id, 'revision', v_existing_rev,
      'server_ts', now(), 'idempotency_replay', true,
      'auto_completed', (v_existing_status = 'completed'),
      'order_status', v_existing_status);
  end if;

  -- (accept) RESTAURANT-OPERATIONS-V1-001 TIME-VARYING acceptance checks —
  -- deliberately AFTER the replay lookup (an already-accepted order must keep
  -- replaying even if its table or an item's availability changed since) and
  -- BEFORE any insert (a refusal never leaves a partial order).
  --
  -- (accept-1) the dine-in table must be a LIVE, ACTIVE, IN-SERVICE table of
  -- the SESSION branch. A foreign-branch, tombstoned, deactivated,
  -- out-of-service, or unknown table is the SAME refusal — the device learns
  -- nothing about other branches (R-003). STABILIZATION: out_of_service is a
  -- HARD manual floor state (a broken table); under a stale client list the
  -- picker's block is not enough, so the server refuses it too. reserved/
  -- occupied remain seatable (the reserving party arriving IS the seating).
  if p_order_type = 'dine_in' and not exists (
       select 1 from public.tables t
       where t.id              = p_table_id
         and t.organization_id = v_org
         and t.restaurant_id   = v_rest
         and t.branch_id       = v_branch
         and t.is_active
         and t.status <> 'out_of_service'
         and t.deleted_at is null) then
    return jsonb_build_object('ok', false, 'error', 'table_not_available', 'entity', 'order');
  end if;

  -- (accept-2) REVIEW CORRECTION (A1 + A2): every line item must be a REAL,
  -- SELLABLE item of the session menu — proven, not presumed — and AVAILABLE
  -- in the session branch, evaluated under a SHARED LOCK so an availability
  -- flip can never race past acceptance.
  --
  -- A1 — the CANONICAL sellability predicate, identical to what app.pos_menu
  -- serves the POS (order_items.menu_item_id is deliberately non-FK, so a
  -- stale or manipulated cart could previously submit an unknown, deleted,
  -- inactive, sibling-branch or foreign-scope id and still create an order):
  --   item:     exists in v_org + v_rest, is_active, deleted_at IS NULL,
  --             branch-visible (branch_id IS NULL OR = v_branch);
  --   category: parent exists, is_active, deleted_at IS NULL, branch-visible;
  --   effective availability: no 'unavailable' override for (v_branch, item).
  -- Absence of an override means available ONLY once the item is proven
  -- sellable. ALL non-sellable cases fail closed as ONE indistinguishable
  -- refusal (error item_unavailable, reason 'unavailable') so nothing —
  -- sibling-branch pins included — becomes an existence oracle (R-003).
  -- Explicit overrides keep their structured reason (sold_out|paused). The
  -- name echoed back is the CLIENT'S OWN payload snapshot, never DB data.
  -- D-008 is untouched: nothing here reprices from the live menu.
  --
  -- A2 — the TOCTOU serialization point: lock the CANONICAL menu_items rows
  -- (the same rows app.menu_set_item_availability locks) BEFORE evaluating.
  -- Locking the override row would not work — it may not exist yet. Locks are
  -- taken in one statement in DETERMINISTIC ascending id order, so two carts
  -- sharing items can never deadlock (and the setter locks exactly one row).
  -- Unknown/foreign ids match no row and take no lock — they fail the
  -- sellability check regardless, and there is nothing to serialize with.
  -- If the setter committed 'unavailable' first, this read (under lock) sees
  -- it and refuses; if this submit locked first, the setter WAITS until the
  -- accepted order commits and its change applies to later orders only.
  select array_agg(distinct (e ->> 'menu_item_id')::uuid)
    into v_item_ids
    from jsonb_array_elements(p_order_items) e;
  perform 1
    from public.menu_items i
    where i.organization_id = v_org
      and i.id = any (v_item_ids)
    order by i.id
    for update;

  select jsonb_agg(jsonb_build_object(
           'menu_item_id', blocked.menu_item_id,
           'name',         blocked.name,
           'reason',       blocked.reason)
           order by blocked.menu_item_id)
    into v_unavailable
    from (
      select li.menu_item_id,
             li.name,
             coalesce(a.reason, 'unavailable') as reason
        from (
          select (e ->> 'menu_item_id')::uuid as menu_item_id,
                 min(e ->> 'menu_item_name_snapshot') as name
            from jsonb_array_elements(p_order_items) e
            group by 1
        ) li
        left join public.menu_items i
          on i.id = li.menu_item_id
         and i.organization_id = v_org
         and i.restaurant_id   = v_rest
         and i.is_active
         and i.deleted_at is null
         and (i.branch_id is null or i.branch_id = v_branch)
        left join public.menu_categories c
          on c.id = i.menu_category_id
         -- REVIEW DELTA (HIGH): the category must belong to the EXACT session
         -- scope — org AND restaurant. The schema permits an item of
         -- restaurant A referencing a category of restaurant B in the same
         -- org; without the restaurant predicate such a hybrid item passed as
         -- sellable here while pos_menu's category list is restaurant-scoped.
         and c.organization_id = v_org
         and c.restaurant_id   = v_rest
         and c.is_active
         and c.deleted_at is null
         and (c.branch_id is null or c.branch_id = v_branch)
        left join public.menu_item_branch_availability a
          on a.organization_id = v_org
         and a.branch_id       = v_branch
         and a.menu_item_id    = li.menu_item_id
         and a.availability    = 'unavailable'
        where i.id is null            -- unknown / foreign / inactive / deleted / pinned elsewhere
           or c.id is null            -- category missing / inactive / deleted / not visible here
           or a.menu_item_id is not null  -- explicitly unavailable in this branch
    ) blocked;
  if v_unavailable is not null then
    return jsonb_build_object('ok', false, 'error', 'item_unavailable',
                              'entity', 'order', 'items', v_unavailable);
  end if;

  -- (insert) order header at status 'submitted'
  insert into public.orders (
    id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
    opened_by_employee_profile_id, resolved_membership_id, table_id, shift_id,
    order_type, status, currency_code,
    subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor,
    notes, local_operation_id, revision, client_created_at)
  values (
    p_order_id, v_org, v_rest, v_branch, p_device_id, p_pin_session_id,
    v_emp, v_membership, p_table_id, p_shift_id,
    p_order_type, 'submitted', p_currency_code,
    v_subtotal, p_client_discount_total_minor, p_client_tax_total_minor, v_grand,
    p_notes, p_local_operation_id, 1, p_client_created_at);

  -- (insert) items at status 'pending' + their modifiers, recomputing line_total
  for v_item in select * from jsonb_array_elements(p_order_items)
  loop
    v_qty       := app.order_parse_minor(v_item -> 'quantity', 'order_items[].quantity');
    v_unit      := app.order_parse_minor(v_item -> 'unit_price_minor_snapshot', 'order_items[].unit_price_minor_snapshot');
    v_line_disc := case when (v_item ? 'line_discount_minor') and jsonb_typeof(v_item -> 'line_discount_minor') <> 'null'
                        then app.order_parse_minor(v_item -> 'line_discount_minor', 'order_items[].line_discount_minor')
                        else 0 end;
    v_mod_sum := 0;
    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        v_mod_sum := v_mod_sum + v_mod_price * v_mod_qty;
      end loop;
    end if;
    v_line_total := v_qty * v_unit + v_mod_sum - v_line_disc;

    insert into public.order_items (
      organization_id, restaurant_id, branch_id, order_id, menu_item_id,
      status, quantity, menu_item_name_snapshot, unit_price_minor_snapshot,
      item_size_snapshot, item_variant_snapshot, line_discount_minor, line_total_minor, notes, prep_snapshot)
    values (
      v_org, v_rest, v_branch, p_order_id, (v_item ->> 'menu_item_id')::uuid,
      'pending', v_qty::int, v_item ->> 'menu_item_name_snapshot', v_unit,
      v_item -> 'item_size_snapshot', v_item -> 'item_variant_snapshot', v_line_disc, v_line_total,
      v_item ->> 'notes', v_item -> 'prep_snapshot')
    returning id into v_item_id;

    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        if (v_modifier ->> 'modifier_option_id') is null then
          raise exception 'submit_order: modifiers[].modifier_option_id is required' using errcode = '42501';
        end if;
        if (v_modifier ->> 'option_name_snapshot') is null then
          raise exception 'submit_order: modifiers[].option_name_snapshot is required' using errcode = '42501';
        end if;
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        insert into public.order_item_modifiers (
          organization_id, restaurant_id, branch_id, order_item_id, modifier_option_id,
          modifier_name_snapshot, option_name_snapshot, price_minor_snapshot, quantity, meat_snapshot)
        values (
          v_org, v_rest, v_branch, v_item_id, (v_modifier ->> 'modifier_option_id')::uuid,
          v_modifier ->> 'modifier_name_snapshot', v_modifier ->> 'option_name_snapshot', v_mod_price, v_mod_qty::int, v_modifier -> 'meat_snapshot');
        v_mod_count := v_mod_count + 1;
      end loop;
    end if;
    v_item_count := v_item_count + 1;
  end loop;

  -- (audit) append-only order.submitted event (D-013, API_CONTRACT §4.1) in the
  -- SAME transaction. This SECURITY DEFINER RPC writes it as the audit_events
  -- table owner (RF-017 grants app roles NO insert; the append-only trigger
  -- blocks only UPDATE/DELETE/TRUNCATE). The idempotency-replay path returns
  -- earlier, so a replay NEVER writes a second audit row. actor =
  -- employee_profile (RF-017 requires app_user OR employee_profile present).
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch,
    null, v_emp, p_device_id,
    'order.submitted', null, null,
    jsonb_build_object(
      'order_id',               p_order_id,
      'status',                 'submitted',
      'revision',               1,
      'currency_code',          p_currency_code,
      'subtotal_minor',         v_subtotal,
      'discount_total_minor',   p_client_discount_total_minor,
      'tax_total_minor',        p_client_tax_total_minor,
      'grand_total_minor',      v_grand,
      'device_id',              p_device_id,
      'local_operation_id',     p_local_operation_id,
      'order_type',             p_order_type,
      'table_id',               p_table_id,
      'shift_id',               p_shift_id,
      'resolved_membership_id', v_membership,
      'item_count',             v_item_count,
      'modifier_count',         v_mod_count));

  -- ---------------------------------------------------------------------------
  -- KITCHEN-MODE-001A (DORMANT, additive tail): a ZERO-TOTAL order submitted in
  -- a `printer_only` branch settles with NOTHING to pay (app.order_is_fully_settled
  -- returns true for grand_total_minor = 0 with NO payment row) and has no
  -- payment.create event to trigger completion — so the SAME auto-completion
  -- helper runs here, at the authoritative tail: grand total is known and
  -- validated, the order + items + audit are durably written, and this
  -- transaction still holds the exclusive lock on the freshly-inserted order
  -- row (satisfying the helper's caller-holds-the-lock contract). The helper
  -- alone decides eligibility: in the default `kds` mode it returns
  -- not_eligible for a `submitted` order, so kds-branch behavior — including
  -- kds zero-total behavior — is byte-identical to before. NO payment row and
  -- NO tender is ever fabricated; the helper is fail-soft, so a completion
  -- side-effect failure can never turn a successful submit into an error.
  -- ---------------------------------------------------------------------------
  -- KITCHEN-MODE-001C1: the ONE mode read for the whole tail (hoisted above
  -- the zero-total gate so the dispatch block below can share it).
  -- CORRECTION-001: FAIL CLOSED — the session liveness chain already proved
  -- this branch live at ingest, so a missing/tombstoned branch row HERE is a
  -- state inconsistency inside the very transaction that just wrote the
  -- order; silently treating it as kds-mode could accept a printer-only
  -- order WITHOUT its kitchen ticket. Raise and roll everything back.
  select b.kitchen_workflow_mode into v_kitchen_mode
    from public.branches b
    where b.id              = v_branch
      and b.organization_id = v_org
      and b.deleted_at is null;
  if v_kitchen_mode is null then
    raise exception 'submit_order: branch row unavailable during the kitchen dispatch gate (state inconsistency)';
  end if;

  -- KITCHEN-MODE-001C1 (DORMANT): EVERY accepted printer-only order gets its
  -- durable, idempotent, money-free kitchen dispatch IN THIS SAME TRANSACTION.
  -- A dispatch failure fails the submit (an accepted printer-only order may
  -- never silently miss its kitchen ticket) and a rolled-back submit leaves
  -- no dispatch. kds branches create NOTHING — byte-identical behavior.
  if v_kitchen_mode = 'printer_only' then
    perform app.create_kitchen_dispatch(
      v_org, v_rest, v_branch, p_order_id, null, 'initial_order',
      app.kitchen_dispatch_payload_initial(v_org, p_order_id),
      v_emp, v_membership, p_device_id);
  end if;

  if v_grand = 0 then
    if v_kitchen_mode = 'printer_only' then
      v_auto := app.try_auto_complete_order(
        v_org, v_rest, v_branch, p_order_id,
        'order_submitted',
        null,          -- no JWT actor on the PIN path
        v_emp, v_membership, v_role,
        p_device_id, p_local_operation_id);
    end if;
  end if;

  -- KITCHEN-MODE-001A: ADDITIVE keys only — `ok`/`order_id`/`server_ts`/
  -- `idempotency_replay` are byte-identical; `revision` still reports the
  -- order's CURRENT revision (1, or 2 when the dormant zero-total completion
  -- just bumped it — reporting 1 for a revision-2 row would poison client
  -- reconciliation). Clients that predate the new keys ignore them.
  return jsonb_build_object(
    'ok', true, 'order_id', p_order_id,
    'revision', coalesce((v_auto ->> 'revision')::integer, 1),
    'server_ts', now(), 'idempotency_replay', false,
    'auto_completed', coalesce((v_auto ->> 'completed')::boolean, false),
    'order_status', case when coalesce((v_auto ->> 'completed')::boolean, false)
                         then 'completed' else 'submitted' end);
end;
$$;


comment on function app.submit_order(uuid, uuid, uuid, text, text, uuid, uuid, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz) is
  'RF-052 .. RESTAURANT-OPERATIONS-V1-001 .. KITCHEN-MODE-001A + KITCHEN-MODE-001C1. Signature and every kds-mode behavior UNCHANGED (faithful re-creation of the 20260723090000 body). KITCHEN-MODE-001C1 (DORMANT): a printer_only branch additionally writes ONE idempotent money-free kitchen dispatch in the SAME transaction (before the 001A zero-total completion tail, sharing its fail-closed mode read); kds branches are byte-identical. Print/dispatch state never joins order state.';

revoke all on function app.submit_order(uuid, uuid, uuid, text, text, uuid, uuid, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz) from public;
revoke all on function app.submit_order(uuid, uuid, uuid, text, text, uuid, uuid, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz) from anon;
grant execute on function app.submit_order(uuid, uuid, uuid, text, text, uuid, uuid, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz) to authenticated;

-- ----------------------------------------------------------------------------
-- 8. app.add_order_items — faithful re-creation of 20260722090000 lines
--    243-692 with the dormant round-dispatch tail. Signature UNCHANGED.
-- ----------------------------------------------------------------------------

create or replace function app.add_order_items(
  p_pin_session_id     uuid,
  p_order_id           uuid,
  p_device_id          uuid,
  p_local_operation_id text,
  p_order_items        jsonb,
  p_client_created_at  timestamptz default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org           uuid;
  v_rest          uuid;
  v_branch        uuid;
  v_dsid          uuid;
  v_emp           uuid;
  v_membership    uuid;
  v_ds_device     uuid;
  v_ds_active     boolean;
  v_ds_revoked    timestamptz;
  v_pairing       text;
  v_role          text;
  v_m_status      text;
  v_m_deleted     timestamptz;
  v_device_type   text;
  v_o_status      text;
  v_o_type        text;
  v_o_rev         integer;
  v_o_sub         bigint;
  v_o_disc        bigint;
  v_o_tax         bigint;
  v_item          jsonb;
  v_modifier      jsonb;
  v_item_id       uuid;
  v_qty           bigint;
  v_unit          bigint;
  v_mod_qty       bigint;
  v_mod_price     bigint;
  v_mod_sum       bigint;
  v_line_total    bigint;
  v_delta         bigint := 0;
  v_new_sub       bigint;
  v_new_grand     bigint;
  v_item_count    integer := 0;
  v_mod_count     integer := 0;
  v_unavailable   jsonb;
  v_item_ids      uuid[];
  v_round_id      uuid;
  v_kitchen_mode  text;  -- KITCHEN-MODE-001C1: branch workflow mode (dispatch gate)
  v_round_no      integer;
  v_new_rev       integer;
  v_ex_round      uuid;
  v_ex_order      uuid;
  v_ex_number     integer;
  v_ex_count      integer;
  v_shape_error   text;
  v_order_code    text := '#' || upper(right(replace(p_order_id::text, '-', ''), 6));
begin
  -- (a) THE CANONICAL PIN PREAMBLE (submit_order parity): session exists+valid,
  --     backing device session/pairing active, device match, membership active.
  --     Every structural failure raises 42501. Scope derived HERE, never payload.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'add_order_items: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'add_order_items: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'add_order_items: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'add_order_items: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'add_order_items: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) DEVICE CLASS: additions are a POS act (the mirror of kitchen_ack_void's
  --     KDS-only rule). A KDS device is refused regardless of role.
  select d.device_type into v_device_type
    from public.devices d
    where d.id = p_device_id and d.organization_id = v_org;
  if v_device_type is distinct from 'pos' then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role,
                               'device_type', coalesce(v_device_type, 'unknown'),
                               'denied_reason', 'invalid_device_type'));
    return jsonb_build_object('ok', false, 'error', 'invalid_device_type', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (c) ROLE: cashier+ may add items (submit_order parity — no new capability;
  --     kitchen_staff/accountant denied).
  if v_role not in ('cashier', 'manager', 'restaurant_owner', 'org_owner') then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role, 'device_type', v_device_type,
                               'denied_reason', 'permission_denied'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) payload envelope shape (structural, submit_order parity).
  if p_order_items is null or jsonb_typeof(p_order_items) <> 'array' or jsonb_array_length(p_order_items) < 1 then
    raise exception 'add_order_items: order_items must be a non-empty jsonb array' using errcode = '42501';
  end if;

  -- (e) PER-LINE SHAPE + ARITHMETIC — the submit_order recompute loop (D-008),
  --     replicated (see the header). Two deliberate deltas for ADDED lines:
  --       * NO order-level client totals exist to cross-check — the deltas are
  --         computed HERE and applied to the parent (server-authoritative);
  --       * a nonzero line_discount_minor is REJECTED (typed) — an addition
  --         never carries a hidden price cut.
  --     Missing identity/name fields are the TYPED invalid_item_payload refusal
  --     (the POS names the broken line); numeric parse failures keep the
  --     structural app.order_parse_minor raise (submit parity).
  v_shape_error := null;
  for v_item in select * from jsonb_array_elements(p_order_items)
  loop
    if (v_item ->> 'menu_item_id') is null then
      v_shape_error := 'menu_item_id_required';
      exit;
    end if;
    if (v_item ->> 'menu_item_name_snapshot') is null then
      v_shape_error := 'menu_item_name_snapshot_required';
      exit;
    end if;
    if (v_item ? 'line_discount_minor') and jsonb_typeof(v_item -> 'line_discount_minor') <> 'null'
       and app.order_parse_minor(v_item -> 'line_discount_minor', 'order_items[].line_discount_minor') <> 0 then
      v_shape_error := 'line_discount_not_allowed';
      exit;
    end if;
    v_qty := app.order_parse_minor(v_item -> 'quantity', 'order_items[].quantity');
    if v_qty <= 0 or v_qty > 2147483647 then
      raise exception 'add_order_items: order_items[].quantity must be between 1 and 2147483647' using errcode = '42501';
    end if;
    v_unit := app.order_parse_minor(v_item -> 'unit_price_minor_snapshot', 'order_items[].unit_price_minor_snapshot');

    v_mod_sum := 0;
    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        if (v_modifier ->> 'modifier_option_id') is null then
          v_shape_error := 'modifier_option_id_required';
          exit;
        end if;
        if (v_modifier ->> 'option_name_snapshot') is null then
          v_shape_error := 'option_name_snapshot_required';
          exit;
        end if;
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        if v_mod_qty <= 0 or v_mod_qty > 2147483647 then
          raise exception 'add_order_items: modifiers[].quantity must be between 1 and 2147483647' using errcode = '42501';
        end if;
        v_mod_sum := v_mod_sum + v_mod_price * v_mod_qty;
      end loop;
      if v_shape_error is not null then
        exit;
      end if;
    end if;

    v_line_total := v_qty * v_unit + v_mod_sum;
    if v_line_total < 0 then
      raise exception 'add_order_items: computed line_total_minor is negative' using errcode = '42501';
    end if;
    v_delta := v_delta + v_line_total;
  end loop;
  if v_shape_error is not null then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role, 'device_type', v_device_type,
                               'denied_reason', 'invalid_item_payload'));
    return jsonb_build_object('ok', false, 'error', 'invalid_item_payload', 'detail', v_shape_error,
                              'order_id', p_order_id, 'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (f) IDEMPOTENCY REPLAY (submit_order parity: after full payload validation,
  --     before the time-varying checks): the SAME (org, device, local_operation_id)
  --     returns the SAME round — no duplicate round, no duplicate items — even if
  --     the parent's state has since moved on. The same key on a DIFFERENT order
  --     is a conflict (40001), mirroring record_payment.
  select r.id, r.order_id, r.round_number
    into v_ex_round, v_ex_order, v_ex_number
    from public.order_service_rounds r
    where r.organization_id = v_org
      and r.device_id = p_device_id
      and r.local_operation_id = p_local_operation_id
    limit 1;
  if found then
    if v_ex_order <> p_order_id then
      raise exception 'add_order_items: idempotency key already used for a different order (%, not %)', v_ex_order, p_order_id using errcode = '40001';
    end if;
    select count(*)::int into v_ex_count
      from public.order_items oi
      where oi.organization_id = v_org and oi.service_round_id = v_ex_round;
    select o.revision into v_o_rev from public.orders o where o.id = p_order_id and o.organization_id = v_org;
    return jsonb_build_object(
      'ok', true, 'order_id', p_order_id, 'round_id', v_ex_round, 'round_number', v_ex_number,
      'added_item_count', v_ex_count, 'revision', v_o_rev,
      'server_ts', now(), 'idempotency_replay', true);
  end if;

  -- (g) ONE SCOPED PARENT LOOKUP, FOR UPDATE — the FIRST lock (the same first
  --     lock payment/void/status/discount take). ANTI-ORACLE (R-003, the
  --     PSC-001D F1 pattern): a nonexistent order and a foreign-tenant order
  --     raise the SAME structural 42501.
  select o.status, o.order_type, o.revision, o.subtotal_minor, o.discount_total_minor, o.tax_total_minor
    into v_o_status, v_o_type, v_o_rev, v_o_sub, v_o_disc, v_o_tax
    from public.orders o
    where o.id = p_order_id
      and o.organization_id = v_org
      and o.restaurant_id   = v_rest
      and o.branch_id       = v_branch
      and o.deleted_at is null
    for update;
  if not found then
    raise exception 'add_order_items: order_not_found_or_not_accessible' using errcode = '42501';
  end if;

  -- (h) ELIGIBILITY (typed RETURN-refusals, each audited).
  if v_o_type <> 'dine_in' then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role, 'device_type', v_device_type,
                               'order_type', v_o_type, 'denied_reason', 'order_not_dine_in'));
    return jsonb_build_object('ok', false, 'error', 'order_not_dine_in', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;
  if v_o_status not in ('submitted', 'accepted', 'preparing', 'ready', 'served') then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role, 'device_type', v_device_type,
                               'order_status', v_o_status, 'denied_reason', 'order_not_eligible'));
    return jsonb_build_object('ok', false, 'error', 'order_not_eligible', 'order_id', p_order_id,
                              'order_status', v_o_status, 'server_ts', now(), 'idempotency_replay', false);
  end if;
  -- The PAYMENT FREEZE (apply_discount precedent): a live COMPLETED payment
  -- froze the bill it covered. record_payment allows at most ONE completed
  -- payment and always charges the CURRENT total, so a post-payment addition
  -- could never be settled — and the numbered receipt's total must stay true.
  -- (A zero-total order with NO completed payment falls through: still open,
  -- still eligible, and the addition simply makes it chargeable again.)
  if exists (
       select 1 from public.payments p
       where p.organization_id = v_org
         and p.order_id = p_order_id
         and p.status = 'completed'
         and p.deleted_at is null) then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role, 'device_type', v_device_type,
                               'order_status', v_o_status, 'denied_reason', 'order_already_settled'));
    return jsonb_build_object('ok', false, 'error', 'order_already_settled', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (i) SELLABILITY + AVAILABILITY under ascending-id FOR UPDATE menu locks —
  --     the submit_order accept-2 block, replicated verbatim (same predicate,
  --     same TOCTOU serialization point, same uniform refusal — R-003).
  select array_agg(distinct (e ->> 'menu_item_id')::uuid)
    into v_item_ids
    from jsonb_array_elements(p_order_items) e;
  perform 1
    from public.menu_items i
    where i.organization_id = v_org
      and i.id = any (v_item_ids)
    order by i.id
    for update;

  select jsonb_agg(jsonb_build_object(
           'menu_item_id', blocked.menu_item_id,
           'name',         blocked.name,
           'reason',       blocked.reason)
           order by blocked.menu_item_id)
    into v_unavailable
    from (
      select li.menu_item_id,
             li.name,
             coalesce(a.reason, 'unavailable') as reason
        from (
          select (e ->> 'menu_item_id')::uuid as menu_item_id,
                 min(e ->> 'menu_item_name_snapshot') as name
            from jsonb_array_elements(p_order_items) e
            group by 1
        ) li
        left join public.menu_items i
          on i.id = li.menu_item_id
         and i.organization_id = v_org
         and i.restaurant_id   = v_rest
         and i.is_active
         and i.deleted_at is null
         and (i.branch_id is null or i.branch_id = v_branch)
        left join public.menu_categories c
          on c.id = i.menu_category_id
         and c.organization_id = v_org
         and c.restaurant_id   = v_rest
         and c.is_active
         and c.deleted_at is null
         and (c.branch_id is null or c.branch_id = v_branch)
        left join public.menu_item_branch_availability a
          on a.organization_id = v_org
         and a.branch_id       = v_branch
         and a.menu_item_id    = li.menu_item_id
         and a.availability    = 'unavailable'
        where i.id is null
           or c.id is null
           or a.menu_item_id is not null
    ) blocked;
  if v_unavailable is not null then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role, 'device_type', v_device_type,
                               'order_status', v_o_status, 'denied_reason', 'item_unavailable'));
    return jsonb_build_object('ok', false, 'error', 'item_unavailable',
                              'entity', 'order', 'items', v_unavailable,
                              'order_id', p_order_id, 'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (j) ALLOCATE the round number under the held parent lock: max(round_number)
  --     across ALL rows of this order (voided/deleted INCLUDED — a number is
  --     NEVER reused), +1; the very first addition is ROUND 2 (the original
  --     order is kitchen work unit 1). Serialized by the parent lock; the
  --     per-order unique constraint is the layer-4 backstop.
  select coalesce(max(r.round_number), 1) + 1
    into v_round_no
    from public.order_service_rounds r
    where r.organization_id = v_org
      and r.order_id        = p_order_id;

  v_round_id := gen_random_uuid();
  insert into public.order_service_rounds (
    id, organization_id, restaurant_id, branch_id, order_id, round_number,
    status, device_id, opened_by_employee_profile_id, local_operation_id,
    revision, client_created_at)
  values (
    v_round_id, v_org, v_rest, v_branch, p_order_id, v_round_no,
    'submitted', p_device_id, v_emp, p_local_operation_id,
    1, p_client_created_at);

  -- (k) insert the ADDED items (status 'pending', submit_order parity) with
  --     their round membership, + modifiers. line_discount_minor is FORCED 0
  --     (validated above).
  for v_item in select * from jsonb_array_elements(p_order_items)
  loop
    v_qty  := app.order_parse_minor(v_item -> 'quantity', 'order_items[].quantity');
    v_unit := app.order_parse_minor(v_item -> 'unit_price_minor_snapshot', 'order_items[].unit_price_minor_snapshot');
    v_mod_sum := 0;
    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        v_mod_sum := v_mod_sum + v_mod_price * v_mod_qty;
      end loop;
    end if;
    v_line_total := v_qty * v_unit + v_mod_sum;

    insert into public.order_items (
      organization_id, restaurant_id, branch_id, order_id, menu_item_id,
      status, quantity, menu_item_name_snapshot, unit_price_minor_snapshot,
      item_size_snapshot, item_variant_snapshot, line_discount_minor, line_total_minor,
      notes, prep_snapshot, service_round_id)
    values (
      v_org, v_rest, v_branch, p_order_id, (v_item ->> 'menu_item_id')::uuid,
      'pending', v_qty::int, v_item ->> 'menu_item_name_snapshot', v_unit,
      v_item -> 'item_size_snapshot', v_item -> 'item_variant_snapshot', 0, v_line_total,
      v_item ->> 'notes', v_item -> 'prep_snapshot', v_round_id)
    returning id into v_item_id;

    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        insert into public.order_item_modifiers (
          organization_id, restaurant_id, branch_id, order_item_id, modifier_option_id,
          modifier_name_snapshot, option_name_snapshot, price_minor_snapshot, quantity, meat_snapshot)
        values (
          v_org, v_rest, v_branch, v_item_id, (v_modifier ->> 'modifier_option_id')::uuid,
          v_modifier ->> 'modifier_name_snapshot', v_modifier ->> 'option_name_snapshot', v_mod_price, v_mod_qty::int, v_modifier -> 'meat_snapshot');
        v_mod_count := v_mod_count + 1;
      end loop;
    end if;
    v_item_count := v_item_count + 1;
  end loop;

  -- (l) PARENT TOTALS (server-authoritative, D-007): subtotal grows by the
  --     recomputed delta; the ABSOLUTE prior discount and the stored tax stay
  --     EXACTLY as they were (locked: never silently re-scaled); the grand
  --     follows the ONE canonical formula. The parent status is NEVER moved.
  v_new_sub   := v_o_sub + v_delta;
  v_new_grand := v_new_sub - v_o_disc + v_o_tax;
  if v_new_grand < 0 then
    raise exception 'add_order_items: computed grand_total_minor is negative' using errcode = '42501';
  end if;
  v_new_rev := v_o_rev + 1;
  update public.orders
    set subtotal_minor = v_new_sub, grand_total_minor = v_new_grand, revision = v_new_rev
    where id = p_order_id;

  -- (m) audit order.items_added (D-013): safe scalars only — and MONEY-FREE
  -- (PSC-001C correction, Finding 6): the approved contract for the four new
  -- service-round actions carries NO monetary field. What was added and to
  -- which order is the operational record; the money moved is derivable from
  -- the order's own authoritative rows, never from this trail.
  insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_added', null,
          jsonb_build_object('order_id', p_order_id, 'revision', v_o_rev),
          jsonb_build_object('order_id', p_order_id, 'order_code', v_order_code,
                             'round_number', v_round_no, 'added_item_count', v_item_count,
                             'order_status', v_o_status, 'role', v_role,
                             'device_type', v_device_type,
                             'revision', v_new_rev,
                             'local_operation_id', p_local_operation_id,
                             'resolved_membership_id', v_membership));

  -- KITCHEN-MODE-001C1 (DORMANT): a printer-only branch gets ONE durable
  -- service-round dispatch in this SAME transaction — the ROUND DELTA only,
  -- idempotent by round id, nothing for kds branches, and nothing survives a
  -- rollback. A dispatch failure fails the addition (fail closed).
  -- CORRECTION-001: a missing branch row here is a state inconsistency (the
  -- liveness chain proved it live at ingest) — never a silent kds fallback.
  select b.kitchen_workflow_mode into v_kitchen_mode
    from public.branches b
    where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;
  if v_kitchen_mode is null then
    raise exception 'add_order_items: branch row unavailable during the kitchen dispatch gate (state inconsistency)';
  end if;
  if v_kitchen_mode = 'printer_only' then
    perform app.create_kitchen_dispatch(
      v_org, v_rest, v_branch, p_order_id, v_round_id, 'service_round',
      app.kitchen_dispatch_payload_round(v_org, p_order_id, v_round_id),
      v_emp, v_membership, p_device_id);
  end if;

  return jsonb_build_object(
    'ok', true, 'order_id', p_order_id, 'round_id', v_round_id, 'round_number', v_round_no,
    'added_item_count', v_item_count, 'revision', v_new_rev,
    'server_ts', now(), 'idempotency_replay', false);
end;
$$;


comment on function app.add_order_items(uuid, uuid, uuid, text, jsonb, timestamptz) is
  'PSC-001C service rounds + KITCHEN-MODE-001C1. Signature, locking, round numbering, validation, idempotency, audit and every kds-mode behavior UNCHANGED (faithful re-creation of the 20260722090000 body). KITCHEN-MODE-001C1 (DORMANT): a printer_only branch additionally writes ONE idempotent money-free ROUND-DELTA dispatch in the SAME transaction; kds branches are byte-identical.';

revoke all on function app.add_order_items(uuid, uuid, uuid, text, jsonb, timestamptz) from public;
revoke all on function app.add_order_items(uuid, uuid, uuid, text, jsonb, timestamptz) from anon;
grant execute on function app.add_order_items(uuid, uuid, uuid, text, jsonb, timestamptz) to authenticated;

-- ----------------------------------------------------------------------------
-- 9. app.void_order — faithful re-creation of 20260722090000 lines 1373-1642
--    (the NEWEST body: PSC-001D void provenance PLUS the PSC-001C whole-order
--    round sweep) with the dormant void-dispatch tail. Signature UNCHANGED.
-- ----------------------------------------------------------------------------

create or replace function app.void_order(
  p_pin_session_id     uuid,
  p_order_id           uuid,
  p_device_id          uuid,
  p_local_operation_id text,
  p_reason             text,
  p_expected_revision  integer default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org          uuid;
  v_rest         uuid;
  v_branch       uuid;
  v_dsid         uuid;
  v_emp          uuid;
  v_membership   uuid;
  v_ds_device    uuid;
  v_ds_active    boolean;
  v_ds_revoked   timestamptz;
  v_pairing      text;
  v_role         text;
  v_m_status     text;
  v_m_deleted    timestamptz;
  v_m_perms      jsonb;
  v_o_org        uuid;
  v_o_branch     uuid;
  v_o_status     text;
  v_o_rev        integer;
  v_authorized   boolean;
  v_new_rev      integer;
  v_voided_items integer;
  v_stored       jsonb;
  v_stored_order uuid;
  v_result       jsonb;
  v_kitchen_mode text;  -- KITCHEN-MODE-001C1: branch workflow mode (dispatch gate)
begin
  -- (a) PIN session + backing device session/pairing; derive actor + scope
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'void_order: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'void_order: PIN session is not valid' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'void_order: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'void_order: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at, m.permissions
    into v_role, v_m_status, v_m_deleted, v_m_perms
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'void_order: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) load the order; it MUST be in the actor's org + branch (no cross-tenant).
  --     RF-062 (A4): FOR UPDATE locks the order row so void_order serializes with
  --     record_payment (which now also locks the order row) on the SAME order — a
  --     payment cannot complete between the (g2) guard and the void.
  select o.organization_id, o.branch_id, o.status, o.revision
    into v_o_org, v_o_branch, v_o_status, v_o_rev
    from public.orders o where o.id = p_order_id
    for update;
  if not found then
    raise exception 'void_order: order not found' using errcode = '42501';
  end if;
  if v_o_org <> v_org or v_o_branch <> v_branch then
    raise exception 'void_order: order is not in the caller scope' using errcode = '42501';
  end if;

  -- (c) authorization (A1): manager/restaurant_owner/org_owner, OR a cashier with an
  --     explicit memberships.permissions->>'void_order' = 'true' grant. RF053-B1:
  --     authorization runs BEFORE the idempotency replay so an unauthorized actor can
  --     never replay a prior SUCCESS result. A DENIAL is audited (order.void_denied)
  --     + RETURNED (no raise, so the audit persists) with NO state change and NO ledger
  --     write (the ledger holds only authorized successes; denials are always re-audited
  --     as probe attempts, never replayed).
  v_authorized := (v_role in ('manager', 'restaurant_owner', 'org_owner'))
                  or app.cashier_capability_allowed(v_role, v_m_perms, 'void_order');

  if not v_authorized then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.void_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
      jsonb_build_object('attempted_action', 'void_order', 'order_id', p_order_id,
                         'role', v_role, 'order_status', v_o_status));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) reason mandatory (AC#2)
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'void_order: a non-empty reason is required' using errcode = '42501';
  end if;

  -- (e) idempotency replay (RF053-B1): AFTER authorization + reason, BEFORE the
  --     voidable-source-state check (the order becomes 'voided' after the first
  --     success). ORDER-BOUND: the stored op MUST be for the same order; the same
  --     (org, device, local_operation_id, action) reused on a DIFFERENT order is a
  --     conflict, not a replay (never leaks the original order's result).
  select oo.result, oo.order_id into v_stored, v_stored_order
    from public.order_operations oo
    where oo.organization_id = v_org and oo.device_id = p_device_id
      and oo.local_operation_id = p_local_operation_id and oo.action = 'void_order';
  if found then
    if v_stored_order <> p_order_id then
      raise exception 'void_order: idempotency key already used for a different order (%, not %)', v_stored_order, p_order_id using errcode = '40001';
    end if;
    return v_stored || jsonb_build_object('server_ts', now(), 'idempotency_replay', true);
  end if;

  -- (f) optimistic concurrency (optional)
  if p_expected_revision is not null and p_expected_revision <> v_o_rev then
    raise exception 'void_order: revision conflict (expected %, got %)', p_expected_revision, v_o_rev using errcode = '40001';
  end if;

  -- (g) state legality (AC#3, D-024): only pre-completion non-terminal source states.
  --     ELIGIBILITY IS UNCHANGED — the legal set is still exactly
  --     submitted/accepted/preparing/ready/served, `completed` remains TERMINAL, and there
  --     is NO completed -> void path. Only the SHAPE of the refusal changes.
  --
  --     MONEY-SETTLEMENT-CONSISTENCY-001 (corrective): RETURN the stable domain code
  --     instead of raising. app.sync_push REBUILDS the envelope from scratch for a RAISE
  --     (collapsing every domain code to the generic literal 'rejected'), but merges a
  --     RETURNED envelope through VERBATIM. Raising left the POS unable to tell
  --     "this order is already closed" apart from a dropped network, a malformed response
  --     or any other rejection — so it was reduced to GUESSING from the order's total, and
  --     could tell an operator an order was closed when the connection had merely failed.
  --
  --     `error` is the established coarse class for an illegal state change
  --     (`invalid_transition`, as the order state machine already uses) and `detail` is the
  --     established fine-grained safe token (as order_has_completed_payment already is).
  --     `order_status` is a STATE, never an identifier — safe to return.
  --
  --     AUDITED like the other two RETURN-based denials in this function
  --     (order.void_denied + denied_reason). A raise could not have audited at all: it
  --     would have rolled the audit row back. NO state change, NO revision bump, NO
  --     order_operations ledger row (denials are re-audited as probe attempts, never
  --     replayed).
  if v_o_status not in ('submitted', 'accepted', 'preparing', 'ready', 'served') then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.void_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
      jsonb_build_object('attempted_action', 'void_order', 'order_id', p_order_id,
                         'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
                         'role', v_role, 'order_status', v_o_status,
                         'denied_reason', 'order_not_voidable'));
    return jsonb_build_object('ok', false, 'error', 'invalid_transition',
                              'detail', 'order_not_voidable', 'order_id', p_order_id,
                              'order_status', v_o_status,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (g2) RF-062 COMPLETED-PAYMENT GUARD (D-023/D-024; STATE_MACHINES §1; API_CONTRACT
  --      §4.6): an order with a LIVE `completed` payment cannot be voided in MVP — there
  --      is no refund/reversal flow. Checked AFTER authorization, reason, the idempotency
  --      replay, expected_revision, and state legality, BEFORE any mutation, so: a prior
  --      successful void still replays at (e) (a voided order can never acquire a
  --      completed payment afterward — record_payment rejects non-eligible orders); a
  --      genuinely terminal status is still refused at (g), which now RETURNS the typed
  --      domain refusal (invalid_transition + detail=order_not_voidable + order_status)
  --      rather than raising an untyped 42501 — so the two refusals stay DISTINGUISHABLE
  --      to the client; and only a
  --      legal-source order that nonetheless carries settled money reaches here. The
  --      order row is locked FOR UPDATE (b) and record_payment also locks it, so a
  --      concurrent payment cannot slip in. A4/A5/A3 decisions: block ONLY a live
  --      `completed` payment (deleted_at IS NULL; no method filter — any completed
  --      payment blocks); org-scoped to the session-derived v_org (tenant-safe); AUDIT
  --      `order.void_denied` (denied_reason=order_has_completed_payment) + RETURN a
  --      permission_denied envelope (NO raise — a raise would roll back the audit), with
  --      NO state change to order/order_items/payment and NO order_operations ledger row
  --      (denials are re-audited as probe attempts on retry, never replayed).
  if exists (
    select 1
    from public.payments p
    where p.organization_id = v_org
      and p.order_id = p_order_id
      and p.status = 'completed'
      and p.deleted_at is null
  ) then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.void_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
      jsonb_build_object('attempted_action', 'void_order', 'order_id', p_order_id,
                         'role', v_role, 'order_status', v_o_status,
                         'denied_reason', 'order_has_completed_payment'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied',
                              'detail', 'order_has_completed_payment', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (h) mutate: order -> voided (+reason, +revision); cascade items -> voided.
  --     PSC-001D: the SAME statement stamps the void PROVENANCE — when it
  --     happened, which state it was in, and whether the kitchen must
  --     acknowledge (an ACTIVE kitchen source: submitted|accepted|preparing|
  --     ready; a served-source void is already off the board). The
  --     acknowledgement triple stays NULL until app.kitchen_ack_void.
  v_new_rev := v_o_rev + 1;
  update public.orders
    set status = 'voided', void_reason = p_reason, revision = v_new_rev,
        voided_at = now(),
        voided_from_status = v_o_status,
        kitchen_ack_required = (v_o_status in ('submitted', 'accepted', 'preparing', 'ready'))
    where id = p_order_id;

  update public.order_items
    set status = 'voided', void_reason = p_reason
    where order_id = p_order_id and organization_id = v_org
      and status not in ('voided', 'cancelled');
  get diagnostics v_voided_items = row_count;
  -- PSC-001C: the whole-order void ALSO sweeps every live ADDITIONAL service
  -- round to `voided` (round void_reason stamped; ready_at PRESERVED — the
  -- historical ready occurrence must survive for the feed; item snapshots and
  -- round membership untouched — the items were already cascaded above). After
  -- this no round transition is possible (parent_order_voided) and the parent
  -- can never complete (voided is terminal AND a voided round blocks
  -- app.order_rounds_all_served). There is NO independent round-void feature.
  update public.order_service_rounds
    set status = 'voided', void_reason = p_reason, revision = revision + 1
    where order_id = p_order_id and organization_id = v_org
      and status <> 'voided';

  -- (i) audit (order.voided) with old/new values (D-013). PSC-001D adds the two
  --     safe provenance scalars (a closed status enum + a boolean — never money,
  --     never an identifier; T-003 holds).
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch, null, v_emp, p_device_id,
    'order.voided', p_reason,
    jsonb_build_object('status', v_o_status, 'revision', v_o_rev),
    jsonb_build_object('status', 'voided', 'revision', v_new_rev,
                       'void_reason', p_reason, 'voided_item_count', v_voided_items,
                       'resolved_membership_id', v_membership,
                       'voided_from_status', v_o_status,
                       'kitchen_ack_required', (v_o_status in ('submitted', 'accepted', 'preparing', 'ready'))));

  -- (j) record ledger + return
  v_result := jsonb_build_object('ok', true, 'order_id', p_order_id, 'status', 'voided', 'revision', v_new_rev);
  insert into public.order_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, order_id, result)
    values (v_org, v_rest, v_branch, p_device_id, p_local_operation_id, 'void_order', p_order_id, v_result);

  -- KITCHEN-MODE-001C1 (DORMANT): when the branch is printer_only and the
  -- kitchen MAY HAVE SEEN this order — the SAME conservative PSC-001D
  -- predicate that drives kitchen_ack_required, OR any prior kitchen dispatch
  -- exists for the order — one durable VOID dispatch is created in this SAME
  -- transaction. CORRECTION-001: the void supersedes EVERY unresolved prior
  -- dispatch of the order (claimed / failed / possibly_printed included) so
  -- no original can ever print after it; completed priors stay (the kitchen
  -- may hold their paper — the VOID slip corrects them). kds branches create
  -- nothing; a rollback leaves nothing; a missing branch row here is a state
  -- inconsistency — never a silent kds fallback.
  select b.kitchen_workflow_mode into v_kitchen_mode
    from public.branches b
    where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;
  if v_kitchen_mode is null then
    raise exception 'void_order: branch row unavailable during the kitchen dispatch gate (state inconsistency)';
  end if;
  if v_kitchen_mode = 'printer_only'
     and ((v_o_status in ('submitted', 'accepted', 'preparing', 'ready'))
          or exists (select 1 from public.kitchen_print_dispatches d
                      where d.organization_id = v_org and d.order_id = p_order_id)) then
    perform app.create_kitchen_dispatch(
      v_org, v_rest, v_branch, p_order_id, null, 'void',
      app.kitchen_dispatch_payload_void(v_org, p_order_id, p_reason),
      v_emp, v_membership, p_device_id);
  end if;

  return v_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
end;
$$;


comment on function app.void_order(uuid, uuid, uuid, text, text, integer) is
  'RF-062 .. MONEY-VOID-001 .. PSC-001D/PSC-001C + KITCHEN-MODE-001C1. Signature, paid-order restrictions, provenance stamps (voided_from_status / kitchen_ack_required), the PSC-001C whole-order round sweep, audit and every kds-mode behavior UNCHANGED (faithful re-creation of the 20260722090000 body). KITCHEN-MODE-001C1 (DORMANT): a printer_only branch whose kitchen MAY HAVE SEEN the order (the same conservative PSC-001D predicate, or any prior dispatch) additionally writes ONE idempotent money-free VOID dispatch in the SAME transaction, superseding EVERY unresolved prior dispatch of the order (CORRECTION-001 — no original can print after its void); kds branches are byte-identical.';

revoke all on function app.void_order(uuid, uuid, uuid, text, text, integer) from public;
revoke all on function app.void_order(uuid, uuid, uuid, text, text, integer) from anon;
grant execute on function app.void_order(uuid, uuid, uuid, text, text, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 10. Device readiness report RPC (+wrapper). Device-token authenticated with
--     the FULL 001A-corrected liveness contract; POS devices only.
-- ----------------------------------------------------------------------------
create or replace function app.report_kitchen_printer_readiness(
  p_device_id              uuid,
  p_session_token          text,
  p_capability             text,
  p_app_build              text,
  p_printer_purpose        text,
  p_transport_kind         text,
  p_paper_width            text,
  p_printer_fingerprint    text,
  p_secure_spool_available boolean,
  p_unresolved_local_jobs  integer,
  p_mode_revision          integer
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_hash    text;
  v_org     uuid;
  v_rest    uuid;
  v_branch  uuid;
  v_dtype   text;
  v_rev     integer;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_printer_readiness');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));

  -- FULL device-liveness contract (the 001A-corrected template): non-expired
  -- active session, active pairing, live device, live+active branch/
  -- restaurant/organization. Scope comes EXCLUSIVELY from the proven session.
  select ds.organization_id, ds.restaurant_id, ds.branch_id, d.device_type
    into v_org, v_rest, v_branch, v_dtype
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
      and dp.organization_id = ds.organization_id
      and dp.restaurant_id   = ds.restaurant_id
      and dp.branch_id       = ds.branch_id
      and dp.device_id       = ds.device_id
    join public.devices d on d.id = ds.device_id
      and d.organization_id = ds.organization_id
    join public.branches b on b.organization_id = ds.organization_id
      and b.restaurant_id = ds.restaurant_id and b.id = ds.branch_id
      and b.deleted_at is null and b.status = 'active'
    join public.restaurants r on r.organization_id = ds.organization_id
      and r.id = ds.restaurant_id and r.deleted_at is null and r.status = 'active'
    join public.organizations org on org.id = ds.organization_id
      and org.deleted_at is null and org.status = 'active'
    where ds.device_id = p_device_id
      and ds.session_token_ref = v_hash
      and ds.is_active and ds.revoked_at is null
      and (ds.expires_at is null or ds.expires_at > now())
      and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null
      and d.is_active and d.deleted_at is null;
  if v_org is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_printer_readiness');
  end if;
  if v_dtype <> 'pos' then
    -- KDS devices are explicitly denied — readiness is a POS capability.
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_printer_readiness');
  end if;

  -- Typed validation (closed vocabularies; the CHECKs re-prove at the row).
  if p_capability is distinct from 'kitchen_printer_only_v1' then
    return jsonb_build_object('ok', false, 'error', 'unsupported_capability');
  end if;
  if p_printer_purpose is distinct from 'kitchen_ticket' then
    return jsonb_build_object('ok', false, 'error', 'unsupported_purpose');
  end if;
  if p_transport_kind is null or p_transport_kind not in ('network', 'bluetooth') then
    return jsonb_build_object('ok', false, 'error', 'unsupported_transport');
  end if;
  if p_paper_width is null or p_paper_width not in ('58mm', '80mm') then
    return jsonb_build_object('ok', false, 'error', 'unsupported_paper_width');
  end if;
  if p_app_build is null or length(btrim(p_app_build)) not between 1 and 64 then
    return jsonb_build_object('ok', false, 'error', 'invalid_app_build');
  end if;
  if p_printer_fingerprint is null or p_printer_fingerprint !~ '^[0-9a-f]{16,128}$' then
    return jsonb_build_object('ok', false, 'error', 'invalid_fingerprint');
  end if;
  if p_secure_spool_available is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_spool_state');
  end if;
  if p_unresolved_local_jobs is null or p_unresolved_local_jobs < 0 then
    return jsonb_build_object('ok', false, 'error', 'invalid_unresolved_count');
  end if;

  select b.kitchen_workflow_mode_revision into v_rev
    from public.branches b
    where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;
  if p_mode_revision is distinct from v_rev then
    return jsonb_build_object('ok', false, 'error', 'stale_mode_revision', 'mode_revision', v_rev);
  end if;

  -- ONE current report per device (upsert; the server owns the clock).
  insert into public.kitchen_printer_readiness_reports
    (organization_id, restaurant_id, branch_id, device_id, capability,
     app_build, printer_purpose, transport_kind, paper_width,
     printer_fingerprint, secure_spool_available, unresolved_local_jobs,
     mode_revision, reported_at, expires_at)
  values
    (v_org, v_rest, v_branch, p_device_id, p_capability,
     btrim(p_app_build), p_printer_purpose, p_transport_kind, p_paper_width,
     p_printer_fingerprint, p_secure_spool_available, p_unresolved_local_jobs,
     p_mode_revision, now(), now() + interval '10 minutes')
  on conflict (organization_id, device_id) do update set
     restaurant_id          = excluded.restaurant_id,
     branch_id              = excluded.branch_id,
     capability             = excluded.capability,
     app_build              = excluded.app_build,
     printer_purpose        = excluded.printer_purpose,
     transport_kind         = excluded.transport_kind,
     paper_width            = excluded.paper_width,
     printer_fingerprint    = excluded.printer_fingerprint,
     secure_spool_available = excluded.secure_spool_available,
     unresolved_local_jobs  = excluded.unresolved_local_jobs,
     mode_revision          = excluded.mode_revision,
     reported_at            = excluded.reported_at,
     expires_at             = excluded.expires_at,
     updated_at             = now();

  return jsonb_build_object(
    'ok', true, 'entity', 'kitchen_printer_readiness',
    -- Honest contract: readiness = "transport accepted the test bytes and the
    -- device reported its local state" — NEVER a physical-paper claim.
    'meaning', 'transport_accepted_not_paper_confirmed',
    'activation_ready', (p_paper_width = '80mm' and p_secure_spool_available),
    'expires_at', now() + interval '10 minutes',
    'server_ts', now());
end;
$$;

comment on function app.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer) is
  'KITCHEN-MODE-001C1: the POS device''s kitchen-printing readiness report (device-token authenticated with the full 001A-corrected liveness contract; KDS explicitly denied; scope exclusively from the proven session). Validates the closed capability/purpose/transport/paper vocabularies, the NON-SECRET fingerprint digest shape, and the branch mode revision; upserts the device''s ONE current report with a server-owned 10-minute validity. Readiness means transport-accepted test bytes + reported local state — never physical paper. NOTE (D-013): no audit row — audit_events requires a human actor and this is a device-only path; observability lives on the report row itself. No client calls this until 001C2/001C3.';

create or replace function public.report_kitchen_printer_readiness(
  p_device_id uuid, p_session_token text, p_capability text, p_app_build text,
  p_printer_purpose text, p_transport_kind text, p_paper_width text,
  p_printer_fingerprint text, p_secure_spool_available boolean,
  p_unresolved_local_jobs integer, p_mode_revision integer)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.report_kitchen_printer_readiness(p_device_id, p_session_token, p_capability, p_app_build, p_printer_purpose, p_transport_kind, p_paper_width, p_printer_fingerprint, p_secure_spool_available, p_unresolved_local_jobs, p_mode_revision); $$;

revoke all on function app.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer) from public;
revoke all on function app.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer) from anon;
grant execute on function app.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer) to authenticated;
revoke all on function public.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer) from public;
revoke all on function public.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer) from anon;
grant execute on function public.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 11. Atomic claim-and-pull (+wrapper).
-- ----------------------------------------------------------------------------
create or replace function app.pull_kitchen_print_dispatches(
  p_device_id         uuid,
  p_session_token     text,
  p_limit             integer default 20,
  p_cursor_created_at timestamptz default null,
  p_cursor_id         uuid default null,
  -- CORRECTION-001: the cursor carries the FULL ordering tuple. No 001C
  -- client exists yet, so adding the component is a safe contract change;
  -- it is LAST with a default, so cursorless recovery calls are unchanged.
  p_cursor_type_rank  integer default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_hash      text;
  v_org       uuid;
  v_rest      uuid;
  v_branch    uuid;
  v_dtype     text;
  v_mode      text;
  v_brev      integer;
  v_limit     integer;
  v_rows      jsonb;
  v_count     integer;
  v_last_at   timestamptz;
  v_last_rank integer;
  v_last_id   uuid;
  v_has_more  boolean;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_print_dispatches');
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 50 then
    return jsonb_build_object('ok', false, 'error', 'invalid_limit', 'entity', 'kitchen_print_dispatches');
  end if;
  -- CORRECTION-001: the cursor is ALL-OR-NOTHING across its three components
  -- and the rank must be a real rank; a malformed cursor is rejected, never
  -- guessed around.
  if not ((p_cursor_created_at is null and p_cursor_id is null and p_cursor_type_rank is null)
          or (p_cursor_created_at is not null and p_cursor_id is not null and p_cursor_type_rank is not null)) then
    return jsonb_build_object('ok', false, 'error', 'invalid_cursor', 'entity', 'kitchen_print_dispatches');
  end if;
  if p_cursor_type_rank is not null and p_cursor_type_rank not in (0, 1, 2) then
    return jsonb_build_object('ok', false, 'error', 'invalid_cursor', 'entity', 'kitchen_print_dispatches');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));

  select ds.organization_id, ds.restaurant_id, ds.branch_id, d.device_type
    into v_org, v_rest, v_branch, v_dtype
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
      and dp.organization_id = ds.organization_id
      and dp.restaurant_id   = ds.restaurant_id
      and dp.branch_id       = ds.branch_id
      and dp.device_id       = ds.device_id
    join public.devices d on d.id = ds.device_id
      and d.organization_id = ds.organization_id
    join public.branches b on b.organization_id = ds.organization_id
      and b.restaurant_id = ds.restaurant_id and b.id = ds.branch_id
      and b.deleted_at is null and b.status = 'active'
    join public.restaurants r on r.organization_id = ds.organization_id
      and r.id = ds.restaurant_id and r.deleted_at is null and r.status = 'active'
    join public.organizations org on org.id = ds.organization_id
      and org.deleted_at is null and org.status = 'active'
    where ds.device_id = p_device_id
      and ds.session_token_ref = v_hash
      and ds.is_active and ds.revoked_at is null
      and (ds.expires_at is null or ds.expires_at > now())
      and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null
      and d.is_active and d.deleted_at is null;
  if v_org is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_print_dispatches');
  end if;
  if v_dtype <> 'pos' then
    -- KDS is explicitly denied: printer-only dispatch payloads never reach a
    -- KDS client through any channel.
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_print_dispatches');
  end if;

  select b.kitchen_workflow_mode, b.kitchen_workflow_mode_revision
    into v_mode, v_brev
    from public.branches b
    where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;
  if coalesce(v_mode, 'kds') <> 'printer_only' then
    return jsonb_build_object('ok', false, 'error', 'branch_not_printer_only', 'entity', 'kitchen_print_dispatches');
  end if;

  -- The deploy-ahead compatibility guard: only a device with a FRESH,
  -- activation-capable readiness report may claim. No deployed client reports
  -- the capability, so production claims are impossible today.
  -- CORRECTION-001: the report must also carry the CURRENT branch mode
  -- revision — a device whose cached mode view is stale may not claim.
  if not exists (
    select 1 from public.kitchen_printer_readiness_reports rr
    where rr.organization_id = v_org
      and rr.device_id = p_device_id
      and rr.branch_id = v_branch
      and rr.expires_at > now()
      and rr.capability = 'kitchen_printer_only_v1'
      and rr.printer_purpose = 'kitchen_ticket'
      and rr.paper_width = '80mm'
      and rr.secure_spool_available
      and rr.mode_revision = v_brev
  ) then
    return jsonb_build_object('ok', false, 'error', 'readiness_required', 'entity', 'kitchen_print_dispatches');
  end if;

  v_limit := p_limit;

  -- ATOMIC CLAIM (CORRECTION-001 tuple contract): ORDER BY and the keyset
  -- cursor use the SAME stable tuple (created_at, type_rank, id), so tied
  -- timestamps can never skip or duplicate a row across a drain loop. The
  -- inner FOR UPDATE serializes concurrent pullers; the outer WHERE re-proves
  -- claimability AFTER the lock wait, so two devices can never claim the
  -- same row. Stale claims (expired) and this device's own claims are
  -- reclaimable; possibly_printed rows are NEVER served; superseded rows are
  -- gone from this feed forever; an UNRESOLVED row never ages out — there is
  -- deliberately NO time window here (CORRECTION-001 retention contract).
  with candidates as (
    select d.id
      from public.kitchen_print_dispatches d
      where d.organization_id = v_org
        and d.branch_id = v_branch
        and d.completed_at is null
        and d.superseded_by_dispatch_id is null
        and d.last_client_status is distinct from 'possibly_printed'
        and (d.claimed_at is null
             or d.claim_expires_at < now()
             or d.claimed_by_device_id = p_device_id)
        and (p_cursor_created_at is null
             or (d.created_at,
                 case d.dispatch_type when 'initial_order' then 0
                                      when 'service_round' then 1 else 2 end,
                 d.id)
                > (p_cursor_created_at, p_cursor_type_rank, p_cursor_id))
      order by d.created_at,
               case d.dispatch_type when 'initial_order' then 0
                                    when 'service_round' then 1 else 2 end,
               d.id
      limit v_limit
      for update of d
  )
  update public.kitchen_print_dispatches d
    set claimed_at = now(),
        claimed_by_device_id = p_device_id,
        claim_expires_at = now() + interval '10 minutes',
        updated_at = now()
    from candidates c
    where d.id = c.id
      and d.completed_at is null
      and d.superseded_by_dispatch_id is null
      and (d.claimed_at is null
           or d.claim_expires_at < now()
           or d.claimed_by_device_id = p_device_id);

  -- The returned page: this device's LIVE claims in tuple order, HARD-capped
  -- at p_limit — own pre-existing active claims can never inflate the page
  -- beyond the requested limit (CORRECTION-001).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id,
           'dispatch_type', p.dispatch_type,
           'order_id', p.order_id,
           'service_round_id', p.service_round_id,
           'payload_version', p.payload_version,
           'payload', p.money_free_payload,
           'created_at', p.created_at,
           'claim_expires_at', p.claim_expires_at)
         order by p.created_at, p.type_rank, p.id), '[]'::jsonb),
         count(*)::int,
         (array_agg(p.created_at order by p.created_at desc, p.type_rank desc, p.id desc))[1],
         (array_agg(p.type_rank  order by p.created_at desc, p.type_rank desc, p.id desc))[1],
         (array_agg(p.id         order by p.created_at desc, p.type_rank desc, p.id desc))[1]
    into v_rows, v_count, v_last_at, v_last_rank, v_last_id
    from (
      select d.*,
             case d.dispatch_type when 'initial_order' then 0
                                  when 'service_round' then 1 else 2 end as type_rank
        from public.kitchen_print_dispatches d
        where d.organization_id = v_org
          and d.branch_id = v_branch
          and d.claimed_by_device_id = p_device_id
          and d.claim_expires_at > now()
          and d.completed_at is null
          and d.superseded_by_dispatch_id is null
          and d.last_client_status is distinct from 'possibly_printed'
          and (p_cursor_created_at is null
               or (d.created_at,
                   case d.dispatch_type when 'initial_order' then 0
                                        when 'service_round' then 1 else 2 end,
                   d.id)
                  > (p_cursor_created_at, p_cursor_type_rank, p_cursor_id))
        order by d.created_at,
                 case d.dispatch_type when 'initial_order' then 0
                                      when 'service_round' then 1 else 2 end,
                 d.id
        limit v_limit
    ) p;

  -- TRUTHFUL has_more (CORRECTION-001): true iff a row SERVABLE TO THIS
  -- DEVICE (its own live claim, or still claimable by anyone) exists beyond
  -- the returned page's last tuple.
  if v_count = 0 then
    v_has_more := false;
  else
    select exists (
      select 1 from public.kitchen_print_dispatches d
      where d.organization_id = v_org
        and d.branch_id = v_branch
        and d.completed_at is null
        and d.superseded_by_dispatch_id is null
        and d.last_client_status is distinct from 'possibly_printed'
        and ((d.claimed_by_device_id = p_device_id and d.claim_expires_at > now())
             or d.claimed_at is null
             or d.claim_expires_at < now())
        and (d.created_at,
             case d.dispatch_type when 'initial_order' then 0
                                  when 'service_round' then 1 else 2 end,
             d.id) > (v_last_at, v_last_rank, v_last_id))
      into v_has_more;
  end if;

  return jsonb_build_object(
    'ok', true, 'entity', 'kitchen_print_dispatches',
    'dispatches', v_rows,
    'has_more', v_has_more,
    'next_cursor', case when v_count > 0
                        then jsonb_build_object('created_at', v_last_at, 'type_rank', v_last_rank, 'id', v_last_id)
                        else null end,
    'server_ts', now());
end;
$$;

comment on function app.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid, integer) is
  'KITCHEN-MODE-001C1: the POS''s ATOMIC claim-and-pull. Device-token authenticated (full 001A-corrected liveness; KDS explicitly denied); branch must currently be printer_only; a FRESH activation-capable readiness report carrying the CURRENT branch mode revision is required (the deploy-ahead guard — no deployed client reports it, so production claims are impossible). Claims are per-device with a 10-minute expiry; stale claims are reclaimable; two devices can never win the same row (inner FOR UPDATE + outer re-check). CORRECTION-001: ORDER BY and the keyset cursor share ONE stable tuple (created_at, type_rank initial<round<void, id) — tied timestamps can never skip or duplicate a row across pages; the returned page is hard-capped at p_limit even when the device already held claims; has_more is truthful (a servable row exists beyond the page); the cursor is all-or-nothing and rank-validated; cursorless recovery re-serves own claims. possibly_printed rows are NEVER re-served (a re-print without operator action could duplicate paper); superseded rows are gone forever; an UNRESOLVED row never ages out (no time window). Payload only to the claiming POS. NOTE (D-013): no audit row on this device-only path — claim observability lives on the row (claimed_at/claimed_by).';

create or replace function public.pull_kitchen_print_dispatches(
  p_device_id uuid, p_session_token text, p_limit integer default 20,
  p_cursor_created_at timestamptz default null, p_cursor_id uuid default null,
  p_cursor_type_rank integer default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.pull_kitchen_print_dispatches(p_device_id, p_session_token, p_limit, p_cursor_created_at, p_cursor_id, p_cursor_type_rank); $$;

revoke all on function app.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid, integer) from public;
revoke all on function app.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid, integer) from anon;
grant execute on function app.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid, integer) to authenticated;
revoke all on function public.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid, integer) from public;
revoke all on function public.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid, integer) from anon;
grant execute on function public.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 12. Acknowledgement (+wrapper).
-- ----------------------------------------------------------------------------
create or replace function app.acknowledge_kitchen_print_dispatch(
  p_device_id      uuid,
  p_session_token  text,
  p_dispatch_id    uuid,
  p_client_status  text,
  p_error_code     text default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_hash    text;
  v_org     uuid;
  v_branch  uuid;
  v_dtype   text;
  v_row     public.kitchen_print_dispatches%rowtype;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_print_dispatch');
  end if;
  if p_client_status is null or p_client_status not in
     ('imported', 'transport_accepted', 'possibly_printed', 'failed_retryable', 'blocked_configuration') then
    -- NEVER a physical claim: 'printed'/'paper_printed' are not a vocabulary.
    return jsonb_build_object('ok', false, 'error', 'invalid_status', 'entity', 'kitchen_print_dispatch');
  end if;
  if p_error_code is not null and p_error_code !~ '^[a-z0-9_.\-]{1,64}$' then
    return jsonb_build_object('ok', false, 'error', 'invalid_error_code', 'entity', 'kitchen_print_dispatch');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));

  select ds.organization_id, ds.branch_id, d.device_type
    into v_org, v_branch, v_dtype
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
      and dp.organization_id = ds.organization_id
      and dp.restaurant_id   = ds.restaurant_id
      and dp.branch_id       = ds.branch_id
      and dp.device_id       = ds.device_id
    join public.devices d on d.id = ds.device_id
      and d.organization_id = ds.organization_id
    join public.branches b on b.organization_id = ds.organization_id
      and b.restaurant_id = ds.restaurant_id and b.id = ds.branch_id
      and b.deleted_at is null and b.status = 'active'
    join public.restaurants r on r.organization_id = ds.organization_id
      and r.id = ds.restaurant_id and r.deleted_at is null and r.status = 'active'
    join public.organizations org on org.id = ds.organization_id
      and org.deleted_at is null and org.status = 'active'
    where ds.device_id = p_device_id
      and ds.session_token_ref = v_hash
      and ds.is_active and ds.revoked_at is null
      and (ds.expires_at is null or ds.expires_at > now())
      and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null
      and d.is_active and d.deleted_at is null;
  if v_org is null or v_dtype <> 'pos' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_print_dispatch');
  end if;

  select * into v_row from public.kitchen_print_dispatches d
    where d.id = p_dispatch_id and d.organization_id = v_org and d.branch_id = v_branch
    for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'kitchen_print_dispatch');
  end if;

  -- Idempotent replay: already completed BY THIS DEVICE.
  if v_row.completed_at is not null then
    if v_row.claimed_by_device_id = p_device_id and p_client_status = 'transport_accepted' then
      return jsonb_build_object('ok', true, 'entity', 'kitchen_print_dispatch',
        'dispatch_id', v_row.id, 'completed', true, 'idempotency_replay', true, 'server_ts', now());
    end if;
    return jsonb_build_object('ok', false, 'error', 'conflict', 'entity', 'kitchen_print_dispatch');
  end if;

  -- Claim ownership: the current claim holder while valid, PLUS the designed
  -- stale-recovery path — the device that HELD the claim may still finish its
  -- slow print after expiry, as long as nobody else claimed meanwhile.
  if v_row.claimed_by_device_id is distinct from p_device_id then
    return jsonb_build_object('ok', false, 'error', 'not_claim_owner', 'entity', 'kitchen_print_dispatch');
  end if;

  -- CORRECTION-001 STICKY HOLD: once possibly_printed, the ambiguity can
  -- never be resolved by the machine — paper may or may not exist. The ONLY
  -- allowed acknowledgement is an idempotent possibly_printed replay by the
  -- owner; every other status (imported / failed_retryable /
  -- blocked_configuration / transport_accepted) is refused with a typed
  -- conflict, the permanent no-lease hold stays, and nothing ever becomes
  -- automatically pullable again. Resolution is a future explicit
  -- operator-facing RPC, deliberately NOT part of 001C1.
  if v_row.last_client_status = 'possibly_printed' then
    if p_client_status = 'possibly_printed' then
      return jsonb_build_object('ok', true, 'entity', 'kitchen_print_dispatch',
        'dispatch_id', v_row.id, 'completed', false, 'idempotency_replay', true, 'server_ts', now());
    end if;
    return jsonb_build_object('ok', false, 'error', 'ambiguous_print_hold', 'entity', 'kitchen_print_dispatch');
  end if;

  if p_client_status = 'transport_accepted' then
    update public.kitchen_print_dispatches
      set completed_at = now(), last_client_status = p_client_status,
          last_error_code = null, updated_at = now()
      where id = v_row.id;
  elsif p_client_status = 'possibly_printed' then
    -- Permanent hold: NEVER auto-re-served (a blind retry could duplicate
    -- paper). Stays visible/unresolved until an operator acts (001C2 UX).
    update public.kitchen_print_dispatches
      set last_client_status = p_client_status,
          last_error_code = p_error_code,
          claim_expires_at = null, updated_at = now()
      where id = v_row.id;
  elsif p_client_status = 'imported' then
    update public.kitchen_print_dispatches
      set last_client_status = p_client_status,
          claim_expires_at = now() + interval '10 minutes', updated_at = now()
      where id = v_row.id;
  else
    -- failed_retryable / blocked_configuration: recorded; the claim keeps its
    -- natural expiry so the SAME or another POS can retry after it lapses.
    update public.kitchen_print_dispatches
      set last_client_status = p_client_status,
          last_error_code = p_error_code, updated_at = now()
      where id = v_row.id;
  end if;

  return jsonb_build_object(
    'ok', true, 'entity', 'kitchen_print_dispatch',
    'dispatch_id', v_row.id,
    'completed', (p_client_status = 'transport_accepted'),
    'idempotency_replay', false,
    'server_ts', now());
end;
$$;

comment on function app.acknowledge_kitchen_print_dispatch(uuid, text, uuid, text, text) is
  'KITCHEN-MODE-001C1: POS-only dispatch acknowledgement (device-token, full liveness, KDS denied). Closed NON-PHYSICAL status vocabulary — imported (extends the claim), transport_accepted (completes; idempotent replay for the same device), possibly_printed (PERMANENT STICKY hold — CORRECTION-001: after it, the ONLY acceptable acknowledgement is an idempotent possibly_printed replay by the owner; imported/failed_retryable/blocked_configuration/transport_accepted are refused with ambiguous_print_hold, the no-lease hold stays, nothing becomes automatically pullable again, and resolution is a future explicit operator RPC), failed_retryable / blocked_configuration (recorded; claim expiry keeps running so retry is possible). ''printed'' deliberately does not exist. Only the claim holder may acknowledge, with a stale-recovery path for the device that HELD the claim finishing a slow print. Error codes are allowlisted-shape, length-limited; no payload/endpoint/money is ever logged. Acknowledgement NEVER touches order state. NOTE (D-013): no audit row on this device-only path — observability lives on the row.';

create or replace function public.acknowledge_kitchen_print_dispatch(
  p_device_id uuid, p_session_token text, p_dispatch_id uuid,
  p_client_status text, p_error_code text default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.acknowledge_kitchen_print_dispatch(p_device_id, p_session_token, p_dispatch_id, p_client_status, p_error_code); $$;

revoke all on function app.acknowledge_kitchen_print_dispatch(uuid, text, uuid, text, text) from public;
revoke all on function app.acknowledge_kitchen_print_dispatch(uuid, text, uuid, text, text) from anon;
grant execute on function app.acknowledge_kitchen_print_dispatch(uuid, text, uuid, text, text) to authenticated;
revoke all on function public.acknowledge_kitchen_print_dispatch(uuid, text, uuid, text, text) from public;
revoke all on function public.acknowledge_kitchen_print_dispatch(uuid, text, uuid, text, text) from anon;
grant execute on function public.acknowledge_kitchen_print_dispatch(uuid, text, uuid, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 13. Read-only transition-readiness inspection (+wrapper). Member-authorized
--     (any active membership covering the branch may READ; the future
--     MUTATION stays owner-only in 001C3). Typed blocker codes + safe counts
--     only — no payloads, no customer data, no money, no endpoints. NEVER
--     mutates anything.
-- ----------------------------------------------------------------------------
create or replace function app.get_kitchen_workflow_transition_readiness(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor          uuid := app.current_app_user_id();
  v_rank           integer;
  v_mode           text;
  v_rev            integer;
  v_active_orders  integer;
  v_ready_orders   integer;
  v_active_rounds  integer;
  v_pending_ops    integer;
  v_unresolved     integer;
  v_pending_voids  integer;
  v_report         public.kitchen_printer_readiness_reports%rowtype;
  v_diag           public.kitchen_printer_readiness_reports%rowtype;
  v_used           public.kitchen_printer_readiness_reports%rowtype;
  v_to_po          jsonb := '[]'::jsonb;
  v_to_kds         jsonb := '[]'::jsonb;
begin
  if v_actor is null then
    raise exception 'get_kitchen_workflow_transition_readiness: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;

  select b.kitchen_workflow_mode, b.kitchen_workflow_mode_revision
    into v_mode, v_rev
    from public.branches b
    where b.id = p_branch_id and b.organization_id = p_organization_id
      and b.restaurant_id = p_restaurant_id and b.deleted_at is null;
  if v_mode is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;

  -- The server RECOMPUTES every server-side blocker itself; the only client
  -- input is the fresh device-session-proven readiness report row.
  select count(*)::int into v_active_orders
    from public.orders o
    where o.organization_id = p_organization_id and o.branch_id = p_branch_id
      and o.deleted_at is null
      and o.status in ('submitted', 'accepted', 'preparing', 'ready', 'served');
  select count(*)::int into v_ready_orders
    from public.orders o
    where o.organization_id = p_organization_id and o.branch_id = p_branch_id
      and o.deleted_at is null and o.status = 'ready';
  select count(*)::int into v_active_rounds
    from public.order_service_rounds r
    where r.organization_id = p_organization_id and r.branch_id = p_branch_id
      and r.deleted_at is null
      and r.status in ('submitted', 'accepted', 'preparing', 'ready');
  select count(*)::int into v_pending_ops
    from public.sync_operations so
    where so.organization_id = p_organization_id and so.branch_id = p_branch_id
      and so.status in ('created', 'pending', 'in_flight');
  select count(*)::int into v_unresolved
    from public.kitchen_print_dispatches d
    where d.organization_id = p_organization_id and d.branch_id = p_branch_id
      and d.completed_at is null and d.superseded_by_dispatch_id is null;
  select count(*)::int into v_pending_voids
    from public.kitchen_print_dispatches d
    where d.organization_id = p_organization_id and d.branch_id = p_branch_id
      and d.dispatch_type = 'void'
      and d.completed_at is null and d.superseded_by_dispatch_id is null;
  -- CORRECTION-001 readiness selection: the report that satisfies a blocker
  -- must be a FULLY QUALIFYING one — fresh, activation-capable (80mm + secure
  -- spool), carrying the CURRENT mode revision, and filed by a LIVE,
  -- correctly-scoped, actively-paired POS device. A newer non-qualifying
  -- report (58mm, stale revision, revoked device, ...) can never SHADOW a
  -- valid qualifying report from another compatible POS.
  select rr.* into v_report
    from public.kitchen_printer_readiness_reports rr
    join public.devices d
      on  d.id = rr.device_id
      and d.organization_id = rr.organization_id
      and d.restaurant_id   = rr.restaurant_id
      and d.branch_id       = rr.branch_id
      and d.device_type = 'pos' and d.is_active and d.deleted_at is null
    where rr.organization_id = p_organization_id and rr.branch_id = p_branch_id
      and rr.expires_at > now()
      and rr.capability = 'kitchen_printer_only_v1'
      and rr.printer_purpose = 'kitchen_ticket'
      and rr.paper_width = '80mm'
      and rr.secure_spool_available
      and rr.mode_revision = v_rev
      and exists (select 1 from public.device_pairings dp
                   where dp.device_id = d.id and dp.organization_id = d.organization_id
                     and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null)
    order by rr.reported_at desc
    limit 1;
  if v_report.id is null then
    -- DIAGNOSTIC fallback (still live-device + fresh + capability-matched):
    -- names the SPECIFIC deficiency instead of a generic absence.
    select rr.* into v_diag
      from public.kitchen_printer_readiness_reports rr
      join public.devices d
        on  d.id = rr.device_id
        and d.organization_id = rr.organization_id
        and d.restaurant_id   = rr.restaurant_id
        and d.branch_id       = rr.branch_id
        and d.device_type = 'pos' and d.is_active and d.deleted_at is null
      where rr.organization_id = p_organization_id and rr.branch_id = p_branch_id
        and rr.expires_at > now()
        and rr.capability = 'kitchen_printer_only_v1'
        and rr.printer_purpose = 'kitchen_ticket'
        and exists (select 1 from public.device_pairings dp
                     where dp.device_id = d.id and dp.organization_id = d.organization_id
                       and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null)
      order by rr.reported_at desc
      limit 1;
  end if;
  if v_report.id is not null then
    v_used := v_report;
  else
    v_used := v_diag;
  end if;

  -- kds -> printer_only blockers.
  if v_active_orders > 0 then v_to_po := v_to_po || '"active_orders"'::jsonb; end if;
  if v_active_rounds > 0 then v_to_po := v_to_po || '"active_service_rounds"'::jsonb; end if;
  if v_ready_orders > 0 then v_to_po := v_to_po || '"unresolved_ready_state"'::jsonb; end if;
  if v_pending_ops > 0 then v_to_po := v_to_po || '"unresolved_sync_operations"'::jsonb; end if;
  if v_report.id is not null then
    null; -- a fully qualifying live report exists: no readiness blocker.
  elsif v_diag.id is null then
    v_to_po := v_to_po || '"no_fresh_pos_readiness"'::jsonb;
  else
    if v_diag.paper_width <> '80mm' then v_to_po := v_to_po || '"paper_width_80mm_required"'::jsonb; end if;
    if not v_diag.secure_spool_available then v_to_po := v_to_po || '"secure_spool_unavailable"'::jsonb; end if;
    if v_diag.mode_revision <> v_rev then v_to_po := v_to_po || '"stale_mode_revision"'::jsonb; end if;
  end if;

  -- printer_only -> kds blockers.
  if v_unresolved > 0 then v_to_kds := v_to_kds || '"unresolved_dispatches"'::jsonb; end if;
  if v_pending_voids > 0 then v_to_kds := v_to_kds || '"pending_void_dispatches"'::jsonb; end if;
  if v_active_orders > 0 then v_to_kds := v_to_kds || '"active_orders"'::jsonb; end if;
  if v_active_rounds > 0 then v_to_kds := v_to_kds || '"active_service_rounds"'::jsonb; end if;
  if v_used.id is null then
    v_to_kds := v_to_kds || '"no_fresh_pos_status_report"'::jsonb;
  elsif v_used.unresolved_local_jobs > 0 then
    v_to_kds := v_to_kds || '"unresolved_local_jobs"'::jsonb;
  end if;

  return jsonb_build_object(
    'ok', true, 'entity', 'kitchen_workflow_transition_readiness',
    'mode', v_mode,
    'mode_revision', v_rev,
    'to_printer_only', jsonb_build_object(
      'ready', (jsonb_array_length(v_to_po) = 0), 'blockers', v_to_po),
    'to_kds', jsonb_build_object(
      'ready', (jsonb_array_length(v_to_kds) = 0), 'blockers', v_to_kds),
    'counts', jsonb_build_object(
      'active_orders', v_active_orders,
      'active_service_rounds', v_active_rounds,
      'ready_orders', v_ready_orders,
      'pending_sync_operations', v_pending_ops,
      'unresolved_dispatches', v_unresolved,
      'pending_void_dispatches', v_pending_voids,
      'unresolved_local_jobs', coalesce(v_used.unresolved_local_jobs, 0)),
    'readiness_report', case when v_used.id is null then null else jsonb_build_object(
      'reported_at', v_used.reported_at,
      'expires_at', v_used.expires_at,
      'paper_width', v_used.paper_width,
      'transport_kind', v_used.transport_kind,
      'secure_spool_available', v_used.secure_spool_available,
      'app_build', v_used.app_build,
      -- CORRECTION-001: says explicitly whether this is the fully QUALIFYING
      -- live report or only the best diagnostic one.
      'qualifying', (v_report.id is not null)) end,
    'server_ts', now());
end;
$$;

comment on function app.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid) is
  'KITCHEN-MODE-001C1: READ-ONLY inspection of every kitchen-workflow transition blocker (typed codes + safe counts only — no payloads, customer data, money or endpoints). The server recomputes every server-side blocker; the only client-derived input is the readiness report. CORRECTION-001 selection: a blocker is satisfied ONLY by a fully QUALIFYING report — fresh, 80mm + secure spool, current mode revision, filed by a LIVE active correctly-scoped actively-paired POS device — and a newer non-qualifying report can never shadow a qualifying one from another POS; when none qualifies, the best live diagnostic report names the specific deficiency (paper/spool/revision) and unresolved_local_jobs comes only from a live-device report. Unresolved dispatches are counted with NO age window (an old unresolved row still blocks). Any active member covering the branch may READ (matches branch-settings read visibility); the future MUTATION (001C3 setter) is owner-only. Never changes mode; never mutates anything.';

create or replace function public.get_kitchen_workflow_transition_readiness(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.get_kitchen_workflow_transition_readiness(p_organization_id, p_restaurant_id, p_branch_id); $$;

revoke all on function app.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid) from public;
revoke all on function app.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid) from anon;
grant execute on function app.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid) to authenticated;
revoke all on function public.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid) from public;
revoke all on function public.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid) from anon;
grant execute on function public.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid) to authenticated;


-- ----------------------------------------------------------------------------
-- 14. Audit trio — faithful re-creations (audit_category from 20260711120000
--     via the 20260724090000 printer delta; has_detail/safe_detail from
--     20260724090000) with the KITCHEN-MODE-001C1 kitchen.% additions.
-- ----------------------------------------------------------------------------

create or replace function app.audit_category(p_action text)
  returns text
  language sql
  immutable
  set search_path = ''
as $$
  select case
    when p_action like 'order.discount%'                               then 'discounts'
    when p_action like 'order.void%'                                   then 'voids'
    when p_action like 'order.%'                                       then 'orders'
    when p_action like 'payment.%' or p_action like 'receipt_number.%' then 'payments'
    when p_action like 'shift.%'   or p_action like 'cash_drawer.%'    then 'shifts'
    when p_action like 'staff.%'                                       then 'staff'
    when p_action like 'membership.%' or p_action like 'employee.%'
         or p_action like 'pin_session.%'                             then 'access'
    when p_action like 'device.%'                                     then 'devices'
    when p_action like 'settings.%'                                   then 'settings'
    -- KITCHEN-MODE-001B: printer configuration IS settings work.
    when p_action like 'printer.%'                                    then 'settings'
    -- KITCHEN-MODE-001C1: kitchen dispatch events are ORDER work.
    when p_action like 'kitchen.%'                                    then 'orders'
    when p_action like 'menu.%'                                       then 'menu'
    when p_action like 'table.%'                                      then 'tables'
    when p_action like 'organization.%'                               then 'organization'
    when p_action like 'sync.%'                                       then 'sync'
    else 'other'
  end;
$$;



comment on function app.audit_category(text) is
  'AUDIT-COVERAGE-002 + KITCHEN-MODE-001B + KITCHEN-MODE-001C1: the single classification source of truth. printer.% -> settings (001B); kitchen.% (dispatch events) -> orders (001C1). Faithful re-creation otherwise.';

revoke all on function app.audit_category(text) from public;


create or replace function app.audit_action_has_detail(p_action text)
  returns boolean
  language sql
  immutable
  set search_path = ''
as $$
  select coalesce(p_action, '') like 'order.void%'
      or p_action like 'order.discount%'
      or p_action like 'order.status%'
      or p_action =    'order.submitted'
      -- RESTAURANT-OPERATIONS-V1-001: table moves (order.table_moved +
      -- order.table_move_denied) carry before/after labels + denied reasons.
      or p_action like 'order.table_mov%'
      or p_action like 'staff.capabilities%'
      -- FULL-COMP-PERMISSION-001: staff.created was NOT projected, so the capabilities
      -- a cashier is PROVISIONED with were written to the append-only trail and then
      -- never shown. Granting "make orders free" invisibly is exactly what this ticket
      -- must not do, so the CREATE path is projected too.
      or p_action =    'staff.created'
      or p_action like 'membership.%'
      or p_action like 'shift.%'
      or p_action like 'cash_drawer.%'
      or p_action like 'payment.%'
      or p_action like 'settings.%'
      -- RESTAURANT-OPERATIONS-V1-001: branch availability changes/denials carry
      -- before/after availability + the item name (menu.* was previously
      -- metadata-only; ONLY the availability family gains detail).
      or p_action like 'menu.%.availability%'
      -- PILOT-OPERATIONS-CORRECTIONS-001: manual table status changes/denials
      -- (before/after floor status) and link/unlink (group label) carry detail.
      or p_action like 'table.status%'
      or p_action like 'table.tables_%'
      or p_action like 'table.link%'
      or p_action like 'table.unlink%'
      -- PSC-001C: order additions (round_number/added_item_count) and round
      -- status changes (round_number/from_status/to_status) carry safe detail.
      or p_action like 'order.items_add%'
      or p_action like 'order.round_status%'
      -- KITCHEN-MODE-001B: printer configuration actions carry a safe scalar
      -- projection (display_name / role / paper_width / is_enabled /
      -- connection_type). connection_config stays a nested object, so the
      -- scalar-only allowlist can never surface host/port/addresses.
      or p_action like 'printer.%'
      -- KITCHEN-MODE-001C1: kitchen dispatch events carry safe scalars only
      -- (order_code / dispatch_type / membership) — never the payload.
      or p_action like 'kitchen.%'
      or p_action =    'pin_session.failed';
$$;


comment on function app.audit_action_has_detail(text) is
  'AUDIT-LOG-DASHBOARD-001 .. KITCHEN-MODE-001B + KITCHEN-MODE-001C1: adds the kitchen.% dispatch family (safe scalars only — order_code / dispatch_type; the money_free_payload is never projected). Faithful re-creation of the 20260724090000 body. Gates app.audit_safe_detail.';


create or replace function app.audit_safe_detail(p_action text, p_values jsonb)
  returns jsonb
  language plpgsql
  immutable
  set search_path = ''
as $$
declare
  v_out  jsonb := '{}'::jsonb;
  v_caps jsonb;
  v_key  text;
begin
  -- Unknown / unsupported action -> no payload details.
  if not app.audit_action_has_detail(p_action) then
    return '{}'::jsonb;
  end if;
  -- Malformed / missing / non-object payload -> empty safe detail (never throws).
  if p_values is null or jsonb_typeof(p_values) <> 'object' then
    return '{}'::jsonb;
  end if;

  -- Canonical SAFE SCALAR allowlist. A key is emitted ONLY when it is on this
  -- list AND its value is a scalar (string/number/boolean) — nested objects,
  -- arrays, and every un-listed key (secret OR merely unknown) are dropped.
  foreach v_key in array array[
    'status','order_status','scope','discount_type','value','attempted_action','order_type',
    'role','from_role','to_role','target_role',
    'discount_total_minor','grand_total_minor','subtotal_minor','line_total_minor','line_discount_minor',
    'amount_minor','tendered_minor','change_minor','opening_float_minor',
    'expected_cash_minor','counted_cash_minor','cash_variance_minor','variance_minor',
    'voided_item_count','failed_attempt_count','locked',
    'timezone','name','receipt_prefix',
    'order_code','payment_status',
    -- ORDER-AUTO-COMPLETION-001: how, and why, an order was completed. Both are
    -- STATES ('automatic'/'manual', 'order_served'/'payment_recorded'), not money
    -- and not identifiers — T-003 still holds.
    'completion_mode','completion_trigger',
    -- MONEY-SETTLEMENT-CONSISTENCY-001: WHY a mutation was denied. order.discount_denied
    -- and order.void_denied have always carried this, but it was never allowlisted — so
    -- the Activity Log showed THAT a discount was refused and never WHY. It is a closed
    -- enum of safe STATE tokens (order_has_completed_payment | full_comp_requires_manager),
    -- never money and never an identifier (T-003 holds).
    'denied_reason',
    -- FULL-COMP-PERMISSION-001: WHAT the mutation would have left the order as. A
    -- closed enum of STATE tokens ('not_chargeable') -- never money, never an
    -- identifier (T-003 holds).
    'resulting_charge_state',
    -- RESTAURANT-OPERATIONS-V1-001: branch availability (closed enums
    -- available|unavailable / sold_out|paused) + the menu item's display name,
    -- and table-move floor labels (human table names). Names/labels are tenant
    -- display text already shown on receipts/tickets — never money, never ids.
    'availability','availability_reason','item_name',
    'table_label','from_table_label','to_table_label',
    -- PILOT-OPERATIONS-CORRECTIONS-001: manual table status transition
    -- (closed enum available|reserved|occupied|out_of_service) + the combined
    -- group label (floor names). Never money, never identifiers (T-003 holds).
    'from_status','to_status','group_label',
    -- PSC-001D: void provenance + kitchen acknowledgement. voided_from_status
    -- is the closed order-status enum; device_type is the closed pos|kds enum;
    -- kitchen_ack_required is a boolean. Never money, never identifiers
    -- (T-003 holds).
    'voided_from_status','device_type','kitchen_ack_required',
    -- PSC-001C: service rounds. round_number and added_item_count are small
    -- integers (a position in the order and a line count) — never money,
    -- never identifiers (T-003 holds).
    'round_number','added_item_count',
    -- KITCHEN-MODE-001B: printer configuration scalars. display_name is tenant
    -- display text (the item_name/table_label class); the rest are closed
    -- enums/booleans. connection_config (host/port/addresses) is a NESTED
    -- OBJECT and is therefore structurally dropped by the scalar-only rule —
    -- endpoints never reach the Activity Log timeline.
    'display_name','paper_width','is_enabled','connection_type',
    -- KITCHEN-MODE-001C1: kitchen dispatch safe scalars (closed enum + the
    -- existing safe order_code class). The money_free_payload itself is
    -- NEVER projected into audit detail.
    'dispatch_type'
  ] loop
    -- PSC-001C correction (Finding 6): the four service-round actions are
    -- MONEY-FREE by approved contract — any *_minor key (hostile, manual, or
    -- accidental) is dropped for EXACTLY these actions, action-specifically:
    -- the approved money-carrying actions (payments / discounts / shifts /
    -- order.submitted / completion) keep their allowlisted money keys.
    if (p_action like 'order.items_add%' or p_action like 'order.round_status%'
        -- KITCHEN-MODE-001B: printer configuration is MONEY-FREE by contract —
        -- the same hostile-key hardening applies to the whole printer family.
        or p_action like 'printer.%'
        -- KITCHEN-MODE-001C1: kitchen dispatch events are MONEY-FREE too.
        or p_action like 'kitchen.%')
       and v_key like '%\_minor' escape '\' then
      continue;
    end if;
    if p_values ? v_key
       and jsonb_typeof(p_values -> v_key) in ('string','number','boolean') then
      v_out := v_out || jsonb_build_object(v_key, p_values -> v_key);
    end if;
  end loop;

  -- The ONLY allowlisted nested object: `capabilities`, kept to its four
  -- canonical boolean capability keys (unknown nested keys dropped).
  if jsonb_typeof(p_values -> 'capabilities') = 'object' then
    select coalesce(jsonb_object_agg(k, p_values -> 'capabilities' -> k), '{}'::jsonb)
      into v_caps
      from unnest(array['apply_discount','void_order','close_shift','apply_full_comp','manage_menu_availability','manage_table_operations']) as k
      where (p_values -> 'capabilities') ? k
        and jsonb_typeof(p_values -> 'capabilities' -> k) in ('string','number','boolean');
    if v_caps is distinct from '{}'::jsonb then
      v_out := v_out || jsonb_build_object('capabilities', v_caps);
    end if;
  end if;

  return v_out;
end;
$$;


comment on function app.audit_safe_detail(text, jsonb) is
  'ALLOWLIST projection of one audit payload to canonical safe fields (see 20260724090000) + KITCHEN-MODE-001C1 dispatch_type. kitchen.% joins the MONEY-FREE hostile-key hardening (every *_minor key dropped for the family). Faithful re-creation otherwise; every un-listed key/structure dropped; malformed -> ''{}''; never throws.';


-- ----------------------------------------------------------------------------
-- 15. app.sync_push — faithful re-creation of the NEWEST body (20260722090000
--     lines 1672-2370; verified: no later migration re-creates it) with ONE
--     CORRECTION-001 delta, inside the order.submit case only: after the
--     ORDER-CUSTOMER-001 customer_name stamp, the order's initial kitchen
--     dispatch payload is REBUILT via the internal builder in the same
--     transaction (marked inline). The operation registry (all 15 ops),
--     signatures, envelopes, identity hardening, atomic ledger claim,
--     batch/finalization semantics, grants, search_path and every other
--     behavior are verbatim. public.sync_push (20260628090000) is untouched
--     and keeps calling this by name.
-- ----------------------------------------------------------------------------
create or replace function app.sync_push(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_operations     jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org          uuid;
  v_rest         uuid;
  v_branch       uuid;
  v_dsid         uuid;
  v_emp          uuid;
  v_membership   uuid;
  v_ds_device    uuid;
  v_ds_active    boolean;
  v_ds_revoked   timestamptz;
  v_pairing      text;
  v_op           jsonb;
  v_local_op     text;
  v_op_type      text;
  v_payload      jsonb;
  v_depends      jsonb;
  v_target_ent   text;
  v_target_id    uuid;
  v_client_ts    timestamptz;
  v_fingerprint  text;
  v_dep          text;
  v_dep_ok       boolean;
  v_ex_status    text;
  v_ex_result    jsonb;
  v_ex_optype    text;
  v_ex_fp        text;
  -- PSC-001C correction (Finding 1): the existing row's id when the atomic
  -- ledger claim loses, and whether this request ADOPTED a stale non-terminal
  -- row (the only case that bumps retry_count — the pre-fix contract).
  v_ex_id        uuid;
  v_adopted      boolean;
  v_so_id        uuid;
  v_dispatch     jsonb;
  v_dispatch_ok  boolean;
  v_caught_state text;
  v_caught_msg   text;
  v_results      jsonb := '[]'::jsonb;
  v_op_result    jsonb;
  v_device_revoked boolean := false;
  v_customer_name text;
  v_ack_order    uuid;
  v_ack_ok       boolean;
begin
  -- (0) batch shape + a conservative size cap (no frozen limit in docs; 100 is the
  --     interim cap, surfaced here and in the tests — keeps a push transaction bounded).
  if p_operations is null or jsonb_typeof(p_operations) <> 'array' then
    raise exception 'sync_push: p_operations must be a JSON array' using errcode = '42501';
  end if;
  if jsonb_array_length(p_operations) > 100 then
    raise exception 'sync_push: batch too large (max 100 operations, got %)', jsonb_array_length(p_operations) using errcode = '42501';
  end if;

  -- (a) PIN session + backing device session/pairing. Scope is derived here. The PIN
  --     session must exist + be valid (offline-window bounded, Q-009); a missing session
  --     or expired PIN still raises (cannot key/record safely without a session/window).
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'sync_push: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'sync_push: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found then
    raise exception 'sync_push: backing device session not found' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'sync_push: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  -- RF061-A1: a REVOKED / inactive device session or pairing no longer fails the whole
  -- batch with a silent raise. Instead each pushed op is RECORDED as rejected
  -- (revoked_device) and surfaced, so the offline-queued operations are not lost (R-007;
  -- AC1). Authorization is INGEST-TIME (the device is revoked NOW); client timestamps are
  -- never trusted. A previously-APPLIED op still replays its stored result (idempotency).
  if not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    v_device_revoked := true;
    for v_op in select * from jsonb_array_elements(p_operations)
    loop
      v_local_op   := v_op ->> 'local_operation_id';
      v_op_type    := v_op ->> 'operation_type';
      v_payload    := v_op -> 'payload';
      v_depends    := coalesce(v_op -> 'depends_on', '[]'::jsonb);
      v_target_ent := v_op ->> 'target_entity';
      -- PSC-001D correction (F3) + PSC-001C: for the three IDENTITY-HARDENED
      -- operations (order.void_ack, order.items_add, order.round_status) the
      -- target id is parsed inside a PROTECTED boundary — a malformed uuid
      -- must reject only ITS operation, never abort the whole batch. The 12
      -- prior operations keep their exact existing parse semantics.
      if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
        begin
          v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
        exception when others then
          v_target_id := null;
        end;
      else
        v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
      end if;
      v_client_ts  := nullif(v_op ->> 'client_created_at', '')::timestamptz;

      -- envelope validation (same as the valid path): malformed -> rejected result, NO ledger row
      if v_local_op is null or btrim(v_local_op) = '' then
        v_results := v_results || jsonb_build_object('ok', false, 'error', 'invalid_envelope',
          'detail', 'local_operation_id is required', 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
      if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink', 'order.void_ack', 'order.items_add', 'order.round_status') then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'ok', false,
          'error', 'unknown_operation_type', 'detail', coalesce(v_op_type, '<null>'), 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
      if v_payload is null or jsonb_typeof(v_payload) <> 'object' then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
          'ok', false, 'error', 'invalid_payload', 'detail', 'payload must be a JSON object', 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;

      -- PSC-001D correction (final pass) + PSC-001C: the SAME canonical
      -- identity contract as the valid path for ALL THREE hardened operations,
      -- enforced BEFORE the fingerprint, the terminal-replay lookup, the
      -- idempotency-conflict comparison and the ledger write. A revoked device
      -- must not gain permission to submit ambiguous or contradictory
      -- operation identity: a missing, malformed or CONTRADICTORY
      -- target/payload-identity pair (payload.order_id for order.void_ack and
      -- order.items_add; payload.round_id for order.round_status) is a hostile
      -- or malformed envelope — rejected with NO ledger row (the malformed-
      -- envelope convention), the batch continues. Only that op is affected.
      if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
        v_ack_ok := v_target_id is not null;
        begin
          v_ack_order := nullif(v_payload ->> (case when v_op_type = 'order.round_status' then 'round_id' else 'order_id' end), '')::uuid;
        exception when others then
          v_ack_order := null;
        end;
        if v_ack_order is null or not v_ack_ok or v_target_id <> v_ack_order then
          v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
            'ok', false, 'error', 'invalid_payload',
            'detail', v_op_type || ' requires matching uuid target_id and payload.'
                      || (case when v_op_type = 'order.round_status' then 'round_id' else 'order_id' end),
            'status', 'rejected', 'idempotency_replay', false);
          continue;
        end if;
      end if;

      -- PSC-001D correction (F2 + final pass) + PSC-001C: the SAME target-
      -- bound fingerprint SHAPE as the valid path for all three hardened
      -- operations — the target component is the PARSED uuid's text
      -- (guaranteed non-null and equal to the parsed payload identity by the
      -- check above), so a legitimately-applied op still replays its stored
      -- result after a revocation (identical identity -> identical
      -- fingerprint), while the 12 prior operations are unchanged.
      if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
        v_fingerprint := md5(v_op_type || '|' || v_payload::text || '|' || v_target_id::text);
      else
        v_fingerprint := md5(v_op_type || '|' || v_payload::text);
      end if;

      -- dedup/replay (PSC-001C correction, Finding 1 — ATOMIC CLAIM): the
      -- rejected/revoked_device recording is now claimed with ONE
      -- INSERT .. ON CONFLICT DO NOTHING on the transport identity. When the
      -- claim loses, the existing row is LOCKED (waiting out any concurrent
      -- claimant's COMMIT) and decided from its COMMITTED state: a TERMINAL
      -- row replays its stored result (a legitimately-APPLIED op before
      -- revocation is NOT re-rejected — and can no longer be OVERWRITTEN by
      -- this path racing a valid-device apply); a different identity is a
      -- conflict; only a genuinely stale NON-terminal row is re-recorded as
      -- rejected (the pre-fix retry contract, bump included).
      v_so_id := null;
      insert into public.sync_operations as so (
        organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type,
        target_entity, target_id, payload, payload_fingerprint, depends_on, status,
        last_error_code, last_error_class, rejection_reason,
        result, client_created_at)
      values (v_org, v_rest, v_branch, p_device_id, v_local_op, v_op_type,
              v_target_ent, v_target_id, v_payload, v_fingerprint, v_depends, 'rejected',
              'revoked_device', 'permanent', 'revoked_device',
              jsonb_build_object('ok', false, 'error', 'rejected', 'detail', 'revoked_device'), v_client_ts)
      on conflict (organization_id, device_id, local_operation_id) do nothing
      returning so.id into v_so_id;
      if v_so_id is null then
        select so.id, so.status, so.result, so.operation_type, so.payload_fingerprint
          into v_ex_id, v_ex_status, v_ex_result, v_ex_optype, v_ex_fp
          from public.sync_operations so
          where so.organization_id = v_org and so.device_id = p_device_id and so.local_operation_id = v_local_op
          for update;
        if v_ex_optype <> v_op_type or v_ex_fp <> v_fingerprint then
          insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
          values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_conflict', null, null,
                  jsonb_build_object('local_operation_id', v_local_op, 'stored_operation_type', v_ex_optype, 'pushed_operation_type', v_op_type,
                                     'stored_status', v_ex_status, 'reason', 'idempotency_key_reused_with_different_operation_or_payload'));
          v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
            'error', 'conflict', 'detail', 'idempotency key already used for a different operation/payload', 'status', 'conflict', 'idempotency_replay', false);
          continue;
        end if;
        if v_ex_status in ('applied', 'rejected', 'dead', 'conflict') then
          v_results := v_results || (coalesce(v_ex_result, '{}'::jsonb)
            || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', v_ex_status, 'idempotency_replay', true));
          continue;
        end if;
        -- a stale NON-terminal row: re-record it as rejected (revoked_device)
        -- under the held lock — the pre-fix on-conflict contract, verbatim.
        update public.sync_operations as so
          set status = 'rejected', last_error_code = 'revoked_device', last_error_class = 'permanent',
              rejection_reason = 'revoked_device',
              result = jsonb_build_object('ok', false, 'error', 'rejected', 'detail', 'revoked_device'),
              retry_count = so.retry_count + 1, updated_at = now()
          where so.id = v_ex_id;
      end if;
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected', 'revoked_device', null,
              jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'reason', 'revoked_device'));
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
        'error', 'rejected', 'detail', 'revoked_device', 'status', 'rejected', 'idempotency_replay', false);
    end loop;
    return jsonb_build_object('ok', true, 'results', v_results, 'server_ts', now(), 'device_revoked', true);
  end if;

  -- (b) per-operation loop (ordered) — VALID device path (unchanged from RF-056)
  for v_op in select * from jsonb_array_elements(p_operations)
  loop
    v_caught_state := null;
    v_caught_msg   := null;
    v_dispatch     := null;
    v_dispatch_ok  := null;
    v_so_id        := null;

    v_local_op   := v_op ->> 'local_operation_id';
    v_op_type    := v_op ->> 'operation_type';
    v_payload    := v_op -> 'payload';
    v_depends    := coalesce(v_op -> 'depends_on', '[]'::jsonb);
    v_target_ent := v_op ->> 'target_entity';
    -- PSC-001D correction (F3) + PSC-001C: protected parse for the three
    -- identity-hardened operations — a malformed target uuid rejects only ITS
    -- operation (below), never the batch. The 12 prior operations keep their
    -- exact existing semantics.
    if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
      begin
        v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
      exception when others then
        v_target_id := null;
      end;
    else
      v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
    end if;
    v_client_ts  := nullif(v_op ->> 'client_created_at', '')::timestamptz;

    -- (b1) envelope shape validation. Malformed envelopes are returned rejected
    --      WITHOUT a ledger row (they cannot be keyed/stored safely); they never dispatch.
    if v_local_op is null or btrim(v_local_op) = '' then
      v_results := v_results || jsonb_build_object('ok', false, 'error', 'invalid_envelope',
        'detail', 'local_operation_id is required', 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;
    if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink', 'order.void_ack', 'order.items_add', 'order.round_status') then
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'ok', false,
        'error', 'unknown_operation_type', 'detail', coalesce(v_op_type, '<null>'), 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;
    if v_payload is null or jsonb_typeof(v_payload) <> 'object' then
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
        'ok', false, 'error', 'invalid_payload', 'detail', 'payload must be a JSON object', 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;
    if jsonb_typeof(v_depends) <> 'array' then
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
        'ok', false, 'error', 'invalid_depends_on', 'detail', 'depends_on must be a JSON array', 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;

    -- (b1+) PSC-001D correction (F2/F3) + PSC-001C: CANONICAL TARGET IDENTITY
    -- for the three hardened operations, enforced BEFORE the fingerprint, the
    -- terminal-replay lookup and the dispatch. The envelope MUST carry a
    -- parseable target_id AND a parseable payload identity (payload.order_id
    -- for order.void_ack and order.items_add; payload.round_id for
    -- order.round_status) and they MUST be the same uuid — a missing,
    -- malformed or CONTRADICTORY pair is a hostile/malformed envelope:
    -- rejected with NO ledger row (the malformed-envelope convention), so a
    -- replayed local_operation_id with a swapped target can never reach the
    -- stored terminal result, mutate anything, or learn anything about
    -- another order or round. Only that operation is affected.
    if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
      v_ack_ok := v_target_id is not null;
      begin
        v_ack_order := nullif(v_payload ->> (case when v_op_type = 'order.round_status' then 'round_id' else 'order_id' end), '')::uuid;
      exception when others then
        v_ack_order := null;
      end;
      if v_ack_order is null or not v_ack_ok or v_target_id <> v_ack_order then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
          'ok', false, 'error', 'invalid_payload',
          'detail', v_op_type || ' requires matching uuid target_id and payload.'
                    || (case when v_op_type = 'order.round_status' then 'round_id' else 'order_id' end),
          'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
    end if;

    -- PSC-001D correction (F2) + PSC-001C: the fingerprint of every hardened
    -- operation BINDS the canonical target identity, so a terminal replay is
    -- valid only for the same local_operation_id + operation + payload +
    -- TARGET. The 12 prior operations keep their exact existing fingerprint
    -- semantics.
    if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
      v_fingerprint := md5(v_op_type || '|' || v_payload::text || '|' || v_target_id::text);
    else
      v_fingerprint := md5(v_op_type || '|' || v_payload::text);
    end if;

    -- (b2) ATOMIC LEDGER CLAIM (PSC-001C correction, Finding 1). The pre-fix
    -- shape read the ledger and only LATER upserted it, so two concurrent
    -- requests with the SAME (org, device, local_operation_id) + fingerprint
    -- could both pass the read; the loser's upsert then dragged the winner's
    -- COMMITTED terminal row back to in_flight, re-dispatched (now an
    -- invalid_transition), and finalized the previously-successful row as
    -- rejected. The claim is now ONE INSERT .. ON CONFLICT DO NOTHING on the
    -- transport identity, computed AFTER envelope validation + identity
    -- canonicalization + the fingerprint:
    --   * claim WON  -> this transaction owns dispatch (fresh row, in_flight,
    --     retry_count 0) and finalizes it exactly once at (b6);
    --   * claim LOST -> the existing row is LOCKED (FOR UPDATE — waiting out a
    --     concurrent claimant's COMMIT) and decided from COMMITTED state: a
    --     fingerprint/op mismatch keeps the exact idempotency-conflict
    --     contract; a TERMINAL row replays its stored result (and can never be
    --     overwritten or reset to in_flight again); only a genuinely stale
    --     NON-terminal row (pending / crashed in_flight) is ADOPTED — the
    --     pre-fix retry contract, bump included. A losing concurrent caller
    --     therefore converges on the winner's stored terminal result.
    v_adopted := false;
    v_so_id   := null;
    insert into public.sync_operations as so (
      organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type,
      target_entity, target_id, payload, payload_fingerprint, depends_on, status, client_created_at)
    values (v_org, v_rest, v_branch, p_device_id, v_local_op, v_op_type,
            v_target_ent, v_target_id, v_payload, v_fingerprint, v_depends, 'in_flight', v_client_ts)
    on conflict (organization_id, device_id, local_operation_id) do nothing
    returning so.id into v_so_id;

    if v_so_id is null then
      select so.id, so.status, so.result, so.operation_type, so.payload_fingerprint
        into v_ex_id, v_ex_status, v_ex_result, v_ex_optype, v_ex_fp
        from public.sync_operations so
        where so.organization_id = v_org and so.device_id = p_device_id and so.local_operation_id = v_local_op
        for update;
      if v_ex_optype <> v_op_type or v_ex_fp <> v_fingerprint then
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_conflict', null, null,
                jsonb_build_object('local_operation_id', v_local_op, 'stored_operation_type', v_ex_optype, 'pushed_operation_type', v_op_type,
                                   'stored_status', v_ex_status, 'reason', 'idempotency_key_reused_with_different_operation_or_payload'));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'conflict', 'detail', 'idempotency key already used for a different operation/payload', 'status', 'conflict', 'idempotency_replay', false);
        continue;
      end if;
      if v_ex_status in ('applied', 'rejected', 'dead', 'conflict') then
        v_results := v_results || (coalesce(v_ex_result, '{}'::jsonb)
          || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', v_ex_status, 'idempotency_replay', true));
        continue;
      end if;
      v_so_id   := v_ex_id;
      v_adopted := true;
    end if;

    -- (b3) dependency guard (still BEFORE any dispatch; the claimed/adopted
    -- row is parked as pending exactly like the pre-fix contract — a fresh
    -- claim keeps retry_count 0, an adopted re-attempt bumps it).
    v_dep_ok := true;
    for v_dep in select jsonb_array_elements_text(v_depends)
    loop
      if not exists (
        select 1 from public.sync_operations so
        where so.organization_id = v_org and so.device_id = p_device_id
          and so.local_operation_id = v_dep and so.status = 'applied'
      ) then
        v_dep_ok := false;
        exit;
      end if;
    end loop;

    if not v_dep_ok then
      update public.sync_operations as so
        set status = 'pending', last_error_code = 'dependency_not_ready', last_error_class = 'transient',
            retry_count = so.retry_count + (case when v_adopted then 1 else 0 end),
            updated_at = now()
        where so.id = v_so_id;
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
        'error', 'dependency_not_ready', 'retryable', true, 'status', 'pending', 'idempotency_replay', false);
      continue;
    end if;

    -- (b4) an ADOPTED stale re-attempt returns to in_flight with the retry
    -- bump (the pre-fix on-conflict contract); a fresh claim is already
    -- in_flight and is never re-written here.
    if v_adopted then
      update public.sync_operations as so
        set status = 'in_flight', retry_count = so.retry_count + 1, updated_at = now()
        where so.id = v_so_id;
    end if;

    -- (b5) dispatch to the matching business RPC inside a per-op EXCEPTION subtransaction.
    begin
      case v_op_type
        when 'shift.open' then
          v_dispatch := app.open_shift(
            p_pin_session_id,
            (v_payload ->> 'shift_id')::uuid,
            (v_payload ->> 'cash_drawer_session_id')::uuid,
            p_device_id,
            v_local_op,
            (v_payload ->> 'opening_float_minor')::bigint);
        when 'order.submit' then
          v_dispatch := app.submit_order(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'order_type',
            nullif(v_payload ->> 'table_id', '')::uuid,
            nullif(v_payload ->> 'shift_id', '')::uuid,
            v_payload ->> 'currency_code',
            v_payload ->> 'notes',
            v_payload -> 'order_items',
            (v_payload ->> 'subtotal_minor')::bigint,
            (v_payload ->> 'discount_total_minor')::bigint,
            (v_payload ->> 'tax_total_minor')::bigint,
            (v_payload ->> 'grand_total_minor')::bigint,
            v_client_ts);
          -- ORDER-CUSTOMER-001: stamp the OPTIONAL customer display name on the
          -- order app.submit_order just created. Kept OUT of submit_order so its
          -- validated INSERT stays byte-unchanged. Money-free display text: trim
          -- + empty->null + 80-char cap. Tenant-scoped by v_org; the
          -- `customer_name is null` guard makes it idempotent (a replay returns
          -- the same order_id, already stamped) and never overwrites.
          v_customer_name := left(btrim(coalesce(v_payload ->> 'customer_name', '')), 80);
          if v_customer_name <> '' then
            update public.orders
              set customer_name = v_customer_name
              where id = (v_dispatch ->> 'order_id')::uuid
                and organization_id = v_org
                and customer_name is null;
          end if;
          -- KITCHEN-MODE-001C1-CORRECTION-001: the initial kitchen dispatch
          -- payload is built inside app.submit_order BEFORE this stamp, so on
          -- the REAL push path customer_display_name was missing. Rebuild the
          -- COMPLETE normalized payload through the trusted internal server
          -- builder IN THIS SAME TRANSACTION — never by patching client JSON
          -- in, never after a client could have seen it (claimed / completed
          -- / superseded rows are left untouched; inside this first-apply
          -- transaction the row is not yet visible to any puller), never
          -- duplicating the dispatch or its audit row (no INSERT, no audit
          -- here). The row only exists for printer_only branches, so kds
          -- branches are a structural no-op; the guard trigger re-proves the
          -- rebuilt payload money-free on UPDATE.
          if v_customer_name <> '' then
            update public.kitchen_print_dispatches kd
              set money_free_payload = app.kitchen_dispatch_payload_initial(v_org, (v_dispatch ->> 'order_id')::uuid),
                  updated_at = now()
              where kd.organization_id = v_org
                and kd.order_id = (v_dispatch ->> 'order_id')::uuid
                and kd.dispatch_type = 'initial_order'
                and kd.claimed_at is null
                and kd.completed_at is null
                and kd.superseded_by_dispatch_id is null;
          end if;
        when 'order.discount' then
          v_dispatch := app.apply_discount(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'scope',
            nullif(v_payload ->> 'order_item_id', '')::uuid,
            v_payload ->> 'discount_type',
            (v_payload ->> 'value')::bigint,
            v_payload ->> 'reason',
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'payment.create' then
          v_dispatch := app.record_payment(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'tender_type',
            (v_payload ->> 'amount_tendered_minor')::bigint,
            nullif(v_payload ->> 'provisional_receipt_number', ''),
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'shift.close' then
          v_dispatch := app.close_shift(
            p_pin_session_id,
            (v_payload ->> 'shift_id')::uuid,
            p_device_id,
            v_local_op,
            (v_payload ->> 'counted_amount_minor')::bigint,
            nullif(v_payload ->> 'reason', ''),
            nullif(v_payload ->> 'expected_revision', '')::integer);
        -- MVP addition: KDS/POS order-status updates ride the SAME outbox/ledger
        -- (D-010/D-022). Scope/actor come from the pin session + device passed
        -- through (A8); the payload contributes ONLY {order_id, new_status}.
        when 'order.status' then
          v_dispatch := app.update_order_status(
            p_pin_session_id,
            p_device_id,
            (v_payload ->> 'order_id')::uuid,
            v_payload ->> 'new_status',
            v_local_op);
        when 'order.void' then
          -- MONEY-VOID-001: role-gated void of a wrong UNPAID order. Mirrors the
          -- order.discount branch - actor/org/branch come from the PIN session
          -- (never the payload) and the op's local_operation_id threads
          -- app.void_order's own idempotency (D-022). app.void_order (RF-053,
          -- hardened by RF-062) enforces manager/restaurant_owner/org_owner (or a
          -- cashier with permissions.void_order='true'), a mandatory reason, legal
          -- source states (submitted/accepted/preparing/ready/served), and the
          -- completed-payment block (an order with a live completed payment
          -- returns permission_denied) - so paid orders are refused server-side.
          -- Money-free: it only sets orders.status='voided' + void_reason +
          -- revision and cascades items -> voided; no payment/total is touched.
          v_dispatch := app.void_order(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'reason',
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'order.table_move' then
          -- RESTAURANT-OPERATIONS-V1-001: atomic dine-in table move. Mirrors the
          -- order.void branch — actor/org/branch come from the PIN session
          -- (never the payload); the op's local_operation_id threads
          -- app.move_order_table's ORDER-BOUND idempotency (D-022); the payload
          -- contributes ONLY {order_id, table_id[, expected_revision]}. Typed
          -- refusals (table_not_allowed / invalid_transition+order_not_movable /
          -- table_not_available / permission_denied) RETURN through verbatim;
          -- a revision conflict raises 40001 -> the per-op 'conflict' status.
          -- Money-free: only orders.table_id + revision move.
          v_dispatch := app.move_order_table(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            nullif(v_payload ->> 'table_id', '')::uuid,
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'menu.availability_set' then
          -- PILOT-OPERATIONS-CORRECTIONS-001: a cashier (default-ON
          -- manage_menu_availability) or manager+ sets a menu item's per-branch
          -- availability from the POS. Actor/org/branch derive from the PIN
          -- session (NEVER the payload); the capability is enforced inside. The
          -- payload contributes ONLY {menu_item_id, availability, reason}. The
          -- setter is naturally idempotent (no-change re-applies the same state
          -- with no audit) and transport dedup (sync_operations) guards replay.
          -- Typed RETURN refusals (permission_denied / not_found) survive
          -- verbatim. MONEY-FREE.
          v_dispatch := app.pos_set_item_availability(
            p_pin_session_id,
            p_device_id,
            (v_payload ->> 'menu_item_id')::uuid,
            v_payload ->> 'availability',
            nullif(v_payload ->> 'reason', ''));
        when 'table.status_set' then
          -- PILOT-OPERATIONS-CORRECTIONS-001: manual table floor-state from the
          -- POS (manage_table_operations). Scope/actor from the session; payload
          -- {table_id, status}. Typed refusals survive verbatim. MONEY-FREE.
          v_dispatch := app.pos_set_table_status(
            p_pin_session_id, p_device_id,
            (v_payload ->> 'table_id')::uuid,
            v_payload ->> 'status');
        when 'table.link' then
          -- Link two same-branch tables into an operational group (no order/bill
          -- merge). Payload {table_id_a, table_id_b}. Deterministic lock order.
          v_dispatch := app.pos_link_tables(
            p_pin_session_id, p_device_id,
            (v_payload ->> 'table_id_a')::uuid,
            (v_payload ->> 'table_id_b')::uuid);
        when 'table.unlink' then
          -- Dissolve the group a table belongs to (orders untouched). Payload
          -- {table_id}.
          v_dispatch := app.pos_unlink_tables(
            p_pin_session_id, p_device_id,
            (v_payload ->> 'table_id')::uuid);
        when 'order.void_ack' then
          -- PSC-001D: the kitchen's cancellation acknowledgement. Mirrors the
          -- order.status branch — actor/org/branch come from the PIN session
          -- (never the payload); the payload contributes ONLY {order_id}.
          -- app.kitchen_ack_void enforces the KDS-class device, the kitchen
          -- role set, the voided + ack-required state, and the idempotent
          -- already-acknowledged replay; its flat typed refusals
          -- (invalid_device_type / permission_denied / order_not_voided /
          -- acknowledgement_not_required) RETURN through verbatim. TARGET-ID
          -- CONSISTENCY is enforced at (b1+) BEFORE the fingerprint and the
          -- terminal replay — by the time this arm runs, target_id and
          -- payload.order_id are guaranteed present, valid and equal. The
          -- check below is pure defence-in-depth and unreachable. MONEY-FREE.
          if v_target_id is null
             or v_target_id <> (v_payload ->> 'order_id')::uuid then
            raise exception 'sync_push: order.void_ack target_id does not match payload.order_id' using errcode = '42501';
          end if;
          v_dispatch := app.kitchen_ack_void(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op);
        when 'order.items_add' then
          -- PSC-001C: add items to an existing eligible dine-in order as ONE
          -- new authoritative service round. Actor/org/branch come from the
          -- PIN session; the payload contributes {order_id, order_items}.
          -- app.add_order_items enforces the POS-class device, the cashier+
          -- role set, eligibility (dine_in, open status, no completed
          -- payment), submit_order-parity pricing/sellability, and round-level
          -- idempotency; its flat typed refusals (invalid_device_type /
          -- permission_denied / order_not_dine_in / order_not_eligible /
          -- order_already_settled / item_unavailable / invalid_item_payload)
          -- RETURN through verbatim. TARGET-ID CONSISTENCY is enforced at
          -- (b1+) BEFORE the fingerprint and the terminal replay — the check
          -- below is pure defence-in-depth and unreachable.
          if v_target_id is null
             or v_target_id <> (v_payload ->> 'order_id')::uuid then
            raise exception 'sync_push: order.items_add target_id does not match payload.order_id' using errcode = '42501';
          end if;
          v_dispatch := app.add_order_items(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload -> 'order_items',
            v_client_ts);
        when 'order.round_status' then
          -- PSC-001C: the additional service round's own single-step
          -- lifecycle. Actor/org/branch come from the PIN session; the
          -- payload contributes {round_id, new_status}. app.update_round_status
          -- enforces the LOCKED device/role matrix (production steps KDS-only;
          -- ready->served KDS kitchen set or POS cashier set), the parent
          -- guards, single-step legality, the WRITE-ONCE ready_at stamp and
          -- the completion chain; its flat typed refusals RETURN through
          -- verbatim. TARGET-ID CONSISTENCY (against payload.round_id) is
          -- enforced at (b1+) — the check below is pure defence-in-depth and
          -- unreachable. MONEY-FREE.
          if v_target_id is null
             or v_target_id <> (v_payload ->> 'round_id')::uuid then
            raise exception 'sync_push: order.round_status target_id does not match payload.round_id' using errcode = '42501';
          end if;
          v_dispatch := app.update_round_status(
            p_pin_session_id,
            (v_payload ->> 'round_id')::uuid,
            p_device_id,
            v_payload ->> 'new_status',
            v_local_op);
      end case;
      v_dispatch_ok := coalesce((v_dispatch ->> 'ok')::boolean, false);
    exception
      when others then
        v_caught_state := SQLSTATE;
        v_caught_msg   := SQLERRM;
    end;

    -- (b6) finalize the operation outcome
    if v_caught_state is not null then
      if v_caught_state = '40001' then
        update public.sync_operations
          set status = 'conflict', last_error_code = v_caught_state, last_error_class = 'conflict',
              conflict_info = jsonb_build_object('sqlstate', v_caught_state, 'message', v_caught_msg),
              result = jsonb_build_object('ok', false, 'error', 'conflict', 'sqlstate', v_caught_state), updated_at = now()
          where id = v_so_id;
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_conflict', v_caught_msg, null,
                jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'sqlstate', v_caught_state));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'conflict', 'sqlstate', v_caught_state, 'status', 'conflict', 'idempotency_replay', false);
      else
        -- validation / state / business-rule failure -> permanent rejected. RF-061: a
        -- revoked-MEMBERSHIP op fails membership-active in the dispatched RPC; classify its
        -- rejection reason as 'revoked_employee' so the offline-revoked-employee case is clear.
        update public.sync_operations
          set status = 'rejected', last_error_code = v_caught_state, last_error_class = 'permanent',
              rejection_reason = case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee' else v_caught_msg end,
              result = jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', v_caught_state,
                         'detail', case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee' else null end), updated_at = now()
          where id = v_so_id;
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected',
                case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee' else v_caught_msg end, null,
                jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'sqlstate', v_caught_state));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'rejected', 'sqlstate', v_caught_state,
          'detail', case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee' else null end,
          'status', 'rejected', 'idempotency_replay', false);
      end if;
    elsif v_dispatch_ok then
      update public.sync_operations
        set status = 'applied', result = v_dispatch, applied_at = now(),
            target_id = coalesce(v_target_id, nullif(v_dispatch ->> 'order_id', '')::uuid, nullif(v_dispatch ->> 'shift_id', '')::uuid, nullif(v_dispatch ->> 'payment_id', '')::uuid),
            updated_at = now()
        where id = v_so_id;
      v_results := v_results || (v_dispatch
        || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', 'applied', 'idempotency_replay', false));
    else
      update public.sync_operations
        set status = 'rejected', last_error_code = coalesce(v_dispatch ->> 'error', 'rejected'), last_error_class = 'permanent',
            rejection_reason = coalesce(v_dispatch ->> 'error', 'rejected'), result = v_dispatch, updated_at = now()
        where id = v_so_id;
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected', coalesce(v_dispatch ->> 'error', 'rejected'), null,
              jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'error', coalesce(v_dispatch ->> 'error', 'rejected')));
      v_results := v_results || (v_dispatch
        || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', 'rejected', 'idempotency_replay', false));
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'results', v_results, 'server_ts', now());
end;
$$;

comment on function app.sync_push(uuid, uuid, jsonb) is
  'RF-056/RF-061 + ... + PSC-001D + PSC-001C (D-010/D-022) SECURITY DEFINER batch push — faithful re-creation of the 20260722090000 body; all 15 canonical operations, identity hardening, atomic ledger claim, batch cap, result ordering, dependency guard, per-op subtransactions, finalization and the customer_name stamp are verbatim. KITCHEN-MODE-001C1-CORRECTION-001 (order.submit only): immediately after the customer_name stamp, the order''s still-unclaimed initial kitchen dispatch payload is REBUILT through app.kitchen_dispatch_payload_initial in the SAME transaction, so the REAL push path carries customer_display_name exactly like the direct-call path; kds branches are a structural no-op and claimed/completed/superseded dispatches are never touched. Authorization INGEST-TIME; scope from the session, never the payload.';

-- ACL parity (CREATE OR REPLACE preserves grants; re-issued explicitly).
revoke all on function app.sync_push(uuid, uuid, jsonb) from public;
revoke all on function app.sync_push(uuid, uuid, jsonb) from anon;
grant execute on function app.sync_push(uuid, uuid, jsonb) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   re-create app.audit_safe_detail / app.audit_action_has_detail /
--     app.audit_category from 20260724090000 (trio),
--     app.sync_push from 20260722090000,
--     app.void_order from 20260722090000,
--     app.add_order_items from 20260722090000,
--     app.submit_order from 20260723090000;
--   drop function if exists public.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid);
--   drop function if exists app.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid);
--   drop function if exists public.acknowledge_kitchen_print_dispatch(uuid, text, uuid, text, text);
--   drop function if exists app.acknowledge_kitchen_print_dispatch(uuid, text, uuid, text, text);
--   drop function if exists public.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid, integer);
--   drop function if exists app.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid, integer);
--   drop function if exists public.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer);
--   drop function if exists app.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer);
--   drop function if exists app.create_kitchen_dispatch(uuid, uuid, uuid, uuid, uuid, text, jsonb, uuid, uuid, uuid);
--   drop function if exists app.kitchen_dispatch_payload_void(uuid, uuid, text);
--   drop function if exists app.kitchen_dispatch_payload_round(uuid, uuid, uuid);
--   drop function if exists app.kitchen_dispatch_payload_initial(uuid, uuid);
--   drop function if exists app.kitchen_prep_projection(jsonb);
--   drop trigger if exists kitchen_print_dispatches_guard_trg on public.kitchen_print_dispatches;
--   drop function if exists app.kitchen_print_dispatches_guard();
--   drop function if exists app.kitchen_payload_offending_key(jsonb);
--   drop function if exists app.kitchen_payload_normalize_key(text);
--   drop table if exists public.kitchen_print_dispatches;
--   drop table if exists public.kitchen_printer_readiness_reports;
--   alter table public.orders drop constraint if exists orders_org_rest_branch_id_key;
--   alter table public.branches drop column if exists kitchen_workflow_mode_revision;
-- ============================================================================
