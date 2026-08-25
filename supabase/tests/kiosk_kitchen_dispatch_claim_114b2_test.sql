-- ============================================================================
-- KIOSK-PRINT-114B.1 — pgTAP: kiosk kitchen dispatch OWNERSHIP (migration 2).
--
-- The kiosk may ask its OWN submit to create the printer_only kitchen
-- dispatch ALREADY CLAIMED by the submitting device (p_claim_kitchen_dispatch,
-- default false — byte-compatible when absent). Contract:
--   * claim-at-submit is atomic (the row is born claimed; no race window);
--   * the submit response carries {kitchen_dispatch: {id, money_free_payload,
--     claim_expires_at}} ONLY when claimed; the stored envelope replays it;
--   * POS pull skips a LIVE kiosk-held lease and recovers it after expiry
--     through the EXISTING lease rules (no manual release RPC);
--   * kiosk acks only its OWN claim, only {transport_accepted,
--     failed_retryable, possibly_printed}; failed_retryable KEEPS the lease;
--     possibly_printed keeps the permanent sticky hold; POS ack unchanged;
--   * a kds-mode branch never claims and never returns a dispatch;
--   * get_device_printer_assignments: kiosk gains kitchen purposes ONLY on a
--     printer_only branch; kds-branch kiosk and POS/KDS answers unchanged.
-- Fixtures inserted as the BYPASSRLS harness role; RPC authority is the
-- device token parameter.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(26);

-- ===== fixture: printer_only branch P + kds branch K; kiosk/POS devices =====
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-b214-0000000000a0', 'B214 Org', 'b214-claim', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-b214-0000000000a1', '00000000-0000-0000-b214-0000000000a0', 'B214 Rest');
insert into branches (id, organization_id, restaurant_id, name, kitchen_workflow_mode, kitchen_workflow_mode_revision) values
  ('00000000-0000-0000-b214-0000000000aa', '00000000-0000-0000-b214-0000000000a0', '00000000-0000-0000-b214-0000000000a1', 'B214 P', 'printer_only', 1),
  ('00000000-0000-0000-b214-0000000000ab', '00000000-0000-0000-b214-0000000000a0', '00000000-0000-0000-b214-0000000000a1', 'B214 K', 'kds', 1);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('00000000-0000-0000-b214-0000000d1001', '00000000-0000-0000-b214-0000000000a0', '00000000-0000-0000-b214-0000000000a1', '00000000-0000-0000-b214-0000000000aa', 'kiosk', 'B214 Kiosk P'),
  ('00000000-0000-0000-b214-0000000d1002', '00000000-0000-0000-b214-0000000000a0', '00000000-0000-0000-b214-0000000000a1', '00000000-0000-0000-b214-0000000000aa', 'kiosk', 'B214 Kiosk P2'),
  ('00000000-0000-0000-b214-0000000d1003', '00000000-0000-0000-b214-0000000000a0', '00000000-0000-0000-b214-0000000000a1', '00000000-0000-0000-b214-0000000000ab', 'kiosk', 'B214 Kiosk K'),
  ('00000000-0000-0000-b214-0000000d1004', '00000000-0000-0000-b214-0000000000a0', '00000000-0000-0000-b214-0000000000a1', '00000000-0000-0000-b214-0000000000aa', 'pos',   'B214 POS');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-b214-0000000d2001', '00000000-0000-0000-b214-0000000000a0', '00000000-0000-0000-b214-0000000000a1', '00000000-0000-0000-b214-0000000000aa', '00000000-0000-0000-b214-0000000d1001', 'active'),
  ('00000000-0000-0000-b214-0000000d2002', '00000000-0000-0000-b214-0000000000a0', '00000000-0000-0000-b214-0000000000a1', '00000000-0000-0000-b214-0000000000aa', '00000000-0000-0000-b214-0000000d1002', 'active'),
  ('00000000-0000-0000-b214-0000000d2003', '00000000-0000-0000-b214-0000000000a0', '00000000-0000-0000-b214-0000000000a1', '00000000-0000-0000-b214-0000000000ab', '00000000-0000-0000-b214-0000000d1003', 'active'),
  ('00000000-0000-0000-b214-0000000d2004', '00000000-0000-0000-b214-0000000000a0', '00000000-0000-0000-b214-0000000000a1', '00000000-0000-0000-b214-0000000000aa', '00000000-0000-0000-b214-0000000d1004', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, expires_at) values
  ('00000000-0000-0000-b214-0000000d3001', '00000000-0000-0000-b214-0000000000a0', '00000000-0000-0000-b214-0000000000a1', '00000000-0000-0000-b214-0000000000aa', '00000000-0000-0000-b214-0000000d1001', '00000000-0000-0000-b214-0000000d2001', app.hash_provisioning_secret('tok-b214-kiosk-p'),  true, now() + interval '1 day'),
  ('00000000-0000-0000-b214-0000000d3002', '00000000-0000-0000-b214-0000000000a0', '00000000-0000-0000-b214-0000000000a1', '00000000-0000-0000-b214-0000000000aa', '00000000-0000-0000-b214-0000000d1002', '00000000-0000-0000-b214-0000000d2002', app.hash_provisioning_secret('tok-b214-kiosk-p2'), true, now() + interval '1 day'),
  ('00000000-0000-0000-b214-0000000d3003', '00000000-0000-0000-b214-0000000000a0', '00000000-0000-0000-b214-0000000000a1', '00000000-0000-0000-b214-0000000000ab', '00000000-0000-0000-b214-0000000d1003', '00000000-0000-0000-b214-0000000d2003', app.hash_provisioning_secret('tok-b214-kiosk-k'),  true, now() + interval '1 day'),
  ('00000000-0000-0000-b214-0000000d3004', '00000000-0000-0000-b214-0000000000a0', '00000000-0000-0000-b214-0000000000a1', '00000000-0000-0000-b214-0000000000aa', '00000000-0000-0000-b214-0000000d1004', '00000000-0000-0000-b214-0000000d2004', app.hash_provisioning_secret('tok-b214-pos'),      true, now() + interval '1 day');

-- menu: one Cola (no groups) on the shared restaurant.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order, is_active) values
  ('00000000-0000-0000-b214-0000000c1000', '00000000-0000-0000-b214-0000000000a0', '00000000-0000-0000-b214-0000000000a1', null, 'B214 Cat', 0, true);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order, is_active) values
  ('00000000-0000-0000-b214-000000110001', '00000000-0000-0000-b214-0000000000a0', '00000000-0000-0000-b214-0000000000a1', null, '00000000-0000-0000-b214-0000000c1000', 'B214 Cola', 1000, 'ILS', 0, true);

-- printers: branch P has a dedicated kitchen (80mm network, the POS readiness
-- anchor), a 'both' and a receipt; branch K has a kitchen printer that must
-- stay INVISIBLE to the kds-branch kiosk.
insert into printer_devices (id, organization_id, restaurant_id, branch_id, display_name, connection_type, role, paper_width, is_enabled) values
  ('00000000-0000-0000-b214-0000000e0001', '00000000-0000-0000-b214-0000000000a0', '00000000-0000-0000-b214-0000000000a1', '00000000-0000-0000-b214-0000000000aa', 'B214 Kitchen P', 'network', 'kitchen', '80mm', true),
  ('00000000-0000-0000-b214-0000000e0002', '00000000-0000-0000-b214-0000000000a0', '00000000-0000-0000-b214-0000000000a1', '00000000-0000-0000-b214-0000000000aa', 'B214 Both P',    'network', 'both',    '80mm', true),
  ('00000000-0000-0000-b214-0000000e0003', '00000000-0000-0000-b214-0000000000a0', '00000000-0000-0000-b214-0000000000a1', '00000000-0000-0000-b214-0000000000aa', 'B214 Receipt P', 'network', 'receipt', '80mm', true),
  ('00000000-0000-0000-b214-0000000e0004', '00000000-0000-0000-b214-0000000000a0', '00000000-0000-0000-b214-0000000000a1', '00000000-0000-0000-b214-0000000000ab', 'B214 Kitchen K', 'network', 'kitchen', '80mm', true);

-- a QUALIFYING fresh readiness report for the POS (pull gate).
insert into kitchen_printer_readiness_reports (
  organization_id, restaurant_id, branch_id, device_id, capability, app_build,
  printer_purpose, transport_kind, paper_width, printer_fingerprint,
  secure_spool_available, unresolved_local_jobs, mode_revision,
  printer_assignment_id, reported_at, expires_at) values
  ('00000000-0000-0000-b214-0000000000a0', '00000000-0000-0000-b214-0000000000a1', '00000000-0000-0000-b214-0000000000aa', '00000000-0000-0000-b214-0000000d1004',
   'kitchen_printer_only_v1', 'b214-test', 'kitchen_ticket', 'network', '80mm',
   'abcdef0123456789', true, 0, 1,
   '00000000-0000-0000-b214-0000000e0001', now(), now() + interval '10 minutes');

-- helpers ---------------------------------------------------------------------
create function pg_temp.csub(p_device uuid, p_tok text, p_order uuid, p_op text, p_claim boolean)
returns jsonb language sql as $$
  select public.kiosk_submit_order(
    p_device, p_tok, p_order, p_op, 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object(
      'menu_item_id', '00000000-0000-0000-b214-000000110001',
      'menu_item_name_snapshot', 'B214 Cola', 'quantity', 1,
      'unit_price_minor_snapshot', 1000)),
    1000, 0, 0, 1000, null, p_claim);
$$;
create function pg_temp.kack(p_device uuid, p_tok text, p_dispatch uuid, p_status text)
returns jsonb language sql as $$
  select public.acknowledge_kitchen_print_dispatch(p_device, p_tok, p_dispatch, p_status);
$$;
create function pg_temp.ppull()
returns jsonb language sql as $$
  select public.pull_kitchen_print_dispatches(
    '00000000-0000-0000-b214-0000000d1004', 'tok-b214-pos', 20);
$$;
create function pg_temp.dof(p_order uuid)
returns uuid language sql as $$
  select d.id from kitchen_print_dispatches d where d.order_id = p_order;
$$;

create temp table _r (label text primary key, r jsonb);

-- ============================================================================
-- C1-C4: claim-at-submit — atomic, leased, returned in the envelope.
-- ============================================================================
insert into _r values ('o1', pg_temp.csub('00000000-0000-0000-b214-0000000d1001', 'tok-b214-kiosk-p',
  '00000000-0000-0000-b214-00000aade001', 'b214-01', true));
select ok((select (r ->> 'ok')::boolean from _r where label = 'o1'),
  'C1: submit with p_claim_kitchen_dispatch=true is accepted');
select ok((select (r -> 'kitchen_dispatch' ->> 'id') is not null
              and (r -> 'kitchen_dispatch' -> 'money_free_payload') ? 'items'
              and (r -> 'kitchen_dispatch' ->> 'claim_expires_at') is not null
             from _r where label = 'o1'),
  'C2: the response carries the claimed dispatch (id + money_free_payload + lease)');
select ok((select d.claimed_by_device_id = '00000000-0000-0000-b214-0000000d1001'
              and d.claimed_at is not null and d.completed_at is null
              and d.claim_expires_at > now()
             from kitchen_print_dispatches d
             where d.order_id = '00000000-0000-0000-b214-00000aade001'),
  'C3: the dispatch row is BORN claimed by the submitting kiosk device');
select ok((select d.claim_expires_at between now() + interval '9 minutes'
                                         and now() + interval '11 minutes'
             from kitchen_print_dispatches d
             where d.order_id = '00000000-0000-0000-b214-00000aade001'),
  'C4: the lease uses the existing 10-minute convention');

-- ============================================================================
-- C5-C8: claim=false stays byte-compatible; POS pull skips the live lease.
-- ============================================================================
-- 16-arg call (no claim argument at all) — the backward-compat proof.
insert into _r values ('o2', (select public.kiosk_submit_order(
  '00000000-0000-0000-b214-0000000d1001', 'tok-b214-kiosk-p',
  '00000000-0000-0000-b214-00000aade002', 'b214-02', 'takeaway', null, 'ILS', null, null, null,
  jsonb_build_array(jsonb_build_object(
    'menu_item_id', '00000000-0000-0000-b214-000000110001',
    'menu_item_name_snapshot', 'B214 Cola', 'quantity', 1,
    'unit_price_minor_snapshot', 1000)),
  1000, 0, 0, 1000)));
select ok((select (r ->> 'ok')::boolean and not (r ? 'kitchen_dispatch')
             from _r where label = 'o2'),
  'C5: the 16-arg call still works and returns NO kitchen_dispatch (compat)');
select ok((select d.claimed_at is null
             from kitchen_print_dispatches d
             where d.order_id = '00000000-0000-0000-b214-00000aade002'),
  'C6: without the claim the dispatch is born UNCLAIMED (today''s behavior)');
insert into _r values ('pull1', pg_temp.ppull());
select ok((select (r -> 'dispatches')::text like '%00000aade002%'
              and (r -> 'dispatches')::text not like '%00000aade001%'
             from _r where label = 'pull1'),
  'C7: POS pull serves the unclaimed dispatch and SKIPS the live kiosk lease');
select ok((select d.claimed_by_device_id = '00000000-0000-0000-b214-0000000d1004'
             from kitchen_print_dispatches d
             where d.order_id = '00000000-0000-0000-b214-00000aade002'),
  'C8: the pull claimed the unclaimed row for the POS (existing semantics)');

-- ============================================================================
-- C9-C15: kiosk acknowledgement — owner-only, narrowed vocabulary, honest
-- lease behavior; POS ack unchanged.
-- ============================================================================
select ok((select ((pg_temp.kack('00000000-0000-0000-b214-0000000d1001', 'tok-b214-kiosk-p',
    pg_temp.dof('00000000-0000-0000-b214-00000aade001'), 'failed_retryable')) ->> 'ok')::boolean),
  'C9: the claim OWNER kiosk may ack failed_retryable');
select ok((select d.claimed_by_device_id = '00000000-0000-0000-b214-0000000d1001'
              and d.last_client_status = 'failed_retryable'
              and d.claim_expires_at is not null and d.completed_at is null
             from kitchen_print_dispatches d
             where d.order_id = '00000000-0000-0000-b214-00000aade001'),
  'C10: failed_retryable KEEPS the kiosk lease (no immediate duplicate race; '
  'POS fallback only through natural expiry)');
select is((pg_temp.kack('00000000-0000-0000-b214-0000000d1002', 'tok-b214-kiosk-p2',
    pg_temp.dof('00000000-0000-0000-b214-00000aade001'), 'transport_accepted')) ->> 'error',
  'not_claim_owner', 'C11: a FOREIGN kiosk device cannot ack the claim');
select is((pg_temp.kack('00000000-0000-0000-b214-0000000d1001', 'tok-b214-kiosk-p',
    pg_temp.dof('00000000-0000-0000-b214-00000aade001'), 'imported')) ->> 'error',
  'invalid_status', 'C12: the kiosk vocabulary excludes imported (POS-only status)');
select is((pg_temp.kack('00000000-0000-0000-b214-0000000d1003', 'tok-b214-kiosk-k',
    pg_temp.dof('00000000-0000-0000-b214-00000aade001'), 'transport_accepted')) ->> 'error',
  'not_found', 'C13: a kiosk on ANOTHER branch cannot even see the dispatch (scope)');
insert into _r values ('ackt', pg_temp.kack('00000000-0000-0000-b214-0000000d1001', 'tok-b214-kiosk-p',
  pg_temp.dof('00000000-0000-0000-b214-00000aade001'), 'transport_accepted'));
select ok((select (r ->> 'ok')::boolean and (r ->> 'completed')::boolean from _r where label = 'ackt'),
  'C14: the owner kiosk completes its dispatch with transport_accepted');
select ok((select ((pg_temp.kack('00000000-0000-0000-b214-0000000d1001', 'tok-b214-kiosk-p',
    pg_temp.dof('00000000-0000-0000-b214-00000aade001'), 'transport_accepted')) ->> 'idempotency_replay')::boolean),
  'C15: the completion ack replays idempotently');

-- POS ack path regression: the POS completes ITS claimed dispatch as before.
select ok((select ((pg_temp.kack('00000000-0000-0000-b214-0000000d1004', 'tok-b214-pos',
    pg_temp.dof('00000000-0000-0000-b214-00000aade002'), 'transport_accepted')) ->> 'ok')::boolean),
  'C16: the POS acknowledgement path is unchanged');

-- ============================================================================
-- C17-C19: possibly_printed keeps the permanent sticky hold.
-- ============================================================================
select pg_temp.csub('00000000-0000-0000-b214-0000000d1001', 'tok-b214-kiosk-p',
  '00000000-0000-0000-b214-00000aade003', 'b214-03', true);
select ok((select ((pg_temp.kack('00000000-0000-0000-b214-0000000d1001', 'tok-b214-kiosk-p',
    pg_temp.dof('00000000-0000-0000-b214-00000aade003'), 'possibly_printed')) ->> 'ok')::boolean),
  'C17: the owner kiosk may record possibly_printed');
select ok((select d.claim_expires_at is null and d.completed_at is null
             from kitchen_print_dispatches d
             where d.order_id = '00000000-0000-0000-b214-00000aade003'),
  'C18: possibly_printed takes the PERMANENT no-lease hold (never auto-re-served)');
select is((pg_temp.kack('00000000-0000-0000-b214-0000000d1001', 'tok-b214-kiosk-p',
    pg_temp.dof('00000000-0000-0000-b214-00000aade003'), 'transport_accepted')) ->> 'error',
  'ambiguous_print_hold', 'C19: the sticky-hold contract is unchanged for the kiosk owner');

-- ============================================================================
-- C20-C22: lease expiry hands a failed kiosk dispatch to the EXISTING POS
-- recovery path — no manual release RPC.
-- ============================================================================
select pg_temp.csub('00000000-0000-0000-b214-0000000d1001', 'tok-b214-kiosk-p',
  '00000000-0000-0000-b214-00000aade005', 'b214-05', true);
select pg_temp.kack('00000000-0000-0000-b214-0000000d1001', 'tok-b214-kiosk-p',
  pg_temp.dof('00000000-0000-0000-b214-00000aade005'), 'failed_retryable');
-- the kiosk crashed / stayed broken: the lease lapses (harness time travel).
update kitchen_print_dispatches
  set claim_expires_at = now() - interval '1 minute'
  where order_id = '00000000-0000-0000-b214-00000aade005';
insert into _r values ('pull2', pg_temp.ppull());
select ok((select (r -> 'dispatches')::text like '%00000aade005%'
              and (r -> 'dispatches')::text not like '%00000aade003%'
             from _r where label = 'pull2'),
  'C20: after expiry the POS pull recovers the failed kiosk dispatch — and '
  'STILL never serves the possibly_printed hold');
select ok((select d.claimed_by_device_id = '00000000-0000-0000-b214-0000000d1004'
              and d.claim_expires_at > now()
             from kitchen_print_dispatches d
             where d.order_id = '00000000-0000-0000-b214-00000aade005'),
  'C21: exactly one live claim owner — the recovery re-claimed it for the POS');
select is((pg_temp.kack('00000000-0000-0000-b214-0000000d1001', 'tok-b214-kiosk-p',
    pg_temp.dof('00000000-0000-0000-b214-00000aade005'), 'transport_accepted')) ->> 'error',
  'not_claim_owner', 'C22: the old kiosk owner lost ack authority with the claim');

-- ============================================================================
-- C23: a kds-mode branch never claims and never returns a dispatch.
-- ============================================================================
insert into _r values ('o4', pg_temp.csub('00000000-0000-0000-b214-0000000d1003', 'tok-b214-kiosk-k',
  '00000000-0000-0000-b214-00000aade004', 'b214-04', true));
select ok((select (r ->> 'ok')::boolean and not (r ? 'kitchen_dispatch') from _r where label = 'o4')
          and (select count(*) from kitchen_print_dispatches d
                 where d.order_id = '00000000-0000-0000-b214-00000aade004') = 0,
  'C23: on a kds branch the claim request is INERT — no dispatch, no claim, '
  'KDS governance untouched');

-- ============================================================================
-- C24: replay returns the STORED envelope including the claim (stable).
-- ============================================================================
insert into _r values ('replay', pg_temp.csub('00000000-0000-0000-b214-0000000d1001', 'tok-b214-kiosk-p',
  '00000000-0000-0000-b214-00000aade001', 'b214-01', true));
select ok((select (r ->> 'idempotency_replay')::boolean
              and (r -> 'kitchen_dispatch' ->> 'id') = pg_temp.dof('00000000-0000-0000-b214-00000aade001')::text
             from _r where label = 'replay')
          and (select count(*) from kitchen_print_dispatches d
                 where d.order_id = '00000000-0000-0000-b214-00000aade001') = 1,
  'C24: the idempotent replay returns the SAME stored claim envelope and '
  'creates no second dispatch/claim');

-- ============================================================================
-- C25-C26: printer assignments — kiosk kitchen purpose is printer_only-gated.
-- ============================================================================
insert into _r values ('asg-p', (select public.get_device_printer_assignments(
  '00000000-0000-0000-b214-0000000d1001', 'tok-b214-kiosk-p')));
select ok((select exists (
             select 1 from jsonb_array_elements(r -> 'printers') p
             where p ->> 'display_name' = 'B214 Kitchen P'
               and p -> 'supported_purposes' = '["kitchen_ticket"]'::jsonb)
           and exists (
             select 1 from jsonb_array_elements(r -> 'printers') p
             where p ->> 'display_name' = 'B214 Both P'
               and p -> 'supported_purposes' @> '["kitchen_ticket"]'::jsonb
               and p -> 'supported_purposes' @> '["customer_receipt"]'::jsonb)
             from _r where label = 'asg-p'),
  'C25: a printer_only-branch kiosk now sees kitchen printers and dual-purpose '
  'both-printers (the 114B widening)');
insert into _r values ('asg-k', (select public.get_device_printer_assignments(
  '00000000-0000-0000-b214-0000000d1003', 'tok-b214-kiosk-k')));
select ok((select not exists (
             select 1 from jsonb_array_elements(r -> 'printers') p
             where p ->> 'display_name' = 'B214 Kitchen K')
           and not exists (
             select 1 from jsonb_array_elements(r -> 'printers') p
             where p -> 'supported_purposes' @> '["kitchen_ticket"]'::jsonb)
             from _r where label = 'asg-k'),
  'C26: a kds-branch kiosk remains CUSTOMER-RECEIPT ONLY (no kitchen printer, '
  'no kitchen purpose — KDS governs paper there)');

select * from finish();
rollback;
