# PRODUCTION_READINESS.md — RF-094 production hardening go/no-go

> **Operational companion to the frozen [OPERATIONS_AND_RECOVERY.md](OPERATIONS_AND_RECOVERY.md).**
> OPERATIONS_AND_RECOVERY.md OWNS the operational *design* (environments, secrets, migration
> procedure, backup/recovery, monitoring, incident handling, retention, capacity). This document does
> **not** redefine any of it — it records the **current production-readiness verdict** for RestoFlow
> and the go/no-go gate that must close before a real production go-live. The concrete procedures live
> in [RUNBOOKS.md](RUNBOOKS.md).

> **RF-094 is human-owned (Saleh) with Claude Code as implementer; Codex/Human review** (**DECISION
> D-016**). This is a docs + local-verification deliverable only. **It does not authorize, perform, or
> configure any production deployment.** No remote Supabase, no `supabase link`, no `supabase db push`,
> no secrets, no provider keys, no live third-party monitoring were used or created.

---

```text
REAL PRODUCTION GO-LIVE: BLOCKED
CURRENT CAPABILITY: LOCAL/SIMULATED OPERATIONAL READINESS ONLY
```

---

## Status legend

Every line item below is labelled with exactly one honest status:

- **READY** — implemented, tested, usable as-is.
- **SIMULATED-LOCAL** — logic/procedure exists and is exercisable only against the Docker-local
  Supabase stack and/or printed checklists; no real infra, no real data, no real hardware.
- **NOT IMPLEMENTED — human/infra** — requires a real production project, provider configuration,
  secrets, or hardware that this ticket may not (and must not) create.
- **HUMAN DECISION** — a frozen-baseline decision the human owner must make (an open question or a
  required sign-off), never guessed by an AI agent.

---

## 1. Executive summary

RestoFlow's database core (multi-tenant schema, RLS, audited RPCs, isolation suite) and its printing,
sync, money, shift, and reporting *logic* are implemented and tested locally. **None of that is a
production system.** There is no production Supabase project, no automated backups/PITR, no live
monitoring or alert routing, no managed secret store wired up, and no real hardware transport. Several
go-live decisions (RPO/RTO, retention/privacy, MFA policy) remain **HUMAN DECISION**, and a mandatory
human RLS/security sign-off (**RISK R-003**, CRITICAL) has not been recorded.

RF-094 therefore delivers the **operational readiness layer** — runbooks, a go/no-go checklist, and
two local-only verification scripts — and states the honest verdict: **real production go-live is
BLOCKED**; current capability is **LOCAL/SIMULATED operational readiness only**. This is the last M4
backlog ticket; closing it does **not** make the product production-deployed — it makes the path to a
human-run, human-signed-off go-live explicit and rehearsable.

This document mirrors the honest [PILOT_READINESS.md](PILOT_READINESS.md) (RF-076) pattern: the pilot
was already assessed as **BLOCKED / SIMULATED-only**, and production hardening inherits those blockers
plus the production-specific infra/decision gates below.

---

## 2. What is ready now (READY)

| Area | Status | Evidence / note |
|---|---|---|
| Multi-tenant schema + migrations | **READY** | `supabase/migrations` rf014..rf093 replay cleanly via `supabase db reset` (local) |
| RLS / tenant isolation (code) | **READY** | RF-059/060 scoped policies + canonical suite incl. `supabase/tests/rf019_tenant_isolation_harness_test.sql`; green locally + in CI `db-tests` |
| Audited RPCs (sensitive mutations) | **READY** | `submit_order`/`apply_discount`/`void_order`/`record_payment`/shift RPCs write append-only `audit_events` (**D-011/D-013**) |
| Platform-admin plane (separate, audited) | **READY** | `platform_admin_grants` + `platform_admin_audit_events`; MFA `aal2` gate (**D-026**); RF-091/093 |
| Money integrity (integer `_minor`) | **READY** | `_minor` columns + `tools/check_no_float_money.sh` guard (**D-007**); no floats anywhere |
| Secret hygiene (no committable secrets) | **READY** | `tools/check_secrets.sh`; CI is secret-free, local-only, no remote/login |
| Sync push/pull + revocation (code) | **READY** | RF-056/057/061 outbox/inbox/ledger; idempotency `(device_id, local_operation_id)` (**D-022**) |
| Daily reports (code) | **READY** | RF-075 server views reconcile to orders/payments; KDS/kitchen denied financial reads (T-003) |
| CI guardrails | **READY** | `validate` (format/analyze/tests/guards) + `db-tests` (Docker-local pgTAP); both secret-free |
| RF-094 runbooks + go/no-go gate | **READY** | this document + [RUNBOOKS.md](RUNBOOKS.md) |

---

## 3. What is only simulated locally (SIMULATED-LOCAL)

| Area | Status | Evidence / note |
|---|---|---|
| Restore *procedure* | **SIMULATED-LOCAL** | `tools/restore_drill.sh` replays migrations + runs the isolation suite on the **local** stack and prints the restore-validation checklist; it is **not** a real-prod PITR drill |
| Backup *validation logic* | **SIMULATED-LOCAL** | post-restore checks (row counts per `organization_id`, RLS enabled+forced, money integer, receipt-sequence integrity) are defined and partly executed by `supabase test db`; real backups don't exist yet |
| Alert *detection logic* | **SIMULATED-LOCAL** | `tools/alert_synthetic_check.sh` injects a synthetic failure signal into a TEMP table on the local DB and asserts a detection query catches it (and that a below-threshold control does not). It simulates **detection only — not live pager/alert delivery** |
| Printing / receipt / kitchen / drawer | **SIMULATED-LOCAL** | RF-070..075 logic against `InMemoryPrintTransport` only; `network`/`usb`/`bluetooth` throw `UnsupportedTransportException`; no real device printed/kicked |
| End-to-end POS/KDS device flow | **SIMULATED-LOCAL / NOT READY** | `apps/pos` is a shell; `apps/kds` is a prototype; no hardened on-device client wired to the RPCs |

---

## 4. What is not implemented because it requires human/infra action (NOT IMPLEMENTED — human/infra)

| Area | Status | Why it cannot be done here |
|---|---|---|
| Production Supabase project | **NOT IMPLEMENTED — human/infra** | No remote project may be created/linked; no `supabase link`, no `db push`, no provider keys (approved constraints) |
| Automated backups + PITR | **NOT IMPLEMENTED — human/infra** | Provider-managed feature on a real prod plan; cannot exist on a local stack |
| Real restore drill (recorded) | **NOT IMPLEMENTED — human/infra** | Requires real backups on a real project; only the procedure is rehearsable locally |
| Live monitoring + metrics pipeline | **NOT IMPLEMENTED — human/infra** | Requires a provider/observability integration + keys; none configured (approved constraint) |
| Alert routing to on-call | **NOT IMPLEMENTED — human/infra** | Requires real notification channels; only detection *logic* is simulated locally |
| Managed secret store wiring | **NOT IMPLEMENTED — human/infra** | Real secrets live only in the provider/CI secret store; none created here |
| DR region / multi-region posture | **NOT IMPLEMENTED — human/infra** | Depends on **Q-013**; single-region with PITR is the working assumption until frozen |

---

## 5. Human decision gates (HUMAN DECISION)

These are **not** code and must be decided by the human owner (with qualified advice where legal/fiscal),
never guessed by an AI agent. They gate real go-live; they do **not** gate this docs deliverable.

| Gate | Status | Note |
|---|---|---|
| **Q-013** — backup RPO/RTO targets + DR region | **HUMAN DECISION** | Working assumption (placeholder, not a commitment): RPO ≤ 24h (daily) → near-zero with PITR; RTO best-effort/≤ 24h for pilot. Must be replaced with frozen targets before go-live ([OPERATIONS_AND_RECOVERY.md](OPERATIONS_AND_RECOVERY.md) §5.2/§5.4) |
| **Q-005** — retention / privacy / backup-expiry | **HUMAN DECISION** | Legal/privacy; depends on **Q-001** jurisdiction. No retention/purge automation ships until resolved; backups inherit live-data retention obligations (OPS §6) |
| **Q-008** — MFA / platform-admin auth policy | **HUMAN DECISION** | TOTP is enabled locally for `aal2`; the production MFA policy/method/mapping for owner/manager + platform admins is not frozen |
| **Human RLS / security sign-off** | **HUMAN DECISION** | **RISK R-003** (CRITICAL). A recorded human sign-off on RLS/tenant isolation is mandatory before any real tenant data is served. Not yet recorded |

---

## 6. Production go/no-go checklist (real go-live gate)

A real production go-live is **GO only when every box is checked**. **The decision owner is Saleh
(human)**; Claude Code/Codex are implementer/reviewer only (**D-015/D-016**). As of this document,
multiple boxes are open → **NO-GO**.

- [ ] Production Supabase project exists (its own project; no other tenant's data present) — **NOT IMPLEMENTED — human/infra**
- [ ] Automated backups + PITR enabled on prod — **NOT IMPLEMENTED — human/infra**
- [ ] A **real** restore drill executed and recorded against prod backups, meeting the frozen **Q-013** RPO/RTO — **NOT IMPLEMENTED — human/infra** (blocked also by **Q-013** HUMAN DECISION)
- [ ] Monitoring provider selected and configured — **NOT IMPLEMENTED — human/infra**
- [ ] Alert routing to the human on-call tested (real delivery) — **NOT IMPLEMENTED — human/infra**
- [ ] Secrets stored in a managed secret store (provider + CI), per-env, never reused across tiers — **NOT IMPLEMENTED — human/infra**
- [ ] No secrets in the repo — **READY** (`tools/check_secrets.sh` clean; CI secret-free)
- [ ] Human RLS / security sign-off recorded (**RISK R-003**) — **HUMAN DECISION**
- [ ] Retention/privacy policy frozen (**Q-005**), incl. backup-expiry — **HUMAN DECISION**
- [ ] RPO/RTO + DR region frozen (**Q-013**) — **HUMAN DECISION**
- [ ] MFA / platform-admin auth policy frozen (**Q-008**) — **HUMAN DECISION**
- [ ] Incident runbooks reviewed ([RUNBOOKS.md](RUNBOOKS.md)) — **READY** (to review)
- [ ] Incident owner / on-call defined and reachable — **HUMAN DECISION** (working assumption: on-call = Saleh; **RISK R-005** single-builder bus factor)

> **Verdict: NO-GO.** Real production go-live remains **BLOCKED** until every box above is checked and
> Saleh records a GO. Nothing in RF-094 changes that verdict.

---

## 7. Evidence checklist for RF-094 local work

What this ticket actually produced and how to verify it locally (no remote, no secrets):

- [ ] Local restore-drill script exists and runs: `bash tools/restore_drill.sh` (and `--check`) — see [RUNBOOKS.md](RUNBOOKS.md) §1.
- [ ] Synthetic alert script exists and runs: `bash tools/alert_synthetic_check.sh` — see [RUNBOOKS.md](RUNBOOKS.md) §2.
- [ ] Guard scripts pass: `bash tools/check_secrets.sh`, `bash tools/check_no_float_money.sh`, `bash tools/check_no_hardcoded_strings.sh`.
- [ ] `git diff --check` clean (no whitespace/conflict markers).
- [ ] **No remote commands required** — every step runs against the Docker-local stack or prints a
  checklist; nothing connects to a remote Supabase project, performs `supabase link`/`db push`, or
  reads/writes a secret.
- [ ] (Optional, if Docker available) `supabase db reset` + `supabase test db` pass — the same
  local "migrations replay + isolation suite green" gate the restore drill wraps.

---

## 8. Recommended follow-ups (human/infra — do NOT auto-create Jira tickets)

These are the real go-live steps; they are **human/infra work or human decisions**, not code this
ticket may do. **IDs are assigned by Saleh in Jira — this document does not create them.**

1. **Production infra ticket** — provision a dedicated prod Supabase project; wire the managed secret
   store (service-role key server/CI only — **D-011**); configure forward-only migration promotion
   (local → dev → staging → prod, OPS §2.2).
2. **Real backup / PITR enablement** — enable provider-managed daily backups + PITR on prod; set
   backup retention per the **Q-005** resolution.
3. **Real restore drill** — execute and record a restore against prod backups (to an isolated
   instance first), validated per [RUNBOOKS.md](RUNBOOKS.md) §1, meeting the frozen **Q-013** targets.
4. **Live monitoring + alert routing** — select an observability provider, wire the signals in
   [RUNBOOKS.md](RUNBOOKS.md) §2, and test real alert delivery to the on-call.
5. **Decision freeze** — resolve **Q-013** (RPO/RTO + DR region), **Q-005** (retention/privacy +
   backup-expiry), and **Q-008** (MFA/platform-admin policy).
6. **Human RLS / security sign-off** — record the mandatory sign-off (**RISK R-003**) before serving
   any real tenant data.

> **Do not create these Jira tickets automatically.** They are listed for Saleh to triage and assign.

---

## 9. Explicit statement

**RF-094 does not authorize, perform, or configure a production deployment.** It produces the
production-readiness verdict, the go/no-go gate, the operational runbooks ([RUNBOOKS.md](RUNBOOKS.md)),
and two local-only verification scripts. Real production go-live remains **BLOCKED** and is Saleh's
decision, gated on the §6 checklist, the §5 human decisions, and the recorded human RLS/security
sign-off.
