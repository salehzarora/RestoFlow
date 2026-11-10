# BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E — execution packet: the `pos-card-charge` Edge adapter (local, fake-provider)

Work ID: `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E` (a ticket of the umbrella
[BIZBOT-PAYMENTS-ZCREDIT-PILOT-001](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001.md)).
Controlling contract: [API_CONTRACT](API_CONTRACT.md) §4.55 and the merged pilot packet; the 001D server side is
[the 001D execution packet](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001D_EXECUTION.md) (§4.2 finish inputs, §4.3 key formatter,
§4.5 text policy, §10 the 001E handoff). This packet records how 001E implements that contract. It amends no
**DECISION**, adds no **OPEN QUESTION** and allocates no new ID.

## 1. Authorization and boundary

- Command-room authorization of 2026-10-27, "LOCAL EDGE ADAPTER + FAKE-PROVIDER TESTS": a bounded local
  implementation. It is not a merge, deployment, real-provider test or activation approval, and **D-061** (scoped to
  001D) does not cover 001E.
- Local only: no push, PR, Update branch, retarget, merge, deployment, hosted SQL, secret or configuration change, provider
  request of any kind (commit, status, release, health probe, vendor-panel login), terminal or card action, printer or
  APK action, and no new ticket. S14 C stays in force for 001D (#370 / #371 untouched).
- Fake-only: every test injects a scripted fake provider transport and a scripted fake PostgREST; unexpected outbound
  network access fails the test. Synthetic data only; no raw credential, test-card or vendor file is opened.
- Fail closed and default OFF: with no `POS_CARD_PAYMENTS_ENABLED=true`, no valid `POS_CARD_PROVIDER_CONFIG` and no
  vendor wire profile (§6) the function makes no provider call. **Q-047** and **Q-049** stay Open; synthetic fixtures
  satisfy neither.

## 2. Source anchor (preflight 2026-10-27, read-only)

| Item | Value |
|---|---|
| Branch | `feat/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-edge-adapter` (local, no upstream) |
| Base | #370 head `54b19ab58ce72a2fa9a43860e31181a08222b254`, tree `2bbbb1f694c9157f77535bec4d5fb16d0397e7ea` |
| Base CI | run `40428907718` on the test merge `40026b194899d90c83e9db843a3a1ce2125a59d0` with `main` `be9e02c69a4913f121dbca039142fd3c37d4b371` |
| Actual `main` at preflight | `be9e02c6` (no drift since the 001D publication); the merge base with this branch is `d2079820` |
| Not contained here | `be9e02c6` (#369: POS alert print notices, 20 files, none under `supabase/functions`, `supabase/config.toml`, `.github/` or the payment contract docs) |
| Postflight (2026-10-27, read-only) | `main` `be9e02c6`, #370 `54b19ab5` and #371 `53d6a6ad` unchanged; both still open drafts; no remote branch for this ticket |

**Stacked-development exception (command room, 2026-10-27).** 001D is intentionally unmerged (S14 C), so this branch
starts from the reviewed #370 head instead of `main`. It does not contain every current-`main` change and imports no
other unmerged work; the companion #371 is not an ancestor.

Ownership at preflight: open PRs #314 / #315 (printing, untouched), #370 / #371 (001D, untouched). The two local
alert-observation branches (`fix/BIZBOT-POS-ALERT-PRINT-NOTICE-001-registration-observation`,
`fix/BIZBOT-POS-ALERT-PRINT-NOTICE-001-observation-correlation`) touch no file of §3. Compared with their merge
base on `main`, the local branches that change `supabase/config.toml` or `.github/workflows/ci.yml` are the 001D
family (its own CI step, contained in the base) and five stale branches: three whose blocks are on `main`
(`fix/BIZBOT-POS-ORDER-DECISION-UX-SYNC-001-database`, `feat/BIZBOT-POS-BACKGROUND-ORDER-ALERT-001-server`,
`fix/vercel-monorepo-deployment-filter`); `feat/STOREFRONT-PUBLISH-001-profile-editor-media` (no upstream, no PR and
no remote branch), whose storefront-media blocks `main` has since replaced with different ones; and
`perf/canvaskit-versioned-shared-assets`, pushed earlier as PR #283 (closed unmerged; its remote branch since deleted),
whose CanvasKit steps near the top of the `validate` job are not on `main` and lie away from the 001E step (corrected
after the fact-check, A2, and the delta verification, R1; the preflight record listed only two of the five). No
branch, PR or worktree named `…ZCREDIT…001E…` existed.

## 3. Exact files

| Path | Change |
|---|---|
| `supabase/functions/pos-card-charge/**` | new: `index.ts`, `handler.mjs`, `CONTRACT.md`, `lib/**`, `test/**` |
| `supabase/config.toml` | one additive `[functions.pos-card-charge]` block (`enabled = true`, `verify_jwt = false`) |
| `.github/workflows/ci.yml` | one additive `validate` step running the function's Node suite; every existing job, step, permission and timeout unchanged |
| `docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_EXECUTION.md` | this packet |

Not touched: `supabase/functions/_shared/**` and every other function (read as precedents only, not imported), every
migration and the 001D SQL, `record_payment` and the payments schema, POS / KDS / Kiosk / printing / Dashboard / l10n
sources, release and signing files, Vercel settings and filters, dependency manifests and lockfiles, frozen governance
documents and the **D-061** companion.

## 4. Interfaces

### 4.1 Boundary (§4.55.1)

`POST` only, on the exact function path (`/pos-card-charge`, or `/functions/v1/pos-card-charge` as some runtimes
present it), no query string. Native Android POS only: any `Origin` header is refused (403) and no CORS is served.
`Authorization: Bearer <three base64url segments>` is required (401 otherwise); the JWT is never decoded — PostgREST
verifies it when the read-only context proof runs (§4.2). `Content-Type: application/json`, identity encoding, a
16 KiB body cap, strict UTF-8 and strict JSON (duplicate keys, lone surrogates and non-canonical number tokens refused).
Exact key sets per action; any other key — a shift, drawer, employee, tenant or binding key included — is
`invalid_request` (400) before any RPC call.

| Action | Keys beyond `action`, `pin_session_id`, `device_id`, `device_session_token`, `attempt_id` |
|---|---|
| `start` | `mode` (`test` \| `live`), `amount_minor` (canonical integer token, 1 .. 99 999 999 999), `currency_code` (`^[A-Z]{3}$`); LIVE adds `order_id` and `expected_revision` (integer 0 .. 2 147 483 647), TEST forbids both |
| `status` | optional `source` (`auto` default \| `operator`), optional `recording_refused` (boolean) and `refusal_code` (the closed §4.55.7 list; present exactly when `recording_refused` is `true`) |
| `release` | none |
| `free_order` | `reason`, `confirmation_source` (a token), `confirmation_reference` — strings; a present `reason` / `confirmation_reference` failing its field rule (§9) is `invalid_request` |

`attempt_id` is the canonical lowercase UUID v4; `pin_session_id`, `device_id` and `order_id` are canonical lowercase
UUIDs; `device_session_token` is 1 .. 4096 UTF-16 code units, not blank, without C0 control characters or DEL.

### 4.2 The two database clients and the caller binding (§4.55.2; D-060 point 2)

- **Caller-scoped client** (`lib/caller.mjs`): the caller's own `Authorization` header plus `SUPABASE_ANON_KEY`; it
  calls only `public.card_attempt_context`. An upstream 401 / 403 (JWT refused by PostgREST) is `invalid_session`.
  A successful answer becomes a request-local *proven context*; its `caller_auth_user_id` is the only binding value
  the service calls of that request ever carry.
- **Service-role client** (`lib/ledger.mjs`, the only module that names `SUPABASE_SERVICE_ROLE_KEY`): the handler
  holds only an opaque key source (a frozen empty object) that no other module can unwrap; the handler's four-name
  environment accessor throws for the key's name. The client opens per request from a proven context and refuses any
  other value, so no service-only call can precede a successful proof, and the binding is never a body field, a cached
  proof or another request's value. Every call is one PostgREST RPC — one transaction at the platform default READ
  COMMITTED; no multi-call transaction, no isolation header. The proof shows request wiring only; hosted isolation is
  not validated (§12).
- **Scope of the service read** (RISK R-003, defence in depth): the claim's and the adapter read's organization and
  restaurant must equal the proof's; the claim's device must equal the requesting device (every role), and for a
  cashier the adapter read's attempt must belong to the requesting device. Otherwise no provider call is made: `start`
  answers the claim's own envelope, and `status` / `release` answer `unavailable`.

| Action | Calls, in order (S = service-role client) |
|---|---|
| `start` | flag + configuration + profile checks (no I/O) → context(order/attempt NULL) → S `card_attempt_claim` → only when `claim_created = true` and the claim's scope, stored keys and the attempt's own frozen references check out: one provider commit (deadline) → S `card_attempt_finish(source='commit')` |
| `status` | context(attempt) → S `card_attempt_adapter_read` (scope checked) → a set `resolution`: the envelope → approved + `recording_refused`: S `card_attempt_mark_recording_result`; `sent` / `unknown` / `released`: poll cap → minimum interval → own records servable → one provider lookup → S `card_attempt_finish(source='lookup')`; otherwise the envelope |
| `release` | context(attempt) → not `sent` / `unknown` or resolved: the envelope → S `card_attempt_adapter_read` (scope checked) → minimum interval → own records servable → S `card_attempt_mark_release_requested` → one provider release → S `card_attempt_finish(source='release')` |
| `free_order` | context(order/attempt NULL) → role not `manager`+: `permission_denied`, nothing else → S `card_attempt_free_order` |

The five session-proving service calls pass `p_caller_auth_user_id` = the same request's proven
`caller_auth_user_id` (the native transport principal — an `auth.users` id — which is never the PIN employee);
`card_attempt_finish` takes no binding and receives the row id and scope facts that the same request's claim or
adapter read returned, never POS values.

### 4.3 Answers

One success envelope (§4.55.4), projected through a closed allowlist: `ok`, `attempt_id`, `state`, `classification`,
`provider_return_code?`, `refusal_code?`, `anomaly_code?`, `resolution?`, `recorded`, `recoverable?`, `resume_count?`,
`payment_id?`, `amount_minor`, `currency_code`, `server_ts`. Adapter-only keys (row id, references, provider keys,
deadlines, counters) never reach the POS. Refusals: `{ok:false, error, detail?, attempt_id?, attempt_state?,
server_ts?}` with closed tokens. HTTP: 200 for every typed answer, 400 `invalid_request`, 401 `invalid_session`, 403
`origin_not_allowed`, 404 `not_found`, 405 `method_not_allowed`, 503 `provider_unavailable` and `unavailable`
(infrastructure or an unreadable upstream answer). A malformed upstream answer fails closed; nothing is logged.

## 5. 001E constants (§4.55.4, §4.55.5)

| Constant | Value | Bound |
|---|---|---|
| Request body read | 5 s, 16 KiB | a body that stalls is `invalid_request` and its stream is cancelled |
| RPC deadline (headers and body) | 5 s per call | — |
| Start answer window | 3 s after the claim | the POS is not held for the terminal interaction |
| Commit budget | 100 s | commit plus one finish call below the 120 s `start_deadline_at`, and below the 150 s request idle timeout |
| Lookup / release deadline | 6 s each | — |
| Automatic poll cap | 90 per attempt (`auto_poll_count`) | `source='auto'` of a cashier only; `operator` and `manager`+ calls are never refused `poll_limit` (§4.55.5) |
| Minimum interval | 3 s between provider lookups of one attempt (`last_lookup_at`) for every source and role, and between release requests (`release_requested_at`); database clock (`server_ts`) | inside it the stored envelope, with no provider call and no write; an absent or unreadable stamp is `unavailable`; a stamp ahead of the clock never suppresses |
| Provider reply cap | 256 KiB | larger replies are unreadable |

`test/static_guard.test.mjs` pins every value and these relations.

**Worst-case answer times** (body read excluded), for 001C's dedicated transport timeout: `start` 2 × RPC + window =
13 s; `status` 3 × RPC + lookup = 21 s; `release` 4 × RPC + release = 26 s; `free_order` 2 × RPC = 10 s. `status` and
`release` exceed the POS's default 15 s bound, so 001C needs a dedicated timeout for this endpoint (review D4).

**Best effort under concurrency (reviews D1, B2-F6).** The poll cap and both minimum intervals are check-then-act on
the adapter read: overlapping requests can each pass them, and a failed finish stamps and counts nothing. 001F must
poll one request at a time per attempt and back off on 503. An atomic reservation under the row lock (stamp, count and
decide in SQL before the provider call) would be a separately approved 001D amendment.

**The release interval (reviews B6, B2-F2).** §4.55.6 sets no release rate; 001E adds one: a release requested within
3 s of `release_requested_at` answers the stored envelope with no mark and no provider call. That answer is not a
confirmation (only state `released` confirms a release; the answer adds no refusal code of its own, and a stored
`release_failed` is that of an earlier failed release); a retry after the interval marks again and calls the provider.
If a mark commits but its answer is lost (503), a retry inside the interval therefore sends nothing; the POS treats
every release answer other than `released` as unconfirmed and keeps polling `status` (001F). An absent or unreadable
stamp answers `unavailable`; a stamp ahead of the database clock never suppresses a call (reviews B2-F1, B2-F5).

**Coverage (review D5).** At the minimum interval, 90 automatic polls span at least 89 intervals of 3 s (about 267 s),
longer than the 120 s start deadline. The final sizing waits for the real interaction times (Q-048, Q-050); `poll_limit`
must surface the "Check status" path in 001F.

**The commit after the answer (review D3).** It continues through `EdgeRuntime.waitUntil` only for the worker's
REMAINING lifetime: the platform wall clock (150 s Free, 400 s paid) counts from the worker's start, which may predate
this request. This is an optimization, never a guarantee and **not a durable queue**. If the worker ends first, the
attempt stays `sent`, then `unknown`, and is recovered only by `status` lookups under the same identity; nothing is
resent, released or freed automatically.

**A claim whose answer is lost (review D4).** If the claim commits in SQL but its answer misses the RPC deadline, the
adapter answers `unavailable` and sends no commit. The attempt is `sent` with no provider request behind it; what its
lookups return is Q-048 (open): a not-found, pending or failed lookup leaves it `sent` until SQL moves it to `unknown`
after the start deadline, and the operator path concludes it. The runbook note belongs to 001H.

## 6. Provider engine and the vendor wire profile (gate W1)

The adapter talks to the provider through `lib/provider/engine.mjs`, a profile-driven JSON-over-HTTPS client: the
request builder (credential and PIN-pad values from the frozen references, the two outbound keys exactly as the claim
or adapter read returned them, the amount as a raw number token), the bounded reply reader (raw number tokens, no
float parse, one leading byte-order mark tolerated as RFC 8259 allows) and the closed classification of §7. Every
vendor fact (routes, request and reply field names, fixed request values and code tables) is a **wire profile**,
validated against a closed schema before use: all eight essential reply keys mapped; return-code lists as canonical
integers within ±999 999; the two approval lists, every status list (incl. the not-found and pending status lists)
and the four return-code lists (success, duplicate, not found, pending) each pairwise disjoint, the success / not-found
and success / pending pairs since `f487ef5f` (fact-check B1); currencies limited to two-decimal ILS, the only exponent
the lexeme can carry (Q-007 interim).

API_CONTRACT §4.55 states that vendor field names, limits and codes are runtime configuration fixed by the owner's
sealed evidence (**Q-047**, **Q-049**) or observed only inside the sealed TEST facility (**Q-048**, **Q-050**), and the
merged packet names none. 001E therefore ships **no vendor profile**: `index.ts` passes none, so `start` answers
`provider_unavailable` before any database call and `status` / `release` answer it only where a provider call would
follow. The tests drive the engine with an obviously synthetic profile. Delivering the real profile is the named gate
**W1** (§13), by one of two routes, a command-room choice:

- a separately reviewed source module bound to the sealed evidence, passed by `index.ts` and pinned by a static guard
  (preferred by the reviewers; the handler is unchanged);
- an additive `wire` object in `POS_CARD_PROVIDER_CONFIG`, which needs a §4.55.9 amendment and a change to
  `lib/config.mjs` and the handler wiring.

**W1 review checklist** (the engine cannot enforce these; reviews A5, A7, B1, B4, C-9, D2, D6, E12, E13):

1. Every fixed request value is tied to its D-052 point 4 rule, with sealed byte-level fixtures of the real requests.
2. The code tables are bound to the sealed evidence. SQL approves a commit only with return code `0` (001D M2), so a
   commit approval lands directly only if `return_success` contains `"0"`; otherwise, and on any other success code
   the adapter accepts, the commit finishes `unknown` and only a later status lookup can conclude it.
3. The vendor's complete status vocabulary (Q-048): every charge-bearing status must sit in `status_approved` or an
   anomaly list, because a declined approval type beside a status in no list declines; and every status value and
   return code the not-found and pending replies carry, so they stay unchanged (a status in no list never hides a
   listed not-found / pending return code, but a listed status always decides). A success code cannot double as a
   lookup code; a status-less reply carrying only the success code is `failed`, which SQL treats like not found.
   *(2026-10-28: superseded in part by **D-063**, BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-W1-LOOKUP-SAFETY-001, not
   merged — a present status in no list is now the `out_of_contract` anomaly before any declined type or return
   code, so the completeness of the status values decides availability, not safety (the declined approval-type and
   not-found / pending return-code lists and the reply field names still matter for safety); see the [W1-LOOKUP-SAFETY-001 packet](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_W1_LOOKUP_SAFETY_001_EXECUTION.md)
   §3 and §7.)*
4. The reply shape and encoding against the sealed replies: byte-order mark, duplicate keys, nesting depth, size,
   number versus string types. *(2026-10-28: for the amount and the tip, **D-064**
   (BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-INBOUND-MONEY-NORMALIZATION-001, not merged) fixes the type — a JSON number token
   with zero, one or two fraction digits; a profile that accepts `string` for either is refused.)*
5. No vendor field is mapped into a reference or code key unless the evidence shows it cannot carry card-derived data
   (§9: a bare BIN plus last four passes both layers).
6. ILS with two decimals only.
7. Profile retention: never removed or changed while any attempt is `sent`, `unknown` or `released` (DEPLOYMENT
   §18.5), or a per-attempt profile version frozen and checked before each lookup or release (none is stored today).
8. The step (1) refusal for a currency the profile cannot encode (`provider_unavailable` before the proof): keep it
   and amend §4.55.4, or let the claim answer its typed currency refusal.

`POS_CARD_PROVIDER_CONFIG` inner shape fixed here (names are RestoFlow's; no credential secret, PIN-pad identifier or
base URL is ever logged, returned or passed to SQL): `environment` (`test` \| `production`), `base_url` (`https://`
origin and optional path, no credentials, query or fragment), `key_format` (one of 001D's `alpha16-l20-v1` /
`alpha16-l24-v1` / `alpha16-l32-v1`), `credentials` (`credential_ref` →
`{mode, scope, restaurant_id?, secret: {name: string}}`), `terminals` (`terminal_ref` → `{credential_ref, pinpad_id}`);
references match `^[a-z0-9_-]{1,64}$` and live in prototype-free maps. SQL receives only the `environment` token (claim
and adapter read), the `key_format` token (claim) and the projections `terminal_ref → credential_ref` and
`credential_ref → {mode, scope, restaurant_id}`. Before `start`, every credential record must feed the profile; before a
lookup or release, only the attempt's own frozen records matter: they must still exist, agree, carry the attempt's mode
in the environment of that mode (`test` / `production`) and feed the profile.

## 7. Reply minimization and the dropped-field event (gate G1)

The reply reader extracts exactly the allowlisted keys of the 001D packet §4.2 by the profile's field names and never
reads a card number, BIN, expiry, token, receipt text, raw record or vendor message. Absent keys, JSON `null` and
values blank after the canonical trim are absent (no value, no failure). Each present value is checked with the same
field rule as SQL (§9; JSON type, canonical return code, the amount grammar, ISO currency, RFC 3339 timestamp with an
offset of at most 15:59) and, in a structured field, with a truncated-card shape check that only drops more than SQL:
once every single `-` / `_` between two digits is removed (grouped renderings), a 4-8 digit group, a run of two or more
`-` / `_`, then 4 digits (reviews B1, LA-3). The adapter refuses the end-of-day
`24:00:00` and a leap second `:60`, which PostgreSQL accepts; such a timestamp is dropped. Command-room rule G: a
failing field is **dropped by the adapter** and never placed in an RPC argument; a TEST attempt's card and
provider-reference fields are never read.

Classification (001D M2; reviews A1-A4, C-1-C-4, D2):

- **Commit**: an unreadable tip is the `out_of_contract` anomaly; any other failing essential field is `unknown`; a
  phone-authorization request and a duplicate refusal are `unknown` (the duplicate goes to the lookup path, even with a
  declined type); then a declined approval type; then an approval (error flag false, a success code, an approved
  type), whose non-zero tip is the `amount_mismatch` anomaly; anything else `unknown`.
- **Lookup** (delta reviews LA-1, LA-2; verification V1-1, V1-2): (1) an unreadable status is the `out_of_contract`
  anomaly; (2) a not-found or pending reply - a listed not-found / pending status or, when the reply carries no status
  or a status in no list, a listed not-found / pending return code - is `not_found` / `pending` whatever approval type,
  amount or reference it also carries (a failing one is only dropped), and SQL leaves the attempt unchanged except that
  a `sent` row past its start deadline moves to `unknown`; a contradiction there never concludes `declined` or an
  anomaly (§4.55.5); (3) void, refund, partial-refund and pre-authorization statuses are their anomaly
  (`out_of_contract` when an essential field failed), never overridden by the approval type; (4) an approved status is
  approved unless the type declines it or an essential field failed (`out_of_contract`); a listed status always decides
  over the return code; (5) a declined approval type with no failing essential field declines, also beside a status in
  no list, because the vendor has no decline status (Q-048); (6) any other status, a declined type with a failing
  essential field, and, with no status, a reply reporting a transaction - an approved type, a readable amount, or an
  unreadable approval type, amount, tip or return code (the result field) - are the `out_of_contract` anomaly; an
  unreadable error flag, phone flag or currency alone, and a reference (non-essential), never decide; (7) anything else,
  and a reply that is not a readable JSON object, is `failed` (no provider fact; SQL stamps the lookup, counts it when
  `source='auto'` and, as in (2), moves a `sent` row past its start deadline to `unknown`). *(2026-10-28: steps (2),
  (5) and (6) are narrowed by **D-063** — a present status that is unreadable or in no list is the `out_of_contract`
  anomaly first, and only an absent status lets a not-found / pending return code decide or a declined type
  decline; see the [W1-LOOKUP-SAFETY-001 packet](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_W1_LOOKUP_SAFETY_001_EXECUTION.md). Not merged; the text above records this ticket's state at `d5456624`.)*
- **Release**: confirmed only by error flag `false` and a success return code.

SQL re-validates every outcome against the fields it receives and stays the final arbiter.

**Gap G1 (contract).** `card_attempt_finish` is the only writer of `security.card_provider_field_dropped`
(**D-058** point 10) and records only failing values it receives, so the adapter-side drop leaves that event
unwritten. The TESTING_STRATEGY Edge lane's "with its event written" and the RUNBOOKS §8 signal cannot be met by 001E
alone. The reviews add three consequences (A6, B3, C-8, D7, E11):

- the SQL backstop for an unreadable essential field (`v_essential_failed`, `v_tip_failed`) no longer fires, so the
  adapter alone carries that guarantee (pinned by the commit and lookup essential-field vectors);
- format drift in a non-essential reconciliation field is silent;
- the adapter already computes the `{field, rule}` tokens and discards them.

Minimum correction, recommended unanimously by the reviewers: an additive allowlisted `p_provider_fields` key carrying
only `{field, rule}` tokens, which `card_attempt_finish` records as the event and feeds into M2's essential and tip
flags (a 001D migration, separately approved), plus an adapter test that each dropped field emits exactly its token
pair and never the value. The reviewers reject the alternative ruling (failing values as transient arguments): those
values are exactly the `digit_run` / `masked_pattern` ones and it reverses rule G. Until G1 closes, RUNBOOKS should
say that dropped fields are silent; RUNBOOKS is outside this ticket's files.

*(2026-10-27: G1 is corrected locally by BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-DROP-EVIDENCE-001 under **DECISION
D-062** — the adapter forwards the `{field, rule}` tokens as `dropped_fields` and `card_attempt_finish` records the
event and applies the flags; see [its packet](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_DROP_EVIDENCE_001_EXECUTION.md). Not
merged. The text above records this ticket's state at `d5456624`.)*

## 8. Money (D-052 point 4; D-056 point 9)

Amounts never pass through a JavaScript `Number`: the request parser keeps number tokens as text, `amount_minor` is
validated as a canonical integer token and converted with `BigInt`, the outbound lexeme is built by integer division
and modulo (`BigInt`), and the provider body carries it as an unquoted JSON number token written by the raw-number
serializer. Inbound provider amounts are read as raw token text (a JSON string or number token) and accepted only when
they match `^(0|[1-9][0-9]{0,8})\.[0-9]{2}$`; they reach SQL as that exact text. Bounds: 1 .. 99 999 999 999 minor
units (the grammar's nine integer digits). Only ILS, whose exponent is 2, can be encoded. A static guard forbids
`Number(`, `parseFloat`, `parseInt`, `toFixed`, `toLocaleString`, `Intl` and `Math.` in the function source; it does
not scan the timestamp module or the runtime entry `index.ts`, which holds none of them. The repository's
`tools/check_no_float_money.sh` scans the Dart apps and packages only.

*(2026-10-28, **D-064**, BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-INBOUND-MONEY-NORMALIZATION-001, not merged: inbound
amounts and tips are now read only as raw JSON number tokens matching `^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$`, and
`canonicalInboundMoney` in `lib/money.mjs` right-pads the fraction so that they reach SQL as the canonical
two-decimal lexeme, the number zero (`0`, `0.0`, `0.00`) as `0.00`. A missing key, a JSON null, an empty string or a
string of Space_Separator characters only is absent — never zero — and every other non-empty JSON string (`"0"` and
`"12.30"` included) is a `format` failure. The outbound path and SQL are unchanged. See the
[INBOUND-MONEY-NORMALIZATION-001 packet](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_INBOUND_MONEY_NORMALIZATION_001_EXECUTION.md).)*

## 9. Text policy (D-059 point 4)

`lib/text_policy.mjs` applies the closed policy of `app.card_safe_text_failure` (raw and canonical checks, NFKC, the 17
Space_Separator trim, the 4 × max length bound, the digit-like count, the masked pattern, the visible-character rule)
with `lib/text_policy_tables.mjs`, which holds the migration's seven class constants verbatim in PostgreSQL escape
syntax; `pgClassToJs` in `lib/text_policy.mjs` converts them mechanically to JavaScript Unicode classes. Parity is
pinned three ways:

- **Tables.** The seven constants and the trim set equal the migration's byte for byte, and the field table equals
  the SQL `CASE` exactly (charset, minimum, maximum, free text), with min − 1 / min / max / max + 1 vectors per field.
- **Vectors.** `test/sql_vectors.mjs` evaluates the SQL of `supabase/tests/bizbot_zcredit_001d_field_rules_test.sql`
  at run time (literals, `U&` escapes, `||`, the functions and `SELECT` / `VALUES` / `CROSS JOIN LATERAL` shapes that
  file uses, and the pgTAP `is()` / `results_eq()` statements; anything else, or a construct whose PostgreSQL meaning
  differs from JavaScript's, fails), so no vector value is copied into JavaScript. It applies: the 520 `_fr_v` vectors
  (FR-1 .. FR-23, FR-30); the trim set (FR-24, FR-25); the review-fix-12 mask vectors (FR-236 .. FR-239); the
  review-fix-13 / 14 length-bound and absence vectors (FR-241 .. FR-251, FR-247 as a 500 ms CPU-time bound in JavaScript); the
  review-fix-26 bound precedence (FR-285); the 792 C1-4 vectors in 14 groups, raw and canonical (FR-296 .. FR-319);
  and the C1-4 class tables and code-space sweeps, i.e. every code point U+0001 .. U+10FFFF without surrogates
  (FR-291 .. FR-295, FR-298, FR-300, FR-302 .. FR-305, FR-310, FR-311, FR-318, FR-320). The ported helpers and
  predicates (`fr_c1_d`, `fr_c1_mixed`, `fr_c1_w`, the `_fr_c1cp` / `_fr_c1fam` derivations, `fr_c1_bad`, the FR-24 /
  FR-25 queries, the `_fr_abs` Space_Separator rows) are pinned to their SQL text. Not ported: FR-26 .. FR-29 and FR-41
  (single canonical and UUID cases that other vectors cover) and every assertion that needs the database.
- **Differential.** Against the live function on a local PostgreSQL 17.6 (evidence `tests/TEXT_POLICY_DIFFERENTIAL.txt`):
  every code point in five shapes (5 560 315 comparisons) and 180 000 random strings, 0 mismatches.

An input that passes the raw allowlist holds only code points assigned in Unicode 15.1, whose NFKC mappings are
stable, so a NEWER runtime cannot diverge; a module-load self-check of the four Unicode 15.0 NFKC mappings of
Cyrillic Extended-D makes the policy refuse every value on an older runtime (review C-10). The check is exported as a
function of a normalize callback, and a child process that simulates an older runtime proves the fail-closed result:
every value refused, so `start` answers `provider_unavailable` with no call (delta reviews LA-4, LC-04). The field
table leaves the module only as frozen plain data (LA-5).

**Limitation (001D packet §11 item 35; corrected by review B1).** The policy is not an absolute masked-card sanitizer.
The residual vectors recorded there pass both layers in the free-text `reason`: masked groups joined by dash-like `Lo`
or sideways-I letters, the non-mask asterisk U+2733, and `Lm`-only reasons. In a structured field the SQL rule treats
`-` and `_` as separators, so more forms pass it. A truncated number masked with a run of two or more hyphens or
underscores, also in grouped renderings, is dropped by the adapter's pre-filter before any RPC argument (§7). A bare
BIN plus last four (at most 11 digits) and a "mask" of a single separator pass both layers; they are recorded
residuals and a W1 review item (§6). No provider value is ever routed into a free-text field.

## 10. Test lanes (`node --test supabase/functions/pos-card-charge/test/*.test.mjs`)

| File | Covers |
|---|---|
| `boundary.test.mjs` | method, path, query, origin, JWT shape, media type, body cap, strict JSON, exact key sets, UUID forms, action schemas, field rules of `free_order`, the stalled-body read deadline, the request and proof-answer byte caps, no timer outliving a request — all before any RPC, except the proof-answer cap and two timer paths (a refused proof, an RPC deadline), which follow the context-proof call |
| `start.test.mjs` | refusal order (the step-(1) refusals — flag, configuration, profile — before the proof, and the proof before the claim); every claim refusal and the replay / concurrent loser with zero provider calls; uncertain claims with their exact answers; exactly one commit for `claim_created`; approval / exact decline / unknown / duplicate (also with a declined type) / phone authorization / anomaly; essential-field, absent / null / blank and truncated-card vectors; typed finish answers; deadline, network loss, HTTP errors (a 5xx with an approval body is unknown) and late replies; the start window; provider request headers; TEST order-less with no recording call; LIVE under a production configuration |
| `status.test.mjs` | lookups for `sent` (before and after its deadline), `unknown` and `released`, automatic and operator; the dying-worker recovery; foreign-scope reads (manager+ held to the restaurant); the classification precedence matrix (not-found / pending first, a decline beside an unlisted status *(superseded 2026-10-28 by **D-063**: the `out_of_contract` anomaly)*, references never decide) and essential-field vectors; an unreadable body is `failed`; a leading BOM; poll cap (89 / 90) and the minimum interval for every source and role; absent, unreadable and future stamps; own versus unrelated configuration records and a credential of another mode; LIVE under a test configuration; frozen references and rotation; an approved attempt under a repointed configuration; the approved recording-refused report without configuration; resolved attempts; typed finish answers with their exact bodies |
| `release.test.mjs` | advisory release, confirmation (error flag and code), failure without retry, the no-mark paths (no profile, no route, own incomplete record, a credential of another mode), an unrelated incomplete record, foreign scope (manager+ held to the restaurant), the release interval (not a confirmation), absent, unreadable and future stamps, a mark refusal, typed finish answers |
| `free_order.test.mjs` | role before lookup, field rules at the boundary, the service call only after a `manager`+ proof |
| `binding.test.mjs` | the binding on all five session-proving calls, the transport principal distinct from the PIN employee, parallel requests for `start`, `status` and `release` interleaved deterministically, proofs bound to their request, the opaque key source, proof refusals stopping every service call |
| `provider.test.mjs` | profile schema (incl. essential keys, canonical return codes, disjoint lists, ILS only), reply extraction by name only, absent / null / blank values, commit / lookup / release classification units, canonical return codes, the truncated-card drop (grouped, two-separator and split shapes) with legitimate values kept, the `provider_saved_at` offset bound, silence |
| `money.test.mjs`, `json.test.mjs` | lexemes and bytes (0.01, 1.00, 12.34, a TEST cap, a LIVE cap, the bound), the inbound grammar vectors, raw tokens *(2026-10-28: the grammar vectors are those of the canonical lexeme; the inbound ones of **D-064** are in `inbound_money.test.mjs`)* |
| `inbound_money.test.mjs` *(2026-10-28, **D-064**, not merged)* | the inbound provider-money grammar and canonicalization, the commit tip and lookup amount cases through the handler, the outbound bytes, the profile schema for the amount keys |
| `config.test.mjs` | configuration shape, projections, the master flag, the four-name accessor, prototype-free maps (`__proto__` / `constructor` references) |
| `text_policy.test.mjs` (+ `sql_vectors.mjs`) | §9: tables, field table, escape conversion, the Unicode self-check (an older runtime in a child process), the 001D text-policy vectors and sweeps listed there, item 35 recorded |
| `static_guard.test.mjs` | the reviewed file set, environment names, key-source confinement, no logging or other network channel, no remote import or URL, the closed RPC set, float-free money, the timing and byte-cap pins (the start-deadline relation read from the migration), `config.toml` and CI pins, synthetic hosts only, no secret in any answer |
| `network_guard.test.mjs` | the network guard itself: every channel it closes (fetch, WebSocket and EventSource when the runtime defines them, net, tls, http, https, http2, dgram, and every resolver entry point of `dns`, `dns.promises` and both `Resolver` classes) throws and is recorded; each probe passes arguments the real API refuses before any I/O, so even a weakened guard sends nothing (fact-check C4) |

Every test file installs the network guard first (fetch, WebSocket, EventSource, net, tls, http, https, http2, dgram
sockets, every dns resolver entry point) and, after its tests and once every background task has settled, asserts that
nothing reached the real network and no unscripted RPC, provider operation or host was called.

## 11. Static guards

The function reads exactly `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `POS_CARD_PAYMENTS_ENABLED` and
`POS_CARD_PROVIDER_CONFIG` through a four-name accessor, and `SUPABASE_SERVICE_ROLE_KEY` only inside `lib/ledger.mjs`
through an opaque key source that no other module can unwrap. `Deno` is used only in `index.ts`, which passes no
timing and no profile; there is no `console`, WebSocket, EventSource or other network channel, no remote import, no
`sync_push`, `record_payment` or `payment.create`; the RPC set is exactly the seven card functions; `fetch` is called
only by the bounded transport; the timing constants and their relations are pinned.

## 12. NOT VALIDATED here

- Real provider acceptance, field names, codes and timing; Q-047 non-settlement, Q-048 lookup semantics, Q-049 key
  compatibility, Q-050 device facts.
- Hosted READ COMMITTED behaviour and hosted JWT verification; hosted secrets and configuration.
- The Deno / Supabase edge runtime: the suite runs on Node with an injected fetch and `waitUntil`; neither Deno nor
  the edge runtime was run, and no `supabase functions serve` smoke was made. The real worker lifetime is not measured.
- Node 24 on Linux, as CI runs it (`storefront/.nvmrc`): locally the suite passes on Node 22.14 and on Node 24.19 on
  Windows (the Node bundled with the installed Codex runtime), and the text-policy differential gives 0 mismatches on
  both; the CI run itself is not observed.
- The Unicode data of the hosted Deno runtime: the self-check makes an older runtime fail closed (every provider field
  dropped, every `start` `provider_unavailable`), which a deployment smoke must rule out.
- Terminal behaviour; the POS transport (001C) and POS flows (001F).

## 13. Remaining gates

- **W1** vendor wire profile (§6, with its review checklist): before any real provider action, bound to the sealed
  Q-047 / Q-049 package. *(2026-10-28: the W1 wire-evidence package was accepted; **D-064**
  (BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-INBOUND-MONEY-NORMALIZATION-001, local, not merged) closes only its two
  representation gaps — the zero tip and the fraction-digit form of an echoed amount; the profile stays unwired.)*
- **G1** dropped-field event (§7): the recommended 001D correction, or a command-room ruling. *(Corrected locally by
  BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-DROP-EVIDENCE-001, **D-062**, 2026-10-27; not merged.)*
- 001C: a dedicated transport timeout for this endpoint (§5 worst cases). 001F: single-flight polling with back-off,
  and `poll_limit` surfaced as "Check status". 001H: the runbook notes of §5 and §7.
- Optional 001D amendment: an atomic lookup reservation (§5, review D1).
- Q-047, Q-049 (hard owner gates), Q-048, Q-050, Q-052; DEPLOYMENT §18 (migration PRE / POST, dark deploy, TEST secret
  setup, physical TEST run, LIVE enablement), each separately approved.
- 001D merge (S14 C), 001G; any publication or merge of this branch needs its own process decision.

## 14. Results

### 14.1 Review

A fresh-context Claude review ran on the first complete head (`832e8260`) in five lenses: A contract and SQL
interface fidelity; B security, authority and data minimization; C money, JSON, text policy and the provider
engine; D failure semantics, timing and runtime; E test evidence quality. Every finding was verified adversarially:
45 findings, 28 confirmed, 17 partial, 0 refuted. Verified severities: 4 MAJOR (B3, C-1, E1, E3), 14 MINOR and
27 NOTE; no BLOCKER. The second fresh-context review of the fix batch (`832e8260..13ceb673`) and its verification
rounds are summarized in §14.3, and the fact-check of this packet in §14.4.

| ID | Verified | Disposition |
|---|---|---|
| A1 | PARTIAL, NOTE (dup. of C-1) | Fixed with C-1: a readable status decides; void / refund / partial-refund / pre-authorization are their anomaly even with a declined type |
| A2 | CONFIRMED, MINOR | Fixed: a duplicate refusal is `unknown` (lookup path) before a declined type |
| A3 | CONFIRMED, MINOR | Fixed: a 2xx lookup body that is not a readable object is `failed`, not an anomaly |
| A4 | CONFIRMED, MINOR | Fixed: transaction evidence without a status is the `out_of_contract` anomaly |
| A5 | CONFIRMED, NOTE | Recorded: W1 checklist item 8 (§6); no code change |
| A6 | CONFIRMED, NOTE | Recorded in §7 (G1 consequences, recommended correction); the timestamp offset bound aligned with PostgreSQL (15:59), the residual strictness documented |
| A7 | CONFIRMED, NOTE | Recorded: W1 checklist (§6) |
| B1 | CONFIRMED, MINOR | Fixed in part: the truncated-card pre-filter drops hyphen / underscore-masked forms in structured fields; the bare BIN + last four stays a recorded residual and a W1 item; §9 corrected |
| B2 | PARTIAL, NOTE | Fixed: opaque key source, four-name accessor, static and runtime guards |
| B3 | CONFIRMED, MAJOR | Fixed in the adapter: commit and lookup essential-field vectors; the SQL backstop itself needs the G1 correction (§7) |
| B4 | PARTIAL, NOTE | Recorded: W1 checklist; the "handler is unchanged" sentence corrected (§6) |
| B5 | CONFIRMED, NOTE | Accepted: §4.55.4 mandates step (1) before the proof; no change |
| B6 | CONFIRMED, NOTE | Fixed: the minimum interval applies to every source and role, and to release requests |
| C-1 | CONFIRMED, MAJOR | Fixed (lookup precedence, §7) |
| C-2 | PARTIAL, NOTE | Fixed with A2 |
| C-3 | PARTIAL, NOTE | Fixed: all eight essential reply keys must be mapped |
| C-4 | PARTIAL, NOTE | Fixed with A4 |
| C-5 | CONFIRMED, MINOR | Fixed: exact field-table parity with boundary vectors |
| C-6 | CONFIRMED, MINOR | Fixed: the 001D text-policy vectors, sweeps and C1 groups applied from the SQL at run time, except the single cases §9 lists as not ported (§9) |
| C-7 | CONFIRMED, NOTE | Fixed: canonical return codes in profile lists and replies |
| C-8 | PARTIAL, NOTE | Recorded: G1 recommended correction (§7) |
| C-9 | PARTIAL, NOTE | Recorded: W1 checklist; ILS-only enforced by the profile schema |
| C-10 | CONFIRMED, NOTE | Fixed: module-load Unicode self-check, fail closed |
| C-11 | CONFIRMED, NOTE | Fixed: prototype-free configuration, secret and profile maps |
| D1 | CONFIRMED, MINOR | Recorded as best effort (§5); 001F single-flight polling; an atomic reservation is an optional 001D amendment |
| D2 | CONFIRMED, NOTE | Fixed in the schema (not-found and pending status lists); stays W1 / Q-048 evidence item 3 |
| D3 | CONFIRMED, NOTE | Fixed: the remaining-lifetime wording and the static timing pins |
| D4 | CONFIRMED, NOTE | Fixed in part: shorter RPC deadline and window (`start` 13 s); `status` 21 s and `release` 26 s recorded for 001C; the lost-claim case recorded (§5) |
| D5 | CONFIRMED, NOTE | Fixed in part: cap 90 (at least 89 intervals of 3 s, about 267 s, at the minimum interval); final sizing after Q-048 / Q-050 |
| D6 | PARTIAL, NOTE | Recorded: W1 checklist items 4 and 7 |
| D7 | PARTIAL, NOTE | Recorded: G1 (§7); a RUNBOOKS note recommended (outside this ticket's files) |
| E1 | CONFIRMED, MAJOR | Fixed: lookups for `sent` (both sides of its deadline), `unknown` and `released`; the dying-worker recovery |
| E2 | PARTIAL, MINOR | Fixed: typed finish answers on `start`, `status` and `release` |
| E3 | CONFIRMED, MAJOR | Fixed: key-source confinement, provider request header assertions, static guards |
| E4 | PARTIAL, MINOR | Fixed: lookups and releases depend only on the attempt's own records; a release `NotSendable` is `provider_unavailable` |
| E5 | PARTIAL, MINOR | Fixed: every file asserts no stray call or host; more channels blocked; static guard for other network channels |
| E6 | CONFIRMED, MINOR | Fixed: the service read's scope is checked on `status` and `release` |
| E7 | CONFIRMED, MINOR | Fixed: the timing constants and relations are pinned |
| E8 | CONFIRMED, MINOR | Fixed: absent, null, blank and format-character vectors at the reply level and through the handler |
| E9 | CONFIRMED, MINOR | Fixed: a 5xx with an approval body is `unknown`; error flag `true` with code 0 is `release_failed`; the lookup precedence is pinned |
| E10 | PARTIAL, NOTE | Fixed: LIVE flows run under a production configuration and the adapter checks the environment of the mode (the fake RPC does not emulate `card_config_mismatch`) |
| E11 | PARTIAL, NOTE | Recorded: G1 recommended correction with its adapter test (§7) |
| E12 | PARTIAL, NOTE | Recorded: W1 checklist items 1 and 7 |
| E13 | PARTIAL, NOTE | Recorded with A5 |
| E14 | CONFIRMED, NOTE | Fixed: parsed-field checks, exact uncertain-claim answers, the amount test title, parallel `status` / `release` bindings |

### 14.2 Local evidence (source-matched to the package head)

- **Commits** (on the #370 head `54b19ab5`; local, no upstream): `ec6ef3e3` this packet; `2a14d196` the source;
  `5dd99406` the tests; `3b1e5cd0` the `config.toml` block; `e18ece1d` the CI step; `832e8260` tests (the first
  reviewed head); `b1f00a3f`, `d7010418` and `13ceb673` the first review's dispositions; `4ded5612` the second review's;
  `aeec2897` the verification's; `6aa59415` the final verification's pins; `206a63db` this packet's results;
  `f487ef5f` and `7264f501` the fact-check's schema fix and network-guard test (§14.4); `002cf905` the fact-check's
  corrections; and the commit that records the delta verification. The suite is green at `e18ece1d`, at `832e8260` and
  at every commit from `d7010418` on; `5dd99406` and
  `3b1e5cd0` fail only the `config.toml` and CI pins that land in the next two commits, and `b1f00a3f` fails 37 of its
  88 tests because its tests land in `d7010418` (evidence `tests/PER_COMMIT_SUITE.txt`).
- **Suite** (`node --test supabase/functions/pos-card-charge/test/*.test.mjs`, Node 22.14.0 on Windows 11): 125 tests,
  125 pass, 0 fail, 0 cancelled, 0 skipped, 0 todo at the package head (evidence `tests/node_test_spec_final.txt`),
  and the same on Node 24.19.0 (evidence `tests/node_test_spec_final_node24.txt`).
  Every file asserts, after its background tasks settle, that no real network was reached and no unscripted RPC,
  provider operation or host was called; `network_guard.test.mjs` proves that the guard throws for every channel it
  closes.
- **Mutations** (tool `tools/mutate.py`, evidence `tests/MUTATIONS_final.txt`): 79 single-point mutations of the
  committed source, harness and constants, at least one per review and fact-check disposition with a source effect
  (M73 for A6's offset bound and M74 / M75 for B1 added after the fact-check) and four that open the network guard
  (M76..M79), run at `7264f501`: 79 killed; the tree restored clean.
- **Text-policy differential** against the live function on a local PostgreSQL 17.6 (evidence
  `tests/TEXT_POLICY_DIFFERENTIAL.txt`), re-run on the final module at `6aa59415` after the live function body was
  re-read and compared with the migration: every code point in five shapes (5 560 315 comparisons) and 180 000 random
  strings from nine seeded pools, 0 mismatches (the text-policy modules are unchanged since `4ded5612`); the same on
  Node 24.19.0, whose Unicode data is 17.0.
- **Provider calls and money bytes** (tests): exactly one commit for a fresh claim, and none for a replay, a concurrent
  loser, an uncertain or refused claim, a failed proof or any step-(1) refusal; at most one lookup or release per
  request, none inside the minimum interval or past the poll cap, none without a wire profile. The outbound amount is an
  unquoted number token (`0.01`, `1.00`, `12.34`, `50.00`, `25000.00`, `999999999.99`); the claim and the finish carry
  the integer token.
- **Guardrails**: `tools/check_no_float_money.sh` OK and `tools/check_secrets.sh` OK at `6aa59415`, `206a63db` and
  `002cf905` and at the package head (evidence `tests/GUARDRAILS_<head>.txt` and `tests/GUARDRAILS_final.txt`); the
  float check scans the Dart apps and packages only (§8).
- **Public-repo hygiene** (tool `tools/hygiene.py`, evidence `tests/HYGIENE_final.txt`): the 001E files and lines add
  no card-shaped value, masked shape, local path or e-mail address; their hits are timestamps, money bounds, the
  migration file name, regex literals, branch names and the user part of a synthetic URL. The scan also covers the
  whole `config.toml` and `ci.yml`, whose other hits are base lines outside the 001E additions.
- **Not run:** Node 24 on Linux (CI), Deno, the Supabase edge runtime, and every hosted, provider, terminal or card
  action (§12).

### 14.3 Second review and verification rounds

**Second review** (fresh context, the fix batch `832e8260..13ceb673`; three lenses: engine and SQL parity, handler and
authority, test evidence; refute-first verifiers for up to four MINOR+ candidates per lens): 21 findings. Verified:
2 MAJOR, 8 MINOR confirmed, 1 partial, 1 refuted; 8 notes and LC-05 (MINOR, beyond the lens cap) unverified, checked
first-hand here. The two MAJOR findings were regressions of the first fix batch. All are closed in `4ded5612` and
`aeec2897` (the latter refines the lookup precedence and adds LA-5's export pin, LC-01's JavaScript-only absence
vectors, LC-08's helper argument checks and LC-09's poll-span relation):

| ID | Verified | Disposition |
|---|---|---|
| LA-1 | CONFIRMED, MAJOR | Fixed: a readable not-found or pending reply is unchanged whatever it carries (§4.55.5); refined by V1-1 |
| LA-2 | CONFIRMED, MAJOR | Fixed: a declined type beside a status in no list declines again (the vendor has no decline status, Q-048) |
| LA-3 | CONFIRMED, MINOR | Fixed: grouped and two-separator masks dropped (single separators between digits removed first) |
| LA-4 | CONFIRMED, MINOR | Fixed: the self-check is tested in a child process that simulates an older runtime; offset vectors at 15:59 |
| LA-5 | NOTE | Fixed: the field table leaves the module only as frozen plain data; the export surface is pinned |
| B2-F1 | REFUTED, NOTE | Applied as hardening: an absent stamp key fails closed (SQL always emits the key) |
| B2-F2 | PARTIAL, NOTE | Documented: a release inside the interval is not a confirmation (§5) |
| B2-F3 | CONFIRMED, MINOR | Fixed: the deadline relation counts the claim's tail and reads the interval from the migration; byte caps pinned |
| B2-F4 | CONFIRMED, MINOR | Fixed: manager+ callers are tested against a foreign restaurant on `status` and `release` |
| B2-F5 | NOTE | Fixed: a stamp ahead of the database clock never suppresses a call |
| B2-F6 | NOTE | Fixed: the best-effort statement covers both intervals and the failed finish |
| B2-F7 | NOTE | Fixed: no-lingering-timer and credential-mode tests; the post-mark `NotSendable` branch is recorded as unreachable defensive code |
| LC-01 | CONFIRMED, MINOR | Fixed: FR-24, FR-25, FR-241 .. FR-251 and FR-285 applied from the SQL text, plus JavaScript-only absence vectors |
| LC-02 | CONFIRMED, MINOR | Fixed: typed finish answers on `release`; the exact resolved envelope on `status` |
| LC-03 | CONFIRMED, MINOR | Fixed: byte caps pinned, each with a behavioural vector (request, proof answer, provider reply) |
| LC-04 | CONFIRMED, MINOR | Fixed with LA-4 |
| LC-05 | MINOR (checked here) | Fixed: deterministic interleaving in the parallel-binding test; a commit budget far above the start window |
| LC-06 | NOTE | Fixed: credential mode, unreadable release stamp, offset bound and an approved attempt under a repointed configuration |
| LC-07 | NOTE | Fixed: every dns resolver entry point and dgram socket method blocked; background tasks settle before the stray check |
| LC-08 | NOTE | Fixed: the SQL evaluator refuses constructs whose PostgreSQL meaning differs, and the ported helpers refuse a zero count or a NULL separator |
| LC-09 | NOTE | Fixed with B2-F3; the poll-span relation also reads the migration's deadline |

**Verification of `4ded5612`** (three refute-first verifiers: classification, tests and harness, handler / timing /
documents): 13 findings (V1-1 and V1-2 latent behind gate W1; the rest test and harness gaps, a timing flake and
wording), all closed in `aeec2897` (the exact precedence in `CONTRACT.md` completed in `6aa59415`, F1-1 / F2-2):

| ID | Severity | Disposition |
|---|---|---|
| V1-1 | MAJOR | Fixed: a status in no list no longer hides a not-found / pending return code, so such a reply never declines; a listed status still decides |
| V1-2 | MINOR | Fixed: with no status, only an approved type, a readable amount or an unreadable approval type, amount, tip or return code reports a transaction |
| V1-3, V2-6 | MINOR | Fixed: the module's export names and the table entries' keys are pinned |
| V2-1 | MINOR | Fixed: a listed status beside a not-found / pending return code is tested to decide |
| V2-2 | MINOR | Fixed: the 16-character underscore grouping is a vector |
| V2-3 | MINOR | Fixed: the essential field is asserted dropped, not only the outcome |
| V2-4 | MINOR | Fixed: characters `String.prototype.trim` removes are tested as values, not blanks |
| V2-5 | MINOR | Fixed: FR-247 measures CPU time (500 ms bound; the unbounded path costs about 1.8 s) |
| V2-7 | NOTE | Fixed: the evaluator refuses `||` and `::text` over non-scalars and a non-text jsonb key |
| V3-1, V3-2, V3-3 | MINOR, NOTE, NOTE | Fixed: `CONTRACT.md` states the exact precedence and the release stamp rules; the poll-span pin reads the deadline |

**Final verification of `aeec2897`** (two refute-first verifiers: the lookup precedence, and the tests and documents
of the batch): no behaviour defect. The lookup classifier equals a contract-derived oracle on 1 382 400 replies (status,
return code, approval type, amount, flags, tip, currency), also through a port of the 001D M2 lookup branch; a separate
sweep of 933 120 classifications finds no outcome that differs between LIVE and TEST or depends on the reference; 34 560
status requests through the handler with a fake RPC, in LIVE and TEST, match; no reply concludes approved or declined,
or clears `charge_may_exist`, where the contract requires an anomaly or no conclusion; four profile variants give
no mismatch. The remaining findings were test pins and wording, closed in `6aa59415`:

| ID | Severity | Disposition |
|---|---|---|
| F1-1, F2-2 | MINOR | Pinned and documented: an unreadable status is the anomaly first, also beside a listed not-found / pending return code (§4.55.4) |
| F1-2, F2-1 | MINOR | Pinned: an unreadable amount alone reports a transaction on a status-less reply |
| F1-3 | NOTE | Pinned: partial-refund and pre-authorization statuses decide over those return codes |
| F2-3 | MINOR | Pinned: the SQL evaluator's refusals and the helpers' argument checks are tested |
| F2-4 | NOTE | Fixed: the FR-247 comments name the 500 ms CPU bound; the absence vectors are described as non-Space_Separators |

### 14.4 Fact-check of this packet

After `206a63db`, three fresh-context, read-only fact-checkers (sections 1-4, 5-8 and 9-14) checked 610 claims of this
packet against the committed source, tests, contract and evidence, and one refute-first verifier per checker re-checked
every finding: 22 findings (2 MAJOR, 6 MINOR, 14 NOTE), 20 confirmed, 1 partial, 1 refuted. A1 was a documentation
error; B1 was a schema gap against the engine's own comment, fixed in the source. Every other confirmed finding is
corrected in the text above (evidence `review/6_packet_factcheck_206a63db.json`).

| ID | Verified | Disposition |
|---|---|---|
| A1 | CONFIRMED, MAJOR | Corrected (§4.2): outside the proof's scope or device, `start` answers the claim's own envelope; only `status` / `release` answer `unavailable` |
| A2 | CONFIRMED, MINOR | Corrected (§2): all five stale local branches that change `config.toml` or `ci.yml` |
| A3 | REFUTED, NOTE | No change: the sentence describes the default-OFF state; the flag gates `start` only (§4.2) |
| A4 | CONFIRMED, NOTE | Corrected (§4.2 and `CONTRACT.md`): a set resolution answers the envelope before the approved branch |
| A5 | CONFIRMED, NOTE | Corrected (§4.1): the token bound in UTF-16 code units; C0 controls and DEL refused |
| B1 | CONFIRMED, MAJOR | Fixed in `f487ef5f`: the schema refuses a success code that is also a not-found or pending lookup code (fail closed); `provider.test.mjs` pins it, mutations M74 / M75 |
| B2 | CONFIRMED, MINOR | Corrected (§8): the float guard does not scan `lib/time.mjs` or `index.ts`; the repository check scans Dart only |
| B3 | CONFIRMED, NOTE | Corrected (§5, and the §14.1 D5 row after R2): 89 intervals, about 267 s |
| B4 | CONFIRMED, NOTE | Corrected (§5): a stored `release_failed` is that of an earlier failed release |
| B5 | CONFIRMED, NOTE | Corrected (§6, W1 item 2): the list must contain `"0"` |
| B6 | CONFIRMED, NOTE | Corrected (§6): SQL also receives the `environment` and `key_format` tokens |
| B7 | CONFIRMED, NOTE | Corrected (§7, step 7): a failed lookup is stamped, counted when automatic, and subject to the deadline rule |
| B8 | PARTIAL, NOTE | Corrected (§5): what a lookup returns for a never-sent request is Q-048 |
| C1 | CONFIRMED, MINOR | Corrected (§14.3): LC-05 was beyond the lens cap |
| C2 | CONFIRMED, MINOR | Corrected (§14.3): four dispositions were completed in `aeec2897` |
| C3 | CONFIRMED, MINOR | Corrected (§14.3): only V1-1 and V1-2 were latent behind W1 |
| C4 | CONFIRMED, MINOR | Fixed: mutation M73 for A6's offset bound; `network_guard.test.mjs` (`7264f501`) and mutations M76..M79 for the guard |
| C5 | CONFIRMED, NOTE | Corrected (§14.1, C-6) |
| C6 | CONFIRMED, NOTE | Corrected (§14.3): the reference and the LIVE / TEST split were varied in a separate sweep |
| C7 | CONFIRMED, NOTE | Corrected (§10, `boundary.test.mjs`) |
| C8 | CONFIRMED, NOTE | Corrected (§10, `start.test.mjs`): the order inside step (1) is not pinned |
| C9 | CONFIRMED, NOTE | Corrected (§9): `pgClassToJs` converts the classes |

**Delta verification of `206a63db..002cf905`** (two fresh-context, read-only reviewers, one for the code delta and one
for the packet corrections, and a refute-first verifier for the reviewer with findings; evidence
`review/7_delta_verification_002cf905.json`). The code reviewer passed 14 checks with no finding: all six return-code
pairs are refused, an overlapping profile answers `provider_unavailable` through the handler, every probe is refused
before any I/O on Node 22.14 and 24.19, and M73..M79 exercise the changes. The packet reviewer passed 22 checks and
found 3, corrected in the commit that records this paragraph:

| ID | Verified | Disposition |
|---|---|---|
| R1 | CONFIRMED, MINOR | Corrected (§2 and `preflight/POSTFLIGHT.txt`): `perf/canvaskit-versioned-shared-assets` was pushed as PR #283, closed unmerged, its remote branch since deleted |
| R2 | CONFIRMED, NOTE | Corrected (§14.1 D5 row): 89 intervals, about 267 s |
| R3 | CONFIRMED, NOTE | Corrected (§6, W1 item 2): without `"0"` a commit approval finishes `unknown` and only a later status lookup concludes it |
