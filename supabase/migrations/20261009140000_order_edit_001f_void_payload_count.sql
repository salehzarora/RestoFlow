-- ============================================================================
-- ORDER-EDIT-001F — the VOID slip's line count after an order edit
-- (API_CONTRACT §4.45.10; ORDER_EDIT_DESIGN §7.3; DECISION D-043).
--
-- app.kitchen_dispatch_payload_void (live 20260725090000, KITCHEN-MODE-001C1;
-- never re-emitted since) counts EVERY non-deleted order_items row of the
-- order as `affected_item_count`. ORDER-EDIT-001A retires an edited line by
-- VOIDING it in place (removed_by_edit_id set) and writes its replacement /
-- remainder as a NEW row, so after a paper edit the VOID slip over-counts:
-- each retired row is counted next to the row that replaced it.
--
-- The body is copied mechanically from its LIVE definition; the ONLY change is
-- one predicate in the affected_item_count subquery:
--
--     and oi.removed_by_edit_id is null
--
-- An edit-retired row is excluded; every other row (live lines, and lines
-- voided or cancelled by anything other than an edit) counts exactly as
-- before, so an order that was never edited gets a byte-identical payload.
-- A status filter would be wrong: app.void_order voids the live lines BEFORE
-- it builds this payload (20261008170200_order_edit_001a_reemits.sql).
--
-- Signature, LANGUAGE sql, STABLE, SECURITY INVOKER, search_path '' and the
-- ACLs are unchanged (CREATE OR REPLACE; ACLs re-stated). The COMMENT gains
-- one provenance sentence. Money-free (D-007, T-003): no column is added and
-- no money column is read. No public wrapper; no grant; no audit; no write.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- app.kitchen_dispatch_payload_void — edit-retired rows leave the line count.
-- ----------------------------------------------------------------------------
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
        and oi.order_id = o.id and oi.deleted_at is null
        and oi.removed_by_edit_id is null)))
  from public.orders o
  left join public.tables tbl
    on tbl.organization_id = o.organization_id and tbl.id = o.table_id
  where o.organization_id = p_organization_id and o.id = p_order_id;
$$;
do $do$
begin
  execute format('comment on function app.kitchen_dispatch_payload_void(uuid, uuid, text) is %L',
    obj_description('app.kitchen_dispatch_payload_void(uuid, uuid, text)'::regprocedure, 'pg_proc')
    || ' ORDER-EDIT-001F: affected_item_count excludes the lines an order edit retired (removed_by_edit_id IS NOT NULL), so each line counts once after an edit; an order never edited is unchanged.');
end;
$do$;

revoke all on function app.kitchen_dispatch_payload_void(uuid, uuid, text) from public;
revoke all on function app.kitchen_dispatch_payload_void(uuid, uuid, text) from anon;
revoke all on function app.kitchen_dispatch_payload_void(uuid, uuid, text) from authenticated;

-- ----------------------------------------------------------------------------
-- The re-emit never broadens either global public surface (D-037). These
-- assertions match ORDER-EDIT-001A / 001B and pending #288 in either apply
-- order.
-- ----------------------------------------------------------------------------
do $$
declare
  v_anon_set text;
  v_defs text;
begin
  select coalesce(string_agg(regexp_replace(p.oid::regprocedure::text, '^public\.', ''), ', '
    order by regexp_replace(p.oid::regprocedure::text, '^public\.', '')), '')
    into v_anon_set from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
      and has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_anon_set <> 'storefront_menu(text)' then
    raise exception 'ORDER-EDIT-001F: unexpected anon public surface [%]', v_anon_set;
  end if;
  select coalesce(string_agg(regexp_replace(p.oid::regprocedure::text, '^public\.', ''), ', '
    order by regexp_replace(p.oid::regprocedure::text, '^public\.', '')), '')
    into v_defs from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') and p.prosecdef;
  if v_defs <> 'storefront_menu(text)' then
    raise exception 'ORDER-EDIT-001F: unexpected public DEFINER surface [%]', v_defs;
  end if;
  if has_schema_privilege('anon', 'app', 'USAGE') then
    raise exception 'ORDER-EDIT-001F: anon has app schema usage';
  end if;
end;
$$;
