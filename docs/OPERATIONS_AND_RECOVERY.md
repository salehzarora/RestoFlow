# OPERATIONS_AND_RECOVERY

> **Status — DRAFT (candidate), not yet frozen.** Drafted by Claude Code (RF-001) · pending ChatGPT review · pending independent Codex review · pending human approval (Saleh). Only the explicit RF-001 invariants (below/where cited) are binding requirements; every other architectural choice is a **PROPOSED DECISION** pending review and human approval. Architecture freeze happens only after independent review, required fixes, and Saleh's approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

Status: candidate document, proposed for architecture freeze (pending review and approval) (M0A / RF-001). Owns: operations, environments, secrets handling at the operational layer, database migration procedure, backup & recovery, monitoring/observability, incident handling, data retention operations, capacity/cost basics.

This document is the proposed source of truth for **operations and recovery** (pending review and approval). It does not redefine security controls, sync semantics, or the agent workflow; it references the documents that own those topics:

- [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) — owns RLS, threat model, isolation tests, secrets as a security control.
- [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md) — owns outbox/inbox, idempotency, conflict rules, device/employee revocation while offline.
- [API_CONTRACT](API_CONTRACT.md) — owns RPC contracts (SECURITY DEFINER functions).
- [DOMAIN_MODEL](DOMAIN_MODEL.md) — owns entities/fields/relationships (including `audit_events`, `sync_operations`).
- [PRINTERS_AND_HARDWARE_SPEC](PRINTERS_AND_HARDWARE_SPEC.md) — owns printing/hardware (device health context).
- [DECISIONS](DECISIONS.md) — owns the decision log (D-xxx).
- [OPEN_QUESTIONS](OPEN_QUESTIONS.md) — owns the open-questions register (Q-xxx).
- [PILOT_PLAN](PILOT_PLAN.md) — owns the M3 pilot specifics.
- `AGENTS.md` (repo root) — owns agent guardrails and forbidden actions referenced below.

> Scope note: M0A is **documentation only**. Nothing here authorizes creating infrastructure, Supabase projects, migrations, CI, or secrets. This document describes the operational design to be implemented from M0B onward, consistent with **DECISION D-009** (tech stack) and **DECISION D-019** (milestones).

---

## 1. Operating Principles

1. RestoFlow is **multi-tenant** (**DECISION D-002**, **DECISION D-003**); the tenant boundary is `organization_id` (**DECISION D-001**). No operational procedure here may assume a single organization/restaurant/branch, even though the pilot uses one.
2. Operations must preserve the four security layers (**DECISION D-012**) and never weaken tenant isolation. **RISK R-003** (RLS bug leaking cross-tenant data) is CRITICAL and constrains every shared-environment action.
3. The system is **offline-first** (**DECISION D-010**). Operational tooling must not assume the cloud backend is the only place data lives or syncs; the POS keeps working offline and reconciles on reconnect (see [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md)).
4. Operations are **human-gated**. No agent may push, create a remote, change production, reset a database, or disclose secrets (`AGENTS.md`, **DECISION D-016**). On-call is a human (Saleh).
5. All sensitive operational actions are auditable. Server-side privileged actions go through audited RPC and append-only `audit_events` (**DECISION D-011**, **DECISION D-013**).

---

## 2. Environments and Promotion

### 2.1 Environment tiers

**ASSUMPTION**: four logical environments. The concrete provisioning happens in M0B; this is the design.

| Environment | Purpose | Backend | Data | Who/what runs here |
|---|---|---|---|---|
| **local** | Developer / agent workstation | Local Drift/SQLite; optional local Supabase stack | Synthetic only | Claude Code, Codex (read-only), developer |
| **dev** | Shared integration | Dedicated Supabase project (dev) | Synthetic only; freely resettable | CI, integration tests |
| **staging** | Pre-production rehearsal; mirrors prod config | Dedicated Supabase project (staging) | Synthetic / anonymized only | Release validation, pilot rehearsal |
| **prod** | Live pilot and real customers | Dedicated Supabase project (prod) | **Real tenant data** | Real restaurants/branches |

Rules:
- Each tier is a **separate Supabase project** with separate credentials, keys, and database. No environment shares a database with another.
- `local` and `dev` are the only freely resettable environments (see §4 forbidden actions).
- **staging** and **prod** are treated as shared/protected: no destructive operations, no db reset, forward-only migrations.
- **SECURITY REQUIREMENT**: real tenant data must never be copied into `local`, `dev`, or `staging`. Lower tiers use synthetic or anonymized data only (data-retention/privacy obligations remain **OPEN QUESTION Q-005**).

### 2.2 Promotion flow

Migrations and application releases flow strictly forward:

```
local  ->  dev  ->  staging  ->  prod
```

- A change is validated in `dev`, rehearsed in `staging`, then promoted to `prod`.
- Promotion to `prod` requires **human approval** (the merge gate in **DECISION D-016**: ChatGPT plan -> human approval -> Claude Code -> tests -> Codex review -> fixes -> human approval -> merge).
- No skipping tiers for schema or release changes that touch shared/prod data shape.
- Promotion never carries data downward (prod -> staging copy of real data is forbidden; see §6 retention/privacy, **Q-005**).

**OPEN QUESTION Q-013**: target RPO/RTO and DR region inform whether `prod` requires a multi-region or read-replica posture; until resolved, single-region with PITR is the working assumption.

---

## 3. Secrets Management

Operational rules. Security ownership of secrets-as-controls lives in [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md); this section covers where secrets live and how they rotate.

### 3.1 Hard rules

- **SECURITY REQUIREMENT**: no secrets of any kind committed to the repository — not in code, config, fixtures, `.env` checked in, CI YAML, or docs. A `.gitignore` and secret-scanning gate (M0B) enforce this.
- **SECURITY REQUIREMENT** (**DECISION D-011**): the Supabase **service-role key** must NEVER ship in or be reachable by Flutter clients (POS/KDS/dashboard apps). It exists only in trusted server-side contexts (CI deploy steps, server functions, the owner's secret store).
- **SECURITY REQUIREMENT**: no shared restaurant password and no shared service account (**DECISION D-004**). Every human and every device has its own identity/credentials (**DECISION D-005**, **DECISION D-006**).
- Clients use only the publishable/anon key plus the user's authenticated session; all sensitive mutations go through audited RPC (**DECISION D-011**, **DECISION D-012**).

### 3.2 Where secrets live

| Secret | Lives in | Reachable by | Notes |
|---|---|---|---|
| Supabase publishable/anon key (per env) | App build config / env injection | Flutter clients | Not sensitive on its own; RLS still enforces isolation |
| Supabase service-role key (per env) | Secret manager + CI secret store | Server/CI only | **Never** in clients (**DECISION D-011**) |
| Database direct connection string (per env) | Secret manager + CI secret store | Migration runner only | Used by forward-only migration tooling |
| Device enrollment/pairing secrets | Server-issued, short-lived | Device during pairing only | Expiring enrollment codes (**DECISION D-006**) |
| Third-party/payment credentials | Secret manager (per env) | Server only | Payments scope per [API_CONTRACT](API_CONTRACT.md) |
| Signing / CI tokens | CI secret store | CI only | No push without human approval (D-016) |

**ASSUMPTION**: the secret store is the cloud provider's managed secret manager plus the CI provider's encrypted secrets (GitHub Actions secrets, per **DECISION D-009**). Local development uses an untracked, machine-local `.env` that is `.gitignore`d.

### 3.3 Rotation

- Each environment has independent secrets; rotating one tier never reuses another tier's value.
- Rotation triggers: scheduled rotation cadence, suspected exposure, personnel/device change, or any commit-scan hit.
- **Service-role key compromise is a SEV-1 incident** (§7): rotate immediately, invalidate sessions, audit `audit_events`, review for cross-tenant access (**RISK R-003**).
- Device/employee credential revocation is an identity operation: revoking must remove FUTURE access including the offline window (**DECISION D-006**, **RISK R-007**, validity window is **OPEN QUESTION Q-009**; mechanics owned by [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md)).
- **ASSUMPTION**: default rotation cadence is quarterly for long-lived secrets and immediate on exposure; final cadence is set during M0B/M2 hardening.

---

## 4. Database Migrations Procedure

Owner of schema content is [DOMAIN_MODEL](DOMAIN_MODEL.md). This section owns the **procedure**.

### 4.1 Principles

- **Forward-only migrations.** Migrations are append-only and ordered. Rolling back is done by writing a new forward migration that corrects state, never by editing or deleting an applied migration on a shared/prod database.
- Every migration is a versioned file under source control, reviewed before promotion, and applied identically across tiers via the promotion flow (§2.2).
- Migrations must respect naming conventions (**DECISION D-017**): snake_case, plural tables, UUID `id`, `organization_id` on every tenant-scoped table, money columns suffixed `_minor`, `created_at`/`updated_at`, `deleted_at` tombstones (**DECISION D-020**), and sync columns (`device_id`, `local_operation_id`, `revision`/`version`, client/server timestamps).
- Schema changes that alter shared packages or API contracts require their own ticket (**DECISION D-016**). Shared-package and API-contract changes are never folded silently into a feature migration.
- RLS policies are part of migrations; any table holding tenant data ships with RLS enabled in the same change (**DECISION D-012**, **RISK R-003**). Isolation tests gate the change (see [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) and [TESTING_STRATEGY](TESTING_STRATEGY.md)).

### 4.2 Procedure (per change)

1. Author migration on a branch (`<type>/RF-<id>-<slug>`, type in {feat,fix,chore,docs,refactor,test,infra}) tied to a ticket.
2. Apply on `local`, then `dev` (resettable). Run isolation/permission tests and the canonical isolation set from [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md).
3. Codex independent review (read-only) per **DECISION D-016**.
4. Human approval -> apply on `staging` (no reset) -> validate.
5. Human approval -> apply on `prod` (forward-only, no reset). Take/verify a recent backup immediately before prod migration (§5).
6. Record outcome; privileged DDL on prod is captured in operational logs (and any data-affecting RPC in `audit_events`).

### 4.3 Expand/contract for destructive shape changes

Because destructive operations are forbidden on shared/prod (§4.4), column/table removals use **expand -> migrate -> contract**:
1. **Expand**: add new column/table; backfill via forward migration.
2. **Migrate**: switch readers/writers to the new shape; keep old in place.
3. **Contract**: only after all tiers and clients (including offline clients that may be behind — see **Q-009** window) have migrated, drop the obsolete object in a later forward migration. Deletions relevant to sync use tombstones, not hard deletes (**DECISION D-020**).

### 4.4 Forbidden actions (consistent with `AGENTS.md`)

On shared (`staging`) and `prod`:
- **NO database reset / drop database / truncate of real data.**
- **NO `reset --hard`, no force push, no deletion of real data, no production changes** without human approval (`AGENTS.md`, **DECISION D-016**).
- **NO editing or deleting an already-applied migration.** Correct forward.
- **NO disabling RLS** on tenant tables to "make a migration work." (**RISK R-003**.)
- **NO secrets** embedded in a migration.
- Agents must not edit the same working tree simultaneously; one active ticket per worktree (**DECISION D-016**).

`dev`/`local` may be reset freely (synthetic data only).

---

## 5. Backup and Recovery

### 5.1 Cadence and mechanism

- **prod**: automated daily full backups plus **Point-In-Time Recovery (PITR)** where the provider plan supports it (Supabase managed Postgres, **DECISION D-009**).
- **staging**: periodic backups sufficient to rehearse restores; no real data.
- **dev/local**: no backup guarantees (synthetic, resettable).
- A verified backup is taken/confirmed immediately before any `prod` migration (§4.2 step 5).
- **ASSUMPTION**: provider-managed automated backups are enabled on `prod` from M2/M3; PITR availability depends on the chosen plan.

### 5.2 RPO / RTO

- **OPEN QUESTION Q-013**: backup RPO/RTO targets and DR region are NOT yet decided. Until frozen, the working assumption is **RPO <= 24h** (daily backup) improving to near-zero with PITR, and **RTO best-effort** within the pilot. These are placeholders, not commitments, and must be replaced when Q-013 is resolved.
- **RISK R-008** (money/rounding/tax errors) and **RISK R-003** (cross-tenant leak) raise the stakes of any restore: a restore must never resurrect deleted tenant data into the wrong tenant or revive revoked access. Restores are validated against isolation tests before being declared complete.

### 5.3 Recovery procedure (skeleton)

1. Declare an incident (§7) and assign the human on-call.
2. Identify recovery target time (for PITR) or backup snapshot.
3. **Restore to a new/isolated instance first** (never overwrite live prod blindly) and validate: row counts per `organization_id`, RLS enabled, isolation tests pass, money columns intact as integer `_minor` values (no floats — **DECISION D-007**).
4. Reconcile offline clients: clients hold authoritative local state and an outbox; the server inbox/processed-operation ledger and idempotency keys (`device_id` + `local_operation_id`, **DECISION D-022**) prevent duplicate application after restore. Reconciliation rules are owned by [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md).
5. Reconcile receipt sequences: per-branch monotonic server-assigned sequences (**DECISION D-021**) must not regress or duplicate after restore; verify the latest assigned value per branch before reopening writes.
6. Cut over and confirm; write a postmortem (§7.4).

### 5.4 DR region

- **OPEN QUESTION Q-013** also covers DR region selection. **DEFERRED** beyond a single-region pilot unless Q-013 mandates otherwise; multi-region is a post-pilot consideration.

---

## 6. Data Retention (Operational)

- **OPEN QUESTION Q-005**: data retention and privacy obligations are NOT yet frozen and depend on the target jurisdiction (**OPEN QUESTION Q-001**). No retention/deletion automation ships until Q-005 is resolved.
- Until then: retain operational and audit data; do not auto-purge. `audit_events` are append-only and never updatable/deletable by app roles (**DECISION D-013**).
- Deletions that matter to sync use tombstones (`deleted_at`, **DECISION D-020**), not hard deletes, so offline clients reconcile correctly.
- **SECURITY REQUIREMENT**: lower environments use synthetic/anonymized data only; real tenant PII never leaves `prod` (§2.1).
- Backups inherit the same retention obligations as live data; backup expiry policy is **DEFERRED** to the Q-005 resolution.

---

## 7. Monitoring, Observability, and Incident Handling

### 7.1 Logs (with redaction)

- Central application/server logs, structured, scoped where possible by `organization_id`/`restaurant_id`/`branch_id`/`device_id` for triage (consistent with naming **DECISION D-017**).
- **SECURITY REQUIREMENT**: logs are **redacted** — no secrets, no service-role keys, no PINs, no full payment credentials, minimal PII. Money appears only as integer `_minor` (**DECISION D-007**); never log raw credentials or tokens.
- Privileged/sensitive mutations are recorded in append-only `audit_events` with actor, device, organization, restaurant, branch, timestamp, action, reason, old/new values (**DECISION D-013**). Platform-admin access is an explicitly audited, separate path ([SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md)).

### 7.2 Metrics

- Backend: error rate, latency, RPC failures, auth failures, RLS-denied rates (a spike may indicate misconfiguration or attack — **RISK R-003**).
- Sync health: outbox depth, in-flight vs applied vs rejected/dead `sync_operations` (PROPOSED state enumerations, pending review and approval; RF-001 §8 directs us to evaluate, not assume final — **DECISION D-018**), conflict counts (**RISK R-002**).
- Device/printing health: device pairing state (`code_issued`..`revoked`, **DECISION D-018**), last-seen, print job failures/abandoned counts (**RISK R-001**, **RISK R-006**; hardware specifics in [PRINTERS_AND_HARDWARE_SPEC](PRINTERS_AND_HARDWARE_SPEC.md)).
- Realtime usage vs provider limits (**OPEN QUESTION Q-014**); Realtime is enhancement-only (**DECISION D-010**), so its degradation is not an outage.

### 7.3 Alerts and device health

- Alert routing target is the **human on-call** (Saleh); **RISK R-005** (single-builder bus factor) means alerts must be simple, actionable, and documented.
- Baseline alerts: prod error-rate spike, auth/RLS-denied spike, sync dead-letter growth, backup failure, secret-scan hit, device offline beyond threshold, print-job abandonment surge.
- Device health: a registered device that stops syncing or repeatedly fails auth is surfaced; revocation while offline is handled per **DECISION D-006** / **RISK R-007** (window = **Q-009**).
- **ASSUMPTION**: alerting uses the cloud provider's built-in alerting plus email/notification to the owner in the pilot; richer paging is **DEFERRED**.

### 7.4 Incident handling

**On-call**: one human (Saleh). No agent is on-call and no agent may take production action (**DECISION D-016**).

**Severity levels** (**ASSUMPTION**, to be confirmed at M3 hardening):

| Severity | Definition | Example | Response |
|---|---|---|---|
| **SEV-1** | Cross-tenant data exposure, secret/service-role leak, prod data loss, prod down | RLS bug leaks Org B data to Org A (**R-003**); service-role key exposed | Immediate: contain, rotate, restore if needed, audit, notify |
| **SEV-2** | Major function broken, no data loss | Sync stuck; payments failing for a branch | Same-day mitigation |
| **SEV-3** | Degraded/non-critical | Realtime lag (enhancement only, **D-010**); single printer flaky (**R-001/R-006**) | Scheduled fix |

**Runbook skeleton (per incident)**:
1. Detect (alert/report) and declare severity.
2. Assign human on-call; open incident record (ticket RF-<number>).
3. Contain — stop the bleed (rotate secret, disable affected path, halt writes). For suspected cross-tenant leak, prioritize isolation verification (**R-003**).
4. Diagnose using logs (§7.1), metrics (§7.2), and `audit_events`.
5. Recover — apply fix forward-only (§4) and/or restore (§5); never reset prod.
6. Verify — isolation tests, money integrity (integer `_minor`), receipt sequence integrity (**D-021**), sync reconciliation (**D-022**).
7. **Postmortem** — blameless write-up: timeline, root cause, blast radius (which `organization_id`s affected), corrective actions, follow-up tickets. Stored in Git/Jira (**DECISION D-015**).

**SECURITY REQUIREMENT**: any incident touching cross-tenant access, secrets, or platform-admin paths is automatically SEV-1 and reviewed against the canonical isolation tests before closure.

---

## 8. Capacity and Cost Basics

- The pilot is small (one organization, one restaurant, one branch — but **no schema/architecture assumes this**, **DECISION D-001/D-002**). Capacity needs are modest in M3.
- Cost drivers to watch: Supabase database/storage tier, Realtime usage (**Q-014**), backup/PITR retention (cost scales with retention; ties to **Q-013**/**Q-005**), and egress.
- Per-tenant growth indicators (orders/day, devices, print volume per `branch_id`) inform when to scale the prod tier; tracked via metrics (§7.2).
- **ASSUMPTION**: pilot runs on a single managed prod project with vertical scaling headroom; horizontal/multi-region scaling is **DEFERRED** to post-pilot (M4 production hardening, **DECISION D-019**), pending **Q-013**.
- Billing/subscription model for the SaaS itself is **DEFERRED** and tracked as **OPEN QUESTION Q-016**.

---

## 9. Open Questions and Risks Referenced

- **OPEN QUESTION Q-001** — jurisdiction (drives retention/privacy).
- **OPEN QUESTION Q-005** — data retention & privacy obligations.
- **OPEN QUESTION Q-009** — offline authorization validity window (affects revocation, restore, contract-phase timing).
- **OPEN QUESTION Q-013** — backup RPO/RTO targets & DR region.
- **OPEN QUESTION Q-014** — Realtime provider limits & fallback (cost/alerts).
- **OPEN QUESTION Q-016** — subscription/billing model (DEFERRED).
- **RISK R-001** — ESC/POS hardware variation. **RISK R-002** — sync conflicts/duplicates. **RISK R-003** — RLS correctness (CRITICAL). **RISK R-005** — single-builder bus factor. **RISK R-006** — Arabic/Hebrew printing. **RISK R-007** — offline authorization staleness. **RISK R-008** — money/rounding/tax errors.

---

*End of OPERATIONS_AND_RECOVERY.md. Operational decisions here are subordinate to [DECISIONS](DECISIONS.md) and the SHARED CANON; conflicts must be resolved in favor of the canon and flagged as an OPEN QUESTION.*
