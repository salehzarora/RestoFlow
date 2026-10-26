# BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D — Execution packet (local database / test phase, corrections C1 / C2 and integration)

> **Status: LOCAL ONLY — the database / test phase, corrections C1 / C2 and the local integration continuation
> (§15), composed with `main` in §16.** Ticket-local execution packet written before any executable
> SQL, under the command-room authorization "001D COMMAND-ROOM AUTHORIZATION — LOCAL DATABASE / TEST PHASE
> ONLY" (2026-10-24). It pins the anchors, the exact file and SQL manifests, the binding M1–M10 / N24 / N28
> treatments, the tests that prove each item, the Dashboard / l10n portion (held in that phase; implemented locally
> by §15) and the boundary to 001E / 001C / 001F / 001G / 001H. It does **not** amend any **DECISION** (the
> D-051..D-058 texts stay as merged; D-054..D-058 carry dated 2026-10-25 integration notes) and it is
> not a decision record: where the merged contract leaves a detail "fixed by 001D", this packet records the
> fix, and §11 lists every interpretation for command-room review. Nothing here is pushed, deployed, applied
> to a hosted database or enabled.
>
> **Correction C1 (2026-10-24):** the command room's "BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D COMMAND-ROOM DECISIONS —
> BOUNDED LOCAL CORRECTION C1" decided §11 items 4, 24, 26 and 27, required the support-context denial at the
> payment caller proof and a direct M10 operation-type test. The decisions are recorded as **D-059** in
> [DECISIONS](DECISIONS.md) — **approved for this local correction only, not proof of merged or deployed
> behaviour** — and implemented by local correction commits on top of the pre-correction candidate `2e011ea5`
> (its six commits kept; no amend, reset or rebase). §12 records the disposition; the sections below are updated
> in place where C1 changed them. **D-051 … D-058** keep their texts.
>
> **Correction C2 (2026-10-25):** the command room's "LOCAL SUPPORT-BOUNDARY CORRECTION C2" decided §11 items 33
> and 36: a seventh `app.sync_push` change that refuses a request made in an ACTIVE support session, and a required
> original-caller binding on the five session-proving service-only operations. §13 records the decisions, the exact
> function / signature manifest and the test plan before any code; they are recorded as **D-060** (approved for
> local C2 only, not merged or deployed). §14 records the C2 disposition; §0, §1, §3.2, §6, §7, §10, §11 and §13
> are updated in place where C2 changed them (§13's later bullets name the review that added them).
>
> **Local integration continuation (2026-10-25):** the command-room decision "LOCAL INTEGRATION CONTINUATION"
> approved a clean-history local branch and the Dashboard audit UI. §15 records the decision sheet, the
> clean-history proof, the exact manifest, the key manifest, the per-action mapping, the Appendix A dispositions and
> the holds — written before any audit-UI edit — the review amendment (§15.4a) and the disposition (§15.9); the
> title, §0, §1, §7, §9, §10, item 31 of §11, §12 and §14 are updated in place where it changed them. No push, PR,
> merge, hosted or provider action is authorized.
>
> **Local integration composition W2–W6 (2026-10-26):** after #368 and then #366 merged independently (`main`
> `d2079820`), the command-room instruction "COMMAND-ROOM RESUME — DEPENDENCY MERGED, CONTINUE W2–W6" released the
> held steps: a normal local merge of `origin/main`, the localization regeneration from the union of keys, D1 test
> 15, the runner's `db-tests` step and the acceptance-ETA regression pair with the API §4.14 / §4.49 reach text. §16
> records the re-verification, the composition, the changes, the documentation, the gates, the validation, the review
> and the disposition; §0, §1, §2, §7, §9, §10, §12, §14, §15.3, §15.7 (rows 10, R1 and R3) and §15.8 are updated
> in place where it changed them. No push, PR, merge, hosted or provider action is authorized.

---

## 0. Anchors

| Item | Value |
|---|---|
| Work ID | `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D` |
| Contract anchor (M2) | `0caf3f5a04a23805ff4f2bda01e5e0ef3933c012` — merge of PR #363 (001B); the combined merged document set at M2 is the contract (not the standalone #362 design, not an older local checkout) |
| Actual base | `0caf3f5a04a23805ff4f2bda01e5e0ef3933c012` = `origin/main` at the preflight fetch and again at packet time (M2 is the base itself); since 2026-10-26 the integration branch is composed with `main` `d20798203052bfcfcdd58cd009bdc6babf5df12c` (#368, then #366) by the local merge `a1b8c1c0` (§16.2) |
| Branch | `feat/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-server-ledger` (the original local branch; no upstream; never pushed; preserved unchanged at `75ef9d74`); since 2026-10-25 the work continues on the clean-history local branch `feat/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-ledger-integration` (from M2; no upstream; §15.2) |
| Worktree | `worktrees/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D` (original) and `worktrees/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-ledger-integration` (integration), siblings of the main checkout, each fresh |
| Pre-correction candidate (C1) | `2e011ea59b82704af75aed9877ae9d994f64cd9e` — migration SHA-256 `335e4ea9d90859586c4e57ca247f17a3ef088b17dd31e7463ef75a73dc99a5f1`; its migration, tests, runner, packet and evidence are preserved outside Git; `origin/main` was still `0caf3f5a` at the C1 preflight (2026-10-24T06:01:47Z) |
| Contract sections implemented | [API_CONTRACT](API_CONTRACT.md) §4.55 (with §4.14, §4.30b, §4.30c, §4.33, §4.35 item 4 card notes); [DOMAIN_MODEL](DOMAIN_MODEL.md) §8.4–§8.7; [DEPLOYMENT](DEPLOYMENT.md) §18.2 (local proof only); T-023 of [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md); [TESTING_STRATEGY](TESTING_STRATEGY.md) card-present pgTAP lane |
| Decisions in force | **DECISION D-051 … D-058** (texts unchanged; D-054..D-058 carry dated 2026-10-25 integration notes), **D-059** (correction C1 — approved for this local correction only) and **D-060** (correction C2 — approved for local C2 only; dated integration notes of 2026-10-25 and 2026-10-26), neither proof of merged or deployed behaviour; **OPEN QUESTION Q-047** and **Q-049** stay OPEN |

## 1. Scope boundary

**Implemented in this phase (local only):** one new forward-only migration carrying the whole database
portion of 001D (five private tables, the context / service-only / internal / operator functions, the
`app.sync_push` re-creation with its seven changes (change 7 by C2), the additive keys of `app.pin_session_capabilities` and
`app.pos_order_snapshots`, the `card_attempt.*` family in the four Activity-log functions), seven new pgTAP
files, one new Node concurrency runner, and this packet. Applied and tested only in the disposable local stack
of §8. Correction C1 (§12) corrects the same unpublished migration in place through new local commits, extends the
seven pgTAP files and the runner, and records **D-059** with the narrow contract amendments it names. Correction C2
(§13, §14) does the same for **D-060**: the support-context admission guard of `app.sync_push` and the required
original-caller binding of the five session-proving service-only operations.

**Audit UI (required for full 001D completion):** the Dashboard audit registry (`kAuditActionRegistry` entries), the
field labels of the projected card keys (rendered through the per-action allowlist `_cardAttemptKeys` /
`_cardFieldKinds`; the global `_displayableKeys` allowlist is deliberately unchanged, §15.6), the localized values
and the ar / he / en titles for the `card_attempt.*` family
([API_CONTRACT](API_CONTRACT.md) §4.33 "Carrying ticket") were held in this phase (§9) and are implemented locally
by the integration continuation of 2026-10-25 under the key-level ownership plan (§15.4–§15.6, amended in §15.4a;
verified locally, §15.9). **001D is still not
complete, not merge-ready and not deployment-ready:** the composition with #366 / #368 (the l10n regeneration on the
union of keys, D1, the CI step, the acceptance-ETA regression) is done locally since 2026-10-26 (§16); the
publication review, the review gate, the exact-head CI runs and every hosted gate remain (§15.8, §16.5).

**Not implemented here (other Work IDs):** the 001E Edge adapter (`pos-card-charge`, provider transport, key
formatter selection from configuration, amount serializer, reply parser, poll cap), 001C shared transport,
001F POS lab and journal, 001G Dashboard verification, 001H operations (designated device, TEST secret,
mapping rows, physical run). See §10.

**Not touched:** `app.record_payment` (definition, ACL, reachability), the Payment enumeration, `payments`
schema and every financial calculation, every existing migration, POS / KDS / Kiosk / Storefront / printing
source, Edge functions, `supabase/config.toml`, CI (on the integration branch: the one approved `db-tests` step, §16.3), lockfiles, release / signing files, the l10n files (held in this
phase; changed on the integration branch, §15),
`AGENTS.md`, `CLAUDE.md`, `AGENT_WORKFLOW.md`, vendor-private evidence, any credential or test-card file.

## 2. Exact file manifest

New files (the only files this phase creates):

| Path | Purpose |
|---|---|
| `docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001D_EXECUTION.md` | this packet |
| `supabase/migrations/20261023225657_bizbot_zcredit_001d_server_ledger.sql` | the single 001D migration; version generated by `supabase migration new bizbot_zcredit_001d_server_ledger` (CLI 2.107.0) in the worktree — never invented, never reused; it sorts after the then-unmerged #366 (`20261022014650`) and #368 (`20261022192530`) migrations — both on `main` since 2026-10-26 and still before it, so the version is unchanged (§16.1) |
| `supabase/tests/bizbot_zcredit_001d_schema_acl_test.sql` | catalog, RLS, privileges, grant posture, N28, re-creation pins |
| `supabase/tests/bizbot_zcredit_001d_claim_identity_test.sql` | context proof, claim, replay, identity, keys, adapter read, denial evidence |
| `supabase/tests/bizbot_zcredit_001d_recording_recovery_test.sql` | `app.sync_push` guard, identity-first gate, recording result, D-054 Resume, batching, transient |
| `supabase/tests/bizbot_zcredit_001d_test_isolation_test.sql` | TEST mode, pre-ledger TEST refusal, revoked-device carve-out, TEST evidence |
| `supabase/tests/bizbot_zcredit_001d_lifecycle_retention_test.sql` | operator revision, terminal binding lifecycle, capability keys, orphan / TEST closure, holds, purge, tombstones, event immutability |
| `supabase/tests/bizbot_zcredit_001d_field_rules_test.sql` | field rules (M3–M5, M7), finish semantics (M1, M2), owner read |
| `supabase/tests/bizbot_zcredit_001d_regression_test.sql` | default-OFF legacy behaviour and unchanged surfaces |
| `supabase/tests/support/run_bizbot_zcredit_001d_concurrency.mjs` | real independent connections (both winning orders, rollback / retry, lock-wait proofs) |

No shared fixture file is added: every pgTAP file is self-contained (the suites run without `\i`), and the
runner takes its fixture from the claim-identity file's prefix up to the marker
`-- ZC001D FIXTURE END:` (the platform-353 / POS-inbox precedent). Existing docs receive **no** edit in this
phase except, if needed, the narrow M1–M10 / N24 / N28 clarification listed in §11 (none is required for the
local proof; every 001D-fixed detail is recorded here). Correction C1 edits, under its scoped file authorization and
creating no file: [API_CONTRACT](API_CONTRACT.md) (§4.30c, §4.55.2, §4.55.3, §4.55.8, §4.55.9, §4.55.10), [DOMAIN_MODEL](DOMAIN_MODEL.md)
§8.4–§8.6, [STATE_MACHINES](STATE_MACHINES.md) (the inactive-device downward transitions of the terminal binding),
[SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) §12 and T-023, [TESTING_STRATEGY](TESTING_STRATEGY.md) §6,
[DEPLOYMENT](DEPLOYMENT.md) §18.2, [DECISIONS](DECISIONS.md) (**D-059** and its changelog line),
[BIZBOT_PAYMENTS_ZCREDIT_PILOT_001](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001.md) (its decision list and the §5 retention bullet) and this packet.

The composition (§16) adds exactly two non-documentation paths to the integration manifest: test 15 of
`supabase/tests/public_surface_acl_remediation_001_test.sql` and one step of `.github/workflows/ci.yml`; the
acceptance-ETA regression extends the existing regression lane.

## 3. SQL object manifest

All `app.*` RPC, guard, writer, proof, derivation and trigger bodies are `SECURITY DEFINER` (the IMMUTABLE text /
key / detail / configuration helpers, the two lock helpers and `app.card_append_only_guard()` are SECURITY INVOKER);
every family function has `search_path = ''` and owner `postgres`; every `public.*`
wrapper is `LANGUAGE sql SECURITY INVOKER` with `search_path = ''` and the body's volatility. ACL idiom
(precedent migration `20261017092726`): `revoke all … from public, anon, authenticated, service_role;` then
one `grant execute … to <role>` per layer where a grant exists. The pilot scope is the Maps Burger tenant
named by **D-051** point 1 and already pinned in-repo by `20261017004438`: organization
`20605c2b-3145-4803-a990-bbec3d9c1096`, restaurant `de3bbc64-edad-4ff4-bccd-c2ef217c1d56`, branch
`2847c0be-3e31-45a5-957c-508729f1971e` (no device UUID appears anywhere, **D-053** point 6).

### 3.1 Tables (all in `app`; RLS enabled + forced; policy `deny_client` `for all to authenticated using(false) with check(false)`; `revoke all` from public / anon / authenticated / service_role; no sequence grant)

| Table | Key content (full rules in [DOMAIN_MODEL](DOMAIN_MODEL.md) §8.4–§8.7) |
|---|---|
| `app.card_payments_pilot_revisions` | identity `revision` PK; pinned pilot scope CHECK + composite FK to `branches`; `enabled`, `mode`, `window_until` (NOT NULL; default bound §4), `max_test_amount_minor` / `max_live_amount_minor` (NULL or 1..99 999 999 999), `reason` / `operator_reference` under `app.card_safe_text_ok` + canonical-form CHECK, `actor_app_user_id`, `executor_principal`, `recorded_at`; append-only trigger (UPDATE / DELETE / TRUNCATE refused) |
| `app.payment_terminals` | `id`, scope + `device_id` NOT NULL (composite FKs to `branches` and `devices`), `terminal_ref` / `credential_ref` (`^[a-z0-9_-]{1,64}$` + safe-text + canonical CHECK, distinct), `mode`, `lifecycle` (default `configured`), `lifecycle_changed_at`, `created_at`, `updated_at`, `deleted_at`; partial UNIQUE `(organization_id, device_id) where deleted_at is null and lifecycle <> 'retired'`; partial UNIQUE `(organization_id) where lifecycle in ('enabled','draining')`; trigger: insert only as `configured`, transitions `configured→enabled|retired`, `enabled→draining`, `draining→enabled|retired`, `retired` final, scope / mode / references immutable, no DELETE, credential-reference ownership (a `live` reference belongs to one organization + restaurant; a reference never spans modes) |
| `app.card_provider_attempts` | every DOMAIN §8.4 column, with (C1, **D-059** point 1) `claim_signal_at timestamptz NOT NULL` — stamped `created_at` by the insert guard and moved to `clock_timestamp()` by the update guard only when `state`, `order_freed_at` or `resolution` changes, whatever a writer supplies; identity UNIQUE `(organization_id, device_id, local_operation_id)` with the UUID v4 CHECK; digests `bytea` (32 bytes) each UNIQUE; outbound keys each UNIQUE; formatter version in the closed set (§4.3) with a key-length CHECK; mode CHECKs (TEST: no order / shift / drawer / expected revision, `retention_until` set, every card and provider-reference field NULL; LIVE: order / shift / drawer set, `retention_until` NULL); composite FKs to `branches`, `devices`, `orders`, `shifts`, `cash_drawer_sessions`, `employee_profiles`, `memberships`; drawer-belongs-to-shift insert check; partial UNIQUE one claim per order `(organization_id, order_id) where order_freed_at is null and state in ('sent','unknown','released','approved')`; token CHECKs (anomaly, refusal, return class, resolution per mode, freed reason, confirmation source); field-rule CHECKs on every provider / reference / note field; trigger: state machine (disallowed transition = silent no-op), frozen columns immutable, resolution / free predicates (§5 of DOMAIN §8.4, using the shared derivation helper), resolved row frozen except TEST hold metadata, DELETE only for an expired, unheld TEST row |
| `app.card_provider_private_events` | DOMAIN §8.6 columns; (C1, **D-059** point 3) CHECK `card_events_test_device` (`mode IS DISTINCT FROM 'test' OR device_id IS NOT NULL`); action / actor-kind token CHECKs; operator-event CHECK; adapter-event CHECK; `mode` / `retention_until` / hold CHECKs; `reason`, `actor_reference`, `incident_hold_reference` field rules; `detail` allowlist CHECK per action (`app.card_event_detail_ok`); partial UNIQUE `(attempt_row_id) where action='test.card_recording_refused'` and `(attempt_row_id, (detail->>'field'), (detail->>'rule')) where action='security.card_provider_field_dropped'`; trigger: facts immutable, only the hold metadata of a `mode='test'` event may change, DELETE only for an expired TEST event without its own hold whose attempt (if any) carries none |
| `app.card_attempt_identity_tombstones` | PK `(organization_id, device_id, local_operation_id)` with the UUID v4 CHECK; digests and outbound keys each UNIQUE; formatter version; `purged_at`; append-only (UPDATE / DELETE / TRUNCATE refused) |

### 3.2 Functions

Grant columns: **A** = `anon`, **U** = `authenticated`, **S** = `service_role` (EXECUTE). "—" = no grant to any app role
(executable only by the owner / an operator SQL session).

| Function (identity arguments) | Layer / kind | A | U | S |
|---|---|---|---|---|
| `app.card_attempt_context(uuid, uuid, text, uuid, text)` + `public.card_attempt_context(…)` | caller-authority, read-only (renewal is the only write), VOLATILE; (C1, **D-059** point 5) `permission_denied` first, before any proof or renewal, for an ACTIVE platform support session; (C2, **D-060** point 2) its `ok` answer carries `caller_auth_user_id` | — | ✓ | — |
| `app.owner_card_attempts(uuid, uuid, uuid, timestamptz, timestamptz, text)` + `public.owner_card_attempts(…)` (`p_mode` default `'live'`) | caller-authority, STABLE | — | ✓ | — |
| `app.card_attempt_claim(uuid, uuid, text, text, text, bigint, text, uuid, integer, text, jsonb, jsonb, text, uuid)` + public | service-only, VOLATILE; (C2, **D-060** point 2) required final `p_caller_auth_user_id`, checked early, after the full-identity lock and, for LIVE, after the order / shift / drawer locks | — | — | ✓ |
| `app.card_attempt_adapter_read(uuid, uuid, text, text, text, jsonb, jsonb, uuid)` + public | service-only, VOLATILE (may write the security event); (C2) the binding checked early and right after the proof (its final check: the attempt read takes no lock) | — | — | ✓ |
| `app.card_attempt_finish(uuid, uuid, uuid, text, text, bigint, text, text, text, jsonb, text)` + public | service-only, scope-bound; (C2, **D-060** point 4) unchanged — no binding, no support check | — | — | ✓ |
| `app.card_attempt_mark_release_requested(uuid, uuid, text, text, uuid)` + public | service-only; (C2) the binding checked early, after the proof and after the attempt row lock | — | — | ✓ |
| `app.card_attempt_mark_recording_result(uuid, uuid, text, text, text, uuid)` + public | service-only; (C2) the binding checked early, after the proof (before the attempt lookup and the first envelope answer) and after the `sync_operations` → attempt row locks | — | — | ✓ |
| `app.card_attempt_free_order(uuid, uuid, text, text, text, text, text, uuid)` + public | service-only (manager action, **D-058** point 9); (C2) the binding checked early, after the proof and after the `orders` → attempt row locks | — | — | ✓ |
| `app.card_claim_guard(uuid, uuid, uuid, text, text, text, uuid)` | internal to `app.sync_push` | — | — | — |
| `app.card_recording_resume_guard(uuid, uuid, uuid, integer, text, uuid, timestamptz, jsonb)` | internal to `app.sync_push` (signature carries the resent envelope fields, §11 item 7) | — | — | — |
| `app.set_card_payments_pilot(boolean, text, timestamptz, bigint, bigint, text, text, uuid)` | operator-only | — | — | — |
| `app.set_payment_terminal(uuid, text, text, text, text, text, text, text, uuid)` | operator-only; (C1, **D-059** point 2) an inactive, deleted or management-revoked pilot POS device only for `draining` / `retired` | — | — | — |
| `app.card_attempt_resolve_orphan(uuid, text, text, text, text, uuid)` | operator-only | — | — | — |
| `app.card_attempt_set_incident_hold(text, uuid, boolean, text, text, text, uuid)` | operator-only | — | — | — |
| `app.purge_expired_test_card_attempts(text, text, uuid, integer)` | operator-only; (C1, **D-059** point 3) `p_max_devices integer DEFAULT NULL`, one bounded batch — the three-argument form existed only in the unpublished pre-correction candidate | — | — | — |
| `app.card_identity_lock(uuid, uuid, text)` / `app.card_terminal_lock(uuid, uuid)` | internal lock helpers (`card-identity/v1:` / `card-terminal/v1:` keys of §4.55.3) | — | — | — |
| `app.card_caller_binding_denial(uuid)` | (C2, **D-060** point 2) internal, STABLE, SECURITY DEFINER: NULL for a valid caller outside an ACTIVE support session, else `invalid_request` / `invalid_session` / `permission_denied`; called only by the five session-proving service-only bodies | — | — | — |
| `app.card_safe_text_ok(text, text)` | internal, IMMUTABLE, SECURITY INVOKER (contract helper; CHECK constraints) | — | — | — |
| `app.card_safe_text_failure(text, text)` / `app.card_text_canonical(text)` / `app.card_text_absent(text)` | internal, IMMUTABLE, SECURITY INVOKER (the rule token behind `card_safe_text_ok`; the M4 canonical form; the linear M4 absent test, §4.5) | — | — | — |
| `app.card_provider_key(bytea, text)` | internal, IMMUTABLE (the closed formatter set, §4.3; called by the claim, the ledger and tombstone key CHECKs, and tests) | — | — | — |
| `app.card_event_detail_ok(text, jsonb)` | internal, IMMUTABLE (private-event detail allowlist CHECK) | — | — | — |
| `app.card_attempt_proof(uuid, uuid, text, boolean)` | internal session proof (renewing for the context proof, non-renewing for service-only bodies) | — | — | — |
| `app.card_attempt_derive(app.card_provider_attempts)` | internal, STABLE (strict `recorded` join, `payment_id`, classification, reason, `recoverable`, active claim, close predicate, unresolved) | — | — | — |
| `app.card_attempt_envelope(app.card_provider_attempts)` | internal, STABLE (the §4.55.4 response shape) | — | — | — |
| `app.card_order_claim_active(uuid, uuid)` / `app.card_shift_close_blocked(uuid, uuid)` | internal, STABLE (active claim; canonical close predicate) | — | — | — |
| `app.card_active_manager_denial(uuid, uuid)` | internal, STABLE (the **D-057** point 3 active-manager proof; NULL or the denial token) | — | — | — |
| `app.card_dispatch_certain_deny(uuid, uuid, text, uuid)` | internal (the guard's payload-independent "certain to deny" check; membership read FOR SHARE) | — | — | — |
| `app.card_pilot_revision_current()` | internal, STABLE (latest revision row) | — | — | — |
| `app.card_attested_approver_ok(uuid)` | internal, STABLE (active `org_owner` / `restaurant_owner` of the pilot scope) | — | — | — |
| `app.card_private_event_write(…)` | internal writer of `app.card_provider_private_events` (ON CONFLICT on the two dedupe indexes only, M1) | — | — | — |
| `app.card_identity_digest(text, uuid, uuid, text)` | internal, IMMUTABLE (the D-058 point 2 SHA-256 of the domain-separated identity; also used by the ledger and tombstone CHECKs) | — | — | — |
| `app.card_attempt_payment_id(app.card_provider_attempts)` | internal, STABLE (the strict-join payment of a LIVE attempt) | — | — | — |
| `app.card_audit_write(uuid, uuid, uuid, uuid, uuid, text, jsonb)` / `app.card_denial_evidence(text, uuid, uuid, uuid, uuid, uuid, uuid, text, text)` | internal writers of the LIVE `card_attempt.*` audit and of the mode-aware denial evidence | — | — | — |
| `app.card_attempt_resolve(jsonb, text)` | internal, STABLE (§4.55.2 resolution: `manager`+ by organization + branch + attempt id — `conflict` on more than one match; every other role its own device only; §11 item 20) | — | — | — |
| `app.card_proof_denial_evidence(jsonb, uuid, text, text)` | internal writer (a mark's write-time `permission_denied` with a proven scope → the mode-aware denial evidence of the originating device's attempt; §11 item 13) | — | — | — |
| `app.card_config_mismatch(text, uuid, text, text, text, jsonb, jsonb)` | internal, IMMUTABLE (the §4.55.4 / §4.55.5 configuration-record check; NULL or a closed mismatch token) | — | — | — |
| `app.card_terminal_posture(uuid, uuid, uuid)` | internal, STABLE (the exact device's binding lifecycle / mode and the `card_terminal_enabled` predicate) | — | — | — |
| trigger functions `app.card_append_only_guard()`, `app.payment_terminals_guard()`, `app.card_attempts_insert_guard()`, `app.card_attempts_guard()`, `app.card_events_guard()` | trigger only | — | — | — |

Correction C2 adds one function, `app.card_caller_binding_denial(uuid)`, so the family is 55 (SA-120 restated; the five
changed wrappers differ from C1 by exactly the binding, SA-119). Correction C1 added and removed no function: the family
stayed exactly 54 functions (the purge's identity
arguments gained `integer`; every other signature, ACL, owner, SECURITY mode and `search_path` is unchanged and the
eight public card wrappers are byte-identical to the pre-correction candidate — SA-119, SA-120).

Re-created (CREATE OR REPLACE, exact signature, ACL re-issued verbatim; wrappers untouched):

| Function | Live source | Documented change only |
|---|---|---|
| `app.sync_push(uuid, uuid, jsonb)` | `20261008170200` L39–954 | the seven changes of §6 (change 7 by C2, **D-060** point 1) |
| `app.pin_session_capabilities(uuid, uuid)` | `20261008190000` L1092–1221 | `branch_features.card_terminal_enabled` / `card_terminal_mode`, emitted only when the session's exact device has a `configured` / `enabled` / `draining` mapping row (absent ⇒ hidden, fail closed; §11 item 3) |
| `app.pos_order_snapshots(…9 args…)` | `20261008190000` L779–1076 | row key `card_attempt_in_progress: true` emitted only while the order has an active claim (absent ⇒ no claim; §11 item 4) and (C1, **D-059** point 1) the newest `claim_signal_at` of the order's LIVE attempts of the same organization, branch and order joined into `sync_at` through `greatest`, so a claim's start and end reach the incremental cursor without churn — a named 001D extension recorded in [API_CONTRACT](API_CONTRACT.md) §4.30c / §4.55.3 and [DEPLOYMENT](DEPLOYMENT.md) §18.2, not part of the earlier two-key list; the key and its stamp both count only the order's own-branch LIVE attempts (the guard's set for every row the RPCs write), and every state transition re-delivers the order once (the recorded over-inclusion, bounded) |
| `app.audit_category(text)` | `20260725090000` L2797–2824 | `card_attempt.%` → `payments` |
| `app.audit_action_has_detail(text)` | `20261008170200` L1334–1388 | `or p_action like 'card_attempt.%'` |
| `app.audit_safe_detail(text, jsonb)` | `20261008170200` L1401–1536 | an action-scoped early branch for `card_attempt.%` with a per-action allowlist (no global key added; §4.7) |
| `app.owner_audit_events(…11 args…)` | `20261008170200` L2045–2267 | the four sensitive actions of §4.33 in the `p_sensitive_only` set |

`app.close_shift`, `app.reconcile_shift`, `app.record_payment` and every other function are **not** re-created
(the `shift.close` exclusion lives in the sync-arm guard).

### 3.3 Locks (the §4.55.3 canonical order)

terminal / device advisory lock (`pg_advisory_xact_lock(hashtextextended('card-terminal/v1:'||org||':'||device, 0))`)
→ [claim: shared purge barrier `pg_advisory_xact_lock_shared(hashtextextended('card-purge/v1', 0))` → proof
identity-row locks] → full-identity advisory lock (`'card-identity/v1:'||org||':'||device||':'||local_operation_id`)
→ `sync_operations` FOR UPDATE → `orders` FOR UPDATE → `shifts` FOR UPDATE → `cash_drawer_sessions` FOR UPDATE
→ `card_provider_attempts` FOR UPDATE → (inside the unchanged `record_payment`) `branch_receipt_counters`.
Operator paths only: `app.set_card_payments_pilot` serializes on `'card-pilot-revision/v1:'||org||':'||branch`
right before it draws the revision (after its argument, authority and field-rule checks, so a refused call holds no
lock), and every `app.payment_terminals` INSERT takes
`'card-credential-ref/v1:'||credential_ref` before its ownership check (two operator calls for different devices
naming one reference therefore serialize). The TEST purge (C1, one bounded batch) takes the terminal / device locks
of its selected device set in device-id order, then the exclusive purge barrier, then the attempt rows FOR UPDATE;
it never takes the terminal lock of a device outside its set (a claim of such a device still waits on the shared
purge barrier while the batch holds it). Membership rows are only ever taken FOR SHARE by card paths. The advisory locks in `app.sync_push` are taken
outside the per-operation exception block (a failure there aborts the whole call, nothing memoized).

## 4. Details fixed by 001D

### 4.1 Codes and shapes

- Refusals RETURN `{ok:false, error, detail?}` (+ `attempt_id` / `attempt_state` siblings only where §4.35 item 4
  allows; the service-only bodies and the `app.sync_push` guard refusals also carry `server_ts`; the read-only
  context proof and the operator RPCs answer the bare shape, as their precedents do; `app.owner_card_attempts`
  raises 42501 / 22023 for authentication, scope, mode and range faults, like its `owner_*` precedent, and returns
  `permission_denied` only for a non-reader role); provider outcomes RETURN the
  §4.55.4 envelope
  `{ok:true, attempt_id, state, classification, provider_return_code?, refusal_code?, anomaly_code?, resolution?,
  recorded, recoverable?, resume_count?, payment_id?, amount_minor, currency_code, server_ts}`.
- The claim and the adapter read add, for the adapter only: `attempt_row_id`, `organization_id`, `device_id`,
  `local_operation_id`, `mode`, `restaurant_id`, `terminal_ref`, `credential_ref`, `start_deadline_at`; the claim
  adds `claim_created` / `replayed` and, for the row it inserted only, `provider_key_format_version`,
  `provider_query_key`, `provider_duplicate_key`; the adapter read adds the stored version and keys and
  `auto_poll_count`, `last_lookup_at`, `release_requested_at`, `start_deadline_passed`.
- Claim refusal order (LIVE) under the `orders` lock: `order_not_chargeable` → `order_already_settled` →
  `payment_in_progress` (an active claim of another attempt, before the unique index) →
  `precondition_failed/ineligible_order_state` (also a missing / out-of-scope order) → `conflict` (stale
  `expected_revision`) → `amount_mismatch` → `precondition_failed/max_live_amount_exceeded` →
  `precondition_failed/no_open_shift` | `no_active_drawer`.
- Start deadline: `start_deadline_at = claim time + 120 s` (001E's commit budget must stay below it and below
  the 150 s platform idle timeout).
- Operator revision default window: `p_window_until` NULL → `now() + 12 hours`; an enabling call requires a
  future window. Amount bound for every amount and cap: `1 .. 99 999 999 999` minor units (the inbound grammar's
  nine integer digits).
- TEST currency: `coalesce(restaurants.currency_override, organizations.default_currency)` of the proven scope.

### 4.2 Finish inputs (`p_provider_fields`, produced by 001E, validated here)

`p_source` ∈ `commit` | `lookup` | `release`; `p_outcome` per source: commit `approved` | `declined` |
`unknown` | `anomaly`; lookup `approved` | `declined` | `anomaly` | `not_found` | `pending` | `failed`;
release `released` | `release_failed`. `p_poll_source` ∈ `auto` | `operator` | NULL (`auto` increments
`auto_poll_count` on a lookup). Allowlisted keys (any other key is ignored, never stored — a vendor message
included):

| Key | Kind | Rule |
|---|---|---|
| `error_flag` | essential | JSON boolean |
| `provider_return_code` | essential | JSON integer within ±999 999 |
| `approval_type` | essential, stored | `^[A-Za-z0-9_-]{1,16}$` + safe text |
| `phone_authorization` | essential | JSON boolean |
| `provider_status_code` | essential, stored | `^[A-Za-z0-9_-]{1,16}$` + safe text |
| `provider_amount` | essential | JSON string `^(0|[1-9][0-9]{0,8})\.[0-9]{2}$` (integer arithmetic) |
| `provider_currency` | essential | JSON string `^[A-Z]{3}$` |
| `tip_amount` | essential | JSON string, amount grammar |
| `anomaly_code` | outcome input (`anomaly` only) | the seven tokens |
| `provider_return_class` | informational (M3) | closed set §4.4, fallback; an empty / Space_Separator-only string is absent |
| `provider_reference`, `deposit_id` | non-essential | `^[A-Za-z0-9-]{1,32}$` + safe text |
| `approval_number`, `voucher_number` | non-essential | `^[A-Za-z0-9]{1,16}$` + safe text |
| `card_last4` | non-essential | `^[0-9]{4}$` after NFKC (fullwidth digits fold) |
| `card_brand_code`, `pan_entry_mode`, `payment_method_code` | non-essential | `^[A-Za-z0-9_-]{1,16}$` + safe text |
| `provider_saved_at` | non-essential (provider timestamp) | JSON string, ISO-8601 / RFC 3339 `YYYY-MM-DD[Tt ]HH:MM:SS[.f{1,9}]` with `Z` / `z` or a `±HH[[:]MM]` offset (fractions rounded to microseconds), and a valid `timestamptz` (no special literal such as `now` / `epoch` / `infinity`, no zone-less or date-only value) |

Absent, JSON null, or an empty string after the canonical trim = absent (NULL, no event). A present failing
field writes one `security.card_provider_field_dropped` (`field`, `rule` ∈ `charset` | `length` |
`control_character` | `digit_run` | `masked_pattern` | `format`, `source`). A TEST attempt discards its card
and provider-reference fields unread (no event) and still checks `provider_saved_at`.

### 4.3 Key formatter — closed candidate set (M7, M8)

`provider_key_format_version` ∈ `alpha16-l20-v1` | `alpha16-l24-v1` | `alpha16-l32-v1`. Each key is the first
N hexadecimal nibbles of its full SHA-256 digest (N = 20 / 24 / 32), each nibble `0..15` mapped to the letter
`a..p` (`translate(hex, '0123456789abcdef', 'abcdefghijklmnop')`). The alphabet `{a..p}` contains no decimal
digit of any script (Nd) and no mask code point (`x` / `X` are outside `a..p`), so no output can trip the
digit-run or masked-pattern rule — a proof by construction, re-checked by FR tests over many identities and by
the ledger CHECK `^[a-p]{20,32}$` with the version's exact length. Collision space 80 / 96 / 128 bits; every
key and digest is UNIQUE across the ledger and the tombstones. **No candidate is runtime-supported without the
sealed Q-049 evidence**: the version is chosen only by the owner-sealed configuration (001E validates and
passes it); an unknown, NULL or unselected version is `provider_unavailable` before any lock, ledger row or
provider action (a typed pre-claim refusal). **Extension gate (M8):** a sealed Q-049 format that matches none
of the three needs a separately approved additive migration (new version token, CHECK and test) plus an Edge
redeploy, slotted after DEPLOYMENT §18.1 step 5 and before step 6 (no secret or physical test before it);
nothing is guessed. A POS "new identity" option is allowed only after a conclusive no-claim / no-request
refusal — never after a timeout, UNKNOWN or an existing attempt — and is recorded for 001F, not implemented.

### 4.4 `provider_return_class` vocabulary (M3)

`approved` | `declined` | `error` | `pending` | `not_found` | `duplicate` | `phone_authorization` |
`unclassified` (fallback for any other or non-string value; an empty or Space_Separator-only string is absent
and keeps the stored class). Informational only: it never decides state,
classification or anomaly; the vendor's free-text message is never accepted as a column, never persisted and
never projected.

### 4.5 Canonical text and field rules (M4, M5)

- **Canonical form (M4):** `app.card_text_canonical(v) = nullif(btrim(normalize(v, NFKC), <Zs set>), '')`,
  where the trimmed boundary set is exactly the 17 Space_Separator code points of Unicode 15.1 (U+0020, U+00A0,
  U+1680, U+2000–U+200A, U+202F, U+205F, U+3000). Stored values are canonical: every stored free-text and reference
  column CHECK requires `value = app.card_text_canonical(value)`; the ASCII-grammar columns (`terminal_ref`,
  `credential_ref`, the outbound keys, `card_last4`) are canonical by their grammar. The control-character, printable-allowlist, digit-run and masked-pattern rules are applied to the
  **raw** value and to the **canonical** value; the field grammar and the length range apply to the canonical value
  (the raw length only through the 4 × max bound below) (e.g. U+2122 "™" between digit groups: NFKC turns it
  into the letters `TM`, and both forms are refused by the whole-field digit count of C1 and tested), and the
  canonical form is idempotent.
- **Closed category policy (M5; closed by **D-059** point 4 in C1), three pinned sources:** Unicode Character
  Database **15.1.0** (`https://www.unicode.org/Public/15.1.0/ucd/`, the PostgreSQL 17 Unicode version) —
  `UnicodeData.txt` SHA-256 `2fc713e6a31a87c4850a37fe2caffa4218180fadb5de86b43a143ddb4581fb86`,
  `DerivedCoreProperties.txt` SHA-256 `f55d0db69123431a7317868725b1fcbf1eab6b265d756d1bd7f0f6d9f9ee108b` and
  `extracted/DerivedNumericType.txt` SHA-256 `0f22ca7770c836211e2b5390c6c9c3b5faae8e60cd8a59f244a43f9f5421cddd`;
  shared with 001E, which must derive its tables from the same three files by the same recipe and apply the same
  vectors. Classes (ranges / code points): **printable allowlist** General_Category `L*`, `M*`, `N*`, `P*`, `S*`,
  `Zs` plus exactly U+061C, U+200C, U+200D, U+200E, U+200F (710 / 149 646); **refused controls** `Cc`, `Zl`, `Zp`,
  every other `Cf` (bidi embeddings / overrides / isolates, U+200B, U+2060, U+FEFF, U+00AD, the invisible operators
  and tags included) and every other `Default_Ignorable_Code_Point` — the Hangul fillers U+115F, U+1160, U+3164,
  U+FFA0, U+034F, U+17B4 / U+17B5, U+180B–U+180F, the variation selectors U+FE00–U+FE0F and U+E0100–U+E01EF … —
  refused, never stripped into an accepted value (26 / 4 268, of which the Default_Ignorable part is 16 / 4 169);
  **non-digit numerics** `Numeric_Type=Numeric` — fractions, Roman numerals, circled ten and above, CJK numerals,
  Ethiopic tens … — refused, never a separator (162 / 1 114); **digit-like** `Numeric_Type` Decimal or Digit —
  every script, full-width, mathematical, superscript, circled, dingbat, Ethiopic (83 / 808: 680 Decimal + 128
  Digit); the **39-code-point mask set** (unchanged: U+0023 `#`, U+002A `*`, U+0058 `X`, U+0078 `x`, U+00B7,
  U+00D7, U+0425, U+0445, U+066D, U+2022, U+2023, U+2027, U+2043, U+204C, U+204D, U+204E, U+2217, U+2219, U+22C5,
  U+25CF, U+25D8, U+25E6, U+2619, U+2715, U+2716, U+2731, U+2765, U+2767, U+29BE, U+29BF, U+2A2F, U+30FB, U+FE5F,
  U+FE61, U+FF03, U+FF0A, U+FF38, U+FF58, U+FF65 — every UCD 15.1 code point named `BULLET` (13; U+1F685, a
  train, aside) plus the ASCII tokens and their compatibility / confusable forms); the **mask-rule keep set** —
  non-modifier letters, digit-like characters and masks (724 / 137 170; everything else, a modifier letter such as
  U+0640 TATWEEL included, is a separator); the **visible set** — letters outside Default_Ignorable and digit-like
  characters (725 / 137 530). `Co`, `Cs` and `Cn` (unassigned in 15.1, Emoji 16 included) stay outside the
  allowlist.
- **Rules (C1), in token order, on the raw value R and its canonical form C:** (1) R contains a refused control →
  `control_character`; (2) R outside the allowlist or containing a Numeric character → `charset`; (3) trimmed R
  longer than 4 × the field maximum → `length`; (4) C absent → `length`, C contains a refused control →
  `control_character`, C outside the allowlist, containing a Numeric character or (structured fields) outside the
  field grammar → `charset`; (5) C outside the field's length range or — for `reason` and `order_freed_note` —
  holding no visible letter or digit → `length`; (6) 12 or more digit-like characters anywhere in R or anywhere in
  C — nothing between them resets the count, Luhn-valid or not → `digit_run`; (7) R or C, with its separators
  removed, matches digit-like{4} + mask{1,} + digit-like{4}, mask{3} + digit-like{4} or digit-like{4} + mask{3} →
  `masked_pattern`. Only these closed tokens (and the field name) reach an error, a private event or an audit row;
  no value is echoed. The policy does not claim to detect every conceivable encoding of a card number.
- **Cost bound and absent test (M4):** before NFKC (whose mark reordering is quadratic in a run of combining
  marks) and after the raw control / charset checks, a value whose Space_Separator-trimmed raw length exceeds
  4 × the field maximum answers `length` — the largest canonical decomposition in UCD 15.1 is 4 code points
  (U+1F82 and 35 siblings), so such a value's canonical form is necessarily longer than the maximum: it is refused
  either way, and only the returned rule token may differ (`length` where the canonical `control_character` /
  `charset` check would have answered first; the token precedence is raw `control_character` → raw `charset` →
  `length` bound → canonical `control_character` → canonical `charset` → `length` (the visible-character rule
  included) → `digit_run` → `masked_pattern`). `app.card_text_absent(v)` = `v IS NULL OR btrim(v, <Zs set>) = ''` replaces
  `card_text_canonical(v) IS NULL` wherever a raw, unbounded value is tested for absence (finish provider fields,
  `free_order` text, operator references); both are equal for every input because NFKC maps each
  Space_Separator only to Space_Separators and maps every other code point to a sequence holding a
  non-Space_Separator (checked over every code point on the local server, Unicode 15.1).
- **Recipe (no committed generator):** parse `UnicodeData.txt` (`<…, First>` / `<…, Last>` pairs expand to
  ranges), the `Default_Ignorable_Code_Point` lines of `DerivedCoreProperties.txt` and the `Decimal` / `Digit` /
  `Numeric` lines of `extracted/DerivedNumericType.txt` (each file checked against its pinned SHA-256 first); merge
  consecutive code points per class (the counts above); emit them as `\uXXXX` / `\UXXXXXXXX` bracket ranges inside
  the PL/pgSQL constants of `app.card_safe_text_failure`. The comment above `app.card_safe_text_failure` repeats the
  three sources, their hashes and the counts;
  the local evidence includes an exhaustive cross-check of the database classes against the file for every code
  point. A committed shared generator or data file would be a new shared tool outside this allowlist: it is
  **not** added (proposal, if wanted: `tools/card_text_policy/` owned by 001D/001E jointly, separate approval).
- **Field table:** `provider_reference`, `deposit_id` `^[A-Za-z0-9-]{1,32}$`; `approval_number`,
  `voucher_number` `^[A-Za-z0-9]{1,16}$`; `card_last4` `^[0-9]{4}$`; `card_brand_code`, `approval_type`,
  `pan_entry_mode`, `payment_method_code`, `provider_status_code` `^[A-Za-z0-9_-]{1,16}$`; `provider_query_key`,
  `provider_duplicate_key` `^[a-p]{1,64}$`; `terminal_ref`, `credential_ref` `^[a-z0-9_-]{1,64}$`;
  `confirmation_reference`, `resolution_reference`, `incident_hold_reference`, `operator_reference`,
  `actor_reference` `^[A-Za-z0-9._:/-]{1,64}$`; `order_freed_note`, `reason` printable allowlist, 1–200 code
  points with at least one visible letter or digit (C1). The UUID identity, the formatter version and closed tokens keep only their own CHECKs.

### 4.6 Private-event detail allowlists

`operator.payment_terminal_updated`: exactly `binding_mode`, `prior_lifecycle`, `new_lifecycle`,
`starts_admitted`, `reason_code`; `security.card_provider_field_dropped`: exactly `field`, `rule`, `source`;
`test.card_recording_refused`: none; `security.card_finish_scope_mismatch`: boolean mismatch flags
`organization_id`, `device_id`, `local_operation_id`, `mode`, `amount_minor`, `currency_code`;
`security.card_credential_mismatch`: `check` (closed token) and `source` (`claim` | `adapter_read`);
`test.card_attempt_denied`: `rpc` (closed token), `denied_reason`; `operator.card_payments_pilot_updated`:
`enabled`, `mode`, `window_until`, `max_test_amount_minor`, `max_live_amount_minor`;
`operator.card_attempt_orphan_resolved` / `operator.card_attempt_test_closed`: `resolution`, `attempt_state`;
`operator.card_test_attempt_hold_updated`: `target_kind`, `hold`; `operator.card_test_attempts_purged`:
`attempts_purged`, `events_purged`, `attempts_deferred`, `events_deferred`, `devices_locked`, `cutoff` (C1); `security.card_resolution_contradicted`: `source`,
`outcome`. Scalars only; never a credential, terminal / credential reference, key, payload or provider text.

### 4.7 Tenant audit (`card_attempt.*`, LIVE only)

Safe detail per action (action-scoped, never a global key): `started` → `attempt_state`, `mode`,
`amount_minor`, `currency_code`; `approved` / `declined` / `unknown` / `released` / `provider_anomaly` →
`attempt_state`, `refusal_code`, `anomaly_code`, `release_requested`; `release_requested` / `release_failed` →
`attempt_state`; `recording_refused` → `refusal_code`; `order_freed` → `attempt_state`, `confirmation_source`;
`recording_resume_requested` → `attempt_state`, `prior_refusal_code`, `resume_count`, `outcome`,
`denied_reason`; `denied` → `denied_reason`. Category `payments`; sensitive: `provider_anomaly`,
`recording_refused`, `order_freed`, `recording_resume_requested` (+ `denied` through `%denied`). `reason` is
always NULL on these rows (the Activity log returns it raw).

## 5. M1–M10 treatments and their proofs

| Item | Treatment (recorded before code) | Proof (test IDs) |
|---|---|---|
| **M1** | The dropped-field event is inserted with `ON CONFLICT (attempt_row_id, (detail->>'field'), (detail->>'rule')) WHERE action = 'security.card_provider_field_dropped' DO NOTHING` (and the TEST refusal event on its own partial index); no `WHEN OTHERS`, so any other error still raises | FR: an UNKNOWN commit dropping `provider_reference` followed by an approving lookup dropping it again → approval written, exactly one event; a different rule on the same field → a second event; a forced non-dedupe error still raises |
| **M2** | Missing approval input never approves: a commit `approved` needs `error_flag=false`, `provider_return_code=0`, a valid `approval_type`, no `phone_authorization=true`, a tip absent or `0.00`; otherwise UNKNOWN (an unreadable tip → `out_of_contract` anomaly; a non-zero tip → `amount_mismatch` anomaly). A lookup `approved` needs a valid status code, amount and currency equal to the attempt's and no `error_flag` / `phone_authorization` = `true` (§11 item 30); a present essential input that fails its rule (or an unreadable tip) on a lookup `approved` / `declined` / `anomaly`, a missing status code / amount / currency on `approved`, or a missing `approval_type` on `declined` becomes the `out_of_contract` anomaly with `charge_may_exist` — never `declined` (a lookup `anomaly` with no failing input keeps its allowlisted code); `not_found` / `pending` / `failed` stay unchanged (events written; a `sent` row past its deadline becomes `unknown`) | FR: one case per missing / failing input per source; parser proofs remain 001E's |
| **M3** | Closed `provider_return_class` set + `unclassified` fallback (§4.4); no message key is read or stored; no column for it | FR: unknown token, non-string and message key cases; catalog test lists the exact ledger columns |
| **M4** | NFKC + the exact Zs trim set; canonical-form CHECK on every stored text column; rules on raw and canonical forms; the linear 4 × max bound and the linear absent test (§4.5) | FR: U+2122 case, fullwidth / superscript digits, NBSP and U+3000 trim, length after normalization, idempotence (`canonical(canonical(v)) = canonical(v)`), a direct non-canonical insert refused by CHECK |
| **M5** | Closed UCD 15.1.0 policy + explicit 39-point mask set (§4.5); closed in C1 by **D-059** point 4 (three pinned property files, Default_Ignorable and Numeric refused, the whole-field digit-like count, the visible-character rule) | FR: Arabic-Indic / Devanagari / fullwidth digits, separators (NBSP, ZWJ, combining marks), every mask code point, invisible formats (U+200B, U+2060, U+FEFF, bidi isolates), Hebrew / Arabic reasons with the allowed marks; C1: FR-291..FR-343 (generated synthetic vectors, exhaustive over the Default_Ignorable, other-control, Numeric, digit-like and `Lm` classes, raw and canonical); local evidence: the exhaustive per-code-point cross-check of all seven classes against the three files |
| **M6** | `app.set_card_payments_pilot` validates caps only when `p_enabled = true`; an authorized OFF revision is always recordable (an invalid cap on an OFF call is recorded NULL); ON / start validation unchanged (TEST ON without a valid cap → `precondition_failed/max_test_amount_missing`; a TEST start under a cap-less revision → `card_payments_disabled`) | LR: OFF with absent / zero / negative cap accepted; ON refused; start refused |
| **M7** | Closed formatter set, construction proof, `provider_unavailable` for an unknown / NULL version before any lock or row (§4.3) | CI: unknown / NULL / empty version → no ledger row, no event; FR: every candidate over thousands of identities passes the key field rule and the digit / mask rules |
| **M8** | Extension gate documented (§4.3); **Q-049** stays OPEN | packet only |
| **M9** | The claim catches `unique_violation` and maps exactly the four key / digest constraints (and the one-claim index → `payment_in_progress`; the identity constraint → replay) to typed refusals; any other constraint re-raises | concurrency runner: a colliding key committed by another connection while the claim waits → `conflict/identity_in_use`, no row; a purge holding the barrier vs a claim of the purged identity → `identity_in_use` |
| **M10** | The Resume guard compares stored vs resent `target_entity`, `target_id`, `client_created_at` with `IS NOT DISTINCT FROM`, the payload by jsonb equality and the fingerprint by recomputation; operation type / fingerprint mismatches stay the preamble's `conflict` | RR: null/null passes, null/value and value/value differences → `operation_mismatch`, payload → `conflict` (RR-088), timestamp difference → `operation_mismatch`; C1 direct type-change test (RR-227..RR-238): `order.void` and each of the dispatcher's 16 other operation types under a reused recording identity — with and without `recording_resume`, on the valid and the revoked-device path, and the reverse direction — refused with no reopen, no dispatch, no Resume-count consumption, no payment and unchanged provider facts, the genuine Resume still authorized afterwards |

## 6. `app.sync_push` — the seven changes (everything else byte-identical, mis-encoded comment bytes included)

1. **Claim guard in six arms** — `v_dispatch := app.card_claim_guard(…)` immediately before the existing call in
   `payment.create`, `order.discount`, `order.edit`, `order.items_add`, `order.void` (order id passed through a
   non-raising UUID parse) and `shift.close` (shift id); a NULL result runs the unchanged call; a refusal becomes
   the RETURNed `{ok:false}` that the unchanged finalization merges.
2. **D-054 reopen** — protected `recording_resume` parse at the per-operation boundary of both paths (before the
   fingerprint; `invalid_payload`, no ledger row, on another operation type, a non-integer, a value outside 0..3 or
   beside a non-empty `depends_on` — in the valid path a non-array `depends_on` keeps today's `invalid_depends_on`,
   which runs first); in the valid path's terminal-replay branch a `rejected`
   `payment.create` carrying the key is handed to `app.card_recording_resume_guard`; a reopen dispatches the same row
   once, a refusal replays the stored result with `resume_denied`; in the adopt branch a row whose LIVE attempt has
   `recording_resume_count > 0` is dispatched only under the active-manager proof, else `resume_authority_required`
   (retryable, row kept `pending`, no audit).
3. **Single-operation check** — before either loop (after the terminal lock): a call of more than one operation
   holding `shift.close`, a provider-identity `payment.create` or a `payment.create` carrying `recording_resume` is
   answered `single_operation_required` for every operation (identity keys as received; the revoked path keeps
   `device_revoked:true`), no ledger row, no audit.
4. **Transient classification** — in the caught branch, ahead of the `40001` branch: a card-sensitive operation whose
   SQLSTATE class is `08`/`40`/`53`/`55`/`57`/`58`/`XX` and whose message does not start with `record_payment:` /
   `close_shift:` returns its row to `pending` (`last_error_class='transient'`, `last_error_code=SQLSTATE`), answers
   `transient_failure` (retryable) and writes no audit.
5. **Admission serialization** — `app.card_terminal_lock` once per call holding any `payment.create` (both paths,
   before any operation); `app.card_identity_lock` immediately before each `payment.create`'s ledger-claim step
   (both paths).
6. **Pre-ledger TEST refusal** — valid path, `payment.create`, under both locks, after the guard's payload-independent
   authorization check: a TEST attempt or a tombstoned identity is answered `test_attempt_not_recordable` (or
   `permission_denied`) with `{local_operation_id, operation_type, ok:false, error, status:'rejected',
   idempotency_replay:false, server_ts, order_id}`, no ledger row, no tenant audit, and at most one
   `test.card_recording_refused` per attempt (none for a tombstone).
7. **Support-context admission guard (C2, D-060 point 1)** — the first statement of the body: a request whose
   verified caller holds an ACTIVE platform support session (`app.current_support_session()`, reused unmodified)
   raises the entrypoint's request-level refusal `42501` `sync_push: permission denied (active support session)`
   before every other check, lock, path, ledger step, replay, Resume and dispatch (§13.1).

PRE / POST proof: the function text is captured before the migration and after it, CR-normalized, and diffed; the
diff must consist of exactly these seven changes — their insertions, the declaration block and three in-place line
edits (change 2's terminal-replay condition and its replay-result line; change 4's `if` → `elsif` on the `40001`
branch) — plus the comment re-stamp outside the definition. Changes 1–5 and 7 are marked
`BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D change N`; change 6 is marked `Change 6 (D-058 point 7)` inside the change-5
block (the re-emit header says so since C2; the body is unchanged).

## 7. Tests and acceptance evidence

| File / lane | Proves (T-023 items and this packet) |
|---|---|
| schema_acl (SA, 139) | five tables, RLS forced, `deny_client`, zero table privileges for anon / authenticated / service_role; the EXECUTE grants of all 54 (C2: 55) family functions on both layers for anon / authenticated / service_role (§3.2, the two review-fix helpers included, with their call sites); DEFINER / INVOKER / search_path / owner; no wrapper for internal / operator functions; `app` not anon-usable; the REPORT-123 family guard; re-created functions keep signature and ACL; ledger column list (no provider free-text column); **N28**; C1 (SA-110..SA-120): `claim_signal_at` (no column ACL or grant, named only by the two ledger guards), the snapshot's `max(claim_signal_at)` join with its branch term, the `card_events_test_device` CHECK, the four-argument purge with the operator ACL and its privilege refusals in both call forms, the eight public card wrappers byte-identical to the pre-correction candidate and the family still exactly 54 functions; C2 (SA-121..SA-138; SA-035..SA-050, SA-053, SA-119, SA-120 re-pinned for the family of 55, **D-060**): the ten changed signatures resolve and the C1 ones do not, one overload each with no default (a C1-arity call raises 42883), owners, SECURITY modes, `search_path` and ACLs of the five bodies, the five wrappers and the helper, `anon` / `authenticated` refused and `service_role` admitted at the privilege layer, the catalog matrix 4 / 12 / 39, change 7 the first statement of `app.sync_push` whose body equals C1's with only that block removed, `public.sync_push`, both layers of `card_attempt_finish` and `card_attempt_context` (but for its added lines) unchanged since C1, the helper called only by the five bodies (call counts, SA-137) and reading only its explicit binding; C2 re-review fix (SA-139): the textual order of each body's checks against its locks, proof, evidence, writes and envelope returns (each check after a lock wait is also proven at runtime by the runner, C34–C41) |
| claim_identity (CI, 397) | context proof (invalid / revoked / expired / wrong device / kitchen / non-POS denials, no refs returned); claim refusal order and every code; credential-map checks with security events; claim success (frozen shift / drawer / initiator, digests, keys, version); replay / conflict / identity_in_use; cross-tenant; the write-time re-proof of the claim, `adapter_read`, both marks and `free_order` (forged token, another device's PIN, a foreign-organization PIN, revoked membership, expired PIN, revoked session, revoked pairing, suspended employee — each `invalid_session`, nothing written); denial evidence (LIVE audit / TEST private event), the marks' proof-level evidence included (§11 item 13); adapter read revalidation; the §4.55.2 resolution (`manager`+ branch-wide with `conflict`, other roles their own device; §11 item 20); a platform support session denied at the context proof and the claim; C1 (CI-324..CI-359, **D-059** point 5): through the public caller-context entrypoint, an ACTIVE support session — with valid cashier or manager PIN / device inputs, support-only, on another organization, after its platform-admin grant was revoked, or the dual-role owner's own — answers `permission_denied` before any proof, renewal or read; expired, ended, un-exchanged and unconsumed sessions are not active; a grant without a session and the native transport JWT keep the ordinary cashier / manager answers; direct `authenticated` / `service_role` grants refused; a membership revoked between the context proof and the service-only write is refused at write time; the finish after the PIN session expired still records the provider fact; C2 (CI-360..CI-395; CI-022, 023, 325, 335–340, 344, 346 re-pinned for `caller_auth_user_id`, **D-060** points 2 and 4): the context answer carries the binding (refusals carry none); NULL → `invalid_request`, unknown / deleted / banned → `invalid_session`, the binding of an ACTIVE support session (pilot or other organization, revoked grant, dual role) → `permission_denied` on all five operations with valid cashier and manager inputs, each writing nothing (ledger, events, audits, orders, payments, sync rows, device session); the early check's order (after the request shape, before the proof, the key format and any proof-level evidence); expired / ended / pending / unconsumed sessions admitted; a support activation after the context proof refused; a valid binding never rescuing a failed proof; JWT claims and the app-user GUC spoofed either way changing nothing; a binding that is not the PIN employee and an app user without membership admitted; the provider finish recording after a support activation and after PIN expiry, never approving a mismatch and leaving a resolved row final; C2 review fix (CI-396, CI-397): an out-of-contract approved reply (an unreadable tip) after a support activation and after the PIN expired is the out_of_contract anomaly, never approved |
| recording_recovery (RR, 273) | guard refusals on a claimed order (every tender, discount, edit, items-add, void) with no business write; identity-first gate tokens in order, also with the binding retired and with no binding row; recording exactly once; `card_terminal_required` by lifecycle; `card_context_lost`; `shift.close` predicate both ways; recording-result derivation (a resolved attempt answers its envelope with no write; a foreign row parked pending keeps `nonrecoverable_refusal` sticky and resolvable); D-054 Resume (allowlist, active-manager proof, M10, the guard order, stale / limit / history / bounded audit, the stored refusal kept and the freshness rule of §11 item 11, the first and the third Resume's transient failure → `pending_recording`); `resume_authority_required`; protected parse (both paths); single-operation (both paths); transient classes and the `starts_with` prefix allowlist; LIVE release marks per request; `device_session_unavailable` and sticky `device_revoked`; RR-148 is a same-transaction re-entrancy check (the lock-order proof is CC-C21); C1 (RR-227..RR-238): the direct M10 operation-type test of §5; C1 review (RR-239): the real Resume path of RR-101 / RR-102 keeps the attempt's `claim_signal_at`; C2 (RR-240..RR-273, **D-060** point 1): with valid cashier / manager PIN and device inputs an ACTIVE support session is refused 42501 with the pinned message for cash, hand-recorded card, the provider recording leg, a Resume, a mixed batch, a card-sensitive batch, a lone non-money operation, an unknown or NULL PIN, a malformed or oversized batch and both paths (fresh and replayed `revoked_device` pushes), with content digests of every written table unchanged and no stored result disclosed by a replay; the refused leg leaves the attempt approved, unfreed, its Resume budget intact; the native cashier, manager and the dual-role owner then apply the same requests once; ended / expired / pending / unconsumed sessions keep the ordinary checks |
| test_isolation (TI, 140) | TEST start / status / finish without tenant audit; TEST minimisation; pre-ledger refusal (no row, one event, repeat silent, tombstone silent, `permission_denied` shape); revoked-device carve-out; TEST classification; TEST never blocks a shift; `free_order` refused; the marks' proof-level TEST evidence (`test.card_attempt_denied`, never a tenant audit); C1 (TI-133..TI-140): the purge's result shape and the `card_events_test_device` CHECK against a direct insert, the private-event writer and the TEST denial writer, with LIVE and with-device controls |
| lifecycle_retention (LR, 244) | operator revision (append-only, attested approver, executor = `session_user`, M6, window, event, a refused call holds no lock); operator authority before field rules on all five RPCs (§11 item 21); terminal binding (creation / activation / retirement gates, rotation, one enabled per org, one current per device, immutability, C1: an inactive, deleted or management-revoked device refused for `configured` / `enabled` and accepted for `draining` / `retired` under the unchanged gates — **D-059** point 2); capability keys; orphan resolution and `test_closed`; holds; the LIVE `free_order` refusal matrix with its denial evidence; ledger trigger guards (§11 item 25); purge, tombstones and the bounded purge batch (**D-059** point 3); event immutability; C1 (LR-200..LR-244 new; LR-119, 124, 127, 150, 155, 158–162, 190, 193–199 re-pinned): the management-revoked or deleted till drained and retired only when clear (an unresolved sent / unknown / released / anomalous / approved-unrecorded / orphan LIVE attempt, a TEST attempt or a pending / in-flight `payment.create` blocks it), never enabled, re-enabled or rotated, the management revoke resolving nothing and re-pairing never clearing `device_revoked`, the owner / scope gates kept, a replacement enabled only after the lawful retirement; the purge's argument bound, two device scopes with deferred counts and eventual coverage, a held attempt's expired event never starving a bounded batch (LR-226..LR-228), the lock set, a forced failure rolling the whole batch back, the TEST-event device CHECK |
| field_rules (FR, 343) | M1–M5, M7 vectors (the 39-point mask set, the 4 × max bound and its token precedence, the absent test, `provider_return_class`, the `provider_saved_at` grammar, the `card_last4` CHECK); finish transitions, idempotence, late commit, contradiction (none for a `failed` lookup), scope mismatch; LIVE audit rows; owner read allowlist, roles (accountant yes, kitchen no) and TEST filter, and a live platform support session refused (42501) in both modes; C1 (FR-291..FR-343, **D-059** point 4): the generated class tables against the three pinned files, exhaustive raw / canonical vectors per rule, the Hangul fillers and dash-like letters, the 12 digit families and mixed scripts, masked forms with modifier-letter separators, invisible / mark-only reasons, positive Arabic / Hebrew / English reasons, short legitimate numeric values, idempotence, post-normalization length limits, the essential / non-essential provider-field treatment with closed-token events only, and the `free_order`, operator-revision and CHECK boundaries |
| regression (RG, 177) | cash / manual-card / non-provider behaviour unchanged without a mapping; snapshot and capability shapes unchanged without attempts / mappings; Activity-log projections unchanged for non-card actions; refusal-path probe; non-UUID text identities; two-organization anti-oracle; printer-only branch recording; C1 (RG-130..RG-168, **D-059** point 1): the snapshot claim watermark — a claim's start and end re-delivered, a state transition re-delivering once more (the recorded over-inclusion), repeat reads empty, poll counters / lookup stamps / marks / holds / the recording-result mark never advancing it, the recording leg through `pay.updated_at`, an unrelated order unchanged, cross-tenant and sibling-branch rows and TEST attempts never contributing, tied-stamp paging in both directions, no write to `orders`; C1 review (RG-169): the Resume guard's own columns written directly keep the signal and the feed stays empty; C2: RG-104 re-pinned for the context key `caller_auth_user_id`; C2 review fix (RG-170..RG-172): the web-order acceptance under an ACTIVE support session raises the shared 42501 (no order, the request pending), the transport-JWT control accepts, and `app.sync_push` has exactly two callers; re-review fix (RG-173): a support-session replay of a decided request keeps its typed answer; integration W3 (RG-174..RG-177, S7(a), §16.3): the acceptance-ETA entry `public.pos_accept_web_order_with_eta` for a platform and a legacy request — in an ACTIVE support session it raises the same 42501 at the RAISE in `app.sync_push`, on the call path read from the error context (`app.sync_push` ← `app.decide_pos_web_order` [← `app.pos_accept_web_order_legacy_353`] ← `app.pos_accept_web_order` ← `app.pos_accept_web_order_with_eta` ← the public wrapper), and rolls back whole (the request row unchanged and pending; no decision and no use of the decision id; no ETA sidecar, print attempt, lease or sync-ledger row; no new order, item, audit or dispatch row); the transport-JWT controls then accept the same requests with the same decision ids through the same path (captured at the order insert), with exactly one ETA sidecar row bound to the winning decision |
| concurrency runner (CC, 41 scenarios, 1 356 checks in each of the two final C2 runs — CC-C13's count follows each round's race outcome, §14; a manual lane until W3 added its one `db-tests` step — not yet run in CI, §10, §16.3) | claim and push of one identity in both winning orders (C1) and a holder of the identity lock alone (C18) + rollback / retry + `pg_locks`; the terminal lock vs drain / retirement / rotation / LIVE activation in both orders (C4, C15), cash and hand-recorded card pushes vs a retirement (C16), concurrent pilot setters (C17); the purge vs a claim and a push in both orders (C5, C19), vs `card_attempt_finish` (C23) and a forced key collision with a purged identity (C20); concurrent claims (same identity; same order); M9 (C8); concurrent Resumes dispatch once and the freshness race of §11 item 11 (C9, C25); Resume / claim / finish vs close; the claim guard's membership FOR SHARE decision (C24); `app.edit_order` vs a claim and the recording leg (C21); the credential-reference lock (C22); a forced deadlock on the recording leg → `transient_failure`, then one recording on resend; the lock-order stress with a TEST purge and an `order.edit` on an ordinary and a printer-only branch (C13); C1: the inactive-device shutdown — a claim against `revoke_device_management` in both orders, the revoked till's drain / retirement on its terminal lock, retirement only after the operator resolution, a replacement blocked until then (C26) — the bounded purge — a device outside the locked set untouched until the next batch, incident holds set and cleared against a batch, the pre-ledger TEST refusal against a batch, a forced failure rolling the whole batch back, each in both orders (C27–C30) — and the support-authority transitions — a support session activated by another session between two context calls (C31), a membership revoked between the context proof and the service-only write (C32); C1 review: a batch's cut-off fixed before its terminal locks — a TEST attempt and an attempt-less TEST event that expire while the batch waits on a held terminal lock survive that batch and are not reported deferred (C33); C2 (**D-060** points 1–3): the authorization cutoff against a support activation committed by another session, both winner orders — the claim waiting on its terminal lock, on its orders row and as a replay (C34), the release mark on the attempt row (C35), the recording mark on the `sync_operations` and the attempt rows (C36), `free_order` on the orders and the attempt rows (C37), `adapter_read` before / after the call and across its proof's wait (C38), `app.sync_push`'s start-of-request guard (C39), and the check right after the write-time proof of both marks, `free_order` and `adapter_read`, which never lets the resolver's `attempt_not_found` follow a wait (C40); the C2 review fix C41: the claim's check after its identity lock (a replay waiting on that lock) and after its shift / drawer locks, and a support push refused while another session holds the terminal lock (no wait). Run: `node supabase/tests/support/run_bizbot_zcredit_001d_concurrency.mjs --container supabase_db_BIZBOTZCREDIT001D` |

Baseline: the full local suite before the migration (314 files / 9 635 tests; the only failure is the CI-only
`zz_storefront_featured_items_001_concurrency_test.sql`, which refuses any non-CI database by design) is compared
file by file with the run after it (321 files / 11 043 tests at the pre-correction candidate, the seven 001D
files adding 1 408 assertions; after C1 and its review fixes 321 files / 11 249 tests, the seven files adding 1 614 assertions; after
C2 and its review fixes 321 files / 11 344 tests, the seven files adding 1 709 assertions, all passing; every lane file sets `\set VERBOSITY terse`, so a statement error that reaches psql prints no DETAIL row, and no write carrying a generated card-shaped value is wrapped in pgTAP's `lives_ok` (which prints DETAIL itself); in both runs the only failures are that CI-only file — a baseline failure, **NOT VALIDATED** locally, no CI
flag is set to disguise it — and the reserved guard below, an unresolved integration gate, not a waived success). **Reserved baseline guard:** `public_surface_acl_remediation_001_test.sql`
D1 enumerates the public functions `authenticated` cannot execute; the six new service-only wrappers make it
fail. The file is reserved by #366 and #368, so this phase preserves the failure and reports the coordination
requirement: whichever change lands after this one appends to D1's denied list the six catalog renderings — since
C2 (§13.3) `card_attempt_adapter_read(uuid,uuid,text,text,text,jsonb,jsonb,uuid)`,
`card_attempt_claim(uuid,uuid,text,text,text,bigint,text,uuid,integer,text,jsonb,jsonb,text,uuid)`,
`card_attempt_finish(uuid,uuid,uuid,text,text,bigint,text,text,text,jsonb,text)`,
`card_attempt_free_order(uuid,uuid,text,text,text,text,text,uuid)`,
`card_attempt_mark_recording_result(uuid,uuid,text,text,text,uuid)` and
`card_attempt_mark_release_requested(uuid,uuid,text,text,uuid)` ("eleven" → "seventeen"; five of the six C1
renderings changed, `card_attempt_finish` did not). *(Update 2026-10-25, S2 / S5, §15.3: 001D itself appends the
six renderings to test 15 at W3 — after the W2 merge, regeneration, proofs and composed-base rerun, which start
only after BOTH #366 and #368 merge independently and their ownership is released — on the actual composed base, where the expected list is re-derived (the proposal expects 22 there; not a
hardcoded goal); "eleven" → "seventeen" is M2-relative.)* *(Update 2026-10-26, W3, §16.3: done — `7c7207ed`
appends the six renderings to test 15 on the composed base, where the expected set had 16 entries (the four anon-only
`storefront_menu` readers through `storefront_menu_v4(text)` and the twelve service-only web-request / notification
wrappers, `get_web_order_request_status_v2(text,uuid,text)` included); the final set has 22.)* Every other existing file
passes unchanged (the capability and snapshot exact-key tests included, §11 items 3–4). pgTAP proves database state and admission guarantees; it does **not** prove real
provider-request counts (001E's lane). *(2026-10-26: the composed tree's local results are in §16.6.)*

## 8. Local database isolation (no secret values)

A disposable Supabase stack under project id `BIZBOTZCREDIT001D`, created from a copy of the repository
`config.toml` in a scratch harness directory (the repository config is never edited), ports 56420–56429 (DB
56422), excluding studio / storage / realtime / edge-runtime / functions / kong / analytics where the CLI allows.
Every write goes through a guard script that refuses unless: no `SUPABASE_DB_URL` / `DATABASE_URL` /
`SUPABASE_ACCESS_TOKEN` / `SUPABASE_PROJECT_REF` / `PGHOST` is set, the harness `project_id` and port match, the
harness is not linked (`.temp/project-ref` absent), the repository `config.toml` is unchanged, and the container
`supabase_db_BIZBOTZCREDIT001D` publishes port 56422. Commands: `supabase start --workdir <harness>`,
`supabase db reset --local --workdir <harness> --no-seed`, `supabase test db --local --workdir <harness>`;
`--linked`, `--project-ref` and remote URLs are never used. CLI 2.107.0; PostgreSQL 17.6 (Unicode 15.1, ICU 15.1).
No existing database was reset, no unrelated container or worktree was touched.

## 9. Held: Dashboard audit registry and l10n (dependency)

The `card_attempt.*` Dashboard registry entries, `_displayableKeys` labels and ar / he / en titles are
**required** for full 001D completion ([API_CONTRACT](API_CONTRACT.md) §4.33). They are **held** because PR #366
(`BIZBOT-STOREFRONT-ACCEPTANCE-ETA-001`, head `672202ab`) owns the seven l10n files
(`packages/l10n/lib/l10n/app_{ar,en,he}.arb` and `packages/l10n/lib/src/generated/app_localizations{,_ar,_en,_he}.dart`).
**N24:** the audit-only l10n exception is held for the same reason; no generic shared-package permission exists.
Dependency: #366 merged (or released) → a fresh scoped approval for the audit-UI portion on a fresh base. Until then
the database writes the family and the existing generic Activity-log rendering applies.

**Update 2026-10-25 (local integration continuation, §15):** the command room approved the explicit key-level
ownership plan — #366 keeps its six keys, 001D owns its `activityLog*` card keys (71; 73 after the §15.4a review
amendment) at the two named anchors, and the
branch that lands second (001D) merges `main` and regenerates — so the audit UI is implemented now on the integration
branch, without waiting for #366. What remains held is the regeneration on the union of keys at W2 — only after
BOTH #366 and #368 merge independently and their ownership is released (§15.3).

**Update 2026-10-26 (§16.2):** done — after #368 and #366 merged, the local merge `a1b8c1c0` kept #366's six
preparation-duration keys, 001D's 73 `activityLog*` keys and every other key and metadata entry, and the four
generated files were regenerated from that union with the pinned Flutter 3.44.2.

## 10. NOT IMPLEMENTED / NOT TESTED here

- **001E:** the Edge function, provider transport, configuration secret validation, key-format selection from
  `POS_CARD_PROVIDER_CONFIG`, the raw-number amount serializer, the reply parser (field extraction, essential-field
  reading, the approval-type mapping), the poll cap and cadence, provider-request counts, `invalid_request` at the
  boundary, the static service-credential guard; (C1) the same-request binding of the caller proven by
  `card_attempt_context` to every service-only call of that Edge request and the text policy of §4.5 applied with
  the same vectors (**D-059** point 4); (C2, **D-060** point 2) passing, unchanged, the `caller_auth_user_id` of the
  successful context proof of the SAME request as `p_caller_auth_user_id` of every session-proving service-only
  call. **NOT IMPLEMENTED (001E tests):** the binding taken from the same request's proof, never from the request
  body; a forged body binding, a cached proof and another request's binding refused or never used; no
  service-only call after a failed or support-refused proof; the binding's support refusal surfaced unchanged;
  every service-only RPC called as a single PostgREST call at READ COMMITTED, never inside a REPEATABLE READ or
  SERIALIZABLE transaction (the condition of the cutoff, **D-060** point 3).
  **NOT TESTED:** any provider call count — pgTAP proves only call intent (a ledger row or none, `claim_created` /
  `replayed`).
- **001C / 001F:** transport, journal, persist-before-send, the provider-leg sibling record, Resume UI, the hidden
  legacy tender, the typed refusal renderers, the "new identity" option of §4.3 (recorded, not built).
- **001G:** Dashboard verification of the audit UI (implemented locally on the integration branch, §15).
- **001H / physical:** designated device, TEST secret, mapping rows, the operator revision, the QD3 / test-card run,
  M11–M14, N14, N15 (mandatory before 001H or any physical test). **Q-047** and **Q-049** stay OPEN.
- **CI wiring of the CC lane:** the concurrency runner is a manual lane (run command in §7); wiring it into
  `.github/workflows/ci.yml` needs a separately approved change (the file is reserved by #366; approved on 2026-10-25
  as one `db-tests` step, released only after BOTH #366 and #368 merge independently and their ownership is
  released (W3, after the W2 composition), §15.3). Its evidence fields
  `productionContacted:false` / `providerRequests:0` are constants by construction (no HTTP client or provider
  transport exists in the runner), not measurements. *(2026-10-26, W3: the step is added locally by `297d576d`,
  directly after the acceptance-ETA runner; it has not run in CI. The 353 and acceptance-ETA runners, which also
  drive `app.sync_push`, admit only their own local container namespaces or CI and were not run here: **NOT
  VALIDATED** locally until their CI runs on the exact published head, §16.5.)*

## 11. Interpretations for command-room review

1. **Pilot pinning** uses the in-repo Maps Burger scope constants (D-051 point 1 + the `20261017004438` precedent).
2. **Proof helper:** the service-only re-proof replicates the renewal's token proof and lock set without its write.
3. **`card_terminal_*` presence:** emitted only with a non-retired mapping row of the exact device (keeps the
   existing exact-equality capability tests green; absent ⇒ hidden).
4. **`card_attempt_in_progress` presence:** emitted (`true`) only while a claim is active; absent otherwise (keeps
   the existing exact-key snapshot test green; an older server also omits it), plus the stamp widening of §3.2. The
   alternative — always emit, and amend `order_edit_001b_pos_order_snapshots_test.sql` test 05 and the capability
   tests — needs a scope extension to existing test files. **Command-room item:** [DEPLOYMENT](DEPLOYMENT.md) §18.2
   names only the `card_attempt_in_progress` key as this function's documented change, so the `sync_at` widening (the
   ORDER-EDIT-001B stamp precedent: an attempt's change must reach an incremental pull, or another till keeps a stale
   gate) needs either a §18.2 / §4.30c clarification or its removal (001F would then refresh the order explicitly).
   **Resolved by D-059 point 1 (C1):** kept and narrowed to the durable `claim_signal_at` of the order's LIVE
   attempts (same organization, branch and order); named in §4.30c and §18.2 (§12).
5. **Missing / out-of-scope order at `start`** answers `precondition_failed/ineligible_order_state`;
   `payment_in_progress` sits right after the paid-order guard.
6. **Reopen bookkeeping:** a Resume reopen clears the sync row's stored rejection fields (the attempt keeps the
   refusal and appends it to `recording_refusal_history`); the dispatch then follows item 11; a transient failure
   leaves `result` untouched.
7. **Resume guard signature** carries the resent `target_entity`, `target_id`, `client_created_at` and `payload`
   so the guard itself performs the explicit comparison of **D-058** point 11 (M10).
8. **`recording_resume` exponent forms:** the batch arrives as `jsonb`, which normalizes a number such as `1e0`
   to `1` before the parse sees it; such an input is accepted as that integer (a fraction such as `1.0` or `2e-1`
   is refused).
9. **Hosted ACL stamping:** new `public.*` functions are created with explicit revokes for every app role before
   their single grant, so the hosted default ACL (which stamps `authenticated` and `service_role`) cannot widen them.
10. **Pre-ledger TEST refusal event:** both answers of change 6 (`test_attempt_not_recordable`, and `permission_denied`
    for a session `record_payment` is certain to deny) write the attempt's single `test.card_recording_refused`
    (deduplicated per attempt; none for a tombstoned identity).
11. **Resume dispatch path:** an authorized reopen continues through the existing adopt path of the ledger-claim step
    (so `retry_count` is bumped like any adoption). The guard writes only `recording_resume_count`,
    `recording_refusal_history` and `recording_resume_history` on the attempt (§4.55.2) — the attempt's stored
    `refusal_code` / `recording_refused_at` are never cleared — and a later Resume requires the refusal of the
    re-dispatch to be reported first: `refusal_not_recorded` also when `recording_refused_at` predates the sync row's
    latest rejection (`sync_operations.updated_at`) or the last authorized Resume (its `at` in
    `recording_resume_history`, the guard's clock time — the sync row's stamp is the pushing transaction's start, so
    only the clock-time reference is race-free), and the recording-result mark re-stamps a report under the same rule.
    The derive follows the same rule: a stored NON-recoverable token is sticky (an orphan, whose identity row may even
    be a foreign row parked `pending`); a stored recoverable token is the current reason only while it reports the
    leg's latest refusal — the leg terminal again and the report not older than the row's last stamp or the last
    authorized Resume — and otherwise the refusal awaits its report (`pending_recording`, recoverable false), e.g.
    while a reopened leg is in flight, after a transient failure, or after a re-dispatch refusal not yet reported.
    The mark re-stamps a same-token report only for a recoverable token. The guard's order: actor → `operation_mismatch` →
    `resume_limit` (count 3, before any staleness) → `resume_stale` → state / order → `payment_exists` →
    `claim_inactive` → `order_not_chargeable` → `context_lost` (a deleted shift or drawer row included) →
    `amount_mismatch` → `refusal_not_recorded` → the token allowlist.
12. **Operator-only result details** (operator SQL only, never a client code): `binding_exists`,
    `lifecycle_transition`, `payment_create_pending`, `attempt_unresolved`, `admitting_binding_exists`,
    `attempt_not_resolvable`, `attempt_not_test`, `event_not_test`, `event_not_found`; an operator call with a device
    outside the pilot scope or a non-POS device answers `invalid_request`, and (C1, **D-059** point 2) so does a
    `configured` / `enabled` step on an inactive, deleted or management-revoked device.
13. **Evidence at proof level:** a write-time `permission_denied` of `card_attempt_mark_release_requested` or
    `card_attempt_mark_recording_result` whose proof established the scope writes the mode-aware denial evidence of
    the attempt the request names on the originating device (organization, device, attempt id), when it exists;
    an `invalid_session` (no proven scope) or an unknown attempt id writes none. `card_attempt_free_order` keeps the
    §4.55.6 rule (a non-manager is answered before any attempt lookup with no evidence); the claim's proof-level
    `permission_denied` writes evidence in the requested mode.
14. **Resume audit de-duplication:** `card_attempt.recording_resume_requested` rows carry the operation's
    `local_operation_id` in `new_values` (never projected by the Activity log, whose allowlist is §4.7) so the
    once-per-(attempt, Resume count, reason) rule is checkable.
15. **Deadline constant:** `start_deadline_at` = claim time + 120 s; 001E's commit budget must stay below it.
16. **Scoped order lock:** the claim guard resolves and locks the order with the session's organization and branch in
    the locking `SELECT` (a foreign order is never locked; the dispatched RPC's own anti-oracle refusal answers).
17. **`card_terminal_enabled` and the caps:** the key follows the literal §4.30b / §4.55.9 predicate (revision ON
    within its window, exact-device binding `enabled`, same mode); a revision missing the cap its mode requires keeps
    the key `true` while every start answers `card_payments_disabled` — 001F renders that refusal; changing the
    predicate would be a contract change.
18. **Anomaly replies with unreadable input:** an `anomaly` outcome whose essential inputs (or tip) fail their rule
    is recorded with the anomaly code `out_of_contract` (charge may exist) in both sources — never a plain UNKNOWN that
    would drop `charge_may_exist`.
19. **Credential-reference ownership** (a reference never spans modes; a LIVE reference belongs to one organization +
    restaurant) is enforced by the `app.payment_terminals` trigger, whose 23514 propagates from
    `app.set_payment_terminal` as a raise (the contract makes the rule trigger-enforced); the trigger serializes
    inserts per reference (§3.3), so the rule also holds between concurrent operator calls. Likewise two concurrent
    calls enabling different devices are decided by the partial unique constraint (at most one `enabled` /
    `draining` row per organization): the second raises 23505 instead of answering `admitting_binding_exists`.
20. **Attempt resolution** follows §4.55.2 literally: a `manager`+ resolves by (organization, branch, attempt id) —
    `attempt_not_found` on no match, `conflict` on more than one (the id is client-minted, unique only per device);
    every other role acts on its own device only.
21. **Operator authority before field rules (T-023):** each operator RPC answers `permission_denied` (writing
    nothing) for a missing, empty or Space_Separator-only `operator_reference` or a non-attested actor, right after
    its `invalid_request` argument checks; only a present reference failing its field rule is
    `precondition_failed` / `out_of_contract`.
22. **Release mark:** every release request of a `sent` / `unknown` attempt without a `resolution` stamps
    `release_requested_at` and, for LIVE, writes `card_attempt.release_requested` — §4.55.6 marks each release
    through the mark ("audited `card_attempt.release_requested` for LIVE"); any other state answers the envelope with
    no write.
23. **Resolved attempts and a lookup without reply:** a `lookup` finish with `failed` carries no provider fact, so on
    a resolved attempt it writes no `security.card_resolution_contradicted` (every other outcome still does).
24. **A revoked device's binding (command-room item):** `app.set_payment_terminal` follows the literal "validates the
    exact active POS device" for every lifecycle step, so once **D-057** point 7 revokes a dead till its `enabled` /
    `draining` row can no longer be drained or retired, and the one-admitting-row-per-organization constraint then
    blocks enabling a replacement till. Closing it needs a §4.55.10 / §4.55.9 amendment (for example: an inactive
    pilot device accepted for `draining` / `retired` only, with the normal gates); nothing is relaxed here.
    **Resolved by D-059 point 2 (C1):** exactly that — `enabled → draining`, `configured → retired` and
    `draining → retired` for an inactive, deleted or management-revoked pilot POS device under the unchanged gates,
    locks and operator evidence; creation, `configured → enabled`, `draining → enabled` and rotation still need an
    active device (§12).
25. **Ledger trigger guards:** besides the frozen facts, clearing `charge_may_exist` outside an `unknown` /
    `released` → `approved` / `declined` transition and setting or replacing `provider_anomaly_code` on an
    `approved` / `declined` row are silent no-ops (the contract's "only a later exact result clears it"; the code is
    history — clearing a stored code raises 23514 in every state),
    and `order_freed_reason` is immutable with `order_freed_at` (23514; on a resolved row such a change is a no-op,
    like every other non-hold change).
26. **Purge scope (interpretation for command-room review):** the purge deletes only attempts of the devices whose
    terminal lock it took (§4.55.10: it "takes the terminal / device lock of every device whose attempts it
    deletes"), and keeps the events of an attempt that still exists on a device it did not lock; that attempt and its
    events wait for the next run (the events of a purged attempt, of a missing one or of none follow the §8.6
    eligibility unchanged). Without the event bound, a hold cleared between the purge's device scan and its deletes
    would delete an unpurged attempt's single `test.card_recording_refused`, and a later push would write a second
    one against **D-058** point 7; the §4.55.10 purge row's "every `mode='test'` private event …" is read as the
    eligible category, and a wording clarification there would make the bound explicit.
    **Resolved by D-059 point 3 (C1):** one bounded batch over the device set it locks (`p_max_devices`), its cut-off
    fixed first; an event belongs to its attempt's device while that attempt exists, else to its own device (every
    TEST event names one — CHECK), so no TEST event is unlockable and a held attempt's event never re-selects its
    device; the rest is reported as deferred and reached by a later batch (§12).
27. **Text residuals for command-room decision (the contract text is implemented literally; nothing guessed):**
    (a) the digit-run rule counts any `L*` character as a run breaker and the mask rule keeps `L*` characters, so
    the blank Hangul fillers U+115F, U+1160, U+3164, U+FFA0 and visible `Lm` letters such as U+0640 TATWEEL or
    U+30FC let a 16-digit number spaced by U+3164 pass; (b) digit-valued `No` characters (dingbat
    and double-circled digits U+2776–U+2793, U+24F5–U+24FF, Ethiopic U+1369–U+1371) are outside "`Nd`, any
    script"; (c) a reason or note made only of blank-rendering allowlisted characters (U+3164, U+2800, a combining
    mark, U+200C–U+200F, U+FE0F) satisfies "printable, 1–200". Closing them needs an amendment of **D-058** point 10 /
    API §4.55.10 (treat the fillers and `Lm` as separators; extend the digit class to Numeric_Type=Digit; require
    one visible graphic character) or an explicit acceptance as residuals. Related, contract-mandated refusals 001F
    and the runbook must expect: a `YYYY-MM-DD HH:MM` date-time or a phone number has 12 digits (`digit_run`), and
    Emoji 16 code points are unassigned in UCD 15.1 (`charset`).
    **Resolved by D-059 point 4 (C1):** (a)–(c) closed — the fillers and every other Default_Ignorable code point are
    refused (`control_character`), letters no longer reset the whole-field count of 12 digit-like characters,
    `Numeric_Type` Digit joins Decimal and Numeric characters are refused (`charset`), modifier letters are mask
    separators, and a reason or note needs one visible letter or digit (`length`) (§4.5, §12).
28. **Unicode version:** `normalize()` uses the server's tables while the classes are pinned to UCD 15.1. The raw
    allowlist refuses every code point unassigned in 15.1 and Unicode normalization stability fixes the NFKC of
    assigned characters, so a later server version cannot change an accepted value's canonical form; no apply-time
    assertion is added. The local server is PostgreSQL 17.6 / Unicode 15.1 (`config.toml` `major_version = 17`);
    the hosted value is checked by the deployment preflight, not here. C1 pins two more UCD 15.1.0 files
    (`DerivedCoreProperties.txt`, `extracted/DerivedNumericType.txt`; §4.5) under the same reasoning.
29. **Context answer for an unknown attempt id:** `card_attempt_context` answers `{ok:true, attempt:null}` for an id
    that resolves to no attempt (a `start` must accept a not-yet-existing id); the action-level `attempt_not_found` of
    §4.55.2 comes from `card_attempt_adapter_read`, the marks and `free_order`.
30. **Lookup approval inputs:** a lookup `approved` follows §4.55.5 literally — an approved status whose amount and
    currency are exact, with no error flag or phone authorization set to `true`; the commit-reply requirements
    (`error_flag = false`, return code 0, an approval type) are not imported into the lookup path.
31. **Support context (C1, D-059 point 5):** `app.current_support_session()` (status `active`, token consumed, not
    expired, keyed by the verified JWT's app user) is reused unmodified; the check runs in `card_attempt_context` after
    the authenticated-user check and before any argument check, proof, renewal or read. The service-only bodies keep
    their write-time PIN / device / membership re-proof; under `service_role` `auth.uid()` is not the original caller,
    so binding that caller within one Edge request is 001E's handoff, and no signature changed in C1 (C2 then added
    the required caller binding, **D-060** points 2–3, §13.2).
32. **Purge home device (C1 fix 2):** found by the C1 test pass — with the event's own device selected, a held
    attempt's expired event re-selected its device in every batch, so a batch bounded to one device never reached
    the next one (LR-227 fails on the first C1 build). The selection and the delete now use the event's home device
    and select only a deletable event.
33. **Support login through `app.sync_push` (C1 delta review; command-room item).** C1 closes the payment caller
    proof only. The `app.sync_push` recording leg (`payment.create` under a provider identity) and a D-054 Resume are
    authorized by the PIN session and the device alone and read no caller identity, so a JWT with an ACTIVE support
    session that also carries a valid staff PIN session can still push them; the payment and audit rows then name
    only the PIN employee. Reproduced read-only by the review; identical on the pre-correction candidate (not a C1
    regression). A support session itself confers no RLS read of PIN or device sessions, and no production caller
    sets the organization setting those policies key on, so a PIN session id comes only from a PIN login — the
    premise of D-059 point 5; where that setting is set (the local harness), a dual-role owner's own memberships
    make PIN and device sessions readable, so the decision should cover the dual-role owner's support login too. Closing it would be a seventh `app.sync_push` change (refuse a
    provider-identity `payment.create` or a `recording_resume` while `app.current_support_session()` is active) and
    needs its own approval; D-059's consequence text is narrowed to the caller proof.
    **Decided by D-060 point 1 (C2):** the whole request is refused, not only the provider leg or a Resume — change 7
    of §6, before every other check (§13.1, §14).
34. **Commit-order skew (C1 delta review).** `claim_signal_at` is stamped inside the claiming transaction, like every
    other `sync_at` term, so an incremental reader can move its cursor past it before that transaction commits and
    then see `card_attempt_in_progress` only at the claim's next transition or end (before C1 a poll's `updated_at`
    bump re-delivered the order within seconds; C1 removed that churn by decision). The key is a UX gate only: the
    `app.sync_push` guard answers `payment_in_progress` regardless, and a targeted read (`p_order_ids`) shows the key
    at once — 001F's refresh rule on that refusal. Recorded in §4.30c and D-059 point 1; no ledger change.
35. **Residual text vectors (C1 delta review; for 001E and the command room).** By D-059's closed definitions a
    non-modifier letter is never a mask separator and the mask set stays the 39 code points, so a masked form whose
    groups are joined by a dash-like `Lo` letter (U+3161, U+1173) or a sideways-I letter (U+A7F7), or whose mask is a
    non-mask asterisk (U+2733), passes when it holds fewer than 12 digit-like characters; and a reason made only of
    modifier letters (e.g. U+0640 TATWEEL) counts as visible. Widening the separator or mask classes would be a new
    decision; the vectors are recorded for 001E.
36. **Write-time support detection (C1 delta review; for command-room confirmation).** The support check runs only in
    `card_attempt_context`; a support session activated after that proof but before a service-only write of the same
    Edge request is not seen at write time (each service-only body except the session-independent, scope-bound
    `card_attempt_finish` re-proves PIN, device and membership, not the caller's support state, because
    `service_role` carries no caller). D-059 point 5 and item 31 assign the same-request binding to 001E with no
    signature change. If the command room wants write-time support detection, the minimal change is an enumerated
    caller parameter (the proven app user) on the five session-proving service-only functions, plus a decision on
    what binds `card_attempt_finish` — which would also change those D1 renderings of §7.
    **Decided by D-060 points 2–4 (C2):** the required binding names the `auth.users` id (not the app user, which
    the native transport principal lacks); `card_attempt_finish` stays unbound as the provider-fact exception; the
    D1 renderings change for five of the six operations (§13.2, §13.3, §14).

## 12. Correction C1 (**D-059**) — disposition

Command-room decisions of 2026-10-24 ("BOUNDED LOCAL CORRECTION C1") on the 001D local implementation report,
recorded as **D-059** in [DECISIONS](DECISIONS.md) — **approved for this local correction only; not proof of merged
or deployed behaviour**. The pre-correction candidate `2e011ea5` (migration SHA-256 `335e4ea9…`) is preserved with
its tests and evidence outside Git; the migration is corrected in place by new local commits (no historical
migration and no migration history touched) and every lane re-ran from a clean disposable rebuild. Each new or
re-pinned assertion was also run against the saved pre-correction candidate (a clone database in the same
disposable container); the last column names what fails there.

| Item | Decision | Implementation | Proof | On the pre-correction candidate |
|---|---|---|---|---|
| §11 item 4 — snapshot watermark | **D-059** point 1 (approved, narrow) | `claim_signal_at` (insert = `created_at`; advanced only by a change of `state`, `order_freed_at` or `resolution`, so it advances a bounded number of times per attempt and terminates); the snapshot joins `max(claim_signal_at)` of the same organization / branch / order LIVE attempts instead of `max(updated_at)`; no read-time watermark, no write to `orders`, no TEST, cross-tenant or provider-field term, no new key; cursor, tie-break and paging unchanged; an order without a LIVE attempt keeps its stamp | RG-130..RG-169, RR-239, SA-026, SA-110..SA-113, the §4.30c / §4.55.3 / §18.2 text | 25 of the 40 RG assertions: 9 behavioural — RG-134, 135, 136, 138, 142, 150, 163 (a poll counter written directly, RG-162) and 169 (the Resume counter), where polls, lookups, marks, holds and counters churned the feed through `updated_at`, and RG-157 (no branch term) — and 16 because `claim_signal_at` does not exist there; RR-239 fails there on the missing column; SA-026 and SA-110..SA-113; the 15 baseline-behaviour RG assertions pass on both. RR-239 and RG-169 also fail under a mutation that advances the signal on a Resume-counter change (every other assertion passes under it) |
| §11 item 24 — stopping an inactive / revoked till | **D-059** point 2 | `app.set_payment_terminal`: scope and `pos` checks for every call; an inactive, deleted or management-revoked device only for `draining` / `retired` (§4.55.9 amended in the review fix); the retirement gates, the terminal lock, the attested approver, operator reference, reason, executor and private event unchanged; no PIN or device session of the dead till needed; no client-asserted device or scope | LR-158..LR-162, LR-200..LR-224, CC-C26, [STATE_MACHINES](STATE_MACHINES.md) | LR-159–162, 207, 209, 210, 212–224 (evidence variant of the final LR file with the pre-correction purge signature) and CC-C26 |
| §11 item 26 — the TEST purge | **D-059** point 3 | one bounded batch: `p_max_devices` 1..1000 or NULL (else `invalid_request`, first); cut-off fixed before selection; devices in id order, their terminal locks, the exclusive barrier, then deletes re-checked under the row locks; attempts tombstoned atomically; events by their home device (§11 item 32); deferred counts; CHECK `card_events_test_device` (no TEST event without a lockable device; the store held none); no NULL-device or global delete path | LR-119..LR-127, LR-155, LR-190..LR-199, LR-225..LR-244, TI-101, TI-104, TI-133..TI-140, SA-035..SA-037, SA-043..SA-047, SA-053, SA-092, SA-114..SA-118, CC-C27..CC-C30, CC-C33 | the four-argument call does not exist there (the LR file aborts at it; CC-C13, C19, C20 and C23, which call the three-argument form, fail there on the C1 result shape — no deferred or device counts); in the evidence variant LR-119, 124, 127, 155, 190, 194, 198, 225, 234–236, 238, 240–244; TI-101, 104, 133, 135–138, 140; SA-035–037, 043–047, 053, 092, 114–117; CC-C27..C30. LR-227 (starvation) passes there only because that variant cannot bound the batch, and fails on the first C1 build. CC-C33 cannot run there (four-argument call); the pre-correction purge also fixed its cut-off first, and a mutation that re-reads the cut-off after the locks fails CC-C33 (two attempts and one event purged instead of one attempt), as does a mutation of the event delete alone (one event purged) |
| §11 item 27 — text-validation gaps | **D-059** point 4 (required) | §4.5: three pinned UCD 15.1.0 files; Default_Ignorable and Numeric refused raw and canonical; 12 digit-like characters anywhere in the field; modifier letters as mask separators; a visible letter or digit in a human reason; closed tokens only; the 001E validator must use the same vectors (not implemented here) | FR-12, 13, 14, 17, 20 (re-pinned), FR-291..FR-343 (generated synthetic vectors; no card-shaped value printed; the public test-card numbers and issuer-prefixed examples of the earlier vectors are replaced by generated `repeat()` sequences, while obviously synthetic literals stay — ascending or all-zero digit runs, the π-digit UUID identity, masked shapes with a synthetic last four), the per-code-point cross-check of all seven classes (PASS); §11 item 35 | FR-12, 13, 14, 17, 20 and 38 of the 53 new FR assertions; the other 15 (harness, setup, the unchanged other-control refusals, the 11-digit and positive-reason controls, idempotence) pass on both |
| support login + staff tokens | **D-059** point 5 (required) | `card_attempt_context` answers `permission_denied` first for an ACTIVE support session (`app.current_support_session()`, reused unmodified); a grant alone confers nothing — the ordinary proof decides; no JWT-user = PIN-employee equality; dual-role owners keep ordinary use; the service-only bodies keep the write-time re-proof; `card_attempt_finish` stays session-independent; no signature changed | CI-320, CI-324..CI-359, CC-C31, CC-C32; §11 items 33 and 36 for the command room | **Reproduced:** with an ACTIVE support session and a valid cashier or manager PIN / device token the context proof answered `ok` and renewed the device session (CI-327, 328, 332, 333, 334, 345 fail there; CI-320 and CI-329..331 were refused there with the ordinary tokens). The earlier fixture (CI-319..CI-323) HAD an active support session but no valid staff PIN session — its refusals came from the ordinary PIN proof (`invalid_session`), not from support detection. CC-C31 fails there; CC-C32 passes on both (the write-time re-proof already existed). The `app.sync_push` recording leg and a Resume stay reachable under a support JWT with a valid staff PIN session on both builds (§11 item 33) |
| M10 operation type | direct test (required) | none needed: the preamble's type comparison already refuses | RR-227..RR-238 | pass on both builds — the behaviour existed; the test now proves it directly |

**Unresolved gates (not waived):** the reserved guard `public_surface_acl_remediation_001_test.sql` D1 (test 15) needs
the six exact service-only wrapper renderings of §7 appended by whichever change lands later (it is not modified
here; update 2026-10-25: 001D itself appends them at W3, after the W2 composition, §7); the CI-only `zz_storefront_featured_items_001_concurrency_test.sql` is **NOT VALIDATED** locally (it refuses
any non-CI database by design); the concurrency runner is a manual lane (§10); the Dashboard audit registry and l10n
stay held (§9; implemented locally since 2026-10-25, §15); 001E carries the same-request caller binding and the text-policy vectors (§10); the command room
decides §11 items 33 and 36 (support login through `app.sync_push`; write-time support detection) and notes items 34
and 35; the source-matched publication review, the independent review gate and human merge approval remain
required. *(2026-10-26: done locally — the six D1 renderings by `7c7207ed`, the runner's `db-tests` step by
`297d576d` (not yet run in CI), the localization union by `a1b8c1c0`; §16.)*

**Delta review.** A fresh-context, read-only Claude review of `2e011ea5..ca3f9639` (three lenses — decisions and
contract, security / isolation / concurrency, tests and evidence — with independent adversarial verification of six
of its eight MINOR findings; the other two duplicate a confirmed one or carry their own mutation evidence) found no
MAJOR and no code defect. Its MINOR findings were six documentation gaps (§4.55.9 and SECURITY §12 still stating the
pre-C1 rules, the watermark's over-inclusion and branch scope unrecorded, the §4.55.3 snapshot sentence, the D-059
support consequence overstated), one duplicate of them (RG-157 pinning the then-unstated branch narrowing) and one
test gap (no Resume-counter pin); an UNCERTAIN test gap (no cut-off-before-locks pin) and the NOTE findings were
addressed too. The review-fix commits fix them (comment-only migration changes, docs, RR-239, RG-169, CC-C33, terse
error verbosity); the remaining findings are §11 items 33–36. A second fresh-context review of the review-fix
commits (two lenses) found no MAJOR or MINOR; its NOTE findings (wording, the C33 event leg, a migration column
comment) are applied by the final correction commits.

## 13. Correction C2 (**D-060**) — the support boundary: decisions, manifest and test plan (recorded before code)

Authorization: "BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D COMMAND-ROOM AUTHORIZATION — LOCAL SUPPORT-BOUNDARY CORRECTION C2"
(2026-10-25). Base: the C1 head `22db55a2e5df1cb006fb0e37a289483621eb443a` (migration SHA-256 `a8a0f73c…`), on M2
`0caf3f5a`, which is still `origin/main` at the C2 preflight (2026-10-25T00:11Z; #366 `672202ab`, #368 `f016c669`,
#314 `54346b37`, #315 `4e8c81f6`, none touching a 001D path, `app.sync_push`, the support functions or D-060).
Allowed: the same unpublished migration, the seven payment pgTAP lanes, the runner, this packet and the C1 nine-doc
set. Not touched: `app.record_payment`, the shared support-session functions and their migrations, global role
helpers, unrelated RPCs, the Dashboard audit UI, the seven l10n files, the D1 guard and `ci.yml`.

### 13.1 Item 33 — change 7 of `app.sync_push`: the support-context admission guard

- The first statement of the body, before every other check:
  `if app.current_support_session() is not null then raise exception 'sync_push: permission denied (active support session)' using errcode = '42501'; end if;`
- `app.current_support_session()` is the established support predicate of the verified JWT caller (reused
  unmodified): `platform_support_sessions.platform_admin_app_user_id = app.current_app_user_id()`, `status =
  'active'`, `token_consumed_at IS NOT NULL`, `expires_at > now()`. No client flag, Origin, metadata or role is read.
- Wire shape (pinned from the current code): the entrypoint's existing request-level refusal — a raised SQLSTATE
  `42501` with a `sync_push: …` message, as for a missing or invalid PIN session, a missing backing device session or
  a device mismatch; PostgREST returns `{code: '42501', message: 'sync_push: permission denied (active support
  session)'}`. No JSON result, no per-operation results, no partial batch.
- Placement: before the batch-shape check, the PIN / device proof, the terminal admission lock, the
  single-operation check, the revoked-device path and the valid path — so before any ledger claim or finalization,
  replay, Resume counter / history write and dispatch (`app.sync_push` renews no device session). A refused request
  writes nothing (no payment, receipt, order, shift, drawer, sync or tenant-audit row) and discloses no attempt or
  order fact. The refusal is identical whatever the request carries (valid cashier / manager PIN and device token,
  no PIN, a replay, a mixed batch).
- Reach (C2 review): `app.sync_push`'s only other caller is the web-order acceptance `app.decide_pos_web_order`
  (`public.pos_accept_web_order`), which re-raises the refusal — a fresh acceptance that reaches `app.sync_push` in an
  ACTIVE support session raises the same 42501, creates no order and leaves the request pending (RG-170..RG-172); its
  earlier refusals and a same-action replay of a decided request keep their typed answers (RG-173); the rejection
  is unchanged.
- Ordinary requests are unchanged: the native transport principal (no app user), a dual-role owner outside an active
  support session and ended / expired / un-exchanged sessions resolve no active session, and the normal PIN / device /
  membership checks, device revocation, TEST isolation, idempotency and transient handling apply as before.
- `public.sync_push` keeps its signature and ACL; `app.sync_push` is re-created once, with seven documented changes.

### 13.2 Item 36 — the required original-caller binding

- **Namespace: `auth.users.id`** — the verified JWT subject (`auth.uid()`). Chosen because the native POS transport
  principal is an authenticated auth user with no `app_users` row, so `app_users.id` would be NULL for every native
  POS request. The conversion to `app_users.id` for the support check uses the trusted existing mapping
  `app_users.auth_user_id` (unique), exactly as `app.current_app_user_id()` does.
- `app.card_attempt_context` (caller-scoped) adds `caller_auth_user_id` = `auth.uid()` to its `ok` answer — the
  minimum binding the adapter needs; its refusals carry none.
- The five session-proving service-only bodies and their public wrappers gain a final, required parameter
  `p_caller_auth_user_id uuid` (no default, no overload, no fallback). `card_attempt_finish` is unchanged (§13.4).
- New internal helper `app.card_caller_binding_denial(p_caller_auth_user_id uuid) returns text` — STABLE, SECURITY
  DEFINER, `search_path = ''`, owner `postgres`, no app-role grant, no wrapper. NULL = the binding names a valid
  caller outside an active support session; `invalid_request` = NULL binding; `invalid_session` = no `auth.users`
  row, or one that is deleted or currently banned; `permission_denied` = the mapped app user holds an ACTIVE support
  session (the canonical predicate above, applied to the explicit identity). It never reads `auth.uid()`,
  `session_user`, `request.jwt.claims` or a GUC, and it sets no GUC.
- Checks in each of the five bodies, answering `{ok:false, error:<token>, server_ts}` and writing nothing:
  - **early** — with the request-shape checks, before the proof, any lock, any evidence write or renewal;
  - **after the proof** (added by the C2 self-review of the first C2 build) — in `card_attempt_adapter_read`,
    `card_attempt_mark_release_requested`, `card_attempt_mark_recording_result` and `card_attempt_free_order`,
    immediately after the proof, whose identity-row locks may wait, and before the role check and the attempt
    lookup, so no answer that follows a lock wait — the resolver's `attempt_not_found` / `conflict` included — is
    returned without a support check (`card_attempt_claim`'s check after its full-identity lock already follows its
    proof); the first C2 build's checks after `card_attempt_adapter_read`'s attempt read and before
    `card_attempt_mark_recording_result`'s first envelope answer followed no lock wait and were removed;
  - **final** — after the body's last lock wait, immediately before its first action-specific write or
    attempt-data return: `card_attempt_claim` after the full-identity lock (before the configuration checks, their
    events and the replay) and again after the `orders` / `shifts` / `cash_drawer_sessions` locks, immediately
    before the refusal evidence or the insert; `card_attempt_adapter_read` the check after the proof (the attempt
    read takes no lock), before the attempt lookup, the credential check, its event and the answer;
    `card_attempt_mark_release_requested` after the attempt row lock, before the stamp, audit and envelope;
    `card_attempt_mark_recording_result` after the `sync_operations` → attempt row locks, before the evidence, the
    refusal write and the envelope (its first envelope answer follows the check after the proof);
    `card_attempt_free_order` after the `orders` → attempt row locks, before the envelope, the evidence and the
    free.
- The existing PIN / device / membership / scope proof (non-renewing, its identity-row locks held to commit) still
  decides staff authority; the binding confers no membership, and the caller need not be the PIN employee. The
  existing proof-level `permission_denied` evidence (a record of the refusal, not an action effect) is unchanged.
- The binding is an assertion of the trusted adapter (service_role), not an end-user authentication inside the
  service request. 001E must pass, unchanged, the binding returned by the successful context proof of the SAME HTTP
  request, checked against its verified caller; no cached proof, body-supplied caller or caller-supplied refusal
  bypass — NOT IMPLEMENTED here (§10).
- (C2 review) A proof that itself refuses keeps its unchanged answer and evidence before the check that follows the
  proof: a `permission_denied` with a proven scope from the claim or a mark is audited (LIVE) or written as
  `test.card_attempt_denied` (TEST); an `invalid_session`, and a proof refusal of `card_attempt_adapter_read` or
  `card_attempt_free_order`, write nothing; a binding refusal writes nothing.
- **Authorization cutoff:** the final check (C2 review: under READ COMMITTED — each check a new statement with a
  fresh snapshot; 001E must call these RPCs as single PostgREST calls, never in a REPEATABLE READ or SERIALIZABLE
  transaction — NOT IMPLEMENTED, §10). An operation admitted before a later support activation may complete;
  the next operation is refused. No advisory lock is added and the shared support writers are not changed, so no
  stronger serialization is claimed.

### 13.3 Exact manifest after C2

- Changed signatures (owner `postgres`, `search_path = ''`; app bodies SECURITY DEFINER, public wrappers `LANGUAGE sql`
  SECURITY INVOKER; EXECUTE for `service_role` only on both layers; PUBLIC, anon and authenticated revoked):
  - `app.card_attempt_claim(uuid, uuid, text, text, text, bigint, text, uuid, integer, text, jsonb, jsonb, text, uuid)` and `public.card_attempt_claim(…same…)`
  - `app.card_attempt_adapter_read(uuid, uuid, text, text, text, jsonb, jsonb, uuid)` and `public.…`
  - `app.card_attempt_mark_release_requested(uuid, uuid, text, text, uuid)` and `public.…`
  - `app.card_attempt_mark_recording_result(uuid, uuid, text, text, text, uuid)` and `public.…`
  - `app.card_attempt_free_order(uuid, uuid, text, text, text, text, text, uuid)` and `public.…`
- Added: `app.card_caller_binding_denial(uuid)` (internal, no grant). Re-created: `app.card_attempt_context(…)`
  (unchanged signature and ACL; the added answer key) and `app.sync_push(uuid, uuid, jsonb)` (seven changes).
- The family becomes **55** functions (54 + the helper): EXECUTE for authenticated on 4 (both layers of
  `card_attempt_context` and `owner_card_attempts`), for service_role on 12 (both layers of the five changed
  operations and of `card_attempt_finish`), for no app role on 39. No function has an old signature or a defaulted
  overload left.
- D1 (held, not edited): its exact expected service-only renderings after C2 would be
  `card_attempt_adapter_read(uuid,uuid,text,text,text,jsonb,jsonb,uuid)`,
  `card_attempt_claim(uuid,uuid,text,text,text,bigint,text,uuid,integer,text,jsonb,jsonb,text,uuid)`,
  `card_attempt_finish(uuid,uuid,uuid,text,text,bigint,text,text,text,jsonb,text)`,
  `card_attempt_free_order(uuid,uuid,text,text,text,text,text,uuid)`,
  `card_attempt_mark_recording_result(uuid,uuid,text,text,text,uuid)` and
  `card_attempt_mark_release_requested(uuid,uuid,text,text,uuid)`; five of the six C1 renderings change.

### 13.4 The provider-fact exception

`card_attempt_finish` keeps its signature, ACL and body: service-only, addressed by the server row id, bound to
organization, device, identity, mode, amount and currency, with the closed transitions and resolution rules; it gains
no binding and no support check, starts no provider request, calls no `record_payment` and frees no order. A support
refusal of a recording leg leaves an approved attempt approved and unfreed, consumes no Resume budget and creates no
charge; a later legitimate non-support push records it under the existing identity and D-054 rules.

### 13.5 Test plan

- **RR (sync admission, both paths):** ACTIVE support + valid cashier inputs — cash, hand-recorded card and the
  provider recording leg refused (42501, the pinned message) with no business / sync / tenant-audit write; ACTIVE
  support + valid manager inputs — the Resume refused, its budget and history unchanged; a replay of an applied
  operation discloses nothing; a mixed batch executes nothing; ACTIVE support without a PIN session — the same
  refusal; the revoked-device path — the same refusal under support, its baseline unchanged without; a dual-role
  owner outside support, the native cashier and the manager — existing behaviour; ended / expired / un-exchanged
  sessions — the normal checks; the support-refused recording leg leaves the attempt approved, unfreed, its Resume
  budget intact, and a later non-support push records it.
- **CI (the binding):** NULL → `invalid_request`, unknown / deleted / banned → `invalid_session`, ACTIVE support of
  the binding's caller → `permission_denied`, each with no write, no renewal and no attempt fact, on all five
  operations; support activated after the proof and before the final check (same transaction) → refused; ordinary
  callers allowed; wrong tenant / device / PIN / membership still refused; a binding that differs from the PIN
  employee allowed; `request.jwt.claims` set to another identity changes nothing (the explicit binding decides);
  the context answer carries `caller_auth_user_id`.
- **SA:** the exact signatures, owners, SECURITY modes, `search_path` and effective ACLs of the 10 changed functions
  and the helper; no old signature or overload; authenticated and anon EXECUTE refused on every changed signature;
  the family count 55; `app.sync_push` against PRE = the six changes plus exactly change 7.
- **FR / CI (the finish exception):** finish after support activation and after the PIN session expired records the
  provider fact with its scope / amount / state protections; a mismatched or out-of-contract result never approves;
  a resolved row stays final.
- **CC (two real connections):** the proof succeeds, support activation commits before the final check while the
  operation waits on a lock, the operation is refused with no effect — both winner orders, for the claim, the marks,
  `free_order` and `adapter_read`; `app.sync_push` against a support activation in both orders.
- **Regression:** all seven lanes from a clean replay, the full suite (D1 still failing until coordinated, the
  CI-only file NOT VALIDATED), the 33 existing scenarios, `record_payment` unchanged, PRE / POST, secrets / float
  guards, a fresh-context delta review of C2 only; pre-C2 counterexamples from a clone holding the C1 migration.

## 14. Correction C2 (**D-060**) — disposition

Command-room authorization of 2026-10-25 ("LOCAL SUPPORT-BOUNDARY CORRECTION C2"), recorded as **D-060** in
[DECISIONS](DECISIONS.md) — **approved for local C2 only; not acceptance of the implementation, not permission to
publish it, not proof of merged or deployed behaviour**. §13 was committed before any code (`befb9e4e`); the migration
is corrected in place by new local commits on the C1 head `22db55a2` (its 16 commits kept; no amend, reset, rebase,
old migration or migration-history change), every lane re-ran on the final migration after a clean disposable reset,
and each new or re-pinned assertion was also run against the C1 migration in a clone database of the same disposable
container (a variant of each lane that drops the binding argument). Local test results are implementer evidence, not
an external sign-off.

| Item | Decision | Implementation | Proof | On the C1 build (pre-C2) |
|---|---|---|---|---|
| §11 item 33 — support login through `app.sync_push` | **D-060** point 1 | change 7 (§6, §13.1): the first statement raises the request-level `42501` `sync_push: permission denied (active support session)` when `app.current_support_session()` (unmodified) is not NULL; nothing else in the body changes (C1 → C2 definition diff: exactly that 10-line block) | RR-240..RR-273, SA-131..SA-134, CC-C39, CC-C41 (p), RG-170..RG-173 (the web-order acceptance, the only other caller) | RR: 24 of the 34 new assertions fail there — the support pushes are executed (cash, card, the recording leg, a Resume, mixed / card-sensitive / lone batches, revoked-path pushes), unknown / NULL PIN and malformed requests get the ordinary errors, replays return the stored result; the other ten — RR-240, a set-up check no mutation fails, and nine set-up and control checks — are covered by ten mutations of the guard (any admin, any session status, after the PIN check, revoked path exempt, payment-only, after the batch checks, Resume exempt, provider leg exempt, every revoked push refused, an ACTIVE session of anyone), each failing a named subset. SA-131..SA-133 fail there; SA-134 passes by design (`public.sync_push` unchanged) and fails under its mutation. CC-C39 fails both legs there; RG-170 fails there (the C1 build accepts and creates the order; RG-171 and RG-173 then fail as knock-ons, RG-172 passes on both); on the final build, moving change 7 after the terminal lock fails CC-C39 (ii) and CC-C41 (p) |
| §11 item 36 — write-time support detection | **D-060** points 2–3 | the binding `p_caller_auth_user_id uuid` (the `auth.users.id` that the context proof returns as `caller_auth_user_id`) as the final, non-defaulted parameter of the five session-proving pairs (no old signature, no overload); `app.card_caller_binding_denial` checked early, right after the proof where an attempt lookup follows, and after every later lock wait (§13.2); 55 functions, EXECUTE 4 / 12 / 39 | CI-360..CI-395, SA-121..SA-130, SA-136..SA-139, CC-C34..CC-C38, CC-C40, CC-C41 | CI: 26 fail there (the 11 re-pinned context assertions, CI-187's parameter names, and the binding refusals, their no-write checks, the check order, the evidence-free refusal and the activation after the proof — the C1 operations act and write); the passing CI assertions — the set-up checks CI-360, CI-361 and CI-390 excepted — are covered by ten mutations of the helper and the bodies (support terms dropped, a grant counted as support, a membership required, any ban refusing, the JWT caller consulted, an app user required, refusal evidence written, a binding rescuing a failed proof, the finish re-checking the caller, the context refusal carrying the binding). SA: 32 fail there (SA-139 included). CC-C34..CC-C38: all 17 legs fail there at their key check (an evidence copy reading the C1 clone with a stand-in helper). On the final build a mutation removing any one binding check that follows a lock wait fails exactly the legs that test it — the claim's check after its identity lock (C34 a3, C41 a1) and after its order / shift / drawer locks (C34 a2, C41 s, d), `adapter_read`'s check after its proof (C38 c, C40 read-a), the release mark's (C40 release-a; C35 a), the recording mark's (C40 recording-a; C36 a1, a2) and `free_order`'s (C40 free-a; C37 a1, a2) — while every (b) leg passes; moving the claim's check after the identity lock before the purge barrier fails exactly CC-C41 (a1), and moving its last check to right after the orders lock fails exactly CC-C41 (s) and (d). moving any check below an evidence write or an attempt-data return fails SA-139. CI-378..CI-380 exercise the early check only; the checks after lock waits are proven by the runner (C34–C41) |
| self-review of the first C2 build | the cutoff of **D-060** points 2–3 | a check right after the proof in `adapter_read`, both marks and `free_order`; the first build's lock-free checks after `adapter_read`'s attempt read and before `mark_recording_result`'s first envelope removed (§13.2) | CC-C40, SA-137 (re-pinned: 3 / 2 / 3 / 3 / 3 calls) | on the first C2 build (migration `e73c4397…`, in a clone) every CC-C40 (a) leg fails: a support activation committed while the proof waited still let the resolver answer `attempt_not_found` — an attempt fact after the cutoff |
| provider-fact exception | **D-060** point 4 | `card_attempt_finish` unchanged on both layers (no binding, no support check; SA-135 md5 equal to C1) | CI-390..CI-397, SA-135, the CC-C34 clean-up (finishes while the support session is ACTIVE) | pass there by design (the behaviour existed); the mutation that makes the finish re-check the caller fails CI-391..CI-395 (the lane agent's run on the 395-assertion lane) and, applied after CI-395 on the final lane, exactly CI-396 and CI-397, and SA-135 fails under a body change or a helper call |
| migration header (SA lane note) | — | comments outside every function body: the header names D-059 / D-060, the helper and "exactly seven changes"; the 9.1 re-emit header says change 6 is marked `Change 6 (D-058 point 7)` inside the change-5 block (the literal "change 6" marker never existed; no body byte changed — SA-132 / SA-133) | SA-132, SA-133 | — |

**Evidence.** All seven lanes on the final migration (its SHA-256 is in the C2 package's identities): SA 139,
CI 397, RR 273, TI 140, LR 244, FR 343, RG 173 — 1 709 assertions, all passing. The runner passes 41 / 41 scenarios
twice (1 356 checks each; the 33 earlier scenarios pass with their earlier counts — CC-C13's varies by design,
below — and C34–C41 add 398). The full local suite: 321 files /
11 344 tests, failing only the reserved D1 guard (test 15, now naming the six C2 renderings of §7) and the CI-only
`zz_storefront_featured_items_001_concurrency_test.sql` (**NOT VALIDATED**; no CI flag set) — on a fresh reset; a
second full-suite run on the same database also fails the unrelated `zz_storefront_home_content_001_concurrency_test.sql`
test 17, which commits append-only audit rows through dblink under a fixed organization id and so passes once per
reset (observed once during C2; not a C2 change). PRE / POST: `app.sync_push`
against the PRE text = the seven changes, against C1 = exactly change 7; `app.record_payment` md5 `aa5d8e02311d…`
unchanged (PRE = C1 = C2); every re-created function's ACL, SECURITY mode, volatility, configuration and owner
unchanged; no other re-created function changed since C1. The secret and float-money guards pass.

**Check counts.** CC-C13 (the lock-order stress) counts, per round, 9 unconditional checks and up to three conditional
ones — `if (p.leg)` (P's claim was created and its recording leg pushed), the mode-specific order-status check when
the round's order was not voided, and `if (edited)` (E's `order.edit` was applied) — so its total follows which session
won each round: 235 fixed checks plus legs, non-voided rounds and applied edits. The two final C1 runs recorded 958 and
959 because their printer-only rounds applied one and two edits; from the outcome tallies the runs print, the formula
reproduces the recorded C13 count of every run output that carries the tally (every C1 and C2 run output listed in the
package, the two final C1 runs included). No other scenario's count varied between the final runs.

**History hygiene.** No card-shaped literal was added by C2. In the reachable local history (`0caf3f5a..HEAD`) the
literals C1 removed (added in `1537cbfe` / `c034705b`, removed in `f58b9926`) are: four publicly documented processor
test numbers (the generic Visa, Mastercard and American Express test numbers and a Visa debit test number, listed in
public sandbox test-card tables), an 11-digit prefix fragment of one of them (below the 12-digit threshold), a
synthetic issuer-prefixed ascending sequence that fails the Luhn check (so it is no valid card number) with its masked
form, and one occurrence of a synthetic 12-digit ascending sequence; none is classified unknown or vendor-derived, so
there is no publication hold from their provenance. The C2 package records the classification (no value printed) and
the optional owner-approved clean-history remediation; nothing was rewritten.

**Delta review.** A fresh-context, read-only Claude review of `22db55a2..2fd75bb1` (three lenses — contract,
security / concurrency, tests — each MAJOR / MINOR finding given to an adversarial verifier) found no MAJOR. Four
MINOR findings were confirmed and fixed by the review-fix commits: the claim's later check positions were not pinned
by any test (CC-C41), the out-of-contract finish case had no assertion (CI-396 / CI-397), the web-order acceptance —
`app.sync_push`'s only other caller — inherits change 7 as a raised 42501 undocumented (D-060, API §4.14 / §4.49,
RG-170..RG-172), and the denial-audit rules lacked the binding-refusal exception (API §4.33 / §4.55.2 / §4.55.7 /
§4.55.8, TESTING_STRATEGY). Two further MINOR findings were refuted by their verifiers and are recorded in the docs:
the proof's own refusal keeps its proof-level evidence before the check after the proof, and the context residual
below. The NOTE findings are applied (the READ COMMITTED condition of the cutoff, the stale §0 / §1 / §3.2 / §7
statements, the scope of "support mode is read-only", wording) or recorded. No code changed: the migration is the
reviewed one. A second fresh-context review of the review-fix commits (two lenses, adversarial verification) found
no MAJOR; its MINOR findings — the web-order wording overclaimed (only a fresh acceptance that reaches
`app.sync_push` raises; RG-173) and nothing pinned the order of the checks against evidence writes and envelope
returns (SA-139) — and its NOTE findings (mutation attributions, the proof-evidence and READ COMMITTED wording, the
001E obligation, the CI-396 comment, packet wording) are applied by the final commits. The C2 package's
DELTA_REVIEW.md lists every finding of both reviews with its disposition.

**Unresolved gates (not waived):** the reserved D1 guard (the six C2 renderings of §7, appended by whichever change
lands later; not modified here); the CI-only file **NOT VALIDATED** locally; the concurrency runner a manual lane (§10);
the Dashboard audit registry and l10n held (§9); 001E's same-request binding, its single-call READ COMMITTED
obligation and their tests **NOT IMPLEMENTED** (§10);
the read-only context proof keeps its single support check before its proof (**D-059** point 5 — a support activation
committed while the context proof waits on its locks is not re-checked by that read, which then still renews the
device session and answers its order and attempt facts and the binding; the next service-only call is refused at its
binding checks); a fresh web-order acceptance in an ACTIVE support session answers the raised 42501 rather than a
typed web-order answer, and the
other PIN-path entry points outside `app.sync_push` and the card path have no support check (pre-existing; each would
need its own Work ID); POS_ONLINE_INBOX_001 and MONEY_AND_TAX_SPEC, outside the C2 doc set, still state the earlier
failure-code list and denial-audit sentence; the source-matched publication review, the independent review gate and human merge
approval remain required. *(Update 2026-10-25: the Dashboard audit registry and l10n are implemented locally on the
integration branch, MONEY_AND_TAX_SPEC's denial-audit sentence is corrected there, POS_ONLINE_INBOX_001 stays with
the web-order owner, and the six D1 renderings are appended by 001D itself at W3, after the W2 composition (§7) —
§15.)* *(2026-10-26: done locally — the six D1 renderings by `7c7207ed`, the runner's `db-tests` step by
`297d576d` (not yet run in CI), the localization union by `a1b8c1c0`; §16.)*

## 15. Local integration continuation — clean history and audit UI (2026-10-25)

Command-room decision "LOCAL INTEGRATION CONTINUATION" of 2026-10-25 (status
`APPROVED_LOCAL_INTEGRATION_WITH_STAGED_DEPENDENCY_GATES`) and the owner's authorization of the same date, which
approved the exact local implementation scope recorded there. Reviewed input: proposal revision 3 (archive SHA-256
`6acb167f8cda52f05ce41dd787db5105bc73bf47dab95601cca12541262643c1`). Technical source anchor: the C2 snapshot
`75ef9d7455e97fa69a6770a363c61364834e4e97`; clean-history anchor: M2 `0caf3f5a04a23805ff4f2bda01e5e0ef3933c012`;
frozen migration SHA-256 `468768f89029a0fb131869f754d5374127930b8bf05b48cd8de19d645546352e`. This section is written
before any audit-UI edit; §15.9 records the disposition afterwards. It authorizes **no** push, PR, merge, hosted
migration, deployment, secret change, provider call, terminal operation, test-card use, printer action or APK operation,
and no new implementation ticket; the S12 companion Work ID is approved but is prepared only after the composed head
is frozen (§15.8).

Work steps (proposal revision 3 §4.1): **W0** read-only re-verification before any edit and before every merge from
`main`; **W1** the clean-history base and the audit UI (this checkpoint); **W2** — only after BOTH #366 and #368 merge
independently and their ownership is released — the merge of `origin/main`, the regeneration from the union of ARB
keys and the preservation proofs; **W3** D1, the acceptance-ETA regression pair and the CI step; **W4** the
documentation refresh and contradiction sweep; **W5** local verification on the integrated head; **W6** the review
material; **W7** push and draft PR and **W8** merge — neither authorized.

### 15.1 Decision sheet as selected

| Item | Selection |
|---|---|
| S1 | Existing Work ID; a NEW clean-history local branch (§15.2). |
| S2 | Intended order #366 → #368 → 001D last; no authority over #366 / #368. |
| S3 | One complete 001D delivery; no database-only merge. |
| S4 | Full audit presentation and key-level ownership now, including the 11th snapshot-test file (§15.4–§15.6). |
| S5 | The exact D1 test-15 change — only after BOTH dependency PRs merge independently and their ownership is released (W3, after the W2 composition). |
| S6 | One `db-tests` runner step — only after BOTH dependency PRs merge independently and their ownership is released (W3, after the W2 composition). |
| S7(a) | The acceptance-ETA support-admission regression pair and the acceptance-ETA (`with_eta`) reach text of API §4.14 / §4.49 — only after BOTH dependency PRs merge independently and their ownership is released (W3, after the W2 composition); the D-060 ratification notes of §4.14 / §4.49 are recorded now (§15.3 item 2). |
| S7(b) | (ii): `docs/POS_ONLINE_INBOX_001.md` is NOT edited; its stale failure-code sentence (lines 56-60) is recorded for the web-order owner's later ticket; API §4.49 carries the reach statement. |
| S8 | Bounded dated integration notes; the Appendix A dispositions of §15.7. |
| S9 | Migration bytes frozen; no optional comment / `lock_timeout` / body change; the drift exceptions and stop conditions recorded in §15.8 apply. Known and frozen, not corrected here: the catalog comment on `app.card_safe_text_ok` (migration about line 6125) still says "12+ Nd digit runs", superseded by **D-059** point 4 (12 or more characters of `Numeric_Type` Decimal or Digit); the migration sets no `lock_timeout` (DEPLOYMENT §18.2a). |
| S10 | A local fresh disposable replay of the integrated (composed) tree at W5; before the composition the C2 database evidence carries over by tree equality at `07ce4794` (no database replay was run at this checkpoint); eventually exact-head `validate` AND `db-tests` success in actual CI. |
| S11 | Clean history; the original 25-commit branch is not published. |
| S12 | (ii): the narrowly scoped owner-directed review exception, recorded under its own docs-only Work ID `BIZBOT-PAYMENTS-ZCREDIT-001D-REVIEW-EXCEPTION-001` on a branch stacked on the frozen final composed head (§15.8). |
| S13 | (a) NO — the C2 review was technical acceptance for local continuation, not publication approval; its source evidence is reusable. (b) REQUIRED at W6. No push or PR now. |
| S14 | C: 001D stays unmerged while later separately authorized pilot work is prepared; no hosted freeze, no early dark cutover; the merged rollout order stands. |
| S15 | Deployment / publication risk accepted as future gates (exact-head fan-out review before any push); no Preview or Production deployment now. |

### 15.2 Clean-history vehicle (S1 / S11)

- New local branch `feat/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-ledger-integration` in its own worktree
  (`worktrees/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-ledger-integration`, a sibling of the main checkout), created from M2.
  It reproduces only the reviewed FINAL 18-file C2 state in three additive commits, documents first:
  `dde0857a` (the nine decision / contract / packet documents), `32d3384d` (the migration), `07ce4794` (the seven
  lanes and the runner). This is a new publication candidate, not a claim that the original local chronology was
  different.
- Proof (recorded outside the preserved C2 artifacts, in
  `evidence/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-INTEGRATION-20261025/`): the import head `07ce4794`'s tree equals the C2
  snapshot tree (`b71237c8b253afbc1250aca2393ba41fee3fbbff`, empty diff); the migration SHA-256 is the frozen value;
  none of the 25 original 001D-only commits — including the two historical test-vector commits — is an ancestor of the
  new branch; no vendor-private or credential-like path is tracked; none of the test-card literals C1 removed recurs.
  The import-head scan covered the three import commits; the broadened final-head scan covers every publishable commit
  above M2 (message and every added line, raw and with the SQL escape / `repeat()` / concatenation constructions
  decoded) must find no publicly documented processor test number, no Luhn-valid 13–19 digit run in a card-network
  range, no credential and no personal e-mail address; its results are recorded in §15.9 and the checkpoint package.
- **Correction (2026-10-25, delta review):** this bullet first said that every publishable commit also scans clean for
  masked card shapes. That was wrong — the import scan's detector matched only a four-digit prefix with a four-digit
  tail. `07ce4794` carries the deliberate synthetic `masked_pattern` refusal vectors of the C2 lanes: rows 549–563, 566
  and 1317 of `bizbot_zcredit_001d_field_rules_test.sql` (plain text or built from U& escapes and `repeat()`; 1317 is
  the `pan_entry_mode` fixture), the
  `payment_method_code` fixture at line 294 of `bizbot_zcredit_001d_test_isolation_test.sql` and the masked reference
  built at line 576 of `bizbot_zcredit_001d_lifecycle_retention_test.sql` — all synthetic, no visible digit group longer
  than four, disclosed in C1 ("masked shapes with a synthetic last four", §12) and frozen with the reviewed lanes. The
  `repeat()`-built Luhn-valid synthetic outside every card-network range (first digit 7) recurs at 22 lane sites. The
  final-head scan inventories both by file and line (length tokens only; after the fix re-review its detector also
  covers single-character, combining-mark-separated and slash-separated masks and lists every row above); the W6
  publication review accepts or rejects them explicitly.
- **Disclosure:** `dde0857a` re-imports the C2 §0 Worktree row with its original absolute local worktree path (a
  Windows user folder; no credential); `d0370204` replaces it with a relative path, so it remains only in commits
  `dde0857a` through `50f052e9` (`dde0857a^..50f052e9`), the same class as the existing occurrences in M2's tree.
  Removing it would break the S1 byte-identity proof.
- The original branch `feat/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-server-ledger` stays at `75ef9d74`, unchanged, with every
  earlier archive, patch and checksum. It is never merged into the clean branch. Existing shared M2 history is not
  rewritten or certified as sanitized.

### 15.3 Exact integration manifest

**Authorized now (this checkpoint):**

1. The eleven audit-UI / l10n files of S4 (exactly): `apps/dashboard/lib/src/data/audit_action_registry.dart`,
   `apps/dashboard/lib/src/data/audit_log_presentation.dart`, `packages/l10n/lib/l10n/app_en.arb`, `app_ar.arb`,
   `app_he.arb`, `packages/l10n/lib/src/generated/app_localizations.dart`, `app_localizations_ar.dart`,
   `app_localizations_en.dart`, `app_localizations_he.dart`, the new `apps/dashboard/test/card_attempt_activity_log_test.dart`
   and `packages/l10n/test/order_edit_labels_test.dart` (only `_activityLogKeyCountSnapshot` and its comment).
2. The narrow documentation refresh of the decision (§5): `docs/DECISIONS.md`, `docs/API_CONTRACT.md`,
   `docs/DOMAIN_MODEL.md`, `docs/STATE_MACHINES.md`, `docs/SECURITY_AND_THREAT_MODEL.md`, `docs/TESTING_STRATEGY.md`,
   `docs/DEPLOYMENT.md`, `docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001.md`, this packet, `docs/IMPLEMENTATION_CHECKLIST.md`
   (umbrella and 001D rows only), `docs/MONEY_AND_TAX_SPEC.md` (the denial-audit exception only) and `docs/RUNBOOKS.md`
   (bounded locked-device purge batches only).

**Released only after BOTH #366 and #368 merge independently and their ownership is released (W2–W6; not yet):** *(Released on 2026-10-26 and done locally, §16.)* a normal merge of the actual
`origin/main` into this branch; the regenerated localizations from the union of approved ARB keys; D1 test 15 of
`supabase/tests/public_surface_acl_remediation_001_test.sql` (the six exact C2 service-only signatures appended, every
predecessor entry and assertion kept, the before / after sets shown); exactly one `db-tests` step in
`.github/workflows/ci.yml` (`node supabase/tests/support/run_bizbot_zcredit_001d_concurrency.mjs --container
supabase_db_RestoFlow`, directly after the merged acceptance-ETA runner); the acceptance-ETA regression pair in the
regression lane and the acceptance-ETA (`with_eta`) reach text of API §4.14 / §4.49 (the D-060 ratification notes
of §4.14 / §4.49 are recorded now, item 2).

**Never under this decision:** any other file (no other migration, Edge function, POS / KDS / Kiosk / Storefront /
printing source, `supabase/config.toml`, pubspec or lockfile, release or signing file, `AGENTS.md`, `CLAUDE.md`,
`AGENT_WORKFLOW.md`, `docs/TASK_TRACKER.md`, `docs/POS_ONLINE_INBOX_001.md`, the pilot sequencing, vendor-private
material) and nothing in #366 / #368 or their branches; W7 (push / PR) and W8 (merge).

### 15.4 Key ownership and generation (S4)

- #366 keeps its six keys (`posOnlineInboxPreparationTitle`, `…Hint`, `…Minutes`, `…Custom`, `…Range`, `…Confirm`),
  their metadata and their generated members; nothing of #366 or its branch is touched.
- 001D owns exactly the 71 new `activityLog*` card keys below and their 71 `@`-metadata entries *(73 and 73 after the
  §15.4a amendment)*
  (a `description` beginning "BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D Activity-log" in the en template; ar / he carry the
  values only, as for every key). Titles go after `activityLogTitlePaymentRecorded`; every other key after
  `activityLogDeniedInvalidDeviceType` (and its metadata in en). No unrelated key, formatting or ordering change.
- `_activityLogKeyCountSnapshot` becomes 200 + 71 = 271 (new non-metadata `activityLog*` keys) *(§15.4a: 200 + 73 =
  273)*.
- Generation: Flutter 3.44.2 (verified locally); the `generate` flag of `packages/l10n/pubspec.yaml` is set only for the
  generation run and its original bytes restored at once; generated files are never hand-edited; a second generation
  must produce no difference. A baseline regeneration from the unmodified ARBs reproduced the committed generated
  files byte for byte before any key was added.

| Key | Anchor | en |
|---|---|---|
| `activityLogTitleCardAttemptStarted` | after `activityLogTitlePaymentRecorded` | Card payment started at the terminal |
| `activityLogTitleCardAttemptApproved` | after `activityLogTitlePaymentRecorded` | Card payment approved by the provider |
| `activityLogTitleCardAttemptDeclined` | after `activityLogTitlePaymentRecorded` | Card payment declined by the provider |
| `activityLogTitleCardAttemptUnknown` | after `activityLogTitlePaymentRecorded` | Card payment result unknown |
| `activityLogTitleCardAttemptReleased` | after `activityLogTitlePaymentRecorded` | Card payment request released at the terminal |
| `activityLogTitleCardAttemptAnomalyRaised` | after `activityLogTitlePaymentRecorded` | Card payment flagged: a charge may exist |
| `activityLogTitleCardAttemptAnomalyCleared` | after `activityLogTitlePaymentRecorded` | Card payment flag cleared by the provider result |
| `activityLogTitleCardAttemptAnomaly` | after `activityLogTitlePaymentRecorded` | Card payment provider anomaly |
| `activityLogTitleCardAttemptReleaseRequested` | after `activityLogTitlePaymentRecorded` | Card payment release requested |
| `activityLogTitleCardAttemptReleaseFailed` | after `activityLogTitlePaymentRecorded` | Card payment release failed |
| `activityLogTitleCardAttemptRecordingRefused` | after `activityLogTitlePaymentRecorded` | Approved card payment could not be recorded |
| `activityLogTitleCardAttemptOrderFreed` | after `activityLogTitlePaymentRecorded` | Order unlocked after a card payment check |
| `activityLogTitleCardAttemptResumeRequested` | after `activityLogTitlePaymentRecorded` | Card payment recording retry requested |
| `activityLogTitleCardAttemptDenied` | after `activityLogTitlePaymentRecorded` | Card payment action denied |
| `activityLogFieldCardState` | after `activityLogDeniedInvalidDeviceType` | Card payment state |
| `activityLogFieldCardMode` | after `activityLogDeniedInvalidDeviceType` | Payment mode |
| `activityLogFieldCurrency` | after `activityLogDeniedInvalidDeviceType` | Currency |
| `activityLogFieldCardRefusal` | after `activityLogDeniedInvalidDeviceType` | Recording refusal |
| `activityLogFieldCardAnomaly` | after `activityLogDeniedInvalidDeviceType` | Provider anomaly |
| `activityLogFieldCardReleaseRequested` | after `activityLogDeniedInvalidDeviceType` | Release requested |
| `activityLogFieldCardConfirmationSource` | after `activityLogDeniedInvalidDeviceType` | Confirmed via |
| `activityLogFieldCardPriorRefusal` | after `activityLogDeniedInvalidDeviceType` | Previous refusal |
| `activityLogFieldCardResumeCount` | after `activityLogDeniedInvalidDeviceType` | Retry number *(§15.4a: Earlier retries)* |
| `activityLogFieldCardResumeOutcome` | after `activityLogDeniedInvalidDeviceType` | Retry result |
| `activityLogCardStateSent` | after `activityLogDeniedInvalidDeviceType` | Sent to the terminal |
| `activityLogCardStateApproved` | after `activityLogDeniedInvalidDeviceType` | Approved |
| `activityLogCardStateDeclined` | after `activityLogDeniedInvalidDeviceType` | Declined |
| `activityLogCardStateUnknown` | after `activityLogDeniedInvalidDeviceType` | Unknown |
| `activityLogCardStateReleased` | after `activityLogDeniedInvalidDeviceType` | Released at the terminal |
| `activityLogCardModeLive` | after `activityLogDeniedInvalidDeviceType` | Live |
| `activityLogCardModeTest` | after `activityLogDeniedInvalidDeviceType` | Test |
| `activityLogCardAnomalyAmountMismatch` | after `activityLogDeniedInvalidDeviceType` | Amount mismatch |
| `activityLogCardAnomalyCurrencyMismatch` | after `activityLogDeniedInvalidDeviceType` | Currency mismatch |
| `activityLogCardAnomalyPreauthorization` | after `activityLogDeniedInvalidDeviceType` | Pre-authorization only |
| `activityLogCardAnomalyPartialRefund` | after `activityLogDeniedInvalidDeviceType` | Partially refunded |
| `activityLogCardAnomalyRefunded` | after `activityLogDeniedInvalidDeviceType` | Refunded |
| `activityLogCardAnomalyVoided` | after `activityLogDeniedInvalidDeviceType` | Voided by the provider |
| `activityLogCardAnomalyOutOfContract` | after `activityLogDeniedInvalidDeviceType` | Unexpected provider reply |
| `activityLogCardRefusalReleaseFailed` | after `activityLogDeniedInvalidDeviceType` | Release failed |
| `activityLogCardRefusalConflict` | after `activityLogDeniedInvalidDeviceType` | Conflicting change |
| `activityLogCardRefusalPreconditionFailed` | after `activityLogDeniedInvalidDeviceType` | Order or shift state changed |
| `activityLogCardRefusalRevokedEmployee` | after `activityLogDeniedInvalidDeviceType` | Employee no longer active |
| `activityLogCardRefusalRevokedDevice` | after `activityLogDeniedInvalidDeviceType` | Device no longer authorized |
| `activityLogCardRefusalPaymentInProgress` | after `activityLogDeniedInvalidDeviceType` | Another payment is in progress |
| `activityLogCardRefusalProviderRecordingRefused` | after `activityLogDeniedInvalidDeviceType` | Recording refused after approval |
| `activityLogCardRefusalNonrecoverable` | after `activityLogDeniedInvalidDeviceType` | Needs manual resolution |
| `activityLogCardConfirmationProviderReport` | after `activityLogDeniedInvalidDeviceType` | Provider report |
| `activityLogCardConfirmationBackOffice` | after `activityLogDeniedInvalidDeviceType` | Provider back office |
| `activityLogCardResumeDispatched` | after `activityLogDeniedInvalidDeviceType` | Retry sent |
| `activityLogCardResumeRefused` | after `activityLogDeniedInvalidDeviceType` | Retry refused |
| `activityLogDeniedIneligibleOrderState` | after `activityLogDeniedInvalidDeviceType` | The order can’t take a card payment now |
| `activityLogDeniedMaxLiveAmountExceeded` | after `activityLogDeniedInvalidDeviceType` | Above the card payment limit |
| `activityLogDeniedNoOpenShift` | after `activityLogDeniedInvalidDeviceType` | No open shift on this device |
| `activityLogDeniedNoActiveDrawer` | after `activityLogDeniedInvalidDeviceType` | No active cash drawer |
| `activityLogDeniedNoRecordingAttempt` | after `activityLogDeniedInvalidDeviceType` | No recording attempt to report |
| `activityLogDeniedAttemptNotFreeable` | after `activityLogDeniedInvalidDeviceType` | This card payment can’t unlock the order |
| `activityLogDeniedChargeMayExist` | after `activityLogDeniedInvalidDeviceType` | A charge may exist — check with the provider |
| `activityLogDeniedConfirmationRequired` | after `activityLogDeniedInvalidDeviceType` | Provider confirmation required |
| `activityLogDeniedDeviceNotActive` | after `activityLogDeniedInvalidDeviceType` | Device not active |
| `activityLogDeniedOperationMismatch` | after `activityLogDeniedInvalidDeviceType` | The retry doesn’t match the original payment |
| `activityLogDeniedResumeLimit` | after `activityLogDeniedInvalidDeviceType` | Retry limit reached |
| `activityLogDeniedResumeStale` | after `activityLogDeniedInvalidDeviceType` | A newer retry already exists |
| `activityLogDeniedNotRecoverable` | after `activityLogDeniedInvalidDeviceType` | Can’t be retried |
| `activityLogDeniedPaymentExists` | after `activityLogDeniedInvalidDeviceType` | Payment already recorded |
| `activityLogDeniedClaimInactive` | after `activityLogDeniedInvalidDeviceType` | The card payment is no longer active |
| `activityLogDeniedOrderNotChargeable` | after `activityLogDeniedInvalidDeviceType` | The order can no longer be charged |
| `activityLogDeniedContextLost` | after `activityLogDeniedInvalidDeviceType` | Shift or cash drawer no longer open |
| `activityLogDeniedAmountMismatch` | after `activityLogDeniedInvalidDeviceType` | Amount doesn’t match the order |
| `activityLogDeniedRefusalNotRecorded` | after `activityLogDeniedInvalidDeviceType` | The last refusal isn’t reported yet |
| `activityLogYes` | after `activityLogDeniedInvalidDeviceType` | Yes |
| `activityLogNo` | after `activityLogDeniedInvalidDeviceType` | No |

Shared tokens reuse one label: refusal `order_not_chargeable` / `amount_mismatch` / `card_context_lost` use
`activityLogDeniedOrderNotChargeable` / `activityLogDeniedAmountMismatch` / `activityLogDeniedContextLost`, and
`permission_denied` keeps the existing `activityLogDeniedPermission` *(§15.4a, narrowed by its re-review amendment:
only the `denied_reason` of `card_attempt.denied` uses `activityLogDeniedCardPermission`; a refusal or prior refusal
keeps this label)*.

#### 15.4a Review amendment (2026-10-25; recorded before the fix commits)

The fresh-context Claude delta review of this checkpoint (§15.9) confirmed label and translation defects in the
manifest above. This amendment is recorded before any fix commit; key ownership, the two anchors, the generation rules
and the eleven-file allowlist are unchanged.

- **Two new 001D keys**, inside the 001D block after `activityLogDeniedInvalidDeviceType`, each with its en
  `@`-metadata:

  | Key | Placed after | en | Use |
  |---|---|---|---|
  | `activityLogFieldCardReleaseStatus` | `activityLogFieldCardRefusal` | Release status | the label of `refusal_code` on the five provider-result actions, where the server writes only `release_failed` — a terminal release fact, never a recording refusal; `card_attempt.recording_refused` keeps "Recording refusal" |
  | `activityLogDeniedCardPermission` | `activityLogDeniedRefusalNotRecorded` | Not permitted on this device or for this role | the label of the `denied_reason` `permission_denied` of `card_attempt.denied`: the card proof answers that one token both for a non-POS device and for a role not allowed to take card payments; a refusal or prior refusal `permission_denied` (`app.record_payment`'s role refusal) and every other action keep the shared `activityLogDeniedPermission` (narrowed by the re-review amendment below) |

- **Changed 001D values:** `activityLogFieldCardResumeCount` en "Retry number" → "Earlier retries" — the server's
  `resume_count` counts the authorized retries made before the request (0 on the first) and is shown raw, never
  shifted into an ordinal. ar / he wording of: `activityLogTitleCardAttemptAnomalyRaised` and
  `activityLogDeniedChargeMayExist` (ar: "a charge may exist" no longer uses the bare noun that means "discount" in
  this app); `activityLogFieldCardResumeCount`, `activityLogFieldCardResumeOutcome`, `activityLogCardResumeDispatched`,
  `activityLogCardResumeRefused`, `activityLogDeniedResumeLimit` and `activityLogDeniedResumeStale` (a retry is named
  as a retry, never as the card attempt; he impersonal); `activityLogDeniedConfirmationRequired` (he: a confirmation,
  not an approval); `activityLogCardStateReleased` (the terminal request was cancelled, not the payment — released is
  provisional); `activityLogCardStateDeclined` and `activityLogTitleCardAttemptDeclined` (a provider decline no longer
  reads like the Denied pill); `activityLogDeniedContextLost`, `activityLogDeniedAttemptNotFreeable` and
  `activityLogFieldCardAnomaly` (ar agreement and referent). The en metadata of `activityLogTitleCardAttemptReleased`,
  `activityLogCardStateReleased`, `activityLogFieldCardRefusal` and `activityLogFieldCardResumeCount` states the
  refined meaning.
- 001D therefore owns 73 keys and 73 `@`-metadata entries; `_activityLogKeyCountSnapshot` becomes 200 + 73 = 273.
- **Presenter:** `refusal_code` is labelled per action (the release status on the five provider-result actions); the
  card family's `denied_reason` renders through a card-scoped kind that differs from the shared denial labels only for
  `permission_denied`. The rendering test pins every action's exact title, every token's exact label (distinct within
  each vocabulary), the exact ordered field labels of each action and the raw `resume_count`.
- **Re-review amendment (2026-10-25, recorded before its fix commit):** the fix re-review (§15.9) narrowed two
  rules. `activityLogDeniedCardPermission` labels only the `denied_reason` of `card_attempt.denied`; a `refusal_code`
  or `prior_refusal_code` of `permission_denied` is `app.record_payment`'s role refusal and keeps the shared
  `activityLogDeniedPermission` (the en metadata of `activityLogDeniedCardPermission` says so). A `prior_refusal_code`
  of `release_failed` — the stored release fact an attempt keeps after a later approval — is labelled as the release
  status, like `refusal_code` on the provider-result rows. The rendering test again asserts that every
  closed-vocabulary token value and every prior-refusal value is non-empty. No key is added; the count stays
  73 / 273. *(Final check, 2026-10-25: the en metadata of `activityLogFieldCardReleaseStatus` and
  `activityLogFieldCardPriorRefusal` also states the `release_failed` prior-refusal rule — descriptions only.)*

### 15.5 Per-action title, fields and tone

Exactly the twelve LIVE tenant actions are registered (`category: payments`, `hasTitle: true`); the private
`operator.*`, `test.*` and `security.*` events are never registry entries. Fields are exactly the keys
`app.audit_safe_detail` projects for the action (§4.7), rendered from the new values in this order.

| Action | Title key | Projected fields | Tone / icon |
|---|---|---|---|
| `card_attempt.started` | activityLogTitleCardAttemptStarted | attempt_state, mode, amount_minor (row currency), currency_code | info / credit card |
| `card_attempt.approved` | activityLogTitleCardAttemptApproved | attempt_state, refusal_code (labelled as the release status, §15.4a), anomaly_code, release_requested | success / credit card |
| `card_attempt.declined` | activityLogTitleCardAttemptDeclined | same four | neutral / card off |
| `card_attempt.unknown` | activityLogTitleCardAttemptUnknown | same four | warning / help |
| `card_attempt.released` | activityLogTitleCardAttemptReleased | same four | info / credit card |
| `card_attempt.provider_anomaly` | AnomalyRaised (unknown / released) · AnomalyCleared (approved / declined) · Anomaly (otherwise) | same four | danger · info · warning / report problem or card |
| `card_attempt.release_requested` | activityLogTitleCardAttemptReleaseRequested | attempt_state | info / credit card |
| `card_attempt.release_failed` | activityLogTitleCardAttemptReleaseFailed | attempt_state | warning / report problem |
| `card_attempt.recording_refused` | activityLogTitleCardAttemptRecordingRefused | refusal_code | warning / report problem |
| `card_attempt.order_freed` | activityLogTitleCardAttemptOrderFreed | attempt_state, confirmation_source | warning / lock open |
| `card_attempt.recording_resume_requested` | activityLogTitleCardAttemptResumeRequested | attempt_state, prior_refusal_code, resume_count (earlier retries, raw), outcome, denied_reason | info (dispatched) · warning (otherwise) / replay |
| `card_attempt.denied` | activityLogTitleCardAttemptDenied | denied_reason | warning / block + Denied pill |

### 15.6 Presenter-only rules

In `audit_log_presentation.dart` only: only the projected keys of the action render (a hostile or
legacy payload cannot surface a provider / terminal / credential reference, an approval or voucher number, an
internal identifier or another family's key); old values and the free-text reason are never shown for this family;
money renders only on `.started`, as an integer minor amount in the row's own ISO currency when well formed (else the
page currency), and a non-integer amount does not render; closed-enum values are localized and an unknown token of a
projected key shows raw; the Denied pill is set for `card_attempt.denied` in the presenter only (`audit_log_models.dart`,
the demo repository, the pre-existing `payment.denied` styling and generic `sync.operation_rejected` localization stay
out of scope); titles describe the provider's result, never that the frozen initiating employee approved or declined.
The card keys render through the per-action allowlist `_cardAttemptKeys` / `_cardFieldKinds` and are labelled in
`auditFieldLabel`; the global `_displayableKeys` allowlist is deliberately unchanged — the recorded reading of the
"`_displayableKeys` labels" wording of API §4.33 and pilot §7. *(Amended 2026-10-25, §15.4a: the per-action
`refusal_code` label, the release-status label of a `release_failed` prior refusal and the card permission label of
`card_attempt.denied`'s `denied_reason` only.)*

### 15.7 Appendix A dispositions (packet §11 numbering; local integration only — no proof of 001E, hosted or physical behaviour)

| Item | Disposition | Existing tests | Downstream gate owner | Still unproven |
|---|---|---|---|---|
| 1 pilot pinning to the in-repo scope constants | ACCEPT | SA-091, SA-001, CI-184, LR-54 | none (real pilot rows: 001H) | Hosted presence of the pinned scope and the real pilot rows (001H) are not verified locally. |
| 2 service-only re-proof without the renewal write | ACCEPT | SA-080, CI-058, CI-278, CC-C32, CC-C40 | none | No assertion reads the device session after a SUCCESSFUL service-only call (CI-387..CI-389 positive controls do not), SA does not pin the p_renew=false argument, and the lock set is never compared directly with the renewal path's. |
| 3 `card_terminal_*` keys only for a non-retired exact-device mapping | ACCEPT | LR-01, LR-29, LR-34, RG-07 | none (client hiding: 001F) | Client hiding on an absent key (001F) is not tested; the pre-existing exact-equality capability tests outside the lanes are evidenced only by the full-suite run. |
| 5 non-disclosing missing / out-of-scope start refusal and check order | ACCEPT | CI-144, CI-146, CI-147, CI-148, CI-171, CI-167 | none | No vector combines a paid order with an active claim, so the paid-guard -> payment_in_progress adjacency is pinned only by CI-167 and CI-171 separately. |
| 6 same-row Resume reopen bookkeeping | ACCEPT | RR-074, RR-077, RR-101, RR-102 | none (Resume UI: 001C / 001F) | DB side pinned; the client Resume UI (001C/001F per packet §10) is not built. |
| 7 explicit target / timestamp / payload comparison in the Resume guard | ACCEPT | SA-053, RR-086, RR-087, RR-091 | none | The guard's own payload comparison is shadowed by the preamble fingerprint (RR-088: payload change -> sync.operation_conflict first); no test isolates that branch. |
| 8 `recording_resume` jsonb parse and bounds | ACCEPT (not a money or generic numeric-input rule) | RR-112, RR-108, RR-107, RR-114 | none | The 2e-1 form is not a named vector; the client/Edge serializer that emits recording_resume is not tested. |
| 9 explicit revokes before the single grant | ACCEPT | SA-037, SA-041, SA-042, SA-044, SA-125 | hosted apply PRE / POST (pinned ACLs) | Hosted default-privilege stamping is not simulated locally; effective hosted grants are unverified. |
| 10 one de-duplicated private TEST refusal event, no tenant trace | ACCEPT (revoked-device carve-out kept) | TI-76, TI-74, TI-85, TI-108, TI-115 | none | Concurrent de-duplication rests on SA-086 and the manual CC lane (C14, C29), which is not CI-wired *(2026-10-26: wired by `297d576d` as one `db-tests` step, not yet run in CI, §16.3)*. |
| 11 Resume adopt path, freshness, bounded history, guard order | ACCEPT (no new provider call) | RR-075, RR-077, RR-201, RR-159, CC-C25 | none (provider counts: 001E) | 'No new provider call' is not measurable in pgTAP (call intent only); 001E provider-request counts not implemented. |
| 12 operator-only result vocabulary with the D-059 shutdown exception | ACCEPT | LR-54, LR-158, LR-159, LR-52, SA-051 | none (operator runbook) | Operator/runbook handling of these tokens is untested (operator SQL only). |
| 13 proof-level, mode-aware denial evidence | ACCEPT WITH LIMIT: no universal zero-write support-race claim — a failed proof may write its denial event before the later binding check; no payment / attempt-state / Resume write or disclosure | CI-297, CI-308, CI-309, CI-373, SA-139 | none | The limit case (a proof refusing with evidence after a concurrent support activation) is pinned only textually by SA-139; no runtime race leg. |
| 14 Resume audit identity for de-duplication, never projected | ACCEPT | RR-078, RR-087, FR-198 | this integration (presenter never projects it); 001G verifies | Dashboard presenter non-projection is outside the DB lanes. |
| 15 120-second internal start deadline | ACCEPT (not a provider response-time promise) | CI-118, FR-136, FR-152 | 001E (commit budget below it) | 001E commit budget and poll cap/cadence NOT IMPLEMENTED; no provider timing evidence. |
| 16 organization / branch-scoped order locking, anti-oracle denial | ACCEPT | RG-61, RG-64, RG-66, RG-67 | none | No lock-level proof (pg_locks / wait) that a foreign order row is never locked; the runner has no cross-scope scenario — only answer equality is pinned. |
| 17 capability key may stay true while cap validation refuses starts | ACCEPT (server start authorization is authoritative) | LR-23, CI-087, LR-97, LR-28 | 001F (must render the refusal) | No assertion reads card_terminal_enabled under a cap-less revision (true-while-refusing is inferred); 001F rendering not built. |
| 18 unreadable essential anomaly inputs keep charge-risk protection | ACCEPT | FR-143, FR-84, FR-101, CI-396 | 001E (reply parser) | A commit-source 'anomaly' outcome with a failing essential field is not separately pinned (FR-98 covers an unknown code only); 001E parser not built. |
| 19 operator-only trigger / uniqueness failures (23514 / 23505) | ACCEPT (no conversion into success, no automatic retry, no public error detail) | LR-76, LR-77, LR-75, CC-C22 | none | Two concurrent enables racing to 23505 are not exercised (LR-75 is a direct UPDATE); operator-side handling of the raw raise is untested. |
| 20 manager-scoped attempt lookup; others own device only | ACCEPT (never cross-device financial recording) | CI-311, CI-312, CI-315, CI-181 | none | No dedicated negative that another device's push can never record d1's payment; rests on the device-scoped identity. |
| 21 operator authority before field-rule detail | ACCEPT | LR-149, LR-152, LR-153, LR-154 | none | Nothing material at the DB level; operator tooling/runbook untested. |
| 22 release-request stamping and LIVE audit | ACCEPT (no automatic release; 001E limits unchanged) | RR-175, RR-176, RR-177, RR-178 | 001E (release transport and limits) | 001E release transport, request limits and cadence NOT IMPLEMENTED. |
| 23 failed lookup without a provider fact is no contradiction | ACCEPT | FR-270, FR-272, FR-273, FR-274 | none (001E transport) | Real provider failure classification (001E transport) not built. |
| 25 closed trigger / no-op / history rules | ACCEPT (no unresolved-charge escape) | LR-175, LR-176, LR-177, LR-178, LR-180 | none | Clearing a stored provider_anomaly_code (23514 in every state) and the resolved-row no-op of an order_freed change have no direct assertion. |
| 28 pinned UCD 15.1 classes, server normalize() | ACCEPT CONDITIONALLY: the hosted PostgreSQL / Unicode preflight stays mandatory and unperformed | FR-11, FR-291, FR-295, FR-318 | hosted deployment preflight | No lane asserts the server's Unicode version; the hosted PostgreSQL/Unicode check is unperformed. |
| 29 context answers ok with a null attempt for an unknown id | ACCEPT (absence decided per action, no foreign exposure) | CI-028, CI-311, LR-170, CC-C40 | none | No context call naming a foreign-organization attempt id is asserted null; non-exposure rests on the device/branch-scoped lookup. |
| 30 lookup approval follows its own validated contract | ACCEPT | FR-102, FR-110, FR-109, FR-111, FR-115, FR-116 | 001E (wire parsing, provider evidence) | Real reply parsing and provider evidence are absent (001E). |
| 34 commit-order cursor skew of `claim_signal_at` | ACKNOWLEDGED as a UX limitation only; the server guard stays financial authority; not every claim start is seen instantly | none for the effect itself; mitigations RR-016, RG-138, RG-131 | 001F (targeted-refresh handoff owed) | A cursor passing an uncommitted claim stamp is untested; the 001F targeted refresh is not built. |
| 35 residual text vectors (Lo / sideways-I joiners, non-mask asterisk, Lm-only reason) | ACKNOWLEDGED LOCAL LIMITATION ONLY — not accepted as satisfying an absolute no-full-or-masked-card guarantee; no Unicode class broadened, C2 not rewritten | none pins the vector itself; bounding controls FR-302, FR-306, FR-310, FR-313 | 001E; real provider input / live operation blocked until a reviewed safe response / metadata disposition | Masked forms under 12 digit-like characters joined by those letters, and Lm-only reasons, still pass; no reviewed safe disposition exists. |
| R1 a reached fresh web-order acceptance in an ACTIVE support session raises 42501 | ACCEPT locally (Edge 401 mapping not newly tested; no typed web-order API here) | RG-170, RG-171, RG-172, RG-173; RG-174..RG-177 (the acceptance-ETA entry, §16.3) | web-order owner (typed answer, own Work ID); the S7(a) ETA regression — executed at W3 on 2026-10-26, after the W2 composition | Edge 401 mapping not newly tested (for the acceptance-ETA entry neither); no typed web-order answer. |
| R2 the context read keeps one support check before its proof | ACCEPT locally (no absolute read-free support isolation claimed) | CC-C31, CI-327, CI-378, CI-379 | none | The exact case (activation committed while the context proof waits on its own locks) has no runtime leg. |
| R3 other pre-existing PIN entry points have no support check | ACKNOWLEDGE (out of scope; no approval to use support mode for tenant writes) | none; RG-172 | each needs its own Work ID | Support refusal on the other PIN entry points is neither implemented nor tested. *(2026-10-26 review note, §16.7: the pre-existing non-PIN kiosk device-token order entry `public.kiosk_submit_order` has no support-session check either; outside **D-060** point 1.)* |
| R4 the cutoff needs 001E single calls at READ COMMITTED | CONDITIONAL: not valid under arbitrary isolation levels | CC-C34, CC-C40, CC-C41, CI-379 | 001E (same-request binding, single READ COMMITTED calls) | 001E binding and single-call obligations NOT IMPLEMENTED; no REPEATABLE READ / SERIALIZABLE negative; no hosted isolation validation. |
| R5 12+ digit-like characters refused (date-times, phone numbers, long references) | ACCEPT locally (false refusals documented; text rules not weakened) | FR-316, FR-13, FR-306, LR-150 | 001F + runbook | 001F refusal rendering and runbook guidance not written; the phone-number shape is covered only generically. |

No general C3 round is requested or authorized; nothing in C2 is rewritten and no Unicode class is broadened.

### 15.8 Holds and later gates

- **Dependency composition (held):** #366 and #368 were OPEN and unmerged at this checkpoint, so W2–W6 (the merge
  from `main`, the union regeneration, D1, the CI step, the acceptance-ETA regression pair and the real-composition
  validation) are held; no combined-base result is claimed. *(Released 2026-10-26: #368 merged first (`30ac598f`),
  then #366 (`d2079820`); W2–W6 are recorded in §16.)*
- **Binding rules for W2–W6 (decision sections 4, 6 and 8; recorded here so the packet is self-contained):**
  - The composition starts only when BOTH #366 and #368 are independently merged and their ownership is released:
    fetch and re-verify `main` and the effective merged contents; merge the actual `origin/main` with a normal merge
    commit only; never import their unmerged branches; preserve the union of approved ARB keys and regenerate (never
    hand-merge generated outputs); prove the unchanged migration content and the preservation of the original payment
    source; rerun the relevant local tests on the composed base. Known key-level l10n overlap and unrelated
    conflict-free drift are not blockers; if their owners merged them in another order, record the actual order and
    re-derive the union, never undoing another stream. If the re-creation of a pinned function or a real semantic
    conflict appears, stop only the affected composition and report its exact delta; never repair another workstream
    or overwrite its source.
  - **Then, and only then** — at W3, after every composition step above — three changes are released:
    - D1: test 15 only — the six exact C2 service-only signatures appended; every predecessor entry, v4 / status_v2
      assertion, other assertion and the test plan preserved; the actual before / after signature sets and the six-entry
      addition shown (22 is the proposal's expectation on its stated base, not a hardcoded goal).
    - CI: exactly one `db-tests` step (the command in §15.3) directly after the merged acceptance-ETA runner; every other
      step, permission, trigger, timeout and environment setting preserved; no CI identity flag is set locally to bypass
      the runner's environment guard.
    - ETA regression: the S7(a) support-admission regression and the ordinary transport-JWT control in the existing 001D
      regression lane, proving the rollback of the order and of the ETA sidecar, the preservation of the pending request
      and the exact real call path; only the corresponding API §4.14 / §4.49 reach text and the payment packet change.
  - Migration drift (S9): the bytes and SHA-256 stay frozen. Only if a later migration version reaches `main` first and
    none of the relevant function definitions or ACLs change is a new CLI-generated filename / version permitted,
    preserving the exact content bytes — the old filename removed from this branch's final tree, every version
    reference updated and both identities recorded; the original C2 branch and archive are preserved and hosted
    migration history is never repaired. If a relevant function was re-created or changed on `main`, renaming is not a
    fix: report the new definitions and the required re-emission scope before changing the frozen SQL; the old
    acceptance does not transfer to a new body.
  - Validation after the composition (S10): a fresh isolated disposable reset and first full-suite run; the seven
    payment lanes; the concurrency runner twice; PRE / POST / hash / ACL / owner / security checks on every re-created
    or pinned routine; `app.record_payment` unchanged, with no new public wrapper or caller; the local Flutter / l10n /
    Dashboard validation and every relevant guardrail; local-only CI-restricted cases stay **NOT VALIDATED**, never
    counted as passing. Eventually BOTH exact-head `validate` AND `db-tests` succeed in actual CI (D1, the 353, ETA
    and 001D runners and the CI-only files included); branch protection requiring only `validate` does not waive
    `db-tests`; no test is weakened; job durations are recorded; if `validate` crosses about 27 minutes, capacity is
    reported and any CI change is requested separately; no timeout or lane waiver is authorized.
- **S12 process record (held):** once the final composed head is frozen, a separate LOCAL docs-only branch stacked on
  it, Work ID `BIZBOT-PAYMENTS-ZCREDIT-001D-REVIEW-EXCEPTION-001`, records the exception (fresh-context Claude
  read-only review + command-room source-matched review of the exact final head + separate owner merge approval, for
  001D and that record only) with the next verified free decision ID (D-061 expected, not reserved). It is not
  prepared at this checkpoint. It does not amend D-016 or AGENT_WORKFLOW, and no Claude review is called a Codex
  review. The exception changes no financial, provider, security, CI, hosted, branch-protection or publication gate
  and does not approve 001E, 001C, 001F, 001G, 001H or any other workstream. Future order: the exception is recorded
  and approved before the 001D merge approval; 001D merges, then its companion, in the approved sequence; the
  companion is never published on `main` ahead of the implementation it is stacked on. No push or merge of either
  branch is authorized now, and this step creates no demand for Codex approval of the owner-directed exception itself.
  The companion's scope is only the narrow DECISIONS entry / changelog line and its own evidence; it states the
  exception, its exact applicability, the remaining reviews and that D-016 / AGENT_WORKFLOW are not amended (those
  files are not edited); its exact text and head are reviewed before any merge approval; the 2026-10-23 one-time
  waiver is not recycled as an unexplained global exception. *(2026-10-26: prepared only after this branch's final
  head is frozen, on its own local branch stacked on that head — not part of this branch, §16.5.)*
- **S13 publication review (owed):** at W6, over the C2 source baseline, every newly publishable commit above M2 on this
  branch and the full integration delta, with the exact-head review. No push or PR is authorized. *(2026-10-26: the
  W6 package, built from the frozen final head, will carry that material, §16.5; the command-room review
  itself remains.)*
- **S14 C:** 001D stays unmerged until the existing pilot rollout prerequisites and the separately approved deployment
  sequence are ready; hosted status is not established by this work.
- **S15:** before any eventual push, every affected project's fan-out is recomputed at the exact head; no
  configuration, Git-link, alias or ignore-build change.
- **Decision text:** the owner's authorization and the command-room decision "LOCAL INTEGRATION CONTINUATION", as
  received, are archived outside Git at `evidence/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-INTEGRATION-20261025/decision/`
  (SHA-256 `d635fb6dbf4c54f4b934f781d2ee2f762c36a5a9cee4923a980614da413df005`).
- **For the web-order owner:** `docs/POS_ONLINE_INBOX_001.md` lines 56-60 still list fixed failure codes without the
  D-060 raise (a fresh acceptance in an ACTIVE support session raises 42501); API §4.49 is accurate.

### 15.9 Disposition (local checkpoint, 2026-10-25)

**Implemented locally (unpushed, unmerged, undeployed):**

- Clean-history import `dde0857a`, `32d3384d`, `07ce4794` (§15.2): the import head's tree equals the C2 tree, the
  migration SHA-256 is the frozen value at every commit, and none of the 25 original commits is reachable.
- Audit UI under §15.3 item 1 — exactly the eleven allowlisted files (`d6b5d325`, `50f052e9`; review fixes `502f085f`,
  `01656b2a`, `67c79726`, `dc141112` and `d649f72e`, the last two en descriptions only): 73 new `activityLog*` keys per locale (the 71 of §15.4 and the two of §15.4a)
  with 73 en `@`-metadata entries, inserted only inside the two 001D blocks at their anchors, with no other entry
  changed; exactly the twelve LIVE `card_attempt.*` actions registered; the presenter rules of §15.4a–§15.6;
  `_activityLogKeyCountSnapshot` 200 → 271 → 273 with its assertion kept.
- Documentation: `2211e52f` (§15, before any UI edit), `d0370204` (the narrow §5 refresh), `bda2abc2`, `ab8a9e72` and
  `8419413d` (the §15.4a amendments, each before its fix commits), `df747cba` and `54a03df0` (the review dispositions)
  and this section (`c7658bf8`, completed after the final check).

**Generation:** Flutter 3.44.2; the `generate` flag of `packages/l10n/pubspec.yaml` was set only for each run and
restored byte for byte; a baseline regeneration from the unmodified ARBs reproduced the committed files; after every ARB
change a second generation produced no difference; no generated file was hand-edited.

**Local validation** at `54a03df0` (code as of `dc141112`; the later commits change documentation, except `d649f72e`,
which changes only two en descriptions and their generated doc comments — on it `check_l10n`, `flutter test
packages/l10n` (95 passed), the format check and the analyzer re-ran green and a second generation was identical):
the `dart format` check (1 774 files, 0 changed); `check_l10n` OK; `flutter test packages/l10n` 95 passed; `flutter test
apps/dashboard` 2 564 passed and 16 skipped (pre-existing skip markers, none in the new test); `melos run analyze` no
issues; the float-money, secret and hardcoded-string guardrails OK; the worktree clean afterwards.
`card_attempt_activity_log_test.dart` passes 15 / 15, and eleven mutations each make it fail (titles, labels, the key
set and order, every presenter review fix reverted — UI-1, UI-4, FIX-RR-2, FIX-RR-3 — the Denied pill, the reason
suppression, a blank generated value). The
broadened history scan passed at `54a03df0` over all fifteen commits above M2 (24 masked-shape entries, all in the C2
lanes; 22 out-of-range Luhn synthetic sites; the one disclosed path; exactly the 32 authorized paths) and is re-run at
the frozen head for the checkpoint package.

**Not run or NOT VALIDATED at this checkpoint:** no database replay — the migration, the seven lanes and the runner are
byte-identical to the C2-validated tree, whose results §14 records; D1 test 15 still fails by design until W3; the
CI-only `zz_storefront_featured_items_001_concurrency_test.sql` stays **NOT VALIDATED** locally; the concurrency runner
stays a manual lane; no combined #366 / #368 base exists, so no combined-base result is claimed; nothing ran in CI.

**Review:** three fresh-context Claude read-only rounds, each followed by one adversarial verifier per non-NOTE
finding.
Round 1 (the clean import and the integration commits at `d0370204`; four lenses — audit UI, l10n, documentation,
clean history) found no BLOCKER: of its 20 verified findings 19 were confirmed and one was refuted to a NOTE, and both
MAJOR findings were confirmed at MINOR. Round 2 (the fix commits `d0370204..df747cba`; two lenses) found the other
round-1 dispositions fixed, history F1 and docs F2 / F3 / F5 PARTIAL (refined by its own findings below) and docs
F1 / history F3 pending this section, and no BLOCKER or MAJOR; its four MINOR findings (all confirmed) and six NOTEs — the
dropped non-empty assertion, the failed-release prior refusal, the scope of the card permission label, the unnamed
masked-vector rows and the scanner's coverage, the W3 placement of D1 and the CI step, the S12 companion's bounds and
wording — are fixed by `ab8a9e72`, `67c79726`, `dc141112` and `54a03df0`. Round 3 (a final check of
`df747cba..c7658bf8`; one reviewer) found every round-2 disposition fixed and no BLOCKER or MAJOR; its two MINOR
findings (both confirmed: the W3 wording of the ETA pair in the S7(a) and R1 rows, and this section's round-2
summary) and four NOTEs (two stale permission pointers, two en descriptions, two coverage phrases, the package's
tense) are fixed by `8419413d`, `d649f72e` and the final wording of this section. A fresh-context check of those fixes
(`c7658bf8..1b51dcb0`; one reviewer and one verifier) found all six fixed and one confirmed MINOR omission in the
commit list above, corrected by `3425b83e` (verified mechanically: every commit above M2 is named in this section,
except the commit that carries this sentence, which cannot name itself). Every confirmed finding and every NOTE of the three rounds and that check is fixed or disclosed. These are Claude reviews, not Codex reviews; the command-room source-matched review
of the exact final head and the owner's separate merge approval remain (§15.8, S12).

**Evidence (outside Git):** `evidence/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-INTEGRATION-20261025/` — the clean-import proof
with its addendum (the limits of the import scan), the archived decision text, and the checkpoint package, built at
the frozen head after this section: the exact source, per-commit and cumulative patches (each verified to reproduce
its commit tree), the per-file SHA-256 manifest, the final-head history scan, the key manifest and the action /
field / tone / locale matrix, the routine-preservation record, sanitized test logs and the review records of all
three rounds; the archive's SHA-256 is given in the hand-off report.

**Holds (unchanged):** at 2026-10-25T13:08Z #366 (`672202ab`) and #368 (`99f41e0d`) were still OPEN drafts and
`origin/main` was still M2, so W2–W6 stay held (§15.8); the S12 record is not prepared; the S13 publication review is
owed at W6; S14 C; no push, PR, merge, hosted, provider, terminal, test-card, printer or APK action is authorized.

## 16. Local integration composition — W2–W6 (2026-10-26)

Command-room instruction "COMMAND-ROOM RESUME — DEPENDENCY MERGED, CONTINUE W2–W6" of 2026-10-26: the #366 merge
dependency is satisfied, so the existing bounded local authorization of §15 (W2–W6) is resumed — an execution
instruction, not a new proposal. It authorizes the local composition merge and local commits only. Push, PR creation,
any GitHub merge, any payment merge into `main`, rebase, force-push or history rewrite, hosted SQL / migration / repair,
deployment or promotion, secret or configuration changes, Preview interaction with live merchant data, provider calls,
vendor-panel login, terminal or test-card use, real orders, printer and APK actions and starting 001C, 001E, 001F,
001G or 001H stay forbidden; S14 C stays in force (001D stays unmerged pending the separately approved rollout
prerequisites; no freeze of other workstreams, no early dark migration). The instruction, as received, is archived
outside Git in `evidence/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-W2W6-20261026/decision/` (SHA-256
`a2eb13ca1eb011249e8541f6d2a901e8d549b45984f71969bdcb92c7b2a31142`).

### 16.1 W0 — re-verification (before any edit)

- `origin/main` was `d20798203052bfcfcdd58cd009bdc6babf5df12c`, the merge of #366 (head
  `752bb4a412db6583c1eea8cdd623c6df19eb820a`); its first parent `30ac598f7f0f21879302377bdff013b2f80e2be7` is the merge
  of #368 (head `99f41e0d`). Both are ancestors of `origin/main`, merged in the actual order #368 → #366. The `main` CI
  run 40297245320 succeeded on `d2079820` — baseline evidence for `main`, not CI of this candidate.
- The integration worktree was clean at the accepted checkpoint `0d73c6b341f16702769e282ca004e88a0c183f35`; the original
  branch is unchanged at `75ef9d74` with a clean worktree; the accepted checkpoint archive (SHA-256
  `4fe94c7fba0c39143161e05b6d0ab707af91753770baa2faf1d666490d741023`) and every earlier evidence file are unchanged.
- Ownership: the only open PRs, #314 and #315, touch none of the integration files, and no open PR, document or active
  workstream claims them (only stale local branches without a PR exist). **D-061** and **Q-058** are free on every ref.
- Drift: no migration on `main` re-creates or alters a 001D routine, a routine whose definition the lanes pin, a 001D
  table or their ACLs; `main`'s two new migrations (`20261022014650`, the acceptance ETA; `20261022192530`, the content
  contract) sort before `20261023225657`, so the frozen version keeps its filename (S9); `supabase/config.toml` is
  identical. The acceptance-ETA function reaches `app.sync_push` only through `app.pos_accept_web_order` (§16.3), so the
  composition needs no change to the frozen SQL.

### 16.2 W2 — composition and localization union

- `a1b8c1c0` is a normal local merge commit of `origin/main` into this branch (parents `0d73c6b3` and `d2079820`), made
  without a conflict; no rebase, amend or reset. The original branch `75ef9d74` is not an ancestor, and #366, #368 and
  their branches are untouched.
- Localization: the union keeps #366's six preparation-duration keys, 001D's 73 `activityLog*` keys with their en
  `@`-metadata, and every other key and metadata entry — 2 943 messages per locale (`main` 2 870 + 73), 2 446 en
  metadata entries (`main` 2 373 + 73) and 273 `activityLog*` keys per locale (`main` 200 + 73). The four generated
  files were regenerated with the pinned Flutter 3.44.2 (the `generate` flag of `packages/l10n/pubspec.yaml` set only
  for the run and restored byte for byte): the result equals Git's conflict-free merge of the generated files, and a
  second generation is identical. No generated file was hand-edited.
- Preservation: among the 001D paths only the seven l10n files differ from `0d73c6b3`; the migration's blob SHA-256 is
  the frozen `468768f8…` at every commit; the seven lanes, the runner and this packet were unchanged by the merge.

### 16.3 W3 — the three released changes

- **D1** (`7c7207ed`, `supabase/tests/public_surface_acl_remediation_001_test.sql`, test 15 only): the expected set on
  the composed base had 16 entries — the four anon-only readers `storefront_menu(text)` … `storefront_menu_v4(text)` and
  the twelve service-only web-request / notification wrappers (`get_web_order_request_status_v2(text,uuid,text)`
  included). The six exact C2 renderings `card_attempt_adapter_read(uuid,uuid,text,text,text,jsonb,jsonb,uuid)`,
  `card_attempt_claim(uuid,uuid,text,text,text,bigint,text,uuid,integer,text,jsonb,jsonb,text,uuid)`,
  `card_attempt_finish(uuid,uuid,uuid,text,text,bigint,text,text,text,jsonb,text)`,
  `card_attempt_free_order(uuid,uuid,text,text,text,text,text,uuid)`,
  `card_attempt_mark_recording_result(uuid,uuid,text,text,text,uuid)` and
  `card_attempt_mark_release_requested(uuid,uuid,text,text,uuid)` are appended, giving 22 — derived, and equal to the
  composed catalog's set of public functions `authenticated` cannot execute. The description names the addition; every
  predecessor entry, the v4 and status_v2 assertions, every other assertion and the test plan are unchanged (the exact
  before / after lists will be in the W6 package).
- **CI** (`297d576d`, `.github/workflows/ci.yml`): one `db-tests` step, "Tests — card-attempt claim, recording, release
  and support-cutoff races (local only)", running `node supabase/tests/support/run_bizbot_zcredit_001d_concurrency.mjs
  --container supabase_db_RestoFlow`, directly after the acceptance-ETA runner and before the CI-only featured-items
  authorization step; every other step, trigger, permission, environment and the 25-minute timeout are unchanged.
  Editing the file triggers nothing; the step has not run.
- **ETA regression** (`47077902`, the regression lane, new section (k), S7(a)), for a platform request (3) and a legacy,
  unenrolled request (4) on the lane's synthetic web-order organization:
  - RG-174 / RG-176: `public.pos_accept_web_order_with_eta` with valid cashier PIN, device and token, called by a JWT
    whose caller holds an ACTIVE platform support session, raises 42501 `sync_push: permission denied (active support
    session)` at the RAISE in `app.sync_push`. The call path is read from the error context: `app.sync_push` ←
    `app.decide_pos_web_order` [← `app.pos_accept_web_order_legacy_353`, legacy only] ← `app.pos_accept_web_order` ←
    `app.pos_accept_web_order_with_eta` ← the public SQL wrapper. The refusal leaves the public wrapper uncaught, so
    the whole call rolls back, and none of the acceptance's rows is written before it (change 7 is the first statement
    of `app.sync_push`; the sidecar insert is the call's last statement; only the device-session renewal of the
    context proof can precede the refusal, and it rolls back with the call): the request row is unchanged (an md5 of
    the full row; pending, unmapped, undecided), and there is no decision, no use of the decision id, no ETA sidecar,
    print attempt, lease or sync-ledger row, and no new order, item, audit or dispatch row in the organization. The
    rollback of an already-written order — with its items, audit, sync ledger, dispatch, decision and lease — when the
    sidecar write then fails is #366's own fault-injection test (`storefront_acceptance_eta_001_test.sql`), which
    passes on the composed tree through the 001D `app.sync_push` (§16.6).
  - RG-175 / RG-177 (controls): the same request, decision id and duration (15 / 25 minutes) under the native transport
    JWT (no app user, no support session) accept through the same path, captured by a probe trigger at the order insert
    (rollback-only, like the lane): ok, accepted, not replayed, the same decision id; one decision, ledger row and print
    attempt, and the platform lease for the platform request only; one new order with its item; and exactly one ETA
    sidecar row in the request's scope, bound to the winning decision (`accepted_at` = `decided_at`, `ready_at` =
    `accepted_at` + the duration, UTC, the versioned fingerprint) — so the refused attempt consumed nothing.
  - Mutation evidence (each mutation applied inside a copy of the lane's own transaction, run outside the suite): with
    change 7 neutralized (`app.current_support_session()` answering NULL) RG-170, RG-171, RG-173 and RG-174..RG-177
    fail; with the ETA function swallowing the refusal (its when-others handler returning a typed answer) exactly
    RG-174 and RG-176 fail; with the ETA function calling `app.decide_pos_web_order` directly, bypassing
    `app.pos_accept_web_order`, exactly RG-174..RG-177 fail (the path, and no lease). A diagnostic copy records the raw
    error contexts and probe stacks.
  - The lane runs 177 assertions (was 173); no migration, function, ACL or other test changed. RG-172 still pins the two
    callers of `app.sync_push`: the ETA function reaches it only through `app.pos_accept_web_order`. The review
    follow-up `fea2105e` (§16.7) keeps a failing assertion's output free of returned ids and the section's helpers out
    of RG-172's caller scan.

### 16.4 W4 — documentation

The acceptance-ETA reach text of [API_CONTRACT](API_CONTRACT.md) §4.14 and §4.49 (S7(a)); a dated 2026-10-26 note on
**D-060**'s status line and one changelog line in [DECISIONS](DECISIONS.md) (no new decision; the next free ID stays
**D-061**); the 001D lane note of [TESTING_STRATEGY](TESTING_STRATEGY.md) §6; the 001D row of
[IMPLEMENTATION_CHECKLIST](IMPLEMENTATION_CHECKLIST.md); the 001D allowlist entry and the decision line of
[BIZBOT_PAYMENTS_ZCREDIT_PILOT_001](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001.md); and this packet (the header, §0, §1, §2, §7, §9,
§10, §12, §14, §15.3, §15.7 rows 10 / R1 / R3, §15.8 and this section). `docs/POS_ONLINE_INBOX_001.md`, #366's
[BIZBOT_STOREFRONT_ACCEPTANCE_ETA_001](BIZBOT_STOREFRONT_ACCEPTANCE_ETA_001.md) and every web-order source are not
edited. The Appendix A dispositions of §15.7 and their downstream gates are kept: R1's test, downstream-gate (the S7(a)
regression now marked executed; the web-order-owner gate kept) and still-unproven cells record W3, and item 10 (CI
wiring) and R3 (the review's kiosk note) carry dated pointers; no disposition changed. The review follow-up (§16.7)
added the §15.3 pointer, the header's §16 list, the future tense of the W6 package, two precision edits of API §4.14
/ §4.49 and a separate 2026-10-26 note in IMPLEMENTATION_CHECKLIST (its 2026-10-25 note restored); the follow-up
check (§16.7) added the dated pointers of §12 and §14 and the exact rollback wording of §16.3.

### 16.5 Holds and remaining gates

- **S12 companion:** prepared only after this branch's final head is frozen — a separate LOCAL docs-only branch
  `docs/BIZBOT-PAYMENTS-ZCREDIT-001D-REVIEW-EXCEPTION-001-review-route` stacked on that head (Work ID
  `BIZBOT-PAYMENTS-ZCREDIT-001D-REVIEW-EXCEPTION-001`) that records, under the next verified free decision ID (**D-061**
  expected, not reserved), the narrow 001D review route: a fresh-context Claude review, the command-room source-matched
  review of the exact final head and a separate owner merge approval. It does not claim that those future approvals
  happened, does not amend **D-016** or AGENT_WORKFLOW, and is neither pushed nor merged.
- **S13 / W6:** the W6 package (outside Git, built from the frozen final head) will carry the exact source, the
  cumulative and checkpoint-to-final patches,
  the per-file manifest, the frozen migration hash, the preservation proofs and the complete history scan of every newly
  publishable commit, for the command-room source-matched review. The absolute local path in the intermediate history
  `dde0857a^..50f052e9` (§15.2) remains an OPEN publication decision; no history is rewritten.
- **CI:** nothing has run in CI for this branch. Both `validate` and `db-tests` must pass on the exact published head —
  D1, the 353, acceptance-ETA and 001D runners and the two CI-only concurrency files included — under a separate
  publication authorization; `main`'s green run is baseline evidence only.
- **Unchanged:** S14 C (001D stays unmerged pending the separately approved rollout prerequisites), S15 and every hosted,
  deployment, provider, terminal, test-card, printer and APK gate; 001C, 001E, 001F, 001G and 001H are not started.

### 16.6 W5 — validation of the composed candidate (local)

W5 ran twice on this task's own disposable stack `BIZBOTZCREDIT001D` (§8; PostgreSQL 17.6, CLI 2.107.0), synthetic data
only, no linked or remote target, no other stack touched: at `47077902` and again, after the review follow-up, at
`fea2105e` (code under test; every later commit changes documentation only). Both runs had the same outcome; the
figures are from the second. Nothing ran in CI for this branch.

- **Fresh replay and first full-suite run:** a fresh reset applied 174 migrations (`main`'s 173 and the frozen 001D
  migration last); the first `supabase test db` run right after it: 326 files / 12 862 tests, 324 files ok. The two
  CI-only concurrency files (`zz_storefront_content_contract_001_concurrency_test.sql`,
  `zz_storefront_featured_items_001_concurrency_test.sql`) refuse any non-CI database before their first test and stay
  **NOT VALIDATED** locally (no CI flag set). `zz_storefront_home_content_001_concurrency_test.sql`, which passes once
  per reset, passed in this first run; D1, the acceptance-ETA test (its fault-injection rollback of the order, items,
  audit, sync ledger, dispatch, decision and lease written through the 001D `app.sync_push` included), the
  content-contract test and every predecessor, Storefront and web-order file pass.
- **The seven lanes, one by one afterwards:** SA 139, CI 397, RR 273, TI 140, LR 244, FR 343, RG 177 — 1 713
  assertions, all passing.
- **The concurrency runner, twice:** 41 / 41 scenarios each (1 356 and 1 357 assertions; CC-C13's count follows each
  round's race outcome), each clone database dropped.
- **PRE / POST:** the composed tree without the 001D migration equals the preserved M2-era PRE for all 14 captured
  routines (md5, ACL, owner, SECURITY, volatility, configuration) and the 8 dumped definitions — so no `main` migration
  changed a routine 001D re-creates; the POST replays equal the C2-validated POST for all 14 routines and 8 definitions,
  and the 55-function manifest equals C2's. `app.record_payment` is unchanged (PRE = POST), its only caller is
  `app.sync_push`, and no public wrapper exists; the payments and shift-closed writers and the close / reconcile
  callers are as in C2.
- **D1:** the composed catalog's public functions that `authenticated` cannot execute are exactly test 15's 22 entries.
- **ETA mutation evidence** (§16.3) re-run at `fea2105e`: unchanged outcome, and no output carries a 12-digit run.
- **Flutter / l10n / Dashboard / guardrails** (no Dart, ARB or generated file changed after `a1b8c1c0`; run at
  `47077902`): `dart format` check 1 785 files, 0 changed; `check_l10n` OK; `flutter test packages/l10n` 95 passed;
  `flutter test apps/dashboard` 2 653 passed, 16 skipped (pre-existing skip markers); `card_attempt_activity_log_test.dart`
  15 / 15; `melos run analyze` no issues; the float-money, secret and hardcoded-string guardrails OK; the worktree clean
  afterwards.
- **Generation repeatability:** two `flutter gen-l10n` runs (Flutter 3.44.2; `generate` set only for the run and
  restored byte for byte) each reproduced the four committed generated files exactly.
- **Environment assumption:** section (k) reads PostgreSQL's English, PostgreSQL 17 context wording; CI uses the same
  CLI and image; under other wording the path is NULL and RG-174..RG-177 fail closed, never pass vacuously.
- **NOT VALIDATED locally:** the two CI-only files above; the 353 and acceptance-ETA node runners (their guards admit
  only their own local namespaces or CI); the new `db-tests` step itself. Both `validate` and `db-tests` must pass on the
  exact published head (§16.5).

### 16.7 Review — fresh-context Claude review (read-only)

One round on the integration delta `0d73c6b3..3cb1e30b` and the preserved financial and security invariants: four
lenses (composition, W3 tests, invariants, documentation), each a fresh-context Claude Code read-only reviewer with the
local evidence, one adversarial verifier for each lens with a finding above NOTE, and a read-only build / deployment
fan-out lane. These are Claude reviews, not Codex reviews. Result: no BLOCKER and no MAJOR.

- **Composition:** nothing above NOTE — the merge is conflict-free in effect (`--remerge-diff` empty), the ARB union is
  exact (no key lost or changed), the generated files match it, and history and preservation are as stated. NOTEs: the
  353 / acceptance-ETA runners are CI-only (§16.6); a duplicated `posShiftDemoNote` key and an orphan
  `@kioskNowPreparing` metadata entry exist identically at M2 and on `main` and pass through unchanged (not 001D's;
  left to the localization owner); one reviewer scratch file was written outside its folder and deleted (no effect).
- **W3 tests:** nothing above NOTE; LF portability was tested empirically (every CR-bearing function re-created
  without CR inside a copy of the lane, and section (k) still passes); the probe trigger, quotas, JWT handling and
  fixtures are sound. NOTEs: (N1) the no-residue facts cannot fail while the call raises — the atomicity rests on the
  uncaught 42501 and on #366's fault-injection test, as §16.3 now states; (N2) two helpers named `app.sync_push(`
  literally, so RG-172 would count them if the section moved — fixed by `fea2105e` (built by concatenation; probed);
  (N3) no acceptance-ETA counterpart of RG-173 (a replay keeps its typed answer) — not required by S7(a); the
  reviewer's probe confirmed the behaviour; not added; (N4) a failing RG-175 / RG-177 printed a synthetic id with a
  12-digit run — fixed by `fea2105e` (answers reduced to id-free facts); (N5) the context parsing assumes English
  PostgreSQL 17 wording — recorded in §16.6; (N6) the exact before / after D1 lists — will be in the W6 package.
- **Invariants:** nothing above NOTE — no object overlap between the 001D migration and `main`'s two new migrations, no
  silent revert, `app.record_payment`, `app.close_shift` and `app.reconcile_shift` equal to their pins, exactly two
  callers of `app.sync_push`, no payment bypass, **RISK R-003** / **R-002** / **R-007** / **R-008** hold, no secret.
  NOTEs: (INV-01) the pre-existing non-PIN kiosk device-token order entry `public.kiosk_submit_order` has no
  support-session check — outside **D-060** point 1, neither introduced nor widened here; recorded as a dated pointer
  on R3 (§15.7), its disposition unchanged, left to its own Work ID; (INV-02) a static reading of the 353 and
  acceptance-ETA runners finds no failure path against 001D's `app.sync_push` (one server-built `order.submit`, batch
  length 1, no support session); exact-head CI stays the evidence.
- **Documentation:** DOCS-02 (MINOR, confirmed) — §15.3's composition list and Appendix A item 10's "not CI-wired" had
  no 2026-10-26 pointer: added. DOCS-01 (verified down to a NOTE) — §16.4 now names every Appendix A cell that changed.
  NOTEs fixed: the header's §16 list (DOCS-03); the W6 package written in the future tense (DOCS-04); API §4.49 names
  the acceptance's own typed refusals and §4.14 cites RG-172 for the two callers (DOCS-05); the 2026-10-25
  IMPLEMENTATION_CHECKLIST note restored with a separate 2026-10-26 note (DOCS-06); the instruction's SHA-256 in §16
  (DOCS-07).
- **Fan-out (read-only; nothing triggered):** a branch push runs no GitHub workflow (CI runs on pull requests and on
  pushes to `main`); a pull request or merge runs `validate` and `db-tests` (with the new step). Vercel: `resto-flow`
  builds a Preview on the first push and production on merge (9 product paths: 2 under `apps/dashboard/lib`, 7 under
  `packages/l10n/lib`); `bizbot-site` ignores; `bizbot-storefront` is recorded as not Git-linked (it would ignore);
  `bizbot-pos-alert-cron` has no ignore step and redeploys production on every merge (and likely builds a Preview on a
  push). No automation applies the 001D migration. Only `resto-flow` was confirmed live through the connector. MINOR,
  pre-existing and outside the approved documentation targets: DEPLOYMENT's "two Git-linked Vercel projects" omits
  `bizbot-pos-alert-cron` — to be recorded in the W6 package for the PR body; DEPLOYMENT is not edited.
- **Follow-up check** (a fresh-context reviewer and one adversarial verifier on `fea2105e` and `04efcc6c`): every
  disposition above was applied as claimed, the Appendix A dispositions and gates are unchanged, §16.6 equals the
  evidence, and no stale or contradictory 001D text remains. R2-01 (MINOR, confirmed): §16.3 said #366's fault test
  rolls back an order and a sidecar that were already written — it rolls back the written order rows when the
  sidecar write fails; corrected. NOTEs: R2-02 — 'nothing is written before it' was absolute; the device-session
  renewal can precede the refusal and rolls back with it; reworded. R2-03 — `fea2105e` also requires
  `canonical_order_id_present` (strictly stronger; its commit message's 'the same facts' understates that;
  recorded, the history is not rewritten). R2-04 — the W6 package was referred to in the present tense; now future.
  R2-05 — the 'Unresolved gates' of §12 and §14 had no 2026-10-26 pointer; added. R2-06 (the W6 staging, outside
  Git) — the D1 delta is regenerated at the final head, and the runner logs' advisory-lock keys are masked in the
  package (19-digit values, not card data).

Every confirmed finding and every NOTE is fixed or disclosed.

### 16.8 Disposition (local, 2026-10-26)

- Commits above the accepted checkpoint: `a1b8c1c0` (W2 merge), `7c7207ed` (D1), `297d576d` (CI step), `47077902`
  (acceptance-ETA regression), `3cb1e30b` (documentation, part 1), `fea2105e` (review follow-up of section (k)),
  `04efcc6c` (§16.6–§16.8) and the commit that carries the follow-up check's corrections — the final head, which
  cannot name itself; the W6 package will name it.
- The frozen migration is unchanged at every commit; the original branch stays at `75ef9d74`; every earlier evidence
  file is unchanged.
- Validation §16.6; review §16.7; holds and gates §16.5 — the S12 companion is prepared on its own branch only after
  this head is frozen, and the W6 package will be built from this head. No push, PR, merge, hosted, deployment, provider,
  terminal, test-card, printer or APK action; S14 C.
