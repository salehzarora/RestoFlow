# RestoFlow — Project Plan

> **Status — DRAFT (candidate), not yet frozen.** Drafted by Claude Code (RF-001) · pending ChatGPT review · pending independent Codex review · pending human approval (Saleh). Only the explicit RF-001 invariants (below/where cited) are binding requirements; every other architectural choice is a **PROPOSED DECISION** pending review and human approval. Architecture freeze happens only after independent review, required fixes, and Saleh's approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

> **Scope of this document.** This file owns the **milestones, timeline, and ownership** view of RestoFlow. It describes *milestones*, not individual tickets. The authoritative per-ticket backlog lives in [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md) (human-readable) and [JIRA_IMPORT.csv](JIRA_IMPORT.csv) (import file). Decisions are owned by [DECISIONS.md](DECISIONS.md); open questions by [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md); risks by [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md). This document cites those IDs; it never redefines them.

---

## 1. Overview

RestoFlow is a **multi-tenant Restaurant Operating System** (not merely a POS). It must eventually connect POS stations (cashiers), Kitchen Display Systems (KDS), owner/manager dashboards, and platform administration, with offline operation, sync, printing, payments, shifts, and reporting — serving **many independent restaurant customers on one platform**. The first pilot may run one restaurant and one branch, but no schema, API, authorization policy, local database, or app architecture assumes that only one organization exists (**DECISION D-001**, **DECISION D-002**, **DECISION D-003**).

This plan carries forward the owner's v1.0 framing:

- **Five delivery milestones** taking the product from an approved (frozen) architecture to a sellable SaaS.
- **~24 weeks** of indicative duration (PROPOSED; see §2 — dates may change).
- **A team of 1 human + 3 AI agents** (see §3 and [AGENTS.md](../AGENTS.md)).
- **Offline-first by construction** — the POS keeps working with no internet; Supabase Realtime is an enhancement only (**DECISION D-010**).

**Change from v1.0:** the original single "M0" milestone is **split into M0A (documentation & architecture freeze candidate)** and **M0B (technical foundation)**. M0A produces only governance and architecture documents — a candidate set proposed for the **RF-004 freeze event**; M0B builds the runnable foundation with no business features (**DECISION D-019**).

The build method is **documentation-and-architecture-first** ("freeze before code"): the architecture documents and contracts are authored as a **candidate set proposed for the architecture freeze**, then independently reviewed and human-frozen before implementation begins. M0A produces this candidate set; the freeze itself occurs only after review, required fixes, and Saleh's approval. The first ticket, **RF-001**, authors this document set as a draft.

**ASSUMPTION:** team composition and indicative dates are stable enough to plan against; all dates remain PROPOSED until the M0A freeze gate (RF-004).

---

## 2. Milestones (DECISION D-019)

Indicative dates are **PROPOSED** (carried from the v1.0 plan) and may change at the freeze gate. Sequencing and dependencies are authoritative; calendar dates are not. The full ticket breakdown per milestone is in [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md) / [JIRA_IMPORT.csv](JIRA_IMPORT.csv).

### M0A — Documentation & Architecture Freeze Candidate

- **Goal:** produce the complete, internally consistent, decision-grade documentation set — a **candidate set proposed for the architecture freeze** — that the rest of the project is implemented against once approved. Freeze before code (the freeze itself is the **RF-004 freeze event**, which occurs after review and approval).
- **Key deliverables:** the full `docs/` set (this plan, [PRODUCT_SPEC.md](PRODUCT_SPEC.md), [MVP_SCOPE.md](MVP_SCOPE.md), [ARCHITECTURE.md](ARCHITECTURE.md), [DOMAIN_MODEL.md](DOMAIN_MODEL.md), [STATE_MACHINES.md](STATE_MACHINES.md), [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md), [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md), [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md), [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md), [API_CONTRACT.md](API_CONTRACT.md), [TESTING_STRATEGY.md](TESTING_STRATEGY.md), [OPERATIONS_AND_RECOVERY.md](OPERATIONS_AND_RECOVERY.md), [PILOT_PLAN.md](PILOT_PLAN.md), [DECISIONS.md](DECISIONS.md), [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md), [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md)); governance files ([AGENTS.md](../AGENTS.md), [TASK_TRACKER.md](TASK_TRACKER.md)); [JIRA_IMPORT.csv](JIRA_IMPORT.csv).
- **Definition of Done:** every document exists and is internally consistent with the shared canon; all D-xxx cited against [DECISIONS.md](DECISIONS.md) and all Q-xxx against [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md); Codex adversarial review (RF-002) finds no unresolved contradiction or silent assumption; blocking open questions are either resolved or set to "Accepted Open" under the four conditions (RF-003) or explicitly flagged as blocking their dependent tickets; human sign-off freezes the set at the **RF-004 freeze event** (gating the START of M0B). **CONSTRAINT:** no application code, Flutter apps, Dart packages, Supabase folders, SQL migrations, package manifests, or CI config are created in M0A.
- **Status:** RF-001 (authoring) done; RF-002 (Codex adversarial review) **complete** — verdict **APPROVE WITH CHANGES**; RF-003 (resolve approved findings + prepare the freeze candidate) **active**; RF-004 (human approval / freeze event) **pending**.
- **Blocker classification (DECISION D-027):** the **RF-004 human architecture approval** gates the **START of M0B as a milestone**. An individual open question blocks **only the tickets that depend on its answer**, not M0A completion or the freeze candidate as a whole. A question may be marked **"Accepted Open"** when all four conditions hold: (1) an owner is assigned; (2) the blocking ticket/milestone is identified; (3) a safe interim interface/config/placeholder/feature-flag exists; and (4) no irreversible schema/contract assumption is made. **RF-004 does NOT require all of Q-001..Q-024 to be resolved.**
- **Indicative dates (PROPOSED):** ~Jul 2026 (first half).
- **Primary agents:** Claude Code (author, RF-001); Codex (review, RF-002); ChatGPT + Human (decisions, RF-003); Human (freeze gate, RF-004).

### M0B — Technical Foundation

- **Goal:** stand up the runnable foundation — monorepo, CI, Supabase bootstrap, first multi-tenant migrations, RLS skeleton, Drift + outbox, localization + RTL — with **no business features**.
- **Key deliverables:** Melos monorepo skeleton; shared package scaffold (core/models/design/l10n); GitHub Actions CI (format/analyze/test); Supabase projects/environments/secrets (**SECURITY REQUIREMENT:** no service-role credentials in clients, per **DECISION D-011**); first multi-tenant migration (organizations/restaurants/branches) with baseline RLS and DB constraints (**DECISION D-012**); identity & membership schema (users, memberships, employee_profiles) per **DECISION D-004/D-005**; device identity, pairing, device/PIN sessions (**DECISION D-006**); append-only audit events (**DECISION D-013**); Drift local schema + outbox/inbox ledger with idempotency keys (**DECISION D-010/D-022**); localization framework ar/he/en + RTL/LTR (**DECISION D-014**).
- **Definition of Done:** monorepo builds and CI is green; first migrations apply with `organization_id` on every tenant-scoped table and baseline RLS present; a tenant-isolation test harness skeleton asserts cross-tenant denial; audit table immutable to app roles; local Drift schema + outbox/inbox in place; no business logic shipped.
- **Indicative dates (PROPOSED):** Jul 2026.
- **Primary agents:** Claude Code (implementation); Codex (review); Human (RLS / secrets / CI sign-off points — see §3).

### M1 — Local POS + KDS Prototype

- **Goal:** a working POS + KDS prototype on **local data only** (no real backend) to validate domain, state machines, and money math.
- **Key deliverables:** menu domain (categories/items/sizes/variants/modifiers) on Drift; POS cart + order build with price/modifier snapshots (**DECISION D-008**); order submission enforcing the PROPOSED order / order-item state machines (**DECISION D-018**, PROPOSED pending review — RF-001 §8 directs us to evaluate, not assume final); kitchen routing (items → stations); KDS screens with kitchen ticket / station-item state machines (bump/recall); basic table management (dine-in/takeaway); money calculation engine in integer minor units (**DECISION D-007**); shift + cash drawer session locally.
- **Definition of Done:** a cashier can build and submit an order offline against local storage; orders/items/tickets transition only along the PROPOSED enumerations in [STATE_MACHINES.md](STATE_MACHINES.md) (pending review and approval); all money math is integer minor-unit and matches [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md) (no floating point anywhere); KDS reflects ticket lifecycle; tests cover the state machines and money engine.
- **Indicative dates (PROPOSED):** Jul–Aug 2026.
- **Primary agents:** Claude Code (implementation); Codex (review).

### M2 — Real Backend + Synchronization

- **Goal:** connect to the real backend — Auth, RLS, RPC, outbox/inbox sync, conflict handling — with full tenant isolation.
- **Key deliverables:** Supabase Auth for owners/managers (personal accounts + MFA for privileged roles, **OPEN QUESTION Q-008**); PIN session flow on paired devices with attempt limits and offline validity window (**OPEN QUESTION Q-009**); sensitive mutations via PostgreSQL RPC — `submit_order` (idempotent via `device_id` + `local_operation_id`, **DECISION D-022**), `apply_discount` / `void_order` (authorize + reason + audit), cash payment RPC + per-branch monotonic receipt numbering (**DECISION D-021**), open/close shift + cash reconciliation; outbox push + server inbox/ledger with retry, backoff, and poison-operation handling; pull sync + per-entity conflict resolution + revisions (**OPEN QUESTION Q-010**); Realtime KDS enhancement (**DECISION D-010**); the **complete** RLS + membership/branch/device-scoped policy set (**DECISION D-012**); the mandatory tenant-isolation & permission test suite; device & employee revocation propagation including the offline window (**RISK R-007**).
- **Definition of Done:** all canonical isolation/permission tests pass (Org A cannot read Org B orders; cashier A cannot modify Restaurant B; KDS cannot read financial reports; a revoked device cannot sync new operations; a removed employee cannot create new valid operations; a cashier cannot void a paid order without permission; platform-admin access is explicitly audited); duplicate mutations are de-duplicated by the ledger; sensitive mutations are RPC-only and audited; **Human RLS sign-off recorded** (R-003 mitigation, CRITICAL).
- **Indicative dates (PROPOSED):** Aug–Sep 2026.
- **Primary agents:** Claude Code (implementation); Codex (review); Human (RLS sign-off, RF-059).

### M3 — Hardware Pilot

- **Goal:** run one real restaurant/branch on real hardware for a full day — ESC/POS printing, cash drawer, daily reports — and make a go/no-go call.
- **Key deliverables:** printing adapter interface + ESC/POS driver behind a replaceable adapter (**RISK R-001**); print job spool + state machine + retry + reprint audit (duplicate-print prevention); kitchen ticket printing routed per station; customer receipt printing ar/he/en at 58/80mm with raster/encoding fallback (**OPEN QUESTION Q-015**, **RISK R-006**); cash drawer kick on cash payment; daily reports (sales, shift, voids/discounts) per branch; on-site pilot deployment.
- **Definition of Done:** a full operating day completed on-site without data loss; receipts and tickets print correctly in all three languages with RTL where required; print job lifecycle follows [STATE_MACHINES.md](STATE_MACHINES.md); daily reports reconcile against shifts and cash drawer sessions; go/no-go decision recorded per [PILOT_PLAN.md](PILOT_PLAN.md).
- **Indicative dates (PROPOSED):** Sep–Oct 2026.
- **Primary agents:** Human (on-site lead, pilot deployment); Claude Code (implementation + on-site support); Codex (review).

### M4 — Sellable SaaS

- **Goal:** turn the pilot-proven system into a sellable multi-tenant SaaS — self-serve signup, platform admin, dashboards, basic billing, production hardening.
- **Key deliverables:** self-serve organization signup + onboarding (new org provisions itself, fully isolated); platform admin panel on a separate, explicitly audited path (platform-admin isolation); owner/manager dashboard across restaurants/branches; basic subscription/billing (**OPEN QUESTION Q-016**); production hardening — backups, monitoring, alerting, incident runbooks (**OPEN QUESTION Q-013**, see [OPERATIONS_AND_RECOVERY.md](OPERATIONS_AND_RECOVERY.md)).
- **Definition of Done:** a new organization can sign up and operate in isolation with no cross-tenant leakage; platform-admin actions are audited on the separate path; cross-branch reporting works; basic billing plans function; backups/monitoring/runbooks are live with stated RPO/RTO targets.
- **Indicative dates (PROPOSED):** Oct–Dec 2026.
- **Primary agents:** Claude Code (implementation); Codex (review); Human (billing & production hardening sign-off).

---

## 3. Team & Ownership

The team is **1 human owner (Saleh) + 3 AI agents**. Permissions and guardrails are detailed in [AGENTS.md](../AGENTS.md); the pipeline is **ChatGPT planning → Human approval → Claude Code implementation → Tests → Codex independent review → Claude Code fixes → Human approval → Merge** (**DECISION D-016**). **Only the human owner (Saleh) performs the merge.**

| Workstream | Primary | Reviewer | Human decision point |
|---|---|---|---|
| Docs / Architecture (M0A) | Claude Code | Codex | Architecture & contracts freeze (RF-004) |
| Decision / Planning | ChatGPT + Human | Human | Resolve blocking open questions; approve plans |
| Foundation / Infra (monorepo, CI, l10n) | Claude Code | Codex (CI: Human) | CI gate sign-off |
| Backend / DB (migrations, RPC, reports) | Claude Code | Codex | First-migration & RLS review |
| Security (auth, RLS, audit, revocation) | Claude Code | Codex (full RLS: Human) | **Human RLS sign-off (R-003, CRITICAL)** |
| Sync / Offline (outbox/inbox, conflicts) | Claude Code | Codex | Conflict-policy approval (Q-010) |
| Frontend / POS | Claude Code | Codex | — |
| Frontend / KDS | Claude Code | Codex | — |
| Hardware / Printing | Claude Code | Codex | Pilot go/no-go (Human, M3) |
| QA / Testing (isolation suite) | Claude Code | Codex | Isolation suite pass before merge |
| Platform / SaaS | Claude Code | Codex (billing/hardening: Human) | Billing & production sign-off |
| Operations | Claude Code | Human | Backup/DR targets approval (Q-013) |

**RISK R-005 (single-builder bus factor):** mitigated by documenting every decision, independent Codex review, and Git as the source of truth for code.

---

## 4. Agent Permissions Summary

Detailed agent capabilities, prohibitions, and worktree rules live in [AGENTS.md](../AGENTS.md). Summary of the binding guardrails (**DECISION D-016**):

- Claude Code and Codex must **not** edit the same working tree simultaneously; Codex reviews **read-only** by default.
- Parallel implementation requires **separate branches + worktrees**; one active ticket per worktree; every task has a ticket ID.
- Shared-package and API-contract changes need **dedicated tickets**.
- **No agent may push without human approval.** No force push. No `reset --hard`. No database reset. No deletion of real data. No production changes. No secret disclosure. No silent scope expansion (**RISK R-004**).
- **SECURITY REQUIREMENT:** no service-role credentials in Flutter clients; no shared restaurant password (**DECISION D-011**, **DECISION D-004**).

---

## 5. Sources of Truth (DECISION D-015)

- **Jira (project key RF)** — official source of truth for **task status**.
- **Git** — official source of truth for **code and change history**.
- **Architecture documents (`docs/`)** — official source of truth for **technical decisions and contracts**.
- **[TASK_TRACKER.md](TASK_TRACKER.md)** — the single tracker, located at `docs/TASK_TRACKER.md`; **only** a concise current-session resume file; **not** a duplicate backlog. The master task list lives in [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md) + [JIRA_IMPORT.csv](JIRA_IMPORT.csv). This plan describes milestones, not tickets.

Recommended Jira workflow states: Backlog → Ready → In Progress → Code Review → Changes Requested → Ready for Merge → Done; plus Blocked, Deferred, Cancelled.

---

## 6. Risks Summary

Risks are owned and expanded in [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md); blocking unknowns are owned by [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md). This table is a pointer view, not the register.

| ID | Risk | Primary milestone(s) | Mitigation (summary) |
|---|---|---|---|
| **R-001** | ESC/POS hardware variation | M3 | Standardize one printer model in pilot; replaceable adapter abstraction. |
| **R-002** | Offline sync conflicts / duplicates | M2 | Idempotency keys + outbox/inbox ledger, tested in M2. |
| **R-003** | RLS correctness — cross-tenant data leak (**CRITICAL**) | M0B, M2 | Mandatory isolation tests + **human RLS sign-off**. |
| **R-004** | Scope creep into deferred features | All | Frozen scope ([MVP_SCOPE.md](MVP_SCOPE.md)) + human gate; no silent scope expansion. |
| **R-005** | Single-builder bus factor | All | Document every decision; independent Codex review; Git source of truth. |
| **R-006** | Arabic/Hebrew printing/encoding correctness | M3 | Raster fallback; pilot validation (**Q-015**). |
| **R-007** | Offline authorization staleness (revoked employee/device acting offline) | M2 | Short offline validity window (**Q-009**); server rejects on reconnect; audit. |
| **R-008** | Money/rounding/tax errors before jurisdiction frozen | M1+ | Integer minor units; keep tax open until **Q-001..Q-004** resolved. |

**Blocking open questions for the M0A freeze and beyond** (resolved under RF-003 where possible): **Q-001** jurisdiction, **Q-007** currency, **Q-006**/**Q-015** pilot hardware shortlist, **Q-008** MFA method/roles, **Q-009** offline validity window. Tax-related questions (**Q-002**, **Q-003**, **Q-004**) remain open until the jurisdiction is frozen and gate M1+ money/tax finalization. See [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) for owners and blocking milestones.
