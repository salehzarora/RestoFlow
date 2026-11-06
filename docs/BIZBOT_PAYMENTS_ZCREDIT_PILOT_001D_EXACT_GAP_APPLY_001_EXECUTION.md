# BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001 — execution packet: the one-time exact-gap apply mode for the 001D migration

Work ID: `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001`, on branch
`fix/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001` from `main` `ad8c3caf1542770c2581630c7074f901bcd579dc`.
It adds one hard-coded, one-time mode to the GR-37 bounded apply wrapper
(`tools/supabase/bounded-db-push.mjs`). The mode applies the merged, unchanged 001D migration
`20261104141959_bizbot_zcredit_001d_server_ledger.sql` into the one history gap that hosted now has. It records the
decision as **DECISION D-066** and proves the mode on disposable local databases.

The packet contains no credential, password, terminal number, TPN, PIN-pad identifier, KEY, device serial, card datum,
provider payload, e-mail address, database URL, access token or real production UUID.

> **REPIN-001 (2026-11-05).** This packet records the mode as first pinned to `main` `ad8c3caf` (187 local
> migrations, 186 hosted versions) and as corrected by CORRECTIONS-001 (§15). REPIN-001 recomposed the corrected source
> onto `main` `0fe8ef80` (the #382 merge) and re-pinned the mode to 188 local migrations and 187 hosted versions, with
> #382's `20261105141815` as the fourth single stored statement, a PostgreSQL 17.6 runtime gate and a #382 surface
> proof: see §16 and the [REPIN-001 execution packet](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001D_EXACT_GAP_APPLY_001_REPIN_001_EXECUTION.md). Where they differ, the wrapper and that packet are current; the counts, pins
> and results below are this packet's historical record.

## 1. Request and boundary

- **The request.** The command-room authorization of 2026-11-05, "ONE-TIME EXACT OUT-OF-ORDER 001D APPLY MODE, D-066
  AND LOCAL PROOF ONLY". It is kept outside Git with a SHA-256 sidecar
  (`74b5b7bdc28bce76ae50cc22053bb8c0ac29fce889345c9fc3debfbb2fa9e2f4`). It accepts the stop
  `HOSTED_001D_DARK_APPLY_STOPPED_PR_380_MERGED_AND_MAIN_MOVED` / `NO_RETRY_PERFORMED`.
- **The hosted facts it states** (read-only, observed by the command room; not re-read by this task):
  - 186 migration versions;
  - the latest three are `20261105025604`, `20261105025413` and `20261104131256`;
  - no row for `20261104141959`, no 001D private card table and no `card_attempt` function;
  - the stored statement SHA-256 of those three versions are `a276aef4…ceb263b` (`20261104131256`),
    `a901a709…c77d5` (`20261105025413`) and `7bfac52a…9b520` (`20261105025604`);
  - their stored names, as CORRECTIONS-001 states (§15): the command room observed the #379 / #380 stored names and
    statement hashes through an authorized read-only query on 2026-11-05.
- **The selected route.**
  - Keep version `20261104141959` and do not re-version it.
  - Add a one-time exact-gap wrapper mode. That mode may use `supabase db push --include-all` internally.
  - Generic `--include-all` stays forbidden, and so do `migration repair` and manual history writes.
- **Scope: exactly six tracked paths.**
  - `tools/supabase/bounded-db-push.mjs`;
  - `tools/supabase/bounded-db-push.test.mjs`;
  - `.github/workflows/ci.yml`;
  - `docs/DECISIONS.md`;
  - `docs/DEPLOYMENT.md`;
  - this packet.
- **Not changed:**
  - the 001D migration, either #380 migration and every other migration;
  - payment SQL and functions;
  - Edge, POS, Dashboard and l10n;
  - the D1 test;
  - the substance of D-061 and D-065;
  - `AGENT_WORKFLOW.md` and D-016.
- **Not authorized and not done:**
  - **any hosted query or apply;**
  - `migration repair`, a manual ledger write, a push, a PR or a merge;
  - an Edge deploy, a Z-Credit secret, `providerProfile` wiring or a provider request;
  - terminal or card use, an APK or a printer action.
- **Review.** No Codex review is requested. One focused fresh-context Claude review runs (§11), and CORRECTIONS-001
  adds one focused fresh-context Claude delta review of its corrections (§15).

## 2. Preflight (read-only, 2026-11-05T08:42Z)

Recorded outside Git (`pre/PREFLIGHT.txt`); every check passed.

- **Main.** `origin/main` is `ad8c3caf` (tree `c6b622ea55f3bbce9ad097e40e0207dbfc81d3c2`). Its parents are `cac03522`
  (#381) and `578a6615` (#380 head). The open PRs are #314 and #315, both untouched (their heads and update times are
  as recorded).
- **The 001D file.** `20261104141959_bizbot_zcredit_001d_server_ledger.sql` is unchanged: blob `b94a3417`, SHA-256
  `468768f89029a0fb131869f754d5374127930b8bf05b48cd8de19d645546352e`.
- **The migrations.** `main` holds 187 migrations; the newest four are `20261104131256`, `20261104141959`,
  `20261105025413` and `20261105025604`. The file SHA-256 of `20261104131256`, `20261105025413` and `20261105025604`
  equal the three stored statement hashes above.
- **Payments.** `providerProfile` stays `null` (no `pos-card-charge` function; no non-docs path names it). No
  non-docs, non-test source turns a card-payment flag on.
- **D-066 is free.** No `## D-066` or `## DECISION D-066` heading exists on `main` or on the #314 and #315 heads. On
  `main`, D-066 appears only as the next free ID: in three `DECISIONS.md` changelog lines (the preflight's "any 'D-066'
  3") and in three lines of the MIGRATION-REORDER-001 execution packet.

## 3. Why an exact gap, and why the stored statements match the files

- **The official route.** #379's `20261104131256` (its release receipt in `BIZBOT_STOREFRONT_CINEMATIC_001B_RELEASE.md`)
  and #380's `20261105025413` / `20261105025604` reached hosted through the official Supabase migration operation. That
  operation assigns the version from the apply time (the repository files were renamed to match). It stores the whole
  file as **one** statement, so the SHA-256 of that single stored statement equals the file's SHA-256.
- **What the CLI does.** `main` orders 001D before those two #380 migrations, but hosted applied them first. Hosted's
  latest version therefore sorts after 001D. The pinned CLI then refuses a normal push: "Found local migration files
  to be inserted before the last migration on remote database … Rerun the command with --include-all". The default
  GR-37 route refuses too, because 001D is not the newest local file.
- **Why repair is invalid.** 001D's schema is absent on hosted, so marking the version applied would record schema
  that does not exist.
- **Why not re-version.** Re-versioning would change the identity of a merged, reviewed migration that the cinematic
  tripwire, the D-061 record and the evidence all pin. It stays the fallback only if the exact-gap proof fails.

## 4. The exact-gap mode contract

- **Selection.** Only `--exact-gap BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001`, exactly once.
  - Any other value refuses (`exact_gap_mode_unknown`; the value is never echoed).
  - A caller's `--include-all` refuses by name (`include_all_refused`), and so does any repair token
    (`repair_refused`).
  - Every other argument follows the default rules. No version, manifest or option comes from the caller.
- **Inputs.** The default route's three environment inputs (`BIZBOT_GR37_DB_URL`, `BIZBOT_GR37_PASSFILE`,
  `BIZBOT_GR37_SUPABASE_CLI`), plus `BIZBOT_GR37_SSLROOTCERT`: the owner-private CA file, which is never printed.
- **Pins.** Every pin is hard-coded and deep-frozen:
  - **The missing migration:** version `20261104141959`, file
    `20261104141959_bizbot_zcredit_001d_server_ledger.sql`, SHA-256 `468768f8…6352e`, ledger name
    `bizbot_zcredit_001d_server_ledger`.
  - **The local set:** 187 migrations. Pinned are the SHA-256 of the sorted name list (`06f982d5…e0d7`) and of the
    "name SHA-256" lines of every file (`ca81ee48…e585`), so every byte of every migration is pinned. The local tail
    must be `20261104131256`, `20261104141959`, `20261105025413`, `20261105025604`, each with its pinned SHA-256.
  - **The workdir's other CLI inputs:** `supabase/config.toml` (SHA-256 `447beeba…6bd7`, `main`'s bytes) and the one
    dotenv name `main` ships, `.env.example`.
  - **Remote before the apply:** 186 versions. The remote tail must be `20261104131256`, `20261105025413`,
    `20261105025604`, and the later hosted migrations are `20261105025413` and `20261105025604`.
  - **Stored statements:** for each of the three tail versions, the stored name and exactly one stored statement
    whose SHA-256 is the pin above.
  - **The 001D manifest,** derived from the migration bytes:
    - 5 tables, the identity sequence, 12 named indexes and 11 named triggers;
    - one `deny_client` policy per table (for all commands, permissive, to `authenticated`, `using (false)` and
      `with check (false)`);
    - 62 functions, each with name, body SHA-256 (= `prosrc`), security definer, `proconfig`, volatility, language and
      EXECUTE group. The groups are 39 without a client grant, 4 granted to `authenticated` and 12 to `service_role`.
      The other 7 are the functions 001D re-creates, with only the bits the file sets.
  - **The seven re-created functions before 001D:** the body SHA-256 of each one's latest definition in the other 186
    files.
  - **The exact access (CR-EG-02, CORRECTIONS-001):** for every selected object, its stored ACL (a NULL ACL resolved to
    its documented default) exploded into `[grantee, privilege, grant option, grantor]` entries:
    - the 39 functions without a client grant: the owner `postgres` alone; the 4 `authenticated` and 12 `service_role`
      functions: the owner plus that one role; every entry EXECUTE, without grant option, granted by `postgres`;
    - the seven re-created functions: their own entries (six with `authenticated` and the owner; `app.audit_category`
      the owner alone), the same before and after 001D;
    - each of the five tables: the owner's eight privileges (PostgreSQL 17, so MAINTAIN is one of them); the sequence:
      the owner's SELECT, UPDATE and USAGE;
    - no column grant on any column of the five tables.
  - **The 001D history row:** 125 recorded statements (the file's top-level statements) and their digest
    (`49b5e0fc…7309`).
  - **The #379 / #380 surfaces:** 34 functions and 2 tables.
  - **The hosted CA:** the accepted CA's SHA-256 fingerprint.
- **Where each pin comes from.**
  - **Re-derived by the unit tests from the committed bytes:** the missing migration's file, SHA-256 and ledger name;
    the local set and its tail; `config.toml` and the dotenv names; the whole 001D manifest, the policy shape included;
    the seven pre-001D bodies (and that the two later #380 files define none of 001D's functions); the 001D row's
    statement count; the surfaces.
  - **The authorization's values:** the versions, counts and tails, and the three stored-statement SHA-256 (the tests
    also check that they equal the files).
  - **Observed in the local proof only:** the 001D row's statements digest, identical on the sequential and the gap
    database; and the exact access entries (CORRECTIONS-001), read on the sequential database A just before and just
    after 001D and identical on the gap database B before and after the apply (§15). The unit tests tie them to the
    migration's own EXECUTE groups and to the bits the file sets; without a database they cannot derive them.
  - **A literal from the owner's file:** the hosted CA fingerprint, of the owner-provided Supabase Root 2021 CA
    validated at the dark-apply resume. It cannot be derived in CI.
  - **Observed on hosted by the command room:** the #379 / #380 stored names and statement hashes, through an
    authorized read-only query on 2026-11-05 (CR-EG-03). The wrapper pins the names from the file names. The check-mode
    run revalidates them immediately before the apply, and the apply run's own PRE checks them again: the earlier
    observation is evidence, and it never substitutes for the final PRE.
- **Local gates, before any CLI process.**
  - The workdir holds exactly the pinned set: count, names and every byte. A CRLF checkout fails here.
  - Its other CLI inputs are pinned too: `supabase/config.toml` must have `main`'s bytes (`local_config`); no dotenv
    file other than `.env.example` may sit in the workdir or its `supabase/` folder (`local_dotenv`: the CLI loads
    dotenv files, and one can set `PGSERVICE*`, which outranks `PGSSLMODE`); and `supabase/.temp` must hold no
    `project-ref` or `pooler-url` (`local_linked`). The CLI's own `.temp/cli-latest` cache is allowed.
  - The URL, pooler and debug gates are the default ones. The passfile gate is the default one plus one rule (CR-EG-01,
    CORRECTIONS-001): the file holds exactly one active entry in total (comments and empty lines aside), and that entry
    is the exact target with a non-empty password. A second active entry refuses (`passfile_entry_count`; a file with
    no exact entry or with two of them is refused earlier, by the default check: `passfile_entry`), a malformed or
    wildcard line still refuses, the second read of the file must itself pass the one-entry rule and select the same
    password (`passfile_changed` otherwise), and nothing about the file is printed.
  - **The CA file** must be: absolute; a regular, non-empty file; outside the repository, the store, `worktrees`,
    `evidence` and the workdir; owner-only; exactly one PEM certificate and no private key; a self-signed CA inside its
    validity. Hosted mode also requires the pinned fingerprint.
- **Sessions.**
  - Every session except the push is read-only. Its passwordless URL carries
    `-c default_transaction_read_only=on` plus the three fixed settings (`lock_timeout=5s`, `statement_timeout=60s`,
    `application_name=bizbot_gr37_001d_v1`).
  - The push uses the default URL with exactly the three fixed settings.
  - The child environment is the default allowlist plus `PGSSLMODE=verify-full`, `PGSSLROOTCERT` (the CA) and
    `SUPABASE_EXPERIMENTAL_PGDELTA_ENABLED=false`. The default route keeps `PGSSLMODE=require` and its child
    environment is unchanged.
  - **The pg-delta post-step is off.** `main`'s `config.toml` enables the pinned CLI's experimental pg-delta step.
    After a real push it writes the CLI's own three-root Supabase CA bundle into `supabase/.temp/pgdelta/`, starts an
    edge-runtime container for a catalog export, and a second read-write session appears. With the variable set to
    `false` the push opens exactly one read-write session and writes no pg-delta file (§14).
  - Every database command adds `--agent no`, because the pinned CLI wraps `db query` answers in an envelope when it
    detects an agent environment. The `--version` call is the one command without it.
- **PRE (read-only).** One catalog statement runs through the pinned CLI (`db query --output json`). It reads catalog
  facts, the ledger's versions and names, and digests; never application data. It must find all of the following:
  - **The session:** read-only, encrypted, and carrying the fixed settings.
  - **The ledger:** exactly 186 unique versions with the pinned tail. The symmetric difference with the local set is
    exactly `{20261104141959}`: no second gap and no remote-only version.
  - **The three stored statements and names,** as pinned. Every other shared version's non-null name must equal its
    file's name; a NULL name is allowed and counted.
  - **No 001D object:** none of the pinned 55 new functions, tables, the sequence, indexes or triggers, and no
    `card_` / `payment_terminal` named relation or function.
  - **The seven re-created functions,** each present exactly once and in its pinned pre-001D form: the body SHA-256
    and owner as pinned (`recreated_drift`: a drifted or partly pre-applied body is never replaced silently), the
    EXECUTE bits the file sets already in place, so the file's re-statement of them is a no-op, and exactly their pinned
    access entries (`recreated_access`: an extra, missing or changed grantee, privilege, grant option or grantor).
  - **All #379 / #380 surfaces present.**
- **Dry run.** `supabase db push --include-all --dry-run` runs read-only and must list exactly
  `20261104141959_bizbot_zcredit_001d_server_ledger.sql`, cross-checked against the read-only set difference. A CLI
  that reports "Connecting to local database" (its local-stack shortcut skips TLS) refuses (`cli_local_database`).
- **Apply.** The wrapper re-reads the state, which must be unchanged (`state_changed` otherwise; the state fingerprint
  covers the exact access of the seven re-created functions), and then re-checks
  the local folder (migrations, `config.toml`, dotenv files, link state) as the last gate before the push. It then
  runs **one** `supabase db push --include-all --yes`. There is no retry.
- **POST (read-only).** Every one of these must hold:
  - **Versions:** 187 remote versions, exactly the local set, with `20261104141959` recorded once under its name, with
    the pinned 125 statements and their digest.
  - **Earlier rows:** every earlier ledger row is unchanged.
  - **The CLI:** a normal dry run without `--include-all` reports the database up to date; `migration list` shows 187
    rows with no divergence; no CLI repair, pull, reset or include-all advice appears.
  - **The 001D manifest:**
    - every pinned function matches: body hash, attributes, owner `postgres`, and EXECUTE for `anon`,
      `authenticated`, `service_role` and PUBLIC per its group;
    - for the re-created functions: all four EXECUTE bits unchanged from PRE (PRE already required the bits the file
      sets);
    - the tables have RLS enabled and forced, owner `postgres`, no client privilege and only `deny_client`;
    - the sequence has no client privilege; all indexes and triggers are present and the triggers enabled;
    - **exact access (CR-EG-02):** every function, each table, every column of them and the sequence carry exactly their
      pinned entries (`post_function_access`, `post_table_access`, `post_column_access`, `post_sequence_access`), so no
      unlisted role, missing grant, other grantor or grant option passes; the four known-role bits above remain as
      readable diagnostics (`post_privilege`). The access of the objects 001D creates is decided by the push itself
      (the server's default privileges for `postgres` and its major version), so only POST can check it, and a
      difference there is a `POSTCHECK_MISMATCH` after the push (§15).
  - **Everything else, by catalog digest:** PRE and POST digests must be equal for every other function of the `app`
    and `public` schemas (identity, body, security definer, config, volatility, language, owner, ACL), for every other
    relation there (kind, RLS flags, owner, ACL, columns, constraints, policies, triggers, indexes), and for every
    default privilege. Nothing else is compared: not view definitions or options, other function attributes (such as
    the return type, STRICT or PARALLEL), other object classes, other schemas or table rows.
- **Verdicts.**

  | Verdict | Exit | Meaning |
  |---|---|---|
  | `REFUSED <code>` | 2 | nothing pushed |
  | `RESULT: CHECKED_EXACT_GAP` | 0 | without `--apply` |
  | `RESULT: APPLIED_EXACT_GAP` | 0 | applied and verified |
  | `RESULT: PRE_READ_FAILED` | 3 | STOP |
  | `RESULT: DRY_RUN_FAILED` | 3 | STOP |
  | `RESULT: PUSH_FAILED` | 3 | STOP |
  | `RESULT: POSTCHECK_MISMATCH` | 4 | STOP |

  Every STOP means: no retry and no repair.
- **The external watchdog.** The operator runs the wrapper under the external 10-minute process-tree watchdog, as
  for the default route.

## 5. Default-mode preservation

- **Unchanged code.** Every default-route function except `main()` keeps its exact text; `main()` gains only the
  dispatch block. Apart from the two import lines, the diff only adds. The changes are:
  - the `node:crypto` import gains `X509Certificate` in place, and the one-line `node:fs` import becomes a three-line
    import with three more names (`mkdtempSync`, `rmSync`, `writeFileSync`);
  - `import os from 'node:os';` is added;
  - a header paragraph is added;
  - **one dispatch line** at the top of `main()` routes the call to the new mode when the argument list contains the
    exact `--exact-gap` token.
- **Unchanged behavior.** Without that flag the default route runs as before: `--include-all` is still an unknown
  argument, the newest-one-pending gate stands, `PGSSLMODE=require` is kept, and the default `dryRunArgs` / `pushArgs`
  are unchanged.
- **Unchanged tests.** The 20 existing unit tests are byte-identical and pass. New tests assert the default
  behavior again for the dispatch.

## 6. Local remote-gap rehearsal (design)

All on this task's disposable stack: project `BIZBOTZCREDIT001D`, container `supabase_db_BIZBOTZCREDIT001D`, loopback
port 56422, the only stack the frozen 001D runner accepts. Every folder is an LF `git archive` of `ad8c3caf` outside
Git.

- **The same files, in a different order.** Both databases start with `supabase db reset` of the 183-file prefix (every
  migration before `20261104131256`, through the CLI). Then:
  - **A, sequential:** filename order — `20261104131256`, then 001D by the CLI (`migration up --local`), then
    `20261105025413` and `20261105025604`.
  - **B, hosted shape:** `20261104131256`, `20261105025413` and `20261105025604` first, then 001D through the wrapper's
    exact-gap mode (`db push --include-all`).

  The three official-route versions take the same route (the emulation below) on both. 001D's command differs: on A
  `migration up --local`, on B the wrapper's `db push --include-all`, both through the same pinned CLI and its apply
  path, and both record an identical history row (125 statements, the same digest).
- **The official-operation emulation (disclosed).** The three official-route versions are applied by a local
  disposable helper that reproduces the hosted ledger shape: it connects as `supabase_admin`, runs the file under
  `SET LOCAL ROLE postgres` in one transaction, then inserts the version, the name and the whole file as the single
  stored statement. Hosted's own operation and its session are not observable here. The helper writes the ledger of a
  disposable local database only; it is not part of the wrapper and is never used against hosted. Without it the
  rehearsal could not reproduce the hosted stored-statement shape that the wrapper's pins check.
- **The hosted ledger is modelled at its tail only.** B's 183 earlier rows come from `supabase db reset` (split
  statements, names as the files), not from hosted's own history. The hosted check-mode run is therefore the first
  test of the `remote_name` gate against hosted's earlier rows.
- **The target as hosted.** B is made to look like hosted for the wrapper:
  - **TLS:** a throwaway CA and a server certificate for `IP:127.0.0.1` only, enabled with `ALTER SYSTEM`;
  - **The password:** a random postgres password, reachable only through owner-only private passfiles outside the
    store;
  - **A probe:** a PG17 login event trigger that `RAISE LOG`s each session's TLS, authentication method, read-only
    default, application name and timeouts.

  Everything is reset afterwards.
- **The wrapper workdir must be a pristine checkout.** The mode pins its migrations, `config.toml`, dotenv files and
  link state (§4). Locally there is one more reason: the pinned CLI treats a URL whose host and port match the
  workdir's own local stack as "the local database" and then ignores `PGSSLMODE`. The rehearsal therefore uses a
  pristine LF checkout of `main` (its `config.toml` names port 54322), exactly as the hosted run will. The mode also
  refuses if the CLI ever reports a local connection.
- **Live negative states** (each a separately built disposable database):
  - no gap (database A);
  - two gaps (the prefix without its newest file);
  - a missing #380 migration (`20261105025604` not applied);
  - a remote-only version (a synthetic extra prefix migration);
  - a changed #380 stored statement (the emulation fed a modified copy);
  - a partial 001D schema (one 001D table created);
  - drifted re-created functions (B, then EXECUTE on `app.sync_push` granted to PUBLIC and `app.audit_category`
    owned by another role; added in the fix round);
  - added by CORRECTIONS-001 (§15): a fifth role with EXECUTE on the re-created `app.audit_category` (N7); and default
    privileges that give every new `app` object a fifth-role grant (N8, built twice: once for the wrapper of
    `c781a18b`, once for the corrected wrapper).

  On database B itself:
  - a caller `--include-all`;
  - a caller repair;
  - changed 001D bytes (a CRLF copy);
  - a CRLF `config.toml`, a dotenv file in `supabase/`, and a linked workdir (each on its own copy of the workdir;
    added in the fix round);
  - an unrelated CA;
  - a host name the certificate does not cover;
  - a wrong password;
  - a passfile holding the exact entry plus another active entry (CORRECTIONS-001).
- **Identities recorded** for both databases: the container, image and `system_identifier`, the postmaster start, the
  ledger and the schema digests.

## 7. Comparison of the final A and B

- **The schema dump.** `pg_dump --schema-only` of the whole `postgres` database, with pg_dump 17's random
  `\restrict` sentinel lines removed.
- **Per-category catalog captures:**
  - functions (identity, body hash, attributes, owner, ACL);
  - tables, columns, constraints and indexes;
  - RLS and policies;
  - default privileges;
  - the ledger (version, name, statements digest);
  - the D1 public surface;
  - `record_payment` (body and callers);
  - the #379 / #380 surfaces;
  - the 001D tables, functions and grants.
- **Ignored items: exactly two, both non-semantic.**
  - pg_dump 17 writes a `\restrict <key>` / `\unrestrict <key>` sentinel pair whose key is random for every dump.
    Those two lines are removed from both dumps before they are compared: they guard pg_dump's own output and are not
    part of the schema.
  - The `session` block of the wrapper's state answer is left out of the captured state. It describes the capturing
    connection (user, read-only setting, timeouts, application name, server version, TLS), not the database; the
    wrapper's own state fingerprint leaves it out too.

  Nothing else is ignored. The 19 catalog captures are compared unfiltered and carry no OIDs or times.
- **Scope.** The comparison covers the database-level schema and the ledger. None of the four tail files writes a row
  or touches roles, database settings or default privileges at the top level (their row statements sit inside function
  bodies), so the schema-level comparison covers everything those four files change.

## 8. Tests (both final databases)

- **Database tests:**
  - the full pgTAP suite;
  - the seven 001D lanes;
  - the 001D concurrency runner twice;
  - the 353 and acceptance-ETA runners, on a task-owned fixture restored from each database;
  - the D1 file;
  - the #380 database tests;
  - the dedicated-database suites in their dedicated modes;
  - the content-contract suite in its local-marker mode.
- **Node tests:** the cinematic contract and wrapper tests, and the wrapper unit tests.
- **Not run locally, by design:**
  - the CI-only featured-items suite;
  - the cinematic real-service runner, which refuses outside GitHub Actions;
  - five `support/` runners that need their own native PostgreSQL instance and checkout.

  None of their guards is bypassed.

## 9. CI

One step in the existing `db-tests` job: `node --test tools/supabase/bounded-db-push.test.mjs`.
- **What it runs:** the default-route regression tests and the exact-gap positive and negative tests.
- **What it uses:** an injected fake CLI only — no database, Docker, network, credential, hosted target or pooler.
- **What it leaves alone:** no other threshold or permission changes.

## 10. D-066 and the deployment runbook

- **D-066** records the one-time exact-gap decision, as allocated in `DECISIONS.md`. The next free ID becomes D-067.
- **`DEPLOYMENT.md` §18.2b** gets a dated, additive amendment. It names the exact-gap mode as the one approved route
  for this one gap. It lists the earlier statements that describe the default route only, and the rules that hold for
  both routes.

## 11. Review

One focused fresh-context Claude review ran on head `17929f40` against `ad8c3caf` (2026-11-05, outside Git:
`review/`). Six reviewers, each with a fresh context and one lens, read the six paths, the authorization and the
evidence:
- D-066 and the documents;
- default-mode preservation and include-all confinement;
- the exact migration-set comparison and the PRE / dry-run / POST gates;
- the local sequential-vs-gap equivalence;
- credentials, redaction and transport;
- CI isolation and test quality.

A seventh agent verified the one MAJOR finding. Every reviewer left the worktree, the main checkout and the earlier
evidence unchanged (checked against a fingerprint taken before the review); the CI lens ran its mutants in temporary
folders only.

**Result: 32 findings — 1 MAJOR, 13 MINOR, 18 NOTE; no BLOCKER.**
- The MAJOR (EG-EQ-1) was lowered to a NOTE by its verifier.
  - The step's behaviour was observed first-hand during the review (§14): the CLI writes its own CA bundle, starts the
    edge-runtime container, and one extra read-write session appears.
  - On that evidence the verifier found no session that trusts the CLI's bundle: the runtime failed before it
    connected.
  - The step is turned off for the mode anyway, so the push is one read-write session.
- Each MINOR and NOTE carried its own evidence: line references, and mutation runs for the test gaps. Each test-gap
  finding was re-checked against the fix-round tests (§13.1).

No reviewer found a false accept in the shipped gates, a credential leak or a weakened default route. One fix round
followed, limited to the six paths and to confirmed defects, with no further broad round.

| Finding | Severity | Disposition |
|---|---|---|
| EG-EQ-1: the pinned CLI's pg-delta post-step may open a further session that trusts the CLI's own CA bundle | MAJOR → NOTE (no such session observed) | Turned off anyway: `SUPABASE_EXPERIMENTAL_PGDELTA_ENABLED=false` in the mode's child environment (§4, §14) |
| EG-DM-IA-01, TQ-02: the local re-check ran before the re-read, not right before the push, and was untested | MINOR | Fixed: it is the last gate before the push; a flow case refuses on the second check, with no push |
| EG-GATE-04: the 001D row was not tied to the pinned bytes | NOTE | Fixed: 125 statements and their digest are pinned |
| EG-GATE-03: the re-created functions' pre-001D bodies and access were unpinned | NOTE | Fixed: body SHA-256, owner and the bits the file sets are PRE gates; POST requires all four bits unchanged |
| EG-GATE-01, TQ-03: several gates and predicates had no failing test | MINOR | Fixed: flow cases (dry run listing one other file; ledger-only change; second local check) and one variant per predicate |
| TQ-01: the CA, CLI, passfile and folder call sites were untested | MINOR | Fixed: wiring tests with the real checks, including a hosted case with a real test CA (`ca_not_accepted`, no CLI process) |
| EG-DM-IA-02: the post-push verdict guard was untested | NOTE | Fixed: an error after the push gives exit 4, never a refusal |
| EG-DM-IA-03: the wrapper was never run as a process | NOTE | Fixed: both routes run as a process and refuse `url_missing` |
| TQ-04: the state-query file content was untested | NOTE | Fixed: the fake CLI checks the file's SQL, that it is owner-only and that it is removed |
| CI-01: on Linux the fake CLI path's directory was `.`, a redaction secret | MINOR | Fixed: platform-native fake paths |
| CI-02: the POSIX CA-permission negative depended on the umask | NOTE | Fixed: the file is set to 0644 first |
| CRED-1: redaction was untested through CLI output | MINOR | Fixed: CLI output echoing every secret is relayed redacted at the three failure sites |
| CRED-2: lines were cut before redaction | NOTE | Fixed in the mode (redact, then cut). The default route's summary is unchanged by mandate |
| CRED-3, F7: dotenv files and `config.toml` were unpinned | NOTE | Fixed: `local_dotenv`, `local_config` and `local_linked` gates |
| DOC-01, F3: not every pin was re-derived as claimed | MINOR | Fixed: `missingName`, the policy shape, `config.toml`, the pre-001D bodies and the 001D statement count are re-derived; §4 states each pin's source |
| F1: three runbook statements became false for the new mode | MINOR | Fixed: the amendment lists them as superseded for this mode |
| F2, EG-GATE-02: "everything else unchanged" overclaimed | MINOR | Fixed: the claim names exactly what the digests cover (the `app` / `public` functions' and relations' listed attributes and every default privilege) and what they do not |
| F4: the preflight misstated where D-066 is mentioned | MINOR | Fixed (§2) |
| F8: three §4 / §5 statements contradicted the code | NOTE | Fixed (§4, §5) |
| F5: no record of the merge gate | NOTE | Addressed (§12) |
| F6, EG-GATE-05: where #380's stored names come from (pinned from the file names) | NOTE | Corrected by CORRECTIONS-001 (CR-EG-03): the command room observed the #379 / #380 stored names and statement hashes through an authorized read-only query on 2026-11-05; the check-mode run revalidates them immediately before the apply, and the earlier observation never substitutes for the final PRE (§4, runbook) |
| EG-EQ-2: a harness script was edited between A's and B's lanes | NOTE | Recorded (§14); the re-run records the harness digests at its start |
| EG-EQ-3: "no item was ignored" despite the sentinel removal | NOTE | Fixed (§7) |
| EG-EQ-4: the comparison is schema-level | NOTE | Fixed: §7 states the scope |
| EG-EQ-5: "same route per version" overstated | NOTE | Fixed (§6) |
| EG-EQ-6: B models the hosted ledger at its tail only | NOTE | Fixed (§6) |

## 12. Publication preparation (plan only)

A branch push plan, the Draft PR title and body, the exact changed-path allowlist, the expected CI and Vercel fan-out,
and the later hosted dark-apply continuation are prepared outside Git. Nothing is pushed and no PR is created.

- **The merge gate.** This packet does not change it. Merging this Work ID keeps the **D-016** gate (independent
  Codex review and the human merge approval) unless the owner records a different decision for it. **D-061**'s narrow
  route covers only the 001D publication head it names.

## 13. Results (local, 2026-11-05; every record is outside Git)

**Superseded in part by §15 (CORRECTIONS-001):** the corrected code, its wrapper SHA-256, the unit-test counts, the
mutation checks of the corrections and the targeted live re-run. The results below are the proof of `783a7d73`; §15 says
which of them it re-ran and which it reuses by hash.

**The final code is `783a7d73`, on `ad8c3caf`.** Its commits:
- `c6df502f`: the packet;
- `7f0dfd27`: the mode and tests; `a4056062`: a test fix;
- `6ce38406`: CI;
- `6dc4c7c0`: D-066 and the runbook;
- `17929f40`: the first results;
- the fix round after the review: `8cfbc8e4` (the mode and tests) and `0c97811d` (the documents);
- after the results fact-check (§14): `8c65f41d` (the mode's output lines and comments) and `783a7d73` (the
  documents).

The commit that records these results changes only this packet.

**The wrapper's SHA-256:**
- `fafac6d0…` at base;
- `b5ba5b71…` at the first candidate;
- `c14668b9…` after the fix round;
- `59ab29aa…` at the final code.

Since `c14668b9…`, only output lines and comments have changed.

**Three proofs are kept outside Git**, each superseding the one before:
- `run/`: head `6dc4c7c0`;
- `run2/`: head `0c97811d`;
- `run3/`: the final code.

The results below are `run3/`'s. `run2/`'s lane statuses and live results match them line for line, apart from the
database identities, the times and the 001D runner's conditional assertion counts. Each re-run records every harness
tool's SHA-256 at its start (§14). Against the first proof, the re-runs add:
- a live negative state for the re-created-function gates;
- three live workdir-gate refusals;
- a check that no pg-delta file appears.

### 13.1 Wrapper unit tests, mutation checks and default-route preservation

- **Windows (Node 22):** 40 of 40 pass: the 20 existing tests byte-identical, plus 20 new
  (`proof/UNIT_TESTS_WINDOWS_NODE22_783a7d73.txt`).
- **Linux (Node 24, in Docker with no network, a read-only mount and no git):** 35 pass and 5 skip
  (`proof/UNIT_TESTS_LINUX_NODE24_783a7d73.txt`):
  - four skips are the Git-backed pin tests, which run in CI's checkout;
  - one is the existing Windows-only path test.

  A redaction mutant fails there too, so the leak checks are live on Linux
  (`proof/UNIT_TESTS_LINUX_MUTANT_M01_783a7d73.txt`; CI-01).
- **Mutation checks,** in scratch copies outside Git. A mutant counts as killed only when a test fails and the test
  count is unchanged.

  | Set | Before the fix: `17929f40`, 36 tests, Git-backed tests running | At the final code: 40 tests |
  |---|---|---|
  | The review's surviving mutants (19) | 16 survive; 3 do not apply (their pins came with the fix) | 19 of 19 killed |
  | The fix round's own mutants (18), each reverting or weakening one fix | — | 18 of 18 killed |

  The records are in `proof/`: `REVIEW_SURVIVOR_MUTANTS_BEFORE_FIX.txt`, `REVIEW_SURVIVOR_MUTANTS_783a7d73.txt` and
  `FIX_ROUND_MUTANTS_783a7d73.txt`.
- **Default-route preservation (`proof/DEFAULT_MODE_PRESERVATION_783a7d73.txt`): PASS.**
  - 43 of the base wrapper's 44 top-level blocks appear verbatim. The 44th, `main()`, is its base body plus exactly
    the dispatch block.
  - The only base lines gone are the two widened import lines.
  - All 32 base test blocks are verbatim, and no base test line is gone.

### 13.2 The live rehearsal on the hosted-shape gap database B (`run3/B_gap_live/`)

**Setup.**
- B was built from the 183-file prefix by `supabase db reset`. `20261104131256`, `20261105025413` and
  `20261105025604` came from the official-operation emulation, each as one stored statement equal to its file hash,
  which gave 186 versions.
- The target had TLS with a throwaway CA and an IP-only certificate, a random password reached only through private
  owner-only passfiles, and the login probe.
- Every run used the wrapper at the final code, under the external watchdog, with a clean environment. The workdir was
  the pristine LF `main` checkout; its `config.toml` SHA-256 is the pin, and its `supabase/.temp` held only
  `cli-latest`.

All thirteen checks PASS: eleven runs, the unchanged state before the apply, and the pg-delta file check. The table
shows the POST result on its own row. The workdir-gate refusals each ran on their own copy of the workdir.

| Run | Result |
|---|---|
| A caller `--include-all` | `REFUSED include_all_refused` before any CLI process |
| A caller `migration repair` | `REFUSED repair_refused` before any CLI process |
| A CRLF copy of the 001D file | `REFUSED migration_hash` |
| A CRLF `config.toml` | `REFUSED local_config` before any CLI process |
| A dotenv file in `supabase/` | `REFUSED local_dotenv` before any CLI process |
| A linked workdir (`supabase/.temp/project-ref`) | `REFUSED local_linked` before any CLI process |
| An unrelated CA | `PRE_READ_FAILED`; "x509: certificate signed by unknown authority"; no server session |
| `localhost` against an `IP:127.0.0.1` certificate | `PRE_READ_FAILED`; "x509: certificate is not valid for any names"; no session |
| A wrong password | `PRE_READ_FAILED`; SQLSTATE 28P01; no session |
| Check mode | `CHECKED_EXACT_GAP` |
| State after every run so far | unchanged (state fingerprint equal) |
| The one apply | `APPLIED_EXACT_GAP`; the push took 972 ms |
| POST | 187 versions; 62 functions, 6 relations, 12 indexes, 11 triggers |
| The workdir's `supabase/.temp` after the apply | only `cli-latest`: no pg-delta file |

**Server-observed sessions (the login probe).**
- Check mode: 2 sessions, each read-only, TLS, scram-sha-256, `lock_timeout=5s`, `statement_timeout=1min`.
- The apply: 7 sessions — 6 read-only and **1 read-write (the push)** — all TLS, scram-sha-256, 5s / 1min.

  The first proof saw 2 read-write sessions. The second appears only while the pg-delta step is on (§14), and the
  mode now turns that step off.

### 13.3 Negative states (`run3/N*`)

Each is a separately built disposable database. Each run exited 2, named every listed gate, and left the database
unchanged (state fingerprint equal).

| State | First refusal | Also named |
|---|---|---|
| N1 no gap (database A, 187 versions) | `remote_count` | `no_gap` |
| N2A two gaps | `remote_count` | `gap_mismatch` |
| N2B #380's `20261105025604` missing | `remote_count` | `remote_tail`, `gap_mismatch`, `later_missing` |
| N3 a remote-only version | `remote_count` | `remote_only` |
| N4 a changed #380 stored statement | `stored_statement` | — |
| N5 a partial 001D table | `partial_001d` | — |
| N6 drifted re-created functions (EXECUTE on `app.sync_push` granted to PUBLIC; `app.audit_category` owned by another role) | `recreated_access` (`anon` and `public` on `app.sync_push`) | `recreated_drift` (`app.audit_category`) |

Some negatives exist only as unit tests:
- a dry run listing two migrations, one other migration, or an unreadable answer;
- a POST normal dry run that is still divergent;
- a state change before the push (another function, or a ledger row only);
- a local-folder change before the push;
- a failed push;
- an error after the push;
- a local-stack connection, before or after the push.

### 13.4 The two final databases, compared (`run3/COMPARISON_A_B.txt`)

- **Database A** (sequential): `system_identifier` `7704659785593561127`.
- **Database B** (gap, then the wrapper): `system_identifier` `7704663002663788583`.
- They were built one after the other in the container named `supabase_db_BIZBOTZCREDIT001D`. Each build's
  `supabase db reset` re-created it as a fresh cluster, hence the two `system_identifier` values. Both used the same
  image (`sha256:f371b5f3…`) and PostgreSQL 17.6. Both ledgers end with 187 rows, the last `20261105025604`.

**Result: EQUIVALENT.** Every one of 19 catalog categories is identical:
- comments; constraints; the D1 public surface; default privileges; event triggers; extensions;
- functions (identity, body hash, definition hash, attributes, owner, ACL); indexes;
- the ledger (version, name, statements digest); the 001D objects; policies; publications;
- `record_payment` (body and its callers); relations (columns, owners, ACLs, RLS); schemas;
- the #379 / #380 surfaces; triggers; types; views.

Also identical:
- the whole schema-only dump: 67,469 lines, SHA-256 `25bde4bd38a3356dff7fc779c104967c16a744d887e50cd9286d6c51c00d54d8`,
  the same value as in the first proof. The comparison record prints 67,470, because its line count includes the
  empty string after the final newline;
- the wrapper's own state answer, without its `session` block.

The two ignored items, both non-semantic, are pg_dump's random `\restrict` sentinel pair and the state answer's
`session` block (§7). The comparison record's result line names only the first.

The comparison covers the database-level schema and the ledger. None of the four tail files writes a row or touches
roles, database settings or default privileges at the top level (`proof/TAIL_FILES_TOPLEVEL_STATEMENTS.txt`).

### 13.5 Tests on both final databases (`run3/A_validate/`, `run3/B_validate/`)

| Lane | A | B |
|---|---|---|
| Full pgTAP suite (`supabase test db`) | `Files=337, Tests=13466, Result: FAIL`, exit 1 | the same |
| Four dedicated-database suites, in their dedicated mode | 205, 33, 35, 26 — all PASS | the same |
| Content-contract suite, local-marker mode | 38 PASS | 38 PASS |
| Seven 001D lanes | 139 + 397 + 273 + 140 + 244 + 343 + 177 = 1,713, all PASS | the same |
| 001D concurrency runner, twice | PASS, 41 scenarios (1,357 and 1,357 assertions) | PASS, 41 scenarios (1,356 and 1,359) |
| 353 runner, on a fixture restored from each database | PASS | PASS |
| Acceptance-ETA runner, same fixture | PASS (106 assertions, 9 races) | the same |
| D1 (`public_surface_acl_remediation_001_test.sql`) | 62 PASS | 62 PASS |
| #380 database tests | 96 + 28 PASS | the same |
| Cinematic database tests | 116 + 49 PASS | the same |
| Cinematic contract / wrapper node tests (run from the worktree) | 19 / 19 | 19 / 19 |
| GR-37 wrapper unit tests | 40 / 40 | 40 / 40 |

- **The full suite.** Exactly six guarded files exited 3 with "No plan found" (0 tests, 0 failed), because their guards
  refused before any test. The other 331 files passed. This is the known local execution limitation:
  - four of the six then ran in their dedicated-database mode;
  - the content-contract suite ran in its local-marker mode;
  - the featured-items suite is CI-only.

  No guard was bypassed.
- **The runners.** Every runner reported `productionContacted: false`. The 001D runner dropped its task-owned database
  and dump each time. The task-owned 353 / acceptance-ETA fixture container was removed after its two runners.
- **The assertion counts of the 001D runner** vary because some of its checks are conditional.

**Not run locally, by design:**
- the CI-only featured-items suite;
- the cinematic real-service runner (`requireEphemeralCi` refuses outside GitHub Actions);
- five `support/` runners that need their own native PostgreSQL instance and work-item checkout, and are not CI lanes.

### 13.6 Hosted and production

**None.** No hosted query, apply, migration repair or manual ledger write. No Edge, secret, provider, terminal, card,
APK or printer action. No push and no PR.

## 14. Process notes

- **Order.** This packet was written after the first draft of the wrapper change, not before it as the authorization
  asked. Its commit is the first commit of the branch. The deviation is recorded here and in the delivery report.
- **Two pinned-CLI behaviors found by the live rehearsal and handled in the mode:**
  - the `db query` answer format depends on agent detection (now pinned with `--agent no`; both shapes are parsed
    strictly);
  - the "local database" shortcut skips TLS (refused explicitly; a pristine workdir is required).
- **A third, raised by the review (EG-EQ-1) and observed first-hand during it** (outside Git: `pgdelta/`). Two fresh
  hosted-shape gap databases each received the mode's exact push (same arguments and child environment, full CLI
  output kept, logins observed by the probe):
  - **With the step on** (as `main`'s `config.toml` sets it): the push succeeded. The CLI then wrote its own
    three-root Supabase CA bundle to `supabase/.temp/pgdelta/pgdelta-target-ca.crt` and started an edge-runtime
    container running `@supabase/pg-delta` 1.0.0-alpha.27, and the server saw a second read-write session with the
    wrapper's application name. The export failed locally (the runtime could not read the bundle at its container
    path: ENOENT), and the wrapper's success summary did not show that warning.
  - **With `SUPABASE_EXPERIMENTAL_PGDELTA_ENABLED=false`:** the push succeeded with exactly one read-write session, no
    pg-delta output and no file.

  The mode now sets the variable for its child processes. The default route is unchanged.
- **The harness during the first run (EG-EQ-2).** A's lanes ran first. A's cinematic node tests then failed in the
  harness folder (a `git archive` has no history), so they were re-run by hand from the worktree, and the harness
  script was edited to run them from the worktree before B's lanes started. The first run's archived harness is
  therefore the edited one. The re-runs (`run2/`, `run3/`) record the SHA-256 of every harness tool at their start.
- **The fix round** after the review (§11) changed the mode and its tests, D-066 point 2, the runbook amendment and
  this packet. The whole local proof was then re-run on the fix-round code (`run2/`), with these harness additions,
  all outside Git:
  - the N6 build mode;
  - the three workdir-gate refusals and the pg-delta file check in the live set;
  - the harness digests at the start of the run;
  - the comparison's wording of its one ignored item.

  Of the 22 tool files hashed at the start of `run2/`, only the packaging script changed afterwards: it was extended,
  while the run was going, to include the re-run's and the pg-delta records, and the run itself does not use it.
  Three tool files were added: the two mutation-check scripts of §13.1 and the top-level statement scan of §13.4.
- **The fact-check of the results record.** Three read-only agents checked §4, §11 and §13, D-066 point 2 and the
  runbook amendment against the evidence and the code (outside Git: `review/FACTCHECK_*`). They made no writes. They
  found ten factual errors in the documents and none in the gates:
  - the live check count;
  - the count of verbatim base blocks;
  - the dump's line count;
  - the container wording;
  - a second ignored item;
  - the scope of the "unchanged" claim;
  - the dry run's place among the gates;
  - which stored names had been observed (corrected again by CORRECTIONS-001, CR-EG-03: the command room had observed
    all three);
  - the runbook's "the rest holds for both routes";
  - the account of EG-EQ-1.

  All ten are corrected. The wrapper's output lines and comments made two of the same claims (the "unchanged" scope
  and the dry run's place), and those were corrected too. Two other output lines now say what their gates check: the
  re-created functions' pre-001D form, and the 001D row's 125 statements. These are output and comment changes only;
  no gate changed.

  The proof was then re-run on that code (`run3/`, §13). Its start hashed 25 tool files. Afterwards one more tool file
  was added: the script that produced §13.1's final-code records. The packaging script was extended again: its packaged
  copies now mask a disposable database's PostgreSQL system identifier when that identifier happens to pass the Luhn
  check (`run3/`'s N3 database), and the package lists each such copy. The original stays in the evidence folder.

## 15. Corrections (CORRECTIONS-001, 2026-11-05; every record is outside Git)

**The request.** The command-room authorization "SOURCE CORRECTIONS BEFORE PUBLICATION"
(`BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001-CORRECTIONS-001`, verdict `SOURCE_CORRECTION_REQUIRED`), kept
outside Git with a SHA-256 sidecar (`0b45cb5eb6776eda977fc58fc61294deb9165426f19c2cc31a110356f2cd9d49`). It accepts the
D-066 design and the sequential-vs-gap equivalence in principle, and requires three source corrections before any push,
PR or hosted use. Only four tracked paths may change: the wrapper, its tests, `DEPLOYMENT.md` and this packet. No
Codex review is requested. The evidence is in its own folder,
`evidence/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001-CORRECTIONS-001-20261105/`; the original evidence
folder and its package (`23e2abaf…`) are unchanged.

**Resume checks** (read-only, before any write; `pre/PREFLIGHT.txt`):
- `origin/main` is still `ad8c3caf` (read with `git ls-remote`); the branch was at `c781a18b` (tree `b35b92a2`), clean,
  with no upstream;
- no remote branch and no PR names this Work ID; #314 and #315 have the heads and update times recorded at §2;
- D-066 is unchanged and allocated only on this branch;
- no hosted action was taken.

New since §2: Draft PR #382 (another Work ID, created 2026-11-05) carries migration
`20261105141815_bizbot_storefront_background_clarity_001_api.sql`. It does not touch `DECISIONS.md`. Its bearing on the
hosted continuation (the 187-file pin) is in the corrected continuation plan.

**CR-EG-01: exactly one passfile entry.** The mode accepted a passfile that held the exact target entry plus another,
unrelated active entry (the default route's rule allows that). Now `verifyExactGapPassfile` runs every default passfile
check (location, owner-only permissions, format, the exact target) and then, on the same file,
`selectExactGapPassfileEntry`:
- comments and empty lines are ignored; a malformed or wildcard line refuses as before;
- the number of active entries must be exactly one (`passfile_entry_count` otherwise; a file with no exact entry or
  with two of them is refused earlier, by the default check, with `passfile_entry`);
- that entry must match the host, port, database and user exactly and carry a non-empty password;
- the second read must itself pass this rule and select the same password (`passfile_changed` otherwise).

Messages name no path and no content. The default route's rule and code are unchanged.

**CR-EG-02: the exact access of every selected object.** The four booleans (`anon`, `authenticated`, `service_role`,
PUBLIC) could not show a grant to any other role. The state query now also returns, for every selected function and
relation, its stored ACL (a NULL ACL resolved to its documented default) exploded into `[grantee, privilege,
grant option, grantor]` entries (role names; PUBLIC for grantee 0), and for every relation each column grant as
`[column, grantee, privilege, grant option, grantor]`. Each list is sorted in byte order (`collate "C"`).
- **Pins** (`EXACT_GAP.access`, §4): one entry set per EXECUTE group, one per re-created function, the table set, the
  sequence set and "no column grant", as observed on the sequential reference A (§15.2).
- **PRE:** each of the seven re-created functions must carry exactly its pinned entries (`recreated_access` otherwise:
  any extra, missing or changed grantee, privilege, grant option or grantor). The re-read before the push compares the
  whole state, so the state fingerprint covers these entries.
- **POST:** every 001D function, each table, every column and the sequence must carry exactly the pinned entries
  (`post_function_access`, `post_table_access`, `post_column_access`, `post_sequence_access`). The four booleans stay
  as readable diagnostics (`post_privilege`). The PRE / POST default-privilege digest check is unchanged, and it is not
  used in place of the exact access.
- The migration is unchanged.

**CR-EG-03: the hosted observation.** The packet (§1, §4, §11 F6, §14), the runbook amendment and the continuation plan
now say: the command room observed the #379 / #380 stored names and statement hashes through an authorized read-only
query on 2026-11-05; the check-mode run revalidates them immediately before the apply; that observation is evidence and
never substitutes for the final PRE. This correction ran no hosted query.

### 15.1 Tests and mutation checks (final code `f7f3fb4b`)

The final code is `f7f3fb4b`: wrapper SHA-256 `3011f56a…`, test file SHA-256 `36344c84…`. The fix round after the delta
review (§15.4) changed one wrapper comment, so the wrapper's code and its state query are the ones `78f936d7` carried
(`626e73a1…`); the state query's SHA-256 is `88cdc196…` in both. Records in `proof/`, named by the head:
- **Unit tests:**
  - **Windows (Node 22):** 48 of 48. The 20 base tests are byte-identical; the 20 earlier exact-gap tests pass; 8 tests
    are new (three for CR-EG-01; five for CR-EG-02: the pins, the state SQL, PRE, POST and the flow).
  - **Linux (Node 24, Docker, no network, read-only mount, no git), mounted at `/repo`:** 42 pass and 6 skip. Four are
    the Git-backed pin tests and one is the Windows-only path test. The sixth is the CR-EG-01 default-wiring test, which
    skips by design when the checkout's parent folder is `/`, because the passfile location rule then refuses every path.
  - **The same, mounted two levels down:** 43 pass and 5 skip; the default-wiring test runs with a real mode-0600 file.
  - **The redaction mutant M01 on Linux:** killed, so the leak checks are live there.
- **Default-route preservation:** PASS. 43 of the base wrapper's 44 top-level blocks are verbatim, `main()` is the base
  body plus exactly the dispatch block, the only base lines gone are the two widened import lines, and all 32 base test
  blocks are verbatim.
- **Mutation checks** (scratch copies outside Git; a kill counts only when a test fails and the test count is unchanged;
  every mutant parses):

  | Set | Result |
  |---|---|
  | The corrections' own mutants (the copied tests read the pins from the Git work tree, so nothing skips) | **34 of 34 killed.** 9 for CR-EG-01: no count; two entries allowed; only same-host entries counted; the default check wired in; the second read unchecked, its change accepted, read by the default rule, or its failure swallowed; malformed lines counted before they are refused. 25 for CR-EG-02: each PRE / POST check removed; grantee-only, grant-option-blind, grantor-blind, subset and superset comparisons; a missing answer read as empty; every function held to one group; re-created functions held to themselves; the fingerprint without the access; ten weakenings of the state SQL, four of them the delta review's (A22–A25) |
  | The delta review's four SQL mutants, against the tests of `012f4041` (control) | 0 of 4 killed: all survive the earlier tests |
  | The earlier fix round's mutants (18) | 18 of 18 killed |
  | The earlier review's surviving mutants (19) | 19 of 19 killed. Two patterns follow the new dependency line (`verifyPassfile: verifyExactGapPassfile`) and still disconnect only the CA check or only the CLI check |

### 15.2 Targeted live re-run (`run5/`, 2026-11-05T15:49Z–16:00Z, on `f7f3fb4b`)

The final wrapper (SHA-256 `3011f56a…`; state query `88cdc196…`, recorded in `run5/STATE_SQL.sql`) ran on fresh disposable
databases of this task's stack (`supabase_db_BIZBOTZCREDIT001D`, image `sha256:f371b5f3…`, PostgreSQL 17.6), under the
external watchdog, with a clean environment, `verify-full` TLS and private owner-only passfiles. The wrapper of
`c781a18b` (SHA-256 `59ab29aa…`, equal to its Git blob) supplied the "before" half of each reproducer. The run hashed its
26 harness tools at its start; the worktree was clean at `f7f3fb4b` from start to end. (`run4/`, the same set on
`78f936d7` before the delta review, gave the same results and is kept.)

| Part | Result |
|---|---|
| A, sequential (`system_identifier` `7704715176365424679`) | built, with a read-only access snapshot just before 001D; captured |
| N1–N6, the earlier negative states | each refused exactly as in `run3/`, the database unchanged. N6 now also names the exact-access difference of both drifted functions: an extra PUBLIC entry on `app.sync_push`; and on `app.audit_category`, now owned by `supabase_admin`, a `supabase_admin` entry granted by `supabase_admin` in place of the `postgres` one |
| N7: a fifth role with EXECUTE on the re-created `app.audit_category` | **before:** `c781a18b`'s check mode passes (exit 0). **After:** the corrected wrapper refuses `recreated_access`, naming `eg_fifth_role` (exit 2), and the database is unchanged. Revoking the grant changes the state fingerprint, and only that function's access differs; the corrected wrapper then passes |
| N8: default privileges give every new `app` object a fifth-role grant (built twice) | **before:** `c781a18b` applies and ends `APPLIED_EXACT_GAP` (exit 0), although 47 functions, the five tables and the sequence carry the fifth role. **After:** the corrected wrapper applies and ends `POSTCHECK_MISMATCH` (exit 4), naming 47 `post_function_access`, 5 `post_table_access` and 1 `post_sequence_access`. The default-privilege digest is unchanged in both runs, as point D of the request expects |
| B, hosted shape (`system_identifier` `7704717533813542951`): the live set | 15 of 15 checks pass: the earlier 13 (caller include-all and repair, a CRLF 001D file, a CRLF `config.toml`, a dotenv file, a linked workdir, a wrong CA, a wrong host name, a wrong password, check mode, the unchanged state, the apply, pg-delta off), a passfile with an extra entry refused `passfile_entry_count` before any CLI process, and the same passfile accepted by `c781a18b` (check mode, exit 0) |
| B, the apply | `APPLIED_EXACT_GAP`: 6 read-only and 1 read-write session, all TLS, scram-sha-256, 5s / 1min; the push took 985 ms. POST: 187 versions, 62 functions, 6 relations, 12 indexes, 11 triggers, each with its exact pinned access |
| A and B compared | **EQUIVALENT:** the 19 earlier categories, 4 new access categories (function, relation and column grants, and default privileges), the whole schema dump and the state answer (now with the exact access) |
| The pins against the live states | PASS: the seven re-created functions on A just before 001D and on B before the apply; every 001D function, table, column and the sequence on A and on B afterwards |
| B after the apply: one column grant (the delta review's CR-R-01) | `SELECT (id)` on `app.card_provider_attempts` to a disposable role: the corrected state answer lists exactly that grant, only that relation's columns differ, and the POST evaluation names exactly `post_column_access`; `c781a18b`'s query has no column field and cannot see it; revoked, the state is as before |

**Reused by hash (not re-run).** The correction changes no migration and no database behaviour, only the wrapper's
read-only verification, so `run3/`'s lanes stand (§13.5). They include the full pgTAP suite (`Files=337, Tests=13466,
Result: FAIL`, exit 1, the six guarded files), the dedicated suites, the content contract, the seven 001D lanes, the
runners, D1 and the #380 and cinematic tests. The re-run ties itself to `run3/` in three ways:
- `run3/`'s comparison record has SHA-256 `61becbe4…`;
- the schema dump of both new databases has SHA-256 `25bde4bd…`, `run3/`'s value;
- `run5/`'s A matches `run3/`'s A byte for byte in all 19 earlier categories.

### 15.3 What the check run cannot see (a residual, for the command room)

PRE pins the seven functions that exist before the apply. The access of every object 001D creates is decided by the
push itself: by the server's default privileges for role `postgres` (in `app`, in `public` and for all schemas) and by
its major version (the pins are PostgreSQL 17 values; a table owner holds MAINTAIN). If hosted differed there, the push
would complete and POST would end `POSTCHECK_MISMATCH` (exit 4, a STOP), as N8 shows. The corrected continuation plan
therefore suggests that the command room compare, under its own authorization, hosted's default privileges for
`postgres` and its server version with the local reference (`run5/A_capture/cat_access_default.txt`) before it
authorizes `--apply`. This correction adds no PRE gate for them: the request keeps the default-privilege check as a
PRE / POST "unchanged" check only.

### 15.4 The focused delta review

One fresh-context Claude review (five lenses: the passfile gate, the access proof, default-route preservation, the
hosted-observation wording, secrets and redaction) read `c781a18b..012f4041`, the authorization and the evidence, ran
the tests and its own mutants in a temporary folder only, and left the worktree, the main checkout and both evidence
folders unchanged (`review/POST_REVIEW_CHECK.txt`). **Result: no BLOCKER and no MAJOR; one MINOR and two NOTEs.**

| Finding | Severity | Disposition |
|---|---|---|
| CR-R-01: the access SQL was guarded by substring checks only; three one-line query changes hid a grantee (relation ACLs read as NULL; unlisted grantees filtered out; only PUBLIC column grants kept), and the column path had never been non-empty live | MINOR, confirmed | **Fixed.** The SQL test pins the SHA-256 of the whole state query, the one the live proof ran, and the two CTE source lines. The reviewer's four mutants survive the earlier tests and fail these (A22–A25). A live column-grant probe now shows the column path (§15.2) |
| CR-R-02: two refusal codes and the second-read rule were stated more broadly than the code behaves (no safety impact) | NOTE, confirmed | **Corrected** in the wrapper comment, §4, §15 and the continuation plan: a file with no exact entry or two of them refuses first with `passfile_entry`; the second read must pass the one-entry rule and select the same password |
| CR-R-03: the new objects' access depends on hosted's default privileges and major version, which no PRE gate checks | NOTE (the documented residual, §15.3) | **No change:** not a defect against the request; the optional PRE gate on the major version is the command room's decision |

The review also noted that §15 did not yet record the Node 24 runs (added in §15.1), and that D-066 in `DECISIONS.md`
describes only part of the checks: true, but nothing in it is false, and that file is outside the four paths this
correction may change.

### 15.5 Hosted and production

**None.** No hosted query or apply, no `--include-all` against hosted, no migration repair, no ledger write, no Edge
deploy, no secret, no `providerProfile` wiring, no provider call, no terminal, card, APK or printer action, no push and
no PR. The only network traffic was read-only: `git ls-remote` and `gh pr` reads for the resume checks, the Vercel
predictor's fetch of public `main` into a throwaway clone, and the pinned Supabase CLI's own version check during the
local runs.

### 15.6 Process notes

- **Where the access pins came from.** Before the pins were written, one exploratory sequential build (outside Git:
  `explore/`) was read to see the reference access. Its four access captures are byte-identical to `run4/`'s and
  `run5/`'s A, and the pin checks of both runs confirm every pin against the live states.
- **`run4/`.** The first targeted re-run, on `78f936d7`, before the delta review. The run reads only the wrapper, and the
  wrapper did not change while it ran. During it the test file and two documents were edited, so its end line shows 3
  changed paths and the same `HEAD`. Its 17 harness tools were unchanged from its start to its end.
- **The harness additions** (outside Git, in the correction evidence's `tools/`):
  - the access captures, the access probe and the pin check;
  - the N7 and N8 build modes and the reproducer sets of the rehearsal driver;
  - the corrections' mutant set (with the delta review's four SQL mutants, and the control switch);
  - the column-grant probe;
  - the run drivers (`eg_run_cr.sh` for `run4/`, `eg_run_cr5.sh` for `run5/`), the final-check, scan, package and
    postflight scripts.

  The earlier review mutant set has its two patterns that name the default-dependency line moved to the new line;
  each still disconnects only the CA check or only the CLI check.
- **The shell.** The shell this task ran in carries two of the owner's variables from the earlier dark-apply session (a
  passfile path and a CA path; their names only are recorded in `pre/PREFLIGHT.txt`). They were never read, printed or
  passed to a run: the tests, the mutation checks and the live harness ran with them unset, and every wrapper run
  builds its own environment.

## 16. Re-pinned to current `main` (REPIN-001, 2026-11-05)

The command room accepted CR-EG-01, CR-EG-02 and CR-EG-03 as reported and required a repin to current `main`: #382
(`0fe8ef80`, merged 2026-11-05T14:51:22Z) added `20261105141815` on `main`, and the command room observed it on hosted.
The corrected source (`3e9e2316`) was recomposed onto `0fe8ef80` blob for blob and then re-pinned; the
[REPIN-001 execution packet](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001D_EXACT_GAP_APPLY_001_REPIN_001_EXECUTION.md) holds the provenance, the contract, the local proof and the review. The pins that changed:

| Pin | This packet (`ad8c3caf`) | REPIN-001 (`0fe8ef80`) |
|---|---|---|
| Local migrations | 187 | 188 |
| Remote versions before the apply | 186 | 187 |
| Local / remote tail | four / three versions | five / four versions, ending `20261105141815` |
| Single stored statements | three | four (`e5cf4b28…` for `20261105141815`) |
| Runtime | not gated (the access pins were PostgreSQL 17 values) | `server_version_num` 170006 and `TimeZone` UTC, in PRE and the re-read |
| #382 | absent | the #379 / #380 / #382 surfaces present; #382's own relation, twelve functions and two Storage policies exactly as pinned (PRE), identical after the apply (POST) |
| State query | SHA-256 `88cdc196…` | SHA-256 `09a3d902…` |

Unchanged: the 001D manifest and its pins, CR-EG-01, CR-EG-02, the default route and the one CI step.
