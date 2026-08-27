-- REPORT-123 — restore the owner-report family's ACL parity for the currency
-- breakdown. GRANT ONLY: no table DDL, no data, no function body is replaced.
--
-- WHAT BROKE. Every owner-report wrapper in `public` is SECURITY INVOKER: it
-- runs with the CALLER's privileges and delegates to a SECURITY DEFINER `app.*`
-- implementation. OPS-043 Phase 2 (20260818090000) shipped
-- `owner_report_currency_breakdown` with the wrapper granted to `authenticated`
-- but the inner `app.*` function only REVOKED from public/anon and never
-- granted to anyone. Its nine siblings -- owner_report_range, owner_top_items,
-- owner_sales_series, owner_daily_report, owner_order_history,
-- owner_active_orders, owner_order_detail, owner_audit_events,
-- owner_complete_order -- all carry the inner grant.
--
-- The production symptom was not a missing report. An authenticated Dashboard
-- call entered the wrapper and was refused on the inner function with
-- `42501 permission denied for function owner_report_currency_breakdown`. The
-- Dashboard repository treats an unavailable breakdown as "currency
-- unverifiable", and the currency guard then resolved to `unknown` for any
-- window with orders -- so every monetary total on the Overview was hidden.
-- The data was never mixed-currency: production is single-currency ILS.
--
-- The gap survived review because the OPS-043 pgTAP suite sets the identity
-- GUC but never `set local role authenticated`, so it executed as superuser,
-- for whom EXECUTE is irrelevant.
-- `supabase/tests/owner_report_family_acl_test.sql` now exercises the real
-- role and additionally asserts family-wide parity DYNAMICALLY, so the next
-- report function added with the same mistake fails without anyone remembering
-- to extend a list.
--
-- SCOPE. One grant. `authenticated` only -- anon and PUBLIC stay revoked, the
-- wrapper's INVOKER posture is unchanged, and the SECURITY DEFINER
-- implementation still enforces membership/role and tenant scope exactly as
-- before. Re-running this migration is harmless.

grant execute
  on function app.owner_report_currency_breakdown(uuid, uuid, uuid, date, date)
  to authenticated;

comment on function app.owner_report_currency_breakdown(uuid, uuid, uuid, date, date) is
  'OPS-043 Phase 2 per-currency report breakdown. REPORT-123 restored the missing authenticated EXECUTE grant: the public wrapper is SECURITY INVOKER, so without a grant on this implementation every authenticated caller received 42501 and the Dashboard hid all monetary totals. authenticated only - anon and PUBLIC remain revoked.';
