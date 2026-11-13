# BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F-JOURNAL-RECOVERY-CORRECTIONS-001 — execution packet: unresolved TEST recovery, the 200-record admission bound and envelope uniqueness (local, fake Edge only)

Work ID: `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F-JOURNAL-RECOVERY-CORRECTIONS-001`, a bounded correction of
[BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001F_EXECUTION.md) (the POS card journal, UI and
recovery). Controlling contract: [API_CONTRACT](API_CONTRACT.md) §4.55 with **D-051** .. **D-064**, as the 001F
packet applies them. This packet records no **DECISION**, adds no **OPEN QUESTION** and allocates no ID.

This packet was written and committed before any executable change (correction request §1). The preamble, §1, §3
and §4 – §8 were then brought in line with the delta review, an accuracy check of this text, a review of the fix
delta, a check of the review package and a check of the round-4 text (§10.3, §10.8); §10 records the results.

## 1. Request and boundary

- Command-room source review of 2026-10-31, "TEST RECOVERY, HARD CAP AND ENVELOPE UNIQUENESS", verdict
  `REQUEST_BOUNDED_CORRECTION_BEFORE_LOCAL_ACCEPTANCE`, on the 001F head
  `d7ce9990482e57c67e499bca2cf8c3ed07ba253c` (tree `8b5cb04ea8680a90add39c64da447defbedbe1ba`; review package
  `946a8c56b082ca1d18dd9c71b0fd703f35662f294f458eb8d2673189de7e448c`). The request is kept outside Git with a SHA-256
  sidecar (`0ca4a64d5f9e457977e2d235d777b5f56ceda073e15b4188d24d80c2db293f43`).
- The command room verified the archive and its content checksums, the 25 source files and the patch round trip, the
  journal / controller / UI / recording architecture, and the preservation of the order action row, printing, SQL, the
  Edge and `providerProfile: null`. It did not rerun the Flutter / Dart logs (no SDK in its review environment). No
  broad redesign and no new Codex review is requested.
- Three corrections (request §2 – §4): **A** an unresolved TEST attempt stays recoverable whatever the lab toggle
  (within the limits of §4.4); **B** the 200-record journal bound becomes a real admission bound; **C** the journal
  envelope is validated for duplicate identities before any record is used. Everything else 001F accepted stays as it
  is (§7).
- Not authorized: a push, a PR, a merge, a hosted action, a deployment, a migration, a secret or configuration change,
  a provider request, a vendor inquiry, a terminal or card action, a printer or APK action; wiring the provider profile;
  the order action row, `packages/printing/**`, kitchen ticket / reprint / printer code, receipt rendering or cutting,
  the #314 / #315 branches or tests; any database suite (no SQL changes). Every network call in the tests goes to a
  fake.
- Branch `fix/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F-JOURNAL-RECOVERY-CORRECTIONS-001-recovery-cap-uniqueness` in its own
  worktree, created from the exact reviewed head `d7ce9990`; no upstream. The 001F branch and every earlier payment
  branch, commit, package and evidence folder are preserved (no amend, rebase, reset, deletion or history rewrite).
  Current main and the uncommitted l10n changes of another worktree are recorded only, never merged.

## 2. Source anchor (preflight 2026-10-31T07:58:39Z, read-only)

| Source | Head | State |
|---|---|---|
| Base: 001F (`feat/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F-pos-card-flow`) | `d7ce9990482e57c67e499bca2cf8c3ed07ba253c` | the reviewed head; tree `8b5cb04e` verified; its worktree clean; no upstream |
| 001C correction | `148df092f08e71e39abfcf493835a1d852cfa9f7` | unchanged; the 001F base |
| 001C card Edge transport | `71bfef5bc57df9434c628894119610f99101b1b6` | unchanged |
| 001E W1 profile candidate / D-064 / W1 / G1 / Edge adapter | `cf1ffacf` / `ca8edb03` / `140be040` / `295cacb6` / `d5456624` | unchanged |
| 001D ledger publication (#370, draft) | `54b19ab58ce72a2fa9a43860e31181a08222b254` | unchanged |
| D-061 route r2 (#371, draft) | `53d6a6adc38f308b7ed6b0dd62177e6edd5ad5ce` | unchanged |
| #314 / #315 (reserved) | `54346b37b35679c21248a64e40dcb3b0ca894673` / `4e8c81f6bd7249f3a44d1089c6253ad84df7f413` | unchanged; never edited here |
| origin/main (`git ls-remote`) | `c31370c4a5df47d084b3138559fddb8a880ad7b9` | recorded only; merge base with the base `d2079820`, 14 commits / 64 files since, of which the seven l10n files are in this request's file scope |

- `supabase/functions/pos-card-charge/index.ts` line 19: `providerProfile: null,` (blob `7a3c5c97`), unchanged.
- The 001F review package verifies, and so does its evidence folder (`SHA256SUMS.txt`: 144 OK); the 001C, 001C
  correction and profile-candidate packages verify too.
- Ownership of the file scope: of the five open PRs (#314, #315, #370, #371 and the storefront draft #377), only #370
  touches files of the scope (the seven l10n files, a known stacking overlap). The worktree
  `BIZBOT-POS-PRINT-HISTORY-L10N-001` holds seven uncommitted changes to the same seven l10n files; they are not merged
  here and are a coordination point for whoever integrates both.
- The new worktree's packages were resolved with `flutter pub get --offline --enforce-lockfile` (Flutter 3.44.2);
  `pubspec.lock` stayed byte-identical.

## 3. Exact files (the request's §6 scope)

Changed by this correction — the minimum of the scope:

| Path | Change |
|---|---|
| `apps/pos/lib/src/data/provider_card_attempt.dart` | A: the set-aside rule (both modes alike) and decoder rule R7d |
| `apps/pos/lib/src/data/provider_card_store.dart` | B: admission inside `createIfAbsent` (mint callback, full result); C: the uniqueness check on every read and before every write |
| `apps/pos/lib/src/state/provider_card_controller.dart` | A: an open TEST attempt is shown whatever the lab; B: the typed `journalFull` start result, minting inside the store's admission |
| `apps/pos/lib/src/widgets/provider_card_payment_view.dart` | A: no way back from a TEST attempt that waits or has a confirmed cancel; Back to payment only once it is final (a TEST "result not confirmed" had none in 001F either, and the set-aside of an attempt proven to have no claim is unchanged) |
| `apps/pos/lib/src/widgets/cash_payment_sheet.dart` | A: a TEST result the sheet showed stays until it is left; B: the full-journal sentence. The 001F covering rule is otherwise unchanged |
| `apps/pos/test/provider_card_journal_test.dart`, `provider_card_controller_test.dart`, `provider_card_sheet_test.dart`, `support/provider_card_fakes.dart` | the required tests (§8.1) and those the fix-delta review asked for (§10.3). Of the 001F tests: three sheet tests that pinned the corrected behaviour are re-targeted, one more sheet test also forbids Back to payment and Cancel this request, and seven journal tests, the controller test's two store fakes and the hooked store follow the new `createIfAbsent` signature (calls only) |
| `packages/l10n/lib/l10n/app_{ar,en,he}.arb` and the four generated `app_localizations*.dart` | one new closed sentence for the full journal (no existing sentence describes it accurately, §5.3) |
| `docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001F_EXECUTION.md` | narrow dated corrections where its text describes the corrected behaviour, and owner point D4 |
| this packet | new |

`apps/pos/test/provider_card_static_test.dart` is in the scope and was not changed: no pin was needed. Not touched: the
presentation, Edge, recording and capability files of 001F, `staff_capabilities.dart`, the base payment kernel, every
manifest and lockfile, the shared transports, `supabase/**`, Dashboard / KDS / Kiosk / Storefront, release files and
every protected path of §1.

## 4. Correction A — an unresolved TEST attempt stays recoverable

### 4.1 Before (001F at `d7ce9990`)

- Visibility: the sheet asked the controller for `currentFor(identity, includeTest: lab)`. With the lab toggle off —
  its default, reset by every PIN-session change and, being in memory, by every restart — every TEST attempt of the
  order was out of sight and the tender form showed, whatever the attempt's state.
- Set-aside: `mayBeSetAside` was true for TEST waiting, TEST cancel-confirmed, TEST approved / declined / closed and a
  TEST "result not confirmed". The card view's "Back to payment" set the waiting, cancel-confirmed and final ones aside
  (`closed: set_aside`), which put them out of sight for good. It offered no way back from a TEST "result not
  confirmed" (Check status and "Close and resume later" only, as in LIVE); the lab default hid that one instead.

### 4.2 After

The lab toggle decides only whether a TEST start may go out: a new TEST attempt, or "Send the same request" for one no
start of which can have had an effect (not sent, sign in again). An open TEST attempt is the restricted recovery
surface of its order on this till, as an open LIVE attempt is: it covers the tender form whatever the lab toggle, and
it can be neither left nor set aside until it is final or proven to have no claim. The limits of this surface are
§4.4.

| TEST state (§7.1 of the 001F packet) | Open? | Shown with the lab OFF | May be set aside | Actions in the card view |
|---|---|---|---|---|
| preparing (in memory) | yes | yes | no | none while the request is in flight |
| not sent | yes | yes | yes (`abandoned`: it never left the device) | Send the same request (needs the lab: a first send to the server); Cancel this request; Close |
| sign in again | yes | yes | yes (`set_aside`: no start can have had an effect) | Send the same request (needs the lab); Take payment another way; Close |
| result not confirmed | yes | yes | **no** | Check status; Close and resume later |
| not found (settled) | yes | yes | yes (`set_aside`: the server proved no attempt exists) | Check status; Take payment another way; Close and resume later |
| test in progress (`test_sent` / `test_unknown`) | yes | yes | **no** | Check status; Cancel on the terminal (advisory); Close and resume later |
| test cancel confirmed (`test_released`) | yes | yes | **no** | Check status; Close and resume later |
| needs reconciliation (a safety stop) | yes | yes | **no** | Check status; Close and resume later (owner point D2) |
| test approved / declined / closed | no | only when this sheet showed it before it turned final, until it is left (in the lab, as before) | not needed | Check status; Back to payment; Close |
| refused / unavailable start | no | only when this sheet showed it, until it is left (in the lab, as before) | not needed | Take payment another way; Close |
| a stored closure (`abandoned`, `set_aside`) | no | no: the view is left when the closure is stored | not needed | Take payment another way; Close |

- Covering: while it is open, the TEST attempt replaces the order's tender form on this till — no other tender, no new
  start, no hand-recorded Card — before and after a PIN-session change, a restart or a reopened sheet (the 001F
  covering rule, now reached whatever the lab toggle). An open LIVE attempt of the order is shown before it.
- Same journal row and identity: showing, checking or closing it mints nothing and adds no row; a status answer
  updates the same row in place. No new TEST attempt: with the lab off no new TEST start is offered or accepted (and
  "Send the same request" sends nothing, noting the terminal unavailable); with it on, a start for an order whose
  TEST attempt is open adopts that attempt. No TEST path builds the recording leg (`payment.create` stays LIVE-only)
  or a receipt, revenue or "Paid". A release stays advisory: "cancel confirmed" is not a no-charge proof and is
  never set aside. Status checks follow the accepted 001F capability (automatic while the view is visible, explicit
  through Check status; the server answers `permission_denied` to a session outside the card roles).
- Set-aside follows one rule for both modes: only where no charge can exist (not sent, sign in again, a settled not
  found). A TEST approval, decline or operator closure is final and needs no set-aside.
- Decoder rule **R7d**: a stored closure (`abandoned` or `set_aside`) never hides an unresolved attempt — without it
  the record must be final already, or one that may be set aside. A closure the 001F build could have stored on an
  unresolved TEST attempt (waiting, cancel confirmed, not confirmed) is therefore quarantined, never honoured as
  "closed"; one it stored on a final TEST result stays readable. The 001F build never left this machine, so none is
  expected in the field.
- The first implementation of this correction (`8c48018f`) let the cashier go back to payment from an unresolved TEST
  attempt and kept it in sight with a banner; the delta review showed that the order could then be paid another way,
  after which nothing showed the attempt again (§10.3, F1). `2e04ec98` replaced it with the covering surface above.

### 4.3 Owner decision D4, as corrected

"An unresolved TEST attempt covers its order's tender form on this till, whatever the lab toggle (a PIN-session
change, a restart or a reopened sheet included), with no way back and no set-aside until it is final or proven to have
no claim; it does not hold the order on another till. A final TEST result is out of sight with the lab off, except one
this sheet showed before it turned final, until the cashier leaves it. A TEST attempt in reconciliation covers its
order on this till until operator tooling exists (as D2)." The limits of this rule are D8 (§4.4).

### 4.4 Limits, for the owner (decision D8)

- Unreachable. The order's payment sheet is the only surface that shows a card attempt, and it opens only while the
  order is payable. If the order stops being payable — settled on another till or by another path, voided, or fully
  comped (a void or a full comp on this till never consults the card journal, and a TEST attempt claims no order on
  the server) — while this till holds an unresolved TEST attempt for it, that attempt is out of sight on this till:
  for good once the order is settled or voided (never shown or checked again, never set aside, never pruned); after a
  full comp, until the order becomes payable again (for example, items added to it), when the attempt covers its form
  again.
- Shown but never final. An operator-run purge removes expired TEST rows (older than 90 days) that are not under an
  incident hold. A TEST attempt in progress or with a confirmed cancel (it holds server facts) that is later answered
  `attempt_not_found` shows the note that the status could not be checked right now ("…try again") — a retry that cannot
  succeed — and can never become final there (an attempt this device saw cannot vanish): while its order is payable it
  keeps covering the order's tender form on this till with only Check status, Cancel on the terminal (while it waits)
  and "Close and resume later", as a reconciliation stop does (D2). One in reconciliation never becomes final either
  way. A TEST result not confirmed (no server facts) settles to "not found" instead and may then be set aside. The order
  can still be paid on another till, or voided or comped here, which takes the attempt out of sight as above.
- Records of either kind count toward the 200-record bound, which both modes share: about 200 of them on one device
  would refuse every integrated start on that till, LIVE included, with a sentence the cashier cannot act on in the
  app.
- Closing these needs a surface or rule outside this request's file scope — a till-level list of unresolved card
  attempts that does not need a payable order, operator tooling, or a per-mode bound. None is built here.

### 4.5 What the cashier reads (owner decision D9)

The restricted TEST surface reaches any cashier on the till, with the lab off, whenever a TEST attempt of a real
order is unresolved. For a TEST attempt that waits or has a confirmed cancel its sentences were written for the lab
operator (complete the test on the terminal; keep checking until the result is final), and a TEST result not
confirmed shows the LIVE sentence (do not charge again). None of these says that the order is held on this till until
the test is final, or how to get the order paid (a TEST attempt in reconciliation already says to ask a manager). A
closed sentence such as "This test holds this order on this till until its result is final. Ask a manager." would
need a second new l10n key; the request allows one, which the full-journal sentence uses (§5.3). With the lab off,
"Send the same request" also stays on a TEST attempt never sent or answered "sign in again": a tap sends nothing and
says card terminal payments are not available on this till, and "Cancel this request" or "Take payment another
way" is the way back. A pilot rule (no TEST attempt on a customer's order; an operator closes a test that stays
unresolved) avoids the state.

## 5. Correction B — the 200-record admission bound

### 5.1 Before (001F at `d7ce9990`)

`createIfAbsent` appended the new record first and then dropped the oldest prunable records while more than 200
remained; with none prunable the journal simply grew ("a bounded overshoot", which was no bound). The controller
minted the attempt id before asking the store, so an adopted start minted an id it then dropped.

### 5.2 After — `createIfAbsent`, inside the serial section of the storage key

1. Read the stored envelope; any quarantine (an unreadable envelope or entry, a foreign-scope entry, or a duplicate
   per §6) refuses the start as before (`ProviderCardCreateQuarantined`).
2. An open attempt of the same order and mode is adopted (`ProviderCardAdopted`): nothing is minted or written. This
   holds at the bound too, so a start never creates a second identity for an order that has an open one.
3. Prune: drop the oldest records that are safe and final — readable, of this scope, and terminal as §7.3 of the 001F
   packet defines it (a LIVE `freed` attempt included, which the server may still reclassify `orphan_approved`, §6) or
   recorded — until fewer than 200 remain.
4. Re-count. With 200 or more still retained, refuse with the closed result `ProviderCardCreateFull`: nothing is
   written, the caller's mint callback is never called (no identity is minted), and nothing is sent. The controller
   answers `ProviderCardStartRequest.journalFull` and the sheet shows its sentence (§5.3).
5. Otherwise mint inside the section, check the new record (its order, mode and scope, and that it reads back), append
   it and write. The identity is minted only once admission is certain: the controller passes the store a callback
   instead of a pre-built record, and an id that is not a lowercase UUID v4 answers `invalid` with nothing written.

- Never pruned: every open record other than a recorded one (not sent, sign in again, result not confirmed, not found,
  waiting, cancel requested, every approved state not recorded, recording refused, manager must send, resume refused,
  needs reconciliation including a provider anomaly), every unresolved TEST record (§4), and every unreadable or
  foreign entry (each of which already refuses new starts).
- `update` is never refused by the bound: status, the recording leg, the manager Resume, the reconciliation display
  and a final resolution keep working at 200. It keeps the 001F retention for a journal that is already above the
  bound.
- Capacity is not corruption: a distinct store result, a distinct start result and a distinct sentence; the journal
  stays readable and `quarantined` stays false.

### 5.3 The sentence

No existing sentence describes the condition accurately: "could not be saved … try again" invites a retry that cannot
succeed, the quarantine sentence says a record is unreadable, and "not available on this till" hides the cause. One
key is added in AR, HE and EN — `posCardJournalFullNote`, "This till's card terminal storage is full. Resolve the open
card terminal payments before starting a new one. No card was charged." — shown in the sheet's start-issue banner.

## 6. Correction C — envelope-level uniqueness

- On every read — `load`, and the re-read inside each `createIfAbsent` and `update` — the whole decoded envelope is
  validated before any record is exposed. It is rejected when:
  - two entries carry the same `attempt_id` string (every entry that is an object, readable or not, of any scope); or
  - two readable records are open (the `isOpen` predicate `createIfAbsent` adopts by, which counts a recorded attempt
    as open) with the same `identity_key` and `mode`.
- A rejected envelope is quarantined as a whole (`ProviderCardQuarantine('envelope', 'duplicate attempt_id')` or
  `('envelope', 'duplicate open attempt')`): no record is exposed (the controller selects none, so no first duplicate
  is chosen and no map entry overwrites another), every write is refused, so no duplicate can be updated and the raw
  stored value stays byte for byte as support evidence, and new integrated starts are blocked with the existing
  quarantine banner until it is resolved by a build that can read it or an operator procedure under its own
  authorization.
- Not checked: terminal rows that share order or amount facts, and an open LIVE and an open TEST attempt of one order
  (different modes).
- The store never writes an envelope it would itself reject (`PosPersistenceException`; the caller sends nothing), so
  a duplicate found on read is outside corruption, not this build's own write. One consequence, recorded for the owner
  (§10.3, F3): a late server answer that would reopen an older attempt beside a newer open or recorded one (a freed
  attempt turning `orphan_approved`) is not saved; no card view reaches such an attempt at this head.
- A valid envelope is untouched: the same encoding and the same bytes as 001F.

## 7. Preserved 001F behaviour (request §5)

Unchanged: the transport-kind mapping; the timeout and the never-retried `start`; the provider recording payload and
its `expected_revision` exception; ordinary tenders' PDR-003 `expected_revision`; status single flight; the manager
Resume authority; the same-device rules; `recorded` as the only "Paid" / receipt point; the terminal posture and the
legacy-card fail-closed policy; `providerProfile: null`; the Edge, SQL, migrations, configuration and CI. No order
action row or printing change. §10.5 lists the proof.

## 8. Tests, mutations and review

### 8.1 Required tests (request §7) → files

| Requirement | File |
|---|---|
| an unresolved TEST attempt recoverable with the lab off; PIN switch and restart keep its identity; test waiting / cancel confirmed / result not confirmed cannot be set aside; Check status uses the same attempt and sends no start; final TEST results may be hidden with the lab off; no TEST path creates `payment.create`, a receipt, revenue or "Paid" | controller, sheet, journal |
| 200 unresolved + a new start: typed refusal, zero journal append, zero Edge request; 199 unresolved + one safe final record: pruned and admitted; status and recovery at capacity; no second identity minted; nothing beyond the safe final set pruned | journal (store), controller, sheet |
| duplicate `attempt_id` and duplicate open identity + mode quarantine the envelope; no update of an arbitrary duplicate; the raw value preserved; new integrated starts blocked; a valid envelope byte-compatible | journal (store), controller, sheet |
| regressions: an uncertain start never sent again; a not-sent retry with the same identity and bytes; `recorded` the only Paid / receipt point; one `payment.create` without `expected_revision`; ordinary tenders keep `expected_revision`; Resume needs a current manager proof; an unmapped till's manual Card unchanged; a LIVE / unknown posture's manual Card held; `providerProfile` null | the existing 001F tests, run unchanged (controller, recording, sheet, static) |

### 8.2 Mutations

Each correction gets single-layer mutants, plus combined ones. A-ALL reverts every code change of correction A to the
001F behaviour, and C-ALL turns off both uses of the uniqueness check (read and write). B-ALL combines three B edits —
no bound, the controller minting before it asks the store, and open records made prunable (the last an injected
fault, not 001F behaviour) — and the other B layers keep single mutants of their own (B2, B3, B6 – B10). A-COVER
combines the two client layers that keep an open attempt in front of the tender form. The mutation list's own label
for B-ALL ("every layer off") and its docstring's "back to the 001F behaviour" claim more than B-ALL does; a note next
to the log in the evidence says so. Round 3 runs every round-2 mutant again at `0bd33261`, the commit with the tests
the fix-delta review asked for, plus that review's eight: the LIVE-first rule, the exits that let the order go, the
hand-recorded Card after a final TEST result and the resume-later label; its list labels B-ALL as what it is. The
mutants run in a scratch copy of the head; a mutant counts as killed only when it compiles and every named test
fails.

### 8.3 Checks and review

The focused card suites, the full POS suite, the l10n package suite, `tools/check_l10n.dart`, `dart format`, `dart
analyze` and the three CI source guards ran at the code head `2e04ec98`; the same checks, with the card suites only
inside the full POS suite, ran again at `bff0e3ec` (§10.2). The final head adds tests (`0bd33261`) and packet text; the
same checks run again once it is committed, and that run is recorded in the evidence, not in this packet. No database
suite runs (no SQL change). One focused fresh-context Claude delta review covered `d7ce9990..53d4e733`; after `bff0e3ec`
a second fresh-context review covered the fix delta `53d4e733..2e04ec98` (§10.3). Each finding above a nit of either
review was put to one adversarial verifier. No Codex review runs.

## 9. Gates still held

`providerProfile: null`; no provider, Z-Credit, terminal or card call; Q-047 and Q-049 untouched; no push, PR, merge,
hosted action, deployment, migration or configuration change.

## 10. Results

### 10.1 Commits and scope

| Commit | What |
|---|---|
| `9b6c9474` | this packet, before any executable change |
| `8c48018f` | A, B and C with their tests and the one l10n key (first form of A: going back to payment left the attempt open behind a banner) |
| `a775ef1f` | the dated notes in the 001F packet; this packet aligned |
| `53d4e733` | two sheet tests the round-1 mutation list needed |
| `2e04ec98` | delta review: an open TEST attempt covers its order with no way back (F1); a TEST result the sheet showed stays until left (F5); LIVE-side, mint-check and id tests (F2); a Resume-at-the-bound test (the review's not-checked list); the write-check test on a server-possible transition (F3) |
| `bff0e3ec` | the preamble, §1, §3 and §4 – §10 of this packet and the dated notes of the 001F packet brought in line with `2e04ec98` and with the accuracy check (§10.8); no executable change |
| `0bd33261` | the tests the fix-delta review asked for (FR-1, FR-3, FR-6); tests only |
| this commit | this packet and the 001F notes brought in line with the fix-delta review and the package check (§10.3); no executable change |

18 paths differ from `d7ce9990`, all in the request's §6 scope: the five library files and four test files of §3,
the three ARB files and four generated l10n files (one key each), and the two packets. No manifest, lockfile or
protected path changed.

### 10.2 Validation

| Check | Result (at the code head `2e04ec98` unless another head is named) |
|---|---|
| `dart format --set-exit-if-changed apps/pos packages/l10n`, `dart analyze apps/pos packages/l10n` | clean |
| `tools/check_l10n.dart`, the three CI source guards | clean |
| POS suite | 5,595 tests: 5,568 passed, 27 skipped, 0 failed (worktree porcelain 0 before and after the run) |
| l10n package suite | 95 of 95 passed |
| the six card suites | 172 tests, all passed (the baseline of the round-2 mutation run); 186 at `0bd33261` (the round-3 baseline) |
| mutation proofs | round 1 at `53d4e733`: 21 of 21 killed (its A mutants tested the first form of A, which `2e04ec98` replaced; its other mutants recur in rounds 2 and 3; kept as history); round 2 at `2e04ec98`: 26 of 26 killed; round 3 at `0bd33261`: 34 of 34 killed (the 26 again and the fix-delta review's eight) |

The full checks of `a775ef1f` are kept as an intermediate run only: two sheet tests were added to the worktree while
its POS suite ran (porcelain 0 → 1), so it is not counted for any head. The same checks at `bff0e3ec` (packet text
only on top of `2e04ec98`) gave the same results. The final head (the tests of `0bd33261` and packet text) will be
checked again after it is committed; that run is recorded in the evidence.

### 10.3 Review and dispositions

One fresh-context delta review of `d7ce9990..53d4e733`, then one adversarial verifier per finding above a nit. Six
findings:

- **F1** (MAJOR; verifier: confirmed, reachable). Going back to payment from an unresolved TEST attempt let the order
  be paid another way, after which no surface showed the attempt, which could not be set aside or pruned and held an
  admission slot. Fixed in `2e04ec98` (§4.2); the limits that remain are §4.4 (owner decision D8).
- **F2** (MINOR; confirmed). The LIVE side of the covering rule, the store's mint check and the `_InvalidMint` mapping
  were unpinned, and no combined mutant existed. Fixed: the two guards it probed no longer exist; tests and the mutants
  of §8.2 added. The review's not-checked list also named the manager Resume at the bound: a controller test and
  mutant B10 now cover it.
- **F3** (MINOR; refuted: not reachable, and the request's own rule). The write check refuses a server-possible
  reopening of an older attempt beside a newer open or recorded one. No code change; the test now uses that transition;
  recorded for the owner in §6 and below.
- **F4** (MINOR; confirmed in part). Packet claims about visibility and mutants. Fixed in this text (§4, and §8.2,
  which now says what B-ALL does).
- **F5** (NIT). A TEST result the sheet showed vanished when it turned final with the lab off. Fixed.
- **F6** (NIT). A TEST attempt in reconciliation covers its order's tender form on this till with no in-app
  resolution. Disclosed (D2 / D4 / D8).

After `bff0e3ec`, a fresh-context review of the fix delta `53d4e733..2e04ec98` (one reviewer, one verifier per
finding above a nit) found no defect in the money, recording or state logic; one confirmed usability gap in the TEST
surface's copy (FR-4); a reported behaviour defect it refuted (FR-2); and these test gaps:

- **FR-1** (MINOR; confirmed). No test paid the order after a card attempt let it go. Fixed in `0bd33261`: seven
  sheet tests complete a payment (TEST and LIVE, lab off and on, and the hand-recorded Card after a final TEST
  result); mutants FR1-M20b, FR1-M23, FR1-M24, FR1-M24b and FR1-M25.
- **FR-2** (MINOR; refuted). A quarantined journal hides the attempts it holds (all of them when the envelope itself is
  quarantined), and its banner shows only while the till's terminal binding is read as present. The verifier found this
  is the accepted 001F rule and the request's own (nothing is exposed before the envelope is valid), older than the fix
  and not producible by this build. No change; owner note in §10.6.
- **FR-3** (MINOR; confirmed). Nothing pinned that an open LIVE attempt is shown before a newer open TEST attempt of
  the order. Fixed in `0bd33261`: controller and sheet tests, including the one way this build reaches that pair (a
  LIVE answer that closed the attempt in memory but could not be saved — tested with a refused start — then the till
  read again as TEST, a TEST start in the lab, then a PIN switch); mutant FR3-M19.
- **FR-4** (MINOR; confirmed). On the restricted TEST surface no sentence tells an ordinary cashier that the order is
  held on this till until the test is final, or how to get it paid (§4.5). A sentence for it needs a second new l10n
  key, beyond the request's one; owner decision D9.
- **FR-5** (NIT). The sheet's `includeTest` expression acts as `true` in every state the sheet can reach. No change.
- **FR-6** (NIT). The resume-later label of the unresolved TEST rows was unpinned. Fixed in `0bd33261`; mutants
  FR6-M7 and FR6-M8.
- **FR-7** (NIT). §4.2 misstated when a refused TEST start shows with the lab off. Fixed in this text.
- **FR-8** (NIT). With the lab off, "Send the same request" stays on a TEST attempt never sent or answered "sign in
  again" and sends nothing. No change; disclosed in §4.5 (D9).

A read-only check of the review package and the draft delivery report (three checkers, one refuter per finding
above a nit) found the package intact and some statements overreaching. Those in this packet are corrected here:
the D8 cases (a comped order can become payable again; the purged-row case needs server facts), two rows of §10.4
and the wording about the agents' writes. The rest concerned the draft report, corrected before delivery, and the
text of two evidence tools.

The dispositions with their evidence are in the evidence folder (`review/REVIEW_DISPOSITIONS.md`).

### 10.4 Request-count evidence (exact counts the tests assert)

| Test (file) | Counts |
|---|---|
| "200 open records: a new start is refused typed — nothing minted, nothing written — and an open attempt of the same order is still adopted, minting nothing" (journal) | mint calls 0 (refused and adopted); stored bytes unchanged |
| "at the bound a start is refused typed — nothing minted, written or sent, no quarantine — and every stored attempt stays usable…" (controller) | refused: ids 0, Edge requests 0, bytes unchanged, no quarantine; then 1 status (asserted: waiting) and a second refusal; a second status (approved; not counted) records it with 1 recording push (`sync_push`), 0 starts, ids 1 (the leg target); then admitted: ids 2, 1 start, 200 retained, the recorded one gone |
| "at the bound an open attempt of the same order is adopted: no second identity, nothing sent" (controller) | ids 0, Edge requests 0, bytes unchanged |
| "199 open records and one safe final record: the final one makes room and the start goes ahead" (controller) | ids 1, 1 start, 200 retained, the final record gone |
| "at the bound the manager Resume of a refused recording still runs…" (controller) | ids 2, still 2 at the refusal; 2 legs pushed in all: the automatic first leg (refused), then the manager Resume's, with `recording_resume` 0 (resume count 1); then admitted: ids 3, 200 retained, the resumed attempt gone |
| "at the bound a card start is refused in words…" (sheet) | Edge requests 0, ids 0, bytes unchanged, no quarantine banner |
| "it stays the attempt shown with the lab off — after a PIN switch and a restart…" (controller) | 2 status requests for the same attempt, 1 start, ids 1 (+0 after the restart), 0 `payment.create` |
| "with the lab off after a PIN switch it covers every tender of its order…" (sheet) | 2 operator status checks for the same attempt, 1 start, ids 1, 0 legs, 0 ordinary pushes, 0 receipt fetches |
| "a TEST result not confirmed stays in sight after a restart…" (sheet) | 1 operator status check for the same attempt, 1 start, ids 0 after the restart, bytes unchanged |
| "a journal holding one attempt twice, or two open attempts of one order and mode, is quarantined whole…" (controller) and "a journal holding one attempt twice is quarantined in words…" (sheet) | Edge requests 0, ids 0, bytes unchanged |
| "an id source that gives no lowercase UUID v4 starts nothing…" (controller) | Edge requests 0, nothing written |
| the seven tests "once a card attempt lets the order go it is paid on this till…" (sheet) | each: the sheet resolves true with exactly 1 ordinary payment carrying `expected_revision` 7 (Confirm asserted live in the six cash cases); 0 card recording pushes (asserted in three of them); the TEST attempt never sent: 0 Edge requests and the closure stored `abandoned` |
| "an open LIVE attempt covers the form before a newer open TEST one…" (sheet, four cases) | 1 automatic status request, about the LIVE attempt; no TEST badge |

### 10.5 Preserved 001F behaviour — the proof

- Unchanged files (blob at `d7ce9990` = blob at the head, by `git diff`; the package builder asserts it again when it
  builds the package): the presentation, Edge client, recording leg and capability files, `staff_capabilities.dart`,
  the edge-mapping, recording and static tests, the base payment kernel, the order action row and #314's tests,
  `packages/printing` (and every guarded tree of the builder), the 001C transport, the Edge sources, CI and Supabase
  settings, every manifest and the lockfile.
- The regression tests of request §7, unchanged and passing at `2e04ec98` and `bff0e3ec`: "uncertain: start is NEVER
  sent again — not by retry, not by a new start, not after a restart; only status resolves it"; "notSent: the SAME
  request may be re-sent explicitly; nothing is minted"; "approved → ONE canonical payment.create, alone, without
  expected_revision → recorded; the provider is not called"; "ordinary tenders keep PDR-003: the base record still sends
  expected_revision…"; "a recoverable refusal is reported, then a MANAGER resumes the SAME leg…"; "a row a Resume
  reopened answers a cashier resume_authority_required; only a manager sends it"; "start → waiting (no other tender) →
  approved → recorded ONCE without expected_revision → Done resolves TRUE; one receipt"; "an approval is never "Paid"…";
  "no terminal binding: the RF-117 tenders and the hand-recorded Card are unchanged…"; "posture unknown…", "the send
  reads it again…" and "posture still unknown after the re-read…"; "the Edge still ships with no provider profile".
- `index.ts` line 19 still reads `providerProfile: null,` (blob `7a3c5c97` at the base and the head).
- The postflight runs after this text is committed and is kept in the evidence (`postflight/POSTFLIGHT.txt`): it
  checks that the 001F branch and every earlier payment branch are at their preflight heads, that #370 / #371 / #314 /
  #315 are unchanged on the remote, that no remote ref or PR exists for this Work ID, and that the main checkout has no
  tracked change.

### 10.6 Owner decision points

- **D4**, corrected (§4.3).
- **D8**, new (§4.4): (1) an unresolved TEST record no surface can reach — its order settled on another till or by
  another path, or voided (for good), or fully comped (until the order becomes payable again, for example when items are
  added); (2) a TEST record that holds server facts and whose server row an operator purge removed stays shown while its
  order is payable but can never become final, so it holds that order's tender form on this till with no in-app
  resolution, as D2 does. Both stay in the journal and count toward the shared bound; a till-level recovery list,
  operator tooling or a per-mode bound would close them, outside this request's file scope.
- **D9**, new (§4.5): on the restricted TEST surface no sentence tells an ordinary cashier that the order is held on
  this till until the test is final, or how to get it paid; a closed sentence for it needs a second new l10n key, which
  the request does not allow. Owner call: approve the key, or adopt the pilot rule of §4.5.
- Quarantine (001F §5.3, now also for duplicate identities, §6, and R7d, §4.2): an envelope-level quarantine (an
  unreadable envelope, or a duplicate identity) exposes no record; a record-level one (an unreadable or foreign entry,
  or an R7d record) hides only that record. An unresolved TEST attempt hidden this way does not cover its order (for
  a LIVE attempt the server's claim guard, API_CONTRACT §4.55.3, still refuses other tenders), and the quarantine
  banner shows only while the till's terminal binding is read as present. Unchanged here, as the request orders
  (nothing is exposed before the envelope is valid).
- **D2**, restated for TEST: a TEST attempt in reconciliation covers its order's tender form on this till with no
  in-app resolution; it claims no order, so the order can still be paid on another till, or voided here (out of sight
  for good) or comped here (out of sight until the order becomes payable again, when it covers the form again) — D8,
  case 1.
- For a future surface over attempts that are not current (F3): decide whether a recorded attempt counts as open for
  envelope uniqueness, and how adoption chooses between a recorded and a reconciliation attempt of one order.

### 10.7 Not validated

- No device, web or emulator run: widget and unit tests only. No real Edge, provider, terminal or card.
- The server facts behind §4.4 and F3 (the 90-day TEST purge, a freed attempt turning `orphan_approved`) were read
  from the 001D migration by the reviewers, not run (no database suite).
- The AR / HE sentence and the existing strings it sits beside were checked for presence and direction, not by a
  native speaker.

### 10.8 Disclosures

- The full checks of `a775ef1f` picked up two sheet tests added to the worktree during the run; they are kept as an
  intermediate run only (§10.2).
- Per their own reports, the delta review's agents wrote only under their own scratch directories. Measured after
  they returned: no porcelain line in the correction worktree or the 001F worktree, no tracked change in the main
  checkout, and only the brief in the evidence folder's `review/`. Other checkouts were not measured right after; the
  postflight of 10:57Z later found the 15 other payment worktrees clean.
- Before `bff0e3ec`, an accuracy check of this packet, the dated notes of the 001F packet and the review
  dispositions (two fresh-context checkers, one adversarial verifier per finding above a nit) found statements that
  claimed more than the code, tests or logs show — among them the B-ALL description, the D8 cases, the review's range
  and checks described before they ran. It was not a code review, and none of its findings needed a code change;
  `bff0e3ec` corrects the text. Per their own reports, its agents wrote only under the session's scratch directory.
  Measured after they returned: the worktree diff hash unchanged, no tracked change in the main checkout, and
  `review/` still holding its three files. Its result is kept in the evidence
  (`review/ACCURACY_CHECK_WORKFLOW_RESULT.json`).
- After `bff0e3ec`, the fix-delta review (one reviewer, four verifiers) and the package-and-report check (three
  checkers, five refuters) ran read-only. Per their own reports their agents wrote only to scratch (besides the tool
  harness's own task logs and the Flutter tool's caches), except one that created a small file in the user's
  temporary folder by a stray shell redirect and deleted it at once (it said so itself; the file no longer exists).
  Measured after both returned (recorded in the review dispositions, §6): no porcelain line in the correction
  worktree at `bff0e3ec` (before the next edit); later the 001F worktree clean, no tracked change in the main
  checkout, and no evidence file changed except those this ticket had edited. Both results are kept in the evidence
  (`review/FIX_DELTA_REVIEW_WORKFLOW_RESULT.json`, `review/PACKAGE_AND_REPORT_CHECK_WORKFLOW_RESULT.json`).
- Before the final head, a read-only check of the round-4 text (two checkers, one refuter per finding above a nit)
  found eleven confirmed overstatements and twenty-three NITs in this packet, the 001F note, the dispositions and
  the evidence notes and tools; none needed a code change, and the final head and the evidence correct them
  (dispositions §8; `review/ROUND4_TEXT_CHECK_WORKFLOW_RESULT.json`). One of its refuters ran `flutter test`
  without `--no-pub` in its scratch copy: the automatic `pub get` read version listings from pub.dev and rewrote two
  files in the pub cache (it reported this itself). No repository file, lockfile or evidence file changed: replaying
  this ticket's own edits reproduces the docs as they stood after the check, and the evidence files matched what
  this ticket had written.
