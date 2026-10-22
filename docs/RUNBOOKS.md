# RUNBOOKS.md — RF-094 operational runbooks

> **Operational companion to the frozen [OPERATIONS_AND_RECOVERY.md](OPERATIONS_AND_RECOVERY.md).**
> OPERATIONS_AND_RECOVERY.md OWNS the operational design (environments §2, secrets §3, migration
> procedure §4, backup/recovery §5, monitoring/incident §7, retention §6, capacity §8). This file does
> **not** redefine any frozen decision — it adds the **concrete, numbered runbooks** that those design
> sections call for, and is linked from them. The production-readiness verdict + go/no-go gate live in
> [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md).

> **Scope + honesty.** These are RF-094 operational runbooks/checklists. Real production go-live is
> **BLOCKED** (see [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md)). Items are labelled **READY**,
> **SIMULATED-LOCAL**, **NOT IMPLEMENTED — human/infra**, or **HUMAN DECISION**. Nothing here connects
> to a remote Supabase project, performs `supabase link`/`db push`, uses secrets, or wires live
> third-party monitoring. On-call is the **human owner (Saleh)**; no agent is on-call and no agent may
> take production action (**DECISION D-016**, OPS §7.4).

> **Referenced owners (never redefined here):** sync/outbox/inbox →
> [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md); security/RLS/threats/isolation tests →
> [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md); printing/hardware →
> [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md); RPC contracts →
> [API_CONTRACT.md](API_CONTRACT.md); entities/states → [DOMAIN_MODEL.md](DOMAIN_MODEL.md) /
> [STATE_MACHINES.md](STATE_MACHINES.md); decisions/questions → [DECISIONS.md](DECISIONS.md) /
> [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

---

## Severity ladder (shared by all incident runbooks)

Mirrors OPERATIONS_AND_RECOVERY.md §7.4 (**ASSUMPTION**, to be confirmed at hardening). Do not redefine.

| Severity | Definition | Response |
|---|---|---|
| **SEV-1** | Cross-tenant data exposure, secret/service-role leak, prod data loss, prod down | Immediate: contain, rotate, restore if needed, audit, notify |
| **SEV-2** | Major function broken, no data loss | Same-day mitigation |
| **SEV-3** | Degraded / non-critical (Realtime lag — enhancement only **D-010**; single flaky printer) | Scheduled fix |

**Any incident touching cross-tenant access, secrets, or the platform-admin path is automatically
SEV-1** and is reviewed against the canonical isolation suite before closure (SECURITY §; OPS §7.4).

**Common incident skeleton (every runbook follows it):** Detect → Declare severity → Contain → Diagnose
→ Recover (forward-only / restore; **never reset prod**) → Verify → Postmortem (blameless; stored in
Git, **D-015** as amended by **D-038**).

---

## 1. Backup and restore drill

**Goal:** prove a restore is *possible and correct* — it never resurrects deleted tenant data into the
wrong tenant, never revives revoked access, and preserves money + receipt-sequence integrity.

### 1.1 Production setup (NOT IMPLEMENTED — human/infra; do NOT execute from this repo)

These steps are performed by the human owner on the real production project. They are documented here,
**not executed by RF-094**.

1. On the dedicated **prod** Supabase project, enable provider-managed **daily full backups** and
   **Point-In-Time Recovery (PITR)** where the plan supports it (OPS §5.1, **D-009**).
2. Set backup retention to satisfy the frozen **Q-005** retention/privacy obligation — **HUMAN
   DECISION** (backups inherit live-data retention; OPS §6). Until frozen, do not auto-expire backups.
3. Confirm **RPO/RTO** targets and **DR region** per **Q-013** — **HUMAN DECISION**. Working assumption
   (placeholder, not a commitment): RPO ≤ 24h → near-zero with PITR; RTO best-effort/≤ 24h pilot;
   single-region until Q-013 mandates otherwise (OPS §5.2/§5.4).
4. Verify/take a fresh backup **immediately before any prod migration** (OPS §4.2 step 5).
5. Schedule a **recurring real restore drill** (restore to an isolated instance, validate per §1.3,
   record the result + measured RPO/RTO). This is acceptance-criterion 1 for a *real* go-live and is
   **NOT IMPLEMENTED — human/infra** here.

### 1.2 Local simulation (SIMULATED-LOCAL — `tools/restore_drill.sh`)

What is rehearsable now, against the **Docker-local** stack only (synthetic data; no real data, no
remote, no secrets):

1. Run `bash tools/restore_drill.sh` from the repo root. It:
   - prints a **LOCAL-ONLY SIMULATION** banner and refuses to run if a linked/remote project ref is
     present (defence-in-depth: never operate against remote);
   - checks prerequisites (`supabase` CLI, Docker, local stack up);
   - if the local stack is up, runs `supabase db reset` (replays migrations rf014..latest — the local
     "up applies cleanly" gate) then `supabase test db` (the canonical isolation suite incl.
     `supabase/tests/rf019_tenant_isolation_harness_test.sql`);
   - prints the §1.3 restore-validation checklist and the validation queries.
2. `bash tools/restore_drill.sh --check` prints prerequisites + the full checklist + queries **without
   running anything** (works with no Docker).
3. **Honest framing:** this validates the restore *procedure* and the post-restore integrity checks. It
   is **not** a real-prod PITR drill and does **not** prove the Q-013 RPO/RTO numbers (unfrozen).

### 1.3 Restore validation checklist (run after ANY restore — local drill or real prod)

Restore **to a new/isolated instance first** — never overwrite live prod blindly (OPS §5.3). Then verify:

- [ ] **Row counts per `organization_id`** match the expected snapshot; no tenant's rows appear under
  another tenant's id (no cross-tenant resurrection — **RISK R-003**).
- [ ] **RLS enabled *and forced*** on every tenant-scoped table (`relrowsecurity` AND
  `relforcerowsecurity` true); a query with no tenant context returns **zero rows**.
- [ ] **Isolation suite green** — `supabase test db` passes (T-001 cross-org read, T-003 KDS/kitchen
  cannot read financials, T-004 revoked device, T-005 removed employee, T-007–T-010 platform-admin
  plane). A red result means a restore re-opened a leak — **do not declare the restore complete**.
- [ ] **Money intact as integer `_minor`** — no floats anywhere (**D-007**); spot-check key money
  columns are integer types and values are sane.
- [ ] **Receipt-sequence integrity** — per-branch monotonic server-assigned sequences (**D-021**) do
  **not** regress or duplicate; verify the latest assigned value per branch before reopening writes.
- [ ] **Sync reconciliation safe** — idempotency keys `(device_id, local_operation_id)` (**D-022**) and
  the server inbox/processed-operation ledger prevent duplicate application after restore
  ([OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md)).
- [ ] **No revived revoked access** — revoked devices/employees remain revoked after restore (**R-007**).

### 1.4 Hard rules

- **Never reset, drop, or truncate production** (OPS §4.4, **D-016**). Roll forward; restore to an
  isolated instance.
- **Never copy real tenant data into `local`/`dev`/`staging`** (OPS §2.1) — lower tiers use synthetic
  or anonymized data only.
- **Never use real prod data locally.** The local drill uses synthetic data only.
- **No secrets**; the local default connection (`127.0.0.1:54322`) is the public Supabase local-dev
  default, not a credential.

---

## 2. Monitoring and alerting

**Goal:** detect failure conditions early and route them to the human on-call with low noise.

### 2.1 Production monitoring plan (NOT IMPLEMENTED — human/infra)

Performed by the human owner on real infra; documented here, **not configured by RF-094** (no provider
integration, no keys):

- Central, structured, **redacted** logs scoped by `organization_id`/`restaurant_id`/`branch_id`/
  `device_id` (OPS §7.1). **Never log** secrets, service-role keys, PINs, full payment credentials, or
  more than minimal PII; money appears only as integer `_minor`.
- Metrics + alert rules per OPS §7.2/§7.3, routed to the **human on-call (Saleh)** via real
  notification channels (**HUMAN DECISION** which provider/channel; **RISK R-005**).
- Privileged/sensitive mutations are already recorded in append-only `audit_events` (**D-013**) and the
  platform plane in `platform_admin_audit_events` (**D-026**) — these are the source signals for
  several alerts below.

### 2.2 Local synthetic simulation (SIMULATED-LOCAL — `tools/alert_synthetic_check.sh`)

`bash tools/alert_synthetic_check.sh` simulates **detection logic only — not live pager/alert
delivery**. Against the Docker-local DB, inside a single rolled-back transaction using **TEMP tables
only** (no permanent tenant mutation), it injects a synthetic failure-signal spike and asserts that a
detection query (a) **flags the spike** and (b) **does not flag** a below-threshold control (guards
against false positives → alert fatigue). If psql/local DB is unavailable it prints the detection
queries + expected results instead. Prints **PASS/FAIL**.

### 2.3 Signals to monitor

| Signal | Source | Severity (typical) | Notes |
|---|---|---|---|
| **Database availability / prod down** | Provider health | **SEV-1** | Core outage; offline-first POS keeps working locally (**D-010**) but cloud sync stalls |
| **Failed migrations** | Migration runner / promotion (OPS §4) | **SEV-1/2** | Forward-only; never edit an applied migration; roll forward |
| **RLS / cross-tenant indicators** | RLS-denied rate spike; isolation-suite failure | **SEV-1** (auto) | A spike may indicate misconfiguration or attack (**R-003**) — see §4 |
| **Auth failure spikes** | Auth logs / lockout events | **SEV-2** (→1 if credential attack) | PIN lockout (RF-051); MFA assurance failures |
| **Sync dead-letter / outbox depth** | `sync_operations` `dead` count; outbox depth | **SEV-2** | Poison ops + backlog growth (**R-002**) — see §3 |
| **Print job abandoned / retry spikes** | `print_jobs` `abandoned`/`retrying` counts | **SEV-2/3** | Spool health (**R-001/R-006**) — see §5 |
| **Billing / platform-admin changes** | `platform_admin_audit_events` (e.g. `platform.org.plan_set`) | **SEV-2** (review) | Every platform-admin action is audited (**D-026**); unexpected ones are reviewed |
| **Backup failures** | Provider backup status | **SEV-1** | A missed backup widens RPO (**Q-013**) |
| **Secret-scan failures** | `tools/check_secrets.sh` (local/CI) | **SEV-1** | A committable secret is treated as compromised — see §6 |

### 2.4 Severity, ownership, warning vs critical, alert fatigue

- **Severity:** use the shared ladder above. **Cross-tenant / secret / platform-admin → auto-SEV-1.**
- **Who handles alerts:** the **human on-call (Saleh)**. No agent is on-call (**D-016**). Alerts must be
  simple, actionable, and documented (**RISK R-005** single-builder bus factor).
- **Warning vs critical:** *warning* = a trend to watch (rising outbox depth, occasional print retry,
  Realtime lag — enhancement only **D-010**); *critical* = act now (cross-tenant indicator, backup
  failure, prod down, secret-scan hit). Critical pages; warning is reviewed on a cadence.
- **Alert fatigue caution:** every alert needs a clear threshold and an owner action; prefer few,
  high-signal alerts over many noisy ones. Tune thresholds so a normal busy service does not page. A
  below-threshold control is part of the synthetic check (§2.2) precisely to avoid false positives.

---

## 3. Incident runbook 1 — Sync outage / dead-letter growth

- **Trigger:** rising `sync_operations` `dead` (poison) count, growing outbox depth, conflict spikes,
  or "operations not draining after reconnect" reports. (**RISK R-002**.)
- **Severity:** **SEV-2** by default; **SEV-1** if accompanied by data-integrity doubt (duplicates, lost
  mutations) or if it blocks all branches.
- **Containment:**
  - Do **not** force-retry payments or hand-edit data. Offline-first means clients keep working and
    reconcile on reconnect (**D-010**) — let the outbox drain via the idempotent inbox/ledger.
  - If a specific poison op is wedging a queue, isolate it (it is already terminal `dead` after max
    retries and will not auto-retry); do not delete business records.
- **Diagnosis:**
  - Inspect the `sync_operations` ledger states: `created → pending → in_flight → applied`; terminal
    `rejected` (permanent auth/validation) vs `dead` (poison after max retries) vs `conflict → resolved`
    ([OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md) §4).
  - Distinguish **rejected** (expected: revoked actor / failed authorization — see §4 and revocation
    R-007) from **dead** (transient-looking error exceeded retries) from **conflict** (concurrent change
    needing resolution per Q-010).
  - Check idempotency keys `(device_id, local_operation_id)` (**D-022**) and the `processed_pull_log`
    for re-delivery/dedup issues.
- **Recovery:** fix forward (**never reset prod**, OPS §4.4). A correction is a **new** sync operation
  with a new `local_operation_id` — never re-run a terminal op (**D-022**). Let the corrected stream
  drain.
- **Verification:** outbox drains to `applied`; **zero duplicate** orders/payments; revisions converge;
  receipt sequences (**D-021**) neither regress nor duplicate; money integer `_minor` intact.
- **Postmortem:** blameless write-up — timeline, root cause, blast radius by `organization_id`,
  corrective actions, follow-up tickets (Git, **D-015** as amended by **D-038**).
- **Sync concepts:** owned by [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md) (outbox/inbox, idempotency,
  ordering/`depends_on`, conflict resolution, revocation-while-offline, tombstones).

---

## 4. Incident runbook 2 — RLS / cross-tenant incident

- **Trigger:** any sign that one tenant can read/write another's data — RLS-denied anomaly, isolation
  test failure in CI/restore, a report of Org B data visible to Org A, or a tenant-scoped table found
  without RLS. **RISK R-003 (CRITICAL).**
- **Severity:** **AUTO-SEV-1.** No triage delay.
- **Containment — halt the affected path first:**
  - Stop the bleed: disable/halt the affected code path or endpoint; if necessary halt writes to the
    affected scope. Prioritize isolation verification over root-causing (OPS §7.4 step 3).
  - **Never disable RLS** to "make something work" (OPS §4.4). If a secret/service-role key is
    implicated, treat it as §6 simultaneously.
- **Audit / log review:** review append-only `audit_events` (**D-013**) and, for any platform-plane
  involvement, `platform_admin_audit_events` (**D-026**) for actor/device/org/timestamp/old-new values.
  Platform-admin access to tenant data must already be reason-tagged and audited (T-007).
- **Isolation-suite verification:** run the canonical suite (`supabase test db`, incl.
  `supabase/tests/rf019_tenant_isolation_harness_test.sql`): T-001 (cross-org read), T-002 (cross-restaurant
  write), T-003 (KDS/kitchen cannot read financials), T-007–T-010 (platform-admin plane cannot bypass
  tenant RLS). Confirm deny-by-default holds.
- **Secret rotation if related:** if the leak involved a leaked/over-privileged key, rotate immediately
  and invalidate sessions (§6); a service-role key never belongs in a client (**D-011**).
- **Blast-radius assessment:** enumerate exactly which `organization_id`s could have been exposed and
  over what window; this drives notification and any regulatory obligations (gated by **Q-005**).
- **Recovery:** fix forward (correct the policy/predicate in a **new** migration; never edit an applied
  one, OPS §4.3). If data was cross-contaminated, restore to an isolated instance and validate per §1.3
  before any cutover — **never reset prod**.
- **Verification:** isolation suite green; deny-by-default confirmed; blast radius bounded; audit trail
  intact.
- **Postmortem:** mandatory blameless write-up; reviewed against the canonical isolation tests **before
  closure** (SECURITY §; OPS §7.4). File follow-up tickets.

---

## 5. Incident runbook 3 — Printer / hardware failure

- **Trigger:** receipt/kitchen ticket not printing, cash drawer not opening, `print_jobs` `abandoned`
  spike, or a printer offline/timeout. (**RISK R-001** hardware variation, **R-006** Arabic/Hebrew
  raster.)
- **Severity:** **SEV-3** for a single flaky printer (convenience, not correctness); **SEV-2** if all
  printing at a branch is down during service.
- **Key principle:** **printing is an enhancement, never the source of truth** (PRINTERS §; **D-010**).
  An order/payment/ticket/shift is valid in the database whether or not paper ever printed. Print
  failures degrade convenience, not correctness.
- **Spool / retry / reprint guard:**
  - Jobs follow `created → queued → printing → printed`; on failure `failed → retrying` with
    exponential backoff + jitter; after max retries → `abandoned` (terminal), surfaced to staff
    ([PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md) §8; states owned by
    [STATE_MACHINES.md](STATE_MACHINES.md)).
  - **Reprint is audited** (actor/device/reason, **D-013**; RF-071). Use the reprint path — do not
    fabricate duplicate fiscal artifacts outside it. Duplicate-print prevention guards against
    accidental re-issue.
- **Cash drawer handling:** the drawer kick is **at-most-once** per payment (`drawer:<paymentId>`,
  `maxRetries: 0`; RF-074). If the drawer fails to open, **open it manually and record it — do NOT
  re-issue kicks** (avoids double-open / reconciliation drift).
- **Manual fallback (soft rollback):** continue taking orders on RestoFlow; use a hand-written chit for
  the affected station; reprint (audited) once the printer is restored (PILOT_RUNBOOK §10/§11).
- **Verification:** the underlying order/ticket/payment record is intact and unaffected; once hardware
  is restored, the spool drains (`retrying → printed`) or the job is intentionally `cancelled`; any
  reprint is audited; drawer opened at most once per payment.
- **Real-hardware caveat (SIMULATED-LOCAL today):** **real hardware transport is NOT production-proven.**
  `packages/printing` ships `InMemoryPrintTransport` only; `network`/`usb`/`bluetooth` throw
  `UnsupportedTransportException`. Physical printing/drawer-kick requires the transport companion
  ticket (PILOT_READINESS B1) and the **Q-006** (hardware) / **Q-015** (connectivity + AR/HE encoding)
  **HUMAN DECISIONS**. Until then this runbook is rehearsal-only.
- **Postmortem:** record retries/abandons per service; recurring hardware faults feed device-health
  metrics (§2.3) and **Q-006/Q-015**.
- **Printing concepts:** owned by [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md).

---

## 6. Incident runbook 4 — service_role key or secret compromise

- **Trigger:** a secret-scan hit (`tools/check_secrets.sh` local/CI), a leaked/exposed service-role key
  or DB connection string, a suspicious commit, or any sign a secret reached a client or public
  surface. (OPS §3.3.)
- **Severity:** **AUTO-SEV-1.**
- **Rotate the secret immediately:** rotate the affected secret in the managed secret store (per env;
  rotating one tier never reuses another tier's value — OPS §3.3). For a **service-role key**, this is a
  SEV-1 by definition.
- **Invalidate the old key / sessions:** revoke/disable the exposed key so it can no longer authenticate;
  invalidate active sessions as needed. Device/employee credential revocation removes **future** access
  including across the offline window (**D-006**, **R-007**; window = **Q-009**).
- **Check repo / CI / logs:**
  - Re-run `tools/check_secrets.sh`; confirm the secret is removed from the working tree and **purged
    from git history** if it was ever committed (treat any committed secret as compromised — OPS §3,
    `check_secrets.sh` guidance).
  - Confirm no secret is present in CI YAML/logs (CI is secret-free by design — `.github/workflows/ci.yml`)
    and that logs are redacted (no keys/PINs/credentials — OPS §7.1).
- **Audit platform-admin + service actions:** review `audit_events` (**D-013**) and
  `platform_admin_audit_events` (**D-026**) for any actions taken with the exposed credential; assess
  cross-tenant exposure (**RISK R-003**) — if any, also run §4.
- **Verify no client exposure:** confirm the **service-role key is not, and never was, reachable by any
  Flutter client** (POS/KDS/dashboard) — clients use only the publishable/anon key + the user's session;
  all sensitive mutations go through audited RPC (**D-011/D-012**). No service-role key on any device
  (PILOT_RUNBOOK §5).
- **Recovery:** once rotated/invalidated and history is clean, restore normal operation. If tenant data
  may have been accessed, follow §4 for blast-radius + notification (gated by **Q-005**).
- **Postmortem:** blameless write-up — what leaked, how, blast radius, rotation timeline, and a
  prevention follow-up (e.g. tighten the guard or pre-commit hook). File in Git (**D-015** as amended by **D-038**).

---

## 7. Verification & honesty notes

- **Local verification (no remote, no secrets):** `bash tools/restore_drill.sh` (§1.2),
  `bash tools/alert_synthetic_check.sh` (§2.2), `bash tools/check_secrets.sh`,
  `bash tools/check_no_float_money.sh`, `bash tools/check_no_hardcoded_strings.sh`, and optionally
  `supabase db reset` + `supabase test db`.
- **What is real vs simulated:** see [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md) §2–§4. In short:
  the *logic and procedures* are READY/SIMULATED-LOCAL; the *production infra* (backups, PITR,
  monitoring, alert routing, secret store, DR) is **NOT IMPLEMENTED — human/infra**; RPO/RTO,
  retention, MFA policy, and the human RLS sign-off are **HUMAN DECISION**.
- **Go-live remains BLOCKED** until the [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md) §6 checklist
  is fully green and Saleh records a GO.

---

## 8. Incident runbook 5 — card provider outage, unknown outcome, approved-unrecorded, orphaned approval (BIZBOT-PAYMENTS-ZCREDIT-PILOT-001)

- **Scope:** the card-present provider leg of **DECISION D-051 / D-052 / D-053 / D-054 / D-055** ([API_CONTRACT](API_CONTRACT.md)
  §4.55). Agents never operate the terminal or call the provider; every step below is an operator /
  manager action.
- **Trigger:** attempts stuck `unknown` or `released`; the provider rejecting the configured
  credentials or environment; a customer charged while the order still reads unpaid
  (`approved_unrecorded` / `orphan_approved`); an order refusing every tender with
  `payment_in_progress`; a shift refusing to close (`card_payment_in_progress`); the pad never
  prompting; a credential suspected exposed.
- **Severity:** **SEV-2** on the shared ladder above ("payments failing for a branch",
  [OPERATIONS_AND_RECOVERY](OPERATIONS_AND_RECOVERY.md) §7.4); **SEV-1** the moment a provider
  credential is suspected exposed.
- **Containment:** if the provider misbehaves broadly, master flag OFF; otherwise operator revision
  OFF for the branch. The flag gates `start` only, so status reads and recording keep working.
  The `app.sync_push` guard keeps every claimed order blocked for competing tenders, edits and voids
  until its attempt is resolved — never work around it with another tender or a hand-recorded card.
  Never delete, edit or replay LIVE ledger rows (TEST rows leave only through the audited purge below).
- **Diagnosis:** list the branch's open attempts with `public.owner_card_attempts` (§4.55.10):
  state, `approved_unrecorded` / `orphan_approved` reason, `refusal_code`, amount rule, device,
  `last_lookup_at`, resolution metadata. Run `status` with `source='operator'` for each
  `unknown` / `released` attempt — from the originating till, or from any POS of the branch as a
  `manager`+ (an operator call is never refused with `poll_limit`).
- **Recovery — approved:** record under the same identity on the original order, inside the shift and
  drawer frozen at the claim (**D-055**: the attempt's `shift_id` must still be OPEN and its
  `cash_drawer_session_id` still ACTIVE on that till — the shift-close guard keeps them so while the
  attempt is unresolved; a new shift or drawer never absorbs the approval). If the first recording
  leg never reached the server (no sync ledger row) the POS resends the same operation through its
  existing durable `payment.create` dispatch. If it was memoized as rejected with a recoverable
  refusal (`precondition_failed` — a defensive token, pre-empted by the context check in practice —,
  `revoked_employee`, `revoked_device`), repair the cause first (reinstate the membership, or return
  a `suspended` pairing of that same device to `active` — a management-revoked device cannot be
  reinstated for this purpose and leaves the attempt `orphan_approved`), confirm the frozen shift
  and drawer are still open and active (the POS re-sends the pending refusal report once a proven
  session exists; the Resume action does it first if still pending), then a `manager`+ on that same
  till performs the explicit **Resume recording** of **D-054** (§4.55.7): the same `payment.create` row is re-dispatched once,
  never a new operation and never a new charge, at most 3 times per attempt. Any other memoized
  refusal, or a frozen context that cannot be restored (`context_lost`), is not resumable: the
  attempt is `approved_unrecorded` / `orphan_approved` and goes to the orphan procedure below. Never
  charge again, never move the approval to another order or shift, never free the order for another
  tender (**D-053** point 1).
- **Shift close refused (`card_payment_in_progress`, D-055):** the shift cannot close while a LIVE
  attempt frozen to it is `sent`, `unknown` or `released` (not yet freed on provider evidence),
  approved-unrecorded or orphaned without a provider void / refund. Resolve each such attempt first —
  operator status lookup, the provider-evidence `free_order`, Resume recording, or the orphan
  procedure — then close; declined, recorded and provider-voided / refunded attempts never
  block; an evidence-freed `unknown` / `released` attempt does not block (an approval found later makes
  it an `order_freed` orphan, which blocks until resolved). A close queued offline is refused the same way when it syncs and is terminal: the POS
  rolls back its provisional local close (the server shift never left `open`) and, once every attempt is
  resolved, pushes a new `shift.close` with a fresh `local_operation_id`. Never force a close and never open a second shift to work around it; a kept
  standing charge (an orphan the owner will not void or refund) holds that shift and station open until
  the future audited financial-adjustment workflow exists. TEST attempts carry no shift and never
  block.
- **Recovery — declined:** the cashier takes another tender (the claim ends with the decline).
- **Recovery — unknown / released:** repeat the operator lookup; if it stays inconclusive, obtain
  documented provider evidence that no approved charge exists — the provider's transaction report
  (`provider_report`) or its back office (`provider_back_office`) — then `free_order` (§4.55.6) with
  that source, its sanitized evidence reference and a reason; the attempt stays `unknown` /
  `released`. Poll-cap exhaustion, a provider outage, "still inconclusive" or any self-attestation
  never frees the order, and no command-room override exists in phase 1 (**D-053** point 1). A
  later approval of a freed attempt is an `orphan_approved` incident (reason `order_freed`) handled
  only by the orphan procedure below — never recorded in-app.
- **Recovery — orphan_approved (the original payment can no longer be legally recorded):** the
  order stays blocked for every tender, void, edit, discount and new attempt while the standing
  charge is unresolved (an `order_freed` orphan's order was already freed by the manager and is
  listed for reconciliation only). Open an incident under a Work ID; the owner decides. A same-day provider
  void, when needed, is performed manually in the provider's back office only after explicit owner
  approval — never by the application. Only documented provider confirmation that the charge was
  actually voided or refunded lets the operator record the resolution through
  `app.card_attempt_resolve_orphan` (§4.55.10) as `provider_voided` / `provider_refunded`, which
  frees the order for another tender or a void. A standing charge the owner wants to keep but
  RestoFlow cannot legally record stays an open incident until a future, separately designed,
  audited financial-adjustment workflow exists. No automatic void, refund or release; no in-app
  reversal in phase 1.
- **Verification:** the provider's transaction report against the ledger's `approved` / `recorded`
  rows for the pilot branch every day; every difference becomes an incident row; every
  `orphan_approved` row has an open incident; the pilot branch's `payments` count equals the
  recorded attempts plus the other tenders.
- **TEST evidence retention (D-053 point 4):** TEST rows expire 90 days after creation; set an
  incident hold (`app.card_attempt_set_incident_hold`, operator only, audited) before expiry when a TEST
  run belongs to an open incident; the operator purge
  (`app.purge_expired_test_card_attempts`) deletes only expired, unheld TEST rows and is audited
  with counts only; LIVE rows are never deleted by any role or RPC (retention per **D-013** / **Q-005**).
- **Credential exposure (SEV-1):** master flag OFF → resolve or list every open attempt → rotate the
  terminal credentials with the provider → replace the configuration secret → redeploy the adapter
  only if 001E caches configuration at worker start → review `card_attempt.*` audit rows and the
  ledger for the exposure window ([OPERATIONS_AND_RECOVERY](OPERATIONS_AND_RECOVERY.md) §3.3). A
  test-terminal credential that reaches any commit, stash, bundle, report or chat is treated as
  exposed and reset.
- **Postmortem:** in git under the incident's Work ID (**D-038**); no credential, terminal number,
  identifier, device UUID or card data in it.
