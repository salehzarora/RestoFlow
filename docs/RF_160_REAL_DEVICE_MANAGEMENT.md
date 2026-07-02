# RF-160 — Real dashboard device management (Phase B) + sprint status

> **STATUS UPDATE (product-rescue sprint, 2026-07-02).** The "deferred" notes below
> are HISTORICAL: RF-161 shipped the device-auth bridge (device-originated
> redemption → device session → secure storage → type-checked restore), and the
> product-rescue sprint added dashboard **revoke** (`public.revoke_device_management`),
> the **Printers** and **Staff/PIN** surfaces, the shared **PIN sign-in** on POS/KDS
> (production bcrypt verifier), the real POS menu + order submission, KDS
> `order.status` persistence, and the Overview `sales_summary`. The manager-side
> redeem/approve/activate simulation no longer applies to the real backend (the
> device pairs itself); the dashboard hides those actions in real mode. See
> [LOCAL_RUNBOOK.md](LOCAL_RUNBOOK.md) for the end-to-end local flow.

> Scope decision (owner, Saleh): **keep the M0A architecture freeze; implement only
> the safe, achievable parts.** This ticket delivers real owner/manager **device
> management** in the dashboard against the existing RF-112 backend, plus one small
> additive read RPC. It does **not** touch the frozen device-session architecture.

## What became real

The dashboard **Devices** tab is now backed by the real backend in authenticated
mode (demo mode and widget tests keep the in-memory demo store — the demo default is
preserved, and a real surface shows **no** demo banner):

- **List devices** — a new `public.list_devices` RPC (see below) returns each device
  in the caller's authorized scope with its live lifecycle status + open-session flag.
- **Create device** — `public.create_device` (RF-112) for a branch-scoped scope.
- **Issue enrollment code** — `public.issue_device_enrollment_code` (RF-112); the
  one-time code is shown exactly once.

Client seam: [`SupabaseAdminDeviceRepository`](../apps/dashboard/lib/src/admin/supabase_admin_device_repository.dart)
implements the `feature_admin` `AdminRepository` seam over the authenticated anon-key
`SyncRpcTransport` (DECISION D-011 — no service-role key; identity is server-derived
from `auth.uid()`, never sent). It is injected only behind the Devices tab; Settings
and Users keep the demo store until their read RPCs land.

## New backend — `public.list_devices` (additive, forward-only)

[`20260701100000_rf160_list_devices.sql`](../supabase/migrations/20260701100000_rf160_list_devices.sql)
adds `app.list_devices(org, restaurant?, branch?)` + a thin `public` SECURITY INVOKER
wrapper. It **mirrors the RF-112 GUC-free authorization model exactly** (DECISION D-033):

- identity from `auth.uid()` → `app.current_app_user_id()`;
- authority via `app.actor_rank_in_scope` over the **passed** scope, downward-only
  (org-wide member covers any restaurant/branch; a branch member covers only its branch);
- `rank >= manager` may list; a rank-1 in-scope member (cashier/kitchen/accountant) →
  `permission_denied`; no covering membership (non-member / cross-org / out-of-scope /
  anon) → `42501` (fail closed);
- **read-only**, and it **never returns a secret** (`enrollment_code_hash` /
  `session_token_ref` never leave the DB).

pgTAP: [`rf160_list_devices_test.sql`](../supabase/tests/rf160_list_devices_test.sql)
covers the role/rank matrix, downward-scope coverage, **cross-tenant isolation
(RISK R-003)**, status reflection, and no-secret-leak.

> **PENDING — mandatory human RLS/security sign-off (AGENTS.md, RISK R-003)** before
> this RPC serves real tenant data.

## Honest deferrals (not faked)

- **Device-side redemption + lifecycle past `code_issued`.** RF-112 is
  *management-driven* and still has **no device-auth bridge** — a device cannot yet
  authenticate as itself. So `redeemEnrollmentCode` / `approveDevice` /
  `activateDevice` / `startDeviceSession` return a typed, localized **conflict**, never
  a fabricated transition. A dashboard-created device therefore reaches `code_issued`
  and waits for the (deferred) device side.
- **Create in an org-wide scope.** `create_device` is branch-scoped; an org-wide
  membership (no restaurant/branch) gets an honest validation error. A branch picker
  for org/restaurant-scoped owners is the follow-up.
- **Settings / Users real reads.** No `list` RPC yet; those tabs stay on the demo store.

## RF-160 sprint status (the rest)

Blocked by the deliberately-frozen baseline or by human-only gates — **not** by missing
code, and not attempted here (per the scope decision):

| Phase | Status | Reason |
|---|---|---|
| B — real dashboard device mgmt | **Delivered** (this ticket) | — |
| C — secure device session storage | Deferred | no real device session token yet (below) |
| D/E — real POS/KDS pairing + session | **Frozen-blocked** | device-auth bridge deferred (RF-112 header; D-034 follow-up) |
| F — real order lifecycle | Blocked | depends on D/E (a real device + PIN session) |
| G — printer adapters/transport | **Human-gated** | on-site hardware + Q-006/Q-015 (RF-150 shipped config only) |
| H — real-first cutover | Premature | do not default to real until D/E/F work |
| I — polish | Partially deferred | sign-out affordance + membership-picker filter recommended next |

## Not ready for paid production

Remaining blockers to a real paid launch: the **mandatory human RLS/security sign-off**
(incl. `list_devices`), the **device-auth bridge + device-session** architecture
(D/E/F), a **printer hardware/transport** decision (human/on-site), and **MFA policy**
(Q-008). Until those are resolved, RestoFlow can onboard an owner and let them manage
devices for real, but the end-to-end POS↔KDS operational loop is not yet real.
