# BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-W1-LOOKUP-SAFETY-001 — execution packet: a present unknown lookup status is out of contract before any fallback, and the W1 evidence map without the circular prerequisite

Work ID: `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-W1-LOOKUP-SAFETY-001`, a bounded local correction stacked on the accepted
G1 head of [BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-DROP-EVIDENCE-001](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_DROP_EVIDENCE_001_EXECUTION.md),
itself a correction of [BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_EXECUTION.md) (umbrella
[BIZBOT-PAYMENTS-ZCREDIT-PILOT-001](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001.md)). It records **DECISION D-063**, the next
verified free ID. Controlling contract: [API_CONTRACT](API_CONTRACT.md) §4.55.5 as amended by **D-063**; the 001E
packet §6 and §7; the G1 packet §11. This packet is the pre-code record of the policy and the scope; §7 onwards are
added by later commits of this branch.

## 1. Authorization and boundary

- Command-room G1 acceptance and bounded W1 lookup-safety correction of 2026-10-28: G1 verdict
  `ACCEPT_LOCAL_G1_SOURCE_AND_FAKE_TESTS_W1_SAFETY_AND_EVIDENCE_HELD` on the reviewed G1 head `295cacb6` (tree
  `9d017759`, archive SHA-256 `cc8968a7…`); G1 needs no further general correction round. This Work ID authorizes the
  narrow lookup policy of §3 locally. It is not a merge, deployment, real-provider test or activation approval and
  requests no Codex review.
- Local only: no push, PR, merge, hosted action, deployment, secret or configuration change, provider request,
  terminal or test-card use, printer or APK action, and no background monitor. #370 and #371 are not changed.
- No raw credential, test-card or vendor file is opened; no vendor inquiry is sent, no provider endpoint is called and
  no vendor account is browsed. **Q-047** and **Q-049** stay Open. No real profile is wired or declared approved:
  `index.ts` keeps `providerProfile: null`, and no runtime-editable wire-profile object is introduced.
- Preserved: the G1 branch at `295cacb6` with its migration, source snapshot, archive and logs; the 001E branch at
  `d5456624`; every earlier branch, commit, ZIP and evidence folder. No amend, rebase, reset or history rewrite.

## 2. Source anchor (preflight 2026-10-28, read-only)

| Item | Value |
|---|---|
| Branch | `fix/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-W1-LOOKUP-SAFETY-001-unknown-status-anomaly` (local, no upstream) |
| Base | the reviewed G1 head `295cacb6c50226da9cba99e769fac0680ee14fcc`, tree `9d017759b7f2afcefe24cc33623d2d8d70933b17` (stacked on the 001E head `d5456624` and the #370 head `54b19ab5`) |
| #370 / #371 | `54b19ab58ce72a2fa9a43860e31181a08222b254` / `53d6a6adc38f308b7ed6b0dd62177e6edd5ad5ce`, open drafts, unchanged |
| Actual `main` | `01d0098b3efd2909f0ce3a96ff19a54c45aa69e2`, unchanged since the G1 postflight; it holds none of the function's files; its latest migration is `20261022192530` |
| Ownership | no branch, worktree, remote ref or PR for this Work ID existed; this branch is its only one |
| Decision ID | **D-063** free on `main`, #370, #371, the 001E and G1 heads and every ref: the only commit that names it (`bbe548cd`) states it as the next free ID |
| Baseline | the function-local Node suite 134 / 134 on Node 22.14 and 24.19 at `295cacb6`; the three superseded fallbacks reproduced with the synthetic profile (evidence `tests/PROBE_LOOKUP_POLICY_BEFORE_295cacb6.txt`) |

## 3. The policy (DECISION D-063)

**Before.** The behaviour is inherited from 001E; it is not a G1 regression and not a real-provider incident.
`classifyLookup` read a status that was present, readable and in none of the profile's seven status lists as if it
were absent for two rules: a listed not-found / pending return code concluded `not_found` / `pending` (001E
verification V1-1), and a declined approval type with no failing essential field concluded `declined` (001E delta
review LA-2). Only when neither applied was such a status the `out_of_contract` anomaly, so failing closed on an
unknown value depended on the profile listing it (the 001E packet §6, W1 item 3; the G1 packet §11, item 3). On a
`declined` lookup SQL sets `declined` and clears `charge_may_exist`, also on an attempt that already carries an
anomaly (field-rules lane FR-145).

**After.** After extraction (the field rules, `extractReply`) and the status normalization (NFKC and the
Space_Separator trim, `canonicalText`), the lookup classification is, in order:

1. a **present** status that is **unreadable** (its value failed the field rule) or **unlisted** (readable, but in
   none of `status_approved`, `status_voided`, `status_refunded`, `status_partial_refund`, `status_preauthorization`,
   `status_not_found` and `status_pending`) is `anomaly` / `out_of_contract`. This is decided before any return code or
   approval type is read, so no not-found / pending return code and no declined or approved approval type overrides it;
2. a listed not-found / pending status, or — only when the status is **absent** — a listed not-found / pending return
   code is `not_found` / `pending`, whatever else the reply carries;
3. a listed void, refund, partial-refund or pre-authorization status is its anomaly (`out_of_contract` when an
   essential field failed);
4. a listed approved status is `approved` unless the approval type declines it or an essential field failed
   (`out_of_contract`);
5. with no status, a declined approval type is `declined` when no essential field failed (the vendor has no decline
   status, **Q-048**) and `out_of_contract` otherwise;
6. with no status, a reply reporting a transaction — an approved type, a readable amount, or an unreadable approval
   type, amount, tip or return code — is `out_of_contract`;
7. anything else is `failed` (no provider fact).

**Absent versus present.** A status is absent exactly when its key is missing, its value is JSON `null`, or it is a
string that is empty or holds only Space_Separator characters. That is the existing absent rule (**D-058** point 10;
`textAbsent`, SQL `app.card_text_absent`). No other value is absent: `"0"`, the number `0`, `"null"`, `"-"` and any
other present value are statuses, unlisted unless the profile lists them. No vendor sentinel is introduced; a future
concrete sentinel needs explicit evidence and a reviewed mapping. The normalization folds no case: `"s1"` is not the
listed `"S1"` and is unlisted.

**Unchanged.** The listed-status handling; the known-conflict rules (an approved status with a declined type; a
listed approved, void, refund, partial-refund or pre-authorization status with a failing essential field — a listed
not-found / pending status keeps its outcome and a failing field is only dropped, 001E delta review LA-1); SQL's
amount and currency checks (the finish lookup arm); the commit
and release classification; the money serialization; the G1 dropped-field evidence (a reply's `{field, rule}` tokens
ride the anomaly finish as `dropped_fields` exactly as before); the transport rule that a non-2xx, non-object or
non-JSON reply, or a transport failure, is `failed`.

**SQL.** No SQL behaviour is added or changed and no migration is edited: the adapter sends the existing finish
outcome `anomaly` with `anomaly_code = 'out_of_contract'` (§6).

| Reply (synthetic profile; a LIVE `unknown` attempt) | Before (`295cacb6`) | After |
|---|---|---|
| status in no list + declined type | `declined` | `anomaly` / `out_of_contract` |
| status in no list + listed not-found return code | `not_found` | `anomaly` / `out_of_contract` |
| status in no list + listed pending return code | `pending` | `anomaly` / `out_of_contract` |
| status in no list + not-found code + declined type | `not_found` | `anomaly` / `out_of_contract` |
| `"0"`, `0`, `"null"` or `"-"` as the status + a declined type, or a not-found / pending code | `declined` / `not_found` / `pending` | `anomaly` / `out_of_contract` |
| status in no list + approved type + matching money; status in no list alone; `"s1"` | `anomaly` / `out_of_contract` | unchanged |
| unreadable status, with any return code or type | `anomaly` / `out_of_contract` | unchanged |
| listed statuses (approved, the conflict, void, refund, partial refund, pre-authorization, not found, pending; `" S1 "` normalized) | as listed | unchanged |
| absent status (missing, `null`, `""`, Space_Separators only) + a declined type, or a not-found / pending code | `declined` / `not_found` / `pending` | unchanged |

## 4. Exact files

| Path | Change |
|---|---|
| `supabase/functions/pos-card-charge/lib/provider/engine.mjs` | `classifyLookup` only: step 1 also takes a present status in no list, so the later steps see a listed or an absent status and the declined-type rule runs only with no status; its comment |
| `supabase/functions/pos-card-charge/test/lookup_status_policy.test.mjs` | new: the required direct-classifier and handler-to-fake-RPC cases (§5) |
| `supabase/functions/pos-card-charge/test/provider.test.mjs`, `test/status.test.mjs` | only the expectations that encoded the superseded fallbacks (LA-2, V1-1), with their comments and test titles |
| `supabase/functions/pos-card-charge/CONTRACT.md` | the lookup paragraph |
| `docs/DECISIONS.md` | **D-063** and its changelog line |
| `docs/API_CONTRACT.md` | §4.55.5's lookup wording |
| `docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_EXECUTION.md`, `docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_DROP_EVIDENCE_001_EXECUTION.md` | dated notes on their W1 policy and evidence text |
| this packet | new |

Not touched: every migration (the 001D migration, blob `b94a34176d6eefb8d1a53c7907d1b4272de7dcfd`, and the G1
migration `20261027211023`, blob `0e7b9c1a3be5b5ac56cb2b4e2e647571c81ec1a8`), every SQL test and the SA-135 pin;
`handler.mjs`; `index.ts` (`providerProfile: null`); the transport (`lib/http.mjs`), the reply reader (`extractReply`,
`readKey`), the commit and release classification and every other `lib/` module; `test/fixtures.mjs`;
`supabase/config.toml`; `.github/workflows/ci.yml`; dependency manifests and lockfiles; POS, l10n, shared helpers,
financial writers, schema and ACLs; `docs/OPEN_QUESTIONS.md` and `docs/TESTING_STRATEGY.md`.

## 5. Test plan (scripted RPC tests, not PostgreSQL runs)

Expectations are literals, never derived from the engine's own reader or classifier.

- **Direct classifier** (`extractReply` + `classifyLookup`): each unlisted status (`"S7"`, `"0"`, `0`, `-7`, `"null"`,
  `"-"`, `"s1"`) and each unreadable status (`"S 1"`, `true`, a control character, `"N/A"`, 17 characters, `1.5`) with
  a declined type, a not-found code, a pending code, a not-found code and a declined type, an approved type with
  matching money, and alone; the recognized controls (approved, the approved / declined conflict, the four listed
  anomalies, a listed not-found / pending status beside another type, a listed status over a not-found code, `" S1 "`
  normalized); the absent-status controls (decline, not found, pending, a failing essential field, a transaction,
  nothing) for each absent encoding (missing, `null`, `""`, a Space, U+3000).
- **Handler to fake RPC** (LIVE and TEST, an `unknown` attempt): the exact finish (`p_source`, `p_outcome` and the
  literal `p_provider_fields`, `dropped_fields` included), exactly one provider lookup and no commit, the RPC sequence,
  and the POS answer.
- **An existing anomaly / charge-risk attempt** (LIVE `unknown` and `released` carrying `provider_anomaly`): an
  unknown status with a declined type, with an approved type and matching money, or with a not-found code is sent as
  `anomaly`, never as a clearing `declined` / `approved`; controls: a listed approved status with matching money and an
  absent status with a declined type still send `approved` / `declined`.
- **Repeated unknown results**: consecutive status calls, each with one lookup and one `anomaly` finish; a repeated
  identical reply carries identical tokens.
- **Dropped fields beside an unknown status**: LIVE and TEST, literal tokens in reply order, no rejected value in the
  RPC argument.
- **Updated expectations**: the LA-2 / V1-1 block of `provider.test.mjs` and the five matching cases of
  `status.test.mjs` *(corrected from "four" after the fresh-context review, W1-BT-4 / F5)*.
- **RED / GREEN**: the new file fails on the `295cacb6` engine and passes after the change.
- **Focused mutations** of `classifyLookup`, including the whole-function revert and the preserved 001E mutations of
  this function re-anchored.
- **Added after the fresh-context review** (§12): with no status, a decline beside a failing currency, error flag or
  phone flag; `false`, `[]` and `{}` as unreadable statuses and the raw number token `-0` as an unlisted one; a
  full-width `S1` control for the NFKC half of the normalization.
- Not re-run: pgTAP (no SQL change, §6), the full 001E and G1 mutation suites, Deno (not installed).

## 6. SQL: the existing finish contract (no change)

The adapter's new outcome is an existing finish input. Its SQL behaviour is the accepted 001D and G1 pgTAP evidence,
reused here and not re-run:

- FR-140 and FR-142: a lookup `anomaly` with an unknown or no `anomaly_code` is `out_of_contract`; a `sent` row moves
  to `unknown` with `charge_may_exist = true` and LIVE classification `provider_anomaly`.
- FR-104: an anomaly leaves an `unknown` row `unknown`; TI-58: a later anomaly on a `released` TEST attempt keeps it
  `released`.
- FR-105 and FR-106: a lookup `anomaly` on a row that already carries one — a different code replaces the stored code
  with a new `card_attempt.provider_anomaly` audit, and the same anomaly again changes only the lookup stamp (no
  audit); the row stays `unknown` with `charge_may_exist` set. These are the SQL side of the existing-anomaly and
  repeated-unknown cases of §5.
- FR-143: a lookup anomaly carrying a failing essential field is `out_of_contract` whatever code it names.
- FR-144 and FR-145: only a later exact `approved` / `declined` result clears `charge_may_exist` — the clearing that
  the superseded fallback could reach with an unknown status.
- G1-028, G1-050, G1-072 and G1-075: the dropped-field evidence on the lookup source.

The lookup arm of `app.card_attempt_finish` is the G1 migration's, unchanged. Those lanes passed in the G1 run on the
`d3074ff4` tree, whose migrations and SQL tests equal those of `295cacb6` and of this branch. That full
`supabase test db` command itself ended `Result: FAIL` / `exit=1` (Files=327, Tests=12 953): the two CI-only
storefront concurrency files `zz_storefront_content_contract_001_concurrency_test.sql` and
`zz_storefront_featured_items_001_concurrency_test.sql` exited 3 with no plan, because their CI-only guards refuse a
non-CI database before any test runs, and every other file passed. That is the known local execution limitation — not
a passing suite and not two successful skips; the guards were not bypassed.

## 7. W1 evidence map, revised: E2 split, known evidence and the exact gaps

The G1 packet §11 asked for "E2 — reply fixtures from the sealed TEST run", which "can exist only after the
**Q-047** facility evidence", while the profile that the first TEST run needs could be built only from E2: a circular
prerequisite. Part of the reason was the old lookup rule — the complete status vocabulary was a safety precondition
because a status in no list could fall back to a decline or to a not-found / pending code. **D-063** removes that
reason, and the command room splits E2:

- **E2-A — the pre-call documented contract and approved redacted examples: a prerequisite of the profile.** What a
  reviewer needs to build and review the source-module profile before any provider call: per operation, the reply
  field names and JSON types; the success return code per operation, the duplicate code and any documented not-found /
  pending lookup codes; the approval-type values with their approved / declined meaning; the documented status values
  with their meaning (each placed in one of the seven lists, or deliberately left unlisted and so an anomaly); the
  currency-type value for ILS in requests and replies; whether errors arrive as non-2xx statuses or as 200 with an
  error flag; and, where documented, what a lookup returns for a never-sent, a declined and a still-waiting attempt;
  plus approved redacted example replies for each documented outcome. Its sources are the vendor's documentation
  (the published WebService documentation and OpenAPI that the pilot packet §3 sanitizes and that **Q-047** and
  **Q-049** cite) and redacted vendor-supplied examples, approved by the owner and the command room as a sanitized
  extract and sealed with the **Q-047** package where they carry non-public material. E2-A is not a TEST-run
  observation.
- **E2-B — later physical TEST acceptance observations: not a prerequisite of the profile.** Only after **Q-047** and
  **Q-049** are sealed and the separate owner action gates of [DEPLOYMENT](DEPLOYMENT.md) §18 are satisfied: the
  replies observed in the sealed non-settling TEST facility confirm or correct E2-A; **Q-048**'s cases (a never-sent,
  a declined and a still-waiting attempt; terminal scoping) where E2-A does not document them; observed sizes,
  encodings and contradictory replies, if any. A difference from E2-A is corrected by a reviewed profile change under
  the retention rule of §8.1 — never by a silent fallback.
- **The unknown default stays mandatory.** A finite set of documented values or fixtures is not proof of every future
  status. Whatever E2-A or E2-B lists, a status the profile does not list is the `out_of_contract` anomaly
  (**D-063**), so the completeness of the status lists now decides availability — how often a real attempt becomes an
  anomaly that holds its order — and no longer safety. Three E2-A inputs remain safety inputs, because the preserved
  rules act on them only when they are listed or mapped: `approval_declined` (a listed approved status beside an
  approval type in neither approval list concludes `approved`, so the approved-status / declined-type conflict fails
  closed only for a listed declined value); `lookup_not_found` / `lookup_pending` (with no status, a reply whose
  not-found or pending return code is unlisted and that carries a declined type concludes `declined`); and the reply
  field names (a status sent under a name the profile does not map is absent). They are W1 review items of the
  profile. *(Narrowed after the fresh-context review, F2.)*

**Sources.** "Known" below uses only the approved sanitized sources of this workstream: the pilot packet
[§3](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001.md) (the sanitized map of the provider's public documentation),
[API_CONTRACT](API_CONTRACT.md) §4.55, [DECISIONS](DECISIONS.md) (**D-051**..**D-063**),
[OPEN_QUESTIONS](OPEN_QUESTIONS.md) (**Q-007**, **Q-047**..**Q-050**), [DEPLOYMENT](DEPLOYMENT.md) §18.5 and the
001D, 001E and G1 packets. Rules that only the engine imposes are marked as engine rules. The synthetic profile of the
tests is test data and supplies no vendor fact. "Not shown in the internal summary" is not read as "never supplied by
the vendor": the workstream's read-only preflight of 2026-10-21 (its §7, kept outside the repository; built from the
vendor's public WebService documentation and OpenAPI, the masked PIN-pad guide and redacted extracts) records
request and reply field names, the success and duplicate return codes and other return codes, the concrete
approval-type values grouped by class (including classes other than approved and declined), the concrete status
values with their meanings, the request currency-type value, and a reply-side currency field with an expected ILS
mapping that it labels an inference *(corrected after the fresh-context review, F3)*. It is not an approved source of this packet: no value from it is used here or
copied into the repository, and whether it may serve as E1 / E2-A input is the command room's decision.

| Item | Known in the approved sources | Exact remaining gap | Stage |
|---|---|---|---|
| **E1** — request shapes | One server-to-server JSON commit over TLS 1.2 with the terminal credentials in every request body; amount, currency type, charge type and customer-present flag fixed before the pad prompts; the PIN pad selected by a device identifier in the track field with the card fields empty; two merchant-supplied keys; a release cancels a pending pad transaction only while the pad shows its swipe screen (pilot §3 Transport, Addressing, Sale, Amount, Correlation, Release). Request rules: no tip object, a regular charge, no installments, no authorization-only or pre-authorization mode, the amount an unquoted JSON number token of the two-decimal lexeme (**D-052** point 4; API §4.55.4 step (5)); the adapter sends exactly the stored keys (**D-058** point 2). Engine rule: the release takes the pad and no key (`requestSpecs`). | The field names, constant encodings and JSON types per operation, how the release identifies the transaction, and byte-level request fixtures: not in the approved sources (candidate material exists in the preflight). The credential fields per operation and the purpose of the separate "KEY" in the test data → **Q-047**. | Pre-call, with the **Q-047** package |
| **E2-A** — documented reply contract | The reply carries an error flag, a return code, a message, an approval type with approved / declined variants and a phone-authorization flag (pilot §3 Reply); approved = no error, return code zero and an approved type (**D-052** point 3; API §4.55.4); the status lookup reports approved-not-deposited, approved-deposited, voided, refunded, partially-refunded and pre-authorization states and no declined state (pilot §3 Status lookup; **Q-048**); lookups echo the amount and the currency type, the commit echoes no amount (pilot §3 Amount); an exact repeat of the duplicate-check key is refused with a dedicated code (pilot §3 Correlation); engine rule: a release is confirmed only by error flag false and a success return code (the 001E packet §7; `classifyRelease`), which decides the `released` / `release_failed` outcomes of API §4.55.6 *(source corrected after the fresh-context review, F1)*. | The values and names: the duplicate code, any not-found / pending lookup code, the approval-type values, the status values, the currency-type value, the reply field names and JSON types per operation, how errors arrive, and approved redacted examples — not in the approved sources. The preflight records the field names, the success and duplicate codes, the concrete approval-type values per class (including classes other than approved and declined), the concrete status values with their meanings, the request currency-type value and an inferred reply-currency mapping; it records no not-found or pending lookup code and leaves the error delivery and **Q-048**'s cases open. | Pre-call: a prerequisite of the profile |
| **E2-B** — TEST acceptance | — | Replies observed in the sealed TEST facility confirming E2-A; **Q-048** (a never-sent, a declined and a still-waiting attempt; terminal scoping), where E2-A does not document it; sizes, encodings and contradictory replies. | After **Q-047** / **Q-049** and the owner action gates; acceptance, not a prerequisite |
| **E3** — outbound keys | Two merchant-supplied keys derived from the full attempt identity; the formatter exists only in 001D's claim and the adapter passes the stored keys (**D-052** point 2, **D-058** point 2); the OpenAPI declares no length or pattern and one error code forbids "special characters" (**Q-049**). | The keys' encoding, length and character set, and the duplicate check's semantics (declined or pending matches, retention window): **UNKNOWN** → **Q-049** sealed evidence (hard gate). | Pre-call |
| **E4** — optional metadata provenance | The reply can carry full or masked card numbers (a terminal setting the application never reads or changes), last four, brand, token, receipt texts and raw records (pilot §3 Reply; **Q-050**); card numbers, BINs, expiries, tokens, raw processor records and receipt texts are never persisted, logged, printed or displayed and the server strips them (**D-052** point 6); engine rule: the reply reader extracts only the allowlisted keys of the 001D packet §4.2 and never reads a card number, BIN, expiry, token, receipt text or raw record (the 001E packet §7) *(sources corrected after the fresh-context review, F1)*; the field rule is not an absolute masked-card sanitizer (**D-059** point 4). | **UNMAPPED**: none of `provider_reference`, `approval_number`, `voucher_number`, `deposit_id`, `card_last4`, `card_brand_code`, `pan_entry_mode`, `payment_method_code` and `provider_saved_at` is mapped without written provenance that it cannot carry card-derived content, and none is added to complete this matrix. The engine runs with all nine unmapped: a profile that maps only the eight essential keys validates, and unmapped fields are never read, forwarded or recorded as evidence (probe evidence `tests/PROBE_ESSENTIAL_ONLY_PROFILE_874297f7.txt`; no committed test pins it). The terminals' masking setting → **Q-050**. | Per field, before mapping it |
| **E5** — ILS and the echoed amount | Amounts are decimal major units with exactly two decimals; the pilot charges ILS only (pilot §3 Amount, §6; **Q-007**); the outbound lexeme and the inbound grammar carry exactly two decimals (**D-052** point 4; API §4.55.4 step (5), §4.55.5); engine rule: only ILS can be encoded (`TWO_DECIMAL_CURRENCIES`). | The currency-type value for ILS in requests and replies and its JSON type, whether echoed amounts always keep two decimals, and the vendor's amount limits: **UNKNOWN** in the approved sources (the preflight records the request currency-type value, the reply's currency field with an expected ILS mapping that it labels an inference, and the amount's JSON type). *(2026-10-28: the W1 wire-evidence package was accepted, and **D-064** (BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-INBOUND-MONEY-NORMALIZATION-001, local, not merged) closes the echoed amount's fraction-digit form (W1 evidence E5-03 / E2-26) — inbound amounts are JSON number tokens with zero, one or two fraction digits, read as their two-decimal lexeme; nothing else in this row changes.)* | Pre-call (E2-A examples confirm) |

Items 7 and 8 of the G1 map are decisions, now confirmed by the command room (§8).

## 8. Decisions 7 and 8 (confirmed): existing tests and the precise missing tests

No working code is changed to restate them.

### 8.1 Profile retention (item 7)

Confirmed: the source-module route; no incompatible profile replacement while dependent unresolved attempts may
still need the old field or code interpretation, including the relevant `sent`, `unknown` and `released` attempts;
no per-attempt version subsystem in this ticket.

- Existing: `static_guard.test.mjs` — "Deno is used only by index.ts …" pins `providerProfile: null`, so no profile
  is wired; "the function's files are exactly the reviewed set" fails for any new profile module until the reviewed
  set is updated in its own ticket. The credential half of retention is runtime-enforced: every lookup and release
  re-validates the attempt's frozen terminal and credential records (API §4.55.5; [DEPLOYMENT](DEPLOYMENT.md) §18.5;
  the 001D adapter read and its pgTAP lanes).
- Missing, precisely (the profile ticket or 001H): nothing ties a deployed profile to the attempts that may still need
  it. Needed: a deployment-gate check, with its own test, that refuses a change of the profile module while any
  attempt is `sent`, `unknown` or `released` without a `resolution` unless the change is reviewed as compatible with
  those attempts; and a static test pinning the module's `version`, so that every change of the module is visible to
  that gate.

### 8.2 Currency (item 8)

Confirmed: an ILS-only pilot; an unsupported-currency start refuses before a new claim or provider request; no
automatic conversion and no assumption that a missing currency means ILS; an unexpected reply currency follows the
existing anomaly contract.

- Existing, adapter (Node): `start.test.mjs` "step (1) …" — a TEST start in USD answers `provider_unavailable` with no
  RPC call, so no claim (the provider is reached only after a fresh claim); `provider.test.mjs` — the profile schema
  refuses a request currency other than ILS (USD, JPY) and a reply-currency mapping to anything but ILS; the engine has
  no conversion path: a reply currency is forwarded as an ISO code (through the profile's mapping, or a three-letter
  code as received) or dropped, and SQL compares it with the attempt's currency. An unreadable reply currency fails closed:
  `start.test.mjs` "every unreadable essential field fails a commit closed …" and `status.test.mjs` "every unreadable
  essential field on a found lookup is the out_of_contract anomaly …". The adapter adds no field the reply did not
  carry: the exact-field assertions of the lookup tests (`lookup_status_policy.test.mjs`, `drop_evidence.test.mjs`).
- Existing, SQL (accepted 001D evidence, not re-run): CI-245, CI-246, CI-249 and CI-257 (a TEST claim in a currency
  other than the tenant's → `precondition_failed` / `currency_not_supported`); FR-91 (a commit currency outside
  `^[A-Z]{3}$` → `unknown`); FR-96 and FR-108 (a commit or lookup approval in another currency → `currency_mismatch`);
  FR-111 (a lookup approval without `provider_currency` → `out_of_contract`: a missing currency is never taken as ILS);
  FR-114 (a failing currency → `out_of_contract` with its field-drop event).
- Missing, precisely: the LIVE variant of the step-(1) refusal — `startLive({ currency_code: "USD" })` answering
  `provider_unavailable` with no RPC call and no provider request; only the TEST variant is tested.

## 9. Results (local; the code and tests are those of `bba0f5f0`; the commits after it change documentation only)

| Check | Result |
|---|---|
| Function-local Node suite | 143 / 143 on Node 22.14 and on Node 24.19 (Windows), 0 skipped, at `ad79864d` (`tests/node_tap_ad79864d_node22.txt`, `tests/node_tap_ad79864d_node24.txt`) |
| On every commit of the branch (exported copies, both Node versions) | green at every commit: 134 tests at `295cacb6` and `57c3c740`, 143 from `874297f7` (`tests/PER_COMMIT_NODE_SUITE_*.txt`) |
| The superseded expectations | with the new engine and the old tests, exactly the two tests that encoded LA-2 / V1-1 failed — `provider.test.mjs` "lookup classification …" and `status.test.mjs` "lookup outcome mapping …" (`tests/node_tap_engine_only_old_tests.txt`); their re-expected rows, with the matching comments and test titles, are the only edits to those files |
| RED / GREEN | `lookup_status_policy.test.mjs` as committed, run on the `295cacb6` engine: the 5 policy tests fail and the 4 control tests pass (`tests/RED_new_tests_ad79864d_on_295cacb6_engine.txt`); 9 / 9 at the head |
| Before / after probe (`tools/probe_lookup_policy.mjs`) | 31 synthetic LIVE replies through the classifier and the handler: exactly the 8 superseded-fallback rows change, to `anomaly` / `out_of_contract`; every other row, with its forwarded fields, is byte-identical; one provider lookup per reply and never a commit (`tests/PROBE_LOOKUP_POLICY_BEFORE_AFTER.txt`) |
| Independent differential (the fresh-context review, §12) | 1 758 000 synthetic replies, 5 profile variants, LIVE and TEST, base against head: 91 202 differences, all of the intended kind (a present readable unlisted status that the base concluded `declined`, `not_found` or `pending` and the head sends as `anomaly` / `out_of_contract` with the same value fields); 0 other differences, 0 exceptions |
| Focused mutations (`tools/mutate_w1.py`; the whole suite per mutant) | 31 / 34 killed at `ad79864d` (`tests/MUTATIONS_W1_ad79864d.txt`): K01–K05, K08–K23 and the re-applied 001E mutations M08, M21, M24, M25, M60, M62, M63, M69 (re-anchored on step 1), M70 and M71. The 3 survivors are equivalent: K06 and K07 cannot differ while step 1 holds, and M61 is caught by the fail-closed guard — K18 (M61 together with K07) is killed. M46 is superseded: its mutant is the D-063 rule. The whole-function revert (K15) and the LA-2 / V1-1 fallbacks restored in place (K16, K17) are killed |
| The review's surviving mutants (`tools/compare_review_mutants.py`) | R01, R02, R04, R05 and R07 pass the whole suite at `502d5694` and fail it at `bba0f5f0` (`tests/REVIEW_MUTANTS_AT_502d5694.txt`, `tests/REVIEW_MUTANTS_AT_bba0f5f0.txt`); they are K19–K23 of the focused set |
| E4 (`tools/probe_essential_only_profile.mjs`) | a profile that maps only the eight essential keys validates; unmapped fields are never read, forwarded or recorded as evidence (`tests/PROBE_ESSENTIAL_ONLY_PROFILE_874297f7.txt`) |
| Guardrails | `tools/check_no_float_money.sh` OK (it scans `apps/` and `packages/`; the function's own static guard covers its money code) and `tools/check_secrets.sh` OK, at `ad79864d` (`tests/GUARDRAILS_ad79864d.txt`) |
| Public-repo hygiene of the added lines and the commit messages (`tools/hygiene_w1.py`) | no card-shaped value, masked shape, local path, secret, URL or invisible character; the digit runs are migration versions and commit, tree and blob hashes, and the only e-mail address is the commit trailer's (`tests/HYGIENE_W1_*.txt`) |
| SQL | not re-run: no migration or SQL test changed (§6) |

## 10. NOT VALIDATED here

- PostgreSQL: no pgTAP lane ran for this ticket. The anomaly finish is the accepted 001D / G1 evidence of §6, whose full
  local command ended `Result: FAIL` / `exit=1` because the two CI-only storefront files refuse a non-CI database (the
  known local execution limitation; their guards were not bypassed).
- The full 001E (79) and G1 (60) mutation suites: not re-run, per the instruction; only the 001E mutations of
  `classifyLookup` were re-applied (§9).
- Deno and the Supabase edge runtime: not installed, and nothing was installed or upgraded.
- Hosted behaviour of any kind, Linux CI (no CI run exists for this branch) and the vendor: no provider request; the
  synthetic profile proves no vendor fact.
- The availability cost of **D-063** with the real provider — how often a real decline or not-found reply carries a
  status the profile does not list — depends on E2-A and E2-B (§7).
- Pre-existing and not changed (G1, outside this scope): `test/drop_evidence.test.mjs` line 40 holds one raw U+200B
  character inside a string literal (`zwsp`); it equals its escape at run time.

## 11. Remaining gates (unchanged by this ticket unless stated)

- **W1**: the reviewed source-module profile, built from an approved E2-A extract and bound to the sealed **Q-047** /
  **Q-049** package (E1, E3, E5); E4 fields mapped one by one, only with provenance; E2-B after the owner action gates;
  the unknown-status default of **D-063** kept whatever E2 lists. W1 review items: the completeness of
  `approval_declined`, of `lookup_not_found` / `lookup_pending` and of the reply field names (§7). *(2026-10-28: the
  W1 wire-evidence package was accepted; **D-064** closes only its two representation gaps, locally; the profile
  stays unwired and these items stand.)*
- An availability item for W1 / 001H (**D-063** consequences): a LIVE attempt whose lookup carries a status the profile
  does not list stays a provider anomaly — the order held, the manager's `free_order` refused — until a later exact
  result; the operator resolutions (`provider_voided`, `provider_refunded`) do not fit a provider-side decline.
- The precise missing tests of §8: a profile-change deployment gate tied to unresolved attempts, and the LIVE
  step-(1) currency refusal.
- **Q-047** and **Q-049** (hard owner gates), **Q-048**, **Q-050**, **Q-052**; 001C, 001F, 001H, the optional atomic
  lookup reservation, DEPLOYMENT §18 and the 001D merge (S14 C), as before.
- Publication: any push, PR or merge of this branch, and of the G1 and 001E branches it stacks on, needs its own
  process decision; **D-063** is approved for this local correction only.

## 12. Fresh-context review and dispositions

One read-only fresh-context review of `295cacb6..502d5694`, as the instruction's section 6 asks. It ran two lenses: a
behaviour-and-tests lens and a documentation, evidence and scope lens. A refute-first verifier checked each finding
of MINOR or above (evidence `review/1_fresh_context_review_502d5694.json`, readable copy alongside). The review found
no BLOCKER, no MAJOR and no behaviour defect: the code is correct, and every finding is a test gap or a wording
inaccuracy.

| ID | Severity | Verified | Disposition |
|---|---|---|---|
| W1-BT-1 | MINOR | CONFIRMED | Fixed `bba0f5f0`: with no status, a declined type beside a failing currency, error flag or phone flag is `out_of_contract` (direct, every absent encoding; handler, LIVE and TEST); mutant R01 (K19) killed |
| W1-BT-2 | MINOR | CONFIRMED | Fixed `bba0f5f0`: `false`, `[]` and `{}` are present, unreadable statuses and the raw number token `-0` a present, unlisted one (direct and handler); R04, R05 and R07 (K21–K23) killed |
| W1-BT-3 | NOTE | — | Fixed `bba0f5f0`: a full-width `S1` control pins the NFKC half of the normalization; R02 (K20) killed |
| W1-BT-4 / F5 | NOTE | — | Fixed `ad79864d`: §5 counts five `status.test.mjs` cases |
| F1 | MINOR | PARTIAL (two of three parts) | Fixed `ad79864d`: the release confirmation and the never-read rule cite the 001E packet §7 as engine rules; **D-052** point 6 is kept for never persisting; **D-059** point 4 stays (it states the limit) |
| F2 | MINOR | CONFIRMED | Fixed `ad79864d`: D-063's consequences, §7 and the dated notes are narrowed to the status lists, and §7 names the three inputs that stay safety inputs. The behaviour behind them is pre-existing and unchanged; it is carried to W1 as review items (§11) |
| F3 | MINOR | CONFIRMED | Fixed `ad79864d`: the preflight is described by category without understating it; no value is copied |
| F4 | MINOR | CONFIRMED | Fixed `ad79864d`: §3's "Unchanged" conflict rules match the engine (a listed not-found / pending status keeps its outcome, LA-1) |
| F6 | NOTE | — | Fixed `ad79864d`: D-063 point 2 and API §4.55.5 state the normalization exactly |
| F7 | NOTE | — | Fixed `ad79864d` (§6) and `bba0f5f0` (the test comments): FR-105 and FR-106 are cited |

As the instruction directs, no second review round ran. The fixes are test additions and wording only. They were
checked by the mutation comparison above, the full suite on both Node versions and the per-commit run.
