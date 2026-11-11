# BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-INBOUND-MONEY-NORMALIZATION-001 — execution packet: inbound provider money with zero, one or two fraction digits, canonicalized to the two-decimal lexeme (D-064)

Work ID: `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-INBOUND-MONEY-NORMALIZATION-001` (a ticket of the umbrella
[BIZBOT-PAYMENTS-ZCREDIT-PILOT-001](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001.md)).
Controlling contract: [API_CONTRACT](API_CONTRACT.md) §4.55.4 and §4.55.5 as amended by **D-064**. The adapter is
described by [the 001E execution packet](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_EXECUTION.md) (§6 engine, §8 money), its
dropped-field evidence by [the G1 packet](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_DROP_EVIDENCE_001_EXECUTION.md) and its
lookup precedence by [the W1-LOOKUP-SAFETY-001 packet](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_W1_LOOKUP_SAFETY_001_EXECUTION.md).
This packet records **DECISION D-064**; it adds no **OPEN QUESTION** and allocates no other ID.

## 1. Authorization and boundary

- Command-room authorization of 2026-10-28, "BOUNDED INBOUND MONEY NORMALIZATION": verdict
  ACCEPT_W1_EVIDENCE_PACKAGE_AND_AUTHORIZE_INBOUND_NORMALIZATION / PROVIDER_PROFILE_REMAINS_UNWIRED, on the accepted
  W1 head `140be040fafb3f21f6af3cacfa8b8d81db251246` (tree `cbfda1f5bfa31667d102593d1bfedd595fb35cea`) and the
  reviewed W1 wire-evidence package `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-W1-EVIDENCE-001-sanitized-review-package.zip`
  (SHA-256 `634d379478a0cd3f90a974f1ec96960031fab4d7fe07b90cc8dcec4744e5f004`). The instruction is kept outside Git
  with a SHA-256 sidecar (`e6a1ae0e2a31700130e5f813fbe2dc05ebf0f8840fcd243885517f5ce9a9bf7b`).
- A bounded contract-and-adapter correction: the inbound provider-money grammar and its canonicalization (**D-064**,
  §3). It does not authorize building or wiring a real provider profile or contacting the provider; `index.ts` keeps
  `providerProfile: null`.
- Allowed files: `lib/money.mjs`, `lib/provider/engine.mjs`, the function-local tests (one new focused file),
  API_CONTRACT, MONEY_AND_TAX_SPEC, DECISIONS, the 001E packet, dated factual notes in the W1 and G1 packets, and this
  packet. Not changed: the provider wiring of `index.ts`, `config.toml`, CI, any migration or SQL test, the 001D / G1
  function definitions, RPC signatures, grants, RLS and tables, POS, transport, Dashboard, l10n, printing and release
  files, #370, #371 and every vendor evidence artifact.
- Process: no push, PR, merge, hosted change, deployment, secret read or write, provider request, vendor inquiry,
  terminal or card action, printer or APK action; no amend, rebase, reset or history rewrite; no Codex review; one
  fresh-context Claude delta review (§11); no background monitor.
- Branch `fix/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-INBOUND-MONEY-NORMALIZATION-001-inbound-provider-money`, created at
  the W1 head in its own worktree, stacked on the unmerged W1 (`140be040`), G1 (`295cacb6`), 001E (`d5456624`) and
  #370 (`54b19ab5`) heads; local only.

## 2. Source anchor (preflight 2026-10-28T15:11:00Z, read-only)

| Item | Value |
|---|---|
| W1 head / tree | `140be040…` / `cbfda1f5…`; the W1 worktree is clean with no upstream; the new branch points at the W1 head with no commit on top before this packet |
| G1, 001E | `295cacb6c50226da9cba99e769fac0680ee14fcc`, `d545662476cea8cfae41729b15034dc713e10a19`; both worktrees clean |
| main | `origin/main` = `01d0098b3efd2909f0ce3a96ff19a54c45aa69e2` (`git ls-remote`; unchanged since the W1 tickets); merge base with this branch `d2079820`; the 4 main commits since it change 28 files, none in this ticket's file scope and none under `supabase/functions/pos-card-charge/` |
| #370 / #371 | OPEN drafts at `54b19ab58ce72a2fa9a43860e31181a08222b254` / `53d6a6adc38f308b7ed6b0dd62177e6edd5ad5ce` |
| Ownership | `lib/money.mjs`, `lib/provider/engine.mjs` and the three 001E-stack packets exist only on this stack (not on main, #370 or #371); API_CONTRACT, MONEY_AND_TAX_SPEC and DECISIONS own their topics ([CLAUDE.md](../CLAUDE.md) §2) and are unchanged on main since the merge base; no PR or remote ref names this Work ID |
| Decision IDs | the highest `## DECISION` header is D-063 on `140be040`, D-058 on `01d0098b`, D-060 on #370 and D-061 on #371; no local or remote-tracking ref carries a D-064 header, so **D-064** is the verified next free ID; the next free question ID stays **Q-058** |
| Node suite at the base | 143 / 143 on Node 22.14.0 and on Node 24.19.0 |

## 3. The contract delta (DECISION D-064)

### 3.1 Two money boundaries

- **Outbound provider amount — unchanged.** `amountToken(minor)` is `new JsonNumber(lexemeFromMinor(minor))`: `BigInt`
  division and modulo of the integer minor amount, the canonical lexeme `^(0|[1-9][0-9]{0,8})\.[0-9]{2}$`, an unquoted
  JSON number token in the request bytes. `AMOUNT_LEXEME`, `lexemeFromMinor`, `amountToken`, `minorFromLexeme` and
  `minorFromToken` keep their code (the doc comments of `AMOUNT_LEXEME` and `minorFromLexeme` now name the canonical
  lexeme).
- **Inbound provider money — new.** Only the two amount-kind reply keys, `provider_amount` and `tip_amount`, go through
  one helper in `lib/money.mjs`; no other reply kind and no other JSON reader changes.

### 3.2 The exact grammar and canonicalization

- Input: a `JsonNumber` — a raw JSON number token kept as its exact text by the strict parser of `lib/json.mjs` — and
  nothing else: a JavaScript string, number or `BigInt`, `null`, a boolean, an array or a plain object is refused.
- Token grammar (`INBOUND_MONEY_TOKEN`): `^(0|[1-9][0-9]{0,8})(?:\.([0-9]{1,2}))?$` — no sign, no exponent, one to nine
  integer digits with JSON's leading-zero rule, and zero, one or two fraction digits.
- Canonical form: the integer part, a point, and the fraction right-padded with `0` to two digits; the result always
  matches `AMOUNT_LEXEME` (checked before it is returned). Text only: no `Number`, `parseFloat`, floating-point
  arithmetic, rounding, truncation or locale formatting. The bound is the existing one — at most `999999999.99`, which
  is `MAX_MINOR` (99 999 999 999 minor units) — and zero is readable.
- The reply reader returns the canonical text as the field's value; a refused value yields the **D-062** token
  `{field, rule: "format"}` and nothing else. A missing key, a JSON `null` or a blank string stays absent (**D-058**
  point 10, unchanged).
- The wire-profile schema accepts only `number` for the two amount keys; a profile listing `string` for either is a
  `ProfileError` before any request.
- SQL is unchanged: `app.card_attempt_finish` still requires a JSON string matching `^(0|[1-9][0-9]{0,8})\.[0-9]{2}$`,
  converts it with `split_part(v_text, '.', 1)::bigint * 100 + split_part(v_text, '.', 2)::bigint` and compares with
  strict equality (the G1 migration `20261027211023_bizbot_zcredit_001e_drop_evidence_001.sql`, lines 168-169 and
  207-210).

### 3.3 Accepted and refused inbound values

| Inbound value | Result | Reason |
|---|---|---|
| `0`, `0.0`, `0.00` | `0.00` | zero in every accepted form |
| `12`, `12.0`, `12.00` | `12.00` | a whole shekel |
| `12.3`, `12.30` | `12.30` | an `x.x0` echo |
| `10.35` | `10.35` | the documented example (W1 evidence E2-26) |
| `0.5`, `0.05` | `0.50`, `0.05` | |
| `999999999`, `999999999.9`, `999999999.99` | `999999999.00`, `999999999.90`, `999999999.99` | the bound |
| `12.345`, `12.300`, `0.000` | refused | a third fraction digit, even a zero (never rounded or truncated) |
| `1e2`, `1E2`, `1e-2`, `0e0`, `12.3e0` | refused | an exponent |
| `-12`, `-0`, `-0.00` | refused | a sign |
| `1000000000`, `1000000000.00`, `9999999999.99` | refused | over the bound (ten integer digits) |
| `01`, `00`, `012.34`, `12.`, `.30`, `+12` | refused | not JSON number tokens: the strict parser refuses the whole reply, and the grammar refuses the text as well |
| `"12"`, `"12.30"`, `"0.00"` | refused | a JSON string instead of a number (a blank string stays absent) |
| `true`, `{}`, `[]` | refused | another JSON type |

### 3.4 Classification consequences (synthetic profile)

The W1-head column is the output of the evidence probe `tools/probe_inbound_money.mjs` on `140be040` (extracted with
`git archive`); the D-064 column is the specification, checked by the same probe after the implementation (§8).
"Approved by the adapter" means the adapter finishes with `p_outcome: "approved"`; the attempt becomes `approved` only
if SQL's unchanged checks agree (amount and currency exact, no tip) — otherwise SQL records `amount_mismatch` or
`currency_mismatch`.

Commit replies with error flag `false`, return code `0` and an approved type unless stated:

| Reply | W1 head `140be040` | D-064 |
|---|---|---|
| tip absent, `null` or blank | approved | approved (unchanged) |
| tip `0` or `0.0` | `out_of_contract` (tip `format`) | approved; the finish gets `tip_amount: "0.00"` |
| tip `0.00` (number) | approved | approved (unchanged) |
| tip `5` or `5.0` | `out_of_contract` | `amount_mismatch` (class `approved`); `tip_amount: "5.00"` |
| tip `5.00` or `0.01` (number) | `amount_mismatch` | `amount_mismatch` (unchanged) |
| tip `0.000`, `1e0`, `-0` or `1000000000` | `out_of_contract` | `out_of_contract` (unchanged) |
| tip `"0.00"` / `"5.00"` (string) | approved / `amount_mismatch` | `out_of_contract` (tip `format`) |
| declined type + tip `0` or `5` | `out_of_contract` | declined |
| declined type + tip `5.00` (number) | declined | declined (unchanged) |
| declined type + tip `0.000` | `out_of_contract` | `out_of_contract` (unchanged: an unreadable tip is decided first) |
| declined type + tip `"0.00"` (string) | declined | `out_of_contract` |
| amount echo `12` | UNKNOWN (amount `format`) | approved by the adapter; SQL compares `12.00` with the attempt |
| amount echo `"12.00"` (string) | approved by the adapter | UNKNOWN (amount `format`) |
| phone flag, duplicate code `-901`, error flag or a non-success code, beside an approved type + tip `5` | `out_of_contract` (tip `format`) | UNKNOWN with its class (`phone_authorization`, `duplicate`, `error`, `unclassified`) and `tip_amount: "5.00"`: the tip rule applies to an otherwise approvable reply only |

Lookup replies with status `S1` (approved) and currency ILS unless stated:

| Reply | W1 head `140be040` | D-064 |
|---|---|---|
| amount `12` or `12.0` | `out_of_contract` | approved by the adapter with `"12.00"` |
| amount `12.3` | `out_of_contract` | approved by the adapter with `"12.30"` |
| amount `12.00`, `12.30`, `10.35` or `999999999.99` | approved by the adapter | unchanged |
| amount `999999999.9` | `out_of_contract` | approved by the adapter with `"999999999.90"` |
| amount `0` | `out_of_contract` | approved by the adapter with `"0.00"`; SQL: `amount_mismatch` against a positive attempt |
| amount `1000000000`, `12.345`, `12.300`, `1e2` or `-12` | `out_of_contract` | `out_of_contract` (unchanged) |
| amount `"12.34"` (string) | approved by the adapter | `out_of_contract` (amount `format`) |
| amount `12` + tip `0` | `out_of_contract` | approved by the adapter with `"12.00"` and `tip_amount: "0.00"` |
| a not-found or pending return code + amount `12.3`, `12` or `12.345` | not found / pending | unchanged (a readable amount is now forwarded, a failing one only dropped) |
| an unlisted status + amount `12` | `out_of_contract` | `out_of_contract` (unchanged, **D-063**) |
| no status + amount `12` | `out_of_contract` | `out_of_contract` (unchanged: a readable amount reports a transaction) |
| no status + a declined type + amount `12.3` | `out_of_contract` (amount `format`) | declined (no essential field fails any more) |
| amount `12` + tip `5` | `out_of_contract` | approved by the adapter with `"12.00"` and `tip_amount: "5.00"`; SQL: `amount_mismatch` (its lookup tip check, FR-107) |
| no status + a declined type + tip `5` | `out_of_contract` (tip `format`) | declined, the tip forwarded |
| no status + a tip `5` alone | `out_of_contract` (tip `format`) | failed — no provider fact, as a two-decimal tip alone already was at the W1 head |
| a void or refund status + tip `5` or amount `12` | `out_of_contract` | the status's own anomaly (`voided`, `refunded`), the value forwarded |

Every lookup change above makes an integer or one-decimal value behave as its two-decimal form already did under the
**D-063** rules; none comes from a changed rule. Per the W1 evidence (row E2-25, FACT) the vendor's status reply
carries neither an approval type nor a tip, so the declined and tip rows are not reachable with the documented replies.

Release replies (error flag `false`, return code `0`) go through the same reader; a release finish carries only the
**D-062** evidence, never a value:

| Reply | W1 head `140be040` | D-064 |
|---|---|---|
| amount `12` + tip `0` | released, two `format` tokens | released, no token |
| amount `"12.34"` (string) | released, no token | released, the `provider_amount` `format` token |
| tip `0.000` | released, the `tip_amount` `format` token | unchanged |

### 3.5 Unchanged

The outbound lexeme and bytes; SQL, migrations, signatures, grants, RLS and tables; the commit order (an unreadable tip
first, then any other failing essential field, the phone flag, a duplicate, a decline, an approval), the lookup
precedence of **D-063** and the release rule; the currency rules (ILS only, the `currency_reply` mapping); the **D-062**
evidence shape (one `{field, rule}` token per failing field, never a value); the absent rule of **D-058** point 10;
`index.ts` (`providerProfile: null`); `config.toml` and CI.

## 4. Exact files

| File | Change |
|---|---|
| `supabase/functions/pos-card-charge/lib/money.mjs` | `INBOUND_MONEY_TOKEN` and `canonicalInboundMoney(value)`; comments; nothing else |
| `supabase/functions/pos-card-charge/lib/provider/engine.mjs` | the `amount` case of the reply reader calls `canonicalInboundMoney`; `ACCEPT.amount` is `["number"]`; the unused `AMOUNT_LEXEME` import is dropped; comments |
| `supabase/functions/pos-card-charge/test/inbound_money.test.mjs` | new: the D-064 cases of §5 |
| `supabase/functions/pos-card-charge/test/fixtures.mjs` | the synthetic profile's two amount keys accept `number`; `numberToken()` writes an exact raw token |
| `test/drop_evidence.test.mjs`, `lookup_status_policy.test.mjs`, `provider.test.mjs`, `start.test.mjs`, `status.test.mjs`, `money.test.mjs` | only the expectations **D-064** changes: JSON-string amounts and tips that stood for readable values become number tokens; the `status.test.mjs` inbound grammar test is rewritten to the D-064 grammar; the `money.test.mjs` grammar test's title names the canonical lexeme |
| `docs/DECISIONS.md` | **D-064** and its changelog line; a dated note on **D-052** point 4 |
| `docs/API_CONTRACT.md` | §4.55.4 (the zero tip), §4.55.5 (inbound provider money) |
| `docs/MONEY_AND_TAX_SPEC.md` | §1 item 6 |
| `docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_EXECUTION.md` | dated notes in §6 (item 4), §8, §10 and §13 |
| the W1 and G1 packets | dated factual notes on E5 and the W1 gate only |
| this packet | new |

The function's own `CONTRACT.md` is not in the allowed file list, so its "Money and replies" paragraph kept the former
inbound grammar (residual R1, §10, since resolved by the documentation-consistency commit `f7d5be5d`).

## 5. Test plan (fake transports only)

New `test/inbound_money.test.mjs`, with literal expectations (the engine's own reader is never its oracle):

1. Direct: every accepted token gives its literal canonical text; every refused `JsonNumber` gives `null`; the texts
   that are not JSON number tokens (`01`, `12.`, `.30`, `+12` …) are refused by the `JsonNumber` constructor, by
   `parseJson` inside a reply and by `INBOUND_MONEY_TOKEN`; strings, JavaScript numbers, `BigInt`, `null`,
   `undefined`, booleans, arrays and plain objects are refused; the bound (`999999999.99` read, ten integer digits
   refused).
2. Parity: every canonical output matches `AMOUNT_LEXEME` and the finish rule read from the G1 migration text, and
   converts with `minorFromLexeme` (`BigInt`) to its literal minor amount.
3. Commit, through the handler with the fake PostgREST and the fake provider and raw reply bytes: a tip absent, `null`,
   `0`, `0.0` or `0.00` approves with the exact finish fields; a readable non-zero tip is `amount_mismatch`; a
   malformed tip is `out_of_contract` with exactly `dropped_fields: [{field: "tip_amount", rule: "format"}]`; declined
   replies keep their outcome; exactly one commit call and no lookup.
4. Lookup, through the handler: `12`, `12.0` and `12.00` for a 1200 attempt and `12.3` and `12.30` for a 1230 attempt
   finish `approved` with `provider_amount` `"12.00"` / `"12.30"`; a different amount and zero reach the finish as
   canonical text for SQL's `amount_mismatch`; malformed and over-precise amounts are `out_of_contract` with the
   `format` token; the **D-063** precedence is unchanged; exactly one lookup and no commit.
5. No refused token reaches an RPC argument or the POS answer: no `provider_amount` / `tip_amount` key carries it, and
   every refused token of four or more characters that contains a digit is searched for in the raw request bodies and
   the answer.
6. Outbound bytes: the whole commit request body for 0.01, 1.00, 12.34, 50.00, 25 000.00 and 999 999 999.99 equals a
   literal byte string.
7. Profile schema: a `string` accept on either amount key is refused.
8. Static: the reader's amount case calls `canonicalInboundMoney`; the outbound helpers keep their exact text; the
   existing float-free and `providerProfile: null` guards still pass.
9. Added after the fresh-context review (§11): a readable tip on a commit reply that is not otherwise approvable (phone,
   duplicate, error flag, a non-success code, an unknown or absent type) stays UNKNOWN; a readable non-zero tip on a
   found lookup reaches the finish; the lookup tip consequences of §3.4; release replies; and a static pin of the whole
   `canonicalInboundMoney` body and `INBOUND_MONEY_TOKEN`, with `JSON.parse`, `globalThis` and `eval` refused in
   `lib/money.mjs`.

Also: the full function-local suite on Node 22.14 and 24.19, a RED run of the branch's test files against the W1 head's sources,
focused mutations of the helper and the reader (`tools/mutate_inbound.py`), and a differential of the W1 head and this
branch over a generated token corpus (`tools/differential_inbound.mjs`) — evidence tools kept outside Git.

## 6. SQL: the existing finish contract (no change)

SQL already accepts and checks only the canonical lexeme, which is exactly what **D-064** forwards. The existing pgTAP
evidence (unchanged SQL, not re-run here): FR-74 (`bizbot_zcredit_001d_field_rules_test.sql`) approves a commit whose
`tip_amount` is `"0.00"`; FR-83 and FR-107 make a non-zero tip `amount_mismatch` on a commit and a lookup; FR-95 and
FR-104 make a different amount `amount_mismatch`; FR-102 approves a lookup with the exact amount and currency; FR-124
refuses a JSON-number amount, a leading zero and ten integer digits with `format` and reads `"999999999.99"`. These ran
in the G1 package, whose full local pgTAP command ended `Result: FAIL` / `exit=1` only because the two CI-only
storefront files refuse a non-CI database (the known local execution limitation; their guards were not bypassed).

## 7. W1 evidence disposition

- The command room accepted the W1 evidence package and selected the bounded normalization route — route (2) of its
  GAPS_AND_GATES §1 — rather than requiring the first physical TEST to prove insignificant JSON-number formatting.
- Closed (representation only): E2-30 / E2-31 — a zero `TipAmount` (an integer `0`, or `0.0` / `0.00`) is zero, and an
  absent one is no tip; E5-03 / E2-26 — a `TransactionSum` with zero, one or two fraction digits is read exactly.
- The package's two NOT_READY cells (commit `reply.tip_amount`, lookup `reply.provider_amount`) were representation
  cells and are resolved in the adapter. Not closed: **Q-047** (the TEST URL, the credentials, the KEY's purpose, the
  PIN-pad identifier and the terminal binding), **Q-049** (the keys' encoding, length and character set, the duplicate
  window), E2-B / **Q-048** / **Q-050**, the not-found and pending semantics, and every provider, runtime, hosted and
  physical validation. No operation's profile is built, wired or declared ready.

## 8. Results (local; the executable code is that of `291f335c` and the tests those of `7bd95d3c`; later commits change documentation and one code comment only)

The logs and tools named here are in the evidence folder outside Git
(`evidence/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-INBOUND-MONEY-NORMALIZATION-001-20261028/`).

| Item | Result |
|---|---|
| Commits | `f6680fec` documentation before code (**D-064**, the contract, this packet's sections 1-7, 9 and 10); `291f335c` the fix and its tests; `7bd95d3c` the review's test findings (tests only); `741e55d3` the results, the review and its dispositions (this packet and the **D-064** consequences line of DECISIONS); `f7d5be5d` the documentation-consistency fix (the function's `CONTRACT.md`, the comment above `TWO_DECIMAL_CURRENCIES` in `lib/provider/engine.mjs` and the inbound vectors of `docs/TESTING_STRATEGY.md`); then the status closeout, which changes only this packet |
| Node suite | 158 / 158 on Node 22.14.0 and on Node 24.19.0 at `7bd95d3c` (155 at `291f335c`, 143 at the base); `inbound_money.test.mjs` holds 15 tests; no existing test was removed |
| RED | the branch's 16 test files against the W1 head's function sources (`tools/red_on_w1_head.py`; for that run only, the new file's named money import becomes a namespace import): 14 of 158 fail — 13 of the 15 new tests and the rewritten status test. The outbound-bytes test passes on both sides (the bytes did not change), and so does the malformed-lookup test, because the branch's synthetic profile already lists only `number`, which the W1 engine honours too |
| Mutations | `tools/mutate_inbound.py` at `7bd95d3c`, 26 mutations, each against the whole suite: 26 killed. N11 (the `AMOUNT_LEXEME` self-check removed) and N15 (the accept-list check removed) are behaviourally equivalent and killed only by static pins. The preserved 001E mutations that concern amounts and tips (M04, M19, M25, M27, M70) are killed |
| Review mutants | `tools/mutate_review_compare.py`, the reviewers' 18 mutants (§11): at `291f335c` 13 survive the whole suite (TE-1 R09, R10; F1 R09, R12, RP, RH, RA; TE-2 R17, R17c; TE-3 R01, R02, R03, R05) and `status.test.mjs` alone misses TE-4's R15 and P1; the control R08 is killed. At `7bd95d3c` all 18 are killed, and `status.test.mjs` alone kills all four TE-4 mutants |
| Differential | `tools/differential_inbound.mjs`, the W1 head against `7bd95d3c`, on Node 22.14 and 24.19: `amountToken` identical for 600 000 amounts (1 .. 200 000, the last 200 000 below the bound, 200 000 sampled); 2 011 whole commit request bodies byte-identical; 7 040 inbound values (1 760 texts × number / string × amount / tip) in exactly the D-064 classes — 126 two-decimal number tokens read identically by both, 126 strings read by the W1 head and refused now, 90 zero- or one-decimal number tokens refused by the W1 head and read now (the only difference when both engines get the same number-only profile), 6 698 refused by both; 0 mismatches |
| What the finish receives | `tools/finish_sweep.mjs` at `7bd95d3c`: 1 760 values (72 accepted, 1 688 refused) as the commit tip and as the lookup amount and tip, LIVE and TEST, through the handler; in 10 560 finish fields every forwarded amount or tip is a canonical `X.XX` JSON string equal to the D-064 value, and every refused one is only its `{field, rule: "format"}` token |
| Classification | `tools/probe_inbound_money.mjs` on the W1 head and on `7bd95d3c`: 60 cases, 35 changed, line by line the §3.4 tables (`logs/PROBE_BEFORE_AFTER.txt`) |
| Scope | through `741e55d3` the changed paths are exactly §4's; `index.ts`, `handler.mjs`, `lib/json.mjs`, `config.toml`, the CI file and both payment migrations keep the base's blob ids; nothing under `supabase/migrations` or `supabase/tests` changed; `CONTRACT.md` kept the base's blob id until `f7d5be5d`, which changed only its three authorized files, and the status closeout changes only this packet; `providerProfile: null` |
| SQL (unchanged, not re-run) | the executed vectors of the accepted 001D / G1 pgTAP lanes: FR-74 approves a commit with tip `"0.00"`; TI-59 approves a lookup whose amount `"50.00"` equals a 5000 attempt; FR-104 and FR-107 make another amount and a non-zero lookup tip `amount_mismatch`; FR-124 refuses a JSON-number amount. No executed vector uses an `x.x0` lexeme such as `"12.30"` or a zero amount `"0.00"`: their handling is the same `split_part` integer conversion, shown by the parity test and by reading the migration |
| Line endings | every committed blob is LF; the evidence package carries the exact blob bytes and lists, apart, the CRLF working-tree hashes of this host |
| Acceptance and final head (local) | The command room's final source verdict of 2026-10-28 (ACCEPT_LOCAL_D064_SOURCE_AND_FAKE_TESTS) accepted the source and the fake tests at `741e55d3677f48c5dbd534308814ca5748883cf8` (tree `3153412a26d945d0767c6a531daedf836bbeab45`; review package SHA-256 `b9464ca8222960c25bb1d9a4d78b60936807402c185788f2f7a849b193b6b44c`; by its own report, its re-run passed 158 / 158 on Linux with Node 22.16.0). Its final packet status closeout (2026-10-28 UTC) accepted the documentation-consistency commit `f7d5be5d80bfd1e454a44420a70bc4317e4f5b82` (tree `23bb6a2e4287017c48f5a6638f3d3ec9b30f95aa`; its local delta record `evidence/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-INBOUND-MONEY-NORMALIZATION-001-DOCS-CONSISTENCY-20261028/` shows 158 / 158 on Node 22.14.0 and 24.19.0 and an `engine.mjs` change that is comment-only, with identical executable tokens and syntax trees) and confirmed F3 (§10). The final local head is the status-closeout commit on `f7d5be5d`: it changes only this packet, every other file is byte-identical to `f7d5be5d`, and no suite was re-run for it. A commit cannot contain its own id, so that id is recorded outside Git (`evidence/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-INBOUND-MONEY-NORMALIZATION-001-STATUS-CLOSEOUT-20261028/`). The branch is local only: no upstream, push, PR, merge or deployment. No provider request was made and no provider compatibility is claimed (§9); `providerProfile` stays `null`; **Q-047** and **Q-049** stay open (§10) |

## 9. NOT VALIDATED here

- PostgreSQL: no pgTAP lane runs for this ticket; SQL and every migration are unchanged, and §6 cites the accepted
  001D / G1 evidence.
- Deno and the Supabase Edge runtime: not installed, and nothing is installed or upgraded.
- The provider: no request. The synthetic profile proves no vendor fact; whether the vendor ever sends a JSON string, a
  third (zero) fraction digit or another number form is not known, and each stays a fail-closed `format` failure.
- The unit of a non-zero `TipAmount` is not inferred (any readable non-zero value only blocks approval).
- Hosted behaviour, Linux CI (no CI run exists for this branch) and any physical terminal or card.
- SQL with an `x.x0` provider amount (`"12.30"`) or a zero amount (`"0.00"`): no executed pgTAP vector uses one (§8).
- Whether a PinPad commit reply carries `TipAmount` at all when no tip object is sent (W1 evidence E2-31): unknown; both
  answers are now safe (absent = no tip, zero = no tip).

## 10. Remaining gates and residuals

- **R1** — RESOLVED by the accepted documentation-consistency commit `f7d5be5d80bfd1e454a44420a70bc4317e4f5b82`.
  The "Money and replies" paragraph of `supabase/functions/pos-card-charge/CONTRACT.md` stated the former inbound
  grammar, and the file was outside this ticket's allowed list; that separately authorized commit replaced this claim
  with the **D-064** rule and also updated the comment above `TWO_DECIMAL_CURRENCIES` in `lib/provider/engine.mjs` and
  the inbound vectors of `docs/TESTING_STRATEGY.md`.
- **F3** — CONFIRMED by the command room (final packet status closeout, 2026-10-28 UTC). Its confirmation, exactly:
  - a missing key, JSON null, an empty string, or a whitespace-only string is ABSENT;
  - absence is never interpreted as zero;
  - a JSON number zero is canonicalized to 0.00;
  - every non-empty JSON string, including "0" and "12.30", is refused for provider-money fields.

  In short: blank/whitespace/null/missing = absent, never zero; non-empty strings are refused; numeric zero
  canonicalizes to 0.00. This is the implemented rule, unchanged by the closeout, with "whitespace-only" read as the F3
  item put it for confirmation ("Space_Separators only") and "a JSON number zero" read within the §3.2 grammar. A
  blank string is empty or holds only Space_Separator characters (**D-058** point 10; **D-064** point 2 states it as the
  exception to "strings are refused"; SQL applies the same absent rule). An absent amount or tip is not forwarded at all
  (the reply reader returns no value), never as `0.00`; an absent tip is no tip, so, like a numeric zero tip, it does
  not block the approval of an otherwise approvable commit reply (§3.4). A numeric `0`, `0.0` or `0.00` is read as
  `0.00`, the only form in which it can reach `card_attempt_finish`; `-0`, `0e0` and `0.000` stay `format` failures
  (§3.3). A string holding a tab, a line break or any other character that is not a Space_Separator is a value, not a
  blank, and so is refused in a provider-money field.
- **W1**: the reviewed source-module profile, bound to the sealed **Q-047** / **Q-049** package; E4 fields mapped one
  by one, only with provenance; E2-B after the owner action gates; the unknown-status default of **D-063** kept. W1
  review items: the completeness of `approval_declined`, of `lookup_not_found` / `lookup_pending` and of the reply
  field names.
- **Q-047**, **Q-049** (hard owner gates), **Q-048**, **Q-050**, **Q-052**; 001C, 001F, 001H, DEPLOYMENT §18 and the
  001D merge (S14 C), as before.
- Publication: any push, PR or merge of this branch and of the W1, G1 and 001E branches it stacks on needs its own
  process decision; **D-064** is approved for this local correction only.

## 11. Fresh-context review and dispositions

One fresh-context Claude delta review ran on `291f335c`: a workflow of two read-only lenses (behaviour and contract;
tests and evidence) with one refute-first verifier per finding of MINOR or above — 7 agents; the worktree stayed clean
at `291f335c`. It found no behaviour defect in the code and 12 findings: 1 MAJOR, 4 MINOR (all five verified
CONFIRMED at the stated severity) and 7 NOTE. As the instruction asks, no broad second round ran: the test fixes are
proved by the mutation compare of §8 (each reviewer mutant survives at `291f335c` and is killed at `7bd95d3c`).

| ID | Severity | Finding | Disposition |
|---|---|---|---|
| TE-1 | MAJOR (confirmed) | No commit test sent a readable non-zero tip on a reply that is not otherwise approvable, so a classifier applying the tip rule to phone, duplicate or error replies (R09, R10) passed the suite; fails closed (`amount_mismatch` with `charge_may_exist`), never a wrong approval | Fixed in `7bd95d3c`: six reply kinds × tips `5`, `5.00`, `0.01`, `0` × LIVE / TEST stay UNKNOWN with their class and exact fields; R09 and R10 killed |
| F1 / TE-2 | MINOR (confirmed) | No lookup test sent a readable non-zero tip; lookup-only mutants that drop or zero it (R09, R12, R17, R17c, RP, RH, RA) passed, and SQL's lookup tip check would then approve | Fixed in `7bd95d3c`: tips `5`, `5.0`, `5.00`, `0.01`, `0.1` reach the finish beside the approved outcome (SQL then gives `amount_mismatch`, FR-107); all seven killed |
| TE-3 | MINOR (confirmed) | The float-free guard does not see a numeric coercion (unary plus, `JSON.parse`, `* 1`, double negation) inside `canonicalInboundMoney`; behaviourally equivalent inside the bound | Fixed in `7bd95d3c`: the static test pins the whole helper body and `INBOUND_MONEY_TOKEN` and refuses `JSON.parse`, `globalThis` and `eval` in `lib/money.mjs`; R01, R02, R03, R05 killed |
| TE-4 | MINOR (confirmed) | Six `status.test.mjs` rows still sent the JSON string `"12.34"` and had silently become unreadable-amount cases | Fixed in `7bd95d3c`: number tokens again; `status.test.mjs` alone now kills R15 and P1 as well |
| F2 | NOTE | §3.4 and **D-064** left out the lookup tip consequences | §3.4 rows and a **D-064** consequence clause added; four lookup cases pinned in `7bd95d3c` |
| F3 | NOTE | A blank-string amount or tip stays absent, which the instruction's wording does not name | No change (**D-064** point 2 states it); listed for confirmation in §10, where the command room's confirmation is now recorded |
| F4 | NOTE | `CONTRACT.md` still states the former inbound grammar | Residual R1 (§10): outside the allowed files; resolved by `f7d5be5d` |
| EV-1 | NOTE | The mutation log predated its tool's path sanitizing | Re-run at `7bd95d3c` (`logs/MUTATIONS_7bd95d3c.txt`) |
| DOC-1 | NOTE | §4 pointed to the empty §8; §5 overstated the raw-body search and called the RED run "of the new file" | Corrected in this packet |
| TE-5 | NOTE | Whole-shekel and `x.x0` equality in SQL and the no-SQL-change guard rest partly on unchanged pgTAP evidence and on Git | Stated in §8 and §9 |
| DOC-2 | NOTE | Release replies use the same reader, so their evidence changes too | §3.4 release table; a release test added in `7bd95d3c` |
