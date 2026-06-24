# M6 Jira Backlog — Real Product Integration / Sellable Restaurant Demo

> **STATUS — ADVISORY.** Human-readable backlog for the M6 post-plan track.
> Direction + guardrails: [M6_REAL_PRODUCT_INTEGRATION_PLAN.md](M6_REAL_PRODUCT_INTEGRATION_PLAN.md).
> Jira import: [M6_JIRA_IMPORT.csv](M6_JIRA_IMPORT.csv). Subordinate to the frozen
> canon ([../CLAUDE.md](../CLAUDE.md), [DECISIONS.md](DECISIONS.md),
> [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md)); new backend tickets are change-controlled
> (candidate **D-030**, §11 of the direction plan).

## Epic

**RF-EPIC-M6 — M6 Real Product Integration / Sellable Restaurant Demo.** Connect
the existing M5 demo UIs to the already-built backend (RF-014→094) by implementing
the stub feature/auth packages and activating real data paths, plus a fenced set
of change-controlled new backend surfaces (menu, image storage, provisioning,
tables, kitchen action). All RF-107→RF-121 sit under this Epic.

**Dependency order (high level):**
`RF-107 → RF-108 → {RF-109→RF-110, RF-112} → {RF-111, RF-113} ; RF-108→RF-114→RF-115→RF-116 ; {RF-108,RF-115}→RF-117 ; {RF-116,RF-117}→RF-118 ; {RF-108,RF-116}→RF-119 ; RF-108→RF-120 ; all→RF-121.`
**First In Progress after the gate: RF-108.**

---

## RF-107 — Formalize M6 direction and Jira backlog (this gate)
- **Goal:** establish the M6 direction, guardrails, backlog, and candidate decision before any M6 code.
- **User-visible result:** the three M6 docs (direction plan, this backlog, the CSV) + candidate D-030.
- **Backend involved:** none.
- **Apps affected:** none.
- **Likely files/packages:** `docs/M6_REAL_PRODUCT_INTEGRATION_PLAN.md`, `docs/M6_JIRA_BACKLOG.md`, `docs/M6_JIRA_IMPORT.csv`.
- **New schema/RLS/RPC/storage:** no.
- **Dependencies:** none.
- **Risk:** Low.
- **Tests/validation:** markdown link check; CSV parses (13 columns; RF-EPIC-M6 + RF-107→121); docs-only `git diff`; secret scan.
- **Acceptance:** M6 docs exist and are approved; candidate D-030 recorded (not ratified); no code/backend/frozen-doc changes.
- **Out of scope:** ratifying D-030 into DECISIONS.md; any implementation.

## RF-108 — Auth and role-based entry
- **Goal:** a real Supabase session + identity/role foundation (the prerequisite for all M6 work).
- **User-visible result:** per-app login — manager/owner email+MFA; cashier/kitchen device-pair + PIN — routing to the right surface by role.
- **Backend involved:** RF-050 (auth binding), RF-051 (`start_pin_session`), RF-059 (RLS), `sync_pull` scope. Reuse only; thin auth/device-pair glue if a gap surfaces.
- **Apps affected:** all four (entry/login + role gate).
- **Likely files/packages:** implement `packages/auth_identity` (session manager, current-user/membership/role provider, PIN flow); a shared Supabase-client bootstrap (env anon key); each app `main.dart` auth gate.
- **New schema/RLS/RPC/storage:** no (reuses RF-050/051).
- **Dependencies:** RF-107.
- **Risk:** High (security foundation).
- **Tests/validation:** auth/session unit tests; role-gate widget tests; wrong-role-denied smoke; `no-service-role` confirmation; analyze/format/guards.
- **Acceptance:** a real PIN/login yields `pin_session_id`+`device_id`+resolved org/restaurant/branch/role; RLS-scoped reads work; no service-role key in client. Activating an injected session makes KDS render live data.
- **Out of scope:** full MFA UX polish (Q-008); self-serve org signup (RF-090).

## RF-109 — Menu backend schema/RLS/RPC/sync (NEW BACKEND, change-controlled)
- **Goal:** server-owned, RLS-isolated menu, synced to devices.
- **User-visible result:** enables owner menu CRUD (RF-111) and real POS menu.
- **Backend involved:** new `menu_categories/menu_items/item_sizes/item_variants/modifiers/modifier_options` tables; RLS; audited management RPCs; add menu entities to `sync_pull`.
- **Apps affected:** none directly.
- **Likely files/packages:** `supabase/migrations/*` (new), `supabase/tests/*` (pgTAP); client mirror via `data_local` `MenuRepository` (exists); `feature_menu` read API.
- **New schema/RLS/RPC/storage:** **yes — schema + RLS + RPC + sync.**
- **Dependencies:** RF-108.
- **Risk:** High (new RLS surface).
- **Tests/validation:** pgTAP schema/constraints/RLS isolation (RF-060 set), idempotency, snapshot-independence (D-008), integer-minor prices.
- **Acceptance:** RLS-isolated menu CRUD via RPC; menu pulls to device; order snapshots remain authoritative; isolation suite green.
- **Out of scope:** inventory/stock; recipes/cost; menu scheduling.

## RF-110 — Menu image storage bucket and policies (NEW BACKEND, change-controlled)
- **Goal:** tenant-scoped image storage for menu items.
- **User-visible result:** item photos in menu management and POS.
- **Backend involved:** Supabase Storage bucket + org-path-scoped RLS policies + signed-URL/upload path.
- **Apps affected:** consumed by RF-111 / POS.
- **Likely files/packages:** `supabase/config.toml` storage section + storage policies; client upload helper (likely in `data_remote`/`feature_menu`).
- **New schema/RLS/RPC/storage:** **yes — storage bucket + policies.**
- **Dependencies:** RF-109.
- **Risk:** High (cross-tenant image leakage).
- **Tests/validation:** storage-policy isolation (org A cannot read/write org B); MIME/size limits.
- **Acceptance:** org-scoped upload/serve; no cross-tenant access; no public PII.
- **Out of scope:** CDN / image transform pipeline.

## RF-111 — Owner menu management UI
- **Goal:** owner edits the menu.
- **User-visible result:** category/item/price/availability/size/variant/modifier CRUD + image upload.
- **Backend involved:** RF-109 (menu RPCs) + RF-110 (images).
- **Apps affected:** dashboard (or admin) — owner surface.
- **Likely files/packages:** `feature_menu` UI + repo; `restoflow_design_system`, `restoflow_l10n`, `restoflow_money`.
- **New schema/RLS/RPC/storage:** no.
- **Dependencies:** RF-109, RF-110.
- **Risk:** Medium.
- **Tests/validation:** widget tests; integer-money + no-float guard; RTL; hardcoded-string guard.
- **Acceptance:** owner CRUD persists to backend and syncs to POS; prices integer-minor.
- **Out of scope:** bulk import; menu scheduling.

## RF-112 — Settings/users/roles/device provisioning backend (NEW BACKEND, change-controlled)
- **Goal:** manage org/restaurant/branch settings, memberships/roles, and device pairing.
- **User-visible result:** enables the owner admin UI (RF-113).
- **Backend involved:** new RPCs (`grant_membership`/`update_role`, `pair_device`/`approve_device`, `update_restaurant|branch_settings`) + RLS; reuse RF-061 revoke.
- **Apps affected:** none directly.
- **Likely files/packages:** `supabase/migrations/*` (new), `supabase/tests/*` (pgTAP).
- **New schema/RLS/RPC/storage:** **yes — RPC + RLS.**
- **Dependencies:** RF-108.
- **Risk:** High (privilege escalation surface).
- **Tests/validation:** pgTAP authorization/isolation (owner/manager-in-scope only; no cross-tenant; revoke propagation); audit on every mutation.
- **Acceptance:** owner adds/revokes users, sets roles, pairs devices, edits settings — all audited, RLS-isolated; isolation suite green.
- **Out of scope:** self-serve org signup (RF-090 path); billing edits (platform-admin only).

## RF-113 — Owner settings/users/devices UI
- **Goal:** the owner admin surface.
- **User-visible result:** restaurant/branch settings, user list + role assignment, device pairing.
- **Backend involved:** RF-112.
- **Apps affected:** dashboard/admin.
- **Likely files/packages:** owner UI screens; design_system/l10n.
- **New schema/RLS/RPC/storage:** no.
- **Dependencies:** RF-112.
- **Risk:** Medium.
- **Tests/validation:** widget + role-gate tests.
- **Acceptance:** end-to-end manage users/devices/settings against the backend.
- **Out of scope:** multi-restaurant org hierarchy editor.

## RF-114 — Tables list, order type, and table assignment (SMALL NEW BACKEND)
- **Goal:** dine-in/takeaway + table assignment.
- **User-visible result:** POS order-type toggle; dine-in picks a table from a branch list.
- **Backend involved:** small new `tables` table + RLS (or local-first); `orders.table_id` already exists.
- **Apps affected:** POS (+ owner table list in dashboard).
- **Likely files/packages:** `supabase/migrations/*` (small, if backed); POS order-type/table UI; reuse domain `TableAssignmentService`.
- **New schema/RLS/RPC/storage:** **small yes** (a `tables` table + RLS) — or deferred local-first.
- **Dependencies:** RF-108.
- **Risk:** Low-Medium.
- **Tests/validation:** assignment rules (one open dine-in per table); RLS isolation.
- **Acceptance:** order carries order-type + table; assignment rule respected.
- **Out of scope:** visual floor map; reservations; merge/split.

## RF-115 — POS real submit-order and client outbox push
- **Goal:** real, offline-first orders.
- **User-visible result:** POS uses real menu; cart with notes/modifiers/size-variant/table/order-type; Submit → `submit_order` via outbox with visible sync status and provisional→authoritative receipt id.
- **Backend involved:** `submit_order` (RF-052), `sync_push` (RF-056), RLS. No new schema.
- **Apps affected:** POS.
- **Likely files/packages:** implement `feature_orders` client + **client outbox push engine** (retry/backoff/conflict over `data_local` outbox + `data_remote` transport; mirror `KdsSyncCoordinator`).
- **New schema/RLS/RPC/storage:** no (reuses RPCs); the push engine is new client code.
- **Dependencies:** RF-108, RF-109, RF-114.
- **Risk:** High (offline correctness + money).
- **Tests/validation:** idempotency (device_id+local_operation_id, D-022); offline queue + reconcile; server-recompute rejection (D-007); integer-money; no-float guard.
- **Acceptance:** an order submitted offline applies exactly once on reconnect; totals server-validated; cart options snapshotted (D-008).
- **Out of scope:** discount/void UI (thin follow-up); refunds.

## RF-116 — POS cash payment, shift, and receipt flow
- **Goal:** cash payment + shift + receipt.
- **User-visible result:** open/close shift; take cash payment + change; receipt number assigned; customer-receipt preview.
- **Backend involved:** `record_payment` (RF-054), `open/close/reconcile_shift` (RF-055). No new schema.
- **Apps affected:** POS.
- **Likely files/packages:** implement `feature_payments`, `feature_shifts` clients; `printing` receipt builder.
- **New schema/RLS/RPC/storage:** no.
- **Dependencies:** RF-115.
- **Risk:** High (money).
- **Tests/validation:** integer change math; receipt monotonicity; pay-first independence (D-025); void-blocked-if-paid (D-024); shift variance.
- **Acceptance:** cash payment completes; receipt number authoritative on sync; shift variance computed.
- **Out of scope:** card/online; tips/service charge.

## RF-117 — KDS live backend orders and kitchen status actions (SMALL NEW BACKEND)
- **Goal:** live kitchen orders + backend-driven status actions.
- **User-visible result:** KDS shows real submitted orders by station; staff Acknowledge→Start→Mark-ready→Bump→Recall against the backend; money-free.
- **Backend involved:** `sync_pull`/realtime (RF-057/058, already) + small new kitchen status-transition RPC.
- **Apps affected:** KDS (activate the existing wired path with a real session).
- **Likely files/packages:** `supabase/migrations/*` (small RPC + RLS); reuse `feature_kitchen` / `KdsSyncCoordinator`.
- **New schema/RLS/RPC/storage:** **small yes** (kitchen action RPC + RLS).
- **Dependencies:** RF-108, RF-115.
- **Risk:** Medium-High (kitchen money redaction).
- **Tests/validation:** KDS money redaction (RLS); status transitions; realtime-as-enhancement (polling source of truth, D-010).
- **Acceptance:** a POS order appears on KDS within the poll interval and advances via the backend; no money visible.
- **Out of scope:** full kitchen-routing-rules engine polish (RF-033).

## RF-118 — Receipt/kitchen-ticket browser print preview
- **Goal:** printable docs in a browser demo (no hardware).
- **User-visible result:** "Print receipt"/"Print kitchen ticket" opens a clean HTML/PDF preview (`window.print`), labeled demo.
- **Backend involved:** none (local print spool only).
- **Apps affected:** POS (receipt), KDS (ticket).
- **Likely files/packages:** reuse `printing` builders for content + a new thin web-preview renderer; keep ESC/POS path intact for future native.
- **New schema/RLS/RPC/storage:** no.
- **Dependencies:** RF-116, RF-117.
- **Risk:** Medium (must not imply hardware works).
- **Tests/validation:** money-free kitchen ticket; integer-money receipt; ar/he/en RTL; golden HTML.
- **Acceptance:** a styled receipt/ticket prints from the browser; the doc states hardware/local-bridge is future.
- **Out of scope:** real USB/BT/network printing and drawer kick (no hardware).

## RF-119 — Owner dashboard real reports
- **Goal:** real reports replacing the demo report.
- **User-visible result:** KPIs/daily-summary/sales-by-branch from real `daily_branch_sales_report`/`dashboard_*` views (RLS-scoped to the owner's branches).
- **Backend involved:** RF-075/092 views.
- **Apps affected:** dashboard.
- **Likely files/packages:** implement `feature_reporting` read client (reuse `data_remote` transport pattern).
- **New schema/RLS/RPC/storage:** no.
- **Dependencies:** RF-108, RF-116.
- **Risk:** Medium.
- **Tests/validation:** integer aggregation; RLS scope (manager sees own branch); single-currency grouping.
- **Acceptance:** dashboard numbers reconcile to real orders/payments.
- **Out of scope:** analytics/trends/charts.

## RF-120 — Platform admin real data
- **Goal:** the platform admin surface.
- **User-visible result:** `apps/admin` shows the platform-admin org overview (RF-091), MFA-gated, reason-logged.
- **Backend involved:** RF-091/093 RPCs.
- **Apps affected:** admin.
- **Likely files/packages:** admin UI; a platform-admin client over RF-091.
- **New schema/RLS/RPC/storage:** no.
- **Dependencies:** RF-108.
- **Risk:** High (privileged path).
- **Tests/validation:** platform-admin separation (D-026); audit-on-access.
- **Acceptance:** a platform admin sees the cross-org overview via the separate audited path; tenant users cannot.
- **Out of scope:** impersonation; grant/revoke admin.

## RF-121 — M6 final QA, isolation, run guide, hardening
- **Goal:** a ship-ready connected demo.
- **User-visible result:** an `M6_DEMO_RUN_GUIDE.md` and a stable end-to-end connected demo.
- **Backend involved:** re-run RF-060 isolation suite + the new pgTAP from RF-109/110/112/114/117.
- **Apps affected:** all.
- **Likely files/packages:** `docs/M6_DEMO_RUN_GUIDE.md`; misc hardening across apps.
- **New schema/RLS/RPC/storage:** no.
- **Dependencies:** all of RF-108→RF-120.
- **Risk:** Medium.
- **Tests/validation:** full workspace tests + guards + web builds + the canonical isolation set (cross-org, cashier-can't-void-paid, KDS-no-money, revoked-device, removed-employee, platform-admin-audited).
- **Acceptance:** end-to-end demo passes; isolation tests green; run guide accurate.
- **Out of scope:** production deploy/secrets/CI.
