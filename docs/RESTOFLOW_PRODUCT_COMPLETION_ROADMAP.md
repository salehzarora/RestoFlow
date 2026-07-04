# RestoFlow — Product Completion Roadmap

> **Status: honest engineering audit, not marketing.** RestoFlow is a **supervised
> local demo / pilot foundation**. It is **NOT production-ready** and must not be
> sold, deployed to real paying tenants, or run on live customer money/hardware
> until the gates below are closed. Every "ready" claim in this doc is scoped to
> *demo* or *pilot* unless it explicitly says *production*.
>
> Authoritative rules still live in the frozen `docs/` set (ARCHITECTURE,
> SECURITY_AND_THREAT_MODEL, MONEY_AND_TAX_SPEC, OFFLINE_SYNC_SPEC,
> PRINTERS_AND_HARDWARE_SPEC, DECISIONS, OPEN_QUESTIONS). This roadmap references
> them; it does not override them. Ticket IDs use the `RF-<n>` convention.
>
> Last updated after: **RF-112** (browser e2e smoke), **RF-113** (shift
> close/reconcile), **RF-114** (durable offline outbox), **RF-115** (print
> bridge), **RF-116** (real users/settings), **RF-117** (taxes/discounts/non-cash
> tenders), **RF-119** (platform-admin MFA: server aal2 enforcement verified +
> `platform_admin_list_organizations` gated + `get_my_context.is_mfa_aal2` +
> honest Admin gate), **RF-119-b** (admin in-app sign-in + TOTP MFA
> enrol/challenge; account-provisioning UI + QR image remain hardening),
> **RF-118** (rate limits + session expiry: pairing brute-force lockout,
> device-session max age, visible client PIN cooldown + session-inactivity policy).

---

## 1. Completed capabilities (after RF-112/113/114/115/116/117)

**Multi-tenant backend (Supabase / Postgres, RLS-first).** Organization →
restaurant → branch → device/station hierarchy; `organization_id` isolation on
every tenant row; RLS + `SECURITY DEFINER` RPCs + DB constraints (four-layer
defence, D-011/D-012). Anon-key-only clients, no service-role key anywhere.
pgTAP suite: **~180 files / ~2900 assertions** incl. the tenant-isolation harness.

**Identity & device auth.** Per-person identities, membership-scoped roles
(`org_owner`/`restaurant_owner`/`manager`/`cashier`/`kitchen_staff`/`accountant`),
device pairing via one-time enrollment codes, anonymous device sessions,
token-proven device reads, PIN-based fast sessions on paired devices. Platform
admin is a separate, audited grant (never reachable by tenants, D-026).

**Owner Dashboard (real mode).** Signup/onboarding (`create_organization`),
session + org/branch context, **real Menu management** (categories/items/
modifiers/sizes/variants, images over the RF-110 bucket), **real Devices** (list/
create/issue-code/revoke), **real Tables**, **real Staff + PINs**, **real Users**
(list/change-role/revoke — RF-116), **real Settings** (branch/restaurant name,
receipt prefix, shift-close toggle, tax setting — RF-116/117), honest sales
summary. Demo mode preserved and clearly labelled.

**POS (cashier).** Pairing → PIN sign-in → live menu → cart (modifiers ×N, item
notes, tables/dine-in vs takeaway) → order submit via the offline outbox →
`public.sync_push`(`order.submit`) → server-authoritative totals. **Cash + card
+ Bit + external tenders** (RF-117), **order-level discounts** (server-authorized
`apply_discount`, RF-117), **per-branch tax** (default off, RF-117), **shift
open/auto-open + close/reconcile UI** (RF-113), receipt preview + **print bridge**
status (RF-115), and now a **durable offline outbox** (RF-114): queued orders
survive refresh/tab-close/restart, retry idempotently, and never fake "sent".

**KDS (kitchen).** Pairing → PIN sign-in → live ticket board via `sync_pull`,
bump/recall (`order.status`), kitchen-ticket print status. **Money-free by
construction** (T-003): no price/total/tender ever reaches the KDS.

**Printing.** A render-neutral document + ESC/POS adapter + a **local, loopback-
only reference print bridge** (`tools/print_bridge`) with honest statuses
(`prepared` → `sent to printer`, never a faked "printed").

**Money discipline.** Integer minor units everywhere (D-007), server recomputes
order subtotals from snapshots, tax rounded half-away as integers, non-cash never
inflates expected cash. Guardrails: no-float-money, secret-leak, no-hardcoded-
strings, l10n parity.

**i18n.** Arabic-first (default), full ar/he/en with RTL/LTR; ILS/₪ only.

**CI.** Two GitHub jobs — the Dart `validate` gate (format/bootstrap/analyze/
tests/guardrails) + the Docker-local pgTAP job — both secret-free.

---

## 2. Demo-ready NOW (supervised local demo)

Runnable end-to-end locally (see `docs/LOCAL_RUNBOOK.md`): owner signs up →
builds a menu → creates + pairs POS/KDS devices → creates staff PINs → cashier
rings dine-in/takeaway orders with modifiers/notes/discounts/tax → pays with
cash or a recorded card/Bit/external tender → the KDS shows the money-free ticket
→ the shift can be closed/reconciled → orders survive a mid-service browser
refresh (RF-114) → an optional local print bridge can drive a real ESC/POS
printer. All backend-touching actions are honest (real result or an honest
error), and the protected RF-112 browser smoke exercises the core path.

**Good enough to demo to a restaurant owner on one laptop + Chrome, supervised.**

---

## 3. Still MVP / demo-only (works, but NOT pilot/production grade)

- **Durable outbox = shared_preferences/localStorage (RF-114 interim).** Web-
  durable and correct for one browser origin, but the *canonical* store per D-010
  is the `data_local` Drift `OutboxOperations` table (SQLite/WASM), which is
  **built but unwired** (no Drift-on-web setup). Only `order.submit` is durably
  queued; `payment.create` / `shift.*` / `order.discount` are not yet in the
  durable outbox. No cross-device outbox, no durable print spool. → **RF-114-b /
  RF-030**.
- **Offline auth window.** A revoked device/PIN can still act during the offline
  window; offline validity is unfrozen (Q-009, R-007). Payments still require an
  open shift, which the POS auto-opens (opening float 0) — no real cash count-in.
- **Tax is client-computed** from the owner's per-branch setting; the server
  validates total-consistency but does **not** re-derive the tax *rate* inside
  `submit_order`. Inclusive mode is stored but not wired. Jurisdiction/rate are
  OPEN (Q-001/Q-002) — no legal/fiscal tax.
- **Non-cash tenders are "record external tender" only** — no PSP, no card
  charge, no settlement, no void/refund of a completed payment (D-023).
- **Print bridge** confirms a socket write ("sent"), not a physical print; only
  network RAW-9100 + a demo sink exist. No Bluetooth/USB, no cash-drawer kick, no
  printer discovery, no durable spool/retry-across-restart for print jobs.
- **Users** = list/change-role/revoke only; **no invite/create of new accounts**
  (no email→user lookup). **Settings** currency is locked to ILS; address/
  receipt-prefix are write-only (not readable to prefill).
- **Reports** = a single sales summary; no date ranges, tender/tax/discount
  breakdowns, exports, or Z-report.
- **Realtime** is polling-first (`sync_pull`); Realtime is enhancement-only and
  not the source of truth.
- **Web "secure storage"** for device tokens is browser storage, not an OS
  keystore — fine for local dev, not for a hardware pilot.

---

## 4. Missing for a real restaurant PILOT (one real branch, real staff, real hardware)

1. **Canonical durable outbox + full op coverage (RF-114-b / RF-030).** Wire the
   Drift `OutboxOperations` store (with a real Flutter-web Drift/WASM setup) or
   commit to the shared_preferences store as canonical; extend durability to
   `payment.create`, `shift.*`, `order.discount`; add a durable print spool
   (RF-071/072 wiring). Prune/retention for applied entries.
2. **Real shift cash management (RF-055+).** Non-zero opening float count-in, the
   manager **reconcile** sign-off (`reconcile_shift` is server-only today), cash
   in/out (paid-in/paid-out), and a Z-report.
3. **Offline authorization safety (RF-007/Q-009).** Freeze the offline validity
   window; ensure a revoked device/PIN stops acting within it (R-007).
4. **Printer hardware validation (RF-070..074).** Test one validated ESC/POS
   model end-to-end (receipt + kitchen), Arabic/Hebrew raster correctness (R-006),
   station→printer routing UI, per-destination health/failure surfacing, drawer
   kick, reprint-with-audit. Decide LAN vs USB vs Bluetooth for the pilot (Q-015).
5. **Rate limiting + session expiry (RF-118) — PARTIALLY DONE.** ✅ Delivered:
   server-side device-pairing brute-force lockout (per calling principal, 10
   attempts → 15-min cooldown), device-session **max age** (7d, activating the
   RF-016-deferred `device_sessions.expires_at`; enforced on restore), a visible
   client PIN cooldown mirroring the server RF-051 lockout, and a client staff
   PIN-session inactivity/max-age policy (30 min idle / 8 h). ⚠️ **Remaining
   production-hardening:** the per-principal pairing lockout is bypassable by
   re-anonymizing (`signInAnonymously`) → real brute-force protection needs
   IP/edge/gateway rate-limiting and/or disabling anonymous sign-in in production;
   the durations are still interim (Q-009, not frozen); step-up re-auth for
   individual sensitive actions is not wired (client expiry is resume-time).
6. **Backups + recovery drill (OPERATIONS_AND_RECOVERY).** Even a pilot needs a
   tested DB backup/restore and a "device lost/stolen" runbook.
7. **User invite flow.** An owner must be able to add a new staff account safely
   (email invite or manager-created pending member), not only role-change existing
   ones.
8. **Human RLS/security sign-off (R-003).** The MVP RPCs carry an explicit
   "pending human sign-off before real tenant data" gate — that review must happen
   before a pilot serves real customers.

---

## 5. Missing for PRODUCTION SaaS (multi-tenant, paid, unsupervised)

- **Billing/subscription** (plans, metering, dunning) — none exists.
- **Payment processing** — a real PSP/terminal integration (or an explicit
  "external tender only" product decision) + PCI posture.
- **Fiscal/tax compliance** — freeze jurisdiction (Q-001), tax mode/rate,
  legal receipt numbering/format + reset cadence (Q-003/Q-004), certified
  hardware if mandated.
- **Platform admin MFA (RF-119 + RF-119-b) — server enforcement + in-app operator
  sign-in + TOTP MFA enrol/challenge DONE.** Remaining for a fully self-service,
  hardened platform-admin plane: admin-account provisioning UI (grants are still a
  manual DBA action) + an in-app QR-image renderer + per-read operator reason.
- **Observability** — centralized logging, metrics, error reporting (Sentry-class),
  uptime/alerting, per-tenant audit viewer.
- **Ops at scale** — automated backups + PITR, migration safety/rollback, blue/green
  or staged deploys, secret management, on-call runbooks, data-retention/GDPR (Q-005).
- **Scale/perf** — connection pooling, index review under load, realtime fan-out,
  read replicas, sync throughput/backpressure.
- **Refunds/voids/corrections** — a designed post-completion money-reversal model
  (deferred, D-023) with audit + fiscal correctness.
- **Account lifecycle** — self-serve onboarding at scale, org suspension/deletion,
  tenant export/offboarding, support tooling & impersonation-with-audit.
- **Accessibility, legal (ToS/privacy), and app-store/native packaging** if shipped
  beyond web.

---

## 6. Security gaps (explicit)

- **RF-118 — rate limits + session expiry — PARTIALLY DONE (server + client).**
  ✅ `start_pin_session` already had per-(employee, device) attempt lockout
  (RF-051: 5 attempts → 15 min). RF-118 added: `redeem_device_pairing`
  brute-force lockout (per `auth.uid()` principal, 10 attempts → 15 min, checked
  before the code lookup, safe generic `locked` error, reset on success);
  `device_sessions.expires_at` now SET at redeem (7-day max age) and ENFORCED on
  `restore_device_session` (activating the RF-016-deferred column); a visible
  client PIN cooldown (durable via shared_preferences, mirrors the server); and a
  client staff PIN-session inactivity/max-age policy surfaced at app resume
  ("session expired — enter PIN again"). ⚠️ **Still production-hardening:** the
  per-principal pairing lockout is bypassable by re-anonymizing → needs IP/edge
  rate-limiting and/or anonymous-sign-in disabled in prod; PIN-session TTL and all
  durations remain interim (Q-009, unfrozen); no anomaly detection; sensitive-action
  step-up re-auth not wired. *Close these before an unsupervised pilot.*
- **RF-119 + RF-119-b — platform-admin MFA — DONE (server + full in-app flow).**
  ✅ Platform data reads are MFA-enforced server-side: `app.platform_admin_guard`
  requires an active grant + **aal2** + reason (RF-091), and RF-119 closed the last
  un-gated path (`platform_admin_list_organizations`, RF-059, now aal2-gated).
  `get_my_context` returns `is_mfa_aal2`. **RF-119-b** added the real in-app flow:
  email/password platform-operator **sign-in** (anon key only, no service-role),
  **TOTP MFA enrolment + challenge** (`auth.mfa.enroll/challenge/verify`), then
  re-fetch `get_my_context` so entry is gated on the SERVER-derived aal2 — never
  the client's own state; sign-out on every state. A restaurant owner who signs in
  is never a platform admin. ⚠️ **Still production-hardening:** no admin-account
  provisioning UI (grants stay a manual DBA action, D-026), no in-app QR-*image*
  renderer (the setup key + otpauth URI are shown as text), no per-read operator
  reason entry (a fixed audited reason is used).
- **R-007 offline authorization staleness.** A device revoked while offline can
  still act until it reconnects; the offline window is unfrozen (Q-009).
- **R-003 RLS/tenant isolation sign-off.** The MVP-era RPCs are gated on a human
  security review before serving real tenant data — not yet done.
- **Device token storage on web** is browser storage, not an OS keystore
  (acceptable for local dev only).
- **Audit coverage** exists for money/membership/settings mutations (append-only,
  D-013) but there is **no in-app audit viewer** and no tamper-evidence/export.
- **Brute-force/lockout hardening (RF-118) is DB-layer + client only** — PIN
  attempts (RF-051) and pairing attempts (RF-118) lock out per identity/principal,
  but there is no IP/edge rate-limiting, no anomaly detection, and the pairing
  lockout is bypassable by minting a fresh anonymous principal per attempt.
- **Secrets discipline is good** (guardrail-enforced, anon-key-only) — keep it.

---

## 7. Operations gaps

- **Backups/recovery** — no automated backup, no restore drill, no PITR
  (OPERATIONS_AND_RECOVERY is spec, not implemented).
- **Monitoring/logging** — no centralized logs, metrics, dashboards, or alerting.
- **Error reporting** — no crash/error aggregation (client or server).
- **Support/admin tooling** — no support console, no audited impersonation, no
  per-tenant health view.
- **Audit events** — captured in the DB (append-only) but not surfaced or
  exportable; no retention policy (Q-005).
- **Runbooks** — LOCAL_RUNBOOK covers local dev; no production incident/on-call,
  device-loss, or key-rotation runbooks.
- **Migration safety** — forward-only migrations + pgTAP are good, but no
  staged/rollback strategy or zero-downtime plan for a live tenant.

---

## 8. Hardware gaps

- **Real printer testing** — never validated against physical ESC/POS hardware;
  only a demo sink + network RAW-9100 path exist (RF-115). Arabic/Hebrew raster
  fidelity (R-006) is unproven on hardware.
- **Printer discovery/assignment** — assignment is owner-configured in the
  Dashboard, but there is no network discovery and no on-device test-print that
  goes through the bridge to confirm a target.
- **Cash drawer** — modeled (kick = a spool job, no auto-retry) but **not wired**;
  no real drawer-kick path.
- **LAN/Bluetooth/USB decision** — only network RAW-9100 is implemented;
  Bluetooth/USB are honestly "requires a native adapter". Pilot transport is OPEN
  (Q-006/Q-015).
- **Durable print spool** — `packages/printing` has the spool/retry engine, but
  the apps use ephemeral in-memory print controllers; a print job does not survive
  a restart.
- **Device health/heartbeat** — no live device health, spool depth, or
  reachability telemetry surfaced to staff.

---

## 9. Business / product gaps

- **Onboarding** — signup + create-org works; no guided multi-step onboarding,
  sample-data seeding, or import wizard.
- **Billing/subscription** — none.
- **Reports** — one sales summary; missing date ranges, tender/tax/discount/void
  breakdowns, per-cashier/per-station, Z-report, and CSV/PDF **exports**.
- **Menu import/export** — no CSV/JSON import or export; menus are built by hand.
- **Role permissions polish** — six roles + rank gates exist; no fine-grained
  permission matrix, no per-action thresholds UI (e.g. cashier discount limits are
  a boolean membership permission, not a configurable cap).
- **Order lifecycle** — no refunds/voids-after-payment, no partial/split tender,
  no tips/service charge (deferred: Q-011/Q-012), no order edit-after-submit.
- **Customer-facing** — no CFD, no receipts by email/SMS, no loyalty/coupons,
  no delivery/online-ordering integrations.

---

## 10. Recommended next ticket order (after RF-114)

Prioritized for **pilot-readiness first**, then production hardening:

1. **RF-114-b — durable outbox: extend + harden.** Cover `payment.create` /
   `shift.*` / `order.discount` in the durable queue; add retention/pruning; decide
   Drift-web vs shared_preferences as canonical; wire a durable print spool.
2. **RF-070..074 — printer hardware validation** on one validated ESC/POS model
   (receipt + kitchen + Arabic/Hebrew raster), routing UI, health/failure surfacing,
   test-print-through-bridge, reprint+audit. Settle Q-015 transport.
3. **RF-055+ — real shift cash management**: opening-float count-in, manager
   `reconcile` sign-off, cash in/out, Z-report.
4. **RF-118 — rate limits + session expiry** (pairing/restore/PIN) — ✅ **DONE
   (DB + client)** for the supervised demo/pilot. Follow-up **RF-118-b**
   (production-hardening): edge/gateway IP rate-limiting for pairing (the
   per-principal DB lockout is re-anonymization-bypassable), freeze the Q-009
   durations, and sensitive-action step-up re-auth.
5. **Backups + recovery drill** (implement OPERATIONS_AND_RECOVERY basics) +
   the R-003 human RLS/security sign-off.
6. **Reports + exports** (date ranges, tender/tax/discount breakdown, CSV).
7. **User invite flow** (safe add-new-account path).
8. **Observability** (logging/metrics/error reporting) + **RF-119-c** platform-admin
   hardening (admin-account provisioning UI, in-app QR-image renderer, per-read
   operator reason) — RF-119-b already delivered in-app operator sign-in + TOTP
   MFA enrol/challenge on top of the RF-119 server aal2 enforcement.
9. **Freeze fiscal/jurisdiction** (Q-001..Q-004): tax mode/rate + legal receipt
   numbering — required before any real fiscal use.

---

## 11. Do NOT claim production-ready yet

RestoFlow today is a **supervised local demo / pilot foundation**. Until at least
sections 4–8 are addressed, the following claims are **false and must not be
made**:

- ❌ "Production-ready" / "enterprise-ready" / "ready to sell".
- ❌ "Processes card payments" — it **records external tenders**; there is no PSP.
- ❌ "Fiscally/tax compliant" — jurisdiction, rate, and legal receipt numbering are
  unfrozen (Q-001..Q-004).
- ❌ "Prints receipts" *unconfirmed* — the bridge confirms a **socket write**, not
  a physical print, and only over network RAW-9100.
- ❌ "Fully offline" — one browser origin's `order.submit` queue is durable;
  payments/shifts/print jobs and cross-device sync are not yet.
- ❌ "Secure for real tenants" — the R-003 human RLS/security sign-off, RF-118 rate
  limits, RF-119 platform-admin MFA, and offline-revocation (R-007) are open.
- ❌ "Backed up / recoverable" — no automated backups or tested restore exist.

**Safe to say:** RestoFlow can run a **supervised, single-branch local demo** and
is a foundation for a **hardware pilot** once the pilot gates (section 4) close.
