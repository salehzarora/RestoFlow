# RestoFlow — Implementation Checklist (Master Task Backlog)

> **Status — FROZEN: M0A architecture baseline, approved at RF-004.** Authored under RF-001, independently reviewed by Codex (RF-002), corrected under RF-003, and verified in a final Codex pass; the architecture freeze was **approved by the human owner, Saleh, at RF-004**. The explicit RF-001 invariants remain binding; decisions **D-001..D-028** are the frozen M0A baseline. Open questions **Q-001..Q-024** remain **Accepted Open** (per **DECISION D-027** — tracked, gating only their dependent tickets; none resolved or guessed). Changes to this frozen baseline now require the architecture-change procedure (a new ticket, independent review, and human approval). Any remaining inline pre-freeze status notes are superseded by this RF-004 approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

**Status:** M0A FROZEN baseline (authored RF-001; approved at RF-004). **Owner of this document:** this file (`IMPLEMENTATION_CHECKLIST.md`) together with [JIRA_IMPORT.csv](JIRA_IMPORT.csv) is the frozen, human-readable MASTER task backlog per **DECISION D-015**.

> **DECISION D-015** — Sources of truth: Jira (project key `RF`) = task *status*; Git = code/history; `docs/` = technical decisions/contracts; [TASK_TRACKER.md](TASK_TRACKER.md) = concise session-resume file only. This checklist and `JIRA_IMPORT.csv` are the only two full backlogs. **[TASK_TRACKER.md](TASK_TRACKER.md) must NOT duplicate this list.** [PROJECT_PLAN.md](PROJECT_PLAN.md) describes milestones, not individual tickets.

This document is **M0A documentation only**. It plans work; it does not create code, migrations, package manifests, or CI. Forward-looking design text describing *future* tasks is intentional.

---

## How to read this checklist (legend)

Each task is rendered as a self-contained block with the following fields:

| Field | Meaning |
|---|---|
| **ID** | Stable ticket id `RF-<number>`. Never reused or renumbered. |
| **Title** | Canonical task title (semantically matches `JIRA_IMPORT.csv`; the CSV omits internal commas in some titles). |
| **Milestone** | One of M0A, M0B, M1, M2, M3, M4 (**DECISION D-019**). |
| **Workstream** | Lane for parallelization/ownership grouping. |
| **Owner** | Primary doer (Claude Code / Codex / ChatGPT/Human / Human). |
| **Reviewer** | Independent reviewer (Codex or Human). Per **DECISION D-016**, owner and reviewer are never the same; Codex reviews read-only. |
| **Priority** | Highest / High / Medium / Low. |
| **Dependencies** | Earlier ticket ids that must reach "Ready for Merge"/"Done" first. Empty for RF-001. Acyclic — see [Dependency integrity](#dependency-integrity). |
| **Scope** | Concise statement of what is in this ticket, derived from the canon + master-list note. |
| **Acceptance criteria** | 2–4 **measurable, testable** checks. "Done" = all pass + reviewer sign-off. |
| **Required tests** | The test artifacts that must exist/pass for this ticket. |
| **Allowed files/areas** | *Guidance only* on where code is expected to land (e.g. `supabase/migrations`, `packages/sync`). Not a hard gate; final layout is owned by [ARCHITECTURE.md](ARCHITECTURE.md). |
| **Architecture impact** | none/low/medium/high + note. Touching shared packages or API contracts needs a dedicated ticket (**DECISION D-016**). |
| **Security impact** | none/low/medium/high + note. Anything touching RLS, RPC, auth, audit, or tenant isolation is at least medium. |

**MARKERS** used in this document follow the shared canon: **DECISION D-xxx**, **ASSUMPTION**, **OPEN QUESTION Q-xxx**, **DEFERRED**, **RISK R-xxx**, **SECURITY REQUIREMENT**. IDs are cited from [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md); this document never invents new D/Q/R ids.

**Cross-cutting non-negotiables (apply to every task; not repeated per block):**
- No assumption that only one organization/restaurant/branch exists (**DECISION D-001, D-002, D-003**).
- No shared accounts; roles are membership-scoped (**DECISION D-004, D-005**).
- Money is integer **minor** units only; **no floating point anywhere** (**DECISION D-007**). Money columns suffixed `_minor`.
- No service-role credentials in Flutter clients; no shared restaurant password (**SECURITY REQUIREMENT**, **DECISION D-011**).
- PROPOSED state enumerations (approved into the frozen M0A baseline (RF-004); RF-001 §8 directs us to evaluate, not assume final) (**DECISION D-018**, owned by [STATE_MACHINES.md](STATE_MACHINES.md)).
- Naming per **DECISION D-017** ([ARCHITECTURE.md](ARCHITECTURE.md), [DOMAIN_MODEL.md](DOMAIN_MODEL.md)).
- No agent may push without human approval; no force push / reset --hard / db reset / data deletion (**DECISION D-016**).

---

## Milestone summary

| Milestone | Theme | Tickets |
|---|---|---|
| **M0A** | Documentation & architecture freeze candidate | RF-001 .. RF-004 |
| **M0B** | Technical foundation (no business features) | RF-010 .. RF-021 |
| **M1** | Local POS + KDS prototype (local data) | RF-030 .. RF-037 |
| **M2** | Real backend + synchronization | RF-050 .. RF-061 |
| **M3** | Hardware pilot | RF-070 .. RF-076 |
| **M4** | Sellable SaaS | RF-090 .. RF-094 |

Indicative timeline is **PROPOSED** and owned by [PROJECT_PLAN.md](PROJECT_PLAN.md) (M0 ~Jul 2026 → M4 Oct–Dec 2026). Scope in/out is owned by [MVP_SCOPE.md](MVP_SCOPE.md).

**Backlog totals: 6 epics + 48 tasks** (one epic per milestone M0A..M4 — note M0 spans two epics, `RF-EPIC-M0A` and `RF-EPIC-M0B`; 48 individual tickets RF-001..RF-004, RF-010..RF-021, RF-030..RF-037, RF-050..RF-061, RF-070..RF-076, RF-090..RF-094). [JIRA_IMPORT.csv](JIRA_IMPORT.csv) contains exactly the same 6 epics + 48 tasks. The two files MUST stay in sync.

> **Jira field-mapping note (guidance, NOT a blocker; do not run a Jira import in M0A):** For Jira Free / team-managed projects, the CSV columns may not map automatically. Expect to set **Issue Type** (Epic/Story/Task), **Epic Link** (the `RF-EPIC-*` parent), **Labels**, and **Components** manually or via the import field-mapping step. The `Blocked By` column maps to the "is blocked by" link type. This is import-tooling guidance only and does not gate any ticket.

> **DEFERRED scope check:** Tips (**Q-011**), refunds (Payment `refunded` state), multi-currency-per-order, and subscription billing logic beyond a basic plan are **DEFERRED**. None of these appear as an M1–M3 deliverable below. Billing appears only at M4 (RF-093) and is explicitly "basic" (**Q-016**). The Payment state machine's `refunded` state is **DEFERRED** per **DECISION D-018** and is not implemented by any task here.

---

# Milestone M0A — Documentation & Architecture Freeze Candidate

> The M0A document set is a **DRAFT freeze candidate**. The freeze **event** (tagging the set as frozen v1) is owned by **RF-004** and requires human architecture approval; this milestone produces the candidate, not the freeze itself.

### RF-001 — M0A Project Foundation and Architecture Documentation
- **Milestone:** M0A · **Workstream:** Docs/Architecture · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** Highest · **Status:** Done
- **Dependencies:** — (none; this is the root ticket)
- **Scope:** Author all M0A governance + architecture documents from the shared canon: [DECISIONS.md](DECISIONS.md), [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md), [PRODUCT_SPEC.md](PRODUCT_SPEC.md), [MVP_SCOPE.md](MVP_SCOPE.md), [ARCHITECTURE.md](ARCHITECTURE.md), [DOMAIN_MODEL.md](DOMAIN_MODEL.md), [STATE_MACHINES.md](STATE_MACHINES.md), [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md), [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md), [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md), [API_CONTRACT.md](API_CONTRACT.md), [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md), [TESTING_STRATEGY.md](TESTING_STRATEGY.md), [PROJECT_PLAN.md](PROJECT_PLAN.md), this checklist, [JIRA_IMPORT.csv](JIRA_IMPORT.csv), [OPERATIONS_AND_RECOVERY.md](OPERATIONS_AND_RECOVERY.md), [PILOT_PLAN.md](PILOT_PLAN.md), [TASK_TRACKER.md](TASK_TRACKER.md). **Docs only — no code.**
- **Acceptance criteria:**
  1. Every document listed in the canon's "AUTHORITATIVE DOCUMENT OWNERSHIP" section exists under `docs/` (or repo root where specified) and is non-empty.
  2. Every proposed enumeration (**DECISION D-018**), every decision id D-001..D-028, and every open question Q-001..Q-024 is referenced by at least one document; no document invents a conflicting D/Q id.
  3. No document contradicts the tenant hierarchy (**D-002**) or asserts single-tenant assumptions; grep for "Restaurant = Tenant" returns zero authoritative uses.
  4. No application code, migration, package manifest, or CI file is created in this milestone.
- **Required tests:** Manual editorial cross-check (markers present where relevant); link-integrity pass (no broken relative links between docs). No automated test harness in M0A.
- **Allowed files/areas:** `docs/**` (including `docs/TASK_TRACKER.md`), repo-root governance files. *Guidance.*
- **Architecture impact:** high — defines all contracts the codebase is built against.
- **Security impact:** high — defines the security model, RLS strategy, and isolation test canon (**DECISION D-011, D-012, D-013**, **RISK R-003**).

### RF-002 — Codex independent review of M0A documentation
- **Milestone:** M0A · **Workstream:** QA/Review · **Owner:** Codex · **Reviewer:** Human · **Priority:** Highest · **Status:** Done (complete; verdict APPROVE WITH CHANGES)
- **Dependencies:** RF-001
- **Scope:** Read-only adversarial review of every M0A doc for contradictions, gaps, and security/sync rigor. No edits to the working tree (**DECISION D-016**).
- **Acceptance criteria:**
  1. A written review enumerates each document and records pass/fail with specific line/section references.
  2. Every found contradiction, silent assumption, or unresolved gap is filed as either an **OPEN QUESTION Q-xxx** candidate or a follow-up ticket id — none left implicit.
  3. Security & sync sections are checked against the canonical isolation tests and the proposed sync states (approved into the frozen M0A baseline (RF-004)); review explicitly confirms or rejects coverage of each canonical isolation test.
  4. Reviewer makes no commits and opens no branches (read-only confirmed by clean working tree).
- **Required tests:** N/A (review artifact). Output is a review report consumed by RF-003/RF-004.
- **Allowed files/areas:** none (read-only). *Guidance.*
- **Architecture impact:** none (review only).
- **Security impact:** high — gates the security model before any code (**RISK R-003**, **R-005**).

### RF-003 — Resolve M0A blocking OPEN QUESTIONS
- **Milestone:** M0A · **Workstream:** Decision · **Owner:** ChatGPT/Human · **Reviewer:** Human · **Priority:** High · **Status:** Done (Q-001..Q-024 recorded **Accepted Open** per D-027; none resolved/guessed)
- **Dependencies:** RF-002
- **Scope:** Decide the M0A-blocking open questions: **Q-001** jurisdiction, **Q-007** currency, **Q-006**/**Q-015** pilot hardware shortlist, **Q-008** MFA method/roles, **Q-009** offline authorization validity window. Record outcomes in [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) and promote to **DECISION D-xxx** in [DECISIONS.md](DECISIONS.md) where a choice is frozen. Per **DECISION D-027** (M0B blocker rule), each open question may end in one of two acceptable states: **Resolved**, or explicitly **"Accepted Open"**. An "Accepted Open" question is permissible only when it has a named owner, the blocking ticket/milestone it gates is identified, a safe interim behavior exists, and no irreversible assumption is baked in; in that case it blocks only the dependent ticket(s), not the milestone start.
- **Acceptance criteria:**
  1. Each of Q-001, Q-006, Q-007, Q-008, Q-009, Q-015 has a recorded status in [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) of either **Resolved** OR **"Accepted Open"** (with named owner, identified blocking ticket/milestone, documented safe interim, and no irreversible assumption) per **DECISION D-027**.
  2. Every resolved item is reflected as a frozen decision (new or amended D-xxx) and any dependent spec ([MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md), [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md), [PILOT_PLAN.md](PILOT_PLAN.md)) cites it.
  3. Items not resolved remain explicitly marked **OPEN QUESTION** in the **"Accepted Open"** state with a named owner and blocking ticket/milestone — none silently closed, and none marked Resolved without a recorded decision.
- **Required tests:** N/A (decision artifact); editorial consistency check that no doc still leaves a now-resolved question open and that every still-open question carries an "Accepted Open" record.
- **Allowed files/areas:** `docs/OPEN_QUESTIONS.md`, `docs/DECISIONS.md`, dependent specs. *Guidance.*
- **Architecture impact:** medium — resolutions may constrain money/tax, auth, and pilot hardware design.
- **Security impact:** medium — Q-008 (MFA) and Q-009 (offline window) directly shape auth and **RISK R-007**.

### RF-004 — Freeze architecture & contracts v1
- **Milestone:** M0A · **Workstream:** Decision · **Owner:** Human · **Reviewer:** — · **Priority:** High · **Status:** Done — **APPROVED by Saleh; M0A architecture baseline FROZEN as v1**
- **Dependencies:** RF-002, RF-003
- **Scope:** Human sign-off; tag the M0A document set as **frozen v1**; this is the freeze **event** that opens the gate to begin M0B. No code. Per **DECISION D-027**, the gate does **not** require that every open question be Resolved; it requires human architecture approval plus each still-open question being either Resolved or in the **"Accepted Open"** state.
- **Acceptance criteria:**
  1. A signed-off freeze record exists (commit tag / Jira transition) naming the exact doc versions frozen, with explicit human architecture approval recorded.
  2. This gate does **NOT** require all of Q-001..Q-024 to be resolved. It requires (a) human architecture approval, AND (b) every still-open question being either **Resolved** or recorded as **"Accepted Open"** per **DECISION D-027** (named owner, identified blocking ticket/milestone, safe interim, no irreversible assumption). An "Accepted Open" question blocks only its dependent ticket(s), not the milestone start.
  3. M0B tickets (RF-010, RF-013) are moved from Backlog to Ready in Jira only after this gate.
- **Required tests:** N/A (governance gate).
- **Allowed files/areas:** docs + Git tag. *Guidance.*
- **Architecture impact:** high — establishes the frozen baseline implemented against.
- **Security impact:** high — freezes the security/RLS/audit contracts before implementation.

---

# Milestone M0B — Technical Foundation (no business features)

### RF-010 — Initialize Melos monorepo skeleton
- **Milestone:** M0B · **Workstream:** Foundation/Infra · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-004
- **Scope:** Create the Melos workspace and the app/package layout per [ARCHITECTURE.md](ARCHITECTURE.md) (**DECISION D-009**). No business code.
- **Acceptance criteria:**
  1. `melos bootstrap` completes with zero errors on a clean checkout.
  2. The app/package directory layout matches [ARCHITECTURE.md](ARCHITECTURE.md) exactly (apps + shared packages stubs present).
  3. `melos run analyze` runs across all packages and reports no missing-package errors.
- **Required tests:** Smoke check that the workspace resolves; no domain tests yet.
- **Allowed files/areas:** repo root (`melos.yaml`, `pubspec.yaml` workspace), `apps/`, `packages/`. *Guidance.*
- **Architecture impact:** high — establishes the monorepo structure.
- **Security impact:** none.

### RF-011 — Shared packages scaffold (core, models, design, l10n)
> **Clarification (RF-011, Option A — human-approved 2026-06-19; wording only, frozen architecture unchanged):** The names `models`/`design` in this entry are **aliases** for the packages already frozen in [ARCHITECTURE.md](ARCHITECTURE.md) §3 and created in RF-010 — **`models` = `packages/domain`**, **`design` = `packages/design_system`**; no `packages/models` or `packages/design` is created. Per **DECISION D-007** and ARCHITECTURE §3, the integer minor-unit **money TYPE is owned by `packages/money` (ticket RF-036)**, not `domain`; acceptance criterion 2's money type is therefore **deferred to RF-036**, and RF-011 instead enforces the no-floating-point-money invariant repo-wide via `tools/check_no_float_money.sh` plus an integer-only convention. The integer-based money **unit test** moves with the money type to RF-036.
- **Milestone:** M0B · **Workstream:** Foundation/Infra · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-010
- **Scope:** Create empty shared packages (`core`, `models`, `design`, `l10n`) exposing public interfaces only — no business logic. Shared-package changes are dedicated tickets (**DECISION D-016**).
- **Acceptance criteria:**
  1. Each of the four packages exists, builds, and exports a documented public surface.
  2. `models` defines money as integer `_minor` types only — a static check/grep proves no `double`/`float` money type exists (**DECISION D-007**).
  3. No package depends on Supabase service-role keys or secrets (**SECURITY REQUIREMENT**).
- **Required tests:** Per-package `flutter analyze` passes; a unit test asserting the money value type is integer-based.
- **Allowed files/areas:** `packages/core`, `packages/models`, `packages/design`, `packages/l10n`. *Guidance.*
- **Architecture impact:** high — shared API surface used by all apps.
- **Security impact:** low — establishes no-secret-in-client convention.

### RF-012 — CI pipeline (analyze, test, build)
- **Milestone:** M0B · **Workstream:** Foundation/Infra · **Owner:** Claude Code · **Reviewer:** Human · **Priority:** High
- **Dependencies:** RF-010
- **Scope:** GitHub Actions running format/analyze/test gates on PRs (**DECISION D-009**).
- **Acceptance criteria:**
  1. A PR with a formatting violation fails CI; a clean PR passes — both demonstrated.
  2. CI runs `format`, `analyze`, and `test` stages and blocks merge on any failure.
  3. CI contains no secrets in plaintext and no service-role key (**SECURITY REQUIREMENT**).
- **Required tests:** CI self-test (a deliberately failing branch shows red; main shows green).
- **Allowed files/areas:** `.github/workflows/`. *Guidance.*
- **Architecture impact:** low.
- **Security impact:** low — secret handling in CI.

### RF-013 — Supabase project bootstrap + environments + secrets
- **Milestone:** M0B · **Workstream:** Backend/DB · **Owner:** Claude Code · **Reviewer:** Human · **Priority:** High
- **Dependencies:** RF-004
- **Scope:** Create Supabase projects/environments and secrets handling. **SECURITY REQUIREMENT:** no service-role key in any client (**DECISION D-011**).
- **Acceptance criteria:**
  1. Separate dev and staging/prod environments exist with distinct credentials.
  2. A scan/checklist confirms only `anon`/publishable keys reach clients; the service-role key exists only in server-side/CI secret storage.
  3. Secrets are referenced via environment/secret store, never committed to Git (grep of history shows no service-role key).
- **Required tests:** Connectivity smoke test against dev env; secret-leak scan in CI.
- **Allowed files/areas:** `supabase/` config, environment/secret config. *Guidance.*
- **Architecture impact:** medium — backend environments.
- **Security impact:** high — credential isolation (**DECISION D-011**, **SECURITY REQUIREMENT**).

### RF-014 — First multi-tenant migration (orgs/restaurants/branches) + RLS skeleton
- **Milestone:** M0B · **Workstream:** Backend/DB · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** Highest
- **Dependencies:** RF-013
- **Scope:** First multi-tenant migration for `organizations`, `restaurants`, `branches` (+ `stations` as needed) with `organization_id` on every tenant-scoped table, baseline RLS, and DB constraints (**DECISION D-001, D-002, D-012, D-017**). Schema fields owned by [DOMAIN_MODEL.md](DOMAIN_MODEL.md); policies owned by [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md).
- **Acceptance criteria:**
  1. Every tenant-scoped table carries a non-null `organization_id` and a `uuid` primary key named `id`; verified by schema introspection.
  2. RLS is **enabled** on every new table; a query without a valid tenant context returns zero rows.
  3. An RLS test proves Org A cannot read Org B `restaurants`/`branches` rows.
  4. Naming matches **DECISION D-017** (snake_case, plural tables, `created_at`/`updated_at`, `deleted_at` tombstones where sync-relevant per **DECISION D-020**).
- **Required tests:** RLS isolation test (cross-org read denied); migration up/down applies cleanly; constraint tests (FK + not-null).
- **Allowed files/areas:** `supabase/migrations/`. *Guidance.*
- **Architecture impact:** high — foundational schema.
- **Security impact:** high — primary tenant-isolation boundary (**DECISION D-001**, **RISK R-003 CRITICAL**).

### RF-015 — Identity & membership schema + RLS
- **Milestone:** M0B · **Workstream:** Backend/DB · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** Highest
- **Dependencies:** RF-014
- **Scope:** `app_users`, `memberships`, `employee_profiles`, role keys, with membership-scoped RLS. Keep the six identity concepts distinct (**DECISION D-005**). Tenant membership role keys (**DECISION D-026**): `org_owner, restaurant_owner, manager, cashier, kitchen_staff, accountant` (accountant gated by **Q-017**). **`platform_admin` is NOT a membership role** (**DECISION D-026**); the identity schema includes a **separate `platform_admin_grants` table** (no `organization_id`; see [DOMAIN_MODEL.md](DOMAIN_MODEL.md) §3.7) that conveys platform-admin authority through a distinct, explicitly audited path — never through `memberships`.
- **Acceptance criteria:**
  1. `memberships` carry role(s) scoped to organization (and optionally restaurant/branch); a user can hold memberships in 2+ organizations in a fixture without leaking data across them.
  2. No table stores a single permanent global role on the user (**DECISION D-004**); verified by schema review.
  3. RLS test proves a cashier membership in Restaurant A cannot read/modify Restaurant B rows.
  4. `employee_profiles` are distinct from `app_users` and `memberships` (separate tables, FK relations) per **DECISION D-005**.
  5. `platform_admin` is not an accepted `memberships` role value (constraint/check rejects it); platform-admin authority is carried only by the separate `platform_admin_grants` table (no `organization_id`) per **DECISION D-026** (verified by schema review). Full platform-admin enforcement/audit tests are owned by RF-019/RF-060.
- **Required tests:** Multi-org membership isolation test; role-scoping RLS test; schema-distinctness assertion; assertion that `platform_admin` is not a valid membership role and that `platform_admin_grants` exists as a separate table with no `organization_id` (**DECISION D-026**).
- **Allowed files/areas:** `supabase/migrations/`. *Guidance.*
- **Architecture impact:** high — identity model.
- **Security impact:** high — access-control foundation (**DECISION D-004, D-005**).

### RF-016 — Device identity, pairing, device/pin sessions + RLS
- **Milestone:** M0B · **Workstream:** Backend/DB · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-015
- **Scope:** `devices`, `device_pairings` (expiring enrollment codes), `device_sessions`, `pin_sessions` (**DECISION D-005, D-006**). Device pairing follows the proposed state machine `code_issued -> pending -> paired -> active -> suspended -> revoked` plus `code_expired`, `rejected` (**DECISION D-018**; PROPOSED, approved into the frozen M0A baseline (RF-004)).
- **Acceptance criteria:**
  1. Enrollment codes are short-lived; a test proves an expired code transitions to `code_expired` and cannot complete pairing.
  2. A device identity is separate from any human identity and has limited permissions (**SECURITY REQUIREMENT**); verified by schema + RLS test.
  3. A `pin_session` can only exist layered on an `active` device session of a paired+authorized device; a PIN session on a non-paired device is rejected by constraint/policy.
  4. Device pairing rows obey the proposed enumeration (no status outside **DECISION D-018** is insertable).
- **Required tests:** Pairing-expiry test; device-isolation RLS test; PIN-session-requires-active-device-session test.
- **Allowed files/areas:** `supabase/migrations/`. *Guidance.*
- **Architecture impact:** medium — device/session model.
- **Security impact:** high — device auth, no shared accounts (**DECISION D-006**).

### RF-017 — Append-only audit events + enforcement
- **Milestone:** M0B · **Workstream:** Security · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-014
- **Scope:** `audit_events` table + triggers/RPC capturing actor, device, organization, restaurant, branch, timestamp, action, reason, old/new values; immutable to app roles (**DECISION D-013**).
- **Acceptance criteria:**
  1. An UPDATE or DELETE on `audit_events` by any app role is rejected (append-only proven by test).
  2. A recorded event contains all required context fields (actor, device, org, restaurant, branch, timestamp, action, reason, old_values, new_values).
  3. Audit rows carry `organization_id` and are RLS-isolated like other tenant data; cross-org audit read is denied.
- **Required tests:** Immutability test (update/delete denied); field-completeness test; cross-tenant audit isolation test.
- **Allowed files/areas:** `supabase/migrations/`. *Guidance.*
- **Architecture impact:** medium.
- **Security impact:** high — tamper-evident audit (**DECISION D-013**).

### RF-018 — Drift local schema + outbox/inbox tables
- **Milestone:** M0B · **Workstream:** Sync/Offline · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-011
- **Scope:** Local SQLite/Drift schema, outbox, processed-operation ledger, idempotency keys (`device_id + local_operation_id`), client/server timestamps, revision/version, tombstones (**DECISION D-010, D-020, D-022**). Sync contract owned by [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md).
- **Acceptance criteria:**
  1. Outbox rows carry an idempotency key `(device_id, local_operation_id)` with a uniqueness constraint; duplicate insert is rejected (**DECISION D-022**).
  2. Money fields in the local schema are integer `_minor` only — no floating-point column exists (**DECISION D-007**).
  3. Sync-relevant deletes are tombstones (`deleted_at`), not hard deletes (**DECISION D-020**); verified by schema.
  4. Sync-operation rows obey the proposed enumeration `created -> pending -> in_flight -> applied` (+ `rejected`, `dead`, `conflict -> resolved`) (**DECISION D-018**).
- **Required tests:** Idempotency-uniqueness test; tombstone-vs-hard-delete test; money-type integer assertion.
- **Allowed files/areas:** `packages/sync`, `packages/core` (local db). *Guidance.*
- **Architecture impact:** high — offline-first foundation.
- **Security impact:** medium — local store handling; no secrets persisted in clear.

### RF-019 — Tenant-isolation test harness (RLS suite skeleton)
- **Milestone:** M0B · **Workstream:** QA/Testing · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-014
- **Scope:** Harness asserting cross-tenant denial with seeded multi-org fixtures. Strategy owned by [TESTING_STRATEGY.md](TESTING_STRATEGY.md); isolation canon owned by [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md). The harness must be extensible to the platform-admin separation tests (**SECURITY T-008..T-011**, **DECISION D-026**): a membership cannot grant platform-admin; a platform-admin grant is not a membership; platform-admin access is audited; the privileged platform-admin path is enforced. (Skeleton here; full implementation at RF-060.)
- **Acceptance criteria:**
  1. Fixtures seed at least two organizations, each with ≥1 restaurant and ≥1 branch, plus members per org.
  2. The harness runs in CI and fails the build if any cross-tenant read/write succeeds.
  3. Harness covers at minimum the "Org A cannot read Org B" case and is extensible to the full canonical isolation set including the platform-admin separation cases **SECURITY T-008..T-011** (**DECISION D-026**), completed at RF-060.
- **Required tests:** The harness *is* the test; a deliberately broken policy makes the suite red (negative control). Includes fixture/scaffolding for the platform-admin separation cases (**SECURITY T-008..T-011**).
- **Allowed files/areas:** `test/`, `packages/*/test`, CI integration. *Guidance.*
- **Architecture impact:** low.
- **Security impact:** high — guards **RISK R-003** continuously.

### RF-020 — Localization framework (ar/he/en) + RTL/LTR scaffolding
- **Milestone:** M0B · **Workstream:** Foundation/Infra · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** Medium
- **Dependencies:** RF-011
- **Scope:** `arb`/intl setup and directionality plumbing for Arabic, Hebrew, English with full RTL/LTR (**DECISION D-014**).
- **Acceptance criteria:**
  1. App resolves locales `ar`, `he`, `en`; switching to `ar`/`he` flips layout direction to RTL (widget test).
  2. A missing translation key fails the build or is reported (no silent English fallback in release config).
  3. No hardcoded user-facing strings remain in the scaffolded surfaces (lint/check passes).
- **Required tests:** Widget test asserting `Directionality` per locale; arb-completeness check across the three locales.
- **Allowed files/areas:** `packages/l10n`, app shells. *Guidance.*
- **Architecture impact:** medium — l10n plumbing used app-wide.
- **Security impact:** none.

### RF-021 — Local data-at-rest protection & device secret handling
- **Milestone:** M0B · **Workstream:** Security · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-013, RF-018
- **Scope:** Establish secure storage for device/session secrets and protection of local operational data at rest. Evaluate and implement encrypted Drift/SQLite at rest, documenting platform support and limitations; define key lifecycle (creation/storage/rotation/revocation); define **fail-closed** behavior when platform secure storage is unavailable. No secrets in logs; no plaintext sensitive-data fallback without explicit human approval. Align with [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) and [OPERATIONS_AND_RECOVERY.md](OPERATIONS_AND_RECOVERY.md). Builds on RF-013 (Supabase bootstrap + secrets) and RF-018 (Drift local schema + outbox).
- **Acceptance criteria:**
  1. Data-at-rest encryption is enabled where the platform supports it, with documented limitations where it does not.
  2. Device/session secrets are stored only in platform secure storage — never in plaintext and never in logs.
  3. A documented key lifecycle exists covering create / store / rotate / revoke.
  4. Behavior is **fail-closed** when secure storage is unavailable (the device does not silently fall back to insecure operation).
  5. No plaintext sensitive-data fallback exists without explicit human approval.
- **Required tests:** Data-at-rest encryption test where technically possible; secret-handling + log-redaction test proving no secrets appear in logs; fail-closed behavior test when secure storage is unavailable.
- **Allowed files/areas:** `packages/core` (secure storage, local db), `packages/sync`. *Guidance.*
- **Architecture impact:** medium — secure-storage and at-rest-encryption layer for the local store.
- **Security impact:** high — protects device/session secrets and local data at rest; fail-closed posture (**SECURITY REQUIREMENT**, **RISK R-007**).

---

# Milestone M1 — Local POS + KDS Prototype (local data, no real backend)

### RF-030 — Menu domain (categories/items/sizes/variants/modifiers) — local
- **Milestone:** M1 · **Workstream:** Frontend/POS · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-018
- **Scope:** Local Drift-backed menu model + repository: `menu_categories`, `menu_items`, `item_sizes`, `item_variants`, `modifiers`, `modifier_options` (**DECISION D-017**). Entities owned by [DOMAIN_MODEL.md](DOMAIN_MODEL.md).
- **Acceptance criteria:**
  1. Menu entities persist locally and carry `organization_id` (+ `restaurant_id`/`branch_id` where relevant) even in single-pilot fixtures (**DECISION D-001**).
  2. Prices stored as integer `_minor` with currency reference (**DECISION D-007**, currency per **Q-007**).
  3. Repository CRUD round-trips through Drift with a passing unit test; tombstone delete supported (**DECISION D-020**).
- **Required tests:** Repository round-trip tests; money-integer assertion; tenant-field-present assertion.
- **Allowed files/areas:** `packages/models`, `packages/core`, POS app menu module. *Guidance.*
- **Architecture impact:** medium.
- **Security impact:** low — local data, tenant fields enforced.

### RF-031 — POS cart + order build — local
- **Milestone:** M1 · **Workstream:** Frontend/POS · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-030
- **Scope:** Fast cashier cart capturing **price snapshots and modifier price snapshots at add-to-cart time** (**DECISION D-008**). Order/order-item totals via the money engine (RF-036).
- **Acceptance criteria:**
  1. Adding an item snapshots its price and modifier prices; later menu price changes do not alter the existing cart line (test).
  2. Cart line and order totals are computed in integer minor units with no floating point (**DECISION D-007**).
  3. Cart supports order-level and item-level entries consistent with [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md).
- **Required tests:** Snapshot-immutability test; integer-total test.
- **Allowed files/areas:** POS app cart module, `packages/models`. *Guidance.*
- **Architecture impact:** medium.
- **Security impact:** low.

### RF-032 — Order submission + order/order-item state machines — local
- **Milestone:** M1 · **Workstream:** Frontend/POS · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-031
- **Scope:** Enforce the proposed enumerations locally (**DECISION D-018**; PROPOSED, approved into the frozen M0A baseline (RF-004)). Order: `draft -> submitted -> accepted -> preparing -> ready -> served -> completed` (+ `cancelled`, `voided`) — ONE shared chain for both order types (the draft "takeaway skips `served`" clause is **superseded** by RESTAURANT-OPERATIONS-V1-001, review B3). Order item: `pending -> queued -> preparing -> ready -> served` (+ `voided`, `cancelled`). Transitions owned by [STATE_MACHINES.md](STATE_MACHINES.md).
- **Acceptance criteria:**
  1. Illegal transitions are rejected (e.g. `draft -> completed` throws) — table-driven test covers all legal/illegal transitions.
  2. `voided` requires authorization + reason even in the local prototype (placeholder authorization), and is post-submission only.
  3. `cancelled` is only reachable pre-production; terminal states (`completed`, `cancelled`, `voided`) accept no further transitions.
  4. *(Superseded by review B3 — was "Takeaway orders never enter `served`".)* Takeaway orders pass through `served` (customer pickup, displayed "Picked up") exactly like dine-in; direct `ready -> completed` is rejected for every order type.
- **Required tests:** Exhaustive state-transition test for order and order-item enumerations.
- **Allowed files/areas:** `packages/models` (state machine), POS app. *Guidance.*
- **Architecture impact:** medium.
- **Security impact:** low — void authorization is fully enforced server-side at RF-053.

### RF-033 — Kitchen routing (items -> stations) — local
- **Milestone:** M1 · **Workstream:** Frontend/KDS · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** Medium
- **Dependencies:** RF-032
- **Scope:** Routing rules mapping order items to kitchen stations, producing `kitchen_tickets` and `kitchen_station_items` locally.
- **Acceptance criteria:**
  1. A submitted order routes each item to exactly one station per the configured rule; unroutable items are flagged, not dropped (test).
  2. Generated `kitchen_station_items` carry `organization_id`, `restaurant_id`, `branch_id`, `station_id`.
  3. Routing is deterministic for a given menu+rule fixture (idempotent re-route produces identical result).
- **Required tests:** Routing-correctness test; tenant/station field-presence test.
- **Allowed files/areas:** KDS module, `packages/models`. *Guidance.*
- **Architecture impact:** low.
- **Security impact:** low.

### RF-034 — KDS screens + kitchen ticket/station state machines — local
- **Milestone:** M1 · **Workstream:** Frontend/KDS · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-033
- **Scope:** KDS screens with bump/recall flows. Kitchen ticket: `new -> acknowledged -> in_preparation -> ready -> bumped` (+ `recalled` = `bumped -> in_preparation`, audited; `cancelled`). Kitchen station item: `queued -> in_preparation -> ready -> bumped` (+ `voided`) (**DECISION D-018**).
- **Acceptance criteria:**
  1. Bump moves a ticket to `bumped`; recall returns `bumped -> in_preparation` and writes an audit event placeholder (**DECISION D-013** target).
  2. Illegal ticket/station transitions are rejected (table-driven test).
  3. KDS layout renders correctly in RTL (`ar`/`he`) and LTR (`en`) (**DECISION D-014**, widget test).
- **Required tests:** Ticket + station state-transition tests; recall-audit test; RTL/LTR widget test.
- **Allowed files/areas:** KDS app, `packages/models`, `packages/design`. *Guidance.*
- **Architecture impact:** medium.
- **Security impact:** low.

### RF-035 — Table management (dine-in/takeaway) basic
- **Milestone:** M1 · **Workstream:** Frontend/POS · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** Medium
- **Dependencies:** RF-031
- **Scope:** `tables` plus order type (dine-in/takeaway) selection.
- **Acceptance criteria:**
  1. An order is assignable to a `table` (dine-in) or marked takeaway. *(Superseded by review B3 — the clause "takeaway orders are flagged to skip `served`" no longer applies: both types share `ready -> served -> completed`, takeaway `served` = pickup, displayed "Picked up".)*
  2. `tables` carry `organization_id`, `restaurant_id`, `branch_id`.
  3. A table cannot host two concurrent open dine-in orders unless explicitly allowed by config (test).
- **Required tests:** Table-assignment test; order-type-flag test.
- **Allowed files/areas:** POS app tables module, `packages/models`. *Guidance.*
- **Architecture impact:** low.
- **Security impact:** low.

### RF-036 — Money calculation engine (minor units, discounts, totals)
- **Milestone:** M1 · **Workstream:** Backend/DB · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-030
- **Scope:** Pure integer math engine for line totals, order-level & item-level discounts (percentage & fixed), rounding rules, and totals. Matches [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md). Distinguishes void vs cancellation vs refund (refund **DEFERRED**, **Q-011 tips DEFERRED**). Tax remains open pending **Q-001..Q-004** (**RISK R-008**).
- **Acceptance criteria:**
  1. All arithmetic is integer minor units; a static check proves zero `double`/`float` usage in the engine (**DECISION D-007**).
  2. Percentage and fixed discounts (order-level and item-level) match the rounding rules in [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md) for a golden-value table (test).
  3. Sum of line totals minus discounts equals the order total for every fixture (no rounding drift > 0 minor units beyond the documented rule).
  4. Tax is not hardcoded; engine exposes a configurable hook left disabled until **Q-002** is resolved.
- **Required tests:** Golden-value discount/rounding tests; no-float static assertion; total-reconciliation property test.
- **Allowed files/areas:** `packages/core` money engine. *Guidance.*
- **Architecture impact:** medium — used by cart, payment, reports.
- **Security impact:** low — correctness-critical (**RISK R-008**).

### RF-037 — Shift + cash drawer session — local
- **Milestone:** M1 · **Workstream:** Frontend/POS · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** Medium
- **Dependencies:** RF-031
- **Scope:** Local open/close shift, opening float, and cash reconciliation. Shift: `opening -> open -> closing -> closed -> reconciled`. Cash drawer session: `opened -> active -> counting -> closed -> reconciled`, bound to a shift (**DECISION D-018**).
- **Acceptance criteria:**
  1. A cash drawer session is always bound to exactly one shift; an unbound session is rejected (test).
  2. Opening float and counted amounts are integer `_minor`; variance = counted − expected computed in integer minor units (**DECISION D-007**).
  3. Illegal shift/drawer transitions are rejected (table-driven test); terminal `reconciled` accepts no further transitions.
- **Required tests:** Shift + drawer state-transition tests; variance integer-math test; binding-constraint test.
- **Allowed files/areas:** POS app shift module, `packages/models`. *Guidance.*
- **Architecture impact:** low.
- **Security impact:** low — server reconciliation enforced at RF-055.

---

# Milestone M2 — Real Backend + Synchronization

### RF-050 — Supabase Auth (owners/managers personal + MFA)
- **Milestone:** M2 · **Workstream:** Security · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** Highest
- **Dependencies:** RF-015
- **Scope:** Email/password personal accounts for owners/managers with MFA for privileged/sensitive roles (**DECISION D-006**; MFA method/roles per **Q-008**). No shared accounts (**DECISION D-004**).
- **Acceptance criteria:**
  1. A privileged-role login (e.g. `org_owner`, `manager`) without completed MFA is denied access to privileged operations (test, once **Q-008** method frozen).
  2. Each human has an individual account; no shared login exists in any fixture (**DECISION D-004**).
  3. Auth principal maps to `app_users` and resolves memberships at session time (**DECISION D-005**).
- **Required tests:** MFA-required-for-privileged test; per-person-identity test; membership-resolution test.
- **Allowed files/areas:** auth config, `packages/core` auth. *Guidance.*
- **Architecture impact:** medium.
- **Security impact:** high — human auth + MFA (**DECISION D-006**, **Q-008**).

### RF-051 — PIN session flow on paired device
- **Milestone:** M2 · **Workstream:** Security · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-016, RF-050
- **Scope:** PIN-based fast staff session **only** on a paired+authorized device, with attempt limits and an offline validity window (**Q-009**). Layered on the device session (**DECISION D-006**).
- **Acceptance criteria:**
  1. A PIN session cannot be established on an unpaired/revoked device (test) (**RISK R-007**).
  2. PIN attempts are rate-limited; after the configured max failures the PIN is locked (test).
  3. Offline PIN/permission validity respects the **Q-009** window; an expired offline window forces re-auth (test once window frozen).
- **Required tests:** Unpaired-device-rejection test; attempt-limit test; offline-window-expiry test.
- **Allowed files/areas:** auth module, `packages/core`. *Guidance.*
- **Architecture impact:** medium.
- **Security impact:** high — staff fast-auth, offline staleness (**RISK R-007**, **Q-009**).

### RF-052 — RPC submit_order (idempotent)
- **Milestone:** M2 · **Workstream:** Backend/DB · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** Highest
- **Dependencies:** RF-014, RF-032
- **Scope:** SECURITY DEFINER RPC to submit an order, idempotent via `device_id + local_operation_id` (**DECISION D-011, D-022**). Contract owned by [API_CONTRACT.md](API_CONTRACT.md).
- **Acceptance criteria:**
  1. Submitting the same `(device_id, local_operation_id)` twice creates exactly one order and returns the same result (idempotency test) (**DECISION D-022**).
  2. The RPC authorizes the caller's membership/scope before writing; a caller without rights in the target org/branch is rejected (test).
  3. Submitted order persists price snapshots from the client and never recomputes from live menu prices (**DECISION D-008**).
  4. All money fields written are integer `_minor` (**DECISION D-007**).
- **Required tests:** Idempotency test; authorization test; snapshot-preservation test.
- **Allowed files/areas:** `supabase/migrations/` (RPC), `packages/sync` (caller). *Guidance.*
- **Architecture impact:** high — core write path.
- **Security impact:** high — sensitive mutation via RPC (**DECISION D-011, D-012**).

### RF-053 — RPC apply_discount / void_order (authorize + audit)
- **Milestone:** M2 · **Workstream:** Security · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** Highest
- **Dependencies:** RF-017, RF-052
- **Scope:** Permission-gated, reason-required, audited RPCs for applying discounts and voiding orders (**DECISION D-011, D-012, D-013, D-018**).
- **Acceptance criteria:**
  1. A cashier without void permission cannot void a paid order; the attempt is rejected and audited (canonical isolation test) (**RISK R-003** family).
  2. `void_order` requires a non-empty reason and writes an append-only `audit_events` row with old/new values (**DECISION D-013**).
  3. Discount amounts are integer `_minor` and obey [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md) rounding; void moves the order to `voided` only from legal source states (**DECISION D-018**).
- **Required tests:** Unauthorized-void-denied test; reason-required test; audit-row-written test; state-transition legality test.
- **Allowed files/areas:** `supabase/migrations/` (RPC). *Guidance.*
- **Architecture impact:** medium.
- **Security impact:** high — privileged mutation + audit (**DECISION D-013**).

### RF-054 — RPC payment (cash) + receipt numbering
- **Milestone:** M2 · **Workstream:** Backend/DB · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-052, RF-036
- **Scope:** Cash payment RPC with **per-branch monotonic server-assigned receipt sequence** (offline provisional id reconciled to authoritative on sync) and change-due calculation (**DECISION D-021, D-022**). Payment: `pending -> tendered -> completed` (+ `voided`, `failed`; `refunded` **DEFERRED**) (**DECISION D-018**).
- **Acceptance criteria:**
  1. Receipt numbers are strictly monotonic and unique **per branch**; a concurrency test issuing N parallel payments yields N gapless/ordered numbers per the documented rule (**DECISION D-021**).
  2. A provisional offline receipt id reconciles to the authoritative server number on sync without duplication (test).
  3. Change due = tendered − total, integer `_minor`, never negative for an accepted payment (test) (**DECISION D-007**).
  4. Payment honors the proposed state machine; `refunded` is not implemented (**DEFERRED**).
- **Required tests:** Per-branch monotonic-sequence concurrency test; offline-reconciliation test; change-due integer test.
- **Allowed files/areas:** `supabase/migrations/` (RPC). *Guidance.*
- **Architecture impact:** medium.
- **Security impact:** medium — financial mutation, idempotent (**DECISION D-022**).

### RF-055 — RPC open/close shift + cash reconciliation
- **Milestone:** M2 · **Workstream:** Backend/DB · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-037
- **Scope:** Server RPCs for shift open/close and cash-drawer reconciliation enforcing the shift and cash-drawer-session state machines (**DECISION D-018**). Per **DECISION D-028**, this single ticket delivers **two separate RPCs** with distinct authorization: **`close_shift`** (callable by the owning `cashier` or an authorized `manager`) closes/counts the shift's bound cash-drawer session; **`reconcile_shift`** (callable by `manager`/`restaurant_owner`/`org_owner`) performs the reconciliation/variance approval. The `accountant` role is **read-only** and may invoke neither mutation. (One ticket, two RPCs — **do not split**.)
- **Acceptance criteria:**
  1. `close_shift` requires its bound cash-drawer session to be counted and is restricted to the owning cashier or an authorized manager; variance is computed server-side in integer `_minor` (test). `reconcile_shift` is restricted to manager/restaurant_owner/org_owner; an `accountant` (read-only) is rejected from both RPCs (**DECISION D-028**, test).
  2. Shift and drawer transitions follow the proposed enumerations; illegal transitions are rejected server-side (test).
  3. Reconciliation (`reconcile_shift`) writes an audit trail of opening float, expected, counted, and variance (**DECISION D-013** target).
- **Required tests:** `close_shift` vs `reconcile_shift` role-authorization tests (incl. accountant read-only denied for both); shift/drawer transition legality test; variance integer-math test; reconciliation-audit test.
- **Allowed files/areas:** `supabase/migrations/` (RPC). *Guidance.*
- **Architecture impact:** medium.
- **Security impact:** medium.

### RF-056 — Outbox push + server inbox/ledger (idempotent)
- **Milestone:** M2 · **Workstream:** Sync/Offline · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** Highest
- **Dependencies:** RF-018, RF-052
- **Scope:** Push local outbox to a server inbox/processed-operation ledger; dedupe via ledger; retry with backoff; poison-operation handling (**DECISION D-010, D-022**). Owned by [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md).
- **Acceptance criteria:**
  1. Replaying the same operation key `(device_id, local_operation_id)` is applied exactly once (ledger dedupe test) (**RISK R-002**).
  2. A transient failure retries with backoff; a poison operation transitions to `dead` after max retries and stops retrying (**DECISION D-018**).
  3. Dependent operations are applied in order; out-of-order arrival does not corrupt state (test).
- **Required tests:** Exactly-once ledger test; retry/backoff + poison-to-`dead` test; dependency-ordering test.
- **Allowed files/areas:** `packages/sync`, `supabase/migrations/` (inbox/ledger). *Guidance.*
- **Architecture impact:** high — sync backbone.
- **Security impact:** medium — server validates actor/scope on apply.

### RF-057 — Pull sync + conflict resolution + revisions
- **Milestone:** M2 · **Workstream:** Sync/Offline · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-056
- **Scope:** Pull sync with per-entity conflict-resolution policy (**Q-010**) and revision/version tracking (**DECISION D-010, D-020**).
- **Acceptance criteria:**
  1. Concurrent edits to the same entity from two devices resolve per the documented per-entity policy (**Q-010**); the loser's change is not silently lost (audited/recorded) (test).
  2. Tombstoned deletes propagate on pull; a deleted entity does not reappear (**DECISION D-020**, test).
  3. Revision/version monotonically increases per entity; stale-write attempts are rejected (test).
- **Required tests:** Conflict-policy test per entity class; tombstone-propagation test; stale-revision-rejection test.
- **Allowed files/areas:** `packages/sync`, `supabase/migrations/`. *Guidance.*
- **Architecture impact:** high.
- **Security impact:** medium.

### RF-058 — Realtime enhancement (KDS live updates)
- **Milestone:** M2 · **Workstream:** Sync/Offline · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** Medium
- **Dependencies:** RF-057
- **Scope:** Supabase Realtime as an **enhancement only** for KDS live updates — never the source of truth or only sync mechanism (**DECISION D-010**). Provider limits/fallback polling per **Q-014**.
- **Acceptance criteria:**
  1. With Realtime disabled, KDS still receives updates via pull sync (test proves Realtime is non-essential) (**DECISION D-010**).
  2. Realtime channels are tenant-scoped; a subscriber in Org A receives no Org B events (isolation test) (**RISK R-003**).
  3. On Realtime drop, the client falls back to polling at the **Q-014** interval without data loss (test).
- **Required tests:** Realtime-optional test; channel-isolation test; fallback-polling test.
- **Allowed files/areas:** `packages/sync`, KDS app. *Guidance.*
- **Architecture impact:** low — enhancement layer.
- **Security impact:** medium — channel isolation (**RISK R-003**).

### RF-059 — Full RLS + membership/branch/device-scoped policies
- **Milestone:** M2 · **Workstream:** Security · **Owner:** Claude Code · **Reviewer:** Human · **Priority:** Highest
- **Dependencies:** RF-014, RF-015, RF-016
- **Scope:** Complete policy set across all tenant tables: membership/role + branch/device scoping; platform-admin isolation as a separate, explicitly audited path (**DECISION D-011, D-012, D-013**). Requires **human RLS sign-off**.
- **Acceptance criteria:**
  1. Every tenant-scoped table has explicit SELECT/INSERT/UPDATE/DELETE policies; a coverage check finds no table with RLS enabled but no policy.
  2. Branch/device-scoped roles cannot read/write outside their scope (tests for cashier, kitchen_staff, device identity).
  3. Platform-admin access uses a separate path and every access writes an audit event (**DECISION D-013**).
  4. Human reviewer signs off on the policy set (governance gate, **RISK R-003 CRITICAL**).
- **Required tests:** Policy-coverage test; per-role scope tests; platform-admin-audited-path test.
- **Allowed files/areas:** `supabase/migrations/` (policies). *Guidance.*
- **Architecture impact:** medium.
- **Security impact:** high — complete isolation surface (**DECISION D-012**, **RISK R-003**).

### RF-060 — Tenant-isolation & permission test suite (mandatory cases)
- **Milestone:** M2 · **Workstream:** QA/Testing · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** Highest
- **Dependencies:** RF-059
- **Scope:** Implement the full canonical isolation/permission test set from [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) on the RF-019 harness, including the platform-admin separation tests **SECURITY T-008..T-011** (**DECISION D-026**): a membership cannot grant platform-admin; a platform-admin grant is not a membership; platform-admin access is audited; the privileged platform-admin path is enforced.
- **Acceptance criteria:**
  1. All canonical cases pass: Org A cannot read Org B orders; Cashier A cannot modify Restaurant B; KDS cannot read financial reports; a revoked device cannot sync new operations; a removed employee cannot create new valid operations; a cashier cannot void a paid order without permission; platform-admin access is explicitly audited.
  2. The platform-admin separation tests pass (**SECURITY T-008..T-011**, **DECISION D-026**): a `memberships` row cannot confer platform-admin; a `platform_admin_grants` row is not a membership; every platform-admin access writes an audit event; the privileged platform-admin path is enforced (no tenant-role bypass).
  3. The suite runs in CI and blocks merge on any failure.
  4. A deliberately broken policy makes the suite red (negative control documented).
- **Required tests:** The seven canonical isolation/permission tests above plus the platform-admin separation tests **SECURITY T-008..T-011**, all green in CI.
- **Allowed files/areas:** `test/`, `packages/*/test`. *Guidance.*
- **Architecture impact:** low.
- **Security impact:** high — the gate for **RISK R-003 CRITICAL**.

### RF-061 — Device & employee revocation propagation (incl. offline)
- **Milestone:** M2 · **Workstream:** Security · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-016, RF-057
- **Scope:** On reconnect, the server rejects operations from a revoked device or removed employee; future access is removed even within the offline window (**Q-009**, **RISK R-007**, **DECISION D-018** device pairing `revoked`).
- **Acceptance criteria:**
  1. A revoked device's queued offline operations are rejected on sync and recorded; no new state is created from them (test) (**RISK R-007**).
  2. A removed employee cannot create new valid operations after removal; existing completed records are untouched (test).
  3. Revocation propagates to clients so the offline window cannot exceed **Q-009**; expired cached permissions force re-auth (test).
- **Required tests:** Revoked-device-reject-on-sync test; removed-employee-no-new-ops test; offline-window-bound test.
- **Allowed files/areas:** `packages/sync`, `supabase/migrations/`. *Guidance.*
- **Architecture impact:** medium.
- **Security impact:** high — closes offline staleness (**RISK R-007**, **Q-009**).

---

# Milestone M3 — Hardware Pilot

### RF-070 — Printing adapter interface + ESC/POS driver
- **Milestone:** M3 · **Workstream:** Hardware/Printing · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-054
- **Scope:** Replaceable printing adapter interface with an ESC/POS implementation (**DECISION D-009**, **RISK R-001**). Owned by [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md).
- **Acceptance criteria:**
  1. Printing is behind an interface; a fake/in-memory adapter can be substituted in tests with no driver changes (**RISK R-001** mitigation).
  2. The ESC/POS driver renders a known byte sequence for a golden ticket (golden-file test).
  3. Connectivity (network/USB/BT) is configurable per **Q-015**; unsupported config fails clearly.
- **Required tests:** Adapter-substitution test; ESC/POS golden-byte test.
- **Allowed files/areas:** `packages/printing`. *Guidance.*
- **Architecture impact:** medium — hardware abstraction.
- **Security impact:** low.

### RF-071 — Print job spool + state machine + retry + reprint audit
- **Milestone:** M3 · **Workstream:** Hardware/Printing · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-070
- **Scope:** `print_jobs` spool with the proposed state machine `created -> queued -> printing -> printed` (+ `failed -> retrying`, `cancelled`, `abandoned` after max retries); duplicate-print prevention; reprint reason audited (**DECISION D-013, D-018**).
- **Acceptance criteria:**
  1. A job follows the proposed enumeration; after max retries it reaches `abandoned` and stops (test).
  2. The same logical document is not printed twice without an explicit, audited reprint (duplicate-prevention test) (**DECISION D-013**).
  3. A reprint writes an `audit_events` row including reason (test).
- **Required tests:** Print-job state-transition test; duplicate-prevention test; reprint-audit test.
- **Allowed files/areas:** `packages/printing`. *Guidance.*
- **Architecture impact:** low.
- **Security impact:** low — reprint audited.

### RF-072 — Kitchen ticket printing routing
- **Milestone:** M3 · **Workstream:** Hardware/Printing · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** Medium
- **Dependencies:** RF-071, RF-034
- **Scope:** Route kitchen tickets to the correct station printer using the RF-033 routing rules.
- **Acceptance criteria:**
  1. Each kitchen ticket prints at exactly its routed station; misrouted tickets are flagged, not silently dropped (test).
  2. Ticket content matches the station's items for the order (golden-file test).
  3. Routing is tenant/branch/station-scoped (no cross-branch print).
- **Required tests:** Station-routing print test; golden-ticket-content test.
- **Allowed files/areas:** `packages/printing`, KDS integration. *Guidance.*
- **Architecture impact:** low.
- **Security impact:** low.

### RF-073 — Customer receipt printing (ar/he/en, 58/80mm, raster fallback)
- **Milestone:** M3 · **Workstream:** Hardware/Printing · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-071, RF-054
- **Scope:** Localized customer receipts in Arabic/Hebrew/English with full RTL, 58mm and 80mm widths, and raster fallback for Arabic/Hebrew encoding (**DECISION D-014**, **Q-015**, **RISK R-006**).
- **Acceptance criteria:**
  1. Receipts render correctly RTL for `ar`/`he` and LTR for `en` at both 58mm and 80mm (golden-file tests per locale/width).
  2. When the printer lacks the codepage, the raster fallback produces a readable Arabic/Hebrew receipt (test) (**RISK R-006**).
  3. Receipt shows the per-branch authoritative receipt number (**DECISION D-021**) and integer `_minor` totals (**DECISION D-007**).
- **Required tests:** Per-locale/per-width golden receipt tests; raster-fallback test.
- **Allowed files/areas:** `packages/printing`, `packages/l10n`. *Guidance.*
- **Architecture impact:** low.
- **Security impact:** low.

### RF-074 — Cash drawer kick
- **Milestone:** M3 · **Workstream:** Hardware/Printing · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** Low
- **Dependencies:** RF-070
- **Scope:** Open the cash drawer on a cash payment via the printer adapter.
- **Acceptance criteria:**
  1. A completed cash payment triggers exactly one drawer-kick signal (test).
  2. Non-cash payments do not trigger a drawer kick (test).
  3. The kick uses the adapter interface (no hardware-specific code outside the driver).
- **Required tests:** Cash-triggers-kick test; non-cash-no-kick test.
- **Allowed files/areas:** `packages/printing`. *Guidance.*
- **Architecture impact:** low.
- **Security impact:** low.

### RF-075 — Daily reports (sales, shift, voids/discounts)
- **Milestone:** M3 · **Workstream:** Backend/DB · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** Medium
- **Dependencies:** RF-055
- **Scope:** Per-branch daily summary: sales, shift, voids and discounts. Money in integer `_minor` (**DECISION D-007**).
- **Acceptance criteria:**
  1. A daily report reconciles to the underlying orders/payments for a branch (sum check, zero drift beyond documented rounding) (test).
  2. Reports are tenant/branch-scoped; KDS/kitchen_staff role cannot read financial reports (canonical isolation test) (**RISK R-003**).
  3. Voids and discounts are reported with reasons sourced from audit data (**DECISION D-013**).
- **Required tests:** Report-reconciliation test; report-access-control test; void/discount-reason test.
- **Allowed files/areas:** `supabase/migrations/` (views/RPC), reporting module. *Guidance.*
- **Architecture impact:** low.
- **Security impact:** medium — financial data access control.

### RF-076 — Pilot deployment in one restaurant/branch
- **Milestone:** M3 · **Workstream:** Hardware/Printing · **Owner:** Human · **Reviewer:** Claude Code · **Priority:** High
- **Dependencies:** RF-072, RF-073, RF-075
- **Scope:** Run a full day on-site in one real restaurant/branch; go/no-go decision. Owned operationally by [PILOT_PLAN.md](PILOT_PLAN.md). Note: pilot uses one restaurant/branch but the system must not assume single-tenant (**DECISION D-001, D-002, D-003**).
- **Acceptance criteria:**
  1. A full trading day completes with POS, KDS, and printing operating, including at least one offline period that reconciles on reconnect (**RISK R-002**).
  2. Daily reports reconcile against manual cash count within the documented variance.
  3. A written go/no-go with defect list is produced; blockers are filed as tickets.
- **Required tests:** On-site acceptance run (manual) per [PILOT_PLAN.md](PILOT_PLAN.md); offline-reconnect reconciliation observed.
- **Allowed files/areas:** deployment config, runbooks. *Guidance.*
- **Architecture impact:** low.
- **Security impact:** medium — real data; revocation/audit verified live.

---

# Milestone M4 — Sellable SaaS

### RF-090 — Self-serve organization signup + onboarding
- **Milestone:** M4 · **Workstream:** Platform/SaaS · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-059
- **Scope:** A new organization can provision itself, fully isolated, creating its first restaurant/branch and org_owner (**DECISION D-001, D-002, D-004**).
- **Acceptance criteria:**
  1. Signup creates an `organization` with `organization_id` isolation; the new org cannot see any other org's data (isolation test) (**RISK R-003**).
  2. The signing-up user becomes `org_owner` via a membership (not a global role) (**DECISION D-004, D-005**).
  3. Onboarding creates at least one restaurant and branch; no shared account/password is created (**SECURITY REQUIREMENT**).
- **Required tests:** New-org-isolation test; org_owner-membership test; no-shared-account test.
- **Allowed files/areas:** onboarding app/module, `supabase/migrations/` (RPC). *Guidance.*
- **Architecture impact:** medium.
- **Security impact:** high — self-serve tenant creation must preserve isolation.

### RF-091 — Platform admin panel (isolated, audited)
- **Milestone:** M4 · **Workstream:** Platform/SaaS · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** High
- **Dependencies:** RF-059
- **Scope:** Separate, explicitly audited platform-admin path for `platform_admin` role (**DECISION D-011, D-012, D-013**).
- **Acceptance criteria:**
  1. Platform-admin access runs through a separate path; every access writes an audit event (**DECISION D-013**, canonical test).
  2. Non-platform-admin users cannot reach the admin panel (authorization test).
  3. Platform-admin actions on tenant data are scoped and logged with actor/org/reason (test).
- **Required tests:** Admin-path-audited test; non-admin-denied test; admin-action-logging test.
- **Allowed files/areas:** admin app, `supabase/migrations/` (RPC/policies). *Guidance.*
- **Architecture impact:** medium.
- **Security impact:** high — privileged cross-tenant path (**DECISION D-013**).

### RF-092 — Owner/manager dashboard (multi-restaurant/branch)
- **Milestone:** M4 · **Workstream:** Platform/SaaS · **Owner:** Claude Code · **Reviewer:** Codex · **Priority:** Medium
- **Dependencies:** RF-075
- **Scope:** Cross-branch reporting UI for owners/managers spanning multiple restaurants/branches within their organization (**DECISION D-002**).
- **Acceptance criteria:**
  1. A restaurant-group org_owner sees aggregated reporting across Restaurant A (many branches) + Restaurant B (many branches) (**DECISION D-002**, test).
  2. A manager scoped to one branch sees only that branch's data (scope test).
  3. All figures are integer `_minor` and reconcile to RF-075 daily reports (test).
- **Required tests:** Multi-restaurant-aggregation test; branch-scope test; reconciliation test.
- **Allowed files/areas:** dashboard app, reporting module. *Guidance.*
- **Architecture impact:** low.
- **Security impact:** medium — membership-scoped reporting.

### RF-093 — Subscription/billing (basic)
- **Milestone:** M4 · **Workstream:** Platform/SaaS · **Owner:** Claude Code · **Reviewer:** Human · **Priority:** Medium
- **Dependencies:** RF-090
- **Scope:** Basic subscription plans per organization (**Q-016**). Advanced billing is **DEFERRED**; only a basic plan ships.
- **Acceptance criteria:**
  1. An organization can be assigned a basic plan; plan state is per-organization and isolated (test).
  2. Plan limits/states are enforced at the org boundary without affecting other orgs (test).
  3. Money in billing is integer `_minor` (**DECISION D-007**); no floating point.
- **Required tests:** Per-org-plan-isolation test; plan-enforcement test; money-integer test.
- **Allowed files/areas:** billing module, `supabase/migrations/`. *Guidance.*
- **Architecture impact:** low.
- **Security impact:** medium — billing data per-tenant.

### RF-094 — Production hardening, backups, monitoring, runbooks
- **Milestone:** M4 · **Workstream:** Operations · **Owner:** Claude Code · **Reviewer:** Human · **Priority:** High
- **Dependencies:** RF-013
- **Scope:** Backups, alerting, monitoring, and incident runbooks; RPO/RTO and DR region per **Q-013**. Owned by [OPERATIONS_AND_RECOVERY.md](OPERATIONS_AND_RECOVERY.md).
- **Acceptance criteria:**
  1. Automated backups run on schedule and a restore is verified to meet the **Q-013** RPO/RTO targets (restore drill recorded).
  2. Monitoring alerts fire on defined failure conditions (synthetic-failure test).
  3. Incident runbooks exist for the top failure modes (sync outage, RLS incident, printer failure) and are linked from [OPERATIONS_AND_RECOVERY.md](OPERATIONS_AND_RECOVERY.md).
- **Required tests:** Backup-restore drill; alert synthetic-failure test.
- **Allowed files/areas:** ops config, runbooks, monitoring config. *Guidance.*
- **Architecture impact:** low.
- **Security impact:** medium — backups/DR handle real tenant data.

---

## Dependency integrity

All dependencies reference an **earlier-or-concurrent** ticket that exists in this list; the graph is **acyclic** (a topological order is the ascending RF-number order shown above).

| Ticket | Depends on | Notes |
|---|---|---|
| RF-001 | — | Root. |
| RF-002 | RF-001 | |
| RF-003 | RF-002 | |
| RF-004 | RF-002, RF-003 | M0A gate. |
| RF-010 | RF-004 | |
| RF-011 | RF-010 | |
| RF-012 | RF-010 | |
| RF-013 | RF-004 | |
| RF-014 | RF-013 | |
| RF-015 | RF-014 | |
| RF-016 | RF-015 | |
| RF-017 | RF-014 | |
| RF-018 | RF-011 | |
| RF-019 | RF-014 | |
| RF-020 | RF-011 | |
| RF-021 | RF-013, RF-018 | Both deps are earlier M0B tickets. |
| RF-030 | RF-018 | |
| RF-031 | RF-030 | |
| RF-032 | RF-031 | |
| RF-033 | RF-032 | |
| RF-034 | RF-033 | |
| RF-035 | RF-031 | |
| RF-036 | RF-030 | |
| RF-037 | RF-031 | |
| RF-050 | RF-015 | |
| RF-051 | RF-016, RF-050 | |
| RF-052 | RF-014, RF-032 | |
| RF-053 | RF-017, RF-052 | |
| RF-054 | RF-052, RF-036 | |
| RF-055 | RF-037 | |
| RF-056 | RF-018, RF-052 | |
| RF-057 | RF-056 | |
| RF-058 | RF-057 | |
| RF-059 | RF-014, RF-015, RF-016 | |
| RF-060 | RF-059 | |
| RF-061 | RF-016, RF-057 | |
| RF-070 | RF-054 | |
| RF-071 | RF-070 | |
| RF-072 | RF-071, RF-034 | |
| RF-073 | RF-071, RF-054 | |
| RF-074 | RF-070 | |
| RF-075 | RF-055 | |
| RF-076 | RF-072, RF-073, RF-075 | |
| RF-090 | RF-059 | |
| RF-091 | RF-059 | |
| RF-092 | RF-075 | |
| RF-093 | RF-090 | |
| RF-094 | RF-013 | |

Every dependency id appears as a defined ticket above, and every dependency has a strictly smaller RF-number than its dependent — confirming no cycles and no forward references.

## Backlog-grooming recommendation (do NOT split now)

Several tickets are deliberately broad and are good candidates to be **split into sub-tickets during grooming, before their respective milestones begin** — but they remain **single tickets here and now**:
- **RF-016** (device identity, pairing, device/PIN sessions + RLS) — pairing vs device-session vs PIN-session could become separate sub-tickets before M0B execution.
- **RF-056** (outbox push + server inbox/ledger) — push transport vs ledger dedupe vs retry/poison handling before M2.
- **RF-057** (pull sync + conflict resolution + revisions) — pull transport vs per-entity conflict policy vs revision tracking before M2.
- **RF-094** (production hardening, backups, monitoring, runbooks) — backups/DR vs monitoring/alerting vs runbooks before M4.

This is a recommendation only; no split is performed in this revision. (RF-055 is intentionally **not** split despite delivering two RPCs — see **DECISION D-028**.)

## DEFERRED-scope guard (cross-check vs MVP_SCOPE)

Per [MVP_SCOPE.md](MVP_SCOPE.md), the following are **DEFERRED** and intentionally have **no** M1–M3 implementation task here:
- **Tips** (**Q-011**) — not in any task.
- **Refunds** (Payment `refunded` state, **DECISION D-018**) — explicitly not implemented by RF-054.
- **Multi-currency per order** — single currency per order only (**DECISION D-007**, **Q-007**).
- **Advanced subscription/billing** (**Q-016**) — only a *basic* plan at M4 (RF-093); nothing earlier.

No DEFERRED feature appears as an MVP/M1–M3 deliverable.
