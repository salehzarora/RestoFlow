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

Both routes read the state a second time after the `--include-all` dry run: the PostgreSQL runtime and `TimeZone`
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

The complete wrapper test file runs on Windows (Node 22) and Linux (Node 24). New tests and mutants cover: each exact
CRLF pin; canonical LF for all seven; mixed endings; a lone CR; one changed line ending; the same normalized hash with
an unpinned raw form; a CRLF `app.audit_category`; a CR in another selected function; POST's CRLF refusal; the
hosted-like Default ACL positive path; Default ACL drift between the two PREs; Default ACL drift at POST; and
final-object grant leakage. Every existing default-route and exact-gap test stays green; the check route's one existing
call-sequence assertion gains the second PRE read.

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

## 10. Results

To be recorded after the runs.
