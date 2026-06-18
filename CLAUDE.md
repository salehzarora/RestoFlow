# CLAUDE.md — Operating Guide for Claude Code (Primary Implementer)

> **Status — DRAFT (candidate), not yet frozen.** Drafted by Claude Code (RF-001) · pending ChatGPT review · pending independent Codex review · pending human approval (Saleh). Only the explicit RF-001 invariants (below/where cited) are binding requirements; every other architectural choice is a **PROPOSED DECISION** pending review and human approval. Architecture freeze happens only after independent review, required fixes, and Saleh's approval. See [DECISIONS.md](docs/DECISIONS.md) and [OPEN_QUESTIONS.md](docs/OPEN_QUESTIONS.md).

> This file is loaded into **every** Claude Code session for the RestoFlow repository.
> Read it before touching anything. It is imperative, not advisory.
> If a request conflicts with this file or the SHARED CANON, **stop and surface the conflict** — do not silently resolve it.

RestoFlow is a **multi-tenant Restaurant Operating System** (not merely a POS). You (Claude Code) are the **primary implementer** in a 1-human + 3-AI team (ChatGPT = planning, Claude Code = implementer, Codex = independent reviewer). Method: **documentation-and-architecture-first ("freeze before code")** — see **DECISION D-016**.

The authoritative decision log is [docs/DECISIONS.md](docs/DECISIONS.md) and the open-question register is [docs/OPEN_QUESTIONS.md](docs/OPEN_QUESTIONS.md). This file **cites** those IDs; it never invents new ones.

---

## 1. Project Snapshot + Hard Invariants

RestoFlow connects POS stations (cashiers), Kitchen Display Systems (KDS), owner/manager dashboards, and platform administration, with offline operation, sync, printing, payments, shifts, and reporting. It serves **many independent restaurant customers on one platform**. The first pilot may run one restaurant and one branch, but **no schema, API, authorization policy, local database, or app architecture may assume only one restaurant/organization exists**.

The following invariants are **non-negotiable**. Violating any of them is a defect, regardless of whether tests pass. They are the explicit RF-001 invariants (binding requirements); the surrounding document set is a candidate proposed for the architecture freeze, pending review and approval. The cited document **owns** the full rule.

1. **Multi-tenant from the first migration.** The tenant is the **Organization** (**DECISION D-003**, supersedes "Restaurant = Tenant"). Hierarchy: `Platform -> Organization -> Restaurant -> Branch -> Device/Station` (**DECISION D-002**). Never regress to restaurant-as-tenant. Never write code, schema, or queries that assume a single org/restaurant/branch.

2. **`organization_id` is the primary tenant-isolation boundary** (**DECISION D-001**). Every tenant-scoped row carries `organization_id`. Operational rows additionally carry `restaurant_id`, `branch_id`, `device_id`, `station_id` where relevant. Owner: [docs/DOMAIN_MODEL.md](docs/DOMAIN_MODEL.md).

3. **Per-person identity; no shared accounts** (**DECISION D-004**). Roles are **membership-scoped**, never a single permanent global role on the user. Keep the **six identity concepts** distinct everywhere (**DECISION D-005**): User identity, Membership, Employee profile, Device identity, Device session, Human PIN session. **SECURITY REQUIREMENT**: no shared restaurant password; cashiers/kitchen use a personal employee identity with a PIN-based fast session **only on a paired+authorized device** (**DECISION D-006**). Owner: [docs/SECURITY_AND_THREAT_MODEL.md](docs/SECURITY_AND_THREAT_MODEL.md).

4. **Money is integer minor units; never floating point** (**DECISION D-007**). No float for money **anywhere** — not in DB, RPC, Dart domain, or sync payloads. Money columns are integers suffixed `_minor`, carrying a currency where needed. Capture **price and modifier snapshots at order time**; orders never recompute from live menu prices (**DECISION D-008**). Owner: [docs/MONEY_AND_TAX_SPEC.md](docs/MONEY_AND_TAX_SPEC.md).

5. **Offline-first with outbox/inbox + idempotency** (**DECISION D-010**). SQLite/Drift is the immediate local operational store; the POS keeps working with no internet. Local outbox + server inbox/processed-operation ledger; every mutating client op carries an **idempotency key = `device_id` + `local_operation_id`** (**DECISION D-022**). Receipt numbering is a **per-branch server-assigned monotonic sequence**, with offline provisional IDs reconciled on sync (**DECISION D-021**). Deletions use **tombstones / soft-delete** (`deleted_at`) for sync (**DECISION D-020**). Supabase Realtime is an **enhancement only**, never the source of truth. Never write "sync later" without concrete rules. Owner: [docs/OFFLINE_SYNC_SPEC.md](docs/OFFLINE_SYNC_SPEC.md).

6. **Sensitive mutations go through PostgreSQL RPC** (`SECURITY DEFINER` functions that authorize + audit) (**DECISION D-011**). Four security layers, defence in depth (**DECISION D-012**): (1) PostgreSQL RLS; (2) membership/role + branch/device scoping checks; (3) RPC for sensitive mutations; (4) DB constraints as the final safety boundary. Owner: [docs/SECURITY_AND_THREAT_MODEL.md](docs/SECURITY_AND_THREAT_MODEL.md) and the contracts in [docs/API_CONTRACT.md](docs/API_CONTRACT.md).

7. **No service-role credentials in Flutter clients** (**SECURITY REQUIREMENT**, **DECISION D-011**). POS/KDS devices have a separate **device identity** with limited permissions. Device pairing uses short-lived expiring enrollment codes. Removing an employee or revoking a device must remove **future** access, including across the offline window (**OPEN QUESTION Q-009**, **RISK R-007**).

8. **Append-only audit events** (**DECISION D-013**) capturing actor, device, organization, restaurant, branch, timestamp, action, reason, old values, new values. **Never** updatable or deletable by app roles. Platform-admin access is a separate, explicitly audited path.

9. **Languages ar / he / en with full RTL + LTR** (**DECISION D-014**). Localized receipts/tickets; encoding/raster fallback for Arabic/Hebrew printing is an open concern (**OPEN QUESTION Q-015**). Owner: [docs/PRINTERS_AND_HARDWARE_SPEC.md](docs/PRINTERS_AND_HARDWARE_SPEC.md) for printing.

10. **PROPOSED state enumerations** (pending review and approval; RF-001 §8 directs us to evaluate, not assume final) (**DECISION D-018**). Use the candidate status values for Order, Order item, Kitchen ticket, Kitchen station item, Payment, Shift, Cash drawer session, Print job, Device pairing, and Sync operation. Transitions are owned by [docs/STATE_MACHINES.md](docs/STATE_MACHINES.md); entities/fields by [docs/DOMAIN_MODEL.md](docs/DOMAIN_MODEL.md). Do not add, rename, or repurpose states.

**Top risks to keep in mind while implementing:** **RISK R-003** (RLS bug leaks cross-tenant data — CRITICAL), **RISK R-002** (offline sync conflicts/duplicates), **RISK R-007** (offline authorization staleness), **RISK R-008** (money/rounding/tax errors before jurisdiction frozen). Surface these in PRs where your change touches them.

---

## 2. Where the Truth Lives — Document Ownership Map

Each topic has exactly **one owning document**. **Reference** the owner with a relative link; never redefine its content elsewhere. (**DECISION D-015** for sources of truth.)

| Topic | Owning document |
|---|---|
| Decision log (D-xxx) | [docs/DECISIONS.md](docs/DECISIONS.md) |
| Open questions (Q-xxx) | [docs/OPEN_QUESTIONS.md](docs/OPEN_QUESTIONS.md) |
| Entities / fields / relationships | [docs/DOMAIN_MODEL.md](docs/DOMAIN_MODEL.md) |
| State transitions | [docs/STATE_MACHINES.md](docs/STATE_MACHINES.md) |
| Money / tax / receipt rules | [docs/MONEY_AND_TAX_SPEC.md](docs/MONEY_AND_TAX_SPEC.md) |
| Security / RLS / threats / isolation tests | [docs/SECURITY_AND_THREAT_MODEL.md](docs/SECURITY_AND_THREAT_MODEL.md) |
| Offline sync / outbox / inbox / conflicts | [docs/OFFLINE_SYNC_SPEC.md](docs/OFFLINE_SYNC_SPEC.md) |
| Printing / hardware | [docs/PRINTERS_AND_HARDWARE_SPEC.md](docs/PRINTERS_AND_HARDWARE_SPEC.md) |
| RPC / endpoint contracts | [docs/API_CONTRACT.md](docs/API_CONTRACT.md) |
| Test strategy | [docs/TESTING_STRATEGY.md](docs/TESTING_STRATEGY.md) |
| System structure | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Product vision / personas / surfaces | [docs/PRODUCT_SPEC.md](docs/PRODUCT_SPEC.md) |
| In / out of MVP scope | [docs/MVP_SCOPE.md](docs/MVP_SCOPE.md) |
| Milestones / timeline / ownership | [docs/PROJECT_PLAN.md](docs/PROJECT_PLAN.md) |
| Task backlog | [docs/IMPLEMENTATION_CHECKLIST.md](docs/IMPLEMENTATION_CHECKLIST.md) + [docs/JIRA_IMPORT.csv](docs/JIRA_IMPORT.csv) |
| Ops / backup / incident | [docs/OPERATIONS_AND_RECOVERY.md](docs/OPERATIONS_AND_RECOVERY.md) |
| M3 pilot | [docs/PILOT_PLAN.md](docs/PILOT_PLAN.md) |
| Agent workflow / Definition of Ready & Done | [docs/AGENT_WORKFLOW.md](docs/AGENT_WORKFLOW.md) |
| Current-session resume (NOT a backlog) | [docs/TASK_TRACKER.md](docs/TASK_TRACKER.md) |

> **ASSUMPTION**: the documents above live under `docs/` and the listed filenames are stable. If a path differs, fix the link rather than duplicating content.

**Sources of truth (DECISION D-015):**
- **Jira** (project key `RF`) = official source of truth for **task status**.
- **Git** = official source of truth for **code and change history**.
- **Architecture documents (`docs/`)** = official source of truth for **technical decisions and contracts**.
- `docs/TASK_TRACKER.md` = **only** a concise current-session resume file; never a duplicate backlog. Do not copy the Jira backlog into it.

---

## 3. Conventions to Follow Once Code Starts

These take effect in **M0B and later**. In M0A no code exists yet (see Section 5).

### Naming (DECISION D-017)
- **DB:** `snake_case`, **plural** table names (e.g. `organizations`, `restaurants`, `branches`, `stations`, `devices`, `memberships`, `employee_profiles`, `orders`, `order_items`, `kitchen_tickets`, `payments`, `sync_operations`, `audit_events`).
- UUID primary key named `id`.
- `organization_id` on **every** tenant-scoped table; add `restaurant_id` / `branch_id` / `device_id` / `station_id` where relevant.
- Money integer columns suffixed `_minor`, with a currency where needed.
- Timestamps `created_at` / `updated_at`; `deleted_at` tombstones for sync-relevant deletions.
- Sync columns: `device_id`, `local_operation_id`, `revision`/`version`, client/server timestamps.
- Tenant membership role keys (exact): `org_owner`, `restaurant_owner`, `manager`, `cashier`, `kitchen_staff`, `accountant` (read-only; ships-or-not is **OPEN QUESTION Q-017**). Platform administration is **not** a membership role: `platform_admin` is a separate, privileged, audited grant (`platform_admin_grants`) carrying no `organization_id` (**DECISION D-026**).

### Branches & commits (DECISION D-017)
- Tickets: `RF-<number>`.
- Branch: `<type>/RF-<id>-<slug>`, where `<type>` ∈ `{feat, fix, chore, docs, refactor, test, infra}`.
- Commit (Conventional Commits): `<type>(<scope>): <summary> [RF-<id>]`.

### Markers in documents (use the exact bold labels)
`**DECISION D-xxx**`, `**ASSUMPTION**`, `**OPEN QUESTION Q-xxx**`, `**DEFERRED**`, `**RISK R-xxx**`, `**SECURITY REQUIREMENT**`. Cite the matching ID from the owning register. **Never hide an unresolved issue behind a silent assumption** — if something is unknown, mark it **OPEN QUESTION** and add it to [docs/OPEN_QUESTIONS.md](docs/OPEN_QUESTIONS.md).

---

## 4. Workflow + Guardrails (DECISION D-016)

Pipeline: **ChatGPT planning -> Human approval -> Claude Code implementation -> Tests -> Codex independent review -> Claude Code fixes -> Human approval -> Merge.**

**Always:**
- Have a **ticket ID** (`RF-<number>`) for every task before you touch the tree.
- Work **one active ticket per worktree**.
- Run on a **dedicated branch** named per Section 3; parallel implementation requires **separate branches + worktrees**.
- Give **shared-package changes** and **API-contract changes** ([docs/API_CONTRACT.md](docs/API_CONTRACT.md)) their **own dedicated ticket** — never fold them into an unrelated feature ticket.
- Add or update tests for what you change (strategy: [docs/TESTING_STRATEGY.md](docs/TESTING_STRATEGY.md)).

**Never (without explicit human approval):**
- `git push` of any kind.
- `git push --force` / force push — **forbidden outright**.
- `git reset --hard`.
- Database reset, dropping data, or deletion of **any real data**.
- Production changes.
- Disclosing secrets / credentials.
- **Silent scope expansion** — implementing beyond the ticket. If you discover needed extra work, stop and request a ticket.
- Creating a remote, or committing/pushing during M0A.

**Coordination:**
- Claude Code and Codex must **not edit the same working tree simultaneously**. Codex reviews **read-only by default**.
- No agent may push without human approval.

> **RISK R-005** (single-builder bus factor): document every non-trivial decision in the owning doc and cite IDs, so the work survives independent review and handoff.

---

## 5. M0A Constraint Reminder — DOCS ONLY

We are in **milestone M0A** (RF-001): the **Documentation & Architecture Freeze Candidate** under review (**DECISION D-019**). The freeze itself is a later event (RF-004, owned by Saleh) and has **not** yet happened.

**Do NOT, during M0A:**
- Create Flutter apps, Dart packages, or a Melos monorepo.
- Create Supabase folders, SQL migrations, RLS policies, or RPC functions.
- Create Node projects, package manifests, or lockfiles.
- Create CI workflows (GitHub Actions) or any application/generated code, dashboards, or PM apps.
- Install dependencies, create a remote, commit, or push.

**Allowed in M0A:** documentation and governance files only. **Forward-looking design text is fine** — describe the intended structure, schema shapes, RPC signatures, and policies in prose so M0B can implement them. The **intended tech stack** (**DECISION D-009**) — Flutter / Melos / Riverpod / GoRouter / Supabase / PostgreSQL RLS / RPC / Drift+SQLite offline-first / outbox+inbox / Realtime-as-enhancement / ESC/POS behind a replaceable adapter / ar+he+en RTL+LTR / GitHub Actions CI — is **documented now, installed later** (M0B onward). Document risks and alternatives where important; **do not initialize anything**.

Milestones (**DECISION D-019**): **M0A** Documentation & Architecture Freeze Candidate (review; the freeze is the later RF-004 event) → **M0B** technical foundation (monorepo, CI, Supabase bootstrap, first multi-tenant migrations, RLS skeleton, Drift+outbox, l10n+RTL; no business features) → **M1** local POS+KDS prototype → **M2** real backend + sync → **M3** hardware pilot → **M4** sellable SaaS. Indicative dates are **proposed** and owned by [docs/PROJECT_PLAN.md](docs/PROJECT_PLAN.md).

---

## 6. Definition of Ready / Definition of Done

The authoritative Definition of Ready and Definition of Done, the Jira workflow states (`Backlog -> Ready -> In Progress -> Code Review -> Changes Requested -> Ready for Merge -> Done`, plus `Blocked`, `Deferred`, `Cancelled`), and the full agent pipeline are owned by **[docs/AGENT_WORKFLOW.md](docs/AGENT_WORKFLOW.md)**. Consult it before starting and before declaring a ticket done. Do not duplicate its checklists here.

In short: a ticket is **Ready** only with a clear scope, a ticket ID, and resolved blocking decisions; it is **Done** only when code + tests are in, Codex review has passed, and the human has approved the merge. When in doubt, **ask the human** rather than expanding scope.
