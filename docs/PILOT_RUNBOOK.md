# PILOT_RUNBOOK.md — RF-076 operational runbook (M3 hardware pilot)

> **Operational companion to the frozen [PILOT_PLAN.md](PILOT_PLAN.md)** and the readiness verdict in
> [PILOT_READINESS.md](PILOT_READINESS.md). PILOT_PLAN.md OWNS the plan; this runbook is the day-of
> procedure (pre-day gate, checklists, manual test script, evidence, incidents, rollback, go/no-go,
> post-pilot review). It references — never redefines — money ([MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md)),
> security ([SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md)), sync
> ([OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md)), printing
> ([PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md)), state machines
> ([STATE_MACHINES.md](STATE_MACHINES.md)), and operations
> ([OPERATIONS_AND_RECOVERY.md](OPERATIONS_AND_RECOVERY.md)).

> **CURRENT STATUS — the real pilot is BLOCKED (see [PILOT_READINESS.md](PILOT_READINESS.md)).** This
> runbook is written so it is ready to execute *once* the blockers (B1–B10) close. Until then it serves
> rehearsal/validation against the local stack + in-memory transport only.

---

## 1. Purpose and scope

Operate **one real full service day** in **one organization → one restaurant → one branch** on RestoFlow,
proving orders flow cashier→kitchen, tickets/receipts print, cash + change + drawer work, shifts reconcile,
a daily report is produced, and sync recovers after an outage — with **no cross-tenant or security incident**
(PILOT_PLAN §1). Cash-only; no shared accounts; full multi-tenant RLS.

## 2. Non-goals

- **No live deployment is performed by Claude Code.** The live day is operated by Saleh (PILOT_PLAN §9).
- **No remote Supabase `db push`/changes** from this work.
- **No secrets in the repo**; **no production credentials created** by this ticket.
- No real hardware-transport code, no POS/KDS feature build, no billing/dashboard/platform-admin (all M4 / separate tickets).

## 3. Pilot target

| Dimension | Pilot value |
|---|---|
| Organization | One pilot Org (`organization_id`) — the tenant (**DECISION D-003**) |
| Restaurant | One `restaurant` under the Org |
| Branch | One `branch` |
| Stations | ≥1 kitchen station (e.g. `grill`/`bar`) per RF-072 routing |
| Devices | One paired POS tablet (device identity); kitchen printer and/or one KDS display |
| Staff roles | owner/manager (personal account, MFA per Q-008); cashier(s) + kitchen_staff (personal employee identities, PIN fast-session on the paired device) |
| Money | Cash only; single currency (Q-007); jurisdiction/tax per Q-001/Q-002 (or explicitly deferred with the restaurant's informed agreement) |

## 4. Pre-day readiness gate (ALL must be true)

Mirror of PILOT_PLAN §4 entry criteria — do not start the live day unless every box is checked:

- [ ] **Tests green** — `supabase db reset` + `supabase test db` pass (migrations + pgTAP, incl. RF-059/060 isolation + RF-075 reconciliation); `melos run analyze` + `flutter test` + `dart test packages/printing` pass.
- [ ] **Isolation evidence + human RLS sign-off captured** (RF-059/060; **RISK R-003**, CRITICAL): Org A cannot read Org B; cashier A cannot modify restaurant B; KDS cannot read financial reports; revoked device/employee rejected; cashier cannot void a paid order without permission; platform-admin path unused or audited.
- [ ] **Hardware selected/frozen** (Q-006) and **connectivity frozen** (Q-015); units acquired, paired as device identities, **pre-flight tested off-site**.
- [ ] **Printing validated on the chosen model** — receipt + kitchen ticket print; ar/he/en raster fallback legible (RF-073, **Q-015/R-006**); duplicate-print prevention + reprint-audit verified (RF-071).
- [ ] **Money/jurisdiction safe** (Q-001/Q-007 frozen; tax Q-002/003/004 resolved or deferred) — **RISK R-008**: never run live money on an unfrozen tax model.
- [ ] **Offline window decided** (Q-009) so the outage test has defined expected behavior (**RISK R-007**).
- [ ] **Data handling agreed** (real-but-isolated; retention Q-005) and **backups/rollback confirmed** (OPERATIONS_AND_RECOVERY; RTO/RPO Q-013); rollback rehearsed.
- [ ] **Daily report dry run** — RF-075 produces a per-branch summary that reconciles.
- [ ] **Spare hardware on hand** (spare receipt printer + tablet).

> If any box is unchecked, the live day is **NO-GO** (see §12). As of [PILOT_READINESS.md](PILOT_READINESS.md), B1–B10 are open → currently NO-GO.

## 5. Environment checklist

- [ ] Pilot Supabase project provisioned (its own project; no other tenant's data present).
- [ ] Migrations applied + validated on that project (forward-only; never `db push` from this repo without Saleh).
- [ ] pgTAP/test database green.
- [ ] **No `service_role` key on any POS/KDS device** — devices use device identity + PIN session + Org-scoped RLS only (**DECISION D-011**).
- [ ] **No secrets committed** to the repo; `tools/check_secrets.sh` clean.
- [ ] Realtime (RF-058) treated as enhancement only (**DECISION D-010**), never the source of truth.

## 6. Data checklist (setup, local-only instructions; no committed seed/secrets)

- [ ] Org / restaurant / branch rows created with correct `timezone` on branch (and/or restaurant) for the daily-report day boundary (RF-075).
- [ ] Menu / services / items + modifiers configured (price + modifier snapshots at order time, **DECISION D-008**).
- [ ] Users / employees / memberships with correct roles (owner/manager/cashier/kitchen_staff); per-person identities only.
- [ ] Devices + stations registered and paired (device identities); station routing map for RF-072.
- [ ] Printer routing (which station → which printer) and **receipt configuration** (language ar/he/en, 58/80mm).
- [ ] **Cash drawer configuration** — drawer kicked via the receipt printer's drawer port on cash payment (RF-074).

## 7. Hardware checklist

- [ ] Receipt printer (one standardized ESC/POS model, **RISK R-001**) — loaded, reachable.
- [ ] Kitchen printer and/or KDS display.
- [ ] Cash drawer wired to the printer's drawer port.
- [ ] Spare paper rolls.
- [ ] Spare network + power (and an offline fallback plan for connectivity loss).
- [ ] Offline fallback ready (RestoFlow continues offline by design, **D-010**).
- [ ] **CURRENT BLOCKER (B1): real printer/drawer transport is not implemented** — `packages/printing` ships in-memory transport only; network/USB/Bluetooth throw `UnsupportedTransportException`. Physical printing/kick is **not possible** until the transport companion ticket lands. Until then, this checklist is rehearsal-only.

## 8. Manual pilot test script (run in order; capture evidence per §9)

1. **Login / device pairing** — pair the POS tablet as a device identity (short-lived enrollment code); confirm no shared account.
2. **PIN session** — cashier signs in with personal PIN on the paired device; confirm session scope.
3. **Menu load** — menu + modifiers visible.
4. **Submit order** — build a cart, submit; order `draft → submitted`; idempotency key recorded (**D-022**).
5. **KDS receive / bump / recall** — ticket appears at the routed station; `new → acknowledged → in_preparation → ready → bumped`; recall is audited.
6. **Apply discount with reason** — permission-gated; reason captured to `audit_events` (**D-013**).
7. **Void order with reason** — permission-gated; reason audited; cannot void a paid order (RF-062).
8. **Cash payment** — tender cash; **change due in integer minor units** (**D-007**); payment `pending → tendered → completed`.
9. **Receipt print** — prints in the order's language (ar/he/en, RTL correct), correct totals, per-branch monotonic receipt number (**D-021**).
10. **Cash drawer kick** — drawer opens once on the cash payment (RF-074; at-most-once, `drawer:<paymentId>`).
11. **Shift close / reconcile** — shift `opening→…→reconciled`, drawer `opened→…→reconciled`; counted vs expected variance recorded + explained (RF-055).
12. **Daily report reconciliation** — RF-075 report matches observed sales/voids/discounts (zero drift).
13. **Simulated outage / reconnect** — disconnect mid-service, keep taking orders + one cash payment offline, reconnect; outbox drains via idempotent inbox/ledger; provisional receipt numbers reconcile; **no duplicates** (**RISK R-002**).
14. **Revocation test** — revoke a test employee/device during the offline window; on reconnect it is rejected (RF-061, **RISK R-007**, Q-009).
15. **Role isolation test** — confirm KDS/kitchen_staff cannot read financial reports; confirm no cross-org/branch visibility (**RISK R-003**, S10).

## 9. Observability / evidence log

Capture for each step / success criterion (S1–S13):
- Screenshots of POS + KDS at each transition; printed **kitchen ticket and receipt samples** (all three languages).
- **Report totals** vs manual tally; **drawer variance notes** (counted − expected) with explanation.
- **Sync evidence** — outbox drained, revisions converged, zero duplicate orders/payments after the outage.
- **RLS isolation evidence** — denial screenshots/logs for KDS-reading-financials and cross-tenant attempts.
- Print spool state for any retry (`failed → retrying`); any `possiblyPrinted` job and how it was manually reviewed.
- A short **incident log** (time, symptom, action, outcome).

## 10. Incident handling

| Incident | Action |
|---|---|
| **Printer failure** | Soft rollback: continue on RestoFlow with a hand-written chit for that station; reprint (audited, RF-071) once restored. |
| **Drawer failure** | Open drawer manually; record; do not re-issue kicks (at-most-once). |
| **Sync failure** | Continue offline by design (**D-010**); do not force-retry payments; let the outbox drain on reconnect. |
| **Wrong report total** | Halt reporting use; preserve data; reconcile manually; file a Jira issue against RF-075; do not edit data to "fix" it. |
| **Suspected cross-tenant access** | **HALT THE PILOT IMMEDIATELY** (**RISK R-003**); preserve audit trail; capture evidence; NO-GO. |
| **Device lost / revoked** | Revoke the device identity; confirm it cannot sync new ops (RF-061); continue on remaining devices. |

## 11. Rollback (never lose data or weaken security)

1. **Soft rollback (preferred)** — one subsystem fails (e.g. printer): keep recording orders on RestoFlow, handle that subsystem manually; reprint/audited on restore.
2. **Offline / manual fallback** — connectivity fails: RestoFlow keeps working offline (**D-010**); sync drains on reconnect (this is normal operation, not a rollback).
3. **Hard stop** — a critical/security issue (cross-tenant anomaly, money corruption, unrecoverable crash): stop using RestoFlow for new orders, switch to the restaurant's manual process, **preserve all RestoFlow data and the audit trail** (no `reset --hard`, no DB reset, no deletion — **DECISION D-016**), capture logs, treat the day as NO-GO.
4. **Never** disable RLS and **never** delete audit/data to "clean up" (**DECISION D-013**, SECURITY REQUIREMENT).

## 12. Go / no-go decision

- **Decision owner:** Saleh (human), recorded in Jira (**D-015/D-016**); Claude Code is reviewer only.
- **GO** — all PILOT_PLAN §5 success criteria (S1–S13) met, with special weight on **S10** (no cross-tenant/security incident) and **S11** (sync recovery). Authorizes M4 (RF-090..094).
- **CONDITIONAL GO** — only minor, non-security defects, tracked into early M4 — never for security, money, or data-integrity defects.
- **NO-GO** — any security/isolation incident, money/rounding error, or data loss → automatic NO-GO; produces a prioritized fix list + re-pilot date; M4 does not start.
- **Required sign-offs:** human RLS/security sign-off (RF-059, **RISK R-003**); Saleh's go/no-go; pilot restaurant's informed agreement on money/tax handling.

## 13. Post-pilot review

- **Success metrics** — record S1–S13 outcomes + the agreed thresholds (0 money errors, 0 security incidents, ≤2 recoverable print retries/service, drawer variance fully explained).
- **Issues list** — every defect/anomaly with severity; security/money/data issues are blockers.
- **Follow-up tickets** — file in Jira against the relevant RF-0xx; include the [PILOT_READINESS.md](PILOT_READINESS.md) §8 companion tickets if still open.
- **M4 readiness** — only on a GO; otherwise schedule a re-pilot after the fix list closes.
