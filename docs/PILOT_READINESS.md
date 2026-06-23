# PILOT_READINESS.md — RF-076 readiness matrix (M3 hardware pilot)

> **Operational companion to the frozen [PILOT_PLAN.md](PILOT_PLAN.md).** PILOT_PLAN.md OWNS the
> pilot plan (objective, scope, entry/success criteria, rollback, go/no-go). This document does
> **not** redefine it — it records the **current readiness verdict** for the M3 hardware pilot
> (**RF-076**) against that plan, as of the baseline commits below. The day-of procedures live in
> [PILOT_RUNBOOK.md](PILOT_RUNBOOK.md).

> **RF-076 is human-owned (Saleh) with Claude Code as reviewer** (PILOT_PLAN §9, **DECISION D-016**).
> This document is a docs/readiness deliverable only. **It does not authorize a live deployment.**

---

## 1. Purpose

Give Saleh a single, honest, evidence-backed answer to: *"Can we run the M3 live pilot today?"* —
by mapping each capability and each PILOT_PLAN entry criterion to its real status (ready / simulated /
blocked / human-decision), and listing exactly what must close before a real service day is scheduled.

---

## 2. Current verdict

- **REAL PILOT: BLOCKED.**
- **CURRENT CAPABILITY: SIMULATED / LOCAL READINESS ONLY.**

The server/backend and the printing *logic* are strong and tested, but a real service day cannot run
because there is **no real printer/drawer transport**, **no end-to-end POS device app**, and several
**entry-criteria decisions are not frozen** (hardware, connectivity, jurisdiction/tax, offline window,
retention, DR), plus a **mandatory human RLS/security sign-off** (RISK R-003) has not been recorded.

---

## 3. Baseline commits (as assessed)

| Ticket | Merge commit | In `main` |
|---|---|---|
| RF-075 — Daily reports | `a4d9624` | yes |
| RF-074 — Cash drawer kick | `df273bd` | yes |
| RF-58 — Cash drawer job type + reprint guard | `b4030d2` | yes |

Assessed on branch `docs/RF-076-pilot-runbook` cut from clean `main` at `a4d9624`.

---

## 4. Dependency status

RF-076's declared dependencies are **RF-072, RF-073, RF-075** (IMPLEMENTATION_CHECKLIST); PILOT_PLAN
entry criteria additionally exercise the M2 backend + isolation tickets. All are merged:

| Ticket | Capability | Status |
|---|---|---|
| RF-050 / RF-051 | Supabase auth + MFA; PIN sessions | Done |
| RF-052 | `submit_order` RPC | Done |
| RF-053 | `apply_discount` / `void_order` RPCs (audited) | Done |
| RF-054 | `record_payment` + per-branch receipt numbering | Done |
| RF-055 | Shift / cash-drawer open/close + reconcile RPCs | Done |
| RF-056 / RF-057 | Sync push (inbox/ledger) + pull/conflict/revisions | Done |
| RF-059 / RF-060 | Full RLS scoped policies + canonical isolation suite | Done (code) — **human RLS sign-off still required** |
| RF-061 | Revocation propagation (device/employee) | Done |
| RF-070 / RF-071 | ESC/POS adapter + print spool/retry/reprint audit | Done (in-memory transport only) |
| RF-072 | Kitchen ticket printing routing | Done (logic) |
| RF-073 | Customer receipt printing (ar/he/en, 58/80mm, raster) | Done (logic) |
| RF-074 / RF-58 | Cash drawer kick + `cashDrawer` job type / reprint guard | Done (logic) |
| RF-075 | Daily reports (sales/shift/voids/discounts) | Done |

---

## 5. Readiness areas

Legend: **READY** (tested, usable) · **SIMULATED** (logic done, in-memory/local only, no real hardware/device) ·
**NOT READY** · **HUMAN DECISION** (frozen-baseline decision required, not code).

| Area | Status | Evidence / note |
|---|---|---|
| Backend migrations + pgTAP | READY | `supabase/migrations` + `supabase/tests`; full suite passes locally (`supabase db reset` + `test db`) |
| Auth / MFA / PIN sessions | READY | RF-050/051 RPC + lockout; MFA assurance gates (Q-008 for owner/manager MFA policy) |
| RLS / tenant isolation | READY (code) / **HUMAN DECISION** (sign-off) | RF-059/060 policies + isolation suite green; **RISK R-003** requires a recorded human RLS sign-off before live |
| Sync push/pull + revocation | READY | RF-056/057/061; idempotency `device_id + local_operation_id` (**D-022**) |
| Printing logic (adapter/spool) | SIMULATED | RF-070/071 render-neutral `PrintDocument` + ESC/POS bytes + spool/retry/reprint; **in-memory transport only** |
| Receipt logic (ar/he/en) | SIMULATED | RF-073 builder + raster fallback validated against in-memory; not validated on a real printer/model |
| Kitchen ticket routing | SIMULATED | RF-072 route→build→enqueue; no physical kitchen printer/KDS device path |
| Cash drawer logic | SIMULATED | RF-074 one-shot `drawer:<paymentId>`, `maxRetries:0`; no real drawer kicked |
| Daily reports | READY | RF-075 server views reconcile to orders/payments; KDS denied financial reads |
| Apps — POS | NOT READY | `apps/pos` is a scaffold (single `main.dart`); no end-to-end order/payment/receipt flow wired to RPCs |
| Apps — KDS | NOT READY (prototype) | `apps/kds` has `src/` + widget tests; prototype, not a hardened on-device pilot client |
| Apps — admin / dashboard | NOT READY (shells) | `apps/{admin,dashboard}` are `main.dart` shells; not required for the pilot (dashboard is M4 RF-092) |
| Hardware transport | NOT READY | `packages/printing` ships `InMemoryPrintTransport` only; `network`/`usb`/`bluetooth` throw `UnsupportedTransportException` |
| Open decisions (hardware/money/offline/DR) | **HUMAN DECISION** | see Blockers §6 |

---

## 6. Blockers (must close before a real service day)

| # | Blocker | Type | Gates |
|---|---|---|---|
| B1 | **No real printer/drawer transport** — in-memory only; network/USB/BT throw `UnsupportedTransportException` | Code (companion ticket) | S3, S4, S5 |
| B2 | **POS device app not end-to-end** — cannot build/submit/pay/print on a tablet | Code (companion ticket) | S1, S2, S5, S6 |
| B3 | **Q-006 hardware not frozen** (printer/POS/KDS/drawer models) | Human decision | Entry criterion 4 |
| B4 | **Q-015 connectivity not frozen** (network/USB/Bluetooth) | Human decision | Entry criterion 4; S11 |
| B5 | **Q-001 jurisdiction / Q-007 currency not frozen** | Human decision | Entry criterion 5; **RISK R-008** |
| B6 | **Q-002 / Q-003 / Q-004 tax/fiscal not frozen** (or explicitly deferred with restaurant's informed agreement) | Human decision | Entry criterion 5 |
| B7 | **Q-009 offline window not frozen** | Human decision | Entry criterion 6; S12; **RISK R-007** |
| B8 | **Q-005 retention not frozen** | Human decision | Entry criterion 7 |
| B9 | **Q-013 RTO/RPO not frozen** | Human decision | Entry criterion 9 |
| B10 | **Human RLS / security sign-off not recorded** (**RISK R-003**, CRITICAL) | Human action | Entry criterion 2; S10 |

---

## 7. Go / no-go summary

- **Go (real service-day pilot): NO.**
- **Conditional-go: SIMULATED / LOCAL ONLY** — backend + printing logic may be exercised end-to-end
  against the local Supabase stack and in-memory transport for rehearsal/validation, **not** with real
  money, real hardware, or a real restaurant.
- **No-go: a real service-day pilot** until B1–B10 close. The final go/no-go is Saleh's (PILOT_PLAN §9).

---

## 8. Future companion tickets needed (IDs assigned in Jira — not invented here)

1. **Real printer/drawer transport** behind the RF-070 adapter (network/USB/Bluetooth), replacing
   `UnsupportedTransportException`; gated by Q-006/Q-015. (B1)
2. **Functional POS app** — end-to-end cart → `submit_order` → `record_payment` → receipt build/enqueue
   → drawer kick, on a paired device identity. (B2)
3. **KDS device wiring/hardening** if the pilot uses a KDS screen rather than a kitchen printer. (B2)
4. **Hardware + connectivity decision freeze** (Q-006, Q-015) and the money/offline/DR freezes
   (Q-001/Q-007/Q-002-004/Q-009/Q-005/Q-013). (B3–B9 — human decisions, not code.)

---

## 9. Security notes (non-negotiable for the pilot)

- **No shared accounts** — each cashier/kitchen staff uses a personal employee identity with a PIN
  fast-session on a paired + authorized device only (**DECISION D-004/D-005/D-006**).
- **No `service_role` credentials on POS/KDS devices** — access is device identity + PIN session +
  Org-scoped RLS only (**DECISION D-011**). No secrets committed.
- **Tenant/branch isolation** — every row carries `organization_id` (+ restaurant/branch/device/station)
  (**DECISION D-001/D-002**); Org A can never read Org B (**RISK R-003**, T-001).
- **KDS / kitchen_staff cannot read financial reports** — enforced by `app.can_read_financials` RLS;
  RF-075 ships the canonical denial test (T-003).
- Any cross-tenant anomaly **halts the pilot immediately** (PILOT_PLAN §6).

---

## 10. Explicit statement

**RF-076 does not authorize a live deployment.** It produces the readiness verdict and runbook only.
The real pilot remains BLOCKED until the §6 blockers close and Saleh records a GO per
[PILOT_PLAN.md](PILOT_PLAN.md) §9. See [PILOT_RUNBOOK.md](PILOT_RUNBOOK.md) for the day-of procedures.
