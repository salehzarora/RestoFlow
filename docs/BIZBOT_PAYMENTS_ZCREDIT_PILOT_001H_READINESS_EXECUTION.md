# BIZBOT-PAYMENTS-ZCREDIT-PILOT-001H-READINESS-001 — execution packet: local pilot readiness, integration map and physical-TEST runbook (docs only, no provider action)

Work ID: `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001H-READINESS-001`, the readiness step of the 001H pilot-operations row of
[BIZBOT-PAYMENTS-ZCREDIT-PILOT-001](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001.md) (§8 "Deploy (001H)", "Physical test (001H)"
and "Rollback"). This packet records no **DECISION**, adds no **OPEN QUESTION** and allocates no ID. It contains no
credential, terminal number, PIN-pad identifier, serial, card number, provider payload or hosted secret value, and
never will.

This packet was written and committed before any other tracked change of this Work ID (authorization §1). Its plan
(§4–§6) is fixed here; the results are added later from the evidence kept outside Git.

## 1. Request and boundary

- Command-room authorization of 2026-11-01, "LOCAL PILOT READINESS, INTEGRATION MAP AND PHYSICAL-TEST RUNBOOK — NO
  PROVIDER ACTION". It accepts 001G and its server-filter pgTAP coverage at head
  `f519b3cd429b1af001caf230835d2faeead71a3a` (tree `8224e6db1159db8212a2b95ec7e1df57a0d0e5b1`; reviewed package
  `8fb47c9870e4afdb84590b3471628654f483670e081f6e49d821d4add758aa96`), and records that the full local database suite
  is not green (two CI-only Storefront concurrency files refuse a non-CI database; the three CI concurrency runners
  did not run). The request is kept outside Git with a SHA-256 sidecar
  (`9a785c12acb41b4c37de59a5088ba63c6649e154f3f8946617c58b115c519d8b`).
- Readiness only. Produced: this packet; sanitized evidence matrices and runbook templates outside Git; read-only
  current-state evidence where §11 of the request allows it.
- Not implemented: provider-profile wiring, secrets or credential configuration, terminal mapping, migrations or Edge
  deployment, the D9 UI copy, `DASHBOARD-COLLECTED-LABEL-001`, or any POS, Dashboard, Edge, SQL or l10n change. No
  shared canon document is modified; §6 lists the future owner and patch of each.
- Not authorized: a physical test, a provider call, profile wiring, a credential read, a secret change, a deployment,
  a migration application, a hosted write, a push, a PR, a merge, terminal or card use, a printer or APK action. No
  Codex review.
- Branch `chore/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001H-pilot-readiness` in its own worktree, created from the exact
  accepted head; no upstream. Every earlier branch, commit, package and evidence folder is preserved; no amend,
  rebase, reset, deletion or history rewrite; current `main` is recorded only, never merged.

## 2. Source anchor (preflight 2026-11-01T08:11:36Z, read-only)

- The base worktree (the server-filter ticket) is at `f519b3cd` / `8224e6db`, clean, no upstream; its package and
  evidence folder verify (157 OK). `index.ts` line 19 reads `providerProfile: null,` (blob `7a3c5c97`).
- Every accepted payment head is unchanged: #370 `54b19ab5`, #371 `53d6a6ad`, 001D `75ef9d74`, 001D integration
  `ce3c67c8`, 001E `d5456624`, G1 `295cacb6`, W1 `140be040`, D-064 `ca8edb03`, profile candidate `cf1ffacf`, 001C
  `71bfef5b`, 001C correction `148df092`, 001F `d7ce9990`, 001F correction `bd281721`, 001G `b1586d6f`, server filter
  `f519b3cd`; 001A `c8a883c8`, 001B `e7df3132`, D-061 `bfbab91b` / r1 `e246492d`. Each head from #370 to the server
  filter is an ancestor of the next. #314 `54346b37` and #315 `4e8c81f6` are unchanged. Fourteen accepted review
  packages verify against their sidecars.
- `origin/main` (`git ls-remote`) is `8ee132d5ef214fd92afc14f0ba2735059a643e77`; merge base with the stack
  `d2079820`; 16 commits / 78 files since, 14 under `supabase/` and 7 under `packages/l10n`. The stack and `main`
  share exactly the seven l10n files (three ARBs and four generated localizations).
- Open PRs: #370, #371, #378 (Storefront SEO discovery, draft; adds one migration), #314, #315. The worktree
  `BIZBOT-POS-PRINT-HISTORY-L10N-001` holds 7 uncommitted l10n changes. No ref, PR or worktree holds this packet's
  path.

## 3. File allowlist

| Path | Purpose |
|---|---|
| `docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001H_READINESS_EXECUTION.md` | this packet (the only tracked change) |

Every other path is protected, in particular every shared canon document under `docs/`, `supabase/**`, `apps/**`,
`packages/**`, `storefront/**`, `.github/**`, `tools/**` and every manifest and lockfile.

## 4. Method (plan)

1. Integration graph from Git only: for every unit of request §3 the exact head, tree, base, ancestry, changed paths,
   overlap with current `main`, migrations, l10n files, CI-relevant paths and deployment fan-out, computed by a tool
   kept outside Git and re-runnable.
2. Read-only reading of the accepted packets, migrations, Edge and POS sources and canon documents for the Q-047 /
   Q-049 matrices, the dark-deployment steps, the PRE / POST design, the runbook and the kill order. No vendor raw
   material is opened; only existing manifests and sanitized sources are used.
3. Read-only current-state checks allowed by request §11 (Git / GitHub identities, Vercel project and deployment
   settings, Supabase migration and function lists and secret NAMES, read-only SELECTs only), each labelled with its
   observation time. No secret value is read and no mutating call is made.
4. One focused fresh-context Claude review of the integration graph, the two matrices, the PRE / POST plan, the
   runbook and the abort sequence; only evidence or wording defects are fixed.
5. A sanitized local review package with the exact identities and hashes.

## 5. Deliverables (outside Git, under this Work ID's evidence folder)

| Deliverable | Request section |
|---|---|
| Integration / merge DAG and the proposed protected merge sequence | §3 |
| l10n and migration conflict map | §3 |
| Q-047 non-settlement evidence matrix | §4 |
| Q-049 identity-key evidence matrix and its acceptance checklist | §5 |
| Dark-deployment checklist (ten steps) | §6 |
| PRE / POST matrix and read-only query templates | §7 |
| Physical TEST runbook (design only) | §8 |
| Abort and kill procedure | §9 |
| Open-gate register | §10 |
| Read-only current-state evidence | §11 |
| Review findings and dispositions | §12 |

## 6. Shared canon documents (no change here)

This ticket changes no shared canon document. The full table (document, section, patch, owner, trigger) is kept
outside Git in `10_CANON_DOCS_OWNER_PATCH.md`. Its owners:

- **`BIZBOT-PAYMENTS-ZCREDIT-PILOT-001H-PILOT-OPS`** — DEPLOYMENT §18.1–§18.5:
  - the G1 migration in the approved list;
  - the configuration's inner member names and the three `key_format` tokens;
  - the D8 rule and the D9 precondition;
  - the PRE set (`app.payment_terminals`, the session-renewal stamps, the public channel counters);
  - the `key_format` retention check;
  - "QD3";
  - RUNBOOKS §8, its TEST gate and the redeploy conditional (RUNBOOKS line 522, OPERATIONS line 101);
  - the TESTING_STRATEGY hosted-run note.
- **PROPOSED `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-PROFILE-WIRING-001`** — the missing provider-profile wiring step and
  the DEPLOYMENT §18.5 profile-retention checks.
- **PROPOSED `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-MIGRATION-REORDER-001`** — the final migration versions.
- **PROPOSED `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-CONTRACT-RECONCILE-001`** — API_CONTRACT §4.55 (an API-contract
  change needs its own ticket).
- **PROPOSED `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001H-EVIDENCE-ACCEPTANCE-001`** — the Q-047 / Q-049 acceptance record.
- **`BIZBOT-PAYMENTS-ZCREDIT-001D-REVIEW-EXCEPTION-001`** — the D-061 re-pin and the held-ID sentence.
- **PROPOSED `BIZBOT-PAYMENTS-ZCREDIT-STACK-REVIEW-EXCEPTION-001`** — a review route per remaining unit.
- **`DASHBOARD-COLLECTED-LABEL-001`** and **`BIZBOT-PAYMENTS-ZCREDIT-HYGIENE-001`** — their own DEPLOYMENT sections.
- **PROPOSED `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001-CANON-RECONCILE-001`** — one post-merge docs ticket for every status
  reconciliation (DECISIONS D-051..D-064, API_CONTRACT, DOMAIN_MODEL, STATE_MACHINES, MONEY_AND_TAX_SPEC,
  TESTING_STRATEGY, IMPLEMENTATION_CHECKLIST, the pilot packet, TASK_TRACKER).

Any canon edit on an accepted head creates a new head and voids D-061 for #370. Status reconciliation therefore waits
for the merges.

## 7. Gates held (unchanged)

D9 (before the physical TEST); `DASHBOARD-COLLECTED-LABEL-001` (before the first LIVE charge, not blocking a
zero-financial-effect TEST); TEST tenant-audit isolation (exact-head CI and physical PRE / POST); **Q-047** /
**Q-049** (sealed owner evidence before any real provider action); **Q-048** / **Q-050** / E2-B (physical and
provider acceptance); provider-profile wiring (`providerProfile: null`); every merge, deployment and hosted gate. The
exact register (35 gates, GR-01..GR-35, each with what it blocks, its owner and the evidence that closes it) is
`09_OPEN_GATE_REGISTER.md`, outside Git.

## 8. Results (2026-11-01; the evidence stays outside Git)

### 8.1 Identities

- Base: `f519b3cd` / `8224e6db`.
- Plan commit: `1811c004` (tree `2994b1b2`).
- The results commit is the next commit of this packet. The postflight records it.
- Every accepted head and the heads of #370, #371, #314 and #315 are unchanged; the preflight and the postflight
  compare them.

### 8.2 Integration graph (request §3)

- **Shape.** The stack is linear: 13 units on the merge base `d2079820`, then this packet. #371 is a side branch on
  #370. Each unit head is an ancestor of the next.
- **What `main` changed.** `main` (`8ee132d5`) moved 16 commits and 78 files. The only shared files are the seven l10n
  files:
  - keys are disjoint (#370 adds 73, 001F 101, its correction 1, `main` 17);
  - no hunk overlaps;
  - the second lander regenerates the union with `flutter gen-l10n`.
- **Publication units:**
  - P1: #370;
  - P1c: #371;
  - P2: the 001E family with G1;
  - P3: 001C;
  - P4: 001F, after #314 / #315;
  - P5: 001G with its server filter;
  - P6: 001H.
- **The proposed protected sequence has eight steps.** Each PR head gets:
  - a normal update from `main`;
  - an exact delta review and fresh CI;
  - then the #371 re-pin and the l10n union regeneration.

  Nothing is implemented and nothing hosted is mutated between merges.
- **Migration order.** The hosted ledger holds 182 migrations, head `20261031013649` (observed between 08:27:12Z and
  08:28:19Z). That head is newer than 001D `20261023225657` and G1 `20261027211023`, which triggers the 001D packet's
  rename condition (S9). The options:
  - M-A: re-version, with content bytes unchanged (recommended);
  - M-B: `--include-all`, re-confirmed by the owner;
  - never `migration repair`; G1 always after 001D.

  Decided on 2026-11-01: M-A, with the bounded-locks gate GR-37 (§11).
- **D-061 conflict.** Under strict protection #371 falls behind once #370 merges. Updating it leaves D-061 item 1. The
  owner chooses a route before step 1. Decided on 2026-11-01: the record is folded into #370 (§11, decision C).
- **Review route.** The canon's Codex gate conflicts with the stack packets' "No Codex review". Each remaining unit
  needs a recorded route. Decided on 2026-11-01: one narrow record for P2–P6 (§11, decision D).
- **Vercel.** Pushing any unit head as it stands builds resto-flow and bizbot-storefront, because `main`'s Storefront
  changes count reversed. Building publication branches on current `main` avoids the Storefront build.
  `bizbot-pos-alert-cron` builds on every push and redeploys on every merge.
- **History.** No disallowed content above #370. The synthetic history-only items are four zero-width lines in the 001E
  history and two `.test` addresses in the server-filter history. Clean-history branches are recommended (Option B).
  Decided on 2026-11-01: clean branches for P2–P6 (§11, decision E).

### 8.3 Q-047 / Q-049 (request §4–§5)

- **Q-047.** Nine cells. Cells 1–8 are `SEALED_OWNER_INPUT_REQUIRED`. Cell 9 proposes the installer procedure. As
  corrected on 2026-11-01 (§11, GR-36), it records only:
  - the archive SHA-256;
  - the SHA-256 of the encrypted configuration member, which is the source of truth;
  - the member manifests.

  It never records a digest of the configuration or of any credential-bearing plaintext. Q-047 stays OPEN.
- **Q-049.** Both keys, by encoding, length, character set, duplicate scope and window, exact repeat, lookup echo,
  formatter version and retention. No formatter is invented. The accepted `key_format` token must fit both keys;
  otherwise a separately approved formatter ticket comes first. Q-049 stays OPEN.

### 8.4 Dark deployment and PRE / POST (request §6–§7)

- **Dark deployment.** Ten steps, each with actor, input, evidence, stop condition, rollback and class. Two canon gaps:
  - no provider-profile wiring step;
  - G1 missing from DEPLOYMENT §18.2.
- **PRE / POST surfaces (17):** the private ledger, events, tombstones, terminals and revisions; payments, orders and
  receipts; shifts and drawers; the operation ledgers; sync; tenant audit; device and PIN sessions; the Dashboard
  aggregates; web intake; telemetry.
- **The only session writes the real path can make** are on the designated device, and only when the renewal is due
  (at most about hourly):
  - `device_sessions.expires_at` / `updated_at`;
  - `devices.last_seen_at` / `updated_at`.

  The context proof renews before its PIN and membership checks, so a request refused after that point may still
  write. A request refused earlier writes nothing. No `pin_sessions` update exists. Public storefront calls may move the
  channel rate counters; that class, and the designated till's telemetry, need owner approval (decided on 2026-11-01:
  §11, decision H).
- **Other paired devices** must be powered off or have their app closed. Signed out is not enough: a paired app at the
  PIN screen renews its session about hourly. The canon's "signed out or idle" (DEPLOYMENT §18.4, D-058 point 8) is
  routed to the canon patch (decided on 2026-11-01: §11, decision F).
- **A TEST anomaly is visible only in the operator's per-row read** (anomaly code, `charge_may_exist`, return code). The
  POS shows a TEST attempt only as its state.
- **The read-only template was validated on a disposable local database**, and re-run after the review fixes (all
  three runs as planned):
  - an empty read-only run;
  - a seeded run in one rolled-back transaction: deterministic digests, exactly the expected surfaces moved, and a
    forbidden void exposed;
  - a refusal for a reader without BYPASSRLS.

  The template pins TimeZone, DateStyle and `bytea_output`, so PRE and POST compare equal across clients.

### 8.5 Runbook and kill order (request §8–§9)

- **Preconditions.** P1–P8.
- **Order-context conflict.** The 001F POS starts a TEST attempt only from an existing server order's payment sheet. The
  pilot packet describes an amount-only lab start. The options:
  - Option A: a dedicated non-customer test order. Recommended: it is consistent with D8, D9 and the accepted build. It
    needs a non-kitchen item priced at the planned amount, which must already exist or come from its own approved
    step.
  - Option B: an order-less Lab start, under a new Work ID.

  Decided on 2026-11-01: Option A (§11, decision A).
- **Safest minimal first session.** Case 1 only: one TEST attempt at the smallest amount, with the cap equal to it.
- **Abort and kill.** Eleven triggers. One sequence serves both the normal close and an abort; its switch order matches
  DEPLOYMENT §18.4 and D-058 point 8:
  1. Lab OFF;
  2. Edge flag OFF (unset);
  3. operator revision OFF, once;
  4. terminal draining, only if the binding is enabled;
  5. an operator-side "no new starts" check;
  6. continued status, only while the run's sessions are intact;
  7. holds;
  8. `test_closed`, with the server row id resolved inline;
  9. POST;
  10. restore intake (order corrected on 2026-11-01, §11);
  11. seal.

  OFF never cancels a sent attempt. The Edge commit continuation does not re-check the flag. The dedicated test order
  is voided only after sealing, under a separate approval (§11, decision A).

### 8.6 Current state and review (request §11–§12)

- **Current state (observation times in the evidence):**
  - no `pos-card-charge` function and no `POS_CARD_*` secret name;
  - `providerProfile` null at every head;
  - the CLI initialised a temporary login role for the one linked SELECT. That is disclosed; no further hosted SQL ran.
- **Review.** See §9.

## 9. Review (request §12)

- **The review.** One focused fresh-context Claude review, a single read-only subagent, covered the integration graph,
  the Q-047 / Q-049 matrices, the PRE / POST plan and template, the runbook and the abort sequence. Result: 3 MAJOR,
  12 MINOR, 4 NOTE, no BLOCKER.
- **Verification.** Before any change, four read-only verifier agents re-checked each finding against the code. They
  sought no new findings. Result: 15 confirmed, 4 partially confirmed, none refuted.
- **Fixes.** All 19 were fixed as evidence or wording defects; no production file changed. The main ones:
  - a TEST anomaly is visible only in the operator's ledger read, so the template now prints the anomaly code,
    `charge_may_exist` and the return code;
  - signed-out devices still renew their sessions, so other paired devices are powered off or their app closed (or an
    owner-approved class), with a canon patch for DEPLOYMENT §18.4 / D-058 point 8;
  - the package had two kill orders; it now has one sequence matching §18.4 and D-058 point 8, and records that the
    pilot setter is not idempotent;
  - the digest session settings are pinned, and the template was re-validated.
- **Records.** The review record and the per-finding dispositions are kept outside Git.

## 10. Ending

`PARTIAL_001H_READINESS_WITH_EXACT_EVIDENCE_OR_OWNERSHIP_GAPS`. The package is complete for its scope, and every
physical and provider action stays held. It is partial for three reasons, all in the gate register (GR-01..GR-35).

**Evidence gaps:**
- the hosted facts not observed after the login-role disclosure: the pilot objects' absence, the server versions and
  the ledger rows;
- the hosted reader role;
- the template on the merged-`main` schema;
- a Deno run of the Edge suite.

**Ownership gaps (decisions or Work IDs not yet approved):**
- the migration order;
- the D-061 strict-protection route;
- the review route for the remaining units;
- the S14 C lift;
- #314 / #315;
- the order context and its test item;
- the provider-profile wiring, the D9 copy and the pilot APK release;
- the hosted read-access path;
- the non-private allowlist classes and the other-devices rule;
- the intake restore pair.

**Sealed inputs:** Q-047 and Q-049 stay OPEN (`SEALED_OWNER_INPUT_REQUIRED`).

## 11. Corrections (Work ID `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001H-READINESS-CORRECTIONS-001`, 2026-11-01)

- **Verdict.** The command room accepted the 001H readiness analysis: head `7ab23e54`, tree `0d646eb3`, package
  `4725a4fa…`. It requested two bounded corrections; physical and provider actions remain held.
- **Scope.** One correction commit changes this packet only:
  - it adds this section;
  - it adds "Decided" notes to §8.2, §8.4 and §8.5;
  - it corrects §8.3 for GR-36;
  - it corrects the §8.5 kill-order end.

  The original package and every earlier evidence folder are preserved unchanged. The corrected documents are kept
  outside Git, in the correction evidence folder.
- **Superseded text.** Where §6, §7, §8.2, §9 or §10 conflict with this section, this section governs:
  - the gate register now has 37 gates (GR-01..GR-37);
  - D-061 is folded into #370, not re-pinned (§6, §8.2);
  - one review record covers P2–P6, not a route per unit (§6, §8.2);
  - other paired devices get no allowlist class (§9);
  - decisions A–I are no longer open ownership gaps (§10);
  - the pilot objects' absence and the server versions are now observed by the command room (§10's evidence gaps);
  - the kill order ends POST → restore intake → seal (§8.5).
- **Decisions recorded, not executed.** These are command-room decisions. None is a `DECISIONS.md` entry, and no
  register ID is allocated.
  - **A — order context: Option A.**
    - The provider TEST attempt has `order_id=NULL`.
    - A dedicated non-customer POS order is only UI context. It is created and synced before PRE, with total =
      planned amount = TEST cap, and it does not change between PRE and POST.
    - It is voided only after evidence sealing, under a separate approval.
  - **B — migration order: M-A.** Re-version 001D and G1 after the then-current hosted / `main` head; G1 after 001D.
    Never `migration repair`; no `--include-all` for this sequence.
  - **C — D-061 / #371.**
    - Fold the final D-061 record into the final #370 head, and get the owner's exact-head approval on the combined
      head. The combined head cannot contain its own hash, so that approval is recorded outside the commit.
    - Besides the pin, the fold forces an enumerated set of hunks of the accepted record: the Status line, item 1,
      item 4, the Alternatives line and the changelog entry. The inclusion proof requires every other accepted sentence
      unchanged, and the command room reviews each enumerated hunk.
    - Merge #370 once.
    - Close #371 as superseded, only after proving its accepted text is included.
    - No admin bypass.
  - **D — review route.** No return to Codex. One narrow `BIZBOT-PAYMENTS-ZCREDIT-STACK-REVIEW-EXCEPTION-001` record
    covers P2–P6: a fresh-context Claude review, a command-room source / package review, and the owner's exact-head
    approval. D-016 and AGENT_WORKFLOW are not amended globally.
  - **E — publication history.** Clean patch / tree-equal branches for P2–P6.
  - **F — quiet window.** Every other paired device is powered off or its app fully closed. Signed out, idle, the PIN
    screen or a screen turned off is insufficient.
  - **G — hosted reads.**
    - Generic read-only checks use the Supabase connector.
    - The exact READ ONLY PRE / POST template runs in the owner's SQL editor or through a separately approved connector
      execution.
    - No more `supabase db query --linked` SELECTs for readiness evidence.
    - `cli_login_postgres` is never deleted or altered.
  - **H — allowlist.** Only the exact row-16b public counters. Designated-device telemetry only after the
    merged-schema template explicitly includes all #373 / #374 tables. Every other device and column stays forbidden.
  - **I — intake restore.** When `ordering_enabled` and `submission_enabled` differ, STOP before pausing. The pair is
    never normalized or overwritten for the test.
- **GR-36 — no plaintext secret digest.**
  - The 001H proposal to record the SHA-256 of the canonical plaintext `POS_CARD_PROVIDER_CONFIG` is removed. A plain
    digest of a secret-bearing object is an offline verifier.
  - **Preferred route.** The encrypted configuration member of the accepted sealed archive is the source of truth. Only
    the archive SHA-256, the encrypted-member SHA-256 and the member manifests are recorded. The installer decrypts the
    exact accepted member in memory, validates its schema, and installs those exact bytes.
  - **Optional keyed route.** An HMAC-SHA-256 over canonical JSON, with an owner-held random 256-bit key that never
    enters Git, evidence, chat, logs or the archive. The encrypted member's decryption key follows the same rule.
  - Never an unkeyed digest of credential plaintext, nor a platform-reported secret digest.
- **GR-37 — bounded database locks.** A new hard gate before any hosted migration apply: the exact apply transaction
  must use a tested, bounded `lock_timeout` and `statement_timeout`.
  - The mechanism is selected and implemented under PROPOSED `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-MIGRATION-REORDER-001`.
  - That Work ID must prove, on a disposable merged-`main` schema:
    1. the exact migration sequence;
    2. a lock conflict fails within the bound;
    3. no partial migration or history row remains;
    4. a retry from the clean ledger succeeds;
    5. any timeout is STOP / preserve / forward-fix, with no `migration repair`.

    It also names the state after a failure at either file (including G1 failing after 001D committed), and shows a
    successful retry from that state.
  - The bound is carried outside both frozen migrations, which are not modified here. Nothing assumes that the Supabase
    CLI propagates a setting. The passwordless CLI path is excluded unless separately approved, because it initialises
    `cli_login_postgres` (decision G).
- **Wording.** The runbook now reads: "The provider TEST attempt has `order_id=NULL`. Option A uses a dedicated
  non-customer POS order only as UI context."
- **Current state.** Recorded as the command room's independent observation at 2026-11-01 10:51 UTC:
  - ACTIVE_HEALTHY; PostgreSQL 17.6, Unicode 15.1, ICU 15.1, UTF8;
  - 182 migrations, head `20261031013649`;
  - the five pilot tables absent; zero `card_attempt*` functions; `pos-card-charge` not deployed;
  - `cli_login_postgres` present, expired at 08:32:40 UTC, non-superuser, non-BYPASSRLS, non-inheriting, and left
    untouched.

  Secret names were not re-observed beyond this packet's 08:27 UTC evidence. This correction ran no hosted read.
- **Found while recording decision G.**
  - The `06b` template uses psql variables, which neither the SQL editor nor a connector substitutes.
  - It runs 41 SELECT statements, while a venue may show only the last result set.
  - A venue-compatible form is added to GR-27, with the merged-schema extension and its re-validation. The same applies
    to the operator hold / closure calls of the kill order. The validated template is unchanged.
  - The venue's executing role has not been observed; it must be confirmed to bypass RLS before a session is scheduled
    (GR-26).
- **Review.** One focused fresh-context Claude delta review of the four correction areas: 2 MAJOR, 7 MINOR, 4 NOTE, no
  BLOCKER.
  - The MAJOR findings: the D-061 inclusion proof must enumerate the hunks the fold forces, not only the pin; and the
    pre-scheduling check of the venue's reader role had been dropped.
  - Each finding was checked against the cited text before any change. All 13 were fixed as evidence or wording
    defects, and no second review round was run.
  - The record and the dispositions are kept in the correction evidence.
- **Ending.** `LOCAL_001H_READINESS_CORRECTED_PHYSICAL_AND_PROVIDER_ACTIONS_HELD`.
