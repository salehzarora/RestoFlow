# BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-HOSTED-PRE-COMPAT-001 — execution packet: the legacy CRLF PRE forms, the per-run Default ACL baseline and D-067

Work ID: `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-HOSTED-PRE-COMPAT-001`, on the fresh branch
`fix/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-HOSTED-PRE-COMPAT-001` from `main`
`e29bdb5176753ab1c88b098d84ec10712f0a08ed` (tree `71f9cb5deb0a329e2ed6f9fa93da5801aa5466e2`; parents `64b78c3e` — the #385
merge, which carries **DECISION D-066** and the exact-gap mode — and `907ff6a5`, #384's candidate). It adapts the one-time
exact-gap mode of the GR-37 wrapper to two facts that the hosted read-only check of 2026-11-06 found, and records them as
**DECISION D-067**.

The packet contains no credential, password, terminal number, TPN, PIN-pad identifier, KEY, device serial, card datum,
provider payload, e-mail address, database URL, access token or real production UUID.

## 1. Request and boundary

- **The request.** The command-room authorization of 2026-11-06 "LEGACY CRLF PRE COMPATIBILITY, HOSTED DEFAULT-ACL
  BASELINE AND D-067, LOCAL ONLY". It accepts the stop of the hosted exact-gap check
  (`HOSTED_001D_EXACT_GAP_CHECK_STOPPED_PRE_RECREATED_DRIFT_AND_DEFAULT_PRIVILEGES_MISMATCH` / `NO_APPLY_NO_RETRY`). It is
  kept outside Git with its SHA-256 (`ad603cc6e5a16f774876654e020bc928d26b4dadf5de232bfc64a421fe11a858`). No Codex
  review is requested.
- **What the hosted check found** (BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-CHECK-001, read-only, two sessions,
  nothing written; its evidence seal `SHA256SUMS.txt` has SHA-256
  `a5e98f820c37a6449b4545f928d4cae719a9c3c14c635cd5c386c5122e6f5781`):
  - six of the seven functions 001D re-creates hold, on hosted, the latest committed pre-001D body with every LF written
    as CRLF: `app.sync_push`, `app.pin_session_capabilities`, `app.pos_order_snapshots`, `app.audit_action_has_detail`,
    `app.audit_safe_detail` and `app.owner_audit_events`. Their LF-normalized bodies equal the reviewed LF source.
    They came from `20261008170200` and `20261008190000`, which the pinned CLI recorded from a CRLF checkout;
  - `app.audit_category` holds its canonical LF body;
  - hosted's default privileges differ from the local reference that the check compared them with (the wrapper itself
    pins none).
- **The verdict this task implements.** The six differences are exact legacy CRLF forms of the reviewed LF source. The
  Default ACL difference is not project-schema drift: hosted's Default ACL becomes a per-run PRE baseline that must stay
  unchanged through the second PRE and POST.
- **Scope: exactly seven tracked paths may differ from `e29bdb51`.**
  - `tools/supabase/bounded-db-push.mjs`;
  - `tools/supabase/bounded-db-push.test.mjs`;
  - `docs/DECISIONS.md`;
  - `docs/DEPLOYMENT.md`;
  - `docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001D_EXACT_GAP_APPLY_001_EXECUTION.md`;
  - `docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001D_EXACT_GAP_APPLY_001_REPIN_001_EXECUTION.md`;
  - this packet.
- **Not changed:** every migration, `.github/workflows/ci.yml`, D1, `supabase/config.toml`, payment SQL, Edge, POS,
  Dashboard and l10n, the cinematic tests and runners, the substance of **D-061**, **D-065** and **D-066**,
  [AGENT_WORKFLOW](AGENT_WORKFLOW.md) and **D-016**.
- **No hosted, remote, provider or device action.** No hosted query or apply, no exact-gap hosted check, no `db push`,
  no `--include-all` against hosted, no migration repair or ledger write, no Edge deploy, no secret installation, no
  `providerProfile` wiring, no provider request, no terminal or card use, no APK or printer action, no push and no PR.

## 2. Preflight (read-only, 2026-11-06T16:53Z, RESULT PASS)

- `main` is `e29bdb51` by the fetched remote-tracking ref, `git ls-remote` and the GitHub API; its tree is `71f9cb5d`.
- 188 migrations, the newest `20261105141815`, none later; `20261104141959_bizbot_zcredit_001d_server_ledger.sql` is
  present once with SHA-256 `468768f89029a0fb131869f754d5374127930b8bf05b48cd8de19d645546352e`.
- The wrapper's SHA-256 is `9d753bab6a3c868b6b1fcc0c8dd82f9e43bd8962b6145af59d45e5a1a0cb7581` (blob `52f82672`); its tests
  are blob `2c2b4594`.
- **D-067 is free.** `main`'s register has 62 decision headings, the highest D-066; the five D-067 mentions in `main`'s
  tree each say that D-067 is not allocated (four of them name it as the next free ID). The open PRs are #314 and #315; both heads' registers were read (highest D-044) and hold no
  D-067. No local branch or `origin/*` tip of the 867 scanned carries a D-067 heading.
- #314 and #315 are open and unchanged (heads `54346b37` and `4e8c81f6`, last updated 2026-10-10).
- No `pos-card-charge` function folder; no non-docs path names `providerProfile`; no source line outside
  `supabase/tests/` turns a card-payment flag on.
- No branch or PR exists for this Work ID. No hosted contact.

## 3. The contract (D-067)

### 3.1 The state answer

For every selected function (the 001D manifest's names, which before 001D include the seven re-created functions, and
the twelve #382 surface functions) the read-only state query returns:
- the raw body SHA-256 (`src`, unchanged);
- the LF-normalized body SHA-256 (`src_lf`): each CRLF pair replaced by one LF, nothing else;
- the CR count, the LF count and the CRLF-pair count;
- whether a lone CR exists (a CR not followed by an LF).

All of them are part of the state fingerprint. The raw hash is never replaced by the normalized one.

### 3.2 PRE

Each of the seven re-created functions passes in exactly one of two forms:

| Form | Accepted for | Raw SHA-256 | LF-normalized SHA-256 | CR / LF / CRLF pairs | Lone CR |
|---|---|---|---|---|---|
| Canonical LF | all seven | the canonical pin | the canonical pin | CR 0 | none |
| Exact legacy CRLF | the six named functions only | that function's reviewed CRLF pin | its canonical pin | all three equal its pinned line-break count | none |

Everything else is refused, naming only the function and the rule: generic normalization (a body accepted because its
normalized hash matches), mixed endings, an inserted or removed CR or LF, another raw form with the same normalized
hash, a CRLF body of `app.audit_category`, and any CR in any other selected function. The canonical pins are unchanged.

| Function | Canonical LF SHA-256 | Legacy CRLF SHA-256 | Line breaks |
|---|---|---|---|
| `app.sync_push` | `3567342245d0b61c509688c5706345b78015152e9f9f8c7843b5b7f6b70da9c5` | `d5114f69ba235571eddba9b98e51d37c89cdd0ae0671cb51073cbfde1ae3d0c1` | 910 |
| `app.pin_session_capabilities` | `7f0ba8c1ac58206eb6763363bda3ddd3ea81f75c89dfb622bf4259b6f813be1e` | `acde331884996f4e570b14c29f72e3dca996c2cb5227434586c6176f43ff3693` | 120 |
| `app.pos_order_snapshots` | `ce10e252ead728320ae798ce62c61db85d3b088e0b6b6669273dda7b37d7d15b` | `3caa845700d7806c10d7f2057f04bc3398527f2f350d4844a48a3c7498d70d1b` | 281 |
| `app.audit_action_has_detail` | `9e3e215f8eb465058a6202e77d1789270e271eb7af4107bfe639f975040345f2` | `5129aea0b695aa7bae4f894b21a05ef70d516244fb222f5c87d27b0f692582f8` | 49 |
| `app.audit_safe_detail` | `b571d902b1ea167848589e8a522233c1d41084599f0757b7707b07f6d2aa6c95` | `500a1888b885fa580d8f1c46f8832dc707dada7c1a1817dcec56654d93a151d1` | 130 |
| `app.owner_audit_events` | `960474ccbc4e11af695d2ce642a6d06c0090f52d7fb103066e1e56bb9e650e21` | `86175d5422dd57c6974ff9bf509548c085e3c281df4773e8537d7cfe80397012` | 204 |
| `app.audit_category` | `49e905af85b8363c355bb7a0262b5901bf1af5b63ff5a4893c3b6a08bc1b17b4` | none (canonical LF only) | — |

### 3.3 POST

After 001D every POST function must match its exact canonical POST pin: the raw hash and the LF-normalized hash both
equal the pin, the CR count is 0 and there is no lone CR. The legacy CRLF form is never accepted in POST.

### 3.4 The Default ACL

- Hosted's Default ACL is never compared with a local reference.
- The digest the first PRE reads (its row count and SHA-256 over every `pg_default_acl` row) is this run's baseline.
- The second PRE and POST must read exactly the same count and digest. The baseline is part of the state fingerprint.
- Its current hosted value is not written into D-067 or the wrapper.
- The exact POST access manifest stays required for every 001D function, the five private tables, every column of
  them and the revision sequence. An extra grant that a default privilege gives a new object still fails POST.

### 3.5 The second PRE in both routes

Both routes read the state a second time after the `--include-all` dry run: that read's own session (read-only,
encrypted, the fixed startup settings; added after the focused review, §10.5), the PostgreSQL runtime and `TimeZone`
again, the Default ACL against the baseline, then the whole state fingerprint against the first PRE's. The check
route therefore proves PRE 2 equality itself, with one more read-only session; the apply route's re-read, immediately
before its push, is this same second PRE. Both reads, the line-ending forms found and the Default ACL baseline are
printed (digests only).

## 4. Local proof (design)

Every database is disposable and local: this task's stack `BIZBOTZCREDIT001D` on PostgreSQL 17.6, never a linked or
remote target. The harness folders come from `git archive` of `e29bdb51` with `core.autocrlf=false`.

- **The hosted-shape database:** the 183-file prefix by the CLI's normal local path, then `20261104131256`,
  `20261105025413`, `20261105025604` and `20261105141815` by the emulation of the official operation (187 versions;
  001D absent).
- **Before 001D:** the six named functions are re-created, by their owner, in their exact CRLF form (the same
  definition, every LF of the body written as CRLF); `app.audit_category` stays canonical LF. Their owners,
  attributes (the whole definition apart from line endings) and exact ACLs are compared before and after.
- **Hosted-like default privileges** for role `postgres` in schema `public`: sequences, functions and tables give
  `authenticated` and `service_role` the full default privileges hosted's rows show.
- **Positive runs:** check mode accepts the legacy CRLF forms and the Default ACL as its first-PRE baseline, with PRE 2
  equal; the apply produces the exact final object ACL manifest despite the defaults, the Default ACL is unchanged, and
  POST succeeds.
- **Negative runs:** another Default ACL between PRE 1 and PRE 2 (refused); another Default ACL between PRE 2 and POST
  (POST mismatch); an extra final object grant (POST mismatch). Live line-ending refusals: a CRLF `app.audit_category`,
  mixed endings and a lone CR on a re-created function, and a CRLF #382 function.

## 5. Tests and mutations

The complete wrapper test file runs on Windows (Node 22) and Linux (Node 24). The Linux image has no git, so the
Git-backed pin tests skip there by design; they run on Windows and in CI's checkout (§10.4). New tests and mutants
cover: each exact CRLF pin; canonical LF for all seven; mixed endings; a lone CR; one changed line ending; the same
normalized hash with an unpinned raw form; a CRLF `app.audit_category`; a CR in another selected function; POST's CRLF
refusal; the hosted-like Default ACL positive path; Default ACL drift between the two PREs; Default ACL drift at POST;
and final-object grant leakage. Every existing default-route and exact-gap test stays green. Three test fixtures gain
the line-ending facts, the check route's one call-sequence assertion gains the second PRE read, and the state SQL pin
moves to the live-proven query.

## 6. CI

No CI workflow change. The existing `db-tests` step (`node --test tools/supabase/bounded-db-push.test.mjs`) runs the
expanded test file once this change reaches a future PR.

## 7. Review

One focused fresh-context Claude review: exact dual-EOL acceptance, rejection of generic normalization, PRE / POST
asymmetry, the per-run Default ACL baseline, exact final-object access, secret and redaction behaviour, and
default-route preservation. Only confirmed defects are fixed.

## 8. Drift rule

Before the package is sealed, `origin/main` is read again. A change that touches a migration, `supabase/config.toml`,
one of the seven paths, D1 or the cinematic contract or runner is a STOP. A change elsewhere is recorded; the package is
still finished against `e29bdb51`, and push and PR stay held.

## 9. Package

One sanitized source and review package outside Git: the base, head, tree and parent; the seven-path allowlist and
hashes; the D-067 text; the hosted read-only observation by digest only; the raw / canonical hash matrix; the local
hosted-shape proof; the tests and mutations; the focused review; a Draft PR plan; and a complete `SHA256SUMS`. The
earlier packages are referenced by hash and never rebuilt: the exact-gap package `23e2abaf…`, the CORRECTIONS-001
package `76c0e074…` and the REPIN-001 package `66fbd25c…`.

## 10. Results (local, 2026-11-06; every record is outside Git, in this task's evidence folder)

### 10.1 Commits and hashes

- `f176561d` opened this packet before any implementation; `e2d5f711` changed the wrapper and its tests; `facbbcaf`
  recorded **D-067** and the dated amendments; `1329974f` fixed the focused review's F1 (§10.5). The final commit adds
  this results section, the session check to §3.5 and to the D-067 and §18.2b text, the precise test notes of §5 (the
  Linux skips, the changed fixtures and the moved SQL pin), and the corrections of the records fact-check (§10.8).
- The wrapper went from blob `52f82672` (SHA-256 `9d753bab…`) to blob `fb8433c5` (SHA-256
  `33edff7c241bcba655a266550c7a507ce50367ae0aded05cfac50155934aecde`); its tests from blob `2c2b4594` (56 tests) to blob
  `24b8838f` (67 tests).
- The state query went from `09a3d902…` (179 lines) to
  `c623b45d80e3128045cad929c97be6ed6f65091478a263208286369d54c724c9` (187 lines): the text the live proof sent, which the
  tests pin.
- Exactly the seven authorized paths differ from `e29bdb51`. Against `e29bdb51` every document change is an addition;
  **D-061**, **D-065** and **D-066** are unchanged.

### 10.2 The seven re-created functions

| Function | Canonical LF | Legacy CRLF (line breaks) | Hosted, 2026-11-06 | Local proof (`run3`) |
|---|---|---|---|---|
| `app.sync_push` | `35673422…` | `d5114f69…` (910) | `d5114f69…`: legacy CRLF | CR = LF = CRLF = 910 before the apply; POST `cad1ebdc…`, CR 0 |
| `app.pin_session_capabilities` | `7f0ba8c1…` | `acde3318…` (120) | `acde3318…`: legacy CRLF | 120 / 120 / 120; POST `7704e5fe…`, CR 0 |
| `app.pos_order_snapshots` | `ce10e252…` | `3caa8457…` (281) | `3caa8457…`: legacy CRLF | 281 / 281 / 281; POST `a1d30d4e…`, CR 0 |
| `app.audit_action_has_detail` | `9e3e215f…` | `5129aea0…` (49) | `5129aea0…`: legacy CRLF | 49 / 49 / 49; POST `26052aa6…`, CR 0 |
| `app.audit_safe_detail` | `b571d902…` | `500a1888…` (130) | `500a1888…`: legacy CRLF | 130 / 130 / 130; POST `1b1cb0a5…`, CR 0 |
| `app.owner_audit_events` | `960474cc…` | `86175d54…` (204) | `86175d54…`: legacy CRLF | 204 / 204 / 204; POST `f3703e22…`, CR 0 |
| `app.audit_category` | `49e905af…` | none (canonical LF only) | `49e905af…`: canonical LF | CR 0 throughout; POST `c828cde6…`, CR 0 |

- The hosted column is the sealed state answer of the read-only check of 2026-11-06, by digest only.
- In the local proof each of the six has its canonical LF facts as built, then exactly the pinned CRLF facts
  (normalized hash = its canonical pin, no lone CR), then its canonical LF POST pin after the apply. Every row is
  consistent (`proof/EOL_MATRIX_run3.txt`).
- A Git-backed unit test derives each CRLF pin and count from the committed LF body.

### 10.3 The local hosted-shape proof (`live/run3/`, 2026-11-06T18:06Z–18:13Z, on `1329974f`)

The disposable stack ran PostgreSQL 17.6 (`server_version_num` 170006, `TimeZone` UTC). Each set had its own freshly
built hosted-shape database (187 versions, 001D absent). Every wrapper run used TLS `verify-full` against a throwaway
CA, a password only in a private owner-only passfile, and the external 10-minute watchdog. The state query sent was
`c623b45d…`, and the worktree's porcelain was 0 at the start and the end. 130 checks passed and none failed.

- **main (56 checks):**
  - **P0:** check mode on the database as built (all seven canonical LF, the local default privileges) ended
    `CHECKED_EXACT_GAP`. Its Default ACL was the run's baseline and PRE 2 was equal; it used three read-only TLS sessions.
  - **The six CRLF bodies:** each was re-created by its owner in its exact CRLF form. The state query then reported
    exactly the reviewed CRLF facts. Each whole definition equals the earlier one apart from line endings, and owner and
    ACL are unchanged; only `src`, `cr` and `crlf` changed in the state answer. `app.audit_category` stayed canonical LF.
  - **Hosted-like default privileges:** the three role-`postgres` / `public` rows now equal hosted's three rows exactly
    (they differed before), and only the `defaultAcl` digest changed.
  - **P1:** check mode on that hosted shape ended `CHECKED_EXACT_GAP`, naming the six legacy CRLF forms and
    `app.audit_category` canonical LF, with the hosted-like Default ACL as the baseline and PRE 2 equal.
  - **N1 and N2:** one more default privilege was injected between PRE 1 and PRE 2, on the check route and on the apply
    route. Both runs ended `REFUSED default_acl_changed`; the apply route pushed nothing (ledger 187).
  - **L1 to L5:** each was refused at the first PRE, naming the function and the rule, then restored (state fingerprint
    back to the reference):
    - a CRLF `app.audit_category` (`recreated_eol`);
    - mixed endings on `app.sync_push` (`recreated_eol`);
    - a lone CR on `app.pos_order_snapshots` (`recreated_eol`);
    - a CRLF body of other content on `app.audit_safe_detail` (`recreated_drift`);
    - a CRLF #382 function (`surface382_function`, with `selected_function_eol` named).
  - **P2:** the apply on the hosted shape ended `APPLIED_EXACT_GAP`, with six read-only sessions and one read-write.
    Read afterwards over the socket:
    - 188 versions, and the Default ACL unchanged;
    - the seven re-created functions in their canonical LF POST form;
    - all 62 manifest functions, the five tables, their columns and the sequence with exactly their pinned access.

    A probe function created in `public` received `authenticated` and `service_role` EXECUTE, so the hosted-like
    defaults were live; it was dropped again.
- **pre2post (24):** another default privilege after the push, before POST, gave `POSTCHECK_MISMATCH` with
  `post_unchanged` (`defaultAcl`) only.
- **extra-default (26):** default privileges that grant a fifth role on new `app` objects were accepted as the run's
  baseline: check mode ended `CHECKED_EXACT_GAP`. The apply then gave `POSTCHECK_MISMATCH` with
  `post_function_access`, `post_sequence_access` and `post_table_access`, while the Default ACL itself was unchanged.
- **extra-direct (24):** a direct grant on a 001D table after the push gave `POSTCHECK_MISMATCH` with `post_table` and
  `post_table_access`.
- `run2` (on `e2d5f711`, before the F1 fix) passed the same 130 checks; `run1` is described in §10.8.

### 10.4 Unit tests, default-route preservation and mutation checks (on `1329974f`)

- **Windows** (Node 22.14.0): 67 tests, 67 pass.
- **Linux** (`node:24-bookworm-slim`, Node 24.21.0, `--network none`, read-only mount, no git in the image): 67
  tests, 0 fail.
  - At `/repo`: 59 pass and 8 skip. Two levels down: 60 pass and 7 skip.
  - The skips are by design: six Git-backed pin tests (among them the CRLF-pin derivation), one Windows-path test and,
    at `/repo` only, the default-wiring passfile test.
- **The test file:**
  - all 56 base tests are present by name, and 11 tests are new;
  - six base blocks changed: three fixtures gain the line-ending facts, the check route's call sequence gains its second
    query, the state SQL pin moves, and one block only re-attaches a comment (`proof/TEST_FILE_DELTA_*`).
- **Default-route preservation** (text, AST and behaviour, against `e29bdb51`): PASS.
  - Every byte before the exact-gap banner is identical, and so are its 50 top-level statements.
  - The default route's exports answer 88 behaviour probes identically.
  - Seven sensitivity probes behave as expected.
- **D-067 mutants:** 56 of 56 killed. Each was a valid program and the full 67 tests ran.
- **Retained mutants** (REPIN-001's five sets, unchanged, none survived):

  | Set | Killed | Not applied |
  |---|---|---|
  | REPIN-001's own | 45 of 47 | 2 |
  | CR-EG-01 / CR-EG-02 | 33 of 34 | 1 |
  | the earlier fix round | 13 of 18 | 5 |
  | the earlier review | 19 of 19 | 0 |
  | REPIN-001's adapted set | 2 of 3 | 1 |

  Seven of the nine not applied anchor on lines this task changed: REPIN-001's D01 and D02, the fix round's M04, M05,
  M12 and M13, and the adapted set's M19. The other two were already not applied at `e29bdb51`, and REPIN-001 had
  covered both: A16 (its pattern occurs twice; split into A16a and A16b, both killed here) and the fix round's M19
  (REPIN-001 changed its anchor line and adapted it as the adapted set's M19). The seven re-anchored versions were all
  killed.
- **At `facbbcaf`** (before the F1 fix): Windows 66 of 66; Linux 66 tests, 0 fail; D-067 mutants 55 of 55.

### 10.5 The focused review

One fresh-context Claude review ran read-only on the worktree; its fingerprint of the worktree was identical before and
after. It found no BLOCKER or MAJOR, and all seven dimensions hold (dimension 4 apart from F1, since fixed).
- **F1 (MINOR, fixed in `1329974f`):**
  - **The defect:** the second read's own session (read-only, TLS, the fixed settings) is outside the fingerprint and
    was unchecked, while the check route reported that read as read-only.
  - **The fix:** both routes now refuse on it.
  - **The proof:** the new test fails against the previous wrapper (a control run), and its mutant D09 is killed.
- **N1 (NOTE):** the Linux runs skip the Git-backed tests, the CRLF-pin derivation among them. This is recorded in §5
  and §10.4; those tests run on Windows and in CI's checkout.
- **N2 (NOTE, by design):** the baseline is per run, so the wrapper never compares a check-mode run's Default ACL with
  a later apply run's (§10.7).

### 10.6 Hosted, remote, provider and device

- **Nothing hosted:** no hosted query or apply, no exact-gap hosted check and no `db push` against hosted. Every wrapper
  run targeted the local stack (loopback, port 56422).
- **Nothing else outside:** no migration repair or ledger write, no Edge deploy, no secret, no `providerProfile`
  wiring, no provider request, and no terminal, card, APK or printer action.
- **Nothing remote:** no push, no remote branch and no PR; #314 and #315 are unchanged.
- **The owner's variables:** the passfile and CA variables present in the shell were never read or passed; every test
  and harness run unset them.

### 10.7 Residuals (for the command room)

- **The Default ACL across runs.** The baseline is per run. A change between a check-mode run and a later apply run is
  not compared by the wrapper. Both runs print their baseline digest, and the exact POST access manifest still protects
  001D's objects.
- **Extra grants from defaults show only at POST.** An extra grant that a default privilege gives a new 001D object is
  seen only after the push (`POSTCHECK_MISMATCH`, then STOP).
  - Hosted's saved role-`postgres` default rows cover `public` and `storage` only.
  - Default privileges reach only new objects. 001D creates no `storage` object, and it revokes all four roles from
    each of the 55 functions it creates before granting; the seven it re-creates keep their earlier ACL.
  - The live proof applied 001D under hosted's exact `public` rows with an exact POST manifest.
- **One more read-only session.** The check route now opens one more read-only session (its second PRE).
- **Exactly six legacy forms.** The legacy pins cover exactly six bodies, so any other hosted difference still refuses.

### 10.8 Process notes

- **run1 (17:27Z to 17:33Z, on `e2d5f711`):** the driver recorded four passing wrapper runs as FAIL. Its regex anchored
  the end of the whole output, and the watchdog prints its status after the wrapper's RESULT line. Every other check
  passed. The regex was fixed and the whole proof re-run as `run2`; run1's records are kept.
- **The first default-route preservation run:** its banner search matched a header comment on line 14, so the section
  "before the banner" held no statement and two of its checks were vacuous. The tool was fixed (the rule line is part
  of the marker, at least 30 statements are required, and two more sensitivity probes were added) and re-run; the first
  record is kept.
- **The retained mutant run started at `facbbcaf`** was stopped once F1 changed the wrapper. Every retained set then ran
  once, at `1329974f`.
- **Copied harness tools:** the watchdog, the target harness, the harness config, the official-operation emulation and
  the access categories are byte copies of REPIN-001's, with their hashes recorded. The stack's start and stop logs
  print the local stack's default keys, so they stay outside the evidence.
- **The worktree:** every scripted run that records its state shows porcelain 0 at its start and end (the three live
  runs, both final-check runs, and the retained and re-anchored mutant runs). Two runs record none. The F1 control
  ran the then uncommitted F1 test, from a scratch copy, against the previous wrapper, by design. The retained run
  started at `facbbcaf` was stopped (18:03:03Z) before the F1 edit began (18:03:23Z) and left no result.
- **The records fact-check:** one read-only round (a workflow of four checkers over separate slices of these records,
  each reported discrepancy then challenged by one skeptic) checked 421 claims. Seven discrepancies were reported; the
  skeptics refuted two and confirmed five, and all five are corrected here and in D-067's wording.
  - this commit's own scope in §10.1;
  - the nine not-applied retained mutants (§10.4);
  - this bullet's scope;
  - the residual on 001D's grants (§10.7);
  - in D-067, where the default-privilege difference comes from.

  One refuted item's optional precision (dimension 4 in §10.5) is applied as well. No code, test or proof result
  changed (`review/FACTCHECK_*`).
