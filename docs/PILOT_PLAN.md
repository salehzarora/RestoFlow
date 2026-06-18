# PILOT_PLAN.md — RestoFlow M3 Hardware Pilot

> **Status — DRAFT (candidate), not yet frozen.** Drafted by Claude Code (RF-001) · pending ChatGPT review · pending independent Codex review · pending human approval (Saleh). Only the explicit RF-001 invariants (below/where cited) are binding requirements; every other architectural choice is a **PROPOSED DECISION** pending review and human approval. Architecture freeze happens only after independent review, required fixes, and Saleh's approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

> **Document ownership.** This document OWNS the M3 hardware pilot plan. It cites decisions from
> [DECISIONS.md](DECISIONS.md) and open questions from [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md);
> it does not redefine money/tax ([MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md)), security/isolation
> ([SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md)), sync ([OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md)),
> printing/hardware ([PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md)), state transitions
> ([STATE_MACHINES.md](STATE_MACHINES.md)), the backlog ([IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md)),
> or operations ([OPERATIONS_AND_RECOVERY.md](OPERATIONS_AND_RECOVERY.md)). It references them.
>
> Milestone context lives in [PROJECT_PLAN.md](PROJECT_PLAN.md); MVP boundaries in [MVP_SCOPE.md](MVP_SCOPE.md).

---

## 1. Purpose and objective

The M3 pilot proves that RestoFlow can run a **real, full service day in ONE real restaurant and ONE real
branch**, on real hardware, with real money and real staff — while running on the **multi-tenant architecture**
exactly as designed. The pilot is the go/no-go gate from M3 to M4 (sellable SaaS).

**Primary objective.** Operate a complete service day end to end: orders flow from the cashier (POS) to the
kitchen (KDS), kitchen tickets and customer receipts print correctly, cash payments are taken with correct change,
shifts and cash drawer sessions open/close and reconcile, a daily report is produced, and synchronization recovers
cleanly after a simulated network outage — with **no cross-tenant or security incident**.

> **SECURITY REQUIREMENT — no single-tenant shortcuts.** The pilot restaurant runs as a normal tenant:
> one `organization` containing one `restaurant` and one `branch`, with rows carrying `organization_id`
> (and `restaurant_id` / `branch_id` / `device_id` / `station_id` where relevant) per **DECISION D-001**
> and the hierarchy of **DECISION D-002**. The TENANT is the Organization (**DECISION D-003**); we do **not**
> regress to "restaurant = tenant", and we do **not** disable RLS, relax policies, embed a service-role key in
> the Flutter client, or create any shared account to "make the pilot easier". Any such shortcut is a pilot
> failure, not a convenience.

> **ASSUMPTION.** The pilot restaurant is owned by Saleh or a willing partner restaurant who has agreed to run a
> supervised live day. The legal jurisdiction is whatever **OPEN QUESTION Q-001** resolves to; the pilot cannot be
> scheduled until Q-001 is frozen (see Entry Criteria).

---

## 2. Scope of the pilot

### 2.1 In scope — MVP features exercised
The pilot exercises the MVP surface delivered through M1–M3. Each capability maps to its M3 (or earlier) ticket and
its owning specification.

| Capability exercised | State model / spec | Backing tickets |
|---|---|---|
| Cashier builds order in POS cart with **price + modifier snapshots** at order time (**DECISION D-008**) | Order: `draft -> submitted` ([STATE_MACHINES.md](STATE_MACHINES.md)) | RF-031, RF-052 |
| Order submission and order/order-item state machine (**DECISION D-018**) | `submitted -> accepted -> preparing -> ready -> served -> completed` | RF-032, RF-052 |
| Kitchen routing items → stations | Kitchen ticket / station item | RF-033, RF-072 |
| KDS displays tickets; bump and recall flows | Kitchen ticket: `new -> acknowledged -> in_preparation -> ready -> bumped`; `recalled` audited | RF-034, RF-072 |
| Table management (dine-in / takeaway) | Takeaway skips `served` (`ready -> completed`) | RF-035 |
| Money engine: integer **minor units**, discounts, totals (no floating point) (**DECISION D-007**) | [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md) | RF-036, RF-054 |
| Cash payment + change due; **per-branch monotonic receipt number** (**DECISION D-021**) | Payment: `pending -> tendered -> completed` (`completed` TERMINAL; void only pre-completion, **DECISION D-023**); payment & fulfillment independent, pay-first supported (**DECISION D-025**) | RF-054 |
| Apply discount / void order — permission-gated, reason required, **audited** (**DECISION D-013**) | `voided` is post-submission, terminal; `completed` order TERMINAL and void/cancel **REJECTED** once a completed payment exists (refund **DEFERRED**) (**DECISION D-023**, **D-024**) | RF-053 |
| Shift + cash drawer session open/close + reconciliation | Shift: `opening -> open -> closing -> closed -> reconciled`; Drawer: `opened -> active -> counting -> closed -> reconciled` | RF-037, RF-055 |
| Outbox push + server inbox/ledger; idempotency via `device_id + local_operation_id` (**DECISION D-022**) | [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md) | RF-056 |
| Pull sync + conflict resolution + revisions | Sync op: `created -> pending -> in_flight -> applied` | RF-057, RF-061 |
| Realtime KDS live updates (**enhancement only**, **DECISION D-010**) | — | RF-058 |
| Printing adapter + ESC/POS driver; print job spool + retry; duplicate-print prevention; reprint audited | Print job: `created -> queued -> printing -> printed`; `failed -> retrying`; `abandoned` | RF-070, RF-071 |
| Kitchen ticket printing routed per station | — | RF-072 |
| Customer receipt printing in ar/he/en, 58/80mm, RTL, raster fallback (**DECISION D-014**) | [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md) | RF-073 |
| Cash drawer kick on cash payment | — | RF-074 |
| Daily reports (sales, shift, voids/discounts) per branch | [PROJECT_PLAN.md](PROJECT_PLAN.md) | RF-075 |
| Tenant isolation holds live (Org-scoped RLS, membership/branch/device scoping) | [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) | RF-059, RF-060, RF-061 |

Identity used on-site (**DECISION D-004/D-005/D-006**): owner/manager personal accounts (MFA per
**OPEN QUESTION Q-008**), cashier/kitchen **personal employee identities** with PIN fast-sessions on a
**paired + authorized device** only, and **device identities** for each POS/KDS. No shared accounts.

### 2.2 Out of scope — DEFERRED for the pilot
- **DEFERRED** — Tips handling (**OPEN QUESTION Q-011**).
- **DEFERRED** — Refunds (Payment `refunded`) and any post-completion reversal; a `completed` payment cannot be voided/reversed (`completed` is TERMINAL, **DECISION D-023**). Card/non-cash payments are deferred; pilot is **cash only** (RF-054).
- **DEFERRED** — Self-serve org signup (RF-090), platform admin panel (RF-091), owner dashboard (RF-092),
  billing (RF-093) — these are M4.
- **DEFERRED** — Accountant / read-only role shipping decision (**OPEN QUESTION Q-017**); not required for the pilot.
- **DEFERRED** — Service-charge rules (**OPEN QUESTION Q-012**) unless Q-001/Q-002 force them in for the jurisdiction.

---

## 3. Hardware selection — OPEN QUESTION

> **OPEN QUESTION Q-006** — Pilot hardware selection (printer model(s), POS tablet, KDS display, cash drawer)
> is **not yet frozen** and must be resolved before the pilot is scheduled. Detailed model behavior, command sets,
> and the adapter contract are owned by [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md); this plan
> only records what the pilot needs and the decision the pilot depends on.

| Hardware role | What the pilot needs | Open question |
|---|---|---|
| Receipt printer | One **standardized** ESC/POS model, 58mm or 80mm, capable of ar/he RTL via raster fallback | **Q-006**, **Q-015**, **RISK R-001**, **RISK R-006** |
| Kitchen printer / KDS | Either a kitchen ticket printer (RF-072) and/or a KDS display screen (RF-034) | **Q-006** |
| POS tablet | One Flutter-capable tablet running the POS app as a registered **device identity** | **Q-006** |
| Cash drawer | Drawer kicked via the receipt printer's drawer port on cash payment (RF-074) | **Q-006** |
| Connectivity | Printer/drawer connection method (network / USB / Bluetooth) | **OPEN QUESTION Q-015** |

> **RISK R-001** (ESC/POS hardware variation) — mitigation: **standardize on exactly one printer model for the
> pilot** and keep the printing adapter abstraction (RF-070) replaceable.
> **RISK R-006** (Arabic/Hebrew printing/encoding) — mitigation: raster fallback (RF-073) validated **before**
> the live day, in all three languages, on the chosen model.

> **ASSUMPTION.** A spare unit of each critical device (one spare receipt printer, one spare tablet) is on hand for
> the live day to remove single-device failure from the critical path.

---

## 4. Entry criteria (must ALL be true before scheduling the live day)

The pilot **cannot start** until every item below holds. These gate M3 → live day.

1. **M2 complete.** Real backend + sync delivered: Auth + MFA (RF-050, **Q-008**), PIN sessions (RF-051),
   RPC `submit_order` / discount / void / payment / shift (RF-052–RF-055), outbox/inbox + pull/conflict
   (RF-056, RF-057), revocation propagation (RF-061).
2. **Isolation tests green.** The full tenant-isolation & permission suite passes (RF-059, RF-060) with the
   canonical cases from [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md): Org A cannot read Org B
   orders; Cashier A cannot modify Restaurant B; KDS cannot read financial reports; revoked device cannot sync
   new ops; removed employee cannot create valid ops; cashier cannot void a paid order without permission;
   platform-admin access explicitly audited. **RISK R-003** is CRITICAL: human RLS sign-off (RF-059) is mandatory.
3. **Printing works.** RF-070–RF-074 complete; receipt + kitchen ticket print on the **chosen Q-006 model**, with
   ar/he/en raster fallback validated (RF-073, **Q-015**), duplicate-print prevention and reprint-audit verified.
4. **Hardware frozen.** **OPEN QUESTION Q-006** resolved; **OPEN QUESTION Q-015** resolved; units acquired,
   paired as device identities, and pre-flight tested off-site.
5. **Money/jurisdiction safe.** **OPEN QUESTION Q-001** (jurisdiction) and **OPEN QUESTION Q-007** (currency)
   frozen; tax handling (**Q-002**, fiscal **Q-003/Q-004**) either resolved or explicitly **DEFERRED** with the
   restaurant's informed agreement. **RISK R-008**: do not run live money on an unfrozen tax model.
6. **Offline window decided.** **OPEN QUESTION Q-009** (offline authorization / PIN validity window) frozen so the
   simulated-outage test has a defined expected behavior (**RISK R-007**).
7. **Data handling agreed.** Real-but-isolated data plan signed off (Section 7), retention per **OPEN QUESTION Q-005**.
8. **Daily report works.** RF-075 produces a per-branch daily summary in a dry run.
9. **Rollback ready.** Manual fallback (Section 8) rehearsed; backups confirmed per
   [OPERATIONS_AND_RECOVERY.md](OPERATIONS_AND_RECOVERY.md) (RTO/RPO **OPEN QUESTION Q-013**).

---

## 5. Success criteria (measurable)

The live day is a **GO** to M4 only if every criterion is met and evidence is captured.

| # | Success criterion | Measure / evidence |
|---|---|---|
| S1 | Full service day completed | One continuous service period (open → close) operated on RestoFlow |
| S2 | Orders flow cashier → kitchen | Each order reaches KDS; ticket states progress `new → … → bumped` with no stuck tickets |
| S3 | Kitchen ticket printed | Ticket prints at the correct station for every routed order (RF-072); 0 missing tickets |
| S4 | Receipt printed correctly | Customer receipt prints in the order's language (ar/he/en, RTL correct), legible, correct totals (RF-073) |
| S5 | Cash payment + change | Cash tendered, **change due computed in integer minor units** (D-007); drawer kicks (RF-074); 0 money math errors |
| S6 | Receipt numbering correct | **Per-branch monotonic** sequence (D-021), no gaps/duplicates; offline provisional reconciled to authoritative on sync |
| S7 | Void / discount controlled | Every void/discount permission-gated, reason captured, written to append-only `audit_events` (D-013); 0 unauthorized voids |
| S8 | Shift + drawer reconcile | Shift `opening→…→reconciled` and drawer `opened→…→reconciled`; counted cash variance recorded and explained |
| S9 | Daily report produced | RF-075 report matches observed sales/voids/discounts for the branch |
| S10 | **No cross-tenant / security incident** | 0 cross-org data exposure, 0 IDOR, platform-admin path unused or audited (**RISK R-003**) |
| S11 | Sync recovers after outage | Simulated network outage during service; POS keeps working offline; on reconnect outbox drains, **no duplicate orders/payments** (idempotency D-022), revisions converge (**RISK R-002**) |
| S12 | Revocation honored | A test employee/device revoked during the offline window is rejected on reconnect (RF-061, **RISK R-007**, **Q-009**) |
| S13 | Stability | No data loss; crash recovery (if any) restores local state cleanly; no print-spool deadlock |

> **ASSUMPTION.** Acceptable thresholds (e.g. max acceptable print failures, max acceptable reconciliation variance)
> are agreed with the restaurant before the day. Defaults proposed: 0 money errors, 0 security incidents, ≤2
> recoverable print retries per service, drawer variance fully explained.

### 5.1 Simulated outage test (S11) — procedure
At a controlled moment mid-service: disconnect the branch from the internet (per **Q-015** connectivity), continue
taking several orders and one cash payment fully offline (SQLite/Drift local store, **DECISION D-010**), then
reconnect. Expected: outbox pushes via the idempotent server inbox/ledger (RF-056), receipt provisional ids
reconcile to authoritative per-branch numbers (D-021), and re-submitting the same op produces **no duplicate**.
Detailed rules are owned by [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md).

---

## 6. Training and on-site support

> **RISK R-005** (single-builder bus factor) — mitigation: every pilot step is documented here and in
> [OPERATIONS_AND_RECOVERY.md](OPERATIONS_AND_RECOVERY.md); Saleh is on-site for the live day; Codex performs the
> independent review of the pilot readiness; Git remains the source of truth for code (**DECISION D-015**).

- **Pre-day training.** Short hands-on session for cashier(s) and kitchen staff: PIN login on the paired device,
  building an order, sending to kitchen, taking cash + change, opening/closing a shift, bump/recall on KDS, and
  what the sync-status indicator means. Each trainee uses their **own personal employee identity** (D-004) — no
  shared logins.
- **On-site support.** Saleh (human owner) on-site for the entire live day with the runbook, spare hardware, and
  the rollback plan. Acts as the privileged operator for void/discount approvals and shift reconciliation.
- **Escalation.** A short incident log is kept; any security/isolation anomaly halts the pilot immediately
  (**RISK R-003**). Issue tickets are filed in Jira against the relevant RF-0xx ticket (D-015).

---

## 7. Data handling (real but isolated)

- **Real data, real tenant, full isolation.** Pilot orders/payments are real transactions stored under the pilot
  Organization's `organization_id` with normal RLS and audit (**DECISION D-001**, **D-013**). No test/prod data
  mixing; no other tenant's data is present in the pilot project.
- **No PII beyond what MVP requires.** Customer personal data is not collected beyond order necessities.
  Staff identities are real employee profiles (D-005).
- **Retention.** Pilot data retention follows **OPEN QUESTION Q-005**; until Q-005 is frozen, pilot data is
  retained read-only and not purged so reconciliation/audit can be reviewed.
- **Backups.** Backups/restore per [OPERATIONS_AND_RECOVERY.md](OPERATIONS_AND_RECOVERY.md); DR targets are
  **OPEN QUESTION Q-013**.
- **SECURITY REQUIREMENT.** No service-role credentials on the POS/KDS tablets; access is via device identity +
  PIN session + Org-scoped RLS only (**DECISION D-006**, **D-011**).

---

## 8. Rollback plan

If RestoFlow cannot safely continue mid-service, fall back **without data loss or security compromise**.

1. **Soft rollback (preferred).** If a single subsystem fails (e.g. printer), continue on RestoFlow with manual
   handling of that subsystem (e.g. hand-written kitchen chit) while the rest of the system keeps recording orders;
   reprints are audited (RF-071) once the printer is restored.
2. **Offline continuation.** If connectivity fails, RestoFlow continues **offline by design** (D-010) — this is
   not a rollback, it is normal operation; sync drains on reconnect.
3. **Hard rollback.** If a critical or security issue appears (any cross-tenant anomaly, money corruption,
   unrecoverable crash), **stop using RestoFlow for new orders**, switch the restaurant to its existing/manual
   process, preserve all RestoFlow data (do **not** reset or delete — per **DECISION D-016** guardrails:
   no `reset --hard`, no database reset, no deletion of real data), capture logs and the audit trail, and treat the
   day as a NO-GO.
4. **Post-rollback.** Reconcile manual transactions against whatever RestoFlow captured; file Jira issues; root-cause
   before any re-attempt.

> **SECURITY REQUIREMENT.** A hard rollback never involves disabling RLS or deleting audit/data to "clean up".
> Preservation of the audit trail (**DECISION D-013**) is mandatory.

---

## 9. Go / no-go decision and exit to M4

- **Decision owner.** Human (Saleh) makes the final go/no-go call (**DECISION D-016**; ticket **RF-076** is
  human-owned with Claude Code as reviewer). The decision is recorded in Jira (**DECISION D-015**).
- **GO criteria.** All Section 5 success criteria met (S1–S13), with special weight on **S10** (no cross-tenant /
  security incident, **RISK R-003**) and **S11** (sync recovery, **RISK R-002**). A GO authorizes starting M4
  (RF-090 self-serve signup, RF-091 platform admin, RF-092 dashboards, RF-093 billing, RF-094 hardening).
- **NO-GO.** Any security/isolation incident, money/rounding error, or data loss is an automatic NO-GO regardless
  of other results. NO-GO produces a prioritized fix list (Jira) and a re-pilot date; M4 does not start.
- **CONDITIONAL GO.** Minor, non-security defects may yield a conditional GO with tracked fixes carried into early
  M4, at the human owner's discretion — never for security, money, or data-integrity defects.

---

## 10. M3 ticket reference

Pilot-relevant tickets from the master task list (full backlog: [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md)):

| Ticket | Title | Role in pilot |
|---|---|---|
| RF-070 | Printing adapter interface + ESC/POS driver | Replaceable adapter; mitigates **R-001** |
| RF-071 | Print job spool + state machine + retry + reprint audit | Duplicate-print prevention; reprint reason audited |
| RF-072 | Kitchen ticket printing routing | Per-station tickets (S3) |
| RF-073 | Customer receipt printing (ar/he/en, 58/80mm, raster fallback) | RTL receipts (S4); **Q-015**, **R-006** |
| RF-074 | Cash drawer kick | Drawer opens on cash payment (S5) |
| RF-075 | Daily reports (sales, shift, voids/discounts) | Per-branch daily summary (S9) |
| RF-076 | Pilot deployment in one restaurant/branch | This plan; full-day run; go/no-go (Section 9) |

Upstream dependencies exercised: RF-052/RF-053/RF-054 (RPCs), RF-055 (shift), RF-056/RF-057 (sync),
RF-059/RF-060/RF-061 (RLS + isolation + revocation).
